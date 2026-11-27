/* ============================================================
 * 脚本：recursive_query.sql
 * 用途：第 12 周「递归查询」—— 三处真用得上的递归 CTE
 *       R1 日期轴补零：把「没有营业的日子」补成 0，而不是让图断掉
 *       R2 断档识别：找出连续无营业日的区间（哪几天没做生意）
 *       R3 品类树展开：递归沿 parent_category_id 向下展开（当前数据只有一层，语法就绪）
 * 依赖：18 表 v1.0 结构
 * 阶段：第 12 周（递归查询与业务事务）
 * 作者：DiSod
 * 日期：2026-11-25
 * 幂等：是 —— 全部只读，不写任何表
 * ============================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
USE milktea_shop;
GO

/* ================================================================
 * R1. 日期轴补零：递归生成连续日期，左连接日销
 * ----------------------------------------------------------------
 * 为什么要递归：日期不是表里的数据，缺的那几天连行都没有，
 * 单纯 GROUP BY 只会返回「有单的日子」，图就从 09-23 直接跳到 11-08。
 * 递归先造一把「尺子」，再把事实表贴上去。
 * ================================================================ */
PRINT N'=== R1. 日期轴补零（把没营业的日子补成 0）===';

DECLARE @start_date DATE = '2026-09-17';
DECLARE @end_date   DATE = '2026-09-26';   -- 故意跨过种子最后一天，制造 3 天空档

IF @start_date IS NULL OR @end_date IS NULL
    THROW 52101, N'起止日期不能为空', 1;
IF @start_date > @end_date
    THROW 52102, N'起始日期不能晚于结束日期', 1;
IF DATEDIFF(DAY, @start_date, @end_date) > 3660
    THROW 52103, N'查询跨度不能超过 10 年（3660 天）', 1;

WITH 日期轴 AS (
    SELECT @start_date AS 营业日
    UNION ALL
    SELECT DATEADD(DAY, 1, 营业日)
      FROM 日期轴
     WHERE 营业日 < @end_date
)
SELECT 日期轴.营业日,
       SUM(CASE WHEN h.order_id IS NULL THEN 0 ELSE 1 END)                                        AS 订单数,
       SUM(ISNULL(h.amount_paid, CAST(0.00 AS DECIMAL(10,2))))  AS 实收,
       CASE WHEN SUM(CASE WHEN h.order_id IS NULL THEN 0 ELSE 1 END) = 0 THEN N'无营业' ELSE N'' END AS 备注
  FROM 日期轴
  LEFT JOIN tbl_order_header h
         ON h.business_date = 日期轴.营业日
        AND h.pay_status = 'SUCCESS'          -- D 口径：只算成功支付的
        AND h.order_status <> 'CANCELLED'     -- 且不含已取消
 GROUP BY 日期轴.营业日
 ORDER BY 日期轴.营业日
OPTION (MAXRECURSION 4000);

/* ================================================================
 * R2. 断档识别：连续无营业日的区间（gaps & islands）
 * ----------------------------------------------------------------
 * 同一把日期轴，先标出「这天有没有单」，再用
 * `营业日 - ROW_NUMBER()` 把连续段归到同一个常量（经典分组技巧），
 * 最后按这个常量分组，就得到每段的起止。
 * ================================================================ */
PRINT N'=== R2. 断档识别（连续无营业日的区间）===';

WITH 日期轴 AS (
    SELECT @start_date AS 营业日
    UNION ALL
    SELECT DATEADD(DAY, 1, 营业日)
      FROM 日期轴
     WHERE 营业日 < @end_date
),
标记 AS (
    SELECT 日期轴.营业日,
           CASE WHEN EXISTS (SELECT 1 FROM tbl_order_header h
                              WHERE h.business_date = 日期轴.营业日) THEN 0 ELSE 1 END AS 是空档
      FROM 日期轴
),
分组 AS (
    SELECT 营业日, 是空档,
           DATEADD(DAY, -CAST(ROW_NUMBER() OVER (ORDER BY 营业日) AS INT), 营业日) AS 段号
      FROM 标记
)
SELECT MIN(营业日) AS 空档起, MAX(营业日) AS 空档止,
       DATEDIFF(DAY, MIN(营业日), MAX(营业日)) + 1 AS 连续天数
  FROM 分组
 WHERE 是空档 = 1
 GROUP BY 段号
 ORDER BY 空档起
OPTION (MAXRECURSION 4000);

