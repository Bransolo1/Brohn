# One explicit setup for the currently supported Windows local profile.
# Installed R, Python and TinyCC are prerequisites, not globally modified here.
param(
    [Parameter(Mandatory=$true)][string]$InstallationRoot,
    [Parameter(Mandatory=$true)][string]$RscriptPath,
    [Parameter(Mandatory=$true)][string]$PythonPath,
    [Parameter(Mandatory=$true)][string]$CompilerPath,
    [string]$Workspace='',
    [string]$CacheRoot='',
    [ValidateRange(1024,65535)][int]$Port=3838,
    [ValidateRange(1024,65535)][int]$ParticipantPort=3840,
    [hashtable]$ScientificProfiles=@{},
    [switch]$ReplaceConfiguration
)
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This setup currently supports Windows. See the installation guide for supported profiles.' }
. (Join-Path $PSScriptRoot 'local-configuration.ps1')
$project=Split-Path -Parent $PSScriptRoot
$invocation=(Get-Location).ProviderPath
$InstallationRoot=Resolve-BrohnConfiguredPath $InstallationRoot $invocation '' 'installation directory'
$RscriptPath=Resolve-BrohnConfiguredPath $RscriptPath $invocation 'Leaf' 'Rscript'
$PythonPath=Resolve-BrohnConfiguredPath $PythonPath $invocation 'Leaf' 'Python'
$CompilerPath=Resolve-BrohnConfiguredPath $CompilerPath $invocation 'Leaf' 'TinyCC'
if ($InstallationRoot.TrimEnd('\','/').Equals($project,[StringComparison]::OrdinalIgnoreCase) -or $InstallationRoot.StartsWith($project+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Choose an installation directory outside the source checkout.' }
if ($Port -eq $ParticipantPort) { throw 'Researcher and participant ports must be distinct.' }
if (-not $Workspace) { $Workspace=Join-Path $InstallationRoot 'workspaces/default' }
$Workspace=Resolve-BrohnConfiguredPath $Workspace $invocation '' 'workspace'
if (-not $CacheRoot) { $CacheRoot=Join-Path $InstallationRoot 'renv-cache' }
$CacheRoot=Resolve-BrohnConfiguredPath $CacheRoot $invocation '' 'package cache'
$marker=Join-Path $InstallationRoot 'brohn-setup.json'
$configuration=Join-Path $InstallationRoot 'local-installation.json'
if (Test-Path -LiteralPath $InstallationRoot) {
    if (-not (Test-Path -LiteralPath $InstallationRoot -PathType Container)) { throw 'Choose an installation directory, not a file.' }
    if (Test-Path -LiteralPath $marker -PathType Leaf) {
        $existing=Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existing.schema -cne 'brohn-local-setup/1.0') { throw 'This directory is not a recognized Brohn installation.' }
    } elseif (@(Get-ChildItem -LiteralPath $InstallationRoot -Force).Count) { throw 'Choose an empty installation directory. Existing unrelated files are left unchanged.' }
}
if ((Test-Path -LiteralPath $configuration) -and -not $ReplaceConfiguration) { throw 'This installation is already configured. Use run-local.ps1, or -ReplaceConfiguration to check and update it.' }
$validatedProfiles=@{}
foreach ($profile in $ScientificProfiles.Keys) {
    if ($profile -cnotin @('methods','acquisition','vision-audio','segmentation')) { throw "Unknown scientific profile: $profile" }
    $validatedProfiles[$profile]=Resolve-BrohnConfiguredPath $ScientificProfiles[$profile] $invocation 'Leaf' $profile
}
$ScientificProfiles=$validatedProfiles
$lockfile=Get-Content -LiteralPath (Join-Path $project 'renv.lock') -Raw -Encoding UTF8 | ConvertFrom-Json
# Validate executable identity before creating the installation directory.
$previousLocale=[Environment]::GetEnvironmentVariable('LC_ALL','Process')
try {
    $env:LC_ALL='C'
    $rVersion=(& $RscriptPath --vanilla -e 'cat(as.character(getRversion()))' | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $rVersion -cne $lockfile.R.Version) { throw "Brohn requires R $($lockfile.R.Version); selected runtime returned '$rVersion'." }
} finally {
    $locale=if($null -eq $previousLocale){[NullString]::Value}else{$previousLocale}
    [Environment]::SetEnvironmentVariable('LC_ALL',$locale,'Process')
}
& $PythonPath -c 'import sys,struct; assert sys.version_info >= (3,10) and struct.calcsize("P")==8, "Brohn requires 64-bit Python 3.10 or newer"'
if ($LASTEXITCODE -ne 0) { throw 'The selected Python does not support this local profile.' }
New-Item -ItemType Directory -Path $InstallationRoot -Force | Out-Null
$lockPath=Join-Path $InstallationRoot '.setup.lock'
$lock=$null; $transcript=$false; $prior=@{}
try {
    try { $lock=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw 'Another setup owns this directory, or an interrupted setup left .setup.lock. Ensure no setup is running before removing that single lock file and retrying.' }
    if (-not (Test-Path -LiteralPath $marker)) {
        [IO.File]::WriteAllText($marker,(@{schema='brohn-local-setup/1.0';created_at=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    }
    $logDirectory=Join-Path $InstallationRoot 'setup-logs'; New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $attempt=Join-Path $logDirectory ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
    Start-Transcript -LiteralPath ($attempt+'.txt') | Out-Null; $transcript=$true
    $bootstrap=Join-Path $InstallationRoot 'r-bootstrap'; $library=Join-Path $InstallationRoot 'r-library'; $native=Join-Path $InstallationRoot 'native'
    $values=@{R_LIBS_USER=$bootstrap;RENV_PATHS_ROOT=$CacheRoot;LC_ALL='C';BROHN_PUBLICATION_PYTHON=$PythonPath;BROHN_PUBLICATION_NATIVE_MANIFEST=(Join-Path $native 'publication-guard.json')}
    foreach ($key in $values.Keys) { $prior[$key]=[Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,$values[$key],'Process') }
    Push-Location -LiteralPath $project
    try {
        Write-Output '1/4 Preparing the pinned dependency installer...'
        & $RscriptPath --vanilla scripts/bootstrap-dependencies.R $bootstrap $lockfile.Packages.renv.Version $lockfile.R.Version
        if ($LASTEXITCODE -ne 0) { throw 'Dependency bootstrap failed. Correct the reported issue and rerun setup.' }
        Write-Output '2/4 Restoring the exact application library...'
        & $RscriptPath --vanilla scripts/restore-dependencies.R $library
        if ($LASTEXITCODE -ne 0) { throw 'Exact dependency restore failed. No configuration was saved; rerun after correcting the reported issue.' }
        & $RscriptPath --vanilla scripts/check-dependencies.R $library
        if ($LASTEXITCODE -ne 0) { throw 'The restored application library failed verification.' }
        $env:R_LIBS_USER=$library
        Write-Output '3/4 Building and checking protected report storage...'
        & $RscriptPath --vanilla scripts/build-publication-guard.R $CompilerPath $native
        if ($LASTEXITCODE -ne 0) { throw 'Report storage preparation failed. No configuration was saved.' }
        Write-Output '4/4 Checking and saving this installation...'
        & (Join-Path $PSScriptRoot 'configure-local.ps1') -RscriptPath $RscriptPath -LibraryPath $library -PublicationPythonPath $PythonPath -PublicationManifestPath $values.BROHN_PUBLICATION_NATIVE_MANIFEST -Workspace $Workspace -ConfigurationPath $configuration -Port $Port -ParticipantPort $ParticipantPort -ScientificProfiles $ScientificProfiles -Replace:$ReplaceConfiguration
        $receipt=@{schema='brohn-setup-result/1.0';status='ready';checked_at=[DateTime]::UtcNow.ToString('o');configuration=$configuration;lock_sha256=(Get-FileHash -LiteralPath 'renv.lock' -Algorithm SHA256).Hash.ToLowerInvariant();r_version=$rVersion;scientific_profiles=@($ScientificProfiles.Keys);scope='Fresh separate dependency library and checked local configuration; not a clean-machine, device or scientific qualification.'}
        [IO.File]::WriteAllText(($attempt+'.json'),($receipt | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        Write-Output 'Brohn is ready to launch. No research workspace or service was started by setup.'
        Write-Output ('./run-local.ps1 -ConfigurationPath '''+$configuration.Replace("'","''")+'''')
    } finally { Pop-Location }
} finally {
    foreach ($key in $prior.Keys) { $value=if($null -eq $prior[$key]){[NullString]::Value}else{$prior[$key]}; [Environment]::SetEnvironmentVariable($key,$value,'Process') }
    if ($transcript) { Stop-Transcript | Out-Null }
    if ($null -ne $lock) { $lock.Dispose(); Remove-Item -LiteralPath $lockPath }
}
