# v2.0 · 阶段三交付说明（第 10—13 周）

> 课程《数据库编程与事务处理》。v1.0 把「设计 + 迁移 + 应用」做完了，
> 这一阶段做的是**把业务规则搬进数据库**：存储过程、函数、触发器，外加窗口、递归与事务。
>
> 冻结线（ISSUE-021 §3）：**18 张表不新增**。所有新能力都靠「库内对象」实现，不改表结构。

## 一、这一版交付什么（六件，与 v1.0 同口径）

| # | 交付物 | 落点 | 状态 |
|---|---|---|---|
| 1 | 提交说明 | 本文件 | ✅ |
| 2 | SQL 代码 | `project/sql/`（37 个脚本，含 `09-programmability/` 8 个、`10-transaction/` 4 个） | ✅ |
| 3 | 运行结果 | `result/`（证据目录，分组见 `result/README.md`） | ⬜ 待采 |
| 4 | 阶段报告 | [`report.md`](report.md) | 🟡 骨架已建，§2—§5 待填 |
| 5 | AI 使用记录 | `ai-log.md` | ⬜ 待写 |
| 6 | 组内分工 | `contributions.md` | ⬜ 待写（继承 v1.0，补第 10—13 周） |

## 二、与 v1.0 比，多了什么

| 维度 | v1.0（第 8—9 周） | v2.0（第 10—13 周） |
|---|---|---|
| 表 / 字段 / CHECK | 18 / 139 / 49 | **一样**（冻结） |
| 存储过程 | 0 | **2**（`usp_sales_report`、`usp_stock_adjust`） |
| 函数 | 0 | **3**（2 个标量 + 1 个内联表值） |
| 触发器 | 0 | **4**（两个流水不可篡改 + 两个数据守卫） |
| 分析查询 | 0（只有 1 处 `ROW_NUMBER`） | **窗口 4 段 + 递归 3 段** |
| 业务事务脚本 | 0（事务在 Python 里） | **2 段 T-SQL**（成功提交 / 中途回滚） |
| 库内断言 | 15 项回归 | **21 项回归 + 96 条可编程对象断言** |
| 应用层测试 | 46 条 | **58 条** |

## 三、复现

```powershell
# 1) 从零重建（约 21 秒）：18 表 + 139 字段 + 49 CHECK + 9 个可编程对象
cd project\sql
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i 99-rebuild.sql

# 2) 可编程对象断言（96 条）
cd ..\..
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\sql\09-programmability\test-function.sql
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\sql\09-programmability\test-procedure.sql
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\sql\09-programmability\test-trigger.sql
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\sql\09-programmability\test-window.sql
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\sql\10-transaction\test-recursive.sql

# 3) 回归（21 项）与应用层（58 条）
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i project\tests\regression.sql
cd project\app; python -m pytest -q
```

`99-rebuild.sql` 里挂的是**对象**（`09-programmability/{function,procedure}.sql`）；
`test-*.sql`、`window_query.sql`、`recursive_query.sql`、两段事务脚本都是**查询与断言**，不进重建，重建后直接跑。

## 四、目录

```
weeks/submissions/v2.0/
├── README.md          ← 本文件
├── report.md          ← 阶段报告（骨架）
├── result/            ← 运行结果证据（待采）
├── ai-log.md          ← 待写
└── contributions.md   ← 待写
```

代码在 `project/sql/09-programmability/` 与 `project/sql/10-transaction/`，
报告里引用的数字都能用上面第 1—3 步重算。

## 五、这一版还没做

1. **第 13 周并发与死锁实验** —— hezhlin5 主责，两个会话脚本 + 锁信息 + 分析。
2. **应用层还没切到调用存储过程** —— 现在 `place_order` 仍自己拼 SQL；课程第 10 周任务 6 要求
   「应用里已实现的要替换，页面层只调用」，这一条留到 v2.0 收尾（与 P-2 的存储过程下沉一起做）。
3. **品类树仍是平的** —— `parent_category_id` 全为 NULL，递归查询目前只有一层。
4. **`result/` 证据目录未采**、`ai-log.md` 与 `contributions.md` 未写。
