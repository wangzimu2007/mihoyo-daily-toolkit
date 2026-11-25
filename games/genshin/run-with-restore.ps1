param(
  [Parameter(Mandatory = $true)][ValidateSet('genshin', 'zzz')][string]$Game,
  [int]$MaxMinutes = 40,
  [switch]$SkipRun,
  [string]$ConfigName = '每日委托',
  [string]$Chain = '',   # 跑完后自动接力的下一个游戏（genshin/zzz）
  [string]$Overlay = ''  # 可选：黑遮罩 exe 路径（用于熄屏防烧屏）
)
$ErrorActionPreference = 'Continue'
$bgi = $PSScriptRoot
$zzzDir = (Join-Path $PSScriptRoot '..\zzz')
$display = Join-Path $bgi 'display.ps1'
$overlay = $Overlay
# request.json 必须与 dispatcher.ps1 同目录（examples/），否则调度器读不到
$req = Join-Path $bgi '..\..\examples\request.json'

# ===== 按自己环境修改（也可用环境变量 BGI_HOME / ZZZ_OD_ROOT 覆盖）=====
$BgiRoot = if ($env:BGI_HOME) { $env:BGI_HOME } else { 'D:\software\BetterGI' }
$ZzzRoot = if ($env:ZZZ_OD_ROOT) { $env:ZZZ_OD_ROOT } else { 'D:\software\ZenlessZoneZero-OneDragon' }
# ======================================================================
$gameYml = Join-Path $ZzzRoot 'config\01\game.yml'
$recDir = Join-Path $ZzzRoot 'config\01\app_run_record'
$bgiExe = Join-Path $BgiRoot 'BetterGI.exe'
$bgiLogDir = Join-Path $BgiRoot 'log'

# 屏保保护（2026-11-25）：跑自动化期间关闭屏保；窗口内不会被提前恢复
# [已移除] 屏保调用：ScreenSaveActive 已永久为 0，此调用为空转

