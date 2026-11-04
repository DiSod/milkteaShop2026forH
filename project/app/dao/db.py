"""数据访问层的基础设施：**全项目唯一 import pyodbc 的模块之一**。

三件事在这里统一做掉（课程段落 10 的原文要求）：
  连接管理 / 参数绑定 / 事务的提交与回滚与连接释放

第四件事是本项目加码的：**每次会话切换数据库受限身份**（``EXECUTE AS USER``），
让「权限在数据库里」成为代码事实，而不是只在 Python 里 ``if`` 一下。
"""

import contextlib

import pyodbc

from config import Config
from dao import errors
from dao.errors import DaoError

# 允许被模拟的数据库身份白名单。
# EXECUTE AS USER 的语句形式不接受绑定参数，只能拼字符串，因此必须靠白名单把住注入风险。
_ALLOWED_DB_USERS = frozenset(
    {"usr_test_cashier", "usr_test_maker", "usr_test_stocker", "usr_test_manager"}
)


class Session:
    """一次请求内的数据库会话：持有一条连接、一个游标，并由调用方显式提交。"""

    def __init__(self, conn, cursor, db_user=None):
        self.conn = conn
        self.cur = cursor
        self.db_user = db_user
        self._finished = False

    def commit(self) -> None:
        """提交事务——由**业务层**调用，数据访问层不会自作主张提交。"""
        self.conn.commit()
        self._finished = True

    def rollback(self) -> None:
        with contextlib.suppress(Exception):
            self.conn.rollback()
        self._finished = True

    def query(self, sql: str, params: tuple = ()) -> list:
        """参数化查询。占位符一律是 ``?``（pyodbc 的 qmark 风格）。"""
        try:
            self.cur.execute(sql, params)
            return self.cur.fetchall()
        except Exception as exc:  # noqa: BLE001 - 统计转译后重抛
            raise errors.translate(exc)

    def query_one(self, sql: str, params: tuple = ()):
        rows = self.query(sql, params)
        return rows[0] if rows else None

    def execute(self, sql: str, params: tuple = ()) -> int:
        """单条写入；返回受影响行数。不提交。"""
        try:
            self.cur.execute(sql, params)
            return self.cur.rowcount
        except Exception as exc:  # noqa: BLE001
            raise errors.translate(exc)

    def execute_many(self, sql: str, seq_of_params) -> int:
        try:
            self.cur.executemany(sql, list(seq_of_params))
            return self.cur.rowcount
        except Exception as exc:  # noqa: BLE001
            raise errors.translate(exc)

    def identity(self) -> int:
        row = self.query_one("SELECT CAST(SCOPE_IDENTITY() AS INT) AS new_id")
        return int(row[0]) if row and row[0] is not None else 0


@contextlib.contextmanager
def open_session(db_user=None):
    """打开会话 → 切身份 → 交给调用方 → 未提交则回滚 → REVERT → 关连接。

    用法（注意提交发生在业务层）::

        with db.open_session("usr_test_cashier") as s:
            s.execute(...)
            s.commit()
    """
    if db_user is not None and db_user not in _ALLOWED_DB_USERS:
        raise DaoError(errors.UNKNOWN, "未知的数据库身份：%s" % db_user)

    conn = None
    cursor = None
    impersonated = False
    try:
        try:
            conn = pyodbc.connect(Config.connection_string(), autocommit=False, timeout=5)
        except Exception as exc:  # noqa: BLE001
            raise errors.translate(exc)

        cursor = conn.cursor()
        if db_user:
            try:
                # 值来自白名单常量，不是用户输入
                cursor.execute("EXECUTE AS USER = N'%s'" % db_user)
            except Exception as exc:  # noqa: BLE001
                raise errors.translate(exc)
            impersonated = True

        session = Session(conn, cursor, db_user)
        try:
            yield session
        finally:
            if not session._finished:
                session.rollback()
    finally:
        if cursor is not None:
            if impersonated:
                with contextlib.suppress(Exception):
                    cursor.execute("REVERT")
            with contextlib.suppress(Exception):
                cursor.close()
        if conn is not None:
            with contextlib.suppress(Exception):
                conn.close()


def probe() -> dict:
    """连通性与结构自检，供启动日志与 /healthz 使用。"""
    info = {"ok": False, "server": None, "database": None, "tables": None,
            "password_hash": None, "error": None}
    try:
        with open_session() as s:
            row = s.query_one(
                "SELECT @@SERVERNAME, DB_NAME(), "
                "(SELECT COUNT(*) FROM sys.tables WHERE name LIKE 'tbl[_]%'), "
                "COL_LENGTH('tbl_member', 'password_hash')"
            )
            info["server"] = row[0]
            info["database"] = row[1]
            info["tables"] = row[2]
            info["password_hash"] = (row[3] is not None)
            info["ok"] = True
    except DaoError as exc:
        info["error"] = "%s: %s" % (exc.category, exc.message)
    return info
