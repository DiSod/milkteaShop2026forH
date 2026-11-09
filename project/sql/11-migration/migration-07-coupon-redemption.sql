/* ============================================================
 * migration-07-coupon-redemption.sql
 * ------------------------------------------------------------
 * 用途：为 v1.0「券核销闭环」补齐两道库层强制，并默认发放一批可用券。
 *
 *   ① ck_coupon_used_time_consistent
 *      status 与 used_time 必须同进同出：
 *        USED  => used_time IS NOT NULL
 *        非 USED => used_time IS NULL
 *      补第 7 周审计发现的 P2 —— 老约束 ck_coupon_used_time_range 只在
 *      used_time 非空时校验区间，拦不住「status='USED' 但 used_time 为空」。
 *
 *   ② uq_order_header_coupon（过滤唯一索引）
 *      WHERE coupon_id IS NOT NULL 的唯一索引，把业务规则 A5
 *      「一张券只能用一次」从"代码自觉"升级为"库层强制"。
 *
 *   ③ 默认发放 6 张可用券（前 3 位会员各 2 张，模板 TPL_CAMP_5 = 5 元无门槛）
 *      历史 24 张券的有效期止于 2026-10-12，全部过期；为了让核销链路
 *      有真实数据可跑，这里按"会员礼"的默认发放造 6 张，不新增券模板。
 *      券号 CP DEF + 6 位序号，按券号幂等，重复执行不会重复发。
 *
 * 依赖：01-schema / 02-constraints / 11-migration/migration.sql（券表拆分）
 * 阶段：第 9 周（应用开发二：券核销闭环）
 * 作者：DiSod
 * 日期：2026-11-09
 * 幂等：是（约束/索引先 DROP 再建；发券按 coupon_code 去重）
 *
 * 执行：Push-Location project\sql 后
 *       sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -d milktea_shop -i .\11-migration\migration-07-coupon-redemption.sql
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    /* ---------------- 0. 前置：对象必须存在 ---------------- */
    IF OBJECT_ID('dbo.tbl_coupon', 'U') IS NULL
        THROW 51301, N'【迁移07】缺少 tbl_coupon，请先执行 11-migration/migration.sql。', 1;
    IF OBJECT_ID('dbo.tbl_order_header', 'U') IS NULL
        THROW 51302, N'【迁移07】缺少 tbl_order_header。', 1;
    IF NOT EXISTS (SELECT 1 FROM tbl_coupon_template WHERE template_code = 'TPL_CAMP_5')
        THROW 51303, N'【迁移07】缺少券模板 TPL_CAMP_5（5 元无门槛）。', 1;

    DECLARE @checks_before INT;
    SELECT @checks_before = COUNT(*)
    FROM sys.check_constraints cc
    JOIN sys.tables t ON t.object_id = cc.parent_object_id
    WHERE t.name LIKE 'tbl[_]%';

    PRINT FORMATMESSAGE(N'【迁移07】迁移前 CHECK 约束 %d 条。', @checks_before);

    /* ---------------- 1. status 与 used_time 同进同出 ---------------- */
    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = 'ck_coupon_used_time_consistent'
                 AND parent_object_id = OBJECT_ID('dbo.tbl_coupon'))
        ALTER TABLE tbl_coupon DROP CONSTRAINT ck_coupon_used_time_consistent;

    ALTER TABLE tbl_coupon WITH CHECK
        ADD CONSTRAINT ck_coupon_used_time_consistent
        CHECK (
            (status = 'USED'   AND used_time IS NOT NULL)
         OR (status <> 'USED'  AND used_time IS NULL)
        );

    PRINT N'【迁移07】已建 ck_coupon_used_time_consistent（USED ⇔ used_time 非空）。';

    /* ---------------- 2. A5：一张券最多出现在一张订单上 ---------------- */
    IF EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'uq_order_header_coupon'
                 AND object_id = OBJECT_ID('dbo.tbl_order_header'))
        DROP INDEX uq_order_header_coupon ON tbl_order_header;

    CREATE UNIQUE INDEX uq_order_header_coupon
        ON tbl_order_header (coupon_id)
        WHERE coupon_id IS NOT NULL;

    PRINT N'【迁移07】已建过滤唯一索引 uq_order_header_coupon（A5 落到库层）。';

    /* ---------------- 3. 默认发券：前 3 位会员各 2 张 ---------------- */
    DECLARE @tpl_id INT;
    SELECT @tpl_id = template_id FROM tbl_coupon_template WHERE template_code = 'TPL_CAMP_5';

    DECLARE @issued INT = 0;

    ;WITH targets AS (
        SELECT TOP (3) member_id,
               ROW_NUMBER() OVER (ORDER BY member_id) AS rn
        FROM tbl_member
        ORDER BY member_id
    ),
    pairs AS (
        SELECT t.member_id, t.rn, s.seq
        FROM targets t
        CROSS JOIN (SELECT 1 AS seq UNION ALL SELECT 2) s
    ),
    issuance AS (
        SELECT p.member_id,
               'CPDEF' + RIGHT('000000' + CAST((p.rn - 1) * 2 + p.seq AS VARCHAR(6)), 6) AS coupon_code
        FROM pairs p
    )
    INSERT INTO tbl_coupon (coupon_code, member_id, template_id, valid_from, valid_to, status, used_time)
    SELECT pl.coupon_code,
           pl.member_id,
           @tpl_id,
           DATEADD(DAY, -1, CAST(SYSDATETIME() AS DATE)),
           DATEADD(DAY, 30, CAST(SYSDATETIME() AS DATE)),
           'UNUSED',
           NULL
    FROM issuance pl
    WHERE NOT EXISTS (SELECT 1 FROM tbl_coupon c WHERE c.coupon_code = pl.coupon_code);

    SET @issued = @@ROWCOUNT;
    PRINT FORMATMESSAGE(N'【迁移07】本次发放可用券 %d 张（已存在则跳过）。', @issued);

    /* ---------------- 4. 自证 ---------------- */
    DECLARE @bad_state INT;
    SELECT @bad_state = COUNT(*)
    FROM sys.check_constraints
    WHERE name = 'ck_coupon_used_time_consistent'
      AND (is_disabled = 1 OR is_not_trusted = 1);

    IF @bad_state <> 0
        THROW 51304, N'【迁移07】ck_coupon_used_time_consistent 未启用或未受信任，事务回滚。', 1;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE name = 'uq_order_header_coupon'
                     AND object_id = OBJECT_ID('dbo.tbl_order_header')
                     AND is_unique = 1 AND has_filter = 1)
        THROW 51305, N'【迁移07】uq_order_header_coupon 未按预期建立（需 unique + filtered），事务回滚。', 1;

    DECLARE @usable INT;
    SELECT @usable = COUNT(*)
    FROM tbl_coupon
    WHERE status = 'UNUSED'
      AND used_time IS NULL
      AND SYSDATETIME() BETWEEN valid_from AND valid_to;

    IF @usable < 6
        THROW 51306, N'【迁移07】可用券不足 6 张，核销链路演示不了，事务回滚。', 1;

    DECLARE @checks_after INT;
    SELECT @checks_after = COUNT(*)
    FROM sys.check_constraints cc
    JOIN sys.tables t ON t.object_id = cc.parent_object_id
    WHERE t.name LIKE 'tbl[_]%';

    IF @checks_after <> @checks_before + 1
        THROW 51307, N'【迁移07】CHECK 约束条数未按预期 +1，事务回滚。', 1;

    PRINT FORMATMESSAGE(N'【迁移07】自证通过：CHECK %d -> %d 条，可用券 %d 张。',
                        @checks_before, @checks_after, @usable);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO

