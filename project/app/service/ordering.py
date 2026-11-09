"""下单 —— 业务层最完整的一段：校验 → 定价 → 库存 → 事务写入。

三件事都集中在业务层（课程段落 9）：
  · 业务规则：商品必须可售、杯数不能超过可做量、金额由服务端算
  · 事务边界：整单要么全成，要么全回滚
  · 角色可执行范围：顾客下单跨「订单域 + 库存域」，只读路径走受限身份，
    写入路径暂以 dbo 执行（见 project/app/README.md §5 的已知边界）
"""

from decimal import Decimal

from dao import catalog_dao, coupon_dao, db, member_dao, order_dao, stock_dao
from service.errors import (
    BusinessRuleViolation,
    NotFound,
    PermissionDenied,
    ValidationError,
)

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


def place_order(member_id, items, cashier_id=None, coupon_id=None) -> dict:
    """下单。

    ``member_id`` 为 ``None`` 表示散客（收银台代客下单），此时不产生积分，
    也不能用券 —— 券本来就只属于会员。
    ``cashier_id`` 为空时由 ``order_dao`` 落一个系统收银员（见那里的说明）。
    ``coupon_id`` 为空表示不用券；门槛按券前金额算，抵扣不超过订单金额。
    """
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

        # 用券：只认「本人的、未用的、在有效期内的」券。门槛按券前金额算；
        # 抵扣不超过订单金额（券可能比单贵，此时实付 0 而不是负数）。
        discount = Decimal("0.00")
        if coupon_id is not None:
            if member_id is None:
                raise ValidationError("散客单不能使用会员券")
            coupon = coupon_dao.get_redeemable(s, coupon_id, member_id)
            if coupon is None:
                raise BusinessRuleViolation("这张券不可用（可能已被用掉或已过期）")
            face, min_amount = _dec(coupon[0]), _dec(coupon[1])
            if amount_due < min_amount:
                raise BusinessRuleViolation(
                    "这张券需要满 %s 元才能用，当前是 %s 元" % (min_amount, amount_due)
                )
            discount = face if face < amount_due else amount_due
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
            cashier_id=cashier_id,
            coupon_id=coupon_id,
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

        # 消费 1 元累计 1 积分（week1 §3.7）。散客单（member_id 为空）不产生积分：
        # tbl_points_ledger.member_id 是 NOT NULL，积分天然只属于会员。
        earned = 0
        if member_id is not None:
            earned = int(amount_paid)
            if earned > 0:
                order_dao.insert_points(s, member_id, order_id, earned)
                member_dao.add_points(s, member_id, earned)

        # 券核销放在最后一步：前面库存、积分都写成功了，这里失败就整单回滚
        if coupon_id is not None:
            if coupon_dao.mark_used(s, coupon_id, member_id) != 1:
                raise BusinessRuleViolation("这张券刚刚被用掉或已过期，请换一张再提交")

        s.commit()

    return {
        "order_id": order_id,
        "order_no": order_no,
        "pickup_no": pickup_no,
        "amount_paid": amount_paid,
        "earned_points": earned,
        "lines": len(priced),
        "discount": discount,
        "coupon_id": coupon_id,
    }

# ── 订单取消 ──────────────────────────────────────────────────────────
CANCELLABLE_STATUS = "PENDING"
_CANCEL_STATUS_LABEL = {
    "PENDING": "待制作",
    "MAKING": "制作中",
    "READY": "待取餐",
    "COMPLETED": "已完成",
    "CANCELLED": "已取消",
}


def cancel_order(order_id: int, member_id: int = None) -> dict:
    """取消一张**还没开始做**的订单，并把代价还回去。

    ``member_id`` 非空表示「会员自助取消」，必须与订单归属一致；
    为空表示店员代为取消（制作台 / 店长台），不做归属校验。

    三件事一个事务：
      ① 状态：PENDING → CANCELLED（带前置条件，避免和制作台推进互相覆盖）
      ② 库存：按该单实际写下的 SALES_USE 流水逐条回冲，写 CANCEL_BACK（正数），
               ``qty_on_hand`` 同事务加回 —— 保住 A6「结存 = Σ流水」
      ③ 积分：若该单给会员加过分，写一条 REVOKE（负数）并扣回余额
      ④ 券：若该单用过券，把券退回 UNUSED（先解绑再退，见下面注释）

    为什么只允许 PENDING：MAKING 之后原料已经进了杯子，回冲库存就是假账；
    退款属于 v2.0（整单退 + 退款单），不在本次范围。
    """
    with db.open_session() as s:
        header = order_dao.get_for_cancel(s, order_id)
        if header is None:
            raise NotFound("订单不存在")
        owner_id, status, coupon_id, order_no = header

        if status != CANCELLABLE_STATUS:
            raise BusinessRuleViolation(
                "只有「待制作」的订单可以取消，这张单现在是「%s」"
                % _CANCEL_STATUS_LABEL.get(status, status)
            )

        if member_id is not None and owner_id != member_id:
            raise PermissionDenied("这张单不属于当前会员")

        # 退券：先把订单上的券解绑（唯一索引要求），再把券退回 UNUSED
        coupon_released = False
        if coupon_id is not None:
            order_dao.detach_coupon(s, order_id)
            coupon_dao.release(s, coupon_id)
            coupon_released = True

        restored = 0
        for ingredient_id, qty in order_dao.list_sales_moves(s, order_id):
            stock_dao.apply_movement(
                s,
                ingredient_id,
                -_dec(qty),          # 原流水是负数，取反即为回冲量
                "CANCEL_BACK",
                "ORDER",
                remark="订单取消回冲",
                order_id=order_id,
            )
            restored += 1

        revoked = 0
        earned = int(order_dao.sum_earned_points(s, order_id) or 0)
        if owner_id is not None and earned > 0:
            order_dao.insert_points_revoke(s, owner_id, order_id, -earned)
            member_dao.add_points(s, owner_id, -earned)
            revoked = earned

        if order_dao.mark_cancelled(s, order_id) != 1:
            # 并发：在读完状态到写之间，制作台可能已经把它推到 MAKING
            raise BusinessRuleViolation("订单状态已被其他操作改变，请刷新后重试")

        s.commit()

    return {
        "order_id": order_id,
        "order_no": order_no,
        "restored_ingredients": restored,
        "points_revoked": revoked,
        "coupon_released": coupon_released,
    }

