param(
  [Parameter(Mandatory = $true)][ValidateSet('auto', 'restore', 'show')][string]$Mode
)
$ErrorActionPreference = 'Stop'
$reg = 'HKCU:\Software\miHoYo\绝区零'
# 你的手动玩设置：3840x2160 全屏
$profile = @{
  'Screenmanager Resolution Width_h182942802'          = 3840
  'Screenmanager Resolution Height_h2627697771'        = 2160
  'Screenmanager Fullscreen mode_h3630240806'          = 1
  'Screenmanager Resolution Use Native_h1405027254'    = 1
  'Screenmanager Resolution Width Default_h680557497'  = 3840
  'Screenmanager Resolution Height Default_h1380706816' = 2160
  'Screenmanager Fullscreen mode Default_h401710285'   = 1
  'Screenmanager Resolution Use Native Default_h1405981789' = 1
}
# 自动化用：1920x1080 窗口化
$auto = @{
  'Screenmanager Resolution Width_h182942802'          = 1920
  'Screenmanager Resolution Height_h2627697771'        = 1080
  'Screenmanager Fullscreen mode_h3630240806'          = 0
  'Screenmanager Resolution Use Native_h1405027254'    = 0
  'Screenmanager Resolution Width Default_h680557497'  = 1920
  'Screenmanager Resolution Height Default_h1380706816' = 1080
  'Screenmanager Fullscreen mode Default_h401710285'   = 0
  'Screenmanager Resolution Use Native Default_h1405981789' = 0
}

function Show-Current {
  foreach ($k in $auto.Keys) {
    $v = (Get-ItemProperty -Path $reg -Name $k -ErrorAction SilentlyContinue).$k
    Write-Output ("  $k = $v")
  }
}
function Apply-Set($set) {
  foreach ($k in $set.Keys) { Set-ItemProperty -Path $reg -Name $k -Value $set[$k] -Type DWord }
}

switch ($Mode) {
  'show' { Show-Current }
  'auto' {
    # 自动化前：关掉游戏（否则退出时会写回），再写 1080p 窗口化
    Get-Process -Name 'ZenlessZoneZero' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Apply-Set $auto
    Write-Output '已切到 1920x1080 窗口化（自动化模式）'
    Show-Current
  }
  'restore' {
    Get-Process -Name 'ZenlessZoneZero' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Apply-Set $profile
    Write-Output '已恢复 3840x2160 全屏（手动玩模式）'
    Show-Current
  }
}
