#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Usage Widget - floating desktop window showing session and weekly limits.
    Right-click to change size (S/M/L) or refresh interval.
    Drag the header to reposition. Position is saved.
#>

$mutex = New-Object System.Threading.Mutex($false, 'ClaudeUsageWidget')
if (-not $mutex.WaitOne(0)) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir   = $PSScriptRoot
$configPath  = Join-Path $scriptDir 'config.json'
$fetchScript = Join-Path $scriptDir 'fetch-usage.js'

# --- Config ---
function Get-Config {
    if (Test-Path $configPath) { return Get-Content $configPath -Raw | ConvertFrom-Json }
    return [PSCustomObject]@{ x = 40; y = 200; refreshMinutes = 5; size = 'M' }
}
function Save-Config($cfg) { $cfg | ConvertTo-Json | Set-Content $configPath -Encoding UTF8 }
$config = Get-Config
if (-not $config.PSObject.Properties['size']) {
    $config | Add-Member -NotePropertyName 'size' -NotePropertyValue 'M'
}

# --- Size definitions ---
$sizes = @{
    S = @{ W = 260; H = 185; headerH = 26; titleFont = 8;  bodyFont = 7.5; pctFont = 8;  barH = 6;  pad = 10 }
    M = @{ W = 360; H = 240; headerH = 32; titleFont = 10; bodyFont = 9;   pctFont = 10; barH = 9;  pad = 14 }
    L = @{ W = 480; H = 305; headerH = 40; titleFont = 13; bodyFont = 11;  pctFont = 13; barH = 12; pad = 18 }
}

# --- Colors ---
$clrBg     = [System.Drawing.Color]::FromArgb(22, 22, 34)
$clrAccent = [System.Drawing.Color]::FromArgb(110, 90, 210)
$clrText   = [System.Drawing.Color]::FromArgb(220, 220, 235)
$clrSub    = [System.Drawing.Color]::FromArgb(185, 185, 205)
$clrBarBg  = [System.Drawing.Color]::FromArgb(45, 45, 65)
$clrGreen  = [System.Drawing.Color]::FromArgb(80, 200, 120)
$clrYellow = [System.Drawing.Color]::FromArgb(230, 180, 50)
$clrRed    = [System.Drawing.Color]::FromArgb(220, 70, 70)

function Get-BarColor($pct) {
    if ($pct -ge 90) { return $clrRed }
    if ($pct -ge 70) { return $clrYellow }
    return $clrGreen
}

# --- Fetch usage ---
function Get-UsageData {
    try { $j = & node $fetchScript 2>$null; if ($j) { return $j | ConvertFrom-Json } } catch {}
    return $null
}

# --- Time helper ---
function Format-TimeLeft([long]$secs) {
    if ($secs -le 0) { return 'now' }
    $h = [math]::Floor($secs / 3600)
    $m = [math]::Floor(($secs % 3600) / 60)
    if ($h -gt 0) { return "${h}h ${m}m" }
    return "${m}m"
}

# --- Drag state ---
$script:isDragging  = $false
$script:dragOffsetX = 0
$script:dragOffsetY = 0
$dragDown = {
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:isDragging  = $true
        $screen = $s.PointToScreen($e.Location)
        $script:dragOffsetX = $screen.X - $form.Left
        $script:dragOffsetY = $screen.Y - $form.Top
    }
}
$dragMove = {
    param($s, $e)
    if ($script:isDragging) {
        $cur = [System.Windows.Forms.Cursor]::Position
        $form.Left = $cur.X - $script:dragOffsetX
        $form.Top  = $cur.Y - $script:dragOffsetY
    }
}
$dragUp = {
    param($s, $e)
    if ($script:isDragging) {
        $script:isDragging = $false
        $cfg = Get-Config; $cfg.x = $form.Left; $cfg.y = $form.Top; Save-Config $cfg
    }
}

# --- Build the form ---
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Claude Usage'
$form.FormBorderStyle = 'None'
$form.BackColor       = $clrBg
$form.ForeColor       = $clrText
$form.ShowInTaskbar   = $false
$form.TopMost         = $true
$form.StartPosition   = 'Manual'
$form.Opacity         = 0.94
$form.Add_MouseDown($dragDown)
$form.Add_MouseMove($dragMove)
$form.Add_MouseUp($dragUp)

# --- Header ---
$header = New-Object System.Windows.Forms.Panel
$header.BackColor = $clrAccent
$header.Cursor    = 'SizeAll'
$header.Add_MouseDown($dragDown)
$header.Add_MouseMove($dragMove)
$header.Add_MouseUp($dragUp)
$form.Controls.Add($header)

