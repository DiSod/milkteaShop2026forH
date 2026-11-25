# 阶段三报告 · v2.0 · 程序对象、窗口与事务

> 小组：DiSod（胡博锐）· 何争霖　　阶段：第 10—13 周《数据库编程与事务处理》
> 仓库：`DiSod/milkteaShop2026forH`　分支：`main`
>
> 这份文件当前是**骨架**：章节、口径、要放哪些证据都定了，`TODO` 标记的位置等对应批次做完再填。
> 每个数字都必须能在仓库里用脚本重算——算不出来的不写。

## 0. 先说这一阶段我们干了什么

v1.0 交完时，我们的库是「18 张表 + 4 个角色 + 一个能跑的应用」，但**一条业务规则都没落在数据库里**：
下单扣料、算折扣、查报表，全在 Python 里。老师在第 10 周的任务里写得很直接——
「把业务规则落实到存储过程、函数、触发器」。

所以这三周做的事可以一句话说完：**把该在库里做的事搬回库里，并且每一件都有正反例和断言兜着。**

| 类别 | 数量 | 落点 |
|---|---:|---|
| 存储过程 | 2 | `project/sql/09-programmability/procedure.sql` |
| 函数（标量 2 + 内联表值 1） | 3 | `project/sql/09-programmability/function.sql` |
| 触发器 | 4 | `project/sql/09-programmability/trigger.sql` |
| 分析查询脚本 | 3 类 | `window_query.sql`（窗口）、`recursive_query.sql`（递归） |
| 业务事务脚本 | 2 | `project/sql/10-transaction/tx1-*.sql`、`tx2-*.sql` |
| 库内断言 | **96 条** | 五个 `test-*.sql`（22+22+18+21+13） |
| 回归断言 | **21 项** | `project/tests/regression.sql` |
| 应用层测试 | **58 条** | `project/app/tests/` |

规模没有膨胀：**还是 18 张表 / 139 字段 / 49 CHECK / 31 外键 / 22 索引 / 6 视图 / 4 角色**，
第 10—13 周**一张表都没加**（ISSUE-021 §3 定的冻结线）。

<!-- 素材出处：sys.objects 实查 2 P + 3 FN + 4 TR；表/字段数来自 result/01-build/schema-object-summary.txt -->

# 1. 设计：什么留在应用层，什么搬进库

## 1.1 三条线：怎么判断一个逻辑该放哪一层

v1.0 定的三层边界（`web/` 不写 SQL、`service/` 不碰 pyodbc、`dao/` 唯一拼 SQL）解决的是「代码放哪」。
这一阶段要解决的是另一个问题：**同一件事，为什么有的写进过程、有的留在 Python？**

我们最后用的是三条判据，逐条落地：

1. **会不会被第二个调用方用到** —— `fn_sales_summary` 被报表页、`usp_sales_report`、测试三处调用，
   所以必须是函数；而「下单」只有一个入口，留在 service 层。
2. **要不要改数据 + 要不要一个事务** —— 改数据且要原子性的（库存调整）做成过程；
   只算不写的（折扣、补货量）做成函数。
3. **错了该怎么让调用方知道** —— 过程能 `THROW`（错误号 51411…），函数不能
   （一抛整条 `SELECT` 全废），所以函数用返回值/NULL 表达「算不出来」。

<!-- 素材出处：weeks/week10/README.md §1、project/docs/programmability.md「过程与函数的三条判据」 -->

## 1.2 五个对象：签名与分工

| 对象 | 类型 | 一句话职责 | 关键约束 |
|---|---|---|---|
| `usp_sales_report` | 过程 | 按日期区间出销售汇总 | 空参/起止颠倒/超 3660 天分别抛 51401/51402/51403；**只返回一个结果集** |
| `usp_stock_adjust` | 过程 | 调整库存并写流水 | 六种拒绝（51411—51416）；`UPDLOCK` 读结存；`XACT_ABORT` + `TRY/CATCH` |
| `fn_replenish_qty` | 标量函数 | 按水位算补货量 | 达标返回 0，编号不存在返回 **NULL**，永不为负 |
| `fn_sales_summary` | 内联 TVF | 商品级销售明细 | 能直接 `SELECT * FROM …()`；非法参数返回空集 |
| `fn_discount_amount` | 标量函数 | 算折扣金额 | 券与满减**取大不叠加**，会员再减 1，总额不超过订单金额 |

<!-- 素材出处：week10/README.md §1；实测取值见 report §2 -->

## 1.3 触发器：只在「防篡改」的地方用

四个触发器全是**集合级**（`FOR INSERT, UPDATE, DELETE`），没有一行级的：

| 触发器 | 防什么 |
|---|---|
| `trg_stock_ledger_immutable` | 库存流水被改；非 dbo 被删；dbo 删 24 小时前的历史 |
| `trg_points_ledger_immutable` | 同上（积分流水） |
| `trg_order_detail_spec_type_guard` | 明细上的杯型/糖度/冰量填成别的规格类别 |
| `trg_order_header_state_guard` | 订单状态跳态、终态回退；到 `COMPLETED` 自动补 `finish_time` |

为什么不用「下单后自动扣料」这种业务触发器：**扣料逻辑已经在 `place_order` 里，而且需要先校验库存**，
触发器里做这件事会让「库存不足」从「返回 409」变成「插入失败 500」。触发器只用在不影响正常流程的地方。

<!-- 素材出处：project/sql/09-programmability/trigger.sql、harness/issues/021 §2 -->

