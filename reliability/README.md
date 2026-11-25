# 自动化可靠性工具

无人值守跑游戏自动化的三个真实问题，以及对应的工具：

| 问题 | 工具 |
|---|---|
| 会话因空闲锁屏 → 输入被系统拒绝 → 自动化静默失败 | `keepawake.ps1` |
| 跑完"成功"了，其实没做事（判据只看进程退出码） | `post-run-audit.ps1` |
| 反复锁屏但找不到原因 | `lock-monitor.ps1` / `input-probe.ps1` |

## keepawake.ps1 — 会话保活

```powershell
.\keepawake.ps1 -Until 09:05 -AllowDisplayOff
```

行为：
- 每 45 秒 `mouse_event(MOUSEEVENTF_MOVE, ±1px)` —— **必须用 mouse_event，`SetCursorPos` 不重置空闲计时**
- `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)` —— 防系统睡眠
- `-AllowDisplayOff`：不申请 `ES_DISPLAY_REQUIRED`，屏幕可以正常熄灭
- 单实例保护：已有实例在跑则直接退出
- 到期或检测到 `.keepawake.stop` 时退出，并（默认）主动 `LockWorkStation` 恢复安全

| 参数 | 说明 |
|---|---|
| `-Until HH:mm` | 运行到当天/次日该时刻 |
| `-AllowDisplayOff` | 允许关屏（仍防锁屏） |
| `-NoLock` | 结束时不要主动锁屏 |
| `-Stop` | 创建停止文件让已有实例退出 |

**验证是否生效**：每 5 秒读一次空闲秒数，应周期性回落到 0（周期 ≈ 45 秒）。

## post-run-audit.ps1 — 跑完体检

```powershell
.\post-run-audit.ps1 -Game genshin -SinceMinutes 45 `
  -BgiLogDir "D:\software\BetterGI\log" `
  -ZzzRecordDir "D:\software\ZenlessZoneZero-OneDragon\config\01\app_run_record"
```

检查 9 项：

1. 进程（残留 BetterGI / 游戏）
2. **窗口状态**：句柄是否为 0、`IsWindowVisible`、`IsMinimized`、**DWM Cloaked**、尺寸
3. 前台窗口 + 输入 API（区分 UIPI 拦截和真锁屏）
4. 显示模式 + 分辨率注册表
5. 运行锁 / 残留调度进程
6. 判据文件与告警文件
7. **BGI 日志关键字**（时间窗内）：体力耗尽、秘境轮次、识图失败、焦点丢失、输入异常、等待主界面
8. 绝区零 `run_status` 记录
9. 结论：PASS / FAIL + 问题清单

注意：脚本已声明 DPI 感知，否则 150% 缩放下窗口尺寸会被读成 `1295x757`（实际 1920x1080）。

## lock-monitor.ps1 — 锁屏诊断

```powershell
.\lock-monitor.ps1 -UntilHour 12 -IntervalSec 15
```

只记录**状态变化**：锁屏/解锁、空闲秒数、前台进程、显示器数量与分辨率。

关键判据：`GetForegroundWindow() == 0` 才是真锁屏；
`SetCursorPos` 失败在"提权窗口在前台"时也会发生（UIPI），不能当锁屏信号。

## input-probe.ps1 — 输入可用性探针

区分三种状态：

| 状态 | 含义 |
|---|---|
| `OK` | `GetCursorPos`/`SetCursorPos`/`mouse_event` 都正常 |
| `PARTIAL` | 光标能设位置但 `mouse_event` 没生效 |
| `BLOCKED` | 输入被拒（锁屏 / 安全桌面） |

## screensaver.ps1 — 屏保开关

```powershell
.\screensaver.ps1 -Action off|on|status [-Force]
```

带"夜间保护窗口"逻辑（默认 01:50~09:05 内拒绝恢复），避免某个脚本提前结束把屏保开回来。
如果已经用 keepawake 方案，这个脚本通常不需要。

## 建议的组合

```
开机自启  → keepawake.ps1 -Until 23:55 -AllowDisplayOff
跑任务前  → 确认 GetForegroundWindow != 0（否则直接退出，别白跑 30 分钟）
跑任务后  → post-run-audit.ps1 + 判据写文件（run-status.log / ALERT.txt）
出问题时  → lock-monitor.ps1 抓状态变化
```
