# 11-migration · 模式演进与规范化重构迁移

> **所属周次**：第 6 周（ch7 函数依赖与规范化）  
> **核心产出**：[migration.sql](migration.sql)（满足课程 6 要素的模式重构与数据迁移脚本）  
> **理论依据**：[project/docs/normalization.md](../../docs/normalization.md) §5.3 · [project/docs/v0.1-issues.md](../../docs/v0.1-issues.md) §1.1  
> **协作定案**：[harness/issues/011-week06-migration-and-subtotal-alignment.md](../../../harness/issues/011-week06-migration-and-subtotal-alignment.md) · ISSUE-012

---

## 1. 模块定位与职责

本目录承载阶段二（第 6 周）的模式演化与规范化重构脚本，核心目标是：
1. **消除传递依赖与数据冗余**：将原发放与核销合一的 	bl_coupon（17 表形态）规范化拆分为「券模板实体表 	bl_coupon_template + 券实例表 	bl_coupon」（18 表形态）；
2. **完整性约束下沉**：新增核销时间有效区间硬约束 ck_coupon_used_time_range（保证 used_time 落在 [valid_from, valid_to] 内）与模板外键约束 k_coupon_template；
3. **课程 6 要素全面落地**：严格实现新表创建、字段调整、码设置、数据迁移、数据校验、旧表兼容处理。

---

## 2. 课程迁移 6 要素落地对照表

| # | 课程 6 要素 | migration.sql 具体实施动作 | 验证与技术保障 |
|---|---|---|---|
| **要素 1** | **新表创建** | 创建优惠券模板实体表 	bl_coupon_template，抽取券公共元数据（面额、门槛、来源、模板名称等） | CREATE TABLE ... pk_coupon_template |
| **要素 2** | **字段调整** | ① 原表 	bl_coupon 增加外键列 	emplate_id；<br>② 在数据安全回填后，安全移除 4 个冗余列（coupon_name, source, discount_amount, min_order_amount） | ALTER TABLE tbl_coupon ADD template_id ...<br>ALTER TABLE tbl_coupon DROP COLUMN ... |
| **要素 3** | **码与约束设置** | ① 新表：主码 pk_coupon_template、候选码 uq_coupon_template_code、域约束（ck_...source, discount_amount > 0 等）；<br>② 原表：外键 k_coupon_template、外键覆盖索引 ix_coupon_template_id、核销区间约束 ck_coupon_used_time_range | 外键、索引、CHECK 均采用幂等探测添加 |
| **要素 4** | **数据迁移** | 从历史 	bl_coupon 抽取唯一模板（实测去重得 2 种模板：TPL_CAMP_5 与 TPL_POINTS_5）装载至模板表；通过多列关联精准回填 	bl_coupon.template_id | INSERT ... SELECT DISTINCT ...<br>UPDATE c SET c.template_id = t.template_id |
| **要素 5** | **数据校验与防重** | 校验孤儿数据（	emplate_id IS NULL 行数必须为 0）；校验核销时间区间违规数（必须为 0）；校验迁移后券总行数无损保持（24 行） | 若出现孤儿数据或非法时间，立即 RAISERROR 阻断事务 |
| **要素 6** | **旧表处理与平滑过渡** | 建立向后兼容全景视图 w_coupon_legacy（连接 	bl_coupon 与 	bl_coupon_template 投影全部旧字段）；旧列从基表安全剥离；同步授权 
ole_cashier 与 
ole_manager | 外部历史查询零感知平滑过渡；RBAC 角色立即具备新表与视图权限 |

---

## 3. 双重验证机制（Single Source of Truth）

1. **全新重建流水线（99-rebuild.sql）**：
   - 接入 project/sql/99-rebuild.sql 第 11 步；
   - 确保从空库一键拉起即为最新重构形态（18 表、137 字段、31 外键、44 CHECK、22 业务索引、6 业务视图、4 安全角色）；
   - 彻底避免第 7—9 周应用开发时的表结构版本漂移。
2. **历史库独立重放演练（独立执行测试）**：
   - 支持在已存在数据的历史库上独立执行：
     `powershell
     cd project\sql
     sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 11-migration\migration.sql
     `
   - 脚本具备**完整幂等性**与**事务回滚保护**，支持重复运行而不产生副作用。

---

## 4. 运行与验证证据

执行自动化回归测试检验迁移效果：
`powershell
cd project\tests
sqlcmd -S .\SQLEXPRESS -E -C -d milktea_shop -f 65001 -b -i regression.sql
`
- **测试结果**：12/12 自动化断言全绿通过；
- **基线比对**：project/tests/baseline/ 抽样订单明细（S1）、销售统计（S2）、库存可用性（S3）对比迁移前快照，**0 差异，指纹完全一致，语义 100% 保持**。
