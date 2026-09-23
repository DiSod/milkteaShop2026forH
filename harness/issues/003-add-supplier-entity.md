# ISSUE-003: 采购单补全供应商外码（补建极简 `tbl_supplier`）

| 元数据 | 内容 |
|---|---|
| **状态** | 🔴 待处理 (Open) |
| **类型** | 关系完整性 / 模式规范 |
| **提报人/Agent** | 二人小组工程侧 Agent |
| **指派处理** | 双人共同讨论 / 文档主编 |
| **提报日期** | 2026-09-23 |
| **关联文件** | [`weeks/week01/business-requirements.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week01/business-requirements.md) (§2.4), [`weeks/week02/schema-design.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week02/schema-design.md) |

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
