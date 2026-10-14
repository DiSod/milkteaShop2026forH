# week06 · 第 6 周 —— ch7 函数依赖与规范化

> **理论内容**：**ch7 函数依赖与规范化**
> **课程依据**：[`course/lecture-week05.md`](../../course/lecture-week05.md) 的「周次安排」表第 6 周行
> **当周产出（课程原文）**：依赖分析、分解方案、**迁移语句 `migration.sql`**、回归测试
> **展示重点（课程原文）**：迁移前后**语义保持**；重复与异常得到解释
>
> ⚠️ **本章是阶段二「重构」动作的真正落点** —— 第 5 周只做分析与清单，结构调整在本周实施。

---

## 一、本周边界（课程原文）

> 项目任务（原文）：**「识别更新异常与函数依赖，完成规范化、反规范化取舍和迁移设计。」**
>
> 提示（原文，第 5 周任务第 4 条）：**「本周先完成分析与问题清单，保留可复现的 v0.1；结构调整在第六周通过迁移脚本实施。」**

| 项 | 内容 |
|---|---|
| **输入** | [`project/docs/v0.1-issues.md`](../../project/docs/v0.1-issues.md)（第 5 周的待调整清单） |
| **输出** | `project/docs/normalization.md` + **`migration.sql`（可执行）** + 回归测试 |
| **不做** | ❌ 应用界面（第 7—9 周）· ❌ 存储过程 / 触发器（第 11—12 周，除非迁移确需） |

---

## 二、✅ 开工两项裁定（已双人定案，见 ISSUE-011）

> 开工前裁定已闭环，指导本周目录与脚本形态：

| # | 裁定项 | 结论 | 说明 |
|---|---|---|---|
| 1 | **`migration.sql` 是否接入 `99-rebuild.sql`** | **确定接入** | ① **单一基准（Single Source of Truth）**：主工程 `project/` 必须始终保持最新可用基准，避免后续第 7—9 周开发 App 时团队环境与代码漂移；② **历史已有独立物理冻结**：v0.1 历史已归档至 `weeks/submissions/v0.1/code/` 100% 独立可跑；③ **兼顾迁移测试**：`migration.sql` 既可独立在老库上演示数据平滑迁移与语义保持，又作为全新重建的标准演进流水线。 |
| 2 | **SQL 落点 = `project/sql/11-migration/`** | **采用** | 编号紧随 `10-transaction`，**不占用阶段三（11—13 周）的预留位**。 |

📌 **已回写对照**：[`weeks/week05/README.md`](../week05/README.md) §9.4、[`project/docs/v0.1-issues.md`](../../project/docs/v0.1-issues.md) §4、`project/sql/README.md` 执行顺序表、`STRUCTURE.md` §3 目录树。

---

## 三、本周任务拆解（已全面闭环）

| # | 任务 | 落点 | 状态 |
|---|---|---|---|
| 1 | **函数依赖分析** —— 逐表列出 FD，找候选码与传递依赖 | [`project/docs/normalization.md`](../../project/docs/normalization.md) | ✅ 已完成 |
| 2 | **更新异常识别** —— 插入 / 删除 / 修改异常各举一例 | 同上 | ✅ 已完成 |
| 3 | **范式判定** —— 各表当前满足到第几范式（1NF/2NF/3NF/BCNF） | 同上 | ✅ 已完成 |
| 4 | **⭐ 反规范化取舍论证** —— 对**有意保留**的冗余做正式论证 | 同上 | ✅ 已完成 |
| 5 | **分解方案** —— 需要拆的表给出分解后模式 | 同上 | ✅ 已完成 |
| 6 | **写 `migration.sql`** —— 真实 DDL 变更 + 数据迁移 | [`project/sql/11-migration/migration.sql`](../../project/sql/11-migration/migration.sql) | ✅ 已完成 |
| 7 | **回归测试** —— 迁移**前后**语义保持的证据 | [`project/tests/01-migration-verification.md`](../../project/tests/01-migration-verification.md) | ✅ 已完成 |

### 3.1 ⭐ 第 4 项已经准备好 4 个现成的论证素材

