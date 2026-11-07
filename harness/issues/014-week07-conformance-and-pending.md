# ISSUE-014: 第 7 周应用开发期的规范偏差清单 —— 已修 5 项、待裁定 4 项、待议 2 项

| 元数据 | 内容 |
|---|---|
| **状态** | 🟢 已解决 (Resolved) —— 4 项裁定已定案，凭据列与 TC-14 回归断言已合入 main |
| **类型** | 数据库约束 / 权限与安全 / 文档一致性 / 协同裁定 |
| **提报人/Agent** | DiSod（文档主编） |
| **指派处理** | **核心工程 (hezhlin5)**：裁定 §4 的 4 个问题；确认是否合并分支 |
| **提报日期** | 2026-11-05 |
| **关联分支** | `feat/week07-points-opening-ledger`（**已合入 main**） |
| **关联文件** | `project/sql/11-migration/migration-02..05`、`project/sql/08-security/role.sql`、`project/tests/regression.sql`、`project/app/`、`weeks/week07/README.md` §十一 §十二 |

---

## 0. 一分钟速览

这一天在第 7 周的应用开发过程中做了一轮「**拿文档契约去撞实现**」的检查（契约 = 课程要求 > `project/docs/**` > `harness/conventions/**`），
共查出 **11 处偏差**，按处置分成三类：

| 组 | 数量 | 处置 | 落点 |
|---|---|---|---|
| **A. 已修**（有代码改动 + 实测） | 5 | 已在分支上修完并自测 | `11-migration/`、`08-security/role.sql`、`project/app/` |
| **B. 待裁定**（要你拍板才能动） | 4 | 已写好方案与实测数据，等你答复 | 本 Issue §4 |
| **C. 登记不修**（已认账） | 4 | 只写进文档，不动代码 | `business-rules.md` §4 A11—A14 |

> ⚠️ **重要前提**：A 组的修复**全部只在这个分支上**。`main` 目前仍是
> 「18 表 / 137 字段 / 31 外键 / 46 CHECK、无积分期初、无时间序约束、单价 2 位小数、店长架构级授权」。
> 所以你在 `main` 上复核时，看到的现象与本文档描述不一致是**正常的**，请先 `git switch feat/week07-points-opening-ledger`。

---

## 1. A 组：已修的 5 项（含"怎么发现的 / 怎么修 / 怎么证明"）

### A-1 积分台账 80/80 不可对账（最严重的一条）

- **怎么发现**：`SUM(tbl_member.points_balance)` = **25,224**，而 `SUM(tbl_points_ledger.point_change)` = **14,401**，缺口 **10,823**；**80 个会员全部不符，且缺口清一色为正**（缺口为正意味着"账面比流水多"，不是随机误差）。
- **根因**：`project/data/generate_seed.py:656` 把期初积分**直接写进余额列**（`init_pts = random.randint(20,200) ...`），**没有生成任何流水**；此后每单再累加 `EARN` 流水。于是 `balance = 期初 + ΣEARN`，而 `Σ流水` 里没有期初那一笔。逐人核对：M001 差 **320**、M002 差 **94**、M003 差 **1240**，正是代码里硬编码的三个值；其余 77 人差值全部落在 20—200 区间 —— **80 个缺口 100% 可解释**。
- **为什么结构上补不回来**：`ck_points_ledger_point_type` 只允许 `('EARN','REDEEM')`，`ck_points_ledger_target` 要求 `EARN` 必挂订单、`REDEEM` 必挂券或订单。期初余额**既没有订单也没有券**，在两not下无处安放。对照：库存那边同期用了 `ref_type='OPENING'` 记期初（`generate_seed.py:691-704`），所以 `qty_on_hand = Σ流水` 是 **0 不符** —— 积分这边漏了同一个手法。
- **怎么修**：`migration-03-points-opening-ledger.sql` —— ① 扩展 `point_type` 允许 `'OPENING'`；② 重建 `ck_points_ledger_target`，为 `OPENING` 单开一条通路且**强制两端外键都为空**；③ 按「期初 = 余额 − Σ既有流水」算出缺口，回填 **80 条** `OPENING` 流水；④ 自证「全员缺口 = 0」才提交，否则 `THROW` 回滚。
- **怎么证明**：重建后 `OPENING 80 条 / 10,823` + `EARN 1,179 条 / 14,401` = **25,224 = 25,224，不符会员 0**；独立执行两遍幂等；`regression.sql` 新增 **TC-13**（`balance <> Σpoint_change` 计数 + `OPENING` 条数必须 80）兜住回归；约束行为 5 例（`OPENING` 挂订单 / 挂券 / `EARN` 无来源 / 变动为 0 全部 **547** 拦截，`OPENING` 两端皆空放行）。

