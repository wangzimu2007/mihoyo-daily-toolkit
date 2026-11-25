# 注册 Windows 计划任务（守夜 + 可选的每日自动化）
# 不需要管理员权限（除非显式要求提权）
param(
  [string]$ToolkitRoot = 'D:\tools\bgi-scan',
  [switch]$KeepAwake,
  [switch]$DailyAll,
  [switch]$WeeklyScan,
  [switch]$M7A,
  [switch]$All
)

$ErrorActionPreference = 'Stop'
$here = Split-Path $PSScriptRoot -Parent
$reliability = Join-Path $here 'reliability'

if ($All) { $KeepAwake = $true; $DailyAll = $true; $WeeklyScan = $true; $M7A = $true }
if (-not ($KeepAwake -or $DailyAll -or $WeeklyScan -or $M7A)) {
  Write-Host '什么都没指定。至少给一个开关：-KeepAwake / -DailyAll / -WeeklyScan / -M7A / -All' -ForegroundColor Yellow
  exit 1
}

$user = "$env:USERDOMAIN\$env:USERNAME"

function Register-UserTask {
  param(
    [string]$Name,
    [string]$ScriptPath,
    [string]$Arguments,
    $Trigger,
    [string]$Description
  )
  if (-not (Test-Path $ScriptPath)) { throw "脚本不存在：$ScriptPath" }
  $argLine = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
  if ($Arguments) { $argLine += ' ' + $Arguments }
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine
  $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName $Name -Action $action -Trigger $Trigger `
    -Principal $principal -Settings $settings -Description $Description -Force | Out-Null
  $i = Get-ScheduledTaskInfo -TaskName $Name
  Write-Host ("  OK  {0,-24} 下次 {1}" -f $Name, $i.NextRunTime) -ForegroundColor Green
}

Write-Host '=== 注册计划任务 ===' -ForegroundColor Cyan

if ($KeepAwake) {
  Register-UserTask -Name 'KeepAwake-AllDay' `
    -ScriptPath (Join-Path $reliability 'keepawake.ps1') `
    -Arguments '-Until 23:55 -AllowDisplayOff' `
    -Trigger (New-ScheduledTaskTrigger -Daily -At '00:05') `
    -Description '每 45 秒 mouse_event 抖动，防止会话因空闲锁屏'

  # 开机自启快捷方式（不需要管理员）
  $startup = [Environment]::GetFolderPath('Startup')
  $lnk = Join-Path $startup 'KeepAwake.lnk'
  $ws = New-Object -ComObject WScript.Shell
  $sc = $ws.CreateShortcut($lnk)
  $sc.TargetPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
  $sc.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $reliability 'keepawake.ps1') + '" -Until 23:55 -AllowDisplayOff'
  $sc.WorkingDirectory = $reliability
  $sc.Description = '会话保活（防止空闲锁屏导致自动化失败）'
  $sc.Save()
  Write-Host ("  OK  开机自启快捷方式 {0}" -f $lnk) -ForegroundColor Green
}

if ($DailyAll) {
  Register-UserTask -Name 'Daily-All-0500' `
    -ScriptPath (Join-Path $ToolkitRoot 'run-daily-all.ps1') `
    -Trigger (New-ScheduledTaskTrigger -Daily -At '04:10') `
    -Description '原神 → 绝区零 每日自动化'
}

if ($WeeklyScan) {
  Register-UserTask -Name 'Weekly-Artifact-Scan' `
    -ScriptPath (Join-Path $ToolkitRoot 'weekly-artifact-scan.ps1') `
    -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '02:00') `
    -Description '每周圣遗物扫描与整理'
}

if ($M7A) {
  Register-UserTask -Name 'ZZZ-Backend-Stop' `
    -ScriptPath (Join-Path $ToolkitRoot 'zzz-stop-flag.ps1') `
    -Trigger (New-ScheduledTaskTrigger -Daily -At '05:30') `
    -Description '停止绝区零后端释放内存'
  Register-UserTask -Name 'M7A-Relic-Daily-0430' `
    -ScriptPath (Join-Path $ToolkitRoot 'm7a-relic-daily.ps1') `
    -Trigger (New-ScheduledTaskTrigger -Daily -At '04:30') `
    -Description '让 M7A 当天必跑一次遗器清理'
  Register-UserTask -Name 'M7A-Power-Fallback-0830' `
    -ScriptPath (Join-Path $ToolkitRoot 'm7a-fallback.ps1') `
    -Trigger (New-ScheduledTaskTrigger -Daily -At '08:30') `
    -Description '崩铁体力兜底'
}

Write-Host ''
Write-Host '完成。可以手动跑一次守夜验证：' -ForegroundColor Cyan
Write-Host '  schtasks /Run /TN "KeepAwake-AllDay"'
