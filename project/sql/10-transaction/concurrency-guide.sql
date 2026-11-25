/* ============================================================
 * 脚本：concurrency-guide.sql
 * 用途：第 13 周并发控制手工双窗口演示剧本（SSMS / 双 sqlcmd 交互用）
 * 说明：
 *   本文件用于课堂展示时在两个查询窗口（会话 A / 会话 B）分步执行，
 *   配合同目录下的自动化并发运行器 run-concurrency-experiments.py 使用。
 *   ⚠️ 本剧本包含会话级指令，请勿直接整本一次性执行！请按【会话 A】【会话 B】分段粘贴执行。
 * 阶段：第 13 周（并发控制与锁机制）
 * 作者：何争霖 (hezhlin5)
 * 日期：2026-11-25
 * ============================================================ */

/* ============================================================
 * 实验一：隔离级别对比（脏读 / 不可重复读 / 幻读）
 * ============================================================

-- 【1A 脏读：READ UNCOMMITTED vs READ COMMITTED】
-- 会话 A（写未提交并回滚）：
USE milktea_shop;
BEGIN TRANSACTION;
UPDATE dbo.tbl_ingredient SET qty_on_hand = qty_on_hand + 888.000 WHERE ingredient_id = 1;
-- 此时暂停，不要提交！去会话 B 读；观察完后再执行：
-- ROLLBACK TRANSACTION;

-- 会话 B（在 READ UNCOMMITTED 下读到脏数据）：
USE milktea_shop;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT ingredient_id, qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1; -- 立即返回 +888 的脏值

-- 会话 C（在 READ COMMITTED 下被阻塞直到会话 A 回滚，返回真实值）：
USE milktea_shop;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT ingredient_id, qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1;

---------------------------------------------------------------

-- 【1B 不可重复读：READ COMMITTED vs REPEATABLE READ】
-- 会话 A：
USE milktea_shop;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED; -- 改进时改为 REPEATABLE READ
BEGIN TRANSACTION;
SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1; -- 第 1 次读
-- 此时暂停，切去会话 B 执行更新并提交；再回来执行第 2 次读：
SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1; -- READ COMMITTED 两次不等；REPEATABLE READ 期间会话 B 被阻塞
COMMIT TRANSACTION;

-- 会话 B：
USE milktea_shop;
BEGIN TRANSACTION;
UPDATE dbo.tbl_ingredient SET qty_on_hand = qty_on_hand + 10.000 WHERE ingredient_id = 1;
COMMIT TRANSACTION; -- 演示后请 -10.000 恢复

---------------------------------------------------------------

-- 【1C 幻读：REPEATABLE READ vs SERIALIZABLE】
-- 会话 A：
USE milktea_shop;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ; -- 改进时改为 SERIALIZABLE
BEGIN TRANSACTION;
SELECT COUNT(*) FROM dbo.tbl_product_category WHERE category_code LIKE 'PHANTOM%'; -- 第 1 次读 = 0
-- 此时暂停，切去会话 B 插入 PHANTOM1 并提交；再回来执行第 2 次读：
SELECT COUNT(*) FROM dbo.tbl_product_category WHERE category_code LIKE 'PHANTOM%'; -- REPEATABLE READ 变成 1（幻读）；SERIALIZABLE 期间会话 B 范围锁阻塞
COMMIT TRANSACTION;

-- 会话 B：
USE milktea_shop;
INSERT INTO dbo.tbl_product_category (parent_category_id, category_code, category_name, sort_no, is_active)
VALUES (NULL, 'PHANTOM1', N'幻读演示品类', 99, 1); -- 演示后 DELETE 清理
*/

/* ============================================================
 * 实验二：锁等待观测（sys.dm_os_waiting_tasks）与 UPDLOCK 防超卖
 * ============================================================

-- 会话 A（持有 UPDLOCK 更新锁）：
USE milktea_shop;
BEGIN TRANSACTION;
SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = 1;
-- 此时暂停 5 秒，切去会话 B 执行同一条 SELECT ... WITH (UPDLOCK, ROWLOCK)，
-- 同时在第三个监视窗口执行下列 DMV 查询抓取 LCK_M_U 锁等待证据：
--
--   SELECT wt.session_id AS 等待会话, wt.blocking_session_id AS 阻塞会话,
--          wt.wait_type AS 等待类型, wt.wait_duration_ms AS 等待毫秒,
--          tl.resource_type, tl.request_mode
--   FROM sys.dm_os_waiting_tasks AS wt
--   JOIN sys.dm_tran_locks AS tl ON tl.lock_owner_address = wt.resource_address
--   WHERE wt.blocking_session_id IS NOT NULL;
--
-- 会话 A 扣除 100 并 COMMIT 后，会话 B 立即苏醒并读到扣减后的最新库存，从而避免 TOCTOU 超卖。
COMMIT TRANSACTION;
*/

/* ============================================================
 * 实验三：AB-BA 死锁（1205）复现与按主键升序加锁根治
 * ============================================================

-- 【改进前（反序加锁，稳定复现 1205 死锁）】：
-- 会话 A：
USE milktea_shop;
BEGIN TRANSACTION;
SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = 1;
-- 等会话 B 锁住 ingredient_id = 2 后，继续执行：
SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = 2;
COMMIT TRANSACTION;

-- 会话 B：
USE milktea_shop;
BEGIN TRANSACTION;
SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = 2;
-- 等会话 A 锁住 ingredient_id = 1 后，继续执行：
SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = 1;
COMMIT TRANSACTION;
-- 结果：SQL Server 死锁监视器检测闭环，选中一侧作为牺牲者抛 Msg 1205！

-- 【改进后（全库统一按 ingredient_id 升序加锁）】：
-- 会话 A 与会话 B 均先锁 ingredient_id = 1 再锁 ingredient_id = 2：
-- 有序等待、零闭环、零 1205 死锁！
*/
GO
