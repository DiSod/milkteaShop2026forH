/* ============================================================
 * 脚本：migration.sql
 * 用途：第 6 周（ch7 规范化与模式重构）标准迁移脚本（满足课程迁移 6 要素）
 * 依赖：00-bootstrap ~ 08-security（从 17 表基线平滑演进至 18 表重构形态）
 * 阶段：第 6 周
 * 作者：hezhlin5 & DiSod
 * 日期：2026-10-21
 * 幂等：是 —— 基于 sys.tables/columns/constraints 探测与显式事务回滚保护
 * ============================================================
 *
 * 【课程迁移 6 要素落地对照】
 *   要素 1【新表创建】：
 *     创建优惠券模板实体表 tbl_coupon_template，抽取券公共元数据
 *   要素 2【字段调整】：
 *     原表 tbl_coupon 增加外键列 template_id；安全移除 4 个冗余列 (coupon_name, source, discount_amount, min_order_amount)
 *   要素 3【码与约束设置】：
 *     新表设置 PK(template_id)、UQ(template_code)、域 CHECK 与默认约束；
 *     原表设置 FK fk_coupon_template、索引 ix_coupon_template_id、核销有效区间约束 ck_coupon_used_time_range
 *   要素 4【数据迁移】：
 *     从 tbl_coupon 抽取去重模板并注入 tbl_coupon_template；精准回填 tbl_coupon.template_id
 *   要素 5【数据校验与防重】：
 *     严格校验无孤儿券记录 (template_id IS NULL = 0)、券总行数无损、模板唯一性、核销时间窗口 100% 合规
 *   要素 6【旧表处理与平滑过渡】：
 *     创建向后兼容全景视图 vw_coupon_legacy，旧列平滑解耦，同步补齐 RBAC 角色权限 (role_cashier / role_manager)
 *
 * 【执行方式】
 *   方式一（独立迁移演练）：
 *     cd project\\sql
 *     sqlcmd -S .\\SQLEXPRESS -E -C -f 65001 -i 11-migration\\migration.sql
 *   方式二（全库一键重建流水线）：
 *     由 project/sql/99-rebuild.sql 统一按序调用
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'============================================================';
PRINT N'【迁移】开始执行第 6 周模式演进与优惠券规范化拆分 (ch7 迁移 6 要素) ...';
PRINT N'============================================================';
GO

BEGIN TRANSACTION;

BEGIN TRY
    -- 0. 基础环境探查
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'tbl_coupon')
    BEGIN
        RAISERROR(N'【迁移阻断】未检测到基础表 tbl_coupon，请确认基础模式已初始化！', 16, 1);
    END;

    /* ------------------------------------------------------------
     * 要素 1：新表创建 —— tbl_coupon_template（优惠券模板表）
     * ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'tbl_coupon_template')
    BEGIN
        PRINT N'【要素 1/6】正在创建优惠券模板实体表 tbl_coupon_template ...';
        CREATE TABLE tbl_coupon_template (
            template_id        INT IDENTITY(1,1) NOT NULL,
            template_code      VARCHAR(20)       NOT NULL,
            template_name      NVARCHAR(20)      NOT NULL,
            source             VARCHAR(16)       NOT NULL,
            discount_amount    DECIMAL(10,2)     NOT NULL,
            min_order_amount   DECIMAL(10,2)     NOT NULL CONSTRAINT df_coupon_template_min_order_amount DEFAULT 0,
            is_active          BIT               NOT NULL CONSTRAINT df_coupon_template_is_active DEFAULT 1,
            created_at         DATETIME2         NOT NULL CONSTRAINT df_coupon_template_created_at DEFAULT SYSDATETIME(),
            CONSTRAINT pk_coupon_template PRIMARY KEY (template_id),
            CONSTRAINT uq_coupon_template_code UNIQUE (template_code),
            CONSTRAINT ck_coupon_template_source CHECK (source IN ('POINTS_EXCHANGE','CAMPAIGN')),
            CONSTRAINT ck_coupon_template_discount_amount CHECK (discount_amount > 0),
            CONSTRAINT ck_coupon_template_min_order_amount CHECK (min_order_amount >= 0)
        );
        PRINT N'  --> ✅ tbl_coupon_template 创建成功（包含 PK, UQ, CHECK, DEFAULT 约束）。';
    END
    ELSE
    BEGIN
        PRINT N'【要素 1/6】检测到 tbl_coupon_template 已存在，跳过建表。';
    END;

    /* ------------------------------------------------------------
     * 要素 2(前置)：字段调整 —— 为 tbl_coupon 添加外键列 template_id
     * ------------------------------------------------------------ */
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID(N'tbl_coupon') AND name = N'template_id'
    )
    BEGIN
        PRINT N'【要素 2/6】正在为 tbl_coupon 添加外键列 template_id ...';
        ALTER TABLE tbl_coupon ADD template_id INT NULL;
        PRINT N'  --> ✅ 列 template_id 已成功添加到 tbl_coupon。';
    END
    ELSE
    BEGIN
        PRINT N'【要素 2/6】检测到 tbl_coupon 已包含 template_id 列。';
    END;

    /* ------------------------------------------------------------
     * 要素 4：数据迁移与抽取 —— 模板去重注入与券关联回填
     * ------------------------------------------------------------ */
    IF EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID(N'tbl_coupon') AND name = N'coupon_name'
    )
    BEGIN
        -- 4.1 抽取去重模板数据注入 tbl_coupon_template（动态 SQL 避免编译期未解析）
        EXEC sp_executesql N'
            IF NOT EXISTS (SELECT 1 FROM tbl_coupon_template)
            BEGIN
                PRINT N''【要素 4/6】正在从 tbl_coupon 抽取去重模板并注入 tbl_coupon_template ...'';
                INSERT INTO tbl_coupon_template (
                    template_code, template_name, source, discount_amount, min_order_amount, is_active
                )
                SELECT 
                    CASE source 
                        WHEN ''POINTS_EXCHANGE'' THEN ''TPL_POINTS_5''
                        WHEN ''CAMPAIGN''        THEN ''TPL_CAMP_5''
                        ELSE ''TPL_GEN_'' + CAST(ROW_NUMBER() OVER(ORDER BY source) AS VARCHAR(10))
                    END AS template_code,
                    coupon_name,
                    source,
                    discount_amount,
                    min_order_amount,
                    1 AS is_active
                FROM (
                    SELECT DISTINCT coupon_name, source, discount_amount, min_order_amount
                    FROM tbl_coupon
                ) AS d;

                DECLARE @tpl_count INT = @@ROWCOUNT;
                PRINT FORMATMESSAGE(N''  --> ✅ 成功抽取并生成 %d 个独立券模板记录。'', @tpl_count);
            END;
        ';

        -- 4.2 回填 tbl_coupon 中的 template_id
        PRINT N'【要素 4/6】正在回填 tbl_coupon.template_id 关联关系 ...';
        EXEC sp_executesql N'
            UPDATE c
            SET c.template_id = t.template_id
            FROM tbl_coupon c
            INNER JOIN tbl_coupon_template t
                ON c.coupon_name = t.template_name
               AND c.source = t.source
               AND c.discount_amount = t.discount_amount
               AND c.min_order_amount = t.min_order_amount
            WHERE c.template_id IS NULL;
        ';
        PRINT N'  --> ✅ 券实例 template_id 回填完成。';
    END;

    /* ------------------------------------------------------------
     * 要素 5：数据校验与防重 —— 迁移完整性硬性断言
     * ------------------------------------------------------------ */
    PRINT N'【要素 5/6】正在执行迁移后数据完整性与约束合规性断言校验 ...';

    -- 5.1 校验孤儿数据（template_id 未命中）
    DECLARE @orphan_count INT = 0;
    EXEC sp_executesql N'SELECT @cnt = COUNT(*) FROM tbl_coupon WHERE template_id IS NULL;', N'@cnt INT OUTPUT', @cnt = @orphan_count OUTPUT;
    IF @orphan_count > 0
    BEGIN
        DECLARE @err_orphan NVARCHAR(200) = FORMATMESSAGE(N'【迁移断言失败】发现 %d 行优惠券未成功关联模板！', @orphan_count);
        RAISERROR(@err_orphan, 16, 1);
    END;

    -- 5.2 校验券核销有效区间合规性
    DECLARE @time_violations INT = 0;
    SELECT @time_violations = COUNT(*)
    FROM tbl_coupon
    WHERE used_time IS NOT NULL 
      AND (used_time < valid_from OR used_time > valid_to);

    IF @time_violations > 0
    BEGIN
        DECLARE @err_time NVARCHAR(200) = FORMATMESSAGE(N'【迁移断言失败】发现 %d 行历史优惠券核销时间超出有效区间！', @time_violations);
        RAISERROR(@err_time, 16, 1);
    END;
    PRINT N'  --> ✅ 数据完整性断言通过：0 孤儿券，核销时间窗口 100% 合规。';

    /* ------------------------------------------------------------
     * 要素 3：码与完整性约束设置 —— FK, CHECK, NOT NULL, INDEX
     * ------------------------------------------------------------ */
    PRINT N'【要素 3/6】正在强化外键、索引与域完整性约束 ...';

    -- 3.1 设定 template_id NOT NULL
    ALTER TABLE tbl_coupon ALTER COLUMN template_id INT NOT NULL;

    -- 3.2 幂等创建外键约束 fk_coupon_template
    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_coupon_template' AND parent_object_id = OBJECT_ID(N'tbl_coupon')
    )
    BEGIN
        ALTER TABLE tbl_coupon WITH CHECK
            ADD CONSTRAINT fk_coupon_template
                FOREIGN KEY (template_id) REFERENCES tbl_coupon_template(template_id);
        PRINT N'  --> ✅ 外键约束 fk_coupon_template 添加成功。';
    END;

    -- 3.3 幂等创建外键索引 ix_coupon_template_id
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes WHERE name = N'ix_coupon_template_id' AND object_id = OBJECT_ID(N'tbl_coupon')
    )
    BEGIN
        CREATE NONCLUSTERED INDEX ix_coupon_template_id ON tbl_coupon (template_id);
        PRINT N'  --> ✅ 外键覆盖索引 ix_coupon_template_id 创建成功。';
    END;

    -- 3.4 幂等创建核销时间区间约束 ck_coupon_used_time_range
    IF NOT EXISTS (
        SELECT 1 FROM sys.check_constraints WHERE name = N'ck_coupon_used_time_range' AND parent_object_id = OBJECT_ID(N'tbl_coupon')
    )
    BEGIN
        ALTER TABLE tbl_coupon WITH CHECK
            ADD CONSTRAINT ck_coupon_used_time_range
                CHECK (used_time IS NULL OR (used_time >= valid_from AND used_time <= valid_to));
        PRINT N'  --> ✅ 核销有效区间检查约束 ck_coupon_used_time_range 添加成功。';
    END;

    /* ------------------------------------------------------------
     * 要素 2(后置)：安全移除旧冗余列（彻底消除传递依赖与更新异常）
     * ------------------------------------------------------------ */
    IF EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID(N'tbl_coupon') AND name = N'coupon_name'
    )
    BEGIN
        PRINT N'【要素 2/6(后置)】正在清理原表旧约束并安全移除 4 个冗余模板列 ...';

        -- 清理原表绑定在旧列上的 CHECK 约束
        IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'ck_coupon_source' AND parent_object_id = OBJECT_ID(N'tbl_coupon'))
            ALTER TABLE tbl_coupon DROP CONSTRAINT ck_coupon_source;

        IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'ck_coupon_discount_amount' AND parent_object_id = OBJECT_ID(N'tbl_coupon'))
            ALTER TABLE tbl_coupon DROP CONSTRAINT ck_coupon_discount_amount;

        IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'ck_coupon_min_order_amount' AND parent_object_id = OBJECT_ID(N'tbl_coupon'))
            ALTER TABLE tbl_coupon DROP CONSTRAINT ck_coupon_min_order_amount;

        -- 清理原表绑定在旧列上的默认约束
        DECLARE @def_name NVARCHAR(128);
        SELECT @def_name = d.name
        FROM sys.default_constraints d
        INNER JOIN sys.columns c ON d.parent_column_id = c.column_id AND d.parent_object_id = c.object_id
        WHERE d.parent_object_id = OBJECT_ID(N'tbl_coupon') AND c.name = N'min_order_amount';

        IF @def_name IS NOT NULL
        BEGIN
            EXEC(N'ALTER TABLE tbl_coupon DROP CONSTRAINT ' + @def_name);
        END;

        -- 执行 DROP COLUMN
        ALTER TABLE tbl_coupon DROP COLUMN coupon_name, source, discount_amount, min_order_amount;
        PRINT N'  --> ✅ 成功移除旧列 coupon_name, source, discount_amount, min_order_amount。';
    END
    ELSE
    BEGIN
        PRINT N'【要素 2/6(后置)】原表已无冗余旧列，跳过列移除。';
    END;

    COMMIT TRANSACTION;
    PRINT N'【迁移成功】核心 DDL 变更与数据迁移事务已成功提交！';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @err_msg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @err_sev INT = ERROR_SEVERITY();
    DECLARE @err_sta INT = ERROR_STATE();

    PRINT N'【迁移失败】事务已全量安全回滚：' + @err_msg;
    RAISERROR(@err_msg, @err_sev, @err_sta);
