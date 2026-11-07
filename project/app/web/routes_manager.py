"""店长工作台：经营日报 + 商品档案维护。

店长是唯一同时拥有"看"与"改"商品档案权限的岗位，所以工作台分两块：
上面是当天经营快照（``vw_daily_business_summary``，只读），
下面是商品档案的增 / 改 / 下架。
"""

import logging

from flask import Blueprint, flash, redirect, render_template, request, url_for

from service import admin
from web.security import current_staff, staff_required

log = logging.getLogger(__name__)
bp = Blueprint("manager", __name__)


@bp.route("/manager")
@staff_required("MANAGER")
def index():
    staff = current_staff("MANAGER")
    data = admin.dashboard(staff["role"])
    return render_template(
        "manager.html",
        staff=staff,
        statuses=admin.STATUS_LABEL,
        **data,
    )


@bp.route("/manager/product/new", methods=["POST"])
@staff_required("MANAGER")
def create_product():
    staff = current_staff("MANAGER")
    product_id = admin.create(
        staff["role"],
        request.form.get("product_code"),
        request.form.get("product_name"),
        request.form.get("category_id"),
        request.form.get("base_price"),
        request.form.get("product_status"),
    )
    log.info("新建商品 product_id=%s", product_id)
    flash("商品已新建（编号 %d）" % product_id, "success")
    return redirect(url_for("manager.index"))


@bp.route("/manager/product/<int:product_id>/edit", methods=["POST"])
@staff_required("MANAGER")
def edit_product(product_id: int):
    staff = current_staff("MANAGER")
    admin.update(
        staff["role"],
        product_id,
        request.form.get("product_name"),
        request.form.get("base_price"),
        request.form.get("product_status"),
    )
    log.info("修改商品 product_id=%s", product_id)
    flash("商品 %d 已更新" % product_id, "success")
    return redirect(url_for("manager.index"))


@bp.route("/manager/product/<int:product_id>/retire", methods=["POST"])
@staff_required("MANAGER")
def retire_product(product_id: int):
    """删除的等价物：下架。历史订单仍指向这个商品。"""
    staff = current_staff("MANAGER")
    admin.retire(staff["role"], product_id)
    log.info("下架商品 product_id=%s", product_id)
    flash("商品 %d 已下架" % product_id, "success")
    return redirect(url_for("manager.index"))
