"""券核销（v1.0 第 9 周）—— 券要真的抵扣、只能用一次、取消要退回。

五条断言对应五件后果：
  1. 券包页列得出可用的券
  2. 用券下单：`discount_amount` = 券面额，`amount_paid` = 券前金额 − 抵扣
  3. 同一张券不能用第二次（并发保护靠受影响行数，不用事务隔离级别）
  4. 别人的券不能用
  5. 取消订单要把券退回 `UNUSED`，并把订单上的 `coupon_id` 解绑

每条写操作都在 finally 里清理，测试不能改变基线快照的期望值。
"""

import pytest

from app import create_app
from config import Config
from dao import db

MEMBER_1 = ("13800000001", "000001")   # 刘洋，默认发券的 3 位会员之一
MEMBER_2 = ("13800000002", "000002")   # 也有券，用来验"不能借别人的券"


def _db_ready() -> bool:
    try:
        return bool(db.probe().get("database"))
    except Exception:  # noqa: BLE001
        return False


pytestmark = pytest.mark.skipif(not _db_ready(), reason="需要可连通的 milktea_shop 实例")


@pytest.fixture()
def client():
    app = create_app(Config)
    app.config.update(TESTING=True)
    with app.test_client() as c:
        yield c


def login_member(client, phone, password):
    return client.post("/login", data={"phone": phone, "password": password})


def _member_id(phone: str) -> int:
    with db.open_session() as s:
        return s.query_one("SELECT member_id FROM tbl_member WHERE member_phone = ?", (phone,))[0]


def _first_sellable_item():
    """取一个可用组合；数量 2 让券前金额明显超过 5 元面额。"""
    with db.open_session() as s:
        row = s.query_one(
            """
            SELECT TOP 1 r.product_id, r.cup_spec_id
            FROM tbl_recipe r
            JOIN tbl_product p ON p.product_id = r.product_id
            WHERE r.sugar_spec_id IS NULL AND p.product_status = 'ON_SALE'
            ORDER BY r.product_id, r.cup_spec_id
            """
        )
        sugar = s.query_one(
            "SELECT TOP 1 spec_option_id FROM tbl_spec_option WHERE spec_type = 'SUGAR' ORDER BY 1"
        )[0]
        ice = s.query_one(
            "SELECT TOP 1 spec_option_id FROM tbl_spec_option WHERE spec_type = 'ICE' ORDER BY 1"
        )[0]
    return {
        "product_id": row[0],
        "cup_spec_id": row[1],
        "sugar_spec_id": sugar,
        "ice_spec_id": ice,
        "qty": 2,
        "toppings": [],
    }


def _form(item, coupon_id=None) -> dict:
    form = {
        "product_id": str(item["product_id"]),
        "cup_spec_id": str(item["cup_spec_id"]),
        "sugar_spec_id": str(item["sugar_spec_id"]),
        "ice_spec_id": str(item["ice_spec_id"]),
        "qty": str(item["qty"]),
    }
    if coupon_id is not None:
        form["coupon_id"] = str(coupon_id)
    return form


def _free_coupon(member_id: int):
    """取一张现在可用的券：(coupon_id, 面额)。"""
    with db.open_session() as s:
        return s.query_one(
            """
            SELECT TOP 1 c.coupon_id, t.discount_amount
              FROM tbl_coupon c
              JOIN tbl_coupon_template t ON t.template_id = c.template_id
             WHERE c.member_id = ? AND c.status = 'UNUSED'
               AND SYSDATETIME() BETWEEN c.valid_from AND c.valid_to
             ORDER BY t.discount_amount DESC, c.coupon_id
            """,
            (member_id,),
        )


def _coupon_state(coupon_id: int):
    with db.open_session() as s:
        return s.query_one(
            "SELECT status, used_time FROM tbl_coupon WHERE coupon_id = ?", (coupon_id,)
        )


def _latest_order():
    with db.open_session() as s:
        return s.query_one(
            """
            SELECT TOP 1 order_id, amount_due, discount_amount, amount_paid, coupon_id, order_status
              FROM tbl_order_header
             ORDER BY order_id DESC
            """
        )


def _purge(order_id: int) -> None:
    """删掉这张单的全部痕迹，并按 Σ流水 重算结存/积分（自愈，不依赖走过取消）。"""
    with db.open_session() as s:
        ingredients = [
            r[0] for r in s.query(
                "SELECT DISTINCT ingredient_id FROM tbl_stock_ledger WHERE order_id = ?", (order_id,)
            )
        ]
        members = [
            r[0] for r in s.query(
                "SELECT DISTINCT member_id FROM tbl_points_ledger WHERE order_id = ?", (order_id,)
            )
        ]
        coupon = s.query_one("SELECT coupon_id FROM tbl_order_header WHERE order_id = ?", (order_id,))
        s.execute("DELETE FROM tbl_stock_ledger WHERE order_id = ?", (order_id,))
        s.execute("DELETE FROM tbl_points_ledger WHERE order_id = ?", (order_id,))
        s.execute(
            "DELETE FROM tbl_order_detail_topping WHERE order_detail_id IN "
            "(SELECT order_detail_id FROM tbl_order_detail WHERE order_id = ?)",
            (order_id,),
        )
        s.execute("DELETE FROM tbl_order_detail WHERE order_id = ?", (order_id,))
        s.execute("DELETE FROM tbl_order_header WHERE order_id = ?", (order_id,))
        if coupon and coupon[0] is not None:
            s.execute(
                "UPDATE tbl_coupon SET status = 'UNUSED', used_time = NULL WHERE coupon_id = ?",
                (coupon[0],),
            )
        for ingredient_id in ingredients:
            s.execute(
                "UPDATE tbl_ingredient SET qty_on_hand = "
                "(SELECT ISNULL(SUM(qty), 0) FROM tbl_stock_ledger WHERE ingredient_id = ?) "
                "WHERE ingredient_id = ?",
                (ingredient_id, ingredient_id),
            )
        for member_id in members:
            s.execute(
                "UPDATE tbl_member SET points_balance = "
                "(SELECT ISNULL(SUM(point_change), 0) FROM tbl_points_ledger WHERE member_id = ?) "
                "WHERE member_id = ?",
                (member_id, member_id),
            )
        s.commit()