### A-2 时间戳只约束了一半

- **怎么发现**：`ck_order_header_finish_time` 只保证 `finish_time >= order_time`，而 `pay_time >= order_time`、`finish_time >= pay_time` **两条都没有**。实测 1963 单违例均为 0 —— 但靠的是造数程序自觉，不会有人因为写错而报错。与当初券 `used_time` 零校验同类。
- **怎么修**：`migration-04-order-time-constraints.sql` 新增 `ck_order_header_pay_time`、`ck_order_header_finish_after_pay`。**没有改原来那条**，因为 `ck_order_header_finish_time` 这个名字与"完成 ≥ 付款"语义脱节，将来报错看不出是哪段时序错。
- **故意没补的一条**：**没有**加「`pay_status` 非空 ⇒ `pay_time` 非空」—— 实测有 **37 单**（CANCELLED，`pay_status='FAILED'`）`pay_time IS NULL`，加了会直接阻断历史数据。此判断写进了脚本注释。
- **怎么证明**：迁移前体检两条违例数（0 / 0）→ 建约束 → 自证 `is_disabled`/`is_not_trusted` 全 0 才提交。

### A-3 单价 / 成本列错用了金额定标

- **怎么发现**：`02-sql-style.md` §6.3 把数值列分三类定标（**金额 `DECIMAL(10,2)` / 物料数量 `(12,3)` / 单价成本 `(12,4)`**），而 6 个单价列用的是金额定标：`tbl_product.base_price`、`tbl_spec_option.extra_price`、`tbl_topping.extra_price`、`tbl_order_detail.unit_price`、`tbl_order_detail_topping.unit_extra_price` 全 `(10,2)`，`tbl_ingredient.moving_avg_cost` 是 `(10,4)`。
- **怎么修**：`migration-05-price-precision.sql` 六列统一 `(12,4)`。顺序是「摘除引用这些列的 6 条 `CHECK` → `ALTER COLUMN` → 按原定义 `WITH CHECK` 重建 → `sp_refreshview` 刷新 6 个视图 → 自证」——因为 `ALTER COLUMN` 会被依赖的 `CHECK` 挡住。
- **不是"一律取大"**：金额列**没动**。升到 4 位会让金额域失去定标、出现无意义尾数。这条判断也写进脚本头注释了。
- **连带影响（已登记）**：`business-rules.md` 的 A3「订单金额 = Σ明细」在出现 3—4 位单价后不再严格成立（`subtotal` 仍是 `(10,2)`，会四舍五入）。现库单价都是 2 位小数，实测偏差 0。

### A-4 店长的架构级授权（原 §十二 待议 P-1）

- **怎么发现**：`role.sql` 用一行 `GRANT ... ON SCHEMA::dbo TO role_manager`。架构级授权的语义是「**现在和将来**该架构下所有对象」——新建一张表就自动对店长开放，且这种扩大静默发生、不需要任何人批准。
- **怎么修**：换成 **17 张业务表 + 5 个业务视图逐个显式 `GRANT`**（授权面不变，仍全库全权；变的是"新对象必须显式补授"）。第 18 表 `tbl_coupon_template` 与第 6 视图 `vw_coupon_legacy` 由 `migration.sql` 建后补授（原本就有）。
- **怎么证明**：`role_manager` 现在 **78 条对象级授权 / 架构级 0 条**，覆盖 24 个对象；**行为探针**——新建 `dbo.tbl_probe_perm` 后以店长身份 `SELECT` → **229 拦截**（改前会放行）；店长对既有对象仍全权；三组越权负例仍全部 229。