第 5 周已把「有意保留的取舍」整理成清单，外加本轮实测定案的明细派生列，本周直接展开论证即可：

| 素材 | 出处 |
|---|---|
| `tbl_recipe.sugar_spec_id IS NULL` 表达「与糖度无关」—— 域语义 vs 范式 | `v0.1-issues.md` §2 第 1 条 |
| `tbl_stock_ledger` 多态来源（判别列 + 3 真外键） | `v0.1-issues.md` §1.2 问题 4 |
| `tbl_member.points_balance` 冗余积分余额（D-12） | `v0.1-issues.md` §2 第 3 条 |
| `tbl_order_detail.subtotal` 冗余金额与跨表小料一致性 | `v0.1-issues.md` §1.1 问题 2（实测证实已含加料，否决单表 CHECK） |

### 3.2 第 6 周的候选迁移项（第 5 周已识别）

| 候选 | 成本 | 出处 |
|---|---|---|
| 券核销时间必须落在 `[valid_from, valid_to]` 内 | **低**（1 条 `CHECK`） | `v0.1-issues.md` §1.1 问题 1 |
| 明细 `subtotal = qty × unit_price` | **否决单表 CHECK**（实测证实加料已计入，0 差额） | 转入 §3.1 反规范化论证（ISSUE-011） |
| 券状态机不可逆（`UNUSED → USED` 只能一次） | **高**（需触发器，属阶段三） | `v0.1-issues.md` §1.1 问题 3 |
| 补建 `tbl_stocktake` / `tbl_stocktake_detail` + `STOCKTAKE` 流水类型 | **高** | `project/data/README.md` §五 |

---

## 四、约束（照做，别自创）

| # | 约束 | 出处 |
|---|---|---|
| 1 | **禁止同一份内容在两处各自演化** —— 表结构以 `data-dictionary.md` 为准 | [`01-layout-and-naming.md`](../../harness/conventions/01-layout-and-naming.md) §5 |
| 2 | **含中文的 `.sql` 必须 UTF-8 with BOM** —— 改完必须回补，否则 `sqlcmd` 静默失效 | [`02-sql-style.md`](../../harness/conventions/02-sql-style.md) §9 |
| 3 | **`project/sql/**` 走分支**（`feat/`）；合并前必须跑通 `99-rebuild.sql` | [`04-git-workflow.md`](../../harness/conventions/04-git-workflow.md) §2.1、§2.2 |
| 4 | **双重验证机制** —— `migration.sql` 既要编入 `99-rebuild.sql` 确保新库可一键重构拉起，又要支持在历史旧库上独立运行验证前后语义保持与数据无损 | ISSUE-011 双人定案 |
| 5 | **强断言必须自己实测** | [`agent-session-start.md`](../../harness/prompts/agent-session-start.md) |
| 6 | **AI 给出的函数依赖 / 分解方案需逐项核实** | 课程第 5 周原文同款提示 |

---

## 五、文件对照

| 文件 | 中文标题 | 说明 |
|---|---|---|
| `README.md` | 第 6 周周报（本文件） | 本周任务与执行看板 |
| [`project/docs/normalization.md`](../../project/docs/normalization.md) | 函数依赖、规范化分析与模式演进报告 | 本周理论分析核心资产（17 表 FD/异常消除/范式判定/5大反规范化取舍） |
| [`project/sql/11-migration/migration.sql`](../../project/sql/11-migration/migration.sql) | 第 6 周模式迁移与完整性重构脚本 | 幂等下沉 `ck_coupon_used_time_range`，已接入 `99-rebuild.sql` |
| [`project/tests/01-migration-verification.sql`](../../project/tests/01-migration-verification.sql) | 迁移回归测试脚本 | 正反例验证（合法放行、越界拦截） |
| [`project/tests/01-migration-verification.md`](../../project/tests/01-migration-verification.md) | 迁移回归测试报告 | 4/4 测试用例全绿与重建集成证据 |

> 按升级路径约定，本周产出**直接进 `project/`**，本表提供相对路径导航，**不在 `weeks/` 下留代码副本**。
