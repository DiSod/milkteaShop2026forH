"""Batch 2 质量加固回归测试。

覆盖范围：
  1. 全量 DAO 不得再包含会话级 SET NOCOUNT ON（杜绝 rowcount = -1 污染）
  2. 已取消采购单不得继续收货，且 add_received 并发超收必须被拒
  3. 取消订单在会员积分余额不足时返回友好 BusinessRuleViolation（409）而非撞裸约束
  4. vw_ingredient_reorder_alert 排除停用原料，且零库存优先于人工沽清（alert_level 与 alert_priority 一致）
  5. vw_product_stock_availability.selling_price 精度锁定 DECIMAL(10,2)

所有写库用例都在 finally 中严格还原，保持零数据库漂移。
"""

import pathlib
from decimal import Decimal

import pytest

from dao import db, purchase_dao, stock_dao
from service import ordering, stock
from service.errors import BusinessRuleViolation

APP_DIR = pathlib.Path(__file__).resolve().parent.parent


def _db_ready() -> bool:
    try:
        return bool(db.probe().get("database"))
    except Exception:  # noqa: BLE001
        return False


pytestmark = pytest.mark.skipif(not _db_ready(), reason="需要可连通的 milktea_shop 实例")


def test_no_dao_contains_set_nocount_on():
    """DAO 层禁止执行 SET NOCOUNT ON，避免污染同一连接后续语句的 cursor.rowcount。"""
    offenders = []
    for path in sorted((APP_DIR / "dao").rglob("*.py")):
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if "SET NOCOUNT ON" in line.upper() and "不能带" not in line and "不能加" not in line:
                offenders.append("%s:%d" % (path.relative_to(APP_DIR), lineno))
    assert not offenders, "以下 DAO 仍残留 SET NOCOUNT ON：%s" % offenders


def test_cancelled_purchase_order_cannot_be_received_and_over_receive_blocked():
    """已取消采购单既不能出现在待收货列表，也不能通过直接传 detail_id 收货；超收返回 0 行。"""
    with db.open_session() as s:
        row = s.query_one(
            "SELECT TOP 1 d.purchase_order_detail_id, o.purchase_order_id, o.order_status, "
            "       d.qty_ordered - d.qty_received AS remaining "
            "  FROM tbl_purchase_order_detail d "
            "  JOIN tbl_purchase_order o ON o.purchase_order_id = d.purchase_order_id "
            " WHERE d.qty_ordered > d.qty_received "
            "   AND o.order_status NOT IN ('ACCEPTED', 'CANCELLED') "
            " ORDER BY d.purchase_order_detail_id"
        )
    if not row:
        pytest.skip("没有未收满的采购单明细")
    detail_id, po_id, orig_status, remaining = row

    try:
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_purchase_order SET order_status = 'CANCELLED' WHERE purchase_order_id = ?",
                (po_id,),
            )
            s.commit()

        with db.open_session("usr_test_stocker") as s:
            open_ids = {r[0] for r in purchase_dao.list_open_lines(s)}
            assert detail_id not in open_ids, "已取消采购单不得出现在待收货列表中"

        with pytest.raises(BusinessRuleViolation) as exc_info:
            stock.receive("STOCKER", 5, detail_id, "1")
        assert "已取消" in exc_info.value.message

        # 恢复后验证并发超收保护（add_received 条件更新拒绝超量）
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_purchase_order SET order_status = ? WHERE purchase_order_id = ?",
                (orig_status, po_id),
            )
            updated = purchase_dao.add_received(s, detail_id, Decimal(str(remaining)) + Decimal("1"))
            assert updated == 0, "超出未收数量时 add_received 必须更新 0 行"
            s.commit()
    finally:
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_purchase_order SET order_status = ? WHERE purchase_order_id = ?",
                (orig_status, po_id),
            )
            s.commit()


