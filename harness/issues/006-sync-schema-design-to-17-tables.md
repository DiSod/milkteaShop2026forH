# ISSUE-006: 关系模式设计正文全面同步修订至 17 表及历史文档连带对齐

| 元数据 | 内容 |
|---|---|
| **状态** | 🔴 待处理 (Open) |
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

## 5. 解决记录（处理者填写）

**处理人**：DiSod（文档主编）
**解决时间**：⏳
**状态**：🔴 待处理
