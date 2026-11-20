/* ============================================================
   脚本：procedure.sql
   用途：第 10 周 —— 两个存储过程（销售统计 / 库存调整）
   依赖：09-programmability/function.sql（usp_sales_report 会调用 fn_sales_summary）
   阶段：第 10 周（存储过程与函数）
   作者：DiSod
   日期：2026-11-20
   幂等：是（CREATE OR ALTER）
   ============================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE milktea_shop;
GO

/* ------------------------------------------------------------
   1. dbo.usp_sales_report —— 销售统计
   ------------------------------------------------------------
   为什么用存储过程而不是函数：
     它要返回**两个结果集**（汇总 + 商品明细），函数做不到；
     而且它要做参数校验并"明确报错"，这也是过程的职责。
   两个结果集：
     结果集 1：一行汇总（订单数 / 销售数量 / 销售金额 / 会员单数 / 客单价）
     结果集 2：商品明细（编号 / 名称 / 杯数 / 金额 / 金额占比）
   口径：pay_status='SUCCESS' 且 order_status<>'CANCELLED'（D 口径），
         日期是**闭区间**，含首尾两天。
   空区间：汇总仍返回一行 0，不报错 —— 让调用方拿到数字，不用判断 NULL。
   ------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.usp_sales_report
    @start_date DATE,
    @end_date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    /* 参数校验：三种非法输入直接抛，错误号固定，方便调用方识别 */
    IF @start_date IS NULL OR @end_date IS NULL
        THROW 51401, N'销售统计：起止日期不能为空。', 1;
    IF @start_date > @end_date
        THROW 51402, N'销售统计：开始日期不能晚于结束日期。', 1;
    IF DATEDIFF(DAY, @start_date, @end_date) > 366
        THROW 51403, N'销售统计：日期跨度不能超过 366 天（防止误查全库）。', 1;

    DECLARE @orders  INT           = 0,
            @amount  DECIMAL(12,2) = 0,
            @members INT           = 0,
            @cups    DECIMAL(12,3) = 0;

    /* 订单级指标：从订单头算，避免与明细 JOIN 后行数翻倍 */
    SELECT  @orders  = COUNT(*),
            @amount  = ISNULL(SUM(h.amount_paid), 0),
            @members = ISNULL(SUM(CASE WHEN h.member_id IS NOT NULL THEN 1 ELSE 0 END), 0)
    FROM    dbo.tbl_order_header AS h
    WHERE   h.pay_status   = 'SUCCESS'
      AND   h.order_status <> 'CANCELLED'
      AND   h.business_date >= @start_date
      AND   h.business_date <= @end_date;

    /* 杯数：从明细算，同样用 D 口径过滤 */
    SELECT  @cups = ISNULL(SUM(d.qty), 0)
    FROM    dbo.tbl_order_detail AS d
    JOIN    dbo.tbl_order_header AS h ON h.order_id = d.order_id
    WHERE   h.pay_status   = 'SUCCESS'
      AND   h.order_status <> 'CANCELLED'
      AND   h.business_date >= @start_date
      AND   h.business_date <= @end_date;

    /* 结果集 1：汇总（始终一行） */
    SELECT  @start_date                                              AS 开始日期,
            @end_date                                                AS 结束日期,
            @orders                                                  AS 订单数,
            @cups                                                    AS 销售数量,
            @amount                                                  AS 销售金额,
            @members                                                 AS 会员单数,
            CAST(CASE WHEN @orders = 0 THEN 0
                      ELSE @amount / @orders END AS DECIMAL(10,2))   AS 客单价;

    /* 明细不在这个过程里返回，交给表值函数：
         SELECT * FROM dbo.fn_sales_summary(@start_date, @end_date);
       理由有二：
         1) 过程管"汇总 + 报错 + 事务"，函数管"可复用的明细查询"，职责不混；
         2) 一个过程只返回一个结果集，调用方才能 INSERT ... EXEC 抓结果做断言。
           （返回两个结果集时 SQL Server 会直接报 213，实测过。）
    */
