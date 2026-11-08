"""订单取消（v1.0）—— 只允许「待制作」，且必须把代价原样还回去。

三条断言对应三件后果，缺一条都不算"取消成功"：
  1. 状态：PENDING → CANCELLED，且二次取消被拒（幂等保护）
  2. 库存：该单的 SALES_USE 流水被 CANCEL_BACK 逐条回冲，A6「结存 = Σ流水」仍成立
  3. 积分：EARN 被 REVOKE 抵掉，会员余额回到下单前

另外两条负例：非 PENDING 不能取消；别人的订单不能取消。
每条写操作都在 finally 里清理，测试不能改变基线快照的期望值。
"""

import pytest

from app import create_app
from config import Config
from dao import db
from service import ordering

MEMBER_1 = ("13800000001", "000001")   # 刘洋
MEMBER_2 = ("13800000002", "000002")   # 另一位会员，用来验越权


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


def _first_sellable_item():
    """取一个原料与杯型都存在的组合，数量 1 足够触发扣料与积分。"""
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
        "qty": 1,
        "toppings": [],
    }


def _snapshot(member_id: int) -> dict:
    with db.open_session() as s:
        return {
            "stock": s.query_one("SELECT SUM(qty_on_hand) FROM tbl_ingredient")[0],
            "points": s.query_one(
                "SELECT points_balance FROM tbl_member WHERE member_id = ?", (member_id,)
            )[0],
            "drift": s.query_one(
                """
                SELECT COUNT(*) FROM tbl_ingredient i
                WHERE i.qty_on_hand <> (SELECT ISNULL(SUM(qty), 0) FROM tbl_stock_ledger l
                                        WHERE l.ingredient_id = i.ingredient_id)
                """
            )[0],
        }


def _purge(order_id: int) -> None:
    """删掉这张单的全部痕迹。

    SALES_USE（负）与 CANCEL_BACK（正）成对删除、EARN 与 REVOKE 成对删除，
    所以删完之后 A6 与 A4 仍然成立，基线快照不受影响。
    """
    with db.open_session() as s:
        ingredients = [
            r[0] for r in s.query(
                "SELECT DISTINCT ingredient_id FROM tbl_stock_ledger WHERE order_id = ?",
                (order_id,),
            )
        ]
        members = [
            r[0] for r in s.query(
                "SELECT DISTINCT member_id FROM tbl_points_ledger WHERE order_id = ?",
                (order_id,),
            )
        ]
        s.execute("DELETE FROM tbl_stock_ledger WHERE order_id = ?", (order_id,))
        s.execute("DELETE FROM tbl_points_ledger WHERE order_id = ?", (order_id,))
        s.execute(
            "DELETE FROM tbl_order_detail_topping WHERE order_detail_id IN "
            "(SELECT order_detail_id FROM tbl_order_detail WHERE order_id = ?)",
            (order_id,),
        )
        s.execute("DELETE FROM tbl_order_detail WHERE order_id = ?", (order_id,))
        s.execute("DELETE FROM tbl_order_header WHERE order_id = ?", (order_id,))
        # 不管这张单有没有被取消过，都按流水重算一次 —— 见模块 docstring 的说明
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


def _status(order_id: int) -> str:
    with db.open_session() as s:
        return s.query_one(
            "SELECT order_status FROM tbl_order_header WHERE order_id = ?", (order_id,)
        )[0]


def test_member_cancels_own_pending_order(client):
    """会员取消自己的待制作订单：状态、库存、积分三样都回到下单前。"""
    member_id = 1
    before = _snapshot(member_id)
    placed = ordering.place_order(member_id, [_first_sellable_item()])
    order_id = placed["order_id"]
    try:
        after_place = _snapshot(member_id)
        assert after_place["stock"] < before["stock"], "下单后结存应减少"
        assert after_place["points"] == before["points"] + placed["earned_points"]
        assert after_place["drift"] == 0

        login_member(client, *MEMBER_1)
        resp = client.post("/orders/%d/cancel" % order_id, follow_redirects=False)
        assert resp.status_code == 302, "取消成功后应重定向回订单页"
        assert _status(order_id) == "CANCELLED"

        after_cancel = _snapshot(member_id)
        assert after_cancel["stock"] == before["stock"], "回冲后结存应回到下单前"
        assert after_cancel["points"] == before["points"], "REVOKE 后积分应回到下单前"
        assert after_cancel["drift"] == 0, "取消不能破坏 A6"

        with db.open_session() as s:
            kinds = dict(
                s.query(
                    "SELECT ledger_type, COUNT(*) FROM tbl_stock_ledger "
                    "WHERE order_id = ? GROUP BY ledger_type",
                    (order_id,),
                )
            )
            ptypes = dict(
                s.query(
                    "SELECT point_type, SUM(point_change) FROM tbl_points_ledger "
                    "WHERE order_id = ? GROUP BY point_type",
                    (order_id,),
                )
            )
        assert kinds.get("SALES_USE", 0) == kinds.get("CANCEL_BACK", 0) > 0
        assert ptypes.get("EARN", 0) + ptypes.get("REVOKE", 0) == 0

        # 二次取消必须被拒（状态已经不是 PENDING）——
        # 业务异常统一走 error.html，HTTP 状态是 409，不是 200
        again = client.post("/orders/%d/cancel" % order_id, follow_redirects=True)
        assert again.status_code == 409
        assert "只有「待制作」的订单可以取消" in again.get_data(as_text=True)
    finally:
        _purge(order_id)


def test_cannot_cancel_after_making_started(client):
    """制作台把单推进到 MAKING 之后，取消必须失败，且库存不动。"""
    member_id = 1
    placed = ordering.place_order(member_id, [_first_sellable_item()])
    order_id = placed["order_id"]
    try:
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_order_header SET order_status = 'MAKING' WHERE order_id = ?",
                (order_id,),
            )
            s.commit()
        before = _snapshot(member_id)

        login_member(client, *MEMBER_1)
        resp = client.post("/orders/%d/cancel" % order_id, follow_redirects=True)
        body = resp.get_data(as_text=True)
        assert "只有「待制作」的订单可以取消" in body
        assert _status(order_id) == "MAKING", "失败的取消不能改状态"
        assert _snapshot(member_id)["stock"] == before["stock"], "失败的取消不能动库存"
    finally:
        _purge(order_id)


def test_cannot_cancel_other_members_order(client):
    """取消别人的订单必须 403，而不是"看起来成功"。"""
    member_id = 1
    placed = ordering.place_order(member_id, [_first_sellable_item()])
    order_id = placed["order_id"]
    try:
        login_member(client, *MEMBER_2)
        resp = client.post("/orders/%d/cancel" % order_id, follow_redirects=True)
        assert resp.status_code == 403
        assert _status(order_id) == "PENDING", "越权取消不能生效"
    finally:
        _purge(order_id)
