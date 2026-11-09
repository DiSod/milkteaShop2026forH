# ISSUE-019 · 券核销闭环（第 9 周）

> 一句话：**券表从第 6 周就设计好了，但直到这一轮之前，应用里没有任何一行代码真正用过它。**
> 本轮把它接上：默认发券、下单抵扣、一券一单、取消退券。

- 提出：2026-11-09　·　状态：✅ 已解决

---

## 1. 为什么做

第 6 周为券做了两件事：把「券种」和「券实例」拆成 `tbl_coupon_template` + `tbl_coupon`（`migration.sql`），
并给核销时间窗加了 `ck_coupon_used_time_range`。**但结构完成不等于功能可用**：

| 现象 | 实测 |
|---|---|
| 应用里没有任何券界面 | `coupon` 只出现在 `member_dao` / `order_dao` / `ordering` 的校验分支，无路由、无模板 |
| 下单永远没有折扣 | `ordering.py` 里 `discount = Decimal("0.00")`、`amount_paid = amount_due - discount` 写死 |
| 24 张历史券全部过期 | 有效期 `2026-09-12 ~ 2026-10-12`，`valid_now = 0` |
| 「一券一单」（A5）只在文档里 | `tbl_order_header.coupon_id` 只是普通外键，没有唯一约束 |
| `status='USED'` 但 `used_time` 为空没人拦 | 这是第 7 周审计的 P2 |

所以「券核销」不是加个新功能，而是**把已设计、已约束、已授权、已写进文档的东西真正跑起来**。

---

## 2. 做了什么

| 层 | 落点 | 内容 |
|---|---|---|
| 结构 | `project/sql/11-migration/migration-07-coupon-redemption.sql` | ① `ck_coupon_used_time_consistent`：`USED` 必有 `used_time`、非 `USED` 必为空；② 过滤唯一索引 `uq_order_header_coupon`（`WHERE coupon_id IS NOT NULL`）把 A5 落到库层；③ 默认发放 6 张可用券（M001—M003 各 2 张，模板 `TPL_CAMP_5`，30 天有效） |
| 重建 | `project/sql/99-rebuild.sql` | 追加第 14 步 `:r`，尾注改为「CHECK 共 49 条」 |
| DAO | `project/app/dao/coupon_dao.py`（新建） | `list_for_member` / `list_available` / `get_redeemable` / `mark_used` / `release` |
| DAO | `project/app/dao/order_dao.py` | `insert_header(...)` 增 `coupon_id=None`；新增 `detach_coupon(order_id)` |
| 业务 | `project/app/service/ordering.py` | `place_order(..., coupon_id=None)`：校验归属/状态/有效期/门槛 → `discount = min(面额, 订单金额)` → 写头 → **提交前**核销；`cancel_order` 退券 |
| 业务 | `project/app/service/coupons.py`（新建） | `wallet()` 分可用 / 已用 / 已过期三组；`available()` |
| 界面 | `coupons.html`（新建）、`menu.html`、`orders.html`、`base.html`、`app.css` | 券包页；菜单页选券；订单页显示被划掉的原价；导航加「我的券」 |
| 测试 | `project/app/tests/test_coupon_redeem.py`（新建 5 条） | 券包可见 / 抵扣生效 / 一券不能二次用 / 不能用别人的券 / 取消退券 |

---

## 3. 关键决策与理由

1. **不做运行时发券**（店长发券、积分兑券），改为迁移脚本里**默认发券** —— 用户 2026-11-09 定调。
   理由：发券是一条完整的运营流程（额度、审批、防刷），v1.0 没有位置承载它；
   而「有券可用」是演示核销的必要条件，所以用静态数据满足。
2. **A5 用过滤唯一索引而不是触发器**：`WHERE coupon_id IS NOT NULL` 允许历史 1,939 张单的 `NULL` 共存，
   同时让「同一张券绑两张单」在库层直接失败。索引比触发器更容易被验证（`is_unique`/`has_filter` 可查）。
3. **抵扣额 `= min(面额, 订单金额)`**，不引入找零：券比单贵时实付 0，不产生负数金额。
4. **核销放在事务最后一步**：前面库存与积分已经写成功，`mark_used` 若返回 0 行就抛异常整单回滚 ——
   宁可重来，也不要出现「扣了料、加了分、券还在」。
5. **取消先解绑再退券**：`uq_order_header_coupon` 是唯一索引，券还挂在单上时无法直接把它改回 `UNUSED` 再被别的单用，
   所以 `detach_coupon` 先把 `coupon_id` 置 `NULL`，`release` 再把状态改回 `UNUSED` 并清 `used_time`。
6. **`SET NOCOUNT OFF` 是必须的**（见下）。

---

## 4. 两个坑

### 4.1 `SET NOCOUNT ON` 会让乐观并发永远失败

`insert_header` 的 SQL 以 `SET NOCOUNT ON;` 开头。**`NOCOUNT` 是会话级设置**，同一连接上后续
`mark_used` 的 `cursor.rowcount` 恒为 `-1`，于是「这张券已被用掉」永远检测不出来，
表现为**每次用券下单都 409「这张券刚刚被用掉或已过期」**。
修法：`mark_used` 的 SQL 以 `SET NOCOUNT OFF;` 开头，并在注释里写明原因。

### 4.2 测试清理只删流水会留下结存偏差

`_purge` 若只删订单与流水、不处理结存，会留下「结存已减、流水已删」的差额（曾让 5 种原料各差 40，
并连累另外三个用例）。修法：删完行后按 `Σ流水` 重算 `qty_on_hand`、按 `Σ积分流水` 重算 `points_balance`。

---

## 5. 验证

| 项 | 结果 |
|---|---|
| `99-rebuild.sql` | exit=0，**19.2 秒**；18 表 / 139 字段 / 31 外键 / **49 CHECK** / 22 索引 / 6 视图 / 4 角色 |
| 券 | 30 张（24 `USED` + 6 `UNUSED`），可用券 6 |
| `pytest -q` | **46 passed**（原 41 + 5 新） |
| `regression.sql -b` | **14/14 全绿**（TC-03/04 已改为种子口径） |
| 端到端 | 用券下单：`8.00 − 5.00 = 3.00`，券变 `USED`；取消：订单 `CANCELLED`、`coupon_id` 置 `NULL`、券回 `UNUSED` |
| 库复原 | 订单 1,963 / 流水 13,851 / 结存 403,371.600 / 积分 25,224 / drift 0 |

---

## 6. 没做

- 运行时发券（店长发券、积分兑换券）—— 用户明确不做。
- 收银台代客下单用券 —— 散客没有会员归属，语义要先定。
- A11（兑换券必须由 `REDEEM` 流水换来）仍未闭合：6 张默认券直接写在 `tbl_coupon`，没有对应积分流水。

---

## 7. 解决记录

- 2026-11-09：结构 + 代码 + 界面 + 测试 + 截图全部完成；顺带把销售额口径的取消单问题（`21b0781`）在同一轮里收口。
