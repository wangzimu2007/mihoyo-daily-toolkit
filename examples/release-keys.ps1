# 强制释放可能卡在"按下"状态的修饰键（Win/Ctrl/Alt/Shift）
# 用途：自动化中断或异常时，修饰键可能没松，之后任何按键都会变成组合键
#      （最典型：Win 卡住 + 按 E → 反复弹出资源管理器）
param([switch]$Quiet)
$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class KEYFIX {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
  public static string Stuck() {
    string s = "";
    int[] keys = { 0x5B, 0x5C, 0xA2, 0xA3, 0xA0, 0xA1, 0x10, 0x11, 0x12 };
    string[] names = { "LWin", "RWin", "LCtrl", "RCtrl", "LShift", "RShift", "Shift", "Ctrl", "Alt" };
    for (int i = 0; i < keys.Length; i++) {
      if ((GetAsyncKeyState(keys[i]) & 0x8000) != 0) s += names[i] + " ";
    }
    return s.Trim();
  }
  public static void ReleaseAll() {
    byte[] mods = { 0x5B, 0x5C, 0xA2, 0xA3, 0xA0, 0xA1, 0x10, 0x11, 0x12 };
    foreach (byte k in mods) {
      keybd_event(k, 0, 0x0002, UIntPtr.Zero);
      keybd_event(k, 0, 0x0003, UIntPtr.Zero);
    }
  }
}
'@ -ErrorAction SilentlyContinue

$before = [KEYFIX]::Stuck()
[KEYFIX]::ReleaseAll()
Start-Sleep -Milliseconds 300
$after = [KEYFIX]::Stuck()
if (-not $Quiet) {
  Write-Output ('释放前卡住的修饰键: [' + $before + ']')
  Write-Output ('释放后: [' + $after + ']')
  if ($before) { Write-Output '已强制松开' }
}
exit 0