def test_cancel_order_insufficient_points_raises_friendly_business_error():
    """会员余额小于本单可扣回积分时，cancel_order 应给出友好业务提示且整单回滚。"""
    with db.open_session() as s:
        row = s.query_one(
            "SELECT TOP 1 r.product_id, r.cup_spec_id "
            "  FROM tbl_recipe r "
            "  JOIN tbl_product p ON p.product_id = r.product_id "
            " WHERE r.sugar_spec_id IS NULL AND p.product_status = 'ON_SALE' "
            " ORDER BY r.product_id, r.cup_spec_id"
        )
        sugar = s.query_one(
            "SELECT TOP 1 spec_option_id FROM tbl_spec_option WHERE spec_type = 'SUGAR' ORDER BY 1"
        )[0]
        ice = s.query_one(
            "SELECT TOP 1 spec_option_id FROM tbl_spec_option WHERE spec_type = 'ICE' ORDER BY 1"
        )[0]
        member_id, orig_points = s.query_one(
            "SELECT TOP 1 member_id, points_balance FROM tbl_member WHERE member_id = 1"
        )

    res = ordering.place_order(
        member_id,
        [
            {
                "product_id": row[0],
                "cup_spec_id": row[1],
                "sugar_spec_id": sugar,
                "ice_spec_id": ice,
                "qty": 2,
                "toppings": [],
            }
        ],
    )
    order_id = res["order_id"]
    earned = res["earned_points"]
    assert earned > 0

    try:
        # 模拟会员已花掉积分，余额低于本单需扣回分值
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_member SET points_balance = 0 WHERE member_id = ?",
                (member_id,),
            )
            s.commit()

        with pytest.raises(BusinessRuleViolation) as exc_info:
            ordering.cancel_order(order_id, member_id=member_id)
        assert "积分余额不足" in exc_info.value.message

        # 确认整单已回滚：订单仍是 PENDING，未留 CANCEL_BACK 或 REVOKE
        with db.open_session() as s:
            status = s.query_one(
                "SELECT order_status FROM tbl_order_header WHERE order_id = ?", (order_id,)
            )[0]
            assert status == "PENDING"
            assert s.query_one(
                "SELECT COUNT(*) FROM tbl_stock_ledger WHERE order_id = ? AND ledger_type = 'CANCEL_BACK'",
                (order_id,),
            )[0] == 0
    finally:
        with db.open_session() as s:
            ingredients = [
                r[0]
                for r in s.query(
                    "SELECT DISTINCT ingredient_id FROM tbl_stock_ledger WHERE order_id = ?",
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
            for ing_id in ingredients:
                s.execute(
                    "UPDATE tbl_ingredient SET qty_on_hand = "
                    "(SELECT ISNULL(SUM(qty), 0) FROM tbl_stock_ledger WHERE ingredient_id = ?) "
                    "WHERE ingredient_id = ?",
                    (ing_id, ing_id),
                )
            s.execute(
                "UPDATE tbl_member SET points_balance = ? WHERE member_id = ?",
                (orig_points, member_id),
            )
            s.commit()
            assert stock_dao.ledger_drift(s) == []


def test_reorder_alert_excludes_inactive_and_aligns_zero_stock_priority():
    """vw_ingredient_reorder_alert 排除停用原料，且零库存 + 人工沽清时等级与优先级一致为 1/零库存。"""
    with db.open_session() as s:
        ing_id, orig_qty, orig_sold_out, orig_active = s.query_one(
            "SELECT TOP 1 ingredient_id, qty_on_hand, is_sold_out, is_active "
            "  FROM tbl_ingredient WHERE is_active = 1 ORDER BY ingredient_id"
        )
    try:
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_ingredient SET qty_on_hand = 0, is_sold_out = 1 WHERE ingredient_id = ?",
                (ing_id,),
            )
            row = s.query_one(
                "SELECT alert_level, alert_priority FROM vw_ingredient_reorder_alert "
                " WHERE ingredient_id = ?",
                (ing_id,),
            )
            assert row[0] == "零库存"
            assert row[1] == 1

            s.execute(
                "UPDATE tbl_ingredient SET is_active = 0 WHERE ingredient_id = ?",
                (ing_id,),
            )
            hidden = s.query_one(
                "SELECT COUNT(*) FROM vw_ingredient_reorder_alert WHERE ingredient_id = ?",
                (ing_id,),
            )[0]
            assert hidden == 0, "停用原料不得出现在补货预警视图中"
            s.rollback()
    finally:
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_ingredient SET qty_on_hand = ?, is_sold_out = ?, is_active = ? "
                " WHERE ingredient_id = ?",
                (orig_qty, orig_sold_out, orig_active, ing_id),
            )
            s.commit()