## 1.4 事务边界：一次下单到底包住了什么

```
BEGIN TRANSACTION
  ① INSERT tbl_order_header        订单头
  ② INSERT tbl_order_detail        明细
  ③ UPDATE tbl_ingredient          扣结存
  ④ INSERT tbl_stock_ledger        写流水（与 ③ 必须成对）
  ⑤ INSERT points_ledger + UPDATE member
COMMIT
```

这五步**要么全有、要么全无**。v1.0 时这件事由 Python 的 `with db.open_session() as s:` 保证，
这一阶段我们用 `tx1-order-commit.sql` / `tx2-order-rollback.sql` 把同一件事摊成 T-SQL，
让「事务包住了什么」可以直接指着看。

<!-- 素材出处：project/sql/10-transaction/tx1-order-commit.sql、tx2-order-rollback.sql、week12/README.md §8 -->

# 2. 实现：逐个对象是怎么做出来的

> 这一章按「解决了什么、怎么验」写，每个对象末尾给出实测输出。

## 2.1 三个函数

TODO：三个函数各 2—3 段（含实测输出截图）

## 2.2 两个存储过程

TODO：`usp_sales_report` 与 `usp_stock_adjust` 各 2—3 段（含错误号实测）

## 2.3 四个触发器

TODO：四个触发器各 1 段 + `test-trigger.sql` 18 条覆盖说明

## 2.4 窗口函数：三类查询，都有业务含义

TODO：三类各 1 段（累计与环比 / 分类内排名与占比 / 近 3 日移动平均）+ 实测表

## 2.5 递归：日期不是表里的数据

TODO：R1 补零 / R2 断档识别 / R3 品类树，含三段实测输出

## 2.6 两段事务脚本：把边界摊开看

TODO：tx1 五步 + tx2 回滚六项比对，含两次运行的输出

# 3. 测试：这一阶段的「证明」长什么样

## 3.1 五套库内断言 + 21 项回归

| 脚本 | 断言数 | 怎么判 | 结果 |
|---|---:|---|---|
| `test-function.sql` | 22 | 固定条数，漏跑判红 | 22/22 |
| `test-procedure.sql` | 22 | 同上 | 22/22 |
| `test-trigger.sql` | 18 | 同上 | 18/18 |
| `test-window.sql` | 21 | 同上，全只读 | 21/21 |
| `test-recursive.sql` | 13 | 同上，全只读 | 13/13 |
| `regression.sql` | 21 | TC-01…TC-21 | 21/21 |

<!-- 素材出处：result/03-regression/regression-verdict.png（21/21）、各 test-*.sql 输出 -->

## 3.2 变异测试：断言到底在不在验

TODO：窗口函数那一轮的四处变异与「假通过」复盘（用例 12 收紧）

## 3.3 应用层没被改坏

`pytest` 58 passed（第 10—11 周从 46 涨到 58，新增两批回归用例），四层验证照旧：
静态 pytest → 连库 regression → 三份基线快照 293 行 → 真 HTTP 点击。

TODO：补一张四层验证矩阵表

# 4. 这一阶段踩的坑

> 只写「改了代码才发现」的，不写纯语法备忘。

## 4.1 存储过程返回多个结果集时，`INSERT … EXEC` 必报 213

TODO：现象（消息 213 列数不匹配）、根因（SQL Server 不支持从多结果集过程取第一个）、
修法（`usp_sales_report` 只返回汇总，明细交给 `fn_sales_summary`）、证明（22/22）

## 4.2 用例会「悄悄消失」——少一条反而全绿

TODO：`SELECT TOP 1` 从真实数据挑「已达标原料」，重建后挑不到 → 少一条；
改为事务里造数据 + 固定总数 22

## 4.3 测试依赖「库里还有可用券」

TODO：用户演示把券用掉 → 券用例退化成「无券」→ 3 条红；改为事务内造 `TESTFN0001/0002`

## 4.4 我写错的预期值：55 元 + 5 元券

TODO：我预期 5，实际 8（券与满减取大），实现对、测试错

## 4.5 往 `tbl_order_header` 写数据必须 `SET QUOTED_IDENTIFIER ON`

TODO：筛选索引 `uq_order_header_coupon` 导致 `消息 1934`，`sqlcmd` 默认 OFF

## 4.6 配方里 `sugar_spec_id IS NULL` 的行不能漏

TODO：只写 `= @sugar_id` 会「没有配方行」，基础原料与糖度无关

## 4.7 `date` 不能减 `bigint`

TODO：`营业日 - ROW_NUMBER()` 报类型冲突，改 `DATEADD(DAY, -CAST(... AS INT), d)`

## 4.8 变异测试抓出的假通过

TODO：用例 12 `COUNT(DISTINCT)=COUNT(*)` 恒真，去掉 `PARTITION BY` 仍绿

# 5. 总结

## 5.1 对照课程第 10—13 周任务

TODO：六项任务逐项对照表（销售统计过程 / 库存调整过程 / 补货量函数 / 销售汇总 TVF /
折扣计算 / 整合）+ 第 11—13 周（触发器与窗口 / 递归与事务 / 并发）

## 5.2 还没做到的和下一步

TODO：并发与死锁（第 13 周，hezhlin5 主责）、品类树仍是平的、应用层还没切到调用存储过程

# 附录

## 附录 A · AI 使用记录（摘要）

TODO：指向 `ai-log.md` 的本阶段条目

## 附录 B · 组内分工

TODO：继承 v1.0 的分工表，补第 10—13 周的分工
