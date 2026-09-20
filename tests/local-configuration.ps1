param([Parameter(Mandatory = $true)][string]$ConfigurationPath)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'scripts/local-configuration.ps1')
$installation = Read-BrohnLocalConfiguration $ConfigurationPath
$fixture = Join-Path (Split-Path -Parent $ConfigurationPath) ('brohn-configuration-check-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$checks = [Collections.Generic.List[string]]::new()
function Check([bool]$Condition, [string]$Label) { if (-not $Condition) { throw "FAILED: $Label" }; $checks.Add($Label) }
function Reject([scriptblock]$Action, [string]$Label) { $failed = $false; try { & $Action | Out-Null } catch { $failed = $true }; Check $failed $Label }
function Write-Fixture($Value, [string]$Name = 'candidate.json') {
    $path = Join-Path $fixture $Name
    [IO.File]::WriteAllText($path, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    return $path
}
$original = Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($installation.rscript -eq $original.rscript -and $installation.workspace -eq $original.workspace) 'Explicit installed paths are preserved'
$relative = Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$relative.workspace = 'study workspace é'
$relativePath = Write-Fixture $relative
Push-Location -LiteralPath $project
try { $resolved = Read-BrohnLocalConfiguration $relativePath } finally { Pop-Location }
Check ($resolved.workspace -eq (Join-Path $fixture 'study workspace é')) 'Relative workspace resolves against configuration, including spaces and Unicode'
Check (-not (Test-Path -LiteralPath $resolved.workspace)) 'Reading configuration does not create research storage'
$invalid = Get-Content -LiteralPath $relativePath -Raw -Encoding UTF8 | ConvertFrom-Json
$invalid.ports.participant = $invalid.ports.researcher
Reject { Read-BrohnLocalConfiguration (Write-Fixture $invalid) } 'Shared researcher and participant port is rejected'
$invalid.ports.participant = 3840.5
Reject { Read-BrohnLocalConfiguration (Write-Fixture $invalid) } 'Fractional ports are rejected without rounding'
$invalid.ports.participant = 80
Reject { Read-BrohnLocalConfiguration (Write-Fixture $invalid) } 'Privileged/out-of-range ports are rejected'
$invalid.ports.participant = 3840
$invalid.schema = 'other/1.0'
Reject { Read-BrohnLocalConfiguration (Write-Fixture $invalid) } 'Unknown schemas fail before launch'
$invalid.schema = 'brohn-local-installation/1.0'
$invalid.scientific = @{ arbitrary = $installation.publication_python }
Reject { Read-BrohnLocalConfiguration (Write-Fixture $invalid) } 'Unknown scientific profiles cannot become environment settings'
$invalid.scientific = @{}
$invalid.rscript = Join-Path $fixture 'missing.exe'
Reject { Read-BrohnLocalConfiguration (Write-Fixture $invalid) } 'Missing configured runtime fails rather than falling back globally'
$invalid.rscript = $installation.rscript
$invalid | Add-Member -NotePropertyName 'command' -NotePropertyValue 'unrecognised executable expression'
Reject { Read-BrohnLocalConfiguration (Write-Fixture $invalid) } 'Configuration accepts data-only declared fields'

$saved = Join-Path $fixture 'verified.json'
$parameters = @{
    RscriptPath = $installation.rscript; LibraryPath = $installation.r_library
    PublicationPythonPath = $installation.publication_python; PublicationManifestPath = $installation.publication_manifest
    PortabilityPythonPath = $installation.portability_python; Workspace = (Join-Path $fixture 'research workspace')
    ConfigurationPath = $saved
}
$environmentNames = @('R_LIBS_USER','LC_ALL','BROHN_PUBLICATION_PYTHON','BROHN_PUBLICATION_NATIVE_MANIFEST','BROHN_PYTHON','BROHN_WORKSPACE','BROHN_APP_MODE','RESEARCH_PLATFORM_PORT','BROHN_PARTICIPANT_PORT','R_USER')
$before = @{}
foreach ($name in $environmentNames) { $before[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$setupLog = & (Join-Path $project 'scripts/configure-local.ps1') @parameters | Out-String
[IO.File]::WriteAllText((Join-Path $fixture 'setup.log'), $setupLog)
Check ((Test-Path -LiteralPath $saved) -and $setupLog.Contains('installation verified and saved')) 'Actual pinned R/publication/portability checks gate configuration creation'
Check (-not (Test-Path -LiteralPath $parameters.Workspace)) 'Configuration checks leave workspace absent'
foreach ($name in $environmentNames) { Check ([Environment]::GetEnvironmentVariable($name,'Process') -ceq $before[$name]) "Setup restores process environment: $name" }
$hashBefore = (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
Reject { & (Join-Path $project 'scripts/configure-local.ps1') @parameters } 'Existing configuration needs explicit replacement'
Check ((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ceq $hashBefore) 'Refused reconfiguration preserves exact prior bytes'
$parameters.Replace = $true
$emptyLibrary = Join-Path $fixture 'empty-library'
New-Item -ItemType Directory -Path $emptyLibrary | Out-Null
$parameters.LibraryPath = $emptyLibrary
Reject { & (Join-Path $project 'scripts/configure-local.ps1') @parameters } 'Failed real dependency check does not activate a replacement'
Check ((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ceq $hashBefore) 'Failed replacement retains the verified configuration'
$readinessLog = & (Join-Path $project 'run-local.ps1') -ConfigurationPath $saved -CheckOnly -Port 3881 | Out-String
[IO.File]::WriteAllText((Join-Path $fixture 'launcher-readiness.log'), $readinessLog)
Check ($readinessLog.Contains('Brohn local readiness: ready')) 'Configured launcher rechecks real dependencies without starting services'
Check (-not (Test-Path -LiteralPath $parameters.Workspace)) 'Readiness-only launch does not open or create research storage'
foreach ($name in $environmentNames) { Check ([Environment]::GetEnvironmentVariable($name,'Process') -ceq $before[$name]) "Launcher restores process environment: $name" }
$result = @{passed = $true; checks = $checks; fixture = $fixture}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $fixture 'results.json') -Encoding UTF8
Write-Output "Local configuration: $($checks.Count) checks passed. Evidence: $fixture"
