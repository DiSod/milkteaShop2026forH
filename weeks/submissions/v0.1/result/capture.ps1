# capture.ps1 —— 按 result/README.md 的清单生成本目录的 .png + .txt
#
#   powershell -ExecutionPolicy Bypass -File capture.ps1            # 全部
#   powershell -ExecutionPolicy Bypass -File capture.ps1 -Only 01  # 只跑某一组
#   powershell -ExecutionPolicy Bypass -File capture.ps1 -NoSql    # 只重渲染已有的 .txt
#
# 每个 shot 产出一对文件：<id>.txt（原始输出）+ <id>.png（渲染图）

param(
    [string]$Only = '',
    [switch]$NoSql
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'render.ps1')

$script:Ok = 0
$script:Fail = 0

function Write-Shot {
    param(
        [string]$Id,          # 相对路径，如 '01-build/rebuild-object-summary'
        [string]$Title,       # 图上标题
        [ValidateSet('Table', 'Text')] [string]$Mode,
        [string]$Sql,         # 要跑的 SQL
        [string]$SourceFile   # 或者：跑一个已有的 .sql 脚本文件
    )
    $base = Join-Path $here $Id
    $dir  = Split-Path -Parent $base
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $txtPath = "$base.txt"
    $pngPath = "$base.png"

    try {
        if (-not $NoSql) {
            $lines = Invoke-SqlText -Sql $Sql
            [System.IO.File]::WriteAllLines($txtPath, $lines, (New-Object System.Text.UTF8Encoding $false))
        } else {
            $lines = Get-Content $txtPath -Encoding UTF8
        }

        if ($Mode -eq 'Table') {
            $t = Invoke-SqlTable -Sql $Sql
            $info = New-TableImage -Title @($Title) -Header $t.Header -Rows $t.Rows -OutPath $pngPath
        } else {
            $info = New-TextImage -Title @($Title) -Lines $lines -OutPath $pngPath
        }
        Write-Host ("  [OK]   {0,-46} {1} x {2}" -f $Id, $info.Width, $info.Height)
        $script:Ok++
    } catch {
        Write-Host ("  [FAIL] {0,-46} {1}" -f $Id, $_.Exception.Message)
        $script:Fail++
    }
}

# ============================================================
#  01-build —— 成功建库
# ============================================================
if ($Only -eq '' -or $Only -eq '01') {
    Write-Host ''
    Write-Host '--- 01-build ---'

    # 先跑一遍一键重建，把完整日志落成 txt（后面几张图共用）
    $rebuildTxt = Join-Path $here '01-build\rebuild-full-log.txt'
    if (-not $NoSql) {
        Write-Host '  ... 正在跑 99-rebuild.sql（约 15—17 秒）'
        $sqlDir = Join-Path $here '..\..\..\..\project\sql'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Push-Location $sqlDir
        $raw = & sqlcmd -S '.\SQLEXPRESS' -E -C -f 65001 -i '99-rebuild.sql' -o $rebuildTxt 2>&1
        Pop-Location
        $sw.Stop()
        Write-Host ("  ... 完成，耗时 {0:N1} 秒" -f $sw.Elapsed.TotalSeconds)
    }
    $log = Get-Content $rebuildTxt -Encoding UTF8
    # 汇总块在末尾 12 行
    $tail = $log | Select-Object -Last 12
    $info = New-TextImage -Title @('milktea_shop · 一键重建完成（对象清单汇总）') -Lines $tail -OutPath (Join-Path $here '01-build\rebuild-object-summary.png')
    Write-Host ("  [OK]   {0,-46} {1} x {2}" -f '01-build/rebuild-object-summary', $info.Width, $info.Height)
    $script:Ok++
    # 完整日志图
    $info2 = New-TextImage -Title @('milktea_shop · 99-rebuild.sql 完整日志') -Lines $log -OutPath (Join-Path $here '01-build\rebuild-full-log.png')
    Write-Host ("  [OK]   {0,-46} {1} x {2}" -f '01-build/rebuild-full-log', $info2.Width, $info2.Height)
    $script:Ok++

    # 数据库设置（表格）
    Write-Shot -Id '01-build/db-settings' -Title 'milktea_shop · 数据库级设置' -Mode Table -Sql @'
SET NOCOUNT ON;
SELECT name AS 库名, collation_name AS 排序规则,
       compatibility_level AS 兼容级别, recovery_model_desc AS 恢复模式
FROM sys.databases WHERE name = 'milktea_shop';
'@
}

