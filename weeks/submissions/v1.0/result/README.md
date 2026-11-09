# result · v1.0 结果证据

> ⭐ 课程要求的结果目录：「**成功建库的截图，正常用例、非法数据、越权访问和关键查询结果截图。
> CRUD 的结果截图，不同的统计视图与不同角色之间权限结果截图。之前每周任务中的要求也要包含。**」
>
> ⚠️ **截图只是证据** —— 每张图背后都必须有一条**可重新执行的命令**。
> 本目录的**数据库类**每一张 .png 都配一份同名 .txt（未经修改的 sqlcmd 原始输出），图糊了也能查、能 diff；**应用类**的原始输入是「登录会话 + 该页路由」，见上一节。

**本版共 31 组证据：19 组数据库类 + 12 组应用类。**

---

## ⚠️ 请先读这一节：两组截图、两种生成方式

| 组 | 目录 | 生成方式 | 一键复现 |
|---|---|---|---|
| **数据库类**（19 组） | `01-build/` … `06-security/` | [`render.ps1`](render.ps1) 把 **`sqlcmd` 的真实输出**渲染成图片 | [`capture.ps1`](capture.ps1) |
| **应用类**（12 组） | `07-app/` | [`capture-app.ps1`](capture-app.ps1) 用 HTTP 会话取回**渲染后的页面**，再用**无头 Edge** 截图 | 同上，需先启动 Flask |

### 为什么不用「手工点鼠标截屏」

| 理由 | 说明 |
|---|---|
| **可复现** | 换一台机器跑脚本能生成**同一批图**；手工截屏做不到 |
| **可核对** | 数据库类每张 .png 旁边有同名 .txt；应用类的输入是登录会话与该页路由，capture-app.ps1 可原样重跑 |
| **可 diff** | `.txt` 能进 git 做版本对比；图片不能 |
| **无人工步骤** | 不依赖"某个人当时记得截了哪一张、截得清不清楚" |

### 应用类截图**具体**是怎么来的（不掩饰）

`capture-app.ps1` 做四件事：

1. 用 `Invoke-WebRequest -WebSession` 以演示账号**真实登录**（会员 `13800000001` / 口令 `000001`；员工 `E002`/`E003`/`E005`/`E001`，口令为小写工号）；
2. `GET` 目标页面，把**服务端渲染出的 HTML** 落盘到 `project/app/web/static/__shot_<name>.html`；
3. 用无头 Edge 打开这个静态副本截图（资产都是 `/static/...` 绝对路径，样式与脚本照常加载；`--virtual-time-budget=5000` 保证图表动画播完）；
4. 删掉临时副本，`static/` 保持干净。

需要交互态（饮品对话框、购物车抽屉）的两张图，脚本会在副本里**注入一小段 JS** 把状态展开后再截 ——
这段 JS 只是"替人点了一下"，不影响页面本身的逻辑。

**它证明了什么 / 没证明什么**

| ✅ 能证明 | ❌ 不能证明 |
|---|---|
| 这些页面确实由**真实登录会话**在真实数据上渲染出来 | 不是人工在浏览器里逐个点出来的（但页面逻辑一致） |
| 权限隔离是真的（库管员访问 `/manager` 返回 **403**） | 没有覆盖并发、跨浏览器、移动端 |
| 渲染管线可一键重跑 | 不证明"用户体验好"，只证明"界面长这样" |

> 课程第 63 行明确「截图只能作为证据，提交内容仍要包含可以重新执行的 SQL 脚本」——
> 数据库类的可执行 SQL 在 `project/sql/` 与 `project/tests/`，应用类的可执行代码在 `project/app/`。

---

## 一、复现命令

```powershell
# 前置：数据库已按 README 的 14 步重建（99-rebuild.sql），Flask 未启动也能跑数据库类
cd weeks\submissions\v1.0\result

# 1) 数据库类 19 张（约 3 分钟；含一次完整 99-rebuild 日志）
powershell -ExecutionPolicy Bypass -File capture.ps1

# 2) 应用类 11 张（需先 cd project\app 并 python app.py）
powershell -ExecutionPolicy Bypass -File capture-app.ps1

# 只重跑某一组 / 只重截图片（源 .txt 已存在）
powershell -ExecutionPolicy Bypass -File capture.ps1 -Only 05-query
powershell -ExecutionPolicy Bypass -File capture.ps1 -Only 03-regression -SkipSource
powershell -ExecutionPolicy Bypass -File capture-app.ps1 -Only manager
```

