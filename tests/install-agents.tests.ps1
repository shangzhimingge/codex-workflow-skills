[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$skillDirectory = Join-Path $repositoryRoot 'skills\sol-luna-handoff'
$installerPath = Join-Path $skillDirectory 'scripts\install-agents.ps1'
$assetsDirectory = Join-Path $skillDirectory 'assets'
$agentFiles = @(
    'sol-planner.toml',
    'sol-compact-planner.toml',
    'luna-scout.toml',
    'terra-executor.toml',
    'luna-executor.toml',
    'luna-fast-executor.toml'
)
$startMarker = '<!-- BEGIN SOL-LUNA-HANDOFF MANAGED BLOCK -->'
$endMarker = '<!-- END SOL-LUNA-HANDOFF MANAGED BLOCK -->'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function New-TemporaryCodexHome {
    $temporaryRoot = if ($env:TEST_TEMP_ROOT) { $env:TEST_TEMP_ROOT } else { [System.IO.Path]::GetTempPath() }
    $path = Join-Path $temporaryRoot ("sol-luna-handoff-test-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function Invoke-TestInstaller {
    param(
        [Parameter(Mandatory)]
        [string]$CodexHome,

        [switch]$WhatIf
    )

    $hadCodexHome = Test-Path Env:CODEX_HOME
    $previousCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = $CodexHome
        & $installerPath -WhatIf:$WhatIf | Out-Null
    } finally {
        if ($hadCodexHome) {
            $env:CODEX_HOME = $previousCodexHome
        } else {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        }
    }
}

function Get-FileState {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not [System.IO.File]::Exists($Path)) {
        return 'MISSING'
    }

    $item = Get-Item -LiteralPath $Path
    return "FILE|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)|$((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash)"
}

