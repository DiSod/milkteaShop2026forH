/* ============================================================
 * 脚本：tx-order-and-replenish.sql
 * 用途：第 12—13 周核心事务实验 —— 订单交易与补货入库的正常提交与失败回滚
 * 依赖：00-bootstrap ~ 11-migration + 09-programmability/trigger.sql
 * 阶段：第 12—13 周（事务与并发控制）
 * 作者：何争霖 (hezhlin5)
 * 日期：2026-11-25
 * 幂等：是（开头清理残留、末尾彻底清理并校验零漂移）
 * ============================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

USE milktea_shop;
GO

/* ============================================================
 * 0. 前置：记录初始不变量基准，并清理可能残留的 TX-DEMO-* 数据
 * ============================================================ */
DELETE FROM dbo.tbl_stock_ledger
WHERE order_id IN (SELECT order_id FROM dbo.tbl_order_header WHERE order_no LIKE N'TX-DEMO-%')
   OR purchase_order_id IN (SELECT purchase_order_id FROM dbo.tbl_purchase_order WHERE purchase_no LIKE N'TX-DEMO-%');
DELETE FROM dbo.tbl_points_ledger
WHERE order_id IN (SELECT order_id FROM dbo.tbl_order_header WHERE order_no LIKE N'TX-DEMO-%');
DELETE FROM dbo.tbl_order_detail_topping
WHERE order_detail_id IN (
    SELECT d.order_detail_id FROM dbo.tbl_order_detail AS d
    JOIN dbo.tbl_order_header AS h ON h.order_id = d.order_id
    WHERE h.order_no LIKE N'TX-DEMO-%'
);
DELETE FROM dbo.tbl_order_detail
WHERE order_id IN (SELECT order_id FROM dbo.tbl_order_header WHERE order_no LIKE N'TX-DEMO-%');
DELETE FROM dbo.tbl_order_header WHERE order_no LIKE N'TX-DEMO-%';
DELETE FROM dbo.tbl_purchase_order_detail
WHERE purchase_order_id IN (SELECT purchase_order_id FROM dbo.tbl_purchase_order WHERE purchase_no LIKE N'TX-DEMO-%');
DELETE FROM dbo.tbl_purchase_order WHERE purchase_no LIKE N'TX-DEMO-%';
GO

PRINT N'============================================================';
PRINT N'【事务验证】启动订单下单/完成与模拟补货入库的 COMMIT / ROLLBACK 验证 ...';
PRINT N'============================================================';

DECLARE @member_id INT = 1;
DECLARE @prod_id INT, @cup_id INT, @sugar_id INT, @ice_id INT;
DECLARE @unit_price DECIMAL(10,2);

SELECT TOP 1
    @prod_id    = p.product_id,
    @cup_id     = r.cup_spec_id,
    @unit_price = CAST(p.base_price + cs.extra_price AS DECIMAL(10,2))
FROM dbo.tbl_recipe AS r
JOIN dbo.tbl_product AS p
    ON p.product_id = r.product_id
JOIN dbo.tbl_spec_option AS cs
    ON cs.spec_option_id = r.cup_spec_id
WHERE r.sugar_spec_id IS NULL
  AND p.product_status = 'ON_SALE'
ORDER BY p.product_id, r.cup_spec_id;

SELECT TOP 1 @sugar_id = spec_option_id FROM dbo.tbl_spec_option WHERE spec_type = 'SUGAR' ORDER BY spec_option_id;
SELECT TOP 1 @ice_id   = spec_option_id FROM dbo.tbl_spec_option WHERE spec_type = 'ICE'   ORDER BY spec_option_id;

DECLARE @points_before INT = (SELECT points_balance FROM dbo.tbl_member WHERE member_id = @member_id);
DECLARE @orders_before INT = (SELECT COUNT(*) FROM dbo.tbl_order_header);

/* ============================================================
 * TX-1A：订单下单 → 扣料/记流水 → 积分 → 状态机完单（正常 COMMIT）
 * ============================================================ */
