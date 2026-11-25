# 创建一个"停止标志"文件，由已提权的 watcher 检测后杀掉绝区零后端（无需管理员权限）
$ErrorActionPreference = 'Continue'
$zzzRoot = if ($env:ZZZ_OD_ROOT) { $env:ZZZ_OD_ROOT } else { 'D:\software\ZenlessZoneZero-OneDragon' }
$flag = (Join-Path $zzzRoot '.debug\zzz-stop.flag')
$log  = (Join-Path $PSScriptRoot 'zzz-stop.log')
function W($m) { ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) | Add-Content -Path $log -Encoding UTF8 }

$before = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
$game = Get-Process -Name 'ZenlessZoneZero','Zenless Zone Zero Cloud' -ErrorAction SilentlyContinue
if ($game) {
  W ('skip: zzz game still running (pid=' + ($game | Select-Object -First 1).Id + '), backend will stay up')
  exit 0
}
$listen = Get-NetTCPConnection -LocalPort 23001 -State Listen -ErrorAction SilentlyContinue
if (-not $listen) {
  W ("backend not listening, nothing to do; free=" + [math]::Round($before,1) + "GB")
  exit 0
}

New-Item -ItemType File -Path $flag -Force | Out-Null
W ("stop flag created; waiting for watcher to kill pid=" + $listen.OwningProcess)

$limit = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $limit) {
  if (-not (Get-NetTCPConnection -LocalPort 23001 -State Listen -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Seconds 2
}
$after = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
$stillUp = [bool](Get-NetTCPConnection -LocalPort 23001 -State Listen -ErrorAction SilentlyContinue)
if ($stillUp) {
  W "FAILED: backend still listening after 60s (watcher missing? flag will stay for next start)"
} else {
  W ("OK: backend stopped; free " + [math]::Round($before,1) + " -> " + [math]::Round($after,1) + "GB")
  Remove-Item $flag -Force -ErrorAction SilentlyContinue
}
