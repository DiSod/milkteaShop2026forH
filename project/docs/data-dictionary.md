# 数据字典（表 / 字段 / 域 / 码）

**项目**：奶茶店经营数据库（茶颜小铺 · 单店）
**阶段**：第一阶段（第 1—4 周）· v0.1
**状态**：✅ **四项任务全部完成**（字段字典 / 码标注 / 样例元组）
**关联**：
- 表结构与设计决策 → [`../../weeks/week02/schema-design.md`](../../weeks/week02/schema-design.md)
- 裁决后的定案（**17 张表**、D1—D8） → [`../../weeks/week02/issue-review.md`](../../weeks/week02/issue-review.md)
- 主数据（成品 / 原料 / 配方） → [`../../weeks/week02/master-data.md`](../../weeks/week02/master-data.md)

> ⚠️ **本文件的表结构以 `issue-review.md` 的 17 张表为准**（ISSUE-001/002/003 的裁决），
> 尚待与 hezhlin5 讨论确认；确认前若有调整，本文件随之修订。

> ### 📌 DDL 的唯一真相源在本文档
>
> 本文件的第二节是**表结构的唯一定义处**。第 3 周的
> `project/sql/01-schema/create-tables.sql` **由本文件翻译生成**，而不是各自独立编写 ——
> 这是 `01-layout-and-naming.md` §5「**禁止同一份内容在两个地方各自演化**」的要求。
>
> 因此本文档**只为 `tbl_employee` 保留一段 DDL 作为格式示例**，其余表不重复附 DDL；
> 需要看建表语句时，以 `project/sql/01-schema/create-tables.sql` 为准，**修改一律先改本文件**。

> ### 🔖 编号体系对照（三个前缀，别混）
>
> 本项目同时存在三套编号，**前缀不同、含义不同**：
>
> | 前缀 | 含义 | 定义处 | 例子 |
> |---|---|---|---|
> | **`D-01`～`D-12`** | 第 2 周的**设计决策** | [`schema-design.md`](../../weeks/week02/schema-design.md) | `D-04` ＝ 主码用代理键 |
> | **`D1`～`D8`** | ISSUE-001/002/003 的**裁决结论** | [`issue-review.md`](../../weeks/week02/issue-review.md) | `D1` ＝ 单库反冲倒扣 |
> | **`DOM-01`～`DOM-16`** | **域**（取值集合） | **本文件第一节** | `DOM-06` ＝ 支付方式 |
>
> ⚠️ **本文件的域一律用 `DOM-` 前缀** —— 早期草稿曾用 `D-xx`，与设计决策编号正面撞车
> （`D-06` 既是"小料建桥接表"又是"支付方式"），已于 2026-09-23 全部改名。

---

## 〇、怎么读这份文档

本文件同时承载课程的三个任务：

| 节 | 对应课程任务 | 内容 |
|---|---|---|
| **第一节 · 域字典** | 任务 2（域） | 把所有**枚举值**集中登记 |
| **第二节 · 字段字典** | **任务 2**（属性＋域） | 17 张表 × 每个字段 7 项说明 |
| **第三节 · 码标注汇总** | **任务 3** | 每张表的 PK / 候选码 / FK |
| **第四节 · 样例元组** | **任务 4** | 每张表 2—3 行真实业务数据 |

### 为什么「域字典」要单列一节

像"岗位 = 店长 / 收银员 / 制作员 / 库管员"这样的枚举，
**在数据库里只是一条 `CHECK` 约束 —— 看表结构看不到它的含义**。

如果我们把每个枚举都建成一张表（像 `tbl_spec_option` 那样），值就在库里；
但**不携带自有属性的取值集合用 `CHECK` 表达更简洁**（这是 D-01 定下的判据）。
代价就是：**这些值必须有一份文档落点，否则组员不知道 `'MAKER'` 是什么意思。**

**这份域字典就是这个落点。**

### 字段字典的 7 项是什么

课程原文：*「每张表每个字段写清：字段名、类型、长度/精度、是否允许空、默认值、域、字段的含义」*

| 项 | 含义 | 填写要点 |
|---|---|---|
| **字段名** | 列名 | 全小写 + 下划线；主键叫 `<表名单数>_id` |
| **类型** | SQL Server 数据类型 | 金额 `DECIMAL(10,2)`、时间 `DATETIME2`、物料 `DECIMAL(12,3)` |
| **长度/精度** | 字符长度或小数位 | 定太短将来改表，定太长浪费 —— **要能说出为什么是这个数** |
| **允许空** | `NULL` / `NOT NULL` | **能 `NOT NULL` 就 `NOT NULL`**；允许空要能说出业务理由 |
| **默认值** | `DEFAULT` | 不填时自动取的值；无则写 `—` |
| **域** | **允许取值的集合** | 三种落地：① 类型本身 ② `CHECK` 枚举 ③ 外键 / 域表（详见第一节） |
| **含义** | 业务上代表什么 | **写到能答辩的程度** —— 课程验收标准是"能解释每个字段及其键" |
| **码** | 该字段在码中的角色 | `PK` / `UNIQUE`（候选码）/ `FK → 表.字段` / 空 |

### 域的三种落地方式（我们的判据）

| 方式 | 什么时候用 | 例子 |
|---|---|---|
| **① 类型即域** | 取值无额外限制 | `employee_id` 的域＝非负整数 |
| **② `CHECK` 枚举** | 固定几值，且**不携带自有属性** | `position`、`ledger_type`、订单状态 |
| **③ 外键 / 域表** | 取值是别表主码；或**携带自有属性** | `product_id` → `tbl_product`；`cup_spec_id` → `tbl_spec_option` |

> **核心判据（D-01 遗留、由漏洞 1 补全）**：
> **取值集合「有没有自有属性」决定它用 `CHECK` 还是建表。**
> - 岗位、流水类型 → 只有几个裸值 → **`CHECK`**
> - 规格选项 → 带**加价 / 排序 / 显示名** → **物化为表 `tbl_spec_option`**

---

## 一、域字典

> 全库枚举值的**集中登记处**。凡是字段的"域"列写成 `CHECK IN (...)` 的，都必须在下面找得到。

### 1.1 业务枚举（`CHECK` 约束）

