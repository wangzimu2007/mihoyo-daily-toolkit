param([string]$RequestPath = 'D:\tools\bgi-scan\request.json', [string]$LogPath = 'D:\tools\bgi-scan\dispatch.log')
$ErrorActionPreference = 'Continue'
function W($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -LiteralPath $LogPath -Append -Encoding UTF8 }
$bgiExe = 'E:\bettergi(genshen)\BetterGI.exe'
$zzzRoot = 'D:\software\ZenlessZoneZero-OneDragon'
$zzzExe = 'E:\绝区零\ZenlessZoneZero Game\ZenlessZoneZero.exe'

function Stop-Bgi {
  Get-Process -Name 'BetterGI' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 5
}
function Stop-Mask {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'blackmask' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Restore-Cursor {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class CUR {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
}
'@ -ErrorAction SilentlyContinue
  $w = [CUR]::GetSystemMetrics(0); $h = [CUR]::GetSystemMetrics(1)
  [void][CUR]::SetCursorPos([int]($w / 2), [int]($h / 2))
}
function Move-Win([string]$target) {
  & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File 'D:\tools\bgi-scan\drag-window.ps1' -Target $target | Out-Null
}

try {
  if (-not (Test-Path -LiteralPath $RequestPath)) { W 'no request file'; exit }
  $req = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $action = $req.action
  W ("request action=" + $action)

  switch ($action) {
    'start' {
      Start-Process -FilePath $bgiExe -ArgumentList 'start'
      W 'BetterGI started'
    }
    'start-game' {
      Start-Process -FilePath $bgiExe -ArgumentList 'start'
      W 'BetterGI + Genshin started'
    }
    'scan' {
      Start-Process -FilePath $bgiExe -ArgumentList '--startGroups', 'OCRArtifacts'
      W 'scan launched'
    }
    'group' {
      $g = $req.group
      if (-not $g) { W 'no group in request'; exit }
      Start-Process -FilePath $bgiExe -ArgumentList '--startGroups', $g
      W ('group launched: ' + $g)
    }
    'focus' {
      Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class FW {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
'@ -ErrorAction SilentlyContinue
      $p = Get-Process -Name 'YuanShen' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($p) { [void][FW]::ShowWindow($p.MainWindowHandle, 9); [void][FW]::SetForegroundWindow($p.MainWindowHandle); W 'genshin focused' }
      else { W 'genshin not running' }
    }
    'mask-on' {
      Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', 'D:\tools\bgi-scan\blackmask.ps1' -WindowStyle Hidden
      W 'black mask started'
    }
    'mask-off' { Stop-Mask; W 'black mask stopped' }
    'close-all' {
      Stop-Bgi
      Get-Process -Name 'YuanShen' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
      Stop-Mask
      W 'close-all done (BetterGI + Genshin + mask)'
    }
    'close-bgi' { Stop-Bgi; W 'BetterGI closed' }
    'zzz-stop' {
      $srv = 'D:\tools\dsh-game-daily\automation\zzz-server.ps1'
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $srv -Action stop -Root $zzzRoot -Port 23001 | Out-Null
      Start-Sleep -Seconds 2
      $c = Get-NetTCPConnection -LocalPort 23001 -State Listen -ErrorAction SilentlyContinue
      if ($c) { W ('zzz backend still listening pid=' + $c.OwningProcess) } else { W 'zzz backend stopped' }
    }
    'uac-off' {
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin' -Value 0 -Type DWord
      W 'UAC prompt disabled (ConsentPromptBehaviorAdmin=0)'
    }
    'zzz-gui' {
      $py = Join-Path $zzzRoot '.venv\Scripts\python.exe'
      $env:PYTHONPATH = (Join-Path $zzzRoot 'src')
      $outLog = Join-Path $zzzRoot '.debug\gui-out.log'
      $errLog = Join-Path $zzzRoot '.debug\gui-err.log'
      Start-Process -FilePath $py -ArgumentList @('-m', 'zzz_od.gui.app') -WorkingDirectory $zzzRoot -RedirectStandardOutput $outLog -RedirectStandardError $errLog
      W 'zzz gui started (elevated)'
    }
    'zzz-server' {
      $srv = 'D:\tools\dsh-game-daily\automation\zzz-server.ps1'
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $srv -Action start -Root $zzzRoot -Port 23001 -WaitSeconds 45 -StopFile 'D:\software\ZenlessZoneZero-OneDragon\.debug\zzz-stop.flag' | Out-Null
      W 'zzz backend start requested'
    }
    'zzz-game' {
      if (Get-Process -Name 'ZenlessZoneZero' -ErrorAction SilentlyContinue) { W 'zzz game already running' }
      else {
        $env:__COMPAT_LAYER = 'HIGHDPIAWARE'
        Start-Process -FilePath $zzzExe -ArgumentList '-screen-width', '1920', '-screen-height', '1080', '-screen-fullscreen', '0' -WorkingDirectory (Split-Path $zzzExe)
        W 'zzz game started (elevated, 1080p windowed)'
      }
    }
    'click-entry' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'D:\tools\bgi-scan\click-entry.ps1' | Out-Null; W 'entry clicked' }
    'gifa' { Start-Process -FilePath 'D:\tools\GIFA\GIFA.exe' -WorkingDirectory 'D:\tools\GIFA'; W 'GIFA started' }
    'consolelock-off' { powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 2>&1 | Out-Null; powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 2>&1 | Out-Null; powercfg /SETACTIVE SCHEME_CURRENT 2>&1 | Out-Null; W 'consolelock off done' }
    'genshin-focus' {
      & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File 'D:\tools\bgi-scan\zzz-focus.ps1' -ProcessName 'YuanShen' | Out-Null
      W 'genshin focus done'
    }
    'zzz-focus' {
      & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File 'D:\tools\bgi-scan\zzz-focus.ps1' | Out-Null
      W 'zzz focus done'
    }
    'move-secondary' { Move-Win 'secondary'; W 'game moved to secondary' }
    'move-primary' { Move-Win 'primary'; W 'game moved to primary' }
    'stop-all' {
      $c = Get-NetTCPConnection -LocalPort 23001 -State Listen -ErrorAction SilentlyContinue
      if ($c) { Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue }
      Get-Process -Name 'ZenlessZoneZero', 'Zenless Zone Zero Cloud', 'BetterGI', 'YuanShen' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
      Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'zzz_od|one_dragon' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
      Stop-Mask
      Restore-Cursor
      W 'STOP-ALL done (backend/game/mask) + cursor restored'
    }
    default { W ('unknown action: ' + $action) }
  }
}
catch { W ('ERROR ' + $_.Exception.Message) }
