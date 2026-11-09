"""优惠券数据访问：查券、核销、退回。

**发券不在这里。** v1.0 的券是建库时由
``project/sql/11-migration/migration-07-coupon-redemption.sql`` 默认发放的
静态数据（3 位会员各 2 张）；运行时发券（活动发券、积分兑换券）属于 v2.0。

两条约定：
  · ``mark_used`` 用 ``WHERE status='UNUSED' AND 当前时间在有效期内`` 的
    受影响行数判成败（乐观并发）。**这条 SQL 不能带 ``SET NOCOUNT ON``**，
    否则 ``cursor.rowcount`` 恒为 -1，"券已被用掉"就检测不出来。
  · 退券要两步：先 ``order_dao.detach_coupon`` 把订单上的 ``coupon_id`` 置空，
    再 ``release`` 回 ``UNUSED``。因为 ``uq_order_header_coupon`` 是过滤唯一
    索引，券还挂在单上时，下一单再用同一张会撞索引。
"""


def list_for_member(s, member_id: int) -> list:
    """会员的全部券，附模板面额/门槛与三态（AVAILABLE / USED / EXPIRED）。"""
    return s.query(
        """
        SELECT c.coupon_id, c.coupon_code, t.template_name,
               t.discount_amount, t.min_order_amount,
               c.valid_from, c.valid_to, c.status, c.used_time,
               CASE
                   WHEN c.status = 'USED' THEN 'USED'
                   WHEN SYSDATETIME() BETWEEN c.valid_from AND c.valid_to THEN 'AVAILABLE'
                   ELSE 'EXPIRED'
               END AS state
          FROM tbl_coupon c
          JOIN tbl_coupon_template t ON t.template_id = c.template_id
         WHERE c.member_id = ?
         ORDER BY CASE
                      WHEN c.status = 'USED' THEN 1
                      WHEN SYSDATETIME() BETWEEN c.valid_from AND c.valid_to THEN 0
                      ELSE 2
                  END,
                  c.valid_to, c.coupon_id
        """,
        (member_id,),
    )


def list_available(s, member_id: int) -> list:
    """下单页下拉用：只取现在真的能用的券。"""
    return s.query(
        """
        SELECT c.coupon_id, c.coupon_code, t.template_name,
               t.discount_amount, t.min_order_amount, c.valid_to
          FROM tbl_coupon c
          JOIN tbl_coupon_template t ON t.template_id = c.template_id
         WHERE c.member_id = ?
           AND c.status = 'UNUSED'
           AND SYSDATETIME() BETWEEN c.valid_from AND c.valid_to
         ORDER BY t.discount_amount DESC, c.valid_to
        """,
        (member_id,),
    )


def get_redeemable(s, coupon_id: int, member_id: int):
    """取一张**属于该会员、未使用、在有效期内**的券；返回 (面额, 门槛) 或 None。"""
    return s.query_one(
        """
        SELECT t.discount_amount, t.min_order_amount
          FROM tbl_coupon c
          JOIN tbl_coupon_template t ON t.template_id = c.template_id
         WHERE c.coupon_id = ?
           AND c.member_id = ?
           AND c.status = 'UNUSED'
           AND SYSDATETIME() BETWEEN c.valid_from AND c.valid_to
        """,
        (coupon_id, member_id),
    )


def mark_used(s, coupon_id: int, member_id: int) -> int:
    """核销：返回受影响行数（1 = 成功，0 = 已被用掉或刚好过期）。不提交。"""
    # ⚠️ 必须先 `SET NOCOUNT OFF`：同一个连接上前面的 insert_header 里带
    # `SET NOCOUNT ON`，而 NOCOUNT 是**会话级**设置——不关掉的话这条 UPDATE
    # 的 rowcount 恒为 -1，券已被用掉就永远检测不出来（实测踩过）。
    return s.execute(
        """
        SET NOCOUNT OFF;
        UPDATE tbl_coupon
           SET status = 'USED', used_time = SYSDATETIME()
         WHERE coupon_id = ?
           AND member_id = ?
           AND status = 'UNUSED'
           AND SYSDATETIME() BETWEEN valid_from AND valid_to
        """,
        (coupon_id, member_id),
    )


def release(s, coupon_id: int) -> int:
    """退券：USED → UNUSED，``used_time`` 一并置空（有 CHECK 约束盯着）。"""
    return s.execute(
        """
        UPDATE tbl_coupon
           SET status = 'UNUSED', used_time = NULL
         WHERE coupon_id = ? AND status = 'USED'
        """,
        (coupon_id,),
    )
