[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

$skillDirectory = Split-Path -Parent $PSScriptRoot
$codexHome = if ($env:CODEX_HOME) {
    $env:CODEX_HOME
} else {
    Join-Path $HOME '.codex'
}

$agentsDirectory = [System.IO.Path]::GetFullPath((Join-Path $codexHome 'agents'))
$globalAgentsPath = [System.IO.Path]::GetFullPath((Join-Path $codexHome 'AGENTS.md'))
$sourceDirectory = Join-Path $skillDirectory 'assets'
$agentFiles = @(
    'sol-planner.toml',
    'sol-compact-planner.toml',
    'luna-scout.toml',
    'terra-executor.toml',
    'luna-executor.toml',
    'luna-fast-executor.toml'
)
# Earlier releases shipped these built-in definitions. Accept only their exact
# UTF-8 bytes, including the Git-standard LF and Windows CRLF checkout forms.
$knownLegacyAgentHashes = @{
    'sol-planner.toml' = @(
        '7B6FB8A14C22354125C08BC255F4203B7BF8EBF505209402FA8A7BBD91EBA431',
        '140A285E3485546848294A9DE46AA96E7B021B24AA8A83BC8E546854D9B93B4F'
    )
    'sol-compact-planner.toml' = @(
        'E8E9F21443434F523AA71DF343965ACDE93AD8ECEC3293F90F8386E4A5046A36',
        '2C7A9FE24E737DC1DD3D6E97CAC9745EB42CA0174587DEB083FC66C7C07DAA8A'
    )
    'luna-executor.toml' = @(
        '292F88AA10D75147F3287AB54E73F0C4C2CE4BF98211F1A8944C789DDF7A7D8F',
        '5BC8230908773356A53BD51F148F8DE116FD8A0283636215ABEA046BB62E2EFA',
        '91AA121E7248CA507FFB594D7768595E1E0C6267BD5435745DC2573DAB9957FA',
        '89864C97A3DC252F684CA46BC405E414D4811465517F5D721AABC9C8AAE2669D'
    )
    'luna-fast-executor.toml' = @(
        '5400B0F6F9EE8CAAD4678779A6FB89F99C59835669BF579DD0A70F1F05BF9393',
        '099C58C9F0AF4B6B2A0F923782E0953BB798FB8AA48ED29EDF7E2550EAA3F5A6'
    )
    'terra-executor.toml' = @(
        'A347C7596F1794A6B91B8E55A4B6C2B411B282E07288E9A5955C18933D7EAD26',
        '721B9C4A60F66A729B409792FC6BF173678D7F62DEF82B36CA1123CC247515AC'
    )
}
$managedBlockPath = [System.IO.Path]::GetFullPath((Join-Path $sourceDirectory 'global-agents.md'))
$startMarker = '<!-- BEGIN SOL-LUNA-HANDOFF MANAGED BLOCK -->'
$endMarker = '<!-- END SOL-LUNA-HANDOFF MANAGED BLOCK -->'
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Test-ByteArrayEqual {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Left,

        [Parameter(Mandatory)]
        [byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }

    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }

    return $true
}

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Write-BytesAtomically {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $directory = [System.IO.Path]::GetDirectoryName($Path)
    $temporaryPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.bak')
    try {
        [System.IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($temporaryPath, $Path, $backupPath)
        } else {
            [System.IO.File]::Move($temporaryPath, $Path)
        }
    } finally {
        if ([System.IO.File]::Exists($temporaryPath)) {
            [System.IO.File]::Delete($temporaryPath)
        }
        if ([System.IO.File]::Exists($backupPath)) {
            [System.IO.File]::Delete($backupPath)
        }
    }
}

# Preflight every custom-agent destination before making any filesystem changes.
$agentInstallPlans = foreach ($fileName in $agentFiles) {
    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $sourceDirectory $fileName))
    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $agentsDirectory $fileName))
    $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    $needsWrite = -not [System.IO.File]::Exists($destinationPath)

    if (-not $needsWrite) {
        $destinationBytes = [System.IO.File]::ReadAllBytes($destinationPath)
        if (-not (Test-ByteArrayEqual -Left $sourceBytes -Right $destinationBytes)) {
            $destinationHash = Get-Sha256Hex -Bytes $destinationBytes
            $knownHashes = @($knownLegacyAgentHashes[$fileName])
            if ($knownHashes -contains $destinationHash) {
                $needsWrite = $true
            } else {
                throw "Custom-agent collision: destination exists with different content: $destinationPath"
            }
        }
    }

    [pscustomobject]@{
        SourcePath = $sourcePath
        DestinationPath = $destinationPath
        SourceBytes = $sourceBytes
        NeedsWrite = $needsWrite
    }
}

