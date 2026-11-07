"""登录 / 登出。会员与员工两条入口，互不干扰。"""

from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from service import auth

bp = Blueprint("auth", __name__)

#: 岗位 → 登录后落到哪个工作台。四个岗位各有一个入口，
#: 与 ``ck_employee_position`` 的四个取值严格一一对应（顾客不是岗位，没有第五条）。
WORKBENCH = {
    "CASHIER": "cashier.index",
    "MAKER": "maker.board",
    "STOCKER": "stocker.index",
    "MANAGER": "manager.index",
}


@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        phone = request.form.get("phone", "")
        password = request.form.get("password", "")
        member = auth.login(phone, password)
        session.clear()
        session["member"] = member
        return redirect(url_for("member.menu"))
    return render_template("login.html")


@bp.route("/staff/login", methods=["GET", "POST"])
def staff_login():
    if request.method == "POST":
        code = request.form.get("employee_code", "")
        password = request.form.get("password", "")
        staff = auth.login_employee(code, password)
        session.clear()
        session["staff"] = staff
        endpoint = WORKBENCH.get(staff["role"])
        if endpoint:
            return redirect(url_for(endpoint))
        # 岗位存在但界面还没做：明确告知，而不是跳到别的岗位拿一个 403
        flash("当前岗位（%s）暂未开通工作台。" % staff["role"], "error")
        return redirect(url_for("auth.staff_login"))
    return render_template("staff_login.html")


@bp.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))
