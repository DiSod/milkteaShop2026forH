# ISSUE-006: 关系模式设计正文全面同步修订至 17 表及历史文档连带对齐

| 元数据 | 内容 |
|---|---|
| **状态** | 🟢 已解决 (Resolved) |
| **类型** | 文档维护 / 模式对齐 |
| **提报人/Agent** | 何争霖（hezhlin5 / 核心工程） |
| **指派处理** | 文档主编（DiSod） |
| **提报日期** | 2026-10-03 |
| **关联文件** | [`weeks/week02/schema-design.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week02/schema-design.md), [`project/docs/data-dictionary.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/project/docs/data-dictionary.md), [`weeks/week01/business-requirements.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week01/business-requirements.md) (§2.4) |

---

## 1. 现象与矛盾描述

随着 ISSUE-001/002/003 裁决意见已获双人共同确认闭环，17 张核心表的关系模式已在成果域 [`project/docs/data-dictionary.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/project/docs/data-dictionary.md) 全面定稿。

但目前文档域仍存在以下口径滞后与“双轨”现象：
1. **主报告正文滞后**：[`weeks/week02/schema-design.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week02/schema-design.md) 正文仍旧记录着 21 张表与已作废的旧决策 D-01（双库位）、D-02（两行移库）、D-03（只认操作台扣料）等，顶部仅有一段“本设计已被修订”的提示横幅；
2. **week1 历史推翻处未留痕**：[`weeks/week01/business-requirements.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week01/business-requirements.md) §2.4 仍写着“方案甲：完全不记供应商”，而 ISSUE-003 已定性推翻此条并新增了 `tbl_supplier`，需在 week1 对应位置增加修订说明；
3. **协作规范中的遗留小尾巴**：`STRUCTURE.md` 10.1 节遗留问题中提到的“`99-rebuild.sql` 桩文件过渡校验”与“脚本头注释归属”，需在文档侧做简要闭环或约定。

---

## 2. 事实证据（对照）

