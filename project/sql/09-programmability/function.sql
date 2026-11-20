/* ============================================================
   脚本：function.sql
   用途：第 10 周 —— 三个函数（补货量 / 销售汇总 / 折扣计算）
   依赖：09-programmability/procedure.sql 会调用这里的函数，须先执行本脚本
   阶段：第 10 周（存储过程与函数）
   作者：DiSod
   日期：2026-11-20
   幂等：是（全部 CREATE OR ALTER，可重复执行）
   ============================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE milktea_shop;
GO

/* ------------------------------------------------------------
   1. dbo.fn_replenish_qty —— 按目标水位算补货量（标量函数）
   返回值：需要补的数量；0 = 已达标不用补；NULL = 原料编号不存在
   为什么 NULL 不在函数里 THROW：函数会被放在 SELECT 里用，
   一个坏编号抛异常会让整条查询失败，把"查不存在的编号"变成灾难。
   ------------------------------------------------------------ */
CREATE OR ALTER FUNCTION dbo.fn_replenish_qty
(
    @ingredient_id INT
)
RETURNS DECIMAL(12,3)
AS
BEGIN
    DECLARE @found    INT           = 0,
            @target   DECIMAL(12,3) = NULL,
            @on_hand  DECIMAL(12,3) = NULL,
            @gap      DECIMAL(12,3);

    SELECT  @found   = 1,
            @target  = ISNULL(i.target_level, i.reorder_point * 2),
            @on_hand = i.qty_on_hand
    FROM    dbo.tbl_ingredient AS i
    WHERE   i.ingredient_id = @ingredient_id;

    IF @found = 0
        RETURN NULL;                       -- 编号不存在

    IF @target IS NULL
        RETURN CAST(0 AS DECIMAL(12,3));   -- 两个水位都没配，视为不需要补

    SET @gap = @target - @on_hand;
    IF @gap <= 0
        RETURN CAST(0 AS DECIMAL(12,3));

    RETURN @gap;
END;
GO

/* ------------------------------------------------------------
   2. dbo.fn_sales_summary —— 销售汇总（内联表值函数）
   用法：SELECT * FROM dbo.fn_sales_summary('2026-09-18', '2026-09-23');
   日期语义：闭区间，含首尾两天（课程提示要求写明）
   口径：pay_status='SUCCESS' 且 order_status<>'CANCELLED'（同 D 口径）
   非法参数：@start_date/@end_date 为 NULL 或起止颠倒时返回空集。
   内联 TVF 里不能 THROW（一抛就破坏内联），校验交给外层过程。
   ------------------------------------------------------------ */
CREATE OR ALTER FUNCTION dbo.fn_sales_summary
(
    @start_date DATE,
    @end_date   DATE
)
RETURNS TABLE
AS
RETURN
(
    SELECT  d.product_id                        AS product_id,
            p.product_name                      AS product_name,
            SUM(d.qty)                          AS qty,
            CAST(SUM(d.subtotal) AS DECIMAL(12,2)) AS amount,
            COUNT(DISTINCT h.order_id)          AS order_count
    FROM    dbo.tbl_order_detail AS d
    JOIN    dbo.tbl_order_header AS h ON h.order_id  = d.order_id
    JOIN    dbo.tbl_product      AS p ON p.product_id = d.product_id
    WHERE   @start_date IS NOT NULL
      AND   @end_date   IS NOT NULL
      AND   @start_date <= @end_date
      AND   h.pay_status   = 'SUCCESS'
      AND   h.order_status <> 'CANCELLED'
      AND   h.business_date >= @start_date      -- 闭区间：含当天
      AND   h.business_date <= @end_date
    GROUP BY d.product_id, p.product_name
);
GO

/* ------------------------------------------------------------
   3. dbo.fn_discount_amount —— 折扣金额（标量函数）
   三条依据：
     ① 券：模板面额，需券未用、在有效期内、订单金额 ≥ 门槛
     ② 订单金额满减：满 30 减 3，满 50 减 8（硬编码，第 12 周再看要不要建表）
     ③ 会员身份：会员再减 1 元
   组合规则：①② 取较优不叠加；③ 在较优值上叠加；总折扣不超过订单金额。
   返回：折扣金额（不是折扣率）；折扣率 = 返回值 / @amount（调用方自行算）
   只算不写：落库由下单流程负责（历史订单要留当时的成交价快照）。
   ------------------------------------------------------------ */
CREATE OR ALTER FUNCTION dbo.fn_discount_amount
(
    @member_id INT           = NULL,      -- NULL = 散客
    @amount    DECIMAL(10,2) = NULL,
    @coupon_id INT           = NULL
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    IF @amount IS NULL OR @amount <= 0
        RETURN CAST(0 AS DECIMAL(10,2));

    /* ① 券 */
    DECLARE @coupon_disc DECIMAL(10,2) = 0;

    IF @coupon_id IS NOT NULL
    BEGIN
        SELECT @coupon_disc = CAST(t.discount_amount AS DECIMAL(10,2))
        FROM   dbo.tbl_coupon AS c
        JOIN   dbo.tbl_coupon_template AS t ON t.template_id = c.template_id
        WHERE  c.coupon_id = @coupon_id
          AND  c.status    = 'UNUSED'
          AND  (@member_id IS NULL OR c.member_id = @member_id)
          AND  SYSDATETIME() BETWEEN c.valid_from AND c.valid_to
          AND  @amount >= t.min_order_amount
          AND  t.is_active = 1;

        SET @coupon_disc = ISNULL(@coupon_disc, 0);
        IF @coupon_disc > @amount
            SET @coupon_disc = @amount;
    END

    /* ② 满减（硬编码） */
    DECLARE @tier DECIMAL(10,2) =
        CASE WHEN @amount >= 50 THEN CAST(8 AS DECIMAL(10,2))
             WHEN @amount >= 30 THEN CAST(3 AS DECIMAL(10,2))
             ELSE CAST(0 AS DECIMAL(10,2)) END;

    /* ①② 取较优 */
    DECLARE @best DECIMAL(10,2) =
        CASE WHEN @coupon_disc > @tier THEN @coupon_disc ELSE @tier END;

    /* ③ 会员叠加 1 元 */
    DECLARE @member_bonus DECIMAL(10,2) =
        CASE WHEN @member_id IS NOT NULL THEN CAST(1 AS DECIMAL(10,2))
             ELSE CAST(0 AS DECIMAL(10,2)) END;

    DECLARE @total DECIMAL(10,2) = @best + @member_bonus;

    IF @total > @amount SET @total = @amount;   -- 不能折成负数
    IF @total < 0       SET @total = 0;

    RETURN @total;
END;
GO

PRINT N'【函数】三个函数已创建/更新：fn_replenish_qty、fn_sales_summary、fn_discount_amount';
GO
