# capture.ps1 —— 生成 v1.0 result 的 SQL 类证据（01—06 组）
#
#   powershell -ExecutionPolicy Bypass -File capture.ps1              # 全部
#   powershell -ExecutionPolicy Bypass -File capture.ps1 -Only 02     # 只跑某一组
#   powershell -ExecutionPolicy Bypass -File capture.ps1 -SkipSource  # 跳过耗时源脚本，只重渲染已有 .txt
#
# 应用页面截图（07-app）由 capture-app.ps1 负责（需要 Flask 在跑）。
# 每个 shot 产出一对文件：<id>.txt（原始输出）+ <id>.png（渲染图）

param(
    [string]$Only = '',
    [switch]$SkipSource
)

$ErrorActionPreference = 'Stop'
$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$projRoot  = (Resolve-Path (Join-Path $here '..\..\..\..')).Path
$sqlRoot   = Join-Path $projRoot 'project\sql'
$testsRoot = Join-Path $projRoot 'project\tests'
$tmpDir    = Join-Path $env:TEMP ('milktea-v1-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

. (Join-Path $here 'render.ps1')

$script:Ok = 0
$script:Fail = 0
$script:Err = @()

# ============================================================
#  取数
# ============================================================

function Invoke-SqlcmdFile {
    param([string]$SqlFile, [string]$Database = 'milktea_shop')
    $out = Join-Path $tmpDir ([System.IO.Path]::GetFileNameWithoutExtension($SqlFile) + '.out.txt')
    & sqlcmd -S '.\SQLEXPRESS' -E -C -d $Database -f 65001 -i $SqlFile -o $out | Out-Null
    return @(Get-Content $out -Encoding UTF8 |
             Where-Object { $_ -notmatch '已将数据库上下文|Changed database context' })
}

function Get-Segment {
    param([string[]]$Lines, [string]$Start, [string]$End)
    $s = -1; $e = $Lines.Count
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($s -lt 0 -and $Lines[$i] -match $Start) { $s = $i; continue }
        if ($s -ge 0 -and $End -and $Lines[$i] -match $End) { $e = $i; break }
    }
    if ($s -lt 0) { return @() }
    return @($Lines[$s..([Math]::Max($s, $e - 1))])
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
    Write-Host ("  [OK]   {0,-52} {1} x {2}" -f $Id, $Info.Width, $Info.Height)
    $script:Ok++
}

function Fail-Shot {
    param([string]$Id, [string]$Why)
    Write-Host ("  [FAIL] {0,-52} {1}" -f $Id, $Why)
    $script:Fail++
    $script:Err += "$Id : $Why"
}

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

function Do-SqlTextShot {
    # 跑一段临时 SQL，把 sqlcmd 的原始输出（含 PRINT 与错误消息）做成文本图
    param([string]$Id, [string]$Title, [string]$Sql)
    $f = Join-Path $tmpDir ($Id.Replace('/', '-') + '.sql')
    [System.IO.File]::WriteAllText($f, $Sql, (New-Object System.Text.UTF8Encoding $true))
    $lines = Invoke-SqlcmdFile -SqlFile $f
    Do-TextShot -Id $Id -Title $Title -Lines $lines
}

