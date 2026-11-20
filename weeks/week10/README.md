# 第 10 周实施清单（任务 → 落点 → 验收）

> 本文件是**开工前的清单**，不是交付物。批准后按它写 SQL。
> 依据：`course` 第三阶段第 10 周任务（存储过程与函数）六条 + 作业五项。
> 现状：`project/sql/09-programmability/` 与 `10-transaction/` 是 v0.1 预留的空目录，**库里目前 0 个存储过程 / 0 个函数 / 0 个触发器**。

## 0. 一句话范围

第 10 周只做**四类对象 + 折扣**，全部落在 `09-programmability/`；**不动**下单主流程（`place_order` 的下沉属于任务 6「整合」，与 P-2 一起单独一轮做）。

---

## 1. 五个对象

### 1.1 `usp_sales_report`（销售统计存储过程）

```sql
CREATE PROCEDURE dbo.usp_sales_report
    @start_date DATE,
    @end_date   DATE
AS
```

| 项 | 设计 |
|---|---|
| 参数校验 | `@start_date`/`@end_date` 为 NULL → `THROW 51401`；`@start_date > @end_date` → `THROW 51402`；跨度超过 366 天 → `THROW 51403`（防误查全库） |
| 日期语义 | **闭区间**：`business_date >= @start_date AND business_date <= @end_date`（文档里写死这句，答辩会被问） |
| 结果集 1（汇总，恒 1 行） | 订单数、销售数量（杯）、销售金额、会员单数、客单价；**用 `ISNULL` 包住**，空区间时也返回一行 0 |
| 结果集 2（商品明细） | 商品编号、名称、杯数、金额、占比 |
| 金额口径 | 商品级用 `SUM(tbl_order_detail.subtotal)`；订单级用 `SUM(amount_paid)`（**D 口径**：`pay_status='SUCCESS' AND order_status<>'CANCELLED'`）——两个口径都要在结果里区分，不能混 |
| 空区间 | 汇总一行全 0，明细 0 行（不报错、不返回空结果集） |

### 1.2 `usp_stock_adjust`（库存调整存储过程）

```sql
CREATE PROCEDURE dbo.usp_stock_adjust
    @ingredient_id INT,
    @delta         DECIMAL(12,3),   -- 正数入库、负数出库
    @reason        NVARCHAR(200),
    @operator_id   INT,
    @ref_no        NVARCHAR(40) = NULL   -- 幂等键，重复调用会被拒
AS
```

| 项 | 设计 |
|---|---|
| 校验顺序 | ①原料存在（否则 `THROW 51411`）②`@delta <> 0`（51412）③`@reason` 去空后非空（51413）④操作员存在（51414）⑤`@delta < 0` 时 `qty_on_hand + @delta >= 0`（51415，报当前结存与调整量） |
| 写入 | 同一条事务里：`UPDATE tbl_ingredient SET qty_on_hand = qty_on_hand + @delta` + `INSERT tbl_stock_ledger(ledger_type='ADJUST', ref_type='MANUAL', qty=@delta, remark=@reason, operator_id=@operator_id)` |
| 复用现有类型（**已定：不新增**） | `@delta > 0` 写 `ledger_type='PURCHASE_IN'`、`< 0` 写 `'LOSS'`，两者都配 `ref_type='MANUAL'`（`ck_stock_ledger_ref_consistency` 要求 MANUAL 时 `order_id` 与 `purchase_order_id` 均为 NULL，两者都满足）。代价：报表里"报损"与"盘点盘亏"分不开 —— 已确认接受，用 `ref_type='MANUAL'` + `remark` 区分。**因此本阶段不需要 `migration-08`，零结构变更** |
| 幂等（**已定：先不做**） | 不引入 `@ref_no`、不加唯一索引。重复调用就是再执行一次、再留一条流水（"重复调用"用例的断言改为**结果可预期**：两次调用后结存再减一次、流水两条，且都不报错） |
| 返回 | 调整前结存、调整后结存、`ledger_id` |

### 1.3 `fn_replenish_qty`（补货量函数，标量）

```sql
CREATE FUNCTION dbo.fn_replenish_qty (@ingredient_id INT)
RETURNS DECIMAL(12,3)
```

