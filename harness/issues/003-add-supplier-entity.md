# ISSUE-003: 采购单补全供应商外码（补建极简 `tbl_supplier`）

| 元数据 | 内容 |
|---|---|
| **状态** | 🟢 已解决 (Resolved) |
| **类型** | 关系完整性 / 模式规范 |
| **提报人/Agent** | 二人小组工程侧 Agent |
| **指派处理** | 双人共同讨论 / 文档主编 |
| **提报日期** | 2026-09-23 |
| **关联文件** | [`weeks/week01/business-requirements.md`](../../weeks/week01/business-requirements.md) (§2.4), [`weeks/week02/schema-design.md`](../../weeks/week02/schema-design.md) |


---

## 1. 为什么提这个 Issue？（直白说问题）
目前设计里把“供应商”完全砍掉了，采购单只记录原料和数量，不记供货商。
这导致在数据库逻辑上变成了**“向空气进货”**，采购单成了没有供货来源的孤单。

---

## 2. 为什么需要补回供应商？
1. **答辩最基本的完整性**：
   数据库实验课程非常注重外键级联。如果有采购入库却查不到供货方，在答辩展示 ER 图时，老师几乎必然会问：*“货是谁送来的？你们采购单的外码连向了哪里？”*
2. **连接查询的天然素材**：
   第 4 周要求做多表连接查询（JOIN），`供应商 ──> 采购单 ──> 采购明细 ──> 原料` 是数据库中最经典、最标准的供应链级联外码模板。
3. **实现代价极小**：
   只需要增加一张 5 个字段的极简小表，写不到 10 行 SQL，完全不会增加系统负担。

---

## 3. 建议修改方案
1. 新建极简供应商表：
   ```sql
   CREATE TABLE tbl_supplier (
       supplier_id     INT IDENTITY PRIMARY KEY,
       supplier_code   VARCHAR(10) UNIQUE NOT NULL, -- 如 'SUP01'
       supplier_name   NVARCHAR(50) NOT NULL,       -- 如 '晨光乳业'
       contact_phone   VARCHAR(20),
       is_active       BIT DEFAULT 1
   );
   ```
2. 在采购单表 `tbl_purchase_order` 中增加一列外键：
   ```sql
   supplier_id INT NOT NULL FOREIGN KEY REFERENCES tbl_supplier(supplier_id)
   ```

---

## 5. 解决记录

**处理人**：DiSod（文档主编）裁决 / hezhlin5（核心工程）确认接受
**解决时间**：2026-10-03
**状态**：🟢 **已解决** —— hezhlin5 确认采纳极简 `tbl_supplier`（4 字段）并入采购单外码，四层级联 JOIN 素材成立

### 裁决摘要（已双人确认闭环）

| 原始诉求 | 裁决 | 确认状态 |
|---|---|---|
| 补建极简 `tbl_supplier` | ✅ **采纳，但降低规格** | ✅ 双方一致确认 |
| 字段 5 个（含 `contact_phone`） | ⚠️ **降为 4 个** —— 去掉 `contact_phone` | ✅ hezhlin5 确认认可 4 字段极简规格 |
| 采购单加 `supplier_id` 外码 | ✅ 采纳 | ✅ 双方一致确认 |

### ⚠️ 一处必须说清的定性

**这是对 week1 §2.4 的「推翻」，不是「细化」。**

week1 §2.4 的方案甲原话是"**完全不记** —— 采购单只记原料与数量" ——
**它明确否掉的就是采购单上的供应商**，不只是"供应商档案"。

初稿曾把它写成"细化而非推翻"，**与 week1 原文不符，已改正**，并补进了
[`issue-review.md`](../../weeks/week02/issue-review.md) 第十节的修正汇总（第 16 行）。

**仍然保留 week1 §4.2 #6 的边界** —— 本表**不记**联系人、账期、银行账户。

### 变更说明

| 项 | 内容 |
|---|---|
| 新增表 | `tbl_supplier(supplier_id, supplier_code, supplier_name, is_active)` |
| 改动表 | `tbl_purchase_order` 增加 `supplier_id` 外码 |
| 留下的 JOIN 链 | `供应商 → 采购单 → 采购明细 → 原料`（**四层级联**，第 4 周 `query.sql` 素材） |
| 已写入 | [`project/docs/data-dictionary.md`](../../project/docs/data-dictionary.md) 第 17 张表 |

### commit 引用

| commit | 说明 |
|---|---|
| `9c5cd69` | 出具裁决意见（采纳 + 降规格） |
| `a5c2428` | 本 Issue 状态 🔴 → 🟡 |
| `ccc19ee` | 补充"推翻 §2.4"的如实定性说明 |
| `f4ea039` | 数据字典定稿 17 表全量定义（含 tbl_supplier 与采购单外码） |

### 遗留

| # | 事项 | 说明 |
|---|---|---|
| 1 | week1 报告 §2.4 正文同步修改 | 移交由 ISSUE-006 文档维护统筹处理 |

