/* ============================================================
 * 脚本：query.sql
 * 用途：奶茶店多表深度连接与业务决策综合查询（DQL 实战）
 * 依赖：00-bootstrap/create-database.sql
 *       01-schema/create-tables.sql
 *       02-constraints/constraints.sql
 *       04-seed/seed_data.sql
 * 阶段：第 4 周
 * 作者：何争霖 (hezhlin5) / 协同：DiSod
 * 日期：2026-10-05
 * 幂等：是 —— 纯 DQL 查询与审计，不修改数据，可安全反复重跑
 * ============================================================
 *
 * 【第 4 周查询设计思想与实战价值】
 * 课程第 4 周核心理论为“多表连接（ch4）与复杂查询”。
 * 本脚本坚决杜绝“无业务意义的机械 JOIN”，每个查询均紧扣单店奶茶店运营的核心痛点：
 *
 * ① Q1：供应链四层级联穿透与入库追溯（跨 6 表/别名）
 *      从供应商 -> 采购订单 -> 采购明细 -> 采购员/库管员 -> 原料台账 -> 关联库存流水，
 *      演示进销存系统中真实单据流向与批次质量追溯。
 *
 * ② Q2：订单全维度穿透与加料定制偏好分析（跨 5 表）
 *      拆解 2,629 条订单明细与加料关系，分析单品加料渗透率（Attach Rate）
 *      与顾客糖度/冰度偏好矩阵，为菜单优化提供量化数据。
 *
 * ③ Q3：品类与单品销售排行及营收贡献度分析（窗口函数实战）
 *      运用 DENSE_RANK、ROW_NUMBER、SUM() OVER (PARTITION BY) 与 SUM() OVER ()，
 *      跨表聚合计算品类及单品销售杯数、营收总额、品类内占比与全店占比。
 *
 * ④ Q4：进销存台账自洽平衡审计报表（账实对账数学证明）
 *      聚合 13,851 条库存流水，自动按 期初+采购-销售-报损 对比当前实际物理在手库存，
 *      以零差额（variance = 0.000）严格数学证明系统满足“物质守恒与台账闭环”。
 *
 * 【执行方式】
 *   sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -i project/sql/06-query/query.sql
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'【查询】开始执行第 4 周多表连接实战查询 ...';
GO

/* ============================================================
 * Q1：供应链四层级联穿透与入库追溯（跨 6 表/别名）
 * ------------------------------------------------------------
 * 业务场景：
 *   库管员与店长进行批次质量溯源与供应商履约审计。
 *   穿透路径：
 *     tbl_supplier (供应商)
 *       -> tbl_purchase_order (采购订单单头)
 *       -> tbl_employee (下单人 / 验收人)
 *       -> tbl_purchase_order_detail (采购明细)
 *       -> tbl_ingredient (原料字典与台账)
 *       -> tbl_stock_ledger (关联入库流水账簿)
 * ============================================================ */
PRINT N'【查询】=== Q1：供应链四层级联穿透与入库追溯（展示前 10 条） ===';
SELECT TOP 10
    s.supplier_code                                                      AS 供应商编码,
    s.supplier_name                                                      AS 供应商名称,
    po.purchase_no                                                       AS 采购单号,
    po.order_date                                                        AS 下单日期,
    po.arrival_date                                                      AS 到货日期,
    po.order_status                                                      AS 订单状态,
    buyer.employee_name                                                  AS 下单人,
    ISNULL(keeper.employee_name, N'待验收')                              AS 验收人,
    i.ingredient_code                                                    AS 原料编码,
    i.ingredient_name                                                    AS 原料名称,
    pod.qty_ordered                                                      AS 订购数量,
    pod.qty_received                                                     AS 实收数量,
    pod.unit_price                                                       AS 采购单价,
    CAST(pod.qty_received * pod.unit_price AS DECIMAL(10,2))             AS 验收入库金额,
    ISNULL(CAST(sl.ledger_id AS VARCHAR(10)), N'未入库')                 AS 关联入库流水号,
    sl.ledger_time                                                       AS 入库记账时间
FROM tbl_supplier s
INNER JOIN tbl_purchase_order po 
    ON po.supplier_id = s.supplier_id
INNER JOIN tbl_employee buyer 
    ON buyer.employee_id = po.ordered_by
LEFT JOIN tbl_employee keeper 
    ON keeper.employee_id = po.received_by
INNER JOIN tbl_purchase_order_detail pod 
    ON pod.purchase_order_id = po.purchase_order_id
INNER JOIN tbl_ingredient i 
    ON i.ingredient_id = pod.ingredient_id
LEFT JOIN tbl_stock_ledger sl 
    ON sl.purchase_order_id = po.purchase_order_id 
   AND sl.ingredient_id = pod.ingredient_id
   AND sl.ledger_type = 'PURCHASE_IN'
