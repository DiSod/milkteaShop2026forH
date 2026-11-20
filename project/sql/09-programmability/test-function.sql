/* ============================================================
   脚本：test-function.sql
   用途：第 10 周 —— 三个函数的正反例（预期 / 实际 / PASS｜FAIL）
   设计要点：
   1) 预期值尽量"独立重算"（不调用被测函数），避免自证循环
   2) 依赖库状态的用例（券、已达标原料）**在事务里临时造，跑完 ROLLBACK**
      —— 库里默认券随时可能被演示用掉，不能让测试依赖"当前还有没有可用券"
   3) 用例总数固定 22，漏跑会判红（"少一条用例"不能表现为全绿）
   退出码：任一 FAIL → RAISERROR 16 → 配合 sqlcmd -b 变成非零退出
   ============================================================ */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE milktea_shop;
GO

DECLARE @r TABLE
(
    seq      INT IDENTITY(1,1) PRIMARY KEY,
    item     NVARCHAR(120),
    expected NVARCHAR(60),
    actual   NVARCHAR(60),
    ok       BIT
);

/* ================= 一、fn_replenish_qty（只读） ================= */

/* 1 正例：布丁粉 I019 —— 预期用独立算式重算 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'补货量·布丁粉 I019（正常）',
       CONVERT(NVARCHAR(60), CAST(CASE WHEN i.qty_on_hand >= ISNULL(i.target_level, i.reorder_point*2) THEN 0
                                       ELSE ISNULL(i.target_level, i.reorder_point*2) - i.qty_on_hand END AS DECIMAL(12,3))),
       CONVERT(NVARCHAR(60), dbo.fn_replenish_qty(19)),
       CASE WHEN dbo.fn_replenish_qty(19)
                 = CASE WHEN i.qty_on_hand >= ISNULL(i.target_level, i.reorder_point*2) THEN 0
                        ELSE ISNULL(i.target_level, i.reorder_point*2) - i.qty_on_hand END
            THEN 1 ELSE 0 END
FROM dbo.tbl_ingredient AS i WHERE i.ingredient_id = 19;

/* 2 正例：椰浆 I055 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'补货量·椰浆 I055（正常）',
       CONVERT(NVARCHAR(60), CAST(CASE WHEN i.qty_on_hand >= ISNULL(i.target_level, i.reorder_point*2) THEN 0
                                       ELSE ISNULL(i.target_level, i.reorder_point*2) - i.qty_on_hand END AS DECIMAL(12,3))),
       CONVERT(NVARCHAR(60), dbo.fn_replenish_qty(55)),
       CASE WHEN dbo.fn_replenish_qty(55)
                 = CASE WHEN i.qty_on_hand >= ISNULL(i.target_level, i.reorder_point*2) THEN 0
                        ELSE ISNULL(i.target_level, i.reorder_point*2) - i.qty_on_hand END
            THEN 1 ELSE 0 END
FROM dbo.tbl_ingredient AS i WHERE i.ingredient_id = 55;

/* 3 反例：不存在的编号 → NULL（不是 0、不报错） */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'补货量·编号 99999（不存在）→ NULL', N'NULL',
        ISNULL(CONVERT(NVARCHAR(60), dbo.fn_replenish_qty(99999)), N'NULL'),
        CASE WHEN dbo.fn_replenish_qty(99999) IS NULL THEN 1 ELSE 0 END);

/* ================= 二、fn_sales_summary（只读） ================= */

DECLARE @rows INT, @amt DECIMAL(12,2), @exp_amt DECIMAL(12,2);

SELECT @rows = COUNT(*), @amt = ISNULL(SUM(amount), 0)
FROM   dbo.fn_sales_summary('2026-09-18', '2026-09-23');

SELECT @exp_amt = CAST(ISNULL(SUM(d.subtotal), 0) AS DECIMAL(12,2))
FROM   dbo.tbl_order_detail AS d
JOIN   dbo.tbl_order_header AS h ON h.order_id = d.order_id
WHERE  h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
  AND  h.business_date BETWEEN '2026-09-18' AND '2026-09-23';

/* 4 */ INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售汇总·9/18–9/23 返回行数 > 0', N'>0',
        CONVERT(NVARCHAR(60), @rows), CASE WHEN @rows > 0 THEN 1 ELSE 0 END);

/* 5 */ INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售汇总·金额与明细复算一致', CONVERT(NVARCHAR(60), @exp_amt),
        CONVERT(NVARCHAR(60), @amt), CASE WHEN @amt = @exp_amt THEN 1 ELSE 0 END);

