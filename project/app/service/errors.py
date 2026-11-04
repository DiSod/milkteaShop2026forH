"""业务层统一错误类型 —— 课程要求的八类异常都在这里。

页面层只认 ``code`` 与 ``message``（面向用户的简明提示），
完整原因写后端日志，不进响应体。
"""

from dao import errors as dao_errors


class AppError(Exception):
    """所有业务异常的基类。子类通过类属性声明错误码与 HTTP 状态。"""

    code = "INTERNAL_ERROR"
    http_status = 500
    default_message = "系统暂时无法完成操作"

    def __init__(self, message: str = None, detail: str = None):
        super().__init__(message or self.default_message)
        self.message = message or self.default_message
        # detail 只进日志，不出响应
        self.detail = detail or ""


# ── 八类异常（顺序与课程段落 13 的枚举一致）────────────────────────────
class ValidationError(AppError):
    code = "INPUT_INVALID"
    http_status = 400
    default_message = "操作失败，请检查输入内容"


class Unauthenticated(AppError):
    code = "UNAUTHENTICATED"
    http_status = 401
    default_message = "请先登录"


class PermissionDenied(AppError):
    code = "PERMISSION_DENIED"
    http_status = 403
    default_message = "当前角色无权执行该操作"


class NotFound(AppError):
    code = "NOT_FOUND"
    http_status = 404
    default_message = "数据不存在"


class BusinessRuleViolation(AppError):
    code = "BUSINESS_RULE_VIOLATION"
    http_status = 409
    default_message = "业务规则不满足，操作已取消"


class ConnectionFailed(AppError):
    code = "DB_CONNECTION_FAILED"
    http_status = 503
    default_message = "系统暂时无法完成操作"


class ConstraintConflict(AppError):
    code = "CONSTRAINT_CONFLICT"
    http_status = 409
    default_message = "数据冲突，操作已取消"


class TransactionFailed(AppError):
    code = "TRANSACTION_FAILED"
    http_status = 500
    default_message = "操作失败，数据未改变"


_MAP = {
    dao_errors.CONNECTION_FAILED: ConnectionFailed,
    dao_errors.CONSTRAINT_CONFLICT: ConstraintConflict,
    dao_errors.PERMISSION_DENIED: PermissionDenied,
}


def from_dao(exc: dao_errors.DaoError) -> AppError:
    """把数据访问层的错误类别翻译成业务异常。"""
    cls = _MAP.get(exc.category, TransactionFailed)
    return cls(detail=exc.message)
