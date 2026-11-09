<#
.SYNOPSIS
    生成 08-errors/ —— 四张错误页截图（400 / 409 / 404 / 405）。

.DESCRIPTION
    与 capture-app.ps1 的分工：
      capture-app.ps1 拍的是"正常路径"（每个角色的工作台长什么样）；
      本脚本拍的是"出错路径"——课程要求"有错误提示"，光有正常截图不算证据。

    做法与 capture-app.ps1 一致：先用登录会话请求，把返回的 HTML 落到
    project/app/web/static/ 下，再用无头 Edge 打开 http://127.0.0.1:5000/static/...
    截图（这样 CSS/字体都从本站加载，和真实浏览一致）。

    每个用例都断言状态码，不对就 FAIL 并返回非零，避免"截了一张但其实是 200"。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File capture-errors.ps1
    powershell -ExecutionPolicy Bypass -File capture-errors.ps1 -SkipSource
#>
param(
    [string]$Base     = 'http://127.0.0.1:5000',
    [string]$Only     = '',
    [switch]$SkipSource
)

$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir  = $here
$projRoot = (Resolve-Path (Join-Path $here '..\..\..\..\..')).Path
$appStatic = Join-Path $projRoot 'project\app\web\static'
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

$accounts = @{
    MEMBER  = @{ Path = '/login';        Body = @{ phone = '13800000001'; password = '000001' } }
    STOCKER = @{ Path = '/staff/login';  Body = @{ employee_code = 'E005'; password = 'e005' } }
}

function New-Session { New-Object Microsoft.PowerShell.Commands.WebRequestSession }

