/* ============================================================
 * 脚本：role.sql
 * 用途：奶茶店 4 岗位 RBAC 权限控制体系与越权拦截负例测试
 * 依赖：00-bootstrap/create-database.sql
 *       01-schema/create-tables.sql
 *       02-constraints/constraints.sql
 *       04-seed/seed_data.sql
 *       07-view/view.sql
 * 阶段：第 4 周
 * 作者：何争霖 (hezhlin5) / 协同：DiSod
 * 日期：2026-10-05
 * 幂等：是 —— 先安全清理测试用户与角色，再重建赋权，最后执行负例验证
 * ============================================================
 *
 * 【第 4 周权限设计思想与业务背景】
 * 课程第 4 周核心理论为“数据库安全与授权（ch4 DCL）”。
 * 单店奶茶店日常运营中，员工职责分工明确，必须实施基于角色的访问控制（RBAC）：
 *
 * 1. 4 大业务岗位角色体系：
 *    - role_manager  【店长】：全店最高管理权限，掌控全库表、视图及流水审计。
 *    - role_cashier  【收银员】：负责前台点单、收银结算、会员注册及优惠券核销；
 *                                拥有菜单与全景订单宽表只读权；严禁修改配方与原料库存。
 *    - role_maker    【制作员/调饮师】：负责吧台饮品制作，可更新订单制作状态，
 *                                查阅配方标准与商品可做杯数；严禁接触会员隐私与财务。
 *    - role_stocker  【库管员】：负责原料收货验收、物料入库记账与缺料预警巡检；
 *                                严禁查询或伪造前台交易订单。
 *
 * 2. 3 组越权行为拦截实测（负例验证）：
 *    通过 EXECUTE AS USER 模拟真实员工身份，验证数据库引擎硬性拦截：
 *    - 负例 1：收银员篡改配方用量（拒绝！防原料偷工减料）
 *    - 负例 2：制作员窃取会员档案与手机号（拒绝！防顾客隐私泄露）
 *    - 负例 3：库管员越权删除前台交易单据（拒绝！防财务销赃对不上账）
 *
 * 【执行方式】
 *   sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -i project/sql/08-security/role.sql
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT N'【安全】开始部署 4 岗位 RBAC 权限体系与安全角色 ...';
GO

/* ============================================================
 * 0. 幂等准备：安全清理旧的测试用户与角色
 * ============================================================ */
-- 若处于模拟上下文中，先恢复为 dbo
WHILE USER_NAME() <> 'dbo'
BEGIN
    REVERT;
END
GO

-- 清理测试用户
IF USER_ID('usr_test_cashier') IS NOT NULL DROP USER usr_test_cashier;
IF USER_ID('usr_test_maker')   IS NOT NULL DROP USER usr_test_maker;
IF USER_ID('usr_test_stocker') IS NOT NULL DROP USER usr_test_stocker;
GO

-- 清理角色
IF DATABASE_PRINCIPAL_ID('role_manager') IS NOT NULL DROP ROLE role_manager;
IF DATABASE_PRINCIPAL_ID('role_cashier') IS NOT NULL DROP ROLE role_cashier;
IF DATABASE_PRINCIPAL_ID('role_maker')   IS NOT NULL DROP ROLE role_maker;
IF DATABASE_PRINCIPAL_ID('role_stocker') IS NOT NULL DROP ROLE role_stocker;
GO

PRINT N'【安全】旧角色与测试用户清理完毕。';
GO

/* ============================================================
 * 1. 建立 4 大岗位角色
 * ============================================================ */
CREATE ROLE role_manager;  -- 店长
CREATE ROLE role_cashier;  -- 收银员
CREATE ROLE role_maker;    -- 制作员
CREATE ROLE role_stocker;  -- 库管员
GO

PRINT N'【安全】4 大岗位角色已创建。';
GO

/* ============================================================
 * 2. 角色精细化授权（GRANT）
 * ============================================================ */

-- 2.1 店长（role_manager）：全权管理
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO role_manager;
GO

-- 2.2 收银员（role_cashier）：交易结算 + 会员营销 + 菜单只读
GRANT SELECT, INSERT, UPDATE ON tbl_order_header         TO role_cashier;
GRANT SELECT, INSERT         ON tbl_order_detail         TO role_cashier;
GRANT SELECT, INSERT         ON tbl_order_detail_topping TO role_cashier;
GRANT SELECT, INSERT, UPDATE ON tbl_member               TO role_cashier;
GRANT SELECT, UPDATE         ON tbl_coupon               TO role_cashier;
GRANT SELECT                 ON tbl_product              TO role_cashier;
GRANT SELECT                 ON tbl_product_category     TO role_cashier;
GRANT SELECT                 ON tbl_spec_option          TO role_cashier;
GRANT SELECT                 ON tbl_topping              TO role_cashier;
GRANT SELECT                 ON vw_product_stock_availability TO role_cashier;
GRANT SELECT                 ON vw_order_detail_full     TO role_cashier;
GO

