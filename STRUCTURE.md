# databaseExp · 目录结构方案

> 本文档定义 17 周项目仓库的目录结构与组织规范。
> 状态：**已执行**（第 1 周建立骨架，第 2 周复核并补充 week02）
> 命名约定：**目录名与文件名全部使用英文**，文档内容使用中文。

---

## 1. 设计目标与原则

### 1.1 要解决的三个问题

| # | 需求 | 对应设计 |
|---|---|---|
| 1 | 17 周，每周有每周的事，要能记录 | `weeks/` 过程域，一周一文件夹 + 索引表 |
| 2 | 最终是一个完整项目，要能交付 | `project/` 成果域，可一键重建 |
| 3 | 是 harness 项目，要有规范文档 | `harness/` 协作域，规范 + AI 留痕 + 小组 |

### 1.2 四条设计原则

1. **过程与成果分离** —— 周报、草稿、探索过程放 `weeks/`；最终可运行的代码放 `project/`。两者不混。
2. **成果域必须可重建** —— `project/` 里的东西要能从空库一键跑出来，这是课程"可复现"要求的技术保障。
3. **协作域只放规则和留痕** —— `harness/` 不放任何业务内容（不放 SQL、不放数据）。
4. **原始资料只读** —— `course/` 里课程发的材料原件不改动、不移动。

---

## 2. 四个顶层域

```
databaseExp/
├─ README.md
├─ STRUCTURE.md          # 本文档
├─ .gitignore
│
├─ course/               # ① 资料域（只读）
├─ weeks/                # ② 过程域（17周 + 阶段提交）
├─ project/              # ③ 成果域（最终项目）
└─ harness/              # ④ 协作域（规范 + AI + 小组）
```

| 域 | 一句话职责 |
|---|---|
| `course/` | 课程原始资料（**只读**） |
| `weeks/` | 过程记录与阶段提交 |
| `project/` | 最终可运行项目 |
| `harness/` | 协作规范与留痕 |

> 📄 **「放什么 / 不放什么」的边界表见** [`01-layout-and-naming.md`](harness/conventions/01-layout-and-naming.md) §4
> 与 §6 违规判定 —— 那里维护，本节不重复。下一节的完整目录树是本节的展开。

---

## 3. 完整目录树

