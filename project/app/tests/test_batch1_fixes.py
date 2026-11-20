"""Batch 1 修复项回归与安全防线测试。

覆盖范围：
  1. 配置对齐与安全默认值（.env.example 键名兼容、弱密钥随机兜底、Cookie 属性、Session 有效期）
  2. CSRF 校验与 POST 登出（CSRF_TEST_ENFORCE=True、GET /logout -> 405、session.permanent）
  3. 经营日报视图 vw_daily_business_summary D 口径过滤与 CARD 渠道统计
  4. 用券订单 amount_due 口径、毛收不重复加折扣、/orders 划线原价与 /me 正常展示
  5. 多杯加料计价与原料扣减 / 取消回冲 / 原料沽清阻断（409）
  6. 下架商品拦截（400）与规格类型（CUP/SUGAR/ICE）校验（400）与 bool 拦截
  7. 制作台推进并发 CAS 保护（CANCELLED 订单不可被复活为 MAKING）

所有写库操作都在 finally 中还原，测试结束后必须保持零数据库漂移。
"""

import importlib
import re
from datetime import timedelta
from decimal import Decimal

import pytest

import app as app_mod
import config as config_mod
from app import create_app
from config import Config
from dao import db, order_dao, stock_dao
from service import maker, ordering
from service.errors import BusinessRuleViolation, ValidationError

MEMBER_1 = ("13800000001", "000001")
STAFF_MAKER = ("E003", "e003")


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


@pytest.fixture()
def csrf_client():
    app = create_app(Config)
    app.config.update(TESTING=True, CSRF_TEST_ENFORCE=True)
    with app.test_client() as c:
        yield c


def _extract_csrf(html: str) -> str:
    match = re.search(r'name="csrf_token"\s+value="([^"]+)"', html)
    assert match, "页面表单缺少 csrf_token 隐藏域"
    return match.group(1)


def _login_member(client, phone=MEMBER_1[0], password=MEMBER_1[1]):
    return client.post("/login", data={"phone": phone, "password": password})


def _member_id(phone: str) -> int:
    with db.open_session() as s:
        return s.query_one("SELECT member_id FROM tbl_member WHERE member_phone = ?", (phone,))[0]


def _first_sellable_item(qty: int = 2) -> dict:
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
        "qty": qty,
        "toppings": [],
    }


def _free_coupon(member_id: int):
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


def _latest_order_id() -> int:
    with db.open_session() as s:
        return s.query_one("SELECT TOP 1 order_id FROM tbl_order_header ORDER BY order_id DESC")[0]


def _order_count() -> int:
    with db.open_session() as s:
        return s.query_one("SELECT COUNT(*) FROM tbl_order_header")[0]


def _purge(order_id: int) -> None:
    """清理单据全部痕迹并按流水重算库存与积分，保证零漂移。"""
    with db.open_session() as s:
        ingredients = [
            r[0]
            for r in s.query(
                "SELECT DISTINCT ingredient_id FROM tbl_stock_ledger WHERE order_id = ?",
                (order_id,),
            )
        ]
        members = [
            r[0]
            for r in s.query(
                "SELECT DISTINCT member_id FROM tbl_points_ledger WHERE order_id = ?",
                (order_id,),
            )
        ]
        coupon = s.query_one(
            "SELECT coupon_id FROM tbl_order_header WHERE order_id = ?", (order_id,)
        )
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


# ------------------------------------------------------------ 1. 配置与安全基线


def test_config_cookie_flags_and_session_lifetime():
    assert Config.SESSION_COOKIE_HTTPONLY is True
    assert Config.SESSION_COOKIE_SAMESITE == "Lax"
    assert Config.CSRF_ENABLED is True
    assert isinstance(Config.PERMANENT_SESSION_LIFETIME, timedelta)
    assert Config.PERMANENT_SESSION_LIFETIME == timedelta(minutes=Config.SESSION_MINUTES)
    assert Config.SECRET_KEY not in ("", "dev-only-change-me", "change-me-to-a-random-string")