$managedBlock = [System.IO.File]::ReadAllText($managedBlockPath, $utf8Strict)
$escapedStartMarker = [System.Text.RegularExpressions.Regex]::Escape($startMarker)
$escapedEndMarker = [System.Text.RegularExpressions.Regex]::Escape($endMarker)
$managedBlockPattern = "(?ms)\A[ \t]*$escapedStartMarker[ \t]*\r?\n.*?^[ \t]*$escapedEndMarker[ \t]*(?:\r?\n)?\z"
$managedStartMarkerCount = [System.Text.RegularExpressions.Regex]::Matches($managedBlock, "(?m)^[ \t]*$escapedStartMarker[ \t]*\r?$").Count
$managedEndMarkerCount = [System.Text.RegularExpressions.Regex]::Matches($managedBlock, "(?m)^[ \t]*$escapedEndMarker[ \t]*\r?$").Count

if ($managedStartMarkerCount -ne 1 -or
    $managedEndMarkerCount -ne 1 -or
    -not [System.Text.RegularExpressions.Regex]::IsMatch($managedBlock, $managedBlockPattern)) {
    throw "Managed global rule must contain exactly one complete marker-delimited block: $managedBlockPath"
}

$existingGlobalAgents = if ([System.IO.File]::Exists($globalAgentsPath)) {
    [System.IO.File]::ReadAllText($globalAgentsPath, $utf8Strict)
} else {
    ''
}

$newline = if ($existingGlobalAgents.Contains("`r`n")) { "`r`n" } else { "`n" }
$normalizedManagedBlock = ($managedBlock.TrimEnd("`r", "`n") -replace "`r`n|`r|`n", $newline) + $newline
$startMarkerCount = [System.Text.RegularExpressions.Regex]::Matches($existingGlobalAgents, "(?m)^[ \t]*$escapedStartMarker[ \t]*\r?$").Count
$endMarkerCount = [System.Text.RegularExpressions.Regex]::Matches($existingGlobalAgents, "(?m)^[ \t]*$escapedEndMarker[ \t]*\r?$").Count

if ($startMarkerCount -eq 0 -and $endMarkerCount -eq 0) {
    if ($existingGlobalAgents.Length -eq 0) {
        $updatedGlobalAgents = $normalizedManagedBlock
    } elseif ($existingGlobalAgents.EndsWith($newline + $newline)) {
        $updatedGlobalAgents = $existingGlobalAgents + $normalizedManagedBlock
    } elseif ($existingGlobalAgents.EndsWith($newline)) {
        $updatedGlobalAgents = $existingGlobalAgents + $newline + $normalizedManagedBlock
    } else {
        $updatedGlobalAgents = $existingGlobalAgents + $newline + $newline + $normalizedManagedBlock
    }
} elseif ($startMarkerCount -eq 1 -and $endMarkerCount -eq 1) {
    $installedBlockPattern = "(?ms)^[ \t]*$escapedStartMarker[ \t]*\r?\n.*?^[ \t]*$escapedEndMarker[ \t]*(?:\r?\n)?"
    $installedBlockMatch = [System.Text.RegularExpressions.Regex]::Match($existingGlobalAgents, $installedBlockPattern)

    if (-not $installedBlockMatch.Success) {
        throw "Managed global rule markers are malformed in $globalAgentsPath"
    }

    $updatedGlobalAgents = $existingGlobalAgents.Substring(0, $installedBlockMatch.Index) +
        $normalizedManagedBlock +
        $existingGlobalAgents.Substring($installedBlockMatch.Index + $installedBlockMatch.Length)
} else {
    throw "Expected zero or one managed global rule block in $globalAgentsPath"
}

# All collision and marker validation is complete. Mutations begin here.
$missingAgentFiles = @($agentInstallPlans | Where-Object { $_.NeedsWrite })
if ($missingAgentFiles.Count -gt 0 -and
    -not [System.IO.Directory]::Exists($agentsDirectory) -and
    $PSCmdlet.ShouldProcess($agentsDirectory, 'Create custom-agent directory')) {
    [System.IO.Directory]::CreateDirectory($agentsDirectory) | Out-Null
}

foreach ($plan in $agentInstallPlans) {
    if ($plan.NeedsWrite -and
        $PSCmdlet.ShouldProcess($plan.DestinationPath, "Install custom agent from $($plan.SourcePath)")) {
        Write-BytesAtomically -Path $plan.DestinationPath -Bytes $plan.SourceBytes
    }

    Write-Output $plan.DestinationPath
}

if ($updatedGlobalAgents -cne $existingGlobalAgents -and
    $PSCmdlet.ShouldProcess($globalAgentsPath, "Install managed global rule from $managedBlockPath")) {
    [System.IO.File]::WriteAllText($globalAgentsPath, $updatedGlobalAgents, $utf8NoBom)
}

Write-Output $globalAgentsPath
