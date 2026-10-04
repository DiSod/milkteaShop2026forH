/* ============================================================
 * 脚本：99-rebuild.sql
 * 用途：一键重建入口 —— 从空库重建出完整可用的数据库
 * 依赖：无（这是唯一入口）
 * 阶段：第 3 周起逐步补全
 * 作者：DiSod
 * 日期：2026-10-04
 * 幂等：是（会先 DROP 再重建）
 * ============================================================
 *
 * 【本文件的作用】
 * 它是整个 project/sql/ 的唯一入口。任何人 clone 仓库后，
 * 只需要按 project/data/README.md 下载好数据，然后执行本脚本，
 * 就能得到与提交版本一致的数据库。
 *
 * 这是课程"可复现"要求的技术保障。
 *
 * 【执行方式】
 *   cd project\sql
 *   sqlcmd -S .\SQLEXPRESS -E -i 99-rebuild.sql
 *
 *   ⚠️ 必须先 cd 到 project/sql/ —— sqlcmd 的 :r 是相对【当前工作目录】解析的，
 *      不是相对脚本所在目录。
 *
 * 【执行顺序 = 目录名的数字前缀顺序】
 *   00-bootstrap       建库（排序规则 / 兼容级别 / 恢复模式）
 *   01-schema          DDL 建表
 *   02-constraints     主外键 / CHECK
 *   03-indexes         索引
 *   04-seed            种子数据装载
 *   05-dml             CRUD 示例
 *   06-query           多表连接查询
 *   07-view            统计视图
 *   08-security        角色与权限
 *   09-programmability 存储过程 / 函数 / 触发器
 *   10-transaction     事务与并发控制
 *
 * 【⚠️ 两条 sqlcmd 坑（见 harness/conventions/02-sql-style.md §9）】
 *   1. 本文件必须存为「UTF-8 带 BOM」，否则中文会被按 GBK 解码 → **静默失效**
 *   2. 日志前缀用【】而不是 []，因为 sqlcmd 会吃掉半角方括号
 *   3. 救急：若无 BOM，用 `sqlcmd -f 65001 -i 99-rebuild.sql`
 * ============================================================ */

/* ---------- 步骤 0：自清理 ---------- */
USE master;
GO

IF DB_ID(N'milktea_shop') IS NOT NULL
BEGIN
    PRINT N'【重建】DROP 已存在的 milktea_shop（含全部数据）...';

    -- 踢掉其他连接，否则 DROP 会被阻塞
    ALTER DATABASE milktea_shop SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE milktea_shop;
END
ELSE
    PRINT N'【重建】milktea_shop 不存在，直接新建。';
GO

/* ---------- 按目录数字前缀顺序装载 ---------- */

PRINT N'【重建】=== 00-bootstrap ===';
:r .\00-bootstrap\create-database.sql

-- ⬜ 01-schema：create-tables.sql 待编写
-- PRINT N'【重建】=== 01-schema ===';
-- :r .\01-schema\create-tables.sql

-- ⬜ 02-constraints：待编写
-- PRINT N'【重建】=== 02-constraints ===';
-- :r .\02-constraints\constraints.sql

-- ⬜ 04-seed：种子数据依赖表结构，待 01-schema 就绪后接入
-- PRINT N'【重建】=== 04-seed ===';
-- :r .\04-seed\seed_data.sql

PRINT N'【重建】完成（当前仅覆盖 00-bootstrap，其余脚本待补）。';
GO