```
databaseExp/
│
├─ README.md                          # 总入口：项目范围、当前进度、导航
├─ STRUCTURE.md                       # 本方案
├─ .gitignore                         # 大文件与构建产物排除规则
│
├─ course/                            # ① 资料域（只读）
│  ├─ README.md                       #   资料清单与来源说明
│  ├─ lecture-week01.docx             #   第一周任务讲解（原件）
│  └─ lecture-week01.md               #   上述原件的 Markdown 转写稿
│
├─ weeks/                             # ② 过程域
│  ├─ README.md                       #   周次索引表（17 周，先行列出）
│  ├─ week01/                         #   目录按需创建，当前 week01/ — week03/
│  │  ├─ README.md                    #     本周小结 + 文件中文标题对照
│  │  ├─ business-requirements.md     #     第一周报告·业务需求分析
│  │  └─ data-availability.md         #     数据可得性对比表
│  ├─ week02/
│  │  ├─ README.md                    #     本周小结 + 进度与复盘
│  │  └─ schema-design.md             #     第二周报告·关系模式设计（表清单 + 设计决策）
│  ├─ week03/
│  │  └─ README.md                    #     第 3 周周报（SQL 直接写进 project/，无草稿副本）
│  └─ submissions/                    #     阶段提交快照
│     ├─ README.md
│     ├─ v0.1/  v1.0/  v2.0/  v3.0/   #     （占位，各含 .gitkeep）
│
├─ project/                           # ③ 成果域
│  ├─ README.md                       #   项目说明 + 一键重建步骤
│  ├─ sql/
│  │  ├─ README.md                    #   SQL 执行顺序说明 + 怎么跑
│  │  ├─ 00-bootstrap/                #   建库（排序规则/兼容级别/恢复模式）
│  │  ├─ 01-schema/                   #   DDL 建表
│  │  ├─ 02-constraints/              #   主外键 / CHECK
│  │  ├─ 03-indexes/                  #   索引
│  │  ├─ 04-seed/                     #   种子数据装载
│  │  ├─ 05-dml/                      #   CRUD 示例
│  │  ├─ 06-query/                    #   多表连接查询
│  │  ├─ 07-view/                     #   统计视图
│  │  ├─ 08-security/                 #   角色与权限
│  │  ├─ 09-programmability/          #   存储过程/函数/触发器
│  │  ├─ 10-transaction/              #   事务与并发控制
│  │  └─ 99-rebuild.sql               #   一键重建入口
│  ├─ data/
│  │  ├─ README.md                    #   数据来源、下载说明、校验值
│  │  ├─ raw/                         #   原始下载（⚠️ 不进 git）
│  │  ├─ interim/                     #   清洗中间产物（⚠️ 不进 git）
│  │  └─ generated/                   #   自建生成数据（⚠️ 不进 git）
│  ├─ app/                            #   应用界面（第2阶段起）
│  ├─ docs/                           #   ER图、数据字典、设计说明
│  └─ tests/                          #   测试用例与运行记录
│
└─ harness/                           # ④ 协作域
   ├─ README.md                       #   harness 是什么、怎么用
   ├─ conventions/                    #   规范文档（见第 6 节）
   │  ├─ 01-layout-and-naming.md
   │  ├─ 02-sql-style.md
   │  ├─ 03-documentation.md
   │  ├─ 04-git-workflow.md
   │  └─ 05-ai-collaboration.md
   ├─ issues/                         #   任务看板（第 2 周新增）
   │  ├─ README.md                    #     看板索引、两条铁律与状态图例
   │  ├─ ISSUE-TEMPLATE.md            #     Issue 模板（五段式）
   │  └─ 001-*.md … 005-*.md          #     一 Issue 一文件，避免并发改大文件
   ├─ team/                           #   小组（原 team/ 并入）
   │  ├─ README.md                    #     成员名单
   │  └─ contributions.md             #     17 周分工与贡献记录
   ├─ prompts/                        #   可复用提示词
   │  └─ agent-session-start.md       #     开工对齐 SOP（第 2 周新增）
   ├─ skills/                         #   可复用技能 / 工作流
   ├─ agents/                         #   子代理任务定义
   └─ logs/                           #   会话与操作留痕
```

---

## 4. 各域边界规矩

这是防止后期混乱的核心，**任何成员新增文件前先查这张表**。

| 域 | 规矩 |
|---|---|
| `course/` | **只读**。不改名、不改内容。若需摘录，摘录稿放 `weeks/` 或 `harness/` |
| `weeks/` | 只放**这一周新产生的、尚未成为项目资产**的内容。一旦某个 SQL 升级为项目正式脚本，**移入 `project/`**，周文件夹里只留**一句说明 + 相对路径链接** |
| `project/` | 只放**最终版**。所有脚本必须能被 `99-rebuild.sql` 按序调用。禁止放探索性草稿 |
| `harness/` | **只放规则与留痕**。出现 SQL、数据、业务文档即为放错位置 |

### 4.1 草稿 → 正式 的升级路径

> 📄 **完整规则见** [`01-layout-and-naming.md`](harness/conventions/01-layout-and-naming.md) §5。

```
weeks/weekNN/ 草稿脚本
      │  验证通过、纳入正式流程
      ▼
project/<对应目录>/ 正式文件
      │
      ▼
weeks/weekNN/README.md 中留一行记录
```

> 这样既保留了"每周做了什么"的过程痕迹（课程要的过程证据），又不会出现两份内容各自演化的分裂。

---

## 5. 命名规范

> 📄 **完整规范见** [`01-layout-and-naming.md`](harness/conventions/01-layout-and-naming.md) §1—3 ——
> 命名总则、目录与文件命名表、两位数字前缀的理由、可读性补偿、**编号前缀（三套，别混）** 都在那里。
>
> **一句话**：目录与文件名**全英文、全小写、`-` 连接**；有序目录用**两位数字前缀**。
> `01-layout-and-naming.md` 是本节的**可执行规范版**，**以它为维护处**。

---

## 6. `harness/conventions/` 五份规范

