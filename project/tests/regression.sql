/* ============================================================
 * 脚本：regression.sql
 * 用途：全库自动化回归测试入口（支持 CI/CD 自动化判定与非零退出码）
 * 依赖：00-bootstrap ~ 11-migration
 * 阶段：第 6 周（第 7 周追加 TC-13、TC-14）
 * 作者：hezhlin5 & DiSod
 * 日期：2026-10-21
 * 追加：2026-11-04 DiSod —— 新增 TC-13 积分台账对账，配合 migration-03 的期初流水
 * 追加：2026-11-04 hezhlin5 —— 新增 TC-14 登录凭据质量校验，配合 migration-02 与 ISSUE-014 裁定
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
DECLARE @total_tests INT = 15;

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
PRINT N'[TC-03] 校验种子区间 tbl_coupon 实例数是否为 24 且无孤儿券记录 ...';
-- 口径：只锁 v0.1 种子区间（valid_from < 2026-10-01）的 24 张券。
-- 第 9 周 migration-07 默认发放的 CPDEF 券属于运行期数据，单独统计、不参与断言。
DECLARE @cpn_cnt INT, @cpn_orphan INT, @cpn_all INT;
SELECT @cpn_cnt = COUNT(*), @cpn_orphan = SUM(CASE WHEN template_id IS NULL THEN 1 ELSE 0 END)
FROM tbl_coupon WHERE valid_from < '2026-10-01';
SELECT @cpn_all = COUNT(*) FROM tbl_coupon;
IF @cpn_cnt = 24 AND @cpn_orphan = 0
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 种子券 24 张、孤儿券 0；全库现有 %d 张（第 9 周默认发放的可用券不计入断言）。', @cpn_all);
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
FROM vw_coupon_legacy WHERE valid_from < '2026-10-01';

IF @vw_cnt = 24 AND @vw_nulls = 0
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 兼容视图按种子口径返回 24 行且模板字段 100%% 完整投影。');
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
 *
 * 口径说明（2026-11-08 修订）：只统计 business_date < '2026-10-01' 的订单，
 * 那一段才是 v0.1 种子数据集（种子数据只到 2026-09-23）。应用上线后顾客会
 * 真的下单，若把断言写死在「全库」，正常点一杯就会让回归变红 —— 实测
 * 2026-11-08 的两张演示单就把数字抬到 1,928 单 / 23,770.00 元。
 * 运行期新增的订单只打印、不参与断言：这条用例要守的是「种子数据有没有被
 * 改坏」，不是「业务数据不许增长」。
 * ------------------------------------------------------------ */
DECLARE @baseline_cutoff DATE = '2026-10-01';
PRINT N'[TC-10] 基线断言：已收款销售额 D 口径校验 (pay_status = ''SUCCESS'' 且 order_status <> ''CANCELLED'' 且 business_date < 2026-10-01) ...';
DECLARE @sales_orders INT, @sales_amt DECIMAL(12,2);
SELECT
    @sales_orders = COUNT(*),
    @sales_amt = ISNULL(SUM(amount_paid), 0)
FROM tbl_order_header
WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
  AND business_date < @baseline_cutoff;

DECLARE @live_orders INT, @live_amt DECIMAL(12,2);
SELECT
    @live_orders = COUNT(*),
    @live_amt = ISNULL(SUM(amount_paid), 0)
FROM tbl_order_header
WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED'
  AND business_date >= @baseline_cutoff;

PRINT FORMATMESSAGE(N'      种子口径 %d 单 / %s 元；运行期新增（不参与断言）%d 单 / %s 元',
    @sales_orders, CAST(@sales_amt AS VARCHAR(20)),
    @live_orders, CAST(@live_amt AS VARCHAR(20)));

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
 * 断言 13：积分台账对账（迁移 03）
 *   每个会员都必须满足 points_balance = Σ point_change。
 *   背景：第 7 周审计发现 80/80 会员对不上、缺口合计 10,823 分，
 *         原因是造数脚本把期初积分直接写进余额列而没有生成流水。
 *         迁移 03 补了 OPENING 类型与 80 条期初流水，这里把它固化成
 *         止损线 —— 以后谁再往余额列里凭空加数，这条断言立刻失败。
 * ------------------------------------------------------------ */