PRINT N'【TX-1A】订单下单并完单事务（正常 COMMIT）...';
DECLARE @o1_id INT = NULL, @o1_detail_id INT = NULL;
DECLARE @o1_points INT = CAST(@unit_price AS INT);
DECLARE @now1 DATETIME2 = SYSDATETIME();

BEGIN TRY
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

        INSERT INTO dbo.tbl_order_header
            (order_no, business_date, pickup_no, member_id, coupon_id,
             discount_amount, amount_due, amount_paid, pay_method, pay_status,
             pay_time, order_status, order_time, cashier_id)
        VALUES
            (N'TX-DEMO-O1', CAST(@now1 AS DATE), 981, @member_id, NULL,
             0.00, @unit_price, @unit_price, 'WECHAT', 'SUCCESS',
             @now1, 'PENDING', @now1, 2);
        SET @o1_id = SCOPE_IDENTITY();

        INSERT INTO dbo.tbl_order_detail
            (order_id, line_no, product_id, qty, unit_price,
             cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
        VALUES
            (@o1_id, 1, @prod_id, 1, @unit_price,
             @cup_id, @sugar_id, @ice_id, @unit_price);
        SET @o1_detail_id = SCOPE_IDENTITY();

        /* 按 ingredient_id 升序加 UPDLOCK, ROWLOCK 扣减配方原料，杜绝超卖与死锁 */
        DECLARE @need TABLE (ingredient_id INT PRIMARY KEY, req_qty DECIMAL(12,3));
        INSERT INTO @need (ingredient_id, req_qty)
        SELECT r.ingredient_id, SUM(r.qty)
        FROM dbo.tbl_recipe AS r
        WHERE r.product_id = @prod_id
          AND r.cup_spec_id = @cup_id
          AND (r.sugar_spec_id = @sugar_id OR r.sugar_spec_id IS NULL)
        GROUP BY r.ingredient_id;

        /* 先按升序锁定并校验余量与沽清状态 */
        IF EXISTS (
            SELECT 1
            FROM @need AS n
            JOIN dbo.tbl_ingredient AS i WITH (UPDLOCK, ROWLOCK)
                ON i.ingredient_id = n.ingredient_id
            WHERE i.is_sold_out = 1 OR i.qty_on_hand < n.req_qty
        )
            THROW 51601, N'【TX-1A】原料已沽清或余量不足。', 1;

        UPDATE i
        SET i.qty_on_hand = i.qty_on_hand - n.req_qty
        FROM dbo.tbl_ingredient AS i
        JOIN @need AS n
            ON n.ingredient_id = i.ingredient_id;

        INSERT INTO dbo.tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, order_id, operator_id, ledger_time, remark)
        SELECT
            n.ingredient_id, 'SALES_USE', -n.req_qty, 'ORDER', @o1_id, 2, SYSDATETIME(), N'TX-1A 事务下单扣料'
        FROM @need AS n
        ORDER BY n.ingredient_id;

        IF @o1_points > 0
        BEGIN
            INSERT INTO dbo.tbl_points_ledger (member_id, point_type, point_change, order_id, change_time)
            VALUES (@member_id, 'EARN', @o1_points, @o1_id, SYSDATETIME());

            UPDATE dbo.tbl_member
            SET points_balance = points_balance + @o1_points
            WHERE member_id = @member_id;
        END;

        /* 推进订单状态机直至 COMPLETED（触发器自动补全 finish_time） */
        UPDATE dbo.tbl_order_header SET order_status = 'MAKING'    WHERE order_id = @o1_id;
        UPDATE dbo.tbl_order_header SET order_status = 'READY'     WHERE order_id = @o1_id;
        UPDATE dbo.tbl_order_header SET order_status = 'COMPLETED' WHERE order_id = @o1_id;

    COMMIT TRANSACTION;
    PRINT N'  ✅ 【PASS】TX-1A 订单下单+扣料+积分+完单事务 COMMIT 成功。';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT
    h.order_no,
    h.order_status,
    h.finish_time,
    (SELECT COUNT(*) FROM dbo.tbl_stock_ledger WHERE order_id = h.order_id) AS stock_moves,
    (SELECT COUNT(*) FROM dbo.tbl_points_ledger WHERE order_id = h.order_id) AS point_moves
