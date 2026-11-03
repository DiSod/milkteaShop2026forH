"""工作台用例：接单队列与状态流转。

状态机（week1 §3.1 的 17 步主流程）：待制作 → 制作中 → 待取餐 → 已完成。
已弃取 / 已取消是旁支，不从这里进入。
"""

from dao import db, order_dao
from service.errors import BusinessRuleViolation, ValidationError

NEXT_STATE = {
    "PENDING": "MAKING",
    "MAKING": "READY",
    "READY": "COMPLETED",
}

STATE_LABEL = {
    "PENDING": "待制作",
    "MAKING": "制作中",
    "READY": "待取餐",
    "COMPLETED": "已完成",
    "ABANDONED": "已弃取",
    "CANCELLED": "已取消",
}


def board(role: str, limit: int = 20) -> list:
    with db.open_session(db_user_for_role(role)) as s:
        return order_dao.list_active_queue(s, limit)


def advance(role: str, order_id: int) -> dict:
    with db.open_session(db_user_for_role(role)) as s:
        current = order_dao.get_status(s, order_id)
        if current is None:
            raise ValidationError("订单不存在")
        target = NEXT_STATE.get(current)
        if target is None:
            raise BusinessRuleViolation(
                "当前状态（%s）不能再推进" % STATE_LABEL.get(current, current)
            )
        order_dao.update_status(s, order_id, target)
        s.commit()
    return {"order_id": order_id, "from": current, "to": target, "to_label": STATE_LABEL[target]}


def db_user_for_role(role: str) -> str:
    from config import db_user_for

    return db_user_for(role)
