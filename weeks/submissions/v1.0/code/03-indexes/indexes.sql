/* ============================================================
 * 脚本：indexes.sql
 * 用途：为高频连接与过滤路径建立索引
 * 依赖：01-schema/create-tables.sql、02-constraints/constraints.sql
 * 阶段：第 4 周
 * 作者：DiSod
 * 日期：2026-10-04
 * 幂等：是 —— 先删除同名索引再创建
 * ============================================================
 *
 * 【为什么需要这个脚本】
 *   **SQL Server 不会为外键自动建索引**（这一点与 MySQL 不同）。
 *   外键只保证引用完整性，不提供查询加速 —— 索引必须显式建。
 *
 * 【选哪些列建索引用了一条判据】
 *   **「这一列会不会被用来连接或过滤，且它所在表的行数会不会增长」**
 *
 *   ✅ 建：**事实表 / 明细表 / 流水表**上的外键 —— 行数随营业增长，是 JOIN 的主力
 *   ❌ 不建：**小字典表**上的外键 —— 表只有几行到几十行，
 *            全表扫描比索引查找还快，建了反而是负担
 *
 * 【本脚本 21 个索引】
 *   19 个建在外键列上（连接路径）
 *    2 个建在日期/时间列上（统计视图与台账查询驱动）
 *
 * 【执行方式】
 *   sqlcmd -S .\SQLEXPRESS -E -i project/sql/03-indexes/indexes.sql
 * ============================================================ */

USE milktea_shop;
GO

SET NOCOUNT ON;
GO

/* ============================================================
 * 幂等处理：删除本脚本负责的索引（ix_ 前缀）
 * ============================================================ */
DECLARE @drop_ix NVARCHAR(MAX) = N'';

SELECT @drop_ix = @drop_ix
                + N'DROP INDEX ' + QUOTENAME(name)
                + N' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(object_id))
                + N'.' + QUOTENAME(OBJECT_NAME(object_id)) + N';' + CHAR(13)
FROM sys.indexes
WHERE name LIKE N'ix[_]%'
  AND object_id IN (SELECT object_id
                     FROM sys.tables WHERE name LIKE N'tbl[_]%');

IF LEN(@drop_ix) > 0
BEGIN
    PRINT N'【索引】清理既有 ix_ 索引 ...';
    EXEC sp_executesql @drop_ix;
END
GO

PRINT N'【索引】开始建索引 ...';
GO

/* ============================================================
 * 一、连接路径索引（19 个）
 * ============================================================ */

-- ---------- 主数据侧 ----------

-- 按品类筛选 / 统计商品
CREATE INDEX ix_product_category
    ON tbl_product (category_id);

-- 反查：某个原料被哪些小料使用
CREATE INDEX ix_topping_ingredient
    ON tbl_topping (ingredient_id);

-- ⭐ 扣料主路径：按成品取配方（"还能做几杯"视图的第一步）
CREATE INDEX ix_recipe_product
    ON tbl_recipe (product_id);

-- ⭐ "还能做几杯"的第二步：按原料聚合配方用量
CREATE INDEX ix_recipe_ingredient
    ON tbl_recipe (ingredient_id);

-- ---------- 采购侧（四层级联 JOIN 的后三跳） ----------

-- 供应商 → 采购单
CREATE INDEX ix_purchase_order_supplier
    ON tbl_purchase_order (supplier_id);

-- 采购单 → 采购明细
CREATE INDEX ix_purchase_order_detail_purchase_order
    ON tbl_purchase_order_detail (purchase_order_id);

-- 按原料统计采购历史（移动加权成本）
CREATE INDEX ix_purchase_order_detail_ingredient
    ON tbl_purchase_order_detail (ingredient_id);

-- ---------- 会员侧 ----------

-- 查某会员的券；带 status 是因为"可用券"查询几乎总是按状态过滤
CREATE INDEX ix_coupon_member_status
    ON tbl_coupon (member_id, status);

-- 会员消费分析：消费额 / 消费次数 / 最近到店
CREATE INDEX ix_order_header_member
    ON tbl_order_header (member_id);