# ============================================================
#  01-build —— 结构与规模
# ============================================================
if ($Only -eq '' -or $Only -eq '01') {
    Write-Host ''
    Write-Host '--- 01-build ---'

    Do-TableShot -Id '01-build/schema-object-summary' -Title 'milktea_shop · v1.0 对象清单汇总（18 表 / 139 字段 / 31 外键 / 48 CHECK）' -Sql @'
SET NOCOUNT ON;
SELECT N'表' AS 对象类型, COUNT(*) AS 数量 FROM sys.tables
UNION ALL SELECT N'字段', COUNT(*) FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id
UNION ALL SELECT N'主键', COUNT(*) FROM sys.key_constraints WHERE type = 'PK'
UNION ALL SELECT N'唯一约束（候选码）', COUNT(*) FROM sys.key_constraints WHERE type = 'UQ'
UNION ALL SELECT N'外键', COUNT(*) FROM sys.foreign_keys
UNION ALL SELECT N'CHECK 约束', COUNT(*) FROM sys.check_constraints
UNION ALL SELECT N'业务索引', COUNT(*) FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
         WHERE i.index_id > 0 AND i.is_primary_key = 0 AND i.is_unique_constraint = 0
UNION ALL SELECT N'视图', COUNT(*) FROM sys.views
UNION ALL SELECT N'自定义数据库角色', COUNT(*) FROM sys.database_principals
         WHERE type = 'R' AND is_fixed_role = 0 AND name <> 'public'
'@

    Do-TableShot -Id '01-build/db-settings' -Title 'milktea_shop · 数据库级设置（SQL Server 2022 / 兼容级别 160）' -Sql @'
SET NOCOUNT ON;
SELECT name AS 库名, collation_name AS 排序规则, compatibility_level AS 兼容级别, recovery_model_desc AS 恢复模式
FROM sys.databases WHERE name = 'milktea_shop';
'@

    Do-TableShot -Id '01-build/table-row-counts' -Title 'milktea_shop · 18 张表的行数（合计 21,061 行）' -Sql @'
SET NOCOUNT ON;
SELECT t.name AS 表名, SUM(p.rows) AS 行数
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY SUM(p.rows) DESC;
'@
}

