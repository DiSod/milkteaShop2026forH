/* ============================================================
 * 脚本：view.sql
 * 用途：建立奶茶店 5 个核心业务统计与全景视图（DDL）
 * 依赖：00-bootstrap/create-database.sql
 *       01-schema/create-tables.sql
 *       02-constraints/constraints.sql
 *       04-seed/seed_data.sql
 * 阶段：第 4 周
 * 作者：何争霖 (hezhlin5) / 协同：DiSod
 * 日期：2026-10-05
 * 幂等：是 —— 使用 CREATE OR ALTER VIEW，可安全反复重跑
 * ============================================================
 *
 * 【第 4 周视图设计思想与业务背景】
 * 1. 派生数据绝不建物理列（关系规范化核心法则）：
 *    在关系数据库中，"可由基础数据动态推导出的数据绝不冗余落地"。
 *    例如"某商品还能做几杯"、"原料缺料建议补货量"、"每日营业额"、"会员等级"等，
 *    均应由视图（VIEW）在查询时按需计算，确保真相源唯一，彻底规避数据不一致风险。
 *
 * 2. 5 个业务与分析视图清单：
 *    ① vw_product_stock_availability  商品理论可做杯数与售卖状态推导（招牌业务视图）
 *    ② vw_ingredient_reorder_alert     原料缺料与补货建议预警视图（供应链与库管看板）
 *    ③ vw_daily_business_summary      全店每日经营汇总与营收日报（店长与财务报表）
 *    ④ vw_member_consumption_profile  会员消费画像与分级洞察（CRM 与精准营销）
 *    ⑤ vw_order_detail_full           订单全景明细平铺宽表（收银台/小票/BI分析）
 *
 * 【执行方式】
 *   sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -i project/sql/07-view/view.sql
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'【视图】开始创建 / 更新 5 个业务统计视图 ...';
GO

/* ============================================================
 * 1. vw_product_stock_availability（商品理论可做杯数与售卖状态推导）
 * ------------------------------------------------------------
 * 业务背景：
 *   “短板理论（木桶原理）”的经典工程实现。
 *   一杯奶茶由 3~5 种原料组成，单品的制作上限取决于最先见底的那味物料。
 *   在交易发生前，为店长巡店备料、前台点单机展示提供理论可做杯数推导；
 *   结合单库反冲倒扣保证的精确 qty_on_hand，实现：
 *     MIN(FLOOR(原料结存 / 配方用量))
 *   同时融合物理售罄与人工沽清（is_sold_out）双重状态机判定。
 * ============================================================ */
CREATE OR ALTER VIEW vw_product_stock_availability AS
SELECT 
    c.category_name                               AS category_name,
    p.product_id                                  AS product_id,
    p.product_code                                AS product_code,
    p.product_name                                AS product_name,
    cs.spec_option_id                             AS cup_spec_id,
    cs.spec_name                                  AS cup_spec_name,
    p.base_price + cs.extra_price                 AS selling_price,
    ISNULL(MIN(FLOOR(i.qty_on_hand / r.qty)), 0)  AS theor_makeable_cups,
    MAX(CAST(i.is_sold_out AS INT))               AS is_ingredient_sold_out,
    p.product_status                              AS product_status,
    CASE 
        WHEN p.product_status = 'OFF_SALE'                     THEN N'已下架'
        WHEN MAX(CAST(i.is_sold_out AS INT)) = 1               THEN N'临时沽清'
        WHEN ISNULL(MIN(FLOOR(i.qty_on_hand / r.qty)), 0) = 0  THEN N'原料售罄'
        WHEN ISNULL(MIN(FLOOR(i.qty_on_hand / r.qty)), 0) < 15 THEN N'紧张预警'
        ELSE N'充足在售'
    END                                           AS sale_status
FROM tbl_product p
JOIN tbl_product_category c 
    ON c.category_id = p.category_id
JOIN tbl_recipe r 
    ON r.product_id = p.product_id
JOIN tbl_spec_option cs 
    ON cs.spec_option_id = r.cup_spec_id
JOIN tbl_ingredient i 
    ON i.ingredient_id = r.ingredient_id
WHERE r.qty > 0
GROUP BY 
    c.category_name, 
    p.product_id, 
    p.product_code, 
    p.product_name, 
    p.product_status, 
    cs.spec_option_id, 
    cs.spec_name, 
    p.base_price, 
    cs.extra_price;
