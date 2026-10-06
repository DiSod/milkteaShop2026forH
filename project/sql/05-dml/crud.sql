/* ============================================================
 * 脚本：crud.sql
 * 用途：增删改查演示（课程第 3 周"现场执行一组 CRUD"的素材）
 * 依赖：00 → 01 → 02 → 03 → 04 全部执行完毕（库里有种子数据）
 * 阶段：第 3 周（负例部分同时服务于第 4 周"非法数据被拒绝"展示）
 * 作者：DiSod
 * 日期：2026-10-04
 * 幂等：是 —— 开头清理上次的演示残留，可反复执行
 * ============================================================
 *
 * 【本脚本想证明什么】
 *   不是"SQL 语法没写错"，而是"**这些设计规则真的在数据库里生效了**"。
 *   因此每个动作都尽量挂上一条我们设计过的业务规则：
 *     - 反冲倒扣：下单 → 按配方扣总库 + 写流水
 *     - CHECK (qty_on_hand >= 0)：库存不允许为负
 *     - 判别列 + 真外键（D-09）：流水必须能追溯到真实单据
 *     - 下架用状态不删行：历史订单不受影响
 *     - 外键阻挡删除：这正是"不删行"的技术理由
 *     - 订单状态机：PENDING → MAKING → READY → COMPLETED
 *     - 券退回 + 积分回滚：取消订单要把三样东西都退回去
 *
 * 【演示数据用 DEMO- 前缀，便于识别与清理】
 *   DEMO-E1  员工        DEMO-M1  会员        DEMO-CP1 券
 *   DEMO-I1  原料        DEMO-P1  成品        DEMO-O1  订单
 *
 * 【执行方式】
 *   sqlcmd -S .\SQLEXPRESS -E -i project/sql/05-dml/crud.sql
 * ============================================================ */

USE milktea_shop;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ============================================================
 * 0. 准备：快照库存 + 清理上次残留
 * ============================================================ */

-- 0.1 把当前库存快照到临时表，脚本末尾用它回滚（甲方案）
DROP TABLE IF EXISTS #inv_snapshot;

SELECT ingredient_id, ingredient_code, qty_on_hand
INTO   #inv_snapshot
FROM   tbl_ingredient;

PRINT N'【CRUD】步骤 0.1 已快照 ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + N' 种原料的当前库存。';
GO

-- 0.2 清理上次演示残留（按依赖逆序）
PRINT N'【CRUD】步骤 0.2 清理上次演示残留 ...';
GO

-- ⚠️ 顺序必须严格按依赖逆序 —— 漏掉任何一张引用表，删除就会失败；
--    而本脚本开头有 SET XACT_ABORT ON，一旦有一条语句失败，**整批后续清理都会被跳过**。
--    （这正是第一版清理段踩到的坑：tbl_purchase_order_detail 还引用着 DEMO-I1。）

-- ① 流水：引用 原料 / 订单 / 采购单 / 员工
DELETE FROM tbl_stock_ledger
WHERE ingredient_id IN (SELECT ingredient_id FROM tbl_ingredient WHERE ingredient_code = 'DEMO-I1')
   OR order_id      IN (SELECT order_id      FROM tbl_order_header WHERE order_no LIKE 'DEMO-%')
   OR purchase_order_id IN (SELECT purchase_order_id FROM tbl_purchase_order WHERE purchase_no = 'DEMO-PO1');

-- ② 积分流水：引用 会员 / 订单 / 券
DELETE FROM tbl_points_ledger
WHERE member_id IN (SELECT member_id FROM tbl_member WHERE member_code LIKE 'DEMO-%')
   OR order_id  IN (SELECT order_id  FROM tbl_order_header WHERE order_no LIKE 'DEMO-%');

-- ③ 加料 → ④ 明细 → ⑤ 订单头
DELETE FROM tbl_order_detail_topping
WHERE order_detail_id IN (
        SELECT d.order_detail_id FROM tbl_order_detail d
        JOIN   tbl_order_header h ON h.order_id = d.order_id
        WHERE  h.order_no LIKE 'DEMO-%');

DELETE FROM tbl_order_detail
WHERE order_id IN (SELECT order_id FROM tbl_order_header WHERE order_no LIKE 'DEMO-%');

DELETE FROM tbl_order_header WHERE order_no LIKE 'DEMO-%';

-- ⑥ 券（订单头已删，不再被引用）
DELETE FROM tbl_coupon
WHERE coupon_code LIKE 'DEMO-%'
   OR member_id  IN (SELECT member_id FROM tbl_member WHERE member_code LIKE 'DEMO-%');

-- ⑦ 采购明细 → ⑧ 采购单头
DELETE FROM tbl_purchase_order_detail
WHERE purchase_order_id IN (SELECT purchase_order_id FROM tbl_purchase_order WHERE purchase_no = 'DEMO-PO1');

