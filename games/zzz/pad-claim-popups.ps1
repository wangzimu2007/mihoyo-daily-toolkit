# 登录后弹窗处理：识别屏幕文字，看到「领取」就按手柄 A 领取，否则按 B 关闭
param([int]$MaxRounds = 8)
$ErrorActionPreference = 'Continue'
$log = (Join-Path $PSScriptRoot 'pad-claim.log')
function L($m) { ("$(Get-Date -Format 'HH:mm:ss') $m") | Out-File -FilePath $log -Append -Encoding UTF8 }
$py = 'D:\software\ZenlessZoneZero-OneDragon\.venv\Scripts\python.exe'

function Send-Pad([string]$btn) {
  $code = if ($btn -eq 'A') { 'XUSB_GAMEPAD_A' } else { 'XUSB_GAMEPAD_B' }
  $s = @"
import time
import vgamepad as vg
pad = vg.VX360Gamepad()
time.sleep(0.2)
pad.press_button(button=vg.XUSB_BUTTON.$code); pad.update(); time.sleep(0.12)
pad.release_button(button=vg.XUSB_BUTTON.$code); pad.update(); time.sleep(0.4)
"@
  [IO.File]::WriteAllText("$env:TEMP\pad_one.py", $s, (New-Object System.Text.UTF8Encoding($false)))
  & $py "$env:TEMP\pad_one.py" 2>&1 | Out-Null
}

L '--- pad-claim start ---'
for ($round = 1; $round -le $MaxRounds; $round++) {
  Start-Sleep -Seconds 2
  $texts = @()
  try {
    $a = Invoke-RestMethod -Uri 'http://127.0.0.1:23001/game/analyze' -TimeoutSec 25
    $texts = @($a.ocr_texts | ForEach-Object { [string]$_.text })
  } catch { L ('analyze 失败: ' + $_.Exception.Message) }
  $all = ($texts -join ' ')
  L ("round $round : " + ($all.Substring(0, [Math]::Min(120, $all.Length))))

  $hasClaim = $all -match '领取'
  $hasPopup = $all -match '今日到账|签到|签署|通知|确认|返回|活动|大世界'
  if ($hasClaim) {
    L '检测到「领取」→ 按 A'
    Send-Pad 'A'
    Start-Sleep -Seconds 2
    continue
  }
  if ($hasPopup) {
    # 有弹窗但不含领取 → 按 B 关
    L '检测到弹窗 → 按 B'
    Send-Pad 'B'
    Start-Sleep -Seconds 2
    continue
  }
  L '没有可处理的弹窗，结束'
  break
}
L '--- pad-claim done ---'
