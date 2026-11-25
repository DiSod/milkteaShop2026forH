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
 * R3. 品类树展开：沿 parent_category_id 递归
 * ----------------------------------------------------------------
 * 当前库里 5 个分类的 parent_category_id 全是 NULL，所以展开出来只有一层 5 行。
 * 这不是写错了 —— 是数据还没有层级。只要以后给某个分类挂上父级，
 * 同一段 SQL 不用改就会多出第 2、3 层（层级深度 = lvl）。
 * 顺带演示两件递归必须处理的事：深度标记、以及用 MAXRECURSION 防跑飞。
 * ================================================================ */
PRINT N'=== R3. 品类树展开（当前数据只有一层）===';

WITH 品类树 AS (
    SELECT c.category_id, c.category_code, c.category_name,
           c.parent_category_id,
           0 AS 层级,
           CAST(c.category_name AS NVARCHAR(400)) AS 路径
      FROM tbl_product_category c
     WHERE c.parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_code, c.category_name,
           c.parent_category_id,
           父.层级 + 1,
           CAST(父.路径 + N' > ' + c.category_name AS NVARCHAR(400))
      FROM tbl_product_category c
      JOIN 品类树 父 ON 父.category_id = c.parent_category_id
)
SELECT category_id, category_code, category_name, 层级, 路径
  FROM 品类树
 ORDER BY 路径
OPTION (MAXRECURSION 100);

PRINT N'【递归结论】日期轴按天连续（含无营业日）、断档可识别、品类树按父级展开 —— 三处都是递归，两处现在就有业务含义。';
GO
