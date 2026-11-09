/* ============================================================
 * 脚本：create-tables.sql
 * 用途：建立奶茶店数据库全部 17 张业务表（表结构 DDL）
 * 依赖：00-bootstrap/create-database.sql
 * 阶段：第 3 周
 * 作者：DiSod
 * 日期：2026-10-04
 * 幂等：是 —— 先删除全部外键，再按依赖逆序 DROP，然后重建
 * ============================================================
 *
 * 【真相源】
 *   本脚本是 project/docs/data-dictionary.md 第二节（字段字典）的**逐字翻译**。
 *   改表结构请先改数据字典，再改本脚本 —— 不要两处各自演化。
 *
 * 【本脚本的范围】
 *   只建**表结构**：列定义 + PRIMARY KEY + NOT NULL + DEFAULT + IDENTITY
 *   以下几类**不在这里**，统一放在 02-constraints/constraints.sql：
 *     - 外键 FK        （跨表约束）
 *     - 唯一约束 UNIQUE（候选码）
 *     - 检查约束 CHECK （域）
 *
 *   这样分的原因：课程第 4 周的任务正是"主外键 / 检查约束"，
 *   拆开后 02-constraints 有实操素材（演示"非法数据被拒绝"）。
 *
 * 【表清单 17 张（按依赖顺序，被引用的在前）】
 *   基础档案与主数据  tbl_employee / tbl_member / tbl_product_category
 *                     tbl_spec_option / tbl_ingredient / tbl_supplier
 *                     tbl_product / tbl_topping / tbl_recipe
 *   采购              tbl_purchase_order / tbl_purchase_order_detail
 *   会员              tbl_coupon
 *   交易              tbl_order_header / tbl_order_detail / tbl_order_detail_topping
 *   流水              tbl_points_ledger / tbl_stock_ledger
 *
 * 【执行方式】
 *   sqlcmd -S .\SQLEXPRESS -E -i project/sql/01-schema/create-tables.sql
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* ============================================================
 * 幂等处理：按依赖逆序重建
 * ============================================================ */

-- 先删除库内全部外键约束（否则 DROP TABLE 会被引用阻塞）
DECLARE @drop_fk NVARCHAR(MAX) = N'';

SELECT @drop_fk = @drop_fk
                + N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id))
                + N'.' + QUOTENAME(OBJECT_NAME(parent_object_id))
                + N' DROP CONSTRAINT ' + QUOTENAME(name) + N';' + CHAR(13)
FROM sys.foreign_keys
WHERE parent_object_id IN (SELECT object_id
                           FROM sys.tables WHERE name LIKE N'tbl[_]%');

IF LEN(@drop_fk) > 0
    EXEC sp_executesql @drop_fk;
GO

-- 按依赖逆序删除（被引用的表最后删）
DROP TABLE IF EXISTS tbl_stock_ledger;
DROP TABLE IF EXISTS tbl_points_ledger;
DROP TABLE IF EXISTS tbl_order_detail_topping;
DROP TABLE IF EXISTS tbl_order_detail;
DROP TABLE IF EXISTS tbl_order_header;
DROP TABLE IF EXISTS tbl_coupon;
DROP TABLE IF EXISTS tbl_purchase_order_detail;
DROP TABLE IF EXISTS tbl_purchase_order;
DROP TABLE IF EXISTS tbl_recipe;
DROP TABLE IF EXISTS tbl_topping;
DROP TABLE IF EXISTS tbl_product;
DROP TABLE IF EXISTS tbl_supplier;
DROP TABLE IF EXISTS tbl_ingredient;
DROP TABLE IF EXISTS tbl_spec_option;
DROP TABLE IF EXISTS tbl_product_category;
DROP TABLE IF EXISTS tbl_member;
DROP TABLE IF EXISTS tbl_employee;
GO

PRINT N'【建表】旧表已清理，开始建表 ...';
GO

/* ============================================================
 * A. 基础档案与主数据（9 张）
 * ============================================================ */

/* ---------- 1/17  tbl_employee（员工） ---------- */
CREATE TABLE tbl_employee (
    employee_id     INT IDENTITY(1,1) NOT NULL,
    employee_code   VARCHAR(10)       NOT NULL,
    employee_name   NVARCHAR(20)      NOT NULL,
    position        VARCHAR(10)       NOT NULL,
    hire_date       DATE              NOT NULL,
    is_active       BIT               NOT NULL CONSTRAINT df_employee_is_active DEFAULT 1,
    CONSTRAINT pk_employee PRIMARY KEY (employee_id)
);
GO

