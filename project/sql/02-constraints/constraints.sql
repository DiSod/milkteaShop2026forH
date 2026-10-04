/* ============================================================
 * 脚本：constraints.sql
 * 用途：为 17 张表添加【候选码 UNIQUE】+【域/值域 CHECK】+【外键 FK】
 * 依赖：01-schema/create-tables.sql
 * 阶段：第 4 周（课程"主外键 / 检查约束"任务）
 * 作者：DiSod
 * 日期：2026-10-04
 * 幂等：是 —— 先删除同名约束再添加
 * ============================================================
 *
 * 【真相源】
 *   project/docs/data-dictionary.md 第一节（域字典）+ 第三节（码标注汇总）
 *
 * 【为什么约束单独一个脚本】
 *   课程第 4 周的任务正是"主外键 / 检查约束"。
 *   拆开后：第 3 周建表（01-schema），第 4 周加约束（本脚本），
 *   演示时可以说清"约束是在表建好之后加上去的"。
 *
 * 【本脚本的四类约束】
 *   一、候选码 UNIQUE   —— 17 个（其中 6 个是复合候选码）
 *   二、域约束 CHECK    —— 15 个（域字典 DOM-01 ~ DOM-15）
 *   三、值域约束 CHECK  —— 非负 / 大于 0 / 不等于 0
 *   四、跨列约束 CHECK  —— 日期先后、金额口径、流水来源一致性
 *   五、外键 FK         —— 30 个
 *
 * 【执行方式】
 *   sqlcmd -S .\SQLEXPRESS -E -i project/sql/02-constraints/constraints.sql
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* ============================================================
 * 幂等处理：先删除本脚本负责的三类约束（FK / CHECK / UNIQUE）
 * 保留 PK 与 DEFAULT —— 它们属于表结构，由 01-schema 负责。
 * ============================================================ */
DECLARE @drop_existing NVARCHAR(MAX) = N'';

SELECT @drop_existing = @drop_existing
                      + N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id))
                      + N'.' + QUOTENAME(OBJECT_NAME(parent_object_id))
                      + N' DROP CONSTRAINT ' + QUOTENAME(name) + N';' + CHAR(13)
FROM sys.objects
WHERE type IN ('F', 'C', 'UQ')     -- 外键 / 检查 / 唯一
  AND is_ms_shipped = 0
  AND parent_object_id IN (SELECT object_id
                           FROM sys.tables WHERE name LIKE N'tbl[_]%');

IF LEN(@drop_existing) > 0
BEGIN
    PRINT N'【约束】清理既有 FK / CHECK / UNIQUE ...';
    EXEC sp_executesql @drop_existing;
END
GO

PRINT N'【约束】开始添加候选码 / CHECK / 外键 ...';
GO

/* ============================================================
 * 一、候选码（UNIQUE）—— 17 个
 *
 * 说明：主码是代理键（系统自增），业务码作 UNIQUE 候选码。
 *       这正是课程那句"主码是选出来做标识的，候选码是其他也能唯一标识的"。
 * ============================================================ */

-- 1  tbl_employee
ALTER TABLE tbl_employee
    ADD CONSTRAINT uq_employee_code UNIQUE (employee_code);

-- 2  tbl_member（两个候选码）
ALTER TABLE tbl_member
    ADD CONSTRAINT uq_member_code  UNIQUE (member_code);
ALTER TABLE tbl_member
    ADD CONSTRAINT uq_member_phone UNIQUE (member_phone);

-- 3  tbl_product_category
ALTER TABLE tbl_product_category
    ADD CONSTRAINT uq_product_category_code UNIQUE (category_code);

-- 4  tbl_spec_option（复合候选码）
ALTER TABLE tbl_spec_option
    ADD CONSTRAINT uq_spec_option_type_code UNIQUE (spec_type, spec_code);

-- 5  tbl_ingredient
ALTER TABLE tbl_ingredient
    ADD CONSTRAINT uq_ingredient_code UNIQUE (ingredient_code);

-- 6  tbl_supplier
ALTER TABLE tbl_supplier
    ADD CONSTRAINT uq_supplier_code UNIQUE (supplier_code);

-- 7  tbl_product
ALTER TABLE tbl_product
    ADD CONSTRAINT uq_product_code UNIQUE (product_code);

