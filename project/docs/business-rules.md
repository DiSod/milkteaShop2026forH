# 业务规则与映射清单

> **产出周**：第 5 周（ch6 ER 模型）
> **课程依据**：[`course/lecture-week05.md`](../../course/lecture-week05.md) —— 本周作业第 2 项：
> 「逐项写明联系两端的**最小/最大基数**、**适用条件**、**对应表和外码**，以及当前由**约束、代码或人工检查**实现的规则。」
> **配套**：[`er-diagram.md`](er-diagram.md)（ER 图）· [`v0.1-issues.md`](v0.1-issues.md)（问题清单）
> **真相源**：表结构 → [`data-dictionary.md`](data-dictionary.md)；实际 DDL → `project/sql/01-schema/`、`02-constraints/`

---

## 0. 三层实现划分（本清单的判读框架）

课程要求区分「**约束 / 代码 / 人工检查**」三种实现。本项目定为三段，**每条规则必须落在其中一段**：

| 实现层 | 落点 | 特点 |
|---|---|---|
| **① 数据库约束** | `01-schema/` + `02-constraints/` | **强制的**，绕过应用也拦得住 → **首选** |
| **② 应用代码** | `05-dml/crud.sql`、后续 `project/app/` | 易被绕过（直接写库就失效）；需要事务保证 |
| **③ 人工检查** | 值班流程 / 盘点 | 最弱，**只用于数据库确实表达不了的规则** |

> ⚠️ **本项目立场**：能进第 ① 层的绝不放到第 ②③ 层。
> 课程第 4 周就点过：「完整性约束要在数据库中真正生效，**不能只在报告中写一条业务规则**」。

---

## 1. 规则总览：实现层分布

| 实现层 | 条数 | 说明 |
|---|---|---|
| ① 数据库约束 | **52** | 43 `CHECK` + 30 `FK`（含基数方向）+ 17 `UNIQUE` 中的业务码部分 |
| ② 应用代码 | **7** | 见 §4 —— **其中 3 条是数据库表达不了的** |
| ③ 人工检查 | **2** | 见 §5 |

---

## 2. 联系基数清单（课程要求的主体）

> **(min, max)** 写法：`min` = 必须参与填 1，可选填 0；`max` = 多端填 N，单端填 1。
> 「外码/表」列给出**该规则在库中的落点** —— 图上的每条线都能追到这。

