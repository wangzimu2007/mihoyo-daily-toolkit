param(
  [int]$PopupPresses = 0
)
$ErrorActionPreference = 'Continue'
$log = (Join-Path $PSScriptRoot 'pad-enter.log')
function L($m) { ("$(Get-Date -Format 'HH:mm:ss') $m") | Out-File -FilePath $log -Append -Encoding UTF8 }
$py = 'D:\software\ZenlessZoneZero-OneDragon\.venv\Scripts\python.exe'

$script = @"
import time
import vgamepad as vg

pad = vg.VX360Gamepad()
time.sleep(0.4)

def tap(btn, wait=1.0):
    pad.press_button(button=btn); pad.update(); time.sleep(0.12)
    pad.release_button(button=btn); pad.update(); time.sleep(wait)

def move_rs(x, y, hold=0.15):
    pad.right_joystick_float(x_value_float=x, y_value_float=y); pad.update()
    time.sleep(hold)
    pad.right_joystick_float(x_value_float=0.0, y_value_float=0.0); pad.update()
    time.sleep(0.2)

# 1) 手柄 A 点「进入游戏」（合成鼠标点击会被反作弊过滤，虚拟手柄是真实 HID 设备）
tap(vg.XUSB_BUTTON.XUSB_GAMEPAD_A, wait=9.0)
print('A sent (enter)')

# 2) 弹窗交给 pad-claim-popups.ps1 处理（它按 OCR 决定 A 领取 / B 关闭）
for i in range($PopupPresses):
    tap(vg.XUSB_BUTTON.XUSB_GAMEPAD_B, wait=1.3)
print('B x$PopupPresses sent (popups)')

# 3) 晃一下右摇杆 + A，避免停在某个确认框
move_rs(0.3, 0.0)
time.sleep(0.5)
print('done')
"@
[IO.File]::WriteAllText("$env:TEMP\pad_enter_full.py", $script, (New-Object System.Text.UTF8Encoding($false)))

L '--- pad-enter start ---'
$out = & $py "$env:TEMP\pad_enter_full.py" 2>&1
L ($out -join ' | ')
Write-Output ($out -join ' ')

# 4) 鼠标轻微抖动，把游戏从手柄 UI 切回键鼠 UI（否则后续鼠标点击无效）
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PE_MOUSE {
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  public struct POINT { public int X, Y; }
}
'@ -ErrorAction SilentlyContinue
try {
  $pt = New-Object PE_MOUSE+POINT
  [void][PE_MOUSE]::GetCursorPos([ref]$pt)
  for ($i = 0; $i -lt 5; $i++) {
    [void][PE_MOUSE]::SetCursorPos($pt.X + 12, $pt.Y + 8)
    Start-Sleep -Milliseconds 120
    [void][PE_MOUSE]::SetCursorPos($pt.X, $pt.Y)
    Start-Sleep -Milliseconds 120
  }
  L 'mouse jiggled (switch to kb/mouse UI)'
} catch { L ('mouse jiggle failed: ' + $_.Exception.Message) }

Start-Sleep -Seconds 2
L '--- pad-enter done ---'
