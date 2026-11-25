# 自动化跑完后的全面体检（2026-11-25）
# 不只看"屏幕关没关"，还检查：窗口可见/最小化/被 DWM 隐藏、前台焦点、输入可用性、
# OCR 识别失败、进程残留、分辨率、判据与告警、日志时序。
# 用法: -Game genshin|zzz  [-SinceMinutes 45]
# 体检工具：检查自动化跑完后的会话/窗口/日志状态
# 用法: .\post-run-audit.ps1 -Game genshin -SinceMinutes 45 `
#         -BgiLogDir "D:\software\BetterGI\log" `
#         -ZzzRecordDir "D:\software\ZenlessZoneZero-OneDragon\config\01\app_run_record"
param(
  [ValidateSet('genshin','zzz')][string]$Game = 'genshin',
  [int]$SinceMinutes = 45,
  [string]$BgiLogDir = 'D:\software\BetterGI\log',
  [string]$ZzzRecordDir = 'D:\software\ZenlessZoneZero-OneDragon\config\01\app_run_record'
)

$ErrorActionPreference = 'Continue'
$bgi = $PSScriptRoot
$problems = New-Object System.Collections.ArrayList
function Add-Problem($m) { [void]$problems.Add($m) }
function Head($t) { Write-Output ''; Write-Output ('=== ' + $t + ' ===') }

Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -Name Dpi -Namespace Win32 -PassThru | Out-Null
[Win32.Dpi]::SetProcessDPIAware() | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class AUD {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@ -ErrorAction SilentlyContinue

function Get-Fg { 
  $h = [AUD]::GetForegroundWindow()
  if ($h -eq [IntPtr]::Zero) { return @{ Name='<none>'; Title='' } }
  $sb = New-Object System.Text.StringBuilder 256
  [void][AUD]::GetWindowText($h, $sb, 256)
  $procId = 0
  [void][AUD]::GetWindowThreadProcessId($h, [ref]$procId)
  $n = ''
  try { $n = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
  return @{ Name=$n; Title=$sb.ToString() }
}

Write-Output ('===== 自动化体检报告  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  game=' + $Game + ' =====')

Head '1. 进程'
foreach ($pn in @('YuanShen','BetterGI','ZenlessZoneZero','Zenless Zone Zero Cloud','March7th Launcher')) {
  $ps = @(Get-Process -Name $pn -ErrorAction SilentlyContinue)
  if ($ps.Count -gt 0) {
    foreach ($p in $ps) { Write-Output ('  ' + $pn + ' pid=' + $p.Id + ' MB=' + [math]::Round($p.WorkingSet64/1MB,0) + ' 启动=' + $p.StartTime.ToString('HH:mm:ss')) }
  }
}

Head '2. 游戏窗口状态（可见/最小化/DWM 隐藏/尺寸）'
$gname = if ($Game -eq 'genshin') { 'YuanShen' } else { 'ZenlessZoneZero' }
$procs = @(Get-Process -Name $gname -ErrorAction SilentlyContinue)
if ($procs.Count -eq 0) {
  Write-Output ('  ' + $gname + ' 进程不存在（已退出或未启动）')
} else {
  foreach ($p in $procs) {
    $h = $p.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) {
      Write-Output ('  pid=' + $p.Id + ' MainWindowHandle=0 → 窗口句柄拿不到（可能最小化到托盘/无窗口）')
      Add-Problem ('窗口句柄为 0：BGI 无法绑定，会一直"等待进入主界面"')
      continue
    }
    $vis = [AUD]::IsWindowVisible($h)
    $ico = [AUD]::IsIconic($h)
    $r = New-Object AUD+RECT
    [void][AUD]::GetWindowRect($h, [ref]$r)
    $cloak = 0
    try { [void][AUD]::DwmGetWindowAttribute($h, 14, [ref]$cloak, 4) } catch { }
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    Write-Output ('  pid=' + $p.Id + ' Visible=' + $vis + ' Minimized=' + $ico + ' DWM_hidden=' + ($cloak -eq 1) + ' 尺寸=' + $w + 'x' + $hh)
    if (-not $vis) { Add-Problem '窗口不可见（IsWindowVisible=False），BGI 会捕获不到画面' }
    if ($ico) { Add-Problem '窗口处于最小化，自动化会被暂停' }
    if ($cloak -eq 1) { Add-Problem '窗口被 DWM 隐藏（Cloaked），画面不可见' }
    if ($w -lt 1920 -or $hh -lt 1080) { Add-Problem ('窗口尺寸 ' + $w + 'x' + $hh + ' 小于 1920x1080') }
  }
}

Head '3. 前台窗口 / 输入可用性'
$fg = Get-Fg
Write-Output ('  前台: ' + $fg.Name + '  「' + $fg.Title + '」')
$pt = New-Object AUD+POINT
$g1 = [AUD]::GetCursorPos([ref]$pt)
$s1 = [AUD]::SetCursorPos($pt.X, $pt.Y)
Write-Output ('  GetCursorPos=' + $g1 + ' SetCursorPos=' + $s1)
# 判定说明（2026-11-25 修正）：SetCursorPos 在"管理员权限的游戏窗口在前台"时会因 UIPI 失败，
# 这不代表锁屏。真正可靠的锁屏信号是前台窗口句柄为 0。
if ($fg.Name -eq '<none>' -or $fg.Name -eq '') {
  Add-Problem '前台窗口为 0（锁屏/无活动桌面），SendInput 必失败'
} elseif (-not $s1) {
  Write-Output '  （SetCursorPos 失败但前台窗口正常：多为 UIPI 拦截，BGI 提权运行不受影响）'
}

Head '4. 显示模式 / 分辨率注册表'
$vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentHorizontalResolution -gt 0 }
foreach ($v in $vc) { Write-Output ('  ' + $v.Name + ' → ' + $v.CurrentHorizontalResolution + 'x' + $v.CurrentVerticalResolution + '@' + $v.CurrentRefreshRate) }
$reg = Get-ItemProperty 'HKCU:\Software\miHoYo\原神' -ErrorAction SilentlyContinue
if ($reg) {
  $rw = $reg.'Screenmanager Resolution Width_h182942802'
  $rh = $reg.'Screenmanager Resolution Height_h2627697771'
  Write-Output ('  原神注册表: ' + $rw + 'x' + $rh)
  if ($rw -ne 3840) { Add-Problem ('注册表分辨率=' + $rw + 'x' + $rh + '（期望 3840x2160 已还原）') }
}

