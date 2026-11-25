/* ============================================================
 * 脚本：test-trigger.sql
 * 用途：第 11 周触发器正反例自动化验证（18 条断言，测后零漂移）
 * 依赖：09-programmability/trigger.sql
 * 阶段：第 11 周（触发器）
 * 作者：何争霖 (hezhlin5)
 * 日期：2026-11-25
 * 幂等：是（测前清理残留，测后完整还原）
 * ============================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

USE milktea_shop;
GO

PRINT N'============================================================';
PRINT N'【触发器测试】启动第 11 周 4 个触发器正反例验证（18 项断言）...';
PRINT N'============================================================';

DECLARE @pass INT = 0, @fail INT = 0, @expected_total INT = 18;
DECLARE @err INT = 0;

/* 准备测试所需基准主键 */
DECLARE @ing_id INT, @member_id INT, @prod_id INT;
DECLARE @cup_id INT, @sugar_id INT, @ice_id INT;
DECLARE @seed_sl_id INT, @seed_pl_id INT;

SELECT TOP 1 @ing_id = ingredient_id FROM dbo.tbl_ingredient ORDER BY ingredient_id;
SELECT TOP 1 @member_id = member_id FROM dbo.tbl_member ORDER BY member_id;
SELECT TOP 1 @prod_id = product_id FROM dbo.tbl_product WHERE product_status = 'ON_SALE' ORDER BY product_id;
SELECT TOP 1 @cup_id = spec_option_id FROM dbo.tbl_spec_option WHERE spec_type = 'CUP' ORDER BY spec_option_id;
SELECT TOP 1 @sugar_id = spec_option_id FROM dbo.tbl_spec_option WHERE spec_type = 'SUGAR' ORDER BY spec_option_id;
SELECT TOP 1 @ice_id = spec_option_id FROM dbo.tbl_spec_option WHERE spec_type = 'ICE' ORDER BY spec_option_id;
SELECT TOP 1 @seed_sl_id = ledger_id FROM dbo.tbl_stock_ledger WHERE ledger_time < DATEADD(DAY, -1, SYSDATETIME()) ORDER BY ledger_id;
SELECT TOP 1 @seed_pl_id = point_ledger_id FROM dbo.tbl_points_ledger WHERE change_time < DATEADD(DAY, -1, SYSDATETIME()) ORDER BY point_ledger_id;

/* 清理可能遗留的测试行（最近 24h 内测试记录允许 dbo 删除） */
DELETE FROM dbo.tbl_order_detail
WHERE order_id IN (SELECT order_id FROM dbo.tbl_order_header WHERE order_no LIKE N'TRG-TEST-%');
DELETE FROM dbo.tbl_order_header WHERE order_no LIKE N'TRG-TEST-%';
DELETE FROM dbo.tbl_stock_ledger WHERE remark = N'TRG-TEST-SL';

/* ============================================================
 * 一、trg_stock_ledger_immutable（T01 ~ T04）
 * ============================================================ */
INSERT INTO dbo.tbl_stock_ledger (ingredient_id, ledger_type, qty, ref_type, operator_id, remark)
VALUES (@ing_id, 'PURCHASE_IN', 1.000, 'MANUAL', 1, N'TRG-TEST-SL');
DECLARE @fresh_sl_id INT = SCOPE_IDENTITY();

-- T01: 禁止 UPDATE 库存流水（51501）
SET @err = 0;
BEGIN TRY
    UPDATE dbo.tbl_stock_ledger SET qty = 2.000 WHERE ledger_id = @fresh_sl_id;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51501 BEGIN PRINT N'  ✅ 【PASS】T01 库存流水 UPDATE 被拦截 (51501)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T01 期望 51501，实际 %d', @err); SET @fail += 1; END;

-- T02: 禁止 dbo 删除超过 24 小时的历史库存流水（51502）
SET @err = 0;
BEGIN TRY
    DELETE FROM dbo.tbl_stock_ledger WHERE ledger_id = @seed_sl_id;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51502 BEGIN PRINT N'  ✅ 【PASS】T02 历史库存流水 DELETE 被拦截 (51502)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T02 期望 51502，实际 %d', @err); SET @fail += 1; END;

