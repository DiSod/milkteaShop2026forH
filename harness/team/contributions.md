# 组内分工与贡献记录

> ✅ **成员已确定**（2026-09-23）—— 胡博锐（DiSod）、何争霖（hezhlin5）。
> ⚠️ 表内**文字描述已按产出物填入，但工时与具体分工归属仍需两位本人确认**。

课程要求提交「**组内分工表**：小组成员分工与贡献」。本文件是 17 周的**累计记录**，每次阶段提交时从本文件汇总出该阶段的版本。

## 记录格式

| 周次 | 成员 | 承担工作 | 产出（文件/路径） | 工时 |
|---|---|---|---|---|
| | | | | |

> **产出必须写到具体路径**（如 `project/sql/01-schema/create-tables.sql`）。写"参与讨论""协助"这类无证据的描述，在答辩时会被追问。

---

## 第 1 周

> ⏳ **待确认** —— 以下归属是**依产出物推断**的，需两位本人核对。

| 成员 | 承担工作 | 产出 | 工时 |
|---|---|---|---|
| **胡博锐** | 经营场景选型（推翻"小卖部"改选奶茶店）、主流程与 6 条支撑流程梳理、5 角色与三组职责分离、数据边界清单（进库 19 / 不进库 13） | `weeks/week01/business-requirements.md` | ⏳ |
| **何争霖** | 数据可得性调研与核验：逐一实测下载链接（发现 Lokad 直链 404）、Mendeley API 核验元数据、实测本机网络限制、7 个候选数据集的字段与覆盖度对比 | `weeks/week01/data-availability.md` | ⏳ |

---

## 第 2 周

| 成员 | 承担工作 | 产出 | 工时 |
|---|---|---|---|
| **胡博锐** | ① 关系模式设计（16 条决策 D-01～D-12、21 张表清单，后精简为 **17 张**）<br>② 对同事 3 项排雷 Issue 出具**裁决意见**（D1—D8 + 关闭 3 个设计漏洞）<br>③ 主数据（30 成品 / 60 原料 / **30 款配方 · 492 行**）<br>④ **课程任务 2/3/4**：字段字典（132 字段）、码标注（17 主码 / 17 候选码 / 30 外码）、样例元组（17 表 + 8 项一致性验证）<br>⑤ 域字典（16 条枚举）与编号体系统一（`DOM-` 前缀）<br>⑥ v0.1 阶段报告草稿<br>⑦ 全库文档同步与规范固化 | `weeks/week02/schema-design.md`<br>`weeks/week02/issue-review.md`<br>`weeks/week02/master-data.md`<br>**`project/docs/data-dictionary.md`（新）**<br>**`weeks/submissions/v0.1/report.md`（新）**<br>`README.md` / `STRUCTURE.md` / `weeks/README.md` | ⏳ |
| **何争霖** | ① 建立 Agent 原生 Issue 看板（含模板与 5 项技术排雷）；开工对齐 SOP；团队角色定调；Git 分支与合并规范修订<br>② **仿真造数原型与进销存台账自洽断言**（ISSUE-004）：实现 60 种原料平衡式零误差断言，生成 7 天 20,979 行纯净种子与 90 天压力测试数据 | `harness/issues/`（README + 模板 + 001～005）<br>`harness/prompts/agent-session-start.md`<br>`harness/team/README.md`<br>`harness/conventions/04-git-workflow.md`<br>`project/data/generate_seed.py`（**新**）<br>`project/sql/04-seed/seed_data.sql`（**新**） | ⏳ |

### 第 2 周的分工边界说明

> 按 `team/README.md` 的「**文档全权由 DiSod 独占执笔**」约定，本周双方的产出**天然分层**：

| | 产出性质 | 说明 |
|---|---|---|
| **胡博锐** | **文档 + 设计** | 关系模式、字段字典、裁决意见、报告 —— **全部是文档**，符合文档独占原则 |
| **何争霖** | **机制 + 排雷** | Issue 看板、开工 SOP、团队定调、Git 规范 —— 属**协作机制的建立**，以及后续的**工程实施**（ISSUE-004 造数） |