| # | 联系 | 两端实体 | 左端 (min,max) | 右端 (min,max) | 对应表与外码 | 适用条件 |
|---|---|---|---|---|---|---|
| 1 | 收银 | 员工 — 订单 | (0,N) | **(1,1)** | `tbl_order_header.cashier_id` → `fk_order_header_cashier` | 所有订单，无例外 |
| 2 | 包含 | 订单 — 订单明细 | (1,1) | **(0,N)** ⚠️ | `tbl_order_detail.order_id` → `fk_order_detail_order` | ⚠️ **右端业务应为 (1,N)**，库中做不到，见 §4 规则 A1 |
| 3 | 下单 | 会员 — 订单 | (0,N) | **(0,1)** | `tbl_order_header.member_id` → `fk_order_header_member` | **散客可下单**，故可空 |
| 4 | 被点 | 商品 — 订单明细 | (0,N) | **(1,1)** | `tbl_order_detail.product_id` → `fk_order_detail_product` | 所有明细 |
| 5 | 加料 | 订单明细 — 加料明细 | (0,N) | **(1,1)** | `tbl_order_detail_topping.order_detail_id` → `fk_order_detail_topping_order_detail` | 左端可 0：**不加小料则无行** |
| 6 | 选用 | 小料 — 加料明细 | (0,N) | **(1,1)** | `tbl_order_detail_topping.topping_id` → `fk_order_detail_topping_topping` | |
| 7 | 规格 | 规格选项 — 订单明细（杯/糖/冰 3 个外码） | (0,N) | **(0,1)** 各 | `cup_spec_id`/`sugar_spec_id`/`ice_spec_id` → `fk_order_detail_cup_spec` 等 3 个 | **可空**：未指定规格时留空 |
| 8 | 归类 | 品类 — 商品 | (0,N) | **(1,1)** | `tbl_product.category_id` → `fk_product_category` | |
| 9 | 上级（自引用） | 品类 — 品类 | (0,N) | **(0,1)** | `tbl_product_category.parent_category_id` → `fk_product_category_parent_category` | **顶级品类为空** |
| 10 | 持有 | 会员 — 券 | (0,N) | **(1,1)** | `tbl_coupon.member_id` → `fk_coupon_member` | **本店不发匿名券** |
| 11 | 用券 | 券 — 订单 | (0,N) | **(0,1)** | `tbl_order_header.coupon_id` → `fk_order_header_coupon` | 可不用券 |
| 12 | 配方 | 商品 — 配方 | (0,N) | **(1,1)** | `tbl_recipe.product_id` → `fk_recipe_product` | 有配方才有行 |
| 13 | 杯型维 | 规格选项 — 配方 | (0,N) | **(1,1)** | `tbl_recipe.cup_spec_id` → `fk_recipe_cup_spec` | **NOT NULL**：配方必须绑定杯型 |
| 14 | 糖度维 | 规格选项 — 配方 | (0,N) | **(0,1)** | `tbl_recipe.sugar_spec_id` → `fk_recipe_sugar_spec` | ⭐ **可空** = 「该原料用量与糖度无关」（D-05a） |
| 15 | 用料 | 原料 — 配方 | (0,N) | **(1,1)** | `tbl_recipe.ingredient_id` → `fk_recipe_ingredient` | |
| 16 | 取材 | 原料 — 小料 | (0,N) | **(1,1)** | `tbl_topping.ingredient_id` → `fk_topping_ingredient` | |
| 17 | 供货 | 供应商 — 采购单 | (0,N) | **(1,1)** | `tbl_purchase_order.supplier_id` → `fk_purchase_order_supplier` | **消除「向空气采购」**（ISSUE-003） |
| 18 | 采购下单 | 员工 — 采购单 | (0,N) | **(1,1)** | `tbl_purchase_order.ordered_by` → `fk_purchase_order_ordered_by` | |
| 19 | 采购收货 | 员工 — 采购单 | (0,N) | **(0,1)** | `tbl_purchase_order.received_by` → `fk_purchase_order_received_by` | **可空**：尚未到货 |
| 20 | 采购明细 | 采购单 — 采购明细 | (0,N) | **(1,1)** | `tbl_purchase_order_detail.purchase_order_id` → `fk_purchase_order_detail_purchase_order` | ⚠️ **左端业务应为 (1,N)**，同规则 A1 |
| 21 | 采购物 | 原料 — 采购明细 | (0,N) | **(1,1)** | `tbl_purchase_order_detail.ingredient_id` → `fk_purchase_order_detail_ingredient` | |
| 22 | 流水对象 | 原料 — 库存流水 | (0,N) | **(1,1)** | `tbl_stock_ledger.ingredient_id` → `fk_stock_ledger_ingredient` | |
| 23 | 采购来源 | 采购单 — 库存流水 | (0,N) | **(0,1)** | `tbl_stock_ledger.purchase_order_id` → `fk_stock_ledger_purchase_order` | 多态来源，见规则 D1 |
| 24 | 销售来源 | 订单 — 库存流水 | (0,N) | **(0,1)** | `tbl_stock_ledger.order_id` → `fk_stock_ledger_order` | 同上 |
| 25 | 经手人 | 员工 — 库存流水 | (0,N) | **(0,1)** | `tbl_stock_ledger.operator_id` → `fk_stock_ledger_operator` | ⭐ **可空 = 系统自动反冲扣料** |
| 26 | 积分归属 | 会员 — 积分流水 | (0,N) | **(1,1)** | `tbl_points_ledger.member_id` → `fk_points_ledger_member` | |
| 27 | 积分来源单 | 订单 — 积分流水 | (0,N) | **(0,1)** | `tbl_points_ledger.order_id` → `fk_points_ledger_order` | REDEEM 类可能无来源单 |
| 28 | 兑换所得券 | 券 — 积分流水 | (0,N) | **(0,1)** | `tbl_points_ledger.coupon_id` → `fk_points_ledger_coupon` | |

