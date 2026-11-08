"""顾客（= 会员）侧页面：菜单、下单、我的订单、我的积分。"""

import logging

from flask import Blueprint, flash, redirect, render_template, request, url_for

from service import auth, catalog, ordering
from web.security import current_member, member_required

log = logging.getLogger(__name__)
bp = Blueprint("member", __name__)


@bp.route("/")
@member_required
def menu():
    member = current_member()
    cards = catalog.menu_cards("MEMBER")
    return render_template(
        "menu.html",
        member=member,
        cards=cards,
        options=catalog.options("MEMBER"),
    )


def _parse_items(form) -> list:
    """把表单解析成下单参数。价格一律由服务端重算，这里只取「选了哪些」。"""
    items = []
    product_ids = form.getlist("product_id")
    cup_ids = form.getlist("cup_spec_id")
    sugar_ids = form.getlist("sugar_spec_id")
    ice_ids = form.getlist("ice_spec_id")
    qtys = form.getlist("qty")
    for idx, product_id in enumerate(product_ids):
        qty_raw = qtys[idx] if idx < len(qtys) else "0"
        if not qty_raw.strip().isdigit() or int(qty_raw) == 0:
            continue
        toppings = []
        for topping_id in form.getlist("topping_id_%d" % idx):
            toppings.append({"topping_id": int(topping_id), "qty": 1})
        items.append(
            {
                "product_id": int(product_id),
                "cup_spec_id": int(cup_ids[idx]),
                "sugar_spec_id": int(sugar_ids[idx]),
                "ice_spec_id": int(ice_ids[idx]),
                "qty": int(qty_raw),
                "toppings": toppings,
            }
        )
    return items


@bp.route("/order", methods=["POST"])
@member_required
def place_order():
    member = current_member()
    result = ordering.place_order(member["member_id"], _parse_items(request.form))
    log.info("下单成功 member_id=%s order_no=%s", member["member_id"], result["order_no"])
    flash(
        "下单成功：单号 %s，取餐号 %d，实付 %s 元，获得 %d 积分"
        % (result["order_no"], result["pickup_no"], result["amount_paid"], result["earned_points"]),
        "success",
    )
    return redirect(url_for("member.orders"))


@bp.route("/orders")
@member_required
def orders():
    data = auth.profile(current_member()["member_id"])
    return render_template("orders.html", member=data["member"], orders=data["orders"])


@bp.route("/me")
@member_required
def me():
    data = auth.profile(current_member()["member_id"])
    return render_template(
        "me.html",
        member=data["member"],
        points=data["points"],
        points_denied=data.get("points_denied", False),
        orders=data["orders"][:5],
    )
