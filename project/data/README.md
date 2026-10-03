# data · 数据文件

> ⚠️ **本目录下的数据文件不进 git**（见根目录 `.gitignore`）。  
> 原因：大文件一旦进入 git 历史便无法回落。  
> **替代方案：本 README 记录母本出处与自建造数脚本，他人 clone 后执行脚本即可 100% 幂等复现。**

---

## ⓪ 数据源总览与选型

依据第一周调研结论（[`weeks/week01/data-availability.md`](../../weeks/week01/data-availability.md)），公开零售数据无法覆盖进销存入库、配方耗用与会员体系。
本项目采用 **“母本波动规律驱动 + 高保真业务仿真自建（Simulation-driven Synthetic Data）”** 模式：

- **销量母本**：参考 Mendeley *Retail Transactions and Stocks Data* 的真实零售客流周期波动曲线（工作日/周末双峰分布）；
- **业务实体**：严格遵循 [`project/docs/data-dictionary.md`](../docs/data-dictionary.md) 的 17 张表模式定义与主数据。

---

## ① 三个子目录

| 目录 | 放什么 | 进 git |
|---|---|---|
| `raw/` | 外部母本参考文件（只读不改） | ❌ |
| `interim/` | 清洗/转换的中间特征数据 | ❌ |
| `generated/` | 由 `generate_seed.py` 生成的 17 表 CSV 数据集 | ❌ |

---

## ② 数据源登记表

### Mendeley Retail Transactions and Stocks Data

| 项 | 内容 |
|---|---|
| 用途 | 提供客流波动曲线母本参考（周末高峰/午晚双峰） |
| 出处 | Mendeley Data (DOI: 10.17632/27x8mjm8k4.1) |
| 链接 | https://data.mendeley.com/datasets/27x8mjm8k4/1 |
| 许可 | CC BY 4.0 |
| 状态 | ✅ 已采纳其客流概率分布参数用于造数引擎 |

---

## ③ 自建造数引擎（`generate_seed.py`）

数据生成主脚本位于本目录下：[`generate_seed.py`](generate_seed.py)。

### 运行方式与复现指令

```powershell
# 运行默认 7 天仿真原型（第 2 周基线测试，输出终端进销存对账报表）
python project/data/generate_seed.py --days 7

# 运行 90 天完整仿真并生成 SQL 种子脚本（第 3 周直接用于建库装载）
python project/data/generate_seed.py --days 90 --export-sql

# 运行第 8 周模式重构测试（开启实物未知损耗方差）
python project/data/generate_seed.py --days 90 --enable-stocktake-variance
```

* **可复现性保证**：脚本内默认固定随机种子 `random.seed(2026)`，确保任何人在任何环境执行输出的订单、流水与金额哈希值 100% 一致。

---

## ④ 进销存台账自洽平衡公式

脚本生成的业务数据在全生命周期内严格满足以下不变量（Invariants）：

$$
\text{期初原料库存} + \sum\text{采购入库} - \sum(\text{订单明细}\times\text{配方反冲}) - \sum\text{打烊已知报损} = \text{期末库存}
$$

且物理约束全时段成立：

$$
\forall t, \quad \text{qty\_on\_hand}(t) \ge 0 \quad (\text{绝无负库存})
$$

### 核心记账口径
1. **两路反冲扣料**（D-06）：$\text{应耗用} = \sum(\text{配方用量} \times \text{杯数}) + \sum(\text{加料份数} \times \text{每份耗量})$；
2. **干重当量记账**（D2）：煮制/泡制形态转变不产生流水，散装物料统一按 `g`/`ml` 计量；
3. **流水关联**：销售耗用 `ref_type='ORDER'`, `operator_id=NULL`（系统自动反冲）；报损 `ref_type='MANUAL'`, `operator_id=制作员工号`。

---

## ⑤ 进销存数据演进路径：从阶段一自洽闭环到第 8 周损耗重构

本项目的数据生成引擎采用**两阶段演进设计**，精准支撑课程不同阶段的实验与答辩需求：

### 阶段一（v0.1 · 第 1—4 周基线）：无差错自洽闭环
- **业务设定**：新店运营初期的“理想账面”。
- **台账平衡**：期初 + 累计采购 − 累计销售耗用 − 累计打烊已知报损 ＝ 期末库存。
- **未知损耗**：设定为 0（无差错闭环）。
- **目的**：服务于第 1 阶段作业（建库完整性、CHECK 约束与权限），确保数据库从空库装载后，账面无任何悬垂异常，所有查询与视图计算 100% 成立。

### 阶段二（v1.0 · 第 8 周模式重构）：真实实物损耗与盘点单迁移
- **课程任务**：第 8 周（ch7 模式重构），要求演示真实的 DDL 变更与数据迁移（由单据留白演进为企业级单据）。
- **业务设定**：真实经营中必定存在蒸发、滴漏、挂壁损耗等“未知损耗”，导致“账实不符”。
- **演进机制**：
  1. 造数脚本开启参数 `--enable-stocktake-variance`（注入 0.5%~1.5% 真实物理损溢）；
  2. 产生“实际盘点库存 ≠ 账面理论库存”的真实差异数据；
  3. 数据库补建 `tbl_stocktake`（盘点单头）与 `tbl_stocktake_detail`（盘点明细）；
  4. 数据库流水表扩展 `STOCKTAKE` 盘盈盘亏类型，执行平账迁移。
- **价值**：第 8 周无须凭空捏造假数据，本脚本可一键为重构实验提供完整的进销存冲突与平账数据源！