---

## 二、`01-build/` —— 数据库建成后的形状

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `schema-object-summary.png` | `sys.*` 统计脚本（`capture.ps1` 内联） | **18 表 / 139 字段 / 18 主键 / 18 唯一约束 / 31 外键 / 48 CHECK / 22 业务索引 / 6 视图 / 4 自定义角色** |
| `db-settings.png` | `SELECT name, collation_name, compatibility_level, recovery_model_desc FROM sys.databases` | `Chinese_PRC_CI_AS` / **160** / `SIMPLE` |
| `table-row-counts.png` | 18 表逐表 `COUNT(*)` | 合计 **21,061** 行（订单 1,963 / 明细 2,629 / 加料 614 / 库存流水 13,851 / 积分流水 1,259） |

## 三、`02-migration/` —— 五段迁移的落地证据

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `coupon-split.png` | 券拆表后的列数与行数 | `tbl_coupon` **8 列**、`tbl_coupon_template` **8 列**、模板 2 行、券 24 张、模板外键悬空 **0**、兼容视图 `vw_coupon_legacy` 24 行 / **14 列** |
| `points-reconcile.png` | 会员余额 vs 积分流水 | 80 位会员：余额合计 **25,224** = 流水合计 **25,224**，`OPENING` 期初 **80** 条，**不符 0** |
| `time-constraints.png` | `sys.check_constraints` | `ck_order_header_pay_time` / `ck_order_header_finish_after_pay` 均 `is_disabled=0`、`is_not_trusted=0` |
| `time-constraints-rationale.png` | 约束定义 + 37 单反例 | 说明**为什么不加**「支付状态非空 ⇒ `pay_time` 非空」 |
| `price-precision.png` | 5 个单价/成本列的类型 | 全部 `decimal(12,4)`（`tbl_ingredient.moving_avg_cost`、`tbl_order_detail.unit_price`、`tbl_order_detail_topping.unit_extra_price`、`tbl_product.base_price`、`tbl_purchase_order_detail.unit_price`） |
| `rebuild-full-log.png` | `sqlcmd -i 99-rebuild.sql` 完整输出 | 12 段（00→01→02→03→04→07→08→11 五支）逐段 `【重建】`，无报错 |
| `rebuild-summary.png` | 同上末 16 行 | 汇总行与 `schema-object-summary.png` 一致 |

## 四、`03-regression/` —— 14 项回归断言

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `regression-verdict.png` | `sqlcmd -b -i project\tests\regression.sql` | 结论行：**14 项全绿** |
| `regression-pass-list.png` | 同上，只取 `[PASS]` 行 | 14 条，含「销售额 D 口径 1,926 单 / 23,762.00」「明细复算偏差 0」「积分 80 位自洽」 |
| `regression-full-log.png` | 同上，完整输出 | 每条断言的实际值都可核对 |

## 五、`04-baseline/` —— 迁移前后业务结果不变

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `compare-summary.png` | 重跑三份快照并与 `project/tests/baseline/result/after-S0*.txt` 逐行比对 | S1 **80/80**、S2 **62/62**、S3 **151/151**，合计 **293 行、差异 0** |

## 六、`05-query/` —— 三种销售额口径 / 库存不变量 / 销量榜

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `sales-caliber.png` | 三种口径同时算 | A 全量 **1,963 单 / 24,208.00**；B 仅 COMPLETED **1,894 / 23,363.00**；**D 仅 SUCCESS 1,926 / 23,762.00**；折扣 120.00 |
| `stock-invariant.png` | `qty_on_hand` vs `SUM(流水)` | 60 种原料，结存 **403,371.600** = 流水 **403,371.600**，不符 **0** |
| `top-products.png` | 销量 Top 10（口径 D） | 按 `SUM(subtotal)` 降序，榜首芋泥波波奶茶（94 杯 / 1,191.00） |

