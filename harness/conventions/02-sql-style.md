# 02 · SQL 编写风格规范

适用：SQL Server。所有 `project/sql/` 下的脚本。

## 1. 大小写

| 对象 | 规则 | 示例 |
|---|---|---|
| 关键字 | **大写** | `SELECT`、`CREATE TABLE`、`NOT NULL` |
| 数据类型 | **大写** | `INT`、`VARCHAR(50)`、`DECIMAL(10,2)`、`DATETIME2` |
| 内置函数 | **大写** | `COUNT()`、`ISNULL()`、`GETDATE()` |
| 标识符（表名/列名） | **小写 + 下划线** | `order_detail`、`member_id` |
| 别名 | **小写**，有意义 | `od`、`m`（避免 `a`、`b`、`x`） |

## 2. 缩进与换行

- 缩进 **4 个空格**（不用 Tab）
- 每个**主要子句**（`SELECT` / `FROM` / `WHERE` / `GROUP BY` / `ORDER BY`）**独占一行**
- `JOIN` 的 `ON` 条件单独换行

```sql
SELECT
    o.order_id,
    o.order_time,
    m.member_name,
    SUM(od.subtotal) AS order_amount
FROM order_header AS o
INNER JOIN order_detail AS od
    ON o.order_id = od.order_id
LEFT JOIN member AS m
    ON o.member_id = m.member_id
WHERE o.status = 'COMPLETED'
    AND o.order_time >= '2026-01-01'
GROUP BY
    o.order_id,
    o.order_time,
    m.member_name
ORDER BY o.order_time DESC;
```

## 3. 命名规范

### 3.1 对象前缀

| 对象 | 前缀 | 示例 |
|---|---|---|
| 表 | `tbl_` | `tbl_order_header` |
| 视图 | `vw_` | `vw_daily_sales` |
| 存储过程 | `sp_` | `sp_create_order` |
| 函数 | `fn_` | `fn_makeable_cups` |
| 触发器 | `trg_` | `trg_order_after_insert` |
| 索引 | `ix_` | `ix_order_header_time` |
| 主键约束 | `pk_` | `pk_order_header` |
| 外键约束 | `fk_` | `fk_order_detail_order` |
| 检查约束 | `ck_` | `ck_order_qty_positive` |
| 默认约束 | `df_` | `df_order_status` |
| 唯一约束 | `uq_` | `uq_member_phone` |

> 不使用 `sp_` 之外的系统保留前缀（`sp_` 在 SQL Server 中有特殊查找语义，若需避免可用 `usp_`，本项目统一用 `sp_` 并知悉该语义）。

### 3.2 列名

- 全小写 + 下划线：`order_time`、`unit_price`
- **主键统一叫 `<表名单数>_id`**：`order_id`、`member_id`
- **外键与所引用主键同名**：`order_detail.member_id` 引用 `member.member_id`
- **布尔语义用 `is_` 前缀**：`is_active`
- **禁用保留字**作列名：`order`、`desc`、`key`、`user` → 用 `order_header`、`description`

## 4. 脚本头注释模板

每个脚本**必须**以此开头：

```sql
/* ============================================================
 * 脚本：create-tables.sql
 * 用途：建立奶茶店数据库全部业务表（DDL）
 * 依赖：00-bootstrap/create-database.sql
 * 阶段：第 3 周
 * 作者：<姓名>
 * 日期：2026-XX-XX
 * 说明：可重复执行（含 IF OBJECT_ID 判断）
 * ============================================================ */
```

## 5. 幂等性

脚本应尽量**可重复执行**：

```sql
IF OBJECT_ID('tbl_member', 'U') IS NOT NULL
    DROP TABLE tbl_member;
GO
```

若脚本**不可**重跑（如纯 `INSERT` 种子数据），必须在头注释中显式声明：

```sql
 * 幂等：否 —— 重复执行会产生重复数据，重跑前请先清空该表
```

## 6. 约束与完整性

### 6.1 通用底线

- 每张表**必须有主键**
- 外键**必须显式命名**（便于后续排查与迁移）
- 可为空的列要问一句"业务上真的允许为空吗"；能 `NOT NULL` 就 `NOT NULL`

### 6.2 码的约定（代理键策略）

> 定于 2026-09-23（第 2 周设计决策 **D-04**），全库 17 张表统一执行。

