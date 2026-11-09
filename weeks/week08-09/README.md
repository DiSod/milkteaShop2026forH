# 第 8—9 周 · 应用开发（二）与阶段二交付

> 本文件把**第 8 周与第 9 周合并记录**：这两周的工作在时间上是连续的（同一套应用、
> 同一批迁移与文档），拆成两份周报会产生大量重复的背景说明，反而更难读。
> 目录索引里第 8、9 两周都指向这里。
>
> 时间范围：2026-11-05 — 2026-11-09　·　对应课程 ch8 应用开发（二）

---

## 一、这两周的目标

课程第 7—9 周的七项任务里，第 7 周已完成 ①②③④⑤ 的骨架与单侧界面，
**剩下的是「(二) 面向角色的操作界面、事务边界、集成测试」与阶段交付**：

| 课程要求 | 第 7 周末的状态 | 本阶段补到 |
|---|---|---|
| ④ 业务层与请求处理 | 登录 / 商品查询 / 订单创建与查询 | + 商品维护、库存查询与调整、收货、报损、报表 |
| ⑤ 界面增删改查 | 顾客侧「查 + 增」 | + 店员侧「改」，删以下架承载 |
| ⑥ 角色界面 | 顾客 + 制作员 | + 收银员 / 库管员 / 店长 |
| ⑦ 集成测试与交付 | 17 条应用测试 | + 41 条应用测试 + 30 组证据 + 交付材料 |

---

## 二、应用（`project/app/`）

### 2.1 从 9 条路由到 20 条

| 层 | 第 7 周 | 现在 |
|---|---|---|
| `dao/` | 4 个模块 | **10 个 .py**（8 个 DAO + `db` / `errors`；+ `product_dao` / `stock_dao` / `purchase_dao` / `report_dao`） |
| `service/` | 5 个模块 | **9 个**（+ `admin` / `stock` / `cashier` / `cancel` 并入 `ordering`） |
| `web/` 路由 | 9 条 | **20 条**（+ 收银台、库管台、店长台、取消订单） |
| 模板 | 8 个 | **13 个**（+ `_menu_cards.html`、`_cart_shell.html`、三个工作台） |
| 测试 | 17 条 | **41 条**（结构 8 / 权限 9 / 岗位工作台 21 / 订单取消 3） |

### 2.2 三个新工作台

- **收银台 `/cashier`**：手机号留空 = 散客单（`member_id` 为 NULL，不产生积分）；复用会员侧的菜单卡片。
- **库管台 `/stocker`**：待收货明细（5 条）+ 低于补货点（5 条）+ 库存全量表（折叠，按「需处理程度」排序）。
  收货写 `PURCHASE_IN`、报损写 `LOSS`，两者都只经 `stock_dao.apply_movement()` —— 这是"改数量必留流水"的唯一入口。
- **店长台 `/manager`**：经营日报 + 销量 Top 10 + 两张图表（Chart.js 4.4.1 本地 vendored）+ 商品维护
  （建档 / 改价 / 改状态 / 下架）。**商品「删除」以下架承载** —— `tbl_order_detail.product_id` 有外键，硬删会打穿历史订单。

### 2.3 岗位与数据库权限的一致性

四个岗位与 `ck_employee_position` 严格一一对应，登录后按岗位跳转到各自工作台：

| 岗位 | 账号 | 落地页 | 数据库身份 |
|---|---|---|---|
| MANAGER | `E001` / `e001` | `/manager`（四个工作台都能进） | `usr_test_manager` |
| CASHIER | `E002` / `e002` | `/cashier` | `usr_test_cashier` |
| MAKER | `E003`、`E004` | `/maker` | `usr_test_maker` |
| STOCKER | `E005` | `/stocker` | `usr_test_stocker` |

跨岗位访问在**三个层面**都被挡住：界面不显示入口、业务层 `@staff_required` 抛 `PermissionDenied`、
数据库 `EXECUTE AS USER` 返回原生 **229**（被翻成 403）。测试断言的是**文案**而非仅状态码 ——
因为数据层的 229 翻译后也是 403，只看状态码分不清是哪一层拦的。

---

## 三、订单取消（第 9 周补的写操作）

第 7 周留下一个死胡同：状态机只有 `PENDING → MAKING → READY → COMPLETED`，
**任何角色都没有取消入口**，演示时下错单只能一路推到完成。

补法（`migration-06` + `service/ordering.cancel_order`）：

| 维度 | 做法 |
|---|---|
| 允许范围 | **只有 `PENDING`**。`MAKING` 之后原料已进杯子，回冲就是假账 |
| 库存 | 按该单 `SALES_USE` 流水反向写 `CANCEL_BACK`，经 `apply_movement` → 保住 A6 `qty_on_hand = Σ流水` |
| 积分 | 写 `REVOKE` 流水并扣回余额（新流水类型，不是删旧行） |
| 券 | 该单券已核销 → **拒绝**，提示人工处理（退券属 v2.0） |
| 并发 | 靠 `UPDATE … WHERE order_status='PENDING'` 的受影响行数判断，=0 即"已被别人改过" |
| 入口 | 会员在 `/orders` 取消自己的单；制作台/店长台可取消队列里的任意待制作单（含散客单） |