/* ---------------- 5. 回显 ---------------- */
PRINT N'';
PRINT N'===== 迁移07 结果 =====';

SELECT '约束' AS 检查项, name AS 名称, CAST(is_disabled AS VARCHAR(1)) AS 禁用,
       CAST(is_not_trusted AS VARCHAR(1)) AS 不受信任, definition AS 定义
FROM sys.check_constraints
WHERE name = 'ck_coupon_used_time_consistent';

SELECT '索引' AS 检查项, i.name AS 名称, i.is_unique AS 唯一,
       CAST(i.has_filter AS VARCHAR(1)) AS 带过滤, i.filter_definition AS 过滤条件
FROM sys.indexes i
WHERE i.name = 'uq_order_header_coupon' AND i.object_id = OBJECT_ID('dbo.tbl_order_header');

SELECT status AS 券状态, COUNT(*) AS 张数
FROM tbl_coupon GROUP BY status ORDER BY status;

SELECT COUNT(*) AS 当前可用券 FROM tbl_coupon
WHERE status = 'UNUSED' AND used_time IS NULL
  AND SYSDATETIME() BETWEEN valid_from AND valid_to;

SELECT TOP 6 coupon_id, coupon_code, member_id, status,
       CONVERT(VARCHAR(19), valid_from, 120) AS 生效,
       CONVERT(VARCHAR(19), valid_to, 120) AS 失效
FROM tbl_coupon WHERE coupon_code LIKE 'CPDEF%' ORDER BY coupon_code;

PRINT N'===== 迁移07 完成 =====';
GO
