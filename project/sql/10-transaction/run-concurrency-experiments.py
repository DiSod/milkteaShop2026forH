"""第 13 周双/三会话并发控制自动化实验套件。

复现并采集以下四类课程要求的真实并发证据（全程使用真实多条 pyodbc 连接 +
threading.Barrier 精确同步时序，并在 try/finally 中完整恢复基准，确保零漂移）：

  1. 隔离级别对比：脏读 / 不可重复读 / 幻读（问题现象 vs 提升隔离级别后的防线）
  2. 锁等待观测（sys.dm_os_waiting_tasks + sys.dm_tran_locks）与 UPDLOCK 防超卖对比
  3. AB-BA 死锁（SQL Server 1205）稳定复现 vs 按 ingredient_id 升序加锁根治（0 死锁）
  4. 测后不变量核对：订单数 1963、库存漂移 0、积分漂移 0

运行（从仓库根或任意目录均可）：
    project\\app\\.venv\\Scripts\\python.exe project\\sql\\10-transaction\\run-concurrency-experiments.py
"""

import pathlib
import sys
import threading
import time
from decimal import Decimal

import pyodbc

ROOT_DIR = pathlib.Path(__file__).resolve().parents[3]
APP_DIR = ROOT_DIR / "project" / "app"
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

from config import Config  # noqa: E402


def new_conn(autocommit: bool = False, timeout: int = 15) -> pyodbc.Connection:
    conn = pyodbc.connect(Config.connection_string(), autocommit=autocommit, timeout=timeout)
    return conn


def scalar(conn: pyodbc.Connection, sql: str, params=()):
    cur = conn.cursor()
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def check_invariants() -> tuple:
    with new_conn(autocommit=True) as conn:
        row = conn.cursor().execute(
            """
            SELECT
                (SELECT COUNT(*) FROM dbo.tbl_order_header),
                (SELECT COUNT(*) FROM dbo.tbl_ingredient AS i
                 WHERE i.qty_on_hand <> ISNULL(
                     (SELECT SUM(qty) FROM dbo.tbl_stock_ledger WHERE ingredient_id = i.ingredient_id), 0)),
                (SELECT COUNT(*) FROM dbo.tbl_member AS m
                 WHERE m.points_balance <> ISNULL(
                     (SELECT SUM(point_change) FROM dbo.tbl_points_ledger WHERE member_id = m.member_id), 0))
            """
        ).fetchone()
        return int(row[0]), int(row[1]), int(row[2])


# =====================================================================
# 实验 1：隔离级别现象对比（脏读 / 不可重复读 / 幻读）
# =====================================================================


def exp1a_dirty_read() -> dict:
    with new_conn(autocommit=True) as c:
        orig_qty = Decimal(str(scalar(c, "SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1")))
    dirty_qty = orig_qty + Decimal("888.000")

    ev_updated = threading.Event()
    ev_dirty_read_done = threading.Event()
    results = {}

    def session_a():
        with new_conn(autocommit=False) as ca:
            ca.cursor().execute(
                "UPDATE dbo.tbl_ingredient SET qty_on_hand = ? WHERE ingredient_id = 1",
                (dirty_qty,),
            )
            ev_updated.set()
            ev_dirty_read_done.wait(timeout=5)
            time.sleep(0.25)  # 让 Session C 先发起 READ COMMITTED 并发生阻塞
            ca.rollback()

    def session_b_uncommitted():
        ev_updated.wait(timeout=5)
        with new_conn(autocommit=False) as cb:
            cb.cursor().execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;")
            val = Decimal(str(scalar(cb, "SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1")))
            results["read_uncommitted"] = val
            cb.commit()
        ev_dirty_read_done.set()

    def session_c_committed():
        ev_dirty_read_done.wait(timeout=5)
        t0 = time.perf_counter()
        with new_conn(autocommit=False) as cc:
            cc.cursor().execute("SET TRANSACTION ISOLATION LEVEL READ COMMITTED;")
            val = Decimal(str(scalar(cc, "SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1")))
            results["read_committed"] = val
            results["read_committed_wait_ms"] = round((time.perf_counter() - t0) * 1000, 1)
            cc.commit()

    threads = [
        threading.Thread(target=session_a),
        threading.Thread(target=session_b_uncommitted),
        threading.Thread(target=session_c_committed),
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=15)

    assert results["read_uncommitted"] == dirty_qty, f"预期读到脏值 {dirty_qty}，实际 {results}"
    assert results["read_committed"] == orig_qty, f"预期 READ COMMITTED 读回原值 {orig_qty}，实际 {results}"
    return {"orig_qty": orig_qty, "dirty_qty": dirty_qty, **results}


