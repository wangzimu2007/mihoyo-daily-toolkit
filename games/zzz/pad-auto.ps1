# 登录流程自动化：反复 OCR 当前画面，按文字决定手柄操作
#  - 点击进入游戏 / 确认 → A
#  - 领取 / 收下 → A（领取奖励）
#  - 弹窗类（今日到账/签到/活动/返回）→ B（关闭）
#  - 连续多轮没有关键文字 → 认为已进大世界，结束
param([int]$MaxRounds = 120, [int]$IdleStop = 4)
$ErrorActionPreference = 'Continue'
$log = (Join-Path $PSScriptRoot 'pad-auto.log')
function L($m) { ("$(Get-Date -Format 'HH:mm:ss') $m") | Out-File -FilePath $log -Append -Encoding UTF8 }
$py = 'D:\software\ZenlessZoneZero-OneDragon\.venv\Scripts\python.exe'

# 通过常驻手柄服务按键（服务只创建一次设备，避免反复连接/断开）
$script:padSeq = 0
function Send-Pad([string]$btn, [int]$waitMs = 3000) {
  $script:padSeq++
  $cmd = @{ btn = $btn; hold = 0.12; wait = [math]::Round($waitMs / 1000.0, 2); seq = $script:padSeq } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot '..\zzz\pad-cmd.json'), $cmd, (New-Object System.Text.UTF8Encoding($false)))
  Start-Sleep -Milliseconds ([int]($waitMs + 500))
}
# 确保服务在跑
$svcCount = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'pad-service' }).Count
if ($svcCount -eq 0) {
  & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'pad-service-run.ps1') | Out-Null
  Start-Sleep -Seconds 3
}
function Jiggle-Mouse {
  Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class PA_M { [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y); public struct POINT { public int X, Y; } }' -ErrorAction SilentlyContinue
  try {
    $pt = New-Object PA_M+POINT
    [void][PA_M]::GetCursorPos([ref]$pt)
    [void][PA_M]::SetCursorPos($pt.X + 12, $pt.Y + 8); Start-Sleep -Milliseconds 120
    [void][PA_M]::SetCursorPos($pt.X, $pt.Y); Start-Sleep -Milliseconds 120
  } catch {}
}

L '=== pad-auto start ==='
$idle = 0
$entered = $false
for ($round = 1; $round -le $MaxRounds; $round++) {
  Start-Sleep -Milliseconds 800
  $texts = @()
  try {
    # 先刷新后端窗口句柄缓存（游戏重启后句柄会失效，导致 analyze 报"窗口未就绪"）
    try { Invoke-RestMethod -Uri 'http://127.0.0.1:23001/game/window' -TimeoutSec 8 | Out-Null } catch {}
    $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:23001/game/analyze' -TimeoutSec 25 -UseBasicParsing
    $json = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    $a = $json | ConvertFrom-Json
    $texts = @($a.ocr_texts | ForEach-Object { [string]$_.text })
  } catch { L ('analyze 失败: ' + $_.Exception.Message) }
  $all = ($texts -join ' ')
  $short = if ($all.Length -gt 100) { $all.Substring(0, 100) } else { $all }
  L ("r${round}: $short")

  if ($all -match '点击进入游戏|进入游戏|点击屏幕|开始游戏') {
    # 立刻确认前台再按 A，避免失焦导致按空
    Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public class PA_FG { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n); }' -ErrorAction SilentlyContinue
    $fg = [PA_FG]::GetForegroundWindow()
    $sb = New-Object System.Text.StringBuilder 128
    [void][PA_FG]::GetWindowText($fg, $sb, 128)
    if ($sb.ToString() -notmatch '绝区零') {
      L '→ 游戏不在前台，先聚焦'
      & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\zzz\zzz-focus.ps1') | Out-Null
      Start-Sleep -Milliseconds 600
    }
    L '→ 进入界面，立刻按 A'
    Send-Pad 'A' 5000
    $entered = $true
    $idle = 0
    continue
  }
  if ($all -match '决战于黎明之前|活动期间|DAY.*REWARD') {
    L '→ 签到活动面板：先 A 尝试领取，再 B 关闭'
    Send-Pad 'A' 2500
    Send-Pad 'B' 2500
    $idle = 0
    continue
  }
  if ($all -match '领取|收下|一键领取') {
    L '→ 有奖励可领，按 A 领取'
    Send-Pad 'A' 2500
    $idle = 0
    continue
  }
  if ($all -match '今日到账|签到|活动|返回|关闭|通知|公告') {
    L '→ 弹窗，按 B 关闭'
    Send-Pad 'B' 2500
    $idle = 0
    continue
  }
  if ([string]::IsNullOrWhiteSpace($all)) {
    L '→ 画面空白（加载中），继续等待'
    continue
  }
  if ($all -match 'New Eridu|CLEANUP|F1|F2|Enter|快速轮盘|相片|委托') {
    L '→ 识别到大世界特征，完成'
    break
  }
  $idle++
  L ("→ 无可识别关键词（连续 $idle 次）")
  if ($idle -ge $IdleStop -and $entered) { L '认为已进入大世界，结束'; break }
}

Jiggle-Mouse
L '=== pad-auto done ==='
