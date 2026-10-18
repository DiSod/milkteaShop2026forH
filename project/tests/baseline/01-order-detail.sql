/* ============================================================
 * 基线快照：01-order-detail.sql
 * 用途：第 6 周模式迁移的「订单明细」迁移前 / 后结果留档（课程任务 ①）
 * 依赖：00-bootstrap ~ 08-security + 11-migration
 * 阶段：第 6 周
 *
 * 抽样规则（确定性，可复现）：
 *   0-用券(全量) —— 24 单，因本次迁移对象就是券表，券路径不抽样
 *   A-多明细     —— 明细行数 >= 3 的订单，按行数降序取前 4
 *   B-有加料     —— 含加料记录的订单，按 order_id 取前 4
 *   D-散客       —— member_id IS NULL 的订单，按 order_id 取前 4
 *   四层取并集去重（同一单命中多层时按 0 > A > B > D 只保留一个理由）
 *   ⚠️ 配额是在去重【前】按层各取 4 单，所以与"用券 24 单"重叠的会被吞掉，
 *      净得数可能小于 4（实测 A 层净得 3 单、D 层净得 3 单）。这是确定性行为，不是 bug。
 *
 * 实测规模：34 张订单 / 59 行明细 / 17 行加料
 * 用法：
 *   sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -W -s"|" -w 8000 -i 01-order-detail.sql -o result\before-S01.txt
 * ============================================================ */

USE milktea_shop;
GO

SET NOCOUNT ON;
SET ANSI_WARNINGS OFF;
GO

PRINT N'=== S1 订单明细基线快照 ===';
GO

WITH ord AS (
    SELECT o.order_id,
           o.coupon_id,
           o.member_id,
           (SELECT COUNT(*) FROM tbl_order_detail d
             WHERE d.order_id = o.order_id) AS n_lines,
           (SELECT COUNT(*) FROM tbl_order_detail d
              JOIN tbl_order_detail_topping t ON t.order_detail_id = d.order_detail_id
             WHERE d.order_id = o.order_id) AS n_top
    FROM tbl_order_header o
),
pick AS (
    SELECT order_id, MIN(prio) AS prio
    FROM (
        SELECT order_id, 0 AS prio FROM ord WHERE coupon_id IS NOT NULL
        UNION ALL
        SELECT order_id, 1
        FROM (SELECT order_id, ROW_NUMBER() OVER (ORDER BY n_lines DESC, order_id) AS rn
              FROM ord WHERE n_lines >= 3) a
        WHERE rn <= 4
        UNION ALL
        SELECT order_id, 2
        FROM (SELECT order_id, ROW_NUMBER() OVER (ORDER BY order_id) AS rn
              FROM ord WHERE n_top > 0) b
        WHERE rn <= 4
        UNION ALL
        SELECT order_id, 3
        FROM (SELECT order_id, ROW_NUMBER() OVER (ORDER BY order_id) AS rn
              FROM ord WHERE member_id IS NULL) c
        WHERE rn <= 4
    ) u
    GROUP BY order_id
),
pick2 AS (
    SELECT order_id,
           CASE prio WHEN 0 THEN N'0-用券(全量)'
                     WHEN 1 THEN N'A-多明细'
                     WHEN 2 THEN N'B-有加料'
                     ELSE        N'D-散客' END AS 入选理由
    FROM pick
),
tp AS (
    SELECT t.order_detail_id,
           COUNT(*)                        AS 加料条数,
           SUM(t.qty * t.unit_extra_price)  AS 加料费,
           STRING_AGG(CONCAT(tp2.topping_name, N'×', t.qty), N' + ') AS 加料清单
    FROM tbl_order_detail_topping t
    JOIN tbl_topping tp2 ON tp2.topping_id = t.topping_id
    GROUP BY t.order_detail_id
)
SELECT p.入选理由,
       o.order_id,
       o.order_no,
       o.business_date,
       o.order_status,
       o.pay_status,
       o.member_id,
       o.coupon_id,
       o.discount_amount,
       o.amount_due,
       o.amount_paid,
       d.order_detail_id,
       d.line_no,
       pd.product_code,
       pd.product_name,
       cs.spec_code  AS 杯型,
       ss.spec_code  AS 糖度,
       ics.spec_code AS 冰量,
       d.qty,
       d.unit_price,
       d.subtotal,
       ISNULL(tp.加料条数, 0) AS 加料条数,
       ISNULL(tp.加料费, 0)   AS 加料费,
       tp.加料清单,
       d.qty * d.unit_price + ISNULL(tp.加料费, 0)                AS 复算小计,
       d.subtotal - (d.qty * d.unit_price + ISNULL(tp.加料费, 0)) AS 小计偏差
INTO #s1
FROM pick2 p
JOIN tbl_order_header    o   ON o.order_id          = p.order_id
JOIN tbl_order_detail    d   ON d.order_id          = o.order_id
JOIN tbl_product         pd  ON pd.product_id       = d.product_id
LEFT JOIN tbl_spec_option cs  ON cs.spec_option_id  = d.cup_spec_id
LEFT JOIN tbl_spec_option ss  ON ss.spec_option_id  = d.sugar_spec_id
LEFT JOIN tbl_spec_option ics ON ics.spec_option_id = d.ice_spec_id
LEFT JOIN tp                  ON tp.order_detail_id = d.order_detail_id;
GO

PRINT N'--- S1.1 明细（按 order_id / line_no 稳定排序） ---';
GO
SELECT * FROM #s1 ORDER BY order_id, line_no;
GO

PRINT N'--- S1.2 抽样覆盖统计（说明"为什么抽到这些单"） ---';
GO
SELECT 入选理由,
       COUNT(DISTINCT order_id) AS 订单数,
       COUNT(*)                 AS 明细行数,
       SUM(CASE WHEN 加料条数 > 0 THEN 1 ELSE 0 END) AS 含加料明细行数,
       SUM(CASE WHEN member_id IS NULL THEN 1 ELSE 0 END) AS 散客明细行数,
       SUM(CASE WHEN coupon_id IS NOT NULL THEN 1 ELSE 0 END) AS 用券明细行数
FROM #s1
GROUP BY 入选理由
ORDER BY 入选理由;
GO

PRINT N'--- S1.3 不变量自检（复算小计 - 小计偏差 应恒为 0） ---';
GO
SELECT COUNT(*)                              AS 明细行数,
       SUM(CASE WHEN 小计偏差 <> 0 THEN 1 ELSE 0 END) AS 小计偏差非零行数,
       CAST(MAX(ABS(小计偏差)) AS DECIMAL(18,2))      AS 最大绝对偏差
FROM #s1;
GO

PRINT N'--- S1.4 指纹（迁移前 / 后各跑一次，先比指纹再比明细） ---';
GO
SELECT N'S1-订单明细' AS 块,
       COUNT(*)       AS 行数,
       CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS 指纹
FROM #s1;
GO

DROP TABLE #s1;
GO

PRINT N'=== S1 结束 ===';
GO
