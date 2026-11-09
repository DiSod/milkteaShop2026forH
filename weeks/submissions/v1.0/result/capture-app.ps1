# -*- coding: utf-8 -*-
<#
.SYNOPSIS
    v1.0 阶段交付：应用层页面证据截图（07-app 组）。

.DESCRIPTION
    与 SQL 类证据（capture.ps1）分开：这一组截的是真实跑起来的 Flask 页面，
    需要 `project/app/app.py` 已在 127.0.0.1:5000 运行。

    做法（可复现，不依赖人工点鼠标）：
      1. 用 Invoke-WebRequest + WebSession 以演示账号登录，把渲染后的 HTML 落盘到
         project/app/web/static/__shot_<name>.html；
      2. 用无头 Edge 打开这个静态副本并截图 —— 资产路径都是 /static/，副本能正常加载样式；
      3. 需要交互态（饮品对话框、购物车抽屉）时，在副本里注入一小段脚本自动展开；
      4. 截完删掉临时 HTML，静态目录保持干净。

.PARAMETER Only
    只跑指定名字（逗号分隔），如 -Only menu,cart。省略则全跑。

.PARAMETER SkipSource
    跳过第 1 步（临时 HTML 已存在时用），只重截图片。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File capture-app.ps1
    powershell -ExecutionPolicy Bypass -File capture-app.ps1 -Only manager
#>
[CmdletBinding()]
param(
    [string]$Only = '',
    [switch]$SkipSource
)

$ErrorActionPreference = 'Stop'

$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$projRoot  = (Resolve-Path (Join-Path $here '..\..\..\..')).Path
$appStatic = Join-Path $projRoot 'project\app\web\static'
$outDir    = Join-Path $here '07-app'
$base      = 'http://127.0.0.1:5000'
$edge      = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$memberPhone = '13800000001'
$memberPwd   = '000001'
$staff = @(
    @{ Role = 'CASHIER'; Code = 'E002'; Pwd = 'e002' },
    @{ Role = 'MAKER';   Code = 'E003'; Pwd = 'e003' },
    @{ Role = 'STOCKER'; Code = 'E005'; Pwd = 'e005' },
    @{ Role = 'MANAGER'; Code = 'E001'; Pwd = 'e001' }
)

function New-Dir([string]$p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }

