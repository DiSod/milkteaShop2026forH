/* ============================================================
 * 脚本：99-rebuild.sql
 * 用途：一键重建入口 —— 从空库重建出完整可用的数据库
 * 依赖：无（这是唯一入口）
 * 阶段：第 3—4 周逐步补全
 * 作者：DiSod / 协同：何争霖 (hezhlin5)
 * 日期：2026-10-05
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
 *   sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 99-rebuild.sql
 *
 *   ⚠️ 必须先 cd 到 project/sql/ —— sqlcmd 的 :r 是相对【当前工作目录】解析的，
 *      不是相对脚本所在目录。
 *
 * 【执行顺序 = 目录名的数字前缀顺序】
 *   00-bootstrap       建库（排序规则 / 兼容级别 / 恢复模式）
 *   01-schema          DDL 建表（17 张业务表）
 *   02-constraints     候选码 / 外键 / CHECK
 *   03-indexes         索引（21 个业务索引）
 *   04-seed            种子数据装载（20,979 行纯净基准数据）
 *   05-dml             CRUD 示例（演示脚本，单独按需执行）
 *   06-query           多表连接查询（查询脚本，单独按需执行）
 *   07-view            统计与全景视图（5 个核心视图）
 *   08-security        角色与权限（4 岗位 RBAC 与负例测试）
 *   09-programmability 存储过程 / 函数 / 触发器（待第 11—12 周）
 *   10-transaction     事务与并发控制（待第 13 周）
 *
 * 【⚠️ 两条 sqlcmd 坑（见 harness/conventions/02-sql-style.md §9）】
 *   1. 本文件必须存为「UTF-8 带 BOM」，否则中文会被按 GBK 解码 → **静默失效**
 *   2. 日志前缀用【】而不是 []，因为 sqlcmd 会吃掉半角方括号
 *   3. 建议参数：sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 99-rebuild.sql
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

PRINT N'【重建】=== 01-schema ===';
:r .\01-schema\create-tables.sql

PRINT N'【重建】=== 02-constraints ===';
:r .\02-constraints\constraints.sql

PRINT N'【重建】=== 03-indexes ===';
:r .\03-indexes\indexes.sql

PRINT N'【重建】=== 04-seed ===';
:r .\04-seed\seed_data.sql

-- ✅ 05-dml/crud.sql 已完成，但故意不接入本文件 ——
--    它是【演示脚本】（CRUD + 负例），会写入 DEMO- 前缀的数据，
--    不属于"从空库重建出干净数据库"的范畴。需要时单独执行：
--      sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -i 05-dml\crud.sql
--
-- ✅ 06-query/query.sql 已完成，作为【查询与审计演示脚本】，单独执行：
--      sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -i 06-query\query.sql

PRINT N'【重建】=== 07-view ===';
:r .\07-view\view.sql

PRINT N'【重建】=== 08-security ===';
:r .\08-security\role.sql

PRINT N'【重建】完成 —— 数据库已从空库重建完毕（含 17 表、约束、索引、种子数据、5 视图、4 安全角色）。';
GO

/* ---------- 重建结果总览 ---------- */
SELECT
    (SELECT COUNT(*) FROM sys.tables)              AS [表],
    (SELECT COUNT(*) FROM sys.columns
      WHERE object_id IN (SELECT object_id FROM sys.tables)) AS [字段],
    (SELECT COUNT(*) FROM sys.foreign_keys)        AS [外键],
    (SELECT COUNT(*) FROM sys.check_constraints)   AS [CHECK],
    (SELECT COUNT(*) FROM sys.indexes
      WHERE name LIKE N'ix[_]%'
        AND object_id IN (SELECT object_id FROM sys.tables
                          WHERE name LIKE N'tbl[_]%'))         AS [业务索引],
    (SELECT COUNT(*) FROM sys.views
      WHERE name LIKE N'vw[_]%')                               AS [业务视图],
    (SELECT COUNT(*) FROM sys.database_principals
      WHERE type = 'R' AND name LIKE N'role[_]%')              AS [安全角色];
GO
