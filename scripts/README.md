# Windows 计划任务安装/卸载

把 `reliability/` 和（可选的）每日自动化注册成计划任务，**不需要管理员权限**
（除非你要注册提权调度器 `dispatcher.ps1`，那需要 `-RunLevel Highest` 和管理员）。

## 安装

```powershell
# 1) 只装守夜（最小可用）：每天 00:05 启动，跑到 23:55
.\scripts\install-tasks.ps1 -KeepAwake

# 2) 守夜 + 每日自动化（原神 04:10 → 绝区零 04:40）
.\scripts\install-tasks.ps1 -KeepAwake -DailyAll -ToolkitRoot "D:\tools\bgi-scan"

# 3) 再加每周圣遗物扫描（周一 02:00）
.\scripts\install-tasks.ps1 -KeepAwake -DailyAll -WeeklyScan -ToolkitRoot "D:\tools\bgi-scan"

# 4) 全部（含 M7A 两条与停后端）
.\scripts\install-tasks.ps1 -All -ToolkitRoot "D:\tools\bgi-scan"
```

`-ToolkitRoot` 是你的脚本目录（本仓库 `examples/` 里的脚本复制过去后所在的位置）。

## 卸载

```powershell
.\scripts\uninstall-tasks.ps1            # 删除本仓库注册的全部任务
.\scripts\uninstall-tasks.ps1 -WhatIfOnly # 只列出会删什么
```

## 注册的任务

| 任务名 | 触发 | 动作 |
|---|---|---|
| `KeepAwake-AllDay` | 每天 00:05 | `reliability\keepawake.ps1 -Until 23:55 -AllowDisplayOff` |
| `Daily-All-0500` | 每天 04:10 | `<ToolkitRoot>\run-daily-all.ps1` |
| `Weekly-Artifact-Scan` | 周一 02:00 | `<ToolkitRoot>\weekly-artifact-scan.ps1` |
| `ZZZ-Backend-Stop` | 每天 05:30 | `<ToolkitRoot>\zzz-stop-flag.ps1` |
| `M7A-Relic-Daily-0430` | 每天 04:30 | `<ToolkitRoot>\m7a-relic-daily.ps1` |
| `M7A-Power-Fallback-0830` | 每天 08:30 | `<ToolkitRoot>\m7a-fallback.ps1` |

另外会创建一个**开机自启快捷方式**（`%APPDATA%\...\Startup\`），让守夜在重启后立刻恢复。

## 验证

```powershell
Get-ScheduledTask | Where-Object { $_.TaskName -match 'KeepAwake|Daily-All|Weekly-Artifact|ZZZ-Backend|M7A-' } |
  ForEach-Object { $i = Get-ScheduledTaskInfo -TaskName $_.TaskName
                   '{0,-24} 下次 {1}' -f $_.TaskName, $i.NextRunTime }
```

手动触发一次守夜：

```powershell
schtasks /Run /TN "KeepAwake-AllDay"
```