def test_config_env_example_names_and_weak_secret_fallback(monkeypatch, capsys):
    try:
        with monkeypatch.context() as mp:
            mp.setenv("APP_SECRET_KEY", "")
            mp.setenv("SECRET_KEY", "test-only-strong-key-not-a-weak-default")
            mp.setenv("SQL_TRUSTED_CONNECTION", "")
            mp.setenv("SQL_TRUSTED", "false")
            mp.setenv("APP_SESSION_MINUTES", "")
            mp.setenv("SESSION_MINUTES", "45")
            reloaded = importlib.reload(config_mod)
            assert reloaded.Config.SECRET_KEY == "test-only-strong-key-not-a-weak-default"
            assert reloaded.Config.SECRET_KEY_EPHEMERAL is False
            assert reloaded.Config.SQL_TRUSTED is False
            assert reloaded.Config.SESSION_MINUTES == 45
            assert reloaded.Config.PERMANENT_SESSION_LIFETIME == timedelta(minutes=45)

        for weak in ("", "dev-only-change-me", "change-me-to-a-random-string"):
            with monkeypatch.context() as mp:
                mp.setenv("APP_SECRET_KEY", weak)
                mp.setenv("SECRET_KEY", "")
                reloaded = importlib.reload(config_mod)
                assert reloaded.Config.SECRET_KEY_EPHEMERAL is True
                assert reloaded.Config.SECRET_KEY != weak
                assert len(reloaded.Config.SECRET_KEY) == 64

                capsys.readouterr()
                tmp_app = create_app(reloaded.Config)
                err = capsys.readouterr().err
                assert "SECRET_KEY" in err
                assert reloaded.Config.SECRET_KEY not in err
                assert tmp_app.config["SESSION_COOKIE_HTTPONLY"] is True
    finally:
        restored = importlib.reload(config_mod)
        db.Config = restored.Config
        app_mod.Config = restored.Config


# ------------------------------------------------------------ 2. CSRF 与会话控制


def test_csrf_enforced_session_permanent_and_post_logout(csrf_client):
    # 无 CSRF token 提交登录必须 403
    no_tok = csrf_client.post(
        "/login", data={"phone": MEMBER_1[0], "password": MEMBER_1[1]}
    )
    assert no_tok.status_code == 403

    # 正常带 token 登录成功，且 session.permanent 与 Cookie 标记生效
    page = csrf_client.get("/login")
    assert page.status_code == 200
    token = _extract_csrf(page.get_data(as_text=True))

    ok = csrf_client.post(
        "/login",
        data={"phone": MEMBER_1[0], "password": MEMBER_1[1], "csrf_token": token},
        follow_redirects=False,
    )
    assert ok.status_code == 302
    cookies = ok.headers.getlist("Set-Cookie")
    assert any("HttpOnly" in c and "SameSite=Lax" in c for c in cookies)
    with csrf_client.session_transaction() as sess:
        assert sess.permanent is True
        assert "member" in sess

    # 已登录状态下 POST /order 缺 token 必须 403
    no_order_tok = csrf_client.post("/order", data={"qty": "0"})
    assert no_order_tok.status_code == 403

    # GET /logout 必须返回 405；无 token POST /logout 必须 403
    assert csrf_client.get("/logout").status_code == 405
    assert csrf_client.post("/logout").status_code == 403

    # 从菜单页提取新 session 的 CSRF token 执行 POST /logout -> 302 并清空会话
    menu_page = csrf_client.get("/")
    assert menu_page.status_code == 200
    logout_token = _extract_csrf(menu_page.get_data(as_text=True))
    out = csrf_client.post("/logout", data={"csrf_token": logout_token}, follow_redirects=False)
    assert out.status_code == 302
    assert "/login" in out.headers["Location"]
    with csrf_client.session_transaction() as sess:
        assert "member" not in sess

    # 员工登录同样走 CSRF 并启用 session.permanent
    staff_page = csrf_client.get("/staff/login")
    staff_token = _extract_csrf(staff_page.get_data(as_text=True))
    staff_ok = csrf_client.post(
        "/staff/login",
        data={
            "employee_code": STAFF_MAKER[0],
            "password": STAFF_MAKER[1],
            "csrf_token": staff_token,
        },
        follow_redirects=False,
    )
    assert staff_ok.status_code == 302
    with csrf_client.session_transaction() as sess:
        assert sess.permanent is True
        assert sess["staff"]["role"] == "MAKER"


