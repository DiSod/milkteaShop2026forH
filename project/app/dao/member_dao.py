"""会员（= 顾客）相关的读取。

「顾客就是会员」是第 7 周前的裁定：顾客侧角色就是 ``tbl_member`` 的一行，
``tbl_order_header.member_id`` 可空只是为了兼容历史散客单，新单一律带会员。
"""


def find_login(s, phone: str):
    """按手机号取登录所需字段（含已入库的凭据摘要）。"""
    return s.query_one(
        """
        SELECT member_id, member_code, member_name, member_phone,
               points_balance, password_hash
        FROM tbl_member
        WHERE member_phone = ?
        """,
        (phone,),
    )


def find_by_phone(s, phone: str):
    return s.query_one(
        """
        SELECT member_id, member_code, member_name, member_phone, points_balance
        FROM tbl_member
        WHERE member_phone = ?
        """,
        (phone,),
    )


def get(s, member_id: int):
    return s.query_one(
        """
        SELECT member_id, member_code, member_name, member_phone, points_balance
        FROM tbl_member
        WHERE member_id = ?
        """,
        (member_id,),
    )


def list_orders(s, member_id: int, limit: int = 50) -> list:
    return s.query(
        """
        SELECT TOP (?) order_id, order_no, business_date, pickup_no,
               amount_due, amount_paid, pay_status, order_status, order_time
        FROM tbl_order_header
        WHERE member_id = ?
        ORDER BY order_id DESC
        """,
        (limit, member_id),
    )


def list_points(s, member_id: int, limit: int = 20) -> list:
    return s.query(
        """
        SELECT TOP (?) point_type, point_change, change_time, order_id, coupon_id
        FROM tbl_points_ledger
        WHERE member_id = ?
        ORDER BY point_ledger_id DESC
        """,
        (limit, member_id),
    )


def add_points(s, member_id: int, delta: int) -> int:
    """按差额调整会员积分余额；返回受影响行数。"""
    return s.execute(
        "UPDATE tbl_member SET points_balance = points_balance + ? WHERE member_id = ?",
        (delta, member_id),
    )


def has_password_column(s) -> bool:
    """登录凭据列是否已由迁移 02 建好。"""
    row = s.query_one("SELECT COL_LENGTH('tbl_member', 'password_hash')")
    return bool(row) and row[0] is not None


def find_employee_login(s, employee_code: str):
    """按工号取员工登录所需字段。"""
    return s.query_one(
        """
        SELECT employee_id, employee_code, employee_name, position, is_active,
               password_hash
        FROM tbl_employee
        WHERE employee_code = ?
        """,
        (employee_code,),
    )
