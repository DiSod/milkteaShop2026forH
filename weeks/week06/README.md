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
| **输出** | `project/docs/normalization.md` + **`migration.sql`（可执行，满足 6 要素）** + **`regression.sql`（非零退出码）** |
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
| 3 | **范式判定** —— 各表当前满足到第几范式（1NF/2NF/3NF/BCNF） | 同上 | ✅ 已完成（15 纯净 BCNF + 3 工程反规范化 = 18 表） |
| 4 | **⭐ 反规范化取舍论证** —— 对**有意保留**的冗余做正式论证 | 同上 | ✅ 已完成 |
| 5 | **分解方案与数学证明** —— 优惠券与派生列的无损连接与保持依赖证明 | 同上 §5 | ✅ 已完成（充要条件推导 + 闭包等价性） |
| 6 | **写 `migration.sql`** —— 真实 DDL 变更 + 6 要素迁移 + 拆分为 18 表 | [`project/sql/11-migration/migration.sql`](../../project/sql/11-migration/migration.sql) | ✅ 已完成 |
| 7 | **回归测试** —— 自动化断言 + 非零退出码 + 快照 0 差异证据 | [`project/tests/regression.sql`](../../project/tests/regression.sql) & [`baseline/`](../../project/tests/baseline/README.md) | ✅ 已完成 |

### 3.1 ⭐ 第 4 项已经准备好 4 个现成的论证素材

第 5 周已把「有意保留的取舍」整理成清单，外加本轮实测定案的明细派生列，本周直接展开论证即可：

| 素材 | 出处 |
|---|---|
| `tbl_recipe.sugar_spec_id IS NULL` 表达「与糖度无关」—— 域语义 vs 范式 | `v0.1-issues.md` §2 第 1 条 |
| `tbl_stock_ledger` 多态来源（判别列 + 3 真外键） | `v0.1-issues.md` §1.2 问题 4 |
| `tbl_member.points_balance` 冗余积分余额（D-12） | `v0.1-issues.md` §2 第 3 条 |
| `tbl_order_detail.subtotal` 冗余金额与跨表小料一致性 | `v0.1-issues.md` §1.1 问题 2（实测证实已含加料，否决单表 CHECK） |

### 3.2 第 6 周迁移项（满足迁移 6 要素）

| 迁移要素 | 实施内容 | 状态 |
|---|---|---|
| 要素 1：新表创建 | 新建优惠券模板实体表 `tbl_coupon_template` | ✅ 已落地 |
| 要素 2：字段调整 | `tbl_coupon` 添加 `template_id`，移除 4 个冗余列 | ✅ 已落地 |
| 要素 3：码设置 | 设置模板 PK/UQ/CHECK，原表设置 FK、外键索引与核销有效区间约束 `ck_coupon_used_time_range` | ✅ 已落地 |
| 要素 4：数据迁移 | 从历史数据去重抽取 2 个标准模板装载，精准回填 `template_id` | ✅ 已落地 |
| 要素 5：数据校验 | 校验 0 孤儿券，核销时间窗口 100% 合规，总券数 24 行无损 | ✅ 已落地 |
| 要素 6：旧表兼容处理 | 建立向后兼容视图 `vw_coupon_legacy`，同步角色权限 | ✅ 已落地 |

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
| [`project/docs/normalization.md`](../../project/docs/normalization.md) | 函数依赖、规范化分析与模式演进报告 | 本周理论分析核心资产（18 表 FD/异常消除/范式判定/5大反规范化取舍/数学证明） |
| [`project/docs/data-dictionary.md`](../../project/docs/data-dictionary.md) | 数据字典 | 18 表完整字段字典与码标注汇总 |
| [`project/sql/11-migration/migration.sql`](../../project/sql/11-migration/migration.sql) | 第 6 周模式迁移与规范化拆分脚本 | 满足迁移 6 要素，已接入 `99-rebuild.sql` |
| [`project/sql/11-migration/README.md`](../../project/sql/11-migration/README.md) | 迁移设计与执行说明 | 6 要素落地对照与双重验证指引 |
| [`project/tests/regression.sql`](../../project/tests/regression.sql) | 全库自动化回归测试入口 | 12 项硬断言，带 `THROW` 与 `sqlcmd -b` 非零退出码机制 |
| [`project/tests/01-migration-verification.sql`](../../project/tests/01-migration-verification.sql) | 迁移专项正反例脚本 | 正反例验证（合法放行、越界拦截、悬空外键拦截） |
| [`project/tests/01-migration-verification.md`](../../project/tests/01-migration-verification.md) | 迁移专项回归测试报告 | 5/5 测试用例全绿与重建集成证据 |
| [`project/tests/baseline/`](../../project/tests/baseline/README.md) | 迁移前后基线快照对比 | 抽样明细 S1、销售 S2、库存 S3 对比迁移前，0 差异 |