### A-5 业务层权限漏参（比 A-4 更实际的一个洞）

- **怎么发现**：`project/app/web/security.py:47` 的实现是 `if roles and staff.get("role") not in roles:` —— **不传角色就放行任何员工**；而 `web/routes_maker.py` 两处装饰器恰好都是 `@staff_required()` **空参**。结果：收银员、库管员登录后能进制作工作台，只能靠数据层 229 兜住。
- **怎么修**：两处改成 `@staff_required("MAKER", "MANAGER")`；`routes_auth.py` 补 `STAFF_WORKBENCH_ROLES` 并把非工作台岗位改为「flash 提示 + 回登录页」（原代码两个分支都跳 `maker.board`，收银员登录必撞 403，是死代码）。
- **怎么证明**：新增 `project/app/tests/test_permissions.py` **9 条**断言（含 2 条行级隔离），`pytest` **17 passed**；**变异测试**——把装饰器还原成空参后 `pytest -k "stocker or cashier"` 变成 **3 failed**（拒绝来自 229），写回后恢复全绿。证明断言不是空断言。

---

## 2. C 组：登记不修的 4 项（已写进 `business-rules.md` §4）

| 编号 | 规则 | 为什么登记不修 |
|---|---|---|
| **A11** | `source='POINTS_EXCHANGE'` 的券必须由一次 `REDEEM` 扣分换来 | 实测 12 张兑换券各抵 5.00（合计 60.00 元让利真实发生），但 `coupon_id` 非空的 `REDEEM` 流水 **0 条**。持有人余额 249/257/327/343/358/369/413 **全部低于 500**，硬补会撞 `ck_member_points_balance >= 0`，只能篡改余额凑数。**认账不追认历史**，只保证今后三步同事务 |
| **A12** | v1.0 起下单必须绑定会员 | 库层 `member_id` 仍可空（承载 **764 张 / 38.9%** 的 v0.1 历史散客单）；应用侧 `/`、`/order`、`/orders`、`/me` 全部 `@member_required` —— **应用比库更严**，而此前这条差异没写在任何文档里 |
| **A13** | 在售商品至少有一条配方 | 在售商品 × 杯型应有 **58** 组合、有配方 **55**；缺 `P019 香草圣代`/`P020 草莓圣代`/`P021 脆皮甜筒` 的**大杯**。业务上合理（圣代只有中杯），但**库里没有记录**，`vw_product_stock_availability` 靠 `JOIN tbl_recipe` 静默滤除 |
| **A14** | 已取消不回冲原料、已制作未取件照常耗用 | `CANCELLED` 37 单 **0** 条耗用流水、`ABANDONED` 32 单**全部**有耗用 —— 数据自洽，但这套语义只活在造数程序里，答辩被问「为什么取消的没扣料」原来答不出 |

---

## 3. 事实证据（可复跑）

```powershell
# 从空库重建（18 表 + 5 段迁移 + RBAC + 负例）
cd project\sql
sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 99-rebuild.sql
#   → exit=0，总览 18 表 / 139 字段 / 31 外键 / 48 CHECK / 22 索引 / 6 视图 / 4 角色

# 自动化回归（14 项，失败会 THROW 出非零码）
cd ..\..
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -i project\tests\regression.sql
#   → exit=0，总用例数 13 / 通过 13 / 失败 0

# 迁移前后业务语义快照对比（293 行，差异必须为 0）
#   见 project/tests/baseline/README.md

# 应用层测试
cd project\app
python -m pytest -q
#   → 17 passed
```

---

## 4. B 组：**4 个需要你裁定的问题**（迁移 02 登录凭据）

