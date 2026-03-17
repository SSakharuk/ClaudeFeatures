# claude-token-saver test script
# Tests filters by running runner.js directly with sample commands

param(
    [ValidateSet('all', 'git-status', 'git-diff', 'git-log', 'git-show', 'ansi')]
    [string]$Type = 'all'
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'runner.js'

function Test-Filter {
    param([string]$Label, [string]$FilterType, [string]$Command)

    Write-Host "`n--- $Label ---" -ForegroundColor Cyan
    Write-Host "Command: $Command" -ForegroundColor DarkGray

    # Run original command
    $rawOutput = & bash -c $Command 2>&1 | Out-String
    $rawLen = $rawOutput.Length

    # Run through filter
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Command))
    $filtOutput = & node $runner $FilterType $b64 2>&1 | Out-String
    $filtLen = $filtOutput.Length

    $savedPct = if ($rawLen -gt 0) { [math]::Round((1 - $filtLen / $rawLen) * 100) } else { 0 }

    Write-Host "Raw:      $rawLen chars ($($rawOutput.Split("`n").Count) lines)" -ForegroundColor White
    Write-Host "Filtered: $filtLen chars ($($filtOutput.Split("`n").Count) lines)" -ForegroundColor White

    if ($savedPct -gt 0) {
        Write-Host "Saved:    $savedPct%" -ForegroundColor Green
    } else {
        Write-Host "Saved:    $savedPct% (output already compact)" -ForegroundColor Yellow
    }

    Write-Host "`nFiltered output preview (first 10 lines):" -ForegroundColor DarkGray
    $filtOutput.Split("`n") | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
}

Write-Host "=== Claude Token Saver - Filter Tests ===" -ForegroundColor Cyan

if ($Type -eq 'all' -or $Type -eq 'git-status') {
    Test-Filter "Git Status" "git-status" "git status"
}

if ($Type -eq 'all' -or $Type -eq 'git-diff') {
    Test-Filter "Git Diff" "git-diff" "git diff"
}

if ($Type -eq 'all' -or $Type -eq 'git-log') {
    Test-Filter "Git Log" "git-log" "git log"
}

if ($Type -eq 'all' -or $Type -eq 'git-show') {
    Test-Filter "Git Show" "git-show" "git show HEAD"
}

if ($Type -eq 'all' -or $Type -eq 'ansi') {
    Write-Host "`n--- ANSI Stripping Test ---" -ForegroundColor Cyan
    # Create a test with ANSI codes
    $testCmd = "printf '\x1b[31mred text\x1b[0m \x1b[32mgreen text\x1b[0m normal text\n'"
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($testCmd))
    $result = & node $runner "git-status" $b64 2>&1 | Out-String
    if ($result -match '\x1b') {
        Write-Host "FAIL: ANSI codes still present" -ForegroundColor Red
    } else {
        Write-Host "PASS: ANSI codes stripped" -ForegroundColor Green
    }
    Write-Host "  Output: $($result.Trim())"
}

Write-Host "`n=== Tests Complete ===" -ForegroundColor Cyan
Write-Host "`nCheck stats with: node `"$PSScriptRoot\stats.js`" --today"
