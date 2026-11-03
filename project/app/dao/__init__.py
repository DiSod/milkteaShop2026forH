"""数据访问层。**本目录是唯一允许 import pyodbc 的地方。**

对外只暴露 ``open_session`` / ``probe`` 与各 DAO 函数；上层不感知连接细节。
"""

from dao import db  # noqa: F401
from dao.errors import DaoError  # noqa: F401

__all__ = ["db", "DaoError"]
