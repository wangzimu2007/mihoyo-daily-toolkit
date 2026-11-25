# 监控 Windows 会话锁定状态，记录状态变化 + 当时的前台窗口，用于定位"谁在锁屏"
# 探针：SetCursorPos 失败 = 锁屏（安全桌面）
param([int]$UntilHour = 12, [int]$IntervalSec = 15)

$ErrorActionPreference = 'Continue'
$log = (Join-Path $PSScriptRoot 'lock-monitor.log')
function W($m) { '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $m | Out-File -FilePath $log -Append -Encoding UTF8 }

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class LM {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LII p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct LII { public uint cbSize; public uint dwTime; }
}
'@ -ErrorAction SilentlyContinue

function Test-Locked {
  # 判据修正（2026-11-25）：SetCursorPos 在提权窗口前台时会因 UIPI 失败，不能当锁屏信号。
  # 真正的锁屏：前台窗口句柄为 0（安全桌面）。
  return ([LM]::GetForegroundWindow() -eq [IntPtr]::Zero)
}

function Get-DisplayState {
  # 记录显示器连接数 + 主屏分辨率：用来区分"软件黑屏"和"显示器信号断开/待机"
  $mons = @()
  try { $mons = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop } catch { }
  $active = @($mons).Count
  $res = ''
  try {
    $vc = Get-CimInstance Win32_VideoController -ErrorAction Stop |
      Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
    if ($vc) { $res = ($vc.CurrentHorizontalResolution.ToString() + 'x' + $vc.CurrentVerticalResolution.ToString() + '@' + $vc.CurrentRefreshRate) }
  } catch { }
  return ('displays=' + $active + ' mode=' + $res)
}
function Get-ForegroundInfo {
  $h = [LM]::GetForegroundWindow()
  if ($h -eq [IntPtr]::Zero) { return 'foreground=<none>' }
  $sb = New-Object System.Text.StringBuilder 256
  [void][LM]::GetWindowText($h, $sb, 256)
  $procId = 0
  [void][LM]::GetWindowThreadProcessId($h, [ref]$procId)
  $name = '?'
  try { $name = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
  return ('foreground=' + $name + ' title="' + $sb.ToString() + '" ' + (Get-DisplayState))
}

function Get-IdleSec {
  $li = New-Object LM+LII
  $li.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($li)
  [void][LM]::GetLastInputInfo([ref]$li)
  return [int]((([Environment]::TickCount - $li.dwTime)) / 1000)
}

W ('=== monitor start (until hour ' + $UntilHour + ', interval ' + $IntervalSec + 's) ===')
$prev = Test-Locked
W (($(if ($prev) { 'LOCKED' } else { 'UNLOCKED' })) + '  idle=' + (Get-IdleSec) + 's  ' + (Get-ForegroundInfo))
$deadline = (Get-Date).Date.AddDays($(if ((Get-Date).Hour -ge $UntilHour) { 1 } else { 0 })).AddHours($UntilHour)
while ((Get-Date) -lt $deadline) {
  $locked = Test-Locked
  if ($locked -ne $prev) {
    $state = if ($locked) { 'LOCKED' } else { 'UNLOCKED' }
    W ($state + '  idle=' + (Get-IdleSec) + 's  ' + (Get-DisplayState) + '  ' + (Get-ForegroundInfo))
    $prev = $locked
  }
  Start-Sleep -Seconds $IntervalSec
}
W '=== monitor end ==='