-- T03: 禁止非 dbo（usr_test_manager）删除当天新流水（51502）
SET @err = 0;
BEGIN TRY
    EXECUTE AS USER = N'usr_test_manager';
    DELETE FROM dbo.tbl_stock_ledger WHERE ledger_id = @fresh_sl_id;
    REVERT;
END TRY
BEGIN CATCH
    WHILE USER_NAME() LIKE N'usr_test[_]%' REVERT;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51502 BEGIN PRINT N'  ✅ 【PASS】T03 非 dbo 删除库存流水被拦截 (51502)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T03 期望 51502，实际 %d', @err); SET @fail += 1; END;

-- T04: 允许 dbo 删除 24 小时内的测试流水
SET @err = 0;
BEGIN TRY
    DELETE FROM dbo.tbl_stock_ledger WHERE ledger_id = @fresh_sl_id;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 0 AND NOT EXISTS (SELECT 1 FROM dbo.tbl_stock_ledger WHERE ledger_id = @fresh_sl_id)
BEGIN PRINT N'  ✅ 【PASS】T04 dbo 清理 24h 内测试库存流水成功'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T04 dbo 清理失败，err=%d', @err); SET @fail += 1; END;

/* ============================================================
 * 二、trg_points_ledger_immutable（T05 ~ T08）
 * ============================================================ */
INSERT INTO dbo.tbl_points_ledger (member_id, point_type, point_change, order_id, coupon_id)
VALUES (@member_id, 'OPENING', 1, NULL, NULL);
DECLARE @fresh_pl_id INT = SCOPE_IDENTITY();

-- T05: 禁止 UPDATE 积分流水（51503）
SET @err = 0;
BEGIN TRY
    UPDATE dbo.tbl_points_ledger SET point_change = 2 WHERE point_ledger_id = @fresh_pl_id;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51503 BEGIN PRINT N'  ✅ 【PASS】T05 积分流水 UPDATE 被拦截 (51503)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T05 期望 51503，实际 %d', @err); SET @fail += 1; END;

-- T06: 禁止 dbo 删除超过 24 小时的历史积分流水（51504）
SET @err = 0;
BEGIN TRY
    DELETE FROM dbo.tbl_points_ledger WHERE point_ledger_id = @seed_pl_id;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51504 BEGIN PRINT N'  ✅ 【PASS】T06 历史积分流水 DELETE 被拦截 (51504)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T06 期望 51504，实际 %d', @err); SET @fail += 1; END;

-- T07: 禁止非 dbo（usr_test_manager）删除当天新积分流水（51504）
SET @err = 0;
BEGIN TRY
    EXECUTE AS USER = N'usr_test_manager';
    DELETE FROM dbo.tbl_points_ledger WHERE point_ledger_id = @fresh_pl_id;
    REVERT;
END TRY
BEGIN CATCH
    WHILE USER_NAME() LIKE N'usr_test[_]%' REVERT;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51504 BEGIN PRINT N'  ✅ 【PASS】T07 非 dbo 删除积分流水被拦截 (51504)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T07 期望 51504，实际 %d', @err); SET @fail += 1; END;

-- T08: 允许 dbo 删除 24 小时内的测试积分流水
SET @err = 0;
BEGIN TRY
    DELETE FROM dbo.tbl_points_ledger WHERE point_ledger_id = @fresh_pl_id;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 0 AND NOT EXISTS (SELECT 1 FROM dbo.tbl_points_ledger WHERE point_ledger_id = @fresh_pl_id)
BEGIN PRINT N'  ✅ 【PASS】T08 dbo 清理 24h 内测试积分流水成功'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T08 dbo 清理失败，err=%d', @err); SET @fail += 1; END;

/* ============================================================
 * 三、trg_order_detail_spec_type_guard（T09 ~ T13）
 * ============================================================ */
INSERT INTO dbo.tbl_order_header
    (order_no, business_date, pickup_no, member_id, discount_amount,
     amount_due, amount_paid, pay_method, pay_status, order_status, order_time, cashier_id)
VALUES
    (N'TRG-TEST-01', CAST(SYSDATETIME() AS DATE), 991, @member_id, 0.00,
     12.00, 12.00, 'WECHAT', 'SUCCESS', 'PENDING', SYSDATETIME(), 2);
DECLARE @oid1 INT = SCOPE_IDENTITY();

