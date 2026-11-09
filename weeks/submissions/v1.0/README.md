# v1.0 · 第二阶段提交

> **提交节点**：第 10 周周二 23:59　　**分值**：20
> **评分要点（课程原文）**：**设计合理性（ER / 规范化）、迁移正确性、应用完整性与可用性**
> **课堂展示**：第 10 周（重点：ER 图 + 规范化与迁移 + 应用登录 / 商品库存订单操作 / 参数化查询 / 错误反馈 / 角色界面）
>
> **依据**：[`course/lecture-week01.md`](../../../course/lecture-week01.md) 的阶段作业要求与
> [`weeks/submissions/README.md`](../README.md) 的归档规则。
>
> ⚠️ **归档规则**：提交前从 `project/` 与 `weeks/` 复制快照，**截止后本目录不再修改**。
> 唯一例外是 [`result/`](result/) —— 证据是提交物本体，无法从别处复制。

---

## 一、六件提交物

| # | 提交物 | 落点 | 状态 |
|---|---|---|---|
| 1 | **README**（范围 / 环境 / 链路 / 复现步骤） | 本文件 + 根 [`README.md`](../../../README.md) | ✅ |
| 2 | **实现代码（sql 目录）** | [`code/`](code/) —— `project/sql/` 的**冻结快照**（19 个文件，含 `11-migration/` 七段）；完整应用在 [`project/app/`](../../../project/app/) | ✅ |
| 3 | **结果证据 `result/`** | [`result/README.md`](result/)（**37 图 + 20 原始输出**：设计 3 项 / 数据库 19 组 / 应用 12 组 / 错误 4 张） | ✅ |
| 4 | **阶段报告** | [`report.md`](report.md)（三章 18 节 + 附录 A/B） | ✅ |
| 5 | **AI 使用记录** | [`ai-log.md`](ai-log.md)（11 条使用记录 + **6 条业务纠错** + 10 条被否决方案） | ✅ |
| 6 | **组内分工表** | [`contributions.md`](contributions.md) + 报告附录 B | 🟡 已建，等何争霖确认 §4；请见 [`ISSUE-020`](../../../harness/issues/016-v1.0-delivery-handoff.md) |

> **操作手册**不在课程清单里，但为了让"应用可用性"可被复核，单独写了一份：
> [`project/docs/manual.md`](../../../project/docs/manual.md)。

---

## 二、本版做了什么

| 维度 | v0.1（第 1—4 周） | v1.0（第 5—9 周） |
|---|---|---|
| 表 | 17 | **18**（券拆成「模板 + 实例」） |
| 字段 | 132 | **139**（+8 模板表、+2 口令哈希、券表 −3） |
| 外键 | 30 | **31** |
| CHECK | 43 | **49**（+9 新约束，−3 随属性上提） |
| 视图 | 5 | **6**（+`vw_coupon_legacy` 兼容视图） |
| 角色 | 4 | 4（`role_manager` 从架构级全权改为 **22 条逐对象授权**） |
| 数据行 | 20,979 | **21,067**（+2 模板行、+80 条积分期初流水、+6 张默认券） |
| 应用 | 无 | **三层结构 + 四个岗位工作台 + 订单取消 + 券核销 + 46 条测试** |
| 界面 | — | 全站 **Material Design 3** 视觉层（薄荷绿，离线 vendored） |

**七段迁移**（`project/sql/11-migration/`）：

| 段 | 内容 | 自证方式 |
|---|---|---|
| `migration.sql` | 券拆「模板 + 实例」+ `ck_coupon_used_time_range` + 兼容视图 + 补授权 | 24 张券外键悬空 0、兼容视图 24 行 |
| `migration-02` | `tbl_member` / `tbl_employee` 各加 `password_hash CHAR(64) NULL` | 80 + 5 条凭据格式全部合法 |
| `migration-03` | 积分期初：加 `OPENING` 类型 + 回填 80 条 + 脚本自证 | 余额合计 = 流水合计 = 25,224，不符 0 |
| `migration-04` | `ck_order_header_pay_time`、`ck_order_header_finish_after_pay` | 37 单反例被排除在约束之外 |
| `migration-05` | 6 个单价 / 成本列升 `DECIMAL(12,4)` | 5 个列类型核对 + 视图刷新 |
| `migration-06` | 取消需要两类新流水：`CANCEL_BACK` / `REVOKE`，改写三条 CHECK | CHECK 仍 48 条、三条均 `is_disabled=0` |
| `migration-07` | 券核销闭环：`ck_coupon_used_time_consistent` + 订单券唯一索引 + 默认发券 6 张 | 券 30 张、可用 6；`CHECK` 49 条；索引 `is_unique=1` 且 `has_filter=1` |

