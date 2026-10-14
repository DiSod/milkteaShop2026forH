# ISSUE-011: 第 6 周迁移接入策略定案与订单明细 subtotal 加料一致性实测反馈

| 元数据 | 内容 |
|---|---|
| **状态** | 🟢 已解决 (Resolved) |
| **类型** | 架构决策 / 完整性约束实测 / 开工对齐 |
| **提报人/Agent** | 何争霖（hezhlin5 / 核心工程） |
| **协同讨论** | 胡博锐（DiSod / 文档主编） · 何争霖（hezhlin5 / 核心工程） |
| **解决日期** | 2026-10-14 |
| **关联核心文件** | [`project/docs/v0.1-issues.md`](../../project/docs/v0.1-issues.md) · [`weeks/week06/README.md`](../../weeks/week06/README.md) · [`weeks/week05/README.md`](../../weeks/week05/README.md) · [`project/sql/README.md`](../../project/sql/README.md) · [`STRUCTURE.md`](../../STRUCTURE.md) |

---

## 0. 一句话

**工程侧已对全库订单明细与加料关系完成 100% 穿透实测，证实 `subtotal` 已严格计入加料（0 差额），据此坚决否决单表行级 CHECK 提议并转为第 6 周反规范化学术论证；同时双人定案第 6 周 `migration.sql` 接入 `99-rebuild.sql` 并落地于 `project/sql/11-migration/`，确保主工程单一基准、杜绝后续版本漂移。**

---

## 1. 对齐诉求与背景

在进入第 6 周（ch7 函数依赖与规范化、`migration.sql` 模式迁移与重构）前，存在三项直接影响架构与约束设计的待对齐问题：
1. **诉求一（业务实测）**：队友在 [`project/docs/v0.1-issues.md`](../../project/docs/v0.1-issues.md) §1.1 问题 2 提出「明细 `subtotal` 与 `qty × unit_price` 的一致性未约束」，标注待工程侧确认加料加价是否计入 `subtotal`，若计入则行级 CHECK 不成立；
2. **诉求二（目录落点）**：第 6 周迁移脚本的目录落点待拍板；
3. **诉求三（架构接入）**：`migration.sql` 是否接入 `99-rebuild.sql`。此前文档存在“倾向不接入以保留 v0.1 基线”的初判，需在版本演进与基准管理上做出最终权衡。

---

## 2. 核心业务实测与约束裁定

### 2.1 实测过程与数据证据

工程侧在本地 SQL Server 2022 Express 生产级种子数据（2,630 行订单明细、90 天仿真销售）上执行穿透审计：

```sql
-- 检验 1: 扫描 qty * unit_price 与 subtotal 的差额分布
SELECT 
    COUNT(*) AS total_details,
    SUM(CASE WHEN subtotal = qty * unit_price THEN 1 ELSE 0 END) AS match_base,
    SUM(CASE WHEN subtotal != qty * unit_price THEN 1 ELSE 0 END) AS has_topping_diff,
    MAX(subtotal - qty * unit_price) AS max_diff
FROM tbl_order_detail;
```

**运行结果**：
- `total_details`: 2,630 行；
- `match_base`: 2,015 行（无加料明细，严格等于 $qty \times unit\_price$）；
- `has_topping_diff`: **615 行（加料明细，全部存在 1.00 ~ 3.00 的差额）**。

```sql
-- 检验 2: 联合小料明细表 tbl_order_detail_topping 校验完整小计恒等式
SELECT COUNT(*) AS mismatch_count
FROM (
    SELECT 
        od.order_detail_id,
        od.subtotal,
        (od.qty * od.unit_price) + ISNULL(SUM(odt.qty * odt.unit_price), 0) AS expected_subtotal
    FROM tbl_order_detail od
    LEFT JOIN tbl_order_detail_topping odt ON od.order_detail_id = odt.order_detail_id
    GROUP BY od.order_detail_id, od.qty, od.unit_price, od.subtotal
) t
WHERE ABS(subtotal - expected_subtotal) > 0.001;
```

**运行结果**：
- `mismatch_count`: **0（全库 2,630 行明细 100% 严丝合缝匹配，差额绝对为 0）**！

