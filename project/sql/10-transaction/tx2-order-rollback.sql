/* ============================================================
 * 脚本：tx2-order-rollback.sql
 * 用途：第 12 周「业务事务」演示之二 —— 同一个下单流程，在第 4 步故意制造失败，
 *       验证 ROLLBACK 之后「一条残留都没有」（不完整数据不落库）。
 * 失败方式：把某种原料的结存扣成负数 → 撞 ck_ingredient_qty_on_hand (qty_on_hand >= 0)，错误 547。
 * 依赖：18 表 v1.0 结构 + 4 个触发器
 * 阶段：第 12 周（递归查询与业务事务）
 * 作者：DiSod
 * 日期：2026-11-25
 * 幂等：是 —— 事务整体回滚，脚本不改变库；可反复运行
 * ============================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- 表上有筛选索引 uq_order_header_coupon，INSERT 必须开
USE milktea_shop;
GO

PRINT N'=== 事务 2：中途失败，验证回滚后一条残留都没有 ===';

/* ---------- 0. 参数 ---------- */
DECLARE @member_id  INT  = 1;
DECLARE @cashier_id INT  = 2;
DECLARE @product_id INT  = 1;
DECLARE @qty        INT  = 2;
DECLARE @today      DATE = CAST(SYSDATETIME() AS DATE);

DECLARE @cup_id   INT = (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type = 'CUP'   AND spec_name = N'中杯');
DECLARE @sugar_id INT = (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type = 'SUGAR' AND spec_name = N'无糖');
DECLARE @ice_id   INT = (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type = 'ICE'   AND spec_name = N'去冰');

DECLARE @unit_price DECIMAL(10,2) =
    (SELECT selling_price FROM vw_product_stock_availability
      WHERE product_id = @product_id AND cup_spec_id = @cup_id);
DECLARE @subtotal DECIMAL(10,2) = @unit_price * @qty;
DECLARE @earned   INT           = CAST(@subtotal AS INT);

/* ---------- 1. 事务开始前先拍一张快照（后面用来比对） ---------- */
DECLARE @snap_head   INT = (SELECT COUNT(*) FROM tbl_order_header);
DECLARE @snap_detail INT = (SELECT COUNT(*) FROM tbl_order_detail);
DECLARE @snap_ledger INT = (SELECT COUNT(*) FROM tbl_stock_ledger);
DECLARE @snap_point  INT = (SELECT COUNT(*) FROM tbl_points_ledger);
DECLARE @snap_pts    INT = (SELECT ISNULL(SUM(points_balance),0) FROM tbl_member);
DECLARE @snap_stock  DECIMAL(12,3) = (SELECT ISNULL(SUM(qty_on_hand),0) FROM tbl_ingredient);

PRINT CONCAT(N'  事务前：订单 ', @snap_head, N' / 明细 ', @snap_detail, N' / 库存流水 ', @snap_ledger,
             N' / 积分流水 ', @snap_point, N' / 会员积分合计 ', @snap_pts, N' / 结存合计 ', @snap_stock);

/* ---------- 2. 原料需求 ---------- */
DECLARE @need TABLE (ingredient_id INT PRIMARY KEY, qty DECIMAL(12,3) NOT NULL);

INSERT INTO @need (ingredient_id, qty)
SELECT r.ingredient_id, SUM(r.qty * @qty)
  FROM tbl_recipe r
 WHERE r.product_id = @product_id
   AND r.cup_spec_id = @cup_id
   -- sugar_spec_id IS NULL 表示「该原料用量与糖度无关」（第 5 周 ER 图 §1.4 的语义），
   -- 必须和糖度专有行一起取；只写 = @sugar_id 会查不到基础原料。
   AND (r.sugar_spec_id = @sugar_id OR r.sugar_spec_id IS NULL)
 GROUP BY r.ingredient_id;

DECLARE @first_ing INT = (SELECT MIN(ingredient_id) FROM @need);

/* ---------- 3. 事务：前三步正常，第四步故意撞约束 ---------- */
DECLARE @order_no VARCHAR(20);
DECLARE @seq      INT;
DECLARE @order_id INT;

SELECT @seq = ISNULL(MAX(CAST(RIGHT(order_no, 4) AS INT)), 0)
  FROM tbl_order_header WHERE business_date = @today;
