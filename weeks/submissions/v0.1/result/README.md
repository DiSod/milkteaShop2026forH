# result · v0.1 结果证据

> ⭐ 课程要求的结果目录：「**成功建库的截图，正常用例、非法数据、越权访问和关键查询结果截图。
> CRUD 的结果截图，不同的统计视图与不同角色之间权限结果截图。之前每周任务中的要求也要包含。**」
>
> ⚠️ **截图只是证据**（课程第 63 行）—— 每张图都必须在 `code/` 里有**可重新执行的 SQL 脚本**。
> 因此本目录的每一张 `.png` 都配一份同名 `.txt`（原始运行输出），图糊了也能查。

---

## 命名与配对规则

| 规则 | 说明 |
|---|---|
| 文件名 | **全英文、全小写、`-` 连接**（[`01-layout-and-naming.md`](../../../../harness/conventions/01-layout-and-naming.md) §1） |
| 配对 | `xxx.png`（图）+ `xxx.txt`（同一次运行的原始输出） |
| 可溯源 | 每张图必须在**下表**登记：对应哪条命令、预期结果是什么 |

---

## 一、`01-build/` —— 成功建库

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `rebuild-object-summary.png` | `cd project\sql` → `sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 99-rebuild.sql` | 末尾汇总：**17 表 / 132 字段 / 30 外键 / 43 CHECK / 21 索引 / 5 视图 / 4 角色** |
| `rebuild-full-log.png` | 同上（完整输出） | 00→04→07→08 全部 `【重建】` 阶段无报错 |
| `db-settings.png` | `SELECT name, collation_name, compatibility_level, recovery_model_desc FROM sys.databases WHERE name='milktea_shop'` | `Chinese_PRC_CI_AS` / **160** / `SIMPLE` |

## 二、`02-crud/` —— 正常用例（含**执行前后**）

> 课程第 3 周作业要求「展示典型操作**及执行前后的结果**」——
> 所以每张图必须**同时看到改动前与改动后的值**。

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `crud-create-member.png` | `crud.sql` §1 新增会员 | `DEMO-M1` 入库，`member_code` 唯一 |
| `crud-create-order.png` | `crud.sql` §1 下单（含反冲倒扣） | 订单头 + 明细 + 加料写入，总库扣减 |
| `crud-read-menu.png` | `crud.sql` §2 查菜单 | 在售成品列表 |
| `crud-read-order-full.png` | `crud.sql` §2 订单全貌 | 订单 → 明细 → 加料多表串联 |
| `crud-read-ledger-by-type.png` | `crud.sql` §2 台账按类型汇总 | 期初 / 采购 / 销售 / 报损 分列 |
| `crud-update-price.png` | `crud.sql` §3.1 调价 12.00 → 13.00 | **改动前 12.00、改动后 13.00 同屏** |
| `crud-update-offsale.png` | `crud.sql` §3.2 下架改状态 | `ON_SALE` → `OFF_SALE`，**历史订单明细完好** |
| `crud-update-order-state.png` | `crud.sql` §3.3 状态机 | `PENDING → MAKING → READY → COMPLETED` |
| `crud-delete-ok.png` | `crud.sql` §4.1 删除无引用会员 | 删除成功 |
| `crud-delete-blocked.png` | `crud.sql` §4.2 删除有订单引用的商品 | **被外键拒绝** → "下架不删行"的技术理由 |

## 三、`03-invalid/` —— 非法数据被拒绝 ⭐

> 课程展示重点第一条：**非法数据被拒绝**。`crud.sql` §1.7 有 **5 个负例**，全部由 `TRY...CATCH` 断言。

| 文件 | 非法数据 | 应被哪条约束拒绝 |
|---|---|---|
| `neg-1-qty-negative.png` | 原料库存改为负数 | **`ck_ingredient_qty_on_hand`** |
| `neg-2-bad-position.png` | 员工岗位填非法枚举 | **`ck_employee_position`** |
| `neg-3-fk-missing-product.png` | 配方引用不存在的商品 | **`fk_recipe_product`** |
| `neg-4-duplicate-member-code.png` | 会员号重复 | **`uq_member_code`**（候选码） |
| `neg-5-ledger-ref-mismatch.png` | 流水来源判别列与真外键不一致 | **`ck_stock_ledger_ref_consistency`**（D-09 判别列） |

