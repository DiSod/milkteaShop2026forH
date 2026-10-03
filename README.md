# 奶茶店经营数据库

数据库实验课程贯穿项目 · 单店奶茶店经营场景 · 17 周

## 项目范围

以**一家奶茶店**为经营场景，在 17 周内把同一个数据库项目从记录业务逐步建设为支持经营分析与补货决策的应用。

| 项 | 设定 |
|---|---|
| 门店数量 | 1 家（单店，不做连锁） |
| 菜单规模 | 约 30 款成品 |
| 原料规模 | 约 60 种 |
| 营业模式 | 堂食 + 自提（**不接**外卖平台） |
| 当前进度 | **第 2 周已完成** · 阶段一（目标版本 v0.1，第 5 周周二截止） |

数据库需覆盖 6 类核心对象：**商品、库存、订单、订单明细、会员、员工**。

### 本场景的结构特征

```
商品（成品）──配方(BOM)──> 原料库存
卖一杯珍珠奶茶 = 珍珠 −20g + 红茶 −5g + 奶精 −15g + 糖浆 −10ml + 杯子 −1
```

| 库存层次 | 是否建物理表 |
|---|---|
| **原料库存**（真实存放的物料） | ✅ 建表 |
| **成品可制作量**（由配方推算） | ❌ 派生数据，**用视图算** |

## 目录导航

| 域 | 职责 | 入口 |
|---|---|---|
| `course/` | ① 资料域（只读）：课程原始材料 | [`course/README.md`](course/README.md) |
| `weeks/` | ② 过程域：17 周记录 + 阶段提交 | [`weeks/README.md`](weeks/README.md) |
| `project/` | ③ 成果域：最终可运行项目 | [`project/README.md`](project/README.md) |
| `harness/` | ④ 协作域：规范 + AI 留痕 + 小组 | [`harness/README.md`](harness/README.md) |

结构规范与命名约定见 [`STRUCTURE.md`](STRUCTURE.md)。

## 整体链路

```
业务需求分析（第1周）                    ✅ 已完成
    → 关系模式设计（第2周）               ✅ 已完成
         ⤷ 17 张表 / 133 字段 / 30 外码 / 样例元组
    → 建库与 CRUD（第3周）                ⬜ 未开始  ← 下一步
        → 连接查询 / 视图 / 约束 / 授权（第4周）   ← v0.1 交付（第5周周二截止）
```

## 关键文档入口

| 我想看… | 去哪里 |
|---|---|
| **表结构、字段、域、码、样例数据** | [`project/docs/data-dictionary.md`](project/docs/data-dictionary.md) ⭐ **表结构的唯一真相源** |
| 本周（第 2 周）做了什么 | [`weeks/week02/README.md`](weeks/week02/README.md) |
| 设计决策与被否决的方案 | [`weeks/week02/schema-design.md`](weeks/week02/schema-design.md) |
| 与同事的技术裁决记录 | [`weeks/week02/issue-review.md`](weeks/week02/issue-review.md) |
| 菜单、原料、配方 | [`weeks/week02/master-data.md`](weeks/week02/master-data.md) |
| 怎么协作、怎么提交 | [`harness/README.md`](harness/README.md) |

## 仓库

| 项 | 值 |
|---|---|
| 远端 | `git@github.com:DiSod/milkteaShop2026forH.git` |
| 主分支 | `main`（始终保持可运行、可交付） |
| 提交规范 | 见 [`harness/conventions/04-git-workflow.md`](harness/conventions/04-git-workflow.md) |

## 环境

| 项 | 说明 |
|---|---|
| 数据库 | SQL Server —— ⚠️ **版本待确认**（影响排序规则与部分语法，**第 3 周建库前必须定**） |
| SQL 脚本 | `project/sql/`（按 `00-` → `99-` 顺序执行） |
| 数据文件 | `project/data/`（**不进 git**，见其 README 下载说明） |
| 客户端 | `sqlcmd`（命令行执行）或 SSMS |

## 快速开始

> ⏳ **待第 3 周补全。** 目标形态：clone → 按 `project/data/README.md` 下载数据 → 执行一条命令重建整库。

```powershell
# 唯一入口（当前仍是桩文件，第 3 周启用）
sqlcmd -S <server> -i project/sql/99-rebuild.sql
```

**当前可复现的部分**：表结构定义在
[`project/docs/data-dictionary.md`](project/docs/data-dictionary.md)（17 张表 / 133 字段），
第 3 周由它翻译生成 `project/sql/01-schema/create-tables.sql`。

## 阶段提交计划

| 阶段 | 截止时间 | 版本 | 分值 |
|---|---|---|---|
| 一 | 第 5 周周二 23:59 | v0.1 | 10 |
| 二 | 第 10 周周二 23:59 | v1.0 | 20 |
| 三 | 第 14 周周二 23:59 | v2.0 | 20 |
| 四 | 第 18 周周二 23:59 | v3.0 | 20 |
