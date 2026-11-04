"""下单 —— 业务层最完整的一段：校验 → 定价 → 库存 → 事务写入。

三件事都集中在业务层（课程段落 9）：
  · 业务规则：商品必须可售、杯数不能超过可做量、金额由服务端算
  · 事务边界：整单要么全成，要么全回滚
  · 角色可执行范围：顾客下单跨「订单域 + 库存域」，只读路径走受限身份，
    写入路径暂以 dbo 执行（见 project/app/README.md §5 的已知边界）
"""

from decimal import Decimal

from dao import catalog_dao, db, member_dao, order_dao
from service.errors import BusinessRuleViolation, ValidationError

MAX_LINES = 20
MAX_QTY_PER_LINE = 20

# 支付方式只有 CARD / ALIPAY / WECHAT / CASH 四种（ck_order_header_pay_method），
# v1.0 网单默认走微信
PAY_METHOD = "WECHAT"
PAY_STATUS = "SUCCESS"
ORDER_STATUS = "PENDING"


def _dec(value) -> Decimal:
    return Decimal(str(value))


def _validate(items) -> None:
    if not items:
        raise ValidationError("请至少选择一个商品")
    if len(items) > MAX_LINES:
        raise ValidationError("一张订单最多 %d 种商品" % MAX_LINES)
    for it in items:
        qty = it.get("qty")
        if not isinstance(qty, int) or qty < 1 or qty > MAX_QTY_PER_LINE:
            raise ValidationError("每行数量需在 1—%d 之间" % MAX_QTY_PER_LINE)
        for key in ("product_id", "cup_spec_id", "sugar_spec_id", "ice_spec_id"):
            if not isinstance(it.get(key), int):
                raise ValidationError("商品选项不完整，请重新选择")


def place_order(member_id: int, items) -> dict:
    _validate(items)

    # 写入路径不切换身份：一次下单要同时写订单域（收银员）与库存域（库管员），
    # 单角色授权做不到；解法的正路是存储过程 + EXECUTE AS OWNER，第 11—12 周再做。
    with db.open_session() as s:
        today = order_dao.today(s)

        priced = []
        for idx, it in enumerate(items, start=1):
            row = catalog_dao.find_cup_price(s, it["product_id"], it["cup_spec_id"])
            if row is None:
                raise ValidationError("所选商品或杯型当前不可售")
            unit_price = _dec(row[0])
            makeable = int(row[1] if row[1] is not None else 0)
            product_name = row[2]
            if row[3]:
                raise BusinessRuleViolation("「%s」已沽清，暂时无法制作" % product_name)
            if makeable < it["qty"]:
                raise BusinessRuleViolation(
                    "「%s」库存不足，当前最多可做 %d 杯" % (product_name, makeable)
                )

            extra = Decimal("0.00")
            topping_rows = []
            for tp in it.get("toppings") or []:
                t_row = catalog_dao.topping_price(s, tp["topping_id"])
                if t_row is None:
                    raise ValidationError("加料已下架，请重新选择")
                t_price = _dec(t_row[1])
                t_qty = int(tp.get("qty") or 1)
                if t_qty < 1 or t_qty > MAX_QTY_PER_LINE:
                    raise ValidationError("加料份数不合法")
                extra += t_price * t_qty
                topping_rows.append((tp["topping_id"], t_qty, t_price))

            subtotal = unit_price * it["qty"] + extra
            priced.append(
                {
                    "line_no": idx,
                    "product_id": it["product_id"],
                    "cup_spec_id": it["cup_spec_id"],
                    "sugar_spec_id": it["sugar_spec_id"],
                    "ice_spec_id": it["ice_spec_id"],
                    "qty": it["qty"],
                    "unit_price": unit_price,
                    "toppings": topping_rows,
                    "subtotal": subtotal,
                }
            )

        amount_due = sum((p["subtotal"] for p in priced), Decimal("0.00"))
        discount = Decimal("0.00")
        amount_paid = amount_due - discount

        # 原料总需求先算完再一次性校验，避免逐行扣减后才发现不够
        need = {}
        for p in priced:
            for ingredient_id, qty in order_dao.recipe_usage(
                s, p["product_id"], p["cup_spec_id"], p["sugar_spec_id"]
            ):
                need[ingredient_id] = need.get(ingredient_id, Decimal("0")) + _dec(qty) * p["qty"]

        used_ids = list(need.keys())
        stock = catalog_dao.stock_of(s, used_ids)  # {ingredient_id: (qty_on_hand, is_sold_out, name)}
        for ingredient_id, required in need.items():
            on_hand, sold_out, name = stock[ingredient_id]
            if sold_out:
                raise BusinessRuleViolation("「%s」已沽清，暂时无法制作" % name)
            if _dec(on_hand) < required:
                raise BusinessRuleViolation("「%s」余量不足，暂时无法制作" % name)

        seq, pickup_no = order_dao.next_sequence(s, today)
        order_no = "%s-%04d" % (today.replace("-", ""), seq)
        order_id = order_dao.insert_header(
            s,
            order_no=order_no,
            business_date=today,
            pickup_no=pickup_no,
            member_id=member_id,
            discount_amount=discount,
            amount_due=amount_due,
            amount_paid=amount_paid,
            pay_method=PAY_METHOD,
            pay_status=PAY_STATUS,
            order_status=ORDER_STATUS,
        )

        for p in priced:
            detail_id = order_dao.insert_detail(
                s,
                order_id=order_id,
                line_no=p["line_no"],
                product_id=p["product_id"],
                qty=p["qty"],
                unit_price=p["unit_price"],
                cup_spec_id=p["cup_spec_id"],
                sugar_spec_id=p["sugar_spec_id"],
                ice_spec_id=p["ice_spec_id"],
                subtotal=p["subtotal"],
            )
            for topping_id, t_qty, t_price in p["toppings"]:
                order_dao.insert_topping(s, detail_id, topping_id, t_qty, t_price)

        for ingredient_id, required in need.items():
            order_dao.deduct_ingredient(s, ingredient_id, required)
            order_dao.insert_stock_ledger(s, ingredient_id, -required, order_id)

        earned = int(amount_paid)  # 消费 1 元累计 1 积分（week1 §3.7）
        if earned > 0:
            order_dao.insert_points(s, member_id, order_id, earned)
            member_dao.add_points(s, member_id, earned)

        s.commit()

    return {
        "order_id": order_id,
        "order_no": order_no,
        "pickup_no": pickup_no,
        "amount_paid": amount_paid,
        "earned_points": earned,
        "lines": len(priced),
    }