function Get-DirectoryState {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not [System.IO.Directory]::Exists($Path)) {
        return 'MISSING'
    }

    $rows = Get-ChildItem -LiteralPath $Path -Recurse -Force -File |
        Sort-Object FullName |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($Path.Length).TrimStart('\')
            "$relativePath|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        }
    return "DIRECTORY`n$($rows -join "`n")"
}

function Test-DifferingAgentCollisions {
    foreach ($fileName in $agentFiles) {
        $codexHome = New-TemporaryCodexHome
        try {
            $agentsDirectory = Join-Path $codexHome 'agents'
            [System.IO.Directory]::CreateDirectory($agentsDirectory) | Out-Null
            $collisionPath = Join-Path $agentsDirectory $fileName
            [System.IO.File]::WriteAllText($collisionPath, 'existing custom definition', $utf8NoBom)
            $globalAgentsPath = Join-Path $codexHome 'AGENTS.md'
            [System.IO.File]::WriteAllText($globalAgentsPath, "# Existing global rules`n", $utf8NoBom)

            $agentsBefore = Get-DirectoryState $agentsDirectory
            $globalBefore = Get-FileState $globalAgentsPath
            $caughtMessage = $null
            try {
                Invoke-TestInstaller $codexHome
            } catch {
                $caughtMessage = $_.Exception.Message
            }

            Assert-True ($null -ne $caughtMessage) "a differing $fileName must abort installation"
            Assert-True ($caughtMessage.Contains($collisionPath)) 'the collision error must name the destination'
            Assert-True ((Get-DirectoryState $agentsDirectory) -ceq $agentsBefore) 'collision abort must leave the agents directory unchanged'
            Assert-True ((Get-FileState $globalAgentsPath) -ceq $globalBefore) 'collision abort must leave AGENTS.md unchanged'
            foreach ($otherFileName in $agentFiles | Where-Object { $_ -cne $fileName }) {
                Assert-True (-not (Test-Path -LiteralPath (Join-Path $agentsDirectory $otherFileName))) 'collision preflight must not install another agent'
            }
            Write-Output "PASS differing $fileName collision aborts without mutation"
        } finally {
            Remove-Item -LiteralPath $codexHome -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-FreshInstall {
    $codexHome = New-TemporaryCodexHome
    try {
        Invoke-TestInstaller $codexHome
        $agentsDirectory = Join-Path $codexHome 'agents'
        foreach ($fileName in $agentFiles) {
            $installedPath = Join-Path $agentsDirectory $fileName
            $assetPath = Join-Path $assetsDirectory $fileName
            Assert-True (Test-Path -LiteralPath $installedPath) "fresh install must create $fileName"
            Assert-True (
                (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash -ceq
                (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash
            ) "fresh install must copy $fileName exactly"
        }

        $globalContent = [System.IO.File]::ReadAllText((Join-Path $codexHome 'AGENTS.md'))
        Assert-True ($globalContent.Contains($startMarker)) 'fresh install must add the managed start marker'
        Assert-True ($globalContent.Contains($endMarker)) 'fresh install must add the managed end marker'
        Write-Output 'PASS fresh install copies agents and global block'
    } finally {
        Remove-Item -LiteralPath $codexHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-V100LunaExecutorContent {
    param(
        [ValidateSet('LF', 'CRLF')]
        [string]$NewlineStyle = 'LF'
    )

    $newline = if ($NewlineStyle -ceq 'CRLF') { "`r`n" } else { "`n" }
    return (@(
        'name = "luna_executor"',
        'description = "Implements an approved plan, runs its checks, and returns concise evidence."',
        'model = "gpt-5.6-luna"',
        'model_reasoning_effort = "medium"',
        'sandbox_mode = "workspace-write"',
        'developer_instructions = """',
        'Execute the supplied plan as a binding contract. Make only in-scope changes, run every specified verification command, inspect the resulting diff, and report changed files, command outputs, and remaining concerns. If context is missing, return NEEDS_CONTEXT with exact missing facts. Do not redesign the task or broaden scope.',
        '"""'
    ) -join $newline) + $newline
}

function Test-V100Upgrade {
    foreach ($newlineStyle in @('LF', 'CRLF')) {
        $codexHome = New-TemporaryCodexHome
        try {
            $agentsDirectory = Join-Path $codexHome 'agents'
            [System.IO.Directory]::CreateDirectory($agentsDirectory) | Out-Null
            [System.IO.File]::WriteAllBytes(
                (Join-Path $agentsDirectory 'sol-planner.toml'),
                [System.IO.File]::ReadAllBytes((Join-Path $assetsDirectory 'sol-planner.toml'))
            )
            [System.IO.File]::WriteAllBytes(
                (Join-Path $agentsDirectory 'luna-executor.toml'),
                $utf8NoBom.GetBytes((Get-V100LunaExecutorContent -NewlineStyle $newlineStyle))
            )

            $oldManagedBlock = @(
                $startMarker,
                '## Sol-Luna project workflow',
                '',
                'For every project artifact task, use the fixed Sol-Luna-Sol route.',
                $endMarker
            ) -join "`n"
            $globalAgentsPath = Join-Path $codexHome 'AGENTS.md'
            [System.IO.File]::WriteAllText($globalAgentsPath, "# Keep this rule`n`n$oldManagedBlock`n", $utf8NoBom)

            Invoke-TestInstaller $codexHome

            foreach ($fileName in $agentFiles) {
                Assert-True (
                    (Get-FileHash -LiteralPath (Join-Path $agentsDirectory $fileName) -Algorithm SHA256).Hash -ceq
                    (Get-FileHash -LiteralPath (Join-Path $assetsDirectory $fileName) -Algorithm SHA256).Hash
                ) "v1.0 $newlineStyle upgrade must install the canonical $fileName bytes"
            }
            $globalContent = [System.IO.File]::ReadAllText($globalAgentsPath)
            Assert-True ($globalContent.Contains('# Keep this rule')) 'v1.0 upgrade must preserve unrelated global guidance'
            Assert-True ($globalContent.Contains('adaptive Tier 1, Tier 2, and Tier 3')) 'v1.0 upgrade must replace the managed rule'
            Write-Output "PASS v1.0 $newlineStyle built-in agent upgrades to v1.2"
        } finally {
            Remove-Item -LiteralPath $codexHome -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-V110CompactPlannerContent {
    param(
        [ValidateSet('LF', 'CRLF')]
        [string]$NewlineStyle = 'LF'
    )

    $newline = if ($NewlineStyle -ceq 'CRLF') { "`r`n" } else { "`n" }
    return (@(
        'name = "sol_compact_planner"',
        'description = "Produces a bounded plan for medium, low-risk project work."',
        'model = "gpt-5.6-sol"',
        'model_reasoning_effort = "medium"',
        'sandbox_mode = "read-only"',
        'developer_instructions = """',
        'Inspect only task-local context and return a plan capped at 500 output tokens. Include only scope and non-goals, ordered steps, affected files, verification commands, and testable acceptance criteria. If essential context is missing, return NEEDS_CONTEXT with the exact missing facts. Do not implement, broaden scope, or perform final verification.',
        '"""'
    ) -join $newline) + $newline
}

function Get-V110BundledAgentContent {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('sol-planner.toml', 'luna-executor.toml', 'luna-fast-executor.toml')]
        [string]$FileName,

        [ValidateSet('LF', 'CRLF')]
        [string]$NewlineStyle = 'LF'
    )

    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    $content = [System.IO.File]::ReadAllText((Join-Path $assetsDirectory $FileName), $utf8Strict)
    $lfContent = $content.Replace("`r`n", "`n").Replace("`r", "`n")
    if ($NewlineStyle -ceq 'CRLF') {
        return $lfContent.Replace("`n", "`r`n")
    }
    return $lfContent
}

function Install-V110AgentFixtures {
    param(
        [Parameter(Mandatory)]
        [string]$AgentsDirectory,

        [ValidateSet('LF', 'CRLF')]
        [string]$NewlineStyle = 'LF'
    )

    foreach ($fileName in @('sol-planner.toml', 'luna-executor.toml', 'luna-fast-executor.toml')) {
        [System.IO.File]::WriteAllBytes(
            (Join-Path $AgentsDirectory $fileName),
            $utf8NoBom.GetBytes((Get-V110BundledAgentContent -FileName $fileName -NewlineStyle $NewlineStyle))
        )
    }
    [System.IO.File]::WriteAllBytes(
        (Join-Path $AgentsDirectory 'sol-compact-planner.toml'),
        $utf8NoBom.GetBytes((Get-V110CompactPlannerContent -NewlineStyle $NewlineStyle))
    )
}

function Test-V110Upgrade {
    $expectedLegacyHashes = @{
        'sol-planner.toml' = @{
            'LF' = '7B6FB8A14C22354125C08BC255F4203B7BF8EBF505209402FA8A7BBD91EBA431'
            'CRLF' = '140A285E3485546848294A9DE46AA96E7B021B24AA8A83BC8E546854D9B93B4F'
        }
        'sol-compact-planner.toml' = @{
            'LF' = 'E8E9F21443434F523AA71DF343965ACDE93AD8ECEC3293F90F8386E4A5046A36'
            'CRLF' = '2C7A9FE24E737DC1DD3D6E97CAC9745EB42CA0174587DEB083FC66C7C07DAA8A'
        }
        'luna-executor.toml' = @{
            'LF' = '91AA121E7248CA507FFB594D7768595E1E0C6267BD5435745DC2573DAB9957FA'
            'CRLF' = '89864C97A3DC252F684CA46BC405E414D4811465517F5D721AABC9C8AAE2669D'
        }
        'luna-fast-executor.toml' = @{
            'LF' = '5400B0F6F9EE8CAAD4678779A6FB89F99C59835669BF579DD0A70F1F05BF9393'
            'CRLF' = '099C58C9F0AF4B6B2A0F923782E0953BB798FB8AA48ED29EDF7E2550EAA3F5A6'
        }
    }

    foreach ($newlineStyle in @('LF', 'CRLF')) {
        $codexHome = New-TemporaryCodexHome
        try {
            $agentsDirectory = Join-Path $codexHome 'agents'
            [System.IO.Directory]::CreateDirectory($agentsDirectory) | Out-Null
            Install-V110AgentFixtures -AgentsDirectory $agentsDirectory -NewlineStyle $newlineStyle
            foreach ($fileName in $expectedLegacyHashes.Keys) {
                Assert-True (
                    (Get-FileHash -LiteralPath (Join-Path $agentsDirectory $fileName) -Algorithm SHA256).Hash -ceq
                    $expectedLegacyHashes[$fileName][$newlineStyle]
                ) "v1.1 $newlineStyle $fileName fixture must match the approved legacy hash"
            }

            $globalAgentsPath = Join-Path $codexHome 'AGENTS.md'
            [System.IO.File]::WriteAllText($globalAgentsPath, "# Keep this v1.1 rule`n", $utf8NoBom)

            Invoke-TestInstaller $codexHome

            foreach ($fileName in $agentFiles) {
                Assert-True (
                    (Get-FileHash -LiteralPath (Join-Path $agentsDirectory $fileName) -Algorithm SHA256).Hash -ceq
                    (Get-FileHash -LiteralPath (Join-Path $assetsDirectory $fileName) -Algorithm SHA256).Hash
                ) "v1.1 $newlineStyle upgrade must install the canonical $fileName bytes"
            }
            $globalContent = [System.IO.File]::ReadAllText($globalAgentsPath)
            Assert-True ($globalContent.Contains('# Keep this v1.1 rule')) 'v1.1 upgrade must preserve unrelated global guidance'
            Write-Output "PASS v1.1 $newlineStyle built-in agents upgrade to v1.2"
        } finally {
            Remove-Item -LiteralPath $codexHome -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-V110UpgradeWithLaterUnknownCollisionIsAtomic {
    $codexHome = New-TemporaryCodexHome
    try {
        $agentsDirectory = Join-Path $codexHome 'agents'
        [System.IO.Directory]::CreateDirectory($agentsDirectory) | Out-Null
        Install-V110AgentFixtures -AgentsDirectory $agentsDirectory -NewlineStyle 'LF'
        $unknownCollisionPath = Join-Path $agentsDirectory 'terra-executor.toml'
        [System.IO.File]::WriteAllText($unknownCollisionPath, 'unknown custom Terra definition', $utf8NoBom)
        $globalAgentsPath = Join-Path $codexHome 'AGENTS.md'
        [System.IO.File]::WriteAllText($globalAgentsPath, "# Keep this v1.1 rule`n", $utf8NoBom)

        $agentsBefore = Get-DirectoryState $agentsDirectory
        $globalBefore = Get-FileState $globalAgentsPath
        $caughtMessage = $null
        try {
            Invoke-TestInstaller $codexHome
        } catch {
            $caughtMessage = $_.Exception.Message
        }

        Assert-True ($null -ne $caughtMessage) 'a later unknown collision must abort a v1.1 migration'
        Assert-True ($caughtMessage.Contains($unknownCollisionPath)) 'the later collision must name the unknown destination'
        Assert-True ((Get-DirectoryState $agentsDirectory) -ceq $agentsBefore) 'known legacy files must remain byte-identical when a later collision aborts preflight'
        Assert-True ((Get-FileState $globalAgentsPath) -ceq $globalBefore) 'AGENTS.md must remain unchanged when a later collision aborts preflight'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $agentsDirectory 'luna-scout.toml'))) 'preflight abort must not create a missing new agent'
        Write-Output 'PASS v1.1 legacy migration plus later unknown collision aborts atomically'
    } finally {
        Remove-Item -LiteralPath $codexHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-MalformedGlobalMarkers {
    $codexHome = New-TemporaryCodexHome
    try {
        $globalAgentsPath = Join-Path $codexHome 'AGENTS.md'
        [System.IO.File]::WriteAllText($globalAgentsPath, "$startMarker`nmissing end marker`n", $utf8NoBom)
        $globalBefore = Get-FileState $globalAgentsPath
        $caughtMessage = $null
        try {
            Invoke-TestInstaller $codexHome
        } catch {
            $caughtMessage = $_.Exception.Message
        }

        Assert-True ($null -ne $caughtMessage) 'malformed global markers must abort installation'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $codexHome 'agents'))) 'marker validation must occur before agent-directory creation'
        Assert-True ((Get-FileState $globalAgentsPath) -ceq $globalBefore) 'marker failure must leave AGENTS.md unchanged'
        Write-Output 'PASS malformed global markers abort before mutation'
    } finally {
        Remove-Item -LiteralPath $codexHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-IdenticalFilesAreIdempotent {
    $codexHome = New-TemporaryCodexHome
    try {
        $agentsDirectory = Join-Path $codexHome 'agents'
        [System.IO.Directory]::CreateDirectory($agentsDirectory) | Out-Null
        foreach ($fileName in $agentFiles) {
            [System.IO.File]::WriteAllBytes(
                (Join-Path $agentsDirectory $fileName),
                [System.IO.File]::ReadAllBytes((Join-Path $assetsDirectory $fileName))
            )
        }

        $globalAgentsPath = Join-Path $codexHome 'AGENTS.md'
        [System.IO.File]::WriteAllText($globalAgentsPath, "# Existing global rules`n", $utf8NoBom)
        $agentsBeforeFirstRun = Get-DirectoryState $agentsDirectory

        Invoke-TestInstaller $codexHome
        Assert-True ((Get-DirectoryState $agentsDirectory) -ceq $agentsBeforeFirstRun) 'identical existing agents must not be rewritten'

        $agentsAfterFirstRun = Get-DirectoryState $agentsDirectory
        $globalAfterFirstRun = Get-FileState $globalAgentsPath
        $globalContent = [System.IO.File]::ReadAllText($globalAgentsPath)
        Assert-True ($globalContent.Contains('# Existing global rules')) 'install must preserve unrelated global guidance'
        Assert-True (([regex]::Matches($globalContent, [regex]::Escape($startMarker))).Count -eq 1) 'the managed start marker must occur once'
        Assert-True (([regex]::Matches($globalContent, [regex]::Escape($endMarker))).Count -eq 1) 'the managed end marker must occur once'

        Start-Sleep -Milliseconds 1100
        Invoke-TestInstaller $codexHome
        Assert-True ((Get-DirectoryState $agentsDirectory) -ceq $agentsAfterFirstRun) 'a repeated install must not rewrite identical agents'
        Assert-True ((Get-FileState $globalAgentsPath) -ceq $globalAfterFirstRun) 'a repeated install must not rewrite identical AGENTS.md content'
        Write-Output 'PASS identical files and managed block are idempotent'
    } finally {
        Remove-Item -LiteralPath $codexHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-WhatIfDoesNotMutate {
    $codexHome = New-TemporaryCodexHome
    try {
        $globalAgentsPath = Join-Path $codexHome 'AGENTS.md'
        [System.IO.File]::WriteAllText($globalAgentsPath, "# Existing global rules`n", $utf8NoBom)
        $homeBefore = Get-DirectoryState $codexHome

        Invoke-TestInstaller -CodexHome $codexHome -WhatIf

        Assert-True ((Get-DirectoryState $codexHome) -ceq $homeBefore) '-WhatIf must not mutate CODEX_HOME'
        Write-Output 'PASS -WhatIf performs no mutation'
    } finally {
        Remove-Item -LiteralPath $codexHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-AdaptiveRoutingContracts {
    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    $skillPath = Join-Path $skillDirectory 'SKILL.md'
    $skill = [System.IO.File]::ReadAllText($skillPath, $utf8Strict)
    $globalRule = [System.IO.File]::ReadAllText((Join-Path $assetsDirectory 'global-agents.md'), $utf8Strict)
    $interfaceMetadata = [System.IO.File]::ReadAllText((Join-Path $skillDirectory 'agents\openai.yaml'), $utf8Strict)

    Assert-True ($skill.Contains('Tier 1')) 'Skill must define Tier 1'
    Assert-True ($skill.Contains('Tier 2')) 'Skill must define Tier 2'
    Assert-True ($skill.Contains('Tier 3')) 'Skill must define Tier 3'
    Assert-True ($skill.Contains('at most 2 expected changed files')) 'Tier 1 must cap files at two'
    Assert-True ($skill.Contains('at most 100 expected changed lines')) 'Tier 1 must cap changed lines at 100'
    Assert-True ($skill.Contains('exactly 1 subsystem')) 'Tier 1 must require one subsystem'
    Assert-True ($skill.Contains('Default to Tier 2')) 'bounded non-Tier-1 work must deterministically default to Tier 2'
    $tier3Index = $skill.IndexOf('Tier 3, Tier 1, then Tier 2')
    Assert-True ($tier3Index -ge 0) 'routing must state the Tier 3 then Tier 1 then Tier 2 classification order'
    $tier1Index = $skill.IndexOf('Tier 1', $tier3Index + 'Tier 3'.Length)
    $tier2Index = $skill.IndexOf('Tier 2', $tier1Index + 'Tier 1'.Length)
    Assert-True ($tier3Index -lt $tier1Index -and $tier1Index -lt $tier2Index) 'routing order must be Tier 3 then Tier 1 then Tier 2'
    Assert-True ($skill.Contains('Scout: yes|no')) 'route line must expose the Scout decision'
    Assert-True ($skill.Contains('Planner: none|compact|full')) 'route line must expose the planner decision'
    Assert-True ($skill.Contains('Executor: luna|terra')) 'route line must expose the executor decision'
    $tierState = $skill.IndexOf('State 1 - classify Tier')
    $scoutState = $skill.IndexOf('State 2 - decide and run Scout')
    $plannerState = $skill.IndexOf('State 3 - decide Planner from Scout evidence')
    $executorState = $skill.IndexOf('State 4 - decide Executor')
    $routeState = $skill.IndexOf('State 5 - emit the final route')
    Assert-True ($tierState -ge 0 -and $tierState -lt $scoutState -and $scoutState -lt $plannerState -and $plannerState -lt $executorState -and $executorState -lt $routeState) 'routing must complete Tier, Scout, Planner, Executor, then final route in order'
    Assert-True ($skill.Contains('Do not emit the final route line before Scout has completed or been skipped')) 'routing must not claim a final decision before Scout'
    Assert-True ($skill.Contains('Emit exactly one final route line immediately before Planner or Executor delegation')) 'routing must emit one final route before implementation delegation'
    Assert-True ($skill.Contains('Tier 1 always records `Scout: no` and skips Scout without evaluating the Conditional Scout triggers, even when supplied diagnostics exceed 500 lines or another discovery trigger appears applicable.')) 'Tier 1 must remain Scout-free even when a discovery trigger superficially matches'
    Assert-True ($skill.Contains('## Conditional Scout for Tier 2 and Tier 3')) 'Conditional Scout heading must limit the mechanism to Tier 2 and Tier 3'
    Assert-True ($skill.Contains('These triggers apply only to Tier 2 and Tier 3. Tier 1 remains Scout-free.')) 'Conditional Scout body must exclude Tier 1'
    foreach ($risk in @('security', 'authentication', 'authorization', 'cryptography', 'data migration', 'destructive operation', 'deployment', 'public API', 'concurrency', 'dependency migration', 'architecture', 'ambiguous requirements')) {
        Assert-True ($skill.Contains($risk)) "Tier 3 must include the $risk predicate"
    }
    Assert-True ($skill.Contains('more than 8 expected changed files')) 'Tier 3 must apply above eight files'
    Assert-True ($skill.Contains('Never downgrade after editing starts')) 'routing must prohibit post-edit downgrades'
    Assert-True ($skill.Contains('more than 500 lines')) 'Scout must have a deterministic diagnostic-size trigger'
    Assert-True ($skill.Contains('relevant files or key symbols are not located')) 'Scout must trigger when files or symbols require cross-subsystem discovery'
    Assert-True ($skill.Contains('modules crossed by the call chain are unclear')) 'Scout must trigger when the call chain modules are unclear'
    Assert-True ($skill.Contains('planner would otherwise need a broad repository search')) 'Scout must trigger before broad planner repository search'
    Assert-True ($skill.Contains('400 output tokens')) 'compact plans must be capped at 400 output tokens'
    Assert-True ($skill.Contains('after Scout, the root cause still requires a choice among multiple candidate approaches')) 'compact planning must trigger for unresolved candidate approaches'
    Assert-True ($skill.Contains('change crosses multiple subsystems with ordering or dependency relationships')) 'compact planning must trigger for ordered cross-subsystem work'
    Assert-True ($skill.Contains('compatibility constraints or a new cross-file invariant exist')) 'compact planning must trigger for compatibility or cross-file invariants'
    Assert-True ($skill.Contains('acceptance criteria permit multiple implementations with material tradeoffs')) 'compact planning must trigger for material implementation tradeoffs'
    Assert-True ($skill.Contains('implementation strategy is completely explicit')) 'Tier 2 Luna must require a completely explicit strategy'
    foreach ($mechanicalKind in @('local', 'mechanical', 'repetitive', 'configuration', 'test', 'documentation editing')) {
        Assert-True ($skill.Contains($mechanicalKind)) "Tier 2 Luna boundary must cover $mechanicalKind work"
    }
    Assert-True ($skill.Contains('Choose `luna_executor` only when the implementation strategy is completely explicit and the work is local, mechanical, repetitive, configuration, test, or documentation editing that requires no derivation of cross-file invariants and no handling of unknown test failures.')) 'Tier 2 Luna must satisfy the complete positive and negative mechanical boundary'
    Assert-True ($skill.Contains('no derivation of cross-file invariants')) 'Tier 2 Luna must exclude cross-file invariant reasoning'
    Assert-True ($skill.Contains('no handling of unknown test failures')) 'Tier 2 Luna must exclude unknown test failures'
    Assert-True ($skill.Contains('Choose `terra_executor` for every other Tier 2 task')) 'Tier 2 must route non-mechanical work to Terra'
    Assert-True ($skill.Contains('Use `terra_executor` as the main executor for every Tier 3 task')) 'Tier 3 must use Terra as the main executor'
    Assert-True ($skill.Contains('mandatory high-reasoning verification')) 'Tier 3 must require final Sol verification'
    Assert-True ($skill.Contains('300 output tokens')) 'executor reports must be capped at 300 output tokens'
    Assert-True ($skill.Contains('After 2 correction rounds')) 'two correction rounds must trigger replanning'
    Assert-True ($skill.Contains('under one task brief or plan')) 'correction counting must cover task briefs and plans'
    Assert-True ($skill.Contains('Planner: none') -and $skill.Contains('invoke `sol_compact_planner` before any further correction')) 'Planner-none work must compact-plan after two corrections'
    Assert-True ($skill.Contains('work already governed by a compact or full plan, return to the applicable Sol planner')) 'planned work must return to its applicable Sol planner after two corrections'
    Assert-True ($skill.Contains('Tier 1') -and $skill.Contains('return `UPGRADE_NEEDED`, reclassify as at least Tier 2')) 'Tier 1 must upgrade after two corrections'
    Assert-True ($skill.Contains('at most one additional Luna worker')) 'agent fan-out must be bounded'
    Assert-True ($skill.Contains('terra_executor')) 'routing must provide the Terra lane'
    Assert-True ($skill.Contains('luna_scout')) 'routing must provide conditional discovery'
    Assert-True ($skill.Contains('Skip Sol')) 'Tier 2 must allow planning-free bounded work'

    Assert-True ($globalRule.Contains('load and follow `$sol-luna-handoff`')) 'global rule must load the Skill'
    Assert-True ($globalRule.Contains('select the route')) 'global rule must delegate adaptive route selection'
    Assert-True (-not $globalRule.Contains('Route the work through Sol planning, Luna execution, and Sol verification')) 'global rule must not mandate the fixed pipeline'
    Assert-True ($interfaceMetadata.Contains('Terra/Luna Handoff')) 'interface metadata must name both execution lanes'
    Assert-True ($interfaceMetadata.Contains('balanced Scout, planning, and execution routing')) 'interface metadata must describe balanced routing'
    Assert-True ($interfaceMetadata.Contains('conditional Luna discovery')) 'interface prompt must request conditional discovery'
    Assert-True ($interfaceMetadata.Contains('minimum necessary Sol planning')) 'interface prompt must request minimum necessary planning'
    Assert-True ($interfaceMetadata.Contains('suitable Terra or Luna executor')) 'interface prompt must request a suitable executor lane'
    Assert-True (-not $interfaceMetadata.Contains('Sol planning, Luna execution, and Sol verification')) 'interface metadata must not mandate the fixed pipeline'

    $expectedAgents = @(
        @{ File = 'sol-planner.toml'; Name = 'sol_planner'; Model = 'gpt-5.6-sol'; Effort = 'high'; Sandbox = 'read-only' },
        @{ File = 'sol-compact-planner.toml'; Name = 'sol_compact_planner'; Model = 'gpt-5.6-sol'; Effort = 'medium'; Sandbox = 'read-only' },
        @{ File = 'luna-scout.toml'; Name = 'luna_scout'; Model = 'gpt-5.6-luna'; Effort = 'low'; Sandbox = 'read-only' },
        @{ File = 'terra-executor.toml'; Name = 'terra_executor'; Model = 'gpt-5.6-terra'; Effort = 'medium'; Sandbox = 'workspace-write' },
        @{ File = 'luna-executor.toml'; Name = 'luna_executor'; Model = 'gpt-5.6-luna'; Effort = 'medium'; Sandbox = 'workspace-write' },
        @{ File = 'luna-fast-executor.toml'; Name = 'luna_fast_executor'; Model = 'gpt-5.6-luna'; Effort = 'low'; Sandbox = 'workspace-write' }
    )
    foreach ($agent in $expectedAgents) {
        $content = [System.IO.File]::ReadAllText((Join-Path $assetsDirectory $agent.File), $utf8Strict)
        Assert-True ($content -match "(?m)^name = `"$([regex]::Escape($agent.Name))`"\r?$") "$($agent.File) must have the expected name"
        Assert-True ($content -match "(?m)^model = `"$([regex]::Escape($agent.Model))`"\r?$") "$($agent.File) must have the expected model"
        Assert-True ($content -match "(?m)^model_reasoning_effort = `"$([regex]::Escape($agent.Effort))`"\r?$") "$($agent.File) must have the expected reasoning effort"
        Assert-True ($content -match "(?m)^sandbox_mode = `"$([regex]::Escape($agent.Sandbox))`"\r?$") "$($agent.File) must have the expected sandbox"
    }
    $compactPlanner = [System.IO.File]::ReadAllText((Join-Path $assetsDirectory 'sol-compact-planner.toml'), $utf8Strict)
    $scout = [System.IO.File]::ReadAllText((Join-Path $assetsDirectory 'luna-scout.toml'), $utf8Strict)
    $terraExecutor = [System.IO.File]::ReadAllText((Join-Path $assetsDirectory 'terra-executor.toml'), $utf8Strict)
    $executor = [System.IO.File]::ReadAllText((Join-Path $assetsDirectory 'luna-executor.toml'), $utf8Strict)
    $fastExecutor = [System.IO.File]::ReadAllText((Join-Path $assetsDirectory 'luna-fast-executor.toml'), $utf8Strict)
    Assert-True ($compactPlanner.Contains('400 output tokens')) 'compact planner instructions must enforce the v1.2 plan budget'
    Assert-True ($scout.Contains('250 output tokens')) 'Scout instructions must enforce the evidence budget'
    Assert-True ($scout.Contains('Do not plan, edit, verify an implementation')) 'Scout instructions must prohibit implementation work'
    Assert-True ($terraExecutor.Contains('300 output tokens')) 'Terra instructions must enforce the implementation report budget'
    Assert-True ($terraExecutor.Contains('ordinary implementation details and test failures')) 'Terra instructions must permit ordinary error correction'
    Assert-True ($executor.Contains('300 output tokens')) 'standard executor instructions must enforce the report budget'
    Assert-True ($fastExecutor.Contains('300 output tokens')) 'fast executor instructions must enforce the report budget'
    Assert-True ($fastExecutor.Contains('self-verif')) 'fast executor instructions must require self-verification'

    $frontmatter = [regex]::Match($skill, '(?s)\A---\r?\n(.*?)\r?\n---').Groups[1].Value
    Assert-True (([regex]::Matches($frontmatter, '(?m)^[A-Za-z_-]+:')).Count -eq 2) 'Skill frontmatter must remain discovery-only with name and description'

    foreach ($file in Get-ChildItem -LiteralPath $skillDirectory -Recurse -File) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "$($file.Name) must not contain a UTF-8 BOM"
        [void][System.IO.File]::ReadAllText($file.FullName, $utf8Strict)
    }
    Write-Output 'PASS adaptive routing, agent configuration, frontmatter, and UTF-8 contracts'
}

Test-DifferingAgentCollisions
Test-FreshInstall
Test-AdaptiveRoutingContracts
Test-V100Upgrade
Test-V110Upgrade
Test-V110UpgradeWithLaterUnknownCollisionIsAtomic
Test-MalformedGlobalMarkers
Test-IdenticalFilesAreIdempotent
Test-WhatIfDoesNotMutate
Write-Output 'ALL TESTS PASSED'
