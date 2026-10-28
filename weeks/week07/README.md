# 第七周 · 数据库应用开发（第 7—9 周合并任务）

| 元信息 | 内容 |
|---|---|
| **阶段** | 第二阶段（第 5—9 周）· 版本目标 **v1.0** |
| **本周边界** | 第 7、8、9 三周是**一个任务**：在 v1.0 数据库上做可运行、可复现的 Web 应用 |
| **课程材料** | `第7-9周任务讲解.docx`（尚未入库 `course/`，见 §10） |
| **截止时间** | 第 10 周周二 23:59（阶段作业含第 5—9 周全部成果） |
| **本文件状态** | 🟡 **技术选型参考稿**——候选清单已核实，**选型本身待与核心工程确认**（见 §9） |
| **本文件作用** | 把「每层有哪些可选技术」摊开，供选型讨论与答辩准备；**不含代码** |

> ⚠️ 本文件是**讨论底稿**，不是定案。§9 的勾选表填完后才生效。
> 代码一旦开工，选型变化要回改本文件——避免代码和文档各说一套。

---

## 一、先说清「三层」是哪三层

课程原文（`第7-9周任务讲解.docx` 段落 7）写的是：

> 分层结构：程序按照"页面层→业务层→数据访问层→**数据库层**"组织。……初学者可以把它理解为：页面提出请求，业务层作出判断，数据访问层执行SQL，SQL Server保存最终数据。

其中**数据库层的原文只有一句**（段落 11）：「数据库层：使用SQL Server连接。」

**它不是我们要写的代码**，而是 SQL Server 本身。所以：

| # | 层 | 我们要写的代码 | 课程原文 |
|---|---|---|---|
| 1 | **页面层** | ✅ | 段落 8：负责查询/新增/修改/必要删除的**展示与操作入口**，做必填项、格式、数值范围的**基础校验** |
| 2 | **业务层** | ✅ | 段落 9：把一次完整业务操作组织起来，负责**业务规则、事务边界、角色可执行范围** |
| 3 | **数据访问层** | ✅ | 段落 10：系统中**唯一与 SQL Server 直接交互**的层级，负责连接、SQL 参数、事务提交回滚、连接释放 |
| — | 数据库层 | ❌（它是 SQL Server） | 段落 11：保存表、约束、视图和数据 |

**答辩时若被问「第四层你们做了什么」**：数据库层是我们**设计的对象**而非写的代码——18 张表 / 137 个字段 / 31 个外键 / 46 个 CHECK / 6 个视图 / 4 个安全角色，全部由 `project/sql/99-rebuild.sql` 从空库一键重建；数据访问层就是它的调用方。

---

## 二、三层的职责与「不该做的事」

| 层 | 一句话职责 | 不该做的事 | 判据 |
|---|---|---|---|
| 页面层 | 收请求、校验格式、渲染结果 | **不碰 SQL**，不做业务判断 | 文件里出现 `import pyodbc` 就是越界 |
| 业务层 | 组织一次完整业务动作，决定事务起止与谁能做 | **不写 SQL** | 文件里出现 `SELECT`/`INSERT` 字符串就是越界 |
| 数据访问层 | 唯一连库、唯一执行 SQL | 不判断业务规则 | 出现 `if 库存 < 需求` 这类业务判断就是越界 |

⚠️ **页面层的校验与业务层的校验不重复、也不互相替代**：

- 页面层查**格式**：手机号是不是 11 位、数量是不是正整数
- 业务层查**规则**：库存够不够、券是否已用过、这个岗位能不能退单

课程段落 12 的要求正是这个分工：「页面可以根据角色隐藏按钮，但**真正的权限检查必须在后端业务层再次执行**」。

---

## 三、功能 → 层的落点矩阵

课程任务④点名了登录、商品查询维护、库存查询调整、订单创建查询。展开成 14 项：

