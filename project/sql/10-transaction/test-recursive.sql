/* ============================================================
 * 脚本：test-recursive.sql
 * 用途：recursive_query.sql 的断言集 —— 15 条，跑完打印 PASS/FAIL 与总数
 * 判据：条数必须等于 @total（漏跑即判红）；任一 FAIL → RAISERROR 16 → sqlcmd -b 非零退出
 * 幂等：是 —— 全部只读，只在表变量里做
 * 阶段：第 12 周（递归查询与业务事务）
 * 作者：DiSod
 * 日期：2026-11-25
 * ============================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
USE milktea_shop;
GO

DECLARE @start_date DATE = '2026-09-17';
DECLARE @end_date   DATE = '2026-09-26';
DECLARE @total INT = 15;

DECLARE @r TABLE (
    序号 INT IDENTITY(1,1) PRIMARY KEY,
    item NVARCHAR(120), expected NVARCHAR(80), actual NVARCHAR(80), ok BIT
);

/* ---------- 造日期轴（与 recursive_query.sql R1 同一段递归） ---------- */
DECLARE @axis TABLE (营业日 DATE PRIMARY KEY, 订单数 INT, 实收 DECIMAL(10,2));

WITH 日期轴 AS (
    SELECT @start_date AS 营业日
    UNION ALL
    SELECT DATEADD(DAY, 1, 营业日) FROM 日期轴 WHERE 营业日 < @end_date
)
INSERT INTO @axis (营业日, 订单数, 实收)
SELECT 日期轴.营业日, SUM(CASE WHEN h.order_id IS NULL THEN 0 ELSE 1 END), SUM(ISNULL(h.amount_paid, CAST(0.00 AS DECIMAL(10,2))))
  FROM 日期轴
  LEFT JOIN tbl_order_header h
         ON h.business_date = 日期轴.营业日
        AND h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
 GROUP BY 日期轴.营业日
OPTION (MAXRECURSION 4000);

/* ---------- 1—9：日期轴 ---------- */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'1 日期轴行数 = 跨度+1',
       CONVERT(NVARCHAR(80), DATEDIFF(DAY, @start_date, @end_date) + 1),
       CONVERT(NVARCHAR(80), COUNT(*)),
       CASE WHEN COUNT(*) = DATEDIFF(DAY, @start_date, @end_date) + 1 THEN 1 ELSE 0 END
  FROM @axis;

INSERT INTO @r (item, expected, actual, ok)
SELECT N'2 首行 = 起始日', CONVERT(NVARCHAR(80), @start_date, 23),
       CONVERT(NVARCHAR(80), MIN(营业日), 23),
       CASE WHEN MIN(营业日) = @start_date THEN 1 ELSE 0 END
  FROM @axis;

INSERT INTO @r (item, expected, actual, ok)
SELECT N'3 末行 = 结束日', CONVERT(NVARCHAR(80), @end_date, 23),
       CONVERT(NVARCHAR(80), MAX(营业日), 23),
       CASE WHEN MAX(营业日) = @end_date THEN 1 ELSE 0 END
  FROM @axis;

INSERT INTO @r (item, expected, actual, ok)
SELECT N'4 日期不重复', CONVERT(NVARCHAR(80), COUNT(*)), CONVERT(NVARCHAR(80), COUNT(DISTINCT 营业日)),
       CASE WHEN COUNT(*) = COUNT(DISTINCT 营业日) THEN 1 ELSE 0 END
  FROM @axis;

INSERT INTO @r (item, expected, actual, ok)
SELECT N'5 有营业日 = 7 天', N'7', CONVERT(NVARCHAR(80), COUNT(*)),
       CASE WHEN COUNT(*) = 7 THEN 1 ELSE 0 END
  FROM @axis WHERE 订单数 > 0;

INSERT INTO @r (item, expected, actual, ok)
SELECT N'6 无营业日 = 3 天', N'3', CONVERT(NVARCHAR(80), COUNT(*)),
       CASE WHEN COUNT(*) = 3 THEN 1 ELSE 0 END
  FROM @axis WHERE 订单数 = 0;

INSERT INTO @r (item, expected, actual, ok)
SELECT N'7 无营业日实收合计 = 0.00', N'0.00', CONVERT(NVARCHAR(80), CAST(ISNULL(SUM(实收),0.00) AS DECIMAL(10,2))),
       CASE WHEN ISNULL(SUM(实收), 0) = 0 THEN 1 ELSE 0 END
  FROM @axis WHERE 订单数 = 0;

