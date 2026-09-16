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

- 每张表**必须有主键**
- 外键**必须显式命名**（便于后续排查与迁移）
- 数值型金额统一 `DECIMAL(10,2)`，**禁止用 `FLOAT`**
- 时间统一 `DATETIME2`，**禁止用字符串存时间**
- 可为空的列要问一句"业务上真的允许为空吗"；能 `NOT NULL` 就 `NOT NULL`

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