GO

PRINT N'【视图】1/5 vw_product_stock_availability 创建完成。';
GO

/* ============================================================
 * 2. vw_ingredient_reorder_alert（原料缺料与补货建议预警视图）
 * ------------------------------------------------------------
 * 业务背景：
 *   供库管员与店长每日巡检库存水位，动态计算建议采购量：
 *     suggested_order_qty = MAX(0, target_level - qty_on_hand)
 *   并根据库存对安全补货点（reorder_point）的覆盖倍数评定预警优先级：
 *     1. 零库存 (qty = 0)
 *     2. 严重不足 (qty <= 50% 补货点)
 *     3. 触及补货点 (qty <= 补货点)
 *     4. 人工沽清 (is_sold_out = 1)
 *     5. 库存健康
 * ============================================================ */
CREATE OR ALTER VIEW vw_ingredient_reorder_alert AS
SELECT 
    i.ingredient_id                               AS ingredient_id,
    i.ingredient_code                             AS ingredient_code,
    i.ingredient_name                             AS ingredient_name,
    i.unit                                        AS unit,
    i.spec                                        AS spec,
    i.qty_on_hand                                 AS qty_on_hand,
    i.reorder_point                               AS reorder_point,
    i.target_level                                AS target_level,
    CASE 
        WHEN i.target_level > i.qty_on_hand THEN i.target_level - i.qty_on_hand 
        ELSE 0 
    END                                           AS suggested_order_qty,
    i.moving_avg_cost                             AS moving_avg_cost,
    CAST(i.qty_on_hand * i.moving_avg_cost AS DECIMAL(12,2)) AS stock_value,
    i.is_sold_out                                 AS is_sold_out,
    CASE
        WHEN i.is_sold_out = 1                          THEN N'人工沽清'
        WHEN i.qty_on_hand = 0                          THEN N'零库存'
        WHEN i.qty_on_hand <= i.reorder_point * 0.5     THEN N'严重不足'
        WHEN i.qty_on_hand <= i.reorder_point           THEN N'触及补货点'
        ELSE N'库存健康'
    END                                           AS alert_level,
    CASE
        WHEN i.qty_on_hand = 0                          THEN 1
        WHEN i.qty_on_hand <= i.reorder_point * 0.5     THEN 2
        WHEN i.qty_on_hand <= i.reorder_point           THEN 3
        WHEN i.is_sold_out = 1                          THEN 4
        ELSE 5
    END                                           AS alert_priority
FROM tbl_ingredient i;
GO

PRINT N'【视图】2/5 vw_ingredient_reorder_alert 创建完成。';
GO

/* ============================================================
 * 3. vw_daily_business_summary（全店每日经营汇总与营收日报）
 * ------------------------------------------------------------
 * 业务背景：
 *   单店店长每日打烊报表与财务对账核心凭证。
 *   聚合订单单头（tbl_order_header）与明细（tbl_order_detail），
 *   按营业日（business_date）统计：
 *     - 总接单量、完成单量、取消单量
 *     - 总出杯数（物理产品出杯杯数）
 *     - 营业毛收、优惠总额、净实收营收
 *     - 平均客单价（AOV）与会员订单占比
 *     - 微信、支付宝、现金多渠道收银拆解
 * ============================================================ */
CREATE OR ALTER VIEW vw_daily_business_summary AS
SELECT 
    h.business_date                                                          AS business_date,
    COUNT(h.order_id)                                                        AS total_orders,
    SUM(CASE WHEN h.order_status = 'COMPLETED' THEN 1 ELSE 0 END)            AS completed_orders,
    SUM(CASE WHEN h.order_status = 'CANCELLED' THEN 1 ELSE 0 END)            AS cancelled_orders,
    ISNULL(SUM(d.cup_count), 0)                                              AS total_cups,
    SUM(h.amount_due + h.discount_amount)                                    AS gross_sales,
    SUM(h.discount_amount)                                                   AS total_discount,
    SUM(h.amount_paid)                                                       AS net_revenue,
    CAST(AVG(h.amount_paid * 1.0) AS DECIMAL(10,2))                          AS avg_order_amount,
    COUNT(h.member_id)                                                       AS member_orders,
    SUM(CASE WHEN h.member_id IS NOT NULL THEN h.amount_paid ELSE 0 END)     AS member_revenue,
    SUM(CASE WHEN h.pay_method = 'WECHAT' THEN h.amount_paid ELSE 0 END)     AS wechat_revenue,
    SUM(CASE WHEN h.pay_method = 'ALIPAY' THEN h.amount_paid ELSE 0 END)     AS alipay_revenue,
    SUM(CASE WHEN h.pay_method = 'CASH'   THEN h.amount_paid ELSE 0 END)     AS cash_revenue
