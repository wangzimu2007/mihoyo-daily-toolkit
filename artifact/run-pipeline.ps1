# 一键跑完整流水线（Windows）
# 用法:
#   .\run-pipeline.ps1                        # 用默认 BGI_HOME，解析最新日志
#   .\run-pipeline.ps1 -Latest                # 只解析最新一份日志（当前背包快照）
#   .\run-pipeline.ps1 -Python "C:\py\python.exe"
#   .\run-pipeline.ps1 -BgiHome "D:\software\BetterGI"
param(
  [string]$Python = 'python',
  [string]$BgiHome = '',
  [switch]$Latest,
  [switch]$SkipAssign
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

if ($BgiHome) { $env:BGI_HOME = $BgiHome }
if (-not $env:BGI_HOME) { Write-Host '提示：未设置 BGI_HOME，脚本内的默认值将生效' -ForegroundColor Yellow }

function Step([string]$name, [scriptblock]$body) {
  Write-Host ''
  Write-Host ('=== ' + $name + ' ===') -ForegroundColor Cyan
  $t0 = Get-Date
  & $body
  if ($LASTEXITCODE -ne 0) { throw ($name + ' 失败（退出码 ' + $LASTEXITCODE + '）') }
  Write-Host ('  耗时 ' + [math]::Round(((Get-Date) - $t0).TotalSeconds, 1) + 's') -ForegroundColor DarkGray
}

Step '解析扫描日志' {
  if ($Latest) { & $Python (Join-Path $here 'parse_artifact_log.py') --latest }
  else { & $Python (Join-Path $here 'parse_artifact_log.py') }
}

Step '规则评分'   { & $Python (Join-Path $here 'evaluate.py') }
Step '角色画像'   { & $Python (Join-Path $here 'build_characters.py') --force }
if (-not $SkipAssign) {
  Step '角色分配' { & $Python (Join-Path $here 'assign.py') }
}
Step '最终清单'   { & $Python (Join-Path $here 'make_final_lists.py') }
Step '四星滚动'   { & $Python (Join-Path $here 'four_star_rolling.py') }

Write-Host ''
Write-Host '完成。产物：' -ForegroundColor Green
Write-Host ('  ' + (Join-Path $here 'output\report.md'))
Write-Host ('  ' + (Join-Path $here 'final\SUMMARY.md'))
Write-Host ('  ' + (Join-Path $here 'final\lock_scheme.md'))
