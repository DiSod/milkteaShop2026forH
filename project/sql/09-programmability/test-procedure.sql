/* ============================================================
   脚本：test-procedure.sql
   用途：第 10 周 —— 两个存储过程的正反例（预期 / 实际 / PASS｜FAIL）
   设计要点：
   1) 错误用例用 TRY/CATCH 捕获 ERROR_NUMBER()，断言"错误号对不对"，
      而不是只看"有没有报错"（报错内容对了、号不对也是问题）
   2) 写库用例真的写，然后**清理并复核**：删掉本次新增的流水、按 Σ流水
      重算结存，最后断言"结存与流水行数回到测试前" —— 这就是作业要的
      "未写入不完整数据的验证"
   3) 用例总数固定 20，漏跑判红
   退出码：任一 FAIL → RAISERROR 16 → 配合 sqlcmd -b 非零退出
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

DECLARE @code INT, @m NVARCHAR(400);

/* ============ 一、usp_sales_report（只读，不写库） ============ */

/* 1 正常：9/18–9/23 —— 订单数与金额用独立查询重算后比对 */
DECLARE @o INT, @a DECIMAL(12,2), @po INT, @pa DECIMAL(12,2), @pc DECIMAL(12,3);

SELECT @o = COUNT(*), @a = ISNULL(SUM(h.amount_paid),0)
FROM dbo.tbl_order_header h
WHERE h.pay_status='SUCCESS' AND h.order_status<>'CANCELLED'
  AND h.business_date BETWEEN '2026-09-18' AND '2026-09-23';

CREATE TABLE #rep (开始日期 DATE, 结束日期 DATE, 订单数 INT, 销售数量 DECIMAL(12,3),
                   销售金额 DECIMAL(12,2), 会员单数 INT, 客单价 DECIMAL(10,2));
INSERT INTO #rep EXEC dbo.usp_sales_report '2026-09-18', '2026-09-23';

SELECT @po = 订单数, @pa = 销售金额, @pc = 销售数量 FROM #rep;

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售统计·订单数（与独立查询一致）', CONVERT(NVARCHAR(60), @o),
        CONVERT(NVARCHAR(60), @po), CASE WHEN @po = @o THEN 1 ELSE 0 END);

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售统计·销售金额（与独立查询一致）', CONVERT(NVARCHAR(60), @a),
        CONVERT(NVARCHAR(60), @pa), CASE WHEN @pa = @a THEN 1 ELSE 0 END);

/* 3 正常：销售数量（杯数）与独立查询一致 */
DECLARE @cups DECIMAL(12,3);

SELECT @cups = ISNULL(SUM(d.qty), 0)
FROM dbo.tbl_order_detail d JOIN dbo.tbl_order_header h ON h.order_id = d.order_id
WHERE h.pay_status='SUCCESS' AND h.order_status<>'CANCELLED'
  AND h.business_date BETWEEN '2026-09-18' AND '2026-09-23';

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售统计·销售数量（与独立查询一致）', CONVERT(NVARCHAR(60), @cups),
        CONVERT(NVARCHAR(60), @pc), CASE WHEN @pc = @cups THEN 1 ELSE 0 END);

/* 4 反例：参数 NULL → 51401 */
BEGIN TRY
    EXEC dbo.usp_sales_report NULL, '2026-09-23';
    SET @code = 0;
END TRY
BEGIN CATCH
    SET @code = ERROR_NUMBER();
END CATCH
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售统计·参数 NULL → 51401', N'51401', CONVERT(NVARCHAR(60), @code),
        CASE WHEN @code = 51401 THEN 1 ELSE 0 END);

/* 4 反例：起止颠倒 → 51402 */
BEGIN TRY
    EXEC dbo.usp_sales_report '2026-09-23', '2026-09-18';
    SET @code = 0;
END TRY
BEGIN CATCH
    SET @code = ERROR_NUMBER();
END CATCH
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售统计·起止颠倒 → 51402', N'51402', CONVERT(NVARCHAR(60), @code),
        CASE WHEN @code = 51402 THEN 1 ELSE 0 END);

/* 5 反例：跨度超过 366 天 → 51403 */
BEGIN TRY
    EXEC dbo.usp_sales_report '2024-01-01', '2026-09-23';
    SET @code = 0;
END TRY
BEGIN CATCH
    SET @code = ERROR_NUMBER();
END CATCH
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售统计·跨度 >366 天 → 51403', N'51403', CONVERT(NVARCHAR(60), @code),
        CASE WHEN @code = 51403 THEN 1 ELSE 0 END);