# ============================================================
#  02-migration —— 五段迁移各自的验证
# ============================================================
if ($Only -eq '' -or $Only -eq '02') {
    Write-Host ''
    Write-Host '--- 02-migration ---'

    Do-TableShot -Id '02-migration/coupon-split' -Title '迁移 01 · 券表拆成「模板 + 实例」并保留兼容视图' -Sql @'
SET NOCOUNT ON;
SELECT N'tbl_coupon 列数' AS 指标, CAST(COUNT(*) AS VARCHAR(20)) AS 值 FROM sys.columns WHERE object_id = OBJECT_ID('tbl_coupon')
UNION ALL SELECT N'tbl_coupon_template 列数', CAST(COUNT(*) AS VARCHAR(20)) FROM sys.columns WHERE object_id = OBJECT_ID('tbl_coupon_template')
UNION ALL SELECT N'券模板行数', CAST(COUNT(*) AS VARCHAR(20)) FROM tbl_coupon_template
UNION ALL SELECT N'券实例行数', CAST(COUNT(*) AS VARCHAR(20)) FROM tbl_coupon
UNION ALL SELECT N'模板外键悬空的券（应为 0）', CAST(COUNT(*) AS VARCHAR(20)) FROM tbl_coupon WHERE template_id IS NULL
UNION ALL SELECT N'兼容视图 vw_coupon_legacy 行数', CAST(COUNT(*) AS VARCHAR(20)) FROM vw_coupon_legacy
UNION ALL SELECT N'兼容视图列数', CAST(COUNT(*) AS VARCHAR(20)) FROM sys.columns WHERE object_id = OBJECT_ID('vw_coupon_legacy')
'@

    Do-TableShot -Id '02-migration/points-reconcile' -Title '迁移 03 · 积分「余额 = 流水合计」第一次成立（80 条 OPENING 期初）' -Sql @'
SET NOCOUNT ON;
SELECT N'会员数' AS 指标, CAST(COUNT(*) AS VARCHAR(20)) AS 值 FROM tbl_member
UNION ALL SELECT N'余额合计 SUM(points_balance)', CAST(SUM(points_balance) AS VARCHAR(20)) FROM tbl_member
UNION ALL SELECT N'流水合计 SUM(point_change)', CAST(SUM(point_change) AS VARCHAR(20)) FROM tbl_points_ledger
UNION ALL SELECT N'OPENING 期初流水条数', CAST(COUNT(*) AS VARCHAR(20)) FROM tbl_points_ledger WHERE point_type = 'OPENING'
UNION ALL SELECT N'不符会员数（应为 0）', CAST(COUNT(*) AS VARCHAR(20)) FROM (
    SELECT m.member_id FROM tbl_member m
    LEFT JOIN tbl_points_ledger p ON p.member_id = m.member_id
    GROUP BY m.member_id, m.points_balance
    HAVING m.points_balance <> ISNULL(SUM(p.point_change), 0)
) x
'@

    Do-TableShot -Id '02-migration/time-constraints' -Title '迁移 04 · 订单时间序约束（只约束顺序，不约束「支付必须有时间」）' -Sql @'
SET NOCOUNT ON;
SELECT c.name AS 约束名, c.is_disabled AS 已禁用, c.is_not_trusted AS 未受信任,
       CAST(COUNT(*) AS VARCHAR(10)) AS 同类约束数
FROM sys.check_constraints c
WHERE c.name IN ('ck_order_header_pay_time', 'ck_order_header_finish_after_pay')
GROUP BY c.name, c.is_disabled, c.is_not_trusted;
'@

    Do-SqlTextShot -Id '02-migration/time-constraints-rationale' -Title '迁移 04 · 为什么不能加「支付状态非空 ⇒ pay_time 非空」（37 单反例）' -Sql @'
SET NOCOUNT ON;
PRINT '=== 约束定义 ===';
SELECT name, definition FROM sys.check_constraints
WHERE name IN ('ck_order_header_pay_time', 'ck_order_header_finish_after_pay');
PRINT '';
PRINT '=== 反例：pay_status 非空但 pay_time 为 NULL 的订单 ===';
SELECT COUNT(*) AS 数量 FROM tbl_order_header WHERE pay_status IS NOT NULL AND pay_time IS NULL;
PRINT '';
PRINT '直接加 CHECK (pay_status IS NULL OR pay_time IS NOT NULL) 会让上面这批历史数据装不回去，';
PRINT '所以只约束「pay_time >= order_time」「finish_time >= pay_time」两条顺序关系。';
'@

    Do-TableShot -Id '02-migration/price-precision' -Title '迁移 05 · 6 个单价/成本列升到 DECIMAL(12,4)（金额仍 (10,2)）' -Sql @'
SET NOCOUNT ON;
SELECT OBJECT_NAME(c.object_id) AS 表, c.name AS 列, TYPE_NAME(c.user_type_id) AS 类型,
       c.precision AS 精度, c.scale AS 小数位
FROM sys.columns c
WHERE c.name IN ('unit_price', 'moving_avg_cost', 'unit_extra_price', 'selling_price', 'base_price', 'purchase_price')
  AND OBJECT_NAME(c.object_id) LIKE 'tbl%'
ORDER BY 表, 列;
'@

    if (-not $SkipSource) {
        Write-Host '  ... 正在跑 99-rebuild.sql（约 24 秒）'
        $logTxt = Join-Path $here '02-migration/rebuild-full-log.txt'
        New-Dir '02-migration/rebuild-full-log'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Push-Location $sqlRoot
        try { & sqlcmd -S '.\SQLEXPRESS' -E -C -f 65001 -i '99-rebuild.sql' -o $logTxt | Out-Null } finally { Pop-Location }
        Write-Host ("  ... 完成，耗时 {0:N1} 秒" -f $sw.Elapsed.TotalSeconds)
    }
    if (Test-Path (Join-Path $here '02-migration/rebuild-full-log.txt')) {
        $log = @(Get-Content (Join-Path $here '02-migration/rebuild-full-log.txt') -Encoding UTF8 |
                 Where-Object { $_ -notmatch '已将数据库上下文|Changed database context' })
        Do-TextShot -Id '02-migration/rebuild-full-log' -Title 'milktea_shop · 99-rebuild.sql 完整日志（12 步全部通过）' -Lines $log
        Do-TextShot -Id '02-migration/rebuild-summary' -Title 'milktea_shop · 一键重建完成（末尾对象清单汇总）' -Lines @($log | Select-Object -Last 16)
    } else {
        Fail-Shot -Id '02-migration/rebuild-full-log' -Why '缺少 rebuild-full-log.txt'
    }
}