---

## 三、复现步骤

```powershell
# 1) 重建数据库（唯一入口；必须在本目录执行，:r 按当前工作目录解析）
cd project\sql
sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 99-rebuild.sql

# 2) 数据库自检（期望 15/15）
sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -d milktea_shop -i ..\tests\regression.sql

# 3) 应用测试（期望 46 passed）
cd ..\app
pip install -r requirements.txt
python -m pytest -q

# 4) 启动应用 → http://127.0.0.1:5000
python app.py

# 5) 重新生成全部证据（37 图 + 20 原始输出）
cd ..\..\weeks\submissions\v1.0\result
powershell -ExecutionPolicy Bypass -File capture.ps1          # 19 组数据库类
powershell -ExecutionPolicy Bypass -File capture-app.ps1      # 12 组应用类（需第 4 步在跑）
```

**演示账号**：会员 `13800000001` / `000001`；员工 `E001`(店长) `E002`(收银) `E003`(制作) `E005`(库管)，口令为小写工号。

---

## 四、目录说明

| 路径 | 内容 |
|---|---|
| [`report.md`](report.md) | 阶段报告：设计思路 / 实验过程 / 实验总结 + 附录 A（决策与 AI 纠错）、附录 B（分工） |
| [`ai-log.md`](ai-log.md) | AI 使用记录（分级统计、11 条明细、**6 条业务纠错**、10 条被否决方案、提示词记录方式） |
| [`result/`](result/) | 37 图 + 20 原始输出；三组脚本 `capture.ps1` / `capture-app.ps1` / `08-errors/capture-errors.ps1` |
| [`code/`](code/) | **`project/sql/` 的冻结快照**（19 个文件：建库 / 建表 / 约束 / 索引 / 种子 / CRUD / 查询 / 视图 / 角色 / 七段迁移 / `99-rebuild.sql`），逐字节复制 |
| [`v0.1/`](../v0.1/) | 第一阶段提交快照（只读对照） |

> **为什么 `code/` 只放 SQL**：课程第 2 项要求的是「sql 目录」的五类脚本，评审要能直接读到 `.sql`；
> 而应用（Flask 三层）留在 `project/app/`，避免把整棵代码树复制两遍后立刻与 `main` 分叉。
> `code/` 与 `project/sql/` 在冻结时刻**逐字节相同**（复制时已用 sha256 逐个核对）。

---

## 五、这一版没做什么（如实交代）

| 未做 | 原因 | 何时 |
|---|---|---|
| 退款 / 退券流程 | 订单取消已做（仅「待制作」，回冲原料 + 扣回积分）；退款与退券仍属程序对象与事务章节 | 第 11—12 周 |
| 盘点（`STOCKTAKE`） | 需补两张表，第 6 周明确延后 | 第 13 周 |
| 下单下沉存储过程 + `EXECUTE AS OWNER` | 当前下单跨域写入走 `dbo`（P-2） | 第 11—12 周 |
| 行级数据隔离（RLS） | 表级授权数据库会真查；行级只能靠应用 `WHERE`（P-3） | 登记为待议 |
| 并发抢库存的严格防护 | 现为"先查后扣"，未加 `UPDLOCK` / 序列化 | 第 11—12 周 |
| 13 条已知边界的其余项 | 见 [`harness/issues/017`](../../../harness/issues/017-v1.0-known-boundaries.md) 与 [`manual.md`](../../../project/docs/manual.md) §9（报告已不再收录该表） | 按表内标注 |
