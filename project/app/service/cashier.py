"""收银台：代客下单 + 会员识别。

**散客**：``tbl_order_header.member_id`` 可空，库里实有 764 张散客单（38.9%）。
应用侧原来的规矩是"顾客自助下单必须绑定会员"（规则 A12），但收银台是店员代客下单，
散客是常态，所以这里允许 ``member_id = NULL``；写入路径复用
:func:`service.ordering.place_order`，它会在 ``member_id`` 为空时跳过积分段。

写入为什么要用 ``dbo`` 而不是 ``usr_test_cashier``：一次下单要同时写订单域
（收银员有权限）与库存域（只有库管员有权限），单角色做不到——这就是
``weeks/week07/README.md`` §十二 P-2 登记的跨岗位死结，正解是存储过程 +
``EXECUTE AS OWNER``，留到第 11—12 周。
"""

from config import db_user_for
from dao import db, member_dao
from service import catalog, ordering
from service.errors import ValidationError


def menu_data(role: str) -> dict:
    """收银台要看的菜单与规格（收银员对商品/规格/加料只有 SELECT）。"""
    return {"menu": catalog.menu(role), "options": catalog.options(role)}


def resolve_member(role: str, phone) -> dict:
    """按手机号认会员；空手机号 = 散客，返回 None。"""
    phone = (phone or "").strip()
    if not phone:
        return None
    if not (len(phone) == 11 and phone.isdigit()):
        raise ValidationError("手机号必须是 11 位数字")
    with db.open_session(db_user_for(role)) as s:
        row = member_dao.find_by_phone(s, phone)
    if row is None:
        raise ValidationError("没有找到该手机号对应的会员；散客请把手机号留空")
    return {
        "member_id": row[0],
        "member_code": row[1],
        "member_name": row[2],
        "member_phone": row[3],
        "points_balance": row[4],
    }


def place(role: str, phone, items) -> dict:
    member = resolve_member(role, phone)
    result = ordering.place_order(member["member_id"] if member else None, items)
    result["member"] = member
    return result
