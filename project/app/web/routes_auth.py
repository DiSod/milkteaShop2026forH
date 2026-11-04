"""登录 / 登出。会员与员工两条入口，互不干扰。"""

from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from service import auth

bp = Blueprint("auth", __name__)

#: 目前已有工作台的岗位。收银员 / 库管员的界面排在第 8—9 周，
#: 在那之前登录成功也不该把人丢进一个 403 页面。
STAFF_WORKBENCH_ROLES = ("MAKER", "MANAGER")


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
        if staff["role"] in STAFF_WORKBENCH_ROLES:
            return redirect(url_for("maker.board"))
        # 岗位存在但界面还没做：明确告知，而不是跳到 /maker 拿一个 403
        flash("当前岗位（%s）的工作台排在第 8—9 周，暂未开放。" % staff["role"], "error")
        return redirect(url_for("auth.staff_login"))
    return render_template("staff_login.html")


@bp.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))
