"""页面层的权限装饰器。

课程段落 12 的要求是「页面可以隐藏按钮，但真正的权限检查必须在后端业务层再次执行」。
所以这里的装饰器只解决**能不能进这个页面**；真正的数据越权由数据库的
``EXECUTE AS USER`` 在数据访问层兜底（越权会拿到 229）。
"""

import functools
import hmac
import secrets

from flask import current_app, g, redirect, request, session, url_for

from service.errors import PermissionDenied, Unauthenticated


def get_csrf_token() -> str:
    """获取当前会话的 CSRF 口令；不存在时生成并存入 session。"""
    token = session.get("_csrf_token")
    if not token:
        token = secrets.token_urlsafe(32)
        session["_csrf_token"] = token
    return token


def verify_csrf_token() -> None:
    """校验状态变更请求的 CSRF 口令；测试模式默认跳过，可用 CSRF_TEST_ENFORCE 开启。"""
    if request.method not in ("POST", "PUT", "PATCH", "DELETE"):
        return
    if not current_app.config.get("CSRF_ENABLED", True):
        return
    if current_app.config.get("TESTING", False) and not current_app.config.get(
        "CSRF_TEST_ENFORCE", False
    ):
        return
    submitted = request.form.get("csrf_token") or request.headers.get("X-CSRF-Token") or ""
    expected = session.get("_csrf_token") or ""
    if not expected or not hmac.compare_digest(submitted, expected):
        raise PermissionDenied("请求校验失败，请刷新页面后重试")


def load_current_user() -> None:
    """每次请求把当前身份放进 ``g``，模板里直接可用。"""
    g.member = session.get("member")
    g.staff = session.get("staff")
    g.current_role = (g.staff or {}).get("role") or ("MEMBER" if g.member else None)


def current_member() -> dict:
    if not g.get("member"):
        raise Unauthenticated()
    return g.member


def current_staff(*roles):
    staff = g.get("staff")
    if not staff:
        raise Unauthenticated()
    if roles and staff.get("role") not in roles:
        raise PermissionDenied()
    return staff


def member_required(view):
    @functools.wraps(view)
    def wrapper(*args, **kwargs):
        if not session.get("member"):
            return redirect(url_for("auth.login"))
        return view(*args, **kwargs)

    return wrapper


def staff_required(*roles):
    def decorator(view):
        @functools.wraps(view)
        def wrapper(*args, **kwargs):
            staff = session.get("staff")
            if not staff:
                return redirect(url_for("auth.staff_login"))
            if roles and staff.get("role") not in roles:
                raise PermissionDenied("当前岗位无权进入该页面")
            return view(*args, **kwargs)

        return wrapper

    return decorator
