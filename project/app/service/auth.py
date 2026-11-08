"""登录与会话相关的业务规则。

口令约定（与 ``project/sql/11-migration/migration-02-login-credentials.sql`` 一致）：
    盐 = 'm' + member_id            （确定性，重建可复现）
    摘要 = UPPER(HEX(SHA-256(盐 + 口令)))
    VARCHAR + 纯 ASCII，因此 SQL 的 HASHBYTES 与 Python 的 hashlib 结果一致
"""

import hashlib

from config import db_user_for
from dao import db, member_dao
from dao import errors as dao_errors
from dao.errors import DaoError
from service.errors import BusinessRuleViolation, Unauthenticated, ValidationError


def hash_password(salt: str, password: str) -> str:
    """计算与 SQL 侧一致的摘要。"""
    return hashlib.sha256((salt + password).encode("utf-8")).hexdigest().upper()


def member_salt(member_id: int) -> str:
    return "m%d" % int(member_id)


def employee_salt(employee_id: int) -> str:
    return "e%d" % int(employee_id)


def _credentials_ready(s) -> bool:
    return member_dao.has_password_column(s)


def _normalize_phone(phone: str) -> str:
    phone = (phone or "").strip()
    if not phone.isdigit() or len(phone) != 11:
        raise ValidationError("请输入 11 位手机号")
    return phone


def login(phone: str, password: str) -> dict:
    """会员登录。失败一律返回同一个提示，不透露「手机号是否存在」。"""
    phone = _normalize_phone(phone)
    if not password:
        raise ValidationError("请输入密码")

    with db.open_session(db_user_for("MEMBER")) as s:
        if not _credentials_ready(s):
            raise BusinessRuleViolation(
                "登录功能尚未开通，请联系店员", detail="tbl_member.password_hash 缺失"
            )
        row = member_dao.find_login(s, phone)
        if row is None:
            raise Unauthenticated("手机号或密码不正确")
        member_id, member_code, name, phone_db, points, pwd_hash = row
        if not pwd_hash or hash_password(member_salt(member_id), password) != pwd_hash.strip():
            raise Unauthenticated("手机号或密码不正确")
        return {
            "member_id": member_id,
            "member_code": member_code,
            "member_name": name,
            "member_phone": phone_db,
            "points_balance": points,
            "role": "MEMBER",
        }


def load_member(member_id: int) -> dict:
    with db.open_session(db_user_for("MEMBER")) as s:
        row = member_dao.get(s, member_id)
        if row is None:
            raise Unauthenticated("请先登录")
        return {
            "member_id": row[0],
            "member_code": row[1],
            "member_name": row[2],
            "member_phone": row[3],
            "points_balance": row[4],
            "role": "MEMBER",
        }


# 订单状态：前三个算「进行中」（订单页主表格），后三个算「历史」（折叠展示）。
# 取值来自 ck_order_header_order_status，不要在这里新增库中不存在状态。
ACTIVE_ORDER_STATUSES = ("PENDING", "MAKING", "READY")

_ORDER_STATUS_LABEL = {
    "PENDING": "待制作",
    "MAKING": "制作中",
    "READY": "待取餐",
    "COMPLETED": "已完成",
    "CANCELLED": "已取消",
    "ABANDONED": "已弃单",
}

_ORDER_STATUS_TONE = {
    "PENDING": "primary",
    "MAKING": "warning",
    "READY": "success",
    "COMPLETED": "secondary",
    "CANCELLED": "danger",
    "ABANDONED": "secondary",
}

# 只有进行中的三个状态需要一句人话，历史状态不必解释
_ORDER_STATUS_HINT = {
    "PENDING": "已下单，等制作",
    "MAKING": "制作中，请稍候",
    "READY": "做好了，可以取餐",
}


def _fmt_time(value) -> str:
    """DATETIME2 直接 str() 会带 7 位小数秒，页面上没意义，统一截到分钟。"""
    if value is None:
        return ""
    try:
        return value.strftime("%Y-%m-%d %H:%M")
    except AttributeError:
        return str(value)


def _order_views(rows: list) -> list:
    """把 `list_orders` 的裸行翻成模板可直接用的字段，避免模板里写 o[7] 这种下标。"""
    views = []
    for row in rows:
        (order_id, order_no, business_date, pickup_no, amount_due,
         amount_paid, pay_status, order_status, order_time) = row
        views.append({
            "order_id": order_id,
            "order_no": order_no,
            "business_date": business_date,
            "pickup_no": pickup_no,
            "amount_due": amount_due,
            "amount_paid": amount_paid,
            "pay_status": pay_status,
            "status": order_status,
            "status_label": _ORDER_STATUS_LABEL.get(order_status, order_status),
            "status_tone": _ORDER_STATUS_TONE.get(order_status, "secondary"),
            "status_hint": _ORDER_STATUS_HINT.get(order_status, ""),
            "order_time": _fmt_time(order_time),
            "is_active": order_status in ACTIVE_ORDER_STATUSES,
        })
    return views


def profile(member_id: int) -> dict:
    """「我的」页面：积分余额 + 最近流水 + 最近订单。"""
    with db.open_session(db_user_for("MEMBER")) as s:
        row = member_dao.get(s, member_id)
        if row is None:
            raise Unauthenticated("请先登录")
        points, points_denied = [], False
        try:
            points = member_dao.list_points(s, member_id)
        except DaoError as exc:
            # role_cashier 目前没有 tbl_points_ledger 的 SELECT 权限（第 4 周的权限矩阵如此），
            # 顾客又借用该身份，因此这里降级展示并如实告知，而不是假装没有流水。
            if exc.category != dao_errors.PERMISSION_DENIED:
                raise
            points_denied = True
        orders = member_dao.list_orders(s, member_id)
        views = _order_views(orders)
        return {
            "member": {
                "member_id": row[0],
                "member_code": row[1],
                "member_name": row[2],
                "member_phone": row[3],
                "points_balance": row[4],
            },
            "points": points,
            "points_denied": points_denied,
            "orders": orders,
            "active_orders": [o for o in views if o["is_active"]],
            "history_orders": [o for o in views if not o["is_active"]],
        }


def login_employee(employee_code: str, password: str) -> dict:
    """员工登录：用工号 + 口令，按 `position` 决定能进哪个界面。"""
    code = (employee_code or "").strip().upper()
    if not code:
        raise ValidationError("请输入工号")
    if not password:
        raise ValidationError("请输入密码")

    with db.open_session(db_user_for("MANAGER")) as s:
        row = member_dao.find_employee_login(s, code)
        if row is None:
            raise Unauthenticated("工号或密码不正确")
        employee_id, emp_code, name, position, is_active, pwd_hash = row
        if not is_active:
            raise Unauthenticated("工号或密码不正确")
        if not pwd_hash:
            raise BusinessRuleViolation(
                "该工号尚未开通登录，请联系管理员", detail="tbl_employee.password_hash 为空"
            )
        if hash_password(employee_salt(employee_id), password) != pwd_hash.strip():
            raise Unauthenticated("工号或密码不正确")
        return {
            "employee_id": employee_id,
            "employee_code": emp_code,
            "employee_name": name,
            "role": position,
        }
