"""四个岗位工作台的功能断言 + 三层一致的越权断言。

课程任务⑥要求"至少区分店员和顾客两类角色"，任务⑤要求"增删改查"，
任务⑦要求"分别验证合法写入和越权操作失败"。这里按岗位把这三件事钉住：

* **店长**：商品档案的新建 / 修改 / 下架（下架 = 删除的等价物）；
* **库管员**：按采购单收货、报损 —— 且必须验证"改数量必留流水"（A6 不变量）；
* **收银员**：代客下单，散客单不产生积分；
* **跨岗位**：不该进的页面必须是业务层 403，而不是数据层 229。

每条写操作都自己清理干净：测试不能改变三份基线快照的期望值。
"""

import re

import pytest

from app import create_app
from config import Config
from dao import db, product_dao, stock_dao

TEST_CODE = "ZZTEST01"

STAFF = {
    "MANAGER": ("E001", "e001"),
    "CASHIER": ("E002", "e002"),
    "MAKER": ("E003", "e003"),
    "STOCKER": ("E005", "e005"),
}


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


def login_staff(client, role):
    code, password = STAFF[role]
    return client.post("/staff/login", data={"employee_code": code, "password": password})


def _manager():
    return db.open_session("usr_test_manager")


def _cleanup_product(code=TEST_CODE):
    with _manager() as s:
        for row in product_dao.list_products(s):
            if row[1] == code:
                product_dao.hard_delete(s, row[0])
        s.commit()


def _row_by_code(s, code):
    for row in product_dao.list_products(s):
        if row[1] == code:
            return row
    return None


@pytest.fixture(autouse=True)
def _guard():
    _cleanup_product()
    yield
    _cleanup_product()


# ---------------------------------------------------------------- 角色界面


@pytest.mark.parametrize(
    "role,url",
    [("MANAGER", "/manager"), ("CASHIER", "/cashier"), ("STOCKER", "/stocker"), ("MAKER", "/maker")],
)
def test_each_role_has_its_own_workbench(client, role, url):
    login_staff(client, role)
    assert client.get(url).status_code == 200


@pytest.mark.parametrize(
    "role,url",
    [
        ("CASHIER", "/manager"),
        ("MAKER", "/manager"),
        ("STOCKER", "/cashier"),
        ("MAKER", "/stocker"),
        ("CASHIER", "/stocker"),
        ("STOCKER", "/manager"),
    ],
)
def test_workbench_is_denied_by_business_layer(client, role, url):
    """必须断言文案：数据层 229 翻译后也是 403，只看状态码挡不住回归。"""
    login_staff(client, role)
    response = client.get(url)
    assert response.status_code == 403
    assert "当前岗位无权进入该页面" in response.get_data(as_text=True)


def test_staff_login_lands_on_own_workbench(client):
    for role, path in [
        ("MANAGER", "/manager"),
        ("CASHIER", "/cashier"),
        ("STOCKER", "/stocker"),
        ("MAKER", "/maker"),
    ]:
        response = login_staff(client, role)
        assert response.status_code == 302
        assert response.headers["Location"].endswith(path)


# ------------------------------------------------------------ 商品档案维护


def test_manager_can_create_edit_and_retire_product(client):
    login_staff(client, "MANAGER")
    created = client.post(
        "/manager/product/new",
        data={
            "product_code": TEST_CODE,
            "product_name": "测试新品",
            "category_id": "2",
            "base_price": "12.50",
            "product_status": "ON_SALE",
        },
    )
    assert created.status_code == 302

    with _manager() as s:
        row = _row_by_code(s, TEST_CODE)
    assert row is not None
    assert row[2] == "测试新品"
    assert str(row[4]) == "12.5000"
    assert row[5] == "ON_SALE"
    product_id = row[0]

    edited = client.post(
        "/manager/product/%d/edit" % product_id,
        data={"product_name": "测试新品改", "base_price": "13.00", "product_status": "ON_SALE"},
    )
    assert edited.status_code == 302
    with _manager() as s:
        row = _row_by_code(s, TEST_CODE)
    assert row[2] == "测试新品改"
    assert str(row[4]) == "13.0000"

    retired = client.post("/manager/product/%d/retire" % product_id)
    assert retired.status_code == 302
    with _manager() as s:
        row = _row_by_code(s, TEST_CODE)
    assert row[5] == "OFF_SALE", "下架是删除的等价物"

    # 再下架一次是业务规则不满足，不是 500
    again = client.post("/manager/product/%d/retire" % product_id)
    assert again.status_code == 409


