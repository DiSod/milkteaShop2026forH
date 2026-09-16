# 第一周 · 数据可得性对比表（选场景决策用）

> 用途：为「小卖部 / 奶茶店」场景选择提供**数据支撑**依据。
> 状态：调研完成，待小组讨论后锁定场景。
> 编制日期：第一周

---

## 〇、一句话结论

**没有任何一个真实公开 CSV 能同时提供课程要求的 6 个实体（商品 / 库存 / 订单 / 订单明细 / 会员 / 员工）。**
其中 **「进货入库记录」和「会员 / 员工」几乎在所有公开零售数据中都是缺失的**。
因此「直接用真实 CSV」在技术上可行，但**必须接受补充**——这一点是选场景时最该先想清楚的。

---

## 一、对照基准：课程硬性要求

来自第一周文档第 1 节，场景**至少**要包含以下 6 类对象：

| # | 对象 | 说明 |
|---|---|---|
| 1 | 商品 | 名称、品类、售价、进价 |
| 2 | 库存 | 数量、上下限、所在仓位 |
| 3 | 订单 | 单头：时间、会员、金额、支付 |
| 4 | 订单明细 | 单行：商品、数量、单价、小计 |
| 5 | 会员 | 等级、积分、注册信息 |
| 6 | 员工 | 岗位、排班、操作权限 |

并且第四阶段还需要：**销量数据集 → 线性回归预测结果入库 → 预测驱动补货**。
这意味着数据还必须满足：**逐日 / 逐品 / 带日期**，且最好有**进销存三方对账关系**。

---

## 二、主对比表

图例：✅ 完整具备　🟡 部分 / 需加工　✘ 完全缺失　❓ 未能验证

