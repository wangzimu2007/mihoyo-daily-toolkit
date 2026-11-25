# 编排示例（需按自己环境修改）

这里的脚本是**本机实际在用的版本**，包含大量硬编码路径和本机约定。
发布出来是为了展示"完整链路怎么串"，**不能直接复制运行**。

## ⚠️ 使用前必须确认

| 项 | 本机值 | 你要改的地方 |
|---|---|---|
| BetterGI 安装目录 | `D:\software\BetterGI` | `run-with-restore.ps1` 里的 `$bgiExe`、`display.ps1` 的注册表键 |
| 绝区零后端 | `D:\software\ZenlessZoneZero-OneDragon`，端口 23001 | `dispatcher.ps1` 里的 `$zzzRoot` |
| March7thAssistant | `E:\March7thAssistant_full` | `m7a-*.ps1` 里的 `$root` |
| 提权调度任务 | 计划任务 `BetterGIDispatch` | 自行用 `setup` 的方式创建 |
| 工具目录 | `D:\tools\bgi-scan` | 所有脚本里的 `$bgi` |

## 文件说明

| 文件 | 作用 |
|---|---|
| `run-daily-all.ps1` | 每日总调度：原神 → 绝区零（串行，各自有超时上限） |
| `run-with-restore.ps1` | 单游戏包装器：切 1080p → 启动 → 跑 → 关游戏 → 还原 4K → 判据 |
| `display.ps1` | 切原神/绝区零的分辨率（改注册表，重启游戏生效） |
| `dispatcher.ps1` | **提权调度器**：由计划任务以管理员运行，读 `request.json` 执行动作（启动游戏/关 BGI/聚焦/停后端…） |
| `weekly-artifact-scan.ps1` | 每周圣遗物扫描全链路（扫描组 → 解析 → 评分 → 分配 → 清单） |
| `zzz-focus.ps1` | 强制把游戏窗口拉到前台（ALT 解锁 + AttachThreadInput） |
| `zzz-stop-flag.ps1` | 通过停止文件让已提权的 watcher 杀掉绝区零后端 |
| `m7a-relic-daily.ps1` | 改 M7A 配置使当天必跑一次遗器清理（只改文件，不碰游戏） |
| `m7a-fallback.ps1` | 崩铁体力兜底（清体力被背包卡住时改打拟造花萼） |
| `pad-service-run.ps1` / `release-keys.ps1` | 虚拟手柄服务启停 / 强制松开修饰键 |

## 为什么需要 dispatcher

游戏和自动化工具通常是**管理员权限**运行的，普通权限脚本无法：

- 结束提权进程（`Access denied`）
- 向提权窗口发输入（UIPI）
- 启动需要 UAC 的程序

做法：建一个**以最高权限运行的计划任务**（`BetterGIDispatch`），
普通脚本只写 `request.json` 然后 `Start-ScheduledTask`，由它代劳。

```powershell
@{ action = 'close-all' } | ConvertTo-Json | Set-Content 'request.json' -Encoding UTF8
Start-ScheduledTask -TaskName 'BetterGIDispatch'
```

创建方式（需管理员）：

```powershell
$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -File "<你的路径>\dispatcher.ps1"'
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'BetterGIDispatch' -Action $a -Principal $p
```

## 完整链路（本机）

```
04:10  Daily-All-0500
         └─ run-daily-all.ps1
              ├─ run-with-restore.ps1 -Game genshin -MaxMinutes 30
              │    ├─ 输入自检 → 1080p → 启动 → 关 BGI → 聚焦（4 次）
              │    ├─ BetterGI startOneDragon 每日委托
              │    ├─ 轮询日志到「一条龙和配置组任务结束」+ 每 60 秒守焦点
              │    ├─ 判据：收尾 + 体力耗尽 + 领奖 + 无输入异常
              │    └─ close-all → 还原 4K
              └─ run-with-restore.ps1 -Game zzz -MaxMinutes 35
                   ├─ 后端启动 → 手柄进游戏 → 前台模式跑应用组
                   ├─ 判据：run_status 全为 1
                   └─ 关游戏
05:30  ZZZ-Backend-Stop（停止文件 → 已提权 watcher 杀后端，省 ~1.6GB）
```

## 判据写到哪

| 文件 | 内容 |
|---|---|
| `run-status.log` | 每次运行一行：`时间 游戏 OK/FAIL 明细` |
| `ALERT.txt` | 仅失败时追加，方便早上第一眼看到 |

这样"跑没跑成"不依赖任何人记着去看日志。