# ------------------------------------------------------------ 3. 经营日报 D 口径


def test_daily_business_summary_matches_d_metric_and_card_channel():
    with db.open_session() as s:
        seed_row = s.query_one(
            """
            SELECT SUM(net_revenue),
                   SUM(total_cups),
                   SUM(card_revenue),
                   SUM(wechat_revenue + alipay_revenue + cash_revenue + card_revenue)
            FROM vw_daily_business_summary
            WHERE business_date < '2026-09-24'
            """
        )
        all_row = s.query_one(
            """
            SELECT SUM(net_revenue),
                   SUM(wechat_revenue + alipay_revenue + cash_revenue + card_revenue)
            FROM vw_daily_business_summary
            """
        )
    assert seed_row[0] == Decimal("23762.00")
    assert seed_row[1] == 2579
    assert seed_row[2] == Decimal("507.00")
    assert seed_row[3] == seed_row[0]
    assert all_row[1] == all_row[0]


# ------------------------------------------------------------ 4. 用券口径与订单页展示


def test_coupon_order_gross_sales_and_orders_page_rendering(client):
    member_id = _member_id(MEMBER_1[0])
    coupon = _free_coupon(member_id)
    assert coupon is not None
    coupon_id, face = coupon

    item = _first_sellable_item(qty=2)
    with db.open_session() as s:
        today = order_dao.today(s)
        before_summary = s.query_one(
            "SELECT ISNULL(gross_sales, 0), ISNULL(total_discount, 0), ISNULL(net_revenue, 0) "
            "FROM vw_daily_business_summary WHERE business_date = ?",
            (today,),
        ) or (Decimal("0.00"), Decimal("0.00"), Decimal("0.00"))

    _login_member(client)
    resp = client.post(
        "/order",
        data={
            "product_id": str(item["product_id"]),
            "cup_spec_id": str(item["cup_spec_id"]),
            "sugar_spec_id": str(item["sugar_spec_id"]),
            "ice_spec_id": str(item["ice_spec_id"]),
            "qty": str(item["qty"]),
            "coupon_id": str(coupon_id),
        },
        follow_redirects=False,
    )
    assert resp.status_code == 302
    order_id = _latest_order_id()

    try:
        with db.open_session() as s:
            head = s.query_one(
                "SELECT order_no, amount_due, discount_amount, amount_paid "
                "FROM tbl_order_header WHERE order_id = ?",
                (order_id,),
            )
            detail_sum = s.query_one(
                "SELECT SUM(subtotal) FROM tbl_order_detail WHERE order_id = ?",
                (order_id,),
            )[0]
            after_summary = s.query_one(
                "SELECT gross_sales, total_discount, net_revenue "
                "FROM vw_daily_business_summary WHERE business_date = ?",
                (today,),
            )
        order_no, due, discount, paid = head
        assert discount == face
        assert due == detail_sum - discount
        assert paid == due

        assert after_summary[0] - before_summary[0] == detail_sum
        assert after_summary[1] - before_summary[1] == discount
        assert after_summary[2] - before_summary[2] == paid

        orders_page = client.get("/orders")
        assert orders_page.status_code == 200
        orders_html = orders_page.get_data(as_text=True)
        assert order_no in orders_html
        assert '<span class="price-was">%.2f</span>' % detail_sum in orders_html

        me_page = client.get("/me")
        assert me_page.status_code == 200
        me_html = me_page.get_data(as_text=True)
        assert order_no in me_html
        assert ("%.2f 元" % paid) in me_html
        assert "· SUCCESS" not in me_html
    finally:
        _purge(order_id)


# ------------------------------------------------------------ 5. 多杯加料计价与扣料


