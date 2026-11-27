/* ============================================================
 * 文件：project/sql/10-transaction/tx3-purchase-commit.sql
 * 用途：补货入库事务的「成功路径」—— 采购明细改实收、重算移动加权成本、
 *       加结存、写 PURCHASE_IN 流水、采购单结案，五步在同一个事务里。
 * 依赖：tbl_purchase_order / tbl_purchase_order_detail / tbl_ingredient
 *       / tbl_stock_ledger / ck_ingredient_qty_on_hand
 * 阶段：第三阶段 · 第 12 周（业务事务）
 * 幂等：是 —— 末尾自清理（删本次采购单与流水、按 Σ流水 重算结存、还原成本）
 * ============================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT N'【TX3-COMMIT】补货入库事务（正常提交）';

DECLARE @ing_id INT, @orig_qty DECIMAL(12,3), @orig_cost DECIMAL(10,4), @sup_id INT;
SELECT TOP (1) @ing_id = ingredient_id, @orig_qty = qty_on_hand, @orig_cost = moving_avg_cost
  FROM dbo.tbl_ingredient ORDER BY ingredient_id;
SELECT TOP (1) @sup_id = supplier_id FROM dbo.tbl_supplier ORDER BY supplier_id;

IF @ing_id IS NULL OR @sup_id IS NULL
    THROW 51631, N'【TX3】缺少原料或供应商基础数据，无法演示补货入库。', 1;

DECLARE @recv DECIMAL(12,3) = 100.000;
DECLARE @new_cost DECIMAL(12,4) = CAST(@orig_cost + 0.0200 AS DECIMAL(12,4));
IF @new_cost <= 0 SET @new_cost = 0.0200;

DECLARE @po_before INT = (SELECT COUNT(*) FROM dbo.tbl_purchase_order);
DECLARE @pod_before INT = (SELECT COUNT(*) FROM dbo.tbl_purchase_order_detail);
DECLARE @ledger_before INT = (SELECT COUNT(*) FROM dbo.tbl_stock_ledger);
DECLARE @qty_before DECIMAL(12,3) = (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = @ing_id);
DECLARE @expected_cost DECIMAL(10,4) =
    CAST((@qty_before * @orig_cost + @recv * @new_cost) / NULLIF(@qty_before + @recv, 0) AS DECIMAL(10,4));

/* 采购单与明细先建（事务外：模拟「到货单已开出、还没收货」） */
INSERT INTO dbo.tbl_purchase_order
    (purchase_no, supplier_id, order_date, arrival_date, order_status, ordered_by, received_by)
VALUES (N'TX3-DEMO-PO', @sup_id, CAST(SYSDATETIME() AS DATE), NULL, 'ORDERED', 1, NULL);
DECLARE @po_id INT = SCOPE_IDENTITY();

INSERT INTO dbo.tbl_purchase_order_detail
    (purchase_order_id, ingredient_id, qty_ordered, qty_received, unit_price)
VALUES (@po_id, @ing_id, @recv, 0.000, @new_cost);
DECLARE @pod_id INT = SCOPE_IDENTITY();

BEGIN TRY
    BEGIN TRANSACTION;

        DECLARE @cur_qty DECIMAL(12,3), @cur_cost DECIMAL(10,4);
        SELECT @cur_qty = qty_on_hand, @cur_cost = moving_avg_cost
          FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK)
         WHERE ingredient_id = @ing_id;

        /* ① 改实收：带 <= qty_ordered 守卫，防超收 */
        UPDATE dbo.tbl_purchase_order_detail
           SET qty_received = qty_received + @recv
         WHERE purchase_order_detail_id = @pod_id
           AND qty_received + @recv <= qty_ordered;
        IF @@ROWCOUNT <> 1
            THROW 51632, N'【TX3】采购明细超收或已不存在，入库中止。', 1;

        /* ② 加结存 + ③ 重算移动加权成本（同一句 UPDATE，要么都生效要么都不生效） */
        UPDATE dbo.tbl_ingredient
           SET qty_on_hand     = @cur_qty + @recv,
               moving_avg_cost = CAST((@cur_qty * @cur_cost + @recv * @new_cost)
                                      / NULLIF(@cur_qty + @recv, 0) AS DECIMAL(10,4))
         WHERE ingredient_id = @ing_id;

        /* ④ 写流水 */
        INSERT INTO dbo.tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, purchase_order_id, operator_id, ledger_time, remark)
        VALUES (@ing_id, 'PURCHASE_IN', @recv, 'PURCHASE', @po_id, 5, SYSDATETIME(), N'TX3 补货入库');

        /* ⑤ 采购单结案 */
        UPDATE dbo.tbl_purchase_order
           SET order_status = 'ACCEPTED',
               received_by  = 5,
               arrival_date = CAST(SYSDATETIME() AS DATE)
         WHERE purchase_order_id = @po_id;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

