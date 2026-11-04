/* ============================================================
 * 脚本：migration-03-points-opening-ledger.sql
 * 用途：给积分台账补上「期初结转」这一类事实 ——
 *         ① 扩展 DOM-09 的取值域，新增 OPENING
 *         ② 放宽 ck_points_ledger_target，允许 OPENING 两端外键都为空
 *         ③ 回填 80 条期初流水
 *       改完之后业务规则 A4（points_balance = Σ point_change）重新成立。
 * 依赖：02-constraints/constraints.sql（tbl_points_ledger 与两条 CHECK 已存在）
 * 阶段：第 7 周（v1.0）—— 修补第 6 周迁移与造数脚本共同留下的台账缺口
 * 作者：DiSod
 * 日期：2026-11-04
 * 说明：可重复执行 —— 约束按名探测后重建；期初流水按「该会员是否已有
 *       OPENING 行」判重，重复执行不会重复插入，也不会重复计分。
 *
 * 为什么必须动约束而不能只补数据：
 *   tbl_points_ledger 原设计只认 EARN / REDEEM 两类事实。期初余额既没有
 *   订单可挂、也没有券可挂，落在原约束之外，所以数据层面根本无处安放。
 *   这与库存流水那边用 ref_type='OPENING' 记期初是同一个道理（DOM-05），
 *   积分这边当初漏了对应的类型。
 * ============================================================ */

USE milktea_shop;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT N'【迁移03】=== 积分台账期初结转（OPENING）===';
GO

BEGIN TRANSACTION;
BEGIN TRY

    /* ------------------------------------------------------------
     * 迁移前体检：有多少会员的余额与流水对不上
     * ------------------------------------------------------------ */
    DECLARE @gap_members_before INT, @gap_points_before INT;

    SELECT
        @gap_members_before = COUNT(*),
        @gap_points_before  = ISNULL(SUM(x.gap), 0)
    FROM (
        SELECT
            m.points_balance
              - ISNULL((SELECT SUM(p.point_change)
                        FROM tbl_points_ledger AS p
                        WHERE p.member_id = m.member_id), 0) AS gap
        FROM tbl_member AS m
    ) AS x
    WHERE x.gap <> 0;

    PRINT FORMATMESSAGE(N'【迁移03】迁移前：%d 位会员余额与流水不符，缺口合计 %d 分。',
                        @gap_members_before, @gap_points_before);

    /* ------------------------------------------------------------
     * 要素 1：扩展 DOM-09 取值域，新增 OPENING
     *   EARN    消费累积(+)
     *   REDEEM  兑换 / 退单扣减(−)
     *   OPENING 期初结转(+)  ← 本次新增，语义与库存流水的 ref_type='OPENING' 对齐
     * ------------------------------------------------------------ */
    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_points_ledger_point_type'
                 AND parent_object_id = OBJECT_ID(N'tbl_points_ledger'))
    BEGIN
        ALTER TABLE tbl_points_ledger DROP CONSTRAINT ck_points_ledger_point_type;
        PRINT N'【迁移03】已移除旧的 ck_points_ledger_point_type。';
    END;

    ALTER TABLE tbl_points_ledger WITH CHECK
        ADD CONSTRAINT ck_points_ledger_point_type
            CHECK (point_type IN ('EARN', 'REDEEM', 'OPENING'));

    PRINT N'【迁移03】已重建 ck_points_ledger_point_type —— 允许 EARN / REDEEM / OPENING。';

    /* ------------------------------------------------------------
     * 要素 2：放宽 ck_points_ledger_target，为 OPENING 开一条通路
     *   原约束：EARN 必挂订单；REDEEM 必挂券或订单。
     *   OPENING 的本质是「开账那天就已经存在的余额」，它不对应任何
     *   单据，因此两端外键必须都为空 —— 反过来也必须强制为空，
     *   否则期初行就能被拿来挂假单据。
     * ------------------------------------------------------------ */
    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = N'ck_points_ledger_target'
                 AND parent_object_id = OBJECT_ID(N'tbl_points_ledger'))
    BEGIN
        ALTER TABLE tbl_points_ledger DROP CONSTRAINT ck_points_ledger_target;
        PRINT N'【迁移03】已移除旧的 ck_points_ledger_target。';
    END;

    ALTER TABLE tbl_points_ledger WITH CHECK
        ADD CONSTRAINT ck_points_ledger_target
            CHECK (
                   (point_type = 'EARN'    AND order_id  IS NOT NULL)
                OR (point_type = 'REDEEM'  AND (coupon_id IS NOT NULL OR order_id IS NOT NULL))
                OR (point_type = 'OPENING' AND order_id IS NULL AND coupon_id IS NULL)
            );

    PRINT N'【迁移03】已重建 ck_points_ledger_target —— OPENING 强制两端外键为空。';

    /* ------------------------------------------------------------
     * 要素 3：回填期初流水
     *   金额取「当前余额 − 已有流水合计」，也就是缺口本身；
     *   时间取会员注册日 00:00，保证期初行早于该会员任何一笔消费积分，
     *   流水按时间排序时成因在前、结果在后。
     *   已存在 OPENING 行的会员直接跳过，所以重复执行无副作用。
     * ------------------------------------------------------------ */
    CREATE TABLE #opening_gap (
        member_id   INT       NOT NULL PRIMARY KEY,
        register_at DATETIME2 NOT NULL,
        gap         INT       NOT NULL
    );

    INSERT INTO #opening_gap (member_id, register_at, gap)
    SELECT
        g.member_id,
        g.register_at,
        g.gap
    FROM (
        SELECT
            m.member_id,
            CAST(m.register_date AS DATETIME2) AS register_at,
            m.points_balance
              - ISNULL((SELECT SUM(p.point_change)
                        FROM tbl_points_ledger AS p
                        WHERE p.member_id = m.member_id), 0) AS gap
        FROM tbl_member AS m
        WHERE NOT EXISTS (
            SELECT 1
            FROM tbl_points_ledger AS o
            WHERE o.member_id = m.member_id
              AND o.point_type = N'OPENING')
    ) AS g
    WHERE g.gap > 0;

    DECLARE @rows_to_insert INT;
    SET @rows_to_insert = @@ROWCOUNT;

    IF @rows_to_insert > 0
    BEGIN
        INSERT INTO tbl_points_ledger
            (member_id, point_type, point_change, order_id, coupon_id, change_time)
        SELECT
            member_id,
            N'OPENING',
            gap,
            NULL,
            NULL,
            register_at
        FROM #opening_gap;

        PRINT FORMATMESSAGE(N'【迁移03】已回填 %d 条期初流水。', @rows_to_insert);
    END
    ELSE
    BEGIN
        PRINT N'【迁移03】所有会员均已有期初行，本次跳过回填。';
    END;

    DROP TABLE #opening_gap;

    /* ------------------------------------------------------------
     * 自证：迁移后必须 0 缺口，否则整体回滚
     * ------------------------------------------------------------ */
    DECLARE @gap_members_after INT, @gap_points_after INT;

    SELECT
        @gap_members_after = COUNT(*),
        @gap_points_after  = ISNULL(SUM(x.gap), 0)
    FROM (
        SELECT
            m.points_balance
              - ISNULL((SELECT SUM(p.point_change)
                        FROM tbl_points_ledger AS p
                        WHERE p.member_id = m.member_id), 0) AS gap
        FROM tbl_member AS m
    ) AS x
    WHERE x.gap <> 0;

    IF @gap_members_after <> 0
    BEGIN
        PRINT FORMATMESSAGE(N'【迁移03】❌ 自证失败：迁移后仍有 %d 位会员对不上（缺口合计 %d 分）。',
                            @gap_members_after, @gap_points_after);
        THROW 51003, N'【迁移03】积分台账自证未通过，事务回滚。', 1;
    END;

    PRINT N'【迁移03】自证通过：全部会员 balance = Σ point_change（缺口 0）。';

    COMMIT TRANSACTION;
    PRINT N'【迁移03】事务提交成功。';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT N'【迁移03】❌ 执行失败，已回滚。';
    THROW;
