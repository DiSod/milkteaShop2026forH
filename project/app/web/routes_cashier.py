"""收银员工作台：代客点单收银。

会员与散客的区别只体现在一个手机号上：填了 = 认出会员、累积分；留空 = 散客单。
"""

import logging

from flask import Blueprint, flash, redirect, render_template, request, url_for

from service import cashier
from web.routes_member import _parse_items
from web.security import current_staff, staff_required

log = logging.getLogger(__name__)
bp = Blueprint("cashier", __name__)


@bp.route("/cashier")
@staff_required("CASHIER", "MANAGER")
def index():
    staff = current_staff()
    data = cashier.menu_data(staff["role"])
    return render_template("cashier.html", staff=staff, **data)


@bp.route("/cashier/order", methods=["POST"])
@staff_required("CASHIER", "MANAGER")
def place_order():
    staff = current_staff()
    result = cashier.place(staff["role"], request.form.get("member_phone"), _parse_items(request.form))
    who = result["member"]["member_name"] if result["member"] else "散客"
    log.info("收银下单 order_no=%s member=%s", result["order_no"], who)
    flash(
        "收银成功（%s）：单号 %s，取餐号 %d，实付 %s 元%s"
        % (
            who,
            result["order_no"],
            result["pickup_no"],
            result["amount_paid"],
            "，累计 %d 积分" % result["earned_points"] if result["earned_points"] else "",
        ),
        "success",
    )
    return redirect(url_for("cashier.index"))
