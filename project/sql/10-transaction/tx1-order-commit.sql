/* ============================================================
 * 脚本：tx1-order-commit.sql
 * 用途：第 12 周「业务事务」演示之一 —— 一次下单在同一个事务里完成五步写入，
 *       COMMIT 后逐张表校验「五步全有」，末尾再把自己产生的行清干净（幂等）。
 * 对比：应用层的 place_order()（project/app/service/ordering.py）做的是同一件事，
 *       事务由 pyodbc 连接对象管；这里把它摊开成 T-SQL，看清 BEGIN/COMMIT 包住了什么。
 * 依赖：18 表 v1.0 结构 + 4 个触发器（trg_stock_ledger_immutable 等）
 * 阶段：第 12 周（递归查询与业务事务）
 * 作者：DiSod
 * 日期：2026-11-25
 * 幂等：是 —— 结尾按 order_id 删除本次写入的行，并按 Σ流水 重算结存
 * ============================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- 表上有筛选索引 uq_order_header_coupon，INSERT 必须开
USE milktea_shop;
GO

PRINT N'=== 事务 1：一次下单，五步全在一个事务里 ===';

/* ---------- 0. 参数（改这里就能换商品/数量/会员） ---------- */
DECLARE @member_id  INT          = 1;          -- 刘洋
DECLARE @cashier_id INT          = 2;          -- 系统收银柜员（与 place_order 默认一致）
DECLARE @product_id INT          = 1;          -- 招牌柠檬水
DECLARE @qty        INT          = 2;
DECLARE @today      DATE         = CAST(SYSDATETIME() AS DATE);

DECLARE @cup_id    INT = (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type = 'CUP'   AND spec_name = N'中杯');
DECLARE @sugar_id  INT = (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type = 'SUGAR' AND spec_name = N'无糖');
DECLARE @ice_id    INT = (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type = 'ICE'   AND spec_name = N'去冰');

IF @cup_id IS NULL OR @sugar_id IS NULL OR @ice_id IS NULL
    THROW 52001, N'规格项缺失（CUP/SUGAR/ICE 至少有一种没配）', 1;

/* ---------- 1. 取价（杯型价来自可售视图，和页面同一张视图） ---------- */
DECLARE @unit_price DECIMAL(10,2) =
    (SELECT selling_price FROM vw_product_stock_availability
      WHERE product_id = @product_id AND cup_spec_id = @cup_id);

IF @unit_price IS NULL
    THROW 52002, N'这个商品在售该杯型没有价格行（可能已下架）', 1;

DECLARE @subtotal DECIMAL(10,2) = @unit_price * @qty;
DECLARE @earned   INT           = CAST(@subtotal AS INT);   -- 1 元 1 分

PRINT CONCAT(N'  参数：会员 ', @member_id, N' / 商品 ', @product_id, N' / 数量 ', @qty,
             N' / 单价 ', @unit_price, N' / 小计 ', @subtotal);

/* ---------- 2. 算原料需求（配方按 商品×杯型×糖度） ---------- */
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

IF NOT EXISTS (SELECT 1 FROM @need)
    THROW 52003, N'这个组合没有配方行，做不出来', 1;

/* ---------- 3. 库里先校验一遍（应用层也有这一步，这里是同一条规则） ---------- */
IF EXISTS (SELECT 1 FROM @need n JOIN tbl_ingredient i ON i.ingredient_id = n.ingredient_id
            WHERE i.is_sold_out = 1 OR i.qty_on_hand < n.qty)
   THROW 52004, N'原料不足或已沽清，不能下单', 1;

/* ---------- 4. 事务开始：五步写 ---------- */
DECLARE @order_no  VARCHAR(20);
DECLARE @pickup_no INT;
DECLARE @order_id  INT;
DECLARE @seq       INT;

SELECT @seq = ISNULL(MAX(CAST(RIGHT(order_no, 4) AS INT)), 0)
  FROM tbl_order_header WHERE business_date = @today;
SET @seq += 1;
SET @pickup_no = @seq;
SET @order_no  = CONVERT(VARCHAR(8), @today, 112) + '-' + RIGHT('0000' + CAST(@seq AS VARCHAR(4)), 4);