END CATCH;
GO

/* ============================================================
 * 结果回显：让每次执行都能一眼看出台账是否自洽
 * ============================================================ */

PRINT N'【迁移03】积分台账覆盖情况：';

SELECT
    t.point_type                                    AS 类型,
    COUNT(*)                                        AS 条数,
    SUM(t.point_change)                             AS 变动合计
FROM tbl_points_ledger AS t
GROUP BY t.point_type
ORDER BY CASE t.point_type WHEN 'OPENING' THEN 1 WHEN 'EARN' THEN 2 ELSE 3 END;

PRINT N'【迁移03】对账结果（余额 vs 流水）：';

SELECT
    COUNT(*)                                                  AS 会员数,
    SUM(m.points_balance)                                     AS 余额合计,
    SUM(ISNULL(l.flow_total, 0))                              AS 流水合计,
    SUM(m.points_balance - ISNULL(l.flow_total, 0))           AS 缺口合计,
    SUM(CASE WHEN m.points_balance <> ISNULL(l.flow_total, 0)
             THEN 1 ELSE 0 END)                               AS 不符会员数
FROM tbl_member AS m
LEFT JOIN (
    SELECT member_id, SUM(point_change) AS flow_total
    FROM tbl_points_ledger
    GROUP BY member_id
) AS l ON l.member_id = m.member_id;

PRINT N'【迁移03】约束状态：';

SELECT
    cc.name         AS 约束名,
    cc.definition   AS 定义,
    cc.is_disabled  AS 已禁用
FROM sys.check_constraints AS cc
WHERE cc.parent_object_id = OBJECT_ID(N'tbl_points_ledger')
ORDER BY cc.name;
GO