| # | 域名称 | 用于 | 取值 | 含义说明 | 状态 |
|---|---|---|---|---|---|
| DOM-01 | **岗位** `position` | `tbl_employee.position` | `MANAGER` / `CASHIER` / `MAKER` / `STOCKER` | 店长 / 收银员 / 制作员 / 库管员 | ✅ week1 §2.5 |
| DOM-02 | **商品状态** | `tbl_product.product_status` | `ON_SALE` / `OFF_SALE` | 在售 / 停售。**下架用状态，不删行** | ✅ week1 §3.8 |
| DOM-03 | **订单状态** | `tbl_order_header.order_status` | `PENDING` / `MAKING` / `READY` / `COMPLETED` / `ABANDONED` / `CANCELLED` | 待制作 / 制作中 / 待取餐 / 已完成 / 已弃取 / 已取消 | ✅ week1 §3.2 |
| DOM-04 | **库存流水类型** | `tbl_stock_ledger.ledger_type` | `PURCHASE_IN` / `SALES_USE` / `LOSS` | 采购入库(+) / 销售耗用(−) / 报损(−)。**v1.0 增 `STOCKTAKE`** | ✅ D2 |
| DOM-05 | **流水来源** | `tbl_stock_ledger.ref_type` | `PURCHASE` / `ORDER` / **`MANUAL`** / `OPENING` | 采购单 / 订单 / **手工登记（报损等无来源单据的流水）** / 期初结转。**v1.0 增 `STOCKTAKE`** | ✅ D-09 · D2 |
| DOM-06 | **支付方式** | `tbl_order_header.pay_method` | `CASH` / `WECHAT` / `ALIPAY` / `CARD` | 现金 / 微信 / 支付宝 / 刷卡 | 🟡 week1 §4.1 #11 只写"在线支付/现金"，此处细化 |
| DOM-07 | **券来源** | `tbl_coupon.source` | `POINTS_EXCHANGE` / `CAMPAIGN` | 积分兑换 / 活动赠与 | ✅ week1 §3.7 |
| DOM-08 | **券状态** | `tbl_coupon.status` | `UNUSED` / `USED` / `EXPIRED` | 未使用 / 已核销 / 已过期 | ✅ D-11 |
| DOM-09 | **积分流水类型** | `tbl_points_ledger.point_type` | `EARN` / `REDEEM` | 消费累积(+) / 兑换扣减(−) | ✅ week1 §3.7 |
| DOM-10 | **规格类型** | `tbl_spec_option.spec_type` | `CUP` / `SUGAR` / `ICE` | 杯型 / 糖度 / 冰量 | ✅ 漏洞 1 |
| DOM-11 | **杯型** | `tbl_spec_option.spec_code`（`spec_type='CUP'`） | `M` / `L` | 中杯 / 大杯（**大杯 +3.00 元**） | ✅ 漏洞 1 |
| DOM-12 | **糖度** | `tbl_spec_option.spec_code`（`spec_type='SUGAR'`） | `NONE` / `S30` / `S50` / `S70` / `FULL` | 无糖 / 三分 / 五分 / 七分 / 全糖<br>⚠️ **没有 `ANY`** —— "该原料用量与糖度无关"由 `tbl_recipe.sugar_spec_id IS NULL` 表达，**不是**一个糖度档（D-05a） | ✅ week1 §3.1 · D-05a |
| DOM-13 | **冰量** | `tbl_spec_option.spec_code`（`spec_type='ICE'`） | `NO_ICE` / `LESS` / `NORMAL` / `HOT` | 去冰 / 少冰 / 正常冰 / 热饮 | ✅ week1 §3.1 |
| DOM-14 | **采购单状态** | `tbl_purchase_order.order_status` | `ORDERED` / `ARRIVED` / `ACCEPTED` / `PARTIAL` / `CANCELLED` | 已下单 / 已到货 / 已验收 / **部分拒收** / 已取消 | 🟡 由 week1 §3.3 流程推出，待确认 |
| DOM-15 | **支付状态** | `tbl_order_header.pay_status` | `SUCCESS` / `FAILED` | 支付成功 / 失败（失败重试见 week1 §3.1 J2 分支） | 🟡 由 week1 §3.1 流程推出，待确认 |
| DOM-16 | **盘点单状态** | `tbl_stocktake.status` | `DRAFT` / `CONFIRMED` | 盘点中 / 已复核确认 | ⏸ **v1.0**（D5 延后） |

### 1.2 由表承载的"域"（不是 `CHECK`，是外键）

| 域 | 承载表 | 说明 |
|---|---|---|
| 商品品类 | `tbl_product_category` | 自引用层级表（D-01 已确认保留） |
| 商品（成品） | `tbl_product` | |
| 原料 | `tbl_ingredient` | |
| 规格选项 | `tbl_spec_option` | **因为它携带 `extra_price` / `sort_no` / `spec_name`，所以必须建表** |
| 小料（加料项） | `tbl_topping` | 携带 `extra_price` / `qty_per_serving` |
| 员工 / 会员 | `tbl_employee` / `tbl_member` | |
| 供应商 | `tbl_supplier` | |
| 券模板 | — | **v0.1 已合并进 `tbl_coupon`**（ISSUE-002 的 2.3） |

### 1.3 单位字典

| 单位 | 用于 | 说明 |
|---|---|---|
| `g` | 茶叶、粉类、小料、鲜果、酱料 | **散装物料一律按克**（含鲜果，2026-09-23 决定） |
| `ml` | 牛奶、糖浆、果浆、椰浆、水 | |
| `个` | 杯、杯盖、甜筒、圣代杯、打包袋 | **仅计件包材** |
| `根` / `张` | 吸管 / 封口膜 | |

> **口径**：**不做单位换算** —— 采购也按基本单位记。
> **煮制 / 泡制不产生库存流水**，台账一律用**干重当量**（见 D2 记账约定）。

---

## 二、字段字典

### 2.1 填写规范速查

| 项 | 规范 |
|---|---|
| **字段名** | 全小写 + 下划线；布尔用 `is_` 前缀；**禁用保留字**（`order` → `order_status`） |
| **主键命名** | `<表名单数>_id`（如 `product_id`） |
| **外键命名** | **与所引用主键同名** |
| **金额** | `DECIMAL(10,2)` —— **禁止 `FLOAT`** |
| **时间** | `DATETIME2` —— **禁止字符串存时间** |
| **物料数量** | `DECIMAL(12,3)` |
| **中文文本** | `NVARCHAR`；纯代码 / 英文用 `VARCHAR` |
| **约束命名** | `pk_` / `uq_` / `fk_` / `ck_` / `df_` |

### 2.2 格式示范：`tbl_employee`（员工）✅ 已填

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `employee_id` | INT | — | 否 | IDENTITY | 正整数 | 员工**代理主码**，系统自增 | **PK** |
| `employee_code` | VARCHAR | 10 | 否 | — | 形如 `E001` | **员工工号**，全店唯一 | **UNIQUE**（候选码） |
| `employee_name` | NVARCHAR | 20 | 否 | — | — | 员工姓名 | |
| `position` | VARCHAR | 10 | 否 | — | `CHECK` → **DOM-01 岗位** | 岗位：店长 / 收银员 / 制作员 / 库管员 | |
| `hire_date` | DATE | — | 否 | — | ≤ 今天 | 入职日期 | |
| `is_active` | BIT | — | 否 | `1` | `0` / `1` | 是否在职；离职改 0，**不删记录** | |

**本表码标注**

```
PK      : employee_id          （代理键，D-04）
候选码  : employee_code        （UNIQUE，业务码）
外码    : 无
```

**对应 DDL**（第 3 周可直接使用）

```sql
CREATE TABLE tbl_employee (
    employee_id    INT IDENTITY(1,1) NOT NULL,
    employee_code  VARCHAR(10)       NOT NULL,
    employee_name  NVARCHAR(20)      NOT NULL,
    position       VARCHAR(10)       NOT NULL,
    hire_date      DATE              NOT NULL,
    is_active      BIT               NOT NULL CONSTRAINT df_employee_is_active DEFAULT 1,
    CONSTRAINT pk_employee      PRIMARY KEY (employee_id),
    CONSTRAINT uq_employee_code UNIQUE (employee_code),
    CONSTRAINT ck_employee_position
        CHECK (position IN ('MANAGER','CASHIER','MAKER','STOCKER'))
);
```

### 2.3 逐表字段定义（第 2—17 张）

---

#### 2. `tbl_member`（会员）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `member_id` | INT | — | 否 | IDENTITY | 正整数 | 会员**代理主码** | **PK** |
| `member_code` | VARCHAR | 10 | 否 | — | 形如 `M001` | 会员号，全店唯一 | **UNIQUE**（候选码） |
| `member_phone` | VARCHAR | 11 | 否 | — | 11 位手机号 | **手机号**；下单时用它识别会员，取餐时用它核验本人 | **UNIQUE**（候选码） |
| `member_name` | NVARCHAR | 20 | 否 | — | — | 会员姓名 | |
| `register_date` | DATE | — | 否 | — | ≤ 今天 | 注册日期 | |
| `points_balance` | INT | — | 否 | `0` | **≥ 0** | **积分余额**（冗余字段，见 D-12；一致性由触发器/事务维护） | |

> **本表无外码。** 会员**不是员工**（week1 §2.5），走独立的会员号体系。
> **注意手机号在本项目出现两次、作用不同**（week1 §3.1）：**下单时报** → 识别会员打折积分；**取餐时报** → 核验是本人。

