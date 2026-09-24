param(
    [Parameter(Mandatory = $true)][string]$PythonPath,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][ValidateSet('methods','acquisition','vision-audio','segmentation','facial-au')][string[]]$Profiles
)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'Supply the explicit path to an installed Python 3.12 interpreter.' }
$PythonPath = (Resolve-Path -LiteralPath $PythonPath).Path
$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
$Destination = [IO.Path]::GetFullPath($Destination)
if ($Destination.TrimEnd('\','/').Equals($repository.TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase) -or
    $Destination.StartsWith($repository.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Choose an isolated environment destination outside the repository.'
}
# Reject existing reparse-point ancestors so an apparently external destination
# cannot redirect installed packages back into the repository or another target.
$cursor = $Destination
while ($cursor) {
    if (Test-Path -LiteralPath $cursor) {
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Choose a destination without reparse-point ancestors.' }
    }
    $parent = Split-Path -Parent $cursor
    if ($parent -eq $cursor) { break }
    $cursor = $parent
}
$version = & $PythonPath -I -c 'import sys; print("%s.%s" % sys.version_info[:2])'
if ($LASTEXITCODE -ne 0 -or ($version -join '').Trim() -ne '3.12') { throw 'The pinned scientific profiles require Python 3.12.' }
$requirements = @{
    'methods' = 'scripts/benchmarks/requirements-methods.txt'
    'acquisition' = 'scripts/readiness/requirements-acquisition.txt'
    'vision-audio' = 'scripts/readiness/requirements-media.txt'
    'segmentation' = 'scripts/readiness/requirements-segmentation.txt'
    'facial-au' = 'scripts/readiness/requirements-facial-au.txt'
}
$Profiles = @($Profiles | Select-Object -Unique)
foreach ($profile in $Profiles) {
    $target = Join-Path $Destination ($profile + '-venv')
    if (Test-Path -LiteralPath $target) { throw "Destination already exists: $target. This installer only creates new environments and never upgrades an existing profile." }
    if (-not (Test-Path -LiteralPath (Join-Path $repository $requirements[$profile]) -PathType Leaf)) { throw "Missing pinned requirements for $profile." }
}
foreach ($profile in $Profiles) {
    $target = Join-Path $Destination ($profile + '-venv')
    & $PythonPath -I -m venv $target
    if ($LASTEXITCODE -ne 0) { throw "Could not create $profile. The partial target is retained for inspection; choose a fresh destination for another attempt." }
    $interpreter = Join-Path $target 'Scripts/python.exe'
    $requirement = Join-Path $repository $requirements[$profile]
    # Every dependency is named in the profile freeze. Do not resolve unpinned
    # extras or execute source-package builds when a platform wheel is absent.
    & $interpreter -I -m pip install --disable-pip-version-check --only-binary=:all: --no-deps --requirement $requirement
    if ($LASTEXITCODE -ne 0) { throw "Pinned wheel installation failed for $profile. The partial environment is retained; it has not been activated." }
    & $interpreter -I -m pip check
    if ($LASTEXITCODE -ne 0) { throw "Dependency consistency failed for $profile. Do not configure this profile until it is corrected." }
    $variable = 'BROHN_PYTHON_' + $profile.ToUpperInvariant().Replace('-', '_')
    Write-Output "$profile installed at $interpreter"
    Write-Output "Configure $variable with that executable path, then run scripts/doctor.R."
}
Write-Output 'No environment was activated. Model weights and ffprobe/ffmpeg are separate explicit prerequisites; no camera or device discovery was performed.'