背景：课程要求「用户登录」，但库里 `tbl_member` / `tbl_employee` **没有任何凭据列**（全库检索 `%pass%|%hash%|%salt%` 只命中 `sys*` 系统表）。
`main` 上过的 `migration-02-login-credentials.sql` 给两张表各加 `password_hash CHAR(64) NULL`（盐 + 单轮 SHA-256，会员初始口令 = 手机号后 6 位、员工 = 小写工号），
已在分支上实跑通过（80 + 5 行回填、2 条格式 `CHECK`、幂等两遍、Python 端 85 个账号端到端登录校验一致）。

**Q1（最关键）是否解冻「18 表结构冻结」以加这 2 列？**
表数仍是 18、只多 2 个字段（137 → 139）。若不解冻，登录只能退到"只验手机号存在"——那等于没有身份认证，`A-5` 的权限三层一致也就失去意义。

**Q2 `password_hash` 是否允许 `NULL`？**
允许的理由：`05-dml/crud.sql` 有 5 处 INSERT 不带凭据（`:113`/`:346` 员工，`:124`/`:366`/`:704` 会员），不允许就要同步改这 5 处。当前约定是 **`NULL` = 未开通登录**，应用侧 fail-closed（查不到 `password_hash` 就拒绝登录并提示"请联系店员开通"）。

**Q3 凭据格式断言是否并入 `project/tests/regression.sql`？**
我暂未加，避免与你后续改动冲突。若并入，建议加两条：`password_hash IS NULL OR LEN=64 且全十六进制`、`已开通登录的会员数 > 0`。

**Q4 员工初始口令用「小写工号」（如 `e003`）是否可接受？**
这是演示级选择，好处是答辩时能当面登录；坏处是工号可猜。若不接受，请给一个约定（例如统一初始口令 + 首次登录强制改密，但那要再加一列状态）。

---

## 5. C 组另一半：两条**结构性**待议（不是不改，是该在更后面的周次改）

| 编号 | 问题 | 为什么不现在改 |
|---|---|---|
| **P-2** | 下单的**写入路径以 `dbo` 执行**（`project/app/service/ordering.py` 的 `open_session()` 不带身份），同一请求的读取路径走受限身份 | 一次「下单」在库里跨 4 个权限域（订单头/明细属收银员、库存流水与原料扣减属库管员），纯 RBAC 无解；正解是**存储过程 + `EXECUTE AS OWNER` + `GRANT EXECUTE`**，属第 11—12 周内容。**不能**简单给收银员库存权限（否则回退成 `UPDATE tbl_ingredient SET qty=0` 凭空改、不留痕） |
| **P-3** | RBAC 只到**表级**，行级隔离全靠应用 `WHERE` | 以 `usr_test_cashier` 身份能读全部 1963 张订单头、80 个会员手机号；`GRANT` 没有行级粒度，只能 RLS（`sys.security_policies` 当前 **0** 条）。已用 `test_permissions.py` 两条断言兜底，RLS 属第 11—12 周 |

另有两项**数据层面的历史缺口**已在别处登记，不重复：退款在库里无独立记录（`business-rules.md` A9）、兑换券无扣分流水（A11）。

---

## 6. 解决记录（处理者填写）

- **处理人**：何争霖 (hezhlin5)
- **解决时间**：2026-11-04
- **裁决结论与实施记录**：

### 6.1 针对 Q1（解冻字段以增设登录凭据）
- **裁定结论**：**同意解冻**。在 `tbl_employee` 与 `tbl_member` 各新增 `password_hash CHAR(64) NULL` 列。
- **架构影响**：全库业务表数严格保持 18 张不变，字段数由 137 扩展至 139（+2 列）。
- **理由**：课程第 7—9 周对 Web 端“用户登录”及基于角色的权限校验有刚性需求；若缺少物理口令凭据列，身份认证只能退化为手机号存在性校验，三层架构的会话身份（`EXECUTE AS USER`）与 RBAC 将形同虚设。增设该两列系保障系统安全架构成立的必要演化。

