/* ============================================================
 * 脚本：migration-04-order-time-constraints.sql
 * 用途：给订单头补上「时间序」的两条约束 ——
 *         ① pay_time    >= order_time      （不能先付款后下单）
 *         ② finish_time >= pay_time        （不能先完成再付款）
 *       原有 ck_order_header_finish_time 只锁了 finish_time >= order_time，
 *       也就是首尾锁住了、中间没锁，可以写出「付款早于下单」「完成早于付款」的单。
 * 依赖：02-constraints/constraints.sql（tbl_order_header 与 finish_time 约束已存在）
 * 阶段：第 7 周（v1.0）—— 第 7 周数据库审计的整改项
 * 作者：DiSod
 * 日期：2026-11-04
 * 说明：可重复执行 —— 约束按名探测后重建；重建前先体检，有违例就整体回滚。
 *
 * 为什么是「补两条」而不是「改一条」：
 *   改 ck_order_header_finish_time 会让约束名与语义脱节（名字叫 finish_time，
 *   却还管 pay_time）。新建两条各管一段，报错时从约束名就能读出是哪条时序错了。
 *
 * 为什么不顺手加「pay_status 非空 ⇒ pay_time 非空」：
 *   现有数据有 37 张 CANCELLED 单 pay_status='FAILED' 而 pay_time IS NULL，
 *   加了会直接让 37 行变非法。这条属于**数据事实与字段语义不一致**，
 *   应当由数据侧（造数/业务流程）决定 FAILED 要不要有时间戳，不在本次整改范围。
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT N'【迁移04】=== 订单头时间序约束（pay_time / finish_time）===';
GO

BEGIN TRANSACTION;

BEGIN TRY
    /* ---------- 1. 迁移前体检 ---------- */
    DECLARE @pay_before_order INT, @finish_before_pay INT;

    SELECT
        @pay_before_order = COUNT(*)
    FROM tbl_order_header
    WHERE pay_time IS NOT NULL AND pay_time < order_time;

    SELECT
        @finish_before_pay = COUNT(*)
    FROM tbl_order_header
    WHERE finish_time IS NOT NULL AND pay_time IS NOT NULL
      AND finish_time < pay_time;

    PRINT N'【迁移04】迁移前体检：付款早于下单 ' + CAST(@pay_before_order AS NVARCHAR(10))
        + N' 单；完成早于付款 ' + CAST(@finish_before_pay AS NVARCHAR(10)) + N' 单。';

    IF @pay_before_order > 0 OR @finish_before_pay > 0
    BEGIN
        DECLARE @msg NVARCHAR(400) = FORMATMESSAGE(
            N'【迁移04】当前数据不满足新约束（付款早于下单 %d 单，完成早于付款 %d 单），事务回滚。',
            @pay_before_order, @finish_before_pay);
        RAISERROR(@msg, 16, 1);
    END

    /* ---------- 2. 幂等清理：同名约束存在则先删 ---------- */
    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_order_header_pay_time'
                 AND parent_object_id = OBJECT_ID(N'tbl_order_header'))
    BEGIN
        ALTER TABLE tbl_order_header DROP CONSTRAINT ck_order_header_pay_time;
        PRINT N'【迁移04】已移除旧的 ck_order_header_pay_time。';
    END

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_order_header_finish_after_pay'
                 AND parent_object_id = OBJECT_ID(N'tbl_order_header'))
    BEGIN
        ALTER TABLE tbl_order_header DROP CONSTRAINT ck_order_header_finish_after_pay;
        PRINT N'【迁移04】已移除旧的 ck_order_header_finish_after_pay。';
    END

    /* ---------- 3. 建立两条时序约束（WITH CHECK 保证 is_not_trusted = 0）---------- */
    ALTER TABLE tbl_order_header WITH CHECK
        ADD CONSTRAINT ck_order_header_pay_time
        CHECK (pay_time IS NULL OR pay_time >= order_time);
    PRINT N'【迁移04】已建立 ck_order_header_pay_time —— pay_time 不得早于 order_time。';

    ALTER TABLE tbl_order_header WITH CHECK
        ADD CONSTRAINT ck_order_header_finish_after_pay
        CHECK (finish_time IS NULL OR pay_time IS NULL OR finish_time >= pay_time);
    PRINT N'【迁移04】已建立 ck_order_header_finish_after_pay —— finish_time 不得早于 pay_time。';

    /* ---------- 4. 自证：两条约束都在、都未被禁用、都是可信的 ---------- */
    DECLARE @missing INT, @bad_state INT;

    SELECT @missing = 2 - COUNT(*)
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'tbl_order_header')
      AND name IN (N'ck_order_header_pay_time', N'ck_order_header_finish_after_pay');

    SELECT @bad_state = COUNT(*)
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'tbl_order_header')
      AND name IN (N'ck_order_header_pay_time', N'ck_order_header_finish_after_pay')
      AND (is_disabled = 1 OR is_not_trusted = 1);

    IF @missing <> 0 OR @bad_state <> 0
    BEGIN
        DECLARE @msg2 NVARCHAR(400) = FORMATMESSAGE(
            N'【迁移04】自证未通过（缺失 %d 条，状态异常 %d 条），事务回滚。', @missing, @bad_state);
        RAISERROR(@msg2, 16, 1);
    END

    PRINT N'【迁移04】自证通过：两条约束均已建立，未禁用且可信。';
    PRINT N'【迁移04】事务提交成功。';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT N'【迁移04】✗ 失败，已回滚：' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/* ---------- 5. 回显：订单头的全部 CHECK ---------- */
SELECT
    cc.name          AS 约束,
    cc.definition    AS 定义,
    cc.is_disabled   AS 已禁用,
    cc.is_not_trusted AS 未经校验
FROM sys.check_constraints AS cc
WHERE cc.parent_object_id = OBJECT_ID(N'tbl_order_header')
ORDER BY cc.name;
GO
