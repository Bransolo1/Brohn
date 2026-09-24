# Windows PowerShell 5.1-compatible helpers; sourcing starts no process/store.
function ConvertTo-BrohnQaNativeArgument {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)
    if ($Value.IndexOf([char]0) -ge 0) { throw 'Native arguments cannot contain NUL.' }
    # Windows CommandLineToArgvW/CRT quoting; ProcessStartInfo never uses a shell.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}
function Resolve-BrohnQaPhysicalPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not ('BrohnQaPhysicalPath' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class BrohnQaPhysicalPath {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle, StringBuilder name, uint size, uint flags);
  public static string Resolve(string path) {
    using (var handle=CreateFileW(path,0,7,IntPtr.Zero,3,0x02000000,IntPtr.Zero)) {
      if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
      var buffer=new StringBuilder(32768);
      uint length=GetFinalPathNameByHandleW(handle,buffer,(uint)buffer.Capacity,0);
      if(length==0) throw new Win32Exception(Marshal.GetLastWin32Error());
      if(length>=buffer.Capacity) throw new InvalidOperationException("Resolved path exceeds the supported bound.");
      string result=buffer.ToString();
      if(result.StartsWith(@"\\?\UNC\",StringComparison.OrdinalIgnoreCase)) return @"\\"+result.Substring(8);
      return result.StartsWith(@"\\?\",StringComparison.Ordinal) ? result.Substring(4) : result;
    }
  }
}
'@
    }
    $cursor = [IO.Path]::GetFullPath($Path)
    $tail = @()
    while (-not (Test-Path -LiteralPath $cursor)) {
        $tail = @(Split-Path -Leaf $cursor) + $tail
        $next = Split-Path -Parent $cursor
        if (-not $next -or $next -eq $cursor) { throw 'No existing ancestor for the selected path.' }
        $cursor = $next
    }
    $actual = [BrohnQaPhysicalPath]::Resolve($cursor)
    foreach ($piece in $tail) { $actual = Join-Path $actual $piece }
    return [IO.Path]::GetFullPath($actual).TrimEnd([char[]]@('\','/'))
}
function Test-BrohnQaPathOverlap {
    param([string]$A,[string]$B)
    $aLower = $A.ToLowerInvariant(); $bLower = $B.ToLowerInvariant()
    return $aLower -eq $bLower -or $aLower.StartsWith($bLower + '\') -or $bLower.StartsWith($aLower + '\')
}
function Stop-BrohnQaOwnedProcess {
    param([Parameter(Mandatory=$true)][Diagnostics.Process]$Process,[Parameter(Mandatory=$true)][datetime]$StartedAt)
    if ($Process.HasExited) { return }
    if ($Process.StartTime.ToUniversalTime() -ne $StartedAt.ToUniversalTime()) { throw 'Owned process identity changed; refusing cleanup.' }
    $stopInfo = New-Object Diagnostics.ProcessStartInfo
    $stopInfo.FileName = Join-Path $env:SystemRoot 'System32/taskkill.exe'
    $stopInfo.Arguments = '/PID ' + $Process.Id + ' /T /F'
    $stopInfo.UseShellExecute = $false; $stopInfo.CreateNoWindow = $true
    $stopInfo.RedirectStandardOutput = $true; $stopInfo.RedirectStandardError = $true
    $stopper = New-Object Diagnostics.Process; $stopper.StartInfo = $stopInfo
    try {
        if (-not $stopper.Start()) { throw 'Owned process-tree cleanup did not start.' }
        $stdout = $stopper.StandardOutput.ReadToEndAsync(); $stderr = $stopper.StandardError.ReadToEndAsync()
        if (-not $stopper.WaitForExit(15000)) { $stopper.Kill(); throw 'Owned process-tree cleanup timed out.' }
        $null = $stdout.GetAwaiter().GetResult(); $detail = $stderr.GetAwaiter().GetResult()
        if (-not $Process.WaitForExit(15000)) { throw ('Owned process remains active: ' + $detail) }
    } finally { $stopper.Dispose() }
}
function Save-BrohnQaJson {
    param($Value,[string]$Path)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
}
