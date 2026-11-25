<#
    演示用：一条命令查看"刚操作完，库里发生了什么"。

    用法：
        .\demo-checks.ps1            # 四组查询，逐组打印
        .\demo-checks.ps1 -Log       # 只看应用日志尾巴（另一开窗口用）
        .\demo-checks.ps1 -Tail      # 常驻滚动日志（Ctrl+C 退出）

    说明：本脚本只读，不改任何数据。
#>
param(
    [switch]$Log,
    [switch]$Tail
)

$ErrorActionPreference = 'Stop'
$Sqlcmd  = 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
$Instance = '.\SQLEXPRESS'
$Database = 'milktea_shop'
$LogFile  = Join-Path $env:TEMP 'milktea-demo.log'

if ($Tail) {
    if (-not (Test-Path $LogFile)) { Write-Host "日志还不存在：$LogFile" -ForegroundColor Yellow; exit 1 }
    Write-Host "滚动日志（Ctrl+C 退出）：$LogFile" -ForegroundColor Cyan
    Get-Content $LogFile -Wait -Tail 20
    exit 0
}

if ($Log) {
    if (-not (Test-Path $LogFile)) { Write-Host "日志还不存在：$LogFile" -ForegroundColor Yellow; exit 1 }
    Get-Content $LogFile -Tail 25
    exit 0
}

if (-not (Test-Path $Sqlcmd)) {
    Write-Host "找不到 sqlcmd：$Sqlcmd" -ForegroundColor Red
    exit 1
}

function Section($title) {
    Write-Host ''
    Write-Host ('=' * 74) -ForegroundColor DarkGray
    Write-Host ('  ' + $title) -ForegroundColor Cyan
    Write-Host ('=' * 74) -ForegroundColor DarkGray
}

function RunSql($sql) {
    & $Sqlcmd -S $Instance -E -C -d $Database -f 65001 -W -s ' | ' -Q ("SET NOCOUNT ON; " + $sql)
}

Section '1. 最近 5 条库存流水（报损/收货/下单都会落到这里）'
RunSql @"
SELECT TOP 5
       l.ledger_id, i.ingredient_name, l.ledger_type, l.ref_type,
       l.qty, l.remark, l.operator_id,
       CONVERT(VARCHAR(19), l.ledger_time, 120) AS ledger_time
FROM tbl_stock_ledger l
JOIN tbl_ingredient i ON i.ingredient_id = l.ingredient_id
ORDER BY l.ledger_id DESC;
"@

Section '2. 库存不变量：结存 = Σ流水（应为 0 行偏差）'
RunSql @"
SELECT COUNT(*) AS 偏差行数
FROM tbl_ingredient i
WHERE i.qty_on_hand <> (SELECT ISNULL(SUM(l.qty), 0) FROM tbl_stock_ledger l
                        WHERE l.ingredient_id = i.ingredient_id);
"@

Section '3. 商品状态与售罄（下架后这里会变成 OFF_SALE）'
RunSql @"
SELECT product_status, COUNT(*) AS 商品数
FROM tbl_product GROUP BY product_status ORDER BY product_status;
SELECT COUNT(*) AS 菜单可见组合数 FROM vw_product_stock_availability;
"@

Section '4. 销售额 D 口径（取消单不计入）'
RunSql @"
SELECT COUNT(*) AS 订单数,
       CAST(SUM(amount_paid) AS DECIMAL(10,2)) AS 实收合计
FROM tbl_order_header
WHERE pay_status = 'SUCCESS' AND order_status <> 'CANCELLED';
"@

Write-Host ''
Write-Host '提示：库存/销售类数字若因演示操作变了，跑 .\start-demo.ps1 -Rebuild 可恢复种子基线（约 20 秒）。' -ForegroundColor DarkGray