/* ---------- 提交后逐项校验 ---------- */
DECLARE @recv_after DECIMAL(12,3), @qty_after DECIMAL(12,3), @cost_after DECIMAL(10,4), @status VARCHAR(20);
DECLARE @ledger_after INT = (SELECT COUNT(*) FROM dbo.tbl_stock_ledger WHERE purchase_order_id = @po_id);
SELECT @recv_after = pod.qty_received, @qty_after = i.qty_on_hand, @cost_after = i.moving_avg_cost, @status = po.order_status
  FROM dbo.tbl_purchase_order po
  JOIN dbo.tbl_purchase_order_detail pod ON pod.purchase_order_id = po.purchase_order_id
  JOIN dbo.tbl_ingredient i ON i.ingredient_id = pod.ingredient_id
 WHERE po.purchase_order_id = @po_id;

DECLARE @ok INT = CASE WHEN @recv_after = @recv
                        AND @qty_after = @qty_before + @recv
                        AND @cost_after = @expected_cost
                        AND @ledger_after = 1
                        AND @status = 'ACCEPTED' THEN 1 ELSE 0 END;

IF @ok = 0
    THROW 51633, N'【TX3】事务提交后校验失败：实收/结存/成本/流水/状态有任一项不符。', 1;

PRINT N'  ✅ 实收 ' + CONVERT(NVARCHAR(20), @recv_after)
    + N' / 结存 ' + CONVERT(NVARCHAR(20), @qty_before) + N' → ' + CONVERT(NVARCHAR(20), @qty_after)
    + N' / 成本 ' + CONVERT(NVARCHAR(20), @orig_cost) + N' → ' + CONVERT(NVARCHAR(20), @cost_after)
    + N' / 流水 ' + CONVERT(NVARCHAR(10), @ledger_after) + N' 条 / 采购单 ' + @status;

/* ---------- 自清理：撤回本次采购与流水，恢复结存与成本 ---------- */
DELETE FROM dbo.tbl_stock_ledger WHERE purchase_order_id = @po_id;
DELETE FROM dbo.tbl_purchase_order_detail WHERE purchase_order_id = @po_id;
DELETE FROM dbo.tbl_purchase_order WHERE purchase_order_id = @po_id;

UPDATE dbo.tbl_ingredient
   SET qty_on_hand     = ISNULL((SELECT SUM(qty) FROM dbo.tbl_stock_ledger WHERE ingredient_id = @ing_id), 0),
       moving_avg_cost = @orig_cost
 WHERE ingredient_id = @ing_id;

DECLARE @drift INT = (SELECT COUNT(*) FROM dbo.tbl_ingredient i
                       WHERE i.qty_on_hand <> ISNULL((SELECT SUM(qty) FROM dbo.tbl_stock_ledger
                                                       WHERE ingredient_id = i.ingredient_id), 0));
DECLARE @po_after INT = (SELECT COUNT(*) FROM dbo.tbl_purchase_order);
DECLARE @pod_after INT = (SELECT COUNT(*) FROM dbo.tbl_purchase_order_detail);
DECLARE @ledger_final INT = (SELECT COUNT(*) FROM dbo.tbl_stock_ledger);

IF @drift <> 0 OR @po_after <> @po_before OR @pod_after <> @pod_before OR @ledger_final <> @ledger_before
    THROW 51639, N'【TX3】清理后库未复原：结存漂移或采购单/流水行数未回到测试前。', 1;

PRINT N'【TX3 结论】✅ PASS —— 五步同一事务正常提交；清理后采购单 '
    + CONVERT(NVARCHAR(10), @po_after) + N' 张、流水 ' + CONVERT(NVARCHAR(10), @ledger_final)
    + N' 条、结存漂移 ' + CONVERT(NVARCHAR(10), @drift) + N' 行。';
GO