END;
GO

/* ------------------------------------------------------------
   2. dbo.usp_stock_adjust —— 库存调整
   ------------------------------------------------------------
   为什么用存储过程：它要**写数据**（改结存 + 记流水），而且必须
   "要么都成、要么都不成" —— 这正是事务该在数据库里做的原因。
   流水类型复用现有取值（不新增类型）：
     @delta > 0 → PURCHASE_IN（盘盈/手工入库）
     @delta < 0 → LOSS（盘亏/报损）
     两者都配 ref_type='MANUAL'，order_id 与 purchase_order_id 留空，
     这样 ck_stock_ledger_ref_consistency 才能通过。
   并发：读结存时加 UPDLOCK, ROWLOCK，防止两个人同时调整把数量算错。
   ------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.usp_stock_adjust
    @ingredient_id INT,
    @delta         DECIMAL(12,3),      -- 正数入库、负数出库
    @reason        NVARCHAR(200),
    @operator_id   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;                 -- 出任何错都回滚，不留半条数据

    /* 参数校验：五个拒绝条件 */
    IF NOT EXISTS (SELECT 1 FROM dbo.tbl_ingredient WHERE ingredient_id = @ingredient_id)
        THROW 51411, N'库存调整：原料不存在。', 1;

    IF @delta IS NULL OR @delta = 0
        THROW 51412, N'库存调整：调整数量不能为空，也不能为 0。', 1;

    IF @reason IS NULL OR LTRIM(RTRIM(@reason)) = N''
        THROW 51413, N'库存调整：必须填写调整原因。', 1;

    IF LEN(@reason) > 200
        THROW 51414, N'库存调整：原因不能超过 200 个字。', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.tbl_employee WHERE employee_id = @operator_id)
        THROW 51416, N'库存调整：操作员不存在。', 1;

    DECLARE @before    DECIMAL(12,3),
            @after     DECIMAL(12,3),
            @ledger_id INT,
            @type      VARCHAR(20),
            @msg       NVARCHAR(400);

    SET @type = CASE WHEN @delta > 0 THEN 'PURCHASE_IN' ELSE 'LOSS' END;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* 加锁读当前结存：并发下两个会话会排队，不会各读各的 */
        SELECT @before = i.qty_on_hand
        FROM   dbo.tbl_ingredient AS i WITH (UPDLOCK, ROWLOCK)
        WHERE  i.ingredient_id = @ingredient_id;

        SET @after = @before + @delta;

        /* 调整后不能为负：报错信息里带当前结存与调整量，方便定位 */
        IF @after < 0
        BEGIN
            SET @msg = N'库存调整：原料 ' + CAST(@ingredient_id AS NVARCHAR(10))
                     + N' 当前结存 ' + CAST(@before AS NVARCHAR(30))
                     + N'，调整量 ' + CAST(@delta AS NVARCHAR(30))
                     + N' 会变成负库存。';
            ROLLBACK TRANSACTION;
            THROW 51415, @msg, 1;
        END

        /* ① 改结存 */
        UPDATE dbo.tbl_ingredient
        SET    qty_on_hand = @after
        WHERE  ingredient_id = @ingredient_id;

        /* ② 记流水：qty 与 delta 同号，remark 存原因 */
        INSERT INTO dbo.tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, order_id, purchase_order_id,
             operator_id, ledger_time, remark)
        VALUES
            (@ingredient_id, @type, @delta, 'MANUAL', NULL, NULL,
             @operator_id, SYSDATETIME(), @reason);

        SET @ledger_id = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;                          -- 原样抛出，错误号不丢
    END CATCH

    /* 返回一行结果，调用方可以直接显示"调整前 → 调整后" */
    SELECT  @ingredient_id AS 原料编号,
            @before        AS 调整前结存,
            @delta         AS 调整量,
            @after         AS 调整后结存,
            @type          AS 流水类型,
            @ledger_id     AS 流水号;
END;
GO

PRINT N'【过程】两个存储过程已创建/更新：usp_sales_report、usp_stock_adjust';
GO
