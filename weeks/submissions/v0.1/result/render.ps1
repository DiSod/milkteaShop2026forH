# render.ps1 —— 把 SQL 运行结果渲染成 PNG
#
# 用法：在被 capture.ps1 dot-source 后调用其中的函数。
#
# 为什么是「渲染」而不是「截屏」：
#   ① 可复现 —— 换一台机器跑 capture.ps1 能生成同一批图；
#   ② 可 diff —— 同时产出 .txt，内容变化一目了然；
#   ③ 无窗口依赖 —— 不要求有人守着桌面。
#
# 字体用 NSimSun（新宋体）：中英文等宽，中文正好 = 2 × ASCII 宽，
# 这样按「显示宽度」补齐后列才能对齐。

Add-Type -AssemblyName System.Drawing

# ---------- 工具 ----------

function Get-DispWidth {
    # 终端显示宽度：CJK 算 2 列，其余算 1 列
    param([string]$S)
    $w = 0
    foreach ($ch in $S.ToCharArray()) {
        $c = [int]$ch
        if (($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF) -or
            ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or
            ($c -ge 0xFE30 -and $c -le 0xFE6F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or
            ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { $w += 2 } else { $w += 1 }
    }
    return $w
}

function Get-FooterText {
    # 每张图都自带脚注 —— 脱离 README 也不会被误认为图形客户端的截屏
    '本图由 sqlcmd 的真实运行输出渲染 —— 不是 GUI 客户端的截屏',
    '可执行 SQL 见 code/ · 运行 capture.ps1 可一键重新生成'
}

function Get-RenderPalette {
    @{
        Bg      = [System.Drawing.Color]::FromArgb(18, 18, 22)
        Title   = [System.Drawing.Color]::FromArgb(255, 210, 120)
        Head    = [System.Drawing.Color]::FromArgb(120, 220, 160)
        HeadBg  = [System.Drawing.Color]::FromArgb(38, 38, 48)
        Text    = [System.Drawing.Color]::FromArgb(220, 220, 225)
        Dim     = [System.Drawing.Color]::FromArgb(150, 150, 160)
        Grid    = [System.Drawing.Color]::FromArgb(100, 100, 122)
        Zebra   = [System.Drawing.Color]::FromArgb(26, 26, 32)
        Ok      = [System.Drawing.Color]::FromArgb(130, 230, 140)
        Bad     = [System.Drawing.Color]::FromArgb(255, 130, 130)
    }
}

function Get-TextBrush {
    # 按行内容着色：✅ 绿 / ❌ 红 / 其余常规
    param([string]$Line, [hashtable]$P)
    if ($Line -match '✅' -or $Line -match '成功') { return (New-Object System.Drawing.SolidBrush $P.Ok) }
    if ($Line -match '❌' -or $Line -match '错误|失败|拒绝') { return (New-Object System.Drawing.SolidBrush $P.Bad) }
    return (New-Object System.Drawing.SolidBrush $P.Text)
}

# ---------- 表格图 ----------

function New-TableImage {
    param(
        [string[]]$Title,
        [string[]]$Header,
        [object[]]$Rows,
        [string]$OutPath,
        [int]$FontSize = 13,
        [string]$FontName = 'NSimSun'
    )
    $P = Get-RenderPalette
    $font      = New-Object System.Drawing.Font($FontName, [float]$FontSize)
    $fontBold  = New-Object System.Drawing.Font($FontName, [float]$FontSize, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font($FontName, [float]($FontSize + 1))

    $probe = New-Object System.Drawing.Bitmap 10, 10
    $gp    = [System.Drawing.Graphics]::FromImage($probe)
    # 单字符宽用 20 字符取平均 —— MeasureString 对单字符会多算冗余
    $charW = $gp.MeasureString(('0' * 20), $font).Width / 20.0
    $lineH = [int][Math]::Ceiling([double]$gp.MeasureString('M', $font).Height)
    $gp.Dispose(); $probe.Dispose()

    $padX = 12; $padY = 8
    $colCount = $Header.Count
    $colW = @()
    for ($i = 0; $i -lt $colCount; $i++) {
        $max = Get-DispWidth $Header[$i]
        foreach ($r in $Rows) { if ($i -lt $r.Count) { $d = Get-DispWidth $r[$i]; if ($d -gt $max) { $max = $d } } }
        $colW += [int][Math]::Ceiling(($max + 2) * $charW)
    }
    $tableW = 0; foreach ($c in $colW) { $tableW += $c }

    $titleLines = if ($Title) { @($Title) } else { @() }
    $titleH = 0; if ($titleLines.Count) { $titleH = $lineH * $titleLines.Count + $padY }
    # 宽度要取「表格」与「标题」的较大者 —— 否则长标题会被裁掉
    $titleW = 0
    foreach ($tl in $titleLines) { $d = Get-DispWidth $tl; if ($d -gt $titleW) { $titleW = $d } }
    [int]$imgW = [Math]::Ceiling([Math]::Max($tableW + $padX * 2 + 2, $titleW * $charW + $padX * 2 + 8))
    $footFont = New-Object System.Drawing.Font($FontName, [float]($FontSize - 3))
    $footLines = @(Get-FooterText)
    $footW = 0
    foreach ($fl in $footLines) { $d = Get-DispWidth $fl; if ($d -gt $footW) { $footW = $d } }
    $needW = [Math]::Ceiling($footW * ($charW * 0.78) + $padX * 2 + 8)
    if ($needW -gt $imgW) { $imgW = $needW }
    $footH = [int]($lineH * 1.25 * $footLines.Count) + 6
    [int]$imgH = [Math]::Ceiling($titleH + ($Rows.Count + 1) * $lineH + $padY * 4 + 8 + $footH)

    $bmp = New-Object System.Drawing.Bitmap $imgW, $imgH
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear($P.Bg)

    $penGrid = New-Object System.Drawing.Pen($P.Grid, 1)
    $brTitle = New-Object System.Drawing.SolidBrush($P.Title)
    $brHead  = New-Object System.Drawing.SolidBrush($P.Head)
    $brHeadBg= New-Object System.Drawing.SolidBrush($P.HeadBg)
    $brZebra = New-Object System.Drawing.SolidBrush($P.Zebra)
    $brText  = New-Object System.Drawing.SolidBrush($P.Text)

    $y = $padY
    foreach ($t in $titleLines) { $g.DrawString($t, $fontTitle, $brTitle, [float]$padX, [float]$y); $y += $lineH }
    if ($titleLines.Count) { $y += [int]($padY / 2) }
    $tableTop = $y

    $g.FillRectangle($brHeadBg, $padX, $y, $tableW, $lineH)
    $x = $padX
    for ($i = 0; $i -lt $colCount; $i++) {
        $g.DrawString($Header[$i], $fontBold, $brHead, [float]($x + $charW / 2), [float]($y + 2))
        $x += $colW[$i]
    }
    $y += $lineH

    for ($r = 0; $r -lt $Rows.Count; $r++) {
        if ($r % 2 -eq 1) { $g.FillRectangle($brZebra, $padX, $y, $tableW, $lineH) }
        $x = $padX
        for ($i = 0; $i -lt $colCount; $i++) {
            $v = if ($i -lt $Rows[$r].Count) { [string]$Rows[$r][$i] } else { '' }
            $g.DrawString($v, $font, $brText, [float]($x + $charW / 2), [float]($y + 2))
            $x += $colW[$i]
        }
        $y += $lineH
    }

    $x = $padX
    foreach ($cw in $colW) { $g.DrawLine($penGrid, $x, $tableTop, $x, $y); $x += $cw }
    $g.DrawLine($penGrid, $x, $tableTop, $x, $y)
    $g.DrawLine($penGrid, $padX, $tableTop, $padX + $tableW, $tableTop)
    $g.DrawLine($penGrid, $padX, $tableTop + $lineH, $padX + $tableW, $tableTop + $lineH)
    $g.DrawLine($penGrid, $padX, $y, $padX + $tableW, $y)

    $brFoot = New-Object System.Drawing.SolidBrush($P.Dim)
    $fy = $y + $padY
    foreach ($fl in $footLines) { $g.DrawString($fl, $footFont, $brFoot, [float]$padX, [float]$fy); $fy += [int]($lineH * 1.25) }

    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $font.Dispose(); $fontBold.Dispose(); $fontTitle.Dispose(); $penGrid.Dispose()
    $brTitle.Dispose(); $brHead.Dispose(); $brHeadBg.Dispose(); $brZebra.Dispose(); $brText.Dispose()
    $footFont.Dispose(); $brFoot.Dispose()
    return @{ Width = $imgW; Height = $imgH }
}

# ---------- 文本图（用于 PRINT 叙述、TRY/CATCH 消息、重建日志） ----------

function New-TextImage {
    param(
        [string[]]$Title,
        [string[]]$Lines,
        [string]$OutPath,
        [int]$FontSize = 13,
        [string]$FontName = 'NSimSun',
        [int]$MaxWidth = 1400
    )
    $P = Get-RenderPalette
    $font      = New-Object System.Drawing.Font($FontName, [float]$FontSize)
    $fontTitle = New-Object System.Drawing.Font($FontName, [float]($FontSize + 1))

    $probe = New-Object System.Drawing.Bitmap 10, 10
    $gp    = [System.Drawing.Graphics]::FromImage($probe)
    $charW = $gp.MeasureString(('0' * 20), $font).Width / 20.0
    $lineH = [int][Math]::Ceiling([double]$gp.MeasureString('M', $font).Height)
    $gp.Dispose(); $probe.Dispose()

    $padX = 12; $padY = 8
    $maxDisp = 0
    foreach ($l in $Lines) { $d = Get-DispWidth $l; if ($d -gt $maxDisp) { $maxDisp = $d } }
    foreach ($t in @($Title)) { if ($t) { $d = Get-DispWidth $t; if ($d -gt $maxDisp) { $maxDisp = $d } } }

    $titleLines = if ($Title) { @($Title) } else { @() }
    [int]$imgW = [Math]::Min($MaxWidth, [Math]::Ceiling($maxDisp * $charW + $padX * 2 + 8))
    # 脚注：图片自带来源说明
    $footFont = New-Object System.Drawing.Font($FontName, [float]($FontSize - 3))
    $footLines = @(Get-FooterText)
    $footW = 0
    foreach ($fl in $footLines) { $d = Get-DispWidth $fl; if ($d -gt $footW) { $footW = $d } }
    $needW = [Math]::Ceiling($footW * ($charW * 0.78) + $padX * 2 + 8)
    if ($needW -gt $imgW) { $imgW = [Math]::Min($MaxWidth, $needW) }
    $footH = [int]($lineH * 1.25 * $footLines.Count) + 6
    [int]$imgH = [Math]::Ceiling(($Lines.Count + $titleLines.Count) * $lineH + $padY * 4 + 8 + $footH)

    $bmp = New-Object System.Drawing.Bitmap $imgW, $imgH
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear($P.Bg)
    $brTitle = New-Object System.Drawing.SolidBrush($P.Title)
    $brDim   = New-Object System.Drawing.SolidBrush($P.Dim)

    $y = $padY
    foreach ($t in $titleLines) { $g.DrawString($t, $fontTitle, $brTitle, [float]$padX, [float]$y); $y += $lineH }
    if ($titleLines.Count) { $y += [int]($padY / 2) }

    foreach ($l in $Lines) {
        $br = Get-TextBrush -Line $l -P $P
        $g.DrawString($l, $font, $br, [float]$padX, [float]$y)
        $br.Dispose()
        $y += $lineH
    }

    $brFoot = New-Object System.Drawing.SolidBrush($P.Dim)
    $fy = $y + $padY
    foreach ($fl in $footLines) { $g.DrawString($fl, $footFont, $brFoot, [float]$padX, [float]$fy); $fy += [int]($lineH * 1.25) }

    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $font.Dispose(); $fontTitle.Dispose(); $brTitle.Dispose(); $brDim.Dispose()
    $footFont.Dispose(); $brFoot.Dispose()
    return @{ Width = $imgW; Height = $imgH }
}

# ---------- 执行 SQL ----------

function Invoke-SqlTable {
    param([string]$Sql, [string]$Connection = '.\SQLEXPRESS', [string]$Database = 'milktea_shop')
    $tmpSql = [System.IO.Path]::GetTempFileName() + '.sql'
    $tmpOut = [System.IO.Path]::GetTempFileName() + '.txt'
    try {
        [System.IO.File]::WriteAllText($tmpSql, $Sql, (New-Object System.Text.UTF8Encoding $true))
        & sqlcmd -S $Connection -E -C -d $Database -W -s '|' -f 65001 -i $tmpSql -o $tmpOut | Out-Null
        $lines = Get-Content $tmpOut -Encoding UTF8 |
                 Where-Object { $_.Trim() -ne '' } |
                 Where-Object { $_ -notmatch '^-+(\|-+)+$' } |
                 Where-Object { $_ -notmatch '已将数据库上下文|Changed database context' }
        if ($lines.Count -lt 1) { return @{ Header = @(); Rows = @() } }
        $header = $lines[0] -split '\|'
        $rows = @()
        foreach ($l in ($lines | Select-Object -Skip 1)) { $rows += ,($l -split '\|') }
        return @{ Header = $header; Rows = $rows }
    } finally {
        Remove-Item $tmpSql, $tmpOut -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SqlText {
    param([string]$Sql, [string]$Connection = '.\SQLEXPRESS', [string]$Database = 'milktea_shop')
    $tmpSql = [System.IO.Path]::GetTempFileName() + '.sql'
    $tmpOut = [System.IO.Path]::GetTempFileName() + '.txt'
    try {
        [System.IO.File]::WriteAllText($tmpSql, $Sql, (New-Object System.Text.UTF8Encoding $true))
        & sqlcmd -S $Connection -E -C -d $Database -W -f 65001 -i $tmpSql -o $tmpOut | Out-Null
        return (Get-Content $tmpOut -Encoding UTF8 |
                Where-Object { $_ -notmatch '已将数据库上下文|Changed database context' })
    } finally {
        Remove-Item $tmpSql, $tmpOut -Force -ErrorAction SilentlyContinue
    }
}