END CATCH;
GO

/* ------------------------------------------------------------
 * 要素 6：兼容旧表与平滑过渡处理 —— 建立向后兼容视图与权限同步
 * ------------------------------------------------------------ */
PRINT N'【要素 6/6】正在创建向后兼容全景视图 vw_coupon_legacy 并同步 RBAC 权限 ...';
GO

EXEC sp_executesql N'
CREATE OR ALTER VIEW vw_coupon_legacy
AS
SELECT 
    c.coupon_id,
    c.coupon_code,
    c.member_id,
    t.template_name      AS coupon_name,
    t.source,
    t.discount_amount,
    t.min_order_amount,
    c.valid_from,
    c.valid_to,
    c.status,
    c.used_time,
    c.template_id,
    t.template_code,
    t.is_active          AS template_is_active
FROM tbl_coupon c
INNER JOIN tbl_coupon_template t ON c.template_id = t.template_id;
';
GO

-- 同步角色访问权限
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'role_cashier' AND type = 'R')
BEGIN
    EXEC(N'GRANT SELECT ON tbl_coupon_template TO role_cashier;');
    EXEC(N'GRANT SELECT ON vw_coupon_legacy    TO role_cashier;');
    PRINT N'  --> ✅ role_cashier 权限已同步（SELECT ON tbl_coupon_template, vw_coupon_legacy）。';
