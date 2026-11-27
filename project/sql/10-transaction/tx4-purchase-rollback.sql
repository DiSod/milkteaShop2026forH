/* ============================================================
 * 文件：project/sql/10-transaction/tx4-purchase-rollback.sql
 * 用途：补货入库事务的「失败路径」—— 已加结存、已写流水，事务中途抛错，
 *       验证整单回滚：结存、成本、流水三样都不留半条账。
 * 依赖：同 tx3
 * 阶段：第三阶段 · 第 12 周（业务事务）
 * 幂等：是 —— 末尾自清理（删本次采购单，按 Σ流水 重算结存）
 * ============================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT N'【TX4-ROLLBACK】补货入库中途异常（整单回滚）';

DECLARE @ing_id INT, @orig_qty DECIMAL(12,3), @orig_cost DECIMAL(10,4), @sup_id INT;
SELECT TOP (1) @ing_id = ingredient_id, @orig_qty = qty_on_hand, @orig_cost = moving_avg_cost
  FROM dbo.tbl_ingredient ORDER BY ingredient_id;
SELECT TOP (1) @sup_id = supplier_id FROM dbo.tbl_supplier ORDER BY supplier_id;

IF @ing_id IS NULL OR @sup_id IS NULL
    THROW 51641, N'【TX4】缺少原料或供应商基础数据，无法演示。', 1;

DECLARE @po_before INT = (SELECT COUNT(*) FROM dbo.tbl_purchase_order);
DECLARE @pod_before INT = (SELECT COUNT(*) FROM dbo.tbl_purchase_order_detail);
DECLARE @ledger_before INT = (SELECT COUNT(*) FROM dbo.tbl_stock_ledger);

INSERT INTO dbo.tbl_purchase_order
    (purchase_no, supplier_id, order_date, arrival_date, order_status, ordered_by, received_by)
VALUES (N'TX4-DEMO-PO', @sup_id, CAST(SYSDATETIME() AS DATE), NULL, 'ORDERED', 1, NULL);
DECLARE @po_id INT = SCOPE_IDENTITY();

INSERT INTO dbo.tbl_purchase_order_detail
    (purchase_order_id, ingredient_id, qty_ordered, qty_received, unit_price)
VALUES (@po_id, @ing_id, 50.000, 0.000, @orig_cost);
DECLARE @pod_id INT = SCOPE_IDENTITY();

DECLARE @qty_before DECIMAL(12,3) = (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = @ing_id);
DECLARE @cost_before DECIMAL(10,4) = (SELECT moving_avg_cost FROM dbo.tbl_ingredient WHERE ingredient_id = @ing_id);
DECLARE @err INT = 0;

BEGIN TRY
    BEGIN TRANSACTION;

        UPDATE dbo.tbl_ingredient
           SET qty_on_hand = qty_on_hand + 50.000
         WHERE ingredient_id = @ing_id;

        INSERT INTO dbo.tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, purchase_order_id, operator_id, ledger_time, remark)
        VALUES (@ing_id, 'PURCHASE_IN', 50.000, 'PURCHASE', @po_id, 5, SYSDATETIME(), N'TX4 待回滚流水');

        /* 模拟「抽检不合格」：业务规则拒绝，整单不应留下任何痕迹 */
        THROW 51642, N'【TX4】抽检不合格，本次入库整单回滚。', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SET @err = ERROR_NUMBER();
END CATCH;

DECLARE @qty_after DECIMAL(12,3) = (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = @ing_id);
DECLARE @cost_after DECIMAL(10,4) = (SELECT moving_avg_cost FROM dbo.tbl_ingredient WHERE ingredient_id = @ing_id);
DECLARE @ledger_after INT = (SELECT COUNT(*) FROM dbo.tbl_stock_ledger WHERE purchase_order_id = @po_id);
DECLARE @recv_after DECIMAL(12,3) = (SELECT qty_received FROM dbo.tbl_purchase_order_detail WHERE purchase_order_detail_id = @pod_id);

IF @err <> 51642
    THROW 51643, N'【TX4】没有捕获到预期的 51642（说明异常没在事务里抛出）。', 1;
IF @qty_after <> @qty_before OR @cost_after <> @cost_before OR @ledger_after <> 0 OR @recv_after <> 0
    THROW 51644, N'【TX4】回滚不完整：结存/成本/流水/实收有任一项被留下。', 1;

PRINT N'  ✅ 捕获 ' + CONVERT(NVARCHAR(10), @err) + N'，回滚后结存 '
    + CONVERT(NVARCHAR(20), @qty_after) + N'（未变）、成本 ' + CONVERT(NVARCHAR(20), @cost_after)
    + N'（未变）、本单流水 ' + CONVERT(NVARCHAR(10), @ledger_after) + N' 条、实收 '
    + CONVERT(NVARCHAR(20), @recv_after) + N'。';

/* ---------- 自清理：采购单/明细本来就在事务外，要手工撤掉 ---------- */
DELETE FROM dbo.tbl_purchase_order_detail WHERE purchase_order_id = @po_id;
DELETE FROM dbo.tbl_purchase_order WHERE purchase_order_id = @po_id;

UPDATE dbo.tbl_ingredient
   SET qty_on_hand = ISNULL((SELECT SUM(qty) FROM dbo.tbl_stock_ledger WHERE ingredient_id = @ing_id), 0)
 WHERE ingredient_id = @ing_id;

DECLARE @drift INT = (SELECT COUNT(*) FROM dbo.tbl_ingredient i
                       WHERE i.qty_on_hand <> ISNULL((SELECT SUM(qty) FROM dbo.tbl_stock_ledger
                                                       WHERE ingredient_id = i.ingredient_id), 0));
DECLARE @po_after INT = (SELECT COUNT(*) FROM dbo.tbl_purchase_order);
DECLARE @ledger_final INT = (SELECT COUNT(*) FROM dbo.tbl_stock_ledger);

IF @drift <> 0 OR @po_after <> @po_before OR @ledger_final <> @ledger_before
    THROW 51649, N'【TX4】清理后库未复原。', 1;

PRINT N'【TX4 结论】✅ PASS —— 中途抛错整单回滚，零半边账；清理后采购单 '
    + CONVERT(NVARCHAR(10), @po_after) + N' 张、流水 ' + CONVERT(NVARCHAR(10), @ledger_final)
    + N' 条、结存漂移 ' + CONVERT(NVARCHAR(10), @drift) + N' 行。';
GO
