"""库存查询与调整（课程任务④的"库存查询调整"）。

**调整库存不是"改一个数"，是记一笔账。** 数据库里的 A6 不变量是
``qty_on_hand = SUM(tbl_stock_ledger.qty)``，``regression.sql`` TC-12 逐原料核对，
所以每次调整都走 :func:`dao.stock_dao.apply_movement`：改数量与写流水一次性完成。

``ledger_type`` 只能取 DOM-04 的三个值（``PURCHASE_IN`` / ``SALES_USE`` / ``LOSS``）：

* **收货入库** → ``PURCHASE_IN`` + ``ref_type='PURCHASE'``（必须挂采购单），正数；
* **报损** → ``LOSS`` + ``ref_type='MANUAL'``（两个外键都为空），负数。

盘点差异（``STOCKTAKE`` 类型）是 D5 明确延后到 v1.0 之后的事，
所以这里不伪造一个"盘点"入口 —— 宁可少一个功能，也不写一个语义不对的流水。
"""

from decimal import Decimal, InvalidOperation

from config import db_user_for
from dao import db, purchase_dao, stock_dao
from service.errors import BusinessRuleViolation, NotFound, PermissionDenied, ValidationError

ROLES = ("STOCKER", "MANAGER")


def _require_stock(role: str) -> None:
    if role not in ROLES:
        raise PermissionDenied("库存只有库管员（或店长）可以调整")


def _positive_qty(text, field: str = "数量") -> Decimal:
    try:
        qty = Decimal(str(text).strip())
    except (InvalidOperation, AttributeError, ValueError):
        raise ValidationError("%s必须是数字" % field)
    if qty <= 0:
        raise ValidationError("%s必须大于 0" % field)
    return qty


def _attention_rank(row) -> int:
    """原料列表的排序权重：越需要处理越靠前。

    0 停用 / 1 手工沽清 / 2 结存低于补货点 / 3 正常。
    库管员打开页面第一眼该看到的是这几类，而不是 60 条按编码排的原料。
    """
    if not row[10]:
        return 0
    if row[9]:
        return 1
    if (row[5] or 0) < (row[6] or 0):
        return 2
    return 3


def overview(role: str) -> dict:
    """库存查询：原料全量 + 低于补货点的预警 + 待收货明细。"""
    _require_stock(role)
    with db.open_session(db_user_for(role)) as s:
        ingredients = list(stock_dao.list_ingredients(s))
        ingredients.sort(key=lambda r: (_attention_rank(r), r[1]))
        return {
            "ingredients": ingredients,
            "alerts": stock_dao.list_alerts(s),
            "open_lines": purchase_dao.list_open_lines(s),
            "drift": stock_dao.ledger_drift(s),
        }


def receive(role: str, staff_id, detail_id, qty) -> dict:
    """按采购单收货：写 ``PURCHASE_IN`` 流水，正数。"""
    _require_stock(role)
    qty = _positive_qty(qty, "收货数量")
    try:
        detail_id = int(detail_id)
    except (TypeError, ValueError):
        raise ValidationError("采购明细无效")

    with db.open_session(db_user_for(role)) as s:
        line = purchase_dao.get_line(s, detail_id)
        if line is None:
            raise NotFound("采购明细不存在")
        (_, purchase_order_id, ingredient_id, ingredient_name,
         unit, _, _, remaining) = line
        remaining = Decimal(str(remaining))
        if qty > remaining:
            raise BusinessRuleViolation(
                "「%s」本单还差 %s%s，不能收 %s%s"
                % (ingredient_name, remaining, unit, qty, unit)
            )

        stock_dao.apply_movement(
            s,
            ingredient_id=ingredient_id,
            delta=qty,
            ledger_type="PURCHASE_IN",
            ref_type="PURCHASE",
            purchase_order_id=purchase_order_id,
            remark="按采购单收货 %d" % purchase_order_id,
            operator_id=staff_id,
        )
        purchase_dao.add_received(s, detail_id, qty)
        finished = purchase_dao.count_open_lines(s, purchase_order_id) == 0
        if finished:
            purchase_dao.mark_order_received(s, purchase_order_id, staff_id)
        s.commit()

    return {
        "ingredient_name": ingredient_name,
        "qty": qty,
        "unit": unit,
        "order_closed": finished,
    }


def loss(role: str, staff_id, ingredient_id, qty, remark) -> dict:
    """报损：写 ``LOSS`` 流水，负数。"""
    _require_stock(role)
    qty = _positive_qty(qty, "报损数量")
    remark = (remark or "").strip()
    if not remark:
        # week1 §3.4：报损登记的意义就在于"有人负责、有原因可查"
        raise ValidationError("报损必须填写原因")
    try:
        ingredient_id = int(ingredient_id)
    except (TypeError, ValueError):
        raise ValidationError("原料无效")

    with db.open_session(db_user_for(role)) as s:
        row = stock_dao.get_ingredient(s, ingredient_id)
        if row is None:
            raise NotFound("原料不存在")
        name, unit, on_hand = row[2], row[3], Decimal(str(row[5]))
        if Decimal(str(qty)) > on_hand:
            raise BusinessRuleViolation(
                "「%s」当前只有 %s%s，报损 %s%s 会变成负库存"
                % (name, on_hand, unit, qty, unit)
            )

        stock_dao.apply_movement(
            s,
            ingredient_id=ingredient_id,
            delta=-Decimal(str(qty)),
            ledger_type="LOSS",
            ref_type="MANUAL",
            remark=remark,
            operator_id=staff_id,
        )
        s.commit()

    return {"ingredient_name": name, "qty": qty, "unit": unit, "remark": remark}