# ============================================================
#  03-invalid —— 非法数据被拒绝
# ============================================================
if ($Only -eq '' -or $Only -eq '03') {
    Write-Host ''
    Write-Host '--- 03-invalid ---'
    Write-Host '  ... 正在跑 05-dml/crud.sql（取其中的负例段）'
    $crudTxt = Join-Path $here '03-invalid\_crud-raw.txt'
    if (-not $NoSql) {
        $sqlDir = Join-Path $here '..\..\..\..\project\sql'
        Push-Location $sqlDir
        & sqlcmd -S '.\SQLEXPRESS' -E -C -d milktea_shop -f 65001 -i '05-dml\crud.sql' -o $crudTxt 2>&1 | Out-Null
        Pop-Location
    }
    $cl = Get-Content $crudTxt -Encoding UTF8
    # 截取「1.7 负例」到「2.」之间的段落
    $s = ($cl | Select-String -Pattern '1\.7 CREATE 负例' | Select-Object -First 1).LineNumber
    $e = ($cl | Select-String -Pattern '【CRUD】2\.' | Select-Object -First 1).LineNumber
    if ($s -and $e -and $e -gt $s) { $seg = $cl[($s-1)..($e-2)] } else { $seg = $cl | Select-Object -First 40 }
    [System.IO.File]::WriteAllLines((Join-Path $here '03-invalid\neg-all-five.txt'), $seg, (New-Object System.Text.UTF8Encoding $false))
    $info = New-TextImage -Title @('milktea_shop · 非法数据被拒绝（5 个负例，均由约束拦截）') -Lines $seg -OutPath (Join-Path $here '03-invalid\neg-all-five.png')
    Write-Host ("  [OK]   {0,-46} {1} x {2}" -f '03-invalid/neg-all-five', $info.Width, $info.Height)
    $script:Ok++
    Remove-Item $crudTxt -Force -ErrorAction SilentlyContinue
}

# ============================================================
#  05-view —— 统计视图
# ============================================================
if ($Only -eq '' -or $Only -eq '05') {
    Write-Host ''
    Write-Host '--- 05-view ---'
    Write-Shot -Id '05-view/view-product-availability' -Title 'milktea_shop · vw_product_stock_availability（还能做几杯）' -Mode Table -Sql @'
SET NOCOUNT ON;
SELECT TOP 12 product_name AS 成品, cup_spec_name AS 杯型, selling_price AS 售价,
       theor_makeable_cups AS 还能做几杯, sale_status AS 在售状态
FROM vw_product_stock_availability ORDER BY theor_makeable_cups;
'@
    Write-Shot -Id '05-view/view-ingredient-reorder-alert' -Title 'milktea_shop · vw_ingredient_reorder_alert（缺料预警）' -Mode Table -Sql @'
SET NOCOUNT ON;
SELECT TOP 12 ingredient_name AS 原料, unit AS 单位, qty_on_hand AS 在手,
       reorder_point AS 补货点, target_level AS 目标水位
FROM vw_ingredient_reorder_alert ORDER BY qty_on_hand;
'@
}

# ============================================================
#  06-security —— 越权拦截
# ============================================================
if ($Only -eq '' -or $Only -eq '06') {
    Write-Host ''
    Write-Host '--- 06-security ---'
    Write-Shot -Id '06-security/role-permission-matrix' -Title 'milktea_shop · 4 岗位 RBAC 赋权矩阵' -Mode Table -Sql @'
SET NOCOUNT ON;
SELECT r.name AS 角色, ISNULL(OBJECT_NAME(p.major_id), N'(数据库级)') AS 对象,
       p.permission_name AS 权限
FROM sys.database_permissions p
JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
WHERE r.name LIKE 'role[_]%'
ORDER BY r.name, 对象, 权限;
'@
}

Write-Host ''
Write-Host ("=== 完成：成功 {0} 张，失败 {1} 张 ===" -f $script:Ok, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