> 📄 **清单与要点见** [`harness/README.md`](harness/README.md) —— 那里维护，本节不重复。
>
> **`05-ai-collaboration.md` 是重点**：课程明确要求"**保留提示词、候选答案、人工修改与验证证据**"，
> 这份规范把已在进行的做法固定成可执行的格式。
>
> **AI 留痕的存放位置**同样见 `harness/README.md`（正式提交 / 周度记录 / 可复用提示词 / 原始日志 四类）。

---

## 7. 大文件策略（⚠️ 开工前必须处理）

### 7.1 问题

`project/data/raw/` 将来会放 **95MB + 37MB** 的 CSV。**GitHub 单文件上限 100MB**，且大文件一旦进入 git 历史，即使后续删除，仓库体积也不会回落。

### 7.2 方案

**数据不进仓库，只进"获取说明"。**

`.gitignore` 内容：

```gitignore
# ---- 数据（不进仓库，见 project/data/README.md 下载说明）----
project/data/raw/*
project/data/interim/*
project/data/generated/*
!project/data/**/README.md
!project/data/**/.gitkeep

# ---- SQL Server 产物 ----
*.mdf
*.ldf
*.bak
*.trn

# ---- 原始会话日志 ----
harness/logs/raw/

# ---- 系统与编辑器 ----
Thumbs.db
.DS_Store
.vscode/
.idea/
*.swp

# ---- 临时文件 ----
*.tmp
*.bak
~$*
```

配套 `project/data/README.md` 记录：**来源 URL、许可、文件大小、SHA-256 校验值、下载后的放置路径、清洗命令**。

> 这样仓库保持轻量，别人 clone 后按说明下载即可完整复现 —— **既满足"可复现"，又不撑爆仓库**。

---

## 8. 现有文件的迁移映射

| 现位置 | 新位置 | 说明 | 状态 |
|---|---|---|---|
| `README.md` | `README.md` | 保留，内容已重写（加入目录导航与结构特征） | ✅ |
| `第一周任务讲解.docx` | `course/lecture-week01.docx` | 重命名 + 移动（原件内容不动） | ✅ |
| — | `course/lecture-week01.md` | **新增**：原件的 Markdown 转写稿 | ✅ |
| `docs/week1/第一周报告-业务需求分析.md` | `weeks/week01/business-requirements.md` | 重命名 + 移动 | ✅ |
| `docs/week1/数据可得性对比表.md` | `weeks/week01/data-availability.md` | 重命名 + 移动 | ✅ |
| `docs/` （空壳） | — | 撤销：职责由 `weeks/`、`project/docs/`、`harness/` 分担 | ✅ |
| `.gitkeep` （根） | — | 撤销：改用各目录 `README.md` + 空目录 `.gitkeep` | ✅ |

> **原件处理说明**：`course/` 约定为只读域。为统一英文命名，第一周讲解文档被重命名了一次，**文件内容未改动**。
> 同时新增 Markdown 转写稿便于检索与引用；**两者不一致时以原件为准**。

---

## 9. 占位策略

Git 不追踪空目录，因此每个占位目录放**一份简短的 `README.md`**（1—3 行：用途 / 放什么 / 不放什么），优于散落的 `.gitkeep`。

示例（`project/app/README.md`）：

```markdown
# app · 应用界面

第 2 阶段起存放数据库应用的界面代码（商品/库存/订单操作、参数化查询、角色界面）。

不在本目录：SQL 脚本（见 ../sql/）、设计文档（见 ../docs/）。
```

---

## 10. 执行清单（已完成）

- [x] 创建 4 个顶层域及全部子目录
- [x] 根 `.gitignore`
- [x] 根 `README.md` 更新（加入目录导航）
- [x] 各目录 `README.md` 占位；空目录用 `.gitkeep` 占位（18 个）
- [x] `harness/conventions/` 五份规范文档
- [x] 迁移现有文件（按第 8 节）
- [x] `course/lecture-week01.md` 转写稿
- [x] `weeks/README.md` 周次索引表（17 周）
- [x] `harness/team/README.md` 与 `contributions.md` 模板
- [x] `project/data/README.md` 下载说明模板
- [x] `project/sql/99-rebuild.sql` 重建入口桩文件
- [x] 删除 `docs/` 空壳与根 `.gitkeep`

### 已决的开放项

