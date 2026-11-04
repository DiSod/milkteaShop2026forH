# app · 应用界面（v1.0）

第 2 阶段的应用层实现：在 **18 表 / 139 字段 / 31 外键 / 48 CHECK** 的 v1.0 库上，
完成「登录 → 点单 → 写库 → 工作台接单」的全流程。

| 项目 | 内容 |
|---|---|
| 当前状态 | 🟡 **本地可运行的第一版**（分支 `feat/week07-points-opening-ledger`，含应用骨架与迁移 02/03，未合并、未推送） |
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
  member_dao.py           会员与我的订单、积分流水
  order_dao.py            下单写入：单号流水、订单头/明细/加料、反冲扣料、积分
service/
  errors.py               八类业务异常 + 从 dao 错误翻译
  auth.py                 会员登录 / 员工登录 / 口令摘要
  catalog.py              菜单与选项的用例
  ordering.py             下单用例（校验 → 定价 → 库存 → 事务写入）
web/
  security.py             登录态与角色装饰器
  routes_auth.py          /login /staff/login /logout
  routes_member.py        / /order /orders /me
  routes_maker.py         /maker /maker/order/<id>/next
  templates/              8 个 Jinja2 模板
  static/                 本地 Bootstrap 5.3.3 + app.css（离线可用）
tests/
  test_layering.py        分层边界三条断言
  test_auth_hash.py       口令摘要与 SQL 侧一致性
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
python -m pytest -q      # 期望 17 passed
```

其中 `tests/test_layering.py` 与 `tests/test_auth_hash.py` 共 8 条是本机就能跑的
**结构断言**（只有 `dao/` 能 `import pyodbc`、`service/` 与 `web/` 不得出现内联
SQL、口令哈希与数据库侧定标一致）；`tests/test_permissions.py` 9 条要连库，
测的是**行级隔离**与**业务层岗位拦截**。

## 4. 两个入口

| 入口 | 账号 | 口令（演示） | 落点 |
|---|---|---|---|
| 会员 | 手机号，如 `13800000001` | 手机号后 6 位，如 `000001` | `/` 菜单 → 下单 → `/orders`、`/me` |
| 员工 | 工号，如 `E003`（制作员） | 小写工号，如 `e003` | `/maker` 接单与推到下一状态 |

口令约定与 `../sql/11-migration/migration-02-login-credentials.sql` 完全一致：
盐 = `m<member_id>` / `e<employee_id>`，摘要 = `UPPER(HEX(SHA-256(盐+口令)))`。

## 5. 已知边界（答辩要主动说）

| # | 情况 | 现状 | 计划 |
|---|---|---|---|
| 1 | 一次下单跨「订单域 + 库存域」，单个角色授权做不到 | 写入路径以 `dbo` 执行，读取路径仍走受限身份 | 第 11—12 周改为存储过程 + `EXECUTE WITH OWNER`，业务层只 `GRANT EXECUTE` |
| 2 | 网单没有收银员，但 `tbl_order_header.cashier_id` NOT NULL | 固定记到 `employee_id=2`（E002 李娜 CASHIER，`SYSTEM_CASHIER_ID`） | 同上，随存储过程一起处理 |
| 3 | 顾客借用收银员的数据库身份（未建 `usr_member`） | `config.ROLE_DB_USER['MEMBER'] = usr_test_cashier` | 可加一个只读 + 写订单的专用账户 |
| 4 | 迁移 02 未合并，`password_hash` 列不存在 | 登录直接抛 `BUSINESS_RULE_VIOLATION`，不 500 | 等核心工程确认后合并 |
| 5 | 口令是单轮 SHA-256，不是 Argon2id | 演示级取舍，答辩时主动说明 | 真实产品应换 PBKDF2/Argon2id + 每用户随机盐 |
| 6 | 只做了「顾客 + 制作员」两条主线 | 收银员/库管员页面未做 | 第 8—9 周补 |
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
