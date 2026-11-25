param(
  [Parameter(Mandatory = $true)][ValidateSet('genshin', 'zzz', 'all')][string]$Game,
  [Parameter(Mandatory = $true)][ValidateSet('auto', '4k', 'show')][string]$Mode
)
$ErrorActionPreference = 'Continue'

$genshinAuto = [ordered]@{
  'Screenmanager Resolution Width_h182942802'    = 1920
  'Screenmanager Resolution Height_h2627697771'  = 1080
  'Screenmanager Is Fullscreen mode_h3981298716' = 0
}
$genshin4k = [ordered]@{
  'Screenmanager Resolution Width_h182942802'    = 3840
  'Screenmanager Resolution Height_h2627697771'  = 2160
  'Screenmanager Is Fullscreen mode_h3981298716' = 1
}
$zzzAuto = [ordered]@{
  'Screenmanager Resolution Width_h182942802'               = 1920
  'Screenmanager Resolution Height_h2627697771'             = 1080
  'Screenmanager Fullscreen mode_h3630240806'               = 0
  'Screenmanager Resolution Use Native_h1405027254'         = 0
  'Screenmanager Resolution Width Default_h680557497'       = 1920
  'Screenmanager Resolution Height Default_h1380706816'     = 1080
  'Screenmanager Fullscreen mode Default_h401710285'        = 0
  'Screenmanager Resolution Use Native Default_h1405981789' = 0
}
$zzz4k = [ordered]@{
  'Screenmanager Resolution Width_h182942802'               = 3840
  'Screenmanager Resolution Height_h2627697771'             = 2160
  'Screenmanager Fullscreen mode_h3630240806'               = 1
  'Screenmanager Resolution Use Native_h1405027254'         = 1
  'Screenmanager Resolution Width Default_h680557497'       = 3840
  'Screenmanager Resolution Height Default_h1380706816'     = 2160
  'Screenmanager Fullscreen mode Default_h401710285'        = 1
  'Screenmanager Resolution Use Native Default_h1405981789' = 1
}

function Write-Values([string]$key, $values) {
  foreach ($k in $values.Keys) {
    reg.exe add $key /v $k /t REG_DWORD /d $values[$k] /f 2>&1 | Out-Null
  }
}
function Show-Values([string]$key) {
  $out = reg.exe query $key 2>&1
  if ($LASTEXITCODE -ne 0) { Write-Output '  (注册表键不存在)'; return }
  $out | Select-String -Pattern 'Screenmanager (Resolution Width|Resolution Height|Is Fullscreen|Fullscreen mode|Resolution Use Native)_' |
    ForEach-Object { '  ' + ($_.Line -replace '\s+', ' ').Trim() }
}

$targets = @()
if ($Game -in @('genshin', 'all')) { $targets += , @('genshin', 'HKCU\Software\miHoYo\原神', 'YuanShen') }
if ($Game -in @('zzz', 'all')) { $targets += , @('zzz', 'HKCU\Software\miHoYo\绝区零', 'ZenlessZoneZero') }

foreach ($t in $targets) {
  $id, $key, $proc = $t
  $label = if ($Mode -eq 'show') { '当前值' } elseif ($Mode -eq 'auto') { '切 1080p 窗口化' } else { '切 4K 全屏' }
  Write-Output "=== $id : $label ==="
  if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
    Write-Output "  注意: $proc 正在运行，退出游戏后才会生效"
  }
  if ($Mode -ne 'show') {
    if ($id -eq 'genshin') { if ($Mode -eq 'auto') { Write-Values $key $genshinAuto } else { Write-Values $key $genshin4k } }
    else { if ($Mode -eq 'auto') { Write-Values $key $zzzAuto } else { Write-Values $key $zzz4k } }
  }
  Show-Values $key
}