| 项 | 设计 |
|---|---|
| 算法 | 目标水位取 `target_level`，为空则取 `reorder_point * 2`；缺口 = 目标 − 当前；**缺口 ≤ 0 返回 0** |
| 不存在 | 返回 **NULL**（并在文档与测试里明确写"NULL = 编号不存在"，与"0 = 不需要补"区分开）。不在函数里 `THROW`，否则一个坏编号会让整条 `SELECT` 挂掉 |
| 不为负 | 数学上已保证（`缺口>0` 才返回），测试里再断言一次 |

### 1.4 `fn_sales_summary`（销售汇总**内联表值函数**）

```sql
CREATE FUNCTION dbo.fn_sales_summary (@start_date DATE, @end_date DATE)
RETURNS TABLE
AS RETURN (SELECT ...)
```

| 项 | 设计 |
|---|---|
| 为什么是内联 TVF | 课程要求"能在 `SELECT` 语句中调用"；内联 TVF 能被优化器内联，`SELECT * FROM dbo.fn_sales_summary('2026-09-01','2026-09-30')` 直接可用 |
| 返回列 | 商品编号、商品名称、销售数量、销售金额、订单数量 |
| 非法参数 | 内联 TVF 里不能 `THROW`（会破坏内联）。约定：**参数为 NULL 或起止颠倒时返回空集**，校验交给外层（`usp_sales_report` 或调用方）；文档写明这条边界 |
| 口径 | 与 1.1 一致（D 口径），保证两处数字能对上 |

### 1.5 `fn_discount_amount`（折扣函数，标量）

```sql
CREATE FUNCTION dbo.fn_discount_amount
(
    @member_id INT = NULL,          -- NULL = 散客
    @amount    DECIMAL(10,2),
    @coupon_id INT = NULL
)
RETURNS DECIMAL(10,2)
```

| 项 | 设计 |
|---|---|
| 三条依据 | ①**券**：`coupon_template.discount_amount`（需满足 `min_order_amount` 且券未用、在有效期）②**订单金额满减**：满 30 减 3、满 50 减 8 ③**会员身份**：会员在 ①② 之外再减 1 元 |
| 组合规则 | ① 与 ② **取较优、不叠加**；会员的 1 元在此基础上叠加；**总折扣不超过订单金额** |
| 返回 | 折扣**金额**（不是率）。另外在文档里给出"折扣率 = 折扣 / 金额"的算法，课程要求"折扣率和折扣金额"两者 |
| 不落库 | 函数只算，不写。落库由调用方（下单时写 `discount_amount` 与 `amount_paid` 快照）负责 —— 这正是"历史订单保存实际折扣"的实现方式 |

---

## 2. 正反例矩阵（作业第三项，也是"结果记录"的骨架）

每个对象都要跑一遍左列，右列是断言。

| 用例类型 | `usp_sales_report` | `usp_stock_adjust` | `fn_replenish_qty` | `fn_sales_summary` | `fn_discount_amount` |
|---|---|---|---|---|---|
| 正常输入 | 9/18–9/23：1,926 单 / 23,762.00（D 口径） | +500 g 入库 | 布丁粉 → 3,740.000 | 返回 ≥1 行 | 8.00 元单 + 5 元券 → 5.00 |
| 空值 / NULL | 参数 NULL → 51401 | `@delta` NULL → 51412 | 参数 NULL → 返回 NULL | 返回空集 | `@amount` NULL → 返回 0 |
| 错误编号 | —（无编号参数） | 99999 → 51411 | 99999 → NULL | — | 99999 券 → 按无券处理 |
| 错误日期 | 结束早于开始 → 51402 | — | — | 返回空集 | — |
| 非法数量 | 跨度 >366 天 → 51403 | `@delta = 0` → 51412；−999999 → 51415 | — | — | 负金额 → 返回 0 |
| 非法折扣 | — | — | — | — | 券不满足门槛 → 只用满减 |
| 重复调用 | 连调两次，结果完全一致 | 同参数再调一次：再执行一次、多一条流水、不报错 | 连调两次一致 | 连调两次一致 | 连调两次一致 |
| 边界 | 空区间（无记录）→ 汇总一行 0 | 调整后结存正好 0（允许） | 库存正好 = 目标 → 0 | 单日区间 | 折扣正好 = 金额 |
| 未写脏数据 | — | 失败用例后 `qty_on_hand` 与流水**均无变化** | — | — | — |

---

## 3. 文件清单与落地顺序

