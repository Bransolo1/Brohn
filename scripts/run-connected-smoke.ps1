# Connected local release smoke. The saved research workspace is never opened.
param(
    [Parameter(Mandatory=$true)][string]$ConfigurationPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$NodePath,
    [Parameter(Mandatory=$true)][string]$BrowserExecutablePath,
    [string]$NodeToolsRoot = '',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This connected smoke profile currently qualifies Windows only.' }
$project = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'local-configuration.ps1')
$configuration = Read-BrohnLocalConfiguration $ConfigurationPath
$invocation = (Get-Location).ProviderPath
$NodePath = Resolve-BrohnConfiguredPath $NodePath $invocation 'Leaf' 'Node executable'
$BrowserExecutablePath = Resolve-BrohnConfiguredPath $BrowserExecutablePath $invocation 'Leaf' 'Chromium browser executable'
if (-not $NodeToolsRoot) { $NodeToolsRoot = $project }
$NodeToolsRoot = Resolve-BrohnConfiguredPath $NodeToolsRoot $invocation 'Container' 'pinned Node tools root'
$output = Resolve-BrohnConfiguredPath $OutputDirectory $invocation '' 'fresh external evidence directory'
# Supply runtime paths only. The harness rejects overlap with this forbidden
# workspace and always derives its own workspace inside a new evidence folder.
$request = [ordered]@{
    schema = 'brohn-connected-smoke-request/1.0'; project = $project; output = $output
    configuration_path = $configuration.configuration_path
    configuration_sha256 = (Get-FileHash -LiteralPath $configuration.configuration_path -Algorithm SHA256).Hash.ToLowerInvariant()
    forbidden_workspace = $configuration.workspace
    rscript = $configuration.rscript; r_library = $configuration.r_library
    publication_python = $configuration.publication_python; publication_manifest = $configuration.publication_manifest
    portability_python = $configuration.portability_python
    node_tools_root = $NodeToolsRoot; browser_executable = $BrowserExecutablePath
    check_only = [bool]$CheckOnly
}
$priorEncoding = $OutputEncoding
try {
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    $request | ConvertTo-Json -Depth 6 -Compress | & $NodePath (Join-Path $project 'tests/connected-smoke.mjs')
    if ($LASTEXITCODE -ne 0) { throw "Connected smoke did not pass (exit $LASTEXITCODE). Inspect the external evidence directory, if created." }
} finally { $OutputEncoding = $priorEncoding }