> 按升级路径约定，本周产出**直接进 `project/`**，本表提供相对路径导航，**不在 `weeks/` 下留代码副本**。

---

## 六、⭐ 本周裁定与口径（2026-10-15 定案）

### 6.1 销售额口径（后果最大的一条）

同一份库里"销售额"有三个不同的数，**报数前必须声明用哪个**：

| 口径 | 筛选条件 | 订单数 | 小计合计 | 实付金额 |
|---|---|---|---|---|
| A 全量 | 无 | 1,963 | 24,328.00 | 24,208.00 |
| **D 已收款** ⭐ | `pay_status = 'SUCCESS'` | **1,926** | **23,882.00** | **23,762.00** |
| B 已完成 | `order_status = 'COMPLETED'` | 1,894 | 23,473.00 | 23,363.00 |

包含关系 **A ⊃ D ⊃ B**。完整口径表见 `data-dictionary.md` §五。

### 6.2 任务 ①「保存迁移前结果」的落点

新建 [`project/tests/baseline/`](../../project/tests/baseline/README.md)：三个快照脚本 + 迁移前实测结果。

| 脚本 | 覆盖 | 迁移前指纹 | 迁移后指纹（实测） | 差异行数 |
|---|---|---|---|---|
| `01-order-detail.sql` | 34 单 / 59 行明细 / 17 行加料 | `-1674015621` | `-1674015621` | **0** |
| `02-product-sales.sql` | 29 商品行 × 三口径 | `436093178` | `436093178` | **0** |
| `03-stock-query.sql` | 60 原料 + 57 视图行 | 原料 `1517769285` / 视图 `394430658` | 原料 `1517769285` / 视图 `394430658` | **0** |

**实测结论**：模式拆分与约束补强后，全链路查询结果完全一致，**语义零丢失、数据零损坏**。

---

## 七、待办与进展跟踪

| # | 待办 | 状态 | 说明 |
|---|---|---|---|
| 1 | `normalization.md` §0 与 §3 的范式判定数字不一致（12+5 vs 14+3） | ✅ **已闭环** | 见 ISSUE-012；统一为 14 纯净 BCNF + 3 工程反规范化（14+3=17） |
| 2 | `normalization.md` §5 只有"无损连接且保持依赖"的断言，无证明步骤 | ✅ **已闭环** | 见 `normalization.md` §5；已补齐交集超码充要条件推导与依赖投影闭包证明 |
| 3 | `migration.sql` 未含课程要求的 6 要素 | ✅ **已闭环** | 落地新表创建、字段调整、码设置、数据迁移、数据校验、旧表兼容处理 6 要素，已接入 `99-rebuild.sql` |
| 4 | `regression.sql` 尚未编写 | ✅ **已闭环** | 编写 `project/tests/regression.sql`，支持 `THROW` 与 `sqlcmd -b` 非零退出码，12 项断言全绿 |
| 5 | 券表拆分（`tbl_coupon` → `tbl_coupon_template` + `tbl_coupon`） | ✅ **已闭环** | 17 表成功扩充为 18 表，消除 12 行模板冗余，单表 BCNF 增至 15 张，补齐无损分解数学证明 |
| 6 | `weeks/submissions/v1.0/report.md` 报告素材 | ⬜ **未起稿** | 目录目前只有 `.gitkeep`，待提交前汇总 |