# Title label
$titleLbl = New-Object System.Windows.Forms.Label
$titleLbl.Text      = 'Claude Usage'
$titleLbl.ForeColor = [System.Drawing.Color]::White
$titleLbl.BackColor = [System.Drawing.Color]::Transparent
$titleLbl.Cursor    = 'SizeAll'
$titleLbl.Add_MouseDown($dragDown); $titleLbl.Add_MouseMove($dragMove); $titleLbl.Add_MouseUp($dragUp)
$header.Controls.Add($titleLbl)

# Close button
$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text      = 'x'
$closeBtn.ForeColor = [System.Drawing.Color]::White
$closeBtn.BackColor = $clrAccent
$closeBtn.FlatStyle = 'Flat'
$closeBtn.FlatAppearance.BorderSize  = 0
$closeBtn.FlatAppearance.MouseOverBackColor  = [System.Drawing.Color]::FromArgb(160, 60, 60)
$closeBtn.Cursor    = 'Hand'
$closeBtn.Add_Click({ $form.Close() })
$header.Controls.Add($closeBtn)

# Refresh button
$refreshBtn = New-Object System.Windows.Forms.Button
$refreshBtn.Text      = 'Refresh'
$refreshBtn.ForeColor = $clrText
$refreshBtn.BackColor = [System.Drawing.Color]::FromArgb(85, 70, 170)
$refreshBtn.FlatStyle = 'Flat'
$refreshBtn.FlatAppearance.BorderSize = 0
$refreshBtn.Cursor    = 'Hand'
$header.Controls.Add($refreshBtn)

# --- Body controls (created once, repositioned on resize) ---
$sessionTitleLbl = New-Object System.Windows.Forms.Label
$sessionTitleLbl.Text      = 'Session limit (5h)'
$sessionTitleLbl.ForeColor = $clrSub
$form.Controls.Add($sessionTitleLbl)

$sessionPctLbl = New-Object System.Windows.Forms.Label
$sessionPctLbl.Text      = '--%'
$sessionPctLbl.ForeColor = $clrText
$sessionPctLbl.TextAlign = 'MiddleRight'
$form.Controls.Add($sessionPctLbl)

$sessionBarBg = New-Object System.Windows.Forms.Panel
$sessionBarBg.BackColor = $clrBarBg
$form.Controls.Add($sessionBarBg)
$sessionBarFill = New-Object System.Windows.Forms.Panel
$sessionBarFill.BackColor = $clrGreen
$sessionBarFill.Location  = [System.Drawing.Point]::new(0, 0)
$sessionBarBg.Controls.Add($sessionBarFill)

$sessionResetLbl = New-Object System.Windows.Forms.Label
$sessionResetLbl.Text      = 'Resets in --'
$sessionResetLbl.ForeColor = $clrSub
$form.Controls.Add($sessionResetLbl)

$weeklyTitleLbl = New-Object System.Windows.Forms.Label
$weeklyTitleLbl.Text      = 'Weekly limit (7d)'
$weeklyTitleLbl.ForeColor = $clrSub
$form.Controls.Add($weeklyTitleLbl)

$weeklyPctLbl = New-Object System.Windows.Forms.Label
$weeklyPctLbl.Text      = '--%'
$weeklyPctLbl.ForeColor = $clrText
$weeklyPctLbl.TextAlign = 'MiddleRight'
$form.Controls.Add($weeklyPctLbl)

$weeklyBarBg = New-Object System.Windows.Forms.Panel
$weeklyBarBg.BackColor = $clrBarBg
$form.Controls.Add($weeklyBarBg)
$weeklyBarFill = New-Object System.Windows.Forms.Panel
$weeklyBarFill.BackColor = $clrYellow
$weeklyBarFill.Location  = [System.Drawing.Point]::new(0, 0)
$weeklyBarBg.Controls.Add($weeklyBarFill)

$weeklyResetLbl = New-Object System.Windows.Forms.Label
$weeklyResetLbl.Text      = 'Resets in --'
$weeklyResetLbl.ForeColor = $clrSub
$form.Controls.Add($weeklyResetLbl)

$statusLbl = New-Object System.Windows.Forms.Label
$statusLbl.Text      = 'Loading...'
$statusLbl.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 185)
$form.Controls.Add($statusLbl)

