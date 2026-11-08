# ISSUE-015: 第 9 周界面 MD3 重构（点单交互与四岗工作台可读性优化）

| 元数据 | 内容 |
|---|---|
| **状态** | 🟢 已解决 (Resolved) |
| **类型** | 界面与交互 / 交付质量 |
| **提报人/Agent** | DiSod（本人发起，AI Agent 落地） |
| **指派处理** | 文档主编 (DiSod) |
| **提报日期** | 2026-11-08 |
| **关联文件** | [`project/app/README.md`](../../project/app/README.md) §3、[`app.css`](../../project/app/web/static/css/app.css)、[`_menu_cards.html`](../../project/app/web/templates/_menu_cards.html)、[`_cart_shell.html`](../../project/app/web/templates/_cart_shell.html)、[`menu.js`](../../project/app/web/static/js/menu.js) |

---

## 0. 一分钟速览

- **视觉**：整站从 Bootstrap 默认样式改为 **Material Design 3**（薄荷绿主色 `#146b56`）。**只换外观，不换框架**——排版仍由 Bootstrap 5.3.3 的栅格与工具类负责，模板里没有一处 class 被重命名。
- **交互**：点单二级菜单改**弹窗**；新增**底部悬浮价格栏 + 购物车抽屉**；我的订单拆成**进行中主表格 + 折叠的历史**；制作台与库管台的全量表收进**折叠区**；店长台加**两张图表**。
- **顺手修了 3 个渲染 bug + 1 个异常处理缺陷**（详见 §4），其中「库管台补货预警整列空白」和「405 被吞成 500」不是界面问题，是逻辑问题。
- **门禁**：`pytest -q` **38 passed**、`regression.sql` **14/14**、`99-rebuild.sql` exit=0、四岗位 200/403 矩阵与重构前一致。
- **没做**：涟漪动效、暗色主题、MD3 全量组件库（只覆盖页面实际用到的组件）。

## 1. 为什么要改

课程 v1.0 的评分要点是「设计合理性、迁移正确性、**应用完整性与可用性**」，演示时看的是「点得动、看得懂」。
重构前有四个具体毛病：

1. **菜单是 55 行的「商品 × 杯型」大表**：同一饮品的中杯/大杯各占一行，商品名重复两遍，视线要在「商品｜杯型｜单价｜可做」四列之间来回跳；用户的原话是「杯型也要是可选项啊，这样就没有那么多表项了」。
2. **制作台「还能做几杯」55 行里有 45 行是「充足在售」**（82%），真正要处理的 5 个饮品被淹没在噪声里。
3. **我的订单把 21 条记录平铺**：正在做的单和三个月前已完成的单长得一模一样。
4. **全场只有 Bootstrap 默认蓝**：没有品牌色、没有图标、没有图表，是「后台管理系统默认脸」，C 端感为零。

## 2. 做了什么

| # | 改动 | 主要落点 | 提交 |
|---|---|---|---|
| 1 | 全站 Material Design 3 视觉层：角色色变量、导航胶囊、表格卡片化、filled text field、胶囊按钮、tonal 徽章/提示条、独立错误页 | `web/static/css/app.css`、`web/templates/base.html`、`error.html` | `a8b75b6` |
| 2 | 菜单改「一饮品一张卡（按分类分组）→ 点卡片弹对话框选杯型/糖度/冰量/数量/加料」 | `templates/_menu_cards.html`、`static/js/menu.js` | `eae7cb6` |
| 3 | 底部悬浮价格栏（杯数 + 合计）+ 购物车抽屉（增减、回到某杯改规格、清空） | `templates/_cart_shell.html`、`menu.js` | `e14670b` |
| 4 | 我的订单拆成「进行中主表格（状态徽章 + 一句人话进度）」+ 折叠的历史订单 | `service/auth.py`、`templates/orders.html` | `586eb4f` |
| 5 | 制作台可做量：一饮品一行、杯型作列、只列不健康的 5 个 + 全量折叠 | `service/catalog.py`（`makeable_cards`）、`templates/maker.html` | `708b638` |
| 6 | 库管台库存全量表收进折叠区，并按「需处理程度」排序 | `service/stock.py`（`_attention_rank`）、`templates/stocker.html` | `116957d` |
| 7 | 店长台两张图表：近 7 天趋势（柱＝实收/线＝订单数，双轴）+ 销量 Top 10（横向柱） | `service/admin.py`（`_chart_payload`）、`templates/manager.html`、vendored Chart.js 4.4.1 | `37cb2be` |