/* 6 边界：无记录区间 → 汇总仍一行、数字全 0 */
DELETE FROM #rep;
INSERT INTO #rep EXEC dbo.usp_sales_report '2020-01-01', '2020-01-02';
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'销售统计·无记录区间 → 一行且订单数 0', N'1|0',
        CONVERT(NVARCHAR(10), (SELECT COUNT(*) FROM #rep)) + N'|'
        + CONVERT(NVARCHAR(10), ISNULL((SELECT 订单数 FROM #rep), -1)),
        CASE WHEN (SELECT COUNT(*) FROM #rep) = 1 AND ISNULL((SELECT 订单数 FROM #rep), -1) = 0
             THEN 1 ELSE 0 END);

DROP TABLE #rep;

/* ============ 二、usp_stock_adjust（写库，最后清理） ============ */

DECLARE @qty_before   DECIMAL(12,3) = (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1),
        @ledger_before INT           = (SELECT COUNT(*) FROM dbo.tbl_stock_ledger),
        @ledger_max    INT           = ISNULL((SELECT MAX(ledger_id) FROM dbo.tbl_stock_ledger), 0),
        @qty_now       DECIMAL(12,3);

/* 7 正常：出库 -1.5 g（红茶 I001，操作员 5 = 陈静） */
DECLARE @res TABLE (原料编号 INT, 调整前结存 DECIMAL(12,3), 调整量 DECIMAL(12,3),
                    调整后结存 DECIMAL(12,3), 流水类型 VARCHAR(20), 流水号 INT);
INSERT INTO @res EXEC dbo.usp_stock_adjust 1, -1.5, N'第10周测试：出库', 5;

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·出库 -1.5 → 结存减 1.5', CONVERT(NVARCHAR(60), @qty_before - 1.5),
        CONVERT(NVARCHAR(60), (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1)),
        CASE WHEN (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1) = @qty_before - 1.5
             THEN 1 ELSE 0 END);

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·出库流水类型 = LOSS/MANUAL', N'LOSS|MANUAL',
        ISNULL((SELECT TOP 1 ledger_type + N'|' + ref_type FROM dbo.tbl_stock_ledger
                WHERE ledger_id = (SELECT TOP 1 流水号 FROM @res)), N'NULL'),
        CASE WHEN EXISTS (SELECT 1 FROM dbo.tbl_stock_ledger
                          WHERE ledger_id = (SELECT TOP 1 流水号 FROM @res)
                            AND ledger_type = 'LOSS' AND ref_type = 'MANUAL') THEN 1 ELSE 0 END);

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·原因写入 remark', N'第10周测试：出库',
        ISNULL((SELECT TOP 1 remark FROM dbo.tbl_stock_ledger
                WHERE ledger_id = (SELECT TOP 1 流水号 FROM @res)), N'NULL'),
        CASE WHEN (SELECT TOP 1 remark FROM dbo.tbl_stock_ledger
                   WHERE ledger_id = (SELECT TOP 1 流水号 FROM @res)) = N'第10周测试：出库'
             THEN 1 ELSE 0 END);

/* 8 正常：入库 +500 → PURCHASE_IN */
INSERT INTO @res EXEC dbo.usp_stock_adjust 1, 500, N'第10周测试：入库', 5;

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·入库 +500 → 结存加 500', CONVERT(NVARCHAR(60), @qty_before + 498.5),
        CONVERT(NVARCHAR(60), (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1)),
        CASE WHEN (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1) = @qty_before + 498.5
             THEN 1 ELSE 0 END);

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·入库流水类型 = PURCHASE_IN/MANUAL', N'PURCHASE_IN|MANUAL',
        ISNULL((SELECT TOP 1 ledger_type + N'|' + ref_type FROM dbo.tbl_stock_ledger
                WHERE ledger_id = (SELECT TOP 1 流水号 FROM @res ORDER BY 流水号 DESC)), N'NULL'),
        CASE WHEN EXISTS (SELECT 1 FROM dbo.tbl_stock_ledger
                          WHERE ledger_id = (SELECT TOP 1 流水号 FROM @res ORDER BY 流水号 DESC)
                            AND ledger_type = 'PURCHASE_IN' AND ref_type = 'MANUAL') THEN 1 ELSE 0 END);

/* 9 反例：数量 0 → 51412 */
BEGIN TRY EXEC dbo.usp_stock_adjust 1, 0, N'x', 5; SET @code = 0;
END TRY BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·数量 0 → 51412', N'51412', CONVERT(NVARCHAR(60), @code),
        CASE WHEN @code = 51412 THEN 1 ELSE 0 END);

/* 10 反例：原因为空 → 51413 */
BEGIN TRY EXEC dbo.usp_stock_adjust 1, -1, N'   ', 5; SET @code = 0;
END TRY BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·原因为空白 → 51413', N'51413', CONVERT(NVARCHAR(60), @code),
        CASE WHEN @code = 51413 THEN 1 ELSE 0 END);