**码标注**
```
PK      : member_id
候选码  : member_code、member_phone（两个）
外码    : 无
```

---

#### 3. `tbl_product_category`（商品品类）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `category_id` | INT | — | 否 | IDENTITY | 正整数 | 品类**代理主码** | **PK** |
| `parent_category_id` | INT | — | **是** | — | `tbl_product_category.category_id` | **上级品类**；NULL 表示顶层（大类） | **FK → 自身** |
| `category_code` | VARCHAR | 10 | 否 | — | 形如 `C01` | 品类编码 | **UNIQUE**（候选码） |
| `category_name` | NVARCHAR | 20 | 否 | — | — | 品类名称（经典奶茶 / 水果茶 / 纯茶 / 冰淇淋与奶昔 / 季节限定） | |
| `sort_no` | INT | — | 否 | `0` | 正整数 | 菜单展示顺序 | |
| `is_active` | BIT | — | 否 | `1` | `0` / `1` | 是否启用 | |

> **`parent_category_id` 是唯一允许为空的"结构字段"** —— 顶层品类没有上级。
> week1 §4.1 #2 写的是"大类 → 系列 → 单品"，本设计用**自引用**支持多层，但当前**只用一层**。

**码标注**
```
PK      : category_id
候选码  : category_code
外码    : parent_category_id → tbl_product_category.category_id（自引用）
```

---

#### 4. `tbl_product`（商品 · 成品菜单）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `product_id` | INT | — | 否 | IDENTITY | 正整数 | 商品**代理主码** | **PK** |
| `product_code` | VARCHAR | 10 | 否 | — | 形如 `P001` | 商品编号 | **UNIQUE**（候选码） |
| `product_name` | NVARCHAR | 30 | 否 | — | — | 商品名称 | |
| `category_id` | INT | — | 否 | — | `tbl_product_category.category_id` | 所属品类 | **FK** |
| `base_price` | DECIMAL | (10,2) | 否 | — | **≥ 0** | **基础售价**（＝中杯价）<br>**大杯加价不在这里**，在 `tbl_spec_option.extra_price` | |
| `product_status` | VARCHAR | 10 | 否 | `'ON_SALE'` | **DOM-02 商品状态** | 在售 / 停售。**下架改状态，不删行**（历史订单不受影响） | |

> **为什么没有"大杯加价"字段** —— 漏洞 1 裁定"**全店统一加价**"，
> 所以加价是**杯型的属性**，落在 `tbl_spec_option`；`base_price` 只记中杯基础价。

**码标注**
```
PK      : product_id
候选码  : product_code
外码    : category_id → tbl_product_category.category_id
```

---

#### 5. `tbl_spec_option`（规格选项）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `spec_option_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `spec_type` | VARCHAR | 10 | 否 | — | **DOM-10** `CUP` / `SUGAR` / `ICE` | 规格维度 | |
| `spec_code` | VARCHAR | 6 | 否 | — | 见 **DOM-11 / DOM-12 / DOM-13** | 规格代码（`M` / `S30` / `NO_ICE` …） | |
| `spec_name` | NVARCHAR | 10 | 否 | — | — | 显示名（`中杯` / `三分糖` / `去冰`） | |
| `extra_price` | DECIMAL | (10,2) | 否 | `0` | ≥ 0 | **加价** —— 大杯 `+3.00` 的落点 | |
| `sort_no` | INT | — | 否 | `0` | 正整数 | 前端展示顺序 | |

> **这张表是本项目"域 vs 实体"判据的正面样本**：规格取值集合**携带自有属性**（加价 / 排序 / 显示名），
> 所以必须物化为表；而岗位、流水类型只有裸值，用 `CHECK` 即可。

**码标注**
```
PK      : spec_option_id
候选码  : (spec_type, spec_code)
外码    : 无
```

---

#### 6. `tbl_recipe`（配方 · BOM）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `recipe_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `product_id` | INT | — | 否 | — | `tbl_product.product_id` | 成品 | **FK** |
| `cup_spec_id` | INT | — | 否 | — | `tbl_spec_option`（`spec_type='CUP'`） | 杯型 | **FK** |
| `sugar_spec_id` | INT | — | **是** | — | `tbl_spec_option`（`spec_type='SUGAR'`） | 糖度；**NULL ＝ 该原料用量与糖度无关** | **FK** |
| `ingredient_id` | INT | — | 否 | — | `tbl_ingredient.ingredient_id` | 原料 | **FK** |
| `qty` | DECIMAL | (12,3) | 否 | — | **> 0** | 用量，**单位＝该原料的基本单位** | |

> **`sugar_spec_id` 用 NULL 表示"与糖度无关"**（见 D-05a）。
> **SQL Server 的 `UNIQUE` 把 NULL 视为相等**，所以下面的候选码在 NULL 时**只允许存一行** —— 唯一性照样成立。
>
> **无糖档不写行**（`NONE` 时配方中无该行＝用量 0）；**煮制/泡制不产生流水**，用量一律是**干重当量**。

**码标注**
```
PK      : recipe_id
候选码  : (product_id, cup_spec_id, sugar_spec_id, ingredient_id)
外码    : product_id → tbl_product.product_id
          cup_spec_id、sugar_spec_id → tbl_spec_option.spec_option_id
          ingredient_id → tbl_ingredient.ingredient_id
```

---

#### 7. `tbl_topping`（小料 · 加料项）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `topping_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `topping_code` | VARCHAR | 10 | 否 | — | 形如 `TP01` | 加料项编码 | **UNIQUE**（候选码） |
| `topping_name` | NVARCHAR | 20 | 否 | — | — | 加料项名称（珍珠 / 椰果 / 布丁 / 芋圆） | |
| `ingredient_id` | INT | — | 否 | — | `tbl_ingredient.ingredient_id` | **对应的库存原料**（桥接点） | **FK** |
| `extra_price` | DECIMAL | (10,2) | 否 | `0` | ≥ 0 | 加料加价（如珍珠 `+2.00`） | |
| `qty_per_serving` | DECIMAL | (12,3) | 否 | — | **> 0** | **加一份耗多少料**（单位＝原料基本单位） | |
| `is_active` | BIT | — | 否 | `1` | `0` / `1` | 是否可点 | |

> **这张表存在的理由**：**固定配方里没有"加珍珠"** —— 它是订单级的**可选增量**，
> 所以"加一份耗多少料"必须有自己的落点（`qty_per_serving`），不能塞进 `tbl_recipe`。
> **它演示了"实体 vs 角色"**：珍珠是**原料实体**，在菜单语境下**扮演**"加料项"角色。

**码标注**
```
PK      : topping_id
候选码  : topping_code
外码    : ingredient_id → tbl_ingredient.ingredient_id
```

---

#### 8. `tbl_ingredient`（原料 · 三表合一）

