/* ============================================================
 * 测试脚本：01-migration-verification.sql
 * 用途：第 6 周模式迁移 (migration.sql) 正反例与完整性回归验证
 * 依赖：00-bootstrap ~ 08-security + 11-migration
 * 阶段：第 6 周
 * 作者：hezhlin5
 * 日期：2026-10-14
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'============================================================';
PRINT N'【回归测试】开始执行第 6 周迁移约束与完整性验证 ...';
PRINT N'============================================================';
GO

-- 准备测试会员 ID（取现有第 1 个会员）
DECLARE @test_member_id INT;
SELECT TOP 1 @test_member_id = member_id FROM tbl_member ORDER BY member_id;

-- 清理历史测试数据
DELETE FROM tbl_coupon WHERE coupon_code LIKE 'TEST-CPN-%';

DECLARE @pass_count INT = 0;
DECLARE @fail_count INT = 0;

/* ---------- 场景 1（正例 1）：未核销券 used_time IS NULL ---------- */
PRINT N'【测试用例 1】正例：插入未核销优惠券 (used_time IS NULL) ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, coupon_name, source,
        discount_amount, min_order_amount, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-01', @test_member_id, N'测试满减券A', 'CAMPAIGN',
        5.00, 20.00, '2026-10-01 00:00:00', '2026-10-31 23:59:59', 'UNUSED', NULL
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
        coupon_code, member_id, coupon_name, source,
        discount_amount, min_order_amount, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-02', @test_member_id, N'测试满减券B', 'CAMPAIGN',
        5.00, 20.00, '2026-10-01 00:00:00', '2026-10-31 23:59:59', 'USED', '2026-10-15 14:30:00'
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
        coupon_code, member_id, coupon_name, source,
        discount_amount, min_order_amount, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-03', @test_member_id, N'测试非法提前券', 'CAMPAIGN',
        5.00, 20.00, '2026-10-10 00:00:00', '2026-10-31 23:59:59', 'USED', '2026-10-09 23:59:59'
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
        coupon_code, member_id, coupon_name, source,
        discount_amount, min_order_amount, valid_from, valid_to, status, used_time
    ) VALUES (
        'TEST-CPN-04', @test_member_id, N'测试非法过期券', 'CAMPAIGN',
        5.00, 20.00, '2026-10-01 00:00:00', '2026-10-10 23:59:59', 'USED', '2026-10-11 00:00:01'
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

-- 清理测试数据
DELETE FROM tbl_coupon WHERE coupon_code LIKE 'TEST-CPN-%';

PRINT N'============================================================';
PRINT FORMATMESSAGE(N'【测试汇总】通过用例数: %d / 失败用例数: %d', @pass_count, @fail_count);
IF @fail_count = 0
    PRINT N'【回归测试结论】🎉 全部用例通过！迁移约束与业务规则完美闭环。';
ELSE
    PRINT N'【回归测试结论】⚠️ 存在失败用例，请排查！';
PRINT N'============================================================';
GO
