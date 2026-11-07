"""应用入口 —— 应用工厂 + 统一异常 + 请求标识日志。

启动：
    python app.py
默认监听 http://127.0.0.1:5000 ；连接信息全部来自环境变量或 .env（见 .env.example）。
"""

import logging
import time
import uuid

from flask import Flask, g, jsonify, render_template, request

from config import Config
from dao import db
from dao import errors as dao_errors
from service import errors as svc_errors
from service.errors import AppError
from web import (
    routes_auth,
    routes_cashier,
    routes_maker,
    routes_manager,
    routes_member,
    routes_stocker,
)
from web.security import load_current_user

LOG_FORMAT = (
    "%(asctime)s level=%(levelname)s req=%(request_id)s "
    "op=%(operation)s role=%(role)s code=%(code)s result=%(result)s :: %(message)s"
)


class _ContextFilter(logging.Filter):
    """把请求级字段塞进每条日志记录，缺省给 '-'。"""

    def filter(self, record):
        for field in ("request_id", "operation", "role", "code", "result"):
            if not hasattr(record, field):
                setattr(record, field, "-")
        return True


def _configure_logging(app: Flask) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter(LOG_FORMAT))
    handler.addFilter(_ContextFilter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(logging.INFO)


def create_app(config_object=Config) -> Flask:
    app = Flask(
        __name__,
        static_folder="web/static",
        template_folder="web/templates",
    )
    app.config.from_object(config_object)
    _configure_logging(app)

    @app.before_request
    def _before():
        g.request_id = uuid.uuid4().hex[:12]
        g.started_at = time.time()
        load_current_user()

    @app.after_request
    def _after(response):
        elapsed = (time.time() - g.get("started_at", time.time())) * 1000
        logging.getLogger("access").info(
            "%s %s -> %s",
            request.method,
            request.path,
            response.status_code,
            extra={
                "request_id": g.get("request_id", "-"),
                "operation": "%s %s" % (request.method, request.path),
                "role": g.get("current_role") or "-",
                "code": response.status_code,
                "result": "%.0fms" % elapsed,
            },
        )
        return response

    app.register_blueprint(routes_auth.bp)
    app.register_blueprint(routes_member.bp)
    app.register_blueprint(routes_maker.bp)
    app.register_blueprint(routes_cashier.bp)
    app.register_blueprint(routes_stocker.bp)
    app.register_blueprint(routes_manager.bp)

    @app.get("/health")
    def health():
        try:
            return jsonify({"ok": True, "db": db.probe()})
        except Exception as exc:  # 健康检查本身不能抛
            logging.getLogger("health").warning("probe failed: %s", exc)
            return jsonify({"ok": False, "error": "DB_CONNECTION_FAILED"}), 503

    @app.errorhandler(dao_errors.DaoError)
    def _handle_dao_error(exc):
        """数据访问层抛上来的错误统一翻译成八类业务异常，不裸奔到 500。"""
        return _handle_app_error(svc_errors.from_dao(exc))

    @app.errorhandler(AppError)
    def _handle_app_error(exc: AppError):
        logging.getLogger("app").warning(
            "%s",
            exc.detail or exc.message,
            extra={
                "request_id": g.get("request_id", "-"),
                "operation": "%s %s" % (request.method, request.path),
                "role": g.get("current_role") or "-",
                "code": exc.code,
                "result": "error",
            },
        )
        payload = {"code": exc.code, "message": exc.message, "request_id": g.get("request_id")}
        if request.accept_mimetypes.best == "application/json":
            return jsonify(payload), exc.http_status
        error = type("E", (), payload)()
        error.ref = payload["request_id"]
        return render_template("error.html", error=error), exc.http_status

    @app.errorhandler(404)
    def _not_found(_exc):
        error = type("E", (), {"code": "NOT_FOUND", "message": "页面不存在", "ref": None})()
        return render_template("error.html", error=error), 404

    @app.errorhandler(Exception)
    def _unhandled(exc: Exception):
        logging.getLogger("app").exception(
            "unhandled: %s",
            exc,
            extra={
                "request_id": g.get("request_id", "-"),
                "operation": "%s %s" % (request.method, request.path),
                "role": g.get("current_role") or "-",
                "code": "INTERNAL_ERROR",
                "result": "error",
            },
        )
        error = type(
            "E", (), {"code": "INTERNAL_ERROR", "message": "系统暂时无法完成操作", "ref": g.get("request_id")}
        )()
        return render_template("error.html", error=error), 500

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=app.config.get("DEBUG", False))