> **本表由原本的「原料字典 + 原料库存」合并而来**（D7）——单库后两者是 1:1，按规范化必须合并。
> **补货点 / 目标水位也在这里**（漏洞 2：它们是"原料的采购策略参数"，不是某个库位的属性）。
> **"保质期"字段已删除**（漏洞 3：week1 §3.5 已砍过期管理，§4.1 #5 系裁剪残留）。

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `ingredient_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `ingredient_code` | VARCHAR | 10 | 否 | — | 形如 `I001` | 原料编号 | **UNIQUE**（候选码） |
| `ingredient_name` | NVARCHAR | 30 | 否 | — | — | 原料名称 | |
| `unit` | VARCHAR | 6 | 否 | — | **1.3 单位字典** `g`/`ml`/`个`/`根`/`张` | **基本单位**；用量口径以它为准 | |
| `spec` | NVARCHAR | 20 | **是** | — | — | 包装规格（`500g/袋`）；**仅供采购参考，不参与扣料** | |
| `qty_on_hand` | DECIMAL | (12,3) | 否 | `0` | **≥ 0** | **当前库存量**（单库；单位＝`unit`）<br>冗余字段，判据见 D-12 | |
| `reorder_point` | DECIMAL | (12,3) | 否 | `0` | ≥ 0 | **补货点** —— 低于它由库管员报缺 | |
| `target_level` | DECIMAL | (12,3) | 否 | `0` | ≥ 0 | **目标水位** —— 补货量＝目标水位 − 当前库存 | |
| `moving_avg_cost` | DECIMAL | (10,4) | 否 | `0` | ≥ 0 | **移动加权成本**（元/基本单位）；每次采购入库后更新 | |
| `is_sold_out` | BIT | — | 否 | `0` | `0` / `1` | **沽清标记**（D4）——"料有、但现在做不了" | |
| `is_active` | BIT | — | 否 | `1` | `0` / `1` | 是否启用 | |

> **`CHECK (qty_on_hand >= 0)` 是本库最硬的一条约束**（D-03/D-12）：
> 它把 week1 反复强调的"**库存必须真实**"变成**结构上不允许为负** —— 而不是靠应用层自觉。

**码标注**
```
PK      : ingredient_id
候选码  : ingredient_code
外码    : 无
```

---

#### 9. `tbl_stock_ledger`（库存流水）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `ledger_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `ingredient_id` | INT | — | 否 | — | `tbl_ingredient.ingredient_id` | 原料 | **FK** |
| `ledger_type` | VARCHAR | 12 | 否 | — | **DOM-04 流水类型** | 采购入库(+) / 销售耗用(−) / 报损(−) | |
| `qty` | DECIMAL | (12,3) | 否 | — | **≠ 0** | 变动量，**正负号区分增减** | |
| `ref_type` | VARCHAR | 10 | 否 | — | **DOM-05 流水来源** | 来源类型；**报损等无来源单据的流水填 `MANUAL`** | |
| `purchase_order_id` | INT | — | **是** | — | `tbl_purchase_order.purchase_order_id` | 采购单（`ref_type='PURCHASE'` 时非空） | **FK** |
| `order_id` | INT | — | **是** | — | `tbl_order_header.order_id` | 订单（`ref_type='ORDER'` 时非空） | **FK** |
| `operator_id` | INT | — | **是** | — | `tbl_employee.employee_id` | 操作人；**NULL ＝ 系统自动产生**（反冲扣料的销售耗用流水） | **FK** |
| `ledger_time` | DATETIME2 | — | 否 | `SYSDATETIME()` | — | 发生时间 | |
| `remark` | NVARCHAR | 100 | **是** | — | — | 备注；**报损时写原因**（打翻 / 其它） | |

> **`qty` 不再有"库位"维度** —— 单库后流水只剩"原料 + 类型 + 数量"（D1）。
>
> **v1.0 再补**：`stocktake_id`（外码）+ 流水类型加 `STOCKTAKE` —— **这都是 D5 刻意延后留出的迁移素材**。


**码标注**
```
PK      : ledger_id
候选码  : 无（流水表按时间追加，无业务候选码）
外码    : ingredient_id → tbl_ingredient.ingredient_id
          purchase_order_id → tbl_purchase_order.purchase_order_id
          order_id → tbl_order_header.order_id
          operator_id → tbl_employee.employee_id
```

---

#### 10. `tbl_order_header`（订单单头**+ 支付**）

> **原 `tbl_payment` 已并入本表**（ISSUE-002 的 2.2，我们采纳）——
> 理由：week1 §4.1 #9 的订单头字段里**本来就写了"支付方式"**（week1 自身不一致）；
> 且"支付失败重试"是**流程分支**，不是数据需求。

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `order_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `order_no` | VARCHAR | 20 | 否 | — | 形如 `20260923-0001` | 订单号（对外） | **UNIQUE**（候选码） |
| `business_date` | DATE | — | 否 | — | — | **营业日**；单店 10:00—22:00 不跨日 | |
| `pickup_no` | INT | — | 否 | — | 正整数 | **取餐号**，**按日重置** | |
| `member_id` | INT | — | **是** | — | `tbl_member.member_id` | 会员；**非会员为 NULL** | **FK** |
| `coupon_id` | INT | — | **是** | — | `tbl_coupon.coupon_id` | 使用的券；**未用券为 NULL** | **FK** |
| `discount_amount` | DECIMAL | (10,2) | 否 | `0` | ≥ 0 | **券抵扣额快照** ← week1 原本缺这个字段 | |
| `amount_due` | DECIMAL | (10,2) | 否 | — | ≥ 0 | **应收** ＝ `Σ明细小计 − discount_amount` | |
| `amount_paid` | DECIMAL | (10,2) | 否 | `0` | ≥ 0 | **实收** | |
| `pay_method` | VARCHAR | 10 | **是** | — | **DOM-06 支付方式** | 现金 / 微信 / 支付宝 / 刷卡 | |
| `pay_status` | VARCHAR | 8 | **是** | — | **DOM-15 支付状态** | 成功 / 失败 | |
| `pay_time` | DATETIME2 | — | **是** | — | — | 支付时间 | |
| `trade_no` | VARCHAR | 40 | **是** | — | — | 第三方支付流水号 | |
| `order_status` | VARCHAR | 10 | 否 | `'PENDING'` | **DOM-03 订单状态** | 6 态流转（week1 §3.2） | |
| `order_time` | DATETIME2 | — | 否 | `SYSDATETIME()` | — | **下单时间** | |
| `finish_time` | DATETIME2 | — | **是** | — | ≥ order_time | **完成时间**；未完成时 NULL | |
| `cashier_id` | INT | — | 否 | — | `tbl_employee.employee_id` | **收银员** | **FK** |

> **金额口径（必须能对账）**：
> ```
> Σ 明细小计 − discount_amount = amount_due
> amount_due = amount_paid（无找零）
> ```
> **支付字段可空**是因为订单在"待制作"之前**可能还没付**（week1 §3.1：支付成功才生成订单，此处按"先生成后支付"的最宽松口径留空）。

**码标注**
```
PK      : order_id
候选码  : order_no、(business_date, pickup_no)     ← 取餐号按日重置
外码    : member_id → tbl_member.member_id
          coupon_id → tbl_coupon.coupon_id
          cashier_id → tbl_employee.employee_id
```

---

#### 11. `tbl_order_detail`（订单明细）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `order_detail_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `order_id` | INT | — | 否 | — | `tbl_order_header.order_id` | 所属订单 | **FK** |
| `line_no` | INT | — | 否 | — | 正整数 | **小票行号**（同一订单内连续） | |
| `product_id` | INT | — | 否 | — | `tbl_product.product_id` | 成品 | **FK** |
| `qty` | INT | — | 否 | `1` | **> 0** | 数量（杯数） | |
| `unit_price` | DECIMAL | (10,2) | 否 | — | ≥ 0 | **成交单价快照**（＝基础价 + 杯型加价） | |
| `cup_spec_id` | INT | — | **是** | — | `tbl_spec_option`（`CUP`） | **杯型快照**；不适用时为 NULL（如圣代/甜筒） | **FK** |
| `sugar_spec_id` | INT | — | **是** | — | `tbl_spec_option`（`SUGAR`） | **糖度快照**；不适用时为 NULL | **FK** |
| `ice_spec_id` | INT | — | **是** | — | `tbl_spec_option`（`ICE`） | **冰量快照**；不适用时为 NULL | **FK** |
| `subtotal` | DECIMAL | (10,2) | 否 | — | ≥ 0 | **小计** ＝ `qty × unit_price + Σ加料加价` | |

> **规格三个 FK 允许为空**，是因为 **"是否适用杯型/糖度/冰量"是成品自己的属性** ——
> 香草圣代与脆皮甜筒既无杯型也无糖度。若设成 `NOT NULL` 就没法表达这类成品。
>
> **规格存"代码值的 FK"而不是 JSON**（D-07）：JSON 会让属性不原子、**域的约束根本写不出来**。
> **快照要快照的是"钱"**：`unit_price` 与子表的 `unit_extra_price` 都存快照；规格代码本身是固定枚举，存 FK 即可。