def test_multi_cup_topping_pricing_stock_and_sold_out_block(client):
    item = _first_sellable_item(qty=2)
    with db.open_session() as s:
        cup_price = Decimal(
            str(
                s.query_one(
                    "SELECT selling_price FROM vw_product_stock_availability "
                    "WHERE product_id = ? AND cup_spec_id = ?",
                    (item["product_id"], item["cup_spec_id"]),
                )[0]
            )
        )
        t_row = s.query_one(
            "SELECT topping_id, extra_price, ingredient_id, qty_per_serving "
            "FROM tbl_topping WHERE is_active = 1 ORDER BY topping_id"
        )
        topping_id, topping_price, t_ing_id, t_per_serving = (
            int(t_row[0]),
            Decimal(str(t_row[1])),
            int(t_row[2]),
            Decimal(str(t_row[3])),
        )
        recipe_rows = dict(
            order_dao.recipe_usage(s, item["product_id"], item["cup_spec_id"], item["sugar_spec_id"])
        )
        before_ing_qty = Decimal(
            str(
                s.query_one(
                    "SELECT qty_on_hand FROM tbl_ingredient WHERE ingredient_id = ?",
                    (t_ing_id,),
                )[0]
            )
        )
        before_sold_out = bool(
            s.query_one(
                "SELECT is_sold_out FROM tbl_ingredient WHERE ingredient_id = ?",
                (t_ing_id,),
            )[0]
        )

    expected_topping_deduct = Decimal(str(recipe_rows.get(t_ing_id, 0))) * 2 + t_per_serving * 2

    _login_member(client)
    resp = client.post(
        "/order",
        data={
            "product_id": str(item["product_id"]),
            "cup_spec_id": str(item["cup_spec_id"]),
            "sugar_spec_id": str(item["sugar_spec_id"]),
            "ice_spec_id": str(item["ice_spec_id"]),
            "qty": "2",
            "topping_id_0": str(topping_id),
        },
        follow_redirects=False,
    )
    assert resp.status_code == 302
    order_id = _latest_order_id()

    try:
        with db.open_session() as s:
            detail = s.query_one(
                "SELECT order_detail_id, subtotal FROM tbl_order_detail WHERE order_id = ?",
                (order_id,),
            )
            dt = s.query_one(
                "SELECT qty, unit_extra_price FROM tbl_order_detail_topping WHERE order_detail_id = ?",
                (detail[0],),
            )
            after_ing_qty = Decimal(
                str(
                    s.query_one(
                        "SELECT qty_on_hand FROM tbl_ingredient WHERE ingredient_id = ?",
                        (t_ing_id,),
                    )[0]
                )
            )
            sales_move = s.query_one(
                "SELECT qty FROM tbl_stock_ledger "
                "WHERE order_id = ? AND ingredient_id = ? AND ledger_type = 'SALES_USE'",
                (order_id, t_ing_id),
            )
            assert stock_dao.ledger_drift(s) == []

        assert detail[1] == (cup_price + topping_price) * 2
        assert int(dt[0]) == 2
        assert dt[1] == topping_price
        assert before_ing_qty - after_ing_qty == expected_topping_deduct
        assert Decimal(str(sales_move[0])) == -expected_topping_deduct

        # 取消后加料原料也必须如数回冲且零漂移
        cancel_resp = client.post("/orders/%d/cancel" % order_id, follow_redirects=False)
        assert cancel_resp.status_code == 302
        with db.open_session() as s:
            restored_qty = Decimal(
                str(
                    s.query_one(
                        "SELECT qty_on_hand FROM tbl_ingredient WHERE ingredient_id = ?",
                        (t_ing_id,),
                    )[0]
                )
            )
            assert restored_qty == before_ing_qty
            assert stock_dao.ledger_drift(s) == []
    finally:
        _purge(order_id)

    # 加料对应原料沽清时，下单必须 409 被拒且不落单
    before_count = _order_count()
    try:
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_ingredient SET is_sold_out = 1 WHERE ingredient_id = ?",
                (t_ing_id,),
            )
            s.commit()

        blocked = client.post(
            "/order",
            data={
                "product_id": str(item["product_id"]),
                "cup_spec_id": str(item["cup_spec_id"]),
                "sugar_spec_id": str(item["sugar_spec_id"]),
                "ice_spec_id": str(item["ice_spec_id"]),
                "qty": "1",
                "topping_id_0": str(topping_id),
            },
            follow_redirects=True,
        )
        assert blocked.status_code == 409
        assert "已沽清" in blocked.get_data(as_text=True)
        assert _order_count() == before_count
    finally:
        with db.open_session() as s:
            s.execute(
                "UPDATE tbl_ingredient SET is_sold_out = ? WHERE ingredient_id = ?",
                (1 if before_sold_out else 0, t_ing_id),
            )
            s.commit()

    # 业务层直接校验：重复加料 / 非法份数
    member_id = _member_id(MEMBER_1[0])
    dup_item = dict(item, toppings=[{"topping_id": topping_id, "qty": 1}, {"topping_id": topping_id, "qty": 1}])
    with pytest.raises(ValidationError):
        ordering.place_order(member_id, [dup_item])
    bad_qty_item = dict(item, toppings=[{"topping_id": topping_id, "qty": True}])
    with pytest.raises(ValidationError):
        ordering.place_order(member_id, [bad_qty_item])


