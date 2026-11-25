# 屏保开关工具（自动化窗口保护）
# 用法: -Action off | on | status   [-Force]
#
# 设计（2026-11-25）：
#   * 夜间保护窗口 01:50 ~ 09:05：所有自动化（周扫描 02:00 / 原神 04:10 / M7A 04:30 /
#     绝区零 04:40 / 停后端 05:30 / 崩铁 06:00 / 兜底 08:30）都在这个窗口内
#   * 窗口内的 -Action on 默认不生效（记 "protected window, skip"），防止某个脚本
#     提前结束把屏保开回来，害下一个任务又被黑屏干扰；需要强制用 -Force
#   * 09:05 由计划任务 ScreenSaver-On-0905 强制恢复
param(
  [ValidateSet('off','on','status')][string]$Action = 'status',
  [switch]$Force
)

$ErrorActionPreference = 'Continue'
$key = 'HKCU:\Control Panel\Desktop'
$log = (Join-Path $PSScriptRoot 'screensaver.log')
$winStart = '01:50'
$winEnd   = '09:05'

function W($m) { '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $m | Out-File -FilePath $log -Append -Encoding UTF8 }

function In-Window {
  $now = Get-Date
  $s = [datetime]::ParseExact($winStart, 'HH:mm', $null)
  $e = [datetime]::ParseExact($winEnd, 'HH:mm', $null)
  $s = $now.Date.AddHours($s.Hour).AddMinutes($s.Minute)
  $e = $now.Date.AddHours($e.Hour).AddMinutes($e.Minute)
  return ($now -ge $s -and $now -lt $e)
}

function Get-State {
  $a = (Get-ItemProperty $key -Name ScreenSaveActive -ErrorAction SilentlyContinue).ScreenSaveActive
  $p = Get-Process -Name 'scrnsave' -ErrorAction SilentlyContinue
  return [pscustomobject]@{ Active = $a; Running = [bool]$p; Pid = $(if($p){$p.Id}else{0}) }
}

switch ($Action) {
  'status' {
    $s = Get-State
    'ScreenSaveActive = ' + $s.Active
    'scrnsave running = ' + $s.Running
    'night window = ' + $winStart + ' ~ ' + $winEnd + '  (now in window: ' + (In-Window) + ')'
  }
  'off' {
    $s = Get-State
    if ($s.Running) { Stop-Process -Id $s.Pid -Force -ErrorAction SilentlyContinue; W ('killed scrnsave pid=' + $s.Pid) }
    Set-ItemProperty -Path $key -Name ScreenSaveActive -Value '0' -ErrorAction SilentlyContinue
    W 'screensaver disabled (ScreenSaveActive=0)'
    'off'
  }
  'on' {
    if ((In-Window) -and (-not $Force)) {
      W ('skip restore: inside protected window ' + $winStart + '~' + $winEnd)
      'skip (protected window)'
      break
    }
    Set-ItemProperty -Path $key -Name ScreenSaveActive -Value '1' -ErrorAction SilentlyContinue
    W 'screensaver restored (ScreenSaveActive=1)'
    'on'
  }
}