SET @seq += 1;
SET @order_no = CONVERT(VARCHAR(8), @today, 112) + '-' + RIGHT('0000' + CAST(@seq AS VARCHAR(4)), 4);

BEGIN TRY
    BEGIN TRANSACTION;

    /* 第 1 步：订单头（成功） */
    INSERT INTO tbl_order_header
        (order_no, business_date, pickup_no, member_id, coupon_id,
         discount_amount, amount_due, amount_paid, pay_method, pay_status,
         order_status, cashier_id)
    VALUES
        (@order_no, @today, @seq, @member_id, NULL,
         0.00, @subtotal, @subtotal, 'WECHAT', 'SUCCESS',
         'PENDING', @cashier_id);
    SET @order_id = SCOPE_IDENTITY();
    PRINT CONCAT(N'  第 1 步 写订单头：成功（order_id=', @order_id, N'）');

    /* 第 2 步：明细（成功） */
    INSERT INTO tbl_order_detail (order_id, line_no, product_id, qty, unit_price,
                                  cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
    VALUES (@order_id, 1, @product_id, @qty, @unit_price, @cup_id, @sugar_id, @ice_id, @subtotal);
    PRINT N'  第 2 步 写明细：成功';

    /* 第 3 步：正常扣一种料（成功） */
    UPDATE tbl_ingredient SET qty_on_hand = qty_on_hand - (@qty * 1.000)
     WHERE ingredient_id = @first_ing;
    PRINT CONCAT(N'  第 3 步 扣原料 ', @first_ing, N'：成功');

    /* 第 4 步：故意把结存扣成负数 —— 撞 CHECK，本次事务必须整体作废 */
    PRINT N'  第 4 步 故意把结存扣成负数（预期在这里失败）…';
    UPDATE tbl_ingredient SET qty_on_hand = qty_on_hand - 999999
     WHERE ingredient_id = @first_ing;

    /* 走不到这里：上一句会抛 547 */
    COMMIT TRANSACTION;
    THROW 52011, N'预期失败但居然提交成功了 —— 这个用例失效，请检查约束是否被禁用', 1;
END TRY
BEGIN CATCH
    DECLARE @err_no INT = ERROR_NUMBER();
    DECLARE @err_msg NVARCHAR(4000) = ERROR_MESSAGE();

    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

    PRINT CONCAT(N'  [CATCH] 捕获错误 ', @err_no, N'：', @err_msg);
    PRINT N'  [ROLLBACK] 事务已整体回滚';

    IF @err_no NOT IN (547)
        THROW;   -- 不是预期的约束冲突，原样抛出去
END CATCH;

/* ---------- 4. 回滚后校验：一条残留都没有 ---------- */
PRINT N'--- 回滚后逐项校验 ---';

DECLARE @after_head   INT = (SELECT COUNT(*) FROM tbl_order_header);
DECLARE @after_detail INT = (SELECT COUNT(*) FROM tbl_order_detail);
DECLARE @after_ledger INT = (SELECT COUNT(*) FROM tbl_stock_ledger);
DECLARE @after_point  INT = (SELECT COUNT(*) FROM tbl_points_ledger);
DECLARE @after_pts    INT = (SELECT ISNULL(SUM(points_balance),0) FROM tbl_member);
DECLARE @after_stock  DECIMAL(12,3) = (SELECT ISNULL(SUM(qty_on_hand),0) FROM tbl_ingredient);
DECLARE @left_order   INT = (SELECT COUNT(*) FROM tbl_order_header WHERE order_id = @order_id);

PRINT CONCAT(N'  事务后：订单 ', @after_head, N' / 明细 ', @after_detail, N' / 库存流水 ', @after_ledger,
             N' / 积分流水 ', @after_point, N' / 会员积分合计 ', @after_pts, N' / 结存合计 ', @after_stock);
PRINT CONCAT(N'  本次的订单头残留 = ', @left_order, N' 行');

IF @after_head <> @snap_head OR @after_detail <> @snap_detail OR @after_ledger <> @snap_ledger
   OR @after_point <> @snap_point OR @after_pts <> @snap_pts OR @after_stock <> @snap_stock OR @left_order <> 0
   THROW 52012, N'回滚不干净：有数据残留或结存被改动', 1;

PRINT N'【事务 2 结论】第 4 步失败后事务整体回滚：订单头/明细/流水/积分/结存全部回到事务前 —— 没有写进半条不完整数据。';
GO