FROM dbo.tbl_order_header AS h
WHERE h.order_id = @o1_id;

/* ============================================================
 * TX-1B：订单下单中途扣料触碰负库存约束 → 整单 ROLLBACK
 * ============================================================ */
PRINT N'【TX-1B】订单下单触碰负库存约束（失败 ROLLBACK 验证零残留）...';
DECLARE @o2_err INT = 0;
DECLARE @now2 DATETIME2 = SYSDATETIME();

BEGIN TRY
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

        INSERT INTO dbo.tbl_order_header
            (order_no, business_date, pickup_no, member_id, coupon_id,
             discount_amount, amount_due, amount_paid, pay_method, pay_status,
             pay_time, order_status, order_time, cashier_id)
        VALUES
            (N'TX-DEMO-O2', CAST(@now2 AS DATE), 982, @member_id, NULL,
             0.00, @unit_price, @unit_price, 'WECHAT', 'SUCCESS',
             @now2, 'PENDING', @now2, 2);
        DECLARE @o2_id INT = SCOPE_IDENTITY();

        INSERT INTO dbo.tbl_order_detail
            (order_id, line_no, product_id, qty, unit_price,
             cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
        VALUES
            (@o2_id, 1, @prod_id, 1, @unit_price,
             @cup_id, @sugar_id, @ice_id, @unit_price);

        /* 故意对配方首种原料超扣 999999，触发 ck_ingredient_qty_on_hand (547) */
        DECLARE @bad_ing INT = (SELECT TOP 1 ingredient_id FROM dbo.tbl_ingredient ORDER BY ingredient_id);
        UPDATE dbo.tbl_ingredient
        SET qty_on_hand = qty_on_hand - 999999.000
        WHERE ingredient_id = @bad_ing;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @o2_err = ERROR_NUMBER();
END CATCH;

DECLARE @o2_left INT = (SELECT COUNT(*) FROM dbo.tbl_order_header WHERE order_no = N'TX-DEMO-O2');
IF @o2_err = 547 AND @o2_left = 0
    PRINT N'  ✅ 【PASS】TX-1B 超扣触发 547 约束，ROLLBACK 后 TX-DEMO-O2 在头/明细/流水均零残留。';
ELSE
    THROW 51691, N'【FAIL】TX-1B 未按预期回滚或残留脏数据！', 1;

/* ============================================================
 * TX-2A：模拟补货入库事务（改实收/重算移动加权成本/加库存/写流水/结案，正常 COMMIT）
 * ============================================================ */
PRINT N'【TX-2A】模拟补货入库事务（正常 COMMIT）...';
DECLARE @po_ing_id INT, @orig_qty DECIMAL(12,3), @orig_cost DECIMAL(10,4), @sup_id INT;
SELECT TOP 1
    @po_ing_id = ingredient_id,
    @orig_qty  = qty_on_hand,
    @orig_cost = moving_avg_cost
FROM dbo.tbl_ingredient
ORDER BY ingredient_id;
SELECT TOP 1 @sup_id = supplier_id FROM dbo.tbl_supplier ORDER BY supplier_id;

INSERT INTO dbo.tbl_purchase_order
    (purchase_no, supplier_id, order_date, arrival_date, order_status, ordered_by, received_by)
VALUES
    (N'TX-DEMO-PO1', @sup_id, CAST(SYSDATETIME() AS DATE), NULL, 'ORDERED', 1, NULL);
DECLARE @po1_id INT = SCOPE_IDENTITY();

DECLARE @new_cost DECIMAL(12,4) = CAST(@orig_cost + 0.0200 AS DECIMAL(12,4));
INSERT INTO dbo.tbl_purchase_order_detail
    (purchase_order_id, ingredient_id, qty_ordered, qty_received, unit_price)
VALUES
    (@po1_id, @po_ing_id, 100.000, 0.000, @new_cost);
DECLARE @pod1_id INT = SCOPE_IDENTITY();

BEGIN TRY
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

        DECLARE @cur_qty DECIMAL(12,3), @cur_cost DECIMAL(10,4), @recv_qty DECIMAL(12,3) = 100.000;
        SELECT
            @cur_qty  = qty_on_hand,
            @cur_cost = moving_avg_cost
        FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK)
        WHERE ingredient_id = @po_ing_id;

        DECLARE @updated_cost DECIMAL(10,4) = CAST(
            (@cur_qty * @cur_cost + @recv_qty * @new_cost) / NULLIF(@cur_qty + @recv_qty, 0)
            AS DECIMAL(10,4)
        );

        UPDATE dbo.tbl_purchase_order_detail
        SET qty_received = qty_received + @recv_qty
        WHERE purchase_order_detail_id = @pod1_id
          AND qty_received + @recv_qty <= qty_ordered;

        IF @@ROWCOUNT <> 1
            THROW 51602, N'【TX-2A】采购明细超收或不存在。', 1;

        UPDATE dbo.tbl_ingredient
        SET qty_on_hand     = @cur_qty + @recv_qty,
            moving_avg_cost = @updated_cost
        WHERE ingredient_id = @po_ing_id;

        INSERT INTO dbo.tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, purchase_order_id, operator_id, ledger_time, remark)
        VALUES
            (@po_ing_id, 'PURCHASE_IN', @recv_qty, 'PURCHASE', @po1_id, 5, SYSDATETIME(), N'TX-2A 补货入库事务');

        UPDATE dbo.tbl_purchase_order
        SET order_status = 'ACCEPTED',
            received_by  = 5,
            arrival_date = CAST(SYSDATETIME() AS DATE)
        WHERE purchase_order_id = @po1_id;

    COMMIT TRANSACTION;
    PRINT N'  ✅ 【PASS】TX-2A 补货入库 COMMIT 成功：数量、加权成本、流水与采购单结案原子生效。';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT
    po.purchase_no,
    po.order_status,
    pod.qty_ordered,
    pod.qty_received,
    @orig_qty  AS 入库前结存,
    i.qty_on_hand AS 入库后结存,
    @orig_cost AS 入库前成本,
    i.moving_avg_cost AS 入库后移动加权成本