function Invoke-PostRaw([string]$path, [hashtable]$body, $sess) {
    try {
        $r = Invoke-WebRequest -Uri "$Base$path" -Method Post -Body $body -WebSession $sess `
            -UseBasicParsing -TimeoutSec 20
        return @{ Status = [int]$r.StatusCode; Html = $r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { throw }
        # PowerShell 5.1 的坑（踩了两次）：
        #   1) 错误响应的流停在末尾，直接 ReadToEnd() 得到空串 -> 截图全白；
        #   2) $_.ErrorDetails.Message 给的是“去掉标签的纯文本” -> 截出来没有样式。
        # 正解是把流 Position 归零再读；只有不可 seek 时才退回 ErrorDetails。
        $st = $resp.GetResponseStream()
        if ($st.CanSeek) { $st.Position = 0 }
        $sr = New-Object System.IO.StreamReader($st)
        $body2 = $sr.ReadToEnd(); $sr.Dispose()
        if ([string]::IsNullOrEmpty($body2)) { $body2 = $_.ErrorDetails.Message }
        return @{ Status = [int]$resp.StatusCode; Html = $body2 }
    }
}

function Invoke-GetRaw([string]$path, $sess) {
    try {
        $r = Invoke-WebRequest -Uri "$Base$path" -WebSession $sess -UseBasicParsing -TimeoutSec 20
        return @{ Status = [int]$r.StatusCode; Html = $r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { throw }
        # PowerShell 5.1 的坑（踩了两次）：
        #   1) 错误响应的流停在末尾，直接 ReadToEnd() 得到空串 -> 截图全白；
        #   2) $_.ErrorDetails.Message 给的是“去掉标签的纯文本” -> 截出来没有样式。
        # 正解是把流 Position 归零再读；只有不可 seek 时才退回 ErrorDetails。
        $st = $resp.GetResponseStream()
        if ($st.CanSeek) { $st.Position = 0 }
        $sr = New-Object System.IO.StreamReader($st)
        $body2 = $sr.ReadToEnd(); $sr.Dispose()
        if ([string]::IsNullOrEmpty($body2)) { $body2 = $_.ErrorDetails.Message }
        return @{ Status = [int]$resp.StatusCode; Html = $body2 }
    }
}

function Save-Source([string]$name, [string]$html) {
    $file = Join-Path $appStatic ("__shot_" + $name + ".html")
    [System.IO.File]::WriteAllText($file, $html, (New-Object System.Text.UTF8Encoding($false)))
}

function New-Shot([string]$name, [int]$width, [int]$height) {
    $profile = Join-Path $env:TEMP ('edgeprof-' + [guid]::NewGuid().ToString('N'))
    $tmpPng  = Join-Path $env:TEMP ('shot-' + $name + '.png')
    $edgeArgs = @(
        '--headless=new', '--disable-gpu', '--no-first-run', '--hide-scrollbars',
        "--user-data-dir=$profile", "--window-size=$width,$height",
        '--virtual-time-budget=5000', "--screenshot=$tmpPng",
        "$Base/static/__shot_$name.html"
    )
    $p = Start-Process -FilePath $edge -ArgumentList $edgeArgs -Wait -PassThru -NoNewWindow
    if (-not (Test-Path $tmpPng)) { throw "截图失败：$tmpPng 未生成" }
    $dst = Join-Path $outDir ("$name.png")
    Copy-Item $tmpPng $dst -Force
    Remove-Item $tmpPng -Force -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $profile -ErrorAction SilentlyContinue
}

function Do-Shot([string]$name, [string]$expectLabel) {
    New-Shot $name 1240 800
    $size = (Get-Item (Join-Path $outDir "$name.png")).Length
    Write-Host ("  [OK] 08-errors/" + $name.PadRight(14) + "$expectLabel  ($size bytes)") -ForegroundColor Green
}

# ---- 会话 ----
$sess = @{}
foreach ($k in $accounts.Keys) {
    $s = New-Session
    $a = $accounts[$k]
    Invoke-PostRaw $a.Path $a.Body $s | Out-Null
    $sess[$k] = $s
}

$targets = if ($Only -eq '') { @('error-400','error-409','error-404','error-405') }
           else { $Only.Split(',') | ForEach-Object { $_.Trim() } }

$ok = 0; $fail = 0
Write-Host '--- 08-errors ---'

foreach ($t in $targets) {
    try {
        switch ($t) {
            'error-400' {
                # 参数错误：数量写 abc —— 服务端校验拦住，不产生任何写入
                $r = Invoke-PostRaw '/order' @{ product_id = '1'; cup_spec_id = '1'; sugar_spec_id = '1'; ice_spec_id = '1'; qty = 'abc' } $sess['MEMBER']
                if ($r.Status -ne 400) { throw "期望 400，实际 $($r.Status)" }
                if (-not $SkipSource) { Save-Source 'error-400' $r.Html }
                Do-Shot 'error-400' '  400 参数错误'
            }
            'error-409' {
                # 业务规则：报损量超过结存 —— 409，事务回滚，结存不变
                $r = Invoke-PostRaw '/stocker/loss' @{ ingredient_id = '1'; qty = '99999999'; remark = '超量报损测试' } $sess['STOCKER']
                if ($r.Status -ne 409) { throw "期望 409，实际 $($r.Status)" }
                if (-not $SkipSource) { Save-Source 'error-409' $r.Html }
                Do-Shot 'error-409' '  409 业务规则冲突'
            }
            'error-404' {
                $r = Invoke-GetRaw '/nope' $sess['MEMBER']
                if ($r.Status -ne 404) { throw "期望 404，实际 $($r.Status)" }
                if (-not $SkipSource) { Save-Source 'error-404' $r.Html }
                Do-Shot 'error-404' '  404 页面不存在'
            }
            'error-405' {
                # /order 只接受 POST；GET 应被 HTTPException handler 接住成 405（历史上它曾被吞成 500）
                $r = Invoke-GetRaw '/order' $sess['MEMBER']
                if ($r.Status -ne 405) { throw "期望 405，实际 $($r.Status)" }
                if (-not $SkipSource) { Save-Source 'error-405' $r.Html }
                Do-Shot 'error-405' '  405 方法不允许'
            }
            default { throw "未知用例：$t" }
        }
        $ok++
    } catch {
        $fail++
        Write-Host ("  [FAIL] 08-errors/" + $t.PadRight(14) + $_.Exception.Message) -ForegroundColor Red
    }
}

Get-ChildItem $appStatic -Filter '__shot_*.html' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Force }

Write-Host ''
Write-Host ('========== 错误类证据：成功 {0} 张 / 失败 {1} 张 ==========' -f $ok, $fail)
if ($fail -gt 0) { exit 1 }
