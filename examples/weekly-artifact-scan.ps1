# 每周圣遗物扫描与整理（独立于 DSH 会话，由 Windows 计划任务调用）
# 2026-11-24 建立：替代原来绑定 DSH 会话的定时任务
#
# 流程：
#   1. 前置检查（锁屏 / MuMu）
#   2. 切 1080p → 启动原神 → 等窗口就绪
#   3. 关 BGI → 聚焦原神 → BetterGI --startGroups 扫描圣遗物（先切页签再扫）
#   4. 等日志出现「配置组 "扫描圣遗物" 执行结束」
#   5. 跑 Python 流水线：parse → evaluate → assign → make_final_lists → four_star_rolling
#   6. 关 BGI 与原神 → 切回 4K（必须，否则下次手动启动是小窗）
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File weekly-artifact-scan.ps1
param(
  [int]$MaxMinutes = 45,
  [switch]$SkipScan,        # 只跑后处理和还原（调试用）
  [switch]$NoRestore,       # 不切回 4K（调试用）
  [switch]$DryRun           # 只打印将执行的步骤
)

$ErrorActionPreference = 'Continue'
$bgi = 'D:\tools\bgi-scan'
$log = Join-Path $bgi 'weekly-scan.log'
$req = Join-Path $bgi 'request.json'
$bgiExe = 'D:\software\BetterGI\BetterGI.exe'
$bgiLog = 'D:\software\BetterGI\log\better-genshin-impact' + (Get-Date -Format 'yyyyMMdd') + '.log'
$py = 'D:\software\ZenlessZoneZero-OneDragon\.venv\Scripts\python.exe'
$artifacts = Join-Path $bgi 'artifacts'

function L($m) {
  $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $m
  Write-Output $line
  $line | Out-File -FilePath $log -Append -Encoding UTF8
}

function Dispatch([string]$action) {
  @{ action = $action } | ConvertTo-Json | Set-Content -LiteralPath $req -Encoding UTF8
  Start-ScheduledTask -TaskName 'BetterGIDispatch'
  Start-Sleep -Seconds 8
  L ("dispatcher -> " + $action)
}

function Invoke-Wake {
  # 轻微移动鼠标唤醒息屏/待机（让输入桌面恢复活动）
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WK2 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@ -ErrorAction SilentlyContinue
  $pt = New-Object WK2+POINT
  [void][WK2]::GetCursorPos([ref]$pt)
  [void][WK2]::SetCursorPos($pt.X + 2, $pt.Y)
  [WK2]::mouse_event(0x0001, 1, 0, 0, [IntPtr]::Zero)   # MOUSEEVENTF_MOVE
  [void][WK2]::SetCursorPos($pt.X, $pt.Y)
  Start-Sleep -Seconds 3
}

function Test-DesktopInteractive {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WK {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
'@ -ErrorAction SilentlyContinue
  $pt = New-Object WK+POINT
  [void][WK]::GetCursorPos([ref]$pt)
  # 锁屏判据用前台窗口句柄（SetCursorPos 会被 UIPI 干扰，2026-11-25 修正）
  $ok = ([WK]::GetForegroundWindow() -ne [IntPtr]::Zero)
  [void][WK]::SetCursorPos($pt.X, $pt.Y)
  return $ok
}

function Wait-GameWindow([int]$TimeoutSec) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WR {
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@ -ErrorAction SilentlyContinue
  $limit = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $limit) {
    $g = Get-Process -Name 'YuanShen' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($g) {
      $r = New-Object WR+RECT
      [void][WR]::GetClientRect($g.MainWindowHandle, [ref]$r)
      $w = $r.R - $r.L; $h = $r.B - $r.T
      if ($w -ge 1920 -and $h -ge 1080) { L ("游戏窗口就绪 " + $w + "x" + $h); return $true }
    }
    Start-Sleep -Seconds 10
  }
  return $false
}

L '================ 周扫描开始 ================'

if ($DryRun) {
  L '[DRY] 将执行：检查→1080p→启动游戏→关BGI→聚焦→扫描组→流水线→关闭→4K'
  exit 0
}


# 1) 前置检查（先唤醒息屏/待机，再判断是否真的锁屏）
Invoke-Wake
L '已尝试唤醒（晃动鼠标）'
if (-not (Test-DesktopInteractive)) { L '✗ 桌面锁屏（SetCursorPos 失败），中止'; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bgi 'display.ps1') -Game genshin -Mode 4k | Out-Null
  exit 2 }
L '✓ 桌面可交互'
if (Get-Process -Name 'MuMuNxDevice' -ErrorAction SilentlyContinue) { L '⚠ MuMu 设备进程存在，可能抢焦点' }

# 2) 1080p + 启动游戏
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bgi 'display.ps1') -Game genshin -Mode auto | Out-Null
L '已切 1080p'
if (-not (Get-Process -Name 'YuanShen' -ErrorAction SilentlyContinue)) {
  Dispatch 'start-game'
  L '已请求启动 BetterGI + 原神'
}
if (-not (Wait-GameWindow 240)) { L '✗ 游戏窗口未在 4 分钟内就绪，中止'; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bgi 'display.ps1') -Game genshin -Mode 4k | Out-Null
  exit 3 }

# 3) 关 BGI → 聚焦 → 跑扫描组
Dispatch 'close-bgi'
Dispatch 'genshin-focus'
L '启动配置组 扫描圣遗物'
Start-Process -FilePath $bgiExe -ArgumentList @('--startGroups', '扫描圣遗物') -WorkingDirectory 'D:\software\BetterGI'

# 4) 等扫描结束
$deadline = (Get-Date).AddMinutes($MaxMinutes)
$done = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 30
  if (Test-Path $bgiLog) {
    $tail = Get-Content $bgiLog -Encoding UTF8 -Tail 40 -ErrorAction SilentlyContinue
    if ($tail -match '配置组 "扫描圣遗物" 执行结束') { $done = $true; break }
  }
}
L ('扫描结束标记: ' + $done + '（上限 ' + $MaxMinutes + ' 分钟）')

# 5) Python 流水线
$steps = @(
  @{ n = 'parse';    a = @('parse_artifact_log.py', '--latest') },
  @{ n = 'evaluate'; a = @('evaluate.py') },
  @{ n = 'assign';   a = @('assign.py') },
  @{ n = 'final';    a = @('make_final_lists.py') },
  @{ n = 'fourstar'; a = @('four_star_rolling.py') }
)
foreach ($s in $steps) {
  $script = Join-Path $artifacts ($s.a[0])
  if (-not (Test-Path $script)) { L ('跳过（脚本不存在）: ' + $s.n); continue }
  L ('--- ' + $s.n + ' ---')
  $extra = @()
  if ($s.a.Count -gt 1) { $extra = $s.a[1..($s.a.Count - 1)] }
  $out = & $py $script @extra 2>&1
  $out | ForEach-Object { L ('  ' + $_) }
}

# 6) 收尾：关 BGI + 原神，切回 4K
Dispatch 'close-all'
if (-not $NoRestore) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bgi 'display.ps1') -Game genshin -Mode 4k | Out-Null
  L '已切回 4K'
}


L '================ 周扫描结束 ================'
exit 0
