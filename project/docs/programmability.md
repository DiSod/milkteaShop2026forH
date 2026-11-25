# 第 10 周可编程对象：两个存储过程 + 三个函数

> 本文件记录第 10 周（《数据库编程与事务处理》第一周）在库内实现的五个对象：
> 它们各管什么、为什么是过程而不是函数（或反过来）、以及 44 条正反例的实测结果。
> 全量用例在 `project/sql/09-programmability/test-function.sql` 与 `test-procedure.sql`，两个脚本失败即非零退出。

## 1. 五个对象一览

| 对象 | 类型 | 签名 | 一句话职责 |
|---|---|---|---|
| `usp_sales_report` | 存储过程 | `(@start_date DATE, @end_date DATE)` | 给定日期区间，返回一行汇总（订单数 / 销售数量 / 销售金额 / 会员单数 / 客单价） |
| `usp_stock_adjust` | 存储过程 | `(@ingredient_id INT, @delta DECIMAL(12,3), @reason NVARCHAR(200), @operator_id INT)` | 改一次结存并留一条流水，全程一个事务 |
| `fn_sales_summary` | 内联表值函数 | `(@start_date DATE, @end_date DATE)` | 按商品汇总销量与销售额，可在 `SELECT` 里直接用 |
| `fn_replenish_qty` | 标量函数 | `(@ingredient_id INT)` | 按当前结存 / 补货点 / 目标水位算建议补货量 |
| `fn_discount_amount` | 标量函数 | `(@member_id INT, @amount DECIMAL(10,2), @coupon_id INT)` | 算这一单能减多少钱（券 / 满减 / 会员） |

返回值：两个标量函数各返回一个数值（`DECIMAL(12,3)` / `DECIMAL(10,2)`），表值函数返回一张表。

## 2. 过程与函数怎么分工

这是课程明确要求“说清楚”的一点。我们用的判据只有三条：

| 判据 | 选过程 | 选函数 |
|---|---|---|
| 是否改数据 | 要改（结存、流水） | 只读，只算 |
| 是否需要报错 | 参数非法要明确拒绝（`THROW` + 错误号） | 不能报错，返回 `NULL` / 空集 / 0 |
| 是否需要放进查询 | 不需要 | 要能 `SELECT ... FROM dbo.fn_x(...)` |

落到本项目：

- **销售统计**是“要报错 + 要汇总”的入口 → 过程；明细部分交给 `fn_sales_summary`，这样明细口径只有一处。
- **库存调整**要写两处（结存 + 流水）且必须原子 → 过程，事务开在库里。
- **补货量**要出现在库存列表的每一行 → 标量函数；编号不存在时**返回 `NULL`** 而不是 `THROW`，因为它在 `SELECT` 里，一抛整条查询就废。
- **销售明细**要能 `JOIN`、能加条件 → 内联表值函数（类型码 `IF`），比多语句 TVF 快，也更好优化。
- **折扣**是“纯计算、要被历史订单复用” → 标量函数；只算不写，写回订单是调用方的事。

## 3. 逐个说明

### 3.1 `usp_sales_report`

- **口径**：只算 `pay_status = 'SUCCESS'` 且 `order_status <> 'CANCELLED'`（D 口径），日期**闭区间**（含首尾当天）。
- **订单级指标从订单头算**：一单多明细时 `JOIN` 会把订单数放大成行数，所以订单数、金额、会员单数单独从 `tbl_order_header` 统计；杯数从 `tbl_order_detail` 统计。
- **空区间也返回一行**（全 0），页面不必判空。
- **拒绝三种输入**：任一参数为 `NULL` → 51401；起 > 止 → 51402；跨度 > 366 天 → 51403。
- **只返回一个结果集**，明细由 `fn_sales_summary` 提供，原因见 §5.1。

### 3.2 `usp_stock_adjust`

- **六个拒绝条件**（错误号）：原料不存在 51411 / 数量为空或 0 → 51412 / 原因为空白 → 51413 / 原因超 200 字 → 51414 / 调整后为负 → 51415 / 操作员不存在 51416。
- **事务**：`SET XACT_ABORT ON` + `BEGIN TRAN` + `TRY/CATCH`，`CATCH` 里先 `ROLLBACK` 再 `THROW`（错误号不丢）。
- **并发**：读结存时 `WITH (UPDLOCK, ROWLOCK)`，两个会话同时调不会各读一次旧值。
- **不新增流水类型**（按老师要求复用）：正数写 `PURCHASE_IN`、负数写 `LOSS`，都配 `ref_type = 'MANUAL'`，`remark` 存原因，`operator_id` 存操作人。
- **回报**：调整前 / 调整量 / 调整后 / 流水类型 / 流水号，页面直接显示。

### 3.3 `fn_sales_summary`

内联 TVF，`WHERE` 里先判 `@start_date IS NOT NULL AND @end_date IS NOT NULL AND @start_date <= @end_date` —— 非法参数自然得到空集（内联 TVF 不允许 `THROW`，校验留在过程侧）。

### 3.4 `fn_replenish_qty`

