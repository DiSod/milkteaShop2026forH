"""券包 —— 会员侧的只读视图。

只读路径要切到会员应得的数据库身份（与 ``service/auth.py`` 一致：会员在库里
执行 ``usr_test_cashier``），所以这里必须把 ``db_user`` 传给 ``open_session``。
"""

from config import db_user_for
from dao import coupon_dao, db


def _item(row) -> dict:
    return {
        "coupon_id": row[0],
        "coupon_code": row[1],
        "template_name": row[2],
        "discount_amount": row[3],
        "min_order_amount": row[4],
        "valid_from": row[5],
        "valid_to": row[6],
        "status": row[7],
        "used_time": row[8],
    }


def wallet(member_id: int, role: str = "MEMBER") -> dict:
    """会员券包，按「可用 / 已用 / 已过期」分三组。"""
    with db.open_session(db_user_for(role)) as s:
        rows = coupon_dao.list_for_member(s, member_id)

    buckets = {"AVAILABLE": [], "USED": [], "EXPIRED": []}
    for row in rows:
        buckets[row[9]].append(_item(row))

    return {
        "available": buckets["AVAILABLE"],
        "used": buckets["USED"],
        "expired": buckets["EXPIRED"],
        "total": len(rows),
    }


def available(member_id: int, role: str = "MEMBER") -> list:
    """下单页下拉：只列现在能用的券。"""
    with db.open_session(db_user_for(role)) as s:
        rows = coupon_dao.list_available(s, member_id)
    return [
        {
            "coupon_id": r[0],
            "coupon_code": r[1],
            "template_name": r[2],
            "discount_amount": r[3],
            "min_order_amount": r[4],
            "valid_to": r[5],
        }
        for r in rows
    ]