> **合计**：本节 28 段**业务联系** ↔ 全库 **30 个外码**。
> 差异来源：第 7 行把「订单明细的杯型 / 糖度 / 冰量」**三个独立外码合并成 1 段**规格联系
> （业务上是一个"选规格"动作，物理上是 3 个 FK）。
> **ER 图上按物理外码画 30 条线**，逐条对应见 [`er-diagram.md`](er-diagram.md) §2.1。

---

## 3. 全部 30 个外码（可逐条追溯到 DDL）

| # | 约束名 | 表.列 → 目标 | 列可空 | 决定的最小基数 |
|---|---|---|---|---|
| 1 | `fk_order_detail_order` | `tbl_order_detail.order_id` → `tbl_order_header` | 否 | 明细必属订单 |
| 2 | `fk_order_detail_product` | `tbl_order_detail.product_id` → `tbl_product` | 否 | 明细必有商品 |
| 3 | `fk_order_detail_cup_spec` | `tbl_order_detail.cup_spec_id` → `tbl_spec_option` | **是** | 规格可空 |
| 4 | `fk_order_detail_sugar_spec` | `tbl_order_detail.sugar_spec_id` → `tbl_spec_option` | **是** | 规格可空 |
| 5 | `fk_order_detail_ice_spec` | `tbl_order_detail.ice_spec_id` → `tbl_spec_option` | **是** | 规格可空 |
| 6 | `fk_order_detail_topping_order_detail` | `tbl_order_detail_topping.order_detail_id` → `tbl_order_detail` | 否 | 加料必属明细 |
| 7 | `fk_order_detail_topping_topping` | `tbl_order_detail_topping.topping_id` → `tbl_topping` | 否 | 加料必是小料 |
| 8 | `fk_order_header_member` | `tbl_order_header.member_id` → `tbl_member` | **是** | 散客可下单 |
| 9 | `fk_order_header_coupon` | `tbl_order_header.coupon_id` → `tbl_coupon` | **是** | 可不用券 |
| 10 | `fk_order_header_cashier` | `tbl_order_header.cashier_id` → `tbl_employee` | 否 | 订单必有收银员 |
| 11 | `fk_purchase_order_supplier` | `tbl_purchase_order.supplier_id` → `tbl_supplier` | 否 | 采购必有供应商 |
| 12 | `fk_purchase_order_ordered_by` | `tbl_purchase_order.ordered_by` → `tbl_employee` | 否 | 采购必有下单人 |
| 13 | `fk_purchase_order_received_by` | `tbl_purchase_order.received_by` → `tbl_employee` | **是** | 未到货为空 |
| 14 | `fk_purchase_order_detail_purchase_order` | `tbl_purchase_order_detail.purchase_order_id` → `tbl_purchase_order` | 否 | 明细必属采购单 |
| 15 | `fk_purchase_order_detail_ingredient` | `tbl_purchase_order_detail.ingredient_id` → `tbl_ingredient` | 否 | 明细必有物料 |
| 16 | `fk_coupon_member` | `tbl_coupon.member_id` → `tbl_member` | 否 | 券必有会员 |
| 17 | `fk_points_ledger_member` | `tbl_points_ledger.member_id` → `tbl_member` | 否 | 流水必有会员 |
| 18 | `fk_points_ledger_order` | `tbl_points_ledger.order_id` → `tbl_order_header` | **是** | 可无来源单 |
| 19 | `fk_points_ledger_coupon` | `tbl_points_ledger.coupon_id` → `tbl_coupon` | **是** | 可非兑换类 |
| 20 | `fk_stock_ledger_ingredient` | `tbl_stock_ledger.ingredient_id` → `tbl_ingredient` | 否 | 流水必有原料 |
| 21 | `fk_stock_ledger_purchase_order` | `tbl_stock_ledger.purchase_order_id` → `tbl_purchase_order` | **是** | 多态来源之一 |
| 22 | `fk_stock_ledger_order` | `tbl_stock_ledger.order_id` → `tbl_order_header` | **是** | 多态来源之一 |
| 23 | `fk_stock_ledger_operator` | `tbl_stock_ledger.operator_id` → `tbl_employee` | **是** | 空 = 系统反冲 |
| 24 | `fk_product_category` | `tbl_product.category_id` → `tbl_product_category` | 否 | 商品必有品类 |
| 25 | `fk_product_category_parent_category` | `tbl_product_category.parent_category_id` → `tbl_product_category` | **是** | 顶级品类无父 |
| 26 | `fk_topping_ingredient` | `tbl_topping.ingredient_id` → `tbl_ingredient` | 否 | 小料必取材 |
| 27 | `fk_recipe_product` | `tbl_recipe.product_id` → `tbl_product` | 否 | 配方必属商品 |
| 28 | `fk_recipe_cup_spec` | `tbl_recipe.cup_spec_id` → `tbl_spec_option` | 否 | 配方必有杯型 |
| 29 | `fk_recipe_sugar_spec` | `tbl_recipe.sugar_spec_id` → `tbl_spec_option` | **是** | ⭐ 空 = 与糖度无关 |
| 30 | `fk_recipe_ingredient` | `tbl_recipe.ingredient_id` → `tbl_ingredient` | 否 | 配方必有原料 |

