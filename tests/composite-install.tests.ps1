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
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$canonicalSkillPath = Join-Path $root 'skills\sol-luna-handoff\SKILL.md'
$compositeSkillPath = Join-Path $root 'skills\quota-aware-runner\SKILL.md'
$routingMarker = '## Deterministic routing'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

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
    # The composite-owned orchestration prefix may differ, but its complete routing tail is canonical.
    $canonicalSkill = [System.IO.File]::ReadAllText($canonicalSkillPath, $utf8Strict)
    $compositeSkill = [System.IO.File]::ReadAllText($compositeSkillPath, $utf8Strict)
    $canonicalIndex = $canonicalSkill.IndexOf($routingMarker)
    $compositeIndex = $compositeSkill.IndexOf($routingMarker)
    if ($canonicalIndex -lt 0 -or $compositeIndex -lt 0) {
        throw 'canonical and composite Skills must contain the deterministic routing marker'
    }
    if ($canonicalSkill.Substring($canonicalIndex) -cne $compositeSkill.Substring($compositeIndex)) {
        throw 'composite deterministic routing tail must equal the canonical Skill tail'
    }
    if (-not $compositeSkill.Contains('The default Tier 2 executor is `luna_executor`')) {
        throw 'composite must carry the Luna-first Tier 2 contract'
    }
    if (-not $compositeSkill.Contains('Profile: adaptive|sol-luna') -or
        -not $compositeSkill.Contains('missing configuration as `sol-luna`') -or
        -not $compositeSkill.Contains('Tier 2 and Tier 3 always select `luna_executor`')) {
        throw 'composite must carry the default Sol-Luna profile contract'
    }
    foreach ($name in $agentNames) {
        $canonicalAsset = Join-Path $root "skills\sol-luna-handoff\assets\$name"
        $compositeAsset = Join-Path $root "skills\quota-aware-runner\assets\$name"
        if ((Get-FileHash -LiteralPath $canonicalAsset -Algorithm SHA256).Hash -cne
            (Get-FileHash -LiteralPath $compositeAsset -Algorithm SHA256).Hash) {
            throw "composite agent asset must match canonical bytes: $name"
        }
    }

    # The agents-only bootstrap must accept exactly the upstream-verified legacy definitions.
    $canonicalInstallerText = [System.IO.File]::ReadAllText($canonicalInstaller, $utf8Strict)
    $compositeInstallerText = [System.IO.File]::ReadAllText($compositeInstaller, $utf8Strict)
    $mapPattern = '(?s)\$knownLegacyAgentHashes = @\{.*?\r?\n\}'
    $canonicalMap = [regex]::Match($canonicalInstallerText, $mapPattern).Value
    $compositeMap = [regex]::Match($compositeInstallerText, $mapPattern).Value
    $canonicalMapNormalized = $canonicalMap.Replace("`r`n", "`n")
    $compositeMapNormalized = $compositeMap.Replace("`r`n", "`n")
    if ([string]::IsNullOrEmpty($canonicalMap) -or $canonicalMapNormalized -cne $compositeMapNormalized) {
        throw 'composite legacy allowlist must exactly match the canonical upstream-verified map'
    }

    $legacyHome = New-TestHome
    $homes += $legacyHome
    $legacyAgents = Join-Path $legacyHome 'agents'
    New-Item -ItemType Directory -Path $legacyAgents | Out-Null
    $legacyLuna = (@(
        'name = "luna_executor"',
        'description = "Implements an approved plan, runs its checks, and returns concise evidence."',
        'model = "gpt-5.6-luna"',
        'model_reasoning_effort = "medium"',
        'sandbox_mode = "workspace-write"',
        'developer_instructions = """',
        'Execute the supplied plan as a binding contract. Make only in-scope changes, run every specified verification command, inspect the resulting diff, and self-review against every acceptance criterion. Stop before further edits and report UPGRADE_NEEDED if discovered scope or risk exceeds the supplied tier. Return a report capped at 300 output tokens with changed files, concise summary, commands and exit status, self-review, and remaining concerns or NONE; raw command output may be stored in files and is excluded from the cap. If context is missing, return NEEDS_CONTEXT with exact missing facts. Do not redesign or broaden scope.',
        '"""'
    ) -join "`n") + "`n"
    [System.IO.File]::WriteAllBytes((Join-Path $legacyAgents 'luna-executor.toml'), $utf8NoBom.GetBytes($legacyLuna))
    Invoke-InHome $legacyHome $compositeInstaller
    foreach ($name in $agentNames) {
        if ((Get-FileHash -LiteralPath (Join-Path $legacyAgents $name) -Algorithm SHA256).Hash -cne
            (Get-FileHash -LiteralPath (Join-Path $root "skills\sol-luna-handoff\assets\$name") -Algorithm SHA256).Hash) {
            throw "composite legacy upgrade must install canonical bytes: $name"
        }
    }

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