**码标注**
```
PK      : order_detail_id
候选码  : (order_id, line_no)
外码    : order_id → tbl_order_header.order_id
          product_id → tbl_product.product_id
          cup_spec_id、sugar_spec_id、ice_spec_id → tbl_spec_option.spec_option_id
```

---

#### 12. `tbl_order_detail_topping`（明细加料）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `od_topping_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `order_detail_id` | INT | — | 否 | — | `tbl_order_detail.order_detail_id` | 所属明细行 | **FK** |
| `topping_id` | INT | — | 否 | — | `tbl_topping.topping_id` | 加料项 | **FK** |
| `qty` | INT | — | 否 | `1` | **> 0** | **加料份数** | |
| `unit_extra_price` | DECIMAL | (10,2) | 否 | — | ≥ 0 | **加价快照** | |

> **一行一种加料**（可加多种就写多行）—— 这是"加料是一对多"的落点。
> 扣料时要走**两路**：`固定配方` + `加料用量`（见 D-06）。

**码标注**
```
PK      : od_topping_id
候选码  : (order_detail_id, topping_id)
外码    : order_detail_id → tbl_order_detail.order_detail_id
          topping_id → tbl_topping.topping_id
```

---

#### 13. `tbl_points_ledger`（积分流水）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `point_ledger_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `member_id` | INT | — | 否 | — | `tbl_member.member_id` | 会员 | **FK** |
| `point_type` | VARCHAR | 10 | 否 | — | **DOM-09** `EARN` / `REDEEM` | 消费累积(+) / 兑换扣减(−) | |
| `point_change` | INT | — | 否 | — | **≠ 0** | 变动值，正负号区分 | |
| `order_id` | INT | — | **是** | — | `tbl_order_header.order_id` | 关联订单（累积时非空） | **FK** |
| `coupon_id` | INT | — | **是** | — | `tbl_coupon.coupon_id` | 关联券（兑换时非空） | **FK** |
| `change_time` | DATETIME2 | — | 否 | `SYSDATETIME()` | — | 发生时间 | |

> **为什么必须流水化**：week1 §3.7 原话 ——「积分**只存余额会丢失去向**，必须流水化」。
> `tbl_member.points_balance` 是冗余余额（D-12），**去向由本表记录**。

**码标注**
```
PK      : point_ledger_id
候选码  : 无
外码    : member_id → tbl_member.member_id
          order_id → tbl_order_header.order_id
          coupon_id → tbl_coupon.coupon_id
```

---

#### 14. `tbl_coupon`（券 · **发放 + 核销合一**）

> **原 `tbl_coupon_template` 已合并进本表**（ISSUE-002 的 2.3，我们采纳）——
> v0.1 的券只有"5 元券"一种形态，**不存在"模板"概念**，也就没有快照问题。
> 第 2 阶段引入多种券种时再拆，**正好是第 8 周规范化的素材**（D8）。

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `coupon_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `coupon_code` | VARCHAR | 20 | 否 | — | 形如 `CP20260923001` | 券号 | **UNIQUE**（候选码） |
| `member_id` | INT | — | 否 | — | `tbl_member.member_id` | 持券会员 | **FK** |
| `coupon_name` | NVARCHAR | 20 | 否 | — | — | 券名（`5 元无门槛券`） | |
| `source` | VARCHAR | 16 | 否 | — | **DOM-07 券来源** | 积分兑换 / 活动赠与 | |
| `discount_amount` | DECIMAL | (10,2) | 否 | — | > 0 | **面值**（发放时快照） | |
| `min_order_amount` | DECIMAL | (10,2) | 否 | `0` | ≥ 0 | **使用门槛**（发放时快照） | |
| `valid_from` | DATETIME2 | — | 否 | — | — | 生效时间 | |
| `valid_to` | DATETIME2 | — | 否 | — | > valid_from | 失效时间 | |
| `status` | VARCHAR | 8 | 否 | `'UNUSED'` | **DOM-08 券状态** | 未使用 / 已核销 / 已过期 | |
| `used_time` | DATETIME2 | — | **是** | — | — | 核销时间；订单取消时**清空**（D-11b 券退回） | |

> **不存 `used_order_id`**（D-11）：反向引用由 `tbl_order_header.coupon_id` 单向承担，
> 两边都存就是**双向冗余**。
> **券退回后历史轨迹不会丢** —— 被取消的订单**仍指向这张券**。

**码标注**
```
PK      : coupon_id
候选码  : coupon_code
外码    : member_id → tbl_member.member_id
          （订单 → 券 的方向由 tbl_order_header.coupon_id 承担）
```

---

#### 15. `tbl_purchase_order`（采购单头）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `purchase_order_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `purchase_no` | VARCHAR | 20 | 否 | — | 形如 `PO20260923001` | 采购单号 | **UNIQUE**（候选码） |
| `supplier_id` | INT | — | 否 | — | `tbl_supplier.supplier_id` | **供货方** ← ISSUE-003 补入 | **FK** |
| `order_date` | DATE | — | 否 | — | — | **下单日** | |
| `arrival_date` | DATE | — | **是** | — | ≥ order_date | **实际到货日**；未到货时 NULL | |
| `order_status` | VARCHAR | 12 | 否 | `'ORDERED'` | **DOM-14 采购单状态** | 已下单 / 已到货 / 已验收 / 部分拒收 / 已取消 | |
| `ordered_by` | INT | — | 否 | — | `tbl_employee.employee_id` | **下单人**（店长拍板） | **FK** |
| `received_by` | INT | — | **是** | — | `tbl_employee.employee_id` | **验收人**（库管员）；未验收时 NULL | **FK** |

> **本表特别不含**以下几个字段（见 D-08b）：
> 预计到货日（**提前期固定 1 天，是算出来的**）、备注、行状态（**部分到货一比即知**）。

**码标注**
```
PK      : purchase_order_id
候选码  : purchase_no
外码    : supplier_id → tbl_supplier.supplier_id
          ordered_by、received_by → tbl_employee.employee_id
```

---

#### 16. `tbl_purchase_order_detail`（采购明细）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `purchase_order_detail_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `purchase_order_id` | INT | — | 否 | — | `tbl_purchase_order.purchase_order_id` | 所属采购单 | **FK** |
| `ingredient_id` | INT | — | 否 | — | `tbl_ingredient.ingredient_id` | 原料 | **FK** |
| `qty_ordered` | DECIMAL | (12,3) | 否 | — | **> 0** | **订购量** | |
| `qty_received` | DECIMAL | (12,3) | 否 | `0` | ≥ 0 | **实收量**；`< qty_ordered` 即**部分拒收**（week1 §3.3 第 8 步） | |
| `unit_price` | DECIMAL | (12,4) | 否 | — | ≥ 0 | **采购单价**（元/基本单位）→ 供移动加权成本计算 | |

**码标注**
```
PK      : purchase_order_detail_id
候选码  : (purchase_order_id, ingredient_id)
外码    : purchase_order_id → tbl_purchase_order.purchase_order_id
          ingredient_id → tbl_ingredient.ingredient_id
```

---

#### 17. `tbl_supplier`（供应商）

| 字段名 | 类型 | 长度/精度 | 允许空 | 默认值 | 域 | 含义 | 码 |
|---|---|---|---|---|---|---|---|
| `supplier_id` | INT | — | 否 | IDENTITY | 正整数 | **代理主码** | **PK** |
| `supplier_code` | VARCHAR | 10 | 否 | — | 形如 `SUP01` | 供应商编码 | **UNIQUE**（候选码） |
| `supplier_name` | NVARCHAR | 50 | 否 | — | — | 供应商名称 | |
| `is_active` | BIT | — | 否 | `1` | `0` / `1` | 是否合作中 | |

