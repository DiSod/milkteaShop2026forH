"""制作员 / 店员工作台：接单与状态流转、可做杯数。

页面层只做取数、渲染和跳转；队列查询与状态机都在业务层，
以哪儿个数据库身份读库也由业务层决定（`config.db_user_for`）。
"""

import logging

from flask import Blueprint, flash, redirect, render_template, url_for

from service import catalog, maker, ordering
from web.security import current_staff, staff_required

log = logging.getLogger(__name__)
bp = Blueprint("maker", __name__)


@bp.route("/maker")
@staff_required("MAKER", "MANAGER")
def board():
    staff = current_staff()
    role = staff["role"]
    return render_template(
        "maker.html",
        staff=staff,
        queue=maker.board(role),
        states=maker.STATE_LABEL,
        cards=catalog.makeable_cards(role),
    )


@bp.route("/maker/order/<int:order_id>/next", methods=["POST"])
@staff_required("MAKER", "MANAGER")
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

@bp.route("/maker/order/<int:order_id>/cancel", methods=["POST"])
@staff_required("MAKER", "MANAGER")
def cancel_order(order_id: int):
    """店员代取消 —— 散客单没有会员账号，只能由这里撤掉。"""
    staff = current_staff()
    result = ordering.cancel_order(order_id)
    log.info(
        "订单取消（店员） order_id=%s order_no=%s by=%s",
        order_id,
        result["order_no"],
        staff["employee_code"],
    )
    flash(
        "订单 %s 已取消：回冲 %d 种原料%s%s"
        % (
            result["order_no"],
            result["restored_ingredients"],
            "，扣回 %d 积分" % result["points_revoked"] if result["points_revoked"] else "",
            "，券已退回" if result.get("coupon_released") else "",
        ),
        "success",
    )
    return redirect(url_for("maker.board"))