DELETE FROM tbl_purchase_order WHERE purchase_no = 'DEMO-PO1';

-- ⑨ 配方 → ⑩ 成品 → ⑪ 原料
DELETE FROM tbl_recipe
WHERE product_id IN (SELECT product_id FROM tbl_product WHERE product_code = 'DEMO-P1');

DELETE FROM tbl_product    WHERE product_code    = 'DEMO-P1';
DELETE FROM tbl_ingredient WHERE ingredient_code = 'DEMO-I1';

-- ⑫ 会员 → ⑬ 员工
DELETE FROM tbl_member   WHERE member_code   LIKE 'DEMO-%';
DELETE FROM tbl_employee WHERE employee_code LIKE 'DEMO-%';
GO

/* ============================================================
 * 1. CREATE（增）
 * ============================================================ */

/* ---------- 1.1 新增一名员工 ---------- */
PRINT N'【CRUD】1.1 CREATE —— 新增员工 DEMO-E1';
GO

INSERT INTO tbl_employee (employee_code, employee_name, position, hire_date)
VALUES (N'DEMO-E1', N'演示员工', N'CASHIER', '2026-10-04');

SELECT employee_id, employee_code, employee_name, position, hire_date, is_active
FROM   tbl_employee WHERE employee_code = 'DEMO-E1';
GO

/* ---------- 1.2 新增一名会员 ---------- */
PRINT N'【CRUD】1.2 CREATE —— 新增会员 DEMO-M1（初始积分 0）';
GO

INSERT INTO tbl_member (member_code, member_phone, member_name, register_date)
VALUES (N'DEMO-M1', N'13900000001', N'演示会员', '2026-10-04');

SELECT member_id, member_code, member_name, points_balance
FROM   tbl_member WHERE member_code = 'DEMO-M1';
GO

/* ---------- 1.3 新增一张券（演示"发放"，面值 5 元） ---------- */
PRINT N'【CRUD】1.3 CREATE —— 给会员发一张 5 元券 DEMO-CP1';
GO

INSERT INTO tbl_coupon
    (coupon_code, member_id, coupon_name, source, discount_amount, min_order_amount, valid_from, valid_to)
VALUES
    (N'DEMO-CP1',
     (SELECT member_id FROM tbl_member WHERE member_code = 'DEMO-M1'),
     N'5 元无门槛券', N'POINTS_EXCHANGE', 5.00, 0.00,
     '2026-10-04 00:00:00', '2026-11-04 23:59:59');

SELECT coupon_id, coupon_code, coupon_name, discount_amount, status
FROM   tbl_coupon WHERE coupon_code = 'DEMO-CP1';
GO

/* ---------- 1.4 新增原料 + 成品 + 配方 ---------- */
PRINT N'【CRUD】1.4 CREATE —— 新增原料 DEMO-I1 与成品 DEMO-P1（含配方）';
GO

INSERT INTO tbl_ingredient
    (ingredient_code, ingredient_name, unit, spec, qty_on_hand, reorder_point, target_level, moving_avg_cost)
VALUES
    (N'DEMO-I1', N'演示原料', N'g', N'1000g/袋', 5000.000, 1000.000, 5000.000, 0.0500);

-- 建立演示原料的期初建账流水（保持进销存台账绝对自洽）
INSERT INTO tbl_stock_ledger
    (ingredient_id, ledger_type, qty, ref_type, operator_id, remark)
VALUES
    ((SELECT ingredient_id FROM tbl_ingredient WHERE ingredient_code = 'DEMO-I1'),
     N'PURCHASE_IN', 5000.000, N'OPENING',
     (SELECT employee_id FROM tbl_employee WHERE employee_code = 'DEMO-E1'),
     N'演示原料期初建账');

INSERT INTO tbl_product (product_code, product_name, category_id, base_price, product_status)
VALUES (N'DEMO-P1', N'演示奶茶', 1, 12.00, N'ON_SALE');

-- 配方：中杯 + 全糖 用 200g 演示原料（其余规格暂不写，演示"按杯型/糖度取配方"）
INSERT INTO tbl_recipe (product_id, cup_spec_id, sugar_spec_id, ingredient_id, qty)
VALUES
    ((SELECT product_id    FROM tbl_product       WHERE product_code = 'DEMO-P1'),
     (SELECT spec_option_id FROM tbl_spec_option  WHERE spec_type='CUP'   AND spec_code='M'),
     (SELECT spec_option_id FROM tbl_spec_option  WHERE spec_type='SUGAR' AND spec_code='FULL'),
     (SELECT ingredient_id FROM tbl_ingredient    WHERE ingredient_code = 'DEMO-I1'),
     200.000);

SELECT p.product_code, p.product_name, i.ingredient_name, r.qty
FROM   tbl_recipe r
JOIN   tbl_product p    ON p.product_id    = r.product_id
JOIN   tbl_ingredient i ON i.ingredient_id = r.ingredient_id
WHERE  p.product_code = 'DEMO-P1';
GO

