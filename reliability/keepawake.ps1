# 防锁守夜（2026-11-25）
# 目的：自动化窗口内（默认 01:50~09:05）阻止会话因空闲被锁：
#   1) SetThreadExecutionState 持续申请"系统+显示"不休眠
#   2) 每 45 秒把鼠标移动 1px 再移回（重置空闲计时，不影响任何操作）
# 用法: -Until "09:05" [-StartNow]  或 -Stop （删除 stop 文件）
# 停止：创建 D:\tools\bgi-scan\.keepawake.stop
param(
  [string]$Until = '09:05',
  [switch]$StartNow,
  [switch]$Stop,
  [switch]$NoLock
)

$ErrorActionPreference = 'Continue'
$log = (Join-Path $PSScriptRoot 'keepawake.log')
$stopFile = (Join-Path $PSScriptRoot '.keepawake.stop')
function W($m) { '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $m | Out-File -FilePath $log -Append -Encoding UTF8 }

# 单实例保护（2026-11-25）：已有守夜在跑就不再起第二个
if (-not $Stop) {
  $existing = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'keepawake\.ps1' -and $_.ProcessId -ne $PID })
  if ($existing.Count -gt 0) {
    W ('singleton: another keepawake running (pid=' + $existing[0].ProcessId + '), exit')
    exit 0
  }
}

if ($Stop) {
  New-Item -ItemType File -Path $stopFile -Force | Out-Null
  W 'stop requested'
  exit 0
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class KA {
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
'@ -ErrorAction SilentlyContinue

$ES_CONTINUOUS = 0x80000000
$ES_SYSTEM_REQUIRED = 0x00000001
$ES_DISPLAY_REQUIRED = 0x00000002
if ($AllowDisplayOff) {
  # 不申请 ES_DISPLAY_REQUIRED：允许关屏，但仍靠输入抖动阻止锁屏
  $flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
} else {
  $flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED
}

# 计算结束时间
$now = Get-Date
try {
  $p = [datetime]::ParseExact($Until, 'HH:mm', $null)
  $deadline = $now.Date.AddHours($p.Hour).AddMinutes($p.Minute)
  if ($deadline -le $now) { $deadline = $deadline.AddDays(1) }
} catch { $deadline = $now.AddHours(1) }

W ('start; until ' + $deadline.ToString('MM-dd HH:mm') + ' (now ' + $now.ToString('HH:mm:ss') + ')')
if (Test-Path $stopFile) { Remove-Item $stopFile -Force -ErrorAction SilentlyContinue }

$jiggle = 0
while ((Get-Date) -lt $deadline) {
  if (Test-Path $stopFile) { W 'stop file detected, exit'; Remove-Item $stopFile -Force -ErrorAction SilentlyContinue; break }
  [void][KA]::SetThreadExecutionState($flags)
  $pt = New-Object KA+POINT
  if ([KA]::GetCursorPos([ref]$pt)) {
    # 必须用 mouse_event（真实输入事件）才能重置空闲计时；SetCursorPos 不算输入（2026-11-25 实测）
    [KA]::mouse_event(0x0001, 1, 0, 0, [IntPtr]::Zero)     # MOUSEEVENTF_MOVE +1px
    Start-Sleep -Milliseconds 60
    [KA]::mouse_event(0x0001, -1, 0, 0, [IntPtr]::Zero)    # 移回
    $jiggle++
    if ($jiggle % 40 -eq 0) { W ('alive; jiggle=' + $jiggle) }
  }
  Start-Sleep -Seconds 45
}
[void][KA]::SetThreadExecutionState($ES_CONTINUOUS)

# 收工后主动锁屏（2026-11-25 采纳调研建议：自动化跑完把安全性补回来）
# 守卫：用户正在用（空闲 < 60 秒）或还有游戏/自动化在跑 → 不锁
if (-not $NoLock) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class LK {
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LII p);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool LockWorkStation();
  [StructLayout(LayoutKind.Sequential)] public struct LII { public uint cbSize; public uint dwTime; }
}
'@ -ErrorAction SilentlyContinue
  $li = New-Object LK+LII
  $li.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($li)
  [void][LK]::GetLastInputInfo([ref]$li)
  $idleSec = (([Environment]::TickCount - $li.dwTime) / 1000)
  $busy = @(Get-Process -Name 'ZenlessZoneZero','YuanShen','BetterGI','m7a','March7th Launcher' -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -ne 'March7th Launcher' })
  $stale = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'run-with-restore|run-daily-all|weekly-artifact-scan' })
  if ($idleSec -lt 60) {
    W ('skip lock: user active (idle ' + [int]$idleSec + 's)')
  } elseif ($busy.Count -gt 0 -or $stale.Count -gt 0) {
    W ('skip lock: automation still running (games=' + $busy.Count + ' runs=' + $stale.Count + ')')
  } else {
    [void][LK]::LockWorkStation()
    W 'workstation locked (post-automation security restore)'
  }
}

W 'end (released execution state)'
