# docs · 项目设计文档

最终项目的设计类文档。

| 文档 | 用途 | 阶段 | 状态 |
|---|---|---|---|
| [`data-dictionary.md`](data-dictionary.md) | 数据字典（表、字段、域、码、样例元组、**§五 指标口径**） | 第 2 周起 | ✅ **四项任务全部完成**（992 行；§五 为第 6 周新增） |
| [`er-diagram.md`](er-diagram.md) | **ER 图**（Crow's Foot · Mermaid 源） | 第 5 周 | ✅ **已建**（17 实体 / 30 段联系 ↔ 30 外码） |
| ├ [`er-diagram.mmd`](er-diagram.mmd) | 上述图的 Mermaid 源（渲染输入，与 `.md` 代码块逐行一致） | 第 5 周 | ✅ |
| ├ [`er-diagram.svg`](er-diagram.svg) | ER 图矢量导出图（**纯文本标签，Word 可用**） | 第 5 周 | ✅ |
| ├ [`er-diagram.png`](er-diagram.png) | ER 图位图导出图（5715 × 2292） | 第 5 周 | ✅ |
| └ [`er-design-notes.md`](er-design-notes.md) | **ER 设计说明与验证记录** ← 作业 4 | 第 5 周 | ✅ **已建**（设计思路 / 三场景 / 97 项命名校验） |
| [`business-rules.md`](business-rules.md) | **业务规则与映射清单**（基数、参与约束、实现层、库表达不了的规则 A1—A10） | 第 5 周 | ✅ **已建**（28 段联系 / 30 外码 / 43 CHECK / A1—A10） |
| ├ [`er-legend.png`](er-legend.png) | Crow's Foot **符号图例**（图形版，作业 4 要求） | 第 5 周 | ✅ |
| ├ [`er-legend.svg`](er-legend.svg) | 图例矢量版（`foreignObject` = 0，Word 可用） | 第 5 周 | ✅ |
| └ [`er-legend.mmd`](er-legend.mmd) | 图例 Mermaid 源 | 第 5 周 | ✅ |
| [`v0.1-issues.md`](v0.1-issues.md) | **v0.1 问题清单与改进方向**（第 6 周迁移的输入） | 第 5 周 | ✅ **已建**（新发现 3 处完整性缺口） |
| [`normalization.md`](normalization.md) | 范式分析与改进记录（全库 FD / 17 表范式判定 / 反规范化论证 / 无损分解数学证明） | 第 6 周 | ✅ **已闭环**（全库 14 纯净 BCNF + 3 受控跨表派生冗余，口径闭环对齐，含分解证明） |
| **`migration.sql`** | ⚠️ **迁移脚本本身是 SQL，不在本目录** —— 落点 [`project/sql/11-migration/`](../sql/11-migration/)（**已定案**，见 ISSUE-011） | 第 6 周 | ✅ **已建**（`ck_coupon_used_time_range`，已接入 `99-rebuild.sql`） |
| `migration.md` | 模式迁移说明 | 第 6 周 | 🟡 内容已由 `normalization.md` §6 与 [`11-migration/README.md`](../sql/11-migration/README.md) 承载，是否另立文件待定 |
| [`design-notes.md`](design-notes.md) | 设计取舍与理由 · **已知边界** | 第 4 周起 | 🟡 已建（首批 2 条） |

> ⚠️ **`project/docs/` 只放文档，不放可执行 SQL** —— 快照脚本与回归测试都在 [`project/tests/`](../tests/)，按
> [`04-git-workflow.md`](../../harness/conventions/04-git-workflow.md) §2.1，
> 本目录归为「文档，直接进 `main`」，**不适用「跑通 `99-rebuild.sql`」这条合并底线**。
> 把 `migration.sql` 放进本目录等于**绕过合并底线**，因此它必须落在 `project/sql/` 下。

> **`data-dictionary.md` 是第 2 周的重点产出** —— 它同时承载课程第 2 周的
> **任务 2（字段定义）· 任务 3（码标注）· 任务 4（样例元组）**，共 **17 张表 / 132 个字段**。
>
> 分工上：**表结构与设计决策在 `weeks/week02/`（过程域），定稿的数据字典在本目录（成果域）。**
>
> ⚠️ **它是 `project/sql/01-schema/create-tables.sql` 的唯一真相源** —— 第 3 周的建表脚本由它翻译生成，不要两处各自演化。

## 放什么 / 不放什么

| ✅ | ❌ |
|---|---|
| 面向**最终项目**的设计文档 | 每周过程记录（→ `weeks/`） |
| ER 图、数据字典、迁移说明 | 规范类文档（→ `harness/conventions/`） |
| 答辩用的设计说明 | 阶段提交报告（→ `weeks/submissions/`） |
