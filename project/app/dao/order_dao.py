"""订单相关的读写。

本模块只负责「把 SQL 执行掉」，**事务由业务层提交**（``Session.commit()``）。
"""

# 自营网单没有收银员，但 tbl_order_header.cashier_id 是 NOT NULL。
# v1.0 的取舍：记到「系统收银台」这个固定员工上，并在文档里登记为已知边界
# （见 project/app/README.md §5）；正解是把下单封装成存储过程，第 11—12 周再做。
SYSTEM_CASHIER_ID = 2  # E002 李娜，岗位 CASHIER


def next_sequence(s, business_date: str):
    """取当日的下一个流水号与取餐号；带 UPDLOCK/HOLDLOCK 串行化并发下单。"""
    row = s.query_one(
        """
        SET NOCOUNT ON;
        SELECT ISNULL(MAX(CAST(RIGHT(order_no, 4) AS INT)), 0) + 1 AS next_seq,
               ISNULL(MAX(pickup_no), 0) + 1 AS next_pickup
        FROM tbl_order_header WITH (UPDLOCK, HOLDLOCK)
        WHERE business_date = ?
        """,
        (business_date,),
    )
    return int(row[0]), int(row[1])


def insert_header(s, order_no, business_date, pickup_no, member_id,
                  discount_amount, amount_due, amount_paid, pay_method,
                  pay_status, order_status, cashier_id=None) -> int:
    row = s.query_one(
        """
        SET NOCOUNT ON;
        INSERT INTO tbl_order_header
            (order_no, business_date, pickup_no, member_id, discount_amount,
             amount_due, amount_paid, pay_method, pay_status, order_status,
             order_time, cashier_id)
        OUTPUT INSERTED.order_id
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, SYSDATETIME(), ?)
        """,
        (
            order_no, business_date, pickup_no, member_id, discount_amount,
            amount_due, amount_paid, pay_method, pay_status, order_status,
            cashier_id if cashier_id is not None else SYSTEM_CASHIER_ID,
        ),
    )
    return int(row[0])


