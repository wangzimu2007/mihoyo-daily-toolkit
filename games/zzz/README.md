# 绝区零（ZZZ-OneDragon）

用 [Zzz-OneDragon](https://github.com/OneDragon-Anything/ZenlessZoneZero-OneDragon) 的
FastAPI 后端 + 应用组跑每日；外层用 PowerShell 包装：起后端 → 手柄进游戏 → 前台模式跑 → 停后端。

## 每日内容（8 项）

| 应用 | 内容 |
|---|---|
| `email` | 邮件奖励 |
| `random_play` | 随机委托（每日一次） |
| `coffee` | 咖啡厅 |
| `notorious_hunt` | 恶名狩猎（每周次数） |
| `charge_plan` | 充电计划（体力） |
| `engagement_reward` | 委托奖励 |
| `city_fund` | 城市基金 |
| `ridu_weekly` | 丽都周纪 |

## 判据

后端会把每个应用的运行结果写进
`config/01/app_run_record/<应用名>.yml`，字段 `run_status`：

| 值 | 含义 |
|---|---|
| 0 | 未运行 |
| 1 | 成功 |
| 2 | 失败 |
| 3 | 运行中 |

一次运行的判据：**本次写入的 8 条记录 `run_status` 全部为 1**。

## 后端 API（127.0.0.1:23001）

| 端点 | 用途 |
|---|---|
| `GET /health` | `{"ok":true,"ready":true}` 表示后端就绪 |
| `GET /game/status` | 当前状态与节点（`running` / `success` / …） |
| `GET /game/window` | 游戏窗口信息 |
| `POST /game/enter` | 让手柄/服务进入游戏 |
| `POST /game/run/one-dragon` | 开始跑应用组 |
| `POST /game/close` | 关闭游戏 |

## 脚本

| 文件 | 作用 |
|---|---|
| `zzz-server.ps1` | 后端启停（`-Action status|start|stop|watch`），支持 `-StopFile` 让已提权的 watcher 被非提权脚本触发停止 |
| `zzz-focus.ps1` | 强制把游戏窗口拉到前台（ALT 解锁 + `AttachThreadInput`） |
| `zzz-stop-flag.ps1` | 写停止文件 → 等后端端口释放（默认 60 秒） |
| `pad-service.py` / `pad-service-run.ps1` | 虚拟手柄服务（让游戏认为有手柄，从而用按键驱动 UI） |
| `pad-auto.ps1` | 手柄自动进游戏 + 领取弹窗 |
| `pad-enter.ps1` / `pad-claim-popups.ps1` | 单一职责：进游戏 / 领弹窗 |
| `zzz-display.ps1` | 切分辨率 |

## 专属坑

1. **`pad-cmd.json` 残留 STOP 会把刚起的 pad 服务杀掉**：启动前要清空该文件。
2. **管道句柄继承导致卡死**：用 `Start-Process` 起 pad 服务时必须重定向输出到文件，
   否则父进程退出会把子进程的输出句柄一并关掉。
3. **`DomainName` 为空会让秘境任务被静默跳过**：配置里必须显式填秘境名。
4. **后端跑完要停**：常驻约 1.6 GB 工作集，跑完即停（本仓库用 `ZZZ-Backend-Stop` 计划任务 05:30 执行）。
5. **停止后端需要提权**：后端由管理员启动，普通权限脚本杀不掉。
   做法是让提权进程带 `-StopFile` 参数启动一个 watcher，
   非提权脚本只需创建停止文件即可触发。
6. **前台模式要求窗口可见且在前台**：被最小化或切走会导致点击错位。
   本仓库在等待循环里每 60 秒检查一次前台进程，不是就重新拉焦点。

## 验证

```powershell
# 后端在不在
Invoke-RestMethod http://127.0.0.1:23001/health

# 8 项结果
Get-ChildItem "D:\software\ZenlessZoneZero-OneDragon\config\01\app_run_record\*.yml" |
  Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-40) } |
  ForEach-Object {
    $c = Get-Content $_.FullName -Raw -Encoding UTF8
    $s = if ($c -match 'run_status:\s*(\d)') { $Matches[1] } else { '?' }
    '{0,-24} {1}' -f $_.BaseName, $s
  }
```

## 要改的路径（首次使用）

| 项 | 默认值 | 覆盖方式 |
|---|---|---|
| 一条龙根目录 | `D:\software\ZenlessZoneZero-OneDragon` | 环境变量 `ZZZ_OD_ROOT`，或 `zzz-server.ps1 -Root` |
| Python 解释器 | `<根目录>\.venv\Scripts\python.exe` | 改各 `pad-*.ps1` 顶部 `$py` |

`zzz-stop-flag.ps1` 用 `$env:ZZZ_OD_ROOT` 定位 `.debug\zzz-stop.flag`；
`zzz-server.ps1` 的 `-StopFile` 参数要指向同一个文件。