-- T09: 合法 CUP/SUGAR/ICE 插入成功
SET @err = 0;
BEGIN TRY
    INSERT INTO dbo.tbl_order_detail
        (order_id, line_no, product_id, qty, unit_price, cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
    VALUES
        (@oid1, 1, @prod_id, 1, 12.00, @cup_id, @sugar_id, @ice_id, 12.00);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 0 BEGIN PRINT N'  ✅ 【PASS】T09 合法 CUP/SUGAR/ICE 订单明细插入成功'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T09 合法插入失败，err=%d', @err); SET @fail += 1; END;

-- T10: 错误 cup_spec_id 被拦截（51511）
SET @err = 0;
BEGIN TRY
    INSERT INTO dbo.tbl_order_detail
        (order_id, line_no, product_id, qty, unit_price, cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
    VALUES
        (@oid1, 2, @prod_id, 1, 12.00, @sugar_id, @sugar_id, @ice_id, 12.00);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51511 BEGIN PRINT N'  ✅ 【PASS】T10 错误杯型规格被拦截 (51511)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T10 期望 51511，实际 %d', @err); SET @fail += 1; END;

-- T11: 错误 sugar_spec_id 被拦截（51512）
SET @err = 0;
BEGIN TRY
    INSERT INTO dbo.tbl_order_detail
        (order_id, line_no, product_id, qty, unit_price, cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
    VALUES
        (@oid1, 3, @prod_id, 1, 12.00, @cup_id, @cup_id, @ice_id, 12.00);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51512 BEGIN PRINT N'  ✅ 【PASS】T11 错误糖度规格被拦截 (51512)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T11 期望 51512，实际 %d', @err); SET @fail += 1; END;

-- T12: 错误 ice_spec_id 被拦截（51513）
SET @err = 0;
BEGIN TRY
    INSERT INTO dbo.tbl_order_detail
        (order_id, line_no, product_id, qty, unit_price, cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
    VALUES
        (@oid1, 4, @prod_id, 1, 12.00, @cup_id, @sugar_id, @sugar_id, 12.00);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51513 BEGIN PRINT N'  ✅ 【PASS】T12 错误冰度规格被拦截 (51513)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T12 期望 51513，实际 %d', @err); SET @fail += 1; END;

-- T13: 多行批量插入（1 合法 + 1 非法）整批原子回滚
SET @err = 0;
DECLARE @cnt_before INT = (SELECT COUNT(*) FROM dbo.tbl_order_detail WHERE order_id = @oid1);
BEGIN TRY
    INSERT INTO dbo.tbl_order_detail
        (order_id, line_no, product_id, qty, unit_price, cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
    VALUES
        (@oid1, 5, @prod_id, 1, 12.00, @cup_id, @sugar_id, @ice_id, 12.00),
        (@oid1, 6, @prod_id, 1, 12.00, @cup_id, @ice_id, @ice_id, 12.00);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
DECLARE @cnt_after INT = (SELECT COUNT(*) FROM dbo.tbl_order_detail WHERE order_id = @oid1);
IF @err = 51512 AND @cnt_after = @cnt_before
BEGIN PRINT N'  ✅ 【PASS】T13 多行批量插入含非法规格整批原子回滚 (51512)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T13 err=%d before=%d after=%d', @err, @cnt_before, @cnt_after); SET @fail += 1; END;

/* ============================================================
 * 四、trg_order_header_state_guard（T14 ~ T18）
 * ============================================================ */
-- T14: 正向流转 PENDING -> MAKING -> READY -> COMPLETED 且自动补全 finish_time
SET @err = 0;
BEGIN TRY
    UPDATE dbo.tbl_order_header SET order_status = 'MAKING'    WHERE order_id = @oid1;
    UPDATE dbo.tbl_order_header SET order_status = 'READY'     WHERE order_id = @oid1;
    UPDATE dbo.tbl_order_header SET order_status = 'COMPLETED' WHERE order_id = @oid1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
DECLARE @fin DATETIME2 = (SELECT finish_time FROM dbo.tbl_order_header WHERE order_id = @oid1);
IF @err = 0 AND @fin IS NOT NULL
BEGIN PRINT N'  ✅ 【PASS】T14 正向状态机流转成功且自动补全 finish_time'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T14 err=%d finish_time=%s', @err, ISNULL(CONVERT(NVARCHAR(30), @fin), N'NULL')); SET @fail += 1; END;

-- T15: 终态 COMPLETED 不可逆转为 CANCELLED（51521）
SET @err = 0;
BEGIN TRY
    UPDATE dbo.tbl_order_header SET order_status = 'CANCELLED' WHERE order_id = @oid1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51521 BEGIN PRINT N'  ✅ 【PASS】T15 终态 COMPLETED 改状态被拦截 (51521)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T15 期望 51521，实际 %d', @err); SET @fail += 1; END;

