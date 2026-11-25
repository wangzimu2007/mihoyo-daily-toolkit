# 实时探测：输入是否可用（区分"物理关屏"与"软件黑屏"对自动化的影响）
# 用法: -Seconds 180 -Interval 3
param([int]$Seconds = 180, [int]$Interval = 3)

$ErrorActionPreference = 'Continue'
$log = (Join-Path $PSScriptRoot 'input-probe.log')
function W($m) { '[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $m | Tee-Object -FilePath $log -Append }

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class IP {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
'@ -ErrorAction SilentlyContinue

W ('=== probe start (' + $Seconds + 's, every ' + $Interval + 's) ===')
$deadline = (Get-Date).AddSeconds($Seconds)
$prev = $null
while ((Get-Date) -lt $deadline) {
  $pt = New-Object IP+POINT
  $g = [IP]::GetCursorPos([ref]$pt)
  $s = [IP]::SetCursorPos($pt.X, $pt.Y)
  # 真实发一次鼠标移动，然后看光标有没有动（验证 SendInput 通道）
  $moved = $false
  if ($g) {
    $before = $pt.X
    [IP]::mouse_event(0x0001, 2, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    $pt2 = New-Object IP+POINT
    if ([IP]::GetCursorPos([ref]$pt2)) { $moved = ($pt2.X -ne $before) }
    [IP]::mouse_event(0x0001, -2, 0, 0, [IntPtr]::Zero)
  }
  $h = [IP]::GetForegroundWindow()
  $sb = New-Object System.Text.StringBuilder 128
  if ($h -ne [IntPtr]::Zero) { [void][IP]::GetWindowText($h, $sb, 128) }
  $fg = if ($h -eq [IntPtr]::Zero) { '<none>' } else { $sb.ToString() }
  $mode = ''
  try {
    $vc = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
    if ($vc) { $mode = $vc.CurrentHorizontalResolution.ToString() + 'x' + $vc.CurrentVerticalResolution + '@' + $vc.CurrentRefreshRate }
  } catch { }
  $state = if ($s -and $moved) { 'OK' } elseif ($s) { 'PARTIAL(移动无效)' } else { 'BLOCKED' }
  if ($state -ne $prev) {
    W ("{0}  Get={1} Set={2} Move={3}  fg='{4}'  mode={5}" -f $state, $g, $s, $moved, $fg, $mode)
    $prev = $state
  }
  Start-Sleep -Seconds $Interval
}
W '=== probe end ==='
