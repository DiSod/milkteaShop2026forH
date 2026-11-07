"""商品档案维护（课程任务④的"商品查询维护"、⑤的"增删改查"）。

为什么只有店长：``tbl_product`` / ``tbl_product_category`` 的写权限只授给了
``role_manager``（``project/sql/08-security/role.sql``），收银员和制作员都是只读。
所以这一层的岗位判断不是"多写的一道保险"，而是**库层权限的应用层镜像** ——
两层同时成立才叫三层一致；任何一层单独成立都还能被绕过。

"删除"实现为下架（``product_status = 'OFF_SALE'``）：商品被历史订单引用，
硬删会让 ``tbl_order_detail`` 失去指向，违反"历史订单不因删商品而消失"的取舍。
"""

from decimal import Decimal, InvalidOperation

from config import db_user_for
from dao import db, product_dao, report_dao
from service.errors import BusinessRuleViolation, NotFound, PermissionDenied, ValidationError

STATUSES = ("ON_SALE", "OFF_SALE")
STATUS_LABEL = {"ON_SALE": "在售", "OFF_SALE": "已下架"}

MAX_CODE = 16
MAX_NAME = 40


def _require_manager(role: str) -> None:
    if role != "MANAGER":
        raise PermissionDenied("商品档案只有店长可以维护")


def _clean_price(text) -> Decimal:
    try:
        price = Decimal(str(text).strip())
    except (InvalidOperation, AttributeError, ValueError):
        raise ValidationError("价格必须是数字")
    if price < 0:
        raise ValidationError("价格不能为负")
    if price > Decimal("9999.9999"):
        raise ValidationError("价格超出 DECIMAL(12,4) 的可用范围")
    return price


def _clean_text(value, field: str, limit: int) -> str:
    text = (value or "").strip()
    if not text:
        raise ValidationError("%s不能为空" % field)
    if len(text) > limit:
        raise ValidationError("%s不能超过 %d 个字符" % (field, limit))
    return text


def overview(role: str) -> dict:
    with db.open_session(db_user_for(role)) as s:
        return {
            "products": product_dao.list_products(s),
            "categories": product_dao.list_categories(s),
        }


def dashboard(role: str, days: int = 7) -> dict:
    """店长工作台首页：经营日报 + 商品销量 Top 10 + 商品档案。"""
    _require_manager(role)
    with db.open_session(db_user_for(role)) as s:
        return {
            "daily": report_dao.daily_summary(s, days),
            "top_products": report_dao.product_sales(s),
            "products": product_dao.list_products(s),
            "categories": product_dao.list_categories(s),
        }


def create(role: str, code, name, category_id, price, status) -> int:
    _require_manager(role)
    code = _clean_text(code, "商品编码", MAX_CODE)
    name = _clean_text(name, "商品名称", MAX_NAME)
    if status not in STATUSES:
        raise ValidationError("商品状态只能是 %s" % " / ".join(STATUSES))
    price = _clean_price(price)
    try:
        category_id = int(category_id)
    except (TypeError, ValueError):
        raise ValidationError("请选择商品分类")

    with db.open_session(db_user_for(role)) as s:
        known = {row[0] for row in product_dao.list_categories(s)}
        if category_id not in known:
            raise ValidationError("商品分类不存在或已停用")
        product_id = product_dao.insert_product(s, code, name, category_id, price, status)
        s.commit()
    return product_id


def update(role: str, product_id, name, price, status) -> int:
    _require_manager(role)
    name = _clean_text(name, "商品名称", MAX_NAME)
    if status not in STATUSES:
        raise ValidationError("商品状态只能是 %s" % " / ".join(STATUSES))
    price = _clean_price(price)
    try:
        product_id = int(product_id)
    except (TypeError, ValueError):
        raise ValidationError("商品编号无效")

    with db.open_session(db_user_for(role)) as s:
        if product_dao.get_product(s, product_id) is None:
            raise NotFound("商品不存在")
        changed = product_dao.update_product(s, product_id, name, price, status)
        s.commit()
    return changed


def retire(role: str, product_id) -> int:
    """下架（不是物理删除）。"""
    _require_manager(role)
    try:
        product_id = int(product_id)
    except (TypeError, ValueError):
        raise ValidationError("商品编号无效")

    with db.open_session(db_user_for(role)) as s:
        row = product_dao.get_product(s, product_id)
        if row is None:
            raise NotFound("商品不存在")
        if row[5] == "OFF_SALE":
            raise BusinessRuleViolation("该商品已经是下架状态")
        changed = product_dao.update_product(s, product_id, row[2], row[4], "OFF_SALE")
        s.commit()
    return changed
