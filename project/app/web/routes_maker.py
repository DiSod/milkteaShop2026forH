"""制作员 / 店员工作台：接单与状态流转、可做杯数。

页面层只做取数、渲染和跳转；队列查询与状态机都在业务层，
以哪儿个数据库身份读库也由业务层决定（`config.db_user_for`）。
"""

import logging

from flask import Blueprint, flash, redirect, render_template, url_for

from service import catalog, maker
from web.security import current_staff, staff_required

log = logging.getLogger(__name__)
bp = Blueprint("maker", __name__)


@bp.route("/maker")
@staff_required()
def board():
    staff = current_staff()
    role = staff["role"]
    return render_template(
        "maker.html",
        staff=staff,
        queue=maker.board(role),
        states=maker.STATE_LABEL,
        makeable=catalog.makeable(role),
    )


@bp.route("/maker/order/<int:order_id>/next", methods=["POST"])
@staff_required()
def advance(order_id: int):
    staff = current_staff()
    result = maker.advance(staff["role"], order_id)
    log.info(
        "订单状态推进 order_id=%s %s -> %s",
        order_id,
        result["from"],
        result["to"],
    )
    flash("订单 %d 已推进到「%s」" % (order_id, result["to_label"]), "success")
    return redirect(url_for("maker.board"))
