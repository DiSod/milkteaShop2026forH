# 10-transaction · 事务与并发控制实验

本目录对应课程第 12—13 周任务（**订单和补货事务边界** + **锁等待、隔离现象与死锁分析证据**）。

## 1. 文件清单

| 文件 | 用途 | 执行方式 |
|---|---|---|
| [`tx-order-and-replenish.sql`](tx-order-and-replenish.sql) | 订单下单/完单、模拟补货入库的正常 `COMMIT` 与失败 `ROLLBACK`（4 组事务 + 零漂移自检） | `sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -b -i project\sql\10-transaction\tx-order-and-replenish.sql` |
| [`run-concurrency-experiments.py`](run-concurrency-experiments.py) | 基于真实双/三会话 `pyodbc` 连接的自动化并发实验套件（隔离级别 / `LCK_M_U` 锁等待 / 1205 死锁与升序根治） | `project\app\.venv\Scripts\python.exe project\sql\10-transaction\run-concurrency-experiments.py` |
| [`concurrency-guide.sql`](concurrency-guide.sql) | 答辩现场 SSMS / 双 `sqlcmd` 窗口交互演示分段剧本 | 按会话 A / B 分段执行 |

> 同批配套的第 12 周高级查询脚本（窗口函数 + 递归 CTE）位于 [`../06-query/advanced-query.sql`](../06-query/advanced-query.sql)。

---

## 2. 实验结论摘要

| 实验项 | 改进前（问题现象） | 改进后（解决措施与结果） |
|---|---|---|
| **脏读** | `READ UNCOMMITTED` 读到未提交的 `+888.000` 脏库存 | `READ COMMITTED` 自动阻塞等待回滚，读回真实已提交值 |
| **不可重复读** | `READ COMMITTED` 同事务内两次读取结存相差 `+10.000` | `REPEATABLE READ` 对读行加共享锁直到事务结束，写会话阻塞，两次读取一致 |
| **幻读** | `REPEATABLE READ` 下并发插入 `PHANTOM1` 使范围计数从 `0` 变 `1` | `SERIALIZABLE` 施加范围锁（RangeS-S）阻塞并发插入，计数保持 `0` |
| **超卖 TOCTOU 与锁等待** | 无锁先查后扣时，双并发均通过余量检查，第二笔撞 `ck_ingredient_qty_on_hand`（547）崩溃 | 改用 `WITH (UPDLOCK, ROWLOCK)`；通过 `sys.dm_os_waiting_tasks` 捕获真实 `LCK_M_U` 锁等待，第一笔提交后第二笔读到 `0` 并优雅拒单 |
| **AB-BA 死锁（1205）** | 会话 A 锁 `1→2`、会话 B 锁 `2→1`，稳定触发 SQL Server 错误 `1205`（死锁牺牲者） | 统一按 **`ingredient_id` 升序**加 `UPDLOCK, ROWLOCK`，5 轮 10 并发事务 **0 次死锁** |
