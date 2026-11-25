# 启动/停止常驻虚拟手柄服务（只创建一次设备，避免反复连接/断开）
# 2026-11-24 修：启动前先把 pad-cmd.json 清成中性值，否则会读到上一次 -Stop 留下的 STOP 而立刻自杀；
#               -Stop 结束时顺手删掉命令文件，避免残留。
param([switch]$Stop)
$ErrorActionPreference = 'Continue'
$py = 'D:\software\ZenlessZoneZero-OneDragon\.venv\Scripts\python.exe'
$svc = (Join-Path $PSScriptRoot 'pad-service.py')
$log = (Join-Path $PSScriptRoot 'pad-service.log')
$cmd = (Join-Path $PSScriptRoot '..\zzz\pad-cmd.json')

if ($Stop) {
  @{ btn = 'STOP' } | ConvertTo-Json | Set-Content $cmd -Encoding UTF8
  Start-Sleep -Seconds 2
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'pad-service' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Remove-Item $cmd -Force -ErrorAction SilentlyContinue
  Write-Output 'pad-service stopped'
  exit 0
}

$running = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'pad-service' }).Count
if ($running -gt 0) { Write-Output ('pad-service already running (' + $running + ')'); exit 0 }

# 清掉上一次 -Stop 留下的 STOP，避免服务一启动就退出
@{ btn = 'NONE' } | ConvertTo-Json | Set-Content $cmd -Encoding UTF8

# 用 WMI 启动，父进程为 WmiPrvSE，不继承调用方的管道/控制台句柄
$cmdLine = '"' + $py + '" "' + $svc + '"'
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine; CurrentDirectory = 'D:\tools\bgi-scan' }
$padPid = [int]$r.ProcessId
$p = Get-Process -Id $padPid -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
Write-Output ('pad-service started pid=' + $p.Id + ' alive=' + (-not $p.HasExited))
if (Test-Path $log) { Get-Content $log -Tail 3 -Encoding UTF8 }
