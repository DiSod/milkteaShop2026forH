# project · 成果域

最终可运行的项目。**本目录只放最终版，禁止放探索性草稿**（草稿在 `weeks/`）。

## 目录

| 目录 | 用途 | 当前状态 |
|---|---|---|
| `sql/` | SQL 脚本，按 `00-` → `99-` 顺序执行 | ✅ **全链路可跑**（00—04, 07, 08） |
| `data/` | 数据文件（原始 / 中间 / 生成） | ✅ 造数引擎 + 母本已登记 |
| `app/` | 应用界面（第 2 阶段起） | ⬜ 占位 |
| `docs/` | ER 图、数据字典、设计说明 | ✅ 数据字典已定稿 |
| `tests/` | 测试用例与运行记录 | ⬜ 占位（负例测试暂在 `sql/05-dml/crud.sql` 与 `08-security/role.sql` 内） |

## 一键重建

**唯一入口**：`sql/99-rebuild.sql`

```powershell
cd project\sql
sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 99-rebuild.sql
```

> ⚠️ **必须先 `cd project\sql`** —— `sqlcmd` 的 `:r` 相对**当前工作目录**解析。
>
> **当前接通**：`00-bootstrap` → `01-schema` → `02-constraints` → `03-indexes` → `04-seed` → `07-view` → `08-security`。
> **按需单独执行**：`05-dml/crud.sql`（CRUD 演示）· `06-query/query.sql`（多表查询）。
> **实测**：从空库重建出 17 张表 / 132 字段 / 20,979 行数据 / 5 视图 / 4 角色，耗时 15—17 秒。

> 本目录必须始终满足：**从空库一键重建出完整可用的数据库**。这是课程"可复现"要求的技术保障。

## 规矩

1. 所有脚本必须能被 `99-rebuild.sql` 按序调用
2. 新增脚本在 `sql/README.md` 的执行顺序表中登记
3. 数据文件不进 git，见 `data/README.md` 的下载说明
