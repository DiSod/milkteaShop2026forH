/* ============================================================
 * 脚本：advanced-query.sql
 * 用途：第 12 周高级查询实战 —— 窗口函数（3 组）与递归 CTE（2 组）
 * 依赖：00-bootstrap ~ 11-migration（全库数据与 D 口径视图就绪）
 * 阶段：第 12—13 周（高级查询与事务）
 * 作者：何争霖 (hezhlin5)
 * 日期：2026-11-25
 * 幂等：是（全只读查询；AQ5 层级演练在事务内 ROLLBACK，零脏数据）
 * ============================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

USE milktea_shop;
GO

/* ============================================================
 * AQ1（窗口函数）：营业日 3 日滑动均值、累计营收与环比涨跌幅
 * ------------------------------------------------------------
 * 窗口要点：
 *   - ROWS BETWEEN 2 PRECEDING AND CURRENT ROW（3 日滑动窗口）
 *   - ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW（累计营收）
 *   - LAG(..., 1) OVER (ORDER BY business_date)（前日对比与环比）
 * 口径：vw_daily_business_summary（已按 D 口径过滤，限定种子营业日）
 * ============================================================ */
PRINT N'【高级查询】=== AQ1：营业日 3 日滑动均值、累计营收与环比涨跌幅 ===';
WITH daily_d AS (
    SELECT
        business_date,
        completed_orders + cancelled_orders AS status_sampled,
        total_cups,
        net_revenue
    FROM dbo.vw_daily_business_summary
    WHERE business_date < '2026-10-01'
)
SELECT
    business_date                                                       AS 营业日,
    total_cups                                                          AS 出杯数,
    net_revenue                                                         AS 当日净实收,
    CAST(
        AVG(net_revenue) OVER (
            ORDER BY business_date
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS DECIMAL(10, 2)
    )                                                                   AS 近3日滑动均收,
    SUM(net_revenue) OVER (
        ORDER BY business_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                                   AS 累计净实收,
    LAG(net_revenue, 1) OVER (ORDER BY business_date)                   AS 前一日实收,
    CAST(
        (net_revenue - LAG(net_revenue, 1) OVER (ORDER BY business_date))
        * 100.0
        / NULLIF(LAG(net_revenue, 1) OVER (ORDER BY business_date), 0)
        AS DECIMAL(6, 2)
    )                                                                   AS 环比涨跌幅_百分比
FROM daily_d
ORDER BY business_date ASC;
GO

/* ============================================================
 * AQ2（窗口函数）：会员消费四分位分层与平均复购间隔（小时）
 * ------------------------------------------------------------
 * 窗口要点：
 *   - LAG(order_time) OVER (PARTITION BY member_id ORDER BY order_time)
 *     计算同一会员相邻两笔有效单的时间间隔（小时）
 *   - DENSE_RANK() OVER (ORDER BY total_spent DESC) 消费排名
 *   - NTILE(4) OVER (ORDER BY total_spent DESC) 价值四分位分层
 * ============================================================ */
PRINT N'【高级查询】=== AQ2：会员消费分层（NTILE/DENSE_RANK）与平均复购间隔 TOP 15 ===';
WITH member_gaps AS (
    SELECT
        h.member_id,
        h.order_id,
        h.amount_paid,
        h.order_time,
        LAG(h.order_time) OVER (
            PARTITION BY h.member_id
            ORDER BY h.order_time, h.order_id
        ) AS prev_order_time
    FROM dbo.tbl_order_header AS h
    WHERE h.member_id IS NOT NULL
      AND h.pay_status = 'SUCCESS'
      AND h.order_status <> 'CANCELLED'
),
member_agg AS (
    SELECT
        m.member_code,
        m.member_name,
        COUNT(g.order_id)                                               AS 有效订单数,
        CAST(SUM(g.amount_paid) AS DECIMAL(10, 2))                      AS 累计实付,
        CAST(AVG(DATEDIFF(MINUTE, g.prev_order_time, g.order_time) / 60.0)
             AS DECIMAL(6, 2))                                          AS 平均复购间隔_小时
    FROM member_gaps AS g
    JOIN dbo.tbl_member AS m
        ON m.member_id = g.member_id
    GROUP BY m.member_code, m.member_name
)
SELECT TOP 15
    DENSE_RANK() OVER (ORDER BY 累计实付 DESC)                           AS 消费排名,
    NTILE(4) OVER (ORDER BY 累计实付 DESC)                               AS 价值四分位,
    member_code                                                         AS 会员码,
    member_name                                                         AS 会员姓名,
    有效订单数,
    累计实付,
    平均复购间隔_小时
FROM member_agg
ORDER BY 消费排名 ASC, 会员码 ASC;
GO

/* ============================================================
 * AQ3（窗口函数）：原料销售消耗成本 ABC 帕累托分类
 * ------------------------------------------------------------
 * 窗口要点：
 *   - SUM(sales_cost) OVER (ORDER BY sales_cost DESC ROWS UNBOUNDED PRECEDING)
 *     计算成本降序累计和
 *   - SUM(sales_cost) OVER () 计算全店销售消耗总成本分母
 * ============================================================ */
PRINT N'【高级查询】=== AQ3：原料消耗成本 ABC 帕累托分析（TOP 15 + 分类汇总） ===';
WITH ing_cost AS (
    SELECT
        i.ingredient_code,
        i.ingredient_name,
        i.unit,
        CAST(SUM(-sl.qty) AS DECIMAL(12, 3))                            AS 累计耗用量,
        CAST(SUM(-sl.qty * i.moving_avg_cost) AS DECIMAL(12, 2))        AS 累计消耗成本
    FROM dbo.tbl_stock_ledger AS sl
    JOIN dbo.tbl_ingredient AS i
        ON i.ingredient_id = sl.ingredient_id
    WHERE sl.ledger_type = 'SALES_USE'
    GROUP BY i.ingredient_code, i.ingredient_name, i.unit
),
pareto AS (
    SELECT
        ingredient_code,
        ingredient_name,
        unit,
        累计耗用量,
        累计消耗成本,
        SUM(累计消耗成本) OVER (
            ORDER BY 累计消耗成本 DESC, ingredient_code ASC
            ROWS UNBOUNDED PRECEDING
        )                                                               AS 累计成本和,
        SUM(累计消耗成本) OVER ()                                       AS 全店消耗总成本
    FROM ing_cost
),
classified AS (
    SELECT
        ingredient_code,
        ingredient_name,
        unit,
        累计耗用量,
        累计消耗成本,
        CAST(累计成本和 * 100.0 / NULLIF(全店消耗总成本, 0) AS DECIMAL(5, 2)) AS 累计成本占比_百分比,
        CASE
            WHEN 累计成本和 * 100.0 / NULLIF(全店消耗总成本, 0) <= 80.0 THEN N'A 类（核心 0-80%）'
            WHEN 累计成本和 * 100.0 / NULLIF(全店消耗总成本, 0) <= 95.0 THEN N'B 类（重要 80-95%）'
            ELSE N'C 类（常规 95-100%）'
        END                                                             AS ABC分类
    FROM pareto
)
SELECT TOP 15
    ingredient_code                                                     AS 原料编码,
    ingredient_name                                                     AS 原料名称,
    unit                                                                AS 单位,
    累计耗用量,
    累计消耗成本,
    累计成本占比_百分比,
    ABC分类
FROM classified
ORDER BY 累计消耗成本 DESC, 原料编码 ASC;

WITH ing_cost AS (
    SELECT
        i.ingredient_code,
        CAST(SUM(-sl.qty * i.moving_avg_cost) AS DECIMAL(12, 2)) AS 累计消耗成本
    FROM dbo.tbl_stock_ledger AS sl
    JOIN dbo.tbl_ingredient AS i
        ON i.ingredient_id = sl.ingredient_id
    WHERE sl.ledger_type = 'SALES_USE'
    GROUP BY i.ingredient_code
),
pareto AS (
    SELECT
        累计消耗成本,
        SUM(累计消耗成本) OVER (
            ORDER BY 累计消耗成本 DESC, ingredient_code ASC
            ROWS UNBOUNDED PRECEDING
        ) * 100.0 / NULLIF(SUM(累计消耗成本) OVER (), 0) AS cum_pct
    FROM ing_cost
),
abc AS (
    SELECT
        累计消耗成本,
        CASE
            WHEN cum_pct <= 80.0 THEN N'A 类（核心 0-80%）'
            WHEN cum_pct <= 95.0 THEN N'B 类（重要 80-95%）'
            ELSE N'C 类（常规 95-100%）'
        END AS ABC分类
    FROM pareto
)
SELECT
    ABC分类,
    COUNT(*)                                                            AS 原料种数,
    CAST(SUM(累计消耗成本) AS DECIMAL(12, 2))                           AS 分类成本合计
FROM abc
GROUP BY ABC分类
ORDER BY ABC分类 ASC;
GO

/* ============================================================
 * AQ4（递归 CTE · R1）：生成连续营业日历并补齐无订单断档日
 * ------------------------------------------------------------
 * 业务背景：门店数据覆盖 2026-09-17 ~ 2026-09-23，前后存在休业/断档日；
 * 递归 CTE 自动生成连续日期序列左连接日报视图，确保趋势图/报表不断天。
 * ============================================================ */
PRINT N'【高级查询】=== AQ4（递归 CTE）：连续营业日历补齐断档（2026-09-16 ~ 2026-09-25） ===';
WITH date_calendar AS (
    SELECT CAST('2026-09-16' AS DATE) AS cal_date
    UNION ALL
    SELECT DATEADD(DAY, 1, cal_date)
    FROM date_calendar
    WHERE cal_date < '2026-09-25'
)
SELECT
    c.cal_date                                                          AS 日期,
    ISNULL(v.total_orders, 0)                                           AS 接单量,
    ISNULL(v.total_cups, 0)                                             AS 出杯数,
    ISNULL(v.net_revenue, 0.00)                                         AS 净实收,
    CASE WHEN v.business_date IS NULL THEN N'无营业记录（补零）' ELSE N'正常营业' END AS 状态
FROM date_calendar AS c
LEFT JOIN dbo.vw_daily_business_summary AS v
    ON v.business_date = c.cal_date
ORDER BY c.cal_date ASC
OPTION (MAXRECURSION 100);
GO

/* ============================================================
 * AQ5（递归 CTE · R2）：品类树层级穿透与销售额自底向上汇总
 * ------------------------------------------------------------
 * 事实说明：种子数据中 5 个品类（C01~C05）parent_category_id 均为 NULL（单层平铺）。
 * 为真实验证多级品类树递归穿透与父节点向上汇总能力，本段在显式事务内临时构建
 * 三级品类树（根大类 R01/R02 -> 现有中类 C01~C05 -> 叶子子类 S01），执行递归汇总后
 * 立即 ROLLBACK，确保种子数据零污染。
 * ============================================================ */
PRINT N'【高级查询】=== AQ5（递归 CTE）：三级品类树层级展开与销售额自底向上汇总（事务回滚零污染） ===';
BEGIN TRANSACTION;

    INSERT INTO dbo.tbl_product_category (parent_category_id, category_code, category_name, sort_no, is_active)
    VALUES
        (NULL, 'R01', N'现制茶饮总类', 0, 1),
        (NULL, 'R02', N'甜品与限定总类', 0, 1);

    DECLARE @r01_id INT = (SELECT category_id FROM dbo.tbl_product_category WHERE category_code = 'R01');
    DECLARE @r02_id INT = (SELECT category_id FROM dbo.tbl_product_category WHERE category_code = 'R02');

    UPDATE dbo.tbl_product_category SET parent_category_id = @r01_id WHERE category_code IN ('C01', 'C02', 'C03');
    UPDATE dbo.tbl_product_category SET parent_category_id = @r02_id WHERE category_code IN ('C04', 'C05');

    DECLARE @c02_id INT = (SELECT category_id FROM dbo.tbl_product_category WHERE category_code = 'C02');
    INSERT INTO dbo.tbl_product_category (parent_category_id, category_code, category_name, sort_no, is_active)
    VALUES (@c02_id, 'S01', N'鲜果茶子类（示例）', 1, 1);

    ;WITH category_tree AS (
        SELECT
            c.category_id,
            c.parent_category_id,
            c.category_code,
            c.category_name,
            1                                                           AS tree_level,
            CAST(c.category_name AS NVARCHAR(400))                      AS category_path
        FROM dbo.tbl_product_category AS c
        WHERE c.parent_category_id IS NULL

        UNION ALL

        SELECT
            ch.category_id,
            ch.parent_category_id,
            ch.category_code,
            ch.category_name,
            ct.tree_level + 1,
            CAST(ct.category_path + N' / ' + ch.category_name AS NVARCHAR(400))
        FROM dbo.tbl_product_category AS ch
        JOIN category_tree AS ct
            ON ch.parent_category_id = ct.category_id
    ),
    /* 每个节点对应的全部后代节点（含自身），用于自底向上销售额汇总 */
    descendant_map AS (
        SELECT
            category_id AS ancestor_id,
            category_id AS descendant_id
        FROM dbo.tbl_product_category

        UNION ALL

        SELECT
            dm.ancestor_id,
            ch.category_id
        FROM descendant_map AS dm
        JOIN dbo.tbl_product_category AS ch
            ON ch.parent_category_id = dm.descendant_id
    ),
    direct_sales AS (
        SELECT
            p.category_id,
            SUM(d.qty)                                                  AS cups,
            CAST(SUM(d.subtotal) AS DECIMAL(12, 2))                     AS amount
        FROM dbo.tbl_order_detail AS d
        JOIN dbo.tbl_order_header AS h
            ON h.order_id = d.order_id
        JOIN dbo.tbl_product AS p
            ON p.product_id = d.product_id
        WHERE h.pay_status = 'SUCCESS'
          AND h.order_status <> 'CANCELLED'
        GROUP BY p.category_id
    )
    SELECT
        ct.tree_level                                                   AS 层级,
        ct.category_code                                                AS 品类编码,
        ct.category_path                                                AS 层级路径,
        ISNULL(SUM(ds.cups), 0)                                         AS 含子级总杯数,
        ISNULL(SUM(ds.amount), 0.00)                                    AS 含子级总销售额
    FROM category_tree AS ct
    JOIN descendant_map AS dm
        ON dm.ancestor_id = ct.category_id
    LEFT JOIN direct_sales AS ds
        ON ds.category_id = dm.descendant_id
    GROUP BY ct.tree_level, ct.category_code, ct.category_path
    ORDER BY ct.category_path ASC
    OPTION (MAXRECURSION 50);

ROLLBACK TRANSACTION;
GO

PRINT N'【高级查询】第 12 周高级查询脚本（窗口函数 + 递归 CTE）执行完毕（零数据改动）。';
GO