function Test-App {
    try {
        $r = Invoke-WebRequest -Uri "$base/health" -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function New-Session { New-Object Microsoft.PowerShell.Commands.WebRequestSession }

function Invoke-Post([string]$path, [hashtable]$body, $sess) {
    # 登录成功会 302 到目标页，Invoke-WebRequest 默认跟随重定向；跟随后的 200 就是成功。
    $r = Invoke-WebRequest -Uri "$base$path" -Method Post -Body $body -WebSession $sess `
        -UseBasicParsing -TimeoutSec 20
    if ([int]$r.StatusCode -ge 400) { throw "POST $path 返回 $($r.StatusCode)" }
}

function Get-Html([string]$path, $sess) {
    $r = Invoke-WebRequest -Uri "$base$path" -WebSession $sess -UseBasicParsing -TimeoutSec 20
    return $r.Content
}

function Get-HtmlAllowError([string]$path, $sess) {
    try {
        $r = Invoke-WebRequest -Uri "$base$path" -WebSession $sess -UseBasicParsing -TimeoutSec 20
        return @{ Status = [int]$r.StatusCode; Html = $r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { throw }
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd()
        $sr.Dispose()
        return @{ Status = [int]$resp.StatusCode; Html = $body }
    }
}

# 需要交互态的页面：注入脚本自动展开（不注入则保持初始态）
$scriptModal = @'
<script>
document.addEventListener('DOMContentLoaded', function () {
  var m = document.querySelector('[data-drink-modal]');
  if (m && window.bootstrap) { bootstrap.Modal.getOrCreateInstance(m).show(); }
});
</script>
'@

$scriptCart = @'
<script>
document.addEventListener('DOMContentLoaded', function () {
  var modals = [].slice.call(document.querySelectorAll('[data-drink-modal]')).slice(0, 3);
  var qty = [2, 1, 1];
  modals.forEach(function (m, i) {
    var sel = m.querySelector('[data-qty]');
    if (sel) { sel.value = String(qty[i]); sel.dispatchEvent(new Event('change', { bubbles: true })); }
  });
  var sheet = document.getElementById('cartSheet');
  if (sheet && window.bootstrap) { bootstrap.Offcanvas.getOrCreateInstance(sheet).show(); }
});
</script>
'@

function Save-Source([string]$name, [string]$path, $sess, [string]$inject = '') {
    $html = Get-Html $path $sess
    if ($inject -ne '') { $html = $html.Replace('</body>', "$inject</body>") }
    $file = Join-Path $appStatic ("__shot_" + $name + ".html")
    [System.IO.File]::WriteAllText($file, $html, (New-Object System.Text.UTF8Encoding($false)))
    return $file
}

function Save-SourceError([string]$name, [string]$path, $sess) {
    $res = Get-HtmlAllowError $path $sess
    $file = Join-Path $appStatic ("__shot_" + $name + ".html")
    [System.IO.File]::WriteAllText($file, $res.Html, (New-Object System.Text.UTF8Encoding($false)))
    return @{ File = $file; Status = $res.Status }
}

function New-Shot([string]$name, [int]$width, [int]$height) {
    $profile = Join-Path $env:TEMP ('edgeprof-' + [guid]::NewGuid().ToString('N'))
    $tmpPng  = Join-Path $env:TEMP ('shot-' + $name + '.png')
    $edgeArgs = @(
        '--headless=new', '--disable-gpu', '--no-first-run', '--hide-scrollbars',
        "--user-data-dir=$profile",
        "--window-size=$width,$height",
        '--virtual-time-budget=5000',
        "--screenshot=$tmpPng",
        "$base/static/__shot_$name.html"
    )
    $p = Start-Process -FilePath $edge -ArgumentList $edgeArgs -Wait -PassThru -NoNewWindow
    Start-Sleep -Milliseconds 300
    if (-not (Test-Path $tmpPng)) { throw "截图失败：$name（exit $($p.ExitCode)）" }
    New-Dir $outDir
    $dest = Join-Path $outDir ($name + '.png')
    Copy-Item $tmpPng $dest -Force
    Remove-Item $tmpPng -Force -ErrorAction SilentlyContinue
    Remove-Item $profile -Recurse -Force -ErrorAction SilentlyContinue
    return $dest
}

function Do-Shot([string]$name, [int]$w, [int]$h) {
    $dest = New-Shot $name $w $h
    $size = (Get-Item $dest).Length
    Write-Host ("  [OK]   07-app/" + $name.PadRight(20) + ("(0x{0:X})" -f $size))
}

# ---------------------------------------------------------------- 主流程

if (-not (Test-App)) {
    Write-Host '[FAIL] Flask 未在 http://127.0.0.1:5000 运行。' -ForegroundColor Red
    Write-Host '       先在 project\app 下执行：python app.py'
    exit 1
}
New-Dir $outDir

$targets = if ($Only -eq '') { @('login','menu','menu-modal','cart','orders','coupons','me','cashier','maker','stocker','manager','forbidden') }
           else { $Only.Split(',') | ForEach-Object { $_.Trim() } }

$memberSess = New-Session
Invoke-Post '/login' @{ phone = $memberPhone; password = $memberPwd } $memberSess

$staffSess = @{}
foreach ($s in $staff) {
    $sess = New-Session
    Invoke-Post '/staff/login' @{ employee_code = $s.Code; password = $s.Pwd } $sess
    $staffSess[$s.Role] = $sess
}

$ok = 0; $fail = 0
Write-Host '--- 07-app ---'

foreach ($t in $targets) {
    try {
        if (-not $SkipSource) {
            switch ($t) {
                'login'     { Save-Source 'login' '/login' (New-Session) | Out-Null }    # 未登录态：用干净会话
                'menu'      { Save-Source 'menu' '/' $memberSess | Out-Null }
                'menu-modal'{ Save-Source 'menu-modal' '/' $memberSess $scriptModal | Out-Null }
                'cart'      { Save-Source 'cart' '/' $memberSess $scriptCart | Out-Null }
                'orders'    { Save-Source 'orders' '/orders' $memberSess | Out-Null }
                'coupons'   { Save-Source 'coupons' '/coupons' $memberSess | Out-Null }
                'me'        { Save-Source 'me' '/me' $memberSess | Out-Null }
                'cashier'   { Save-Source 'cashier' '/cashier' $staffSess['CASHIER'] | Out-Null }
                'maker'     { Save-Source 'maker' '/maker' $staffSess['MAKER'] | Out-Null }
                'stocker'   { Save-Source 'stocker' '/stocker' $staffSess['STOCKER'] | Out-Null }
                'manager'   { Save-Source 'manager' '/manager' $staffSess['MANAGER'] | Out-Null }
                'forbidden' {
                    $r = Save-SourceError 'forbidden' '/manager' $staffSess['STOCKER']
                    if ($r.Status -ne 403) { throw "期望 403，实际 $($r.Status)" }
                }
                default { throw "未知页面：$t" }
            }
        }
        switch ($t) {
            'menu'      { Do-Shot 'menu' 1240 900 }
            'menu-modal'{ Do-Shot 'menu-modal' 1240 900 }
            'cart'      { Do-Shot 'cart' 1240 900 }
            'orders'    { Do-Shot 'orders' 1240 1000 }
            'manager'   { Do-Shot 'manager' 1240 1360 }
            default     { Do-Shot $t 1240 900 }
        }
        $ok++
    } catch {
        $fail++
        Write-Host ("  [FAIL] 07-app/" + $t.PadRight(20) + $_.Exception.Message) -ForegroundColor Red
    }
}

# 清掉静态目录里的临时副本
Get-ChildItem $appStatic -Filter '__shot_*.html' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Force }

Write-Host ''
Write-Host ('========== 应用类证据：成功 {0} 张 / 失败 {1} 张 ==========' -f $ok, $fail)
if ($fail -gt 0) { exit 1 }
