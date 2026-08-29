[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compositeInstaller = Join-Path $root 'skills\quota-aware-runner\scripts\install-agents.ps1'
$canonicalInstaller = Join-Path $root 'skills\sol-luna-handoff\scripts\install-agents.ps1'
$temporaryRoot = if ($env:TEST_TEMP_ROOT) { $env:TEST_TEMP_ROOT } else { [System.IO.Path]::GetTempPath() }
$agentNames = @(
    'sol-planner.toml', 'sol-compact-planner.toml', 'luna-scout.toml',
    'terra-executor.toml', 'luna-executor.toml', 'luna-fast-executor.toml'
)

function New-TestHome {
    $path = Join-Path $temporaryRoot ('quota-aware-runner-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    return $path
}

function Invoke-InHome {
    param([string]$HomePath, [string]$Installer)
    $env:CODEX_HOME = $HomePath
    & $Installer | Out-Null
}

$homes = @()
try {
    # A composite-only install gets all agents and no dangling global activation.
    $compositeOnly = New-TestHome
    $homes += $compositeOnly
    Invoke-InHome $compositeOnly $compositeInstaller
    foreach ($name in $agentNames) {
        if (-not (Test-Path -LiteralPath (Join-Path $compositeOnly "agents\$name"))) {
            throw "missing installed agent: $name"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $compositeOnly 'AGENTS.md')) {
        throw 'composite-only bootstrap must not create global AGENTS.md'
    }

    # Canonical followed by composite preserves the canonical managed block byte-for-byte.
    $canonicalFirst = New-TestHome
    $homes += $canonicalFirst
    Invoke-InHome $canonicalFirst $canonicalInstaller
    $globalPath = Join-Path $canonicalFirst 'AGENTS.md'
    $before = [System.IO.File]::ReadAllBytes($globalPath)
    Invoke-InHome $canonicalFirst $compositeInstaller
    $after = [System.IO.File]::ReadAllBytes($globalPath)
    if ([System.BitConverter]::ToString($before) -cne [System.BitConverter]::ToString($after)) {
        throw 'composite bootstrap must not alter the canonical managed block'
    }

    # Composite followed by canonical is conflict-free and creates one canonical block.
    $compositeFirst = New-TestHome
    $homes += $compositeFirst
    Invoke-InHome $compositeFirst $compositeInstaller
    Invoke-InHome $compositeFirst $canonicalInstaller
    $global = [System.IO.File]::ReadAllText((Join-Path $compositeFirst 'AGENTS.md'))
    if (([regex]::Matches($global, '<!-- BEGIN SOL-LUNA-HANDOFF MANAGED BLOCK -->')).Count -ne 1) {
        throw 'combined bootstrap must contain exactly one canonical managed block'
    }
    if (-not $global.Contains('load and follow `$sol-luna-handoff`')) {
        throw 'combined bootstrap must retain canonical Sol activation ownership'
    }
    if ($global.Contains('$quota-aware-runner')) {
        throw 'combined bootstrap must not add a competing composite activation block'
    }
    Write-Output 'PASS composite-only and combined bootstrap activation ownership'
} finally {
    Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    foreach ($homePath in $homes) {
        Remove-Item -LiteralPath $homePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
