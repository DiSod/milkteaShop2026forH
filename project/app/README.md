# app · 应用界面（v1.0）

第 2 阶段的应用层实现：在 **18 表 / 139 字段 / 31 外键 / 48 CHECK** 的 v1.0 库上，
完成「登录 → 点单 → 写库 → 工作台接单」的全流程。

| 项目 | 内容 |
|---|---|
| 当前状态 | 🟢 **第 7 周七项任务已全部达成**（3 个岗位工作台、商品维护、库存查询与调整、38 条自动化测试） |
| 技术栈 | Flask 3 + Jinja2 + 本地 Bootstrap 5.3.3 + pyodbc（**方案 B**，见 `../../weeks/week07/README.md` §七） |
| Python | 3.12（`SQL Server` 与 `ODBC Driver 17 for SQL Server` 均可） |
| 数据库 | `milktea_shop`，Windows 认证连接，**每请求切换数据库身份** |

## 1. 三层怎么分（课程段落 7 / 11 的口径）

| 层 | 目录 | 职责 | 不该做的事 |
|---|---|---|---|
| 页面层 | `web/`（`templates/`、`static/`、`routes_*.py`、`security.py`） | 接收操作、渲染页面、表单必填与格式校验 | **不含一行 SQL**；不直接 `import dao` |
| 业务层 | `service/` | 业务规则、**事务边界**、角色可执行范围、统一异常 | 不拼 SQL、不碰连接 |
| 数据访问层 | `dao/` | 连库、**参数化**、执行、读取；事务提交/回滚/释放 | 不做业务判断 |
| 数据库层 | SQL Server | 表、约束、视图、权限 | ——（不是我们写的代码层） |

边界由 **可执行的测试** 守住，不靠口头约定：`tests/test_layering.py` 会失败在
「谁 import 了 pyodbc」「上层是否出现内联 SQL」「页面层是否绕过业务层用 dao」这三件事上。

## 2. 目录与文件

```
app.py                    应用工厂、请求标识日志、统一异常处理、/health
config.py                 连接串与角色→数据库账户映射（读 .env，不写死）
requirements.txt          Flask / pyodbc / pytest
.env.example              连接信息模板（.env 本身不提交）
dao/
  db.py                   Session 封装 + open_session（EXECUTE AS USER）+ probe
  errors.py               把 pyodbc 异常归到四类（连接/约束/权限/未知）
  catalog_dao.py          菜单、规格、加料、可做杯数
  product_dao.py          商品档案的查询与维护（含分类）
  stock_dao.py            原料查询、补货预警、**apply_movement（改数量必留流水）**
  purchase_dao.py         采购单待收明细、收货、整单收满改状态
  report_dao.py           日报与商品销量 Top N（只读）
  member_dao.py           会员与我的订单、积分流水
  order_dao.py            下单写入：单号流水、订单头/明细/加料、反冲扣料、积分
service/
  errors.py               八类业务异常 + 从 dao 错误翻译
  auth.py                 会员登录 / 员工登录 / 口令摘要
  catalog.py              菜单与选项的用例
  ordering.py             下单用例（校验 → 定价 → 库存 → 事务写入）
  cashier.py              收银台：按手机号认会员，或散客直接下单
  admin.py                店长台：日报、商品建档/改价/上下架
  stock.py                库管台：收货入库、报损（原因必填）
  maker.py                制作台：接单队列与状态推进
web/
  security.py             登录态与角色装饰器
  routes_auth.py          /login /staff/login /logout
  routes_member.py        / /order /orders /me
  routes_cashier.py       /cashier /cashier/order
  routes_maker.py         /maker /maker/order/<id>/next
  routes_stocker.py       /stocker /stocker/receive /stocker/loss
  routes_manager.py       /manager /manager/product/{new,<id>/edit,<id>/retire}
  templates/              11 个 Jinja2 模板
  static/                 本地 Bootstrap 5.3.3 + app.css（离线可用）
tests/
  test_layering.py        分层边界三条断言
  test_auth_hash.py       口令摘要与 SQL 侧一致性
  test_permissions.py     行级隔离与业务层岗位拦截（9 条）
  test_staff_workbench.py 四个工作台、商品维护、收货与报损（21 条）
```

## 3. 启动

```powershell
cd project\app
python -m pip install -r requirements.txt
Copy-Item .env.example .env      # 按本机改连接信息
python app.py                    # http://127.0.0.1:5000
```

健康检查：`GET /health` 返回 `@@SERVERNAME`、库名、`tbl_` 表数与
`COL_LENGTH('tbl_member','password_hash')`——最后一项为 `null` 说明
**迁移 02 尚未执行，登录不可用**（此时登录页会给出明确提示而不是 500）。

自动化测试（需要能连库，否则权限类用例自动 skip）：

```powershell
cd project\app
python -m pytest -q      # 期望 38 passed
```

其中 `tests/test_layering.py` 与 `tests/test_auth_hash.py` 共 8 条是本机就能跑的
**结构断言**（只有 `dao/` 能 `import pyodbc`、`service/` 与 `web/` 不得出现内联
SQL、口令哈希与数据库侧定标一致）；`tests/test_permissions.py` 9 条与
`tests/test_staff_workbench.py` 21 条要连库，测**行级隔离**、**业务层岗位拦截**、
**四个工作台各自可达**、**商品维护与收货/报损的写入不变量**。

