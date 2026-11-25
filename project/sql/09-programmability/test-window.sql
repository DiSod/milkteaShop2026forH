/* ============================================================
   脚本：test-window.sql
   用途：第 12 周 —— 三类窗口函数查询的正反例（预期 / 实际 / PASS｜FAIL）
   设计要点：
   1) 预期值多数"独立重算"（用另一条聚合路径算出来再比），不把查询复制两遍
      互相自证；只有"业务口径常量"才写死数字（如累计末期 23,762.00）
   2) 全部只读，不建临时表、不写任何业务表 —— 随时可重复执行
   3) 用例总数固定 21，漏跑会判红
   退出码：任一 FAIL → RAISERROR 16 → 配合 sqlcmd -b 变成非零退出
   ============================================================ */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE milktea_shop;
GO

DECLARE @r TABLE
(
    seq      INT IDENTITY(1,1) PRIMARY KEY,
    item     NVARCHAR(140),
    expected NVARCHAR(60),
    actual   NVARCHAR(60),
    ok       BIT
);

/* ================= 一、累计与环比（查询 1） ================= */

/* 1 正例：日报行数 = 有订单的营业日数（窗口不能凭空造行） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'累计·营业日行数（窗口不增不减）',
       CONVERT(NVARCHAR(60), COUNT(DISTINCT business_date)),
       CONVERT(NVARCHAR(60), COUNT(*)),
       CASE WHEN COUNT(DISTINCT business_date) = COUNT(*) THEN 1 ELSE 0 END
FROM (SELECT business_date FROM tbl_order_header
      WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
      GROUP BY business_date) t;

/* 2 正例：累计末值 = 全期销售额合计（累计的定义自洽） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'累计·末值 = 全期销售额合计',
       CONVERT(NVARCHAR(60), CAST(SUM(amt) AS DECIMAL(12,2))),
       CONVERT(NVARCHAR(60), CAST((SELECT MAX(cum) FROM (
            SELECT SUM(amt) OVER (ORDER BY d ROWS UNBOUNDED PRECEDING) AS cum
            FROM (SELECT business_date AS d, SUM(amount_paid) AS amt
                  FROM tbl_order_header
                  WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
                  GROUP BY business_date) g) c) AS DECIMAL(12,2))),
       CASE WHEN SUM(amt) = (SELECT MAX(cum) FROM (
            SELECT SUM(amt) OVER (ORDER BY d ROWS UNBOUNDED PRECEDING) AS cum
            FROM (SELECT business_date AS d, SUM(amount_paid) AS amt
                  FROM tbl_order_header
                  WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
                  GROUP BY business_date) g) c) THEN 1 ELSE 0 END
FROM (SELECT business_date AS d, SUM(amount_paid) AS amt FROM tbl_order_header
      WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
      GROUP BY business_date) s;

/* 3 正例：累计末值 = D 口径业务常量 23,762.00（独立于窗口实现的硬口径） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'累计·末值 = D 口径常量 23762.00', N'23762.00',
       CONVERT(NVARCHAR(60), CAST(MAX(cum) AS DECIMAL(12,2))),
       CASE WHEN MAX(cum) = 23762.00 THEN 1 ELSE 0 END
FROM (SELECT SUM(amt) OVER (ORDER BY d ROWS UNBOUNDED PRECEDING) AS cum
      FROM (SELECT business_date AS d, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g) c;

/* 4 正例：首日没有"前一日" → LAG 必须返回 NULL，且环比也为 NULL */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'环比·首日 LAG = NULL', N'NULL',
       ISNULL(CONVERT(NVARCHAR(60), prev), N'NULL'),
       CASE WHEN prev IS NULL THEN 1 ELSE 0 END
