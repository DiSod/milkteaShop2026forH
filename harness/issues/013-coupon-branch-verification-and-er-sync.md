# ISSUE-013: 券拆分分支的验证环境存疑 + 18 表未回写 ER 图与业务规则（合并前请先确认三件事）

| 元数据 | 内容 |
|---|---|
| **状态** | 🔴 待处理 (Open) |
| **类型** | 协同验证 / 文档一致性 |
| **提报人/Agent** | DiSod（胡博锐） |
| **指派处理** | 核心工程 (hezhlin5) |
| **提报日期** | 2026-10-21 |
| **关联文件** | [`feat/week06-coupon-template-migration`](../../project/sql/11-migration/migration.sql)、[`er-diagram.mmd`](../../project/docs/er-diagram.mmd)、[`business-rules.md`](../../project/docs/business-rules.md) |

---

## 0. 先说结论

分支 `feat/week06-coupon-template-migration` 的内容我逐项看过，**设计方向我完全同意**（券表拆分、六要素迁移、可失败的回归测试都是该做的）。

提报本条不是质疑实现，而是合并前有**两件必须先对齐的事**：

1. **验证环境对不上** —— 分支声称「12 项断言全绿」，但本机共享库 `milktea_shop` 现在还是 **17 表 / 没有 `tbl_coupon_template`**，建表时间落在我 10-19 跑 main 门禁那一刻。也就是说这套迁移**没有在这台机器的这个库上跑过**。
2. **18 表没有回写到设计文档** —— `er-diagram.mmd` 仍是 **17 实体**、`business-rules.md` 仍是 **30 个外码**。

**暂不合并。** 先把这两条对齐，再走门禁。

---

## 1. 分支内容清点（我自己核的，供你确认口径）

分支基于 `2ac9352`，3 个提交、14 文件、**+1249 / −257**：

| 提交 | 内容 |
|---|---|
| `5b322ad` | `migration.sql` 106 → **350 行**；`crud.sql` 6 行；`99-rebuild.sql` 1 行；`11-migration/README.md` |
| `99decbb` | `regression.sql` **337 行 / 12 用例**；`after-S01~03`；`01-migration-verification.sql` 160 行（补 `THROW`） |
| `137aebc` | `data-dictionary.md` 88 行（18 表）；`normalization.md` 106 行；`week06/README.md` |

**动到的 SQL（5 个，全部带 BOM ✅）**：

```
project/sql/05-dml/crud.sql
project/sql/11-migration/migration.sql
project/sql/99-rebuild.sql
project/tests/01-migration-verification.sql
project/tests/regression.sql
```

**新增/变更的数据库对象**：

| 对象 | 类型 |
|---|---|
| `tbl_coupon_template` | 新表（第 18 张） |
| `vw_coupon_legacy` | 新视图（第 6 个，向后兼容） |
| `fk_coupon_template` | 外码（第 31 个） |
| `ix_coupon_template_id` | 索引 |
| `ck_coupon_used_time_range` | 保留并用幂等逻辑重建 |

**值得肯定的两处**（我实测过，不是转述）：

- `regression.sql` 用的是 `THROW 51000` + `sqlcmd -b`，**真的会返回非零退出码**。之前 `01-migration-verification.sql` 只有 `PRINT`，全挂也是 `exit=0`，这个坑补上了。
- `after-S01/02/03` 与我提交的 `before-S01/02/03` **逐行完全相同**（80 / 62 / 151，合计 **293/293**）。这等于用实测证明了券表拆分对业务查询零影响 —— 这是分支里最有说服力的证据。

---

## 2. 问题一：验证环境与共享库不一致

### 2.1 事实

我在本机查 `milktea_shop`（就是第 3 周起一直在用的那个库）：

```
tbl_ 表数                      17
tbl_coupon_template 是否存在   NO
vw_ 视图数                     5
tbl_coupon 列数                11        ← 尚未拆分为模板 + 实例
tbl_ 表最早 create_date        2026-10-19 00:25:50
ck_coupon_used_time_range      2026-10-19 00:26:06
```

