# Explicit configured QA subset; independent of the saved research workspace.
# Configuration selects runtimes; this profile never opens its saved workspace.
#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$ConfigurationPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('core','store','delivery','run-evidence','backup','task-portability','task-import-platform')]
    [string[]]$Test = @('core','store','delivery','run-evidence','backup','task-portability','task-import-platform')
)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This configured component QA profile currently qualifies Windows only.' }
$project = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'local-configuration.ps1')
. (Join-Path $PSScriptRoot 'configured-checks-helpers.ps1')
$configuration = Read-BrohnLocalConfiguration $ConfigurationPath
if ($Test.Count -eq 0 -or @($Test | Sort-Object -Unique).Count -ne $Test.Count) { throw 'Choose one or more tests, each only once.' }
$catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'qa-catalog.json') -Raw | ConvertFrom-Json
$profile = $catalog.configured_profiles.'portable-core'
$expectedIds = @('core','store','delivery','run-evidence','backup','task-portability','task-import-platform')
if ($catalog.schema -cne 'brohn-qa-catalog/1.0' -or $profile.schema -cne 'brohn-configured-check-profile/1.0' -or
    ($profile.test_ids -join '|') -cne ($expectedIds -join '|') -or
    ($profile.prerequisites -join '|') -cne 'core_r_lockfile|source_bound_publication_python_and_native_guard' -or
    @($profile.additional_prerequisites.PSObject.Properties).Count -ne 1 -or
    ($profile.additional_prerequisites.'task-portability' -join '|') -cne 'portability_python') {
    throw 'The configured QA profile differs from this launcher reviewed scope; review prerequisites before running.'
}
foreach ($id in $Test) {
    $entry = @($catalog.tests | Where-Object id -CEQ $id)
    if ($entry.Count -ne 1 -or $entry[0].timeout_s -le 0 -or $entry[0].timeout_s -gt 1200) { throw 'Selected check needs one bounded catalog entry.' }
}

$output = Resolve-BrohnQaPhysicalPath $OutputDirectory
$parent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $parent -PathType Container) -or (Test-Path -LiteralPath $output)) {
    throw 'Choose a new external evidence directory with an existing parent.'
}
$protected = @($project,$configuration.configuration_path,$configuration.workspace,$configuration.rscript,
    $configuration.r_library,$configuration.publication_python,$configuration.publication_manifest,$configuration.portability_python)