### 2.2 结论与裁定

1. **业务事实确凿**：系统业务逻辑中，`tbl_order_detail.subtotal` **已完整计入加料金额**；
2. **否决单表 CHECK**：若在 `tbl_order_detail` 强加行级 `CHECK (subtotal = qty * unit_price)`，将直接导致 615 行（占全库 23.4%）的合法加料订单明细插入/校验失败，属于阻断性错误；
3. **约束归宿与反规范化论证**：
   - 该一致性属于**跨表派生一致性**（跨 `tbl_order_detail` 与 `tbl_order_detail_topping` 两张表），标准 SQL 无法用单表行级 `CHECK` 表达；
   - 本项作为第 6 周规范化分析报告（`project/docs/normalization.md`）中关于「派生列冗余 vs 一致性维护成本」的核心论证案例（反规范化以加速明细与订单金额聚合查询，代价是跨表一致性需额外机制维护）；
   - 后续阶段三（第 11—12 周）可通过触发器/事务型存储过程或应用层业务事务进行一致性保障。

---

## 3. 架构接入与目录落点定案

### 3.1 `migration.sql` 接入 `99-rebuild.sql`（推翻原“不接入”倾向）

| 对比维度 | 方案 A：不接入 99-rebuild | 方案 B：接入 99-rebuild（定案采纳） |
|---|---|---|
| **单一基准（SSOT）** | ❌ 主工程存在 v0.1 和重构后两套分裂状态；第 7—9 周开发 App 时，环境若未手动打补丁就会产生模式漂移 | ✅ `project/` 主工程永远处于最新唯一基准，拉起即可支撑后续 App 开发与测试 |
| **历史可复现性** | 维持 v0.1 | ✅ **完全不受影响**：v0.1 已在 `weeks/submissions/v0.1/code/` 100% 独立物理冻结，内含独立一键重建，无须担心被覆盖 |
| **迁移演示价值** | 独立执行迁移脚本 | ✅ **兼得**：`migration.sql` 本身保持可重复执行的独立幂等脚本，在老库副本上可单独重放演示迁移前后数据语义保持；同时被 `99-rebuild.sql` 作为阶段二演进标准流水线编排 |

### 3.2 目录落点定案

- **落地目录**：`project/sql/11-migration/`
- **理由**：数字序号紧随 `10-transaction`，清晰不抢占阶段三（11—13 周）存储过程/触发器/视图优化的预留位置，完全符合规范约定。

---

## 4. 落地与回写对照

各项定案与反馈已同步回写至各基准文档：
1. [`project/docs/v0.1-issues.md`](../../project/docs/v0.1-issues.md)：
   - §1.1 问题 2 补充实测 0 差额数据证据，明确否决单表 CHECK 结论；
   - §4 回写两项双人定案结果；
   - §5 新增汇总表更新状态。
2. [`weeks/week06/README.md`](../../weeks/week06/README.md)：
   - §二 回写两项开工定案；
   - §三 任务 6 锁定路径 `project/sql/11-migration/migration.sql`，第 4 项补充第 4 个反规范化素材；
   - §四 约束 4 更新为双重验证机制。
3. [`weeks/week05/README.md`](../../weeks/week05/README.md)：§9.4 回写裁定闭环。
4. [`project/sql/README.md`](../../project/sql/README.md)：执行顺序表登记序号 11 `11-migration/`。
5. [`STRUCTURE.md`](../../STRUCTURE.md)：目录树更新为接入 99-rebuild 保持单一真源。

---

## 5. 解决记录 · 何争霖（hezhlin5）· 2026-10-14

- **状态**：🟢 **已解决 (Resolved)**
- **结论**：加料实测确认，单表 CHECK 否决；接入 99-rebuild 与 11-migration 落点定案。
- **分支与提交**：
  - 本次反馈文档与定案由 `main` 提交并推送到远端，保证队友可见；
  - 随后从 `main` 切出特性分支 `feat/week06-normalization-and-migration` 并推送到远端，开启第 6 周规范化分析与模式迁移实现。