### 6.2 针对 Q2（password_hash 允许 NULL 的兼容设计）
- **裁定结论**：**同意允许为 NULL**。
- **兼容考量**：既有 `project/sql/05-dml/crud.sql` 中存在 5 处未传凭据的会员/员工常规插入（如基础注册与演示数据测试）。允许 NULL 可避免对存量业务脚本与外围工具造成破坏性阻断。
- **安全保障**：应用层严格落实 fail-closed 策略：凡 `password_hash IS NULL` 的账号一律视为未开通登录，认证环节直接拒绝并提示联系店员开通。

### 6.3 针对 Q3（凭据质量断言并入回归套件）
- **裁定结论**：**同意并在 `project/tests/regression.sql` 中固化为 [TC-14]**。
- **断言口径**：
  1. 格式断言：全库所有非空凭据均必须满足 64 位大写十六进制 SHA-256 格式（`LEN(password_hash) = 64` 且无非法字符）；
  2. 覆盖度断言：基准数据中 80 位会员（`COUNT(password_hash) = 80`）与 5 位员工（`COUNT(password_hash) = 5`）的初始凭据全部有效回填且无 NULL。
  3. 异常阻断：任何不满足项直接计入 `@fail_count`，并由末尾 `THROW 51000` 抛出非零退出码阻断流水线。

### 6.4 针对 Q4（员工初始口令规则）
- **裁定结论**：**同意采纳小写工号规则（如 `e003`）**。
- **理由**：答辩现场演示直观、记忆与输入成本低；结合加盐机制（`'e' + employee_id` + 单轮 SHA-256），既保证了库内单向哈希不可逆，又满足教学演示与自动化测试的可确定性要求。

### 6.5 结构性待议（P-2 / P-3）及分支合并推进
- **P-2（下单写入走 dbo 跨域）**：确认留待第 11—12 周通过存储过程及 `EXECUTE AS OWNER` + `GRANT EXECUTE` 正式重构，当前阶段维持应用层事务隔离；
- **P-3（行级隔离依赖应用层 WHERE）**：确认留待第 11—12 周基于 SQL Server 行级安全（RLS）机制落地，目前已在应用层测试用例（`test_permissions.py`）中设置严密越权探测。
- **分支状态**：特性分支 `origin/feat/week07-points-opening-ledger` 已正式合入 `main`，并在本地完成 `99-rebuild.sql`（18表/139字段/31外码/48 CHECK/6视图/4角色）、`regression.sql`（TC-01~TC-14 全绿）及 `pytest`（17 passed）三重全量门禁验证。

---

## 7. 分支状态（供你决定是否合并）

```text
main                    b2c6c07  （分支已合入；本节为合并前留档）
  └─ feat/week07-points-opening-ledger  (已推送，领先 10 个提交)
       ad2295f  feat(migration): 迁移 02 登录凭据（草稿阶段）
       7d924fc  feat(app): 三层应用骨架
       cc6d32a  merge: 合并登录凭据分支
       4e98367  fix(app): 修正支付方式枚举 + 补建店长测试身份
       0ea9da0  feat(migration): 迁移 03 积分期初结转
       f1a607c  docs: 登记兑换券无扣分流水（A11）
       ec6eb6e  fix(app): 业务层岗位校验补参 + 9 条权限断言
       9591e4e  docs(week07): 待议清单
       5899473  feat(migration): 迁移 04 时间序 + 迁移 05 单价精度
       da0ef43  fix(security): 店长权限改逐对象授权（关闭 P-1）
       9487229  docs: 同步各文档并统一计数口径
```

**合并前请确认**：`project/sql/**` 属代码路径，按 `04-git-workflow.md` §2.1 必须先本地跑通 `99-rebuild.sql`；
我这边在 `main` 基础上 rebase 过一次，重建、回归（13/13）、基线（293/293）、`pytest`（17）都是绿的。
