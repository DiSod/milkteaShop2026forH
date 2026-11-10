<#
.SYNOPSIS
  茶颜小铺 · 数据库实验 v1.0 —— 演示用一键启动
.DESCRIPTION
  只做三件事：检查本机环境、启动 Flask、打开浏览器。
  不安装任何东西，不改动数据库（除非你加 -Rebuild）。
.EXAMPLE
  .\start-demo.ps1              # 直接启动
  .\start-demo.ps1 -Rebuild     # 先恢复种子基线（约 20 秒）再启动，演示前推荐
  .\start-demo.ps1 -Stop        # 停掉服务
#>
[CmdletBinding()]
param(
  [switch]$Rebuild,
  [switch]$Stop,
  [switch]$NoBrowser,
  [int]$Port = 5000
)

$ErrorActionPreference = 'Stop'

# ---------- 绝对路径（改机器只需要改这三行） ----------
$Root    = $PSScriptRoot
$AppDir  = Join-Path $Root 'project\app'
$SqlDir  = Join-Path $Root 'project\sql'
$Python  = 'C:\Users\GRIFFINL\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$Sqlcmd  = 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
$Instance = '.\SQLEXPRESS'
$Database = 'milktea_shop'

$PidFile = Join-Path $env:TEMP 'milktea-demo.pid'
$LogFile = Join-Path $env:TEMP 'milktea-demo.log'
$Health  = "http://127.0.0.1:$Port/health"

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

# ---------- 停止 ----------
if ($Stop) {
  $stopped = $false
  if (Test-Path $PidFile) {
    $oldPid = [int](Get-Content $PidFile -Raw).Trim()
    if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) {
      Stop-Process -Id $oldPid -Force
      Say "已停止进程 PID $oldPid" 'Yellow'
      $stopped = $true
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  }
  # 兜底：谁占着这个端口就停谁
  $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($conn) {
    Stop-Process -Id $conn.OwningProcess -Force
    Say "已停止占用端口 $Port 的进程 PID $($conn.OwningProcess)" 'Yellow'
    $stopped = $true
  }
  if (-not $stopped) { Say "没有正在运行的服务。" 'DarkGray' }
  return
}

Say ''
Say '========== 茶颜小铺 · 数据库实验 v1.0 ==========' 'Cyan'

# ---------- 环境检查 ----------
Say '[1/4] 检查环境'

if (-not (Test-Path $Python)) {
  $fallback = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
  if (-not $fallback) { throw "找不到 Python：$Python 不存在，PATH 里也没有 python.exe" }
  $Python = $fallback
  Say "  · Python（回退到 PATH）：$Python" 'Yellow'
} else {
  Say "  · Python：$Python"
}

$drv = Get-OdbcDriver -Name 'ODBC Driver 1*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $drv) { throw '找不到 ODBC Driver 17/18 for SQL Server，pyodbc 连不上库' }
Say "  · ODBC：$($drv.Name)"

$svc = Get-Service -Name 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
if (-not $svc) { throw "找不到 SQL Server 实例 MSSQL`$SQLEXPRESS" }
if ($svc.Status -ne 'Running') {
  Say "  · SQL 服务未运行，尝试启动（可能需要管理员）" 'Yellow'
  Start-Service 'MSSQL$SQLEXPRESS'
  Start-Sleep -Seconds 2
}
Say "  · SQL 服务：$($svc.Name) $((Get-Service 'MSSQL$SQLEXPRESS').Status)"

if (-not (Test-Path $Sqlcmd)) { Say "  · 警告：找不到 sqlcmd（$Sqlcmd），-Rebuild 与自检将跳过" 'Yellow' }

# ---------- 可选：恢复基线 ----------
if ($Rebuild) {
  Say '[2/4] 重建数据库到种子基线（99-rebuild.sql）'
  if (-not (Test-Path $Sqlcmd)) { throw '没有 sqlcmd，无法重建' }
  Push-Location $SqlDir
  try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Sqlcmd -S $Instance -E -C -b -f 65001 -i '99-rebuild.sql' | Out-Null
    $sw.Stop()
    if ($LASTEXITCODE -ne 0) { throw "99-rebuild.sql 执行失败，退出码 $LASTEXITCODE" }
    Say ("  · 完成，用时 {0:N1} 秒" -f $sw.Elapsed.TotalSeconds) 'Green'
  } finally { Pop-Location }
} else {
  Say '[2/4] 跳过重建（加 -Rebuild 可恢复种子基线）' 'DarkGray'
}

# ---------- 启动 ----------
Say '[3/4] 启动 Web 服务'

$conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) {
  Say "  · 端口 $Port 已被 PID $($conn.OwningProcess) 占用，直接复用" 'Yellow'
} else {
  # 用一层 hidden powershell 再起 python：调用方的控制台不会被服务占住，
  # 脚本能正常返回（服务输出全部落到 $LogFile）。
  $inner = "& '$Python' -X utf8 app.py *> '$LogFile'"
  $proc = Start-Process -FilePath 'powershell' `
    -ArgumentList '-NoProfile', '-Command', $inner `
    -WorkingDirectory $AppDir `
    -WindowStyle Hidden `
    -PassThru
  Set-Content -Path $PidFile -Value $proc.Id -Encoding ascii
  Say "  · 已启动，PID $($proc.Id)，日志 $LogFile"

  $ok = $false
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    try {
      $r = Invoke-WebRequest -Uri $Health -UseBasicParsing -TimeoutSec 2
      if ($r.StatusCode -eq 200) { $ok = $true; break }
    } catch { }
  }
  if (-not $ok) {
    Say '  · 服务没起来，最后 20 行日志：' 'Red'
    Get-Content $LogFile -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Say "    $_" 'Red' }
    throw '启动失败'
  }
}

$health = (Invoke-WebRequest -Uri $Health -UseBasicParsing -TimeoutSec 5).Content
Say "  · 自检通过：$health" 'Green'

# ---------- 交付信息 ----------
Say '[4/4] 可以演示了'
Say ''
Say "  顾客入口    http://127.0.0.1:$Port/login"        'White'
Say "  员工入口    http://127.0.0.1:$Port/staff/login"  'White'
Say "  健康检查    $Health"                             'White'
Say ''
Say '  会员账号    13800000001 / 000001   刘洋，2 张可用券' 'Gray'
Say '              13800000002 / 000002   另一会员，同样 2 张' 'Gray'
Say '  员工账号    E001 / e001  店长     E002 / e002  收银'        'Gray'
Say '              E003 / e003  制作     E005 / e005  库管'        'Gray'
Say ''
Say "  停止服务    .\start-demo.ps1 -Stop"     'DarkGray'
Say "  服务日志    $LogFile"                    'DarkGray'
Say ''

Say '  关掉这个窗口服务仍在跑；要停服务用 .\start-demo.ps1 -Stop' 'DarkGray'
Say ''

if (-not $NoBrowser) { Start-Process "http://127.0.0.1:$Port/login" }
