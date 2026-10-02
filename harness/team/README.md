# team · 小组

> 舍友二人对等协作，开发模式为 Agent 原生 + 全员工程参与。

## 成员名单

课程要求 2—3 人一组，共用一个代码仓库。

| 用户名 | 姓名 | 学号 | 核心角色 | 主要职责范围 | 数据库账号（第 3 阶段用） |
|---|---|---|---|---|---|
| **DiSod** | 胡博锐 | 24325095 | 文档主编 / 架构统筹 / 阶段答辩展示人 | 全库规范与周报文档统筹、业务模式设计、答辩 PPT 与现场汇报、阶段工程共建 | `db_disod` |
| **hezhlin5** | 何争霖 | 24325094 | 核心工程 / 技术把关 / 数据与测试保障 | 数据仿真造数算法与台账自洽、SQL 性能与重构排雷、Issue 看板维护、阶段工程共建 | `db_hezhlin5` |

## 协作约定（舍友对等模式）

| 项 | 约定 |
|---|---|
| **基本关系** | 舍友二人同组，面对面高带宽交流，杜绝低效文字传话 |
| **文档归属** | 全权由 **DiSod** 负责统一执笔、排版与落库，彻底避免 Markdown 并发 Git 冲突 |
| **工程分工** | **全员参与（50/50 代码量）**，按方案 B 分阶段切分，核心底线是**任何时候两人开发域尽量不重叠** |
| **技术细节传递** | 微观技术问题与排雷建议直接走 [`harness/issues/`](../issues/README.md) 看板，零口头中转成本 |
| **开工与分支** | 每次开工前使用 [`agent-session-start.md`](../prompts/agent-session-start.md) 对齐 Agent；分支开工必先 `git pull --rebase origin main` |
| **合并底线** | 任何代码合并至 `main` 前，必须在本地确认 [`project/sql/99-rebuild.sql`](../../project/sql/99-rebuild.sql) 一键重建跑通无误 |

## 相关文档

- 分工与贡献累计记录 → [`contributions.md`](contributions.md)（后续填报）
- Git 协作规范 → [`../conventions/04-git-workflow.md`](../conventions/04-git-workflow.md)
- 会话开工对齐提示词 → [`../prompts/agent-session-start.md`](../prompts/agent-session-start.md)
- 技术排雷看板 → [`../issues/README.md`](../issues/README.md)
