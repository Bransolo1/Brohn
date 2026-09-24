# Focused launcher preflight/refusal checks. No HTTP or research service starts.
param(
    [Parameter(Mandatory=$true)][string]$ConfigurationPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$NodePath,
    [Parameter(Mandatory=$true)][string]$BrowserExecutablePath,
    [Parameter(Mandatory=$true)][string]$NodeToolsRoot
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'scripts/local-configuration.ps1')
$configuration = Read-BrohnLocalConfiguration $ConfigurationPath
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Use a fresh external test evidence directory.' }
if ($output.StartsWith($project+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Keep evidence outside the checkout.' }
New-Item -ItemType Directory -Path $output | Out-Null
$beforeHash = (Get-FileHash -LiteralPath $configuration.configuration_path -Algorithm SHA256).Hash
$checks = [Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Label) { if (-not $Condition) { throw "FAILED: $Label" }; $checks.Add($Label) }
function Reject([hashtable]$Arguments,[string]$Label) {
    $failed = $false
    try { & (Join-Path $project 'scripts/run-connected-smoke.ps1') @Arguments *> (Join-Path $output ($Label+'.log')) } catch { $failed = $true }
    Check $failed $Label
}
$arguments = @{ConfigurationPath=$configuration.configuration_path;OutputDirectory=(Join-Path $output 'ready');NodePath=$NodePath;BrowserExecutablePath=$BrowserExecutablePath;NodeToolsRoot=$NodeToolsRoot;CheckOnly=$true}
$keys = @('BROHN_WORKSPACE','BROHN_HOSTED_PROFILE','BROHN_PYTHON_METHODS','R_LIBS_USER','R_PROFILE','LC_ALL')
$previous = @{}; foreach ($key in $keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
$encoding = $OutputEncoding
try {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,'original-caller-sentinel','Process') }
    & (Join-Path $project 'scripts/run-connected-smoke.ps1') @arguments *> (Join-Path $output 'readiness.log')
    $receipt = Get-Content -LiteralPath (Join-Path $output 'ready/results.json') -Raw | ConvertFrom-Json
    Check ($receipt.status -ceq 'passed' -and $receipt.mode -ceq 'readiness_only' -and @($receipt.cycles).Count -eq 0) 'Readiness uses explicit runtimes and starts no integrated service'
    Check (-not (Test-Path -LiteralPath (Join-Path $output 'ready/workspace'))) 'Readiness creates no study workspace'
    foreach ($key in $keys) { Check ([Environment]::GetEnvironmentVariable($key,'Process') -ceq 'original-caller-sentinel') "Caller environment preserved $key" }
    Check ([object]::ReferenceEquals($OutputEncoding,$encoding)) 'Caller pipe encoding restored'
    Reject $arguments.Clone() 'existing-evidence-refused'
    $invalid = $arguments.Clone(); $invalid.OutputDirectory = Join-Path $configuration.workspace 'forbidden-smoke-child'
    Reject $invalid 'configured-workspace-refused'
    Check (-not (Test-Path -LiteralPath $invalid.OutputDirectory)) 'Refused workspace destination remains absent'
    $invalid = $arguments.Clone(); $invalid.OutputDirectory = Join-Path $project 'forbidden-smoke-output'
    Reject $invalid 'checkout-evidence-refused'
    Check (-not (Test-Path -LiteralPath $invalid.OutputDirectory)) 'Refused checkout destination remains absent'
    $invalid = $arguments.Clone(); $invalid.OutputDirectory = Join-Path $output 'invalid-browser'; $invalid.BrowserExecutablePath = Join-Path $output 'missing-browser.exe'
    Reject $invalid 'missing-browser-refused'
    Check (-not (Test-Path -LiteralPath $invalid.OutputDirectory)) 'Missing browser fails before evidence creation'
    Check ((Get-FileHash -LiteralPath $configuration.configuration_path -Algorithm SHA256).Hash -ceq $beforeHash) 'Supplied configuration bytes preserved after success and refusals'
    [IO.File]::WriteAllText((Join-Path $output 'results.json'),(@{status='passed';checks=@($checks);scope='Actual launcher readiness and path/environment refusals; no integrated service or research workspace mutation.'} | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    Write-Output "PASS $($checks.Count) portable launcher checks; $output"
} finally {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key],'Process') }
}