- 目标水位 = `target_level`，为空则 `reorder_point * 2`；两者都为空返回 0。
- 缺口 = 目标 − 结存，`<= 0` 返回 0（已达标不补）。
- **编号不存在返回 `NULL`**：与“达标返回 0”区分开，调用方能分辨“没这个原料”和“不用补”。

### 3.5 `fn_discount_amount`

三条依据，取较优：

1. **券**：`UNUSED` + 属本人 + 在有效期内 + 订单金额达到 `min_order_amount` + 模板 `is_active = 1` → 抵券面额；
2. **满减**（硬编码）：满 50 减 8、满 30 减 3、其余 0；
3. **会员**：会员再加 1 元。

券与满减**取大不叠加**，会员 1 元可叠加，总额不超过订单金额。只算不写。

## 4. 结果记录（44 条用例，摘录）

| # | 输入 | 预期 | 实际 | 结果 |
|---|---|---|---|---|
| F1 | `fn_replenish_qty(19)` 布丁粉 | 目标 4000 − 结存 260 = 3740 | 3740.000 | ✅ |
| F2 | `fn_replenish_qty(-1)` 不存在 | `NULL` | `NULL` | ✅ |
| F3 | 已达标原料 | 0 | 0 | ✅ |
| F4 | `fn_sales_summary('2026-09-18','2026-09-23')` | 与独立查询逐行一致 | 一致 | ✅ |
| F5 | `fn_sales_summary(非法日期)` | 空集 | 0 行 | ✅ |
| F6 | `fn_discount_amount(NULL, 55, 5 元券)` | 取优 → 满减 8 | 8.00 | ✅ |
| F7 | `fn_discount_amount(会员, 20, NULL)` | 满减 0 + 会员 1 = 1 | 1.00 | ✅ |
| P1 | `usp_sales_report('2026-09-18','2026-09-23')` | 1,674 单 / 20,692.00 / 2,245 杯 | 同 | ✅ |
| P2 | `usp_sales_report(NULL, …)` | 抛 51401 | 51401 | ✅ |
| P3 | `usp_stock_adjust(1, -1.5, 原因, 5)` | 结存 4418.900 → 4417.400，流水 `LOSS` / `MANUAL` | 同 | ✅ |
| P4 | `usp_stock_adjust(1, 0, …)` | 抛 51412 | 51412 | ✅ |
| P5 | `usp_stock_adjust(1, -99999999, …)` | 抛 51415 | 51415 | ✅ |
| P6 | 超结存被拒之后 | 结存不变 | 4917.400 | ✅ |
| P7 | 同参数连调两次 | 不报错，减两次 | 4915.400 | ✅ |
| P8 | 清理后 | 结存 4418.900、流水 13,851 行 | 同 | ✅ |

（F 编号对应 `test-function.sql` 的 22 条，P 编号对应 `test-procedure.sql` 的 22 条；两个脚本各自打印完整表格并以 `PASS` / `FAIL` 计数收尾。）

## 5. 遇到的问题

### 5.1 过程返回两个结果集时，`INSERT ... EXEC` 必报 213

最初 `usp_sales_report` 设计成“结果集 1 汇总 + 结果集 2 明细”，测试脚本想用 `INSERT INTO #rep EXEC ...` 抓汇总做断言，结果报：

```
消息 213，级别 16 ... 列名或所提供值的数目与表定义不匹配。
```

用最小用例复现后确认这是 SQL Server 的行为（不是“只取第一个结果集、其余忽略”），于是把明细挪到 `fn_sales_summary`，过程只返回一个结果集。**好处不只是可测**：过程管汇总与报错、函数管可复用明细，正好对应课程“区分存储过程与函数”的要求。

### 5.2 函数里不能 `THROW`

标量函数在 `SELECT` 里被调用，一抛异常整条查询失败。所以 `fn_replenish_qty` 用 `NULL` 表示“编号不存在”，`fn_sales_summary` 用空集表示“参数非法”，校验留在过程侧。

### 5.3 统计函数个数要认三种类型

`sys.objects.type` 里：`FN` = 标量函数，`IF` = 内联表值函数，`TF` = 多语句表值函数。只查 `FN` 会漏掉 `fn_sales_summary`（它是 `IF`），TC-16 第一次就是因为这个判红。

### 5.4 测试数据要自己造，别依赖库里剩下什么

`fn_discount_amount` 依赖“有一张可用券”、`fn_replenish_qty` 依赖“有一个已达标原料”。演示时券会被用掉、重建后原料全是低水位 —— 用例会**悄悄少一条**（`SELECT TOP 1` 选不中就不插），少一条反而更容易全绿。这次改成：在事务里插测试券、临时抬高某个原料的结存，跑完 `ROLLBACK`，并且**固定用例数**（22 条，少一条即判红）。

## 6. 怎么自己验

```powershell
cd project\sql
sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -b -f 65001 -i 09-programmability\test-function.sql
sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -b -f 65001 -i 09-programmability\test-procedure.sql
sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -b -f 65001 -i ..\tests\regression.sql
```

三条命令都应 exit 0；回归脚本末尾的 `TC-16` 会额外确认 5 个对象都在库里、`fn_replenish_qty` 取值正确。