| # | 功能 | 页面层 | 业务层 | 数据访问层 |
|---|---|:---:|:---:|:---:|
| ① | 顾客登录 | 表单 | 验哈希、建会话 | 查 `tbl_member` |
| ② | 看菜单 | 渲染卡片 | 组装规格选项 | 读 `tbl_product` + `vw_product_stock_availability` |
| ③ | **下单** | 选规格加料 | **事务、库存校验、算价、扣库存、计积分** | 写 5 张表 + 2 张流水 |
| ④ | 我的订单 | 列表页 | 拼 `member_id = 当前用户` | 读 `vw_order_detail_full` |
| ⑤ | 积分与券 | 展示 | 统计可用券 | 读 `tbl_points_ledger` / `tbl_coupon` |
| ⑥ | 开会员 | 表单 | 查重手机号 | 写 `tbl_member` |
| ⑦ | 点单收银 | 同 ③ | 同 ③ + 代客身份 | 同 ③ |
| ⑧ | 券核销 | 扫券码 | 校验有效期与状态 | 更新 `used_time` / `status` |
| ⑨ | 改订单状态 | 按钮 | 状态机是否允许（`PENDING→MAKING→READY`） | 更新 `tbl_order_header` |
| ⑩ | 看配方 / 可做杯数 | 列表 | —（纯查询，可跳过业务层） | 读 `tbl_recipe` / 视图 |
| ⑪ | 收货入库 | 表单 | 算加权成本 | 写采购单 + 3 行流水 |
| ⑫ | 库存调整 | 表单 | 判别盘盈 / 报损 | 写 `tbl_stock_ledger` |
| ⑬ | 补货预警 | 列表 | —（纯查询） | 读 `vw_ingredient_reorder_alert` |
| ⑭ | 日报审计 | 页面 | 按日期聚合 | 读 `vw_daily_business_summary` |

**规律**：⑩⑬ 这类**纯查询可以不经过业务层**，③⑧⑨⑪⑫ 这类**写操作必须经过业务层**——因为只有业务层持有事务。这是设计决策，不是偷懒，答辩时值得主动说明。

---

## 四、页面层：4 个子问题

### 4.1 渲染模式（影响工作量最大的一项）

| 模式 | 候选技术 | 特点 | 适配 |
|---|---|---|---|
| **服务端渲染 SSR** | Jinja2（Flask）、Django Template、Mako、Thymeleaf（Spring）、Blade（Laravel）、Razor Pages（.NET）、EJS/Pug（Express） | 后端出数据、模板出 HTML，**一套代码** | ✅ 课程场景 |
| 前后端分离 SPA | React、Vue、Angular、Svelte、Solid | 前端独立构建，后端只出 JSON | 两套代码两套构建，过重 |
| 混合（SSR + 局部刷新） | htmx、Alpine.js、Stimulus、Livewire | 仍服务端渲染，局部交互不整页刷新 | 想要 SPA 手感又不想上构建链 |
| 数据应用框架 | Streamlit、Gradio、NiceGUI | 几行出界面 | ❌ 分层讲不清 |

**候选：Jinja2 SSR。**

### 4.2 样式与组件库

| 候选 | 定位 | 代价 |
|---|---|---|
| **Bootstrap 5** | 最通用，表格/表单/模态/导航齐全 | 样式较"制服感" |
| Tailwind CSS | 原子类，定制性强 | 需要构建步骤 |
| Bulma / Foundation / Pico.css | 轻量替代 | 组件少 |
| Ant Design / Element Plus / MUI | 企业级组件库 | 绑定 React/Vue，SSR 不适用 |
| 手写 CSS | 完全可控 | 时间成本高 |

**候选：Bootstrap 5，文件放 `project/app/static/vendor/`，不引 CDN。** 验收机可能断网，这是硬要求。

### 4.3 表单校验（本层只做"格式"）

| 候选 | 层次 | 说明 |
|---|---|---|
| **HTML5 原生**（`required` / `type="tel"` / `pattern` / `min` / `max`） | 浏览器 | 零依赖 |
| **WTForms / Flask-WTF** | 后端 | 声明式字段 + 校验器，可顺带做 CSRF |
| Pydantic | 后端 | 类型驱动，FastAPI 常用；Flask 里也能当校验器 |
| validator.js / Yup / Zod | 前端 JS | SSR 下多余 |
| 手写 `if` | — | 依赖最少，容易漏 |

**候选：HTML5 原生 + WTForms（后端再校验一次）。**

### 4.4 静态资源与前端构建

| 方案 | 说明 |
|---|---|
| **无构建**（本地 `<link>` / `<script>`） | 最简单，改动即时生效 |
| Flask-Assets / Flask-Static-Digest | 加缓存指纹 |
| Vite / webpack | 需要 Node 工具链，SSR 下得不偿失 |

**候选：无构建**；担心缓存就给 `<link>` 手工加 `?v=1`。

---

## 五、业务层：5 个子问题（候选最多的一层）

### 5.1 Web 框架

