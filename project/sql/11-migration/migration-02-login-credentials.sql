/* ============================================================
 * 脚本：11-migration/migration-02-login-credentials.sql
 * 用途：为应用层登录补充登录凭据列（第 7—9 周 Web 应用的前置条件）
 * 依赖：00—11 各步已执行（需要 tbl_member / tbl_employee 存在）
 * 阶段：第 7 周（应用开发一）
 * 作者：DiSod / 待 hezhlin5 确认
 * 日期：2026-10-28
 * 幂等：是（加列与加约束都先探测 sys / COL_LENGTH）
 * 状态：⏸ 草稿 —— 尚未合并进 main，等核心工程确认后再接入 99-rebuild.sql
 * ============================================================
 *
 * 【为什么需要本迁移】
 * 全库实查（sys.columns 里 name LIKE '%pass%|%hash%|%salt%|%login%'）只命中
 * sys* 系统表，**用户表没有任何登录凭据列**。而第 7—9 周课程要求
 * 「用户登录 → Web 界面操作 → 数据写入」，没有凭据就无法验证"你是你",
 * 后续的「角色界面 / 权限差异 / 越权拦截」全部失去立足点。
 *
 * 【口径声明（DiSod 裁定，2026-10-28）】
 *   「默认顾客就是会员」——
 *     · 顾客 = tbl_member 的一行；member_id 可空仅为兼容历史散客单
 *     · 顾客登录 = 按会员身份登录，只能看到 member_id = 自己的订单
 *     · 员工登录 = 按岗位登录，tbl_employee.position 决定可见界面
 *       （position 已被 ck_employee_position 限定为 MANAGER/CASHIER/MAKER/STOCKER）
 *
 * 【口令与盐的约定（应用层必须完全照此实现，否则登录永远失败）】
 *   会员：盐 = 'm' + member_id     初始口令 = 手机号后 6 位 RIGHT(member_phone,6)
 *   员工：盐 = 'e' + employee_id   初始口令 = 小写工号 LOWER(employee_code)
 *   摘要：password_hash = UPPERCASE_HEX( SHA-256( 盐 + 口令 ) )，定长 64 字符
 *
 * 【⚠️ 三个必须遵守的实现约束】
 *   1. 拼接只能用 VARCHAR，不能混入 NVARCHAR(N'...')
 *      SQL Server 的 HASHBYTES 对 NVARCHAR 按 UTF-16LE 取字节，而 Python 的
 *      hashlib.sha256 按 UTF-8 取字节，两者结果不同。全链路保持 VARCHAR 且
 *      输入为纯 ASCII（数字 / 字母 / 冒号），UTF-8 与单字节编码才逐字节相同。
 *      实测同一输入 'm1'+'000001'：SQL 与 Python 均得
 *      1E1B7D0D6A69C96EEDFEA681049626ABEFD6E6FB20AFCD2C9AE1EB79F4EA4192
 *   2. 盐不能含 NEWID() 之类的随机源
 *      NEWID() 每次调用都不同（已实测），会让 99-rebuild 的重建结果不确定，
 *      直接破坏第 6 周建立的"迁移前后快照逐行一致（293/293）"承诺。
 *      本脚本用 member_id / employee_id 派生盐 —— 既确定，又逐行唯一。
 *   3. 引用新列的语句必须走动态 SQL
 *      同一个批次内的语句在【编译期】就要求列已存在，而 ALTER TABLE ADD 要到
 *      执行期才生效，直接写会报「列名 'password_hash' 无效」（消息 207）。
 *      故本脚本对"引用新列"的 UPDATE / CHECK / 自证全部走 sp_executesql。
 *
 * 【为什么 password_hash 允许为 NULL】
 *   05-dml/crud.sql 有 5 处 INSERT 只给 member/employee 的业务列，不给凭据。
 *   若设为 NOT NULL，那些演示脚本会当场失败。取 NULL = "账号已建但未开通登录"，
 *   应用侧必须按失败处理（fail-closed），即 NULL 永远登录不成功。
 *   本迁移保证现存 80 会员 + 5 员工全部有值。
 *
 * 【回滚方法】
 *   ALTER TABLE dbo.tbl_member   DROP CONSTRAINT ck_member_password_hash_format;
 *   ALTER TABLE dbo.tbl_employee DROP CONSTRAINT ck_employee_password_hash_format;
 *   ALTER TABLE dbo.tbl_member   DROP COLUMN password_hash;
 *   ALTER TABLE dbo.tbl_employee DROP COLUMN password_hash;
 *   （只删列，不动任何业务数据；不新增表、不新增外码、不改主码）
 *
 * 【本次迁移的规模】
 *   表数 18 → 18（不变）  字段 137 → 139（+2）
 *   外码 31 → 31（不变）  CHECK 44 → 46（+2 格式约束）
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'【迁移02】开始 —— 补充登录凭据列';
GO

BEGIN TRANSACTION;

BEGIN TRY

    DECLARE @sql NVARCHAR(MAX);
    DECLARE @rows INT;

    /* ---------- 1. 前置校验 ---------- */
    IF OBJECT_ID(N'dbo.tbl_member', N'U') IS NULL
       OR OBJECT_ID(N'dbo.tbl_employee', N'U') IS NULL
    BEGIN
        THROW 52001, N'【迁移02】缺少 tbl_member / tbl_employee，请先执行 00—11 各步后重试。', 1;
    END

    /* ---------- 2. 幂等加列 ---------- */
    IF COL_LENGTH(N'dbo.tbl_member', N'password_hash') IS NULL
    BEGIN
        EXEC sp_executesql N'ALTER TABLE dbo.tbl_member ADD password_hash CHAR(64) NULL;';
        PRINT N'【迁移02】tbl_member.password_hash 已创建。';
    END
    ELSE
        PRINT N'【迁移02】tbl_member.password_hash 已存在，跳过。';

    IF COL_LENGTH(N'dbo.tbl_employee', N'password_hash') IS NULL
    BEGIN
        EXEC sp_executesql N'ALTER TABLE dbo.tbl_employee ADD password_hash CHAR(64) NULL;';
        PRINT N'【迁移02】tbl_employee.password_hash 已创建。';
    END
    ELSE
        PRINT N'【迁移02】tbl_employee.password_hash 已存在，跳过。';

    /* ---------- 3. 回填初始口令（只填 NULL，重跑不覆盖已改过的密码） ---------- */
    SET @sql = N'
        UPDATE dbo.tbl_member
           SET password_hash = CONVERT(CHAR(64),
                 HASHBYTES(''SHA2_256'',
                   ''m'' + CONVERT(VARCHAR(10), member_id) + RIGHT(member_phone, 6)), 2)
         WHERE password_hash IS NULL;
        SET @n = @@ROWCOUNT;';

    EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @rows OUTPUT;
    PRINT N'【迁移02】tbl_member 回填 ' + CONVERT(VARCHAR(10), @rows) + N' 行。';

    SET @sql = N'
        UPDATE dbo.tbl_employee
           SET password_hash = CONVERT(CHAR(64),
                 HASHBYTES(''SHA2_256'',
                   ''e'' + CONVERT(VARCHAR(10), employee_id) + LOWER(employee_code)), 2)
         WHERE password_hash IS NULL;
        SET @n = @@ROWCOUNT;';

    EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @rows OUTPUT;
    PRINT N'【迁移02】tbl_employee 回填 ' + CONVERT(VARCHAR(10), @rows) + N' 行。';

    /* ---------- 4. 幂等加格式约束：64 位大写十六进制 ---------- */
    IF OBJECT_ID(N'dbo.ck_member_password_hash_format', N'C') IS NULL
    BEGIN
        SET @sql = N'ALTER TABLE dbo.tbl_member WITH CHECK
                     ADD CONSTRAINT ck_member_password_hash_format
                     CHECK (password_hash IS NULL
                            OR (LEN(password_hash) = 64
                                AND password_hash COLLATE Latin1_General_100_BIN2
                                    NOT LIKE ''%[^0-9A-F]%''));';
        EXEC sp_executesql @sql;
        PRINT N'【迁移02】ck_member_password_hash_format 已创建。';
    END
    ELSE
        PRINT N'【迁移02】ck_member_password_hash_format 已存在，跳过。';

    IF OBJECT_ID(N'dbo.ck_employee_password_hash_format', N'C') IS NULL
    BEGIN
        SET @sql = N'ALTER TABLE dbo.tbl_employee WITH CHECK
                     ADD CONSTRAINT ck_employee_password_hash_format
                     CHECK (password_hash IS NULL
                            OR (LEN(password_hash) = 64
                                AND password_hash COLLATE Latin1_General_100_BIN2
                                    NOT LIKE ''%[^0-9A-F]%''));';
        EXEC sp_executesql @sql;
        PRINT N'【迁移02】ck_employee_password_hash_format 已创建。';
    END
    ELSE
        PRINT N'【迁移02】ck_employee_password_hash_format 已存在，跳过。';

    /* ---------- 5. 自证：库里每一行都必须能被同一规则重算出来 ---------- */
    SET @sql = N'
        IF EXISTS (
            SELECT 1 FROM dbo.tbl_member
             WHERE password_hash IS NULL
                OR password_hash <> CONVERT(CHAR(64),
                     HASHBYTES(''SHA2_256'',
                       ''m'' + CONVERT(VARCHAR(10), member_id) + RIGHT(member_phone, 6)), 2)
        )
            THROW 52002, N''【迁移02】tbl_member 存在为空或与规则不符的凭据。'', 1;';
    EXEC sp_executesql @sql;

    SET @sql = N'
        IF EXISTS (
            SELECT 1 FROM dbo.tbl_employee
             WHERE password_hash IS NULL
                OR password_hash <> CONVERT(CHAR(64),
                     HASHBYTES(''SHA2_256'',
                       ''e'' + CONVERT(VARCHAR(10), employee_id) + LOWER(employee_code)), 2)
        )
            THROW 52003, N''【迁移02】tbl_employee 存在为空或与规则不符的凭据。'', 1;';
    EXEC sp_executesql @sql;

    PRINT N'【迁移02】自证通过：全部凭据均可按约定重算。';

    COMMIT TRANSACTION;
    PRINT N'【迁移02】事务提交成功。';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT N'【迁移02】失败并已回滚：' + ERROR_MESSAGE();
    THROW;
END CATCH;
GO

/* ---------- 6. 迁移结果回显（留档用） ---------- */
PRINT N'【迁移02】凭据覆盖情况：';

SELECT N'tbl_member' AS [表], COUNT(*) AS [行数],
       SUM(CASE WHEN password_hash IS NULL THEN 1 ELSE 0 END) AS [未设凭据],
       MIN(password_hash) AS [哈希样例]
  FROM dbo.tbl_member
UNION ALL
SELECT N'tbl_employee', COUNT(*),
       SUM(CASE WHEN password_hash IS NULL THEN 1 ELSE 0 END),
       MIN(password_hash)
  FROM dbo.tbl_employee;

PRINT N'【迁移02】约束状态：';

SELECT c.name AS [约束名], OBJECT_NAME(c.parent_object_id) AS [所属表],
       c.is_disabled AS [已禁用]
  FROM sys.check_constraints c
 WHERE c.name IN (N'ck_member_password_hash_format', N'ck_employee_password_hash_format');

PRINT N'【迁移02】完成 —— 18 表不变，字段 137 → 139，CHECK 44 → 46。';
GO