# ------------------------------------------------------------ 6. 下架商品与规格校验


def test_off_sale_product_and_invalid_spec_type_blocked(client):
    with db.open_session() as s:
        off_sale = s.query_one(
            """
            SELECT TOP 1 r.product_id, r.cup_spec_id
            FROM tbl_recipe r
            JOIN tbl_product p ON p.product_id = r.product_id
            WHERE p.product_status = 'OFF_SALE'
            ORDER BY r.product_id, r.cup_spec_id
            """
        )
    assert off_sale is not None, "测试前提：种子数据应包含已下架商品 P030"

    valid = _first_sellable_item(qty=1)
    before_count = _order_count()
    _login_member(client)

    # 下架商品直调 POST /order 必须 400
    resp_off = client.post(
        "/order",
        data={
            "product_id": str(off_sale[0]),
            "cup_spec_id": str(off_sale[1]),
            "sugar_spec_id": str(valid["sugar_spec_id"]),
            "ice_spec_id": str(valid["ice_spec_id"]),
            "qty": "1",
        },
        follow_redirects=True,
    )
    assert resp_off.status_code == 400
    assert "不可售" in resp_off.get_data(as_text=True)
    assert _order_count() == before_count

    # 规格错位（把 cup_spec_id 传成 sugar_spec_id）必须 400
    resp_spec = client.post(
        "/order",
        data={
            "product_id": str(valid["product_id"]),
            "cup_spec_id": str(valid["cup_spec_id"]),
            "sugar_spec_id": str(valid["cup_spec_id"]),
            "ice_spec_id": str(valid["ice_spec_id"]),
            "qty": "1",
        },
        follow_redirects=True,
    )
    assert resp_spec.status_code == 400
    assert "规格选项无效" in resp_spec.get_data(as_text=True)
    assert _order_count() == before_count

    # bool 传入 qty / product_id 必须被拒绝
    member_id = _member_id(MEMBER_1[0])
    with pytest.raises(ValidationError):
        ordering.place_order(member_id, [dict(valid, qty=True)])
    with pytest.raises(ValidationError):
        ordering.place_order(member_id, [dict(valid, product_id=True)])


# ------------------------------------------------------------ 7. 制作台并发 CAS


def test_maker_advance_cas_cannot_resurrect_cancelled_order(monkeypatch):
    member_id = _member_id(MEMBER_1[0])
    placed = ordering.place_order(member_id, [_first_sellable_item(qty=1)])
    order_id = placed["order_id"]
    try:
        ordering.cancel_order(order_id, member_id=member_id)

        with db.open_session("usr_test_maker") as s:
            affected = order_dao.update_status(
                s, order_id, "MAKING", expected_status="PENDING"
            )
            s.commit()
            assert affected == 0
            assert order_dao.get_status(s, order_id) == "CANCELLED"

        with pytest.raises(BusinessRuleViolation):
            maker.advance("MAKER", order_id)

        # 模拟并发竞态：初读状态为 PENDING，但实际数据库已变为 CANCELLED
        monkeypatch.setattr(order_dao, "get_status", lambda s, oid: "PENDING")
        with pytest.raises(BusinessRuleViolation, match="订单状态已被其他操作改变"):
            maker.advance("MAKER", order_id)

        with db.open_session() as s:
            assert s.query_one(
                "SELECT order_status FROM tbl_order_header WHERE order_id = ?", (order_id,)
            )[0] == "CANCELLED"
    finally:
        _purge(order_id)
