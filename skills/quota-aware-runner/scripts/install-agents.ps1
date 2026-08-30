[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$skillDirectory = Split-Path -Parent $PSScriptRoot
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$agentsDirectory = [System.IO.Path]::GetFullPath((Join-Path $codexHome 'agents'))
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

function Test-ByteArrayEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Write-BytesAtomically {
    param([string]$Path, [byte[]]$Bytes)
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
        if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
        if ([System.IO.File]::Exists($backupPath)) { [System.IO.File]::Delete($backupPath) }
    }
}

# Validate every destination before writing anything. Existing canonical Sol
# agent definitions are byte-identical and therefore safely reused.
$plans = foreach ($fileName in $agentFiles) {
    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $sourceDirectory $fileName))
    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $agentsDirectory $fileName))
    $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    $needsWrite = -not [System.IO.File]::Exists($destinationPath)
    if ([System.IO.File]::Exists($destinationPath)) {
        $destinationBytes = [System.IO.File]::ReadAllBytes($destinationPath)
        if (-not (Test-ByteArrayEqual -Left $sourceBytes -Right $destinationBytes)) {
            $destinationHash = Get-Sha256Hex -Bytes $destinationBytes
            if (@($knownLegacyAgentHashes[$fileName]) -contains $destinationHash) {
                $needsWrite = $true
            } else {
                throw "Refusing to overwrite differing custom agent: $destinationPath"
            }
        }
    }
    [pscustomobject]@{ Source = $sourcePath; Destination = $destinationPath; Bytes = $sourceBytes; NeedsWrite = $needsWrite }
}

if (-not [System.IO.Directory]::Exists($agentsDirectory)) {
    if ($PSCmdlet.ShouldProcess($agentsDirectory, 'Create custom-agent directory')) {
        [System.IO.Directory]::CreateDirectory($agentsDirectory) | Out-Null
    }
}

foreach ($plan in $plans) {
    if ($plan.NeedsWrite) {
        if ($PSCmdlet.ShouldProcess($plan.Destination, "Install custom agent from $($plan.Source)")) {
            Write-BytesAtomically -Path $plan.Destination -Bytes $plan.Bytes
        }
    }
}

Write-Output 'Installed or reused six custom-agent definitions; global AGENTS.md was not modified.'