> **验证**：30 个约束名**全部符合** `fk_<表>_<列>` 命名规范（`02-sql-style.md` §3.1）。

---

## 4. 数据库**表达不了**、需代码或人工兜底的规则（⭐ 重点）

> 这一节是本次清单**最有价值的部分** —— 课程明确提示「**请区分数据库现有约束与业务要求**」。
> 以下每条都是「**业务上成立、但 v0.1 的库里拦不住**」的规则。

| # | 业务规则 | 为什么库拦不住 | 当前实现 | 计划 |
|---|---|---|---|---|
| **A1** | **每张订单至少含一条明细** | 子表向父表建外码，**无法约束父端必须有一个子端**（标准 SQL 无「至少一」约束） | `crud.sql` 应用逻辑显式插入 | 第 6 周迁移候选（触发器或事务封装） |
| **A2** | **每张采购单至少含一条明细** | 同 A1 | 应用逻辑 | 同 A1 |
| **A3** | **`order_header` 金额 = Σ 明细 `subtotal`** | 跨行聚合，`CHECK` 不能引用其他行 | 应用计算后写入 | 第 6 周事务/触发器 |
| **A4** | **`tbl_member.points_balance` = Σ 积分流水** | 同上（冗余字段，D-12 有意保留） | 事务维护 | 同上 |
| **A5** | **一券只能用一次** | `status`/`used_time` 有 `CHECK` 保证**取值合法**，但「只能改一次」是**状态转换**约束 | 应用逻辑 | 第 6 周 |
| **A6** | **`tbl_ingredient.qty_on_hand` = 期初 + Σ 流水** | 同上，跨行聚合 | 造数引擎保证 + 审计查询验证 | v1.0 校准 |
| **A7** | **券核销时间必须落在有效期内** | `used_time` 与 `valid_from/valid_to` 的跨列关系**未建 CHECK** | 应用逻辑 | ⭐ **可低成本补 `CHECK`**，建议第 6 周加 |

### ⚠️ 一个值得单独记录的教训

**A7 是本轮新发现的**：`ck_coupon_valid_period` 只保证 `valid_to > valid_from`，
**没有任何约束保证 `used_time` 落在区间内** —— 理论上可以写出一张「在过期后 3 天才被核销」的券。
这是**低成本的补强点**（一条 `CHECK` 即可），建议纳入第 6 周迁移清单。

---

## 5. 人工检查层（仅 2 条）

