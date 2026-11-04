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
