param(
    [Parameter(Mandatory=$true)][string]$ConfigurationPath,
    [Parameter(Mandatory=$true)][string]$FacialPython,
    [Parameter(Mandatory=$true)][string]$ModelDirectory,
    [Parameter(Mandatory=$true)][string]$FfmpegDirectory,
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory
)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'scripts/local-configuration.ps1')
$installed=Read-BrohnLocalConfiguration $ConfigurationPath
if(Test-Path -LiteralPath $EvidenceDirectory){throw 'Choose a fresh evidence directory.'}
New-Item -ItemType Directory -Path $EvidenceDirectory | Out-Null
$EvidenceDirectory=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$value,[string]$label){if(-not $value){throw "FAILED: $label"};$checks.Add($label)}
function Reject([scriptblock]$action,[string]$label){$failed=$false;try{& $action | Out-Null}catch{$failed=$true};Check $failed $label}
function Save($value,[string]$name='candidate.json'){
    $path=Join-Path $EvidenceDirectory $name
    [IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false));return $path
}
$original=Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$original.PSObject.Properties.Remove('assets')
$original.scientific=[pscustomobject]@{}
$legacy=Read-BrohnLocalConfiguration (Save $original 'legacy.json')
Check ($legacy.assets.Count -eq 0) 'Existing version1 configurations remain readable without assets'
$original.scientific=[pscustomobject]@{'facial-au'=$FacialPython}
Reject {Read-BrohnLocalConfiguration (Save $original)} 'Facial installation cannot rely on undeclared inherited asset directories'
$original | Add-Member -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{facial_models=$ModelDirectory})
Reject {Read-BrohnLocalConfiguration (Save $original)} 'Both model and shared native runtime directories are required'
$original.assets=[pscustomobject]@{facial_models=$ModelDirectory;facial_ffmpeg=$FfmpegDirectory}
$selected=Read-BrohnLocalConfiguration (Save $original)
$environment=Get-BrohnConfiguredEnvironment $selected
Check ($environment.BROHN_PYTHON_FACIAL_AU -eq [IO.Path]::GetFullPath($FacialPython) -and $environment.BROHN_FACIAL_MODEL_DIR -eq [IO.Path]::GetFullPath($ModelDirectory) -and $environment.BROHN_FACIAL_FFMPEG_DIR -eq [IO.Path]::GetFullPath($FfmpegDirectory)) 'Explicit interpreter and both directories map to their scoped runtime settings'
$original.assets | Add-Member -NotePropertyName arbitrary -NotePropertyValue $ModelDirectory
Reject {Read-BrohnLocalConfiguration (Save $original)} 'Unknown asset keys cannot become environment variables'
$original.assets=[pscustomobject]@{facial_models=$FacialPython;facial_ffmpeg=$FfmpegDirectory}
Reject {Read-BrohnLocalConfiguration (Save $original)} 'An executable file cannot stand in for a model directory'
$saved=Join-Path $EvidenceDirectory 'verified.json'
$parameters=@{RscriptPath=$installed.rscript;LibraryPath=$installed.r_library;PublicationPythonPath=$installed.publication_python;
    PublicationManifestPath=$installed.publication_manifest;PortabilityPythonPath=$installed.portability_python;
    Workspace=(Join-Path $EvidenceDirectory 'unopened-study-store');ConfigurationPath=$saved;
    ScientificProfiles=@{'facial-au'=$FacialPython};RuntimeAssets=@{facial_models=$ModelDirectory;facial_ffmpeg=$FfmpegDirectory}}
$names=@('BROHN_PYTHON_FACIAL_AU','BROHN_FACIAL_MODEL_DIR','BROHN_FACIAL_FFMPEG_DIR','R_LIBS_USER','LC_ALL','BROHN_PUBLICATION_PYTHON','BROHN_PUBLICATION_NATIVE_MANIFEST','BROHN_PYTHON')
$before=@{};foreach($name in $names){$before[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$log=& (Join-Path $project 'scripts/configure-local.ps1') @parameters | Out-String
[IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'setup.log'),$log,[Text.UTF8Encoding]::new($false))
Check ((Test-Path -LiteralPath $saved) -and $log.Contains('installation verified and saved')) 'Actual pinned package, asset and native import checks gate activation'
$verified=Read-BrohnLocalConfiguration $saved
Check ($verified.assets.Count -eq 2 -and $verified.scientific.Count -eq 1) 'Both asset paths persist in the checked installation'
foreach($name in $names){Check ([Environment]::GetEnvironmentVariable($name,'Process') -ceq $before[$name]) "Setup restores process setting $name"}
Check (-not (Test-Path -LiteralPath $parameters.Workspace)) 'Setup does not create or open participant storage'
$hash=(Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
$empty=Join-Path $EvidenceDirectory 'empty-models';New-Item -ItemType Directory -Path $empty | Out-Null
$parameters.RuntimeAssets.facial_models=$empty;$parameters.Replace=$true
Reject {& (Join-Path $project 'scripts/configure-local.ps1') @parameters} 'A real missing-model check refuses replacement'
Check ((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ceq $hash) 'Failed activation preserves the exact verified configuration'
$launch=& (Join-Path $project 'run-local.ps1') -ConfigurationPath $saved -CheckOnly | Out-String
[IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'launcher.log'),$launch,[Text.UTF8Encoding]::new($false))
Check ($launch.Contains('Brohn local readiness: ready')) 'Launcher rechecks the saved optional profile without starting services'
foreach($name in $names){Check ([Environment]::GetEnvironmentVariable($name,'Process') -ceq $before[$name]) "Launcher restores process setting $name"}
Check (-not (Test-Path -LiteralPath $parameters.Workspace)) 'Readiness-only launch leaves the research workspace unopened'
$sourceHashes=@{};foreach($path in @('scripts/local-configuration.ps1','scripts/configure-local.ps1','scripts/doctor.R','scripts/check-scientific-runtime.py','scripts/readiness/facial_runtime_check.py','run-local.ps1')){
    $sourceHashes[$path]=(Get-FileHash -LiteralPath (Join-Path $project $path) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$result=@{passed=$true;checks=$checks;source_hashes=$sourceHashes;configuration_sha256=$hash.ToLowerInvariant();scope='Checked existing Windows runtimes and saved setup; no inference, acquisition, new package install or clean-machine qualification.'}
$null=Save $result 'results.json'
Write-Output "Facial configuration: $($checks.Count) checks passed. Evidence: $EvidenceDirectory"