def test_product_maintenance_rejects_bad_input(client):
    login_staff(client, "MANAGER")
    bad_price = client.post(
        "/manager/product/new",
        data={
            "product_code": TEST_CODE,
            "product_name": "负价",
            "category_id": "2",
            "base_price": "-1",
            "product_status": "ON_SALE",
        },
    )
    assert bad_price.status_code == 400

    bad_status = client.post(
        "/manager/product/new",
        data={
            "product_code": TEST_CODE,
            "product_name": "坏状态",
            "category_id": "2",
            "base_price": "1",
            "product_status": "SOLD",
        },
    )
    assert bad_status.status_code == 400


def test_cashier_cannot_maintain_products(client):
    login_staff(client, "CASHIER")
    response = client.post(
        "/manager/product/new",
        data={
            "product_code": TEST_CODE,
            "product_name": "越权",
            "category_id": "2",
            "base_price": "1",
            "product_status": "ON_SALE",
        },
    )
    assert response.status_code == 403
    with _manager() as s:
        assert _row_by_code(s, TEST_CODE) is None


# ---------------------------------------------------------------- 库存调整


def _ingredient_with_stock():
    with _manager() as s:
        for row in stock_dao.list_ingredients(s):
            if float(row[5]) > 10 and row[10]:
                return row
    pytest.skip("没有可用原料")


def test_loss_writes_ledger_and_keeps_invariant(client):
    ingredient = _ingredient_with_stock()
    ingredient_id, name, before = ingredient[0], ingredient[2], float(ingredient[5])
    login_staff(client, "STOCKER")

    response = client.post(
        "/stocker/loss",
        data={"ingredient_id": str(ingredient_id), "qty": "1.500", "remark": "测试报损"},
    )
    assert response.status_code == 302

    try:
        with _manager() as s:
            after = float(stock_dao.get_ingredient(s, ingredient_id)[5])
            assert abs((before - after) - 1.5) < 1e-6, "数量必须正好减 1.5"
            assert stock_dao.ledger_drift(s) == [], "改数量必须同时留流水（A6 不变量）"
            rows = s.query(
                "SELECT TOP 1 ledger_type, ref_type, qty, remark, operator_id "
                "  FROM tbl_stock_ledger WHERE ingredient_id = ? ORDER BY ledger_id DESC",
                (ingredient_id,),
            )
        assert rows[0][0] == "LOSS"
        assert rows[0][1] == "MANUAL"
        assert float(rows[0][2]) == -1.5
        assert rows[0][3] == "测试报损"
        assert rows[0][4] == 5, "操作人要落库管员 E005"
    finally:
        # 断言失败也要把痕迹清掉：测试库不是垃圾桶
        with _manager() as s:
            s.execute(
                "DELETE FROM tbl_stock_ledger WHERE ledger_id = "
                "(SELECT MAX(ledger_id) FROM tbl_stock_ledger WHERE ingredient_id = ?)",
                (ingredient_id,),
            )
            s.execute(
                "UPDATE tbl_ingredient SET qty_on_hand = qty_on_hand + 1.5 WHERE ingredient_id = ?",
                (ingredient_id,),
            )
            s.commit()
            assert abs(float(stock_dao.get_ingredient(s, ingredient_id)[5]) - before) < 1e-6


