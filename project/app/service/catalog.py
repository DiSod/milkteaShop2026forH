"""菜单与库存查询 —— 只读，走受限身份。"""

from config import db_user_for
from dao import catalog_dao, db


def menu(role: str = "MEMBER") -> list:
    with db.open_session(db_user_for(role)) as s:
        return catalog_dao.list_menu(s)


def options(role: str = "MEMBER") -> dict:
    """下单页需要的选项：杯型 / 糖度 / 冰量 / 加料。"""
    with db.open_session(db_user_for(role)) as s:
        specs = catalog_dao.list_specs(s)
        toppings = catalog_dao.list_toppings(s)
    grouped = {"CUP": [], "SUGAR": [], "ICE": []}
    for spec_id, spec_type, code, name, extra_price, _sort_no in specs:
        grouped.setdefault(spec_type, []).append(
            {
                "spec_option_id": spec_id,
                "spec_code": code,
                "spec_name": name,
                "extra_price": float(extra_price),
            }
        )
    return {
        "specs": grouped,
        "toppings": [
            {
                "topping_id": r[0],
                "topping_code": r[1],
                "topping_name": r[2],
                "extra_price": float(r[3]),
            }
            for r in toppings
        ],
    }


def makeable(role: str = "MAKER") -> list:
    """每个商品每个杯型的可做杯数。

    ``role_maker`` 对 ``tbl_ingredient`` 没有直接 SELECT 权限，只能经这张视图取值 ——
    这是第 4 周就设计好的边界，此处不改。
    """
    with db.open_session(db_user_for(role)) as s:
        return catalog_dao.makeable(s)