> **只有 4 个字段**（ISSUE-003 降规格，去掉 `contact_phone`）——
> week1 §4.2 #6 砍掉的是"**供应商档案**"（含联系人、账期、银行账户），
> 本表补的只是"**给采购单一个来源标识**"，两者不矛盾。
>
> **收益是第 4 周的 JOIN 素材**：`供应商 → 采购单 → 采购明细 → 原料` 是**四层级联**。

---

## 三、码标注汇总（任务 3）

> **17 张表全量登记**。左三列是码，右一列是外码指向。

| # | 表名 | 主码 PK | 候选码 UNIQUE | 外码 FK → 目标 |
|---|---|---|---|---|
| 1 | `tbl_employee` | `employee_id` | `employee_code` | **无** |
| 2 | `tbl_member` | `member_id` | `member_code`、`member_phone` | **无** |
| 3 | `tbl_product_category` | `category_id` | `category_code` | `parent_category_id` → `tbl_product_category`（**自引用**） |
| 4 | `tbl_product` | `product_id` | `product_code` | `category_id` → `tbl_product_category` |
| 5 | `tbl_spec_option` | `spec_option_id` | `(spec_type, spec_code)` | **无** |
| 6 | `tbl_recipe` | `recipe_id` | `(product_id, cup_spec_id, sugar_spec_id, ingredient_id)` | `product_id` → `tbl_product`<br>`cup_spec_id`、`sugar_spec_id` → `tbl_spec_option`<br>`ingredient_id` → `tbl_ingredient` |
| 7 | `tbl_topping` | `topping_id` | `topping_code` | `ingredient_id` → `tbl_ingredient` |
| 8 | `tbl_ingredient` | `ingredient_id` | `ingredient_code` | **无** |
| 9 | `tbl_stock_ledger` | `ledger_id` | **无**（流水无业务候选码） | `ingredient_id` → `tbl_ingredient`<br>`purchase_order_id` → `tbl_purchase_order`<br>`order_id` → `tbl_order_header`<br>`operator_id` → `tbl_employee` |
| 10 | `tbl_order_header` | `order_id` | `order_no`、`(business_date, pickup_no)` | `member_id` → `tbl_member`<br>`coupon_id` → `tbl_coupon`<br>`cashier_id` → `tbl_employee` |
| 11 | `tbl_order_detail` | `order_detail_id` | `(order_id, line_no)` | `order_id` → `tbl_order_header`<br>`product_id` → `tbl_product`<br>`cup_spec_id`、`sugar_spec_id`、`ice_spec_id` → `tbl_spec_option` |
| 12 | `tbl_order_detail_topping` | `od_topping_id` | `(order_detail_id, topping_id)` | `order_detail_id` → `tbl_order_detail`<br>`topping_id` → `tbl_topping` |
| 13 | `tbl_points_ledger` | `point_ledger_id` | **无** | `member_id` → `tbl_member`<br>`order_id` → `tbl_order_header`<br>`coupon_id` → `tbl_coupon` |
| 14 | `tbl_coupon` | `coupon_id` | `coupon_code` | `member_id` → `tbl_member` |
| 15 | `tbl_purchase_order` | `purchase_order_id` | `purchase_no` | `supplier_id` → `tbl_supplier`<br>`ordered_by`、`received_by` → `tbl_employee` |
| 16 | `tbl_purchase_order_detail` | `purchase_order_detail_id` | `(purchase_order_id, ingredient_id)` | `purchase_order_id` → `tbl_purchase_order`<br>`ingredient_id` → `tbl_ingredient` |
| 17 | `tbl_supplier` | `supplier_id` | `supplier_code` | **无** |

**统计**

| 项 | 数量 |
|---|---|
| 表 | **17** |
| 主码 | **17**（**全部为代理键**） |
| 候选码 | **17** 个（其中 **6 个是复合候选码**） |
| 外码 | **30** 个 |
| 无外码的表 | **5 张** —— `tbl_employee` / `tbl_member` / `tbl_spec_option` / `tbl_ingredient` / `tbl_supplier` |

**约定**

- **主码一律用代理键**（`INT IDENTITY`）—— D-04
- **业务码一律建 `UNIQUE` 作为候选码**（如 `product_code`）
- **外键一律引用代理键**，且**显式命名**为 **`fk_<表>_<列>`**（用**外键列名**，不用目标表名）<br>  ⚠️ 不用 `fk_<表>_<目标>` —— `tbl_order_detail` 有 3 个外键都指向 `tbl_spec_option`，用目标表名会撞名
- 复合候选码用括号括起
- **`tbl_stock_ledger` 与 `tbl_points_ledger` 没有候选码** —— 流水表按时间追加，没有业务唯一标识

> **本表就是课程作业要求的"标出主码（PK）、候选码（UNIQUE 候选）、外码（FK → 哪个表哪个字段）"。**

### 3.1 值得在答辩时讲的三处

| # | 现象 | 为什么值得讲 |
|---|---|---|
| 1 | **所有主码都是代理键** | 演示课程那句"**主码是选出来做标识的，候选码是其他也能唯一标识的**" —— 每张表都能举例 |
| 2 | **`tbl_recipe` 的候选码有 4 列** | 它是"**带属性的联系**"而非纯连接表：既有属性（`qty`），码里又多了杯型与糖度两个维度 |
| 3 | **30 个外码里没有一个是弱类型** | `tbl_stock_ledger` 的"来源"用**判别列 + 真外键**（D-09），而不是一个字符串 `ref_no` —— 这样每个来源都能被数据库强制保证存在 |

---

## 四、样例元组（任务 4）

> 每张表 2—3 行**真实业务数据**（字典类小表给出全部行）。
> 数据取自 [`master-data.md`](../../weeks/week02/master-data.md) 的 30 成品 / 60 原料 / **30 款配方（492 行）**。
>
> **本节的样例是自洽的** —— 订单、明细、加料、支付、积分、券、库存流水之间**能对得上账**，
> 可直接作为第 3 周种子数据的雏形。

---

### 1. `tbl_employee`（全店 5 人，给出全部行）

| employee_id | employee_code | employee_name | position | hire_date | is_active |
|---:|---|---|---|---|---|
| 1 | E001 | 张伟 | MANAGER | 2024-03-01 | 1 |
| 2 | E002 | 李娜 | CASHIER | 2024-06-15 | 1 |
| 3 | E003 | 王强 | MAKER | 2025-01-10 | 1 |
| 4 | E004 | 赵敏 | MAKER | 2025-03-20 | 1 |
| 5 | E005 | 陈静 | STOCKER | 2025-05-06 | 1 |

> **会员不在本表**（week1 §2.5：会员用会员号标识，**不是员工**）。

### 2. `tbl_member`

| member_id | member_code | member_phone | member_name | register_date | points_balance |
|---:|---|---|---|---|---:|
| 1 | M001 | 13800138001 | 刘洋 | 2026-05-12 | 320 |
| 2 | M002 | 13800138002 | 周婷 | 2026-06-03 | 94 |
| 3 | M003 | 13800138003 | 吴磊 | 2026-07-21 | 1240 |

### 3. `tbl_product_category`（5 类，给出全部行）

| category_id | parent_category_id | category_code | category_name | sort_no | is_active |
|---:|---:|---|---|---:|---:|
| 1 | NULL | C01 | 经典奶茶 | 1 | 1 |
| 2 | NULL | C02 | 水果茶 | 2 | 1 |
| 3 | NULL | C03 | 纯茶 | 3 | 1 |
| 4 | NULL | C04 | 冰淇淋与奶昔 | 4 | 1 |
| 5 | NULL | C05 | 季节限定 | 5 | 1 |

> 全部 `parent_category_id` 为 NULL —— **当前只用一层**；结构上支持多层（自引用）。

### 4. `tbl_product`