-- 8  tbl_topping
ALTER TABLE tbl_topping
    ADD CONSTRAINT uq_topping_code UNIQUE (topping_code);

-- 9  tbl_recipe（4 列复合候选码）
--    ⚠️ sugar_spec_id 为 NULL 表示"该原料用量与糖度无关"。
--       SQL Server 的 UNIQUE 把 NULL 视为相等，所以同 (成品,杯型,原料) 在"与糖度无关"时只允许一行 ——
--       唯一性照样成立（D-05a）。这是本库最有讲头的一条约束。
ALTER TABLE tbl_recipe
    ADD CONSTRAINT uq_recipe_product_cup_sugar_ingredient
        UNIQUE (product_id, cup_spec_id, sugar_spec_id, ingredient_id);

-- 10 tbl_purchase_order
ALTER TABLE tbl_purchase_order
    ADD CONSTRAINT uq_purchase_order_no UNIQUE (purchase_no);

-- 11 tbl_purchase_order_detail（复合候选码）
ALTER TABLE tbl_purchase_order_detail
    ADD CONSTRAINT uq_purchase_order_detail_order_ingredient
        UNIQUE (purchase_order_id, ingredient_id);

-- 12 tbl_coupon
ALTER TABLE tbl_coupon
    ADD CONSTRAINT uq_coupon_code UNIQUE (coupon_code);

-- 13 tbl_order_header（两个候选码）
ALTER TABLE tbl_order_header
    ADD CONSTRAINT uq_order_header_no UNIQUE (order_no);
--    取餐号按日重置，所以候选码要带上营业日
ALTER TABLE tbl_order_header
    ADD CONSTRAINT uq_order_header_business_date_pickup_no
        UNIQUE (business_date, pickup_no);

-- 14 tbl_order_detail（复合候选码）
ALTER TABLE tbl_order_detail
    ADD CONSTRAINT uq_order_detail_order_line UNIQUE (order_id, line_no);

-- 15 tbl_order_detail_topping（复合候选码）
ALTER TABLE tbl_order_detail_topping
    ADD CONSTRAINT uq_order_detail_topping_detail_topping
        UNIQUE (order_detail_id, topping_id);

-- 16 / 17  tbl_points_ledger、tbl_stock_ledger
--     ⚠️ 流水表**没有候选码** —— 按时间追加，没有业务唯一标识。
--        这不是遗漏，是流水表的固有性质。
GO

PRINT N'【约束】候选码 17 个已添加。';
GO

/* ============================================================
 * 二、域约束（CHECK）—— 域字典 DOM-01 ~ DOM-15
 * ============================================================ */

-- DOM-01 岗位
ALTER TABLE tbl_employee
    ADD CONSTRAINT ck_employee_position
        CHECK (position IN ('MANAGER','CASHIER','MAKER','STOCKER'));

-- DOM-02 商品状态
ALTER TABLE tbl_product
    ADD CONSTRAINT ck_product_product_status
        CHECK (product_status IN ('ON_SALE','OFF_SALE'));

-- DOM-03 订单状态（6 态）
ALTER TABLE tbl_order_header
    ADD CONSTRAINT ck_order_header_order_status
        CHECK (order_status IN ('PENDING','MAKING','READY','COMPLETED','ABANDONED','CANCELLED'));

-- DOM-04 库存流水类型
ALTER TABLE tbl_stock_ledger
    ADD CONSTRAINT ck_stock_ledger_ledger_type
        CHECK (ledger_type IN ('PURCHASE_IN','SALES_USE','LOSS'));

-- DOM-05 流水来源
ALTER TABLE tbl_stock_ledger
    ADD CONSTRAINT ck_stock_ledger_ref_type
        CHECK (ref_type IN ('PURCHASE','ORDER','MANUAL','OPENING'));

-- DOM-06 支付方式（可空：订单可能尚未支付）
ALTER TABLE tbl_order_header
    ADD CONSTRAINT ck_order_header_pay_method
        CHECK (pay_method IS NULL OR pay_method IN ('CASH','WECHAT','ALIPAY','CARD'));

-- DOM-07 券来源
ALTER TABLE tbl_coupon
    ADD CONSTRAINT ck_coupon_source
        CHECK (source IN ('POINTS_EXCHANGE','CAMPAIGN'));