FROM dbo.tbl_purchase_order AS po
JOIN dbo.tbl_purchase_order_detail AS pod ON pod.purchase_order_id = po.purchase_order_id
JOIN dbo.tbl_ingredient AS i ON i.ingredient_id = pod.ingredient_id
WHERE po.purchase_order_id = @po1_id;

/* ============================================================
 * TX-2B：模拟补货入库中途业务异常 → 整单 ROLLBACK（防半边账）
 * ============================================================ */
PRINT N'【TX-2B】模拟补货入库中途异常（失败 ROLLBACK 验证结存/成本/流水不变）...';
INSERT INTO dbo.tbl_purchase_order
    (purchase_no, supplier_id, order_date, arrival_date, order_status, ordered_by, received_by)
VALUES
    (N'TX-DEMO-PO2', @sup_id, CAST(SYSDATETIME() AS DATE), NULL, 'ORDERED', 1, NULL);
DECLARE @po2_id INT = SCOPE_IDENTITY();

INSERT INTO dbo.tbl_purchase_order_detail
    (purchase_order_id, ingredient_id, qty_ordered, qty_received, unit_price)
VALUES
    (@po2_id, @po_ing_id, 50.000, 0.000, @new_cost);
DECLARE @pod2_id INT = SCOPE_IDENTITY();