| # | 规则 | 为什么只能人工 | 频度 |
|---|---|---|---|
| **M1** | **实物损溢（蒸发 / 滴漏 / 挂壁）** | 物理现象**不可由数据库推导**，只能靠盘点发现 | 打烊盘点 → v1.0 走 `tbl_stocktake` |
| **M2** | **原料品质与保质期** | v0.1 **未建批次维度**（D-06 有意延后），库里根本没有这个属性 | 收货时人工验收 |

> M1 正是第 6 周模式重构的**业务动机** —— 见 [`data/README.md`](../data/README.md) §五。

---

## 6. 数据库约束全量清单（43 个 `CHECK`）

> 供逐条核对「规则是否真的在库里生效」。分三类。

### 6.1 枚举域约束（13 个，对应数据字典 DOM-01 ～ DOM-16）

| 约束名 | 表 | 表达式 |
|---|---|---|
| `ck_employee_position` | `tbl_employee` | `position IN ('MANAGER','CASHIER','MAKER','STOCKER')` |
| `ck_product_product_status` | `tbl_product` | `product_status IN ('ON_SALE','OFF_SALE')` |
| `ck_order_header_order_status` | `tbl_order_header` | `order_status IN (6 值)` |
| `ck_stock_ledger_ledger_type` | `tbl_stock_ledger` | `ledger_type IN ('PURCHASE_IN','SALES_USE','LOSS')` |
| `ck_stock_ledger_ref_type` | `tbl_stock_ledger` | `ref_type IN ('PURCHASE','ORDER','MANUAL','OPENING')` |
| `ck_order_header_pay_method` | `tbl_order_header` | `pay_method IS NULL OR IN (4 值)` |
| `ck_order_header_pay_status` | `tbl_order_header` | `pay_status IS NULL OR IN ('SUCCESS','FAILED')` |
| `ck_coupon_source` | `tbl_coupon` | `source IN ('POINTS_EXCHANGE','CAMPAIGN')` |
| `ck_coupon_status` | `tbl_coupon` | `status IN ('UNUSED','USED','EXPIRED')` |
| `ck_points_ledger_point_type` | `tbl_points_ledger` | `point_type IN ('EARN','REDEEM')` |
| `ck_spec_option_spec_type` | `tbl_spec_option` | `spec_type IN ('CUP','SUGAR','ICE')` |
| `ck_purchase_order_order_status` | `tbl_purchase_order` | `order_status IN (5 值)` |
| `ck_spec_option_code_by_type` | `tbl_spec_option` | ⭐ **规格码必须与规格类型匹配**（`CUP` 只能是 `M`/`L`）：`(spec_type='CUP' AND code IN ('M','L')) OR (spec_type='SUGAR' AND …) OR (spec_type='ICE' AND …)` |

> ℹ️ `ck_spec_option_code_by_type` 形式上是「跨字段」，**实质是域约束** ——
> 它保证的是「规格码这个域的取值**依赖于**规格类型」，属 DOM-11/12/13 的完整落地。

### 6.2 跨字段一致性约束（5 个 —— 业务规则的硬核部分）

| 约束名 | 表 | 保证的业务规则 |
|---|---|---|
| `ck_stock_ledger_ref_consistency` | `tbl_stock_ledger` | ⭐ **来源与来源单必须匹配**（`PURCHASE` 必有采购单且无订单，反之亦然） |
| `ck_points_ledger_target` | `tbl_points_ledger` | ⭐ **EARN 必有来源单；REDEEM 必有券或订单**（ISSUE-008 修复的死锁点） |
| `ck_order_header_finish_time` | `tbl_order_header` | 完成时间 ≥ 下单时间 |
| `ck_purchase_order_arrival_date` | `tbl_purchase_order` | 到货日期 ≥ 下单日期 |
| `ck_coupon_valid_period` | `tbl_coupon` | 有效期 `valid_to > valid_from` ⚠️ **不含 `used_time`，见 §4 规则 A7** |

### 6.3 非负 / 非零约束（25 个，逐条列名以保证可核对）