-- DOM-08 券状态
ALTER TABLE tbl_coupon
    ADD CONSTRAINT ck_coupon_status
        CHECK (status IN ('UNUSED','USED','EXPIRED'));

-- DOM-09 积分流水类型
ALTER TABLE tbl_points_ledger
    ADD CONSTRAINT ck_points_ledger_point_type
        CHECK (point_type IN ('EARN','REDEEM'));

-- DOM-10 规格类型
ALTER TABLE tbl_spec_option
    ADD CONSTRAINT ck_spec_option_spec_type
        CHECK (spec_type IN ('CUP','SUGAR','ICE'));

-- DOM-11 / DOM-12 / DOM-13  规格代码
--     ⚠️ 这是**跨列** CHECK：spec_code 的合法集合**取决于 spec_type**。
--        SQL Server 没有"条件域"语法，所以三种维度合成一条 CHECK 表达。
--     ⚠️ 糖度里**没有 'ANY'** —— "与糖度无关"由 tbl_recipe.sugar_spec_id IS NULL 表达（D-05a）。
ALTER TABLE tbl_spec_option
    ADD CONSTRAINT ck_spec_option_code_by_type
        CHECK (
               (spec_type = 'CUP'   AND spec_code IN ('M','L'))
            OR (spec_type = 'SUGAR' AND spec_code IN ('NONE','S30','S50','S70','FULL'))
            OR (spec_type = 'ICE'   AND spec_code IN ('NO_ICE','LESS','NORMAL','HOT'))
        );

-- DOM-14 采购单状态
ALTER TABLE tbl_purchase_order
    ADD CONSTRAINT ck_purchase_order_order_status
        CHECK (order_status IN ('ORDERED','ARRIVED','ACCEPTED','PARTIAL','CANCELLED'));

-- DOM-15 支付状态（可空）
ALTER TABLE tbl_order_header
    ADD CONSTRAINT ck_order_header_pay_status
        CHECK (pay_status IS NULL OR pay_status IN ('SUCCESS','FAILED'));

-- DOM-16 盘点单状态：⏸ v1.0 才有 tbl_stocktake，本阶段不加。
GO

PRINT N'【约束】域约束已添加 —— 15 个域（DOM-01 ~ DOM-15）合成为 13 条 CHECK（DOM-11/12/13 三种规格维度合成一条）。';
GO

/* ============================================================
 * 三、值域约束（CHECK）—— 非负 / 大于 0 / 不等于 0
 * ============================================================ */

-- ⭐ 本库最硬的一条：库存**结构上不允许为负**
--    它把 week1 反复强调的"库存必须真实"变成数据库层面的强制保证（D-03 / D-12）。
ALTER TABLE tbl_ingredient
    ADD CONSTRAINT ck_ingredient_qty_on_hand
        CHECK (qty_on_hand >= 0);

ALTER TABLE tbl_ingredient
    ADD CONSTRAINT ck_ingredient_reorder_point
        CHECK (reorder_point >= 0);

ALTER TABLE tbl_ingredient
    ADD CONSTRAINT ck_ingredient_target_level
        CHECK (target_level >= 0);

ALTER TABLE tbl_ingredient
    ADD CONSTRAINT ck_ingredient_moving_avg_cost
        CHECK (moving_avg_cost >= 0);

-- 积分余额非负（冗余字段，一致性由事务维护）
ALTER TABLE tbl_member
    ADD CONSTRAINT ck_member_points_balance
        CHECK (points_balance >= 0);

-- 金额非负
ALTER TABLE tbl_product
    ADD CONSTRAINT ck_product_base_price
        CHECK (base_price >= 0);

ALTER TABLE tbl_spec_option
    ADD CONSTRAINT ck_spec_option_extra_price
        CHECK (extra_price >= 0);

ALTER TABLE tbl_topping
    ADD CONSTRAINT ck_topping_extra_price
        CHECK (extra_price >= 0);

ALTER TABLE tbl_topping
    ADD CONSTRAINT ck_topping_qty_per_serving
        CHECK (qty_per_serving > 0);

-- 配方用量必须为正
ALTER TABLE tbl_recipe
    ADD CONSTRAINT ck_recipe_qty
        CHECK (qty > 0);

-- 订单明细
ALTER TABLE tbl_order_detail
    ADD CONSTRAINT ck_order_detail_qty
        CHECK (qty > 0);