Head '5. 运行锁 / 残留进程'
$lock = Join-Path $bgi '.game-run.lock'
Write-Output ('  锁文件: ' + (Test-Path $lock))
if (Test-Path $lock) { Write-Output ('    内容: ' + ((Get-Content $lock -Raw -Encoding UTF8) -replace '\s+',' ')); Add-Problem '运行锁未释放（可能是上次异常退出）' }
$stale = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'run-with-restore|run-daily-all' })
Write-Output ('  残留调度进程: ' + $stale.Count)
if ($stale.Count -gt 0) { Add-Problem ('仍有 run 进程在跑: ' + (($stale | ForEach-Object { $_.ProcessId }) -join ',')) }

Head '6. 判据 / 告警 / 状态行'
$rs = Join-Path $bgi 'run-status.log'
if (Test-Path $rs) { Write-Output ('  run-status.log 最后 3 行:'); Get-Content $rs -Encoding UTF8 -Tail 3 | ForEach-Object { '    ' + $_ } }
else { Write-Output '  run-status.log 不存在' }
$al = Join-Path $bgi 'ALERT.txt'
if (Test-Path $al) {
  $recent = @(Get-Content $al -Encoding UTF8 | Where-Object { $_ -match '2026-11-25' })
  if ($recent.Count -gt 0) { Add-Problem ('ALERT.txt 今日有 ' + $recent.Count + ' 条告警'); $recent | Select-Object -Last 3 | ForEach-Object { '    ' + $_ } }
  else { Write-Output '  ALERT.txt 无今日记录' }
} else { Write-Output '  ALERT.txt 不存在（今日无失败）' }