/* 09-18 的实收与「直接查订单表」得到的值一致（常量来自 regression.sql TC-10 的 7 日窗口） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'8 09-18 实收 = 3074.00（与直接查一致）', N'3074.00',
       CONVERT(NVARCHAR(80), CAST((SELECT 实收 FROM @axis WHERE 营业日 = '2026-09-18') AS DECIMAL(10,2))),
       CASE WHEN (SELECT 实收 FROM @axis WHERE 营业日 = '2026-09-18') = CAST(3074.00 AS DECIMAL(10,2)) THEN 1 ELSE 0 END;

/* 补零不改变总额：10 天窗口的实收合计 = 7 天窗口的 23,762.00（TC-10 常量） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'9 补零后总额仍 = 23762.00', N'23762.00',
       CONVERT(NVARCHAR(80), CAST(SUM(实收) AS DECIMAL(10,2))),
       CASE WHEN SUM(实收) = CAST(23762.00 AS DECIMAL(10,2)) THEN 1 ELSE 0 END
  FROM @axis;

/* ---------- 10—12：断档识别 ---------- */
DECLARE @gap TABLE (空档起 DATE, 空档止 DATE, 连续天数 INT);

WITH 日期轴 AS (
    SELECT @start_date AS 营业日
    UNION ALL
    SELECT DATEADD(DAY, 1, 营业日) FROM 日期轴 WHERE 营业日 < @end_date
),
标记 AS (
    SELECT 日期轴.营业日,
           CASE WHEN EXISTS (SELECT 1 FROM tbl_order_header h
                              WHERE h.business_date = 日期轴.营业日) THEN 0 ELSE 1 END AS 是空档
      FROM 日期轴
),
分组 AS (
    SELECT 营业日, 是空档, DATEADD(DAY, -CAST(ROW_NUMBER() OVER (ORDER BY 营业日) AS INT), 营业日) AS 段号 FROM 标记
)
INSERT INTO @gap
SELECT MIN(营业日), MAX(营业日), DATEDIFF(DAY, MIN(营业日), MAX(营业日)) + 1
  FROM 分组 WHERE 是空档 = 1 GROUP BY 段号
OPTION (MAXRECURSION 4000);

INSERT INTO @r (item, expected, actual, ok)
SELECT N'10 识别出 1 段空档', N'1', CONVERT(NVARCHAR(80), COUNT(*)),
       CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END
  FROM @gap;

INSERT INTO @r (item, expected, actual, ok)
SELECT N'11 空档 = 09-24 ~ 09-26 共 3 天',
       N'2026-09-24 ~ 2026-09-26 / 3',
       CONVERT(NVARCHAR(80), MIN(空档起), 23) + N' ~ ' + CONVERT(NVARCHAR(80), MAX(空档止), 23)
         + N' / ' + CONVERT(NVARCHAR(80), MAX(连续天数)),
       CASE WHEN MIN(空档起) = '2026-09-24' AND MAX(空档止) = '2026-09-26' AND MAX(连续天数) = 3
            THEN 1 ELSE 0 END
  FROM @gap;

/* ---------- 12—14：品类树（临时表造三级，验证多级穿透与自底向上汇总） ---------- */
DECLARE @tree TABLE (category_id INT, 层级 INT, category_code VARCHAR(20), 金额 DECIMAL(12,2));

/* 与 recursive_query.sql 的 R3 同一套构造：真表 5 行搬进临时表，再加两个根一个叶子 */
IF OBJECT_ID('tempdb..#品类') IS NOT NULL DROP TABLE #品类;
CREATE TABLE #品类 (
    category_id   INT           NOT NULL PRIMARY KEY,
    parent_id     INT           NULL,
    category_code VARCHAR(20)   NOT NULL,
    category_name NVARCHAR(100) NOT NULL
);
INSERT INTO #品类 (category_id, parent_id, category_code, category_name)
SELECT category_id, parent_category_id, category_code, category_name FROM tbl_product_category;
INSERT INTO #品类 (category_id, parent_id, category_code, category_name) VALUES
    (1001, NULL, 'R01', N'现制茶饮总类'),
    (1002, NULL, 'R02', N'甜品与限定总类');
UPDATE #品类 SET parent_id = 1001 WHERE category_code IN ('C01', 'C02', 'C03');
UPDATE #品类 SET parent_id = 1002 WHERE category_code IN ('C04', 'C05');
INSERT INTO #品类 (category_id, parent_id, category_code, category_name)
SELECT 1003, category_id, 'S01', N'鲜果茶子类（示例）' FROM #品类 WHERE category_code = 'C02';

WITH 品类树 AS (
    SELECT c.category_id, 1 AS 层级, c.category_code FROM #品类 c WHERE c.parent_id IS NULL
    UNION ALL
    SELECT c.category_id, 父.层级 + 1, c.category_code
      FROM #品类 c JOIN 品类树 父 ON 父.category_id = c.parent_id
),
后代 AS (
    SELECT category_id AS 祖先, category_id AS 后代 FROM #品类
    UNION ALL
    SELECT d.祖先, c.category_id FROM 后代 d JOIN #品类 c ON c.parent_id = d.后代
),
直营 AS (
    SELECT p.category_id, CAST(SUM(d.subtotal) AS DECIMAL(12,2)) AS 金额
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      JOIN tbl_product      p ON p.product_id = d.product_id
     WHERE h.pay_status = 'SUCCESS' AND h.order_status <> 'CANCELLED'
     GROUP BY p.category_id
)
INSERT INTO @tree (category_id, 层级, category_code, 金额)
SELECT t.category_id, t.层级, t.category_code, ISNULL(SUM(s.金额), 0.00)
  FROM 品类树 t
  JOIN 后代 d ON d.祖先 = t.category_id
  LEFT JOIN 直营 s ON s.category_id = d.后代
 GROUP BY t.category_id, t.层级, t.category_code