| 候选 | 语言 | 定位 | 适配 |
|---|---|---|---|
| **Flask** | Python | 微框架，路由 + 模板 + 自选扩展 | ✅ 结构自定，分层看得清 |
| FastAPI | Python | 异步 + Pydantic + 自动 OpenAPI | 适合纯 API，配模板需插件 |
| Django | Python | 全家桶（ORM/Admin/迁移/认证） | ⚠️ ORM 与 Admin 会替我们做掉要演示的东西 |
| Bottle / Pyramid | Python | 轻量 / 可扩展 | 生态小 |
| Spring Boot | Java | Controller/Service/Repository 原生 | 最"教科书"，但要 JDK + Maven |
| Express / Koa / Fastify | Node | 中间件链 | 需 Node 工具链 |
| NestJS | Node | 装饰器式分层，最接近 Spring | 学习曲线陡 |
| Laravel | PHP | 全家桶 | 需 PHP 环境 |
| ASP.NET Core | C# | 分层 + EF Core | 需 .NET 环境 |
| Gin / Echo | Go | 高性能 | 偏基础设施 |

**候选：Flask**（Python 3.12 已就绪 + 微框架不预设分层 + 课程提示点名）。

### 5.2 业务代码的组织方式

| 方式 | 长什么样 | 优点 | 缺点 |
|---|---|---|---|
| **事务脚本** | 一个函数从校验写到提交 | 直白，与"业务层负责一次完整业务操作"完全对应 | 逻辑膨胀后函数变长 |
| 用例层 Use Case | 每动作一个类，`execute()` | 边界清晰、易测 | 类数量翻倍 |
| 领域模型 + 仓储（DDD） | 富对象 + Repository | 长期可维护 | 对作业严重过度设计 |
| 胖模型（Django 式） | 逻辑写在 model 方法里 | 少写文件 | 业务层被稀释进 ORM，分层讲不清 |

**候选：事务脚本 + 按领域拆模块**（`order.py` / `stock.py` / `member.py`）。

### 5.3 事务边界怎么实现

| 方案 | 写法 | 谁管提交 |
|---|---|---|
| **显式事务** | `conn.autocommit = False` → `commit()` / `rollback()` | 业务层显式调用 |
| **上下文管理器** | `with conn:` | Python 自动提交 / 回滚 |
| ORM 会话 | `with Session.begin():`、`transaction.atomic()` | 框架管 |
| 声明式注解 | `@Transactional`（Spring） | 框架管 |
| 存储过程内事务 | `BEGIN TRAN ... COMMIT` 写在 SQL 里 | 数据库管 |

**候选：`with conn:` 包住整段业务。**

### 5.4 权限判断

| 方案 | 说明 | 强度 |
|---|---|---|
| **手写装饰器 + 会话角色** | `@require_role('CASHIER')` | 够用，代码全透明 |
| Flask-Login + 自写 RBAC | 登录态由库管，角色自己判 | 少样板 |
| Flask-Principal / Flask-Security | 提供 permission 抽象 | 抽象层多，答辩要多解释 |
| Casbin | 策略文件 + 引擎，支持 RBAC/ABAC | 强，但与数据库 GRANT 成了两套 |
| Django permissions / Spring Security | 内置 | 只在各自框架内 |
| OPA / Cedar（外置策略引擎） | 策略独立服务 | 生产级，课程场景过重 |
| **数据库层 `EXECUTE AS USER`** | 请求内切换数据库身份 | ⭐ 唯一能证明"权限真在库里"的方案 |

**候选：两层一起做**——业务层 `@require_role` 管"给不给进"，数据访问层 `EXECUTE AS USER` 管"进了也改不了"。

### 5.5 统一异常与日志

| 方案 | 对课程要求 |
|---|---|
| **`@app.errorhandler` + 自定义异常类** | 段落 13「统一异常处理机制」 |
| 蓝图级 `errorhandler` | 按模块分区 |
| `before/after_request` 中间件 | 统一响应格式 |
| Spring `@ControllerAdvice`、FastAPI `exception_handler` | 等价物 |

日志候选：`logging`（标准库）+ `request_id` 中间件；`structlog`；`loguru`。

**候选：自定义异常基类 + 全局 `errorhandler` + `logging` 带 `request_id`。** 课程要求日志含**请求标识、时间、操作名称、用户角色、错误码、处理结果**六项。

---

## 六、数据访问层：5 个子问题

### 6.1 访问方式（核心选择）

| 方式 | 候选 | 写法 | 适配 |
|---|---|---|---|
| **原生驱动** | **pyodbc**、pymssql、python-tds、JDBC、node-mssql、Go `database/sql` | `cur.execute("... WHERE id = ?", (id,))` | ✅ SQL 全透明 |
| 查询构建器 | SQLAlchemy Core、Knex、jOOQ、Squirrel | `select(t.c.x).where(t.c.id == id)` | 半透明，能讲参数绑定 |
| ORM | SQLAlchemy ORM、Django ORM、Hibernate/JPA、Prisma、TypeORM、Sequelize、EF Core | `session.query(User).get(id)` | ❌ SQL 被藏起来，"无字符串拼接"不好演示 |
| 存储过程 | `EXEC proc @a=?, @b=?` | 逻辑放库里 | 阶段三（11—12 周）才有意义 |