# --- Apply size: repositions all controls ---
function Apply-Size($sizeKey) {
    $s = $sizes[$sizeKey]
    $W = $s.W; $H = $s.H; $hH = $s.headerH; $p = $s.pad

    $form.Width  = $W
    $form.Height = $H

    # Header
    $header.Location = [System.Drawing.Point]::new(0, 0)
    $header.Size     = [System.Drawing.Size]::new($W, $hH)

    $tf   = New-Object System.Drawing.Font('Segoe UI', $s.titleFont, [System.Drawing.FontStyle]::Bold)
    $bf   = New-Object System.Drawing.Font('Segoe UI', ($s.bodyFont))
    $sf   = New-Object System.Drawing.Font('Segoe UI', ($s.bodyFont - 1))
    $pf   = New-Object System.Drawing.Font('Segoe UI', $s.pctFont, [System.Drawing.FontStyle]::Bold)

    # Right-side buttons: [Refresh] [X] — fixed widths, then title fills remaining space
    $closeW = $hH
    $refW   = [math]::Max(55, [int]($hH * 2.2))
    $btnH   = $hH - 6

    $closeBtn.Font     = $tf
    $closeBtn.Size     = [System.Drawing.Size]::new($closeW, $hH)
    $closeBtn.Location = [System.Drawing.Point]::new($W - $closeW, 0)

    $refreshBtn.Font     = $sf
    $refreshBtn.Size     = [System.Drawing.Size]::new($refW, $btnH)
    $refreshBtn.Location = [System.Drawing.Point]::new($W - $closeW - $refW - 4, 3)

    $titleW = $W - $closeW - $refW - 4 - $p
    $titleLbl.Font     = $tf
    $titleLbl.Location = [System.Drawing.Point]::new($p, [math]::Max(0, ($hH - $tf.Height) / 2 - 1))
    $titleLbl.Size     = [System.Drawing.Size]::new($titleW, $hH)

    # Section 1: Session
    $y1 = $hH + $p
    $innerW = $W - $p * 2

    $sessionTitleLbl.Font     = $bf
    $sessionTitleLbl.Location = [System.Drawing.Point]::new($p, $y1)
    $sessionTitleLbl.Size     = [System.Drawing.Size]::new([int]($innerW * 0.72), [int]($s.bodyFont * 2))

    $sessionPctLbl.Font     = $pf
    $sessionPctLbl.Location = [System.Drawing.Point]::new($W - $p - 70, $y1 - 2)
    $sessionPctLbl.Size     = [System.Drawing.Size]::new(70, [int]($s.pctFont * 2.2))

    $barY = $y1 + [int]($s.bodyFont * 2) + 4
    $sessionBarBg.Location = [System.Drawing.Point]::new($p, $barY)
    $sessionBarBg.Size     = [System.Drawing.Size]::new($innerW, $s.barH)
    $sessionBarFill.Size   = [System.Drawing.Size]::new($sessionBarFill.Width, $s.barH)

    $sessionResetLbl.Font     = $sf
    $sessionResetLbl.Location = [System.Drawing.Point]::new($p, $barY + $s.barH + 4)
    $sessionResetLbl.Size     = [System.Drawing.Size]::new($innerW, [int]($s.bodyFont * 1.8))

    # Section 2: Weekly
    $y2 = $barY + $s.barH + [int]($s.bodyFont * 1.8) + $p + 6

    $weeklyTitleLbl.Font     = $bf
    $weeklyTitleLbl.Location = [System.Drawing.Point]::new($p, $y2)
    $weeklyTitleLbl.Size     = [System.Drawing.Size]::new([int]($innerW * 0.72), [int]($s.bodyFont * 2))

    $weeklyPctLbl.Font     = $pf
    $weeklyPctLbl.Location = [System.Drawing.Point]::new($W - $p - 70, $y2 - 2)
    $weeklyPctLbl.Size     = [System.Drawing.Size]::new(70, [int]($s.pctFont * 2.2))

    $barY2 = $y2 + [int]($s.bodyFont * 2) + 4
    $weeklyBarBg.Location = [System.Drawing.Point]::new($p, $barY2)
    $weeklyBarBg.Size     = [System.Drawing.Size]::new($innerW, $s.barH)
    $weeklyBarFill.Size   = [System.Drawing.Size]::new($weeklyBarFill.Width, $s.barH)

    $weeklyResetLbl.Font     = $sf
    $weeklyResetLbl.Location = [System.Drawing.Point]::new($p, $barY2 + $s.barH + 4)
    $weeklyResetLbl.Size     = [System.Drawing.Size]::new($innerW, [int]($s.bodyFont * 1.8))

    # Status
    $statusLbl.Font     = $sf
    $statusLbl.Location = [System.Drawing.Point]::new($p, $H - [int]($s.bodyFont * 2.2))
    $statusLbl.Size     = [System.Drawing.Size]::new($innerW, [int]($s.bodyFont * 1.8))

    $form.Refresh()
}

