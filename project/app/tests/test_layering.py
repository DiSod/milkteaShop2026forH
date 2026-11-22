"""分层边界的机器校验 —— 课程段落 15 要求「能指出各层的文件或模块」。

三条断言都是可执行的门槛，任何一条被破坏，验收时就会被追问：
  1. 只有数据访问层允许 import pyodbc
  2. 页面层与业务层不得出现 SQL 拼接式字符串（粗筛，靠 dao 之外的目录里出现
     ``SELECT``/``INSERT``/``UPDATE``/``DELETE`` 关键字来判断）
  3. 页面层不得直接 import dao（必须经业务层）
"""

import ast
import pathlib
import re

import pytest

APP_DIR = pathlib.Path(__file__).resolve().parent.parent
LAYERS = ("dao", "service", "web")

SQL_KEYWORDS = re.compile(r"\b(SELECT\s|INSERT\s+INTO|UPDATE\s+tbl_|DELETE\s+FROM)\b", re.IGNORECASE)


def _docstring_node_ids(tree: ast.AST) -> set:
    """收集模块/类/函数首句 docstring 节点，其余三引号字符串一律按代码字符串检查。"""
    ids = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            if (
                node.body
                and isinstance(node.body[0], ast.Expr)
                and isinstance(node.body[0].value, ast.Constant)
                and isinstance(node.body[0].value.value, str)
            ):
                ids.add(id(node.body[0].value))
    return ids


def _imports_module(tree: ast.AST, root_name: str) -> bool:
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name == root_name or alias.name.startswith(root_name + ".") for alias in node.names):
                return True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == root_name or node.module.startswith(root_name + ".")):
                return True
    return False


def _py_files(layer: str):
    return sorted((APP_DIR / layer).rglob("*.py"))


def test_only_dao_imports_pyodbc():
    offenders = []
    for layer in ("service", "web"):
        for path in _py_files(layer):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            if _imports_module(tree, "pyodbc"):
                offenders.append(str(path.relative_to(APP_DIR)))
    # app.py 只经 dao.probe 间接探活，不直接 import pyodbc
    top = APP_DIR / "app.py"
    if _imports_module(ast.parse(top.read_text(encoding="utf-8"), filename=str(top)), "pyodbc"):
        offenders.append("app.py")
    assert not offenders, "以下文件直接引用了 pyodbc，违反分层：%s" % offenders


@pytest.mark.parametrize("layer", ["service", "web"])
def test_no_sql_in_upper_layers(layer):
    offenders = []
    for path in _py_files(layer):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        doc_ids = _docstring_node_ids(tree)
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                if id(node) in doc_ids:
                    continue
                if SQL_KEYWORDS.search(node.value):
                    offenders.append("%s:%d" % (path.relative_to(APP_DIR), node.lineno))
    assert not offenders, "上层出现疑似内联 SQL：%s" % offenders


def test_web_does_not_import_dao():
    offenders = []
    for path in _py_files("web"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        if _imports_module(tree, "dao"):
            offenders.append(str(path.relative_to(APP_DIR)))
    assert not offenders, "页面层绕过业务层直接用了 dao：%s" % offenders
