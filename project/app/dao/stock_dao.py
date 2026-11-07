"""库存与流水的数据访问。

两条硬规矩，写在这里而不是散在业务层：

1. **任何数量变化都必须同时写一条 ``tbl_stock_ledger``**。库里的 A6 不变量是
   ``tbl_ingredient.qty_on_hand == SUM(tbl_stock_ledger.qty)``，`regression.sql`
   TC-12 会逐原料核对。所以这里不提供"只改数量"的方法 —— 只有
   :func:`apply_movement`，它两个动作一起做。
2. **流水方向的符号**：入库为正、出库为负。``ledger_type`` 只允许
   ``PURCHASE_IN`` / ``SALES_USE`` / ``LOSS``（DOM-04，``OPENING`` 属积分域不在此），
   而 ``ref_type`` 的取值受 ``ck_stock_ledger_ref_consistency`` 约束：
   ``PURCHASE`` 必须挂采购单、``ORDER`` 必须挂订单、``MANUAL`` 两个外键都必须为 NULL。
"""


def list_ingredients(s) -> list:
    return s.query(
        "SELECT ingredient_id, ingredient_code, ingredient_name, unit, spec, "
        "       qty_on_hand, reorder_point, target_level, moving_avg_cost, "
        "       is_sold_out, is_active "
        "  FROM tbl_ingredient ORDER BY ingredient_id"
    )


def get_ingredient(s, ingredient_id: int):
    rows = s.query(
        "SELECT ingredient_id, ingredient_code, ingredient_name, unit, spec, "
        "       qty_on_hand, reorder_point, target_level, moving_avg_cost, "
        "       is_sold_out, is_active "
        "  FROM tbl_ingredient WHERE ingredient_id = ?",
        (ingredient_id,),
    )
    return rows[0] if rows else None


def list_alerts(s) -> list:
    """低于补货点的原料（视图已算好建议进货量）。"""
    return s.query(
        "SELECT ingredient_id, ingredient_code, ingredient_name, unit, spec, "
        "       qty_on_hand, reorder_point, target_level, suggested_order_qty, "
        "       alert_level, alert_priority "
        "  FROM vw_ingredient_reorder_alert ORDER BY alert_priority, ingredient_id"
    )


def apply_movement(s, ingredient_id: int, delta, ledger_type: str,
                   ref_type: str, remark: str = None,
                   purchase_order_id: int = None, order_id: int = None,
                   operator_id: int = None) -> None:
    """改库存 + 记流水，两件事必须同事务同调用。

    ``delta`` 带符号：入库为正、出库为负；流水里记的就是这个带符号值。
    """
    s.execute(
        "UPDATE tbl_ingredient SET qty_on_hand = qty_on_hand + ? WHERE ingredient_id = ?",
        (delta, ingredient_id),
    )
    s.execute(
        "INSERT INTO tbl_stock_ledger "
        "    (ingredient_id, ledger_type, qty, ref_type, purchase_order_id, "
        "     order_id, operator_id, ledger_time, remark) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, SYSDATETIME(), ?)",
        (ingredient_id, ledger_type, delta, ref_type,
         purchase_order_id, order_id, operator_id, remark),
    )


def ledger_drift(s) -> list:
    """对账用：返回 ``qty_on_hand != SUM(流水)`` 的原料（正常应为空列表）。"""
    return s.query(
        "SELECT i.ingredient_id, i.ingredient_name, i.qty_on_hand, "
        "       ISNULL(SUM(l.qty), 0) AS flow_total "
        "  FROM tbl_ingredient i "
        "  LEFT JOIN tbl_stock_ledger l ON l.ingredient_id = i.ingredient_id "
        " GROUP BY i.ingredient_id, i.ingredient_name, i.qty_on_hand "
        "HAVING i.qty_on_hand <> ISNULL(SUM(l.qty), 0) "
        " ORDER BY i.ingredient_id"
    )