ORDER BY po.order_date DESC, pod.purchase_order_detail_id ASC;
GO

/* ============================================================
 * Q2：订单全维度穿透与加料定制偏好分析
 * ------------------------------------------------------------
 * 业务场景：
 *   茶饮行业极为依赖“客制化与加料（小料经济）”提升客单毛利。
 *   Q2a: 统计各单品的总销量、加料杯数、加料渗透率（Attach Rate）及小料创收
 *   Q2b: 统计全店顾客对于糖度与冰度搭配的消费行为热度排行
 * ============================================================ */
PRINT N'【查询】=== Q2a：单品加料渗透率与小料增收贡献（展示加料渗透率 TOP 10） ===';
SELECT TOP 10
    p.product_code                                                       AS 商品编码,
    p.product_name                                                       AS 商品名称,
    c.category_name                                                      AS 所属品类,
    COUNT(d.order_detail_id)                                             AS 累计销售杯数,
    SUM(CASE WHEN odt.topping_count > 0 THEN 1 ELSE 0 END)               AS 加料定制杯数,
    CAST(SUM(CASE WHEN odt.topping_count > 0 THEN 1.0 ELSE 0.0 END) 
         * 100.0 / COUNT(d.order_detail_id) AS DECIMAL(5,2))             AS 加料渗透率_百分比,
    ISNULL(SUM(odt.topping_amount), 0)                                   AS 小料附加增收,
    SUM(d.subtotal)                                                      AS 商品销售总额
FROM tbl_order_detail d
INNER JOIN tbl_product p 
    ON p.product_id = d.product_id
INNER JOIN tbl_product_category c 
    ON c.category_id = p.category_id
INNER JOIN tbl_order_header h 
    ON h.order_id = d.order_id
LEFT JOIN (
    SELECT 
        order_detail_id, 
        COUNT(topping_id)           AS topping_count, 
        SUM(qty * unit_extra_price) AS topping_amount
    FROM tbl_order_detail_topping
    GROUP BY order_detail_id
) odt 
    ON odt.order_detail_id = d.order_detail_id
WHERE h.order_status = 'COMPLETED'
GROUP BY p.product_code, p.product_name, c.category_name
ORDER BY 加料定制杯数 DESC, 累计销售杯数 DESC;
GO

PRINT N'【查询】=== Q2b：全店顾客甜度与冰度组合偏好热度分布（TOP 10 组合） ===';
SELECT TOP 10
    ISNULL(sugar.spec_name, N'默认/无配方')                              AS 甜度档位,
    ISNULL(ice.spec_name,   N'默认/常温')                                AS 冰度档位,
    COUNT(d.order_detail_id)                                             AS 点单杯数,
    CAST(COUNT(d.order_detail_id) * 100.0 
         / SUM(COUNT(d.order_detail_id)) OVER() AS DECIMAL(5,2))         AS 点单占比_百分比
FROM tbl_order_detail d
INNER JOIN tbl_order_header h 
    ON h.order_id = d.order_id
LEFT JOIN tbl_spec_option sugar 
    ON sugar.spec_option_id = d.sugar_spec_id
LEFT JOIN tbl_spec_option ice 
    ON ice.spec_option_id = d.ice_spec_id
WHERE h.order_status = 'COMPLETED'
GROUP BY sugar.spec_name, ice.spec_name
ORDER BY 点单杯数 DESC;
GO

/* ============================================================
 * Q3：品类与商品销售排行与营收贡献度分析（窗口函数实战）
 * ------------------------------------------------------------
 * 业务场景：
 *   店长运营复盘与商品矩阵优化（二八法则分析）。
 *   运用 4 个高级窗口分析函数：
 *     - DENSE_RANK(): 全店商品营收总排名
 *     - ROW_NUMBER() OVER (PARTITION BY 品类): 品类内部冠亚军排行
 *     - SUM() OVER (PARTITION BY 品类): 动态推导单品占所在品类的营收比重
 *     - SUM() OVER (): 动态推导单品占全店总营收的大盘贡献率
 * ============================================================ */
