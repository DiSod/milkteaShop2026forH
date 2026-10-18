/* ============================================================
 * 基线快照：03-stock-query.sql
 * 用途：第 6 周模式迁移的「库存查询」迁移前 / 后结果留档（课程任务 ①③）
 * 依赖：00-bootstrap ~ 08-security + 11-migration
 * 阶段：第 6 周
 *
 * 为什么同时查基表和视图：
 *   迁移改的是基表。只查视图会把"视图 vs 视图"的差异吸收掉，
 *   所以 3a 查 tbl_ingredient 原始行，3b 查 vw_product_stock_availability，
 *   两者各有独立指纹。视图是派生物，改坏它不会影响 3a，故必须单独比。
 *
 * 实测：原料 60 行 / 单位 5 种 / 视图 57 行 / theor_makeable_cups 合计 5,579
 *       sale_status 是中文四值：充足在售 51 / 紧张预警 6 / 临时沽清 4 / 已下架 2
 *       （不是 AVAILABLE / SOLD_OUT 这类英文枚举，写断言时别猜）
 * 用法：
 *   sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -W -s"|" -w 8000 -i 03-stock-query.sql -o result\before-S03.txt
 * ============================================================ */

USE milktea_shop;
GO

SET NOCOUNT ON;
SET ANSI_WARNINGS OFF;
GO

PRINT N'=== S3 库存查询基线快照 ===';
GO

/* ---------- 3a：原料基表（迁移对比的唯一真相源） ---------- */
PRINT N'--- S3.1 tbl_ingredient 原始行（按 ingredient_code 稳定排序） ---';
GO
SELECT ingredient_code,
       ingredient_name,
       spec,
       unit,
       qty_on_hand,
       reorder_point,
       target_level,
       moving_avg_cost,
       CAST(qty_on_hand * moving_avg_cost AS DECIMAL(18,2)) AS 库存金额,
       is_sold_out,
       is_active,
       CASE WHEN qty_on_hand < reorder_point THEN N'低于补货点'
            WHEN qty_on_hand < target_level  THEN N'低于目标水位'
            ELSE N'充足' END AS 补货判断
FROM tbl_ingredient
ORDER BY ingredient_code;
GO

PRINT N'--- S3.2 原料账合计（⚠️ qty_on_hand 跨单位相加无业务含义，仅作指纹） ---';
GO
SELECT COUNT(*)                                                    AS 原料行数,
       COUNT(DISTINCT unit)                                        AS 单位种类数,
       COUNT(DISTINCT spec)                                        AS 规格种类数,
       SUM(CASE WHEN is_sold_out = 1 THEN 1 ELSE 0 END)            AS 手工沽清行数,
       SUM(CASE WHEN is_active   = 0 THEN 1 ELSE 0 END)            AS 停用行数,
       SUM(CASE WHEN qty_on_hand < reorder_point THEN 1 ELSE 0 END) AS 低于补货点行数,
       CAST(SUM(qty_on_hand) AS DECIMAL(18,3))                     AS 跨单位数量总和_无业务含义,
       CAST(SUM(qty_on_hand * moving_avg_cost) AS DECIMAL(18,2))   AS 库存金额合计,
       CHECKSUM_AGG(BINARY_CHECKSUM(*))                            AS 原料行指纹
FROM tbl_ingredient;
GO

/* ---------- 3b：库存视图（"还能做几杯" = 木桶原理 + 手工沽清） ---------- */
PRINT N'--- S3.3 vw_product_stock_availability（按 product_code, cup_spec_id 稳定排序） ---';
GO
SELECT category_name,
       product_code,
       product_name,
       cup_spec_id,
       cup_spec_name,
       selling_price,
       theor_makeable_cups,
       is_ingredient_sold_out,
       product_status,
       sale_status
FROM vw_product_stock_availability
ORDER BY product_code, cup_spec_id;
GO

PRINT N'--- S3.4 视图口径合计（覆盖全部 57 行，含已售罄 / 停售） ---';
GO
SELECT COUNT(*)                                                  AS 视图行数,
       COUNT(DISTINCT product_code)                              AS 商品数,
       SUM(CASE WHEN sale_status = N'充足在售' THEN 1 ELSE 0 END) AS 充足在售行数,
       SUM(CASE WHEN sale_status = N'紧张预警' THEN 1 ELSE 0 END) AS 紧张预警行数,
       SUM(CASE WHEN sale_status = N'临时沽清' THEN 1 ELSE 0 END) AS 临时沽清行数,
       SUM(CASE WHEN sale_status = N'已下架'   THEN 1 ELSE 0 END) AS 已下架行数,
       SUM(CASE WHEN is_ingredient_sold_out = 1 THEN 1 ELSE 0 END) AS 原料沽清行数,
       SUM(theor_makeable_cups)                                  AS theor_makeable_cups_合计,
       CAST(AVG(CAST(theor_makeable_cups AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS 平均可做杯数,
       CHECKSUM_AGG(BINARY_CHECKSUM(*))                          AS 视图行指纹
FROM vw_product_stock_availability;
GO

PRINT N'--- S3.5 theory 分布（"木桶"缺口在哪一环） ---';
GO
SELECT CASE WHEN theor_makeable_cups = 0  THEN N'0 杯'
            WHEN theor_makeable_cups <= 5 THEN N'1—5 杯'
            WHEN theor_makeable_cups <= 20 THEN N'6—20 杯'
            ELSE N'20 杯以上' END AS 可做杯数区间,
       COUNT(*) AS 行数,
       SUM(CASE WHEN sale_status = N'充足在售' THEN 1 ELSE 0 END) AS 充足在售行数
FROM vw_product_stock_availability
GROUP BY CASE WHEN theor_makeable_cups = 0  THEN N'0 杯'
              WHEN theor_makeable_cups <= 5 THEN N'1—5 杯'
              WHEN theor_makeable_cups <= 20 THEN N'6—20 杯'
              ELSE N'20 杯以上' END
ORDER BY 可做杯数区间;
GO

PRINT N'--- S3.6 按单位分组（跨单位求和不可加，必须分组） ---';
GO
SELECT unit,
       COUNT(*)                                                  AS 原料行数,
       CAST(SUM(qty_on_hand) AS DECIMAL(18,3))                   AS 结存数量,
       CAST(SUM(reorder_point) AS DECIMAL(18,3))                 AS 补货点合计,
       CAST(SUM(target_level) AS DECIMAL(18,3))                  AS 目标水位合计,
       CAST(SUM(qty_on_hand * moving_avg_cost) AS DECIMAL(18,2)) AS 库存金额,
       SUM(CASE WHEN qty_on_hand < reorder_point THEN 1 ELSE 0 END) AS 低于补货点行数
FROM tbl_ingredient
GROUP BY unit
ORDER BY unit;
GO

PRINT N'--- S3.7 不变量自检：qty_on_hand < 0 应无行；沽清与结存不应矛盾 ---';
GO
SELECT SUM(CASE WHEN qty_on_hand < 0 THEN 1 ELSE 0 END)               AS 负结存行数,
       SUM(CASE WHEN is_sold_out = 1 AND qty_on_hand > 0 THEN 1 ELSE 0 END) AS 沽清但仍有库存行数,
       SUM(CASE WHEN qty_on_hand = 0 AND is_sold_out = 0 AND is_active = 1
                THEN 1 ELSE 0 END)                                    AS 零结存未沽清行数
FROM tbl_ingredient;
GO

PRINT N'=== S3 结束 ===';
GO