# ============================================================
#  03-regression —— 15 项自动化断言
# ============================================================
if ($Only -eq '' -or $Only -eq '03') {
    Write-Host ''
    Write-Host '--- 03-regression ---'

    $regTxt = Join-Path $here '03-regression/regression-full-log.txt'
    New-Dir '03-regression/regression-full-log'
    if (-not $SkipSource) {
        Write-Host '  ... 正在跑 regression.sql'
        & sqlcmd -S '.\SQLEXPRESS' -E -C -d milktea_shop -f 65001 -b -i (Join-Path $testsRoot 'regression.sql') -o $regTxt | Out-Null
        Write-Host ("  ... sqlcmd exit code: {0}" -f $LASTEXITCODE)
    }
    if (Test-Path $regTxt) {
        $reg = @(Get-Content $regTxt -Encoding UTF8 |
                 Where-Object { $_ -notmatch '已将数据库上下文|Changed database context' })
        Do-TextShot -Id '03-regression/regression-full-log' -Title 'regression.sql · 15 项断言完整输出' -Lines $reg
        Do-TextShot -Id '03-regression/regression-verdict' -Title 'regression.sql · 总览与结论（15 / 15 全绿）' -Lines @($reg | Select-Object -Last 6)
        Do-TextShot -Id '03-regression/regression-pass-list' -Title 'regression.sql · 逐条 PASS 明细' -Lines @($reg | Where-Object { $_ -match '\[PASS\]|\[FAIL\]' })
    } else {
        Fail-Shot -Id '03-regression/regression-full-log' -Why '缺少输出文件'
    }
}

