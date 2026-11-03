# 11-migration · 模式演进与规范化重构迁移

> **所属周次**：第 6 周（ch7 函数依赖与规范化）  
> **核心产出**：[`migration.sql`](migration.sql)（满足课程 6 要素的模式重构与数据迁移脚本）  
> **理论依据**：[`project/docs/normalization.md`](../../docs/normalization.md) §5.3 · [`project/docs/v0.1-issues.md`](../../docs/v0.1-issues.md) §1.1  
> **协作定案**：[`harness/issues/011-week06-migration-and-subtotal-alignment.md`](../../../harness/issues/011-week06-migration-and-subtotal-alignment.md) · ISSUE-012 · ISSUE-013

---

## 1. 模块定位与职责

本目录承载阶段二（第 6 周）的模式演化与规范化重构脚本，核心目标是：
1. **消除传递依赖与数据冗余**：将原发放与核销合一的 `tbl_coupon`（17 表形态）规范化拆分为「券模板实体表 `tbl_coupon_template` + 券实例表 `tbl_coupon`」（18 表形态）；
2. **完整性约束下沉**：新增核销时间有效区间硬约束 `ck_coupon_used_time_range`（保证 `used_time` 落在 `[valid_from, valid_to]` 内）与模板外键约束 `fk_coupon_template`；
3. **课程 6 要素全面落地**：严格实现新表创建、字段调整、码设置、数据迁移、数据校验、旧表兼容处理。

---

## 2. 课程迁移 6 要素落地对照表

| # | 课程 6 要素 | `migration.sql` 具体实施动作 | 验证与技术保障 |
|---|---|---|---|
| **要素 1** | **新表创建** | 创建优惠券模板实体表 `tbl_coupon_template`，抽取券公共元数据（面额、门槛、来源、模板名称等） | `CREATE TABLE ... pk_coupon_template` |
| **要素 2** | **字段调整** | ① 原表 `tbl_coupon` 增加外键列 `template_id`；<br>② 在数据安全回填后，安全移除 4 个冗余列（`coupon_name`, `source`, `discount_amount`, `min_order_amount`） | `ALTER TABLE tbl_coupon ADD template_id ...`<br>`ALTER TABLE tbl_coupon DROP COLUMN ...` |
| **要素 3** | **码与约束设置** | ① 新表：主码 `pk_coupon_template`、候选码 `uq_coupon_template_code`、域约束（`ck_...source`, `discount_amount > 0` 等）；<br>② 原表：外键 `fk_coupon_template`、外键覆盖索引 `ix_coupon_template_id`、核销区间约束 `ck_coupon_used_time_range` | 外键、索引、CHECK 均采用幂等探测添加 |
| **要素 4** | **数据迁移** | 从历史 `tbl_coupon` 抽取唯一模板（实测去重得 2 种模板：`TPL_CAMP_5` 与 `TPL_POINTS_5`）装载至模板表；通过多列关联精准回填 `tbl_coupon.template_id` | `INSERT ... SELECT DISTINCT ...`<br>`UPDATE c SET c.template_id = t.template_id` |
| **要素 5** | **数据校验与防重** | 校验孤儿数据（`template_id IS NULL` 行数必须为 0）；校验核销时间区间违规数（必须为 0）；校验迁移后券总行数无损保持（24 行） | 若出现孤儿数据或非法时间，立即 `RAISERROR` 阻断事务 |
| **要素 6** | **旧表处理与平滑过渡** | 建立向后兼容全景视图 `vw_coupon_legacy`（连接 `tbl_coupon` 与 `tbl_coupon_template` 投影全部旧字段）；旧列从基表安全剥离；同步授权 `role_cashier` 与 `role_manager` | 外部历史查询零感知平滑过渡；RBAC 角色立即具备新表与视图权限 |

---

## 3. 双重验证机制（Single Source of Truth）

1. **全新重建流水线（99-rebuild.sql）**：
   - 接入 `project/sql/99-rebuild.sql` 第 11 步（状态：✅ 已接入）；
   - 确保从空库一键拉起即为最新重构形态（18 表、137 字段、31 外键、44 CHECK、22 业务索引、6 业务视图、4 安全角色）；
   - 彻底避免第 7—9 周应用开发时的表结构版本漂移。
2. **历史库独立重放演练（独立执行测试）**：
   - 支持在已存在数据的历史库上独立执行：
     ```powershell
     cd project\sql
     sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 11-migration\migration.sql
     ```
   - 脚本具备**完整幂等性**与**事务回滚保护**，支持重复运行而不产生副作用。

---

## 4. 开发规范守则

1. ⚠️ **文件编码**：含中文字符必须使用 **UTF-8 with BOM** 保存，防止 `sqlcmd` 静默丢行；
2. ⚠️ **幂等执行**：脚本必须支持重复执行（基于 `IF NOT EXISTS` / `IF EXISTS` 做对象探测）；
3. ⚠️ **事务安全**：DDL 与数据迁移必须包裹于显式事务 `BEGIN TRANSACTION ... COMMIT` 中，出现错误时整块回滚，不破坏源库。