def _run_non_repeatable(isolation_sql: str) -> tuple:
    with new_conn(autocommit=True) as c:
        orig_qty = Decimal(str(scalar(c, "SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1")))

    ev_first_read = threading.Event()
    ev_writer_done = threading.Event()
    reads = {}

    try:
        def session_a():
            with new_conn(autocommit=False) as ca:
                cur = ca.cursor()
                cur.execute(isolation_sql)
                r1 = Decimal(str(scalar(ca, "SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1")))
                reads["r1"] = r1
                ev_first_read.set()
                if "READ COMMITTED" in isolation_sql:
                    ev_writer_done.wait(timeout=5)
                else:
                    time.sleep(0.35)  # 让 writer 尝试并发更新并被 S 锁阻塞
                r2 = Decimal(str(scalar(ca, "SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1")))
                reads["r2"] = r2
                ca.commit()

        def session_b():
            ev_first_read.wait(timeout=5)
            t0 = time.perf_counter()
            with new_conn(autocommit=False) as cb:
                cb.cursor().execute(
                    "UPDATE dbo.tbl_ingredient SET qty_on_hand = qty_on_hand + 10.000 WHERE ingredient_id = 1"
                )
                cb.commit()
            reads["writer_elapsed_ms"] = round((time.perf_counter() - t0) * 1000, 1)
            ev_writer_done.set()

        ta = threading.Thread(target=session_a)
        tb = threading.Thread(target=session_b)
        ta.start()
        tb.start()
        ta.join(timeout=15)
        tb.join(timeout=15)
    finally:
        with new_conn(autocommit=True) as c:
            c.cursor().execute(
                "UPDATE dbo.tbl_ingredient SET qty_on_hand = ? WHERE ingredient_id = 1",
                (orig_qty,),
            )

    return reads["r1"], reads["r2"], reads.get("writer_elapsed_ms", 0.0)


def exp1b_non_repeatable_read() -> dict:
    rc_r1, rc_r2, rc_ms = _run_non_repeatable("SET TRANSACTION ISOLATION LEVEL READ COMMITTED;")
    rr_r1, rr_r2, rr_ms = _run_non_repeatable("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;")
    assert rc_r1 != rc_r2, f"READ COMMITTED 下应复现不可重复读，实际 r1={rc_r1}, r2={rc_r2}"
    assert rr_r1 == rr_r2, f"REPEATABLE READ 下应保持可重复读，实际 r1={rr_r1}, r2={rr_r2}"
    return {
        "rc_r1": rc_r1, "rc_r2": rc_r2, "rc_writer_ms": rc_ms,
        "rr_r1": rr_r1, "rr_r2": rr_r2, "rr_writer_ms": rr_ms,
    }


def _run_phantom(isolation_sql: str) -> tuple:
    with new_conn(autocommit=True) as c:
        c.cursor().execute("DELETE FROM dbo.tbl_product_category WHERE category_code LIKE 'PHANTOM%';")

    ev_first_count = threading.Event()
    ev_inserter_done = threading.Event()
    counts = {}

    try:
        def session_a():
            with new_conn(autocommit=False) as ca:
                ca.cursor().execute(isolation_sql)
                c1 = int(scalar(ca, "SELECT COUNT(*) FROM dbo.tbl_product_category WHERE category_code LIKE 'PHANTOM%'"))
                counts["c1"] = c1
                ev_first_count.set()
                if "REPEATABLE READ" in isolation_sql:
                    ev_inserter_done.wait(timeout=5)
                else:
                    time.sleep(0.35)  # 让 inserter 尝试插入并被 SERIALIZABLE 范围锁阻塞
                c2 = int(scalar(ca, "SELECT COUNT(*) FROM dbo.tbl_product_category WHERE category_code LIKE 'PHANTOM%'"))
                counts["c2"] = c2
                ca.commit()

        def session_b():
            ev_first_count.wait(timeout=5)
            t0 = time.perf_counter()
            with new_conn(autocommit=False) as cb:
                cb.cursor().execute(
                    "INSERT INTO dbo.tbl_product_category "
                    "(parent_category_id, category_code, category_name, sort_no, is_active) "
                    "VALUES (NULL, 'PHANTOM1', N'幻读测试品类', 99, 1)"
                )
                cb.commit()
            counts["inserter_ms"] = round((time.perf_counter() - t0) * 1000, 1)
            ev_inserter_done.set()

        ta = threading.Thread(target=session_a)
        tb = threading.Thread(target=session_b)
        ta.start()
        tb.start()
        ta.join(timeout=15)
        tb.join(timeout=15)
    finally:
        with new_conn(autocommit=True) as c:
            c.cursor().execute("DELETE FROM dbo.tbl_product_category WHERE category_code LIKE 'PHANTOM%';")

    return counts["c1"], counts["c2"], counts.get("inserter_ms", 0.0)