-- 按收银员统计（week1 §2.2 的职责分离要能查"谁收的"）
CREATE INDEX ix_order_header_cashier
    ON tbl_order_header (cashier_id);

-- ---------- 交易侧（行数最大的部分） ----------

-- ⭐ 最高频的连接：订单 → 明细
CREATE INDEX ix_order_detail_order
    ON tbl_order_detail (order_id);

-- 销量排行 / 单品分析
CREATE INDEX ix_order_detail_product
    ON tbl_order_detail (product_id);

-- 明细 → 加料
CREATE INDEX ix_order_detail_topping_order_detail
    ON tbl_order_detail_topping (order_detail_id);

-- 加料销量排行
CREATE INDEX ix_order_detail_topping_topping
    ON tbl_order_detail_topping (topping_id);

-- ---------- 流水侧 ----------

-- 积分流水：查某会员的积分去向
CREATE INDEX ix_points_ledger_member
    ON tbl_points_ledger (member_id);

-- 订单 → 积分（核对某单累积了多少分）
CREATE INDEX ix_points_ledger_order
    ON tbl_points_ledger (order_id);

-- ⭐ 台账对账主路径：按原料汇总全部流水
CREATE INDEX ix_stock_ledger_ingredient
    ON tbl_stock_ledger (ingredient_id);

-- ⭐ 反查：某张订单扣了哪些料（正是"反冲倒扣"的可追溯性）
CREATE INDEX ix_stock_ledger_order
    ON tbl_stock_ledger (order_id);

-- 采购单 → 流水
CREATE INDEX ix_stock_ledger_purchase_order
    ON tbl_stock_ledger (purchase_order_id);

/* ============================================================
 * 二、查询驱动索引（2 个）
 *
 * 这两个不是外键列，而是**统计视图与台账查询**的过滤条件。
 * ============================================================ */

-- 日销统计：按营业日聚合订单（第 4 周统计视图的主力条件）
CREATE INDEX ix_order_header_business_date
    ON tbl_order_header (business_date);

-- 台账时间轴：按时间区间查流水（对账、经营日报）
CREATE INDEX ix_stock_ledger_ledger_time
    ON tbl_stock_ledger (ledger_time);
GO

PRINT N'【索引】21 个已创建。';
GO

/* ============================================================
 * 三、明确【不建索引】的列（答辩时能讲出"考虑过并主动放弃"）
 *
 *   | 列 | 表 | 不建的理由 |
 *   |---|---|---|
 *   | parent_category_id | tbl_product_category | 全表仅 5 行，自引用层级几乎不查 |
 *   | coupon_id | tbl_order_header | 券是可选、低频；且已由 ix_coupon_member_status 覆盖会员侧 |
 *   | coupon_id | tbl_points_ledger | 同上 |
 *   | cup_spec_id / sugar_spec_id | tbl_recipe | 规格共 12 行；且查询多先按 product_id 过滤 |
 *   | cup_spec_id / sugar_spec_id / ice_spec_id | tbl_order_detail | 同上；明细查询几乎都从 order_id 进 |
 *   | ordered_by / received_by | tbl_purchase_order | 员工仅 5 人，区分度极低 |
 *   | operator_id | tbl_stock_ledger | 同上 |
 * ============================================================ */

PRINT N'【索引】完成。当前索引清单：';
GO

SELECT
    OBJECT_NAME(i.object_id)  AS [表],
    i.name                    AS [索引],
    i.type_desc               AS [类型],
    (SELECT COUNT(*) FROM sys.index_columns ic
      WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id) AS [列数]
FROM sys.indexes i
WHERE i.name LIKE N'ix[_]%'
  AND i.object_id IN (SELECT object_id
                       FROM sys.tables WHERE name LIKE N'tbl[_]%')
ORDER BY OBJECT_NAME(i.object_id), i.name;
GO

PRINT N'【索引】下一步：执行 04-seed/seed_data.sql 装载种子数据。';
GO
