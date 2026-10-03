# ISSUE-004: 锁定销量母本并启动 Python 仿真造数原型（台账自洽）

| 元数据 | 内容 |
|---|---|
| **状态** | 🔴 待处理 (Open) |
| **类型** | 数据工程 / 仿真造数 |
| **提报人/Agent** | 二人小组工程侧 Agent |
| **指派处理** | 核心工程 (编写造数脚本) / 文档主编 (登记说明) |
| **提报日期** | 2026-09-23 |
| **关联文件** | [`project/data/README.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/project/data/README.md), [`weeks/week01/data-availability.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week01/data-availability.md) |

---

## 1. 为什么提这个 Issue？（直白说问题）
虽然第一周调研了很多公开数据，但目前 [`project/data/README.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/project/data/README.md) 里的数据源依然全都是“待定”。
下周（第 3 周）就必须往数据库里装入真实的种子数据（`04-seed`）。
手填几万行订单不可能，必须尽快用 Python 写出仿真造数脚本，否则第 3 周建好表后将陷入“空库无数据可查”的尴尬。

---

## 2. 真实造数的核心逻辑（台账平衡）

结合 Issue 001 还原的真实奶茶店逻辑，造数脚本其实非常好写，遵循以下自洽公式：

$$\text{期初原料库存} + \sum\text{采购入库} - \sum(\text{订单明细}\times\text{配方反冲}) - \sum\text{打烊损耗} = \text{期末库存}$$

- **销量母本**：直接选定 Mendeley 的 *Retail Transactions and Stocks Data*，只借用它的**日常波动曲线（周末高峰、雨天低谷等周期性）**；
- **自洽流转**：
  1. 每天随机生成 200~400 笔订单；
  2. 订单根据配方自动扣减总原料库存；
  3. 闭店时模拟扣除少量打烊损耗；
  4. 当某种原料低于补货点时，自动触发采购单，隔天入库补足。

---

## 3. 建议行动方案
1. **工程侧牵头**：在 `project/data/` 下编写 `generate_seed.py`，先跑出 **7 天** 的小样本数据，验证没有负库存、台账严格平衡；
2. **生成种子 SQL**：验证通过后放大至 90 天，直接导出为 `project/sql/04-seed/seed_data.sql`；
3. **文档侧配合**：舍友在 `project/data/README.md` 中补齐母本来源说明与生成规则说明。

---

## 5. 解决记录

**处理人**：⏳ **核心工程（hezhlin5）主责** —— 尚未开工
**解决时间**：⏳
**状态**：🔴 **待处理** —— **本 Issue 是当前唯一完全未动的排雷项，且卡着第 3 周的种子数据**

### 前置条件（现已具备）

| # | 前置 | 状态 |
|---|---|---|
| 1 | 表结构（17 张表 / 133 字段） | ✅ 已定稿于 [`project/docs/data-dictionary.md`](../../project/docs/data-dictionary.md) |
| 2 | 主数据（30 成品 / 60 原料 / 10 配方） | ✅ 已定稿于 [`weeks/week02/master-data.md`](../../weeks/week02/master-data.md) |
| 3 | 扣料口径（反冲倒扣 + 两路展开） | ✅ **D1 · D-06**：`应耗用 = Σ(配方 qty × 数量) + Σ(加料 qty_per_serving × 份数)` |
| 4 | 台账平衡式 | ✅ `期初 + 采购入库 − 销售耗用 − 报损 = 期末`（v0.1，不含盘盈亏） |
| 5 | 记账口径 | ✅ **干重当量**；煮制/泡制不产生流水（**D2**） |

> **本 Issue 的 4 项前置已全部就绪** —— 它现在是**纯工程任务**，不再被设计问题阻塞。

### 仍缺的一件事（文档侧配合，属我方）

- `project/data/README.md` 的**数据源登记表仍是空的**（`_（待登记）_`），
  而本 Issue 已给出母本答案（Mendeley *Retail Transactions and Stocks Data*）→ **待登记**

### commit 引用

⏳ 待开工后填写