那个时间点是**我在 `main` 上跑 `99-rebuild.sql` 门禁**的时刻（当时回显 17 表 / 5 视图）。

### 2.2 为什么这条要紧

`regression.sql` 的 TC-01 断言「全库业务表数为 18 张」、TC-02 断言「模板表含 2 个去重模板」——
这些断言**只有在迁移执行过的库上才可能通过**。而本机库现在还是 17 表，说明：

> **这套迁移没有在 `milktea_shop` 上执行过。** 因此「12 项断言全绿」的结论目前**在本机无法复现**。

可能的解释有三种，请回一句确认为哪种：

- **(a)** 你用了另一个数据库名（如 `milktea_shop_test`）；
- **(b)** 你用了另一个实例；
- **(c)** 你验证后库被重建回了 17 表版本（比如又跑了一次 main 的 `99-rebuild`）。

### 2.3 请求的动作

请在**分支上**执行一次，并把回显贴回来：

```powershell
cd project\sql
sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 99-rebuild.sql     # 期望 18 表 / 6 视图

cd ..\..\
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -i project\tests\regression.sql   # 期望 12 项全绿、exit=0
```

> 注意 `regression.sql` 必须带 `-b`，否则 `THROW` 不会反映到退出码 —— 那这个脚本就又白写了。

---

## 3. 问题二：18 表没有回写到设计文档

### 3.1 事实

```
er-diagram.mmd   实体块 = 17            含 coupon_template = False
business-rules   外码 = 30 个
```

而分支已经把库变成 **18 表 / 31 外码 / 6 视图**，`data-dictionary.md` 也同步成了 18 表。

### 3.2 为什么这属于「我们这边」的问题

按 [`project/docs/README.md:33`](../../project/docs/README.md) 的既有裁定：
**设计文档是唯一真相源，建表脚本由它翻译生成，不要两处各自演化。**

也就是说方向是**设计 → 表**，不是表 → 设计。所以：

- 第 5 周 ER 图是**逆向取证**（从 DDL 反推现状），那时它从属于表 —— 这是当时的已知代价，写在 `er-design-notes.md` §1.1。
- 这次的券拆分是**正向路径**：`normalization.md` §5 先给出冗余分析和无损分解证明，`migration.sql` 再实施。

**所以 ER 图落后不是「表比图权威」，而是设计升级了、描述文档没跟上。** 这是一笔欠债，要补。

### 3.3 建议的补法（我的活，不占你的时间）

| 文档 | 改动量 |
|---|---|
| `er-diagram.mmd` | +1 实体 +1 联系，`R01`—`R30` 重排进第 31 条 |
| `er-diagram.md` | §2 图、§3 实体↔表 17↔17 → 18↔18、§5 基数表 |
| `er-diagram.svg` / `.png` | 重渲染（命令在 `er-design-notes.md` §4.4） |
| `business-rules.md` | 补第 31 个外码 `fk_coupon_template`，§1 实现层分布条数跟着调 |

---

## 4. 请你确认三件事

| # | 问题 | 我需要的答案 |
|---|---|---|
| **Q1** | 2.2 的 (a) (b) (c) 是哪种？能不能在分支上用 `-b` 跑一次 `regression.sql` 把回显贴回来 | 确认验证是真的 |
| **Q2** | **18 表的结构是否已冻结？**（`tbl_coupon_template` 的列、`tbl_coupon` 保留哪 8 列、外码与 4 个 CHECK 的归属） | 冻结了我就照它补 ER 图与业务规则；还会变我就先不动，免得画两遍 |
| **Q3** | **共享单库（`milktea_shop`）最终是 17 还是 18 表？** 第 7 周应用开发要连这个库，如果 app 按 18 表写而库是 17 表，本地直接报错 | 定一个口径，避免双方各按各的做 |

> 另外：`week06/README.md` §七 第 6 项（`submissions/v1.0/report.md` 报告素材）**先不动**，
> 按团队意见，等第 6 周这些收尾完了再起稿。

---

## 5. 解决记录（处理者填写）

- 处理人：`⏳`
- 解决时间：`⏳`
- 变更说明与 commit 引用：`⏳`
- 遗留：`⏳`