| 顺序 | 文件 | 内容 |
|---|---|---|
| 1 | `project/sql/09-programmability/function.sql` | 3 个函数（1.3 / 1.4 / 1.5）—— 先写函数，因为过程要用它们 |
| 2 | `project/sql/09-programmability/procedure.sql` | 2 个过程（1.1 / 1.2） |
| 3 | `project/sql/09-programmability/test-function.sql` | 函数正反例，逐条打印"预期 / 实际 / PASS｜FAIL"，`sqlcmd -b` 下 FAIL 即非零退出 |
| 4 | `project/sql/09-programmability/test-procedure.sql` | 过程正反例，同上，含"失败后库未变"的复查 |
| 5 | `project/docs/programmability.md` | **存储过程 vs 函数**对照表 + 结果记录表 + 口径说明 |
| 6 | `project/sql/99-rebuild.sql` | 接入顺序：`08-security` → `09-programmability/{function,procedure}.sql`（**无 migration-08**） |

**编码约定**：`.sql` 一律 **UTF-8 BOM + CRLF**；每个对象自带 `SET ANSI_NULLS / QUOTED_IDENTIFIER ON`。

---

## 4. 验收（怎么证明它成立）

1. **对象存在且可调用**：`sys.objects` 查出 2 个 `P` + 3 个 `FN`（1 标量×2 + 内联 TVF×1）。
2. **`regression.sql` 加 TC-16**：断言上述对象存在、数量正确、且 `fn_replenish_qty` 对三个已知原料返回预期值（布丁粉 3740、椰浆 290.6、不存在 → NULL）。
3. **两份 test 脚本**跑完输出 `PASS / FAIL` 计数，全零失败。
4. **不动既有基线**：三份基线快照（`293` 行）重跑差异仍为 0；`pytest` 46 条仍全绿（本阶段不碰应用代码，理应零影响）。
5. **失败用例不留痕**：每个错误用例后立刻查 `qty_on_hand` 与 `sys.fn_dump_dblog`… 太重的不用，就查"流水行数 + 结存"两项前后一致。

---

## 5. 三点已拍板（2026-11-20）

| # | 问题 | 结论 |
|---|---|---|
| 1 | 新增 `ADJUST` 流水类型？ | **不新增**。正数→`PURCHASE_IN`、负数→`LOSS`，都配 `ref_type='MANUAL'`；代价是报表里"报损"与"盘点盘亏"混在一起，靠 `remark` 区分。**零结构变更，无 `migration-08`** |
| 2 | 满减规则硬编码还是建表？ | **硬编码在函数里**（满 30 减 3、满 50 减 8），建表留到第 12 周 |
| 3 | 重复调用报错还是静默？ | **先不报错**。不做幂等键，重复调用就是再执行一次；用例只断言"行为可预期"（再减一次、多一条流水、不抛异常） |

## 5.1 质量怎么控（每批交付的门禁）

每一批（函数 / 过程 / 测试脚本 / 文档）都按同一套跑完才交，任一红就停下来说明原因：

1. `sqlcmd -b` 执行 —— **`-b` 让任何错误变成非零退出**，不接受"看起来没错"。
2. 对象自检 `sys.objects`：5 个对象在、类型与参数个数对（2 `P` + 3 `FN`）。
3. 该批的 `test-*.sql` 全绿：PASS/FAIL 计数里 FAIL 必须为 0。
4. `99-rebuild.sql` 从零重建（exit=0）—— 证明脚本可重复部署，不是"手工贴进库"。
5. `regression.sql` **16/16**（含新增 TC-16）。
6. 基线三份快照 **293 行零差异**；`pytest` **46 passed**。
7. 交一张红绿表：**对象 / 正例 / 反例 / 门禁 / 结论**，你只看这张表就能判。

反过来，你随时可以自己复核（不用等我）：

```powershell
# 看对象在不在、正反例过不过
sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -b -i project\sql\09-programmability\test-function.sql
# 看整体回归
sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -b -i project\tests\regression.sql
```

---

## 6. 不做的事（第 10 周范围内）

- 不把 `place_order` 下沉成存储过程（任务 6 与 P-2，单独一轮）
- 不写触发器、窗口函数、递归 CTE（分别是第 11、12 周）
- 不碰应用代码（除任务 6 明确要求替换的两处，留到整合轮）
- 不重建全库后再改（先 `migration-08`，再重建验证）
