"""经营报表类的只读查询（店长工作台用）。

放在 dao 而不是 service：``test_layering.py`` 的断言是「service 与 web 里不许出现
内联 SQL」，这条规矩的作用是让"唯一能连库、唯一写 SQL 的地方"真的只有一个。
"""


def daily_summary(s, days: int = 7) -> list:
    return s.query(
        "SELECT TOP (?) business_date, total_orders, completed_orders, "
        "       cancelled_orders, total_cups, gross_sales, total_discount, "
        "       net_revenue, member_orders, member_revenue "
        "  FROM vw_daily_business_summary "
        " ORDER BY business_date DESC",
        (days,),
    )


def product_sales(s, limit: int = 10) -> list:
    """商品销量 Top N（按明细行聚合，含加料费）。"""
    return s.query(
        "SELECT TOP (?) p.product_id, p.product_name, "
        "       SUM(d.qty) AS cups, "
        "       CAST(SUM(d.subtotal) AS DECIMAL(10, 2)) AS sales_amount "
        "  FROM tbl_order_detail d "
        "  JOIN tbl_product p ON p.product_id = d.product_id "
        "  JOIN tbl_order_header h ON h.order_id = d.order_id "
        " WHERE h.pay_status = 'SUCCESS' "
        " GROUP BY p.product_id, p.product_name "
        " ORDER BY cups DESC, p.product_id",
        (limit,),
    )
