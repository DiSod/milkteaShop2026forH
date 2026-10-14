/* ============================================================
 * 脚本：migration.sql
 * 用途：第 6 周（ch7 规范化与模式重构）迁移脚本
 * 依赖：02-constraints/constraints.sql, 04-seed/seed_data.sql
 * 阶段：第 6 周
 * 作者：hezhlin5 & DiSod
 * 日期：2026-10-14
 * 幂等：是 —— 基于 sys.objects / sys.check_constraints 探测与事务回滚保护
 * ============================================================
 *
 * 【背景与迁移目标】
 *   承接 project/docs/v0.1-issues.md §1.1 问题 1 与 project/docs/normalization.md：
 *   1. 【约束补强】添加 ck_coupon_used_time_range 检查约束：
 *      保证核销时间 used_time 必须落在 [valid_from, valid_to] 有效期内；
 *   2. 【完整性加固】确保迁移前后历史业务数据 100% 保持、语义零丢失。
 *
 * 【执行方式】
 *   方式一（独立迁移演练）：
 *     sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i project/sql/11-migration/migration.sql
 *   方式二（全库一键重建集成）：
 *     由 project/sql/99-rebuild.sql 统一按序调用
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'【迁移】开始执行第 6 周模式演进与规范化重构 (ch7) ...';
GO

BEGIN TRANSACTION;

BEGIN TRY
    -- 1. 验证目标表是否存在
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'tbl_coupon')
    BEGIN
        RAISERROR(N'【迁移错误】未检测到 tbl_coupon 表，请先确认基础模式已初始化！', 16, 1);
    END;

    -- 2. 幂等处理：若已存在同名约束，先安全移除
    IF EXISTS (
        SELECT 1 
        FROM sys.check_constraints 
        WHERE name = N'ck_coupon_used_time_range' 
          AND parent_object_id = OBJECT_ID(N'tbl_coupon')
    )
    BEGIN
        PRINT N'【迁移】检测到既有约束 ck_coupon_used_time_range，执行幂等清理 ...';
        ALTER TABLE tbl_coupon DROP CONSTRAINT ck_coupon_used_time_range;
    END;

    -- 3. 历史数据兼容性与完整性探测
    DECLARE @violation_count INT = 0;
    SELECT @violation_count = COUNT(*)
    FROM tbl_coupon
    WHERE used_time IS NOT NULL 
      AND (used_time < valid_from OR used_time > valid_to);

    IF @violation_count > 0
    BEGIN
        DECLARE @err_msg NVARCHAR(200) = 
            FORMATMESSAGE(N'【迁移阻断】发现 %d 行历史优惠券核销时间超出有效区间，无法直接下沉硬约束！', @violation_count);
        RAISERROR(@err_msg, 16, 1);
    END;

    -- 4. 实施 DDL 约束补强：核销时间区间检查
    PRINT N'【迁移】正在添加券核销有效区间检查约束 ck_coupon_used_time_range ...';
    ALTER TABLE tbl_coupon WITH CHECK
        ADD CONSTRAINT ck_coupon_used_time_range
            CHECK (used_time IS NULL OR (used_time >= valid_from AND used_time <= valid_to));

    COMMIT TRANSACTION;
    PRINT N'【迁移】事务提交成功，第 6 周模式迁移顺利完成！';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState INT = ERROR_STATE();

    PRINT N'【迁移失败】事务已安全回滚：' + @ErrorMessage;
    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH;
GO

/* ============================================================
 * 迁移后状态回显与验证
 * ============================================================ */
PRINT N'【迁移验证】检查新约束当前生效状态：';
GO

SELECT 
    cc.name                                AS [约束名称],
    OBJECT_NAME(cc.parent_object_id)       AS [所属表名],
    cc.definition                          AS [约束表达式],
    cc.is_disabled                         AS [是否禁用],
    cc.is_not_trusted                      AS [是否未经验证]
FROM sys.check_constraints cc
WHERE cc.name = N'ck_coupon_used_time_range';
GO