> **`project/` 下同样按此分层**：设计文档（`project/docs/`）由文档侧执笔；
> 代码（`project/sql/`、造数脚本）由工程侧主责。边界见
> [`04-git-workflow.md`](../conventions/04-git-workflow.md) §2.1。

---

## 第 3 周

| 成员 | 承担工作 | 产出 | 工时 |
|---|---|---|---|
| **胡博锐** | ① 确定数据库环境（**SQL Server 2022** / 排序规则 / 兼容级别 / 库名）<br>② **建库**脚本（幂等，4 项设置锁定）<br>③ **建表** —— 由数据字典逐字翻译出 **17 张表 / 132 字段**<br>④ **约束** —— 17 候选码 + 43 CHECK + 30 外键<br>⑤ **索引** —— 21 个（19 外键路径 + 2 查询驱动），并登记 7 处"不建"及理由<br>⑥ **CRUD 演示脚本**（含 5 个负例）<br>⑦ 打通**一键重建**链路并实测（**17 秒 / 20,979 行**）<br>⑧ 排查修复 **7 个坑**（BOM 静默失效 / 方括号被吃 / 惰性元数据 / `:r` 路径 / 索引误伤系统表 / 糖度档 `ANY` 残留 / `XACT_ABORT` 放大失败）<br>⑨ 固化编码与数据库级约定到规范 · 提报 ISSUE-007 | `project/sql/00-bootstrap/create-database.sql`（**新**）<br>`project/sql/01-schema/create-tables.sql`（**新**）<br>`project/sql/02-constraints/constraints.sql`（**新**）<br>`project/sql/03-indexes/indexes.sql`（**新**）<br>`project/sql/05-dml/crud.sql`（**新**）<br>`project/sql/99-rebuild.sql`<br>`harness/conventions/02-sql-style.md` §7 §9 §10<br>`weeks/week03/README.md`<br>`harness/issues/007-*.md`（**新**） | ⏳ |
| **何争霖** | ① **闭环 ISSUE-007**：造数引擎输出 UTF-8 BOM 规范化、清除糖度 `ANY` 哨兵残留、实现以 `master-data.md` 为唯一真相源的 492 行配方自动解析，消除两处维护技术债<br>② **穿透式代码审查与实测排雷**：复现并定位无券退单积分约束死锁（Error 547）、退单库存多对一回冲吞行漏洞、采购加权成本除零击穿 NOT NULL（Error 515）<br>③ **闭环 ISSUE-008**：修复 `ck_points_ledger_target` 支持无券退单回滚，重构 `crud.sql` 步骤 3.4/3.6 健壮性加固，经 99-rebuild 与 crud 实测验证<br>④ **提报 ISSUE-009**：交叉审查定位 132 vs 133 字段口径不一、数据字典样例 ANY 残留与设计文档 D-05a 段落重复冲突 | `project/data/generate_seed.py`<br>`project/sql/04-seed/seed_data.sql`<br>`project/sql/02-constraints/constraints.sql`<br>`project/sql/05-dml/crud.sql`<br>`harness/issues/007-*.md`<br>`harness/issues/008-*.md`<br>`harness/issues/009-*.md` | ⏳ |

### 第 3 周的分工边界说明

> 仍按 `team/README.md` 的边界：**设计侧文档由文档主编执笔**；
> **`project/data/**` 的脚本改造属工程侧** —— ISSUE-007 已由 hezhlin5 闭环（造数引擎改为 `utf-8-sig`、以 `master-data.md` 为单一真相源）。

---

## 累计贡献汇总

> 每次阶段提交前更新。

| 成员 | 第 1—4 周 | 第 5—9 周 | 第 10—13 周 | 第 14—17 周 | 合计占比 |
|---|---|---|---|---|---|
| **胡博锐** | ⏳ | | | | |
| **何争霖** | ⏳ | | | | |

> **填写提示**：累计占比在**阶段提交时**汇总，第一阶段（第 1—4 周）截止于第 5 周周二。
> 按 `team/README.md` 的约定，工程为 **50/50** 参与，占比差异主要来自文档与专项工作量。