-- 新建第二张待制作测试单测试跳过/回退与取消
INSERT INTO dbo.tbl_order_header
    (order_no, business_date, pickup_no, member_id, discount_amount,
     amount_due, amount_paid, pay_method, pay_status, order_status, order_time, cashier_id)
VALUES
    (N'TRG-TEST-02', CAST(SYSDATETIME() AS DATE), 992, @member_id, 0.00,
     10.00, 10.00, 'WECHAT', 'SUCCESS', 'PENDING', SYSDATETIME(), 2);
DECLARE @oid2 INT = SCOPE_IDENTITY();

-- T16: 禁止跳态 PENDING -> COMPLETED（51522）
SET @err = 0;
BEGIN TRY
    UPDATE dbo.tbl_order_header SET order_status = 'COMPLETED' WHERE order_id = @oid2;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51522 BEGIN PRINT N'  ✅ 【PASS】T16 跳态 PENDING->COMPLETED 被拦截 (51522)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T16 期望 51522，实际 %d', @err); SET @fail += 1; END;

-- T17: PENDING -> MAKING 后禁止逆向回退或取消（READY->MAKING / MAKING->CANCELLED 均拦 51522）
UPDATE dbo.tbl_order_header SET order_status = 'MAKING' WHERE order_id = @oid2;
SET @err = 0;
BEGIN TRY
    UPDATE dbo.tbl_order_header SET order_status = 'CANCELLED' WHERE order_id = @oid2;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51522 BEGIN PRINT N'  ✅ 【PASS】T17 制作中订单取消 MAKING->CANCELLED 被拦截 (51522)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T17 期望 51522，实际 %d', @err); SET @fail += 1; END;

-- T18: 新建第 3 单验证 PENDING -> CANCELLED 合法，且 CANCELLED 不可复活为 MAKING（51521）
INSERT INTO dbo.tbl_order_header
    (order_no, business_date, pickup_no, member_id, discount_amount,
     amount_due, amount_paid, pay_method, pay_status, order_status, order_time, cashier_id)
VALUES
    (N'TRG-TEST-03', CAST(SYSDATETIME() AS DATE), 993, @member_id, 0.00,
     10.00, 10.00, 'WECHAT', 'SUCCESS', 'PENDING', SYSDATETIME(), 2);
DECLARE @oid3 INT = SCOPE_IDENTITY();
UPDATE dbo.tbl_order_header SET order_status = 'CANCELLED' WHERE order_id = @oid3;

SET @err = 0;
BEGIN TRY
    UPDATE dbo.tbl_order_header SET order_status = 'MAKING' WHERE order_id = @oid3;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err = 51521 BEGIN PRINT N'  ✅ 【PASS】T18 已取消单复活 CANCELLED->MAKING 被拦截 (51521)'; SET @pass += 1; END
ELSE BEGIN PRINT FORMATMESSAGE(N'  ❌ 【FAIL】T18 期望 51521，实际 %d', @err); SET @fail += 1; END;

/* 清理全部测试订单，确保零漂移 */
DELETE FROM dbo.tbl_order_detail WHERE order_id IN (@oid1, @oid2, @oid3);
DELETE FROM dbo.tbl_order_header WHERE order_id IN (@oid1, @oid2, @oid3);

PRINT N'============================================================';
PRINT FORMATMESSAGE(N'【触发器测试总览】总用例数: %d | 通过数: %d | 失败数: %d', @expected_total, @pass, @fail);
PRINT N'============================================================';

IF @fail > 0 OR @pass <> @expected_total
    THROW 51599, N'【触发器测试失败】存在未通过断言，请检查输出日志！', 1;
GO