- **真相源 A**：[`project/docs/data-dictionary.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/project/docs/data-dictionary.md) 已定稿为 17 张表，废弃移库与双库位；
- **滞后处 B**：[`weeks/week02/schema-design.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week02/schema-design.md) 第三节表清单仍列 21 张表；
- **滞后处 C**：[`weeks/week01/business-requirements.md`](file:///f:/%E6%95%B0%E6%8D%AE%E5%BA%93/milkteaShop2026forH/weeks/week01/business-requirements.md) §2.4 方案甲未附推翻说明。

---

## 3. 影响评估与潜在风险

- **对工程侧影响**：**零影响**。工程造数与第 3 周 DDL 严格以 `project/docs/data-dictionary.md` 为唯一真相源，不依赖 `schema-design.md`。
- **对阶段交付与答辩影响**：阶段一报告评审与答辩时，评委若阅读第 2 周过程报告，正文 21 表与数据字典 17 表容易造成阅读误导，给人“文档未整理完毕”的印象。

---

## 4. 建议解法与行动方案

按照团队“**全库文档由 DiSod 独占执笔**”的协作规矩，工程侧提报此 Issue 交由文档主编统筹维护：
1. **翻新 `schema-design.md` 正文**：将正文中的 21 表清单统一精简为 17 表，标明作废决策（D-01~D-03），撤掉顶部的临时警示横幅；
2. **同步 week1 附注**：在 `weeks/week01/business-requirements.md` §2.4 加一行脚注或修订框，明确该条已被 ISSUE-003 与 `issue-review.md` 裁决修订；
3. **阶段一报告对齐**：配合完善 `weeks/submissions/v0.1/report.md` 中的设计决策章节。

---

## 5. 解决记录

**处理人**：DiSod（文档主编）
**解决时间**：2026-10-03
**状态**：🟢 **已解决** —— 第 4 节的**三项行动方案全部完成**，并额外闭环了两条连带问题

### 逐条对照原始诉求

| # | 原诉求 | 落地 | 状态 |
|---|---|---|---|
| 1 | **翻新 `schema-design.md` 正文**：21 表 → 17 表，标明作废 D-01~D-03，撤掉临时警示横幅 | 见下"具体改动" | ✅ |
| 2 | **同步 week1 §2.4 附注**：明确该条已被 ISSUE-003 推翻 | week1 §2.4 **改写为终态结论**（定案建 `tbl_supplier`），并连带修正 §4.1 #16 / §4.2 #6 两处引用 | ✅ |
| 3 | **阶段一报告对齐**：配合完善设计决策章节 | `report.md` 补齐 1.3.5 的**裁决闭环结果**、2.1 数据源、2.2 **仿真造数成果**、3.2/3.3 | ✅ |

### 具体改动

> **原则**：文档一律呈现**最终成果**，**不带修订痕迹**（不留"原 X → 现 Y"对照表、不留 ~~删除线~~，也不用 `已作废 / 已打补丁` 这类标注）。
> 被否决的方案以正常的"**被否决的方案**"表格呈现 —— 答辩素材保留，但不读起来像修订日志。

**① `weeks/week02/schema-design.md`**

| 位置 | 改动 |
|---|---|
| 头部 | 撤掉"⚠️ 本文件的设计已被修订，尚未同步"横幅 → 改为**「已完成」+ 与数据字典的分工说明** |
| **D-01 / D-02 / D-03** | **内容重写为终态决策**：D-01 库位 → **库存模型：单库**；D-02 移库 → **扣减方式：反冲倒扣**；D-03 操作台 → **库存完整性：非负约束**。旧的库位 / 移库 / 操作台方案降为各节的「**被否决的方案**」 |
| **D-05a / D-07 / D-10 / D-11** | 同样改为终态表述（`NULL` 表"与维度无关" / 规格外键 + 小料子表 / 支付并入订单头 / 券一张表）；旧方案进「被否决的方案」 |
| **D-08 / D-08a** | D-08 去掉"命名说明"，表名直接写 `_detail`；D-08a 改为"**移库单：不建**" |
| 决策总览 | **去掉状态列**，只列 16 条决策的**最终结论**；裁决 D1—D8 改为一句指向 `issue-review.md` |
| 第三节表清单 | **21 张 → 17 张**全量重写；**不保留"4 张消失、3 张延后"对照表**；表间关系图重画 |
| 三·补 | 由"3 个设计漏洞 ✅ 已关闭"改为「**设计时暴露的 3 个问题及结论**」 |
| 四 / 五 / 六 | 改为**指向 `data-dictionary.md`**（不再重复，避免双轨） |
| 七 修正汇总 | **7 条 → 16 条**（与 `issue-review.md` 第十节对齐） |
| 八 主动简化 | 去掉已失效的"领料不建单据"一条；新增干重当量、盘点延后、审计落点延后 |
| 九 AI 使用记录 | 补充**被人工推翻的那条论证**（单列成表） |

**② `weeks/week01/business-requirements.md` §2.4**

- §2.4 **改写为终态结论**（定案建 `tbl_supplier`），甲 / 乙 / 丙三方案改为正常的"被否决 / 采用"取舍表
- **连带修正两处引用**：§4.1 #16 的"不记供应商"、§4.2 #6 的整条排除 → 收窄为"只不记联系人 / 账期 / 银行账户"
- **§4.1 进库清单新增第 19 项「供应商」**；全仓"进库 18 项"统一改为 **19 项**（week1 / issue-review / schema-design / report / contributions 共 5 处）

**③ `weeks/submissions/v0.1/report.md`**

1.3.5 补「**裁决结果：ISSUE-001~003 已全部闭环**」含三处分歧点的对方表态；2.2 补仿真造数成果；3.2 / 3.3 同步。

### 额外闭环的两条连带问题

| # | 问题 | 处理 |
|---|---|---|
| 1 | **§2.4 被推翻一事未登记进修正汇总** | 已补为第 16 条（15 → 16 行），**并把定性从"细化"改为如实的"推翻"** |
| 2 | **配方"双轨"**（`master-data.md` 与 `generate_seed.py` 各存一份） | 已由 seed **反填** `master-data.md` 至 **30 款 / 492 行**（逐行一致），并在该文件第六节声明**"主数据的唯一真相源"** |
| 3 | **供应商未计入数据边界** | 数据边界清单 **18 → 19 项**（新增「供应商」），全仓 5 处数字同步 |

> **第 2 条给工程侧留了一条反向待办**：`generate_seed.py` 应改为**读入 `master-data.md` 派生出的数据**，
> 而不是各维护一份 —— 在那之前，**改一次配方要改两处**（已在 `master-data.md` 中写明为已知技术债）。

### commit 引用

| commit | 说明 |
|---|---|
| `feat(data): …and close issue-004`（工程侧） | 触发本 Issue 的前置：表结构与 seed 全部就位 |
| 本次提交（文档侧） | `schema-design.md` 全量同步 + week1 §2.4 留痕 + report 对齐 + master-data 反填 |

### 遗留

无 —— 本 Issue 的三项诉求与两条连带问题**全部处理完毕**。