FROM tbl_order_header h
LEFT JOIN (
    SELECT order_id, SUM(qty) AS cup_count 
    FROM tbl_order_detail 
    GROUP BY order_id
) d ON d.order_id = h.order_id
GROUP BY h.business_date;
GO

PRINT N'【视图】3/5 vw_daily_business_summary 创建完成。';
GO

/* ============================================================
 * 4. vw_member_consumption_profile（会员消费画像与分级洞察）
 * ------------------------------------------------------------
 * 业务背景：
 *   为私域运营与 CRM 精细化营销提供会员 360 度画像：
 *   - 基础档案：会员卡号、手机号、注册时间、当前可用积分
 *   - 消费指标：已完成订单数、累计消费总额、历史客单均价
 *   - 时间跨度：首单消费时间、最近下单时间
 *   - 会员价值等级（普通 / 白银 / 黄金 / 黑金）
 *   - 活跃度标签（沉睡新客 / 低频尝鲜 / 中频稳定 / 高频活跃）
 * ============================================================ */
CREATE OR ALTER VIEW vw_member_consumption_profile AS
SELECT 
    m.member_id                                                              AS member_id,
    m.member_code                                                            AS member_code,
    m.member_name                                                            AS member_name,
    m.member_phone                                                           AS member_phone,
    m.register_date                                                          AS register_date,
    m.points_balance                                                         AS points_balance,
    COUNT(o.order_id)                                                        AS total_orders,
    ISNULL(SUM(o.amount_paid), 0)                                            AS total_spent,
    ISNULL(CAST(AVG(o.amount_paid * 1.0) AS DECIMAL(10,2)), 0)               AS avg_order_spent,
    MIN(o.order_time)                                                        AS first_order_time,
    MAX(o.order_time)                                                        AS last_order_time,
    CASE 
        WHEN ISNULL(SUM(o.amount_paid), 0) >= 400 THEN N'黑金会员'
        WHEN ISNULL(SUM(o.amount_paid), 0) >= 250 THEN N'黄金会员'
        WHEN ISNULL(SUM(o.amount_paid), 0) >= 100 THEN N'白银会员'
        ELSE N'普通会员'
    END                                                                      AS member_tier,
    CASE
        WHEN COUNT(o.order_id) >= 15 THEN N'高频活跃'
        WHEN COUNT(o.order_id) >= 8  THEN N'中频稳定'
        WHEN COUNT(o.order_id) >= 1  THEN N'低频尝鲜'
        ELSE N'沉睡新客'
    END                                                                      AS activity_level
FROM tbl_member m
LEFT JOIN tbl_order_header o 
    ON o.member_id = m.member_id 
   AND o.order_status = 'COMPLETED'
GROUP BY 
    m.member_id, 
    m.member_code, 
    m.member_name, 
    m.member_phone, 
    m.register_date, 
    m.points_balance;
GO

PRINT N'【视图】4/5 vw_member_consumption_profile 创建完成。';
GO

/* ============================================================
 * 5. vw_order_detail_full（订单全景明细平铺宽表）
 * ------------------------------------------------------------
 * 业务背景：
 *   关系型数据库遵循 1NF~3NF 进行了高度规范化拆分，
 *   在前端小票打印、收银退单核对以及导出数据至 Excel/BI 报表时，
 *   往往需要跨 7~8 张表进行深度连接。
 *   本视图将订单单头、明细、小料加料（STRING_AGG 平铺）、
 *   商品分类、规格选项、操作员工与会员客户完整联立成业务宽表。
 * ============================================================ */
