# 离线自测：用仓库自带的样例日志跑通整条流水线
#
# 作用：不装游戏、不装 BetterGI，也能验证代码能跑、规则有输出。
# 用法：.\samples\offline-test.ps1 [-Python python]
param([string]$Python = 'python')

$ErrorActionPreference = 'Stop'
$repo  = Split-Path $PSScriptRoot -Parent
$art   = Join-Path $repo 'artifact'
$sample = Join-Path $PSScriptRoot 'artifact_log_sample.txt'

if (-not (Test-Path $sample)) { throw "缺少样例日志：$sample" }

# 造一个临时的 BGI_HOME 结构，把样例日志放进去
$tmp = Join-Path $env:TEMP ('gat-offline-' + (Get-Date -Format 'HHmmss'))
$rec = Join-Path $tmp 'User\JsScript\OCRArtifacts\records'
New-Item -ItemType Directory -Path $rec -Force | Out-Null
Copy-Item $sample (Join-Path $rec 'artifact_log_1795000000000.txt') -Force

$oldHome = $env:BGI_HOME
$env:BGI_HOME = $tmp
try {
  Write-Host ("临时 BGI_HOME: " + $tmp) -ForegroundColor DarkGray

  Push-Location $art
  & $Python 'parse_artifact_log.py' --latest
  if ($LASTEXITCODE -ne 0) { throw 'parse 失败' }
  & $Python 'evaluate.py'
  if ($LASTEXITCODE -ne 0) { throw 'evaluate 失败' }
  & $Python 'assign.py'
  if ($LASTEXITCODE -ne 0) { throw 'assign 失败' }
  & $Python 'make_final_lists.py'
  if ($LASTEXITCODE -ne 0) { throw 'make_final_lists 失败' }
  Pop-Location

  Write-Host ''
  Write-Host '✓ 离线自测通过，产物：' -ForegroundColor Green
  Write-Host ('  ' + (Join-Path $art 'output\report.md'))
  Write-Host ('  ' + (Join-Path $art 'final\SUMMARY.md'))
} finally {
  $env:BGI_HOME = $oldHome
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
