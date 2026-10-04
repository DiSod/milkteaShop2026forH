# ISSUE-008: 积分退单约束死锁修复与 CRUD 健壮性加固（防吞库存/防除零崩溃）

| 元数据 | 内容 |
|---|---|
| **状态** | 🟡 进行中 (In Progress) |
| **类型** | 数据库约束 / DML 健壮性 · Bug 修复 |
| **提报人/Agent** | 何争霖（hezhlin5 / 核心工程） |
| **指派处理** | 核心工程（hezhlin5）—— 改 `02-constraints/constraints.sql` 与 `05-dml/crud.sql` |
| **提报日期** | 2026-10-04 |
| **关联文件** | [`project/sql/02-constraints/constraints.sql`](../../project/sql/02-constraints/constraints.sql), [`project/sql/05-dml/crud.sql`](../../project/sql/05-dml/crud.sql) |

---

## 1. 现象与矛盾描述

在对第 3 周交付成果的穿透式代码审查与实测验证中，定位到 DDL 约束与 CRUD 演示脚本中存在的 3 个严密性漏洞：

1. **🚨 积分退单死锁（Error 547）**：
   `ck_points_ledger_target` 规定 `point_type='REDEEM'` 必须 `coupon_id IS NOT NULL`。但在现实业务中，超过 90% 的自费订单顾客**并未使用优惠券**。在发生退单时，由于 `coupon_id IS NULL`，插入扣回积分的流水会直接触发 CHECK 约束拦截，导致**全店无券订单退单事务 100% 崩溃**。
2. **🚨 退单库存回冲触发非确定性多对一 UPDATE（吞库存）**：
   `crud.sql` 步骤 3.6 中，更新库存语句仅根据 `WHERE l.remark = N'订单取消回冲'` 关联流水表。当同一原料历史上发生多次退单回冲时，SQL Server 的 `UPDATE ... FROM ... JOIN` 会随机拾取其中一行的值叠加，其余退单数量被**静默吞掉**。
3. **🚨 采购加权成本除零与击穿 NOT NULL（Error 515）**：
   `crud.sql` 步骤 3.4 中，采购加权平均成本公式使用 `NULLIF(qty_on_hand + qty_received, 0)`。当新原料初始库存为 0 且到货验收为 0（因变质全部拒收）时，`NULLIF` 返回 NULL，撞上 `moving_avg_cost NOT NULL` 约束导致收货事务报错失败。

---

## 2. 事实证据（对照与实测复现）

### 证据 ① —— 无券订单取消退单直接崩溃 (Error 547)
```sql
-- 模拟无券订单取消时扣回积分
INSERT INTO tbl_points_ledger (member_id, point_type, point_change, order_id, coupon_id)
VALUES (1, 'REDEEM', -5, 1, NULL);
```
**实测结果**：
```text
消息 547，级别 16，状态 1
INSERT 语句与 CHECK 约束"ck_points_ledger_target"冲突。该冲突发生于表"dbo.tbl_points_ledger"。
语句已终止。
```

### 证据 ② —— 两次退单回冲实测被吞掉 20g 库存
初始库存 100g，发生两次退单回冲（+10g 与 +20g），预期应为 130g。
使用原版 `WHERE l.remark = N'订单取消回冲'` 执行 UPDATE：
```text
更新后库存(应为130): 110.000 (丢失 20g 原料，只加上了其中一条！)
```

### 证据 ③ —— 零到货验收时击穿 NOT NULL (Error 515)
初始库存 0g，采购到货因变质拒收（实收 0g）：
```text
消息 515，级别 16，状态 2
不能将值 NULL 插入列 'moving_avg_cost'，表 'milktea_shop.dbo.tbl_ingredient'；列不允许有 Null 值。
UPDATE 失败。
```

---

## 3. 建议解法与行动方案

### 方案一：修复 `ck_points_ledger_target` 约束（支持无券退单）
在 `project/sql/02-constraints/constraints.sql` 中将约束调整为：
```sql
ALTER TABLE tbl_points_ledger
    ADD CONSTRAINT ck_points_ledger_target
        CHECK (
               (point_type = 'EARN'   AND order_id  IS NOT NULL)
            OR (point_type = 'REDEEM' AND (coupon_id IS NOT NULL OR order_id IS NOT NULL))
        );
```
*语义说明*：`REDEEM` 既可以是积分兑券（`coupon_id` 非空），也可以是退单积分回滚（`order_id` 非空）。两者不能同时为空。

### 方案二：重构 `crud.sql` 步骤 3.6 的库存回冲更新（严格聚合防吞行）
改用按订单 ID 聚合的 CTE 或内联分组视图：
```sql
UPDATE i
SET    i.qty_on_hand = i.qty_on_hand + r.total_return_qty
FROM   tbl_ingredient i
JOIN (
    SELECT ingredient_id, SUM(qty) AS total_return_qty
    FROM   tbl_stock_ledger
    WHERE  order_id = (SELECT order_id FROM tbl_order_header WHERE order_no = 'DEMO-O1')
      AND  remark   = N'订单取消回冲'
    GROUP BY ingredient_id
) r ON r.ingredient_id = i.ingredient_id;
```

### 方案三：完善 `crud.sql` 步骤 3.4 移动加权成本防除零保护
使用 `CASE WHEN (qty_on_hand + qty_received) > 0` 保护：
```sql
UPDATE i
SET    i.moving_avg_cost = CASE 
           WHEN (i.qty_on_hand + d.qty_received) > 0 
           THEN (i.qty_on_hand * i.moving_avg_cost + d.qty_received * d.unit_price) / (i.qty_on_hand + d.qty_received)
           ELSE i.moving_avg_cost 
       END,
       i.qty_on_hand = i.qty_on_hand + d.qty_received
FROM   tbl_ingredient i ...
```

---

## 4. 验收标准
1. 无券订单退单（`coupon_id IS NULL, order_id IS NOT NULL`）执行成功，积分成功扣减；
2. 同一原料多次退单回冲时，库存数量精准累加，零丢损；
3. 实收为 0 的异常到货单更新时，加权成本保持原值，不抛出 NULL 错误；
4. `99-rebuild.sql` 与 `crud.sql` 连续执行 3 次全部通过。

---

## 5. 解决记录
*(修复完成后填写)*
