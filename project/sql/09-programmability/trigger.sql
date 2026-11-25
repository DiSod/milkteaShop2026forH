/* ============================================================
 * 脚本：trigger.sql
 * 用途：第 11 周 —— 4 个集合级触发器（流水不可篡改 / 规格类型校验 / 订单状态机守卫）
 * 依赖：01-schema / 02-constraints / 11-migration（18 张业务表就绪）
 * 阶段：第 11 周（触发器）
 * 作者：何争霖 (hezhlin5)
 * 日期：2026-11-25
 * 幂等：是（全部 CREATE OR ALTER TRIGGER，可重复执行）
 * ============================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE milktea_shop;
GO

/* ------------------------------------------------------------
 * 1. dbo.trg_stock_ledger_immutable
 *    库存流水表只增不改（AFTER UPDATE, DELETE）：
 *      - 禁止任何角色 UPDATE 流水记录（THROW 51501）；
 *      - 禁止非 dbo 角色 DELETE 流水（封堵 role_manager 的审计销赃口子），
 *        亦禁止 dbo 删除超过 24 小时的历史已结账流水（THROW 51502）。
 * ------------------------------------------------------------ */
CREATE OR ALTER TRIGGER dbo.trg_stock_ledger_immutable
ON dbo.tbl_stock_ledger
AFTER UPDATE, DELETE
AS
BEGIN
    IF @@ROWCOUNT = 0
        RETURN;

    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted)
        THROW 51501, N'【触发器】库存流水表只增不改，禁止执行 UPDATE。', 1;

    IF USER_NAME() <> N'dbo'
       OR EXISTS (
           SELECT 1
           FROM deleted
           WHERE ledger_time < DATEADD(DAY, -1, SYSDATETIME())
       )
        THROW 51502, N'【触发器】库存流水表禁止非 dbo 角色删除，亦禁止删除超过 24 小时的历史已结账流水。', 1;
END;
GO

/* ------------------------------------------------------------
 * 2. dbo.trg_points_ledger_immutable
 *    积分流水表只增不改（AFTER UPDATE, DELETE）：
 *      - 禁止任何角色 UPDATE 积分流水记录（THROW 51503）；
 *      - 禁止非 dbo 角色 DELETE 流水，亦禁止 dbo 删除超过 24 小时的历史流水（THROW 51504）。
 * ------------------------------------------------------------ */
CREATE OR ALTER TRIGGER dbo.trg_points_ledger_immutable
ON dbo.tbl_points_ledger
AFTER UPDATE, DELETE
AS
BEGIN
    IF @@ROWCOUNT = 0
        RETURN;

    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted)
        THROW 51503, N'【触发器】积分流水表只增不改，禁止执行 UPDATE。', 1;

    IF USER_NAME() <> N'dbo'
       OR EXISTS (
           SELECT 1
           FROM deleted
           WHERE change_time < DATEADD(DAY, -1, SYSDATETIME())
       )
        THROW 51504, N'【触发器】积分流水表禁止非 dbo 角色删除，亦禁止删除超过 24 小时的历史已结账流水。', 1;
END;
GO

/* ------------------------------------------------------------
 * 3. dbo.trg_order_detail_spec_type_guard
 *    订单明细规格类型集合级校验（AFTER INSERT, UPDATE）：
 *      - cup_spec_id   必须属于 spec_type = 'CUP'  （THROW 51511）
 *      - sugar_spec_id 必须属于 spec_type = 'SUGAR'（THROW 51512）
 *      - ice_spec_id   必须属于 spec_type = 'ICE'  （THROW 51513）
 *    说明：单列 FK 只校验 spec_option_id 存在，无法区分杯型/糖度/冰度；
 *    本触发器在库层兜底，杜绝跨类错传导致跳过糖浆反冲扣料。
 * ------------------------------------------------------------ */