def exp1c_phantom_read() -> dict:
    rr_c1, rr_c2, rr_ms = _run_phantom("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;")
    sz_c1, sz_c2, sz_ms = _run_phantom("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;")
    assert rr_c1 == 0 and rr_c2 == 1, f"REPEATABLE READ 下应复现幻读，实际 c1={rr_c1}, c2={rr_c2}"
    assert sz_c1 == 0 and sz_c2 == 0, f"SERIALIZABLE 下应阻断幻读，实际 c1={sz_c1}, c2={sz_c2}"
    return {
        "rr_c1": rr_c1, "rr_c2": rr_c2,
        "sz_c1": sz_c1, "sz_c2": sz_c2, "sz_inserter_ms": sz_ms,
    }


# =====================================================================
# 实验 2：锁等待观测（LCK_M_U）与 UPDLOCK 防超卖对比
# =====================================================================


def exp2_lock_wait_and_oversell() -> dict:
    with new_conn(autocommit=True) as c:
        orig_qty = Decimal(str(scalar(c, "SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1")))

    need_qty = Decimal("100.000")
    out = {}

    try:
        # ---- Part A: 改进前（无锁先查后扣 TOCTOU） ----
        with new_conn(autocommit=True) as c:
            c.cursor().execute("UPDATE dbo.tbl_ingredient SET qty_on_hand = ? WHERE ingredient_id = 1", (need_qty,))

        barrier_before = threading.Barrier(2)
        before_outcomes = []

        def worker_naive(name: str):
            with new_conn(autocommit=False) as conn:
                qty = Decimal(str(scalar(conn, "SELECT qty_on_hand FROM dbo.tbl_ingredient WHERE ingredient_id = 1")))
                barrier_before.wait(timeout=5)
                if qty < need_qty:
                    before_outcomes.append((name, "graceful_reject", qty))
                    conn.rollback()
                    return
                try:
                    conn.cursor().execute(
                        "UPDATE dbo.tbl_ingredient SET qty_on_hand = qty_on_hand - ? WHERE ingredient_id = 1",
                        (need_qty,),
                    )
                    conn.commit()
                    before_outcomes.append((name, "committed", qty))
                except pyodbc.Error as exc:
                    conn.rollback()
                    before_outcomes.append((name, "constraint_547_crash", str(exc)[:120]))

        t1 = threading.Thread(target=worker_naive, args=("A",))
        t2 = threading.Thread(target=worker_naive, args=("B",))
        t1.start()
        t2.start()
        t1.join(timeout=15)
        t2.join(timeout=15)

        statuses_before = sorted(r[1] for r in before_outcomes)
        assert statuses_before == ["committed", "constraint_547_crash"], f"未复现 TOCTOU 撞约束：{before_outcomes}"
        out["before"] = before_outcomes

        # ---- Part B: 改进后（WITH (UPDLOCK, ROWLOCK) + 捕获真实 LCK_M_U 锁等待） ----
        with new_conn(autocommit=True) as c:
            c.cursor().execute("UPDATE dbo.tbl_ingredient SET qty_on_hand = ? WHERE ingredient_id = 1", (need_qty,))

        ev_a_locked = threading.Event()
        ev_b_started = threading.Event()
        after_outcomes = []
        lock_waits = []
        spids = {}

        def worker_a_updlock():
            with new_conn(autocommit=False) as conn:
                spids["A"] = int(scalar(conn, "SELECT @@SPID"))
                qty = Decimal(str(scalar(
                    conn,
                    "SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = 1",
                )))
                ev_a_locked.set()
                ev_b_started.wait(timeout=5)
                time.sleep(0.55)  # 留出窗口让监视线程在 DMV 抓取 LCK_M_U 锁等待
                if qty >= need_qty:
                    conn.cursor().execute(
                        "UPDATE dbo.tbl_ingredient SET qty_on_hand = qty_on_hand - ? WHERE ingredient_id = 1",
                        (need_qty,),
                    )
                    conn.commit()
                    after_outcomes.append(("A", "committed", qty))
                else:
                    conn.rollback()
                    after_outcomes.append(("A", "graceful_reject", qty))

        def worker_b_updlock():
            ev_a_locked.wait(timeout=5)
            with new_conn(autocommit=False) as conn:
                spids["B"] = int(scalar(conn, "SELECT @@SPID"))
                ev_b_started.set()
                qty = Decimal(str(scalar(
                    conn,
                    "SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = 1",
                )))
                if qty >= need_qty:
                    conn.cursor().execute(
                        "UPDATE dbo.tbl_ingredient SET qty_on_hand = qty_on_hand - ? WHERE ingredient_id = 1",
                        (need_qty,),
                    )
                    conn.commit()
                    after_outcomes.append(("B", "committed", qty))
                else:
                    conn.rollback()
                    after_outcomes.append(("B", "graceful_reject", qty))

        def monitor_dmv():
            ev_b_started.wait(timeout=5)
            with new_conn(autocommit=True) as mon:
                for _ in range(12):
                    time.sleep(0.05)
                    rows = mon.cursor().execute(
                        """
                        SELECT wt.session_id,
                               wt.blocking_session_id,
                               wt.wait_type,
                               wt.wait_duration_ms,
                               tl.resource_type,
                               tl.request_mode,
                               wt.resource_description
                        FROM sys.dm_os_waiting_tasks AS wt
                        LEFT JOIN sys.dm_tran_locks AS tl
                            ON tl.lock_owner_address = wt.resource_address
                        WHERE wt.session_id = ?
                          AND wt.blocking_session_id IS NOT NULL
                        """,
                        (spids["B"],),
                    ).fetchall()
                    if rows:
                        for r in rows:
                            lock_waits.append({
                                "waiting_spid": r[0],
                                "blocking_spid": r[1],
                                "wait_type": r[2],
                                "wait_ms": r[3],
                                "resource_type": r[4],
                                "request_mode": r[5],
                                "resource_desc": (r[6] or "")[:80],
                            })
                        break

        ta = threading.Thread(target=worker_a_updlock)
        tb = threading.Thread(target=worker_b_updlock)
        tm = threading.Thread(target=monitor_dmv)
        ta.start()
        tb.start()
        tm.start()
        ta.join(timeout=15)
        tb.join(timeout=15)
        tm.join(timeout=15)

        statuses_after = sorted(r[1] for r in after_outcomes)
        assert statuses_after == ["committed", "graceful_reject"], f"UPDLOCK 结果异常：{after_outcomes}"
        assert lock_waits, "未能从 sys.dm_os_waiting_tasks 抓到锁等待证据"
        out["after"] = after_outcomes
        out["lock_wait"] = lock_waits[0]
    finally:
        with new_conn(autocommit=True) as c:
            c.cursor().execute("UPDATE dbo.tbl_ingredient SET qty_on_hand = ? WHERE ingredient_id = 1", (orig_qty,))

    return out