def insert_detail(s, order_id, line_no, product_id, qty, unit_price,
                  cup_spec_id, sugar_spec_id, ice_spec_id, subtotal) -> int:
    row = s.query_one(
        """
        SET NOCOUNT ON;
        INSERT INTO tbl_order_detail
            (order_id, line_no, product_id, qty, unit_price,
             cup_spec_id, sugar_spec_id, ice_spec_id, subtotal)
        OUTPUT INSERTED.order_detail_id
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (order_id, line_no, product_id, qty, unit_price,
         cup_spec_id, sugar_spec_id, ice_spec_id, subtotal),
    )
    return int(row[0])


def insert_topping(s, order_detail_id, topping_id, qty, unit_extra_price) -> None:
    s.execute(
        """
        SET NOCOUNT ON;
        INSERT INTO tbl_order_detail_topping
            (order_detail_id, topping_id, qty, unit_extra_price)
        VALUES (?, ?, ?, ?)
        """,
        (order_detail_id, topping_id, qty, unit_extra_price),
    )


def recipe_usage(s, product_id: int, cup_spec_id: int, sugar_spec_id: int) -> list:
    """某商品在「某杯型 + 某糖度」下的原料用量。

    ``tbl_recipe.sugar_spec_id IS NULL`` 表示该原料用量与糖度无关（第 5 周 ER 图 §1.4
    登记的语义），因此取「糖度专有行 ∪ NULL 行」。实测这两类行的 (商品,杯型,原料)
    互不重叠，不会重复计量。
    """
    return s.query(
        """
        SELECT ingredient_id, SUM(qty) AS qty
        FROM tbl_recipe
        WHERE product_id = ?
          AND cup_spec_id = ?
          AND (sugar_spec_id = ? OR sugar_spec_id IS NULL)
        GROUP BY ingredient_id
        """,
        (product_id, cup_spec_id, sugar_spec_id),
    )


def deduct_ingredient(s, ingredient_id: int, qty) -> int:
    return s.execute(
        "UPDATE tbl_ingredient SET qty_on_hand = qty_on_hand - ? WHERE ingredient_id = ?",
        (qty, ingredient_id),
    )


def insert_stock_ledger(s, ingredient_id, qty, order_id, operator_id=None) -> None:
    """销售耗用流水：``qty`` 传负数表示出库，与既有台账口径一致。"""
    s.execute(
        """
        SET NOCOUNT ON;
        INSERT INTO tbl_stock_ledger
            (ingredient_id, ledger_type, qty, ref_type, order_id,
             operator_id, ledger_time, remark)
        VALUES (?, 'SALES_USE', ?, 'ORDER', ?, ?, SYSDATETIME(), ?)
        """,
        (ingredient_id, qty, order_id, operator_id, "网单销售耗用"),
    )


def insert_points(s, member_id, order_id, point_change) -> None:
    s.execute(
        """
        SET NOCOUNT ON;
        INSERT INTO tbl_points_ledger
            (member_id, point_type, point_change, order_id, change_time)
        VALUES (?, 'EARN', ?, ?, SYSDATETIME())
        """,
        (member_id, point_change, order_id),
    )


def today(s) -> str:
    """取数据库当天的业务日（'YYYY-MM-DD'），与业务日口径保持一处来源。"""
    return s.query_one(
        "SET NOCOUNT ON; SELECT CONVERT(char(10), CAST(SYSDATETIME() AS date), 120)"
    )[0]


def list_active_queue(s, limit: int = 20) -> list:
    """工作台队列：还没走完的订单，先进先出。"""
    return s.query(
        """
        SELECT TOP (?) order_id, order_no, pickup_no, order_status, order_time,
               amount_paid
        FROM tbl_order_header
        WHERE order_status IN ('PENDING', 'MAKING', 'READY')
        ORDER BY order_id
        """,
        (limit,),
    )


def get_status(s, order_id: int):
    row = s.query_one(
        "SELECT order_status FROM tbl_order_header WHERE order_id = ?", (order_id,)
    )
    return row[0] if row else None


def update_status(s, order_id: int, status: str) -> int:
    return s.execute(
        "UPDATE tbl_order_header SET order_status = ? WHERE order_id = ?",
        (status, order_id),
    )


# ── 订单取消（v1.0，仅 PENDING）────────────────────────────────────────
def get_for_cancel(s, order_id: int):
    """取取消所需的订单快照；不存在返回 None。

    返回 ``(member_id, order_status, coupon_id, order_no)``。
    """
    return s.query_one(
        """
        SET NOCOUNT ON;
        SELECT member_id, order_status, coupon_id, order_no
        FROM tbl_order_header
        WHERE order_id = ?
        """,
        (order_id,),
    )


def list_sales_moves(s, order_id: int) -> list:
    """该单实际写下的销售耗用流水 ``[(ingredient_id, qty)]``，qty 为负数。"""
    return s.query(
        """
        SELECT ingredient_id, qty
        FROM tbl_stock_ledger
        WHERE order_id = ? AND ledger_type = 'SALES_USE'
        ORDER BY ingredient_id
        """,
        (order_id,),
    )


def sum_earned_points(s, order_id: int):
    """该单累计获得的积分（EARN 合计）；没有则 0。"""
    return s.query_one(
        """
        SET NOCOUNT ON;
        SELECT ISNULL(SUM(point_change), 0)
        FROM tbl_points_ledger
        WHERE order_id = ? AND point_type = 'EARN'
        """,
        (order_id,),
    )[0]


def insert_points_revoke(s, member_id: int, order_id: int, point_change) -> None:
    """订单取消扣回积分：``point_change`` 传负数。"""
    s.execute(
        """
        SET NOCOUNT ON;
        INSERT INTO tbl_points_ledger
            (member_id, point_type, point_change, order_id, change_time)
        VALUES (?, 'REVOKE', ?, ?, SYSDATETIME())
        """,
        (member_id, point_change, order_id),
    )


def coupon_is_used(s, coupon_id: int) -> bool:
    """券是否已核销（``status = 'USED'`` 或 ``used_time`` 非空）。"""
    row = s.query_one(
        """
        SET NOCOUNT ON;
        SELECT CASE WHEN status = 'USED' OR used_time IS NOT NULL THEN 1 ELSE 0 END
        FROM tbl_coupon
        WHERE coupon_id = ?
        """,
        (coupon_id,),
    )
    return bool(row and row[0])


def mark_cancelled(s, order_id: int) -> int:
    """置为已取消 —— 带状态前置条件，避免与制作台的推进互相覆盖。"""
    # 注意：这里不能加 SET NOCOUNT ON —— 那会让 cursor.rowcount 变成 -1，
    # 调用方就无法用返回值判断"这一行到底改没改"（并发保护就失效了）。
    return s.execute(
        """
        UPDATE tbl_order_header
        SET order_status = 'CANCELLED'
        WHERE order_id = ? AND order_status = 'PENDING'
        """,
        (order_id,),
    )
