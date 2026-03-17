# claude-token-saver install script
# Registers the PreToolUse hook in ~/.claude/settings.json
# No admin rights required - everything is in user space

param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$settingsPath = Join-Path (Join-Path $env:USERPROFILE '.claude') 'settings.json'
$hookCommand = "node `"$($PSScriptRoot.Replace('\', '/') )/hook.js`""
$dataDir = Join-Path $env:USERPROFILE '.claude-token-saver'

if ($Uninstall) {
    # Remove hook from settings.json
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

        if ($settings.hooks -and $settings.hooks.PreToolUse) {
            $filtered = @($settings.hooks.PreToolUse | Where-Object {
                $dominated = $false
                if ($_.hooks) {
                    foreach ($h in $_.hooks) {
                        if ($h.command -and $h.command -like '*claude-token-saver*') {
                            $dominated = $true
                        }
                    }
                }
                -not $dominated
            })

            if ($filtered.Count -eq 0) {
                $settings.hooks.PSObject.Properties.Remove('PreToolUse')
            } else {
                $settings.hooks.PreToolUse = $filtered
            }

            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
            Write-Host "[OK] Hook removed from settings.json" -ForegroundColor Green
        } else {
            Write-Host "[--] No hook found in settings.json" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "Uninstall complete. Tracking data kept in: $dataDir"
    Write-Host "To remove tracking data: Remove-Item -Recurse '$dataDir'"
    exit 0
}

# --- Install ---

# Ensure settings.json exists
$claudeDir = Join-Path $env:USERPROFILE '.claude'
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

if (-not (Test-Path $settingsPath)) {
    '{}' | Set-Content $settingsPath -Encoding UTF8
}

# Read current settings
$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

# Ensure hooks object exists
if (-not $settings.hooks) {
    $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{})
}

# Check if our hook already exists
$alreadyInstalled = $false
if ($settings.hooks.PreToolUse) {
    foreach ($entry in $settings.hooks.PreToolUse) {
        if ($entry.hooks) {
            foreach ($h in $entry.hooks) {
                if ($h.command -and $h.command -like '*claude-token-saver*') {
                    $alreadyInstalled = $true
                }
            }
        }
    }
}

if ($alreadyInstalled) {
    Write-Host "[OK] Hook already installed" -ForegroundColor Green
} else {
    # Create hook entry
    $hookEntry = [PSCustomObject]@{
        matcher = 'Bash'
        hooks = @(
            [PSCustomObject]@{
                type = 'command'
                command = $hookCommand
            }
        )
    }

    # Add to PreToolUse array
    if ($settings.hooks.PreToolUse) {
        $settings.hooks.PreToolUse = @($settings.hooks.PreToolUse) + $hookEntry
    } else {
        $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{
            PreToolUse = @($hookEntry)
        }) -Force

        # Preserve existing hooks (Stop, Notification, etc.)
        $raw = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($raw.hooks) {
            foreach ($prop in $raw.hooks.PSObject.Properties) {
                if ($prop.Name -ne 'PreToolUse') {
                    $settings.hooks | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            }
        }
    }

    # Write back
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "[OK] Hook registered in settings.json" -ForegroundColor Green
}

# Create data directory
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    Write-Host "[OK] Created data directory: $dataDir" -ForegroundColor Green
}

# Verify node is available
$nodeVersion = & node --version 2>$null
if ($nodeVersion) {
    Write-Host "[OK] Node.js found: $nodeVersion" -ForegroundColor Green
} else {
    Write-Host "[!!] Node.js not found in PATH - hook won't work without it" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Installation complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "The token saver is now active. Restart Claude Code for the hook to take effect."
Write-Host ""
Write-Host "Commands:"
Write-Host "  View stats:    node `"$PSScriptRoot\stats.js`""
Write-Host "  Bypass filter: Add # nofilter to any command"
Write-Host "  Uninstall:     .\install.ps1 -Uninstall"
Write-Host "  Config:        Edit config.json to tune filter limits"