| product_id | product_code | product_name | category_id | base_price | product_status |
|---:|---|---|---:|---:|---|
| 1 | P001 | 招牌柠檬水 | 2 | 4.00 | ON_SALE |
| 4 | P004 | 珍珠奶茶 | 1 | 7.00 | ON_SALE |
| 30 | P030 | 红丝绒奶昔 | 5 | 12.00 | **OFF_SALE** |

> P030 演示 week1 §3.8：**下架只改状态，历史订单不受影响**。

### 5. `tbl_spec_option`（12 行，给出全部行）

| spec_option_id | spec_type | spec_code | spec_name | extra_price | sort_no |
|---:|---|---|---|---:|---:|
| 1 | CUP | M | 中杯 | 0.00 | 1 |
| 2 | CUP | L | 大杯 | **3.00** | 2 |
| 3 | SUGAR | ANY | 任意糖度 | 0.00 | 1 |
| 4 | SUGAR | NONE | 无糖 | 0.00 | 2 |
| 5 | SUGAR | S30 | 三分糖 | 0.00 | 3 |
| 6 | SUGAR | S50 | 五分糖 | 0.00 | 4 |
| 7 | SUGAR | S70 | 七分糖 | 0.00 | 5 |
| 8 | SUGAR | FULL | 全糖 | 0.00 | 6 |
| 9 | ICE | NO_ICE | 去冰 | 0.00 | 1 |
| 10 | ICE | LESS | 少冰 | 0.00 | 2 |
| 11 | ICE | NORMAL | 正常冰 | 0.00 | 3 |
| 12 | ICE | HOT | 热饮 | 0.00 | 4 |

> **`ANY`（任意糖度）只用于配方表，不用于订单** —— 顾客必须选一个真实糖度档。
> **大杯加价 3.00 落在这里**，而不是商品表（漏洞 1 = 全店统一加价）。

### 6. `tbl_recipe`（取「珍珠奶茶 P004 · 中杯」的 4 行）

| recipe_id | product_id | cup_spec_id | sugar_spec_id | ingredient_id | qty |
|---:|---:|---:|---:|---:|---:|
| 1 | 4 | 1 | **NULL** | 1 | 5.000 |
| 2 | 4 | 1 | **NULL** | 17 | 20.000 |
| 3 | 4 | 1 | 6 | 12 | 25.000 |
| 4 | 4 | 1 | 5 | 12 | 10.000 |

> **前两行 `sugar_spec_id = NULL`** —— 红茶与珍珠的用量**与糖度无关**（D-05a：用 NULL 取代原 `'ANY'` 哨兵）。
> **后两行**是糖浆随糖度变化：五分糖 25 ml、三分糖 10 ml。
> **「无糖」档不写行** —— 缺行即用量 0。

### 7. `tbl_topping`（4 种加料，给出全部行）

| topping_id | topping_code | topping_name | ingredient_id | extra_price | qty_per_serving | is_active |
|---:|---|---|---:|---:|---:|---:|
| 1 | TP01 | 珍珠 | 17 | 2.00 | 20.000 | 1 |
| 2 | TP02 | 椰果 | 18 | 2.00 | 20.000 | 1 |
| 3 | TP03 | 布丁 | 19 | 3.00 | 30.000 | 1 |
| 4 | TP04 | 芋圆 | 20 | 3.00 | 30.000 | 1 |

> **`qty_per_serving` 是这张表的灵魂** —— 加一份珍珠耗 20 g，
> 这正是「固定配方里没有加料」的那部分扣料依据。

### 8. `tbl_ingredient`

| ingredient_id | ingredient_code | ingredient_name | unit | spec | qty_on_hand | reorder_point | target_level | moving_avg_cost | is_sold_out | is_active |
|---:|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 1 | I001 | 红茶（阿萨姆） | g | 500g/袋 | 4200.000 | 500.000 | 3000.000 | 0.0620 | 0 | 1 |
| 12 | I012 | 果糖（F60） | ml | 2.5kg/桶 | 8600.000 | 2000.000 | 10000.000 | 0.0185 | 0 | 1 |
| 17 | I017 | 珍珠（生） | g | 1kg/袋 | **320.000** | **1000.000** | 6000.000 | 0.0110 | **1** | 1 |

> **第 3 行同时演示三件事**：① 库存 **320 < 补货点 1000** → 库管员该报缺；
> ② `is_sold_out = 1` → 珍珠**已沽清**，所有含珍珠的成品前端标售罄；
> ③ 库存仍为正 —— **`CHECK (qty_on_hand >= 0)` 从未被违反**（D-03）。

### 9. `tbl_stock_ledger`

| ledger_id | ingredient_id | ledger_type | qty | ref_type | purchase_order_id | order_id | operator_id | ledger_time | remark |
|---:|---:|---|---:|---|---:|---:|---:|---|---|
| 1001 | 17 | PURCHASE_IN | **+6000.000** | PURCHASE | 1 | NULL | 5 | 2026-09-22 09:15:00 | NULL |
| 1002 | 17 | SALES_USE | **−48.000** | ORDER | NULL | 1 | **NULL** | 2026-09-23 10:09:25 | NULL |
| 1003 | 17 | LOSS | **−850.000** | **MANUAL** | NULL | NULL | 3 | 2026-09-23 22:10:00 | **打烊称重：熟珍珠打翻** |

> **三条流水正好演示三种来源**：
> - `PURCHASE_IN` ← **采购单**（`ref_type='PURCHASE'`，外码指向 `purchase_order_id`）
> - `SALES_USE` ← **订单反冲**（`ref_type='ORDER'`）；**`operator_id = NULL` ＝ 系统自动产生**
> - `LOSS` ← **手工登记**（`ref_type='MANUAL'`，报损无来源单据）
>
> **−48 g 是算出来的**：订单 1 的珍珠奶茶是**大杯**（配方 28 g）+ **加珍珠一份**（`qty_per_serving` 20 g）= 48 g。
> **这正好演示"扣料是两路"**（D-06）：固定配方 + 可选加料。

### 10. `tbl_order_header`

| order_id | order_no | business_date | pickup_no | member_id | coupon_id | discount_amount | amount_due | amount_paid | pay_method | pay_status | pay_time | trade_no | order_status | order_time | finish_time | cashier_id |
|---:|---|---|---:|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|---:|
| 1 | 20260923-0001 | 2026-09-23 | 1 | 1 | 1 | **5.00** | 11.00 | 11.00 | WECHAT | SUCCESS | 2026-09-23 10:05:12 | WX20260923100512 | COMPLETED | 2026-09-23 10:04:50 | 2026-09-23 10:09:30 | 2 |
| 2 | 20260923-0002 | 2026-09-23 | 2 | 2 | NULL | 0.00 | 9.00 | 9.00 | CASH | SUCCESS | 2026-09-23 11:20:05 | NULL | READY | 2026-09-23 11:19:40 | NULL | 2 |

> **对账验证（订单 1）**：`Σ明细小计 16.00 − 券抵扣 5.00 = 应收 11.00 = 实收 11.00` ✅
> **`business_date + pickup_no` 是候选码** —— 取餐号**按日重置**。
> **订单 2 是现金支付**，`trade_no` 为 NULL（无第三方流水号）。

### 11. `tbl_order_detail`

| order_detail_id | order_id | line_no | product_id | qty | unit_price | cup_spec_id | sugar_spec_id | ice_spec_id | subtotal |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 1 | 4 | 1 | **10.00** | 2 (L) | 6 (S50) | 11 (NORMAL) | **12.00** |
| 2 | 1 | 2 | 1 | 1 | 4.00 | 1 (M) | 5 (S30) | 9 (NO_ICE) | 4.00 |
| 3 | 2 | 1 | 4 | 1 | 7.00 | 1 (M) | 8 (FULL) | 11 (NORMAL) | **9.00** |