---

## 5. 运行与验证证据

执行自动化回归测试检验迁移效果：
```powershell
cd project\tests
sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -b -i regression.sql
```
- **测试结果**：12/12 自动化断言全绿通过；
- **基线比对**：`project/tests/baseline/` 抽样订单明细（S1）、销售统计（S2）、库存可用性（S3）对比迁移前快照，**0 差异，指纹完全一致，语义 100% 保持**。

---

## 6. 迁移清单

| # | 脚本 | 周次 | 作用 | 状态 |
|---|---|---|---|---|
| 01 | [`migration.sql`](migration.sql) | 第 6 周 | 券表拆分（17 表 → 18 表）+ 核销区间约束 | ✅ 已并入 `main`，已接入 `99-rebuild.sql` |
| 02 | [`migration-02-login-credentials.sql`](migration-02-login-credentials.sql) | 第 7 周 | 登录凭据列：`tbl_member` / `tbl_employee` 各 +1 列 | ⏸ **草稿待确认**，仅在 `feat/week07-login-credentials` 分支 |

> **02 为什么需要**：全库实查确认**用户表没有任何登录凭据列**，而第 7—9 周课程要求
> 「用户登录 → Web 界面操作 → 数据写入」。没有凭据就无法验证"你是你"，
> 后续的角色界面、权限差异、越权拦截全部失去立足点。
> 口径依据：DiSod 2026-10-28 裁定「**默认顾客就是会员**」。

### 6.1 迁移 02 的实测结果

环境：本机 SQL Server 2022 Express（16.0.1000.6），2026-10-28。

| 验证项 | 结果 |
|---|---|
| 独立执行第 1 次 | 加列成功，回填 **80 会员 + 5 员工**，2 个格式约束创建，自证通过 |
| 独立执行第 2 次 | 全部「已存在，跳过」，回填 **0 行** → **幂等成立** |
| 从空库 `99-rebuild.sql` | exit=0，总览 **18 表 / 139 字段 / 31 外键 / 46 CHECK / 22 索引 / 6 视图 / 4 角色** |
| `project/tests/regression.sql` | **12/12 全绿，exit=0**（迁移 02 未破坏任何既有断言） |
| 三份基线快照 | 与 `result/after-S01~03.txt` 逐行比对：**293/293 行差异 0** |
| 端到端登录模拟（Python） | **80 会员 + 5 员工**都能用约定口令算出同一哈希；错误口令被拒 |
| 约束行为 5 例 | 63 位 / 小写 64 位 / 非十六进制 → **全部拒绝**；`NULL` 与合法 64 位 → 接受；回滚后残留 0 |

### 6.2 口令与盐的约定（应用层必须照此实现）

| 主体 | 盐 | 初始口令 | 摘要 |
|---|---|---|---|
| 会员 | `'m' + member_id` | 手机号后 6 位 | `UPPER(HEX(SHA-256(盐 + 口令)))`，64 字符 |
| 员工 | `'e' + employee_id` | 小写工号（如 `e001`） | 同上 |

三条实现约束（写进脚本头注释，这里只列结论）：

1. **拼接只能用 `VARCHAR`**：`HASHBYTES` 对 `NVARCHAR` 按 UTF-16LE 取字节，Python 的
   `hashlib.sha256` 按 UTF-8 取字节，混用会导致"同一口令两边算出不同哈希"，
   实测同输入 `'m1'+'000001'` 两边均为 `1E1B7D0D…F4EA4192`。
2. **盐不能含 `NEWID()`**：随机盐会让每次重建结果不同，直接破坏第 6 周建立的
   "迁移前后快照逐行一致（293/293）"承诺。
3. **引用新列的语句必须走动态 SQL**：同批次内语句在编译期就要求列存在，
   直接写会报「列名 'password_hash' 无效」（消息 207）。

### 6.3 待核心工程确认的四个问题

| # | 问题 | 我的建议 |
|---|---|---|
| 1 | 是否解冻「18 表结构冻结」口径以加这 2 列 | 表数仍 18，只 +2 字段，**不新增表、不新增外码、不改主码** |
| 2 | `password_hash` 是否允许 `NULL` | 建议允许。`05-dml/crud.sql` 有 5 处 INSERT 不带凭据，设 `NOT NULL` 会让演示脚本当场失败；`NULL` = 账号已建但未开通登录，应用侧 fail-closed |
| 3 | 是否把凭据断言并入 `regression.sql` | 建议**合并之后**再加，避免两边同时改同一文件冲突；迁移脚本内已有自证（逐行重算比对） |
| 4 | 员工初始口令用「小写工号」是否可接受 | 可接受。这只是初始值，真实系统首次登录应强制改密 |

> ⚠️ 本迁移**尚未合并进 `main`**。合并前 `main` 上的 `99-rebuild.sql` 不会执行它，
> 数据库仍是 137 字段 / 44 CHECK。