/* ---------- 2/17  tbl_member（会员） ---------- */
CREATE TABLE tbl_member (
    member_id       INT IDENTITY(1,1) NOT NULL,
    member_code     VARCHAR(10)       NOT NULL,
    member_phone    VARCHAR(11)       NOT NULL,
    member_name     NVARCHAR(20)      NOT NULL,
    register_date   DATE              NOT NULL,
    points_balance  INT               NOT NULL CONSTRAINT df_member_points_balance DEFAULT 0,
    CONSTRAINT pk_member PRIMARY KEY (member_id)
);
GO

/* ---------- 3/17  tbl_product_category（商品品类，自引用层级） ---------- */
CREATE TABLE tbl_product_category (
    category_id         INT IDENTITY(1,1) NOT NULL,
    parent_category_id  INT               NULL,
    category_code       VARCHAR(10)       NOT NULL,
    category_name       NVARCHAR(20)      NOT NULL,
    sort_no             INT               NOT NULL CONSTRAINT df_product_category_sort_no DEFAULT 0,
    is_active           BIT               NOT NULL CONSTRAINT df_product_category_is_active DEFAULT 1,
    CONSTRAINT pk_product_category PRIMARY KEY (category_id)
);
GO

/* ---------- 4/17  tbl_spec_option（规格选项：杯型 / 糖度 / 冰量，含加价） ---------- */
CREATE TABLE tbl_spec_option (
    spec_option_id  INT IDENTITY(1,1) NOT NULL,
    spec_type       VARCHAR(10)       NOT NULL,
    spec_code       VARCHAR(6)        NOT NULL,
    spec_name       NVARCHAR(10)      NOT NULL,
    extra_price     DECIMAL(10,2)     NOT NULL CONSTRAINT df_spec_option_extra_price DEFAULT 0,
    sort_no         INT               NOT NULL CONSTRAINT df_spec_option_sort_no DEFAULT 0,
    CONSTRAINT pk_spec_option PRIMARY KEY (spec_option_id)
);
GO

/* ---------- 5/17  tbl_ingredient（原料 · 三表合一：字典 + 库存 + 采购策略） ---------- */
CREATE TABLE tbl_ingredient (
    ingredient_id    INT IDENTITY(1,1) NOT NULL,
    ingredient_code  VARCHAR(10)       NOT NULL,
    ingredient_name  NVARCHAR(30)      NOT NULL,
    unit             VARCHAR(6)        NOT NULL,
    spec             NVARCHAR(20)      NULL,
    qty_on_hand      DECIMAL(12,3)     NOT NULL CONSTRAINT df_ingredient_qty_on_hand    DEFAULT 0,
    reorder_point    DECIMAL(12,3)     NOT NULL CONSTRAINT df_ingredient_reorder_point  DEFAULT 0,
    target_level     DECIMAL(12,3)     NOT NULL CONSTRAINT df_ingredient_target_level   DEFAULT 0,
    moving_avg_cost  DECIMAL(10,4)     NOT NULL CONSTRAINT df_ingredient_moving_avg_cost DEFAULT 0,
    is_sold_out      BIT               NOT NULL CONSTRAINT df_ingredient_is_sold_out    DEFAULT 0,
    is_active        BIT               NOT NULL CONSTRAINT df_ingredient_is_active      DEFAULT 1,
    CONSTRAINT pk_ingredient PRIMARY KEY (ingredient_id)
);
GO

/* ---------- 6/17  tbl_supplier（供应商 · 4 字段极简） ---------- */
CREATE TABLE tbl_supplier (
    supplier_id    INT IDENTITY(1,1) NOT NULL,
    supplier_code  VARCHAR(10)       NOT NULL,
    supplier_name  NVARCHAR(50)      NOT NULL,
    is_active      BIT               NOT NULL CONSTRAINT df_supplier_is_active DEFAULT 1,
    CONSTRAINT pk_supplier PRIMARY KEY (supplier_id)
);
GO

/* ---------- 7/17  tbl_product（商品 · 成品菜单） ---------- */
CREATE TABLE tbl_product (
    product_id      INT IDENTITY(1,1) NOT NULL,
    product_code    VARCHAR(10)       NOT NULL,
    product_name    NVARCHAR(30)      NOT NULL,
    category_id     INT               NOT NULL,
    base_price      DECIMAL(10,2)     NOT NULL,
    product_status  VARCHAR(10)       NOT NULL CONSTRAINT df_product_product_status DEFAULT N'ON_SALE',
    CONSTRAINT pk_product PRIMARY KEY (product_id)
);
GO

