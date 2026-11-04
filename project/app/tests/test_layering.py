"""分层边界的机器校验 —— 课程段落 15 要求「能指出各层的文件或模块」。

三条断言都是可执行的门槛，任何一条被破坏，验收时就会被追问：
  1. 只有数据访问层允许 import pyodbc
  2. 页面层与业务层不得出现 SQL 拼接式字符串（粗筛，靠 dao 之外的目录里出现
     ``SELECT``/``INSERT``/``UPDATE``/``DELETE`` 关键字来判断）
  3. 页面层不得直接 import dao（必须经业务层）
"""

import pathlib
import re

import pytest

APP_DIR = pathlib.Path(__file__).resolve().parent.parent
LAYERS = ("dao", "service", "web")

SQL_KEYWORDS = re.compile(r"\b(SELECT\s|INSERT\s+INTO|UPDATE\s+tbl_|DELETE\s+FROM)\b", re.IGNORECASE)


def _strip_docstrings(text: str) -> list:
    """去掉三引号块（文档字符串里提到 SQL 是正常的），返回剩余行。"""
    kept = []
    in_block = False
    for line in text.splitlines():
        fences = line.count('"""') + line.count("'''")
        if in_block:
            if fences % 2 == 1:
                in_block = False
            continue
        if fences >= 2:
            continue
        if fences % 2 == 1:
            in_block = True
            continue
        kept.append(line)
    return kept


def _py_files(layer: str):
    return sorted((APP_DIR / layer).rglob("*.py"))


def test_only_dao_imports_pyodbc():
    offenders = []
    for layer in ("service", "web"):
        for path in _py_files(layer):
            text = path.read_text(encoding="utf-8")
            if "import pyodbc" in text:
                offenders.append(str(path.relative_to(APP_DIR)))
    # app.py 只经 dao.probe 间接探活，不直接 import pyodbc
    top = APP_DIR / "app.py"
    if "import pyodbc" in top.read_text(encoding="utf-8"):
        offenders.append("app.py")
    assert not offenders, "以下文件直接引用了 pyodbc，违反分层：%s" % offenders


@pytest.mark.parametrize("layer", ["service", "web"])
def test_no_sql_in_upper_layers(layer):
    offenders = []
    for path in _py_files(layer):
        text = path.read_text(encoding="utf-8")
        # 注释与文档字符串里提到 SQL 是允许的，只查真正的代码行
        for lineno, line in enumerate(_strip_docstrings(text), start=1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if SQL_KEYWORDS.search(line):
                offenders.append("%s:%d" % (path.relative_to(APP_DIR), lineno))
    assert not offenders, "上层出现疑似内联 SQL：%s" % offenders


def test_web_does_not_import_dao():
    offenders = []
    for path in _py_files("web"):
        text = path.read_text(encoding="utf-8")
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("from dao") or stripped.startswith("import dao"):
                offenders.append("%s: %s" % (path.relative_to(APP_DIR), stripped))
    assert not offenders, "页面层绕过业务层直接用了 dao：%s" % offenders
