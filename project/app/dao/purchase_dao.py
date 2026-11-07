"""采购单的数据访问（只覆盖库管员要用的那部分）。

库管员对 ``tbl_purchase_order`` / ``tbl_purchase_order_detail`` 只有
``SELECT`` + ``UPDATE``（没有 ``INSERT``），这正对应业务上的分工：
**采购单由店长下单，库管员只负责按单收货。**
"""


def list_open_lines(s) -> list:
    """还没收满的采购明细（``qty_ordered > qty_received``）。"""
    return s.query(
        "SELECT d.purchase_order_detail_id, o.purchase_order_id, o.purchase_no, "
        "       o.order_status, i.ingredient_id, i.ingredient_code, i.ingredient_name, "
        "       i.unit, d.qty_ordered, d.qty_received, "
        "       d.qty_ordered - d.qty_received AS qty_remaining, d.unit_price "
        "  FROM tbl_purchase_order_detail d "
        "  JOIN tbl_purchase_order o ON o.purchase_order_id = d.purchase_order_id "
        "  JOIN tbl_ingredient i ON i.ingredient_id = d.ingredient_id "
        " WHERE d.qty_ordered > d.qty_received "
        " ORDER BY o.purchase_order_id, d.purchase_order_detail_id"
    )


def get_line(s, detail_id: int):
    rows = s.query(
        "SELECT d.purchase_order_detail_id, o.purchase_order_id, i.ingredient_id, "
        "       i.ingredient_name, i.unit, d.qty_ordered, d.qty_received, "
        "       d.qty_ordered - d.qty_received AS qty_remaining "
        "  FROM tbl_purchase_order_detail d "
        "  JOIN tbl_purchase_order o ON o.purchase_order_id = d.purchase_order_id "
        "  JOIN tbl_ingredient i ON i.ingredient_id = d.ingredient_id "
        " WHERE d.purchase_order_detail_id = ?",
        (detail_id,),
    )
    return rows[0] if rows else None


def add_received(s, detail_id: int, qty) -> int:
    return s.execute(
        "UPDATE tbl_purchase_order_detail SET qty_received = qty_received + ? "
        " WHERE purchase_order_detail_id = ?",
        (qty, detail_id),
    )


def mark_order_received(s, purchase_order_id: int, receiver_id: int) -> int:
    return s.execute(
        "UPDATE tbl_purchase_order "
        "   SET order_status = 'ACCEPTED', received_by = ? "
        " WHERE purchase_order_id = ? AND order_status <> 'ACCEPTED'",
        (receiver_id, purchase_order_id),
    )


def count_open_lines(s, purchase_order_id: int) -> int:
    rows = s.query(
        "SELECT COUNT(*) FROM tbl_purchase_order_detail "
        " WHERE purchase_order_id = ? AND qty_ordered > qty_received",
        (purchase_order_id,),
    )
    return int(rows[0][0]) if rows else 0