/* ---------- 8/17  tbl_topping（小料 · 加料项，菜单 ↔ 原料的桥） ---------- */
CREATE TABLE tbl_topping (
    topping_id        INT IDENTITY(1,1) NOT NULL,
    topping_code      VARCHAR(10)       NOT NULL,
    topping_name      NVARCHAR(20)      NOT NULL,
    ingredient_id     INT               NOT NULL,
    extra_price       DECIMAL(10,2)     NOT NULL CONSTRAINT df_topping_extra_price DEFAULT 0,
    qty_per_serving   DECIMAL(12,3)     NOT NULL,
    is_active         BIT               NOT NULL CONSTRAINT df_topping_is_active DEFAULT 1,
    CONSTRAINT pk_topping PRIMARY KEY (topping_id)
);
GO

/* ---------- 9/17  tbl_recipe（配方 BOM · 订单 ↔ 库存的桥） ---------- */
CREATE TABLE tbl_recipe (
    recipe_id       INT IDENTITY(1,1) NOT NULL,
    product_id      INT               NOT NULL,
    cup_spec_id     INT               NOT NULL,
    sugar_spec_id   INT               NULL,      -- NULL ＝ 该原料用量与糖度无关（D-05a）
    ingredient_id   INT               NOT NULL,
    qty             DECIMAL(12,3)     NOT NULL,
    CONSTRAINT pk_recipe PRIMARY KEY (recipe_id)
);
GO

/* ============================================================
 * B. 采购（2 张）
 * ============================================================ */

/* ---------- 10/17  tbl_purchase_order（采购单头） ---------- */
CREATE TABLE tbl_purchase_order (
    purchase_order_id  INT IDENTITY(1,1) NOT NULL,
    purchase_no        VARCHAR(20)       NOT NULL,
    supplier_id        INT               NOT NULL,
    order_date         DATE              NOT NULL,
    arrival_date       DATE              NULL,
    order_status       VARCHAR(12)       NOT NULL CONSTRAINT df_purchase_order_order_status DEFAULT N'ORDERED',
    ordered_by         INT               NOT NULL,
    received_by        INT               NULL,
    CONSTRAINT pk_purchase_order PRIMARY KEY (purchase_order_id)
);
GO

/* ---------- 11/17  tbl_purchase_order_detail（采购明细） ---------- */
CREATE TABLE tbl_purchase_order_detail (
    purchase_order_detail_id  INT IDENTITY(1,1) NOT NULL,
    purchase_order_id         INT               NOT NULL,
    ingredient_id             INT               NOT NULL,
    qty_ordered               DECIMAL(12,3)     NOT NULL,
    qty_received              DECIMAL(12,3)     NOT NULL CONSTRAINT df_purchase_order_detail_qty_received DEFAULT 0,
    unit_price                DECIMAL(12,4)     NOT NULL,
    CONSTRAINT pk_purchase_order_detail PRIMARY KEY (purchase_order_detail_id)
);
GO

/* ============================================================
 * C. 会员（1 张）
 * ============================================================ */

/* ---------- 12/17  tbl_coupon（券 · 发放 + 核销合一） ---------- */
CREATE TABLE tbl_coupon (
    coupon_id         INT IDENTITY(1,1) NOT NULL,
    coupon_code       VARCHAR(20)       NOT NULL,
    member_id         INT               NOT NULL,
    coupon_name       NVARCHAR(20)      NOT NULL,
    source            VARCHAR(16)       NOT NULL,
    discount_amount   DECIMAL(10,2)     NOT NULL,
    min_order_amount  DECIMAL(10,2)     NOT NULL CONSTRAINT df_coupon_min_order_amount DEFAULT 0,
    valid_from        DATETIME2         NOT NULL,
    valid_to          DATETIME2         NOT NULL,
    status            VARCHAR(8)        NOT NULL CONSTRAINT df_coupon_status DEFAULT N'UNUSED',
    used_time         DATETIME2         NULL,
    CONSTRAINT pk_coupon PRIMARY KEY (coupon_id)
);
GO

/* ============================================================
 * D. 交易（3 张）
 * ============================================================ */