def test_loss_requires_reason_and_positive_qty(client):
    ingredient = _ingredient_with_stock()
    login_staff(client, "STOCKER")
    no_reason = client.post(
        "/stocker/loss",
        data={"ingredient_id": str(ingredient[0]), "qty": "1", "remark": "  "},
    )
    assert no_reason.status_code == 400
    negative = client.post(
        "/stocker/loss",
        data={"ingredient_id": str(ingredient[0]), "qty": "0", "remark": "数量为零"},
    )
    assert negative.status_code == 400


def test_over_loss_is_blocked(client):
    """报损量超过结存 → 业务规则不满足（409），不会写出负库存。"""
    ingredient = _ingredient_with_stock()
    login_staff(client, "STOCKER")
    response = client.post(
        "/stocker/loss",
        data={"ingredient_id": str(ingredient[0]), "qty": "999999", "remark": "超量"},
    )
    assert response.status_code == 409
    with _manager() as s:
        assert float(stock_dao.get_ingredient(s, ingredient[0])[5]) == float(ingredient[5])


def test_receive_purchase_line(client):
    with _manager() as s:
        lines = s.query(
            "SELECT TOP 1 purchase_order_detail_id, ingredient_id, "
            "       qty_ordered - qty_received AS remaining "
            "  FROM tbl_purchase_order_detail WHERE qty_ordered > qty_received "
            " ORDER BY purchase_order_detail_id"
        )
    if not lines:
        pytest.skip("没有待收货明细")
    detail_id, ingredient_id, remaining = lines[0][0], lines[0][1], float(lines[0][2])

    login_staff(client, "STOCKER")
    response = client.post("/stocker/receive", data={"detail_id": str(detail_id), "qty": "1"})
    assert response.status_code == 302

    try:
        with _manager() as s:
            after = s.query_one(
                "SELECT qty_received, qty_ordered FROM tbl_purchase_order_detail "
                " WHERE purchase_order_detail_id = ?",
                (detail_id,),
            )
            assert float(after[1]) - float(after[0]) == pytest.approx(remaining - 1, abs=1e-6)
            assert stock_dao.ledger_drift(s) == []
            last = s.query_one(
                "SELECT ledger_type, ref_type, qty FROM tbl_stock_ledger "
                " WHERE ingredient_id = ? ORDER BY ledger_id DESC",
                (ingredient_id,),
            )
        assert last[0] == "PURCHASE_IN"
        assert last[1] == "PURCHASE"
        assert float(last[2]) == 1.0
    finally:
        with _manager() as s:
            s.execute(
                "UPDATE tbl_purchase_order_detail SET qty_received = qty_received - 1 "
                " WHERE purchase_order_detail_id = ?",
                (detail_id,),
            )
            s.execute(
                "DELETE FROM tbl_stock_ledger WHERE ledger_id = "
                "(SELECT MAX(ledger_id) FROM tbl_stock_ledger WHERE ingredient_id = ?)",
                (ingredient_id,),
            )
            s.execute(
                "UPDATE tbl_ingredient SET qty_on_hand = qty_on_hand - 1 WHERE ingredient_id = ?",
                (ingredient_id,),
            )
            s.commit()


def test_receive_more_than_remaining_is_blocked(client):
    with _manager() as s:
        lines = s.query(
            "SELECT TOP 1 purchase_order_detail_id FROM tbl_purchase_order_detail "
            " WHERE qty_ordered > qty_received ORDER BY purchase_order_detail_id"
        )
    if not lines:
        pytest.skip("没有待收货明细")
    login_staff(client, "STOCKER")
    response = client.post(
        "/stocker/receive", data={"detail_id": str(lines[0][0]), "qty": "99999"}
    )
    assert response.status_code == 409


# ---------------------------------------------------------------- 收银台


