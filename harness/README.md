# harness · 协作域

本项目的**协作规范与留痕**。这里定义"活怎么干"，不存放任何业务内容。

## 一句话职责

| 目录 | 管什么 |
|---|---|
| `conventions/` | **规范文档**：目录命名、SQL 风格、文档格式、Git 流程、AI 协作 |
| `team/` | **小组**：成员名单、17 周分工与贡献记录 |
| `prompts/` | **可复用提示词**：经过验证的、可再次使用的提示词 |
| `skills/` | **可复用技能/工作流**：重复性任务的固定做法 |
| `agents/` | **子代理任务定义**：可委派的独立任务模板 |
| `logs/` | **留痕**：会话与操作记录 |

## 边界规矩

> **本域只放规则与留痕。**
> 出现 SQL、数据、业务文档，即为放错位置：
> - SQL → `project/sql/`
> - 数据 → `project/data/`
> - 业务文档 → `weeks/` 或 `project/docs/`

## 为什么需要这个域

课程明确要求：**"允许使用大模型，但须保留提示词、候选答案、人工修改与验证证据；AI 生成结果不能替代 SQL 测试、约束验证和个人答辩。"**

本项目大量借助 AI（harness）完成工作，因此必须把"怎么用 AI"固化成规范，让留痕**可审计、可复现**，而不是事后补写。同时它也承载小组协作的规则——2—3 人共用仓库，没有统一规范必然冲突。

## 规范清单

| # | 文档 | 管什么 |
|---|---|---|
| 01 | [`conventions/01-layout-and-naming.md`](conventions/01-layout-and-naming.md) | 目录与命名 |
| 02 | [`conventions/02-sql-style.md`](conventions/02-sql-style.md) | SQL 编写风格 |
| 03 | [`conventions/03-documentation.md`](conventions/03-documentation.md) | 文档与报告格式 |
| 04 | [`conventions/04-git-workflow.md`](conventions/04-git-workflow.md) | Git 提交与分支 |
| 05 | [`conventions/05-ai-collaboration.md`](conventions/05-ai-collaboration.md) | **AI 协作与留痕** |

## AI 留痕的存放位置

| 内容 | 位置 | 进 git |
|---|---|---|
| 正式提交用的 AI 使用记录 | `weeks/submissions/vX.Y/ai-usage.md` | ✅ |
| 周度 AI 使用记录 | `weeks/weekNN/README.md` 的「AI 使用记录」小节 | ✅ |
| 经整理的可复用提示词 | `harness/prompts/` | ✅ |
| 原始会话日志 / 大段原始对话 | `harness/logs/raw/` | ❌ 已 gitignore |

详见 `conventions/05-ai-collaboration.md`。