/* ================================================================
 * R3. 品类树展开：沿 parent_category_id 递归（三级 + 自底向上汇总）
 * ----------------------------------------------------------------
 * 库里 5 个分类的 parent_category_id 全是 NULL —— 真实数据是平的，
 * 直接递归只能出一层，证明不了多级穿透。
 *
 * 一开始想直接 INSERT 两个根类再 ROLLBACK，但那样会消耗 IDENTITY
 * （category_id 回滚不回退号），表里的号会跳号。所以改成：
 *   把真实 5 行搬进 #品类（临时表，用真实 category_id），
 *   再在临时表里加两个根（1001/1002）和一个叶子（1003），
 *   只改临时表里的父子关系 —— 真表一个字节都不动。
 *
 * 两段递归：
 *   ① 品类树：从根开始逐层展开，带层级与路径；
 *   ② 后代映射：每个节点 → 它自己 + 全部后代（自底向上汇总要用）。
 * 汇总口径与日报一致（D 口径），杯数取明细 qty。
 * ================================================================ */
PRINT N'=== R3. 品类树展开（临时表造三级，不动真表）===';

/* 真实 5 个分类搬进临时表（category_id 沿用真值） */
CREATE TABLE #品类 (
    category_id   INT           NOT NULL PRIMARY KEY,
    parent_id     INT           NULL,
    category_code VARCHAR(20)   NOT NULL,
    category_name NVARCHAR(100) NOT NULL
);

INSERT INTO #品类 (category_id, parent_id, category_code, category_name)
SELECT category_id, parent_category_id, category_code, category_name
  FROM tbl_product_category;

/* 临时表里加两个根，并把真实分类挂到根下 */
INSERT INTO #品类 (category_id, parent_id, category_code, category_name) VALUES
    (1001, NULL, 'R01', N'现制茶饮总类'),
    (1002, NULL, 'R02', N'甜品与限定总类');

UPDATE #品类 SET parent_id = 1001 WHERE category_code IN ('C01', 'C02', 'C03');
UPDATE #品类 SET parent_id = 1002 WHERE category_code IN ('C04', 'C05');

/* 再给「水果茶」挂一个叶子（父级 id 从表里查，不写死） */
INSERT INTO #品类 (category_id, parent_id, category_code, category_name)
SELECT 1003, category_id, 'S01', N'鲜果茶子类（示例）'
  FROM #品类 WHERE category_code = 'C02';

WITH 品类树 AS (
    SELECT c.category_id, c.category_code, c.category_name,
           c.parent_id,
           1 AS 层级,
           CAST(c.category_name AS NVARCHAR(400)) AS 路径
      FROM #品类 c
     WHERE c.parent_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_code, c.category_name,
           c.parent_id,
           父.层级 + 1,
           CAST(父.路径 + N' / ' + c.category_name AS NVARCHAR(400))
      FROM #品类 c
      JOIN 品类树 父 ON 父.category_id = c.parent_id
),
后代 AS (
    SELECT category_id AS 祖先, category_id AS 后代 FROM #品类
    UNION ALL
    SELECT d.祖先, c.category_id
      FROM 后代 d
      JOIN #品类 c ON c.parent_id = d.后代
),
直营 AS (
    SELECT p.category_id,
           SUM(d.qty)                        AS 杯数,
           CAST(SUM(d.subtotal) AS DECIMAL(12,2)) AS 金额
      FROM tbl_order_detail d
      JOIN tbl_order_header h ON h.order_id = d.order_id
      JOIN tbl_product      p ON p.product_id = d.product_id
     WHERE h.pay_status = 'SUCCESS'
       AND h.order_status <> 'CANCELLED'
     GROUP BY p.category_id
)
SELECT t.层级,
       t.category_code                             AS 品类编码,
       t.路径,
       ISNULL(SUM(s.杯数), 0)                      AS 含子级杯数,
       ISNULL(SUM(s.金额), 0.00)                   AS 含子级销售额
  FROM 品类树 t
  JOIN 后代   d ON d.祖先 = t.category_id
  LEFT JOIN 直营 s ON s.category_id = d.后代
 GROUP BY t.层级, t.category_code, t.路径
 ORDER BY t.路径
OPTION (MAXRECURSION 100);

DROP TABLE #品类;

PRINT N'【递归结论】日期轴按天连续（含无营业日）、断档可识别、品类树三级穿透且能自底向上汇总 —— 三处都是递归，三处都有业务含义。';
GO
