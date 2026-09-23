# ISSUE-005: 明确文档归舍友、工程分阶段切分、严格遵守 Agent 对齐与提交规范

| 元数据 | 内容 |
|---|---|
| **状态** | 🔴 待处理 (Open) |
| **类型** | 团队协作 / 流程规范 |
| **提报人/Agent** | 二人小组工程侧 Agent |
| **指派处理** | 双人共同讨论 / 文档主编 |
| **提报日期** | 2026-09-23 |
| **关联文件** | [`harness/team/README.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/harness/team/README.md), [`harness/conventions/04-git-workflow.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/harness/conventions/04-git-workflow.md), [`harness/prompts/agent-session-start.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/harness/prompts/agent-session-start.md) |

---

## 1. 为什么提这个 Issue？（直白说问题）
我们是舍友二人同组，且主要通过 AI Agent 辅助开发。
之前由于分工界限和提交规范不够明确，导致出现过：
- 两人/两 Agent 改文档时容易产生上下文漂移；
- 各自开发容易发生代码踩脚；
- 对齐规范若太复杂执行不下去，若太随意又会造成仓库混乱。

---

## 2. 协作与分工的三大原则（直接定调）

### 原则一：全库文档全权由舍友负责（独占维护）
- **核心规矩**：所有规范文档（`harness/`）、周报与阶段报告（`weeks/`）统筹由**舍友统一执笔维护与排版**。
- **为什么这么做**：彻底消灭两人同时改 Markdown 产生的毁灭性 Git 冲突；工程侧有修改意见通过本 Issue 看板或宿舍口头提议，由舍友统一汇总落库。

### 原则二：工程全员参与，按方案 B 分阶段切分，开发域不重叠
- **不用过早把人卡死在某个具体模块**，大家都有工程实操；
- 核心要求是：**任何时候两人的开发域尽量不重叠**，大致保持偏向：
  - **第 1 阶段**：一人偏重模式结构与约束 DDL，一人偏重种子数据生成与装载查询；
  - **第 2 阶段**：一人偏重 ER 规范化重构迁移，一人偏重应用界面与参数化调用；
  - **第 3 阶段**：一人偏重存储过程与触发器编程，一人偏重并发事务与锁实验设计；
  - **第 4 阶段**：一人偏重销量预测模型，一人偏重预测驱动补货事务与 NL2SQL。

### 原则三：Agent 开工对齐与 GitHub 提交规范（大道至简，确定了就必须死守）
为保证开发绝对顺畅，将流程精简为两条**必须严格执行的死规矩**：
1. **Agent 开工必须执行对齐**：
   - 每次开工前，将 [`harness/prompts/agent-session-start.md`](../prompts/agent-session-start.md) 发给 Agent，让 Agent 自动查阅当前周进度与本 Issue 看板，确认上下文再动手；
2. **Git 提交与分支铁律**：
   - **Issue 看板在 `main` 维护**：提报或关闭 Issue 直接推 `main`；
   - **开发分支开工必拉取**：开发分支每次动工前，先执行一条 `git pull --rebase origin main` 同步最新 Issue，绝不落后；
   - **代码合并底线**：任何分支合入 `main` 前，必须在本地确认 `project/sql/99-rebuild.sql` 一键跑通无报错！
