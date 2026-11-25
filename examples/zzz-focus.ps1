param([string]$ProcessName = 'ZenlessZoneZero')
$ErrorActionPreference = 'Continue'
$log = 'D:\tools\bgi-scan\zzz-focus.log'
"[$((Get-Date).ToString('HH:mm:ss'))] zzz-focus start" | Out-File -FilePath $log -Append -Encoding UTF8

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class ZF {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool alt);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(IntPtr idAttach, IntPtr idAttachTo, bool fAttach);
  [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentThreadId();
}
'@

$p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) {
  'zzz window not found' | Out-File -FilePath $log -Append -Encoding UTF8
  exit 1
}
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) {
  # 主窗口句柄可能为空，枚举找可见窗口
  'main handle zero, skip' | Out-File -FilePath $log -Append -Encoding UTF8
  exit 1
}
if ([ZF]::IsIconic($h)) { [void][ZF]::ShowWindow($h, 9) }
[void][ZF]::ShowWindow($h, 5)   # SW_SHOW

# 1) ALT 键解锁
[ZF]::keybd_event(0x12, 0, 1, [UIntPtr]::Zero)
[ZF]::keybd_event(0x12, 0, 3, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 100

# 2) AttachThreadInput 到前台线程，绕过前台锁
$fg = [ZF]::GetForegroundWindow()
$fgPid = 0
$fgThread = [ZF]::GetWindowThreadProcessId($fg, [ref]$fgPid)
$myThread = [ZF]::GetCurrentThreadId()
$attached = [ZF]::AttachThreadInput($myThread, $fgThread, $true)
[void][ZF]::BringWindowToTop($h)
[void][ZF]::SetForegroundWindow($h)
[ZF]::SwitchToThisWindow($h, $true)
if ($attached) { [void][ZF]::AttachThreadInput($myThread, $fgThread, $false) }
Start-Sleep -Milliseconds 400

$fg2 = [ZF]::GetForegroundWindow()
$sb = New-Object System.Text.StringBuilder 256
[void][ZF]::GetWindowText($fg2, $sb, 256)
$ok = ($fg2 -eq $h)
('hwnd=' + $h + ' foreground=' + $fg2 + ' ok=' + $ok + ' title=' + $sb.ToString()) | Out-File -FilePath $log -Append -Encoding UTF8
if ($ok) { exit 0 } else { exit 2 }