ALTER TABLE tbl_order_detail
    ADD CONSTRAINT ck_order_detail_unit_price
        CHECK (unit_price >= 0);

ALTER TABLE tbl_order_detail
    ADD CONSTRAINT ck_order_detail_subtotal
        CHECK (subtotal >= 0);

ALTER TABLE tbl_order_detail_topping
    ADD CONSTRAINT ck_order_detail_topping_qty
        CHECK (qty > 0);

ALTER TABLE tbl_order_detail_topping
    ADD CONSTRAINT ck_order_detail_topping_unit_extra_price
        CHECK (unit_extra_price >= 0);

-- 订单头金额
ALTER TABLE tbl_order_header
    ADD CONSTRAINT ck_order_header_discount_amount
        CHECK (discount_amount >= 0);

ALTER TABLE tbl_order_header
    ADD CONSTRAINT ck_order_header_amount_due
        CHECK (amount_due >= 0);

ALTER TABLE tbl_order_header
    ADD CONSTRAINT ck_order_header_amount_paid
        CHECK (amount_paid >= 0);

-- 券
ALTER TABLE tbl_coupon
    ADD CONSTRAINT ck_coupon_discount_amount
        CHECK (discount_amount > 0);

ALTER TABLE tbl_coupon
    ADD CONSTRAINT ck_coupon_min_order_amount
        CHECK (min_order_amount >= 0);

-- 采购单明细
ALTER TABLE tbl_purchase_order_detail
    ADD CONSTRAINT ck_purchase_order_detail_qty_ordered
        CHECK (qty_ordered > 0);

ALTER TABLE tbl_purchase_order_detail
    ADD CONSTRAINT ck_purchase_order_detail_qty_received
        CHECK (qty_received >= 0);

ALTER TABLE tbl_purchase_order_detail
    ADD CONSTRAINT ck_purchase_order_detail_unit_price
        CHECK (unit_price >= 0);

-- 流水数量与积分变动值：**正负号区分增减，所以不能为 0**
ALTER TABLE tbl_stock_ledger
    ADD CONSTRAINT ck_stock_ledger_qty_nonzero
        CHECK (qty <> 0);

ALTER TABLE tbl_points_ledger
    ADD CONSTRAINT ck_points_ledger_change_nonzero
        CHECK (point_change <> 0);
GO

PRINT N'【约束】值域 CHECK 已添加。';
GO

/* ============================================================
 * 四、跨列约束（CHECK）
 * ============================================================ */

-- 完成时间不能早于下单时间（未完成时为 NULL）
ALTER TABLE tbl_order_header
    ADD CONSTRAINT ck_order_header_finish_time
        CHECK (finish_time IS NULL OR finish_time >= order_time);

-- 到货日不能早于下单日（未到货时为 NULL）
ALTER TABLE tbl_purchase_order
    ADD CONSTRAINT ck_purchase_order_arrival_date
        CHECK (arrival_date IS NULL OR arrival_date >= order_date);

-- 券的失效时间必须晚于生效时间
ALTER TABLE tbl_coupon
    ADD CONSTRAINT ck_coupon_valid_period
        CHECK (valid_to > valid_from);

-- ⭐ 库存流水的"判别列 + 真外键"一致性（D-09）
--    ref_type 说明了来源类型，那么对应的外键**必须存在**；反之不用的外键**必须为 NULL**。
--    这条约束保证：**每一条流水都能追溯到一张真实的单据**，而不是一个字符串 ref_no。
ALTER TABLE tbl_stock_ledger
    ADD CONSTRAINT ck_stock_ledger_ref_consistency
        CHECK (
               (ref_type = 'PURCHASE'
                AND purchase_order_id IS NOT NULL
                AND order_id IS NULL)
            OR (ref_type = 'ORDER'
                AND order_id IS NOT NULL
                AND purchase_order_id IS NULL)
            OR (ref_type IN ('MANUAL','OPENING')
                AND purchase_order_id IS NULL
                AND order_id IS NULL)
        );

-- ⭐ 积分流水的"去向二选一"一致性
--    EARN 应对应一张订单；REDEEM 应对应一张券。两者不能同时为空。
ALTER TABLE tbl_points_ledger
    ADD CONSTRAINT ck_points_ledger_target
        CHECK (
               (point_type = 'EARN'   AND order_id  IS NOT NULL)
            OR (point_type = 'REDEEM' AND coupon_id IS NOT NULL)
        );