foreach ($item in $protected) {
    if (Test-BrohnQaPathOverlap $output (Resolve-BrohnQaPhysicalPath $item)) { throw 'Evidence must stay separate from source, saved workspace, configuration and runtimes.' }
}
$configHash = (Get-FileHash -LiteralPath $configuration.configuration_path -Algorithm SHA256).Hash.ToLowerInvariant()
$launcherSources = [ordered]@{}
foreach ($file in @($PSCommandPath,(Join-Path $PSScriptRoot 'local-configuration.ps1'),(Join-Path $PSScriptRoot 'configured-checks-helpers.ps1'),(Join-Path $PSScriptRoot 'run-checks.R'),(Join-Path $PSScriptRoot 'qa-catalog.json'))) {
    $launcherSources[(Split-Path -Leaf $file)] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest = [ordered]@{schema='brohn-configured-component-qa/1.0';status='running';started_at=[DateTime]::UtcNow.ToString('o');
    selected=@($Test);configuration_sha256=$configHash;launcher_sources=$launcherSources;powershell_version=$PSVersionTable.PSVersion.ToString();scope='Selected core component checks only; no browser, optional scientific profile, external reference comparator or physical-device qualification.';results=@()}
[IO.Directory]::CreateDirectory($output) | Out-Null
foreach ($folder in @('checks','r-user','temp')) { [IO.Directory]::CreateDirectory((Join-Path $output $folder)) | Out-Null }
$resultPath = Join-Path $output 'results.json'
Save-BrohnQaJson $manifest $resultPath
try {
    foreach ($id in $Test) {
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $configuration.rscript
        $start.WorkingDirectory = $project
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $arguments = @('--vanilla',(Join-Path $PSScriptRoot 'run-checks.R'),'--test',$id,'--output',(Join-Path (Join-Path $output 'checks') $id))
        $start.Arguments = (($arguments | ForEach-Object { ConvertTo-BrohnQaNativeArgument $_ }) -join ' ')
        foreach ($key in @($start.EnvironmentVariables.Keys)) {
            if ($key -match '^BROHN_|^R_') { $start.EnvironmentVariables.Remove($key) | Out-Null }
        }
        $settings = @{
            R_LIBS_USER=$configuration.r_library; R_LIBS_SITE=''; R_LIBS=''; R_USER=(Join-Path $output 'r-user')
            TMP=(Join-Path $output 'temp'); TEMP=(Join-Path $output 'temp'); TMPDIR=(Join-Path $output 'temp')
            BROHN_RUNTIME_MODE='local'; BROHN_RSCRIPT=$configuration.rscript
            BROHN_PUBLICATION_PYTHON=$configuration.publication_python; BROHN_PUBLICATION_NATIVE_MANIFEST=$configuration.publication_manifest
            BROHN_PYTHON=$configuration.portability_python
        }
        foreach ($key in $settings.Keys) { $start.EnvironmentVariables[$key] = $settings[$key] }
        $child = [Diagnostics.Process]::new(); $child.StartInfo = $start; $childStarted = $false
        $began = [DateTime]::UtcNow
        try {
            if (-not $child.Start()) { throw 'The configured R process did not start.' }
            $childStarted = $true; $childStartedAt = $child.StartTime
            $stdout = $child.StandardOutput.ReadToEndAsync(); $stderr = $child.StandardError.ReadToEndAsync()
            # Keep the catalog's actual test deadline. The additional bound is
            # only for this parent's runtime preflight and receipt finalization.
            $testBudget = ($catalog.tests | Where-Object id -CEQ $id).timeout_s
            $completed = $child.WaitForExit([int](($testBudget + 120) * 1000))
            if (-not $completed) { Stop-BrohnQaOwnedProcess -Process $child -StartedAt $childStartedAt }
            [IO.File]::WriteAllText((Join-Path $output ($id + '-runner-stdout.log')), $stdout.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $output ($id + '-runner-stderr.log')), $stderr.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
            $unchanged = $configHash -eq (Get-FileHash -LiteralPath $configuration.configuration_path -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifest.results += [ordered]@{id=$id;exit_code=$child.ExitCode;status=$(if($completed -and $child.ExitCode -eq 0 -and $unchanged){'passed'}else{'failed'});duration_s=([DateTime]::UtcNow-$began).TotalSeconds;configuration_unchanged=$unchanged;runner_watchdog_expired=(-not $completed)}
            Save-BrohnQaJson $manifest $resultPath
            Write-Output (($manifest.results[-1].status.ToUpperInvariant()) + ' ' + $id)
        } finally {
            if ($childStarted -and -not $child.HasExited) { Stop-BrohnQaOwnedProcess -Process $child -StartedAt $childStartedAt }
            $child.Dispose()
        }
    }
    $manifest.status = if (@($manifest.results | Where-Object status -ne 'passed').Count) { 'failed' } else { 'passed' }
} catch {
    $manifest.status = 'failed'
    $manifest['failure'] = $_.Exception.Message
    throw
} finally {
    $sourcesUnchanged = $true
    foreach ($file in @($PSCommandPath,(Join-Path $PSScriptRoot 'local-configuration.ps1'),(Join-Path $PSScriptRoot 'configured-checks-helpers.ps1'),(Join-Path $PSScriptRoot 'run-checks.R'),(Join-Path $PSScriptRoot 'qa-catalog.json'))) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $launcherSources[(Split-Path -Leaf $file)]) { $sourcesUnchanged = $false }
    }
    $manifest['launcher_sources_unchanged'] = $sourcesUnchanged
    if (-not $sourcesUnchanged) { $manifest.status = 'failed' }
    $manifest['finished_at'] = [DateTime]::UtcNow.ToString('o')
    Save-BrohnQaJson $manifest $resultPath
}
if ($manifest.status -ne 'passed') { throw 'A selected configured check did not pass; inspect the retained results.' }
