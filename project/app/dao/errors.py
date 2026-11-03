"""把驱动层异常翻译成统一错误类别。

只有这一个模块认识 ``pyodbc`` 的异常类型，上层（service / web）只见错误码。
"""

import re

import pyodbc

# 类别常量与课程要求的八类异常一一对应
CONNECTION_FAILED = "DB_CONNECTION_FAILED"
CONSTRAINT_CONFLICT = "CONSTRAINT_CONFLICT"
PERMISSION_DENIED = "DB_PERMISSION_DENIED"
UNKNOWN = "DB_ERROR"


class DaoError(Exception):
    """数据访问层错误：只携带错误类别与原始信息，不含业务语义。"""

    def __init__(self, category: str, message: str, native: int = 0):
        super().__init__(message)
        self.category = category
        self.message = message
        self.native = native


def translate(exc: Exception) -> DaoError:
    """按 SQLSTATE / 原生错误号归类。"""
    if isinstance(exc, pyodbc.OperationalError):
        return DaoError(CONNECTION_FAILED, str(exc))
    if isinstance(exc, pyodbc.IntegrityError):
        return DaoError(CONSTRAINT_CONFLICT, str(exc), _native(exc))
    if isinstance(exc, pyodbc.ProgrammingError):
        native = _native(exc)
        # 229 / 230 = 对象或列级权限被拒
        if native in (229, 230):
            return DaoError(PERMISSION_DENIED, str(exc), native)
        # 207 无效列名 / 208 对象名无效，通常是库结构未迁移到位
        if native in (207, 208):
            return DaoError(UNKNOWN, str(exc), native)
        return DaoError(UNKNOWN, str(exc), native)
    if isinstance(exc, pyodbc.DatabaseError):
        return DaoError(UNKNOWN, str(exc), _native(exc))
    return DaoError(UNKNOWN, str(exc))


def _native(exc: Exception) -> int:
    """取 SQL Server 原生错误号。

    pyodbc 的异常参数形状不统一：有时是 ``(sqlstate, native_int)``，
    有时是 ``(sqlstate, message_str)``，驱动只把错误号写进消息文本，
    所以两种都要认，最后再从消息里的 ``(229)`` 这类括号数字兜底。
    """
    args = getattr(exc, "args", ())
    if len(args) >= 2 and isinstance(args[1], int):
        return args[1]
    match = re.search(r"\((\d{1,6})\)\s*\(SQLExecDirectW\)", str(exc))
    if match:
        return int(match.group(1))
    match = re.search(r"\[SQL Server\].*?\((\d{1,6})\)", str(exc))
    if match:
        return int(match.group(1))
    return 0
