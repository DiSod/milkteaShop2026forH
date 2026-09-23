# issues · 团队协作与技术排雷看板

本项目采用 **Agent 原生文件式 Issue 系统**。
用于在舍友二人与各自的 AI Agent 之间建立高效、异步、可追溯的技术交流通道，无需对微观技术细节进行低效的口头传达。

---

## 规则摘要（两句话铁律）
1. **统一在 `main` 追踪**：所有 Issue 直接在 `main` 维护，一 Issue 一文件，避免并发编辑大文件产生 Git 冲突；
2. **开工必对齐，修复随合闭环**：
   - Agent 每次开工前，先读取本看板认领属于自己的待办；
   - 开发分支每次动工前先 `git pull --rebase origin main`；
   - 修复分支在本地跑通 `project/sql/99-rebuild.sql` 后，将对应 Issue 标记为 `🟢 已解决`，合并回 `main` 闭环。

---

## 当前 Issue 看板索引

| 编号 | 核心主题 | 类型 | 建议指派 | 状态 | 关联核心文件 |
|---|---|---|---|---|---|
| [**001**](001-real-world-inventory-and-backflushing.md) | **还原真实奶茶店库存机制**：反冲倒扣、手工沽清与打烊损耗（取消“还能做几杯”与两层移库流水） | 业务模型重构 | 双人共同讨论 / 文档主编 | 🔴 待处理 | [`weeks/week02/schema-design.md`](../../weeks/week02/schema-design.md) (D-01~D-03) |
| [**002**](002-schema-scope-and-table-count.md) | **第 1 阶段表结构精简**：从 21 张表收敛至 10~12 张核心表（非核心拆分留待后续重构） | 架构边界 | 双人共同讨论 / 文档主编 | 🔴 待处理 | [`weeks/week02/schema-design.md`](../../weeks/week02/schema-design.md) |
| [**003**](003-add-supplier-entity.md) | **采购单补全供应商外码**：补建极简 `tbl_supplier`，消除“向空气采购”漏洞 | 关系规范化 | 双人共同讨论 / 文档主编 | 🔴 待处理 | [`weeks/week01/business-requirements.md`](../../weeks/week01/business-requirements.md) (§2.4) |
| [**004**](004-data-generation-prototype.md) | **锁定销量母本并启动 Python 仿真造数原型**：验证台账平衡闭环（7天/90天） | 数据工程 | 核心工程 (主抓造数脚本) | 🔴 待处理 | [`project/data/README.md`](../../project/data/README.md) |
| [**005**](005-collaboration-and-git-alignment.md) | **协作与分工定调**：明确文档归舍友、工程分阶段切分、严格遵守 Agent 对齐与提交规范 | 流程与规范 | 双人共同讨论 / 文档主编 | 🔴 待处理 | [`harness/team/README.md`](../team/README.md), [`04-git-workflow.md`](../conventions/04-git-workflow.md) |

---

## 状态图例
- 🔴 **待处理 (Open)**：已提报，待责任人认领或双人讨论
- 🟡 **进行中 (In Progress)**：责任人已认领，正在对应分支上修复/求证
- 🟢 **已解决 (Resolved)**：修复代码或文档已合并回 main，Issue 关闭
- ⚪ **暂不处理 (WontFix)**：经讨论达成一致，维持原设计或取消
