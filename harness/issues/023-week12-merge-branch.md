# 023 · 分支说明：`feat/week12-merge-advanced`（方案 B 产物，未合 main）

| 项目 | 内容 |
|---|---|
| 分支 | `feat/week12-merge-advanced` |
| 基提交 | `8d7ddf0`（`main` 当时所在） |
| 分支提交 | `77afe08` `feat(sql): 按方案 B 吸纳队友第 12 周脚本` |
| 规模 | 9 文件 +1,380 / −48 |
| 状态 | 🟡 **待复核** —— 代码只在这个分支上，`main` 未改动 |
| 相关 | [ISSUE-022](022-week12-overlap-and-week13-concurrency.md)（重叠裁定与四方案） |

---

## 0. 一句话

这是 **ISSUE-022 选了方案 B（去重吸纳）之后的产物**：把队友分支
`feat/week12-advanced-query-and-transaction` 里我们主干没有的东西吸收进来，
统一成一套第 12 周脚本。**它现在只在本地分支上，没有合进 `main`**，所以
拉 `main` 是看不到的，要 `git switch feat/week12-merge-advanced` 才能看到。

## 1. 为什么单独开一个分支，而不是直接合

1. ISSUE-022 里还有四个问题没定（AQ5 的 `IDENTITY` 消耗、并发脚本是否跑过、
   两份 README 口径谁为准、第 13 周报告章节归谁写）；
2. 这次改动**动了队友写的文件**（把他的 AQ2/AQ3 并进我们的 `window_query.sql`），
   属于"共同资产"，一个人拍板不合适；
3. 主干保持绿色：`main` 现在 `regression` 21/21、`pytest` 58 passed 都是可用的，
   分支上做了几处语义调整（见 §4），不适合直接压上去。

## 2. 分支里到底改了什么

| 文件 | 改动 | 来源 |
|---|---|---|
| `project/sql/09-programmability/window_query.sql` | 新增**查询 5**：会员价值分层 + 平均复购间隔（`LAG` 算间隔、`NTILE(4)` 四分位、`DENSE_RANK` 排名） | 他的 AQ2 |
| 同上 | 新增**查询 6**：原料消耗成本 ABC 帕累托（累计占比 ≤80% 为 A、≤95% 为 B、其余 C） | 他的 AQ3 |
| `project/sql/09-programmability/test-window.sql` | 断言 **21 → 30 条**（补 22—26 会员层、27—30 ABC 层） | 新增 |
| `project/sql/10-transaction/recursive_query.sql` | **R3** 从"只能展开一层"改成**临时表造三级树** + 祖先-后代映射自底向上汇总，真表零写入 | 他的 AQ5（改法见 §4.1） |
| `project/sql/10-transaction/test-recursive.sql` | 断言 **13 → 15 条**（12—14 改三级树验证） | 新增 |
| `project/sql/10-transaction/tx3-purchase-commit.sql` | **新增**：补货入库的成功路径（改实收 → 重算移动加权成本 → 加结存 → 写 `PURCHASE_IN` → 采购单结案，五步同一事务） | 他的 TX-2A |
| `project/sql/10-transaction/tx4-purchase-rollback.sql` | **新增**：补货入库的失败路径（中途 `THROW 51642`，验证结存/成本/流水三样都不留半条账） | 他的 TX-2B |
| `project/sql/10-transaction/concurrency-guide.sql` | **新增**：双会话并发实验引导（第 13 周内容） | 原样复制 |
| `project/sql/10-transaction/run-concurrency-experiments.py` | **新增**：并发实验脚本（519 行） | 原样复制 |
| `weeks/week12/README.md` | 新增 **§10 合并说明**（吸收清单 / 没吸收什么 / 断言数对照） | 新增 |
| `harness/issues/022` | 补 **§6 解决记录** | 新增 |

## 3. 门禁（2026-11-27 全跑过）

| 检查 | 结果 |
|---|---|
| `test-window.sql` | **30/30 PASS** |
| `test-recursive.sql` | **15/15 PASS** |
| `tx1-order-commit.sql` / `tx2-order-rollback.sql` | exit=0（七项指标前后一致） |
| `tx3-purchase-commit.sql` | exit=0 —— 实收 100、结存 4418.900 → 4518.900、成本 0.0620 → 0.0624、流水 1 条、采购单 `ACCEPTED` |
| `tx4-purchase-rollback.sql` | exit=0 —— 捕获 51642，结存/成本未变、本单流水 0 条、实收 0 |
| `regression.sql` | **21/21** |
| `99-rebuild.sql` | exit=0 → 18 表 / 139 字段 / 49 CHECK / 4 触发器 |
| `pytest` | **58 passed** |

所有事务脚本**自带清理**（删本次采购单与流水、按 Σ流水 重算结存、还原移动加权成本），
跑完库回到基线：订单 1,963 / 库存流水 13,851 / 结存合计 403,371.600 / 积分 25,224 / 漂移 0。

## 4. 三处我没有照抄的地方（需要你确认）

### 4.1 AQ5 不再往真表 `INSERT`

你的 AQ5 是「事务内 `INSERT` 两个根类 + 改 5 个真实分类的 parent + 插一个叶子 → 递归 → `ROLLBACK`」。
`ROLLBACK` 会回滚数据，但**不回滚 `IDENTITY` 号段**——每跑一次就永久消耗几个 id。
我改成：把真实 5 个分类搬进 `#品类` 临时表，在临时表里加根加叶子、改父子关系，
**真表零写入**，自然也不需要 `ROLLBACK`。数字对得上：`R01 1,862 杯 / 17,063.00`、`R02 717 杯 / 6,819.00`。

### 4.2 TX-1/TX-2 拆成四段

你的 `tx-order-and-replenish.sql` 把「订单事务」和「补货事务」合在一个文件里（384 行）。
我拆成 `tx1` / `tx2` / `tx3` / `tx4` 四个文件，好处是**每一段可以单独跑、单独截图、单独说明失败路径**，
坏处是文件变多。如果你更想要"一个文件看全"，我可以合回去。

### 4.3 `10-transaction/README.md` 没有保留

你那份 25 行的 README 内容（采购事务的五步、锁表顺序）我并进了
`weeks/week12/README.md` §8/§10，避免同一个东西两处口径。如果你希望它作为独立文件存在，我加回来。

## 5. 怎么本地复核（三条命令）

```powershell
git fetch --all --prune
git switch feat/week12-merge-advanced

sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\sql\09-programmability\test-window.sql
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\sql\10-transaction\test-recursive.sql
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\sql\10-transaction\tx3-purchase-commit.sql
```

看四个地方：`30 条用例全部通过`、`15 条用例全部通过`、`【TX3 结论】✅ PASS`、
以及跑完 `SELECT COUNT(*) FROM tbl_purchase_order;` 仍是 8 张（说明自清理生效）。

## 6. 什么时候合进 main

**等你回 ISSUE-022 那四个问题**，尤其是：

1. 第 13 周的并发实验脚本你跑过没有？报告里那一段写"实测通过"还是"脚本已备、待跑"？
2. 第 13 周报告章节（事务 + 并发）归谁写？
3. §4 那三处改法你认不认（AQ5 改临时表 / TX 拆四段 / README 合并）。

这三点一确认，我就 `git switch main && git merge --ff-only feat/week12-merge-advanced` 并推上去。
在那之前，**这个分支就是"给你看的草稿"**，不影响主干任何东西。

---

*作者：DiSod（胡博锐）· 2026-11-27*
