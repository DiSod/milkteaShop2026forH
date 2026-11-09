# ISSUE-018 · 订单取消（仅待制作）的实现记录

| 项目 | 内容 |
|---|---|
| **Issue** | 018 |
| **标题** | 订单取消（仅 `PENDING`）：让「下错单」有退路，同时不破坏库存与积分不变量 |
| **类型** | 功能补齐 / 结构变更 |
| **提出** | DiSod |
| **日期** | 2026-11-09 |
| **状态** | 🟢 已解决（同一提交闭环） |
| **关联** | [014](014-week07-conformance-and-pending.md) · [017](017-v1.0-known-boundaries.md)（边界 8） · [015](015-week09-ui-redesign.md) |

## 1. 为什么做

第 9 周补完菜单与购物车之后，暴露出第一个**演示现场会卡住**的问题：订单一旦创建就只会往前走。

`project/app/service/maker.py:11-13` 的状态机只有一条路：

```
PENDING → MAKING → READY → COMPLETED
```

顾客点错杯型、收银员按错饮品，**没有任何入口能撤回**；制作员只能一路推到「已完成」，
而那张单会以 `COMPLETED` 留在报表里，污染销售额与销量统计。

`business-rules.md` 的 A14 当时写的是「`CANCELLED` 不回冲原料」，说的是 v0.1 的 37 张历史单
（它们确实没回冲，认账不追）。新取消如果照抄 A14，会造成「状态取消了、原料却已经被扣掉」的假账，
所以这条规则必须改成「**新取消要回冲**」。

## 2. 做了什么

| 层面 | 落点 | 内容 |
|---|---|---|
| 结构 | `project/sql/11-migration/migration-06-order-cancellation.sql` | `ledger_type` 增 `CANCEL_BACK`、`point_type` 增 `REVOKE`、`ck_points_ledger_target` 允许 `REVOKE` 挂订单；**CHECK 总数仍 48 条**，脚本内自证后 `COMMIT` |
| 接线 | `project/sql/99-rebuild.sql` | 在 `migration-05` 之后追加第 13 步 |
| DAO | `project/app/dao/order_dao.py` | `get_for_cancel` / `list_sales_moves` / `sum_earned_points` / `insert_points_revoke` / `coupon_is_used` / `mark_cancelled` |
| 服务 | `project/app/service/ordering.py::cancel_order(order_id, member_id=None)` | 一个事务：状态校验 → 归属校验 → 券校验 → 逐条回冲 → 扣回积分 → 置 `CANCELLED` |
| 路由（18 → 20） | `routes_member.py` / `routes_maker.py` | `POST /orders/<id>/cancel`（`@member_required`）、`POST /maker/order/<id>/cancel`（`@staff_required("MAKER","MANAGER")`） |
| 界面 | `orders.html` / `maker.html` | `PENDING` 行才出现「取消」，点击先 `confirm()` |
| 测试 | `project/app/tests/test_order_cancel.py`（3 条） | 取消成功（库存与积分回到下单前）／已开工不可取消（409）／不能取消他人订单（403） |

## 3. 关键决策与理由

1. **只允许取消 `PENDING`**。`MAKING` 之后原料已经进杯子，回冲就是假账；宁可让店长走人工。这条限制写进了界面（按钮只在 `PENDING` 出现）和数据库更新条件（`AND order_status='PENDING'`）。
2. **不删数据，写反向流水**。取消不是 `DELETE`：库存加一条 `CANCEL_BACK`（正数）、积分加一条 `REVOKE`（负数），两条不变量（A6 `qty_on_hand = Σ流水`、A4 `points_balance = Σ流水`）因此自动成立。
3. **库存走唯一入口**。回冲不自己 `UPDATE tbl_ingredient`，而是复用 `stock_dao.apply_movement()`——它同时改结存与写流水，是"改数量必留流水"的唯一通道。
4. **状态更新靠受影响行数判断**。`UPDATE ... WHERE order_id=? AND order_status='PENDING'` 返回 0 就说明被别人抢先推进了，整体回滚并提示刷新。
5. **券已核销则拒绝**。退券需要"券回到未使用状态"，还牵涉有效期，属于 v2.0 的整单退；现在直接 409 并把人工处理的路留给店长。
6. **写入不切数据库身份**。取消同时跨订单域与库存域，单个岗位角色做不到（与 `place_order` 同一取舍，即 P-2）。

## 4. 踩到的两个坑

- **`SET NOCOUNT ON` 会让 `cursor.rowcount` 变成 -1**。`mark_cancelled` 最初带了 `SET NOCOUNT ON;`，导致并发保护恒失效、每次都报「订单状态已被其他操作改变」。DAO 里其余 insert 类函数保留 `NOCOUNT` 没关系，唯独这个"靠 rowcount 判断"的函数不能有。
- **测试清理只删流水会留下结存偏差**。第一次跑新用例时，`_purge` 只删了订单与流水、没有走取消流程，库里 5 种原料的结存与 `Σ流水` 差了 40，还连累 `test_staff_workbench` 三个用例失败。修法：`_purge` 删完行后**按 `Σ流水` 重算 `qty_on_hand`、按 `Σ积分流水` 重算 `points_balance`**，这样不管测试走到哪一步都能自愈。

## 5. 验证

| 检查 | 结果 |
|---|---|
| `python -m pytest -q` | **41 passed**（38 → +3） |
| `regression.sql` | **14/14 全绿** |
| `99-rebuild.sql` | exit=0，25.4 秒，仍然 `18 表 / 139 字段 / 31 外键 / 48 CHECK / 6 视图 / 4 角色` |
| 库基线 | 订单 1,963 / 库存流水 13,851 / `SUM(qty_on_hand)` 403,371.600 / 积分 25,224 / drift 0 |
| 端到端脚本 | 下单扣 784 → 取消回冲 5 种原料、扣回 8 分 → 状态 `CANCELLED` → 二次取消被拒 → 清理复原 |
| 截图 | `weeks/submissions/v1.0/result/07-app/orders.png`、`maker.png` 已重拍 |

## 6. 没做的部分

- 退款、退券、部分退款：属于 v2.0 整单退（A9），接口位置与状态机已留好。
- 收银员侧取消入口：散客单由制作台取消即可覆盖；收银台目前没有订单列表。
- 并发 TOCTOU：`place_order` 仍是"先查可做量再扣减"，与取消无关，留给 v2.0 与 P-2 一起处理。

## 7. 解决记录

- **2026-11-09**：实现并合入 `main`（提交 `60639e9`）。
- **2026-11-09（同日追加）**：修掉取消功能暴露的口径缺陷 —— `pay_status='SUCCESS'` 只排除了未支付单，不排除"已收款又取消"的单，报表会把退款算成营业额。D 口径统一追加 `order_status <> 'CANCELLED'`（`dao/report_dao.py` 的 Top N、`regression.sql` TC-10 的主查询与运行期查询）；`business-rules.md` A10、`manual.md` §8、报告 §3 同步。种子数据里没有 "SUCCESS 且 CANCELLED" 的行，故 1,926 单 / 23,762.00 不变；实测"下单 +1 单 4.00 → 取消后回到基线"，旧口径仍会把它算进去。`vw_daily_business_summary` 有意不动（保持全量口径，`cancelled_orders` 单独成列）。报告 `§1.4` 改为六段迁移、`§2.2` 执行顺序补第 13 步、`§2.3` 增「订单取消」小节；`business-rules.md` A14 补"第 9 周起新取消会回冲"；应用 README 增边界 11。