# 输入可用性自检（2026-11-25）：锁屏/黑屏时 SendInput 必被拒，直接失败，不要白跑 30+ 分钟
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class INCHK {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
'@ -ErrorAction SilentlyContinue
$ipChk = New-Object INCHK+POINT
[void][INCHK]::GetCursorPos([ref]$ipChk)
# 注意：SetCursorPos 在提权窗口前台时会因 UIPI 失败，不能作为锁屏判据；改用前台窗口句柄
$fgProbe = [INCHK]::GetForegroundWindow()
if ($fgProbe -eq [IntPtr]::Zero) {
  Write-Output ('[' + (Get-Date -Format 'HH:mm:ss') + '] ✗ 输入不可用（锁屏/黑屏），中止本次运行')
  '✗ 输入不可用（锁屏/黑屏），中止' | Out-File -FilePath (Join-Path $PSScriptRoot 'ALERT.txt') -Append -Encoding UTF8
  exit 3
}
Write-Output ('[' + (Get-Date -Format 'HH:mm:ss') + '] ✓ 输入自检通过')

function Log($m) { Write-Output ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

# ---- 成功判据（2026-11-25）----
# 背景：任务只要脚本没崩就返回 0，2026-11-25 凌晨两段全废却报"成功"，属于监控盲区。
$script:runVerdict = 'unknown'
$script:verdictDetail = ''
function Set-Verdict([string]$v, [string]$detail) {
  $script:runVerdict = $v
  $script:verdictDetail = $detail
  Log ('判据: ' + $v + ' — ' + $detail)
}
function Write-Alert([string]$msg) {
  $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $Game + ' ' + $msg
  $line | Out-File -FilePath (Join-Path $PSScriptRoot 'ALERT.txt') -Append -Encoding UTF8
  Log ('已写告警: ' + $line)
}

# 前台进程名探测（用于"丢焦点就重新拉回来"，2026-11-25）
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class FGP {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
'@ -ErrorAction SilentlyContinue
function Get-ForegroundProcessName {
  try {
    $h = [FGP]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero) { return '' }
    $procId = 0
    [void][FGP]::GetWindowThreadProcessId($h, [ref]$procId)
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($p) { return $p.ProcessName } else { return '' }
  } catch { return '' }
}

function Dispatch($action, $extra = @{}) {
  $body = @{ action = $action }
  foreach ($k in $extra.Keys) { $body[$k] = $extra[$k] }
  $body | ConvertTo-Json | Set-Content -LiteralPath $req -Encoding UTF8
  # 调度任务可能卡在 Running（僵尸实例），先复位再派发，否则请求会被吞掉
  try {
    $st = (Get-ScheduledTask -TaskName 'BetterGIDispatch' -ErrorAction Stop).State
    if ($st -ne 'Ready') {
      Log ('调度任务状态为 ' + $st + '，先复位')
      Stop-ScheduledTask -TaskName 'BetterGIDispatch' -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
    }
  } catch {}
  Start-ScheduledTask -TaskName 'BetterGIDispatch'
  Start-Sleep -Seconds 2
}
function Backend-Up {
  try { Invoke-RestMethod -Uri 'http://127.0.0.1:23001/health' -TimeoutSec 3 | Out-Null; return $true } catch { return $false }
}
function Set-BgMode([bool]$enabled) {
  $t = [IO.File]::ReadAllText($gameYml, [Text.Encoding]::UTF8)
  $val = if ($enabled) { 'true' } else { 'false' }
  $t = $t -replace '(?m)^background_mode:\s*\S+', "background_mode: $val"
  [IO.File]::WriteAllText($gameYml, $t, (New-Object System.Text.UTF8Encoding($false)))
}
function Restart-Backend {
  $c = Get-NetTCPConnection -LocalPort 23001 -State Listen -ErrorAction SilentlyContinue
  if ($c) { Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 4 }
  Dispatch 'zzz-server'
  for ($i = 0; $i -lt 25; $i++) { Start-Sleep -Seconds 3; if (Backend-Up) { return $true } }
  return $false
}

try {
  Log "=== $Game 任务开始（跑完自动恢复 4K）==="
  # 运行锁：两个游戏串行，后到的等前一个真正结束；同一游戏重复触发则直接退出
  $lockFile = (Join-Path $PSScriptRoot '.game-run.lock')
  $waited = 0
  while (Test-Path $lockFile) {
    $info = $null
    try { $info = Get-Content $lockFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    $alive = $false
    if ($info -and $info.pid) { $alive = $null -ne (Get-Process -Id $info.pid -ErrorAction SilentlyContinue) }
    if (-not $alive) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue; break }
    if ($info.game -eq $Game) { Log ('已有同游戏任务在跑（pid=' + $info.pid + '），本次退出避免重复'); exit 0 }
    Log ('另一个游戏任务在跑（' + $info.game + '，pid=' + $info.pid + '），等待其结束…已等 ' + $waited + ' 秒')
    Start-Sleep -Seconds 30
    $waited += 30
    if ($waited -gt 3600) { throw 'WAIT-OTHER-GAME-TIMEOUT' }
  }
  @{ pid = $PID; game = $Game; at = (Get-Date).ToString('s') } | ConvertTo-Json | Set-Content -LiteralPath $lockFile -Encoding UTF8
  Log ('已获得运行锁（' + $Game + '）')
  # 遮罩：跑前关掉（截图/输入更稳），跑完恢复
  # 主屏遮罩有两种：blackmask.ps1（powershell 脚本）和 BlackOverlay.exe（桌面工具）
  $maskPs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'blackmask' })
  $maskExe = @(Get-Process -Name 'BlackOverlay' -ErrorAction SilentlyContinue)
  $script:maskWasOn = ($maskPs.Count + $maskExe.Count) -gt 0
  $script:maskHadExe = $maskExe.Count -gt 0
  if ($script:maskWasOn) {
    Log ('检测到主屏遮罩（脚本 ' + $maskPs.Count + ' 个 / BlackOverlay ' + $maskExe.Count + ' 个），先关闭')
    $maskPs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $maskExe | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
  }
  # 锁屏预检：用 OpenInputDesktop 判断（可靠）；不再用 SetCursorPos，它在 UIPI 下会误判
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class LKCHK2 {
  [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr OpenInputDesktop(uint dwFlags, bool fInherit, uint dwDesiredAccess);
  [DllImport("user32.dll", SetLastError = true)] public static extern bool CloseDesktop(IntPtr hDesktop);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@ -ErrorAction SilentlyContinue
  $isLocked = $false
  try {
    $hDesk = [LKCHK2]::OpenInputDesktop(0, $false, 0x0001)
    if ($hDesk -eq [IntPtr]::Zero) { $isLocked = $true } else { [void][LKCHK2]::CloseDesktop($hDesk) }
  } catch { $isLocked = $false }
  $fg = 0
  try { $fg = [LKCHK2]::GetForegroundWindow() } catch {}
  if ($isLocked) {
    Log '检测到屏幕处于锁屏状态（OpenInputDesktop 失败），无法发送键鼠输入 → 本次跳过'
    Log ('foreground=' + $fg)
    throw 'LOCKED-SCREEN'
  }
  if ($fg -eq 0) { Log '警告：前台窗口句柄为 0，可能刚切换桌面，继续执行' }
  Log '切 1080p 窗口化'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $display -Game $Game -Mode auto | Out-Null

  if ($Game -eq 'zzz') {
    Log '阶段1：前台模式进游戏（会短暂占用键鼠）'
    # 关键：必须先自己用 1080p 参数启动游戏，否则游戏会用账号云端的 4K 设置启动，
    # 一条龙按 1080p 模板识别会全部"未知画面"。
    Get-Process -Name 'ZenlessZoneZero' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    # 并行准备：先把虚拟手柄挂好、把后端起好，游戏加载期间就绪 → 窗口一出来 5 秒内能进
    try {
      Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'pad-service-run.ps1')) -WindowStyle Hidden -Wait
      Log '虚拟手柄已预启动'
    } catch { Log ('预启动手柄失败: ' + $_.Exception.Message) }
    Set-BgMode $false
    if (-not (Restart-Backend)) { Log '后端预启动失败（进入后再重试）' } else { Log '后端已就绪（前台模式）' }
    Log '用 1080p 窗口化参数启动游戏'
    Dispatch 'zzz-game'
    # 启动请求可能被并发占用吞掉：40 秒没窗口就再发一次（每次 dispatch 之间有间隔）
    $retryDispatch = 0
    $waited = 0
    while ($waited -lt 150) {
      Start-Sleep -Seconds 5
      $waited += 5
      $gp = Get-Process -Name 'ZenlessZoneZero' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne '' -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
      if ($gp) { Log ('游戏窗口已出现（等待 ' + $waited + ' 秒, PID=' + $gp.Id + '）'); break }
      if ($waited % 30 -eq 0) { Log ('等待游戏窗口... ' + $waited + 's') }
      if ($waited -ge 40 -and $retryDispatch -lt 2) {
        $retryDispatch++
        Log ('游戏窗口未出现，重新发送启动请求（第 ' + $retryDispatch + ' 次）')
        Dispatch 'zzz-game'
      }
    }
    if (-not $gp) { throw '游戏窗口未出现（启动失败）' }
    # 后端若在游戏加载期间还没起来，这里补一次（通常已经就绪）
    if (-not (Backend-Up)) {
      Log '后端仍未就绪，补启动一次'
      if (-not (Restart-Backend)) { throw '后端启动失败' }
    }
    # 只等 2 秒让窗口稳定，然后立刻聚焦 + 按 A（不再等 8 秒）
    Start-Sleep -Seconds 2
    Log '强制聚焦游戏窗口（关键：不聚焦则键鼠输入进不去）'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\zzz\zzz-focus.ps1') | Out-Null
    Start-Sleep -Milliseconds 500
    # 手柄自动循环：OCR 看画面 → 进入游戏按 A / 看到领取按 A 领 / 弹窗按 B 关
    Log '手柄自动进游戏 + 领取弹窗'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$zzzDir\pad-auto.ps1"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p2 = [System.Diagnostics.Process]::Start($psi)
    $p2.WaitForExit(300000) | Out-Null
    Log '手柄流程结束'
    # 校验是否真的到大世界了；没有就再跑一次手柄流程
    $inWorld = $false
    for ($try2 = 1; $try2 -le 2; $try2++) {
      try {
        $resp2 = Invoke-WebRequest -Uri 'http://127.0.0.1:23001/game/analyze' -TimeoutSec 25 -UseBasicParsing
        $j2 = [System.Text.Encoding]::UTF8.GetString($resp2.RawContentStream.ToArray())
        $t2 = (($j2 | ConvertFrom-Json).ocr_texts | ForEach-Object { [string]$_.text }) -join ' '
      } catch { $t2 = '' }
      if ($t2 -match 'New Eridu|CLEANUP|F1|快速轮盘|委托|相片') { $inWorld = $true; break }
      if ($try2 -lt 2) { Log ('未确认进入大世界，再跑一次手柄流程（第 ' + $try2 + ' 次）'); $p3 = [System.Diagnostics.Process]::Start($psi); $p3.WaitForExit(300000) | Out-Null }
    }
    if ($inWorld) { Log '已确认在大世界' } else { Log '未能确认大世界，继续交给 /game/enter' }
    if ($inWorld) {
      Log '手柄已确认进入大世界，跳过 /game/enter'
    } else {
      $r = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:23001/game/enter' -ContentType 'application/json' -Body '{}' -TimeoutSec 240
      Log ('进入结果: ' + ($r | ConvertTo-Json -Compress))
      $st = Invoke-RestMethod -Uri 'http://127.0.0.1:23001/game/status' -TimeoutSec 10
      if ($st.state -ne 'success') { throw ('进入游戏未成功，state=' + $st.state) }
      Log '已进入大世界'
    }

    if ($SkipRun) { throw 'SKIPRUN-END' }

    Log '阶段2：切前台模式跑应用（会占用键鼠；后台点击实测空转，2026-11-23 改）'
    Set-BgMode $false
    if (-not (Restart-Backend)) { throw '后端重启失败（后台模式）' }
    $run = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:23001/game/run/one-dragon' -ContentType 'application/json' -Body '{}' -TimeoutSec 30
    Log ('已发起: ' + ($run | ConvertTo-Json -Compress))
    $deadline = (Get-Date).AddMinutes($MaxMinutes)
    $focusTick = 0
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 30
      # 每 60 秒检查一次焦点，丢了就拉回（2026-11-25）
      $focusTick++
      if ($focusTick % 2 -eq 0) {
        $fgn = Get-ForegroundProcessName
        if ($fgn -and $fgn -ne 'ZenlessZoneZero') {
          Log ('焦点被 ' + $fgn + ' 抢走，重新聚焦绝区零')
          Dispatch 'zzz-focus'
        }
      }
      try { $st = Invoke-RestMethod -Uri 'http://127.0.0.1:23001/game/status' -TimeoutSec 8 } catch { continue }
      Log ('进度: ' + $st.state + ' / ' + $st.current_node)
      if ($st.state -ne 'running') { break }
    }
    $st = Invoke-RestMethod -Uri 'http://127.0.0.1:23001/game/status' -TimeoutSec 10
    Log ('一条龙结果: ' + $st.state + ' / ' + $st.last_status)

    # 成功判据：本次运行写出的所有 run_status 都必须是 1（成功）
    
    $since = (Get-Date).AddMinutes(-1 * ($MaxMinutes + 5))
    $recs = @()
    if (Test-Path $recDir) {
      $recs = @(Get-ChildItem "$recDir\*.yml" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $since })
    }
    $bad = @()
    foreach ($rec in $recs) {
      $rc = Get-Content $rec.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
      if ($rc -match 'run_status:\s*(\d+)' -and $Matches[1] -ne '1') { $bad += ($rec.BaseName + '(' + $Matches[1] + ')') }
    }
    if ($recs.Count -gt 0 -and $bad.Count -eq 0) {
      Set-Verdict 'OK' ('绝区零 ' + $recs.Count + ' 项记录全部成功')
    } else {
      $why = '记录=' + $recs.Count + ' 失败=' + $bad.Count + $(if ($bad.Count -gt 0) { ' [' + ($bad -join ',') + ']' } else { '' })
      Set-Verdict 'FAIL' $why
      Write-Alert ('绝区零段失败：' + $why)
    }

    Log '关闭游戏'
    try { Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:23001/game/close' -TimeoutSec 30 | Out-Null } catch {}
  }
  else {
    # 原神分支的 SkipRun（2026-11-25 修：原来只在绝区零分支生效，导致 -SkipRun 也会真跑）
    if ($SkipRun) { Log 'SkipRun：跳过原神实际运行（仅验证前置流程）'; throw 'SKIPRUN-END' }
    # 先清掉可能残留的 BetterGI 实例（它是提权运行的，必须走提权调度器）
    $bgiProc = @(Get-Process -Name 'BetterGI' -ErrorAction SilentlyContinue)
    if ($bgiProc.Count -gt 0) {
      Log ('发现 BetterGI 在跑（' + $bgiProc.Count + ' 个），先关闭')
      Dispatch 'close-bgi'
      Start-Sleep -Seconds 6
    }
    Log '用 BetterGI 官方 startOneDragon 触发一条龙（它会自己启动游戏并点「点击进入」）'
    $logStartStamp = (Get-Date).ToString('HH:mm:ss')   # 判据扫日志用：只统计本次运行之后的行
    
    $cfgName = $ConfigName
    try {
      Start-Process -FilePath $bgiExe -ArgumentList @('startOneDragon', $cfgName) -WorkingDirectory $BgiRoot
    } catch {
      Log ('启动 BetterGI 失败: ' + $_.Exception.Message)
      throw
    }
    # 确保原神窗口在前台（2026-11-25 新增：昨夜游戏窗口没到前台，BGI 的 SendInput 打到 DSH 窗口上直接抛异常）
    for ($k = 0; $k -lt 4; $k++) {
      $g = Get-Process -Name 'YuanShen' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
      if ($g) {
        Dispatch 'genshin-focus'
        Log ('已请求把原神拉到前台（第 ' + ($k + 1) + ' 次）')
        Start-Sleep -Seconds 8
      } else {
        Start-Sleep -Seconds 10
      }
    }
    # 等它把游戏拉起来并真正开始跑
    Start-Sleep -Seconds 40
    $started = $false
    for ($i = 0; $i -lt 30; $i++) {
      $logFile = Get-ChildItem $bgiLogDir -Filter ('better-genshin-impact' + (Get-Date -Format 'yyyyMMdd') + '.log') -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($logFile) {
        $tail = Get-Content $logFile.FullName -Tail 40 -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($tail -match '一条龙任务执行|任务启动') { $started = $true; break }
      }
      Start-Sleep -Seconds 10
    }
    if ($started) { Log 'BetterGI 一条龙已开始执行' } else { Log '未能确认一条龙开始（继续等待）' }
    # 等“一条龙和配置组任务结束”标记（BGI 跑完不会自动退出，死等进程会白等）
    $deadline2 = (Get-Date).AddMinutes($MaxMinutes)
    $done = $false
    $focusTick2 = 0
    while ((Get-Date) -lt $deadline2) {
      Start-Sleep -Seconds 15
      # 每 60 秒检查焦点，丢了就拉回（2026-11-25：实测 Edge / 命令行都会抢前台，BGI 会一直暂停）
      $focusTick2++
      if ($focusTick2 % 4 -eq 0) {
        $fgn2 = Get-ForegroundProcessName
        if ($fgn2 -and $fgn2 -ne 'YuanShen') {
          Log ('焦点被 ' + $fgn2 + ' 抢走，重新聚焦原神')
          Dispatch 'genshin-focus'
        }
      }
      $logFile2 = Get-ChildItem $bgiLogDir -Filter ('better-genshin-impact' + (Get-Date -Format 'yyyyMMdd') + '.log') -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($logFile2) {
        $tail2 = Get-Content $logFile2.FullName -Tail 30 -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($tail2 -match '一条龙和配置组任务结束') { $done = $true; break }
      }
      if (@(Get-Process -Name 'BetterGI' -ErrorAction SilentlyContinue).Count -eq 0) { $done = $true; break }
    }
    if ($done) { Log 'BetterGI 一条龙已收尾' } else { Log '等待超时，强制收尾' }

    # 成功判据（2026-11-25 修正）：扫整个运行窗口，不看最后 N 行
    # 教训：委托阶段会写上千行，最后 400 行里早看不到"体力耗尽"了（09-16 误判 FAIL）
    $tailAll = ''
    if ($logFile2) {
      $allL = Get-Content $logFile2.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
      $keep = @(); $on = $false
      foreach ($ln in $allL) {
        if ($ln -match '^\[(\d{2}:\d{2}:\d{2})') { if ($Matches[1] -ge $logStartStamp) { $on = $true } }
        if ($on) { $keep += $ln }
      }
      $tailAll = ($keep -join "`n")
    }
    $resinUsed  = ($tailAll -match '体力耗尽') -or ($tailAll -match '轮次已达标') -or ($tailAll -match '完成\d星圣遗物快速分解')
    # 领奖成功的实际措辞（2026-11-25 实测）："检查每日奖励结果：\"今日奖励已领取\""
    $rewardDone = ($tailAll -match '今日奖励已领取') -or ($tailAll -match '每日奖励已领取') -or ($tailAll -match '检查每日奖励：已领取') -or ($tailAll -match '每日委托奖励已完成')
    $inputErr   = ($tailAll -match '模拟键鼠消息发送失败')
    $focusLost  = ([regex]::Matches($tailAll, '不是原神，暂停')).Count
    # 委托汇总可能是 "共执行 3/4" 也可能 "共执行 1/1"（当日已完成部分后只补剩余）
    $commM = [regex]::Match($tailAll, '共执行 (\d+)/(\d+) 个委托')
    $commDone = if ($commM.Success) { $commM.Groups[1].Value + '/' + $commM.Groups[2].Value } else { '?' }
    $cmpFail = ([regex]::Matches($tailAll, '共 \d+ 次尝试后仍未完成')).Count

    if ($done -and $resinUsed -and $rewardDone -and -not $inputErr) {
      Set-Verdict 'OK' ('收尾+体力+领奖 均完成（委托 ' + $commDone + '，焦点丢失 ' + $focusLost + '）')
    } else {
      $why = '收尾=' + $done + ' 体力=' + $resinUsed + ' 领奖=' + $rewardDone + ' 委托=' + $commDone + ' 委托失败=' + $cmpFail + ' 焦点丢失=' + $focusLost + ' 输入异常=' + $inputErr
      Set-Verdict 'FAIL' $why
      Write-Alert ('原神段失败：' + $why)
    }

    # 关掉 BGI 与原神（2026-11-25：跑完不关会留 1080p 前台窗口，干扰后续任务与次日启动）
    Dispatch 'close-all'
    Log '已关闭 BetterGI 与原神（原神段跑完关游戏）'
    Start-Sleep -Seconds 5
    Log 'BetterGI 已结束'
  }
}
catch {
  if ($_.Exception.Message -notin @('SKIPRUN-END', 'LOCKED-SCREEN')) { Log ('出错: ' + $_.Exception.Message) }
}
finally {
  Start-Sleep -Seconds 3
  # 输出本次判据结论（便于查询与告警）
  Log ('=== 本次结果判据: ' + $script:runVerdict + ' — ' + $script:verdictDetail + ' ===')
  try {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm') + "  " + $Game.PadRight(8) + "  " + $script:runVerdict.PadRight(8) + "  " + $script:verdictDetail
    $line | Out-File -FilePath (Join-Path $PSScriptRoot 'run-status.log') -Append -Encoding UTF8
  } catch { }
  # 收尾先强制松开可能卡住的修饰键，避免之后按键变成 Win+E 之类
  try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\..\examples\release-keys.ps1') -Quiet | Out-Null } catch {}
  # 释放运行锁（只释放自己的）
  try {
    $lf = (Join-Path $PSScriptRoot '.game-run.lock')
    if (Test-Path $lf) {
      $li = $null
      try { $li = Get-Content $lf -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
      if (-not $li -or $li.pid -eq $PID) { Remove-Item $lf -Force -ErrorAction SilentlyContinue; Log '已释放运行锁' }
    }
  } catch { Log ('释放运行锁失败: ' + $_.Exception.Message) }
  # 断开虚拟手柄：绝区零用不到后必须摘掉，否则和真实手柄冲突
  try {
    $padSvc = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'pad-service' })
    if ($padSvc.Count -gt 0) {
      Log '断开虚拟手柄（停止手柄服务）'
      @{ btn = 'STOP' } | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot '..\zzz\pad-cmd.json') -Encoding UTF8
      Start-Sleep -Seconds 1
      $padSvc | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
      Start-Sleep -Seconds 2
      Log ('虚拟手柄已断开，剩余服务进程: ' + @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'pad-service' }).Count)
    }
  } catch { Log ('断开虚拟手柄失败: ' + $_.Exception.Message) }
  if ($script:maskWasOn) {
    if ($script:maskHadExe) {
      Log '恢复主屏遮罩（BlackOverlay）'
      if ($overlay -and (Test-Path $overlay)) { try { Start-Process -FilePath $overlay } catch { Log ('恢复 BlackOverlay 失败: ' + $_.Exception.Message) } }
    } else {
      Log '恢复主屏遮罩（blackmask）'
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = 'powershell.exe'
      $psi.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$bgi\..\..\examples\blackmask.ps1"'
      $psi.UseShellExecute = $false
      $psi.CreateNoWindow = $true
      try { [void][System.Diagnostics.Process]::Start($psi) } catch {}
    }
  }
  Log '恢复 4K 全屏'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $display -Game $Game -Mode 4k | Out-Null
  Log "=== $Game 任务结束 ==="
  # 接力：跑完立刻接着跑下一个游戏，不再等固定时间
  if ($Chain -and $Chain -ne $Game) {
    Log ('接力启动: ' + $Chain)
    try {
      $nx = New-Object System.Diagnostics.ProcessStartInfo
      $nx.FileName = 'powershell.exe'
      $nx.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Game ' + $Chain + ' -MaxMinutes 60'
      $nx.UseShellExecute = $false
      $nx.CreateNoWindow = $true
      [void][System.Diagnostics.Process]::Start($nx)
      Log ('已启动 ' + $Chain + ' 任务')
    } catch { Log ('接力启动失败: ' + $_.Exception.Message) }
  }
}
# end of run-with-restore: 恢复屏保（夜间窗口内会被跳过，由 09:05 任务兜底）
# [已移除] 屏保调用：ScreenSaveActive 已永久为 0，此调用为空转