| 数据集 | 来源 / 许可 | 规模 | 单店 | 商品 | 库存 | **进货入库** | 销售出库 | 订单明细 | 会员 | 员工 | 可直接下载 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Retail Transactions and Stocks Data** | [Mendeley 27x8mjm8k4](https://data.mendeley.com/datasets/27x8mjm8k4/1) · CC BY 4.0 | 40 店 / 2,326 SKU / 日粒度 | ✘ 40店 | ✅ | 🟡 仅"在手"快照 | ✘ | ✅ | 🟡 | ✘ | ✘ | ✅ 直链 |
| **Lokad 1-echelon 2017** | [Lokad 官方文档](https://docs.lokad.com/gallery/dataset-one-echelon-2017/) · 教学用 | 小型零售商 | ✅ **单店** | ✅ | ✅ StockOnHand + **StockOnOrder** | ✅ **采购单** | ✅ | ✅ | ✘ | ✘ | ✘ 链接404 |
| **FreshRetailNet-50K** | [HuggingFace](https://huggingface.co/datasets/Dingdong-Inc/FreshRetailNet-50K) · CC BY 4.0 | 898 店 / 863 SKU / 90 天 / 485 万行 | ✘ 898店 | ✅ | 🟡 **缺货小时级标注** | ✘ | ✅ 小时级 | ✘ | ✘ | ✘ | ✅ HF / 镜像 |
| **DataCo SMART Supply Chain** | [Mendeley 8gx2fvg2k6](https://data.mendeley.com/datasets/8gx2fvg2k6/5) · CC BY 4.0 | 180,519 笔交易 / 95.9MB | ✘ 全球分销 | ✅ | 🟡 | ✘ | ✅ | ✅ | 🟡 客户非会员制 | ✘ | ✅ 直链 |
| **Retail Inventory Data** | [Mendeley 9pn955p5vj](https://data.mendeley.com/datasets/9pn955p5vj/1) · CC BY 4.0 | 24 KB xlsx | ❓ | ✅ | ✅ 成本/价格/数量 | ✘ | ✘ | ✘ | ✘ | ✘ | ✅ 直链 |
| **Store Item Demand Forecasting** | [Kaggle](https://www.kaggle.com/datasets/dhrubangtalukar/store-item-demand-forecasting-dataset/data) | 50 品 × 10 店 × 2013–2017 逐日 | ✘ 10店 | 🟡 | ✘ | ✘ | ✅ 纯销量 | ✘ | ✘ | ✘ | ✅ Kaggle |
| **Shop Inventory Purchase Records** | [Kaggle](https://www.kaggle.com/datasets/alankuriyan/shop-inventory-purchase-records) | 未验证 | ❓ | ❓ | ❓ | ❓ **疑似有进货** | ❓ | ❓ | ❓ | ❓ | ✅ Kaggle |

---

## 三、6 实体覆盖度矩阵

这是**最该拿去讨论**的一张表 —— 直接看谁能补齐课程的硬性要求。

| 数据集 | 商品 | 库存 | 订单 | 订单明细 | 会员 | 员工 | 覆盖数 |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Retail Transactions and Stocks | ✅ | 🟡 | ✅ | 🟡 | ✘ | ✘ | **3.5 / 6** |
| Lokad 1-echelon 2017 | ✅ | ✅ | ✅ | ✅ | ✘ | ✘ | **4 / 6** |
| FreshRetailNet-50K | ✅ | 🟡 | ✘ | ✘ | ✘ | ✘ | **1.5 / 6** |
| DataCo Smart Supply Chain | ✅ | 🟡 | ✅ | ✅ | ✘ | ✘ | **3.5 / 6** |

**关键观察：没有任何一个数据集能覆盖「会员」和「员工」。**
这不是数据不够好，而是公开零售数据集基本都是**交易流水型**，天生不含人事与会员档案。

---

## 四、逐项详述

### 1. Retail Transactions and Stocks Data ⭐ 当前最均衡

- **DOI**：10.17632/27x8mjm8k4.1　**作者**：Jimmy Smith　**许可**：CC BY 4.0
- **原始描述（原文）**：
  > Daily transaction-level sales and stock keeping unit (On hand) from a retail business that holds the four-level product hierarchy (Division → Category → Subcategory → Segment). Trimmed to a stratified ML-ready sample of 40 retail storefront stores and 2,326 SKUs across three divisions.
- **文件**：
  - `retail_sales_ml_apl.csv` — 37.3 MB（交易级销售）
  - `retail_inventory_ml_apl.csv` — 95.4 MB（SKU 在手库存）
- **优点**：销售与库存**分两个文件**，天然适合做「订单明细 → 库存扣减」的对账关系；4 级商品层级可直接做成商品分类表。
- **缺点**：
  1. **40 家门店**，不是单店（但可按店过滤，取 1 家）；
  2. 库存只有 **On hand（在手快照）**，**没有进货入库单据**，即"库存怎么涨上来的"无据可查；
  3. 无会员、无员工。

### 2. Lokad 1-echelon 2017 ⭐ 结构最贴合「库存进出货」

- **文件与字段**（官方文档公开，结构已核实）：

| 文件 | 字段 | 课程对应表 |
|---|---|---|
| `Lokad_Items.tsv` | Id, Name, Category, SubCategory, Brand, ColorCode, Supplier, BuyPrice, SellPrice, SellCurrency, **SupplierLeadTime**, **StockOnHand**, **StockOnOrder** | 商品表 + 库存表 |
| `Lokad_Orders.tsv` | Id, Date, Quantity, NetAmount, Currency | 订单明细（销售出库） |
| `Lokad_PurchaseOrders.tsv` | Id, Date, **DeliveryDate**, Quantity, Currency, **Supplier**, NetAmount | **进货单（入库）** |
| `Lokad_Suppliers.tsv` | Supplier, **MOQ**（最小起订量） | 供应商表 |
| `Lokad_BOM.tsv` | Bundle, Part, Quantity | **配方 / 物料清单** |

- **优点（唯一同时具备"进 + 销 + 存"的候选）**：
  - `PurchaseOrders` 是真正的**进货入库单据**；
  - `DeliveryDate` vs `Date` 给出**订货→到货**的完整链路；
  - `SupplierLeadTime`（供货周期）+ `StockOnOrder`（在途）+ `MOQ`（起订量）= **第四阶段"预测驱动补货"所需的全部字段**；
  - `BOM` 正好对应奶茶的**配方**（茶底 + 小料）；
  - 是**单店**（一家小型零售商）。
- **致命缺点**：文档页给出的 `/sample-files/*.tsv` 直链**实测 404（BlobNotFound）**，只能在 Lokad 的 Envision playground 中取用。→ **适合当"结构范本"，不适合当直接下载的数据源。**

### 3. FreshRetailNet-50K

- **来源**：叮咚买菜（Dingdong-Inc）　**许可**：CC BY 4.0　**论文**：[arXiv 2505.16319](https://arxiv.org/abs/2505.16319)
- **规模**：50,000 组「门店-商品」90 天时序；898 家门店、18 个城市、863 个易逝 SKU；训练 4,500,000 行 + 验证 350,000 行
- **已核实字段**：
  `city_id`、`store_id`、`management_group_id`、`first/second/third_category_id`、`product_id`、`dt`、`sale_amount`、`hours_sale`（小时级销量序列）、**`stock_hour6_22_cnt`**（6:00–22:00 缺货小时数）、**`hours_stock_status`**（小时级缺货状态）、`discount`、`holiday_flag`、`activity_flag`、`precpt`、`avg_temperature`、`avg_humidity`、`avg_wind_level`
- **优点**：**约 20% 为自然发生的缺货样本** —— 这是公开数据中极罕见的"库存真实约束"证据，非常适合做**补货决策**的论证；还有天气/促销协变量，可做预测特征。
- **缺点**：
  1. 销售金额经过**全局归一化**（非真实元），无法直接当价格用；
  2. **没有订单维度**（是聚合后的销量，不是订单/订单明细）；
  3. 无进货、无会员、无员工；
  4. 898 家门店，非单店。

### 4. DataCo SMART SUPPLY CHAIN FOR BIG DATA ANALYSIS

- **DOI**：10.17632/8gx2fvg2k6.5　**许可**：CC BY 4.0
- **内容**：`DataCoSupplyChainDataset.csv`（95.9 MB，**180,519 笔交易**）+ `tokenized_access_logs.csv`（点击流）+ `DescriptionDataCoSupplyChain.csv`（字段说明）
- **品类**：Clothing / Sports / Electronics
- **评价**：属于**跨境电商/分销供应链**数据，与本课程的"一家实体小店"场景**明显不符**；且无实体库存台账。**不建议选用**，仅作对照。

### 5. Store Item Demand Forecasting（Kaggle）

- 50 个商品 × 10 家门店 × 2013–2017 **逐日销量**。
- 价值：**纯粹用于校准销量量级与季节性分布**（真实零售的周末效应、节假日峰值），可作为生成自身数据的母本。
- 无库存、无进货、无订单结构。

### 6. 未能验证项

| 数据集 | 原因 |
|---|---|
| [Shop Inventory Purchase Records](https://www.kaggle.com/datasets/alankuriyan/shop-inventory-purchase-records) | Kaggle 页面为 JS 渲染，反爬拦截，**字段未能核实**。名称含 "Inventory Purchase"，**疑似含进货记录**，值得本机下载后人工确认。 |
| [Retail Sales Register Data](https://www.kaggle.com/datasets/alankuriyan/retail-sales-register-data/data) | 同上（同一作者）。 |
| HuggingFace 直连 | 本环境无法访问 huggingface.co，需走 `hf-mirror.com` 镜像。 |

---

## 五、决策建议

### 三种可行路线

| 路线 | 做法 | 优点 | 风险 |
|---|---|---|---|
| **A. 真实 CSV 直导**（你倾向的方案） | 以 *Retail Transactions and Stocks* 为主数据源，导入自建表 | 数据真实、可复现、有出处可引用 | **会员 / 员工 / 进货入库全缺**，需自行补造；40 店需过滤为单店 |
| **B. 母本 + 自建** | 用 Lokad 结构定骨架 + 真实数据校准量级，生成台账平衡的单店数据集 | 6 实体齐全、进销存**可对账**、字段完全可控 | 数据是生成的，需在报告中说明来源与生成规则 |
| **C. 混合**（推荐） | 商品/销售用真实 CSV，进货入库与会员/员工按业务规则补齐 | 兼具真实性与完整性；对账关系可控 | 工作量略大，需明确标注哪些是真实、哪些是生成 |

### 若坚持「直接用真实 CSV」

必须先接受以下**三个补造项**，否则第一周之后会立刻卡住：

1. **进货入库单** —— *Retail Transactions and Stocks* 只有库存快照，没有入库记录。可用「期初库存 + 销售出库 → 反推进货」的方式补造，保证 `期初 + 入库 − 出库 = 期末` 平衡。
2. **会员表** —— 公开数据完全没有。需按业务规则生成会员档案并与订单关联。
3. **员工表** —— 公开数据完全没有。需按岗位（店长 / 收银 / 制作 / 库管）生成。

### 场景倾向的客观影响

你的数据诉求（**单店 + 库存进出货 + 台账平衡**）实际上**削弱了奶茶店**的胜算：

- 奶茶的公开数据几乎**只有销量**，没有任何单店库存台账；
- 而便利店 / 小卖部一侧，*Retail Transactions and Stocks* 与 FreshRetailNet 都能提供**库存维度**的数据。

> 但注意：**奶茶的配方（BOM）是它独有的优势**——`Lokad_BOM` 那种「成品 ← 原料」结构，正好能把「一杯奶茶出库」拆成「茶底 + 珍珠 + 糖浆」的原料消耗，这会让第三阶段的**触发器**和第四阶段的**补货**实验非常有料。小卖部是"整进整出"，没有这个层次。

---

## 六、数据获取说明（重要）

1. **本环境的 `pwsh` 无法联网**（实测 `curl` / `Invoke-WebRequest` 均因沙箱 TLS 凭证被拦，报 `SEC_E_NO_CREDENTIALS`），**我无法代你把 CSV 下载到工作目录**。
2. 可行做法：由组员在本机手动下载，或将仓库中的 `.csv` 放入工作目录后我再做字段解析、清洗与建表映射。
3. 已验证**公开直链可下载**的（可放心让组员去下）：
   - `https://data.mendeley.com/public-files/datasets/27x8mjm8k4/files/0f2e12a6-6110-4bda-b343-63a76234fa02/file_downloaded`（销售，37.3 MB）
   - `https://data.mendeley.com/public-files/datasets/27x8mjm8k4/files/6cdf316b-453e-482d-a9df-142262cfc6f6/file_downloaded`（库存，95.4 MB）
4. **Lokad 的 TSV 直链已失效**，不要在这上面浪费时间。

---

## 七、决策结果

| # | 问题 | 结论 |
|---|---|---|
| 1 | 场景锁定 | ✅ **奶茶店（单店）** —— 本学期不得更换 |
| 2 | 选择理由 | **结构完备优先**：商品 ↔ 库存之间隔着**配方(BOM)**，天然多一个层次，订单有"点单→制作→取餐"状态流转 |
| 3 | 数据策略 | ✅ **路线 B：母本 + 自建**（由"真实CSV直导"变更而来，原因见下） |
| 4 | 结构范本 | ⏳ **待定** —— 候选见第 4 节第 2 项 |
| 5 | 销量母本 | ⏳ **待定** —— 候选见第 2 节与第 4 节第 3 项 |
| 6 | 复杂度控制 | 原料 ≤ 60 种、菜单 ≤ 30 款、不做外卖平台、不做多门店、配方不做版本管理 |

> **数据源尚未确定。** 上表第 4、5 项的候选数据集**仅完成可访问性与覆盖度调研**，尚未选型。
> 选型落定后，登记到 `project/data/README.md` 的登记表中。

### ⚠️ 变更说明

上一轮曾按"**数据现成优先**"选定小卖部。现改选**奶茶店**，**连带放弃了"数据现成"这条路**——

> 经调研，**公开数据中不存在任何一家单店奶茶店的库存 / 进货记录**。
> 奶茶店的核心结构（配方 BOM）在所有公开数据中都不存在。

因此数据策略从"真实 CSV 直导"改为"**母本 + 自建**"：公开数据承担**销量分布的母本**与**结构范本**两个角色；库存、配方、会员、员工等主体数据由我们按业务规则自建，并保证**台账平衡**。

换来的是：**一个多层次的、更接近真实的数据库结构** —— 这正是选奶茶店的收益。

> **注**：策略已定，但**具体采用哪个数据源仍待定**。

详见 `business-requirements.md`。

---

## 附：AI 使用记录（课程要求留痕）

| 项 | 内容 |
|---|---|
| 使用目的 | 调研"单店 + 库存进出货"的公开数据可得性，产出选型依据 |
| 提示词要点 | ① 检索奶茶店/便利店销售与库存公开数据集；② 核实各数据集字段与许可；③ 对照课程 6 实体要求评估覆盖度 |
| AI 输出 | 候选数据集清单、字段表、覆盖度矩阵（即本文档主体） |
| **人工修改/验证** | ① 逐一核验数据集元数据（Mendeley API、Lokad 官方文档）；② 实测下载链接可用性，发现 Lokad 直链 404；③ 实测本机网络限制；④ 补充"无任何数据集覆盖会员/员工"的判断 |
| 存疑项 | Kaggle 两个数据集字段未核实；HuggingFace 直连被阻，字段经第三方镜像交叉验证 |