/* 6 反例：NULL 参数 → 空集 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'销售汇总·参数 NULL → 0 行', N'0',
       CONVERT(NVARCHAR(60), COUNT(*)), CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM   dbo.fn_sales_summary(NULL, '2026-09-23');

/* 7 反例：起止颠倒 → 空集 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'销售汇总·起止颠倒 → 0 行', N'0',
       CONVERT(NVARCHAR(60), COUNT(*)), CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM   dbo.fn_sales_summary('2026-09-23', '2026-09-18');

/* 8 边界：闭区间——单日区间应等于当天自己 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'销售汇总·单日区间（闭区间）',
       CONVERT(NVARCHAR(60), CAST(ISNULL(SUM(d.subtotal),0) AS DECIMAL(12,2))),
       CONVERT(NVARCHAR(60), CAST(ISNULL((SELECT SUM(amount) FROM dbo.fn_sales_summary('2026-09-23','2026-09-23')),0) AS DECIMAL(12,2))),
       CASE WHEN ISNULL((SELECT SUM(amount) FROM dbo.fn_sales_summary('2026-09-23','2026-09-23')),0)
                 = ISNULL(SUM(d.subtotal),0) THEN 1 ELSE 0 END
FROM   dbo.tbl_order_detail AS d
JOIN   dbo.tbl_order_header AS h ON h.order_id = d.order_id
WHERE  h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
  AND  h.business_date = '2026-09-23';

/* ============ 三、需要造状态的用例（事务内，跑完回滚） ============ */

DECLARE @c1 INT, @c2 INT,
        @coupon_before INT      = (SELECT COUNT(*) FROM dbo.tbl_coupon),
        @qty19_before   DECIMAL(12,3) = (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 19);

BEGIN TRANSACTION;

/* 造一个"已达标"的原料：把布丁粉的结存临时抬到目标水位 */
UPDATE dbo.tbl_ingredient
SET    qty_on_hand = ISNULL(target_level, reorder_point * 2)
WHERE  ingredient_id = 19;

/* 9 边界：已达标 → 0 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'补货量·已达标（临时抬到目标水位）→ 0', N'0',
        CONVERT(NVARCHAR(60), dbo.fn_replenish_qty(19)),
        CASE WHEN dbo.fn_replenish_qty(19) = 0 THEN 1 ELSE 0 END);

/* 造两张测试券：会员 1 / 会员 2 */
INSERT INTO dbo.tbl_coupon (coupon_code, member_id, template_id, valid_from, valid_to, status, used_time)
SELECT N'TESTFN0001', 1, t.template_id,
       DATEADD(DAY, -1, SYSDATETIME()), DATEADD(DAY, 30, SYSDATETIME()), 'UNUSED', NULL
FROM   dbo.tbl_coupon_template AS t WHERE t.template_code = 'TPL_CAMP_5';
SET @c1 = SCOPE_IDENTITY();

INSERT INTO dbo.tbl_coupon (coupon_code, member_id, template_id, valid_from, valid_to, status, used_time)
SELECT N'TESTFN0002', 2, t.template_id,
       DATEADD(DAY, -1, SYSDATETIME()), DATEADD(DAY, 30, SYSDATETIME()), 'UNUSED', NULL
FROM   dbo.tbl_coupon_template AS t WHERE t.template_code = 'TPL_CAMP_5';
SET @c2 = SCOPE_IDENTITY();

/* 10 */ INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·散客 8 元无券 → 0.00', N'0.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(NULL, 8.00, NULL)),
        CASE WHEN dbo.fn_discount_amount(NULL, 8.00, NULL) = 0.00 THEN 1 ELSE 0 END);

/* 11 券与满减取优：满减 8 更高 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·55 元 + 5 元券 → 8.00（满减 8 更优，不叠加）', N'8.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(NULL, 55.00, @c1)),
        CASE WHEN dbo.fn_discount_amount(NULL, 55.00, @c1) = 8.00 THEN 1 ELSE 0 END);

/* 12 券更优：券 5 > 满减 3 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·35 元 + 5 元券 → 5.00（券 5 > 满减 3）', N'5.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(NULL, 35.00, @c1)),
        CASE WHEN dbo.fn_discount_amount(NULL, 35.00, @c1) = 5.00 THEN 1 ELSE 0 END);

/* 13 */ INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·散客 55 元无券 → 8.00（满 50 减 8）', N'8.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(NULL, 55.00, NULL)),
        CASE WHEN dbo.fn_discount_amount(NULL, 55.00, NULL) = 8.00 THEN 1 ELSE 0 END);