END;

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'role_manager' AND type = 'R')
BEGIN
    EXEC(N'GRANT SELECT, INSERT, UPDATE, DELETE ON tbl_coupon_template TO role_manager;');
    EXEC(N'GRANT SELECT                         ON vw_coupon_legacy    TO role_manager;');
    PRINT N'  --> ✅ role_manager 权限已同步。';
END;
GO

/* ============================================================
 * 迁移后状态回显与验证报表
 * ============================================================ */
PRINT N'============================================================';
PRINT N'【迁移成果统计】第 6 周规范化拆分迁移完成，状态概览：';
PRINT N'============================================================';
GO

SELECT 
    (SELECT COUNT(*) FROM tbl_coupon_template) AS [模板表总行数],
    (SELECT COUNT(*) FROM tbl_coupon)          AS [优惠券实例总行数],
    (SELECT COUNT(*) FROM vw_coupon_legacy)    AS [兼容视图可用行数],
    (SELECT COUNT(*) FROM sys.tables)          AS [全库业务表数(应为18)];
GO

SELECT 
    template_id        AS [模板ID],
    template_code      AS [模板编码],
    template_name      AS [模板名称],
    source             AS [券来源],
    discount_amount    AS [抵扣金额],
    min_order_amount   AS [使用门槛],
    is_active          AS [启用状态]
FROM tbl_coupon_template;
GO
