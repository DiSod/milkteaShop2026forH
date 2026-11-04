"""配置：全项目唯一读取环境变量的地方。

课程要求「数据库连接信息放在配置中，不写死在页面代码里」——本模块是那句话的落点。
密钥与连接串都不进 git，见 ``.env.example`` 与 ``harness/conventions/04-git-workflow.md`` §4。
"""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent


def _load_dotenv(path: Path) -> None:
    """极简 .env 读取：只支持 KEY=VALUE，够用且不引依赖。"""
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


_load_dotenv(BASE_DIR / ".env")


class Config:
    """应用配置。所有值都可以用环境变量覆盖。"""

    SECRET_KEY = os.environ.get("APP_SECRET_KEY", "dev-only-change-me")

    SQL_DRIVER = os.environ.get("SQL_DRIVER", "ODBC Driver 17 for SQL Server")
    SQL_SERVER = os.environ.get("SQL_SERVER", r".\SQLEXPRESS")
    SQL_DATABASE = os.environ.get("SQL_DATABASE", "milktea_shop")
    SQL_TRUSTED = os.environ.get("SQL_TRUSTED_CONNECTION", "yes").lower() == "yes"

    SESSION_MINUTES = int(os.environ.get("APP_SESSION_MINUTES", "30"))
    PERMANENT_SESSION_LIFETIME_MINUTES = SESSION_MINUTES

    @classmethod
    def connection_string(cls) -> str:
        parts = [
            "DRIVER={%s}" % cls.SQL_DRIVER,
            "SERVER=%s" % cls.SQL_SERVER,
            "DATABASE=%s" % cls.SQL_DATABASE,
        ]
        if cls.SQL_TRUSTED:
            parts.append("Trusted_Connection=yes")
        else:
            parts.append("UID=%s" % os.environ.get("SQL_USER", ""))
            parts.append("PWD=%s" % os.environ.get("SQL_PASSWORD", ""))
        parts.append("Encrypt=yes")
        parts.append("TrustServerCertificate=yes")
        return ";".join(parts)


# 应用角色 → 数据库受限身份。
# 说明：v1.0 的 08-security/role.sql 只建了 cashier / maker / stocker / manager 四个
# 数据库身份，没有「会员」身份（顾客=会员的裁定晚于 role.sql）。因此顾客侧暂时借用
# 收银员的身份——它的授权集合恰好覆盖顾客所需（读商品/规格、读写会员、下单）。
# 待办：新增 usr_test_member 后再把 MEMBER 映射过来，见 project/app/README.md §5。
ROLE_DB_USER = {
    "MEMBER": "usr_test_cashier",
    "CASHIER": "usr_test_cashier",
    "MAKER": "usr_test_maker",
    "STOCKER": "usr_test_stocker",
    "MANAGER": "usr_test_manager",
}


def db_user_for(role: str):
    """把应用角色翻译成数据库身份；未知角色返回 None（= 不切身份）。"""
    return ROLE_DB_USER.get((role or "").upper())