def test_cashier_creates_guest_order_without_points(client):
    """散客单：``member_id`` 为空、不写积分、库存照扣 —— 这是 A12 的应用侧落地。"""
    with _manager() as s:
        row = s.query_one(
            "SELECT TOP 1 product_id, cup_spec_id, selling_price "
            "  FROM vw_product_stock_availability "
            " WHERE product_status = 'ON_SALE' AND theor_makeable_cups > 0 "
            " ORDER BY product_id"
        )
        sugar = s.query_one(
            "SELECT TOP 1 spec_option_id FROM tbl_spec_option WHERE spec_type = 'SUGAR' "
            " ORDER BY spec_option_id DESC"
        )
        ice = s.query_one(
            "SELECT TOP 1 spec_option_id FROM tbl_spec_option WHERE spec_type = 'ICE' "
            " ORDER BY spec_option_id"
        )
        points_before = s.query_one("SELECT SUM(points_balance) FROM tbl_member")[0]
        ledger_before = s.query_one("SELECT COUNT(*) FROM tbl_stock_ledger")[0]
    product_id, cup_spec_id = row[0], row[1]

    login_staff(client, "CASHIER")
    response = client.post(
        "/cashier/order",
        data={
            "member_phone": "",
            "product_id": str(product_id),
            "cup_spec_id": str(cup_spec_id),
            "sugar_spec_id": str(sugar[0]),
            "ice_spec_id": str(ice[0]),
            "qty": "1",
        },
    )
    assert response.status_code == 302

    with _manager() as s:
        header = s.query_one(
            "SELECT TOP 1 order_id, member_id, cashier_id, order_status, amount_paid "
            "  FROM tbl_order_header ORDER BY order_id DESC"
        )
        assert header[1] is None, "散客单的 member_id 必须为空"
        assert header[3] == "PENDING"
        order_id = header[0]
        assert s.query_one(
            "SELECT COUNT(*) FROM tbl_points_ledger WHERE order_id = ?", (order_id,)
        )[0] == 0
        assert s.query_one("SELECT SUM(points_balance) FROM tbl_member")[0] == points_before
        assert s.query_one("SELECT COUNT(*) FROM tbl_stock_ledger")[0] > ledger_before

        # 清理：先把这条单扣掉的库存补回去，再按外键逆序删行
        for ingredient_id, qty in s.query(
            "SELECT ingredient_id, qty FROM tbl_stock_ledger WHERE order_id = ?", (order_id,)
        ):
            s.execute(
                "UPDATE tbl_ingredient SET qty_on_hand = qty_on_hand - ? WHERE ingredient_id = ?",
                (qty, ingredient_id),
            )
        s.execute("DELETE FROM tbl_stock_ledger WHERE order_id = ?", (order_id,))
        s.execute(
            "DELETE FROM tbl_order_detail_topping WHERE order_detail_id IN "
            "(SELECT order_detail_id FROM tbl_order_detail WHERE order_id = ?)",
            (order_id,),
        )
        s.execute("DELETE FROM tbl_order_detail WHERE order_id = ?", (order_id,))
        s.execute("DELETE FROM tbl_order_header WHERE order_id = ?", (order_id,))
        s.commit()
        assert stock_dao.ledger_drift(s) == []


def test_cashier_rejects_unknown_member_phone(client):
    with _manager() as s:
        row = s.query_one(
            "SELECT TOP 1 product_id, cup_spec_id FROM vw_product_stock_availability "
            " WHERE product_status = 'ON_SALE' AND theor_makeable_cups > 0 ORDER BY product_id"
        )
        sugar = s.query_one(
            "SELECT TOP 1 spec_option_id FROM tbl_spec_option WHERE spec_type = 'SUGAR' "
            " ORDER BY spec_option_id DESC"
        )
        ice = s.query_one(
            "SELECT TOP 1 spec_option_id FROM tbl_spec_option WHERE spec_type = 'ICE' "
            " ORDER BY spec_option_id"
        )
    login_staff(client, "CASHIER")
    response = client.post(
        "/cashier/order",
        data={
            "member_phone": "13900000000",
            "product_id": str(row[0]),
            "cup_spec_id": str(row[1]),
            "sugar_spec_id": str(sugar[0]),
            "ice_spec_id": str(ice[0]),
            "qty": "1",
        },
    )
    assert response.status_code == 400
    assert re.search(r"没有找到该手机号", response.get_data(as_text=True))