# =====================================================================
# 实验 3：AB-BA 死锁（1205）复现与有序加锁根治
# =====================================================================


def exp3_deadlock_and_fix() -> dict:
    # ---- Part A: 改进前（A: 1->2, B: 2->1）稳定复现 1205 ----
    barrier = threading.Barrier(2)
    outcomes_deadlock = []

    def lock_pair(name: str, first_id: int, second_id: int):
        with new_conn(autocommit=False) as conn:
            try:
                conn.cursor().execute(
                    "SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = ?",
                    (first_id,),
                ).fetchone()
                barrier.wait(timeout=5)
                conn.cursor().execute(
                    "SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = ?",
                    (second_id,),
                ).fetchone()
                conn.commit()
                outcomes_deadlock.append((name, "committed", None))
            except pyodbc.Error as exc:
                conn.rollback()
                msg = str(exc)
                is_1205 = "(1205)" in msg or "1205" in msg
                outcomes_deadlock.append((name, "deadlock_1205" if is_1205 else "other_error", msg[:120]))

    ta = threading.Thread(target=lock_pair, args=("A(1->2)", 1, 2))
    tb = threading.Thread(target=lock_pair, args=("B(2->1)", 2, 1))
    ta.start()
    tb.start()
    ta.join(timeout=15)
    tb.join(timeout=15)

    deadlocks = [r for r in outcomes_deadlock if r[1] == "deadlock_1205"]
    assert len(deadlocks) == 1, f"未按预期复现 1205 死锁：{outcomes_deadlock}"

    # ---- Part B: 改进后（全员统一按 ingredient_id 升序 1->2 加锁，连跑 5 轮 10 事务） ----
    fixed_outcomes = []
    for rnd in range(1, 6):
        b_round = threading.Barrier(2)

        def lock_ordered(name: str):
            b_round.wait(timeout=5)
            with new_conn(autocommit=False) as conn:
                try:
                    for ing_id in sorted([2, 1]):  # 统一升序：1 -> 2
                        conn.cursor().execute(
                            "SELECT qty_on_hand FROM dbo.tbl_ingredient WITH (UPDLOCK, ROWLOCK) WHERE ingredient_id = ?",
                            (ing_id,),
                        ).fetchone()
                    conn.commit()
                    fixed_outcomes.append((rnd, name, "committed"))
                except pyodbc.Error as exc:
                    conn.rollback()
                    fixed_outcomes.append((rnd, name, str(exc)[:100]))

        t1 = threading.Thread(target=lock_ordered, args=("A",))
        t2 = threading.Thread(target=lock_ordered, args=("B",))
        t1.start()
        t2.start()
        t1.join(timeout=15)
        t2.join(timeout=15)

    assert len(fixed_outcomes) == 10 and all(r[2] == "committed" for r in fixed_outcomes), (
        f"有序加锁出现非预期失败：{fixed_outcomes}"
    )
    return {
        "before": outcomes_deadlock,
        "after_total": len(fixed_outcomes),
        "after_deadlocks": 0,
    }