CREATE OR ALTER TRIGGER dbo.trg_order_detail_spec_type_guard
ON dbo.tbl_order_detail
AFTER INSERT, UPDATE
AS
BEGIN
    IF @@ROWCOUNT = 0
        RETURN;

    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        LEFT JOIN dbo.tbl_spec_option AS s
            ON s.spec_option_id = i.cup_spec_id
        WHERE s.spec_type IS NULL OR s.spec_type <> 'CUP'
    )
        THROW 51511, N'【触发器】订单明细杯型规格无效：cup_spec_id 必须属于 CUP 类型。', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        LEFT JOIN dbo.tbl_spec_option AS s
            ON s.spec_option_id = i.sugar_spec_id
        WHERE s.spec_type IS NULL OR s.spec_type <> 'SUGAR'
    )
        THROW 51512, N'【触发器】订单明细糖度规格无效：sugar_spec_id 必须属于 SUGAR 类型。', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        LEFT JOIN dbo.tbl_spec_option AS s
            ON s.spec_option_id = i.ice_spec_id
        WHERE s.spec_type IS NULL OR s.spec_type <> 'ICE'
    )
        THROW 51513, N'【触发器】订单明细冰度规格无效：ice_spec_id 必须属于 ICE 类型。', 1;
END;
GO

/* ------------------------------------------------------------
 * 4. dbo.trg_order_header_state_guard
 *    订单状态机库层守卫（AFTER UPDATE）：
 *      - 仅当修改 order_status 时触发检查（兼防自更新递归）；
 *      - 终态 COMPLETED / CANCELLED / ABANDONED 不可变更状态（THROW 51521）；
 *      - 只允许 5 条合法正向流转（THROW 51522）：
 *          PENDING → MAKING | CANCELLED
 *          MAKING  → READY
 *          READY   → COMPLETED | ABANDONED
 *      - 流转至 COMPLETED 且 finish_time 为空时，自动补全 finish_time。
 * ------------------------------------------------------------ */
CREATE OR ALTER TRIGGER dbo.trg_order_header_state_guard
ON dbo.tbl_order_header
AFTER UPDATE
AS
BEGIN
    IF @@ROWCOUNT = 0
        RETURN;

    SET NOCOUNT ON;

    IF NOT UPDATE(order_status)
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN deleted AS d
            ON d.order_id = i.order_id
        WHERE i.order_status <> d.order_status
          AND d.order_status IN ('COMPLETED', 'CANCELLED', 'ABANDONED')
    )
        THROW 51521, N'【触发器】终态订单（COMPLETED/CANCELLED/ABANDONED）不可再变更状态。', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN deleted AS d
            ON d.order_id = i.order_id
        WHERE i.order_status <> d.order_status
          AND NOT (
              (d.order_status = 'PENDING' AND i.order_status IN ('MAKING', 'CANCELLED'))
           OR (d.order_status = 'MAKING'  AND i.order_status = 'READY')
           OR (d.order_status = 'READY'   AND i.order_status IN ('COMPLETED', 'ABANDONED'))
          )
    )
        THROW 51522, N'【触发器】非法订单状态流转，已拦截。', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN deleted AS d
            ON d.order_id = i.order_id
        WHERE d.order_status <> 'COMPLETED'
          AND i.order_status = 'COMPLETED'
          AND i.finish_time IS NULL
    )
    BEGIN
        UPDATE h
        SET h.finish_time = CASE
            WHEN SYSDATETIME() >= h.order_time
                 AND (h.pay_time IS NULL OR SYSDATETIME() >= h.pay_time)
            THEN SYSDATETIME()
            ELSE COALESCE(h.pay_time, h.order_time)
        END
        FROM dbo.tbl_order_header AS h
        JOIN inserted AS i
            ON i.order_id = h.order_id
        JOIN deleted AS d
            ON d.order_id = h.order_id
        WHERE d.order_status <> 'COMPLETED'
          AND i.order_status = 'COMPLETED'
          AND h.finish_time IS NULL;
    END;
END;
GO

PRINT N'【触发器】4 个触发器已创建/更新：trg_stock_ledger_immutable、trg_points_ledger_immutable、trg_order_detail_spec_type_guard、trg_order_header_state_guard';
GO