GO

PRINT N'【约束】跨列 CHECK 已添加。';
GO

/* ============================================================
 * 五、外键（FK）—— 30 个
 *
 * 命名规则：fk_<表>_<列>  —— 用【外键列名】而不是目标表名。
 * 原因：tbl_order_detail 有 3 个外键都指向 tbl_spec_option（杯型/糖度/冰量），
 *       若用目标表名会造成三个约束重名。
 *
 * 全部使用默认的 NO ACTION（不允许删除仍被引用的行）——
 * 在本项目里这是对的：历史订单不该因为删商品而消失，正确做法是改状态而非删行。
 * ============================================================ */

/* ---------- tbl_product_category（1 个，自引用） ---------- */
ALTER TABLE tbl_product_category
    ADD CONSTRAINT fk_product_category_parent_category
        FOREIGN KEY (parent_category_id) REFERENCES tbl_product_category(category_id);

/* ---------- tbl_product（1 个） ---------- */
ALTER TABLE tbl_product
    ADD CONSTRAINT fk_product_category
        FOREIGN KEY (category_id) REFERENCES tbl_product_category(category_id);

/* ---------- tbl_topping（1 个） ---------- */
ALTER TABLE tbl_topping
    ADD CONSTRAINT fk_topping_ingredient
        FOREIGN KEY (ingredient_id) REFERENCES tbl_ingredient(ingredient_id);

/* ---------- tbl_recipe（4 个） ---------- */
ALTER TABLE tbl_recipe
    ADD CONSTRAINT fk_recipe_product
        FOREIGN KEY (product_id) REFERENCES tbl_product(product_id);

ALTER TABLE tbl_recipe
    ADD CONSTRAINT fk_recipe_cup_spec
        FOREIGN KEY (cup_spec_id) REFERENCES tbl_spec_option(spec_option_id);

ALTER TABLE tbl_recipe
    ADD CONSTRAINT fk_recipe_sugar_spec
        FOREIGN KEY (sugar_spec_id) REFERENCES tbl_spec_option(spec_option_id);

ALTER TABLE tbl_recipe
    ADD CONSTRAINT fk_recipe_ingredient
        FOREIGN KEY (ingredient_id) REFERENCES tbl_ingredient(ingredient_id);

/* ---------- tbl_purchase_order（3 个） ---------- */
ALTER TABLE tbl_purchase_order
    ADD CONSTRAINT fk_purchase_order_supplier
        FOREIGN KEY (supplier_id) REFERENCES tbl_supplier(supplier_id);

ALTER TABLE tbl_purchase_order
    ADD CONSTRAINT fk_purchase_order_ordered_by
        FOREIGN KEY (ordered_by) REFERENCES tbl_employee(employee_id);

ALTER TABLE tbl_purchase_order
    ADD CONSTRAINT fk_purchase_order_received_by
        FOREIGN KEY (received_by) REFERENCES tbl_employee(employee_id);

/* ---------- tbl_purchase_order_detail（2 个） ---------- */
ALTER TABLE tbl_purchase_order_detail
    ADD CONSTRAINT fk_purchase_order_detail_purchase_order
        FOREIGN KEY (purchase_order_id) REFERENCES tbl_purchase_order(purchase_order_id);

ALTER TABLE tbl_purchase_order_detail
    ADD CONSTRAINT fk_purchase_order_detail_ingredient
        FOREIGN KEY (ingredient_id) REFERENCES tbl_ingredient(ingredient_id);

/* ---------- tbl_coupon（1 个） ---------- */
ALTER TABLE tbl_coupon
    ADD CONSTRAINT fk_coupon_member
        FOREIGN KEY (member_id) REFERENCES tbl_member(member_id);

/* ---------- tbl_order_header（3 个） ---------- */
ALTER TABLE tbl_order_header
    ADD CONSTRAINT fk_order_header_member
        FOREIGN KEY (member_id) REFERENCES tbl_member(member_id);

ALTER TABLE tbl_order_header
    ADD CONSTRAINT fk_order_header_coupon
        FOREIGN KEY (coupon_id) REFERENCES tbl_coupon(coupon_id);