| 角色 | 约定 | 例子 |
|---|---|---|
| **主码 PK** | **一律代理键** `INT IDENTITY` | `product_id` |
| **候选码 UNIQUE** | **业务码**建 `UNIQUE` 约束 | `product_code`（形如 `P001`） |
| **复合候选码** | 用括号括起，**列序固定** | `(order_id, line_no)` |
| **外码 FK** | **一律引用代理键** | `product_id` → `tbl_product.product_id` |

> **为什么主码用代理键**：外键短、稳定；业务码调整时不破坏引用完整性。
> 这也正好演示课程那句"**主码是选出来做标识的，候选码是其他也能唯一标识的**"。

### 6.3 数据类型与精度（强制）

| 用途 | 类型 | 说明 |
|---|---|---|
| **金额** | `DECIMAL(10,2)` | **禁止 `FLOAT`** —— 浮点有精度误差，钱不能算错 |
| **物料数量** | `DECIMAL(12,3)` | 支持 0.001 精度，兼容 `g` / `ml` |
| **单价 / 成本** | `DECIMAL(12,4)` | 按基本单位计价时数值很小（如 `0.0110` 元/g），需 4 位小数 |
| **时间** | `DATETIME2` | **禁止用字符串存时间** |
| **日期** | `DATE` | 只有日期无时间的场景（`hire_date`、`business_date`） |
| **中文文本** | `NVARCHAR` | 纯代码 / 英文用 `VARCHAR` |
| **布尔** | `BIT` | 列名用 `is_` 前缀 |
| **时间默认值** | `DEFAULT SYSDATETIME()` | 记录类字段（如 `order_time`） |

### 6.4 `CHECK` 约束的两类用法

| 用途 | 写法 | 例子 |
|---|---|---|
| **非负** | `CHECK (列 >= 0)` | `ck_ingredient_qty`：`qty_on_hand >= 0` |
| **枚举** | `CHECK (列 IN (...))` | `ck_employee_position`：`position IN ('MANAGER','CASHIER','MAKER','STOCKER')` |

> ⚠️ **枚举值不在数据库里，只活在 `CHECK` 约束中** —— 所以**必须同步登记到域字典**
> （[`project/docs/data-dictionary.md`](../../project/docs/data-dictionary.md) 第一节）。
> 否则组员看到 `position = 'MAKER'` 根本不知道它是什么意思。

**非负约束是本库最硬的一条**：`CHECK (qty_on_hand >= 0)` 把"**库存必须真实**"变成
**结构上不允许为负**，而不是靠应用层自觉（第 2 周设计决策 **D-03 / D-12**）。

### 6.5 ⭐ SQL Server 特性：`UNIQUE` 把 `NULL` 视为相等

**这一条我们专门用来表达"与某个维度无关"，替代哨兵值。**

```sql
-- 配方表：某原料的用量"与糖度无关"时，sugar_spec_id 为 NULL
CONSTRAINT uq_recipe UNIQUE (product_id, cup_spec_id, sugar_spec_id, ingredient_id)
```

在 SQL Server 中，`UNIQUE` 约束**认为两个 `NULL` 是相等的**（这与 SQL 标准的默认行为**不同**），
所以上面这个复合唯一约束在 `sugar_spec_id` 为 `NULL` 时**只允许存一行** ——
**"与糖度无关"这件事仍然被唯一性约束保证住**。

> 我们因此**放弃了原来的 `'ANY'` 哨兵值方案**（设计决策 **D-05a** 的补丁）：
> `NULL` 比 `'ANY'` 更诚实 —— `'ANY'` 是一个**虚构的糖度档**，而 `NULL` 表达的是"**该维度不适用**"。

## 7. 事务

```sql
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
        -- 业务操作
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
```

## 8. 禁止事项

| 禁止 | 原因 |
|---|---|
| `SELECT *` 出现在交付脚本中 | 表结构变更即静默出错 |
| 字符串拼接 SQL | 注入风险；课程要求**参数化查询** |
| 在 `WHERE` 中对列使用函数（如 `WHERE YEAR(order_time)=2026`） | 索引失效 |
| 未命名约束 | 后续无法定位与迁移 |
| 用 `FLOAT` 存金额 | 精度丢失 |