BEGIN TRY
    BEGIN TRANSACTION;

    /* 第 1 步：订单头 */
    INSERT INTO tbl_order_header
        (order_no, business_date, pickup_no, member_id, coupon_id,
         discount_amount, amount_due, amount_paid, pay_method, pay_status,
         order_status, cashier_id)
    VALUES
        (@order_no, @today, @pickup_no, @member_id, NULL,
         0.00, @subtotal, @subtotal, 'WECHAT', 'SUCCESS',
         'PENDING', @cashier_id);
    SET @order_id = SCOPE_IDENTITY();

    /* 第 2 步：订单明细 */
    INSERT INTO tbl_order_detail (order_id, line_no, product_id, qty, unit_price,
                                  cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
    VALUES (@order_id, 1, @product_id, @qty, @unit_price, @cup_id, @sugar_id, @ice_id, @subtotal);

    /* 第 3、4 步：逐种原料「扣结存」+「写流水」——两步必须成对 */
    UPDATE i SET i.qty_on_hand = i.qty_on_hand - n.qty
      FROM tbl_ingredient i JOIN @need n ON n.ingredient_id = i.ingredient_id;

    INSERT INTO tbl_stock_ledger (ingredient_id, ledger_type, qty, ref_type, order_id, operator_id, remark)
    SELECT n.ingredient_id, 'SALES_USE', -n.qty, 'ORDER', @order_id, NULL, N'下单扣料'
      FROM @need n;

    /* 第 5 步：积分（会员才产生） */
    IF @earned > 0
    BEGIN
        INSERT INTO tbl_points_ledger (member_id, point_type, point_change, order_id)
        VALUES (@member_id, 'EARN', @earned, @order_id);

        UPDATE tbl_member SET points_balance = points_balance + @earned
         WHERE member_id = @member_id;
    END

    COMMIT TRANSACTION;
    PRINT CONCAT(N'  [COMMIT] 订单 ', @order_no, N'（order_id=', @order_id, N'）已提交');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    PRINT CONCAT(N'  [ROLLBACK] 出错：', ERROR_NUMBER(), N' / ', ERROR_MESSAGE());
    THROW;
END CATCH;

/* ---------- 5. 提交后校验：五步都落库了 ---------- */
PRINT N'--- 提交后逐表校验 ---';

DECLARE @c_head   INT = (SELECT COUNT(*) FROM tbl_order_header  WHERE order_id = @order_id);
DECLARE @c_detail INT = (SELECT COUNT(*) FROM tbl_order_detail  WHERE order_id = @order_id);
DECLARE @c_ledger INT = (SELECT COUNT(*) FROM tbl_stock_ledger  WHERE order_id = @order_id);
DECLARE @c_point  INT = (SELECT COUNT(*) FROM tbl_points_ledger WHERE order_id = @order_id);
DECLARE @c_need   INT = (SELECT COUNT(*) FROM @need);

PRINT CONCAT(N'  订单头 ', @c_head, N' 行 / 明细 ', @c_detail, N' 行 / 库存流水 ', @c_ledger,
             N' 行（应=', @c_need, N'）/ 积分流水 ', @c_point, N' 行');

IF @c_head <> 1 OR @c_detail <> 1 OR @c_ledger <> @c_need OR @c_point <> (CASE WHEN @earned > 0 THEN 1 ELSE 0 END)
    THROW 52005, N'提交后行数不对：五步没有全部落库', 1;

/* ---------- 6. 清理：把自己写的行删干净，并按 Σ流水 重算结存 ---------- */
PRINT N'--- 清理（把本次演示写入的行删掉） ---';

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE FROM tbl_points_ledger WHERE order_id = @order_id;

    UPDATE tbl_member SET points_balance = points_balance - @earned
     WHERE member_id = @member_id AND @earned > 0;

    DELETE FROM tbl_stock_ledger WHERE order_id = @order_id;

    /* 结存按流水重算，保证恒等式 qty_on_hand = Σ流水 */
    UPDATE i SET i.qty_on_hand = f.flow_total
      FROM tbl_ingredient i
      JOIN (SELECT n.ingredient_id,
                   (SELECT ISNULL(SUM(l.qty), 0) FROM tbl_stock_ledger l
                     WHERE l.ingredient_id = n.ingredient_id) AS flow_total
              FROM @need n) f ON f.ingredient_id = i.ingredient_id;

    DELETE t FROM tbl_order_detail_topping t
      JOIN tbl_order_detail d ON d.order_detail_id = t.order_detail_id
     WHERE d.order_id = @order_id;

    DELETE FROM tbl_order_detail WHERE order_id = @order_id;
    DELETE FROM tbl_order_header WHERE order_id = @order_id;

    COMMIT TRANSACTION;
    PRINT N'  [COMMIT] 清理完成';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    PRINT CONCAT(N'  [ROLLBACK] 清理失败：', ERROR_NUMBER(), N' / ', ERROR_MESSAGE());
    THROW;
END CATCH;

/* ---------- 7. 复核：回到演示前 ---------- */
PRINT N'--- 复核 ---';

DECLARE @left_head   INT = (SELECT COUNT(*) FROM tbl_order_header  WHERE order_id = @order_id);
DECLARE @left_detail INT = (SELECT COUNT(*) FROM tbl_order_detail  WHERE order_id = @order_id);
DECLARE @left_ledger INT = (SELECT COUNT(*) FROM tbl_stock_ledger  WHERE order_id = @order_id);
DECLARE @left_point  INT = (SELECT COUNT(*) FROM tbl_points_ledger WHERE order_id = @order_id);
DECLARE @drift       INT = (SELECT COUNT(*) FROM tbl_ingredient i
                             WHERE i.qty_on_hand <> (SELECT ISNULL(SUM(l.qty),0) FROM tbl_stock_ledger l
                                                      WHERE l.ingredient_id = i.ingredient_id));

PRINT CONCAT(N'  残留：头/明细/流水/积分 = ', @left_head, '/', @left_detail, '/', @left_ledger, '/', @left_point);
PRINT CONCAT(N'  库存恒等式偏差行数 = ', @drift);

IF @left_head + @left_detail + @left_ledger + @left_point <> 0 OR @drift <> 0
    THROW 52006, N'清理不干净：库里还有残留或结存与流水不一致', 1;

PRINT N'【事务 1 结论】五步全部提交、逐表校验通过、清理后库复原 —— 事务边界正确。';
GO