/* 14 */ INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·会员 55 元无券 → 9.00（满减 + 会员 1 元）', N'9.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(1, 55.00, NULL)),
        CASE WHEN dbo.fn_discount_amount(1, 55.00, NULL) = 9.00 THEN 1 ELSE 0 END);

/* 15 券不属于本人 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·券不属于本人 → 满减 3 + 会员 1 = 4.00', N'4.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(2, 35.00, @c1)),
        CASE WHEN dbo.fn_discount_amount(2, 35.00, @c1) = 4.00 THEN 1 ELSE 0 END);

/* 16 边界：折扣不超过订单金额 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·3 元单 + 5 元券 → 3.00（不超过订单金额）', N'3.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(NULL, 3.00, @c1)),
        CASE WHEN dbo.fn_discount_amount(NULL, 3.00, @c1) = 3.00 THEN 1 ELSE 0 END);

/* 17 */ INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·金额 NULL → 0.00', N'0.00',
        ISNULL(CONVERT(NVARCHAR(60), dbo.fn_discount_amount(NULL, NULL, NULL)), N'NULL'),
        CASE WHEN ISNULL(dbo.fn_discount_amount(NULL, NULL, NULL), 0.00) = 0.00 THEN 1 ELSE 0 END);

/* 18 */ INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·负金额 → 0.00', N'0.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(NULL, -5.00, NULL)),
        CASE WHEN dbo.fn_discount_amount(NULL, -5.00, NULL) = 0.00 THEN 1 ELSE 0 END);

/* 19 */ INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·券编号 99999 → 按无券 8.00', N'8.00',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(NULL, 55.00, 99999)),
        CASE WHEN dbo.fn_discount_amount(NULL, 55.00, 99999) = 8.00 THEN 1 ELSE 0 END);

/* 20 重复调用 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'折扣·重复调用结果一致',
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(1, 55.00, @c2)),
        CONVERT(NVARCHAR(60), dbo.fn_discount_amount(1, 55.00, @c2)),
        CASE WHEN dbo.fn_discount_amount(1, 55.00, @c2) = dbo.fn_discount_amount(1, 55.00, @c2) THEN 1 ELSE 0 END);

ROLLBACK TRANSACTION;

/* 21 未写脏数据：券表行数不变 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'未写脏数据·券表行数回滚后不变',
        CONVERT(NVARCHAR(60), @coupon_before),
        CONVERT(NVARCHAR(60), (SELECT COUNT(*) FROM dbo.tbl_coupon)),
        CASE WHEN (SELECT COUNT(*) FROM dbo.tbl_coupon) = @coupon_before THEN 1 ELSE 0 END);

/* 22 未写脏数据：原料结存不变 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'未写脏数据·布丁粉结存回滚后不变',
        CONVERT(NVARCHAR(60), @qty19_before),
        CONVERT(NVARCHAR(60), (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 19)),
        CASE WHEN (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 19) = @qty19_before
             THEN 1 ELSE 0 END);

/* ================= 汇总 ================= */
SELECT  seq,
        item                                         AS [用例],
        expected                                     AS [预期],
        actual                                       AS [实际],
        CASE ok WHEN 1 THEN N'PASS' ELSE N'FAIL' END AS [结果]
FROM    @r
ORDER BY seq;

DECLARE @pass INT, @fail INT, @total INT, @msg NVARCHAR(200), @msg2 NVARCHAR(200);

SELECT  @pass = SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END),
        @fail = SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END)
FROM    @r;

SET @total = @pass + @fail;

PRINT N'============================================================';
PRINT N'【函数测试总览】用例数: ' + CAST(@total AS NVARCHAR(10))
    + N' | 通过: ' + CAST(@pass AS NVARCHAR(10))
    + N' | 失败: ' + CAST(@fail AS NVARCHAR(10));
PRINT N'============================================================';

IF @total <> 22
BEGIN
    SET @msg2 = N'【函数测试】用例数应为 22，实际 ' + CAST(@total AS NVARCHAR(10))
              + N' 条 —— 有用例没跑，按失败处理。';
    RAISERROR(@msg2, 16, 1);
END
ELSE IF @fail > 0
BEGIN
    SET @msg = N'【函数测试】有 ' + CAST(@fail AS NVARCHAR(10)) + N' 条用例失败。';
    RAISERROR(@msg, 16, 1);
END
ELSE
    PRINT N'【函数测试结论】22 条用例全部通过。';
GO