# --- Update display from cached data ---
$script:cached    = $null
$script:fetchedAt = $null

function Update-Bar($barFill, $barBg, $pct) {
    $w = [math]::Max(0, [math]::Round($barBg.Width * $pct / 100))
    $barFill.Width    = $w
    $barFill.BackColor = Get-BarColor $pct
}

function Update-Display {
    $data = $script:cached
    if (-not $data) { $statusLbl.Text = 'No data - click Refresh'; return }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $s5pct  = [math]::Round($data.session5h.utilization * 100)
    $s5left = [math]::Max(0, $data.session5h.resetAt - $now)
    $sessionPctLbl.Text      = "$s5pct%"
    $sessionPctLbl.ForeColor = Get-BarColor $s5pct
    Update-Bar $sessionBarFill $sessionBarBg $s5pct
    $sessionResetLbl.Text = "Resets in $(Format-TimeLeft $s5left)"

    $s7pct  = [math]::Round($data.weekly7d.utilization * 100)
    $s7left = [math]::Max(0, $data.weekly7d.resetAt - $now)
    $weeklyPctLbl.Text      = "$s7pct%"
    $weeklyPctLbl.ForeColor = Get-BarColor $s7pct
    Update-Bar $weeklyBarFill $weeklyBarBg $s7pct
    $weeklyResetLbl.Text = "Resets in $(Format-TimeLeft $s7left)"

    if ($script:fetchedAt) {
        $cfg = Get-Config
        $statusLbl.Text = "$($data.subscription) | Updated $(Get-Date $script:fetchedAt -Format 'HH:mm') | auto: $($cfg.refreshMinutes)m"
    }
}

function Invoke-Fetch {
    $statusLbl.Text = 'Fetching...'
    $form.Refresh()
    $data = Get-UsageData
    if ($data) { $script:cached = $data; $script:fetchedAt = Get-Date }
    Update-Display
}

$refreshBtn.Add_Click({ Invoke-Fetch })

# --- Context menu ---
$ctx = New-Object System.Windows.Forms.ContextMenuStrip

# Size submenu
$sizeMenu = New-Object System.Windows.Forms.ToolStripMenuItem 'Size'
foreach ($sz in @('S','M','L')) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text    = switch ($sz) { 'S' { 'Small' } 'M' { 'Medium' } 'L' { 'Large' } }
    $item.Tag     = $sz
    $item.Checked = ($sz -eq $config.size)
    $item.Add_Click({
        foreach ($si in $sizeMenu.DropDownItems) { $si.Checked = $false }
        $this.Checked = $true
        Apply-Size $this.Tag
        $cfg = Get-Config; $cfg.size = $this.Tag; Save-Config $cfg
        $script:config = $cfg
    })
    $sizeMenu.DropDownItems.Add($item) | Out-Null
}
$ctx.Items.Add($sizeMenu) | Out-Null

# Refresh interval submenu
$intMenu = New-Object System.Windows.Forms.ToolStripMenuItem 'Auto-refresh'
foreach ($min in @(1, 5, 10, 30, 60)) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text    = if ($min -eq 1) { '1 minute' } else { "$min minutes" }
    $item.Tag     = $min
    $item.Checked = ($min -eq $config.refreshMinutes)
    $item.Add_Click({
        foreach ($si in $intMenu.DropDownItems) { $si.Checked = $false }
        $this.Checked = $true
        $autoTimer.Interval = $this.Tag * 60000
        $cfg = Get-Config; $cfg.refreshMinutes = $this.Tag; Save-Config $cfg
        $script:config = $cfg
    })
    $intMenu.DropDownItems.Add($item) | Out-Null
}
$ctx.Items.Add($intMenu) | Out-Null

$ctx.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Exit'
$exitItem.Add_Click({ $form.Close() })
$ctx.Items.Add($exitItem) | Out-Null
$form.ContextMenuStrip = $ctx

# --- Timers ---
$countdownTimer          = New-Object System.Windows.Forms.Timer
$countdownTimer.Interval = 30000
$countdownTimer.Add_Tick({ Update-Display })
$countdownTimer.Start()

$autoTimer          = New-Object System.Windows.Forms.Timer
$autoTimer.Interval = $config.refreshMinutes * 60000
$autoTimer.Add_Tick({ Invoke-Fetch })
$autoTimer.Start()

# --- Start ---
$form.Location = [System.Drawing.Point]::new($config.x, $config.y)
Apply-Size $config.size
$form.Add_Shown({ Invoke-Fetch })
[System.Windows.Forms.Application]::Run($form)
$mutex.ReleaseMutex()