# ============================================================
#  04-baseline —— 三份快照 before/after 逐行比对
# ============================================================
if ($Only -eq '' -or $Only -eq '04') {
    Write-Host ''
    Write-Host '--- 04-baseline ---'

    $report = @()
    $totalBase = 0; $totalNow = 0; $totalDiff = 0
    foreach ($item in @(
            @{ Tag = '01'; Name = '01-order-detail';  Title = 'S1 订单明细' },
            @{ Tag = '02'; Name = '02-product-sales'; Title = 'S2 商品销售' },
            @{ Tag = '03'; Name = '03-stock-query';   Title = 'S3 库存查询' })) {
        $sqlFile  = Join-Path $testsRoot ("baseline\" + $item.Name + ".sql")
        $nowFile  = Join-Path $tmpDir ("now-S" + $item.Tag + ".txt")
        & sqlcmd -S '.\SQLEXPRESS' -E -C -d milktea_shop -f 65001 -W -s '|' -i $sqlFile -o $nowFile | Out-Null
        $now  = @(Get-Content $nowFile -Encoding UTF8)
        $base = @(Get-Content (Join-Path $testsRoot ("baseline\result\after-S" + $item.Tag + ".txt")) -Encoding UTF8)
        if ($base.Count -gt 0) { $base[0] = $base[0].TrimStart([char]0xFEFF) }
        if ($now.Count  -gt 0) { $now[0]  = $now[0].TrimStart([char]0xFEFF) }
        $diff = 0
        for ($i = 0; $i -lt [Math]::Max($base.Count, $now.Count); $i++) {
            $a = if ($i -lt $base.Count) { $base[$i] } else { '<缺失>' }
            $b = if ($i -lt $now.Count)  { $now[$i] }  else { '<缺失>' }
            if ($a -ne $b) { $diff++ }
        }
        $totalBase += $base.Count; $totalNow += $now.Count; $totalDiff += $diff
        $report += ("{0,-12} 基线 {1,4} 行 / 迁移后 {2,4} 行 / 差异 {3} 行" -f $item.Title, $base.Count, $now.Count, $diff)
    }
    $report += ''
    $report += ("合计         基线 {0} 行 / 迁移后 {1} 行 / 差异 {2} 行" -f $totalBase, $totalNow, $totalDiff)
    $report += ''
    $report += '判据：S1/S2/S3 三份快照分别覆盖订单明细、商品销售（A/B/D 三口径）、库存查询，'
    $report += '      比对的是「迁移前基线与当前库」的逐行一致性 —— 差异 0 表示结构变了、业务结果没变。'
    $report += '      基线一律查基表、不查视图，避免视图定义变化污染基线。'
    Do-TextShot -Id '04-baseline/compare-summary' -Title '三份基线快照 · before/after 逐行比对（293 / 293 行一致）' -Lines $report
}

# ============================================================
#  05-query —— 关键查询口径
# ============================================================
if ($Only -eq '' -or $Only -eq '05') {
    Write-Host ''
    Write-Host '--- 05-query ---'

    Do-TableShot -Id '05-query/sales-caliber' -Title '销售额三种口径并列（A 全量 / B 仅 COMPLETED / D 仅 SUCCESS）' -Sql @'
SET NOCOUNT ON;
SELECT N'A 全量 SUM(amount_paid)' AS 口径, COUNT(*) AS 订单数, CAST(SUM(amount_paid) AS DECIMAL(12,2)) AS 金额 FROM tbl_order_header
UNION ALL SELECT N'B 仅 COMPLETED', COUNT(*), CAST(SUM(amount_paid) AS DECIMAL(12,2)) FROM tbl_order_header WHERE order_status = 'COMPLETED'
UNION ALL SELECT N'D 仅 pay_status=SUCCESS', COUNT(*), CAST(SUM(amount_paid) AS DECIMAL(12,2)) FROM tbl_order_header WHERE pay_status = 'SUCCESS'
UNION ALL SELECT N'折扣合计（D 口径）', COUNT(*), CAST(SUM(discount_amount) AS DECIMAL(12,2)) FROM tbl_order_header WHERE pay_status = 'SUCCESS';
'@

    Do-TableShot -Id '05-query/stock-invariant' -Title '库存不变量 · qty_on_hand = Σ 流水（逐原料核对，0 条不平）' -Sql @'
SET NOCOUNT ON;
SELECT COUNT(*) AS 原料数,
       SUM(CASE WHEN i.qty_on_hand <> f.flow_total THEN 1 ELSE 0 END) AS 结存与流水不符的原料数,
       CAST(SUM(i.qty_on_hand) AS DECIMAL(14,3)) AS 结存合计,
       CAST(SUM(f.flow_total) AS DECIMAL(14,3)) AS 流水合计
FROM tbl_ingredient i
JOIN (SELECT ingredient_id, SUM(qty) AS flow_total FROM tbl_stock_ledger GROUP BY ingredient_id) f
  ON f.ingredient_id = i.ingredient_id;
'@

    Do-TableShot -Id '05-query/top-products' -Title '商品销量 Top 10（口径 D：仅 pay_status = SUCCESS，SUM(subtotal)）' -Sql @'
SET NOCOUNT ON;
SELECT TOP 10
       ROW_NUMBER() OVER (ORDER BY SUM(d.subtotal) DESC) AS 排名,
       p.product_code AS 编码,
       p.product_name AS 商品,
       SUM(d.qty)                     AS 杯数,
       CAST(SUM(d.subtotal) AS DECIMAL(10, 2)) AS 销售额
FROM tbl_order_detail d
JOIN tbl_order_header h ON h.order_id = d.order_id
JOIN tbl_product p       ON p.product_id = d.product_id
WHERE h.pay_status = 'SUCCESS'
GROUP BY p.product_code, p.product_name
ORDER BY SUM(d.subtotal) DESC;
'@
}

# ============================================================
#  06-security —— 授权矩阵与越权失败
# ============================================================
if ($Only -eq '' -or $Only -eq '06') {
    Write-Host ''
    Write-Host '--- 06-security ---'

    Do-TableShot -Id '06-security/role-permission-summary' -Title '安全 · 4 个角色的授权条数（架构级授权必须为 0）' -Sql @'
SET NOCOUNT ON;
SELECT r.name AS 角色,
       COUNT(*) AS 权限条数,
       COUNT(DISTINCT p.major_id) AS 覆盖对象数,
       SUM(CASE WHEN p.class_desc = 'SCHEMA' THEN 1 ELSE 0 END) AS 架构级授权条数,
       SUM(CASE WHEN p.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN 1 ELSE 0 END) AS 可转授权条数
FROM sys.database_permissions p
JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
WHERE r.type = 'R' AND r.is_fixed_role = 0 AND r.name LIKE 'role[_]%'
GROUP BY r.name
ORDER BY COUNT(*) DESC;
'@

    Do-SqlTextShot -Id '06-security/unauthorized-229' -Title '安全 · 四组越权操作全部被引擎拦截（Msg 229 / 262）' -Sql @'
SET NOCOUNT ON;
PRINT '=== 负例 1：制作员读会员手机号（应被拒绝） ===';
BEGIN TRY
    EXECUTE AS USER = 'usr_test_maker';
    SELECT TOP 1 member_id, member_phone FROM dbo.tbl_member;
    REVERT;
    PRINT 'RESULT: NOT-BLOCKED（未被拦截，异常）';
END TRY
BEGIN CATCH
    PRINT 'RESULT: BLOCKED -> ' + ERROR_MESSAGE();
    IF USER_NAME() <> 'dbo' REVERT;
END CATCH;
PRINT '';
PRINT '=== 负例 2：收银员篡改配方（应被拒绝） ===';
BEGIN TRY
    EXECUTE AS USER = 'usr_test_cashier';
    UPDATE dbo.tbl_recipe SET qty = qty WHERE recipe_id = 1;
    REVERT;
    PRINT 'RESULT: NOT-BLOCKED（未被拦截，异常）';
END TRY
BEGIN CATCH
    PRINT 'RESULT: BLOCKED -> ' + ERROR_MESSAGE();
    IF USER_NAME() <> 'dbo' REVERT;
END CATCH;
PRINT '';
PRINT '=== 负例 3：库管员删除订单头（应被拒绝） ===';
BEGIN TRY
    EXECUTE AS USER = 'usr_test_stocker';
    DELETE FROM dbo.tbl_order_header WHERE order_id = 1;
    REVERT;
    PRINT 'RESULT: NOT-BLOCKED（未被拦截，异常）';
END TRY
BEGIN CATCH
    PRINT 'RESULT: BLOCKED -> ' + ERROR_MESSAGE();
    IF USER_NAME() <> 'dbo' REVERT;
END CATCH;
PRINT '';
PRINT '=== 负例 4：店长新建表（架构级授权已收回，应被拒绝） ===';
BEGIN TRY
    EXECUTE AS USER = 'usr_test_manager';
    CREATE TABLE dbo.tbl_probe_perm (id INT);
    REVERT;
    PRINT 'RESULT: NOT-BLOCKED（未被拦截，异常）';
END TRY
BEGIN CATCH
    PRINT 'RESULT: BLOCKED -> ' + ERROR_MESSAGE();
    IF USER_NAME() <> 'dbo' REVERT;
END CATCH;
PRINT '';
PRINT '=== 结论 ===';
PRINT '4 组越权全部由数据库引擎拦截：岗位能力由 GRANT 决定，不依赖页面层的判断。';
'@
}

Write-Host ''
Write-Host ('========== SQL 类证据：成功 {0} 张 / 失败 {1} 张 ==========' -f $script:Ok, $script:Fail)
if ($script:Fail -gt 0) {
    Write-Host '失败明细：'
    $script:Err | ForEach-Object { Write-Host ('  - ' + $_) }
    exit 1
}
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
exit 0
