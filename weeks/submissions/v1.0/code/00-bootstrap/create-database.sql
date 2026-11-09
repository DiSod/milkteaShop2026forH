/* ============================================================
 * 脚本：create-database.sql
 * 用途：建立 milktea_shop 数据库，并锁定排序规则 / 兼容级别 / 恢复模式
 * 依赖：无（这是全库第一个脚本）
 * 阶段：第 3 周
 * 作者：DiSod
 * 日期：2026-10-04
 * 幂等：是 —— 库不存在则创建；已存在则只校正设置，**不删除数据**
 * ============================================================
 *
 * 【本脚本锁定的四项设置】
 *
 *   1. 库名       milktea_shop
 *                 —— 与 project/sql/04-seed/seed_data.sql 的 `USE milktea_shop;` 一致，
 *                    改名会导致种子数据装载失败。
 *
 *   2. 排序规则   Chinese_PRC_CI_AS
 *                 —— 中文项目应显式指定，而不是依赖服务器默认值。
 *                    CI = 大小写不敏感，AS = 重音敏感。
 *
 *   3. 兼容级别   160  （= SQL Server 2022）
 *                 —— 显式声明，让脚本行为不随服务器版本漂移。
 *                    实验室推荐 SQL Server 2022。
 *
 *   4. 恢复模式   SIMPLE
 *                 —— 课程项目不做日志备份。
 *
 * 【架构说明】
 *   本库统一使用默认架构 dbo，**不另建自定义 schema** ——
 *   表名一律带 `tbl_` 前缀（见 01-layout-and-naming.md），
 *   裸写 `tbl_product` 与 `dbo.tbl_product` 等价。
 *
 * 【执行方式】
 *   sqlcmd -S .\SQLEXPRESS -E -i project/sql/00-bootstrap/create-database.sql
 *   或在 SSMS 中打开执行。
 * ============================================================ */

USE master;
GO

/* ---------- 建库 ---------- */
IF DB_ID(N'milktea_shop') IS NULL
BEGIN
    PRINT N'【建库】 创建数据库 milktea_shop ...';

    CREATE DATABASE milktea_shop
        COLLATE Chinese_PRC_CI_AS;
END
ELSE
BEGIN
    PRINT N'【建库】 数据库 milktea_shop 已存在，跳过创建。';
    PRINT N'       （如需从零重建，请执行 99-rebuild.sql，它会先 DROP）';
END
GO

/* ---------- 校正设置（可重复执行） ---------- */
PRINT N'【建库】 校正排序规则一致性检查 ...';

IF EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE name = N'milktea_shop'
      AND collation_name <> N'Chinese_PRC_CI_AS'
)
BEGIN
    PRINT N'【建库】 ⚠️ 警告：现有库的排序规则不是 Chinese_PRC_CI_AS。';
    PRINT N'       排序规则无法就地修改，需 DROP 后重建（见 99-rebuild.sql）。';
END
GO

ALTER DATABASE milktea_shop SET COMPATIBILITY_LEVEL = 160;   -- SQL Server 2022
GO

ALTER DATABASE milktea_shop SET RECOVERY SIMPLE;
GO

-- 本项目数据量极小（种子数据约 2 MB），无需自动收缩；
-- 且自动收缩会造成索引碎片化。
ALTER DATABASE milktea_shop SET AUTO_SHRINK OFF;
GO

/* ---------- 回显最终设置 ---------- */
-- ⚠️ 先打开一次数据库再回显。
--    SQL Server 的 sys.databases.collation_name 是【惰性填充】的：
--    库刚建好、从未被连接过时，该列（及 DATABASEPROPERTYEX 的 Collation）会显示 NULL，
--    看起来像排序规则没设上，其实已经设好了。USE 一次之后即正常。
USE milktea_shop;
GO

PRINT N'【建库】 完成。当前设置：';
GO

SELECT
    name                AS [数据库],
    collation_name      AS [排序规则],
    compatibility_level AS [兼容级别],
    recovery_model_desc AS [恢复模式],
    is_auto_shrink_on   AS [自动收缩]
FROM sys.databases
WHERE name = N'milktea_shop';
GO