-- 2.3 制作员（role_maker）：制作看板 + 配方查阅
GRANT SELECT, UPDATE         ON tbl_order_header         TO role_maker;
GRANT SELECT                 ON tbl_order_detail         TO role_maker;
GRANT SELECT                 ON tbl_order_detail_topping TO role_maker;
GRANT SELECT                 ON tbl_recipe               TO role_maker;
GRANT SELECT                 ON tbl_product              TO role_maker;
GRANT SELECT                 ON tbl_spec_option          TO role_maker;
GRANT SELECT                 ON tbl_topping              TO role_maker;
GRANT SELECT                 ON vw_product_stock_availability TO role_maker;
GO

-- 2.4 库管员（role_stocker）：物料台账 + 采购验收 + 补货预警
GRANT SELECT, UPDATE         ON tbl_purchase_order        TO role_stocker;
GRANT SELECT, UPDATE         ON tbl_purchase_order_detail TO role_stocker;
GRANT SELECT                 ON tbl_supplier              TO role_stocker;
GRANT SELECT, UPDATE         ON tbl_ingredient            TO role_stocker;
GRANT SELECT, INSERT         ON tbl_stock_ledger          TO role_stocker;
GRANT SELECT                 ON vw_ingredient_reorder_alert TO role_stocker;
GO

PRINT N'【安全】4 大角色权限矩阵配置完毕。';
GO

/* ============================================================
 * 3. 创建测试用户并分配角色（WITHOUT LOGIN，纯净安全）
 * ============================================================ */
CREATE USER usr_test_cashier WITHOUT LOGIN;
CREATE USER usr_test_maker   WITHOUT LOGIN;
CREATE USER usr_test_stocker WITHOUT LOGIN;
GO

ALTER ROLE role_cashier ADD MEMBER usr_test_cashier;
ALTER ROLE role_maker   ADD MEMBER usr_test_maker;
ALTER ROLE role_stocker ADD MEMBER usr_test_stocker;
GO

PRINT N'【安全】测试用户已建立并成功加入对应角色。';
GO

/* ============================================================
 * 4. 越权拦截负例测试（Negative Authorization Tests）
 * ============================================================ */
PRINT N'【安全】=== 开始执行 3 组越权拦截负例测试 ===';
GO

/* ---------- 负例 1：收银员试图私自篡改配方（防偷工减料） ---------- */
EXECUTE AS USER = 'usr_test_cashier';
GO

PRINT N'【负例 1】当前身份：' + USER_NAME() + N'，正在尝试篡改配方表 tbl_recipe ...';
BEGIN TRY
    UPDATE tbl_recipe SET qty = 999.000 WHERE recipe_id = 1;
    PRINT N'❌ 测试失败：收银员未被拦截，权限出现泄露！';
END TRY
BEGIN CATCH
    PRINT N'✅ 负例 1 成功拦截：' + ERROR_MESSAGE() 
        + N' (错误码: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N')';
END CATCH;
GO

REVERT;
GO

/* ---------- 负例 2：制作员试图越权窥探会员隐私与手机号（防客户数据外泄） ---------- */
EXECUTE AS USER = 'usr_test_maker';
GO

PRINT N'【负例 2】当前身份：' + USER_NAME() + N'，正在尝试窥探会员隐私表 tbl_member ...';
BEGIN TRY
    SELECT TOP 1 member_phone FROM tbl_member;
    PRINT N'❌ 测试失败：制作员未被拦截，权限出现泄露！';
END TRY
BEGIN CATCH
    PRINT N'✅ 负例 2 成功拦截：' + ERROR_MESSAGE() 
        + N' (错误码: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N')';
END CATCH;
GO

REVERT;
GO

/* ---------- 负例 3：库管员试图越权删除前台交易订单（防财务销赃对不上账） ---------- */
EXECUTE AS USER = 'usr_test_stocker';
GO

PRINT N'【负例 3】当前身份：' + USER_NAME() + N'，正在尝试删除订单单头表 tbl_order_header ...';
BEGIN TRY
    DELETE FROM tbl_order_header WHERE order_id = 999999;
    PRINT N'❌ 测试失败：库管员未被拦截，权限出现泄露！';
END TRY
BEGIN CATCH
    PRINT N'✅ 负例 3 成功拦截：' + ERROR_MESSAGE() 
        + N' (错误码: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N')';
END CATCH;
GO

REVERT;
GO

/* ============================================================
 * 5. 权限矩阵总览回显
 * ============================================================ */
PRINT N'【安全】=== 数据库自定义角色权限清单汇总 ===';
SELECT 
    r.name                                                               AS 角色名称,
    o.name                                                               AS 授权对象,
    p.permission_name                                                    AS 授予权限,
    p.state_desc                                                         AS 权限状态
FROM sys.database_permissions p
INNER JOIN sys.database_principals r 
    ON p.grantee_principal_id = r.principal_id
LEFT JOIN sys.objects o 
    ON p.major_id = o.object_id
WHERE r.name IN ('role_manager', 'role_cashier', 'role_maker', 'role_stocker')
ORDER BY r.name, o.name, p.permission_name;
GO

PRINT N'【安全】第 4 周 RBAC 权限体系与越权拦截负例测试全部通过！';
GO