> **第 1 行 `unit_price = 10.00`** ＝ 基础价 7.00 + **大杯加价 3.00**（来自 `tbl_spec_option`）。
> **第 1、3 行的 `subtotal > unit_price`** —— 多出来的是加料加价，记在 `tbl_order_detail_topping`。
> 三行的三个规格 FK **都非空**（这几款成品都适用杯型/糖度/冰量）。

### 12. `tbl_order_detail_topping`

| od_topping_id | order_detail_id | topping_id | qty | unit_extra_price |
|---:|---:|---:|---:|---:|
| 1 | 1 | 1 (珍珠) | 1 | 2.00 |
| 2 | 3 | 2 (椰果) | 1 | 2.00 |

> 加料加价**存快照**（`unit_extra_price`）—— 日后调价不影响历史订单。

### 13. `tbl_points_ledger`

| point_ledger_id | member_id | point_type | point_change | order_id | coupon_id | change_time |
|---:|---:|---|---:|---:|---:|---|
| 1 | 1 | EARN | **+11** | 1 | NULL | 2026-09-23 10:05:15 |
| 2 | 1 | REDEEM | **−500** | NULL | 1 | 2026-09-20 14:30:00 |
| 3 | 2 | EARN | **+9** | 2 | NULL | 2026-09-23 11:20:08 |

> **第 1 行 +11**：订单 1 实付 11 元 → 11 积分（1 元 = 1 积分）。
> **第 2 行 −500**：用 500 积分兑换了券 1 —— **这一行与 `tbl_coupon` 的券 1 通过 `coupon_id` 对应**。
> **这就是"积分必须流水化"的意义**：余额只告诉你"有多少"，流水才告诉你"怎么来的、怎么去的"。

### 14. `tbl_coupon`

| coupon_id | coupon_code | member_id | coupon_name | source | discount_amount | min_order_amount | valid_from | valid_to | status | used_time |
|---:|---|---:|---|---|---:|---:|---|---|---|---|
| 1 | CP20260920001 | 1 | 5 元无门槛券 | POINTS_EXCHANGE | 5.00 | 0.00 | 2026-09-20 14:30:00 | 2026-10-20 23:59:59 | **USED** | 2026-09-23 10:05:10 |
| 2 | CP20260901002 | 3 | 5 元无门槛券 | CAMPAIGN | 5.00 | 0.00 | 2026-09-01 00:00:00 | 2026-12-31 23:59:59 | UNUSED | NULL |
| 3 | CP20260801003 | 2 | 3 元券（满 15 可用） | CAMPAIGN | 3.00 | 15.00 | 2026-08-01 00:00:00 | 2026-08-31 23:59:59 | **EXPIRED** | NULL |

> 三种状态各一行。**券 1 与积分流水第 2 行、订单 1 三处对得上**：
> 兑换 → 核销 → 抵扣 5 元。
> **`discount_amount` 是发放时的快照**；本表**不存 `used_order_id`**（由 `tbl_order_header.coupon_id` 单向承担）。

### 15. `tbl_purchase_order`

| purchase_order_id | purchase_no | supplier_id | order_date | arrival_date | order_status | ordered_by | received_by |
|---:|---|---:|---|---|---|---:|---:|
| 1 | PO20260921001 | 1 | 2026-09-21 | 2026-09-22 | **PARTIAL** | 1 | 5 |
| 2 | PO20260923002 | 2 | 2026-09-23 | **NULL** | ORDERED | 1 | NULL |

> **单 1 是"部分拒收"**（明细 2 只收了 2800/3000）；**单 2 尚未到货**（`arrival_date`、`received_by` 均为 NULL）。
> **`ordered_by = 1`（店长张伟）**、**`received_by = 5`（库管员陈静）** —— 这正是 week1 §3.3 的"店长拍板 → 库管员验收"。

### 16. `tbl_purchase_order_detail`

| purchase_order_detail_id | purchase_order_id | ingredient_id | qty_ordered | qty_received | unit_price |
|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 17 | 6000.000 | 6000.000 | 0.0110 |
| 2 | 1 | 1 | 3000.000 | **2800.000** | 0.0620 |
| 3 | 2 | 12 | 10000.000 | **0.000** | 0.0185 |

> **第 2 行 `qty_received < qty_ordered`** ＝ 部分拒收（week1 §3.3 第 8 步）；
> **第 3 行 `qty_received = 0`** ＝ 尚未到货。
> **没有 `line_status` 字段**（D-08b）—— 部分到货**一比即知**，不必再存一列状态。

### 17. `tbl_supplier`

| supplier_id | supplier_code | supplier_name | is_active |
|---:|---|---|---:|
| 1 | SUP01 | 晨光乳业 | 1 |
| 2 | SUP02 | 闽南茶叶批发 | 1 |
| 3 | SUP03 | 佳益包材 | 1 |

> **只有 4 个字段**（ISSUE-003 降规格）—— 它不记联系人 / 账期 / 银行账户。

---

### 4.1 一致性交叉验证

本节样例是**互相咬合**的，可在第 3 周当作一次自检清单：

| # | 验证项 | 结果 |
|---|---|---|
| 1 | `Σ明细小计 − discount_amount = amount_due = amount_paid`（订单 1） | 16.00 − 5.00 = 11.00 = 11.00 ✅ |
| 2 | 积分＝实付金额（1 元 = 1 积分） | 订单 1 → +11；订单 2 → +9 ✅ |
| 3 | 券：兑换（积分流水 −500）→ 核销（`used_time`）→ 抵扣（订单 1 的 5.00） | 三处对得上 ✅ |
| 4 | 扣料 = 配方 + 加料 | 大杯珍珠 28 g + 加珍珠 20 g = **48 g**，与流水 1002 一致 ✅ |
| 5 | 规格 FK 指向的 `spec_type` 与实际相符 | 杯型 → CUP、糖度 → SUGAR、冰量 → ICE ✅ |
| 6 | `CHECK (qty_on_hand >= 0)` 未被违反 | 最小库存 320 > 0 ✅ |
| 7 | 停售商品仍出现在历史订单中 | P030 停售，但无订单引用；**若引用过也必须仍可查** ✅ |
| 8 | 采购单状态与明细一致 | 存在部分拒收 → `PARTIAL` ✅ |

---

## 五、进度台账

| 节 | 内容 | 进度 |
|---|---|---|
| 〇 | 使用说明、域的三种落地判据、DDL 归属声明 | ✅ |
| 一 | **域字典**（16 条业务枚举 + 表承载域 + 单位字典） | ✅ |
| 二 | **字段字典** —— 17 张表逐表定义（**132 个字段**） | ✅ **17 / 17** |
| 三 | **码标注汇总** —— 17 张表 + 统计 + 答辩要点 | ✅ |
| 四 | **样例元组** —— 17 张表，含一致性交叉验证 8 项 | ✅ **17 / 17** |

### 课程第 2 周三项任务的完成情况

| 课程任务 | 状态 |
|---|---|
| **任务 1** 表清单（实体） | ✅ 在 `weeks/week02/schema-design.md`（21 张）→ 裁决后为 **17 张** |
| **任务 2** 字段定义（属性＋域） | ✅ 本文件第二节 + 第一节域字典 |
| **任务 3** 码标注（PK / 候选码 / FK） | ✅ 本文件第三节 |
| **任务 4** 样例元组 | ✅ 本文件第四节 |

### 下一步

1. **由本文件第二节翻译生成** `project/sql/01-schema/create-tables.sql`（本文件是唯一真相源）
2. 第四节样例元组 → 已扩充为种子数据 `project/sql/04-seed/seed_data.sql`
3. v1.0 再补 3 张表的定义（**D5** 延后）：`tbl_stocktake` / `tbl_stocktake_detail` / `tbl_price_history`

> **表结构已双人确认**（见 [`issue-review.md`](../../weeks/week02/issue-review.md)）。
> 本文档中的域取值与字段设计即为**最终定案**。

