# 卸载本仓库注册的计划任务与开机自启
param([switch]$WhatIfOnly)

$ErrorActionPreference = 'Continue'

$taskNames = @(
  'KeepAwake-AllDay',
  'Daily-All-0500',
  'Weekly-Artifact-Scan',
  'ZZZ-Backend-Stop',
  'M7A-Relic-Daily-0430',
  'M7A-Power-Fallback-0830'
)

Write-Host '=== 将删除以下计划任务 ===' -ForegroundColor Cyan
foreach ($n in $taskNames) {
  $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
  if ($t) {
    Write-Host ("  [有] " + $n)
    if (-not $WhatIfOnly) {
      Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue
      Write-Host ("       -> 已删除") -ForegroundColor DarkGray
    }
  } else {
    Write-Host ("  [无] " + $n) -ForegroundColor DarkGray
  }
}

$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'KeepAwake.lnk'
Write-Host ''
Write-Host '=== 开机自启 ===' -ForegroundColor Cyan
if (Test-Path $lnk) {
  Write-Host ('  [有] ' + $lnk)
  if (-not $WhatIfOnly) {
    Remove-Item $lnk -Force -ErrorAction SilentlyContinue
    Write-Host '       -> 已删除' -ForegroundColor DarkGray
  }
} else {
  Write-Host '  [无] KeepAwake.lnk' -ForegroundColor DarkGray
}

# 停止正在运行的守夜
$keep = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'keepawake\.ps1' })
Write-Host ''
Write-Host ('=== 运行中的守夜进程：' + $keep.Count + ' 个 ===') -ForegroundColor Cyan
if ($keep.Count -gt 0 -and -not $WhatIfOnly) {
  $keep | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Write-Host '  已结束' -ForegroundColor DarkGray
}

Write-Host ''
if ($WhatIfOnly) { Write-Host '（预览模式，未做任何修改）' -ForegroundColor Yellow }
else { Write-Host '卸载完成。' -ForegroundColor Green }
