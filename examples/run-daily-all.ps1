# 每日总调度：原神 → 绝区零，严格串行（前一个进程真正退出才开始下一个）
# 崩铁不在这里跑：由 M7A 自己的定时任务负责（config.yaml scheduled_tasks，06:00 + 随机延迟）
# 2026-11-24 调整：原神提到最前（原神段上限 20→30 分钟，因为一条龙里加了 AutoCommissionNova 做委托）
param(
  [switch]$SkipZzz,
  [switch]$SkipGenshin,
  [switch]$SkipHsr      # 已废弃：崩铁已移出总调度，保留参数只为兼容旧调用
)
$ErrorActionPreference = 'Continue'
$bgi = 'D:\tools\bgi-scan'
$wrap = Join-Path $bgi 'run-with-restore.ps1'
$log = Join-Path $bgi 'daily-all.log'

function L($m) {
  $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m)
  Write-Output $line
  $line | Out-File -FilePath $log -Append -Encoding UTF8
}

function Run-Step([string]$name, [scriptblock]$action) {
  L ("---- 开始: $name ----")
  $t0 = Get-Date
  try { & $action } catch { L ("步骤异常: " + $_.Exception.Message) }
  $dur = [math]::Round(((Get-Date) - $t0).TotalSeconds, 0)
  L ("---- 结束: $name（耗时 ${dur}s）----")
  Start-Sleep -Seconds 5
}

L '=== 每日总调度开始 ==='

if (-not $SkipGenshin) {
  Run-Step '原神日常' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrap -Game genshin -MaxMinutes 30 2>&1
  }
}

if (-not $SkipZzz) {
  Run-Step '绝区零日常' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrap -Game zzz -MaxMinutes 35 2>&1
  }
}

L '=== 每日总调度结束（崩铁由 M7A 定时单独跑）==='
