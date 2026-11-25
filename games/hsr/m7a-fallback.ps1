# 崩铁「体力没花出去」保底：清体力被遗器背包卡住时，临时改打拟造花萼（不产遗器）把体力花掉，
# 再跑一次 daily 拿满 500 活跃度档位奖励，最后恢复原配置。
param(
  [switch]$Force,     # 忽略检测，强制执行兜底
  [switch]$DryRun     # 只检测并打印决策，不真正执行
)
$ErrorActionPreference = 'Continue'
$root = 'E:\March7thAssistant_full'
$cfg = Join-Path $root 'config.yaml'
$log = (Join-Path $PSScriptRoot 'm7a-fallback.log')
function L($m) { ("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m") | Out-File -FilePath $log -Append -Encoding UTF8 }
function Say($m) { Write-Output $m; L $m }

if (-not (Test-Path $cfg)) { Say ('配置不存在: ' + $cfg); exit 1 }
Set-Location $root

# 1) 读最近一次运行状态
$statusJson = & .\m7a.exe --status 2>&1 | Out-String
$st = $null
try { $st = $statusJson | ConvertFrom-Json } catch { Say '无法解析 --status 输出'; }
$last = $null
if ($st -and $st.recent_runs) { $last = $st.recent_runs | Select-Object -First 1 }
Say ('最近一次运行: ' + $(if ($last) { $last.run_id + ' task=' + $last.task + ' status=' + $last.status + ' error=' + $last.error } else { '无记录' }))

if ($st -and $st.active_run) { Say ('已有任务在运行（' + $st.active_run.run_id + '），本次跳过'); exit 0 }

# 2) 判断是否需要兜底：失败原因含遗器/清体力，或强制
$need = $false
if ($Force) { $need = $true; Say 'Force：强制执行兜底' }
elseif ($last -and $last.status -ne 'success') {
  $err = [string]$last.error
  $reason = [string]$last.reason
  # 再从当次日志里找关键行
  $runLog = $last.log_file
  $hit = ''
  if ($runLog -and (Test-Path $runLog)) {
    $lines = Get-Content $runLog -Encoding UTF8 -ErrorAction SilentlyContinue
    $hit = ($lines | Select-String -Pattern '遗器背包已满|清体力失败|日常准备未完成' | Select-Object -First 3 | ForEach-Object { $_.Line.Trim() }) -join ' | '
  }
  Say ('失败原因: ' + $err + ' ' + $reason + ' 日志命中: ' + $hit)
  if (($err + $reason + $hit) -match '遗器|清体力|日常准备') { $need = $true }
}
else { Say '最近一次运行成功，本次不需要兜底' }

# 2b) 活跃度不足 500 时（即便上次运行成功）也要补：清体力 → 补领活跃度
if (-not $need) {
  $todayLog = Join-Path $root ('logs\' + (Get-Date -Format 'yyyy-MM-dd') + '.log')
  $activity = -1
  if (Test-Path $todayLog) {
    $hitAct = Get-Content $todayLog -Encoding UTF8 -ErrorAction SilentlyContinue |
      Select-String -Pattern '每日实训活跃度\s*(\d+)/500' | Select-Object -Last 1
    if ($hitAct) { $activity = [int]$hitAct.Matches[0].Groups[1].Value }
  }
  Say ('今日最后一次活跃度记录: ' + $(if ($activity -ge 0) { "$activity/500" } else { '未找到' }))
  if ($activity -ge 0 -and $activity -lt 500) {
    Say ('活跃度未满（' + $activity + '/500），开始补：清体力 → daily')
    if ($DryRun) { Say 'DryRun：不执行'; exit 0 }
    & .\m7a.exe power --after-finish None --json 2>&1 | Out-Null
    Say ('power 退出码: ' + $LASTEXITCODE)
    Start-Sleep -Seconds 30
    & .\m7a.exe daily --after-finish None --json 2>&1 | Out-Null
    Say ('daily 退出码: ' + $LASTEXITCODE)
    exit 0
  }
}

if (-not $need) { Say '== 无需兜底，结束 =='; exit 0 }
if ($DryRun) { Say 'DryRun：需要兜底，但不执行'; exit 0 }

# 3) 备份配置并临时改：关闭培养目标（改打拟造花萼）
$bak = $cfg + '.fallback-' + (Get-Date -Format 'HHmmss')
Copy-Item $cfg $bak -Force
$t = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8)
$orig = [regex]::Match($t, '(?m)^build_target_enable:\s*(\S+)').Groups[1].Value
$t2 = $t -replace '(?m)^build_target_enable:\s*\S+', 'build_target_enable: false'
[IO.File]::WriteAllText($cfg, $t2, (New-Object System.Text.UTF8Encoding($false)))
Say ('已临时关闭培养目标（原 build_target_enable=' + $orig + '），改打拟造花萼')

try {
  # 4) 清体力（花萼不产遗器，不会被背包卡）
  Say '开始清体力（拟造花萼）…'
  & .\m7a.exe power --after-finish None --json 2>&1 | Out-Null
  Say ('清体力退出码: ' + $LASTEXITCODE)
  Start-Sleep -Seconds 30

  # 5) 补领活跃度奖励
  Say '开始 daily（补领 500 活跃度奖励）…'
  & .\m7a.exe daily --after-finish None --json 2>&1 | Out-Null
  Say ('daily 退出码: ' + $LASTEXITCODE)
}
finally {
  # 6) 恢复配置
  Copy-Item $bak $cfg -Force
  Remove-Item $bak -Force -ErrorAction SilentlyContinue
  Say '已恢复原配置'
}
Say '== 保底流程结束 =='
