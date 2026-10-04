# week03 · 第 3 周

**理论内容**：ch3 DDL 与数据修改
**项目任务**：用脚本建库，并完成商品、库存、订单等对象的增删改查
**当周产出**：建库语句、增删改查语句
**硬指标**：⚠️ **要求能够复现** —— 从空库开始构建
**展示重点**：演示从空库开始构建；现场执行一组 CRUD

## 文件对照

| 文件 | 说明 |
|---|---|
| `README.md` | 本文件 —— 周报 |
| （SQL 全部在 `project/sql/`，本周起不再有草稿阶段） | 见 `../../project/sql/README.md` |

> **本周与第 1—2 周不同**：产出直接就是可运行的 SQL，按 `weeks/README.md` 的「草稿 → 正式」升级路径，
> 一律**直接写进 `project/sql/`**，不在 `weeks/` 下留副本（避免两份各自演化）。

## 本周产出摘要

| # | 交付物 | 状态 | 落点 |
|---|---|---|---|
| 1 | **建库语句** | ✅ | [`00-bootstrap/create-database.sql`](../../project/sql/00-bootstrap/create-database.sql) |
| 2 | **建表语句（DDL）** | ✅ **17 张表 / 132 字段** | [`01-schema/create-tables.sql`](../../project/sql/01-schema/create-tables.sql) |
| 3 | **约束（主外键 / CHECK）** | ✅ **候选码 17 / CHECK 43 / 外键 30** | [`02-constraints/constraints.sql`](../../project/sql/02-constraints/constraints.sql) |
| 4 | **索引** | ✅ **21 个** | [`03-indexes/indexes.sql`](../../project/sql/03-indexes/indexes.sql) |
| 5 | **种子数据装载** | ✅ **20,979 行** | [`04-seed/seed_data.sql`](../../project/sql/04-seed/seed_data.sql) |
| 6 | **一键重建全链路** | ✅ **实测 17 秒从空库跑通** | [`99-rebuild.sql`](../../project/sql/99-rebuild.sql) |
| 7 | **增删改查语句** | ✅ **含 5 个负例** | [`05-dml/crud.sql`](../../project/sql/05-dml/crud.sql) |

### ✅ 一键重建实测结果（硬指标：要求能够复现）

```powershell
cd project\sql
sqlcmd -S .\SQLEXPRESS -E -i 99-rebuild.sql
```

```
【重建】DROP 已存在的 milktea_shop（含全部数据）...
【重建】=== 00-bootstrap ===   建库
【重建】=== 01-schema ===      17 张表
【重建】=== 02-constraints === 候选码 17 + 域 15 + 值域 + 跨列 + 外键 30
【重建】=== 03-indexes ===     21 个索引
【重建】=== 04-seed ===        20,979 行种子数据
【重建】完成 —— 数据库已从空库重建完毕。

业务表 17 | 字段 132 | 外键 30 | 候选码 17 | CHECK 43 | 索引 21 | 总行数 20,979
耗时 17.1 秒
```

### 本周已完成的部分

| 项 | 成果 |
|---|---|
| **数据库环境** | **SQL Server 2022** Express · 实例 `.\SQLEXPRESS` · 排序规则 `Chinese_PRC_CI_AS` · 兼容级别 **160** |
| **建库脚本** | 幂等；库名 / 排序规则 / 兼容级别 / 恢复模式**四项全部锁定** |
| **建表脚本** | 从 `data-dictionary.md` **逐字翻译**，17 张表 / 132 字段，与字典完全对得上 |
| **约束脚本** | 17 候选码（6 复合）+ 15 条域 CHECK + 值域/跨列 CHECK + **30 个外键** |
| **索引脚本** | 21 个 —— 19 个建在外键连接路径，2 个建在日期/时间列 |
| **一键重建** | **从空库一键跑通**，含 2 万行种子数据，17 秒 |

> **课程第 3 周的三项要求全部达成**：① 建库语句 ✅ ② 增删改查语句 ✅ ③ **要求能够复现 ✅**

## 已并入 project 的产出

| 产出 | 位置 | 说明 |
|---|---|---|
| `create-database.sql` | `project/sql/00-bootstrap/` | 第 3 周首个正式脚本 |
| `99-rebuild.sql` | `project/sql/` | 已从桩文件变为**可执行** |
| `seed_data.sql` | `project/sql/04-seed/` | 第 2 周超前产出，本周补 BOM 修复 |

