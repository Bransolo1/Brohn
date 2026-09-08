param(
    [ValidateRange(1024,65535)][int]$Port = 3838,
    [ValidateRange(1024,65535)][int]$ParticipantPort = 3840,
    [string]$Workspace = '',
    [string]$RscriptPath = '',
    [string]$LibraryPath = '',
    [switch]$Legacy
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
if (-not $Legacy -and $Port -eq $ParticipantPort) { throw 'Researcher and participant ports must differ.' }
$workspaceParent = Split-Path (Split-Path $projectRoot -Parent) -Parent
$priorEnvironment = @{}
foreach ($name in @('R_LIBS_USER', 'R_USER', 'LC_ALL', 'RESEARCH_PLATFORM_PORT', 'BROHN_PARTICIPANT_PORT', 'BROHN_WORKSPACE', 'BROHN_APP_MODE')) {
    $priorEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
if (-not $RscriptPath) {
    $rCommand = Get-Command Rscript -ErrorAction SilentlyContinue
    if ($rCommand) { $RscriptPath = $rCommand.Source }
    else {
        $candidate = Join-Path $workspaceParent 'work\native-r\bin\Rscript.exe'
        if (Test-Path -LiteralPath $candidate) {
            $RscriptPath = $candidate
        }
    }
}
if (-not $RscriptPath -or -not (Test-Path -LiteralPath $RscriptPath -PathType Leaf)) {
    throw 'Rscript was not found. Install R and the packages in DEPENDENCIES.md, or pass -RscriptPath.'
}
$RscriptPath = (Resolve-Path -LiteralPath $RscriptPath).Path
if ($Workspace) { $Workspace = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Workspace) }
if (-not $LibraryPath -and -not $env:R_LIBS_USER) {
    $libraryCandidates = @(Join-Path $projectRoot 'renv\library')
    if ($Legacy) { $libraryCandidates += Join-Path $workspaceParent 'work\r-library' }
    else { $libraryCandidates += Join-Path $workspaceParent 'work\r-library-brohn' }
    foreach ($candidateLibrary in $libraryCandidates) {
        if (Test-Path -LiteralPath (Join-Path $candidateLibrary 'shiny') -PathType Container) {
            $LibraryPath = $candidateLibrary
            break
        }
    }
}
if ($LibraryPath -and -not (Test-Path -LiteralPath $LibraryPath -PathType Container)) { throw 'The selected R library directory does not exist.' }
if ($LibraryPath) { $LibraryPath = (Resolve-Path -LiteralPath $LibraryPath).Path }
Push-Location -LiteralPath $projectRoot
try {
    if ($LibraryPath) { $env:R_LIBS_USER = $LibraryPath }
    if (-not $env:R_USER -and (Test-Path -LiteralPath (Join-Path $workspaceParent 'work') -PathType Container)) {
        $env:R_USER = Join-Path $workspaceParent 'work'
    }
    $env:RESEARCH_PLATFORM_PORT = [string]$Port
    $env:BROHN_PARTICIPANT_PORT = [string]$ParticipantPort
    if ($Workspace) { $env:BROHN_WORKSPACE = $Workspace }
    if ($env:LC_ALL -eq 'C.UTF-8') { $env:LC_ALL = 'C' }
    $env:BROHN_APP_MODE = if ($Legacy) { 'legacy' } else { 'platform' }
    $entryPoint = if ($Legacy) { 'scripts/run-local.R' } else { 'scripts/run-brohn.R' }
    & $RscriptPath --vanilla $entryPoint
    if ($LASTEXITCODE -ne 0) { throw "Brohn stopped with exit code $LASTEXITCODE. See the startup message or the workspace logs directory." }
}
finally {
    Pop-Location
    foreach ($name in $priorEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $priorEnvironment[$name], 'Process')
    }
}
