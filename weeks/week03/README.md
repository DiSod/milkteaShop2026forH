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
| 1 | **建库语句** | ✅ | [`project/sql/00-bootstrap/create-database.sql`](../../project/sql/00-bootstrap/create-database.sql) |
| 2 | **一键重建入口接线** | ✅ **已可跑** | [`project/sql/99-rebuild.sql`](../../project/sql/99-rebuild.sql) |
| 3 | 建表语句（DDL） | ⬜ **进行中** | `project/sql/01-schema/create-tables.sql` |
| 4 | 约束（主外键 / CHECK） | ⬜ | `project/sql/02-constraints/` |
| 5 | 种子数据装载 | 🟡 脚本已就绪，**待表结构** | [`project/sql/04-seed/seed_data.sql`](../../project/sql/04-seed/seed_data.sql) |
| 6 | 增删改查语句 | ⬜ | `project/sql/05-dml/` |

### 本周已完成的部分

| 项 | 成果 |
|---|---|
| **数据库环境** | **SQL Server 2022** Express · 实例 `.\SQLEXPRESS` · 排序规则 `Chinese_PRC_CI_AS` · 兼容级别 **160** |
| **建库脚本** | 幂等；库名 / 排序规则 / 兼容级别 / 恢复模式**四项全部锁定** |
| **一键重建** | `cd project\sql && sqlcmd -S .\SQLEXPRESS -E -i 99-rebuild.sql` —— **实测通过**，已接通 `00-bootstrap` |
| **设计输入** | 表结构定义已 100% 就绪（`project/docs/data-dictionary.md`，17 张表 / 132 字段），可直接翻译为 DDL |

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

1. **`create-tables.sql`**（17 张表 / 132 字段，由 `data-dictionary.md` 翻译）
2. `02-constraints/constraints.sql`（主外键 / CHECK）
3. `99-rebuild.sql` 接入 `01-schema` 与 `04-seed`
4. `05-dml/crud.sql`（现场演示用）
