/* ============================================================
 * 脚本：migration-06-order-cancellation.sql
 * 用途：为「订单取消」在两张流水表上各开一个业务动作类别 ——
 *         ① tbl_stock_ledger.ledger_type  增加 'CANCEL_BACK'（取消回冲，数量为正）
 *         ② tbl_points_ledger.point_type  增加 'REVOKE'      （取消扣回积分，数量为负）
 *       三条 CHECK 的定义被替换，**约束条数不变**（仍是 48 条）。
 * 依赖：02-constraints/constraints.sql、migration-03（points 的 target 约束已放宽过）
 * 阶段：第 9 周（v1.0）—— ISSUE-017「订单取消」的配套结构变更
 * 作者：DiSod
 * 日期：2026-11-09
 * 说明：可重复执行 —— 约束按名探测后重建；重建前先体检，有违例就整体回滚。
 *
 * 为什么必须新开类型，而不是复用现有取值：
 *   · 库存侧原有三个类别是 PURCHASE_IN（入库）/ SALES_USE（销售耗用）/ LOSS（报损），
 *     都是"消耗"方向；取消回冲是把原料**加回来**，语义上没有一个是它。
 *     复用 SALES_USE 再写正数，会让"销售耗用合计"这个统计口径被回冲污染。
 *   · 积分侧原有 EARN / REDEEM / OPENING：REDEEM 的业务含义是"兑换券抵掉的积分"，
 *     用它记"订单取消扣回"会让兑换券的台账（ISSUE-014 A11 那条待议）更加说不清。
 *   宁可多两个枚举值，也不要把两种业务动作挤进同一个词。
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT N'【迁移06】=== 订单取消的流水类型（CANCEL_BACK / REVOKE）===';
GO

BEGIN TRANSACTION;

BEGIN TRY
    /* ---------- 1. 迁移前体检 ---------- */
    DECLARE @checks_before INT;

    SELECT @checks_before = COUNT(*) FROM sys.check_constraints;

    IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
                   WHERE name = N'ck_stock_ledger_ledger_type'
                     AND parent_object_id = OBJECT_ID(N'tbl_stock_ledger'))
        THROW 51201, N'【迁移06】找不到 ck_stock_ledger_ledger_type，请先执行 02-constraints/constraints.sql。', 1;

    IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
                   WHERE name = N'ck_points_ledger_point_type'
                     AND parent_object_id = OBJECT_ID(N'tbl_points_ledger'))
        THROW 51202, N'【迁移06】找不到 ck_points_ledger_point_type，请先执行 02-constraints/constraints.sql。', 1;

    IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
                   WHERE name = N'ck_points_ledger_target'
                     AND parent_object_id = OBJECT_ID(N'tbl_points_ledger'))
        THROW 51203, N'【迁移06】找不到 ck_points_ledger_target，请先执行 02-constraints/constraints.sql。', 1;

    PRINT N'【迁移06】迁移前：全库 CHECK 共 ' + CAST(@checks_before AS NVARCHAR(10)) + N' 条。';

    /* ---------- 2. 幂等清理 ---------- */
    ALTER TABLE tbl_stock_ledger  DROP CONSTRAINT ck_stock_ledger_ledger_type;
    ALTER TABLE tbl_points_ledger DROP CONSTRAINT ck_points_ledger_point_type;
    ALTER TABLE tbl_points_ledger DROP CONSTRAINT ck_points_ledger_target;
    PRINT N'【迁移06】已移除三条待改写的 CHECK。';

    /* ---------- 3. 重建（WITH CHECK 保证 is_not_trusted = 0）---------- */
    ALTER TABLE tbl_stock_ledger WITH CHECK
        ADD CONSTRAINT ck_stock_ledger_ledger_type
        CHECK (ledger_type IN ('PURCHASE_IN', 'SALES_USE', 'LOSS', 'CANCEL_BACK'));
    PRINT N'【迁移06】已重建 ck_stock_ledger_ledger_type —— 增加 CANCEL_BACK。';

    ALTER TABLE tbl_points_ledger WITH CHECK
        ADD CONSTRAINT ck_points_ledger_point_type
        CHECK (point_type IN ('EARN', 'REDEEM', 'OPENING', 'REVOKE'));
    PRINT N'【迁移06】已重建 ck_points_ledger_point_type —— 增加 REVOKE。';

    -- REVOKE 必须挂在订单上（取消的是订单，不是券），且不能带 coupon_id
    ALTER TABLE tbl_points_ledger WITH CHECK
        ADD CONSTRAINT ck_points_ledger_target
        CHECK (
            point_type = 'EARN'    AND order_id IS NOT NULL
         OR point_type = 'REDEEM'  AND (coupon_id IS NOT NULL OR order_id IS NOT NULL)
         OR point_type = 'OPENING' AND order_id IS NULL AND coupon_id IS NULL
         OR point_type = 'REVOKE'  AND order_id IS NOT NULL AND coupon_id IS NULL
        );
    PRINT N'【迁移06】已重建 ck_points_ledger_target —— REVOKE 必须挂订单、不得挂券。';

    /* ---------- 4. 自证：三条都在、都可信、条数没变 ---------- */
    DECLARE @checks_after INT, @bad_state INT, @has_tokens INT;

    SELECT @checks_after = COUNT(*) FROM sys.check_constraints;

    SELECT @bad_state = COUNT(*)
    FROM sys.check_constraints
    WHERE name IN (N'ck_stock_ledger_ledger_type',
                   N'ck_points_ledger_point_type',
                   N'ck_points_ledger_target')
      AND (is_disabled = 1 OR is_not_trusted = 1);

    SELECT @has_tokens = COUNT(*)
    FROM sys.check_constraints
    WHERE (name = N'ck_stock_ledger_ledger_type'  AND definition LIKE N'%CANCEL_BACK%')
       OR (name = N'ck_points_ledger_point_type'  AND definition LIKE N'%REVOKE%')
       OR (name = N'ck_points_ledger_target'      AND definition LIKE N'%REVOKE%');

    IF @bad_state <> 0
        THROW 51204, N'【迁移06】自证未通过：有约束被禁用或不可信，事务回滚。', 1;

    IF @has_tokens <> 3
        THROW 51205, N'【迁移06】自证未通过：新取值未出现在约束定义里，事务回滚。', 1;

    IF @checks_after <> @checks_before
        THROW 51206, N'【迁移06】自证未通过：CHECK 条数发生变化（应为不变），事务回滚。', 1;

    PRINT N'【迁移06】自证通过：三条约束均已重建、可信，全库 CHECK 仍为 '
        + CAST(@checks_after AS NVARCHAR(10)) + N' 条。';
    PRINT N'【迁移06】事务提交成功。';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT N'【迁移06】✗ 失败，已回滚：' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/* ---------- 5. 回显：两张流水表的 CHECK ---------- */
SELECT
    OBJECT_NAME(cc.parent_object_id) AS 表,
    cc.name          AS 约束,
    cc.definition    AS 定义,
    cc.is_disabled   AS 已禁用,
    cc.is_not_trusted AS 未经校验
FROM sys.check_constraints AS cc
WHERE cc.parent_object_id IN (OBJECT_ID(N'tbl_stock_ledger'), OBJECT_ID(N'tbl_points_ledger'))
ORDER BY 表, 约束;
GO
