/* ============================================================
 * 脚本：99-rebuild.sql
 * 用途：一键重建入口 —— 从空库重建出完整可用的数据库
 * 依赖：无（这是唯一入口）
 * 阶段：第 3 周起逐步补全
 * 作者：<待填>
 * 日期：<待填>
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
 *   sqlcmd -S <server> -i project/sql/99-rebuild.sql
 *
 * 【执行顺序 = 目录名的数字前缀顺序】
 *   00-bootstrap       建库、建 schema
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
 * ============================================================ */

-- ⬜ 待第 3 周补全：按上述顺序 :r 各脚本

/*
PRINT '=== 00-bootstrap ===';
:r .\00-bootstrap\create-database.sql

PRINT '=== 01-schema ===';
:r .\01-schema\create-tables.sql

-- ... 依此类推

PRINT '=== 重建完成 ===';
*/
