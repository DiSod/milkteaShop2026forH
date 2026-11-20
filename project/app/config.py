"""配置：全项目唯一读取环境变量的地方。

课程要求「数据库连接信息放在配置中，不写死在页面代码里」——本模块是那句话的落点。
密钥与连接串都不进 git，见 ``.env.example`` 与 ``harness/conventions/04-git-workflow.md`` §4。
"""

import os
import secrets
from datetime import timedelta
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

_WEAK_SECRETS = frozenset({"", "dev-only-change-me", "change-me-to-a-random-string"})


def _env_first(*keys: str, default: str = "") -> str:
    """按优先级读取首个非空环境变量，兼容 APP_* 与 .env.example 命名。"""
    for key in keys:
        value = os.environ.get(key)
        if value is not None and value.strip():
            return value.strip()
    return default


def _resolve_secret_key() -> tuple:
    raw = _env_first("APP_SECRET_KEY", "SECRET_KEY")
    if raw in _WEAK_SECRETS:
        return secrets.token_hex(32), True
    return raw, False


class Config:
    """应用配置。所有值都可以用环境变量覆盖。"""

    SECRET_KEY, SECRET_KEY_EPHEMERAL = _resolve_secret_key()

    SQL_DRIVER = _env_first("SQL_DRIVER", default="ODBC Driver 17 for SQL Server")
    SQL_SERVER = _env_first("SQL_SERVER", default=r".\SQLEXPRESS")
    SQL_DATABASE = _env_first("SQL_DATABASE", default="milktea_shop")
    SQL_TRUSTED = _env_first("SQL_TRUSTED_CONNECTION", "SQL_TRUSTED", default="yes").lower() in (
        "yes",
        "true",
        "1",
    )

    SESSION_MINUTES = int(_env_first("APP_SESSION_MINUTES", "SESSION_MINUTES", default="30"))
    PERMANENT_SESSION_LIFETIME = timedelta(minutes=SESSION_MINUTES)
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    CSRF_ENABLED = True

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