此外 `regression.sql` 的 TC-10 一并改为**只断言 v0.1 种子区间**（`business_date < '2026-10-01'`），
把演示期新增订单从断言里摘出去，只打印不判定——见 `3ee5a11` 与 `project/tests/README.md` §约定。

## 3. 关键决策与理由

| 决策 | 被否掉的备选 | 为什么这么定 |
|---|---|---|
| **MD3 皮肤，而不是换框架** | Materialize 1.0 / MDB UI Kit 9 / `@material/web` | Materialize 与 Bootstrap 的栅格和工具类不兼容——模板里 116 个去重 class 中的 `col-md-*` / `d-flex` / `justify-*` / `g-*` 会全部失效，等于重写 13 个模板；MDB 9 是商业版；`@material/web` 需要 ESM importmap。换皮肤只动 CSS，**38 条测试零影响** |
| **二级菜单用原生 Bootstrap modal** | 内联 `<details>` 展开 | 用户明确要求「以新页面内窗口的形式弹出」；`<details>` 展开会把下方卡片整体顶下去，同屏只能看一个饮品。modal 仍然渲染在 `<form>` 内，**提交契约一条没改** |
| **杯型用 `<select>` 不是 radio** | 每杯型一个 radio | 表单是**平行列表**契约（`product_id` / `cup_spec_id` / `sugar_spec_id` / `ice_spec_id` / `qty` 按下标对齐），同名 radio 会跨商品互斥，破坏对齐 |
| **购物车状态存在对话框的 `qty` select 上** | JS 内存里另存一份购物车数组 | 不制造第二份真相：渲染购物车时读的、提交给后端的，都是同一批控件。好处是**没有 JS 也能正常下单**，JS 只是增强 |
| **折叠区统一成 `.fold-*`** | 各页各写一套 | 先给订单页写了 `.history-*`，制作台/库管台复用时要改名 → 统一成通用类名，后面再加折叠区直接照抄 |
| **图表 vendored Chart.js 4.4.1** | CDN / ECharts | 与 Bootstrap、Bootstrap Icons、Roboto 一样**离线可用、无 CDN、无构建步骤**；ECharts 体积是它的 3 倍，这里只要两张图 |
| **库管台按「需处理程度」排序** | 按 `ingredient_id` 排序 | 展开 60 行时第一屏应该是要动手的：停用 → 手工沽清 → 低于补货点 → 正常 |
| **数字只在有含义时出现** | 沽清时也显示可做杯数 | 某饮品原料沽清时，那个「49 杯」是做不出来的，属于误导；改为只显示「原料沽清」徽章 |

## 4. 过程中发现并修掉的问题（六条，都不是「看起来不好看」）

1. **店长台商品档案表被压扁**：编辑表单原本塞在「名称」单元格里，保存按钮竖排换行、状态 select 被挤成窄条。改为「名称/单价/状态」只读文本列 + 编辑表单整体挪进「操作」列。
2. **库管台补货预警表整列空白**：模板用 `a[12]` 取 `alert_level`，但 `stock_dao.list_alerts` 只 SELECT 了 11 列（索引 0..10）——Jinja 拿到 `Undefined`，静默渲染空白。实测视图 `vw_ingredient_reorder_alert` 有 14 列，`alert_level` 是第 13 列（索引 9）。同时该查询没过滤 `alert_priority = 5`（库存健康）的 55 行，全混在「低于补货点」标题下 → 加 `WHERE alert_priority < 5`。
3. **403 页错误条渲染两次**：`base.html` 的 `{% if error %}` 与 `error.html` 各渲染一次；`error` 变量只在渲染 `error.html` 时传入，base 那块是纯重复。
4. **`GET /order` 返回 500 而不是 405**：`@app.errorhandler(Exception)` 把 `HTTPException` 也兜住了，方法不允许被翻译成「服务器内部错误」。新增 `@app.errorhandler(HTTPException)`，按 `exc.name` 生成 code 并渲染错误页。
5. **购物车面板只露出 2 行**：`.cart-sheet` 的 `height/max-height` 被 Bootstrap 的 `.offcanvas.offcanvas-bottom`（优先级 0,2,0，写死 30vh）压住 → 选择器改成 `.offcanvas.cart-sheet` + `height:auto; max-height:74vh`。
6. **Jinja `Unexpected end of template … 'endblock'`**：用脚本给 `manager.html` 加 `{% block scripts %}` 时把 content 块的 `{% endblock %}` 顶掉了，`/manager` 直接 500。

## 5. 验证记录