## 四、`04-query/` —— 关键查询结果

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `q1-supply-chain-4level.png` | `query.sql` Q1 | 供应商 → 采购单 → 员工 → 采购明细 → 原料 → 入库流水（**跨 6 表**） |
| `q2a-topping-penetration.png` | `query.sql` Q2a | 加料渗透率 TOP 10 |
| `q2b-sugar-ice-preference.png` | `query.sql` Q2b | 甜度 × 冰度组合 TOP 10 |
| `q3-category-sales-rank.png` | `query.sql` Q3 | 品类与单品销售总榜（**窗口函数**） |
| `q4-ledger-balance.png` | `query.sql` Q4 | 期初+采购−销售−报损 = 实存，**逐原料平账** |
| `q4-balance-assertion.png` | `query.sql` Q4 汇总断言 | **0 条不平记录**（60 / 60 原料零差额） |

## 五、`05-view/` —— 不同统计视图

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `view-product-availability.png` | `SELECT TOP 20 * FROM vw_product_stock_availability` | **"还能做几杯"**（木桶短板理论） |
| `view-ingredient-reorder-alert.png` | `SELECT * FROM vw_ingredient_reorder_alert` | 缺料与采购预警 |
| `view-daily-business-summary.png` | `SELECT * FROM vw_daily_business_summary` | 每日经营日报 |
| `view-member-consumption-profile.png` | `SELECT TOP 20 * FROM vw_member_consumption_profile` | 会员消费画像与分级 |
| `view-order-detail-full.png` | `SELECT TOP 20 * FROM vw_order_detail_full` | 订单全景明细宽表 |

## 六、`06-security/` —— 角色权限与越权失败 ⭐

> 课程展示重点第二条：**越权操作失败**。`role.sql` 有 **3 组负例**，全部被 `Error 229` 拦截。

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `role-permission-matrix.png` | `SELECT r.name, p.permission_name, OBJECT_NAME(p.major_id) FROM sys.database_permissions …` | **4 个角色的赋权矩阵**（`role_manager` / `role_cashier` / `role_maker` / `role_stocker`） |
| `role-member-roles.png` | `SELECT r.name, m.name FROM sys.database_role_members …` | 每个角色绑定一个 `WITHOUT LOGIN` 测试主体 |
| `neg-1-cashier-alter-recipe.png` | `role.sql` 负例 1 | **收银员**篡改 `tbl_recipe` → ❌ `Error 229` |
| `neg-2-maker-read-member.png` | `role.sql` 负例 2 | **制作员**窥探 `tbl_member` → ❌ `Error 229` |
| `neg-3-stocker-delete-order.png` | `role.sql` 负例 3 | **库管员**删除 `tbl_order_header` → ❌ `Error 229` |
| `role-allow-vs-deny.png` | 同一角色的"允许"与"拒绝"对照 | **最小权限**的正反例同屏 |

---

## 七、合计

| 目录 | 张数 |
|---|---:|
| `01-build/` | 3 |
| `02-crud/` | 10 |
| `03-invalid/` | 5 |
| `04-query/` | 6 |
| `05-view/` | 5 |
| `06-security/` | 6 |
| **合计** | **35** |

---

## 八、生成方式

本目录的内容由脚本生成，便于**重跑刷新**：

```powershell
cd weeks\submissions\v0.1\result
pwsh -File capture.ps1              # 跑全部并生成 .txt
pwsh -File capture.ps1 -Only 03     # 只跑某一组
```

> `capture.ps1` 做两件事：
> ① 逐条执行上表命令，把 sqlcmd 的原始输出写成同名 **`.txt`**；
> ② 把 `.txt` 渲染成 **`.png`**（等宽字体、深色底，便于阅读与打印）。
>
> **为什么渲染而不是手工截屏**：结果**可复现、可重跑、可 diff** ——
> 换一台机器跑 `capture.ps1` 能生成同一批图，符合课程「可复现」的要求。
