"""商品、规格、加料、可做杯数的读取。

纯查询模块：不做业务判断，不做价格计算（价格一律以库里的视图/列为准）。
"""


def list_menu(s) -> list:
    """在售商品的每个杯型一行；``selling_price`` 已含杯型加价。"""
    return s.query(
        """
        SELECT product_id, product_code, product_name, category_name,
               cup_spec_id, cup_spec_name, selling_price,
               theor_makeable_cups, is_ingredient_sold_out, sale_status
        FROM vw_product_stock_availability
        WHERE product_status = 'ON_SALE'
        ORDER BY product_id, cup_spec_id
        """
    )


def list_specs(s) -> list:
    """规格选项原始行：(id, 类型, 代码, 名称, 加价, 排序号)。分组放在业务层做。"""
    return s.query(
        """
        SELECT spec_option_id, spec_type, spec_code, spec_name, extra_price, sort_no
        FROM tbl_spec_option
        ORDER BY spec_type, sort_no, spec_option_id
        """
    )


def list_toppings(s) -> list:
    return s.query(
        """
        SELECT topping_id, topping_code, topping_name, extra_price
        FROM tbl_topping
        WHERE is_active = 1
        ORDER BY topping_id
        """
    )


def makeable(s) -> list:
    """制作员视角的「还能做几杯」。

    注意：本视图是 ``role_maker`` 唯一能读库存的入口——它没有 ``tbl_ingredient``
    的任何直接权限，绕过视图去读原料表会得到错误码 229。
    """
    return s.query(
        """
        SELECT product_code, product_name, cup_spec_name, theor_makeable_cups,
               is_ingredient_sold_out, sale_status
        FROM vw_product_stock_availability
        WHERE product_status = 'ON_SALE'
        ORDER BY theor_makeable_cups, product_code, cup_spec_name
        """
    )


def find_cup_price(s, product_id: int, cup_spec_id: int):
    """取定价与可做杯数。返回 (selling_price, theor_makeable_cups, product_name, is_sold_out)。"""
    return s.query_one(
        """
        SELECT selling_price, theor_makeable_cups, product_name, is_ingredient_sold_out
        FROM vw_product_stock_availability
        WHERE product_id = ? AND cup_spec_id = ?
        """,
        (product_id, cup_spec_id),
    )


def topping_price(s, topping_id: int):
    """取加料单价。返回 (topping_name, extra_price)。"""
    return s.query_one(
        "SELECT topping_name, extra_price FROM tbl_topping WHERE topping_id = ? AND is_active = 1",
        (topping_id,),
    )


def stock_of(s, ingredient_ids) -> dict:
    """批量取原料余量与沽清标志：{ingredient_id: (qty_on_hand, is_sold_out, ingredient_name)}。

    走的是**目标角色的身份**，所以调用方必须持有 ``tbl_ingredient`` 的 SELECT 权限；
    制作员读库存只能走 :func:`makeable`，不要用这个函数。
    """
    ids = [int(i) for i in ingredient_ids]
    if not ids:
        return {}
    placeholders = ", ".join("?" for _ in ids)
    rows = s.query(
        "SELECT ingredient_id, qty_on_hand, is_sold_out, ingredient_name "
        "FROM tbl_ingredient WHERE ingredient_id IN (%s)" % placeholders,
        tuple(ids),
    )
    return {r[0]: (r[1], bool(r[2]), r[3]) for r in rows}
