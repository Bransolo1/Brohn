param(
    [Parameter(Mandatory=$true)][string]$TestRoot,
    [Parameter(Mandatory=$true)][string]$RscriptPath,
    [Parameter(Mandatory=$true)][string]$PythonPath,
    [Parameter(Mandatory=$true)][string]$CompilerPath,
    [string]$CacheRoot=''
)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$TestRoot=[IO.Path]::GetFullPath($TestRoot)
if (-not (Split-Path -Leaf $TestRoot).StartsWith('brohn-setup-check-') -or (Test-Path -LiteralPath $TestRoot)) { throw 'Choose a fresh external brohn-setup-check-* directory.' }
New-Item -ItemType Directory -Path $TestRoot | Out-Null
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Label) { if(-not $Condition){throw "FAILED: $Label"};$checks.Add($Label);Write-Output "PASS $Label" }
function Reject([scriptblock]$Action,[string]$Label) { $failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Label }
$installation=Join-Path $TestRoot 'installation'
$setup=Join-Path $project 'scripts/setup-local.ps1'
$arguments=@{InstallationRoot=$installation;RscriptPath=$RscriptPath;PythonPath=$PythonPath;CompilerPath=$CompilerPath;Port=3895;ParticipantPort=3896}
if($CacheRoot){$arguments.CacheRoot=$CacheRoot}
$keys=@('R_LIBS_USER','RENV_PATHS_ROOT','LC_ALL','BROHN_PUBLICATION_PYTHON','BROHN_PUBLICATION_NATIVE_MANIFEST')
$before=@{};foreach($key in $keys){$before[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
& $setup @arguments *> (Join-Path $TestRoot 'initial-setup.log')
$configuration=Join-Path $installation 'local-installation.json'
Check (Test-Path -LiteralPath $configuration) 'Fresh separate installation finishes and saves a checked configuration'
$value=Get-Content -LiteralPath $configuration -Raw | ConvertFrom-Json
Check (-not (Test-Path -LiteralPath $value.workspace)) 'Setup does not create a research workspace'
Check ((Test-Path -LiteralPath $value.publication_manifest) -and (Test-Path -LiteralPath (Join-Path $value.r_library 'shiny/DESCRIPTION'))) 'Separate application library and protected publication runtime exist'
$hash=(Get-FileHash -LiteralPath $configuration).Hash
$nativeHash=(Get-FileHash -LiteralPath $value.publication_manifest).Hash
Reject { & $setup @arguments *> (Join-Path $TestRoot 'existing-configuration.log') } 'Existing checked configuration requires explicit replacement'
Check ((Get-FileHash -LiteralPath $configuration).Hash -eq $hash) 'Refused replacement preserves the original configuration'
$unrelated=Join-Path $TestRoot 'unrelated';New-Item -ItemType Directory -Path $unrelated | Out-Null
[IO.File]::WriteAllText((Join-Path $unrelated 'keep.txt'),'Unrelated original file')
$invalid=$arguments.Clone();$invalid.InstallationRoot=$unrelated
Reject { & $setup @invalid *> (Join-Path $TestRoot 'unrelated.log') } 'Nonempty unrelated directory is refused'
Check ([IO.File]::ReadAllText((Join-Path $unrelated 'keep.txt')) -eq 'Unrelated original file') 'Unrelated file bytes remain unchanged'
$invalid=$arguments.Clone();$invalid.InstallationRoot=Join-Path $TestRoot 'invalid-ports';$invalid.ParticipantPort=$invalid.Port
Reject { & $setup @invalid *> (Join-Path $TestRoot 'invalid-ports.log') } 'Conflicting service ports fail before creating an installation'
Check (-not (Test-Path -LiteralPath $invalid.InstallationRoot)) 'Invalid port setup leaves no installation directory'
$badCompiler=Join-Path $TestRoot 'invalid-compiler/not-a-program.exe';New-Item -ItemType Directory -Path (Split-Path -Parent $badCompiler) | Out-Null
[IO.File]::WriteAllText($badCompiler,'Original deliberate invalid tool fixture')
$invalid=$arguments.Clone();$invalid.CompilerPath=$badCompiler;$invalid.ReplaceConfiguration=$true
Reject { & $setup @invalid *> (Join-Path $TestRoot 'failed-replacement.log') } 'Actual native build failure prevents replacement from being accepted'
Check ((Get-FileHash -LiteralPath $configuration).Hash -eq $hash -and (Get-FileHash -LiteralPath $value.publication_manifest).Hash -eq $nativeHash) 'Failed preparation preserves prior configuration and native manifest'
Check (-not (Test-Path -LiteralPath (Join-Path $installation '.setup.lock'))) 'Failed setup releases its owned lock for a retry'
foreach($key in $keys){Check ([Environment]::GetEnvironmentVariable($key,'Process') -ceq $before[$key]) "Environment restored after success and failure: $key"}
$arguments.ReplaceConfiguration=$true
& $setup @arguments *> (Join-Path $TestRoot 'recovered-setup.log')
& (Join-Path $project 'run-local.ps1') -ConfigurationPath $configuration -CheckOnly *> (Join-Path $TestRoot 'launcher-check.log')
Check (-not (Test-Path -LiteralPath $value.workspace)) 'Successful retry and actual launcher readiness preserve the unopened workspace'
Check (-not (Test-Path -LiteralPath (Join-Path $installation '.setup.lock'))) 'Successful retry releases its owned setup lock'
$sources=@{};foreach($file in @('scripts/setup-local.ps1','scripts/bootstrap-dependencies.R')){$sources[$file]=(Get-FileHash -LiteralPath (Join-Path $project $file)).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText((Join-Path $TestRoot 'results.json'),(@{checks=@($checks);configuration=$configuration;sources=$sources;scope='Fresh isolated R library, native build, configuration failure/retry and real launcher readiness on an existing Windows host.'} | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output "PASS $($checks.Count) setup and recovery checks; $TestRoot"