CREATE OR ALTER VIEW vw_order_detail_full AS
WITH topping_agg AS (
    SELECT
        odt.order_detail_id,
        CAST(STRING_AGG(CONCAT(t.topping_name, N'*', odt.qty), N'、') WITHIN GROUP (ORDER BY odt.od_topping_id) AS NVARCHAR(100)) AS topping_summary,
        SUM(odt.qty * odt.unit_extra_price) AS topping_extra_total
    FROM tbl_order_detail_topping odt
    JOIN tbl_topping t ON t.topping_id = odt.topping_id
    GROUP BY odt.order_detail_id
)
SELECT 
    h.order_id                                   AS order_id,
    h.order_no                                   AS order_no,
    h.business_date                              AS business_date,
    h.pickup_no                                  AS pickup_no,
    h.order_time                                 AS order_time,
    h.order_status                               AS order_status,
    e.employee_id                                AS cashier_id,
    e.employee_name                              AS cashier_name,
    m.member_id                                  AS member_id,
    ISNULL(m.member_name, N'非会员散客')          AS customer_name,
    ISNULL(m.member_phone, N'-')                 AS customer_phone,
    d.order_detail_id                            AS order_detail_id,
    d.line_no                                    AS line_no,
    c.category_id                                AS category_id,
    c.category_name                              AS category_name,
    p.product_id                                 AS product_id,
    p.product_code                               AS product_code,
    p.product_name                               AS product_name,
    cup.spec_name                                AS cup_spec,
    sugar.spec_name                              AS sugar_spec,
    ice.spec_name                                AS ice_spec,
    ISNULL(ta.topping_summary, N'无加料')         AS topping_summary,
    ISNULL(ta.topping_extra_total, 0)            AS topping_extra_total,
    d.qty                                        AS qty,
    d.unit_price                                 AS unit_price,
    d.subtotal                                   AS subtotal,
    h.discount_amount                            AS order_discount_amount,
    h.amount_due                                 AS order_amount_due,
    h.amount_paid                                AS order_amount_paid,
    h.pay_method                                 AS pay_method,
    h.pay_status                                 AS pay_status,
    h.pay_time                                   AS pay_time
FROM tbl_order_header h
JOIN tbl_order_detail d 
    ON d.order_id = h.order_id
JOIN tbl_employee e 
    ON e.employee_id = h.cashier_id
LEFT JOIN tbl_member m 
    ON m.member_id = h.member_id
JOIN tbl_product p 
    ON p.product_id = d.product_id
JOIN tbl_product_category c 
    ON c.category_id = p.category_id
LEFT JOIN tbl_spec_option cup 
    ON cup.spec_option_id = d.cup_spec_id
LEFT JOIN tbl_spec_option sugar 
    ON sugar.spec_option_id = d.sugar_spec_id
LEFT JOIN tbl_spec_option ice 
    ON ice.spec_option_id = d.ice_spec_id
LEFT JOIN topping_agg ta 
    ON ta.order_detail_id = d.order_detail_id;
GO

PRINT N'【视图】5/5 vw_order_detail_full 创建完成。';
GO

/* ============================================================
 * 验证：回显各视图前 3 行样例数据
 * ============================================================ */
PRINT N'【视图】=== 视图 1 样例：商品库存可做杯数（前 3 条） ===';
SELECT TOP 3 
    category_name, product_name, cup_spec_name, selling_price, theor_makeable_cups, sale_status 
FROM vw_product_stock_availability 
ORDER BY theor_makeable_cups ASC;

PRINT N'【视图】=== 视图 2 样例：原料缺料与补货建议（前 3 条） ===';
SELECT TOP 3 
    ingredient_code, ingredient_name, qty_on_hand, reorder_point, suggested_order_qty, alert_level 
FROM vw_ingredient_reorder_alert 
ORDER BY alert_priority ASC;

PRINT N'【视图】=== 视图 3 样例：每日经营日报（前 3 天） ===';
SELECT TOP 3 
    business_date, total_orders, completed_orders, total_cups, net_revenue, avg_order_amount 
FROM vw_daily_business_summary 
ORDER BY business_date ASC;

PRINT N'【视图】=== 视图 4 样例：会员消费画像与分级（前 3 位） ===';
SELECT TOP 3 
    member_code, member_name, total_orders, total_spent, member_tier, activity_level 
FROM vw_member_consumption_profile 
ORDER BY total_spent DESC;

PRINT N'【视图】=== 视图 5 样例：订单明细全景平铺（前 3 条） ===';
SELECT TOP 3 
    order_no, customer_name, product_name, cup_spec, sugar_spec, ice_spec, topping_summary, subtotal 
FROM vw_order_detail_full 
ORDER BY order_id DESC, line_no ASC;
GO

PRINT N'【视图】5 个视图已全部创建并校验成功！';
GO
