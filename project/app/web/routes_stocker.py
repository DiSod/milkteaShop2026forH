"""库管员工作台：库存查询、补货预警、按单收货、报损。

库管员的对象权限里没有 ``tbl_product``（商品档案不归他管），
所以这个页面不出现商品 —— 岗位边界在页面上也看得见。
"""

import logging

from flask import Blueprint, flash, redirect, render_template, request, url_for

from service import stock
from web.security import current_staff, staff_required

log = logging.getLogger(__name__)
bp = Blueprint("stocker", __name__)


@bp.route("/stocker")
@staff_required("STOCKER", "MANAGER")
def index():
    staff = current_staff()
    data = stock.overview(staff["role"])
    return render_template("stocker.html", staff=staff, **data)


@bp.route("/stocker/receive", methods=["POST"])
@staff_required("STOCKER", "MANAGER")
def receive():
    staff = current_staff()
    result = stock.receive(
        staff["role"],
        staff["employee_id"],
        request.form.get("detail_id"),
        request.form.get("qty"),
    )
    log.info("收货入库 detail=%s qty=%s", request.form.get("detail_id"), result["qty"])
    flash(
        "已收货：%s +%s%s%s"
        % (
            result["ingredient_name"],
            result["qty"],
            result["unit"],
            "（该采购单已收满结案）" if result["order_closed"] else "",
        ),
        "success",
    )
    return redirect(url_for("stocker.index"))


@bp.route("/stocker/loss", methods=["POST"])
@staff_required("STOCKER", "MANAGER")
def report_loss():
    staff = current_staff()
    result = stock.loss(
        staff["role"],
        staff["employee_id"],
        request.form.get("ingredient_id"),
        request.form.get("qty"),
        request.form.get("remark"),
    )
    log.info("报损 ingredient=%s qty=%s", request.form.get("ingredient_id"), result["qty"])
    flash(
        "已登记报损：%s −%s%s（%s）"
        % (result["ingredient_name"], result["qty"], result["unit"], result["remark"]),
        "success",
    )
    return redirect(url_for("stocker.index"))