PRINT N'[TC-13] 积分台账对账：points_balance = Σ point_change ...';
DECLARE @pts_mismatch INT, @pts_opening_cnt INT;

SELECT @pts_mismatch = COUNT(*)
FROM tbl_member AS m
LEFT JOIN (
    SELECT member_id, SUM(point_change) AS flow_total
    FROM tbl_points_ledger
    GROUP BY member_id
) AS l ON l.member_id = m.member_id
WHERE m.points_balance <> ISNULL(l.flow_total, 0);

SELECT @pts_opening_cnt = COUNT(*)
FROM tbl_points_ledger
WHERE point_type = N'OPENING';

IF @pts_mismatch = 0 AND @pts_opening_cnt = 80
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 积分台账自洽（80 位会员余额 = 流水合计，期初流水 80 条）。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 积分台账不自洽！不符会员 %d 位，期初流水 %d 条。', @pts_mismatch, @pts_opening_cnt);
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 断言 14：登录凭据质量校验（迁移 02 与 ISSUE-014 裁定）
 *   验证 80 位会员与 5 位员工初始登录凭据覆盖度与 64 位大写十六进制 SHA-256 格式。
 *   任何格式不符或基准数据凭据缺失都将阻断流水线。
 * ------------------------------------------------------------ */
PRINT N'[TC-14] 登录凭据质量校验：80 会员 + 5 员工 64 位 SHA-256 散列有效性 ...';
DECLARE @member_cred_cnt INT, @member_bad_hash INT;
DECLARE @emp_cred_cnt INT, @emp_bad_hash INT;

SELECT 
    @member_cred_cnt = COUNT(password_hash),
    @member_bad_hash = SUM(CASE 
        WHEN password_hash IS NOT NULL 
             AND (LEN(password_hash) <> 64 OR password_hash COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9A-F]%') 
        THEN 1 ELSE 0 END)
FROM tbl_member;

SELECT 
    @emp_cred_cnt = COUNT(password_hash),
    @emp_bad_hash = SUM(CASE 
        WHEN password_hash IS NOT NULL 
             AND (LEN(password_hash) <> 64 OR password_hash COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9A-F]%') 
        THEN 1 ELSE 0 END)
FROM tbl_employee;

IF @member_cred_cnt = 80 AND @member_bad_hash = 0 AND @emp_cred_cnt = 5 AND @emp_bad_hash = 0
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 登录凭据质量达标（会员 80/80、员工 5/5，无非法哈希格式）。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 登录凭据异常！会员凭据: %d (非法: %d), 员工凭据: %d (非法: %d)',
        @member_cred_cnt, ISNULL(@member_bad_hash, 0), @emp_cred_cnt, ISNULL(@emp_bad_hash, 0));
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 断言 15：角色授权与越权防护（第 9 周追加，对应课程要求的「权限」检查）
 *   1) 四个业务角色都在，且授权条数与覆盖对象数固定 —— 结构冻结后不应漂移；
 *   2) 没有任何架构级（class=3）授权 —— role_manager 已从 SCHEMA::dbo 全权
 *      改为 22 条逐对象授权，若有人重新用 GRANT ... ON SCHEMA::dbo，这里会失败；
 *   3) 三组关键越权必须「无权限」：制作员读会员、收银员改商品、收银员读原料。
 *      用 HAS_PERMS_BY_NAME 在 EXECUTE AS 下判定，比"真跑一条被拒的语句"更稳定
 *      （不依赖错误号，也不会污染日志）。
 * ------------------------------------------------------------ */
PRINT N'[TC-15] 角色授权与越权防护：四角色授权条数 / 架构级授权 0 / 关键越权必须被拒 ...';

DECLARE @perm_mgr INT, @obj_mgr INT, @perm_cash INT, @obj_cash INT;
DECLARE @perm_stock INT, @obj_stock INT, @perm_maker INT, @obj_maker INT;
DECLARE @schema_grants INT;
DECLARE @deny_maker_member INT, @deny_cashier_product INT, @deny_cashier_ingredient INT;
DECLARE @deny_stocker_order INT, @allow_manager_product INT;

SELECT @perm_mgr = COUNT(*), @obj_mgr = COUNT(DISTINCT p.major_id)
FROM sys.database_permissions p
JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
WHERE r.name = N'role_manager' AND p.state IN (N'G', N'W');

