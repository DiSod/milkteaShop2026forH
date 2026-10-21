/* ============================================================
 * 脚本：regression.sql
 * 用途：全库自动化回归测试入口（支持 CI/CD 自动化判定与非零退出码）
 * 依赖：00-bootstrap ~ 11-migration
 * 阶段：第 6 周
 * 作者：hezhlin5 & DiSod
 * 日期：2026-10-21
 *
 * 【执行方式与退出码机制】
 *   必须带 -b 参数运行：
 *     cd project\\tests
 *     sqlcmd -S .\\SQLEXPRESS -E -C -d milktea_shop -f 65001 -b -i regression.sql
 *
 *   若所有断言通过：退出码 0，打印成功摘要；
 *   若任意断言失败：抛出 THROW 51000，sqlcmd -b 捕获后立即返回非零退出码（Non-zero Exit Code），机器可判定！
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'============================================================';
PRINT N'【回归测试】启动第 6 周规范化拆分与全库核心业务自动化回归验证 ...';
PRINT N'============================================================';
GO

DECLARE @pass_count INT = 0;
DECLARE @fail_count INT = 0;
DECLARE @total_tests INT = 12;

-- 测试辅助变量
DECLARE @test_member_id INT;
SELECT TOP 1 @test_member_id = member_id FROM tbl_member ORDER BY member_id;

DECLARE @test_template_id INT;
SELECT TOP 1 @test_template_id = template_id FROM tbl_coupon_template WHERE template_code = 'TPL_CAMP_5';

-- 清理测试残留
DELETE FROM tbl_coupon WHERE coupon_code LIKE 'REG-CPN-%';

/* ------------------------------------------------------------
 * 断言 1：全库表数判定（应从 17 表扩充为 18 表）
 * ------------------------------------------------------------ */
PRINT N'[TC-01] 校验数据库总表数是否为 18 表（含新拆分 tbl_coupon_template）...';
DECLARE @tbl_cnt INT;
SELECT @tbl_cnt = COUNT(*) FROM sys.tables;
IF @tbl_cnt = 18
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 全库业务表数为 18 张。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 表数不符！期望 18，实际: %d', @tbl_cnt);
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 断言 2：模板表存在性与行数校验
 * ------------------------------------------------------------ */
PRINT N'[TC-02] 校验 tbl_coupon_template 是否包含 2 个去重券模板 ...';
DECLARE @tpl_cnt INT;
SELECT @tpl_cnt = COUNT(*) FROM tbl_coupon_template WHERE template_code IN ('TPL_CAMP_5', 'TPL_POINTS_5');
IF @tpl_cnt = 2
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 券模板表包含 2 个标准去重模板。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 券模板数不符！期望 2，实际: %d', @tpl_cnt);
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 断言 3：优惠券实例总数与孤儿数据校验
 * ------------------------------------------------------------ */
PRINT N'[TC-03] 校验 tbl_coupon 实例总数是否为 24 且无孤儿券记录 ...';
DECLARE @cpn_cnt INT, @cpn_orphan INT;
SELECT @cpn_cnt = COUNT(*), @cpn_orphan = SUM(CASE WHEN template_id IS NULL THEN 1 ELSE 0 END) FROM tbl_coupon;
IF @cpn_cnt = 24 AND @cpn_orphan = 0
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 优惠券实例总数 24，孤儿券记录数 0。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 券数据不符！总数: %d, 孤儿数: %d', @cpn_cnt, @cpn_orphan);
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 断言 4：兼容视图可用性与投影字段校验
 * ------------------------------------------------------------ */
PRINT N'[TC-04] 校验向后兼容视图 vw_coupon_legacy 可用性 ...';
DECLARE @vw_cnt INT, @vw_nulls INT;
SELECT @vw_cnt = COUNT(*), 
       @vw_nulls = SUM(CASE WHEN coupon_name IS NULL OR discount_amount IS NULL OR min_order_amount IS NULL THEN 1 ELSE 0 END)
FROM vw_coupon_legacy;

IF @vw_cnt = 24 AND @vw_nulls = 0
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 兼容视图返回 24 行且模板字段 100%% 完整投影。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 兼容视图异常！行数: %d, 空字段数: %d', @vw_cnt, @vw_nulls);
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 断言 5：约束负例 1 —— 提前核销拦截
 * ------------------------------------------------------------ */