## 七、`06-security/` —— 角色授权与越权拦截

| 文件 | 命令 | 预期结果 |
|---|---|---|
| `role-permission-summary.png` | `sys.database_permissions` 汇总 | `role_manager` **78 条 / 24 对象 / 架构级 0**；`role_cashier` 20 条 / 13 对象；`role_stocker` 10 条 / 6 对象；`role_maker` 9 条 / 8 对象 |
| `unauthorized-229.png` | 四组负例：制作员读会员、收银员改配方、库管员删订单、店长建表 | 全部 `RESULT: BLOCKED`（`Msg 229` / `CREATE TABLE 权限被拒`） |

## 八、`07-app/` —— 应用界面与角色视图

> 演示账号：会员 `13800000001`（口令 `000001`）；员工 `E001`/`E002`/`E003`/`E005`（口令为小写工号）。

| 文件 | 页面 | 预期结果 |
|---|---|---|
| `login.png` | `/login` | 会员登录页：logo + MD3 filled field + 悬浮标签 |
| `menu.png` | `/` | 6 个分类、27 张可售饮品卡、底部「今日售罄」区（杨枝甘露 / 芒果冰沙），空购物车时不显示悬浮栏 |
| `menu-modal.png` | `/`（展开单个饮品） | 弹窗内：杯型（含价）/ 糖度 / 冰量 / 数量 / 加料 + 实时小计 + 「加入订单」 |
| `cart.png` | `/`（购物车抽屉） | 3 行明细 + 小计、`−`/`+`/`改`、底部「清空 / 继续点单 / 提交订单」；卡片显示「已选 N 杯」徽标 |
| `orders.png` | `/orders` | 进行中主表格（单号 / 取餐号 / 状态徽章 + 提示 / 实付 / 下单时间）+ 折叠的「历史订单 N 笔」 |
| `me.png` | `/me` | 积分卡（当前积分 / 会员码）+ 积分流水 + 最近 5 笔订单 |
| `cashier.png` | `/cashier` | 收银台：会员手机号输入（散客留空）+ 同一套饮品卡 |
| `maker.png` | `/maker` | 待处理订单 + 「需要关注」5 个饮品（杯型作列）+ 折叠的全量 29 个饮品 |
| `stocker.png` | `/stocker` | 待收货 5 条 + 低于补货点 5 条（彩色预警徽章）+ 折叠的「库存查询与报损」60 种 |
| `manager.png` | `/manager` | 近 7 天趋势图（断档断开）+ 销量 Top 10 横向柱 + 经营日报 + 商品档案（行内编辑 / 下架） |
| `forbidden.png` | 库管员访问 `/manager` | **403** 页：`PERMISSION_DENIED`「当前岗位无权进入该页面」+ 请求标识 + 返回首页 / 退出登录 |

---

## 九、与 v0.1 的差异

| 维度 | v0.1 | v1.0 |
|---|---|---|
| 证据组数 | 35 组（建库 / CRUD / 查询 / 权限） | **31 组**（少了 CRUD 的逐条图，多了迁移、回归、基线、三口径、应用界面） |
| 建库规模 | 17 表 / 132 字段 / 30 外键 / 43 CHECK / 21 索引 / 5 视图 | **18 表 / 139 字段 / 31 外键 / 49 CHECK / 22 索引 / 6 视图** |
| 新类别 | — | `02-migration/`（五段迁移自证）、`03-regression/`、`04-baseline/`、`07-app/`（应用界面与角色视图） |
| 应用截图 | 无 | 11 张，由 `capture-app.ps1` 生成 |

> **为什么 v1.0 不再逐条截 CRUD**：课程第 2 周的 CRUD 要求已在 v0.1 交付；
> v1.0 的评分要点是「设计合理性、迁移正确性、应用完整性与可用性」——
> 因此本版把证据重心放在**迁移前后语义保持**（§3—§5）与**应用可用性**（§8）上。