/* ---------- 13/17  tbl_order_header（订单单头，含支付） ---------- */
CREATE TABLE tbl_order_header (
    order_id         INT IDENTITY(1,1) NOT NULL,
    order_no         VARCHAR(20)       NOT NULL,
    business_date    DATE              NOT NULL,
    pickup_no        INT               NOT NULL,
    member_id        INT               NULL,
    coupon_id        INT               NULL,
    discount_amount  DECIMAL(10,2)     NOT NULL CONSTRAINT df_order_header_discount_amount DEFAULT 0,
    amount_due       DECIMAL(10,2)     NOT NULL,
    amount_paid      DECIMAL(10,2)     NOT NULL CONSTRAINT df_order_header_amount_paid     DEFAULT 0,
    pay_method       VARCHAR(10)       NULL,
    pay_status       VARCHAR(8)        NULL,
    pay_time         DATETIME2         NULL,
    trade_no         VARCHAR(40)       NULL,
    order_status     VARCHAR(10)       NOT NULL CONSTRAINT df_order_header_order_status DEFAULT N'PENDING',
    order_time       DATETIME2         NOT NULL CONSTRAINT df_order_header_order_time   DEFAULT SYSDATETIME(),
    finish_time      DATETIME2         NULL,
    cashier_id       INT               NOT NULL,
    CONSTRAINT pk_order_header PRIMARY KEY (order_id)
);
GO

/* ---------- 14/17  tbl_order_detail（订单明细，含规格快照） ---------- */
CREATE TABLE tbl_order_detail (
    order_detail_id  INT IDENTITY(1,1) NOT NULL,
    order_id         INT               NOT NULL,
    line_no          INT               NOT NULL,
    product_id       INT               NOT NULL,
    qty              INT               NOT NULL CONSTRAINT df_order_detail_qty DEFAULT 1,
    unit_price       DECIMAL(10,2)     NOT NULL,
    cup_spec_id      INT               NULL,
    sugar_spec_id    INT               NULL,
    ice_spec_id      INT               NULL,
    subtotal         DECIMAL(10,2)     NOT NULL,
    CONSTRAINT pk_order_detail PRIMARY KEY (order_detail_id)
);
GO

/* ---------- 15/17  tbl_order_detail_topping（明细加料，一行一种） ---------- */
CREATE TABLE tbl_order_detail_topping (
    od_topping_id      INT IDENTITY(1,1) NOT NULL,
    order_detail_id    INT               NOT NULL,
    topping_id         INT               NOT NULL,
    qty                INT               NOT NULL CONSTRAINT df_order_detail_topping_qty DEFAULT 1,
    unit_extra_price   DECIMAL(10,2)     NOT NULL,
    CONSTRAINT pk_order_detail_topping PRIMARY KEY (od_topping_id)
);
GO

/* ============================================================
 * E. 流水（2 张，只增不改）
 * ============================================================ */

/* ---------- 16/17  tbl_points_ledger（积分流水） ---------- */
CREATE TABLE tbl_points_ledger (
    point_ledger_id  INT IDENTITY(1,1) NOT NULL,
    member_id        INT               NOT NULL,
    point_type       VARCHAR(10)       NOT NULL,
    point_change     INT               NOT NULL,
    order_id         INT               NULL,
    coupon_id        INT               NULL,
    change_time      DATETIME2         NOT NULL CONSTRAINT df_points_ledger_change_time DEFAULT SYSDATETIME(),
    CONSTRAINT pk_points_ledger PRIMARY KEY (point_ledger_id)
);
GO

/* ---------- 17/17  tbl_stock_ledger（库存流水，单库、无库位维度） ---------- */
CREATE TABLE tbl_stock_ledger (
    ledger_id          INT IDENTITY(1,1) NOT NULL,
    ingredient_id      INT               NOT NULL,
    ledger_type        VARCHAR(12)       NOT NULL,
    qty                DECIMAL(12,3)     NOT NULL,
    ref_type           VARCHAR(10)       NOT NULL,
    purchase_order_id  INT               NULL,
    order_id           INT               NULL,
    operator_id        INT               NULL,   -- NULL ＝ 系统自动反冲扣料
    ledger_time        DATETIME2         NOT NULL CONSTRAINT df_stock_ledger_ledger_time DEFAULT SYSDATETIME(),
    remark             NVARCHAR(100)     NULL,
    CONSTRAINT pk_stock_ledger PRIMARY KEY (ledger_id)
);
GO

/* ============================================================
 * 建表结果回显
 * ============================================================ */

PRINT N'【建表】完成。共建立 17 张表：';
GO

SELECT
    t.name                                   AS [表名],
    (SELECT COUNT(*) FROM sys.columns c
      WHERE c.object_id = t.object_id)       AS [字段数],
    (SELECT COUNT(*) FROM sys.key_constraints k
      WHERE k.parent_object_id = t.object_id
        AND k.type = 'PK')                   AS [主码]
FROM sys.tables t
ORDER BY t.name;
GO

PRINT N'【建表】下一步：执行 02-constraints/constraints.sql 添加外键 / 候选码 / 域约束。';
GO
