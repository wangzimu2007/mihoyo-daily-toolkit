# 崩坏：星穹铁道（March7thAssistant）

用 [March7thAssistant](https://github.com/moesnow/March7thAssistant)（M7A / 三月七小助手）
跑每日；包装脚本只做两件事：让 M7A 当天必跑一次，以及体力兜底。

## 每日内容（M7A `main` 任务）

| 项 | 完成标志（日志） |
|---|---|
| 邮件奖励 | `邮件奖励已领取` |
| 支援礼盒 | `支援礼盒奖励完成` |
| 无名勋礼 | `无名勋礼奖励完成` |
| 每日实训活跃度 | `每日实训活跃度 500/500` + `已领取实训档位奖励` |
| 委托奖励 | `已领取委托奖励` |
| 开拓力（体力） | `开拓力：N/300`（清到阈值以下） |
| 历战余响 / 差分宇宙 | 按配置的星期与次数 |

## 判据

M7A 自己会给 `<run_id>.log` 结论，外层只需检查：

1. `m7a.exe --status` 里该 `run_id` 的 `status == success`
2. 日志里有 `每日实训活跃度 500/500`
3. 日志里有 `开拓力：` 且数值低于阈值

## 和其他两个游戏的关键差异

**崩铁的后台模式不需要前台窗口，也不需要会话解锁。**

M7A 用后台截图 + 后台输入，实测在**锁屏状态下仍能跑完**（本仓库原神/绝区零那套守夜对它不是必需的）。
所以它的调度可以放在守夜窗口之外。

## 脚本

| 文件 | 作用 |
|---|---|
| `m7a-relic-daily.ps1` | 改 M7A 配置，让当天的「遗器清理」必定执行一次（**只改文件，不启动游戏**） |
| `m7a-fallback.ps1` | 体力兜底：清体力被背包容量卡住时，改为打拟造花萼（`--after-finish None` 避免跑完后自动关游戏） |

## 专属坑

1. **M7A 的 GUI 必须常驻**：它的内部定时任务（默认 06:00 main）只在 GUI 运行时生效。
   纯命令行调用 `m7a.exe --task main` 也可以，但不会自带定时。
2. **`--after-finish None`**：不带这个参数时，某些任务结束会顺手关掉游戏，
   后续脚本再想操作就得重新启动。
3. **体力被背包卡住是常见失败**：满背包时清体力会失败，`m7a-fallback.ps1` 就是为此存在。
4. **日志在 `logs/runs/<run_id>.log`**，`--status` 输出 JSON 里有 `recent_runs`，两者对照看。

## 验证

```powershell
Push-Location "E:\March7thAssistant_full"
.\m7a.exe --status | Out-String
Pop-Location

# 最近一次 main 的关键行
Get-ChildItem "E:\March7thAssistant_full\logs\runs\*.log" | Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 | ForEach-Object {
    Select-String -Path $_.FullName -Pattern '活跃度|开拓力|委托|邮件|勋礼' | Select-Object -Last 8
  }
```

## 要改的路径（首次使用）

| 项 | 默认值 | 说明 |
|---|---|---|
| M7A 根目录 | `E:\March7thAssistant_full` | 改两个脚本顶部的 `$root` / `$cfg` |

两个脚本只改 M7A 的配置文件与启动一次 `m7a.exe`，**不直接操作游戏窗口**。