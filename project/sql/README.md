# sql · SQL 脚本

按 **数字前缀顺序**执行。目录名即执行顺序，无需额外文档。

## 执行顺序

| 序号 | 目录 | 内容 | 阶段 | 状态 |
|---|---|---|---|---|
| 00 | `00-bootstrap/` | 建库（排序规则 / 兼容级别 / 恢复模式） | 第 3 周 | ✅ |
| 01 | `01-schema/` | DDL 建表（17 张表 / 132 字段） | 第 3 周 | ✅ |
| 02 | `02-constraints/` | 候选码 17 / CHECK 43 / 外键 30 | 第 4 周 | ✅ |
| 03 | `03-indexes/` | 索引（21 个） | 第 4 周 | ✅ |
| 04 | `04-seed/` | 种子数据装载 | 第 3 周 | ✅ |
| 05 | `05-dml/` | CRUD 示例（含 5 个负例） | 第 3 周 | ✅ |
| 06 | `06-query/` | 多表连接查询 | 第 4 周 | ⬜ |
| 07 | `07-view/` | 统计视图 | 第 4 周 | ⬜ |
| 08 | `08-security/` | 角色与权限 | 第 4 周 | ⬜ |
| 09 | `09-programmability/` | 存储过程 / 函数 / 触发器 | 第 11—12 周 | ⬜ |
| 10 | `10-transaction/` | 事务与并发控制 | 第 13 周 | ⬜ |
| 99 | `99-rebuild.sql` | **一键重建入口** | — | ✅ **全链路可跑**（00—04） |

## 怎么跑

```powershell
# 全库重建（唯一入口）—— ⚠️ 必须先 cd 到 project\sql
cd project\sql
sqlcmd -S .\SQLEXPRESS -E -i 99-rebuild.sql
```

> ⚠️ **`99-rebuild.sql` 里用的是 sqlcmd 的 `:r` 指令，它相对【当前工作目录】解析，不是相对脚本目录。**
> 从仓库根直接跑会报"找不到 `.\00-bootstrap\...`"。

| 项 | 值 |
|---|---|
| 实例 | `.\SQLEXPRESS`（本机 Express 默认实例） |
| 认证 | `-E`（Windows 集成认证） |
| 库名 | `milktea_shop` |
| 排序规则 / 兼容级别 | `Chinese_PRC_CI_AS` / **160**（SQL Server 2022） |

## 规矩

1. 脚本命名：全小写，`-` 连接，如 `create-tables.sql`
2. 每个脚本头部写明：用途、依赖的前置脚本、作者、日期
3. 脚本必须**可重复执行**（幂等），或显式声明不可重跑
4. 新增脚本后，在上表登记
5. ⚠️ **含中文的 `.sql` 必须存为「UTF-8 带 BOM」** —— 否则 `sqlcmd` 会**静默失效**
   （无报错，但一行都不生效）。详见 [`02-sql-style.md`](../../harness/conventions/02-sql-style.md) §9
   · **备选（不改文件）**：运行时加 `-f 65001` 显式指定输入编码
     `sqlcmd -S .\SQLEXPRESS -E -f 65001 -i 99-rebuild.sql`
6. ⚠️ **日志前缀用 `【建库】` 而不是 `[建库]`** —— `sqlcmd` 会吃掉半角方括号

编写风格见 `harness/conventions/02-sql-style.md`。
