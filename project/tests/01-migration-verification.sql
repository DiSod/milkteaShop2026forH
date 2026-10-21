/* ============================================================
 * 测试脚本：01-migration-verification.sql
 * 用途：第 6 周模式迁移 (migration.sql) 优惠券正反例与完整性回归验证（支持非零退出码）
 * 依赖：00-bootstrap ~ 08-security + 11-migration
 * 阶段：第 6 周
 * 作者：hezhlin5 & DiSod
 * 日期：2026-10-21
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'============================================================';
PRINT N'【回归测试】开始执行第 6 周迁移约束与完整性验证 (01-migration-verification) ...';
PRINT N'============================================================';
GO

-- 准备测试会员 ID 与模板 ID
DECLARE @test_member_id INT;
SELECT TOP 1 @test_member_id = member_id FROM tbl_member ORDER BY member_id;

DECLARE @test_template_id INT;
SELECT TOP 1 @test_template_id = template_id FROM tbl_coupon_template WHERE template_code = 'TPL_CAMP_5';

-- 清理历史测试数据
DELETE FROM tbl_coupon WHERE coupon_code LIKE 'TEST-CPN-%';

DECLARE @pass_count INT = 0;
DECLARE @fail_count INT = 0;

/* ---------- 场景 1（正例 1）：未核销券 used_time IS NULL ---------- */
PRINT N'【测试用例 1】正例：插入未核销优惠券 (used_time IS NULL) ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-01', @test_member_id, @test_template_id,
        '2026-10-01 00:00:00', '2026-10-31 23:59:59', 'UNUSED', NULL
    );
    PRINT N'  --> ✅ 用例 1 通过：允许 used_time 为 NULL 的正常发券。';
    SET @pass_count = @pass_count + 1;
END TRY
BEGIN CATCH
    PRINT N'  --> ❌ 用例 1 失败：' + ERROR_MESSAGE();
    SET @fail_count = @fail_count + 1;
END CATCH;

/* ---------- 场景 2（正例 2）：合法核销 valid_from <= used_time <= valid_to ---------- */
PRINT N'【测试用例 2】正例：插入在有效期内核销的优惠券 ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-02', @test_member_id, @test_template_id,
        '2026-10-01 00:00:00', '2026-10-31 23:59:59', 'USED', '2026-10-15 14:30:00'
    );
    PRINT N'  --> ✅ 用例 2 通过：合法时间内核销券成功写入。';
    SET @pass_count = @pass_count + 1;
END TRY
BEGIN CATCH
    PRINT N'  --> ❌ 用例 2 失败：' + ERROR_MESSAGE();
    SET @fail_count = @fail_count + 1;
END CATCH;

/* ---------- 场景 3（负例 1）：过早核销 used_time < valid_from ---------- */
PRINT N'【测试用例 3】负例：尝试插入早于生效时间的非法核销券 (提前核销) ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-03', @test_member_id, @test_template_id,
        '2026-10-10 00:00:00', '2026-10-31 23:59:59', 'USED', '2026-10-09 23:59:59'
    );
    PRINT N'  --> ❌ 用例 3 失败：非法提前核销未被拦截！';
    SET @fail_count = @fail_count + 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE '%ck_coupon_used_time_range%'
    BEGIN
        PRINT N'  --> ✅ 用例 3 通过：已被 ck_coupon_used_time_range 成功拦截（拒绝提前核销）。';
        SET @pass_count = @pass_count + 1;
    END
    ELSE
    BEGIN
        PRINT N'  --> ❌ 用例 3 异常错误：' + ERROR_MESSAGE();
        SET @fail_count = @fail_count + 1;
    END
END CATCH;

/* ---------- 场景 4（负例 2）：过期核销 used_time > valid_to ---------- */
PRINT N'【测试用例 4】负例：尝试插入晚于失效时间的非法核销券 (过期核销) ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-04', @test_member_id, @test_template_id,
        '2026-10-01 00:00:00', '2026-10-10 23:59:59', 'USED', '2026-10-11 00:00:01'
    );
    PRINT N'  --> ❌ 用例 4 失败：非法过期核销未被拦截！';
    SET @fail_count = @fail_count + 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE '%ck_coupon_used_time_range%'
    BEGIN
        PRINT N'  --> ✅ 用例 4 通过：已被 ck_coupon_used_time_range 成功拦截（拒绝过期核销）。';
        SET @pass_count = @pass_count + 1;
    END
    ELSE
    BEGIN
        PRINT N'  --> ❌ 用例 4 异常错误：' + ERROR_MESSAGE();
        SET @fail_count = @fail_count + 1;
    END
END CATCH;

/* ---------- 场景 5（负例 3）：无效模板外键 template_id 拦截 ---------- */
PRINT N'【测试用例 5】负例：尝试插入不存在的 template_id ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-05', @test_member_id, 999999,
        '2026-10-01 00:00:00', '2026-10-31 23:59:59', 'UNUSED', NULL
    );
    PRINT N'  --> ❌ 用例 5 失败：无效模板外键未被拦截！';
    SET @fail_count = @fail_count + 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE '%fk_coupon_template%'
    BEGIN
        PRINT N'  --> ✅ 用例 5 通过：已被 fk_coupon_template 成功拦截。';
        SET @pass_count = @pass_count + 1;
    END
    ELSE
    BEGIN
        PRINT N'  --> ❌ 用例 5 异常错误：' + ERROR_MESSAGE();
        SET @fail_count = @fail_count + 1;
    END
END CATCH;

-- 清理测试数据
DELETE FROM tbl_coupon WHERE coupon_code LIKE 'TEST-CPN-%';

PRINT N'============================================================';
PRINT FORMATMESSAGE(N'【测试汇总】通过用例数: %d / 失败用例数: %d', @pass_count, @fail_count);
IF @fail_count = 0
BEGIN
    PRINT N'【回归测试结论】🎉 全部用例通过！迁移约束与业务规则完美闭环。';
END
ELSE
BEGIN
    PRINT N'【回归测试结论】⚠️ 存在失败用例，触发非零退出码！';
    THROW 51000, N'【回归测试失败】测试未完全通过！', 1;
END;
PRINT N'============================================================';
GO