**结构变更**：新增 `CANCEL_BACK` / `REVOKE` 两类流水值，改写三条 CHECK；
`CHECK` 总数仍 **48**，三条约束均 `is_disabled=0` / `is_not_trusted=0`。

---

## 四、界面：全站 Material Design 3

第 9 周把界面整体重做为 MD3 视觉层（薄荷绿 `#146b56`），**不换排版引擎**：

- 只写 `static/css/app.css` 一个文件（约 1,000 行）+ 改 13 个模板，Bootstrap 栅格与工具类照旧生效；
- 全部资源本地 vendored（Bootstrap 5.3.3 / Bootstrap Icons 1.11.3 / Roboto / Chart.js 4.4.1），
  **无 CDN、无构建步骤**；
- 菜单从「商品 × 杯型」大表改成**卡片 + 弹窗**：点一杯饮品弹出对话框选杯型/糖度/冰量/加料，
  底部悬浮栏汇总已选金额，点开是购物车抽屉；
- **无 JS 也能提交**：购物车状态存在对话框原生的 `qty` select 上，提交的仍是平行列表，`_parse_items` 一行没改。

过程中修掉 6 个真 bug（详见 `harness/issues/015`）：补货预警整列空白、`GET /order` 被兜底吞成 500、
购物车面板被 Bootstrap 的 `.offcanvas.offcanvas-bottom` 压住、店长商品档案表被压扁、
403 页错误条渲染两次、趋势图 46 天断档。

---

## 五、验证（第 9 周末实测）

| 项 | 结果 |
|---|---|
| `pytest -q` | **41 passed** |
| `regression.sql -b` | **14/14 全绿** |
| 三份基线快照 | S1 80 / S2 62 / S3 151 = **293 行，差异 0** |
| `99-rebuild.sql` | `exit=0`，**25.4 秒** → 18 表 / 139 字段 / 31 外键 / **48 CHECK** / 22 索引 / 6 视图 / 4 角色 |
| 库不变量 | `order_header` 1,963 · `stock_ledger` 13,851 · `SUM(qty_on_hand)` 403,371.600 · 积分 25,224 = 25,224 · drift **0** |
| 证据 | `weeks/submissions/v1.0/result/` **30 组**（19 数据库类 + 11 应用类） |

---

## 六、这两周暴露的问题与处理

| # | 问题 | 处理 |
|---|---|---|
| 1 | 补货预警表整列空白 | `stock_dao.list_alerts` 只 SELECT 11 列，模板却用 `a[12]`；同时漏了 `WHERE alert_priority < 5`，把 55 条「库存健康」算进「低于补货点」→ 一并修 |
| 2 | 店长商品档案表被压扁 | 编辑表单原在「名称」单元格内 → 挪进独立的「操作」列 |
| 3 | `GET /order` 返回 500 而非 405 | 兜底 `errorhandler(Exception)` 吞掉 `HTTPException` → 补 `@app.errorhandler(HTTPException)` |
| 4 | 购物车面板只露两行 | `.cart-sheet`（0,1,0）压不住 `.offcanvas.offcanvas-bottom`（0,2,0）→ 改 `.offcanvas.cart-sheet` |
| 5 | 趋势图 46 天断档 | 种子数据到 09-23，演示单在 11-08，中间无记录 → 插占位标签 `09-24~11-07` + `spanGaps:false` |
| 6 | `regression.sql` TC-10 变红 | 断言把全库绝对数字写死 → 改为只断言 `business_date < '2026-10-01'` 的种子区间，运行期新增单只打印不断言 |

---

## 七、遗留（转第 11—12 周）

| 项 | 原因 |
|---|---|
| 退款 / 退券 | 取消已做，退款涉及资金流与券状态回退，属事务与程序对象章节 |
| 下单下沉存储过程 + `EXECUTE AS OWNER` | 当前跨域写入走 `dbo`（P-2） |
| 行级数据隔离（RLS） | 表级授权数据库会真查，行级只能靠应用 `WHERE`（P-3） |
| 并发抢库存的严格防护 | 现为"先查后扣"，未加 `UPDLOCK` / 序列化 |
| 连接失败 503 与事务失败 500 的故障注入 | 已定义异常与页面，但没有构造真实故障 |
| 盘点（`STOCKTAKE`） | 需补两张表，第 6 周明确延后 |

---

## 八、产出落点

| 产出 | 位置 |
|---|---|
| 应用代码 | `project/app/`（`dao/` 10 · `service/` 9 · `web/` 8 · `tests/` 5 个 .py；20 条路由 / 13 个模板） |
| 迁移 06 | `project/sql/11-migration/migration-06-order-cancellation.sql` |
| 集成测试 | `project/app/tests/`（41 条）+ `project/tests/regression.sql`（14 项） |
| 证据 | `weeks/submissions/v1.0/result/`（30 组，`capture.ps1` / `capture-app.ps1` 可重跑） |
| 交付材料 | `weeks/submissions/v1.0/`（README / report / ai-log / code / result） |
| 变更记录 | `harness/issues/015`（界面重构）、`017`（已知边界存档）、`018`（订单取消） |