**候选：pyodbc。**

### 6.2 参数化占位符（写错会直接报错）

| 驱动 / 框架 | 占位符 | 示例 |
|---|---|---|
| **pyodbc** | `?` | `cur.execute("... WHERE member_id = ?", (mid,))` |
| pymssql | `%s` | `cur.execute("... WHERE member_id = %s", (mid,))` |
| SQLAlchemy | `:name`（方言转换） | `text("... WHERE member_id = :mid")` |
| JDBC | `?` | `ps.setInt(1, mid)` |
| node-mssql | `@name` 或 `?` | `request.input('mid', mid)` |

**候选：全用 `?` + 元组传参**，并用 `pytest` 扫源码禁止 `execute(` 里出现 f-string。

### 6.3 连接管理与连接池

| 方案 | 说明 | 代价 |
|---|---|---|
| **每请求新建 / 关闭** | `connect()` → `finally: close()` | 单机低并发无压力 |
| 自建轻量池 | `queue.Queue` 存连接 | 要处理失效重连 |
| SQLAlchemy Pool | 成熟池 + 健康检查 | 引入 SQLAlchemy |
| 框架池 | HikariCP、pgbouncer | 语言绑定 |
| 长连接 + 心跳 | 减少握手 | 要处理超时断开 |

**候选：每请求新建 / 关闭 + `finally` 释放**（"连接释放"本身是课程要求演示的点）。

### 6.4 事务对象归谁

| 方案 | 事务对象在哪 | 说明 |
|---|---|---|
| **业务层持有、传给 DAO** | 业务层 `conn` | ⭐ DAO 只执行、不提交 |
| DAO 自己开事务 | DAO | 跨多次调用无法原子 |
| Unit of Work | 独立对象 | 形式感强 |
| 框架托管 | `@Transactional` | Java 侧标准 |

**候选：业务层持有连接与事务，DAO 接收 `conn` 参数。**

### 6.5 迁移工具与测试替身

| 子问题 | 候选 | 现状 / 候选 |
|---|---|---|
| 迁移 | **手写幂等 SQL + `:r`**、Flyway、Liquibase、Alembic、Prisma Migrate、dbmate、sqitch | 已用手写幂等（`11-migration/`），能展示课程要求的"6 要素" |
| 数据库测试 | `sqlcmd` 脚本、pytest + pyodbc、tSQLt | 已有 `regression.sql`（12 用例）+ `baseline/` 快照 |
| 测试数据隔离 | **事务内跑完 ROLLBACK**、独立测试库、快照恢复、testcontainers | 已用事务内回滚，残留 0 |
| 权限测试 | `EXECUTE AS USER` + 断言错误码 229 | 已用 |

---

## 七、三套成套方案

单层选对不够，**层与层要配套**。下面是三套已经配套好的组合：

| | **A 最小可用** | **B 推荐** | **C 更工程化** |
|---|---|---|---|
| 页面 | Jinja2 + 手写 CSS | Jinja2 + Bootstrap 5 本地 | Jinja2 + Bootstrap + htmx |
| 表单校验 | HTML5 原生 | HTML5 + WTForms | HTML5 + WTForms + CSRF |
| 框架 | Flask 单文件 | **Flask + Blueprint（一岗一蓝图）** | Flask + Blueprint + 应用工厂 |
| 业务组织 | 路由里直接写 | 事务脚本 + 领域模块 | 用例类 + 服务接口 |
| 事务 | `conn.commit()` | `with conn:` | Unit of Work |
| 权限 | 会话 `if` 判断 | 装饰器 + `EXECUTE AS USER` | 装饰器 + Casbin + `EXECUTE AS` |
| 数据访问 | pyodbc 裸调 | pyodbc + DAO 模块 | SQLAlchemy Core |
| 连接 | 每请求新建 | 每请求新建 + `finally` | SQLAlchemy Pool |
| 异常 | try/except | 自定义异常 + 全局 handler | + OpenTelemetry |
| 测试 | 手点 | pytest + `regression.sql` | + CI |
| 工作量 | 最小 | 适中 | 明显更大 |

> **建议 B**：课程要求的每一条（三层边界、参数化、事务边界、权限三层一致、统一异常、角色界面）都覆盖到，且没有一条是"为了好看而加"。

---

## 八、环境的现状与缺口

