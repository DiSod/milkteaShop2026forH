"""登录 / 登出。会员与员工两条入口，互不干扰。"""

from flask import Blueprint, redirect, render_template, request, session, url_for

from service import auth

bp = Blueprint("auth", __name__)


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
        if staff["role"] == "MAKER":
            return redirect(url_for("maker.board"))
        return redirect(url_for("maker.board"))
    return render_template("staff_login.html")


@bp.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))