PRINT N'[TC-05] 负例：试图核销早于 valid_from 的券 (应当被 ck_coupon_used_time_range 拦截) ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'REG-CPN-01', @test_member_id, @test_template_id,
        '2026-10-10 00:00:00', '2026-10-31 23:59:59', 'USED', '2026-10-09 23:59:59'
    );
    PRINT N'  --> ❌ [FAIL] 非法提前核销未被拦截！';
    SET @fail_count = @fail_count + 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE '%ck_coupon_used_time_range%'
    BEGIN
        PRINT N'  --> ✅ [PASS] 成功拦截提前核销 (ck_coupon_used_time_range)。';
        SET @pass_count = @pass_count + 1;
    END
    ELSE
    BEGIN
        PRINT N'  --> ❌ [FAIL] 拦截异常：' + ERROR_MESSAGE();
        SET @fail_count = @fail_count + 1;
    END;
END CATCH;

/* ------------------------------------------------------------
 * 断言 6：约束负例 2 —— 过期核销拦截
 * ------------------------------------------------------------ */
PRINT N'[TC-06] 负例：试图核销晚于 valid_to 的券 (应当被 ck_coupon_used_time_range 拦截) ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'REG-CPN-02', @test_member_id, @test_template_id,
        '2026-10-01 00:00:00', '2026-10-10 23:59:59', 'USED', '2026-10-11 00:00:01'
    );
    PRINT N'  --> ❌ [FAIL] 非法过期核销未被拦截！';
    SET @fail_count = @fail_count + 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE '%ck_coupon_used_time_range%'
    BEGIN
        PRINT N'  --> ✅ [PASS] 成功拦截过期核销 (ck_coupon_used_time_range)。';
        SET @pass_count = @pass_count + 1;
    END
    ELSE
    BEGIN
        PRINT N'  --> ❌ [FAIL] 拦截异常：' + ERROR_MESSAGE();
        SET @fail_count = @fail_count + 1;
    END;
END CATCH;

/* ------------------------------------------------------------
 * 断言 7：外键负例 —— 不存在模板 ID 拦截
 * ------------------------------------------------------------ */
PRINT N'[TC-07] 负例：试图插入不存在的 template_id (应当被 fk_coupon_template 拦截) ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'REG-CPN-03', @test_member_id, 999999,
        '2026-10-01 00:00:00', '2026-10-31 23:59:59', 'UNUSED', NULL
    );
    PRINT N'  --> ❌ [FAIL] 悬空外键未被拦截！';
    SET @fail_count = @fail_count + 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE '%fk_coupon_template%'
    BEGIN
        PRINT N'  --> ✅ [PASS] 成功拦截悬空模板外键 (fk_coupon_template)。';
        SET @pass_count = @pass_count + 1;
    END
    ELSE
    BEGIN
        PRINT N'  --> ❌ [FAIL] 拦截异常：' + ERROR_MESSAGE();
        SET @fail_count = @fail_count + 1;
    END;
END CATCH;

/* ------------------------------------------------------------
 * 断言 8：正例 1 —— 未核销合法入库
 * ------------------------------------------------------------ */
PRINT N'[TC-08] 正例：插入未核销券 (used_time IS NULL) ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'REG-CPN-04', @test_member_id, @test_template_id,
        '2026-10-01 00:00:00', '2026-10-31 23:59:59', 'UNUSED', NULL
    );
    PRINT N'  --> ✅ [PASS] 合法未核销券成功入库。';
    SET @pass_count = @pass_count + 1;
END TRY
BEGIN CATCH
    PRINT N'  --> ❌ [FAIL] 正常发券失败：' + ERROR_MESSAGE();
    SET @fail_count = @fail_count + 1;
END CATCH;

/* ------------------------------------------------------------
 * 断言 9：正例 2 —— 有效区间内核销入库
 * ------------------------------------------------------------ */
PRINT N'[TC-09] 正例：插入有效区间内核销券 ...';
BEGIN TRY
    INSERT INTO tbl_coupon (
        coupon_code, member_id, template_id, valid_from, valid_to, status, used_time
    ) VALUES (
        'REG-CPN-05', @test_member_id, @test_template_id,
        '2026-10-01 00:00:00', '2026-10-31 23:59:59', 'USED', '2026-10-15 12:00:00'
    );
    PRINT N'  --> ✅ [PASS] 合法区间内核销券成功入库。';
    SET @pass_count = @pass_count + 1;
END TRY
BEGIN CATCH
    PRINT N'  --> ❌ [FAIL] 合法核销失败：' + ERROR_MESSAGE();
    SET @fail_count = @fail_count + 1;
END CATCH;

