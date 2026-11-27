/* ============================================================
   脚本：window_query.sql
   用途：第 12 周 —— 三类窗口函数查询（排名 / 累计与环比 / 移动平均）
   依赖：需先跑过 99-rebuild.sql（表与种子数据就绪）
   阶段：第 12 周（递归查询与业务事务 → 高级查询部分）
   作者：DiSod
   日期：2026-11-25
   幂等：是（纯查询，不写任何表）
   ============================================================ */

USE milktea_shop;
GO

SET NOCOUNT ON;   -- 只影响消息行（"N 行受影响"），不影响结果集
GO

/* ------------------------------------------------------------
   查询 1｜每日销售额：累计 + 环比
   ------------------------------------------------------------
   业务问题：老板看日报时真正关心的不是"今天卖了多少"，而是
             "到今天为止这个月累计多少""比昨天好还是差"。
   口径：D 口径 —— pay_status='SUCCESS' 且 order_status<>'CANCELLED'
         （取消单是已退款单，不能算营业额，见 business-rules A10）
   为什么先 GROUP BY 再开窗：窗口函数在 SELECT 之后计算，
         不能直接对明细行求和同时又按天分组，所以先用 CTE 把天聚出来，
         再在"每天一行"的结果上开窗。
   为什么写 ROWS 而不是省略：省略时默认帧是
         RANGE UNBOUNDED PRECEDING AND CURRENT ROW —— 同一天若有多行会被
         一起算进当前行。这里一天一行两种写法等价，但显式写 ROWS 能让
         以后改成按小时分组时语义不变。
   ------------------------------------------------------------ */
;WITH daily AS (
    SELECT  h.business_date                AS d,
            COUNT(DISTINCT h.order_id)      AS orders,
            SUM(h.amount_paid)              AS amt
    FROM    tbl_order_header h
    WHERE   h.pay_status = 'SUCCESS'
      AND   h.order_status <> 'CANCELLED'
    GROUP BY h.business_date
)
SELECT  d                                                        AS 营业日,
        orders                                                   AS 订单数,
        amt                                                      AS 销售额,
        SUM(amt) OVER (ORDER BY d ROWS UNBOUNDED PRECEDING)      AS 累计销售额,
        LAG(amt) OVER (ORDER BY d)                               AS 前一日销售额,
        amt - LAG(amt) OVER (ORDER BY d)                         AS 环比差额
FROM    daily
ORDER BY d;
GO

/* ------------------------------------------------------------
   查询 2｜商品在"自己分类内"排第几 + 占分类 / 占全店多少
   ------------------------------------------------------------
   业务问题：全店 Top10 里一个小分类可能永远进不去，店长想知道
             "这款在我这一类里是不是卖得最好的"，以及"这一类占了全店多少"。
   三个窗口：RN = 分类内排名（并列跳号）
             PCT_CAT = 本商品金额 / 本分类金额合计
             PCT_ALL = 本商品金额 / 全店金额合计
   注意 PARTITION BY 里放的是"分类"，不是商品 —— 这是分类内排名的关键。
   ------------------------------------------------------------ */
;WITH s AS (
    SELECT  p.product_id,
            p.product_name,
            c.category_name,
            SUM(d.qty)      AS cups,
            SUM(d.subtotal) AS amt
    FROM    tbl_order_detail d
    JOIN    tbl_order_header   h ON h.order_id    = d.order_id
    JOIN    tbl_product        p ON p.product_id  = d.product_id
    JOIN    tbl_product_category c ON c.category_id = p.category_id
    WHERE   h.pay_status = 'SUCCESS'
      AND   h.order_status <> 'CANCELLED'
    GROUP BY p.product_id, p.product_name, c.category_name
)
SELECT  category_name                                                      AS 分类,
        product_name                                                       AS 商品,
        cups                                                               AS 杯数,
        amt                                                                AS 销售额,
        RANK()       OVER (PARTITION BY category_name ORDER BY cups DESC)  AS 分类内排名,
        ROUND(100.0 * amt / SUM(amt) OVER (PARTITION BY category_name), 2) AS 占本分类百分比,
        ROUND(100.0 * amt / SUM(amt) OVER (), 2)                           AS 占全店百分比
FROM    s
ORDER BY category_name, 分类内排名, product_id;
GO

