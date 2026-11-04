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