Head '7. BGI 日志体检（只统计本次运行时间窗）'
$blog = Join-Path $BgiLogDir (('better-genshin-impact' + (Get-Date -Format 'yyyyMMdd') + '.log'))
if (Test-Path $blog) {
  $allLines = Get-Content $blog -Encoding UTF8 -ErrorAction SilentlyContinue
  $cut = (Get-Date).AddMinutes(-1 * $SinceMinutes).ToString('HH:mm:ss')
  # 只保留时间窗内的行（日志是当天累积的，历史异常不该算进本次）
  $lines = @()
  $inWin = $false
  foreach ($ln in $allLines) {
    if ($ln -match '^\[(\d{2}:\d{2}:\d{2})') {
      if ($Matches[1] -ge $cut) { $inWin = $true }
    }
    if ($inWin) { $lines += $ln }
  }
  Write-Output ('  统计窗口: ' + $cut + ' 之后  行数: ' + $lines.Count + '  最后写入: ' + (Get-Item $blog).LastWriteTime.ToString('HH:mm:ss'))
  $patterns = @{
    '进入大世界/主界面' = '进入主界面|已进入大世界|游戏运行环境已绑定'
    '一条龙开始'       = '一条龙任务执行|任务启动'
    '一条龙收尾'       = '一条龙和配置组任务结束'
    '体力耗尽/轮次达标' = '体力耗尽|轮次已达标'
    '圣遗物分解'       = '完成\d星圣遗物快速分解'
    '秘境轮次'         = '第\d+轮|自动秘境'
    '识图失败'         = '未能识别|识别失败|未找到'
    'OCR选择失败'      = '未能通过文本OCR'
    '焦点丢失'         = '不是原神，暂停'
    '输入异常'         = '模拟键鼠消息发送失败'
    '等待主界面'       = '当前不在游戏主界面'
  }
  foreach ($k in $patterns.Keys) {
    $c = @($lines | Select-String $patterns[$k]).Count
    Write-Output ('  ' + $k.PadRight(18) + ' : ' + $c)
    if ($k -eq '输入异常' -and $c -gt 0) { Add-Problem ('BGI 报输入异常 ' + $c + ' 次（SendInput 被拒）') }
    if ($k -eq '焦点丢失' -and $c -gt 5) { Add-Problem ('焦点丢失 ' + $c + ' 次（重聚焦可能未生效或被频繁抢占）') }
    if ($k -eq '等待主界面' -and $c -gt 0) { Write-Output '    （有"等待主界面"记录，说明进游戏阶段曾停滞）' }
  }
  Write-Output '  最后 6 条正文:'
  $msgs = @(); for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -notmatch '^\[' -and $lines[$i].Trim()) { $msgs += $lines[$i].Trim() } }
  $msgs | Select-Object -Last 6 | ForEach-Object { '    ' + $_ }
} else { Write-Output '  日志不存在' }

Head '8. 绝区零记录（若适用）'
if ($Game -eq 'zzz') {
  $recDir = $ZzzRecordDir
  $recs = @(Get-ChildItem "$recDir\*.yml" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge (Get-Date).AddMinutes(-1 * $SinceMinutes) })
  Write-Output ('  最近 ' + $SinceMinutes + ' 分钟内的记录: ' + $recs.Count)
  foreach ($r in $recs) {
    $c = Get-Content $r.FullName -Raw -Encoding UTF8
    $stt = if ($c -match 'run_status:\s*(\d+)') { $Matches[1] } else { '?' }
    Write-Output ('    ' + $r.BaseName.PadRight(26) + ' status=' + $stt + ' (' + $r.LastWriteTime.ToString('HH:mm:ss') + ')')
    if ($stt -ne '1') { Add-Problem ('绝区零应用失败: ' + $r.BaseName + ' status=' + $stt) }
  }
}

Head '9. 结论'
if ($problems.Count -eq 0) {
  Write-Output '  ✅ PASS — 未发现异常'
} else {
  Write-Output ('  ❌ FAIL — 发现 ' + $problems.Count + ' 个问题:')
  $i = 0
  foreach ($p in $problems) { $i++; Write-Output ('   ' + $i + ') ' + $p) }
}
Write-Output ''
