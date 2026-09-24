param(
    [Parameter(Mandatory=$true)][string]$ProfilePath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$RscriptPath,
    [Parameter(Mandatory=$true)][string]$LibraryPath,
    [Parameter(Mandatory=$true)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$ClientSecretFile,
    [Parameter(Mandatory=$true)][string]$CookieSecretFile
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($item in @($ProfilePath,$RscriptPath,$ClientSecretFile,$CookieSecretFile)) {
    if(-not(Test-Path -LiteralPath $item -PathType Leaf)){throw 'A required configuration, executable or secret file is absent.'}
}
if(-not(Test-Path -LiteralPath $LibraryPath -PathType Container)){throw 'Choose the prepared R application library.'}
$destination=[IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory))
$sourceRoot=[IO.Path]::GetFullPath($repo).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
if($destination.StartsWith($sourceRoot,[StringComparison]::OrdinalIgnoreCase)-or$destination-eq$repo){throw 'Keep hosted configuration and secrets outside the source checkout.'}
if(Test-Path -LiteralPath $destination){throw 'Choose a new hosted configuration directory; existing attempts are retained.'}
$r=(Resolve-Path -LiteralPath $RscriptPath).Path
$library=(Resolve-Path -LiteralPath $LibraryPath).Path
$arguments=@('--vanilla','scripts/configure-hosted.R',(Resolve-Path -LiteralPath $ProfilePath).Path,$destination,$ClientId,
    (Resolve-Path -LiteralPath $ClientSecretFile).Path,(Resolve-Path -LiteralPath $CookieSecretFile).Path)
New-Item -ItemType Directory -Path $destination | Out-Null
$priorLibrary=$env:R_LIBS_USER;$priorLocale=$env:LC_ALL
Push-Location -LiteralPath $repo
try {
    $env:R_LIBS_USER=$library;$env:LC_ALL='C'
    & $r @arguments
    if($LASTEXITCODE-ne0){throw 'Hosted configuration check failed. The attempted output directory is retained.'}
} finally {
    Pop-Location
    $env:R_LIBS_USER=$priorLibrary;$env:LC_ALL=$priorLocale
}