def main() -> int:
    before_inv = check_invariants()
    print(f"【基线核对】起始状态：订单={before_inv[0]}, 库存漂移={before_inv[1]}, 积分漂移={before_inv[2]}")

    r1a = exp1a_dirty_read()
    print(
        f"[Exp 1A 脏读] 原值={r1a['orig_qty']} | READ UNCOMMITTED 读到脏值={r1a['read_uncommitted']} "
        f"| READ COMMITTED 阻塞 {r1a['read_committed_wait_ms']}ms 后读到={r1a['read_committed']}"
    )

    r1b = exp1b_non_repeatable_read()
    print(
        f"[Exp 1B 不可重复读] READ COMMITTED: ({r1b['rc_r1']} -> {r1b['rc_r2']}, 写耗时 {r1b['rc_writer_ms']}ms) "
        f"| REPEATABLE READ: ({r1b['rr_r1']} -> {r1b['rr_r2']}, 写被阻塞 {r1b['rr_writer_ms']}ms)"
    )

    r1c = exp1c_phantom_read()
    print(
        f"[Exp 1C 幻读] REPEATABLE READ: ({r1c['rr_c1']} -> {r1c['rr_c2']}) "
        f"| SERIALIZABLE: ({r1c['sz_c1']} -> {r1c['sz_c2']}, 插入被范围锁阻塞 {r1c['sz_inserter_ms']}ms)"
    )

    r2 = exp2_lock_wait_and_oversell()
    lw = r2["lock_wait"]
    print(f"[Exp 2A 无锁防超卖失败(TOCTOU)] {r2['before']}")
    print(
        f"[Exp 2B UPDLOCK 锁等待与防超卖] 结果={r2['after']} | DMV 抓包："
        f"等待SPID={lw['waiting_spid']} 被阻塞于 SPID={lw['blocking_spid']}, "
        f"wait_type={lw['wait_type']}, mode={lw['request_mode']}, resource={lw['resource_type']}"
    )

    r3 = exp3_deadlock_and_fix()
    print(f"[Exp 3A AB-BA 死锁(1205)复现] {r3['before']}")
    print(f"[Exp 3B 升序加锁根治] {r3['after_total']} 次并发事务全部提交，死锁次数={r3['after_deadlocks']}")

    after_inv = check_invariants()
    print(f"【基线核对】结束状态：订单={after_inv[0]}, 库存漂移={after_inv[1]}, 积分漂移={after_inv[2]}")
    assert after_inv == before_inv and after_inv[1] == 0 and after_inv[2] == 0, "实验结束后存在数据漂移！"
    print("【结论】🎉 全部并发控制实验复现与改进验证通过，数据库零漂移！")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