PRINT N'【查询】=== Q3：品类与单品销售总榜及多层贡献率排行（全店 TOP 12） ===';
WITH product_sales AS (
    SELECT 
        c.category_id,
        c.category_name,
        p.product_id,
        p.product_code,
        p.product_name,
        SUM(d.qty)                               AS sales_cups,
        SUM(d.subtotal)                          AS sales_revenue,
        CAST(AVG(d.unit_price) AS DECIMAL(10,2)) AS avg_selling_price
    FROM tbl_order_detail d
    INNER JOIN tbl_order_header h 
        ON h.order_id = d.order_id
    INNER JOIN tbl_product p 
        ON p.product_id = d.product_id
    INNER JOIN tbl_product_category c 
        ON c.category_id = p.category_id
    WHERE h.order_status = 'COMPLETED'
    GROUP BY c.category_id, c.category_name, p.product_id, p.product_code, p.product_name
)
SELECT TOP 12
    ps.category_name                                                     AS 所属品类,
    ps.product_code                                                      AS 商品编码,
    ps.product_name                                                      AS 商品名称,
    ps.sales_cups                                                        AS 售出杯数,
    ps.sales_revenue                                                     AS 销售营收,
    ps.avg_selling_price                                                 AS 平均售价,
    DENSE_RANK() OVER (ORDER BY ps.sales_revenue DESC)                   AS 全店营收排名,
    ROW_NUMBER() OVER (PARTITION BY ps.category_name 
                       ORDER BY ps.sales_revenue DESC)                   AS 品类内排名,
    CAST(ps.sales_revenue * 100.0 
         / SUM(ps.sales_revenue) OVER (PARTITION BY ps.category_name) 
         AS DECIMAL(5,2))                                                AS 占品类营收比_百分比,
    CAST(ps.sales_revenue * 100.0 
         / SUM(ps.sales_revenue) OVER () 
         AS DECIMAL(5,2))                                                AS 占全店营收比_百分比
FROM product_sales ps
ORDER BY 全店营收排名 ASC;
GO

/* ============================================================
 * Q4：进销存台账自洽平衡审计报表（账实对账数学证明）
 * ------------------------------------------------------------
 * 业务场景：
 *   财务月结与供应链严谨对账，验证台账是否满足“物质守恒与零差错”：
 *     期末实际物理在手库存 (qty_on_hand)
 *       == 期初库存 + 累计采购入库 - 累计销售扣减 - 累计打烊损耗
 *   对比 60 种原料在 13,851 条库存流水冲减后的差异。
 * ============================================================ */
PRINT N'【查询】=== Q4：进销存台账自洽平衡审计（展示主要物料平衡状况） ===';
SELECT TOP 10
    i.ingredient_code                                                    AS 原料编码,
    i.ingredient_name                                                    AS 原料名称,
    i.unit                                                               AS 单位,
    SUM(CASE WHEN sl.ref_type = 'OPENING' THEN sl.qty ELSE 0 END)        AS 期初建账库存,
    SUM(CASE WHEN sl.ref_type = 'PURCHASE' THEN sl.qty ELSE 0 END)       AS 累计采购入库,
    SUM(CASE WHEN sl.ledger_type = 'SALES_USE' THEN ABS(sl.qty) 
             ELSE 0 END)                                                 AS 累计销售耗用,
    SUM(CASE WHEN sl.ledger_type = 'LOSS' THEN ABS(sl.qty) 
             ELSE 0 END)                                                 AS 累计报损耗用,
    SUM(sl.qty)                                                          AS 流水理论结存,
    i.qty_on_hand                                                        AS 物理在手实存,
    i.qty_on_hand - SUM(sl.qty)                                          AS 账实差异,
    CASE 
        WHEN ABS(i.qty_on_hand - SUM(sl.qty)) < 0.001 THEN N'严格平账' 
        ELSE N'账实异常' 
    END                                                                  AS 审计核对结论
FROM tbl_ingredient i
INNER JOIN tbl_stock_ledger sl 
    ON sl.ingredient_id = i.ingredient_id
GROUP BY i.ingredient_code, i.ingredient_name, i.unit, i.qty_on_hand
ORDER BY 累计采购入库 DESC, i.ingredient_code ASC;
GO

PRINT N'【查询】=== Q4 汇总断言：检查全库 60 种原料是否存在任何账实不平记录 ===';
SELECT 
    COUNT(*)                                                             AS 存在差异物料数,
    ISNULL(SUM(ABS(i.qty_on_hand - sub.ledger_sum)), 0)                  AS 差异总量绝对值,
    CASE 
        WHEN COUNT(*) = 0 THEN N'✅ 全库 60 种原料 100% 账实自洽，进销存台账绝对守恒！'
        ELSE N'❌ 警告：检测到台账不平，请排查流水！'
    END                                                                  AS 全店审计最终裁决
FROM (
    SELECT ingredient_id, SUM(qty) AS ledger_sum
    FROM tbl_stock_ledger
    GROUP BY ingredient_id
) sub
INNER JOIN tbl_ingredient i 
    ON i.ingredient_id = sub.ingredient_id
WHERE ABS(i.qty_on_hand - sub.ledger_sum) > 0.0001;
GO

PRINT N'【查询】第 4 周多表连接查询实战脚本执行完毕。';
GO
