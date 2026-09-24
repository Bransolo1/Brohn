# Focused native/helper/refusal qualification; no catalog test is run here.
#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ConfigurationPath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'scripts/local-configuration.ps1')
. (Join-Path $project 'scripts/configured-checks-helpers.ps1')
$configuration=Read-BrohnLocalConfiguration $ConfigurationPath
$folder=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $folder){throw 'Choose a new external evidence directory.'}
if(Test-BrohnQaPathOverlap (Resolve-BrohnQaPhysicalPath $folder) (Resolve-BrohnQaPhysicalPath $project)){throw 'Evidence must be external.'}
[IO.Directory]::CreateDirectory($folder)|Out-Null
$checks=@();$failure=$null;$owned=@()
function Check([string]$Name,[bool]$Value){if(-not $Value){throw $Name};$script:checks+=@($Name);Write-Output ('PASS '+$Name)}
function Run-Native([string]$Executable,[string[]]$Arguments,[string]$Name){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Executable;$info.Arguments=(($Arguments|ForEach-Object{ConvertTo-BrohnQaNativeArgument $_})-join ' ')
    $info.WorkingDirectory=$folder;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info;$started=$false
    try{[void]$p.Start();$started=$true;$began=$p.StartTime;$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(60000)){Stop-BrohnQaOwnedProcess $p $began;throw 'Focused invocation exceeded its budget.'}
        $stdout=$out.GetAwaiter().GetResult();$stderr=$err.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $folder ($Name+'-stdout.log')),$stdout,(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $folder ($Name+'-stderr.log')),$stderr,(New-Object Text.UTF8Encoding($false)))
        return [pscustomobject]@{status=$p.ExitCode;stdout=$stdout;stderr=$stderr}
    }finally{if($started -and -not $p.HasExited){Stop-BrohnQaOwnedProcess $p $began};$p.Dispose()}
}
function Refuse([string]$Name,[string]$Config,[string]$Destination,[string[]]$Extra=@(),[string]$Pattern='Evidence must stay separate',[string]$Launcher=(Join-Path $project 'scripts/run-configured-checks.ps1')){
    $out=Run-Native (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') (@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Launcher,'-ConfigurationPath',$Config,'-OutputDirectory',$Destination)+$Extra) $Name
    Check $Name ($out.status -ne 0 -and $out.stderr -match $Pattern)
}
try{
    Check 'Executed on actual Windows PowerShell 5.1' ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1)
    $originalHash=(Get-FileHash -LiteralPath $configuration.configuration_path -Algorithm SHA256).Hash
    $argsScript=Join-Path $folder 'literal args.R';$argsOutput=Join-Path $folder 'argument-hex.txt'
    [IO.File]::WriteAllText($argsScript,'a<-commandArgs(TRUE);writeLines(vapply(a[-1],function(x)paste(sprintf("%02x",as.integer(charToRaw(enc2utf8(x)))),collapse=""),character(1)),a[1],useBytes=TRUE)',(New-Object Text.UTF8Encoding($false)))
    $literal=@('','one space','embedded"quote','ends\','back\\"quote','C:\path with space\','$(literal) & | > <')
    $argResult=Run-Native $configuration.rscript (@('--vanilla',$argsScript,$argsOutput)+$literal) 'native-arguments'
    $expected=@($literal|ForEach-Object{([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($_))).Replace('-','').ToLowerInvariant()})
    $actual=@([IO.File]::ReadAllLines($argsOutput))
    Check 'Actual R receives exact empty/space/quote/backslash/shell-like argument bytes without a shell' ($argResult.status -eq 0 -and ($actual-join '|') -ceq ($expected-join '|'))
    $existing=Join-Path $folder 'existing';[IO.Directory]::CreateDirectory($existing)|Out-Null
    Refuse 'Existing evidence is refused' $configuration.configuration_path $existing @() 'Choose a new external evidence directory'
    Refuse 'Checkout evidence is refused' $configuration.configuration_path (Join-Path $project 'must-not-create-qa')
    Refuse 'Configured research workspace evidence is refused' $configuration.configuration_path (Join-Path $configuration.workspace 'must-not-create-qa')
    Refuse 'Unknown or unreviewed test is refused' $configuration.configuration_path (Join-Path $folder 'unreviewed') @('-Test','raw-gaze') 'ValidateSet|does not belong'
    Check 'Refusals create no output under protected paths' (-not(Test-Path -LiteralPath (Join-Path $project 'must-not-create-qa')) -and -not(Test-Path -LiteralPath (Join-Path $configuration.workspace 'must-not-create-qa')) -and -not(Test-Path -LiteralPath (Join-Path $folder 'unreviewed')))
    $junction=Join-Path $folder 'source-junction'
    New-Item -ItemType Junction -Path $junction -Value $project|Out-Null
    Check 'Physical path resolver follows a real junction' ((Resolve-BrohnQaPhysicalPath $junction) -ieq (Resolve-BrohnQaPhysicalPath $project))
    Refuse 'Junction into checkout is refused' $configuration.configuration_path (Join-Path $junction 'must-not-create-qa')
    $bad=Get-Content -LiteralPath $configuration.configuration_path -Raw|ConvertFrom-Json
    $bad.r_library=Join-Path $folder 'missing-library';$badConfig=Join-Path $folder 'missing-library.json';Save-BrohnQaJson $bad $badConfig
    Refuse 'Missing explicit library is refused before any test' $badConfig (Join-Path $folder 'missing-library-result') @() 'configured r_library was not found'
    Check 'Missing-prerequisite refusal creates no evidence/store' (-not(Test-Path -LiteralPath (Join-Path $folder 'missing-library-result')))
    $badProject=Join-Path $folder 'bad-profile-project';$badScripts=Join-Path $badProject 'scripts';[IO.Directory]::CreateDirectory($badScripts)|Out-Null
    foreach($file in @('run-configured-checks.ps1','configured-checks-helpers.ps1','local-configuration.ps1')){Copy-Item -LiteralPath (Join-Path (Join-Path $project 'scripts') $file) -Destination (Join-Path $badScripts $file)}
    $badCatalog=Get-Content -LiteralPath (Join-Path $project 'scripts/qa-catalog.json') -Raw|ConvertFrom-Json
    $badCatalog.configured_profiles.'portable-core'.test_ids+=@('raw-gaze')
    Save-BrohnQaJson $badCatalog (Join-Path $badScripts 'qa-catalog.json')
    Refuse 'Changed catalog scope requires an explicit review' $configuration.configuration_path (Join-Path $folder 'bad-profile-result') @() 'differs from this launcher reviewed scope' (Join-Path $badScripts 'run-configured-checks.ps1')
    Check 'Changed-profile refusal creates no evidence/store' (-not(Test-Path -LiteralPath (Join-Path $folder 'bad-profile-result')))
    $badNative=Get-Content -LiteralPath $configuration.configuration_path -Raw|ConvertFrom-Json
    $badNative.publication_manifest=Join-Path $folder 'invalid-native.json';[IO.File]::WriteAllText($badNative.publication_manifest,'{}')
    $badNativeConfig=Join-Path $folder 'bad-native-config.json';Save-BrohnQaJson $badNative $badNativeConfig
    $badNativeOutput=Join-Path $folder 'bad-native-result'
    Refuse 'Existing invalid native manifest fails actual R readiness' $badNativeConfig $badNativeOutput @('-Test','core') 'A selected configured check did not pass'
    $nativeLog=Get-Content -LiteralPath (Join-Path $badNativeOutput 'core-runner-stderr.log') -Raw
    Check 'Native refusal occurs before any selected test assertions or store' ($nativeLog -match "publisher needs attention" -and -not(Test-Path -LiteralPath (Join-Path $badNativeOutput 'checks/core')))
    $childScript=Join-Path $folder 'owned-child.R';$parentScript=Join-Path $folder 'owned-parent.R'
    $childPidFile=Join-Path $folder 'owned-child.pid'
    [IO.File]::WriteAllText($childScript,'a<-commandArgs(TRUE);writeLines(as.character(Sys.getpid()),a[1]);Sys.sleep(90)',(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($parentScript,'a<-commandArgs(TRUE);p<-processx::process$new(file.path(R.home("bin"),"Rscript.exe"),c("--vanilla",a[1],a[2]),windows_hide_window=TRUE);Sys.sleep(90)',(New-Object Text.UTF8Encoding($false)))
    $pi=New-Object Diagnostics.ProcessStartInfo;$pi.FileName=$configuration.rscript
    $pi.Arguments=((@('--vanilla',$parentScript,$childScript,$childPidFile)|ForEach-Object{ConvertTo-BrohnQaNativeArgument $_})-join ' ')
    $pi.UseShellExecute=$false;$pi.CreateNoWindow=$true;$pi.EnvironmentVariables['R_LIBS_USER']=$configuration.r_library
    $parent=New-Object Diagnostics.Process;$parent.StartInfo=$pi;[void]$parent.Start();$parentStart=$parent.StartTime
    $owned+=@([pscustomobject]@{process=$parent;started=$parentStart})
    $until=[DateTime]::UtcNow.AddSeconds(20);while(-not(Test-Path -LiteralPath $childPidFile)-and[DateTime]::UtcNow-lt$until){Start-Sleep -Milliseconds 100}
    Check 'Owned cleanup fixture starts an actual R descendant' (Test-Path -LiteralPath $childPidFile)
    $childId=[int]([IO.File]::ReadAllText($childPidFile).Trim())
    $wrongRefused=$false;try{Stop-BrohnQaOwnedProcess $parent $parentStart.AddSeconds(1)}catch{$wrongRefused=$true}
    Check 'Cleanup refuses mismatched process start identity without stopping it' ($wrongRefused -and -not $parent.HasExited)
    Stop-BrohnQaOwnedProcess $parent $parentStart
    $descendant=Get-Process -Id $childId -ErrorAction SilentlyContinue
    Check 'Cleanup stops the exact owned process and its real descendant' ($parent.HasExited -and $null -eq $descendant)
    Check 'Original supplied configuration bytes remain unchanged' ((Get-FileHash -LiteralPath $configuration.configuration_path -Algorithm SHA256).Hash -ceq $originalHash)
}catch{$failure=$_.Exception.Message;throw}finally{
    foreach($entry in $owned){if(-not $entry.process.HasExited){Stop-BrohnQaOwnedProcess $entry.process $entry.started};$entry.process.Dispose()}
    Save-BrohnQaJson ([ordered]@{schema='brohn-configured-qa-focused/1.0';status=$(if($failure){'failed'}else{'passed'});checks=$checks;failure=$failure;powershell_version=$PSVersionTable.PSVersion.ToString();scope='Actual Windows PowerShell/helper/native argv/refusal/owned-tree checks; no catalog suite execution.'}) (Join-Path $folder 'results.json')
}