/* 11 反例：原料不存在 → 51411 */
BEGIN TRY EXEC dbo.usp_stock_adjust 99999, -1, N'x', 5; SET @code = 0;
END TRY BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·原料不存在 → 51411', N'51411', CONVERT(NVARCHAR(60), @code),
        CASE WHEN @code = 51411 THEN 1 ELSE 0 END);

/* 12 反例：操作员不存在 → 51416 */
BEGIN TRY EXEC dbo.usp_stock_adjust 1, -1, N'x', 99999; SET @code = 0;
END TRY BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·操作员不存在 → 51416', N'51416', CONVERT(NVARCHAR(60), @code),
        CASE WHEN @code = 51416 THEN 1 ELSE 0 END);

/* 13 反例：超结存 → 51415，且结存不变 */
SET @qty_now = (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1);
BEGIN TRY EXEC dbo.usp_stock_adjust 1, -99999999, N'x', 5; SET @code = 0;
END TRY BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·超结存 → 51415', N'51415', CONVERT(NVARCHAR(60), @code),
        CASE WHEN @code = 51415 THEN 1 ELSE 0 END);

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·超结存被拒后结存未变', CONVERT(NVARCHAR(60), @qty_now),
        CONVERT(NVARCHAR(60), (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1)),
        CASE WHEN (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1) = @qty_now
             THEN 1 ELSE 0 END);

/* 14 重复调用：同参数再出库一次，再留一条流水、不再报错 */
INSERT INTO @res EXEC dbo.usp_stock_adjust 1, -1, N'第10周测试：重复调用', 5;
INSERT INTO @res EXEC dbo.usp_stock_adjust 1, -1, N'第10周测试：重复调用', 5;

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·重复调用两次 → 结存再减 2（不报错）',
        CONVERT(NVARCHAR(60), @qty_now - 2),
        CONVERT(NVARCHAR(60), (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1)),
        CASE WHEN (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1) = @qty_now - 2
             THEN 1 ELSE 0 END);

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'库存调整·本次共写 4 条流水', N'4',
        CONVERT(NVARCHAR(60), (SELECT COUNT(*) FROM dbo.tbl_stock_ledger WHERE ledger_id > @ledger_max)),
        CASE WHEN (SELECT COUNT(*) FROM dbo.tbl_stock_ledger WHERE ledger_id > @ledger_max) = 4
             THEN 1 ELSE 0 END);

/* ---------- 清理：删掉本次新增流水，按 Σ流水 重算结存 ---------- */
DELETE FROM dbo.tbl_stock_ledger WHERE ledger_id > @ledger_max;

UPDATE i
SET    i.qty_on_hand = ISNULL(f.flow_total, 0)
FROM   dbo.tbl_ingredient AS i
LEFT JOIN (SELECT ingredient_id, SUM(qty) AS flow_total
           FROM dbo.tbl_stock_ledger GROUP BY ingredient_id) AS f
       ON f.ingredient_id = i.ingredient_id
WHERE  i.ingredient_id = 1;

/* 15 未写脏数据：清理后结存回到测试前 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'未写脏数据·清理后结存 = 测试前', CONVERT(NVARCHAR(60), @qty_before),
        CONVERT(NVARCHAR(60), (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1)),
        CASE WHEN (SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1) = @qty_before
             THEN 1 ELSE 0 END);

/* 16 未写脏数据：流水行数回到测试前 */
INSERT INTO @r (item, expected, actual, ok)
VALUES (N'未写脏数据·流水行数 = 测试前', CONVERT(NVARCHAR(60), @ledger_before),
        CONVERT(NVARCHAR(60), (SELECT COUNT(*) FROM dbo.tbl_stock_ledger)),
        CASE WHEN (SELECT COUNT(*) FROM dbo.tbl_stock_ledger) = @ledger_before THEN 1 ELSE 0 END);

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
PRINT N'【过程测试总览】用例数: ' + CAST(@total AS NVARCHAR(10))
    + N' | 通过: ' + CAST(@pass AS NVARCHAR(10))
    + N' | 失败: ' + CAST(@fail AS NVARCHAR(10));
PRINT N'============================================================';

IF @total <> 22
BEGIN
    SET @msg2 = N'【过程测试】用例数应为 22，实际 ' + CAST(@total AS NVARCHAR(10)) + N' 条 —— 有用例没跑，按失败处理。';
    RAISERROR(@msg2, 16, 1);
END
ELSE IF @fail > 0
BEGIN
    SET @msg = N'【过程测试】有 ' + CAST(@fail AS NVARCHAR(10)) + N' 条用例失败。';
    RAISERROR(@msg, 16, 1);
END
ELSE
    PRINT N'【过程测试结论】22 条用例全部通过。';
GO