ALTER TABLE tbl_order_header
    ADD CONSTRAINT fk_order_header_cashier
        FOREIGN KEY (cashier_id) REFERENCES tbl_employee(employee_id);

/* ---------- tbl_order_detail（5 个） ---------- */
ALTER TABLE tbl_order_detail
    ADD CONSTRAINT fk_order_detail_order
        FOREIGN KEY (order_id) REFERENCES tbl_order_header(order_id);

ALTER TABLE tbl_order_detail
    ADD CONSTRAINT fk_order_detail_product
        FOREIGN KEY (product_id) REFERENCES tbl_product(product_id);

ALTER TABLE tbl_order_detail
    ADD CONSTRAINT fk_order_detail_cup_spec
        FOREIGN KEY (cup_spec_id) REFERENCES tbl_spec_option(spec_option_id);

ALTER TABLE tbl_order_detail
    ADD CONSTRAINT fk_order_detail_sugar_spec
        FOREIGN KEY (sugar_spec_id) REFERENCES tbl_spec_option(spec_option_id);

ALTER TABLE tbl_order_detail
    ADD CONSTRAINT fk_order_detail_ice_spec
        FOREIGN KEY (ice_spec_id) REFERENCES tbl_spec_option(spec_option_id);

/* ---------- tbl_order_detail_topping（2 个） ---------- */
ALTER TABLE tbl_order_detail_topping
    ADD CONSTRAINT fk_order_detail_topping_order_detail
        FOREIGN KEY (order_detail_id) REFERENCES tbl_order_detail(order_detail_id);

ALTER TABLE tbl_order_detail_topping
    ADD CONSTRAINT fk_order_detail_topping_topping
        FOREIGN KEY (topping_id) REFERENCES tbl_topping(topping_id);

/* ---------- tbl_points_ledger（3 个） ---------- */
ALTER TABLE tbl_points_ledger
    ADD CONSTRAINT fk_points_ledger_member
        FOREIGN KEY (member_id) REFERENCES tbl_member(member_id);

ALTER TABLE tbl_points_ledger
    ADD CONSTRAINT fk_points_ledger_order
        FOREIGN KEY (order_id) REFERENCES tbl_order_header(order_id);

ALTER TABLE tbl_points_ledger
    ADD CONSTRAINT fk_points_ledger_coupon
        FOREIGN KEY (coupon_id) REFERENCES tbl_coupon(coupon_id);

/* ---------- tbl_stock_ledger（4 个） ---------- */
ALTER TABLE tbl_stock_ledger
    ADD CONSTRAINT fk_stock_ledger_ingredient
        FOREIGN KEY (ingredient_id) REFERENCES tbl_ingredient(ingredient_id);

ALTER TABLE tbl_stock_ledger
    ADD CONSTRAINT fk_stock_ledger_purchase_order
        FOREIGN KEY (purchase_order_id) REFERENCES tbl_purchase_order(purchase_order_id);

ALTER TABLE tbl_stock_ledger
    ADD CONSTRAINT fk_stock_ledger_order
        FOREIGN KEY (order_id) REFERENCES tbl_order_header(order_id);

ALTER TABLE tbl_stock_ledger
    ADD CONSTRAINT fk_stock_ledger_operator
        FOREIGN KEY (operator_id) REFERENCES tbl_employee(employee_id);
GO

PRINT N'【约束】外键 30 个已添加。';
GO

/* ============================================================
 * 约束清点回显
 * ============================================================ */

PRINT N'【约束】完成。清点：';
GO

SELECT
    '主键 PK'   AS [约束类型], COUNT(*) AS [数量] FROM sys.key_constraints WHERE type = 'PK'
UNION ALL SELECT
    '唯一 UNIQUE', COUNT(*) FROM sys.key_constraints WHERE type = 'UQ'
UNION ALL SELECT
    '外键 FK',     COUNT(*) FROM sys.foreign_keys
UNION ALL SELECT
    '检查 CHECK',  COUNT(*) FROM sys.check_constraints
UNION ALL SELECT
    '默认 DEFAULT', COUNT(*) FROM sys.default_constraints
ORDER BY 2 DESC;
GO

PRINT N'【约束】下一步：执行 03-indexes/indexes.sql 建索引，然后 04-seed 装载种子数据。';
GO
