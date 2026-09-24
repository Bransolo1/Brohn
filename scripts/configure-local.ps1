param(
    [Parameter(Mandatory = $true)][string]$RscriptPath,
    [Parameter(Mandatory = $true)][string]$LibraryPath,
    [Parameter(Mandatory = $true)][string]$PublicationPythonPath,
    [Parameter(Mandatory = $true)][string]$PublicationManifestPath,
    [Parameter(Mandatory = $true)][string]$Workspace,
    [string]$PortabilityPythonPath = '',
    [string]$ConfigurationPath = '',
    [ValidateRange(1024,65535)][int]$Port = 3838,
    [ValidateRange(1024,65535)][int]$ParticipantPort = 3840,
    [hashtable]$ScientificProfiles = @{},
    [hashtable]$RuntimeAssets = @{},
    [switch]$Replace
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'local-configuration.ps1')
$project = Split-Path -Parent $PSScriptRoot
$invocationRoot = (Get-Location).ProviderPath
if (-not $ConfigurationPath) { $ConfigurationPath = Join-Path $project '.brohn/local-installation.json' }
$ConfigurationPath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigurationPath))
if ([IO.Path]::GetExtension($ConfigurationPath) -ine '.json') { throw 'Save the installation configuration as a .json file.' }
if (Test-Path -LiteralPath $ConfigurationPath -PathType Container) { throw 'Choose a configuration file, not an existing directory.' }
if ((Test-Path -LiteralPath $ConfigurationPath) -and -not $Replace) { throw 'This configuration already exists. Use -Replace to update the selected installation after checking it.' }
if (-not $PortabilityPythonPath) { $PortabilityPythonPath = $PublicationPythonPath }
$profiles = [ordered]@{}
foreach ($profile in $ScientificProfiles.Keys) {
    if ($profile -cnotin @('methods','acquisition','vision-audio','segmentation','facial-au')) { throw "Unknown scientific profile: $profile" }
    $profiles[$profile] = Resolve-BrohnConfiguredPath $ScientificProfiles[$profile] $invocationRoot 'Leaf' $profile
}
$assets = [ordered]@{}
foreach ($asset in $RuntimeAssets.Keys) {
    if ($asset -cnotin @('facial_models','facial_ffmpeg')) { throw "Unknown runtime asset: $asset" }
    $assets[$asset] = Resolve-BrohnConfiguredPath $RuntimeAssets[$asset] $invocationRoot 'Container' $asset
}
if ($profiles.Contains('facial-au') -and (-not $assets.Contains('facial_models') -or -not $assets.Contains('facial_ffmpeg'))) {
    throw 'Supply RuntimeAssets facial_models and facial_ffmpeg when configuring facial-au.'
}
$configuration = [ordered]@{
    schema = 'brohn-local-installation/1.0'
    rscript = Resolve-BrohnConfiguredPath $RscriptPath $invocationRoot 'Leaf' 'Rscript'
    r_library = Resolve-BrohnConfiguredPath $LibraryPath $invocationRoot 'Container' 'R library'
    publication_python = Resolve-BrohnConfiguredPath $PublicationPythonPath $invocationRoot 'Leaf' 'publication Python'
    publication_manifest = Resolve-BrohnConfiguredPath $PublicationManifestPath $invocationRoot 'Leaf' 'publication manifest'
    portability_python = Resolve-BrohnConfiguredPath $PortabilityPythonPath $invocationRoot 'Leaf' 'portable-design Python'
    workspace = Resolve-BrohnConfiguredPath $Workspace $invocationRoot '' 'workspace'
    ports = @{researcher = $Port; participant = $ParticipantPort}
    scientific = $profiles
    assets = $assets
    checked_at = [DateTime]::UtcNow.ToString('o')
}
if ($Port -eq $ParticipantPort) { throw 'Researcher and participant ports must be distinct.' }
$environment = Get-BrohnConfiguredEnvironment ([pscustomobject]$configuration)
$environment['R_LIBS_USER'] = $configuration.r_library
$environment['LC_ALL'] = 'C'
$prior = @{}
foreach ($key in $environment.Keys) { $prior[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
Push-Location -LiteralPath $project
try {
    foreach ($key in $environment.Keys) { [Environment]::SetEnvironmentVariable($key, $environment[$key], 'Process') }
    $selected = if ($profiles.Count) { @($profiles.Keys) -join ',' } else { 'none' }
    $arguments = @('--vanilla','scripts/doctor.R','--library',$configuration.r_library,'--profiles',$selected,'--required-profiles',$selected,'--require-portability','--json')
    $reportText = & $configuration.rscript @arguments
    $doctorExit = $LASTEXITCODE
    if ($doctorExit -ne 0) { $reportText | Write-Output; throw 'The selected installation is not ready. No configuration was saved; fix the reported dependency and retry.' }
    $report = ($reportText -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($report.schema -cne 'brohn-local-doctor/1.0' -or $report.status -cne 'ready') { throw 'The installation check did not return a ready Brohn report. No configuration was saved.' }
    $parent = Split-Path -Parent $ConfigurationPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ('.brohn-configuration-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($temporary, ($configuration | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
        $null = Read-BrohnLocalConfiguration $temporary
        if (Test-Path -LiteralPath $ConfigurationPath) {
            if (-not $Replace) { throw 'A configuration appeared while checking. It was not replaced.' }
            [IO.File]::Replace($temporary, $ConfigurationPath, [NullString]::Value)
        } else { [IO.File]::Move($temporary, $ConfigurationPath) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
    Write-Output "Brohn installation verified and saved: $ConfigurationPath"
    Write-Output 'Core runtime, guarded publication and portable designs are ready. Configured scientific profiles passed their dependency checks.'
    Write-Output 'Launch with run-local.ps1 -ConfigurationPath PATH. Use -CheckOnly for a fresh check without starting services.'
    Write-Output 'This check did not create a research workspace, start services or activate devices.'
} finally {
    Pop-Location
    foreach ($key in $prior.Keys) {
        $savedValue = if ($null -eq $prior[$key]) { [NullString]::Value } else { $prior[$key] }
        [Environment]::SetEnvironmentVariable($key, $savedValue, 'Process')
    }
}