写库的用例用 `try/finally` 清理自己造的痕迹（断言失败也不留）；若曾中途失败，
可用 `harness/logs/tmp-repair-qty.py` 那种「把 `qty_on_hand` 校正回 Σ流水」的
幂等脚本复原，再用 `dao.stock_dao.ledger_drift()` 确认漂移为 0。

## 4. 两个入口

| 入口 | 账号 | 口令（演示） | 落点 |
|---|---|---|---|
| 会员 | 手机号，如 `13800000001` | 手机号后 6 位，如 `000001` | `/` 菜单 → 下单 → `/orders`、`/me` |
| 收银员 | `E002` | `e002` | `/cashier`：按手机号认会员，或留空按散客下单 |
| 制作员 | `E003` | `e003` | `/maker` 接单与推到下一状态 |
| 库管员 | `E005` | `e005` | `/stocker`：待收货、补货预警、报损登记 |
| 店长 | `E001` | `e001` | `/manager`：日报、销量 Top 10、商品建档/改价/下架 |

登录后按岗位自动跳到各自工作台（`web/routes_auth.py` 的 `WORKBENCH` 映射），
四类岗位与 `ck_employee_position` 一一对应，**没有第五个角色**。

**岗位能做什么由数据库授权决定，不是页面说了算**：商品维护只有 `MANAGER` 能写
（`role_cashier` 对 `tbl_product` 只有 `SELECT`），库存增减只有 `STOCKER`/`MANAGER`
（`role_cashier` 对 `tbl_ingredient` 无任何权限）——所以收银下单的扣料只能走
`dbo` 写路径（见 §5 第 1 条）。

口令约定与 `../sql/11-migration/migration-02-login-credentials.sql` 完全一致：
盐 = `m<member_id>` / `e<employee_id>`，摘要 = `UPPER(HEX(SHA-256(盐+口令)))`。

## 5. 已知边界（答辩要主动说）

| # | 情况 | 现状 | 计划 |
|---|---|---|---|
| 1 | 一次下单跨「订单域 + 库存域」，单个角色授权做不到 | 写入路径以 `dbo` 执行，读取路径仍走受限身份 | 第 11—12 周改为存储过程 + `EXECUTE WITH OWNER`，业务层只 `GRANT EXECUTE` |
| 2 | 网单没有收银员，但 `tbl_order_header.cashier_id` NOT NULL | 固定记到 `employee_id=2`（E002 李娜 CASHIER，`SYSTEM_CASHIER_ID`） | 同上，随存储过程一起处理 |
| 3 | 顾客借用收银员的数据库身份（未建 `usr_member`） | `config.ROLE_DB_USER['MEMBER'] = usr_test_cashier` | 可加一个只读 + 写订单的专用账户 |
| 4 | 迁移 02 若未执行，`password_hash` 列不存在 | 登录直接抛 `BUSINESS_RULE_VIOLATION`，不 500 | ✅ 经 ISSUE-014 裁定已接入 `99-rebuild.sql` 重建流水线 |
| 5 | 口令是单轮 SHA-256，不是 Argon2id | 演示级取舍，答辩时主动说明 | 真实产品应换 PBKDF2/Argon2id + 每用户随机盐 |
| 6 | ~~只做了「顾客 + 制作员」两条主线~~ | ✅ **已补齐**：收银台 `/cashier`、库管台 `/stocker`、店长台 `/manager` 均可用，商品维护与库存调整已落地 | —— |
| 7 | 「积分兑换券」未实现 | 库里 12 张 `POINTS_EXCHANGE` 券没有对应的 `REDEEM` 扣分流水（历史造数缺陷，已认账不追认） | 若做，必须在一个事务里「扣积分 → 发券 → 写 `REDEEM` 流水」；见 `../docs/business-rules.md` A11 |
| 8 | **RBAC 只到表级，管不了行级** | 顾客与收银员共用表级授权：`usr_test_cashier` 能读全部 1963 张订单头、80 个会员手机号；行级隔离**全靠应用写 `WHERE member_id = ?`**（`dao/member_dao.py`），`WHERE` 漏写数据库不会报警 | 行级安全只有 SQL Server RLS 能下沉（本库 `sys.security_policies` = 0，从未启用）；`tests/test_permissions.py` 用断言把「只出现自己的单号」钉住，作为补偿 |
| 9 | 角色是**封闭的 4 个** | 与 `ck_employee_position` 的 4 个取值（MANAGER/CASHIER/MAKER/STOCKER）严格一一对应；顾客不是岗位、在 `tbl_employee` 不占行，故**不设** `role_member`，界面层用 `member_required` 区分 | 若将来要给顾客独立数据库身份，只加**用户**（`usr_member`）不加角色，配合行级过滤——保持 4 角色不变 |
| 10 | **v1.0 应用强制会员下单** | 库层 `tbl_order_header.member_id` 仍允许 NULL（为承载 v0.1 的 764 张历史散客单，占 38.9%），但应用侧 `/`、`/order`、`/orders`、`/me` 全部 `@member_required`，**散客无法下单** | 见 `../docs/business-rules.md` A12；若要库层也强制，需先把 764 行散客单迁到"匿名会员" |

## 6. 放什么 / 不放什么

| ✅ | ❌ |
|---|---|
| 应用源代码、界面资源、依赖清单 | SQL 脚本（→ `../sql/`） |
| 应用的构建与启动说明 | 设计文档（→ `../docs/`） |
| | 数据文件（→ `../data/`） |
