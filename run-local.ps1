param(
    [ValidateRange(1024,65535)][int]$Port = 3838,
    [ValidateRange(1024,65535)][int]$ParticipantPort = 3840,
    [string]$Workspace = '',
    [string]$RscriptPath = '',
    [string]$LibraryPath = '',
    [string]$ConfigurationPath = '',
    [switch]$CheckOnly,
    [switch]$Legacy
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
. (Join-Path $projectRoot 'scripts/local-configuration.ps1')
$configuration = $null
$configuredEnvironment = @{}
if (-not $ConfigurationPath -and -not $Legacy) {
    $savedConfiguration = Join-Path $projectRoot '.brohn/local-installation.json'
    if (Test-Path -LiteralPath $savedConfiguration -PathType Leaf) { $ConfigurationPath = $savedConfiguration }
}
if ($ConfigurationPath) {
    if ($Legacy) { throw 'A connected installation configuration cannot be used with the historical legacy application.' }
    $configuration = Read-BrohnLocalConfiguration $ConfigurationPath
    if (-not $RscriptPath) { $RscriptPath = $configuration.rscript }
    if (-not $LibraryPath) { $LibraryPath = $configuration.r_library }
    if (-not $Workspace) { $Workspace = $configuration.workspace }
    if (-not $PSBoundParameters.ContainsKey('Port')) { $Port = $configuration.ports.researcher }
    if (-not $PSBoundParameters.ContainsKey('ParticipantPort')) { $ParticipantPort = $configuration.ports.participant }
    $configuredEnvironment = Get-BrohnConfiguredEnvironment $configuration
}
if (-not $Legacy -and $Port -eq $ParticipantPort) { throw 'Researcher and participant ports must differ.' }
$workspaceParent = Split-Path (Split-Path $projectRoot -Parent) -Parent
$priorEnvironment = @{}
foreach ($name in (@('R_LIBS_USER', 'R_USER', 'LC_ALL', 'RESEARCH_PLATFORM_PORT', 'BROHN_PARTICIPANT_PORT', 'BROHN_WORKSPACE', 'BROHN_APP_MODE') + @($configuredEnvironment.Keys) | Select-Object -Unique)) {
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
    foreach ($name in $configuredEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $configuredEnvironment[$name], 'Process') }
    if ($LibraryPath) { $env:R_LIBS_USER = $LibraryPath }
    if (-not $env:R_USER -and (Test-Path -LiteralPath (Join-Path $workspaceParent 'work') -PathType Container)) {
        $env:R_USER = Join-Path $workspaceParent 'work'
    }
    $env:RESEARCH_PLATFORM_PORT = [string]$Port
    $env:BROHN_PARTICIPANT_PORT = [string]$ParticipantPort
    if ($Workspace) { $env:BROHN_WORKSPACE = $Workspace }
    if ($env:LC_ALL -eq 'C.UTF-8') { $env:LC_ALL = 'C' }
    $env:BROHN_APP_MODE = if ($Legacy) { 'legacy' } else { 'platform' }
    if ($CheckOnly) {
        if ($Legacy) { throw 'Readiness checks apply to the connected Brohn application.' }
        $profiles = if ($configuration -and $configuration.scientific.Count) { @($configuration.scientific.Keys) -join ',' } else { 'none' }
        $doctorArguments = @('--vanilla','scripts/doctor.R','--profiles',$profiles,'--required-profiles',$profiles,'--require-portability')
        if ($LibraryPath) { $doctorArguments += @('--library',$LibraryPath) }
        & $RscriptPath @doctorArguments
        if ($LASTEXITCODE -ne 0) { throw 'Brohn readiness failed. Correct the reported dependency before launching.' }
        return
    }
    $entryPoint = if ($Legacy) { 'scripts/run-local.R' } else { 'scripts/run-brohn.R' }
    & $RscriptPath --vanilla $entryPoint
    if ($LASTEXITCODE -ne 0) { throw "Brohn stopped with exit code $LASTEXITCODE. See the startup message or the workspace logs directory." }
}
finally {
    Pop-Location
    foreach ($name in $priorEnvironment.Keys) {
        $savedValue = if ($null -eq $priorEnvironment[$name]) { [NullString]::Value } else { $priorEnvironment[$name] }
        [Environment]::SetEnvironmentVariable($name, $savedValue, 'Process')
    }
}
