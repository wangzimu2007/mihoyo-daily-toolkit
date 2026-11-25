# 每天 04:30 预处理：让 M7A 当天的日常必定执行一次「清理四星及以下遗器」
# 原理：把 weekly_relic_cleanup_day_of_week 改成当天星期几，并把上周成功时间戳清零，
#       这样 07:00 的完整运行会认为"本周清理日已到且未清理"，先清遗器再清体力。
param([switch]$DryRun)
$ErrorActionPreference = 'Continue'
$cfg = 'E:\March7thAssistant_full\config.yaml'
$log = (Join-Path $PSScriptRoot 'm7a-relic-daily.log')
function L($m) { ("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m") | Out-File -FilePath $log -Append -Encoding UTF8 }

if (-not (Test-Path $cfg)) { L ('配置文件不存在: ' + $cfg); exit 1 }

# PowerShell 的 DayOfWeek：Sunday=0..Saturday=6；M7A：周一=1..周日=7
$dow = (Get-Date).DayOfWeek
$map = @{ 'Monday' = 1; 'Tuesday' = 2; 'Wednesday' = 3; 'Thursday' = 4; 'Friday' = 5; 'Saturday' = 6; 'Sunday' = 7 }
$target = $map[$dow.ToString()]
L ('今天 = ' + $dow + ' → 目标清理日=' + $target)

$t = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8)
$before = [regex]::Match($t, '(?m)^weekly_relic_cleanup_day_of_week:\s*(\d+)').Groups[1].Value
$t = $t -replace '(?m)^weekly_relic_cleanup_day_of_week:\s*\d+', ("weekly_relic_cleanup_day_of_week: " + $target)
$t = $t -replace '(?m)^weekly_relic_cleanup_timestamp:\s*\d+', 'weekly_relic_cleanup_timestamp: 0'

if ($DryRun) {
  L ("DryRun：原清理日=$before，将改为 $target，时间戳清零（未写入）")
  Write-Output ("DryRun ok: day $before -> $target")
  exit 0
}

[IO.File]::WriteAllText($cfg, $t, (New-Object System.Text.UTF8Encoding($false)))
$check = [regex]::Match([IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8), '(?m)^weekly_relic_cleanup_day_of_week:\s*(\d+)').Groups[1].Value
L ("已写入：清理日=$check（原 $before），时间戳=0")
Write-Output ("relic-cleanup-day set to $check")
