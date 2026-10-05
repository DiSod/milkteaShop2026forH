# ISSUE-009: 交付文档全量一致性清扫与历史残留消除（132 字段定案、ANY 样例清除、D-05a 去重）

| 元数据 | 内容 |
|---|---|
| **状态** | 🟢 已解决 (Resolved) |
| **类型** | 文档维护 / 一致性排雷 · 交付审查 |
| **提报人/Agent** | 何争霖（hezhlin5 / 核心工程） |
| **指派处理** | 文档主编（DiSod） |
| **提报日期** | 2026-10-04 |
| **关联文件** | [`weeks/submissions/v0.1/report.md`](../../weeks/submissions/v0.1/report.md), [`project/docs/data-dictionary.md`](../../project/docs/data-dictionary.md), [`weeks/week02/schema-design.md`](../../weeks/week02/schema-design.md), [`README.md`](../../README.md), [`weeks/week02/README.md`](../../weeks/week02/README.md) |

---

## 1. 现象与矛盾描述

在阶段成果交叉审查中，发现多处文档口径与数据库真实 DDL/约束存在不一致，以及多处编辑历史残留，需在提交前统筹清扫：

1. **📄 132 vs 133 “幽灵字段”矛盾**：
   - 数据库 17 张表实际字段总数已在 `tbl_supplier` 砍掉联系电话后精确为 **132** 个（已由 `sys.columns` 证实）；
   - 但在 [`weeks/submissions/v0.1/report.md`](../../weeks/submissions/v0.1/report.md)（第 152、314、361 行）、根目录 [`README.md`](../../README.md)（第 47 行）、[`weeks/week02/README.md`](../../weeks/week02/README.md)（第 27 行）与 [`harness/team/contributions.md`](../team/contributions.md)（第 33 行）中，仍写着 **133 字段**，口径未同步。
2. **📄 `data-dictionary.md` 样例数据与现有 CHECK 约束冲突**：
   - [`project/docs/data-dictionary.md`](../../project/docs/data-dictionary.md) 第四节样例数据中，第 5 张表 `tbl_spec_option` 写着 `（12 行，给出全部行）`，且第 3 行包含 `(3, SUGAR, ANY, 任意糖度)`；
   - 而 DDL 约束 `ck_spec_option_code_by_type` 早就将 `ANY` 剔除，如果将该样例装入库中会当场报 CHECK 异常。
3. **📄 `schema-design.md` D-05a 决策段落重复与精神分裂**：
   - [`weeks/week02/schema-design.md`](../../weeks/week02/schema-design.md) 第 220 行刚叙述“否决 `'ANY'` 哨兵值并改用 NULL”，紧接着第 228 行又出现旧草稿“决策：采用 B2 —— 配方表仍为一张表，用 `sugar_level = 'ANY'`”，下方又重复粘贴了一次“被否决的方案”表格与旧版 DDL。
4. **📄 阶段一报告进度表状态滞后**：
   - [`weeks/submissions/v0.1/report.md`](../../weeks/submissions/v0.1/report.md) 中第 3 周任务仍标记为 `⬜`，未决问题列表仍列着已于 ISSUE-007 闭环的造数引擎 BOM 和配方数据源问题。

---

## 2. 事实证据（对照）

- **真实数据库元数据**：
  ```sql
  SELECT COUNT(*) FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id WHERE t.name LIKE 'tbl_%';
  -- 输出: 132
  ```
- **滞后文档**：`report.md`、`README.md`、`week02/README.md` 写着 `133 字段`。
- **数据字典第四节**：`tbl_spec_option` 第 3 行为 `ANY`，总行数标注为 12 行（实际为 11 行）。

---

## 3. 建议解法与行动方案

按照团队“全库文档由 DiSod 独占统筹执笔”的约定，请文档主编排查并闭环以下事项：
1. **全局统一字段统计**：将各处文档中的 133 字段统一定案为 **132 字段**；
2. **同步数据字典样例元组**：将 `tbl_spec_option` 样例元组中的第 3 行 `ANY` 剔除，说明行数更新为 11 行；
3. **整理 `schema-design.md` D-05a**：清理重复段落与旧版 DDL，保留最终的 NULL 设计决策；
4. **刷新 `report.md` 进度**：将第 3 周标记为 ✅ 完成，移除已解决的技术债描述。

---

## 4. 解决记录

**处理人**：DiSod（文档主编）
**解决时间**：2026-10-04
**状态**：🟢 **已解决** —— 四类不一致全部清扫完毕，并**多查出 2 处**本 Issue 未列出的残留

### 逐条对照

| # | 原诉求 | 落地 | 状态 |
|---|---|---|---|
| 1 | 全局统一 **132 字段** | 实际清理 **6 处**（本 Issue 列了 4 处，另多查 2 处）；顺带修正同行的「10 配方」（应为 30 款 / 492 行） | ✅ |
| 2 | 数据字典样例剔除 `ANY`、行数改 11 | `tbl_spec_option` 三处：标题 12 → **11 行**、删第 3 行 `ANY`、下方注释改写为「糖度档里没有 `ANY`」 | ✅ |
| 3 | 整理 `schema-design.md` D-05a | **删除旧正文整段 916 字符**（旧「决策：采用 B2 …用 `sugar_level='ANY'`」+ 旧 DDL + 重复的「被否决的方案」表 + 旧「保留的重构余地」） | ✅ |
| 4 | 刷新 `report.md` 进度 | 3.1.3 第 3 周 → ✅（实测 17 秒）、第 4 周 → 🔄；3.2 未决清单去掉已闭环项；3.3 把第 3 周划掉 | ✅ |

### 比原 Issue 多查出的 2 处

| # | 位置 | 内容 |
|---|---|---|
| 1 | `harness/issues/002-schema-scope-and-table-count.md:78` | ISSUE-002 的闭环记录里也写着「逐表 133 个字段」 |
| 2 | `harness/team/contributions.md:33` | 同一行里既有「133 字段」，又有「**10 配方**」—— 两个都过期 |

> **有意保留未改**：`contributions.md:56`（何争霖描述本 Issue 时写的「132 vs 133 字段口径不一」）
> 与本 Issue 正文里的「133」—— **那是问题描述，不是口径断言**，改了反而失真。

### 根因与教训

| 问题 | 根因 | 教训 |
|---|---|---|
| `ANY` 残留 | 删除 `ANY` 时只处理了**域字典**与**种子数据**，漏了**样例元组** | 同一个概念散落多处时，**要全库搜一遍再改** |
| D-05a 重复 | "终态化"那轮**只替换了标题和开头**，旧正文整段留在下面 | 改写章节时**要读到下一个标题为止**，确认旧内容全部处理 |

### 遗留

无。全库文档口径已与数据库真实结构（**132 字段 / 17 表 / 30 外键**）一致。