-- 清理测试数据
DELETE FROM tbl_coupon WHERE coupon_code LIKE 'REG-CPN-%';

/* ------------------------------------------------------------
 * 断言 10：基线 S2 已收款销售额 D 口径校验（23,762.00 / 1,926 单）
 * ------------------------------------------------------------ */
PRINT N'[TC-10] 基线断言：已收款销售额 D 口径校验 (pay_status = ''SUCCESS'') ...';
DECLARE @sales_orders INT, @sales_amt DECIMAL(12,2);
SELECT 
    @sales_orders = COUNT(*),
    @sales_amt = SUM(amount_paid)
FROM tbl_order_header
WHERE pay_status = 'SUCCESS';

IF @sales_orders = 1926 AND @sales_amt = 23762.00
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 销售额 D 口径精确匹配：订单数 1,926，实收 23,762.00。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 销售额 D 口径偏差！实际订单数: %d, 金额: %s', @sales_orders, CAST(@sales_amt AS VARCHAR(20)));
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 断言 11：基线 S1 抽样 34 单 59 明细计算不变量偏差为 0
 * ------------------------------------------------------------ */
PRINT N'[TC-11] 基线断言：订单明细复算恒等式偏差校验 ...';
DECLARE @bad_diff_count INT = 0;
WITH SampleOrders AS (
    SELECT order_id FROM tbl_order_header WHERE coupon_id IS NOT NULL
    UNION
    SELECT TOP 4 order_id FROM (SELECT order_id, COUNT(*) cnt FROM tbl_order_detail GROUP BY order_id HAVING COUNT(*) > 1) d
    UNION
    SELECT TOP 4 order_id FROM tbl_order_detail WHERE order_detail_id IN (SELECT order_detail_id FROM tbl_order_detail_topping)
    UNION
    SELECT TOP 4 order_id FROM tbl_order_header WHERE member_id IS NULL
),
CalculatedDetails AS (
    SELECT 
        d.order_detail_id,
        d.subtotal,
        (d.qty * d.unit_price) + ISNULL(SUM(t.qty * t.unit_extra_price), 0) AS calc_subtotal
    FROM tbl_order_detail d
    INNER JOIN SampleOrders s ON d.order_id = s.order_id
    LEFT JOIN tbl_order_detail_topping t ON d.order_detail_id = t.order_detail_id
    GROUP BY d.order_detail_id, d.subtotal, d.qty, d.unit_price
)
SELECT @bad_diff_count = COUNT(*)
FROM CalculatedDetails
WHERE subtotal <> calc_subtotal;

IF @bad_diff_count = 0
BEGIN
    PRINT N'  --> ✅ [PASS] 抽样订单明细复算恒等式 100% 成立，偏差行数 0。';
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 发现 %d 行明细小计与加料复算存在偏差！', @bad_diff_count);
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 断言 12：基线 S3 原料库存基表行数与负库存硬性断言
 * ------------------------------------------------------------ */
PRINT N'[TC-12] 基线断言：原料库存基表完整性与无负库存校验 ...';
DECLARE @ing_cnt INT, @neg_stock_cnt INT, @unit_cnt INT;
SELECT 
    @ing_cnt = COUNT(*),
    @neg_stock_cnt = SUM(CASE WHEN qty_on_hand < 0 THEN 1 ELSE 0 END),
    @unit_cnt = COUNT(DISTINCT unit)
FROM tbl_ingredient;

IF @ing_cnt = 60 AND @neg_stock_cnt = 0 AND @unit_cnt = 5
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 原料表完整（60 行，5 种单位，0 负库存）。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 原料库存异常！行数: %d, 负库存: %d, 单位数: %d', @ing_cnt, @neg_stock_cnt, @unit_cnt);
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 汇总评定与非零退出码机制
 * ------------------------------------------------------------ */
PRINT N'============================================================';
PRINT FORMATMESSAGE(N'【回归测试总览】总用例数: %d | 通过数: %d | 失败数: %d', @total_tests, @pass_count, @fail_count);
PRINT N'============================================================';

IF @fail_count > 0
BEGIN
    PRINT N'【回归测试失败】存在未通过的硬性断言，正在触发非零退出码阻断流水线！';
    THROW 51000, N'【回归测试失败】测试断言未全量通过，请查看控制台日志排查！', 1;
END
ELSE
BEGIN
    PRINT N'【回归测试结论】🎉 12 项自动化断言全绿通过！模式演进、数据完整性与基线语义 100% 保持！';
END;
GO