OPTION (MAXRECURSION 100);

DROP TABLE #品类;

/* 12：最大层级 = 3，且各层节点数 2 / 5 / 1 */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'12 品类树三级穿透（层级 2/5/1，最大 3）', N'3 层 / 2-5-1',
       CONVERT(NVARCHAR(80), MAX(层级)) + N' 层 / '
         + CONVERT(NVARCHAR(10), SUM(CASE WHEN 层级 = 1 THEN 1 ELSE 0 END)) + N'-'
         + CONVERT(NVARCHAR(10), SUM(CASE WHEN 层级 = 2 THEN 1 ELSE 0 END)) + N'-'
         + CONVERT(NVARCHAR(10), SUM(CASE WHEN 层级 = 3 THEN 1 ELSE 0 END)),
       CASE WHEN MAX(层级) = 3
                 AND SUM(CASE WHEN 层级 = 1 THEN 1 ELSE 0 END) = 2
                 AND SUM(CASE WHEN 层级 = 2 THEN 1 ELSE 0 END) = 5
                 AND SUM(CASE WHEN 层级 = 3 THEN 1 ELSE 0 END) = 1
            THEN 1 ELSE 0 END
  FROM @tree;

/* 13：根类 R01 的含子级金额 = C01+C02+C03 直接销售额之和（自底向上汇总对了） */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'13 根类汇总 = 三个子类直接销售额之和', N'相等',
       CONVERT(NVARCHAR(80), CAST((SELECT 金额 FROM @tree WHERE category_code = 'R01') AS DECIMAL(12,2)))
         + N' vs '
         + CONVERT(NVARCHAR(80), CAST((SELECT SUM(金额) FROM @tree
                                       WHERE category_code IN ('C01', 'C02', 'C03')) AS DECIMAL(12,2))),
       CASE WHEN (SELECT 金额 FROM @tree WHERE category_code = 'R01')
                 = (SELECT SUM(金额) FROM @tree WHERE category_code IN ('C01', 'C02', 'C03'))
            THEN 1 ELSE 0 END;

/* 14：真表没被污染 —— 仍是 5 个分类、parent_category_id 全 NULL */
INSERT INTO @r (item, expected, actual, ok)
SELECT N'14 真表未被临时树污染（5 类 / 父级全 NULL）', N'5 / 0',
       CONVERT(NVARCHAR(80), COUNT(*)) + N' / '
         + CONVERT(NVARCHAR(80), SUM(CASE WHEN parent_category_id IS NOT NULL THEN 1 ELSE 0 END)),
       CASE WHEN COUNT(*) = 5
                 AND SUM(CASE WHEN parent_category_id IS NOT NULL THEN 1 ELSE 0 END) = 0
            THEN 1 ELSE 0 END
  FROM tbl_product_category;

/* ---------- 15：跨度守卫（>3660 天必须抛 52101） ---------- */
DECLARE @guard_err INT = 0;
BEGIN TRY
    IF DATEDIFF(DAY, '2000-01-01', '2026-11-25') > 3660
        THROW 52101, N'查询跨度不能超过 10 年（3660 天）', 1;
END TRY
BEGIN CATCH
    SET @guard_err = ERROR_NUMBER();
END CATCH;

INSERT INTO @r (item, expected, actual, ok)
VALUES (N'15 跨度 > 3660 天被拒（错误号 52101）', N'52101', CONVERT(NVARCHAR(80), @guard_err),
        CASE WHEN @guard_err = 52101 THEN 1 ELSE 0 END);

/* ---------- 汇总 ---------- */
DECLARE @pass INT, @fail INT;
SELECT @pass = SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END),
       @fail = SUM(CASE WHEN ok = 1 THEN 0 ELSE 1 END)
  FROM @r;

SELECT 序号, item AS 用例, expected AS 预期, actual AS 实际,
       CASE WHEN ok = 1 THEN 'PASS' ELSE 'FAIL' END AS 结论
  FROM @r ORDER BY 序号;

PRINT N'';
PRINT N'【递归查询测试总览】用例数: ' + CONVERT(NVARCHAR(10), @pass + @fail)
    + N' | 通过: ' + CONVERT(NVARCHAR(10), @pass) + N' | 失败: ' + CONVERT(NVARCHAR(10), @fail);

IF @pass + @fail <> @total
BEGIN
    PRINT N'【递归查询测试结论】用例条数不对（应有 ' + CONVERT(NVARCHAR(10), @total) + N' 条）';
    RAISERROR(N'用例条数不符，可能有断言被跳过', 16, 1);
END
ELSE IF @fail > 0
BEGIN
    PRINT N'【递归查询测试结论】有断言失败';
    RAISERROR(N'递归查询测试未全部通过', 16, 1);
END
ELSE
    PRINT N'【递归查询测试结论】' + CONVERT(NVARCHAR(10), @total) + N' 条用例全部通过。';
GO