| # | 约束名 | 表 | 表达式 |
|---|---|---|---|
| 1 | `ck_ingredient_qty_on_hand` | `tbl_ingredient` | `qty_on_hand >= 0` |
| 2 | `ck_ingredient_reorder_point` | `tbl_ingredient` | `reorder_point >= 0` |
| 3 | `ck_ingredient_target_level` | `tbl_ingredient` | `target_level >= 0` |
| 4 | `ck_ingredient_moving_avg_cost` | `tbl_ingredient` | `moving_avg_cost >= 0` |
| 5 | `ck_member_points_balance` | `tbl_member` | `points_balance >= 0` |
| 6 | `ck_product_base_price` | `tbl_product` | `base_price >= 0` |
| 7 | `ck_spec_option_extra_price` | `tbl_spec_option` | `extra_price >= 0` |
| 8 | `ck_topping_extra_price` | `tbl_topping` | `extra_price >= 0` |
| 9 | `ck_topping_qty_per_serving` | `tbl_topping` | `qty_per_serving > 0` |
| 10 | `ck_recipe_qty` | `tbl_recipe` | `qty > 0` |
| 11 | `ck_order_detail_qty` | `tbl_order_detail` | `qty > 0` |
| 12 | `ck_order_detail_unit_price` | `tbl_order_detail` | `unit_price >= 0` |
| 13 | `ck_order_detail_subtotal` | `tbl_order_detail` | `subtotal >= 0` |
| 14 | `ck_order_detail_topping_qty` | `tbl_order_detail_topping` | `qty > 0` |
| 15 | `ck_order_detail_topping_unit_extra_price` | `tbl_order_detail_topping` | `unit_extra_price >= 0` |
| 16 | `ck_order_header_discount_amount` | `tbl_order_header` | `discount_amount >= 0` |
| 17 | `ck_order_header_amount_due` | `tbl_order_header` | `amount_due >= 0` |
| 18 | `ck_order_header_amount_paid` | `tbl_order_header` | `amount_paid >= 0` |
| 19 | `ck_coupon_discount_amount` | `tbl_coupon` | `discount_amount > 0` |
| 20 | `ck_coupon_min_order_amount` | `tbl_coupon` | `min_order_amount >= 0` |
| 21 | `ck_purchase_order_detail_qty_ordered` | `tbl_purchase_order_detail` | `qty_ordered > 0` |
| 22 | `ck_purchase_order_detail_qty_received` | `tbl_purchase_order_detail` | `qty_received >= 0` |
| 23 | `ck_purchase_order_detail_unit_price` | `tbl_purchase_order_detail` | `unit_price >= 0` |
| 24 | `ck_stock_ledger_qty_nonzero` | `tbl_stock_ledger` | `qty <> 0`（⚠️ **非 `> 0`**） |
| 25 | `ck_points_ledger_change_nonzero` | `tbl_points_ledger` | `point_change <> 0` |

> ⭐ **值得在答辩讲的一处**：第 24、25 条用 `<> 0` 而不是 `> 0` ——
> 因为库存/积分流水**用符号表达方向**（入库正、耗用负），
> 「数量不能为零」与「数量必须为正」是**两条不同的规则**。

**本节合计校验**：13 + 5 + 25 = **43** ✅ 与 `sys.check_constraints` 实测数一致。

---

## 7. 与 ER 图的对照检查

| 检查项 | 结果 |
|---|---|
| ER 图上的每条线都能追到外码？ | ✅ **30 条线 ↔ 30 个外码，一一对应**（`er-diagram.md` §2.1 有编号映射表） |
| 每个外码都有 (min,max)？ | ✅ §2 覆盖 28 段业务联系 / 30 个外码 |
| 每条规则都有实现层？ | ✅ ① 52 条 / ② 7 条 / ③ 2 条 |
| 有没有「写在文档里但库里不生效」的规则？ | ⚠️ **有 7 条**，全部列在 §4 —— **这正是第 6 周迁移的输入** |
