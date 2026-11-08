"""菜单与库存查询 —— 只读，走受限身份。"""

from config import db_user_for
from dao import catalog_dao, db


def menu(role: str = "MEMBER") -> list:
    with db.open_session(db_user_for(role)) as s:
        return catalog_dao.list_menu(s)


def menu_cards(role: str = "MEMBER") -> dict:
    """把「商品 × 杯型」的扁平行折叠成「每个商品一张卡」。

    页面只需要知道**能不能做**：可做杯数为 0（或原料沽清）即售罄。
    具体可做杯数不再暴露给顾客——它是库存内部量，顾客看到只会困惑。
    """
    cards = {}
    order = []
    for row in menu(role):
        product_id = row[0]
        card = cards.get(product_id)
        if card is None:
            card = cards[product_id] = {
                "product_id": product_id,
                "product_code": row[1],
                "product_name": row[2],
                "category_name": row[3],
                "cups": [],
            }
            order.append(product_id)
        card["cups"].append(
            {
                "cup_spec_id": row[4],
                "cup_spec_name": row[5],
                "price": float(row[6]),
                "sold_out": bool(row[8]) or (row[7] or 0) <= 0,
            }
        )

    available, sold_out = [], []
    for product_id in order:
        card = cards[product_id]
        # 可做的杯型排在前面，售罄的留在下拉里但标灰
        card["cups"].sort(key=lambda c: c["sold_out"])
        live = [c for c in card["cups"] if not c["sold_out"]]
        card["sold_out"] = not live
        pool = live or card["cups"]
        card["price_min"] = min(c["price"] for c in pool)
        card["price_max"] = max(c["price"] for c in pool)
        (sold_out if card["sold_out"] else available).append(card)

    # 分类分组：按分类首次出现的顺序，同类饮品聚在一起（product_id 顺序会让分类交错）
    groups, group_order = {}, []
    for card in available:
        name = card["category_name"]
        if name not in groups:
            groups[name] = {"category_name": name, "cards": []}
            group_order.append(name)
        groups[name]["cards"].append(card)

    return {
        "available": available,
        "sold_out": sold_out,
        "groups": [groups[n] for n in group_order],
    }



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


# 视图里的三档健康度，数字越大越糟：用它给一个商品定「整体状态」。
_MAKEABLE_RANK = {"充足在售": 0, "紧张预警": 1, "临时沽清": 2}

_MAKEABLE_TONE = {"充足在售": "success", "紧张预警": "warning", "临时沽清": "danger"}


def makeable_cards(role: str = "MAKER") -> dict:
    """制作员工作台：**每个商品一行，杯型作列**。

    扁平视图是「商品 × 杯型」的 55 行，其中 45 行都是「充足在售」，对制作员没有
    信息量。这里折叠成 29 行，并拆成两组：

    * ``attention`` —— 至少一个杯型不健康（原料沽清 / 可做数 ≤ 0 / 状态非「充足在售」）
    * ``others``    —— 全部杯型都健康

    杯型列的先后顺序取自 ``tbl_spec_option`` 的排序（中杯、大杯），不是写死的。
    单杯型商品（如圣代只有中杯）缺的那格留 ``None``，模板显示「—」。
    """
    rows = makeable(role)
    cup_names = [spec["spec_name"] for spec in options(role)["specs"]["CUP"]]

    cards, order = {}, []
    for product_code, product_name, cup_name, cups, ingredient_out, status in rows:
        card = cards.get(product_code)
        if card is None:
            card = cards[product_code] = {
                "product_code": product_code,
                "product_name": product_name,
                "cells": {},
            }
            order.append(product_code)
        card["cells"][cup_name] = {
            "makeable": int(cups or 0),
            "status": status,
            "ingredient_out": bool(ingredient_out),
        }

    attention, others = [], []
    for product_code in order:
        card = cards[product_code]
        live = [
            cell for cell in card["cells"].values()
            if cell["makeable"] > 0 and not cell["ingredient_out"]
        ]
        worst_rank = max(
            (_MAKEABLE_RANK.get(cell["status"], 0) for cell in card["cells"].values()),
            default=0,
        )
        worst_name = next(
            (name for name, rank in _MAKEABLE_RANK.items() if rank == worst_rank), ""
        )
        card["sold_out"] = not live
        card["status_label"] = worst_name
        card["status_tone"] = _MAKEABLE_TONE.get(worst_name, "secondary")
        # 「最紧的那档还能做几杯」——排序与提醒都用它
        card["min_makeable"] = min(cell["makeable"] for cell in card["cells"].values())
        card["needs_attention"] = card["sold_out"] or worst_rank > 0
        (attention if card["needs_attention"] else others).append(card)

    attention.sort(key=lambda c: (c["min_makeable"], c["product_code"]))
    others.sort(key=lambda c: c["product_code"])

    return {
        "cup_names": cup_names,
        "attention": attention,
        "others": others,
        "total_products": len(order),
        "total_rows": len(rows),
    }
