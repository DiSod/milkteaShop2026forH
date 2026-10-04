# ISSUE-007: 造数引擎输出规范化（UTF-8 BOM）与配方数据源单一化

| 元数据 | 内容 |
|---|---|
| **状态** | 🔴 待处理 (Open) |
| **类型** | 数据工程 / 编码规范 · 数据源治理 |
| **提报人/Agent** | DiSod（文档主编） |
| **指派处理** | 核心工程（hezhlin5）—— 两处均改 `project/data/generate_seed.py` |
| **提报日期** | 2026-10-04 |
| **关联文件** | [`project/data/generate_seed.py`](../../project/data/generate_seed.py), [`project/sql/04-seed/seed_data.sql`](../../project/sql/04-seed/seed_data.sql), [`weeks/week02/master-data.md`](../../weeks/week02/master-data.md), [`harness/conventions/02-sql-style.md`](../conventions/02-sql-style.md) (§9) |

---

## 1. 现象与矛盾描述

第 3 周接通 `99-rebuild.sql` 时，在**本机实测**到两个问题：

**① 种子数据会静默装不进数据库。**
`project/sql/04-seed/seed_data.sql` 原先保存为 **UTF-8 无 BOM**。
`sqlcmd -i` 在无 BOM 时按系统 OEM 代码页（中文 Windows 上是 **GBK**）读取，
UTF-8 的中文被错误解码后 —— **不报错，而是整个批次静默失效**。

**② 配方数据仍有两份来源。**
`generate_seed.py` 内嵌一份配方（30 款），而 [`master-data.md`](../../weeks/week02/master-data.md)
已声明自己是「**主数据的唯一真相源**」（30 款 / 492 行）。两者目前内容一致，但**改一次配方要改两处**。

---

## 2. 事实证据（对照）

### 证据 ① —— 同一条语句，有无 BOM 的结果完全不同

```sql
INSERT INTO dbo.enc_probe (id, name) VALUES (1, N'红茶（阿萨姆）'), (2, N'珍珠奶茶'), (3, N'招牌柠檬水');
```

| 文件编码 | 实测结果 |
|---|---|
| **UTF-8 无 BOM** | `(0 行受影响)` —— **且没有任何错误消息** |
| **UTF-8 带 BOM** | `(3 行受影响)` ✅ 中文正确 |

> 同期测试：中文列别名也会乱码（同一个根因）。

### 证据 ② —— 现状

| 文件 | 当前 BOM | 由谁生成 |
|---|---|---|
| `project/sql/04-seed/seed_data.sql` | ✅ **已由文档侧手工补上** | `generate_seed.py` |
| `project/data/generate_seed.py` 的输出逻辑 | ❌ 仍是普通 `utf-8` | 工程侧 |

**风险**：文档侧只补了**已提交的那一份文件**。**只要脚本重新生成一次，BOM 就会再次丢失**，
而症状是"装载成功但一行都没有"——极难察觉。

---

## 3. 影响评估与潜在风险

| # | 风险 | 级别 |
|---|---|---|
| 1 | 重新生成 seed → BOM 丢失 → **种子数据一行都装不进去且不报错** | 🔴 **高**（会直接毁掉第 3 周的可复现演示） |
| 2 | 换到队友/老师机器执行时，同样的静默失效 | 🔴 高 |
| 3 | 配方两处维护 → 改一处漏一处 → **台账与主数据不一致** | 🟡 中（目前内容一致，是**潜在**问题） |

---

## 4. 建议解法与行动方案

均只需改 `project/data/generate_seed.py` 一个文件。

### 方案一（**必须做**）：输出 UTF-8 带 BOM

```python
# 导出 SQL 时（以及任何写出含中文文本文件的场合）
with open(sql_path, 'w', encoding='utf-8-sig', newline='\r\n') as f:
    f.write(sql_text)
```

> `utf-8-sig` 即 **UTF-8 with BOM**。Python 写入时会自动加上 `EF BB BF` 三字节。

**验收**：重新生成 `seed_data.sql` 后，
`[System.IO.File]::ReadAllBytes(...)[0..2]` 应为 `EF BB BF`；
且用 `sqlcmd -i` 装载后中文正确、行数不为 0。

### 方案二（**建议做**）：配方数据改为读 `master-data.md` 派生

`master-data.md` 已声明为主数据的唯一真相源。建议：

1. 从 `master-data.md` **导出一份机器可读文件**（如 `project/data/generated/master-data.csv`），
   或直接在脚本里解析该 Markdown 的配方表（格式已固定为 `| 杯型 | 糖度 | 原料 | 用量 |`）；
2. `generate_seed.py` **读入**该数据，不再内嵌一份。

**验收**：改一次 `master-data.md` 的配方 → 重新生成 seed → 数据随之变化，**无需改脚本**。

> **过渡期约定**：在方案二落地前，**改配方必须同步改两处**（该技术债已写在 `master-data.md` 第六节）。

### 方案三（可选，防御性）：装载命令加编码参数

在 `99-rebuild.sql` 的使用说明中，把 `sqlcmd -f 65001` 列为**备选**（不改文件的救急手段）。
（已写进 `02-sql-style.md` §9，此处不重复。）

---

## 5. 解决记录（处理者填写）

**处理人**：⏳ 核心工程（hezhlin5）
**解决时间**：⏳
**状态**：🔴 待处理

| 项 | 方案一（BOM） | 方案二（数据源单一化） |
|---|---|---|
| 优先级 | 🔴 **必须做** | 🟡 建议做 |
| 状态 | ⏳ | ⏳ |
| commit | ⏳ | ⏳ |

### 遗留

- 方案二未落地前，**改配方要改两处**（已知技术债）
- 尚未在**第二台机器**上验证一键重建的可移植性
