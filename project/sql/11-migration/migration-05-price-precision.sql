/* ============================================================
 * 脚本：migration-05-price-precision.sql
 * 用途：把「单价 / 成本」类列的精度统一到 conventions/02-sql-style.md §6.3 的口径 ——
 *         单价 / 成本 → DECIMAL(12,4)
 *       涉及 6 列（原来错标成 DECIMAL(10,2) 或 DECIMAL(10,4)）：
 *         tbl_product.base_price                (10,2) → (12,4)
 *         tbl_spec_option.extra_price           (10,2) → (12,4)
 *         tbl_topping.extra_price               (10,2) → (12,4)
 *         tbl_order_detail.unit_price           (10,2) → (12,4)
 *         tbl_order_detail_topping.unit_extra_price (10,2) → (12,4)
 *         tbl_ingredient.moving_avg_cost        (10,4) → (12,4)
 * 依赖：
 *   02-constraints/constraints.sql —— 6 条的 CHECK 直接引用这些列，必须先删后建
 *   07-view/view.sql              —— 两个视图引用这些列，改完要刷新元数据
 * 阶段：第 7 周（v1.0）—— 第 7 周数据库审计的整改项
 * 作者：DiSod
 * 日期：2026-11-04
 * 说明：可重复执行 —— 已经是 (12,4) 的列跳过；CHECK 按名探测后重建。
 *
 * 为什么口径是「金额 (10,2) / 单价成本 (12,4)」而不是「一律取大」：
 *   §6.3 把三类数值分开定标，因为它们的量级和精度需求本来就不同：
 *     金额        总额，两位小数就够（分）
 *     物料数量    0.001 精度（g / ml 要小数点后三位）
 *     单价 / 成本 按基本单位计价时数值很小（如 0.0110 元/g），必须 4 位
 *   若把所有金额也升到 4 位，等于让「金额」这个域失去定标，
 *   而且 subtotal / amount_due 这类总额列会出现 0.001 元这种无意义的尾数。
 *
 * ⚠️ 连带影响（已评估，不是疏漏）：
 *   业务规则 A3 断言 subtotal = qty*unit_price + Σ加料费。unit_price 变 4 位后，
 *   若将来出现 3—4 位小数的单价，subtotal（金额，2 位）会四舍五入，等式只在
 *   「单价恰为 2 位小数」时严格成立。当前 2,629 行明细单价全是 x.00，
 *   所以实测偏差仍为 0；这一条已写进 business-rules.md 的 A3 备注。
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT N'【迁移05】=== 单价 / 成本精度对齐 DECIMAL(12,4) ===';
GO

BEGIN TRANSACTION;

BEGIN TRY
    /* ---------- 1. 迁移前体检：目标列当前精度 ---------- */
    SELECT
        c.TABLE_NAME + N'.' + c.COLUMN_NAME AS 列,
        c.NUMERIC_PRECISION                  AS 精度,
        c.NUMERIC_SCALE                      AS 小数位
    FROM INFORMATION_SCHEMA.COLUMNS AS c
    WHERE (c.TABLE_NAME = N'tbl_product'                AND c.COLUMN_NAME = N'base_price')
       OR (c.TABLE_NAME = N'tbl_spec_option'            AND c.COLUMN_NAME = N'extra_price')
       OR (c.TABLE_NAME = N'tbl_topping'                AND c.COLUMN_NAME = N'extra_price')
       OR (c.TABLE_NAME = N'tbl_order_detail'           AND c.COLUMN_NAME = N'unit_price')
       OR (c.TABLE_NAME = N'tbl_order_detail_topping'   AND c.COLUMN_NAME = N'unit_extra_price')
       OR (c.TABLE_NAME = N'tbl_ingredient'             AND c.COLUMN_NAME = N'moving_avg_cost')
    ORDER BY 列;

    /* ---------- 2. 删除引用这些列的 CHECK（不删就 ALTER 不动）---------- */
    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_product_base_price' AND parent_object_id = OBJECT_ID(N'tbl_product'))
    BEGIN
        ALTER TABLE tbl_product DROP CONSTRAINT ck_product_base_price;
        PRINT N'【迁移05】已移除 ck_product_base_price。';
    END

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_spec_option_extra_price' AND parent_object_id = OBJECT_ID(N'tbl_spec_option'))
    BEGIN
        ALTER TABLE tbl_spec_option DROP CONSTRAINT ck_spec_option_extra_price;
        PRINT N'【迁移05】已移除 ck_spec_option_extra_price。';
    END

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_topping_extra_price' AND parent_object_id = OBJECT_ID(N'tbl_topping'))
    BEGIN
        ALTER TABLE tbl_topping DROP CONSTRAINT ck_topping_extra_price;
        PRINT N'【迁移05】已移除 ck_topping_extra_price。';
    END

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_order_detail_unit_price' AND parent_object_id = OBJECT_ID(N'tbl_order_detail'))
    BEGIN
        ALTER TABLE tbl_order_detail DROP CONSTRAINT ck_order_detail_unit_price;
        PRINT N'【迁移05】已移除 ck_order_detail_unit_price。';
    END

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_order_detail_topping_unit_extra_price' AND parent_object_id = OBJECT_ID(N'tbl_order_detail_topping'))
    BEGIN
        ALTER TABLE tbl_order_detail_topping DROP CONSTRAINT ck_order_detail_topping_unit_extra_price;
        PRINT N'【迁移05】已移除 ck_order_detail_topping_unit_extra_price。';
    END

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_ingredient_moving_avg_cost' AND parent_object_id = OBJECT_ID(N'tbl_ingredient'))
    BEGIN
        ALTER TABLE tbl_ingredient DROP CONSTRAINT ck_ingredient_moving_avg_cost;
        PRINT N'【迁移05】已移除 ck_ingredient_moving_avg_cost。';
    END

    /* ---------- 3. 改精度（升精度不丢数据；已是 (12,4) 的跳过）---------- */
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_NAME = N'tbl_product' AND COLUMN_NAME = N'base_price'
                 AND NOT (NUMERIC_PRECISION = 12 AND NUMERIC_SCALE = 4))
        ALTER TABLE tbl_product ALTER COLUMN base_price DECIMAL(12,4) NOT NULL;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_NAME = N'tbl_spec_option' AND COLUMN_NAME = N'extra_price'
                 AND NOT (NUMERIC_PRECISION = 12 AND NUMERIC_SCALE = 4))
        ALTER TABLE tbl_spec_option ALTER COLUMN extra_price DECIMAL(12,4) NOT NULL;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_NAME = N'tbl_topping' AND COLUMN_NAME = N'extra_price'
                 AND NOT (NUMERIC_PRECISION = 12 AND NUMERIC_SCALE = 4))
        ALTER TABLE tbl_topping ALTER COLUMN extra_price DECIMAL(12,4) NOT NULL;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_NAME = N'tbl_order_detail' AND COLUMN_NAME = N'unit_price'
                 AND NOT (NUMERIC_PRECISION = 12 AND NUMERIC_SCALE = 4))
        ALTER TABLE tbl_order_detail ALTER COLUMN unit_price DECIMAL(12,4) NOT NULL;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_NAME = N'tbl_order_detail_topping' AND COLUMN_NAME = N'unit_extra_price'
                 AND NOT (NUMERIC_PRECISION = 12 AND NUMERIC_SCALE = 4))
        ALTER TABLE tbl_order_detail_topping ALTER COLUMN unit_extra_price DECIMAL(12,4) NOT NULL;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_NAME = N'tbl_ingredient' AND COLUMN_NAME = N'moving_avg_cost'
                 AND NOT (NUMERIC_PRECISION = 12 AND NUMERIC_SCALE = 4))
        ALTER TABLE tbl_ingredient ALTER COLUMN moving_avg_cost DECIMAL(12,4) NOT NULL;

    PRINT N'【迁移05】6 列精度已对齐 DECIMAL(12,4)。';

    /* ---------- 4. 重建 6 条 CHECK（定义与原来一致）---------- */
    ALTER TABLE tbl_product WITH CHECK
        ADD CONSTRAINT ck_product_base_price CHECK (base_price >= 0);

    ALTER TABLE tbl_spec_option WITH CHECK
        ADD CONSTRAINT ck_spec_option_extra_price CHECK (extra_price >= 0);

    ALTER TABLE tbl_topping WITH CHECK
        ADD CONSTRAINT ck_topping_extra_price CHECK (extra_price >= 0);

    ALTER TABLE tbl_order_detail WITH CHECK
        ADD CONSTRAINT ck_order_detail_unit_price CHECK (unit_price >= 0);

    ALTER TABLE tbl_order_detail_topping WITH CHECK
        ADD CONSTRAINT ck_order_detail_topping_unit_extra_price CHECK (unit_extra_price >= 0);

    ALTER TABLE tbl_ingredient WITH CHECK
        ADD CONSTRAINT ck_ingredient_moving_avg_cost CHECK (moving_avg_cost >= 0);

    PRINT N'【迁移05】6 条 CHECK 已重建（WITH CHECK，is_not_trusted = 0）。';

    /* ---------- 5. 刷新引用这些列的视图元数据 ---------- */
    EXEC sp_refreshview N'vw_product_stock_availability';
    EXEC sp_refreshview N'vw_order_detail_full';
    EXEC sp_refreshview N'vw_ingredient_reorder_alert';
    EXEC sp_refreshview N'vw_daily_business_summary';
    EXEC sp_refreshview N'vw_member_consumption_profile';
    EXEC sp_refreshview N'vw_coupon_legacy';
    PRINT N'【迁移05】6 个视图的元数据已刷新。';

    /* ---------- 6. 自证：精度全是 (12,4)、CHECK 都回来了 ---------- */
    DECLARE @bad_precision INT, @bad_checks INT;

    SELECT @bad_precision = COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS AS c
    WHERE ((c.TABLE_NAME = N'tbl_product'              AND c.COLUMN_NAME = N'base_price')
        OR (c.TABLE_NAME = N'tbl_spec_option'          AND c.COLUMN_NAME = N'extra_price')
        OR (c.TABLE_NAME = N'tbl_topping'              AND c.COLUMN_NAME = N'extra_price')
        OR (c.TABLE_NAME = N'tbl_order_detail'         AND c.COLUMN_NAME = N'unit_price')
        OR (c.TABLE_NAME = N'tbl_order_detail_topping' AND c.COLUMN_NAME = N'unit_extra_price')
        OR (c.TABLE_NAME = N'tbl_ingredient'           AND c.COLUMN_NAME = N'moving_avg_cost'))
      AND NOT (c.NUMERIC_PRECISION = 12 AND c.NUMERIC_SCALE = 4);

    SELECT @bad_checks = 6 - COUNT(*)
    FROM sys.check_constraints
    WHERE name IN (N'ck_product_base_price', N'ck_spec_option_extra_price',
                   N'ck_topping_extra_price', N'ck_order_detail_unit_price',
                   N'ck_order_detail_topping_unit_extra_price', N'ck_ingredient_moving_avg_cost')
      AND is_disabled = 0;

    IF @bad_precision <> 0 OR @bad_checks <> 0
    BEGIN
        DECLARE @msg NVARCHAR(400) = FORMATMESSAGE(
            N'【迁移05】自证未通过（精度未达标的列 %d 个，缺失或禁用的 CHECK %d 条），事务回滚。',
            @bad_precision, @bad_checks);
        RAISERROR(@msg, 16, 1);
    END

    PRINT N'【迁移05】自证通过：6 列精度均为 (12,4)，6 条 CHECK 均可信。';
    PRINT N'【迁移05】事务提交成功。';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT N'【迁移05】✗ 失败，已回滚：' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/* ---------- 7. 回显：全部 DECIMAL 列的最终精度 ---------- */
SELECT
    c.TABLE_NAME + N'.' + c.COLUMN_NAME AS 列,
    c.NUMERIC_PRECISION                  AS 精度,
    c.NUMERIC_SCALE                      AS 小数位
FROM INFORMATION_SCHEMA.COLUMNS AS c
WHERE c.DATA_TYPE = N'decimal'
  AND c.TABLE_NAME LIKE N'tbl[_]%'
ORDER BY 列;
GO