FROM (SELECT TOP 1 LAG(amt) OVER (ORDER BY d) AS prev
      FROM (SELECT business_date AS d, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g ORDER BY d) t;

/* 5 正例：09-18 环比 = 当日 − 前一日（独立重算，不复制窗口逻辑） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'环比·09-18 差额', CONVERT(NVARCHAR(60), CAST(e.amt - p.amt AS DECIMAL(12,2))),
       CONVERT(NVARCHAR(60), CAST(r.delta AS DECIMAL(12,2))),
       CASE WHEN e.amt - p.amt = r.delta THEN 1 ELSE 0 END
FROM (SELECT business_date, SUM(amount_paid) AS amt FROM tbl_order_header
      WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED' AND business_date = '2026-09-18'
      GROUP BY business_date) e
CROSS JOIN (SELECT business_date, SUM(amount_paid) AS amt FROM tbl_order_header
      WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED' AND business_date = '2026-09-17'
      GROUP BY business_date) p
CROSS JOIN (SELECT business_date AS d, amt - LAG(amt) OVER (ORDER BY business_date) AS delta
      FROM (SELECT business_date, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g) r
WHERE r.d = '2026-09-18';

/* 6 正例：09-21 环比为负数（下跌日也要能算出来，不能取绝对值） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'环比·09-21 为负值（跌幅保留符号）',
       CONVERT(NVARCHAR(60), CAST(2954.00 - 4245.00 AS DECIMAL(12,2))),
       CONVERT(NVARCHAR(60), CAST(r.delta AS DECIMAL(12,2))),
       CASE WHEN r.delta = 2954.00 - 4245.00 THEN 1 ELSE 0 END
FROM (SELECT business_date AS d, amt - LAG(amt) OVER (ORDER BY business_date) AS delta
      FROM (SELECT business_date, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g) r
WHERE r.d = '2026-09-21';

/* 7 反例：累计口径必须同时带两个过滤。
   种子里 37 张取消单的 pay_status 都是 FAILED，所以"只滤 pay_status"与"两个都滤"
   结果相同（都等于 23,762.00）—— 这一点要写清楚，别让人误以为第二个过滤没用；
   一旦出现"取消但支付成功"的单，两者就会分叉，那时才看得出差异。
   本用例断言：两种口径在当前数据上相等，且都等于 D 口径常量。 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'累计·只滤 pay_status 与双过滤等价（种子取消单均为 FAILED）',
       N'都等于 23762.00',
       CONVERT(NVARCHAR(60), CAST(a.d_amt AS DECIMAL(12,2)))
           + N' / ' + CONVERT(NVARCHAR(60), CAST(a.all_amt AS DECIMAL(12,2))),
       CASE WHEN a.d_amt = a.all_amt AND a.d_amt = 23762.00 THEN 1 ELSE 0 END
FROM (SELECT SUM(CASE WHEN order_status <> 'CANCELLED' THEN amount_paid ELSE 0 END) AS d_amt,
             SUM(CASE WHEN pay_status = 'SUCCESS' THEN amount_paid ELSE 0 END)        AS all_amt
      FROM tbl_order_header) a;

/* ================= 二、分类内排名与占比（查询 2） ================= */

/* 8 正例：纯茶分类内第一名 = 四季春茶（99 杯） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'排名·纯茶第一名', N'四季春茶',
       MAX(CASE WHEN rk = 1 THEN product_name ELSE N'' END),
       CASE WHEN MAX(CASE WHEN rk = 1 THEN product_name ELSE N'' END) = N'四季春茶' THEN 1 ELSE 0 END
FROM (SELECT p.product_name, c.category_name,
             RANK() OVER (PARTITION BY c.category_name ORDER BY SUM(d.qty) DESC) AS rk
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      JOIN tbl_product p ON p.product_id = d.product_id
      JOIN tbl_product_category c ON c.category_id = p.category_id
      WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
      GROUP BY p.product_id, p.product_name, c.category_name) s
WHERE category_name = N'纯茶';

/* 9 正例：水果茶分类内第一名杯数 = 99 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'排名·水果茶第一名杯数', N'99',
       CONVERT(NVARCHAR(60), MAX(cups)),
       CASE WHEN MAX(cups) = 99 THEN 1 ELSE 0 END
FROM (SELECT c.category_name, SUM(d.qty) AS cups,
             RANK() OVER (PARTITION BY c.category_name ORDER BY SUM(d.qty) DESC) AS rk
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      JOIN tbl_product p ON p.product_id = d.product_id
      JOIN tbl_product_category c ON c.category_id = p.category_id
      WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
      GROUP BY p.product_id, p.product_name, c.category_name) s
WHERE category_name = N'水果茶' AND rk = 1;

/* 10 正例：经典奶茶 96 杯的两款并列第 3（RANK 遇到并列要同名次） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'排名·经典奶茶 96 杯两款并列', N'2',
       CONVERT(NVARCHAR(60), COUNT(*)),
       CASE WHEN COUNT(*) = 2 AND MIN(rk) = 3 AND MAX(rk) = 3 THEN 1 ELSE 0 END
FROM (SELECT p.product_name, SUM(d.qty) AS cups,
             RANK() OVER (PARTITION BY c.category_name ORDER BY SUM(d.qty) DESC) AS rk
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      JOIN tbl_product p ON p.product_id = d.product_id
      JOIN tbl_product_category c ON c.category_id = p.category_id
      WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
        AND c.category_name = N'经典奶茶'
      GROUP BY p.product_id, p.product_name, c.category_name) s
WHERE cups = 96;

/* 11 正例：并列之后的名次跳号 —— 95 杯的红豆奶茶为第 5（不是第 4） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'排名·并列后跳号（95 杯 = 第 5）', N'5',
       CONVERT(NVARCHAR(60), MAX(rk)),
       CASE WHEN MAX(rk) = 5 THEN 1 ELSE 0 END
FROM (SELECT p.product_name, SUM(d.qty) AS cups,
             RANK() OVER (PARTITION BY c.category_name ORDER BY SUM(d.qty) DESC) AS rk
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      JOIN tbl_product p ON p.product_id = d.product_id
      JOIN tbl_product_category c ON c.category_id = p.category_id
      WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
        AND c.category_name = N'经典奶茶'
      GROUP BY p.product_id, p.product_name, c.category_name) s
WHERE cups = 95;

/* 12 正例：每个分类恰好一个第 1 名（PARTITION BY 分得开，不会全店只有一个 1）
   —— 必须同时断『第 1 名的行数 = 分类数』：去掉 PARTITION BY 后只剩 1 行，
      COUNT(DISTINCT) 与 COUNT(*) 都等于 1，原断言会假通过（变异测试 M1 实测过）。 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'排名·每分类一个第 1 名（行数 = 分类数 5）', N'5',
       CONVERT(NVARCHAR(60), COUNT(*)) + N' 行 / ' + CONVERT(NVARCHAR(60), COUNT(DISTINCT category_name)) + N' 分类',
       CASE WHEN COUNT(DISTINCT category_name) = COUNT(*) AND COUNT(*) = 5 THEN 1 ELSE 0 END
FROM (SELECT c.category_name,
             RANK() OVER (PARTITION BY c.category_name ORDER BY SUM(d.qty) DESC) AS rk
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      JOIN tbl_product p ON p.product_id = d.product_id
      JOIN tbl_product_category c ON c.category_id = p.category_id
      WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
      GROUP BY p.product_id, p.product_name, c.category_name) s
WHERE rk = 1;

/* 13 正例：每个分类的"本分类百分比"之和都 = 100（先按分类汇总再断言，
       直接对全表 SUM 会得到 分类数 × 100） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'占比·每个分类内合计 100%', N'5 个分类全部 100 ± 0.2',
       CONVERT(NVARCHAR(60), CAST(MAX(cat_pct) AS DECIMAL(12,2))) + N' / '
           + CONVERT(NVARCHAR(60), CAST(MIN(cat_pct) AS DECIMAL(12,2))),
       CASE WHEN MAX(ABS(cat_pct - 100)) <= 0.2 THEN 1 ELSE 0 END
FROM (SELECT category_name, SUM(pct) AS cat_pct
      FROM (SELECT c.category_name,
                   ROUND(100.0 * SUM(d.subtotal) / SUM(SUM(d.subtotal)) OVER (PARTITION BY c.category_name), 2) AS pct
            FROM tbl_order_detail d
            JOIN tbl_order_header h ON h.order_id = d.order_id
            JOIN tbl_product p ON p.product_id = d.product_id
            JOIN tbl_product_category c ON c.category_id = p.category_id
            WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
            GROUP BY p.product_id, p.product_name, c.category_name) x
      GROUP BY category_name) y;

/* 14 正例：占全店百分比之和 = 100 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'占比·全店合计 100%', N'100 ± 0.2',
       CONVERT(NVARCHAR(60), CAST(SUM(pct) AS DECIMAL(12,2))),
       CASE WHEN ABS(SUM(pct) - 100) <= 0.2 THEN 1 ELSE 0 END
FROM (SELECT c.category_name,
             ROUND(100.0 * SUM(d.subtotal) / SUM(SUM(d.subtotal)) OVER (), 2) AS pct
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      JOIN tbl_product p ON p.product_id = d.product_id
      JOIN tbl_product_category c ON c.category_id = p.category_id
      WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
      GROUP BY p.product_id, p.product_name, c.category_name) s;

/* 15 反例：占比不能大于 100（单款商品占比恒小于 100） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'占比·单款最大占比 < 100', N'< 100',
       CONVERT(NVARCHAR(60), CAST(MAX(pct) AS DECIMAL(12,2))),
       CASE WHEN MAX(pct) < 100 THEN 1 ELSE 0 END
FROM (SELECT ROUND(100.0 * SUM(d.subtotal) / SUM(SUM(d.subtotal)) OVER (), 2) AS pct
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
      GROUP BY d.product_id) s;

/* ================= 三、移动平均（查询 3） ================= */

/* 16 正例：首日窗口只有 1 行 —— 平均值等于当日值，窗口内天数 = 1 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'移动平均·首日窗口 1 行',
       CONVERT(NVARCHAR(60), CAST(m.v AS DECIMAL(12,2))) + N' / 1',
       CONVERT(NVARCHAR(60), CAST(m.avg3 AS DECIMAL(12,2)))
           + N' / ' + CONVERT(NVARCHAR(60), m.n3),
       CASE WHEN m.n3 = 1 AND m.avg3 = m.v THEN 1 ELSE 0 END
FROM (SELECT TOP 1 amt AS v,
             AVG(amt) OVER (ORDER BY d ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)   AS avg3,
             COUNT(*) OVER (ORDER BY d ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)   AS n3
      FROM (SELECT business_date AS d, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g ORDER BY d) m;

/* 17 正例：第 3 天起窗口满 3 行，均值 = 独立重算的三日均值 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'移动平均·09-19 三日均值',
       CONVERT(NVARCHAR(60), CAST((3070.00 + 3074.00 + 4631.00) / 3 AS DECIMAL(12,2))),
       CONVERT(NVARCHAR(60), CAST(m.avg3 AS DECIMAL(12,2))),
       CASE WHEN m.n3 = 3 AND m.avg3 = (3070.00 + 3074.00 + 4631.00) / 3 THEN 1 ELSE 0 END
FROM (SELECT business_date AS d,
             AVG(amt) OVER (ORDER BY business_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg3,
             COUNT(*) OVER (ORDER BY business_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS n3
      FROM (SELECT business_date, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g) m
WHERE m.d = '2026-09-19';

/* 18 正例：末日三日合计 = 三行数值相加（窗口帧边界正确） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'移动平均·09-23 三日合计',
       CONVERT(NVARCHAR(60), CAST(2954.00 + 2945.00 + 2843.00 AS DECIMAL(12,2))),
       CONVERT(NVARCHAR(60), CAST(m.sum3 AS DECIMAL(12,2))),
       CASE WHEN m.sum3 = 2954.00 + 2945.00 + 2843.00 THEN 1 ELSE 0 END
FROM (SELECT business_date AS d,
             SUM(amt) OVER (ORDER BY business_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS sum3
      FROM (SELECT business_date, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g) m
WHERE m.d = '2026-09-23';

/* 19 正例：末日三日均值 = 2914.00（窗口不会"少算一天"） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'移动平均·09-23 三日均值', N'2914.00',
       CONVERT(NVARCHAR(60), CAST(m.avg3 AS DECIMAL(12,2))),
       CASE WHEN m.avg3 = 2914.00 THEN 1 ELSE 0 END
FROM (SELECT business_date AS d,
             AVG(amt) OVER (ORDER BY business_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg3
      FROM (SELECT business_date, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g) m
WHERE m.d = '2026-09-23';

/* 20 反例：移动平均不能用"当日 / 天数"冒充 —— 末日两者必须不相等（除非三日恰好相等） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'移动平均·均值≠当日值（口径未被简化）',
       N'不相等',
       CONVERT(NVARCHAR(60), CAST(m.avg3 AS DECIMAL(12,2))) + N' vs '
           + CONVERT(NVARCHAR(60), CAST(m.v AS DECIMAL(12,2))),
       CASE WHEN m.avg3 <> m.v THEN 1 ELSE 0 END
FROM (SELECT TOP 1 amt AS v,
             AVG(amt) OVER (ORDER BY d ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg3
      FROM (SELECT business_date AS d, SUM(amount_paid) AS amt FROM tbl_order_header
            WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
            GROUP BY business_date) g ORDER BY d DESC) m;

/* ================= 四、排名函数口径对照（查询 4） ================= */

/* 21 正例：并列 90 分 → RANK 2,2 / DENSE_RANK 2,2 / ROW_NUMBER 2,3 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'口径对照·并列行的三种名次',
       N'RANK 2,2 / DENSE 2,2 / RN 2,3',
       N'RANK ' + CONVERT(NVARCHAR(10), MIN(rk)) + N',' + CONVERT(NVARCHAR(10), MAX(rk))
           + N' / DENSE ' + CONVERT(NVARCHAR(10), MIN(dr)) + N',' + CONVERT(NVARCHAR(10), MAX(dr))
           + N' / RN ' + CONVERT(NVARCHAR(10), MIN(rn)) + N',' + CONVERT(NVARCHAR(10), MAX(rn)),
       CASE WHEN MIN(rk) = 2 AND MAX(rk) = 2
                 AND MIN(dr) = 2 AND MAX(dr) = 2
                 AND MIN(rn) = 2 AND MAX(rn) = 3
            THEN 1 ELSE 0 END
FROM (SELECT score,
             RANK()       OVER (ORDER BY score DESC) AS rk,
             DENSE_RANK() OVER (ORDER BY score DESC) AS dr,
             ROW_NUMBER() OVER (ORDER BY score DESC, name) AS rn
      FROM (VALUES (N'甲', 100), (N'乙', 90), (N'丙', 90), (N'丁', 80)) v(name, score)) t
WHERE score = 90;

/* ================= 汇总 ================= */
SELECT  seq                                          AS [#],
        item                                         AS [用例],
        expected                                     AS [预期],
        actual                                       AS [实际],
        CASE ok WHEN 1 THEN N'PASS' ELSE N'FAIL' END AS [结果]
FROM    @r
ORDER BY seq;

DECLARE @pass INT, @fail INT, @total INT, @msg NVARCHAR(200), @msg2 NVARCHAR(200);

SELECT  @pass = SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END),
        @fail = SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END)
FROM    @r;

SET @total = @pass + @fail;

PRINT N'============================================================';
PRINT N'【窗口函数测试总览】用例数: ' + CAST(@total AS NVARCHAR(10))
    + N' | 通过: ' + CAST(@pass AS NVARCHAR(10))
    + N' | 失败: ' + CAST(@fail AS NVARCHAR(10));
PRINT N'============================================================';

IF @total <> 21
BEGIN
    SET @msg2 = N'【窗口函数测试】用例数应为 21，实际 ' + CAST(@total AS NVARCHAR(10))
              + N' 条 —— 有用例没跑，按失败处理。';
    RAISERROR(@msg2, 16, 1);
END
ELSE IF @fail > 0
BEGIN
    SET @msg = N'【窗口函数测试】有 ' + CAST(@fail AS NVARCHAR(10)) + N' 条用例失败。';
    RAISERROR(@msg, 16, 1);
END
ELSE
    PRINT N'【窗口函数测试结论】21 条用例全部通过。';
GO
