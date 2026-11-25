# 远程控制断开测试监控：每 5 秒记录锁屏/前台/显示器/远程连接状态
param([int]$Minutes = 8)
$ErrorActionPreference = 'Continue'
$log = (Join-Path $PSScriptRoot 'remote-test.log')
function W($m) { '[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $m | Out-File -FilePath $log -Append -Encoding UTF8 }

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class RT {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LII p);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [StructLayout(LayoutKind.Sequential)] public struct LII { public uint cbSize; public uint dwTime; }
}
'@ -ErrorAction SilentlyContinue

W ('=== test start (' + $Minutes + ' min) ===')
$deadline = (Get-Date).AddMinutes($Minutes)
$prevLock = $null
$prevDisplays = $null
$prevRd = $null
while ((Get-Date) -lt $deadline) {
  $h = [RT]::GetForegroundWindow()
  $locked = ($h -eq [IntPtr]::Zero)
  $li = New-Object RT+LII
  $li.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($li)
  [void][RT]::GetLastInputInfo([ref]$li)
  $idle = [int]((([Environment]::TickCount - $li.dwTime) / 1000))

  $fgName = ''
  if ($h -ne [IntPtr]::Zero) {
    $procId = 0
    [void][RT]::GetWindowThreadProcessId($h, [ref]$procId)
    try { $fgName = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
  }

  $displays = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue).Count
  $mode = ''
  try {
    $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
    if ($vc) { $mode = $vc.CurrentHorizontalResolution.ToString() + 'x' + $vc.CurrentVerticalResolution + '@' + $vc.CurrentRefreshRate }
  } catch { }

  $rd = @(Get-Process -Name 'RustDesk','ToDesk','ToDesk_Service' -ErrorAction SilentlyContinue).Count
  $rdConns = 0
  try {
    $rdPids = @(Get-Process -Name 'RustDesk','ToDesk' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    if ($rdPids.Count -gt 0) {
      $rdConns = @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $rdPids -contains $_.OwningProcess -and $_.State -eq 'Established' }).Count
    }
  } catch { }

  $changed = ($locked -ne $prevLock) -or ($displays -ne $prevDisplays) -or ($rdConns -ne $prevRd)
  if ($changed -or (($idle % 30) -lt 6)) {
    $flag = if ($locked) { 'LOCKED' } else { 'ok' }
    W ("{0}  idle={1}s  displays={2}  mode={3}  remoteConn={4}  fg='{5}'" -f $flag, $idle, $displays, $mode, $rdConns, $fgName)
  }
  $prevLock = $locked
  $prevDisplays = $displays
  $prevRd = $rdConns
  Start-Sleep -Seconds 5
}
W '=== test end ==='