| # | 事项 | 结论 |
|---|---|---|
| 1 | 课程讲解文档是否重命名 | ✅ 已重命名为 `course/lecture-week01.docx`，**内容未改动** |
| 2 | 课程讲解文档格式 | ✅ **同时提供 `.md` 转写稿**（`lecture-week01.md`） |
| 3 | 周次文件夹是否一次建全 | ✅ **只建 `week01/`**，后续按需创建； `weeks/README.md` 索引表先行列出 17 周 |
| 4 | `harness/logs/raw/` 是否进 git | ✅ 排除 |
| 5 | 是否现在 `git init` | ✅ **已完成（第 2 周补做）** —— 远端 `git@github.com:DiSod/milkteaShop2026forH.git`，主分支 `main` |

### 待办

| # | 事项 | 状态 |
|---|---|---|
| 1 | `harness/team/` 成员名单与分工记录 | ⏸ **暂不落实，保持空模板** |
| 2 | `git init` 与远端仓库创建 | ✅ **已完成** |

> `harness/team/` 下两份文件、以及 `weeks/week01/business-requirements.md` 附录 B 均已保留**空表格模板**，待成员确定后再填。

---

## 10.1 第 2 周的目录变更

工程侧（hezhlin5）在第 2 周建立了一套「Agent 原生协作机制」，新增两个目录/文件。本节补登进结构文档：

| 新增 | 类型 | 用途 |
|---|---|---|
| `harness/issues/` | **新目录** | Agent 原生文件式 Issue 看板。一 Issue 一文件、统一在 `main` 维护，避免两人并发编辑大文件产生 Git 冲突 |
| `harness/prompts/agent-session-start.md` | 新文件 | 开工对齐 SOP：每次开工先读周目录 + 看板 + 最近 3 次提交，回显确认后再动手 |

**边界判定**：两者都属于"**规则与留痕**"，符合 `harness/` 的域边界（不放 SQL、数据、业务内容），**无需调整第 4 节的边界规矩**。

**与既有规范的衔接**：`harness/issues/` 的规则与 `04-git-workflow.md` 是配套的 —— 看板走 `main`，业务代码走 `feat/` `fix/` 分支。详见 `harness/issues/README.md` 与 `04-git-workflow.md`。

### 本节的遗留问题（已在 `weeks/week02/issue-review.md` 登记）

| # | 问题 | 现状 |
|---|---|---|
| 1 | ~~`99-rebuild.sql` 仍是桩文件~~ → "合并前必须跑通 99-rebuild"这条底线无法执行 | ✅ **已解决** —— `99-rebuild.sql` 已可执行，第 3 周实测从空库重建 **17 秒 / 20,979 行** |
| 2 | ~~"文档"的边界未写清~~ —— 脚本头注释算文档还是代码？ | ✅ **已解决** —— [`04-git-workflow.md`](harness/conventions/04-git-workflow.md) §2.1 按**路径**判定：`project/sql/**` 算代码走分支；`project/docs/**`、`harness/**`、`weeks/**` 算文档直接进 `main` |
| 3 | **看板"直接推 main" 与 "随分支合入 main" 的优先关系未定** —— 两边同时改同一个 Issue 文件会冲突 | ❌ **未解决**（待定） |
| 4 | **看板未表达 Issue 之间的依赖**（如 ISSUE-001 直接决定 ISSUE-002 的表数） | 🟡 **部分解决** —— [`issues/README.md`](harness/issues/README.md) 已写明"依赖要显式写"，但 Issue 元数据里还没有 `依赖` 字段 |

---

## 附：设计决策记录

| 决策 | 选择 | 理由 |
|---|---|---|
| 命名风格 | 全英文 | 排序友好、脚本可处理 |
| 顶层域数量 | 4 个 | 精简：`team/`并入协作域，`submissions/`并入过程域 |
| 过程与成果 | 分离为 `weeks/` 与 `project/` | 避免第 10 周后代码与周报混杂、出现两份 SQL 各自演化 |
| 占位方式 | 各目录 `README.md` | Git 不追踪空目录，README 兼作说明 |
| 大文件 | 不进 git，只进下载说明 | GitHub 单文件 100MB 上限，且历史无法回落 |
