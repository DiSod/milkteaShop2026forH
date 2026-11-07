"""权限三层一致性 + 行级隔离的可执行断言。

课程段落 12：「页面可以根据角色隐藏按钮，但**真正的权限检查必须在后端业务层
再次执行**」。所以这里只测后端这一层 —— 一个岗位不该进的页面，必须由业务层
给出 403，而不是等数据层报 229 才算「拦住」。

另外两条测的是行级隔离：RBAC 只管「能不能碰这张表」，管不了「能碰哪几行」，
行级过滤只能由应用自己写进 ``WHERE``，所以必须有一条断言把它钉住。
"""

import re

import pytest

from app import create_app
from config import Config


def _db_ready() -> bool:
    try:
        from dao import db

        info = db.probe()
        return bool(info.get("database"))
    except Exception:  # noqa: BLE001
        return False


pytestmark = pytest.mark.skipif(not _db_ready(), reason="需要可连通的 milktea_shop 实例")

ORDER_NO = re.compile(r"20\d{6}-\d{4}")

# 实测在库的账号（见 project/app/README.md §4）
MEMBER_1 = ("13800000001", "000001")
STAFF = {
    "MANAGER": ("E001", "e001"),
    "CASHIER": ("E002", "e002"),
    "MAKER": ("E003", "e003"),
    "STOCKER": ("E005", "e005"),
}


@pytest.fixture()
def client():
    app = create_app(Config)
    app.config.update(TESTING=True)
    with app.test_client() as c:
        yield c


def login_member(client, phone, password):
    return client.post("/login", data={"phone": phone, "password": password})


def login_staff(client, code, password):
    return client.post("/staff/login", data={"employee_code": code, "password": password})


def own_order_numbers(member_id: int) -> set:
    """直接问库：这个会员名下到底有哪些单号。"""
    from dao import db

    with db.open_session("usr_test_cashier") as s:
        rows = s.query("SELECT order_no FROM tbl_order_header WHERE member_id = ?", (member_id,))
        return {r[0] for r in rows}


# ---------------------------------------------------------------- 行级隔离


def test_member_order_page_only_contains_own_orders(client):
    """顾客的订单页只应出现自己的单号 —— 行级隔离全靠这条 WHERE。"""
    login_member(client, *MEMBER_1)
    resp = client.get("/orders")
    assert resp.status_code == 200

    body = resp.get_data(as_text=True)
    shown = set(ORDER_NO.findall(body))
    assert shown, "订单页一个单号都没渲染出来，断言失去意义"

    mine = own_order_numbers(1)
    assert shown <= mine, "订单页出现了不属于该会员的单号：%s" % sorted(shown - mine)


def test_member_api_does_not_leak_other_rows(client):
    """`/me` 返回体里不该出现别人的手机号。"""
    login_member(client, *MEMBER_1)
    resp = client.get("/me")
    assert resp.status_code == 200
    body = resp.get_data(as_text=True)
    assert "13800000001" in body  # 自己的
    for phone in ("13800000002", "13800000005", "13800000080"):
        assert phone not in body, "页面泄露了其他会员的手机号：%s" % phone


# ---------------------------------------------------------------- 业务层权限


def test_stocker_is_blocked_by_business_layer(client):
    """库管员不属于制作台岗位，应当被业务层 403，而不是靠数据层 229 兜底。

    两者都会是 403，所以断言必须看**文案**：业务层的拒绝语是
    「当前岗位无权进入该页面」（web/security.py），数据层透出来的是 SQL Server
    的「拒绝了对对象 … 的 SELECT 权限」。只断言状态码的话，这条测试挡不住回归。
    """
    login_staff(client, *STAFF["STOCKER"])
    resp = client.get("/maker")
    assert resp.status_code == 403
    assert "当前岗位无权进入该页面" in resp.get_data(as_text=True)


def test_cashier_is_blocked_by_business_layer(client):
    login_staff(client, *STAFF["CASHIER"])
    resp = client.get("/maker")
    assert resp.status_code == 403
    assert "当前岗位无权进入该页面" in resp.get_data(as_text=True)


def test_maker_can_open_workbench(client):
    login_staff(client, *STAFF["MAKER"])
    resp = client.get("/maker")
    assert resp.status_code == 200


def test_manager_can_open_workbench(client):
    login_staff(client, *STAFF["MANAGER"])
    resp = client.get("/maker")
    assert resp.status_code == 200


def test_stocker_cannot_advance_order_status(client):
    """状态推进是 POST 入口，同样必须被业务层拒绝。"""
    login_staff(client, *STAFF["STOCKER"])
    resp = client.post("/maker/order/1/next")
    assert resp.status_code == 403
    assert "当前岗位无权进入该页面" in resp.get_data(as_text=True)


def test_anonymous_is_redirected_to_staff_login(client):
    resp = client.get("/maker")
    assert resp.status_code == 302
    assert "/staff/login" in resp.headers["Location"]


def test_every_staff_role_lands_on_a_workbench(client):
    """四个岗位各有一个工作台：登录后不该停在登录页，也不该撞 403。

    （第 7 周之前只有制作台，收银员/库管员登录会被送回登录页并提示"排在第 8—9 周"；
    角色界面补全后这条断言改为"必须落到自己的入口"。）
    """
    expected = {
        "MANAGER": "/manager",
        "CASHIER": "/cashier",
        "MAKER": "/maker",
        "STOCKER": "/stocker",
    }
    for role, path in expected.items():
        resp = login_staff(client, *STAFF[role])
        assert resp.status_code == 302
        assert resp.headers["Location"].endswith(path)