/* ---------- 1.5 ⭐ 开一张订单（订单头 + 明细 + 加料，事务） ---------- */
PRINT N'【CRUD】1.5 CREATE —— 开订单 DEMO-O1（2 杯「招牌柠檬水」中杯五分糖 + 加珍珠 1 份 + 用 5 元券）';
GO

BEGIN TRY
    BEGIN TRANSACTION;

        -- 订单头
        INSERT INTO tbl_order_header
            (order_no, business_date, pickup_no, member_id, coupon_id,
             discount_amount, amount_due, amount_paid,
             pay_method, pay_status, pay_time,
             order_status, cashier_id)
        VALUES
            (N'DEMO-O1', '2026-10-04',
             (SELECT ISNULL(MAX(pickup_no), 0) + 1 FROM tbl_order_header WHERE business_date = '2026-10-04'),
             (SELECT member_id FROM tbl_member WHERE member_code = 'DEMO-M1'),
             (SELECT coupon_id FROM tbl_coupon WHERE coupon_code = 'DEMO-CP1'),
             5.00,
             5.00,   -- 应收 = 10.00 小计 − 5.00 券
             5.00,   -- 实收
             N'CASH', N'SUCCESS', SYSDATETIME(),
             N'COMPLETED',
             (SELECT employee_id FROM tbl_employee WHERE employee_code = 'DEMO-E1'));

        -- 订单明细：P001 招牌柠檬水 ×2，中杯（+0）、五分糖、正常冰
        -- 成交单价快照 = 基础价 4.00 + 中杯加价 0.00；小计 = 2×4.00 + 加料 1×2.00 = 10.00
        INSERT INTO tbl_order_detail
            (order_id, line_no, product_id, qty, unit_price,
             cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
        VALUES
            ((SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O1'),
             1, 1, 2, 4.00,
             (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type='CUP'   AND spec_code='M'),
             (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type='SUGAR' AND spec_code='S50'),
             (SELECT spec_option_id FROM tbl_spec_option WHERE spec_type='ICE'   AND spec_code='NORMAL'),
             10.00);

        -- 加料：珍珠 1 份，加价快照 2.00
        INSERT INTO tbl_order_detail_topping (order_detail_id, topping_id, qty, unit_extra_price)
        VALUES
            ((SELECT TOP 1 order_detail_id FROM tbl_order_detail
               WHERE order_id = (SELECT order_id FROM tbl_order_header WHERE order_no='DEMO-O1')
               ORDER BY line_no),
             (SELECT topping_id FROM tbl_topping WHERE topping_code = 'TP01'),
             1, 2.00);

        -- 券核销
        UPDATE tbl_coupon
        SET    status = 'USED', used_time = SYSDATETIME()
        WHERE  coupon_code = 'DEMO-CP1';

    COMMIT TRANSACTION;
    PRINT N'    ✅ 订单已开：订单头 1 + 明细 1 + 加料 1，券已核销';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'    ❌ 开单失败：' + ERROR_MESSAGE();
END CATCH;
GO

/* ---------- 1.6 ⭐ 反冲倒扣：按配方扣总库 + 写流水 ---------- */
PRINT N'【CRUD】1.6 CREATE —— 反冲倒扣（按 订单明细 × 配方 扣总库，走"固定配方 + 加料"两路）';
GO

BEGIN TRY
    BEGIN TRANSACTION;

        -- ① 扣料：固定配方 + 加料，两路相加
        INSERT INTO tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, order_id, operator_id, remark)
        SELECT
            u.ingredient_id,
            N'SALES_USE',
            -u.total_qty,       -- 耗用为负
            N'ORDER',
            u.order_id,
            NULL,               -- NULL ＝ 系统自动反冲
            N'订单反冲扣料'
        FROM (
            -- 路一：固定配方
            SELECT d.order_id,
                   r.ingredient_id,
                   SUM(r.qty * d.qty) AS total_qty
            FROM   tbl_order_detail d
            JOIN   tbl_recipe r
                   ON  r.product_id    = d.product_id
                   AND r.cup_spec_id   = d.cup_spec_id
                   AND (r.sugar_spec_id = d.sugar_spec_id OR r.sugar_spec_id IS NULL)
            WHERE  d.order_id = (SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O1')
            GROUP BY d.order_id, r.ingredient_id

            UNION ALL

            -- 路二：加料
            SELECT d.order_id,
                   t.ingredient_id,
                   SUM(t.qty_per_serving * ot.qty) AS total_qty
            FROM   tbl_order_detail_topping ot
            JOIN   tbl_order_detail d ON d.order_detail_id = ot.order_detail_id
            JOIN   tbl_topping      t ON t.topping_id      = ot.topping_id
            WHERE  d.order_id = (SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O1')
            GROUP BY d.order_id, t.ingredient_id
        ) u;

        -- ② 扣减库存（若扣成负数，ck_ingredient_qty_on_hand 会直接拒绝 —— 这正是设计意图）
        UPDATE i
        SET    i.qty_on_hand = i.qty_on_hand + l.qty
        FROM   tbl_ingredient i
        JOIN   tbl_stock_ledger l ON l.ingredient_id = i.ingredient_id
        WHERE  l.order_id = (SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O1');

        -- ③ 积分累积：1 元 = 1 分
        INSERT INTO tbl_points_ledger (member_id, point_type, point_change, order_id)
        SELECT h.member_id, N'EARN', CAST(h.amount_paid AS INT), h.order_id
        FROM   tbl_order_header h
        WHERE  h.order_no = 'DEMO-O1';

        UPDATE m
        SET    m.points_balance = m.points_balance + CAST(h.amount_paid AS INT)
        FROM   tbl_member m
        JOIN   tbl_order_header h ON h.member_id = m.member_id
        WHERE  h.order_no = 'DEMO-O1';

    COMMIT TRANSACTION;
    PRINT N'    ✅ 反冲倒扣完成：已写库存流水并扣减总库，积分已累积';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'    ❌ 反冲失败：' + ERROR_MESSAGE();
END CATCH;
GO

PRINT N'    —— 扣料明细（两路相加）——';
GO

SELECT i.ingredient_code AS 原料, i.ingredient_name AS 名称,
       l.qty AS 变动量, i.qty_on_hand AS 现库存, l.ref_type AS 来源
FROM   tbl_stock_ledger l
JOIN   tbl_ingredient i ON i.ingredient_id = l.ingredient_id
WHERE  l.order_id = (SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O1')
ORDER BY i.ingredient_code;
GO

/* ---------- 1.7 ❌ 负例：4 类非法数据，全部应被数据库拒绝 ---------- */
PRINT N'【CRUD】1.7 CREATE 负例 —— 故意插入非法数据，验证约束生效（应当全部失败）';
GO

DECLARE @err NVARCHAR(400);

-- 负例 1：库存为负 → CHECK (qty_on_hand >= 0) 拒绝
BEGIN TRY
    INSERT INTO tbl_ingredient (ingredient_code, ingredient_name, unit, qty_on_hand)
    VALUES (N'DEMO-BAD1', N'负库存测试', N'g', -1);
    PRINT N'    ❌ 负例1 居然成功了（约束没生效！）';
END TRY
BEGIN CATCH
    PRINT N'    ✅ 负例1 被拒绝（ck_ingredient_qty_on_hand）：' + ERROR_MESSAGE();
END CATCH;

-- 负例 2：非法枚举 → 域 CHECK 拒绝
BEGIN TRY
    INSERT INTO tbl_employee (employee_code, employee_name, position, hire_date)
    VALUES (N'DEMO-BAD2', N'非法岗位', N'BOSS', '2026-10-04');
    PRINT N'    ❌ 负例2 居然成功了（约束没生效！）';
END TRY
BEGIN CATCH
    PRINT N'    ✅ 负例2 被拒绝（ck_employee_position）：' + ERROR_MESSAGE();
END CATCH;

-- 负例 3：引用不存在的商品 → FK 拒绝
BEGIN TRY
    INSERT INTO tbl_recipe (product_id, cup_spec_id, sugar_spec_id, ingredient_id, qty)
    VALUES (999999, 1, NULL, 1, 10);
    PRINT N'    ❌ 负例3 居然成功了（外键没生效！）';
END TRY
BEGIN CATCH
    PRINT N'    ✅ 负例3 被拒绝（fk_recipe_product）：' + ERROR_MESSAGE();
END CATCH;

-- 负例 4：业务码重复 → 候选码 UNIQUE 拒绝
BEGIN TRY
    INSERT INTO tbl_member (member_code, member_phone, member_name, register_date)
    VALUES (N'DEMO-M1', N'13900000002', N'重复会员号', '2026-10-04');
    PRINT N'    ❌ 负例4 居然成功了（候选码没生效！）';
END TRY
BEGIN CATCH
    PRINT N'    ✅ 负例4 被拒绝（uq_member_code）：' + ERROR_MESSAGE();
END CATCH;

-- 负例 5：流水来源与真外键不一致 → ck_stock_ledger_ref_consistency 拒绝（D-09）
BEGIN TRY
    INSERT INTO tbl_stock_ledger (ingredient_id, ledger_type, qty, ref_type, order_id)
    VALUES (1, N'PURCHASE_IN', 100, N'PURCHASE', 1);   -- 说自己是采购，却填了订单号
    PRINT N'    ❌ 负例5 居然成功了（判别列一致性没生效！）';
END TRY
BEGIN CATCH
    PRINT N'    ✅ 负例5 被拒绝（ck_stock_ledger_ref_consistency）：' + ERROR_MESSAGE();
END CATCH;
GO

/* ============================================================
 * 2. READ（查）
 * ============================================================ */

/* ---------- 2.1 商品菜单（带品类） ---------- */
PRINT N'【CRUD】2.1 READ —— 演示成品与它的品类';
GO

SELECT TOP 5
       p.product_code AS 编号, p.product_name AS 成品,
       c.category_name AS 品类, p.base_price AS 中杯价, p.product_status AS 状态
FROM   tbl_product p
JOIN   tbl_product_category c ON c.category_id = p.category_id
WHERE  p.product_code LIKE 'DEMO%' OR p.product_id <= 3
ORDER BY p.product_code;
GO

/* ---------- 2.2 会员的订单历史 + 积分 ---------- */
PRINT N'【CRUD】2.2 READ —— 演示会员的订单历史与积分';
GO

SELECT h.order_no AS 订单号, h.business_date AS 营业日,
       h.amount_due AS 应收, h.amount_paid AS 实收,
       h.order_status AS 状态, h.pay_method AS 支付
FROM   tbl_order_header h
JOIN   tbl_member m ON m.member_id = h.member_id
WHERE  m.member_code = 'DEMO-M1';

SELECT m.member_code AS 会员, m.points_balance AS 当前积分,
       p.point_type AS 类型, p.point_change AS 变动, p.change_time AS 时间
FROM   tbl_member m
LEFT JOIN tbl_points_ledger p ON p.member_id = m.member_id
WHERE  m.member_code = 'DEMO-M1';
GO

/* ---------- 2.3 订单全貌（头 + 明细 + 加料 + 支付） ---------- */
PRINT N'【CRUD】2.3 READ —— 演示订单全貌（多表连接）';
GO

SELECT h.order_no AS 订单号, d.line_no AS 行号,
       p.product_name AS 成品, d.qty AS 数量,
       cs.spec_name AS 杯型, ss.spec_name AS 糖度, ts.spec_name AS 冰量,
       d.unit_price AS 单价, d.subtotal AS 小计,
       tp.topping_name AS 加料, ot.qty AS 份数, ot.unit_extra_price AS 加料价,
       h.discount_amount AS 券抵扣, h.amount_due AS 应收, h.amount_paid AS 实收
FROM   tbl_order_header h
JOIN   tbl_order_detail d       ON d.order_id        = h.order_id
JOIN   tbl_product p            ON p.product_id      = d.product_id
LEFT JOIN tbl_spec_option cs    ON cs.spec_option_id = d.cup_spec_id
LEFT JOIN tbl_spec_option ss    ON ss.spec_option_id = d.sugar_spec_id
LEFT JOIN tbl_spec_option ts    ON ts.spec_option_id = d.ice_spec_id
LEFT JOIN tbl_order_detail_topping ot ON ot.order_detail_id = d.order_detail_id
LEFT JOIN tbl_topping tp        ON tp.topping_id     = ot.topping_id
WHERE  h.order_no = 'DEMO-O1';
GO

/* ---------- 2.4 ⭐ "还能做几杯"（库存 ÷ 配方） ---------- */
PRINT N'【CRUD】2.4 READ —— "还能做几杯"：库存 ÷ 配方（week1 §4.2 #1 保留的视图素材）';
GO

SELECT TOP 8
       p.product_code AS 编号, p.product_name AS 成品,
       cs.spec_name AS 杯型,
       MIN(FLOOR(i.qty_on_hand / r.qty)) AS 还能做几杯
FROM   tbl_recipe r
JOIN   tbl_product       p  ON p.product_id      = r.product_id
JOIN   tbl_ingredient    i  ON i.ingredient_id   = r.ingredient_id
JOIN   tbl_spec_option   cs ON cs.spec_option_id = r.cup_spec_id
WHERE  r.qty > 0
GROUP BY p.product_code, p.product_name, cs.spec_name
ORDER BY 还能做几杯 DESC;
GO

/* ---------- 2.5 ⭐ 台账：按流水类型汇总 + 反推期初 ---------- */
PRINT N'【CRUD】2.5 READ —— 库存台账：按类型汇总流水，并反推期初库存';
GO

-- 恒等式：期初 = 期末（当前库存） − Σ流水
--    其中 Σ流水 = 采购入库(+) + 销售耗用(−) + 报损(−)
SELECT TOP 8
       i.ingredient_code AS 原料,
       i.ingredient_name AS 名称,
       ISNULL(SUM(CASE WHEN l.ledger_type = 'PURCHASE_IN' THEN l.qty END), 0) AS 采购入库,
       ISNULL(SUM(CASE WHEN l.ledger_type = 'SALES_USE'   THEN l.qty END), 0) AS 销售耗用,
       ISNULL(SUM(CASE WHEN l.ledger_type = 'LOSS'        THEN l.qty END), 0) AS 报损,
       i.qty_on_hand                                                          AS 期末库存,
       i.qty_on_hand - ISNULL(SUM(l.qty), 0)                                  AS 反推期初
FROM   tbl_ingredient  i
LEFT JOIN tbl_stock_ledger l ON l.ingredient_id = i.ingredient_id
GROUP BY i.ingredient_code, i.ingredient_name, i.qty_on_hand
ORDER BY i.ingredient_code;
GO

/* ============================================================
 * 3. UPDATE（改）
 * ============================================================ */

/* ---------- 3.1 商品调价 ---------- */
PRINT N'【CRUD】3.1 UPDATE —— 演示奶茶从 12.00 调到 13.00';
GO

UPDATE tbl_product SET base_price = 13.00 WHERE product_code = 'DEMO-P1';

SELECT product_code AS 编号, product_name AS 成品, base_price AS 现价
FROM   tbl_product WHERE product_code = 'DEMO-P1';
GO

/* ---------- 3.2 商品下架（改状态，不删行 —— 历史订单不受影响） ---------- */
PRINT N'【CRUD】3.2 UPDATE —— 下架演示奶茶（改状态而不是删行）';
GO

UPDATE tbl_product SET product_status = N'OFF_SALE' WHERE product_code = 'DEMO-P1';

SELECT product_code AS 编号, product_name AS 成品, product_status AS 状态
FROM   tbl_product WHERE product_code = 'DEMO-P1';

PRINT N'    —— 下架后，历史订单明细仍然完好（这正是"不删行"的理由）——';
GO

SELECT h.order_no AS 订单号, d.line_no AS 行号,
       p.product_name AS 成品, d.qty AS 数量, h.order_status AS 订单状态
FROM   tbl_order_detail d
JOIN   tbl_order_header h ON h.order_id   = d.order_id
JOIN   tbl_product      p ON p.product_id = d.product_id
WHERE  p.product_code = 'DEMO-P1';
GO

/* ---------- 3.3 订单状态流转（6 态状态机） ---------- */
PRINT N'【CRUD】3.3 UPDATE —— 订单状态流转 PENDING → MAKING → READY → COMPLETED';
GO

DECLARE @oid INT = (SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O2');

-- 先造一张"正在制作中"的订单用于演示状态机
INSERT INTO tbl_order_header
    (order_no, business_date, pickup_no, amount_due, amount_paid,
     pay_method, pay_status, pay_time, order_status, cashier_id)
VALUES
    (N'DEMO-O2', '2026-10-04',
     (SELECT ISNULL(MAX(pickup_no), 0) + 1 FROM tbl_order_header WHERE business_date = '2026-10-04'),
     4.00, 4.00, N'CASH', N'SUCCESS', SYSDATETIME(), N'PENDING',
     (SELECT employee_id FROM tbl_employee WHERE employee_code = 'DEMO-E1'));

SELECT order_no AS 订单号, order_status AS 状态 FROM tbl_order_header WHERE order_no = 'DEMO-O2';

UPDATE tbl_order_header SET order_status = N'MAKING'    WHERE order_no = 'DEMO-O2';
SELECT order_no AS 订单号, order_status AS 状态 FROM tbl_order_header WHERE order_no = 'DEMO-O2';

UPDATE tbl_order_header SET order_status = N'READY'     WHERE order_no = 'DEMO-O2';
SELECT order_no AS 订单号, order_status AS 状态 FROM tbl_order_header WHERE order_no = 'DEMO-O2';

UPDATE tbl_order_header
SET    order_status = N'COMPLETED', finish_time = SYSDATETIME()
WHERE  order_no = 'DEMO-O2';
SELECT order_no AS 订单号, order_status AS 状态, finish_time AS 完成时间
FROM   tbl_order_header WHERE order_no = 'DEMO-O2';
GO

/* ---------- 3.4 ⭐ 采购收货：库存增加 + 移动加权成本重算 ---------- */
PRINT N'【CRUD】3.4 UPDATE —— 采购收货：库存增加，移动加权成本重算';
GO

BEGIN TRY
    BEGIN TRANSACTION;

        -- 先看收货前
        SELECT i.ingredient_code AS 原料, i.qty_on_hand AS 收货前库存, i.moving_avg_cost AS 收货前成本
        FROM   tbl_ingredient i WHERE i.ingredient_code = 'DEMO-I1';

        -- 造一张采购单 + 明细（订购 2000g，实收 2000g，单价 0.0600）
        INSERT INTO tbl_purchase_order
            (purchase_no, supplier_id, order_date, order_status, ordered_by)
        VALUES
            (N'DEMO-PO1',
             (SELECT supplier_id FROM tbl_supplier WHERE is_active = 1 ORDER BY supplier_id OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY),
             '2026-10-04', N'ARRIVED',
             (SELECT employee_id FROM tbl_employee WHERE employee_code = 'DEMO-E1'));

        INSERT INTO tbl_purchase_order_detail
            (purchase_order_id, ingredient_id, qty_ordered, qty_received, unit_price)
        VALUES
            ((SELECT purchase_order_id FROM tbl_purchase_order WHERE purchase_no = 'DEMO-PO1'),
             (SELECT ingredient_id FROM tbl_ingredient WHERE ingredient_code = 'DEMO-I1'),
             2000.000, 2000.000, 0.0600);

        -- 写采购入库流水
        INSERT INTO tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, purchase_order_id, operator_id, remark)
        VALUES
            ((SELECT ingredient_id FROM tbl_ingredient WHERE ingredient_code = 'DEMO-I1'),
             N'PURCHASE_IN', 2000.000, N'PURCHASE',
             (SELECT purchase_order_id FROM tbl_purchase_order WHERE purchase_no = 'DEMO-PO1'),
             (SELECT employee_id FROM tbl_employee WHERE employee_code = 'DEMO-E1'),
             N'采购入库');

        -- 库存增加 + 移动加权成本重算
        --   新成本 = (旧库存×旧成本 + 本次入库量×本次单价) / (旧库存 + 本次入库量)
        --   （带除零防御：若总入库与现库存为 0，保持原成本，杜绝击穿 NOT NULL）
        UPDATE i
        SET    i.moving_avg_cost = CASE 
                   WHEN (i.qty_on_hand + d.qty_received) > 0 
                   THEN (i.qty_on_hand * i.moving_avg_cost + d.qty_received * d.unit_price) / (i.qty_on_hand + d.qty_received)
                   ELSE i.moving_avg_cost 
               END,
               i.qty_on_hand = i.qty_on_hand + d.qty_received
        FROM   tbl_ingredient i
        JOIN   tbl_purchase_order_detail d ON d.ingredient_id = i.ingredient_id
        JOIN   tbl_purchase_order       o ON o.purchase_order_id = d.purchase_order_id
        WHERE  o.purchase_no = 'DEMO-PO1';

        COMMIT TRANSACTION;
        PRINT N'    ✅ 收货完成';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'    ❌ 收货失败：' + ERROR_MESSAGE();
END CATCH;
GO

SELECT i.ingredient_code AS 原料, i.qty_on_hand AS 收货后库存,
       i.moving_avg_cost AS 收货后成本
FROM   tbl_ingredient i WHERE i.ingredient_code = 'DEMO-I1';
GO

/* ---------- 3.5 沽清标记（料有，但现在做不了） ---------- */
PRINT N'【CRUD】3.5 UPDATE —— 把珍珠标为沽清（"料有、但现在做不了"）';
GO

UPDATE tbl_ingredient SET is_sold_out = 1 WHERE ingredient_code = 'I017';   -- 珍珠（生）

SELECT ingredient_code AS 原料, ingredient_name AS 名称,
       qty_on_hand AS 库存, is_sold_out AS 沽清
FROM   tbl_ingredient WHERE ingredient_code = 'I017';

-- 演示完恢复
UPDATE tbl_ingredient SET is_sold_out = 0 WHERE ingredient_code = 'I017';
GO

/* ---------- 3.6 ⭐ 取消订单：退库存 + 退积分 + 退券 ---------- */
PRINT N'【CRUD】3.6 UPDATE —— 取消订单 DEMO-O1：三样东西都要退回去';
GO

BEGIN TRY
    BEGIN TRANSACTION;

        -- ① 退券（D-11b）
        UPDATE tbl_coupon
        SET    status = 'UNUSED', used_time = NULL
        WHERE  coupon_id = (SELECT coupon_id FROM tbl_order_header WHERE order_no = 'DEMO-O1');

        -- ② 退积分：写一条 REDEEM 反向流水，并把余额减回去
        INSERT INTO tbl_points_ledger (member_id, point_type, point_change, order_id, coupon_id)
        SELECT h.member_id, N'REDEEM', -CAST(h.amount_paid AS INT), h.order_id, h.coupon_id
        FROM   tbl_order_header h
        WHERE  h.order_no = 'DEMO-O1';

        UPDATE m
        SET    m.points_balance = m.points_balance - CAST(h.amount_paid AS INT)
        FROM   tbl_member m
        JOIN   tbl_order_header h ON h.member_id = m.member_id
        WHERE  h.order_no = 'DEMO-O1';

        -- ③ 退库存：把该订单的销售耗用**反向冲回**
        --    ⚠️ 注意是"**写一条反向流水**"，而不是删掉原流水 —— 流水表只增不改。
        --    方向：原 SALES_USE 的 qty 是负数，取反后就是正数（回冲入库）。
        --
        --    📌 v0.1 的一个已知限制：流水类型只有 3 类（PURCHASE_IN / SALES_USE / LOSS），
        --       "取消回冲"这类**正向调整**只能借用 PURCHASE_IN 表达；ref_type 仍用 ORDER
        --       以保持"能追溯到订单"。v1.0 补上 STOCKTAKE 后才会有专门的调整类型。
        INSERT INTO tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, order_id, operator_id, remark)
        SELECT l.ingredient_id,
               N'PURCHASE_IN',
               -l.qty,                       -- 取反：负 → 正
               N'ORDER',                     -- 仍可追溯到这张订单
               l.order_id,
               (SELECT employee_id FROM tbl_employee WHERE employee_code = 'DEMO-E1'),
               N'订单取消回冲'
        FROM   tbl_stock_ledger l
        WHERE  l.order_id = (SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O1')
          AND  l.ledger_type = N'SALES_USE';

        -- 库存加回去（用刚写入的那条回冲流水，严格限定当前订单并聚合，杜绝多对一非确定性覆盖）
        UPDATE i
        SET    i.qty_on_hand = i.qty_on_hand + r.total_return_qty
        FROM   tbl_ingredient i
        JOIN (
            SELECT ingredient_id, SUM(qty) AS total_return_qty
            FROM   tbl_stock_ledger
            WHERE  order_id = (SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O1')
              AND  remark   = N'订单取消回冲'
            GROUP BY ingredient_id
        ) r ON r.ingredient_id = i.ingredient_id;

        -- ④ 订单改状态（不删行）
        UPDATE tbl_order_header SET order_status = N'CANCELLED' WHERE order_no = 'DEMO-O1';

        COMMIT TRANSACTION;
        PRINT N'    ✅ 取消完成：券已退回、积分已回滚、库存已回冲、订单状态改为 CANCELLED';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'    ❌ 取消失败：' + ERROR_MESSAGE();
END CATCH;
GO

SELECT order_no AS 订单号, order_status AS 状态, coupon_id AS 券 FROM tbl_order_header WHERE order_no = 'DEMO-O1';
SELECT coupon_code AS 券号, status AS 状态, used_time AS 核销时间 FROM tbl_coupon WHERE coupon_code = 'DEMO-CP1';
SELECT member_code AS 会员, points_balance AS 积分余额 FROM tbl_member WHERE member_code = 'DEMO-M1';
GO

/* ============================================================
 * 4. DELETE（删）
 * ============================================================ */

/* ---------- 4.1 删除一条无引用的数据（应当成功） ---------- */
PRINT N'【CRUD】4.1 DELETE —— 删除无任何引用的演示会员（应当成功）';
GO

INSERT INTO tbl_member (member_code, member_phone, member_name, register_date)
VALUES (N'DEMO-M9', N'13900000009', N'待删除会员', '2026-10-04');

DELETE FROM tbl_member WHERE member_code = 'DEMO-M9';
PRINT N'    ✅ 已删除（无外键引用）';
GO

/* ---------- 4.2 ❌ 删除有引用的数据（应当失败） ---------- */
PRINT N'【CRUD】4.2 DELETE 负例 —— 删除有订单引用的商品（应当失败）';
GO

BEGIN TRY
    DELETE FROM tbl_product WHERE product_code = 'DEMO-P1';
    PRINT N'    ❌ 居然删掉了（外键没起保护作用！）';
END TRY
BEGIN CATCH
    PRINT N'    ✅ 删除被拒绝（fk_recipe_product / 订单引用）：' + ERROR_MESSAGE();
    PRINT N'       → 这就是"**下架用状态、不删行**"的技术理由：历史订单不能被删掉。';
END CATCH;
GO

/* ============================================================
 * 5. 收尾：库存核对与兜底回滚
 *
 *    演示过程中真的改动过库存。**正常情况下不需要这一步** ——
 *    因为 3.6 的"取消订单"已经用**反向流水**把料冲回去了，
 *    台账的恒等关系仍然成立。
 *
 *    这一步是**兜底**：拿开头拍的快照核对一遍，若有偏差就修正，
 *    保证脚本可以反复执行而不会让库存慢慢漂移。
 * ============================================================ */

PRINT N'【CRUD】步骤 5 库存核对（对照脚本开始前的快照）';
GO

SELECT COUNT(*) AS 与快照不一致的原料数
FROM   tbl_ingredient i
JOIN   #inv_snapshot  s ON s.ingredient_id = i.ingredient_id
WHERE  i.qty_on_hand <> s.qty_on_hand;
GO

UPDATE i
SET    i.qty_on_hand = s.qty_on_hand
FROM   tbl_ingredient i
JOIN   #inv_snapshot  s ON s.ingredient_id = i.ingredient_id;

PRINT N'    ✅ 已按快照对齐（若上面显示 0，说明正常路径本身就是干净的）。';
PRINT N'';
PRINT N'【CRUD】完成。';
PRINT N'';
PRINT N'  · 本脚本**保留**演示数据（DEMO- 前缀），便于现场观察结果。';
PRINT N'  · 再次执行时会自动清理上次残留，因此可反复运行。';
PRINT N'  · 如需彻底恢复到干净状态，请重跑 99-rebuild.sql。';
GO