DECLARE @qty_before_2b DECIMAL(12,3) = (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = @po_ing_id);
DECLARE @tx2b_err INT = 0;

BEGIN TRY
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

        UPDATE dbo.tbl_ingredient
        SET qty_on_hand = qty_on_hand + 50.000
        WHERE ingredient_id = @po_ing_id;

        INSERT INTO dbo.tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, purchase_order_id, operator_id, ledger_time, remark)
        VALUES
            (@po_ing_id, 'PURCHASE_IN', 50.000, 'PURCHASE', @po2_id, 5, SYSDATETIME(), N'TX-2B 待回滚流水');

        /* 模拟质检失败或超收校验未通过，事务中途抛出业务异常 */
        THROW 51603, N'【TX-2B】模拟入库抽检不合格，整单回滚。', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @tx2b_err = ERROR_NUMBER();
END CATCH;

DECLARE @qty_after_2b DECIMAL(12,3) = (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = @po_ing_id);
DECLARE @po2_ledgers INT = (SELECT COUNT(*) FROM dbo.tbl_stock_ledger WHERE purchase_order_id = @po2_id);
IF @tx2b_err = 51603 AND @qty_after_2b = @qty_before_2b AND @po2_ledgers = 0
    PRINT N'  ✅ 【PASS】TX-2B 中途抛错 51603，ROLLBACK 后库存与流水完全未变（零半边账）。';
ELSE
    THROW 51692, N'【FAIL】TX-2B 未能完整回滚！', 1;

/* ============================================================
 * 收尾清理：完整撤回 TX-DEMO-* 临时演示记录，恢复基准零漂移
 * ============================================================ */
DELETE FROM dbo.tbl_stock_ledger
WHERE order_id = @o1_id OR purchase_order_id IN (@po1_id, @po2_id);
DELETE FROM dbo.tbl_points_ledger WHERE order_id = @o1_id;
DELETE FROM dbo.tbl_order_detail WHERE order_id = @o1_id;
DELETE FROM dbo.tbl_order_header WHERE order_id = @o1_id;
DELETE FROM dbo.tbl_purchase_order_detail WHERE purchase_order_id IN (@po1_id, @po2_id);
DELETE FROM dbo.tbl_purchase_order WHERE purchase_order_id IN (@po1_id, @po2_id);

/* 按流水重算受影响原料结存并恢复初始移动加权成本与会员积分 */
UPDATE i
SET i.qty_on_hand = ISNULL((SELECT SUM(qty) FROM dbo.tbl_stock_ledger WHERE ingredient_id = i.ingredient_id), 0)
FROM dbo.tbl_ingredient AS i;

UPDATE dbo.tbl_ingredient
SET moving_avg_cost = @orig_cost
WHERE ingredient_id = @po_ing_id;

UPDATE dbo.tbl_member
SET points_balance = @points_before
WHERE member_id = @member_id;

DECLARE @stock_drift INT = (
    SELECT COUNT(*) FROM dbo.tbl_ingredient AS i
    WHERE i.qty_on_hand <> ISNULL((SELECT SUM(qty) FROM dbo.tbl_stock_ledger WHERE ingredient_id = i.ingredient_id), 0)
);
DECLARE @points_drift INT = (
    SELECT COUNT(*) FROM dbo.tbl_member AS m
    WHERE m.points_balance <> ISNULL((SELECT SUM(point_change) FROM dbo.tbl_points_ledger WHERE member_id = m.member_id), 0)
);
DECLARE @orders_after INT = (SELECT COUNT(*) FROM dbo.tbl_order_header);

IF @stock_drift = 0 AND @points_drift = 0 AND @orders_after = @orders_before
    PRINT FORMATMESSAGE(N'【事务验证总览】🎉 4 组事务（2 COMMIT + 2 ROLLBACK）全过；清理后订单 %d，库存漂移 0，积分漂移 0。', @orders_after);
ELSE
    THROW 51699, N'【FAIL】收尾清理后存在数据库漂移！', 1;
GO