/* ------------------------------------------------------------
   查询 3｜移动平均：近 3 天平均日销（平滑掉单日波动）
   ------------------------------------------------------------
   业务问题：单日销售额受天气、周末影响剧烈，看"近 3 天平均"才看得出趋势。
   窗口帧：ROWS BETWEEN 2 PRECEDING AND CURRENT ROW = 当前行 + 前两行 = 3 天。
   N_IN_WINDOW：窗口里实际有几行。序列开头没有"前两行"，
                所以第 1 天是 1、第 2 天是 2，之后稳定为 3；
                这个列保证"平均值的分母"是透明的，不会被误读成 3 天平均。
   ------------------------------------------------------------ */
;WITH daily AS (
    SELECT  h.business_date                AS d,
            SUM(h.amount_paid)              AS amt
    FROM    tbl_order_header h
    WHERE   h.pay_status = 'SUCCESS'
      AND   h.order_status <> 'CANCELLED'
    GROUP BY h.business_date
)
SELECT  d                                                                     AS 营业日,
        amt                                                                   AS 当日销售额,
        SUM(amt)   OVER (ORDER BY d ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS 近3日合计,
        CAST(AVG(amt) OVER (ORDER BY d ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(12,2))
                                                                              AS 近3日均值,
        COUNT(*)   OVER (ORDER BY d ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS 窗口内天数
FROM    daily
ORDER BY d;
GO

/* ------------------------------------------------------------
   查询 4｜三个排名函数的口径对照（这不是业务查询，是给答辩用的对照）
   ------------------------------------------------------------
   同一份 4 行数据里「乙」「丙」并列 90 分：
       ROW_NUMBER → 1 2 3 4（强行给出不同名次，谁在前看排序列）
       RANK       → 1 2 2 4（并列跳号：两个第 2 名之后直接第 4）
       DENSE_RANK → 1 2 2 3（并列不跳号）
   选哪个取决于业务："前 3 名"用 RANK 会把并列的一起算进或一起排除，
   用 DENSE_RANK 则保证"3 个不同名次"，用 ROW_NUMBER 保证"恰好 3 行"。
   ------------------------------------------------------------ */
WITH t AS (
    SELECT * FROM (VALUES
        (N'甲', 100),
        (N'乙',  90),
        (N'丙',  90),
        (N'丁',  80)
    ) v(name, score)
)
SELECT  name                AS 名称,
        score               AS 分数,
        ROW_NUMBER() OVER (ORDER BY score DESC) AS ROW_NUMBER口径,
        RANK()       OVER (ORDER BY score DESC) AS RANK口径,
        DENSE_RANK() OVER (ORDER BY score DESC) AS DENSE_RANK口径
FROM    t
ORDER BY score DESC, name;
GO

/* ------------------------------------------------------------
   查询 5｜会员价值分层 + 平均复购间隔
   ------------------------------------------------------------
   业务问题：会员运营要知道"哪 25% 的人贡献了大头"，以及
             "老客多久回来一次"——后者是判断促活活动频率的依据。
   两个窗口：
     · LAG(order_time) OVER (PARTITION BY member_id ORDER BY order_time)
       拿到同一会员的上一单时间，相减即复购间隔（小时）
     · NTILE(4) OVER (ORDER BY 累计实付 DESC) 把会员切成四等份，
       DENSE_RANK 只用来标排名（并列不跳号）
   为什么间隔用 DATEDIFF(MINUTE)/60.0 而不是 DATEDIFF(HOUR)：
       DATEDIFF(HOUR) 会截断，60 分钟差会被算成 1 小时、59 分钟算成 0；
       先用分钟取差再除 60，得到的是真实小时数（精确到分钟）。
   为什么只算有效单：口径与 TC-10 一致（SUCCESS 且非 CANCELLED），
       否则已取消的单会把复购间隔算短。
   ------------------------------------------------------------ */
;WITH member_gaps AS (
    SELECT  h.member_id,
            h.order_id,
            h.amount_paid,
            h.order_time,
            LAG(h.order_time) OVER (
                PARTITION BY h.member_id
                ORDER BY h.order_time, h.order_id
            ) AS prev_order_time
    FROM    tbl_order_header h
    WHERE   h.member_id IS NOT NULL
      AND   h.pay_status = 'SUCCESS'
      AND   h.order_status <> 'CANCELLED'
),
member_agg AS (
    SELECT  m.member_code,
            m.member_name,
            COUNT(g.order_id)                                          AS 有效订单数,
            CAST(SUM(g.amount_paid) AS DECIMAL(10,2))                  AS 累计实付,
            CAST(AVG(DATEDIFF(MINUTE, g.prev_order_time, g.order_time) / 60.0) AS DECIMAL(6,2))
                                                                       AS 平均复购间隔_小时
    FROM    member_gaps g
    JOIN    tbl_member m ON m.member_id = g.member_id
    GROUP BY m.member_code, m.member_name
)
SELECT  DENSE_RANK() OVER (ORDER BY 累计实付 DESC)                      AS 消费排名,
        NTILE(4)     OVER (ORDER BY 累计实付 DESC)                      AS 价值四分位,
        member_code                                                    AS 会员码,
        member_name                                                    AS 会员姓名,
        有效订单数,
        累计实付,
        平均复购间隔_小时
FROM    member_agg
ORDER BY 消费排名 ASC, 会员码 ASC;
GO

/* ------------------------------------------------------------
   查询 6｜原料消耗成本的 ABC 帕累托
   ------------------------------------------------------------
   业务问题：采购预算有限时，先盯住"花掉 80% 钱的那批原料"。
   两个窗口：
     · SUM(成本) OVER (ORDER BY 成本 DESC ROWS UNBOUNDED PRECEDING)
       —— 降序累计，得到"到这一行为止花掉多少"
     · SUM(成本) OVER () —— 不带 ORDER BY 时整表就是一个窗口，
       得到分母（全店消耗总成本）
   累计占比 ≤80% 记 A 类、≤95% 记 B 类、其余 C 类。
   为什么排序键要带 ingredient_code：成本并列时若只按成本排，
       两次执行的行序可能不同，累计占比会抖动；加编码做第二键保证可复现。
   ------------------------------------------------------------ */
;WITH ing_cost AS (
    SELECT  i.ingredient_code,
            i.ingredient_name,
            i.unit,
            CAST(SUM(-sl.qty)                     AS DECIMAL(12,3)) AS 累计耗用量,
            CAST(SUM(-sl.qty * i.moving_avg_cost) AS DECIMAL(12,2)) AS 累计消耗成本
    FROM    tbl_stock_ledger sl
    JOIN    tbl_ingredient   i ON i.ingredient_id = sl.ingredient_id
    WHERE   sl.ledger_type = 'SALES_USE'
    GROUP BY i.ingredient_code, i.ingredient_name, i.unit
),
pareto AS (
    SELECT  ingredient_code,
            ingredient_name,
            unit,
            累计耗用量,
            累计消耗成本,
            SUM(累计消耗成本) OVER (
                ORDER BY 累计消耗成本 DESC, ingredient_code ASC
                ROWS UNBOUNDED PRECEDING
            )                                                                 AS 累计成本和,
            SUM(累计消耗成本) OVER ()                                         AS 全店消耗总成本,
            CAST(SUM(累计消耗成本) OVER (
                ORDER BY 累计消耗成本 DESC, ingredient_code ASC
                ROWS UNBOUNDED PRECEDING
            ) * 100.0 / NULLIF(SUM(累计消耗成本) OVER (), 0) AS DECIMAL(5,2)) AS 累计成本占比
    FROM    ing_cost
)
SELECT  ingredient_code                                    AS 原料编码,
        ingredient_name                                    AS 原料名称,
        unit                                               AS 单位,
        累计耗用量,
        累计消耗成本,
        累计成本占比,
        CASE WHEN 累计成本占比 <= 80.0 THEN N'A 类（核心 0-80%）'
             WHEN 累计成本占比 <= 95.0 THEN N'B 类（重要 80-95%）'
             ELSE N'C 类（常规 95-100%）' END              AS ABC分类
FROM    pareto
ORDER BY 累计消耗成本 DESC, 原料编码 ASC;
GO

PRINT N'【窗口函数】六个查询执行完毕：累计与环比 / 分类内排名与占比 / 近 3 日移动平均 / 排名口径对照 / 会员分层与复购 / 原料成本 ABC。';
GO