SELECT @perm_cash = COUNT(*), @obj_cash = COUNT(DISTINCT p.major_id)
FROM sys.database_permissions p
JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
WHERE r.name = N'role_cashier' AND p.state IN (N'G', N'W');

SELECT @perm_stock = COUNT(*), @obj_stock = COUNT(DISTINCT p.major_id)
FROM sys.database_permissions p
JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
WHERE r.name = N'role_stocker' AND p.state IN (N'G', N'W');

SELECT @perm_maker = COUNT(*), @obj_maker = COUNT(DISTINCT p.major_id)
FROM sys.database_permissions p
JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
WHERE r.name = N'role_maker' AND p.state IN (N'G', N'W');

SELECT @schema_grants = COUNT(*) FROM sys.database_permissions WHERE class = 3;

EXECUTE AS USER = N'usr_test_maker';
SELECT @deny_maker_member = HAS_PERMS_BY_NAME(N'tbl_member', N'OBJECT', N'SELECT');
REVERT;

EXECUTE AS USER = N'usr_test_cashier';
SELECT @deny_cashier_product = HAS_PERMS_BY_NAME(N'tbl_product', N'OBJECT', N'UPDATE'),
       @deny_cashier_ingredient = HAS_PERMS_BY_NAME(N'tbl_ingredient', N'OBJECT', N'SELECT');
REVERT;

EXECUTE AS USER = N'usr_test_stocker';
SELECT @deny_stocker_order = HAS_PERMS_BY_NAME(N'tbl_order_header', N'OBJECT', N'SELECT');
REVERT;

EXECUTE AS USER = N'usr_test_manager';
SELECT @allow_manager_product = HAS_PERMS_BY_NAME(N'tbl_product', N'OBJECT', N'UPDATE');
REVERT;

IF @perm_mgr = 78 AND @obj_mgr = 24
   AND @perm_cash = 20 AND @obj_cash = 13
   AND @perm_stock = 10 AND @obj_stock = 6
   AND @perm_maker = 9 AND @obj_maker = 8
   AND @schema_grants = 0
   AND ISNULL(@deny_maker_member, 1) = 0
   AND ISNULL(@deny_cashier_product, 1) = 0
   AND ISNULL(@deny_cashier_ingredient, 1) = 0
   AND ISNULL(@deny_stocker_order, 1) = 0
   AND ISNULL(@allow_manager_product, 0) = 1
BEGIN
    PRINT FORMATMESSAGE(N'  --> ✅ [PASS] 权限边界符合设计（店长 78/24、收银 20/13、库管 10/6、制作 9/8；架构级授权 0；4 组越权均被拒、店长改商品为允许）。');
    SET @pass_count = @pass_count + 1;
END
ELSE
BEGIN
    PRINT FORMATMESSAGE(N'  --> ❌ [FAIL] 权限边界异常！店长 %d/%d、收银 %d/%d、库管 %d/%d、制作 %d/%d；架构级 %d；越权检查(制作读会员 %d, 收银改商品 %d, 收银读原料 %d, 库管读订单 %d, 店长改商品 %d)',
        @perm_mgr, @obj_mgr, @perm_cash, @obj_cash, @perm_stock, @obj_stock, @perm_maker, @obj_maker,
        @schema_grants, ISNULL(@deny_maker_member, -1), ISNULL(@deny_cashier_product, -1),
        ISNULL(@deny_cashier_ingredient, -1), ISNULL(@deny_stocker_order, -1), ISNULL(@allow_manager_product, -1));
    SET @fail_count = @fail_count + 1;
END;

/* ------------------------------------------------------------
 * 汇总评定与非零退出码机制
 * ------------------------------------------------------------ */
PRINT N'============================================================';
PRINT FORMATMESSAGE(N'【回归测试总览】总用例数: %d | 通过数: %d | 失败数: %d', @total_tests, @pass_count, @fail_count);
PRINT N'============================================================';

IF @fail_count > 0 OR @pass_count <> @total_tests
BEGIN
    PRINT N'【回归测试失败】存在未通过的硬性断言，正在触发非零退出码阻断流水线！';
    THROW 51000, N'【回归测试失败】测试断言未全量通过，请查看控制台日志排查！', 1;
END
ELSE
BEGIN
    PRINT N'【回归测试结论】🎉 15 项自动化断言全绿通过！模式演进、数据完整性与基线语义 100% 保持！';
END;
GO