def test_coupon_page_lists_available_coupon(client):
    """券包页要能看到可用的券号（默认发券由 migration-07 写入）。"""
    login_member(client, *MEMBER_1)
    resp = client.get("/coupons")
    assert resp.status_code == 200
    body = resp.get_data(as_text=True)
    assert "可用" in body
    assert "CPDEF" in body, "券包页应列出默认发放的券"


def test_member_pays_less_with_coupon(client):
    """用券下单：抵扣等于券面额，实付 = 券前金额 − 抵扣。"""
    member_id = _member_id(MEMBER_1[0])
    coupon = _free_coupon(member_id)
    assert coupon is not None, "测试前提：该会员有可用券（migration-07 默认发放）"
    coupon_id, face = coupon

    login_member(client, *MEMBER_1)
    resp = client.post("/order", data=_form(_first_sellable_item(), coupon_id), follow_redirects=False)
    assert resp.status_code == 302, resp.get_data(as_text=True)[:300]

    order_id = None
    try:
        row = _latest_order()
        order_id, due, discount, paid, cid, status = row
        assert cid == coupon_id, "订单上要记下用了哪张券"
        assert discount == face, "抵扣金额应等于券面额"
        assert paid == due - discount, "实付 = 券前金额 − 抵扣"
        assert status == "PENDING"
        assert _coupon_state(coupon_id)[0] == "USED", "下单成功后券应变成已用"
    finally:
        if order_id is not None:
            _purge(order_id)


def test_coupon_cannot_be_used_twice(client):
    """同一张券第二次下单必须被拒（409），且不能产生第二张订单。"""
    member_id = _member_id(MEMBER_1[0])
    coupon_id, _face = _free_coupon(member_id)

    login_member(client, *MEMBER_1)
    first = client.post("/order", data=_form(_first_sellable_item(), coupon_id), follow_redirects=False)
    assert first.status_code == 302
    order_id = _latest_order()[0]
    try:
        second = client.post("/order", data=_form(_first_sellable_item(), coupon_id), follow_redirects=True)
        assert second.status_code == 409
        assert "不可用" in second.get_data(as_text=True) or "刚刚被用掉" in second.get_data(as_text=True)
        assert _latest_order()[0] == order_id, "被拒的下单不能留下新订单"
    finally:
        _purge(order_id)


def test_cannot_use_other_members_coupon(client):
    """用别人的券必须被拒，且不能扣掉别人的券。"""
    other_id = _member_id(MEMBER_2[0])
    coupon = _free_coupon(other_id)
    assert coupon is not None, "测试前提：M002 也有默认券"
    coupon_id, _face = coupon

    login_member(client, *MEMBER_1)
    resp = client.post("/order", data=_form(_first_sellable_item(), coupon_id), follow_redirects=True)
    assert resp.status_code == 409
    assert _coupon_state(coupon_id)[0] == "UNUSED", "越权的下单不能把别人的券用掉"


def test_cancel_releases_coupon(client):
    """取消订单要退券：券回到 UNUSED，订单上的 coupon_id 解绑。"""
    member_id = _member_id(MEMBER_1[0])
    coupon_id, _face = _free_coupon(member_id)

    login_member(client, *MEMBER_1)
    resp = client.post("/order", data=_form(_first_sellable_item(), coupon_id), follow_redirects=False)
    assert resp.status_code == 302
    order_id = _latest_order()[0]
    try:
        assert _coupon_state(coupon_id)[0] == "USED"

        cancel = client.post("/orders/%d/cancel" % order_id, follow_redirects=True)
        assert cancel.status_code == 200
        body = cancel.get_data(as_text=True)
        assert "已取消" in body

        status, used_time = _coupon_state(coupon_id)
        assert status == "UNUSED", "取消后券应退回可用"
        assert used_time is None, "退券要把 used_time 清空（有 CHECK 约束盯着）"

        with db.open_session() as s:
            head = s.query_one(
                "SELECT order_status, coupon_id FROM tbl_order_header WHERE order_id = ?", (order_id,)
            )
        assert head[0] == "CANCELLED"
        assert head[1] is None, "退券必须把订单上的 coupon_id 解绑，否则唯一索引会挡住下一单"
    finally:
        _purge(order_id)
