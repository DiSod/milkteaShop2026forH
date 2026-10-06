# capture.ps1 —— 按 result/README.md 的清单生成 .png + .txt
#
#   powershell -ExecutionPolicy Bypass -File capture.ps1              # 全部 35 张
#   powershell -ExecutionPolicy Bypass -File capture.ps1 -Only 02     # 只跑某一组
#   powershell -ExecutionPolicy Bypass -File capture.ps1 -SkipSource  # 跳过耗时的源脚本，只重渲染
#
# 每个 shot 产出一对文件：<id>.txt（原始输出）+ <id>.png（渲染图）

param(
    [string]$Only = '',
    [switch]$SkipSource
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$localCode = Join-Path $here '..\code'
$projSql   = Join-Path $here '..\..\..\..\project\sql'
if (Test-Path $localCode) {
    $sqlRoot = (Resolve-Path $localCode).Path
} elseif (Test-Path $projSql) {
    $sqlRoot = (Resolve-Path $projSql).Path
} else {
    throw "找不到 SQL 脚本根目录（需存在 ..\code 或 project\sql）"
}
$tmpDir  = Join-Path $env:TEMP ('milktea-cap-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

. (Join-Path $here 'render.ps1')

$script:Ok = 0
$script:Fail = 0
$script:Err = @()

# ============================================================
#  取数
# ============================================================

function Get-Transcript {
    # 跑一个 .sql 脚本文件，返回全部输出行
    param([string]$SqlFile, [string]$Database = 'milktea_shop', [switch]$Delimited)
    $out = Join-Path $tmpDir ([System.IO.Path]::GetFileNameWithoutExtension($SqlFile) + '.out.txt')
    $a = @('-S', '.\SQLEXPRESS', '-E', '-C', '-d', $Database, '-f', '65001', '-i', $SqlFile, '-o', $out)
    if ($Delimited) { $a += @('-W', '-s', '|') }
    Push-Location $sqlRoot
    try { & sqlcmd @a | Out-Null } finally { Pop-Location }
    return @(Get-Content $out -Encoding UTF8 |
             Where-Object { $_ -notmatch '已将数据库上下文|Changed database context' })
}

function Get-Segment {
    # 按起止正则从 transcript 里切一段（含起始行，不含结束行）
    param([string[]]$Lines, [string]$Start, [string]$End)
    $s = -1; $e = $Lines.Count
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($s -lt 0 -and $Lines[$i] -match $Start) { $s = $i; continue }
        if ($s -ge 0 -and $End -and $Lines[$i] -match $End) { $e = $i; break }
    }
    if ($s -lt 0) { return @() }
    return @($Lines[$s..([Math]::Max($s, $e - 1))])
}

function Get-DelimitedTable {
    # 从 transcript 片段里取出 `a|b|c` 形式的结果表（丢弃叙述行与分隔行）
    param([string[]]$Lines)
    $rows = @($Lines | Where-Object { $_ -match '\|' } |
                     Where-Object { $_ -notmatch '^-+(\|-+)+$' -and $_.Trim() -ne '' })
    if ($rows.Count -lt 1) { return @{ Header = @(); Rows = @() } }
    $header = $rows[0] -split '\|'
    $data = @()
    foreach ($l in ($rows | Select-Object -Skip 1)) { $data += ,($l -split '\|') }
    return @{ Header = $header; Rows = $data }
}

# ============================================================
#  出图
# ============================================================

function New-Dir {
    param([string]$Id)
    $d = Split-Path -Parent (Join-Path $here $Id)
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

function Save-Txt {
    param([string]$Id, [string[]]$Lines)
    [System.IO.File]::WriteAllLines((Join-Path $here "$Id.txt"), $Lines, (New-Object System.Text.UTF8Encoding $false))
}

function Show-Result {
    param([string]$Id, [hashtable]$Info)
    Write-Host ("  [OK]   {0,-46} {1} x {2}" -f $Id, $Info.Width, $Info.Height)
    $script:Ok++
}

function Fail-Shot {
    param([string]$Id, [string]$Why)
    Write-Host ("  [FAIL] {0,-46} {1}" -f $Id, $Why)
    $script:Fail++
    $script:Err += "$Id : $Why"
}

# --- 纯 SQL 查询 → 表格图 ---
function Do-TableShot {
    param([string]$Id, [string]$Title, [string]$Sql)
    try {
        New-Dir $Id
        $t = Invoke-SqlTable -Sql $Sql
        if ($t.Header.Count -lt 1) { throw '查询无结果' }
        Save-Txt -Id $Id -Lines (@(($t.Header -join ' | ')) + @($t.Rows | ForEach-Object { $_ -join ' | ' }))
        $info = New-TableImage -Title @($Title) -Header $t.Header -Rows $t.Rows -OutPath (Join-Path $here "$Id.png")
        Show-Result -Id $Id -Info $info
    } catch { Fail-Shot -Id $Id -Why $_.Exception.Message }
}

# --- 一段文本 → 文本图 ---
function Do-TextShot {
    param([string]$Id, [string]$Title, [string[]]$Lines)
    try {
        New-Dir $Id
        if ($Lines.Count -lt 1) { throw '片段为空' }
        Save-Txt -Id $Id -Lines $Lines
        $info = New-TextImage -Title @($Title) -Lines $Lines -OutPath (Join-Path $here "$Id.png")
        Show-Result -Id $Id -Info $info
    } catch { Fail-Shot -Id $Id -Why $_.Exception.Message }
}

# --- transcript 片段 → 文本图 ---
function Do-SegmentTextShot {
    param([string]$Id, [string]$Title, [string[]]$Source, [string]$Start, [string]$End)
    $seg = Get-Segment -Lines $Source -Start $Start -End $End
    if ($seg.Count -lt 1) { Fail-Shot -Id $Id -Why "未匹配到片段 ($Start)"; return }
    Do-TextShot -Id $Id -Title $Title -Lines $seg
}

# --- transcript 片段里的结果表 → 表格图 ---
function Do-SegmentTableShot {
    param([string]$Id, [string]$Title, [string[]]$Source, [string]$Start, [string]$End)
    $seg = Get-Segment -Lines $Source -Start $Start -End $End
    if ($seg.Count -lt 1) { Fail-Shot -Id $Id -Why "未匹配到片段 ($Start)"; return }
    $t = Get-DelimitedTable -Lines $seg
    if ($t.Header.Count -lt 1) { Fail-Shot -Id $Id -Why '片段内没有结果表'; return }
    try {
        New-Dir $Id
        Save-Txt -Id $Id -Lines $seg
        $info = New-TableImage -Title @($Title) -Header $t.Header -Rows $t.Rows -OutPath (Join-Path $here "$Id.png")
        Show-Result -Id $Id -Info $info
    } catch { Fail-Shot -Id $Id -Why $_.Exception.Message }
}

# ============================================================
#  01-build —— 成功建库
# ============================================================
if ($Only -eq '' -or $Only -eq '01') {
    Write-Host ''
    Write-Host '--- 01-build ---'
    $logTxt = Join-Path $here '01-build\rebuild-full-log.txt'
    if (-not $SkipSource) {
        Write-Host '  ... 正在跑 99-rebuild.sql'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Push-Location $sqlRoot
        try { & sqlcmd -S '.\SQLEXPRESS' -E -C -f 65001 -i '99-rebuild.sql' -o $logTxt | Out-Null } finally { Pop-Location }
        Write-Host ("  ... 完成，耗时 {0:N1} 秒" -f $sw.Elapsed.TotalSeconds)
    }
    $log = @(Get-Content $logTxt -Encoding UTF8)
    Do-TextShot -Id '01-build/rebuild-object-summary' -Title 'milktea_shop · 一键重建完成（对象清单汇总）' -Lines @($log | Select-Object -Last 14)
    Do-TextShot -Id '01-build/rebuild-full-log'      -Title 'milktea_shop · 99-rebuild.sql 完整日志'        -Lines $log
    Do-TableShot -Id '01-build/db-settings' -Title 'milktea_shop · 数据库级设置（排序规则 / 兼容级别 / 恢复模式）' -Sql @'
SET NOCOUNT ON;
SELECT name AS 库名, collation_name AS 排序规则,
       compatibility_level AS 兼容级别, recovery_model_desc AS 恢复模式
FROM sys.databases WHERE name = 'milktea_shop';
'@
}

# ============================================================
#  02-crud / 03-invalid —— 源脚本：05-dml/crud.sql
# ============================================================
if ($Only -eq '' -or $Only -eq '02' -or $Only -eq '03') {
    $crudTxt = Join-Path $tmpDir 'crud.out.txt'
    Write-Host ''
    Write-Host '  ... 正在跑 05-dml/crud.sql（带 -s "|" 取分隔符格式）'
    Push-Location $sqlRoot
    try { & sqlcmd -S '.\SQLEXPRESS' -E -C -d milktea_shop -W -s '|' -f 65001 -i '05-dml\crud.sql' -o $crudTxt | Out-Null } finally { Pop-Location }
    $crud = @(Get-Content $crudTxt -Encoding UTF8)

    if ($Only -eq '' -or $Only -eq '02') {
        Write-Host ''
        Write-Host '--- 02-crud ---'
        Do-SegmentTextShot  -Id '02-crud/crud-create-member'    -Title 'CRUD · CREATE —— 新增会员（1.2）'                       -Source $crud -Start '【CRUD】1\.2 CREATE' -End '【CRUD】1\.3 CREATE'
        Do-SegmentTextShot  -Id '02-crud/crud-create-order'     -Title 'CRUD · CREATE —— 开单 + 反冲倒扣（1.5—1.6）'            -Source $crud -Start '【CRUD】1\.5 CREATE' -End '【CRUD】1\.7 CREATE'
        Do-SegmentTableShot -Id '02-crud/crud-read-menu'        -Title 'CRUD · READ —— 商品菜单（2.1）'                         -Source $crud -Start '【CRUD】2\.1 READ'   -End '【CRUD】2\.2 READ'
        Do-SegmentTableShot -Id '02-crud/crud-read-order-full'  -Title 'CRUD · READ —— 订单全貌（2.3）'                         -Source $crud -Start '【CRUD】2\.3 READ'   -End '【CRUD】2\.4 READ'
        Do-SegmentTableShot -Id '02-crud/crud-read-ledger'      -Title 'CRUD · READ —— 台账按类型汇总并反推期初（2.5）'           -Source $crud -Start '【CRUD】2\.5 READ'   -End '【CRUD】3\.1 UPDATE'
        Do-SegmentTableShot -Id '02-crud/crud-update-price'     -Title 'CRUD · UPDATE —— 商品调价（3.1）'                       -Source $crud -Start '【CRUD】3\.1 UPDATE' -End '【CRUD】3\.2 UPDATE'
        Do-SegmentTextShot  -Id '02-crud/crud-update-offsale'   -Title 'CRUD · UPDATE —— 下架改状态，历史订单不受影响（3.2）'     -Source $crud -Start '【CRUD】3\.2 UPDATE' -End '【CRUD】3\.3 UPDATE'
        Do-SegmentTextShot  -Id '02-crud/crud-update-state'     -Title 'CRUD · UPDATE —— 订单状态机流转（3.3）'                  -Source $crud -Start '【CRUD】3\.3 UPDATE' -End '【CRUD】3\.4 UPDATE'
        Do-SegmentTextShot  -Id '02-crud/crud-delete-ok'        -Title 'CRUD · DELETE —— 删除无引用会员，成功（4.1）'             -Source $crud -Start '【CRUD】4\.1 DELETE' -End '【CRUD】4\.2 DELETE'
        Do-SegmentTextShot  -Id '02-crud/crud-delete-blocked'   -Title 'CRUD · DELETE —— 删除有引用商品，被外键拒绝（4.2）'        -Source $crud -Start '【CRUD】4\.2 DELETE' -End '【CRUD】步骤 5'
    }

    if ($Only -eq '' -or $Only -eq '03') {
        Write-Host ''
        Write-Host '--- 03-invalid（5 个负例各自独立 + 1 张汇总）---'
        $seg17 = Get-Segment -Lines $crud -Start '【CRUD】1\.7 CREATE 负例' -End '【CRUD】2\.1 READ'
        $titles = @{
            1 = '非法数据被拒绝 · 负例 1 —— 库存为负（ck_ingredient_qty_on_hand）'
            2 = '非法数据被拒绝 · 负例 2 —— 员工岗位非法枚举（ck_employee_position）'
            3 = '非法数据被拒绝 · 负例 3 —— 配方引用不存在的商品（fk_recipe_product）'
            4 = '非法数据被拒绝 · 负例 4 —— 会员号重复（uq_member_code 候选码）'
            5 = '非法数据被拒绝 · 负例 5 —— 流水判别列与真外键不一致（ck_stock_ledger_ref_consistency）'
        }
        for ($k = 1; $k -le 5; $k++) {
            $line = @($seg17 | Where-Object { $_ -match "负例$k 被拒绝|负例 $k 被拒绝" })
            if ($line.Count -lt 1) { Fail-Shot -Id ("03-invalid/neg-{0}" -f $k) -Why '未找到该负例的输出行'; continue }
            Do-TextShot -Id ("03-invalid/neg-{0}" -f $k) -Title $titles[$k] -Lines $line
        }
        Do-TextShot -Id '03-invalid/neg-all-five' -Title 'milktea_shop · 非法数据被拒绝 —— 5 个负例汇总（均由约束拦截）' -Lines $seg17
    }
}

# ============================================================
#  04-query —— 源脚本：06-query/query.sql
# ============================================================
if ($Only -eq '' -or $Only -eq '04') {
    $qTxt = Join-Path $tmpDir 'query.out.txt'
    Write-Host ''
    Write-Host '  ... 正在跑 06-query/query.sql（带 -s "|"）'
    Push-Location $sqlRoot
    try { & sqlcmd -S '.\SQLEXPRESS' -E -C -d milktea_shop -W -s '|' -f 65001 -i '06-query\query.sql' -o $qTxt | Out-Null } finally { Pop-Location }
    $q = @(Get-Content $qTxt -Encoding UTF8)
    Write-Host ''
    Write-Host '--- 04-query ---'
    Do-SegmentTableShot -Id '04-query/q1-supply-chain-4level'   -Title '查询 Q1 · 供应链四层级联穿透与入库追溯（跨 6 表）' -Source $q -Start '=== Q1：'        -End '=== Q2a：'
    Do-SegmentTableShot -Id '04-query/q2a-topping-penetration'  -Title '查询 Q2a · 单品加料渗透率与小料增收贡献'          -Source $q -Start '=== Q2a：'       -End '=== Q2b：'
    Do-SegmentTableShot -Id '04-query/q2b-sugar-ice-preference' -Title '查询 Q2b · 全店甜度与冰度组合偏好热度分布'        -Source $q -Start '=== Q2b：'       -End '=== Q3：'
    Do-SegmentTableShot -Id '04-query/q3-category-sales-rank'   -Title '查询 Q3 · 品类与单品销售总榜（窗口函数）'          -Source $q -Start '=== Q3：'        -End '=== Q4：'
    Do-SegmentTableShot -Id '04-query/q4-ledger-balance'        -Title '查询 Q4 · 进销存台账自洽平衡审计'                  -Source $q -Start '=== Q4：进销存'   -End '=== Q4 汇总断言'
    Do-SegmentTableShot -Id '04-query/q4-balance-assertion'     -Title '查询 Q4 断言 · 全库 60 种原料零差额'               -Source $q -Start '=== Q4 汇总断言' -End '第 4 周多表连接查询实战脚本执行完毕'
}

# ============================================================
#  05-view —— 5 个统计视图
# ============================================================
if ($Only -eq '' -or $Only -eq '05') {
    Write-Host ''
    Write-Host '--- 05-view ---'
    Do-TableShot -Id '05-view/view-product-availability' -Title '统计视图 · vw_product_stock_availability（还能做几杯）' -Sql @'
SET NOCOUNT ON;
SELECT TOP 12 product_name AS 成品, cup_spec_name AS 杯型, selling_price AS 售价,
       theor_makeable_cups AS 还能做几杯, sale_status AS 在售状态
FROM vw_product_stock_availability
WHERE product_name NOT LIKE N'演示%'
ORDER BY theor_makeable_cups, product_name;
'@
    Do-TableShot -Id '05-view/view-ingredient-reorder-alert' -Title '统计视图 · vw_ingredient_reorder_alert（缺料与采购预警）' -Sql @'
SET NOCOUNT ON;
SELECT TOP 12 ingredient_name AS 原料, unit AS 单位, qty_on_hand AS 在手,
       reorder_point AS 补货点, target_level AS 目标水位
FROM vw_ingredient_reorder_alert ORDER BY qty_on_hand;
'@
    Do-TableShot -Id '05-view/view-daily-business-summary' -Title '统计视图 · vw_daily_business_summary（每日经营日报）' -Sql @'
SET NOCOUNT ON;
SELECT business_date AS 营业日, total_orders AS 总单数, completed_orders AS 完成,
       cancelled_orders AS 取消, total_cups AS 总杯数,
       gross_sales AS 流水, net_revenue AS 实收, avg_order_amount AS 客单价
FROM vw_daily_business_summary ORDER BY business_date;
'@
    Do-TableShot -Id '05-view/view-member-consumption-profile' -Title '统计视图 · vw_member_consumption_profile（会员消费画像与分级）' -Sql @'
SET NOCOUNT ON;
SELECT TOP 12 member_code AS 会员号, member_name AS 姓名, member_level AS 等级,
       order_count AS 订单数, total_paid AS 累计消费
FROM vw_member_consumption_profile ORDER BY total_paid DESC;
'@
    Do-TableShot -Id '05-view/view-order-detail-full' -Title '统计视图 · vw_order_detail_full（订单全景明细 · 宽表节选）' -Sql @'
SET NOCOUNT ON;
SELECT TOP 10 order_no AS 订单号, business_date AS 营业日, order_status AS 状态,
       customer_name AS 顾客, category_name AS 品类, product_name AS 成品,
       cup_spec AS 杯型, sugar_spec AS 糖度, topping_summary AS 加料,
       qty AS 数量, subtotal AS 小计, order_amount_paid AS 实付
FROM vw_order_detail_full ORDER BY business_date DESC, order_no, line_no;
'@
}

# ============================================================
#  06-security —— 源脚本：08-security/role.sql
# ============================================================
if ($Only -eq '' -or $Only -eq '06') {
    Write-Host ''
    Write-Host '--- 06-security ---'
    Do-TableShot -Id '06-security/role-permission-matrix' -Title '安全 · 4 岗位 RBAC 赋权矩阵' -Sql @'
SET NOCOUNT ON;
SELECT r.name AS 角色, ISNULL(OBJECT_NAME(p.major_id), N'(数据库级)') AS 对象, p.permission_name AS 权限
FROM sys.database_permissions p
JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
WHERE r.name LIKE 'role[_]%'
ORDER BY r.name, 对象, 权限;
'@
    Do-TableShot -Id '06-security/role-member-roles' -Title '安全 · 角色与测试主体绑定（WITHOUT LOGIN，不污染服务器登录）' -Sql @'
SET NOCOUNT ON;
SELECT r.name AS 角色, m.name AS 测试主体, m.type_desc AS 类型
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name LIKE 'role[_]%' OR r.name = 'db_owner'
ORDER BY r.name;
'@

    $roleTxt = Join-Path $tmpDir 'role.out.txt'
    Write-Host '  ... 正在跑 08-security/role.sql'
    Push-Location $sqlRoot
    try { & sqlcmd -S '.\SQLEXPRESS' -E -C -d milktea_shop -f 65001 -i '08-security\role.sql' -o $roleTxt | Out-Null } finally { Pop-Location }
    $role = @(Get-Content $roleTxt -Encoding UTF8)
    Do-SegmentTextShot -Id '06-security/neg-1-cashier-alter-recipe' -Title '越权拦截 · 负例 1 —— 收银员篡改配方表 tbl_recipe'      -Source $role -Start '【负例 1】' -End '【负例 2】'
    Do-SegmentTextShot -Id '06-security/neg-2-maker-read-member'    -Title '越权拦截 · 负例 2 —— 制作员窥探会员隐私表 tbl_member'   -Source $role -Start '【负例 2】' -End '【负例 3】'
    Do-SegmentTextShot -Id '06-security/neg-3-stocker-delete-order' -Title '越权拦截 · 负例 3 —— 库管员删除订单单头 tbl_order_header' -Source $role -Start '【负例 3】' -End '【安全】=== 数据库自定义角色权限清单汇总'
    Do-SegmentTextShot -Id '06-security/role-allow-vs-deny'         -Title '越权拦截 · 3 组负例全部被 Error 229 拦截（汇总）'        -Source $role -Start '=== 开始执行 3 组越权拦截负例测试' -End '第 4 周 RBAC 权限体系与越权拦截负例测试全部通过'
}

Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ("=== 完成：成功 {0} 张，失败 {1} 张 ===" -f $script:Ok, $script:Fail)
if ($script:Err.Count) { Write-Host '--- 失败明细 ---'; $script:Err | ForEach-Object { Write-Host ("  " + $_) } }
if ($script:Fail -gt 0) { exit 1 }