## 本周遇到的问题与处理

> ⚠️ 本节的 4 个坑**都已修好并写进规范**（[`02-sql-style.md`](../../harness/conventions/02-sql-style.md) §9 / §10）。

| # | 问题 | 发现方式 | 处理 |
|---|---|---|---|
| 1 | ⭐ **SQL 文件无 BOM → `sqlcmd` 静默失效** | 实测：同一条 INSERT，无 BOM 时 **0 行受影响且不报错** | 三个 SQL 文件补 BOM；写进规范 §9；**工程侧生成脚本需改用 `utf-8-sig`**（见 [ISSUE-007](../../harness/issues/007-seed-generator-encoding-and-datasource.md)） |
| 2 | **`sqlcmd` 会吃掉半角方括号** | 日志前缀 `[建库]` 不显示 | 改用 `【建库】`，写进规范 §9 |
| 3 | **`sys.databases.collation_name` 是惰性填充的** | 库刚建好时该列返回 `NULL`，**看起来像排序规则没设上** | 对照实验确认非 bug；脚本里加 `USE milktea_shop` 触发元数据 |
| 4 | **`:r` 相对当前工作目录**，不是脚本目录 | 从仓库根执行 `99-rebuild.sql` 报"找不到文件" | 文档明确要求 `cd project\sql` 再执行 |
| 7 | **CRUD 脚本的清理段不完整 + `XACT_ABORT ON` 放大后果** | 第二次执行报"重复键"错误 | `tbl_purchase_order_detail` 还引用着演示原料，导致 DELETE 失败；而 `XACT_ABORT ON` 使**整批后续清理全部跳过** → 重写清理段为**严格的 13 步依赖逆序**，并连测 3 次全绿 |
| 5 | **`ix[_]%` 匹配到了系统表的索引** | 重建总览显示"业务索引 23"而非 21 | `backup_metadata_store` 的 `IX_backup_*` 被不区分大小写的匹配捞进来了 → 三处清理逻辑全部**限定到 `tbl_%` 表** |
| 6 | **域字典里的 `ANY` 糖度档是废弃残留** | 写约束时发现 `DOM-12` 含 `ANY`，但它**从未被任何订单或配方引用**（1963 单 / 492 条配方里都没有） | 它是被 **D-05a 废弃的哨兵**（"与糖度无关"改由 `sugar_spec_id IS NULL` 表达）→ 已从**域字典**与**种子数据**中删除，并要求生成脚本同步（并入 ISSUE-007） |

## 本周关键决策

| 决策 | 结论 | 依据 |
|---|---|---|
| SQL Server 版本 | **2022**（Express Edition） | **实验室推荐**；本机已装并在运行，零安装成本 |
| 兼容级别 | **160** | 与版本一致；显式锁定避免行为漂移 |
| 排序规则 | `Chinese_PRC_CI_AS` | 中文项目显式指定，不依赖服务器默认 |
| 库名 | `milktea_shop` | 与 `seed_data.sql` 的 `USE milktea_shop;` 一致，**不可改** |
| 架构 | 默认 `dbo`，**不建自定义 schema** | 表名一律带 `tbl_` 前缀 |

## AI 使用记录

| 项 | 内容 |
|---|---|
| 使用目的 | ① 确定数据库版本与建库参数；② 编写 `create-database.sql`；③ 接线 `99-rebuild.sql`；④ 实测复现链路 |
| 人工决策 | **SQL Server 2022** 由实验室环境确定；兼容级别、排序规则、库名三项由小组确认 |
| **AI 输出被验证/纠正** | ① AI 起草的建库脚本**首次执行静默失败** → 实测定位到 BOM 问题（非脚本逻辑错）；② AI 一度把 `collation_name = NULL` 误判为缺陷 → 对照实验证实是惰性填充；③ 编辑工具会剥掉 BOM，**每次改完 SQL 必须回补** |
| 存疑 / 未验证 | 尚未在**第二台机器**上验证过一键重建（换机可移植性待测） |

## 下一步

1. ✅ **第 3 周三项要求已全部达成**（建库 / CRUD / 可复现）
2. 补充本周的 **2.4 验证与测试记录**（把一键重建 + CRUD 的实测输出正式记进阶段报告）
3. 第 4 周：`06-query`（多表连接）· `07-view`（统计视图）· `08-security`（角色权限）
4. 顺带：把 `03-indexes` 与 `02-constraints` 的说明补进答辩提纲
