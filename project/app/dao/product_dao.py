"""商品档案的数据访问。

只有店长（``role_manager``）对 ``tbl_product`` / ``tbl_product_category``
持有写权限，收银员与制作员只能 SELECT —— 所以商品维护界面天然只有店长能进，
这一层的 SQL 写错也不会被别的岗位"顺路"跑通。

「删除商品」在这里实现为**下架**（``product_status = 'OFF_SALE'``）：
``tbl_order_detail.product_id`` 有外键指向商品，硬删会让历史订单失去引用，
这与 ``project/docs/business-rules.md`` 里"历史订单不该因删商品而消失"的取舍一致。
"""

from decimal import Decimal


def _select_sql(where: str = "") -> str:
    return (
        "SELECT p.product_id, p.product_code, p.product_name, c.category_name, "
        "       p.base_price, p.product_status "
        "  FROM tbl_product p "
        "  JOIN tbl_product_category c ON c.category_id = p.category_id "
        + where
        + " ORDER BY p.product_id"
    )


def list_products(s) -> list:
    return s.query(_select_sql())


def get_product(s, product_id: int):
    rows = s.query(_select_sql(" WHERE p.product_id = ?"), (product_id,))
    return rows[0] if rows else None


def list_categories(s) -> list:
    return s.query(
        "SELECT category_id, category_code, category_name "
        "  FROM tbl_product_category WHERE is_active = 1 ORDER BY sort_no, category_id"
    )


def insert_product(s, code: str, name: str, category_id: int,
                   base_price: Decimal, status: str) -> int:
    # 用 OUTPUT INSERTED 而不是 SCOPE_IDENTITY()：每次 execute 是一个独立批，
    # SCOPE_IDENTITY() 换批之后拿到的是 NULL。
    row = s.query_one(
        "SET NOCOUNT ON; "
        "INSERT INTO tbl_product (product_code, product_name, category_id, base_price, product_status) "
        "OUTPUT INSERTED.product_id "
        "VALUES (?, ?, ?, ?, ?)",
        (code, name, category_id, base_price, status),
    )
    return int(row[0])


def update_product(s, product_id: int, name: str, base_price: Decimal, status: str) -> int:
    return s.execute(
        "UPDATE tbl_product "
        "   SET product_name = ?, base_price = ?, product_status = ? "
        " WHERE product_id = ?",
        (name, base_price, status, product_id),
    )


def hard_delete(s, product_id: int) -> int:
    """仅用于测试与误建撤回；有订单引用时会被外键挡住（这是期望行为）。"""
    return s.execute("DELETE FROM tbl_product WHERE product_id = ?", (product_id,))
