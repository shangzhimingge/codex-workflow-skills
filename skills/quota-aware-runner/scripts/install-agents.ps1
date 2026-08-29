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

function Test-ByteArrayEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Write-BytesAtomically {
    param([string]$Path, [byte[]]$Bytes)
    $directory = [System.IO.Path]::GetDirectoryName($Path)
    $temporaryPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        [System.IO.File]::Move($temporaryPath, $Path)
    } finally {
        if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
    }
}

# Validate every destination before writing anything. Existing canonical Sol
# agent definitions are byte-identical and therefore safely reused.
$plans = foreach ($fileName in $agentFiles) {
    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $sourceDirectory $fileName))
    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $agentsDirectory $fileName))
    $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    if ([System.IO.File]::Exists($destinationPath)) {
        $destinationBytes = [System.IO.File]::ReadAllBytes($destinationPath)
        if (-not (Test-ByteArrayEqual -Left $sourceBytes -Right $destinationBytes)) {
            throw "Refusing to overwrite differing custom agent: $destinationPath"
        }
    }
    [pscustomobject]@{ Source = $sourcePath; Destination = $destinationPath; Bytes = $sourceBytes }
}

if (-not [System.IO.Directory]::Exists($agentsDirectory)) {
    if ($PSCmdlet.ShouldProcess($agentsDirectory, 'Create custom-agent directory')) {
        [System.IO.Directory]::CreateDirectory($agentsDirectory) | Out-Null
    }
}

foreach ($plan in $plans) {
    if (-not [System.IO.File]::Exists($plan.Destination)) {
        if ($PSCmdlet.ShouldProcess($plan.Destination, "Install custom agent from $($plan.Source)")) {
            Write-BytesAtomically -Path $plan.Destination -Bytes $plan.Bytes
        }
    }
}

Write-Output 'Installed or reused six custom-agent definitions; global AGENTS.md was not modified.'