| 需要 | 现状 | 待办 |
|---|---|---|
| Python | 3.12.14 ✅ | — |
| ODBC 驱动 | Driver 17（32/64 位）✅ | — |
| SQL Server | 2022 Express，`milktea_shop` 18 表 ✅ | — |
| `flask` | ❌ 未装 | `pip install flask` |
| `pyodbc` | ❌ 未装 | `pip install pyodbc` |
| `flask-wtf` | ❌ 未装（走方案 B 才需要） | `pip install flask-wtf` |
| `pytest` | ❌ 未装 | `pip install pytest` |
| 样式文件 | — | Bootstrap 5 存本地 `static/vendor/` |
| `requirements.txt` | ❌ 尚无 | 选型定案后创建（本仓第一份依赖清单） |

> 数据库连接方式的关键实测：当前实例为**仅 Windows 认证**（`IsIntegratedSecurityOnly = 1`），`sa` 已禁用；库内 `usr_test_cashier` / `usr_test_maker` / `usr_test_stocker` 均为 `WITHOUT LOGIN`。实测每请求 `EXECUTE AS USER` 可行（切到收银员身份后读 `tbl_recipe` 报 **229**）→ **不开混合认证也能做到真实最小权限**，只需补建 `usr_test_manager`。

---

## 九、待定案（选型勾选表）

> 下列各项等核心工程（hezhlin5）确认后，本文件由 🟡 转 ✅，并据此建目录与代码。

| # | 待定事项 | 选项 | 我的建议 | 结论 |
|---|---|---|---|---|
| 1 | 成套方案 | A / **B** / C | B | ⬜ |
| 2 | Web 框架 | Flask / FastAPI / Django / Spring Boot | Flask | ⬜ |
| 3 | 数据访问方式 | **pyodbc** / SQLAlchemy Core / ORM | pyodbc | ⬜ |
| 4 | 渲染模式 | **Jinja2 SSR** / SPA / htmx | Jinja2 SSR | ⬜ |
| 5 | 样式来源 | **本地 Bootstrap** / CDN / Tailwind | 本地 Bootstrap（离线可用） | ⬜ |
| 6 | 权限实现 | 装饰器 / Casbin / 仅数据库 | **装饰器 + `EXECUTE AS USER`** | ⬜ |
| 7 | 连接管理 | 每请求新建 / 池 | 每请求新建 + `finally` | ⬜ |
| 8 | 会话 | **Flask 签名 cookie** / JWT / 服务端表 | 签名 cookie | ⬜ |
| 9 | 密码哈希强度 | 单轮 SHA-256 / PBKDF2 / Argon2id | 见 §9.1 | ⬜ |
| 10 | 顾客能否自助注册 | 开放 / **不开放（收银员代开）** | 不开放 | ⬜ |
| 11 | 角色口径 | 店员 + **顾客（= 会员）** / 店员 + 管理员 | 顾客 = 会员（已裁定） | ✅ |
| 12 | `tbl_member.is_active` 是否加列 | 加 / 不加 | 随迁移 02 一起加，一次解冻 | ⬜ |

### 9.1 关于密码哈希（唯一"低于市面标准"的地方）

市面推荐顺序是 **Argon2id > scrypt > bcrypt > PBKDF2**。当前起草的迁移 02 用的是**单轮 SHA-256 + 确定性盐**，理由是 SQL 侧 `HASHBYTES` 可算、迁移可自证、重建可复现。

这是**有意识的取舍，不是无知**：文档必须写明"演示级，生产应换 Argon2id"。若老师问起，这是加分项而非减分项。

---

## 十、与既有资产的关系

| 资产 | 状态 |
|---|---|
| `project/sql/`（18 表 / 137 字段 / 31 外键 / 46 CHECK / 22 索引 / 6 视图 / 4 角色） | ✅ 已成，`99-rebuild.sql` 一键重建实测通过 |
| `project/tests/regression.sql`（12 用例，失败 `THROW`） | ✅ 已成 |
| `project/tests/baseline/`（迁移前后快照，293 行零差异） | ✅ 已成 |
| `project/docs/normalization.md`（14 BCNF + 3 受控冗余，含无损分解证明） | ✅ 已成 |
| `project/sql/11-migration/migration-02-login-credentials.sql`（登录凭据列） | 🟡 **在分支 `feat/week07-login-credentials`，未合并**，等核心工程答复 4 个问题 |
| `course/lecture-week07-09.*` | ❌ **课程材料尚未入库** |
| `project/app/` | ❌ 只有 `README.md`（514 B） |
| `weeks/submissions/v1.0/` | ❌ 只有 `.gitkeep` |

> **本文件不涉及代码，也不改变任何数据库对象。** 它是一份选型讨论底稿。
