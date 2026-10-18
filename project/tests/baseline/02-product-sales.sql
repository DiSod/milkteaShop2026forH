/* ============================================================
 * 基线快照：02-product-sales.sql
 * 用途：第 6 周模式迁移的「商品销售」迁移前 / 后结果留档（课程任务 ①②）
 * 依赖：00-bootstrap ~ 08-security + 11-migration
 * 阶段：第 6 周
 *
 * ⭐ 销售额口径（第 6 周裁定，见 weeks/week06/README.md §六）：
 *   A 全量      —— 不分状态，1,963 单
 *   D 已收款    —— pay_status = 'SUCCESS'，**主口径**
 *   B 已完成    —— order_status = 'COMPLETED'
 *   三者是包含关系 A ⊃ D ⊃ B，数字互不相同，三个都要留档。
 *
 * 实测：D 口径 29 个商品行有销售（共 30 个商品）、2,579 杯、小计 23,882.00
 *       商品金额 22,389.00 + 加料费 1,493.00 = 23,882.00
 * 用法：
 *   sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -W -s"|" -w 8000 -i 02-product-sales.sql -o result\before-S02.txt
 * ============================================================ */

USE milktea_shop;
GO

SET NOCOUNT ON;
SET ANSI_WARNINGS OFF;
GO

PRINT N'=== S2 商品销售基线快照 ===';
GO

/* ---------- 2a：按商品 × 三口径 ---------- */
WITH tp AS (
    SELECT d.product_id,
           SUM(t.qty * t.unit_extra_price) AS topping_fee
    FROM tbl_order_detail_topping t
    JOIN tbl_order_detail d ON d.order_detail_id = t.order_detail_id
    JOIN tbl_order_header h ON h.order_id         = d.order_id
    WHERE h.pay_status = 'SUCCESS'
    GROUP BY d.product_id
)
SELECT p.product_code,
       p.product_name,
       pc.category_name,
       SUM(d.qty)                                                  AS A_杯数,
       SUM(CASE WHEN h.pay_status = 'SUCCESS'    THEN d.qty ELSE 0 END) AS D_杯数,
       SUM(CASE WHEN h.order_status = 'COMPLETED' THEN d.qty ELSE 0 END) AS B_杯数,
       CAST(SUM(CASE WHEN h.pay_status = 'SUCCESS' THEN d.qty * d.unit_price ELSE 0 END) AS DECIMAL(18,2)) AS D_商品金额,
       CAST(ISNULL(MAX(tp.topping_fee), 0) AS DECIMAL(18,2))       AS D_加料费,
       CAST(SUM(CASE WHEN h.pay_status = 'SUCCESS' THEN d.subtotal ELSE 0 END) AS DECIMAL(18,2)) AS D_小计合计,
       COUNT(DISTINCT CASE WHEN h.pay_status = 'SUCCESS'    THEN d.order_id END) AS D_订单数,
       COUNT(DISTINCT CASE WHEN h.order_status = 'COMPLETED' THEN d.order_id END) AS B_订单数
INTO #s2
FROM tbl_order_detail d
JOIN tbl_order_header     h  ON h.order_id    = d.order_id
JOIN tbl_product          p  ON p.product_id  = d.product_id
LEFT JOIN tbl_product_category pc ON pc.category_id = p.category_id
LEFT JOIN tp                   ON tp.product_id = d.product_id
GROUP BY p.product_code, p.product_name, pc.category_name;
GO

PRINT N'--- S2.1 按商品（D 杯数降序，稳定排序） ---';
GO
SELECT * FROM #s2 ORDER BY D_杯数 DESC, product_code;
GO

PRINT N'--- S2.2 合计与商品覆盖 ---';
GO
SELECT COUNT(*)                                        AS 商品行数,
       SUM(CASE WHEN D_杯数 > 0 THEN 1 ELSE 0 END)      AS D_有销售商品数,
       SUM(CASE WHEN B_杯数 > 0 THEN 1 ELSE 0 END)      AS B_有销售商品数,
       SUM(A_杯数) AS A_杯数合计,
       SUM(D_杯数) AS D_杯数合计,
       SUM(B_杯数) AS B_杯数合计,
       CAST(SUM(D_商品金额) AS DECIMAL(18,2)) AS D_商品金额合计,
       CAST(SUM(D_加料费)   AS DECIMAL(18,2)) AS D_加料费合计,
       CAST(SUM(D_小计合计) AS DECIMAL(18,2)) AS D_小计合计,
       SUM(D_订单数)  AS D_商品订单数之和_含重复,
       SUM(B_订单数)  AS B_商品订单数之和_含重复
FROM #s2;
GO

PRINT N'--- S2.3 不变量自检：商品金额 + 加料费 = 小计合计（偏差应恒为 0） ---';
GO
SELECT CAST(SUM(D_小计合计) - SUM(D_商品金额) - SUM(D_加料费) AS DECIMAL(18,2)) AS 偏差,
       CASE WHEN SUM(D_小计合计) = SUM(D_商品金额) + SUM(D_加料费)
            THEN N'✅ 成立' ELSE N'❌ 不成立' END AS 结论
