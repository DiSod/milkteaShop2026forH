# 11-migration · 模式演进与规范化重构迁移

> **所属周次**：第 6 周（ch7 函数依赖与规范化）  
> **核心产出**：`migration.sql`（可执行模式迁移与数据演进脚本）  
> **理论依据**：[`project/docs/normalization.md`](../../docs/normalization.md) · [`project/docs/v0.1-issues.md`](../../docs/v0.1-issues.md)  
> **协作定案**：[`harness/issues/011-week06-migration-and-subtotal-alignment.md`](../../../harness/issues/011-week06-migration-and-subtotal-alignment.md)

---

## 1. 模块定位与职责

本目录承载阶段二（第 6 周）的模式演化与规范化重构脚本，负责将第 5 周识别的完整性缺口下沉至数据库层，并在必要时完成表的规范化分解与数据平滑迁移。

### 双重验证运行机制

1. **全新重建流水线（Single Source of Truth）**：
   - 接入 `project/sql/99-rebuild.sql`；
   - 保证全新拉起的 `milktea_shop` 数据库始终处于最新、完整的阶段二重构形态，杜绝后续第 7—9 周 App 开发时的环境与模式漂移。
2. **历史库独立重放演练（语义保持与数据无损验证）**：
   - 支持在已存在数据的 v0.1 数据库副本上独立执行：
     ```powershell
     cd project\sql
     sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 11-migration\migration.sql
     ```
   - 配合 `project/tests/` 中的回归断言，检验模式变更前后数据 100% 保持、业务语义不受破坏。

---

## 2. 脚本清单与计划

| 脚本 | 用途 | 状态 |
|---|---|---|
| `migration.sql` | 包含 DDL 结构调整、完整性约束补强、必要数据迁移与历史兼容映射 | ✅ 已接入 `99-rebuild.sql` |

---

## 3. 开发规范守则

1. ⚠️ **文件编码**：含中文字符必须使用 **UTF-8 with BOM** 保存，防止 `sqlcmd` 静默丢行；
2. ⚠️ **幂等执行**：脚本必须支持重复执行（基于 `IF NOT EXISTS` / `IF EXISTS` 做对象探测）；
3. ⚠️ **事务安全**：DDL 与数据迁移必须包裹于显式事务 `BEGIN TRANSACTION ... COMMIT` 中，出现错误时整块回滚，不破坏源库。