```powershell
# 应用测试（结构 + 权限 + 四个工作台）
cd project\app; python -m pytest -q            # 38 passed

# 数据库回归（14 项断言）
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -d milktea_shop -i ..\tests\regression.sql
# 🎉 14 项断言全部通过（TC-10 打印：种子口径 1926 单 / 23762.00 元；运行期新增 2 单 / 8.00 元，不参与断言）

# 从零重建
sqlcmd -S .\SQLEXPRESS -E -C -b -f 65001 -i project\sql\99-rebuild.sql   # exit=0
```

| 角色 | 自己的入口 | 越权（应 403） |
|---|---|---|
| 会员 `13800000001` | `/`、`/orders`、`/me` 均 200 | —— |
| 收银员 `E002` | `/cashier` 200 | `/maker`、`/stocker`、`/manager` 均 403 |
| 制作员 `E003` | `/maker` 200 | `/cashier`、`/stocker`、`/manager` 均 403 |
| 库管员 `E005` | `/stocker` 200 | `/cashier`、`/maker`、`/manager` 均 403 |
| 店长 `E001` | 四个工作台全 200 | —— |

页面级自查方式：无头 Edge（`--headless=new`）对登录后取回的 HTML 逐页截图，
人工过一遍间距、对齐、空态、溢出；表单契约用脚本把渲染后的控件序列化后喂回
`_parse_items`，确认 27 张卡 × 5 个字段没有错位。

## 6. 未做与待议

| # | 事项 | 现状 / 待定 |
|---|---|---|
| 1 | 涟漪（ripple）动效、暗色主题 | 未做。前者要 JS 事件委托，后者要另备一套色板，都不影响答辩 |
| 2 | MD3 未覆盖「紧凑表单」 | 工作台表格行内的输入框仍是 Bootstrap 尺寸（`.form-control-sm`），只有登录页与收银台用了 56px 的 filled field；要不要全站统一待定 |
| 3 | ~~趋势图 46 天断档~~ | ✅ **已定案（2026-11-08，方案 B）**：营业日之间只要有缺口，就在横轴插一个浅色占位标签（如 `09-24~11-07`），各序列在占位处填 `None`，`spanGaps: false` 让折线断开——11-08 成为独立的一点，不再连出一条「从 2911 元直坠 12 元」的假折线；tooltip 也过滤掉占位点 |
| 4 | ~~弹窗模式是否推广到工作台~~ | ✅ **已定案（2026-11-08）：不推广**。行内表单是「连续录多行」的正确形态（收货、报损常一次录好几行，表格像 Excel 一样往下填），且当前不依赖 JS 就能提交；真要做弹窗，优先给 `/manager` 的「新建商品」那张独立表单，而不是行内编辑 |
| 5 | `weeks/submissions/v1.0/` 归档 | 仍只有 `.gitkeep`，阶段报告与 `ai_log` 未起稿 |

## 7. 解决记录

- **处理人**：DiSod（AI Agent 落地实施）
- **解决时间**：2026-11-08
- **状态**：视觉重构与六项交互优化全部完成，已合入 `main`；门禁全绿
- **变更说明（逐条对照原始诉求）**：
  - 「把整个项目的 UI 重构成 MD3」→ 采纳，但**采用皮肤方案而不是换组件库**，理由见 §3 第一行；
  - 「点单品后以窗口形式弹出二级菜单」→ 采纳，`<details>` 改 Bootstrap modal；
  - 「底部悬浮栏显示价格，点开显示购物车」→ 采纳，价格栏常驻（有商品才出现），点开是 bottom offcanvas；
  - 「我的订单要有进行中主表格 + 点击才展开的历史」→ 采纳，按 `PENDING/MAKING/READY` 归「进行中」，其余进折叠区；
  - 「制作台还能做几杯太多了」→ 采纳「只列不健康的 + 全量折叠 + 杯型作列」，**没有**做「杯型合并取最小值」（会与菜单页数字打架）。
- **commit 引用**：`a8b75b6`（MD3 视觉层）、`eae7cb6`（点单弹窗）、`e14670b`（价格栏 + 购物车）、`586eb4f`（我的订单）、`3ee5a11`（TC-10 口径）、`708b638`（制作台）、`116957d`（库管台）、`37cb2be`（店长台图表）
- **遗留**：见 §6 —— 第 1、2 条属「已知取舍」（答辩时主动说明原因比补上更有说服力），第 3、4 条已于同日定案（断档断开 / 弹窗不推广），第 5 条（`weeks/submissions/v1.0/` 归档）属于 v1.0 交付清单。