FROM #s2;
GO

/* ---------- 2b：订单级三口径对照 ---------- */
PRINT N'--- S2.4 订单级三口径对照（金额单位：元） ---';
GO
SELECT N'A-全量（不分状态）' AS 口径, COUNT(*) AS 订单数,
       CAST(SUM(amount_due + discount_amount) AS DECIMAL(18,2)) AS 小计合计,
       CAST(SUM(discount_amount) AS DECIMAL(18,2))              AS 折扣合计,
       CAST(SUM(amount_paid) AS DECIMAL(18,2))                  AS 实付金额,
       N'due+discount 即明细小计合计' AS 说明
FROM tbl_order_header
UNION ALL
SELECT N'D-已收款（⭐ 主口径）', COUNT(*),
       CAST(SUM(amount_due + discount_amount) AS DECIMAL(18,2)),
       CAST(SUM(discount_amount) AS DECIMAL(18,2)),
       CAST(SUM(amount_paid) AS DECIMAL(18,2)),
       N'pay_status = SUCCESS；含 ABANDONED 32 单'
FROM tbl_order_header WHERE pay_status = 'SUCCESS'
UNION ALL
SELECT N'B-已完成', COUNT(*),
       CAST(SUM(amount_due + discount_amount) AS DECIMAL(18,2)),
       CAST(SUM(discount_amount) AS DECIMAL(18,2)),
       CAST(SUM(amount_paid) AS DECIMAL(18,2)),
       N'order_status = COMPLETED；不含 ABANDONED'
FROM tbl_order_header WHERE order_status = 'COMPLETED'
UNION ALL
SELECT N'已退款（由 FAILED 反推）', COUNT(*),
       CAST(SUM(amount_due + discount_amount) AS DECIMAL(18,2)),
       CAST(SUM(discount_amount) AS DECIMAL(18,2)),
       CAST(SUM(amount_paid) AS DECIMAL(18,2)),
       N'⚠️ amount_paid 是退款前原值，不是退款额之外的净额'
FROM tbl_order_header WHERE pay_status = 'FAILED'
ORDER BY 口径;
GO

/* ---------- 2c：按订单求和 vs 按明细求和的差额（必须等于折扣合计） ----------
 * ⚠️ 两侧必须分别聚合。若把 tbl_order_header 与 tbl_order_detail 直接 JOIN 后
 * 再 SUM(h.amount_paid)，订单头会被明细行数放大（实测放大成 37,387.00）。 */
PRINT N'--- S2.5 差额归因：按明细小计 - 按订单实付 应 = 折扣合计 ---';
GO
DECLARE @sub  DECIMAL(18,2),
        @paid DECIMAL(18,2),
        @disc DECIMAL(18,2);

SELECT @sub = SUM(d.subtotal)
FROM tbl_order_detail d
JOIN tbl_order_header h ON h.order_id = d.order_id
WHERE h.pay_status = 'SUCCESS';

SELECT @paid = SUM(amount_paid),
       @disc = SUM(discount_amount)
FROM tbl_order_header
WHERE pay_status = 'SUCCESS';

SELECT @sub  AS D_按明细小计,
       @paid AS D_按订单实付,
       @disc AS D_折扣合计,
       @sub - @paid - @disc AS 残差,
       CASE WHEN @sub - @paid = @disc
            THEN N'✅ 差额已由折扣完全解释' ELSE N'❌ 存在无法解释的差额' END AS 结论;
GO

/* ---------- 2d：已付未取（ABANDONED）明细，纳入销售额的依据 ---------- */
PRINT N'--- S2.6 ABANDONED（已付款未取件）计入销售额的明细 ---';
GO
WITH a AS (
    SELECT h.order_id, h.order_status, h.pay_status,
           h.amount_paid, h.discount_amount,
           (SELECT SUM(qty)      FROM tbl_order_detail d WHERE d.order_id = h.order_id) AS cups,
           (SELECT SUM(subtotal) FROM tbl_order_detail d WHERE d.order_id = h.order_id) AS sub
    FROM tbl_order_header h
    WHERE h.order_status = 'ABANDONED'
)
SELECT order_status,
       pay_status,
       COUNT(*)                                    AS 订单数,
       SUM(cups)                                   AS 杯数,
       CAST(SUM(sub)             AS DECIMAL(18,2)) AS 小计合计,
       CAST(SUM(discount_amount) AS DECIMAL(18,2)) AS 折扣合计,
       CAST(SUM(amount_paid)     AS DECIMAL(18,2)) AS 实付金额,
       CAST(AVG(amount_paid)     AS DECIMAL(18,2)) AS 单据均价
FROM a
GROUP BY order_status, pay_status;
GO

PRINT N'--- S2.7 指纹（迁移前 / 后各跑一次，先比指纹再比明细） ---';
GO
SELECT N'S2-商品销售' AS 块,
       COUNT(*)       AS 行数,
       CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS 指纹
FROM #s2;
GO

DROP TABLE #s2;
GO

PRINT N'=== S2 结束 ===';
GO
