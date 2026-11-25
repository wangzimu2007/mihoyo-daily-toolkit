# 踩坑记录

这份文档记录的是**实测**出来的行为差异，不是推测。每条都带验证方法。

---

## 1. SetCursorPos 不重置空闲计时

**现象**：写了"每 45 秒把光标移动 1 像素"的守夜脚本，屏幕照样在 5 分钟左右锁掉。

**根因**：
| 调用 | 光标会动 | 重置 `GetLastInputInfo` 的空闲计时 |
|---|---|---|
| `SetCursorPos(x, y)` | ✅ | ❌ **不算输入** |
| `mouse_event(MOUSEEVENTF_MOVE, dx, dy)` | ✅ | ✅ 算输入 |
| `SendInput`（鼠标/键盘） | ✅ | ✅ 算输入 |

**验证方法**：守夜脚本跑起来后，每 5 秒读一次
`(GetTickCount() - GetLastInputInfo().dwTime) / 1000`：

- 用 `SetCursorPos`：空闲会单调涨到 300s 然后锁屏
- 用 `mouse_event`：空闲在 0~45 秒之间周期回落

**正确写法**（见 `reliability/keepawake.ps1`）：

```powershell
[KA]::mouse_event(0x0001, 1, 0, 0, [IntPtr]::Zero)   # MOUSEEVENTF_MOVE +1px
Start-Sleep -Milliseconds 60
[KA]::mouse_event(0x0001, -1, 0, 0, [IntPtr]::Zero)  # 移回原位
```

**补充**：`SetThreadExecutionState(ES_DISPLAY_REQUIRED)` 只能防"睡眠/关屏"，
**不重置锁屏计时**，必须配合真实输入。

---

## 2. 锁屏后无法用任何用户态程序解锁

**结论**：锁屏（安全桌面）与用户会话是**不同安全上下文**，用户态进程既不能注入输入，也不能切回。

**证据**：
- 微软官方 PowerToys Awake 文档：*"Awake doesn't function when the lock screen is displayed. This limitation exists because the lock screen operates in a separate security context from the user session."*
- 本机实测：锁屏后 `GetForegroundWindow()=0`、`GetCursorPos/SetCursorPos` 全失败、`SendInput` 抛异常。

**推论**：
1. 想要无人值守能跑，只能**防止锁屏**，不能指望"自动解锁"。
2. 所谓"自动解锁工具"需要 SYSTEM 服务 + 存储明文口令 + 模拟 SAS，属于绕过安全机制，不建议。

**可用的锁屏判据**：`GetForegroundWindow() == IntPtr.Zero`。

---

## 3. 判据只看日志最后 N 行会误判

**现象**：脚本跑完后判据报 `体力=False`，但日志里明明有「体力耗尽」。

**根因**：一条龙流程顺序是 秘境 → 委托 → 领奖。委托阶段会写上千行日志，
`Get-Content -Tail 400` 早已看不到秘境阶段的「体力耗尽」。

**正确做法**：记录开始时间戳，按时间窗过滤整份日志：

```powershell
$logStartStamp = (Get-Date).ToString('HH:mm:ss')
# 结束时
$keep = @(); $on = $false
foreach ($ln in (Get-Content $log)) {
  if ($ln -match '^\[(\d{2}:\d{2}:\d{2})') { if ($Matches[1] -ge $logStartStamp) { $on = $true } }
  if ($on) { $keep += $ln }
}
```

---

## 4. 提权窗口在前台时，普通权限进程的输入探针会误报"锁屏"

**现象**：游戏/自动化程序（管理员权限）在前台时，`SetCursorPos` 返回 `False`，
看起来像锁屏，其实会话完全正常。

**根因**：UIPI（用户界面特权隔离）—— 低完整性级别进程不能向高完整性级别窗口发送输入。

**对策**：
- 判断锁屏用 `GetForegroundWindow() == 0`，不要用 `SetCursorPos` 的返回值。
- 体检脚本里 `SetCursorPos` 失败只记为"可能是 UIPI"，不作为失败项。

---

## 5. DPI 缩放会让窗口尺寸读取偏小

**现象**：体检报「窗口 1295x757 小于 1920x1080」，实际游戏客户区就是 1920x1080。

**根因**：非 DPI 感知进程读到的是**虚拟化坐标**：`1942 / 1.5 ≈ 1295`（150% 缩放）。

**对策**：脚本开头声明 DPI 感知：

```powershell
Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' `
  -Name Dpi -Namespace Win32 -PassThru | Out-Null
[Win32.Dpi]::SetProcessDPIAware() | Out-Null
```

---

## 6. BetterGI 的 OCRArtifacts 不会自己切背包页签

**现象**：直接跑 `OCRArtifacts` 扫出来的是**武器**，不是圣遗物。

**根因**：脚本注释写明「页签点击已禁用：坐标不可靠，改为要求用户预先切到圣遗物页签」。

**对策**：先跑一个会点击页签的脚本（本仓库用「读取圣遗物数量」），
再跑扫描；用两次的「数量」是否一致来校验。

---

## 7. 圣遗物日志里的「治疗加成」会被误删

**现象**：治疗头解析失败，占空的 51 个块全是 `治疗加成`。

**根因**：为兼容「水元素伤害**加成**」而统一 `replace('加成', '')`，
把「治疗加成」变成了「治疗」。

**对策**：只裁掉 `伤害加成` 的尾缀：

```python
if s.endswith('伤害加成'):
    s = s[:-2]
```

---

## 8. Nova 的战斗策略文件必须在 AutoFight 根目录

**现象**：所有需要战斗的委托必然失败 → 委托永远 3/4 → 每日奖励永远领不到。

**根因**：配置里写的是 `万能战斗策略（萌新推荐）`，程序在
`<BetterGI>/User/AutoFight/<名字>.txt` 找文件，而实际文件在
`<BetterGI>/User/AutoFight/群友分享/<名字>.txt`（子目录）。

**对策**：把策略文件复制到 `User/AutoFight/` 根目录，或在配置里用完整相对路径。

**教训**：这类"路径对不上"的失败是**静默的**，只有对判据做「委托完成数」检查才能发现。

---

## 9. 自动锁屏的排查顺序

本机排查过一轮，顺序如下（从便宜到贵）：

1. `ScreenSaveActive` / 屏保组策略
2. `powercfg /query` 的 `VIDEOIDLE` / `STANDBYIDLE`
3. `HKLM\...\Policies\System\InactivityTimeoutSecs`
4. `EnableGoodbye`（动态锁）
5. 是否存在人体存在感应硬件（`Get-PnpDevice -Class Sensor`、`SensorService`）
6. 事件日志 `Kernel-Power` 42/107/506/507（判断是否 Modern Standby）
7. 远程控制软件断开行为（RustDesk/ToDesk）

**本机结论**：以上全排除，最终靠「每 45 秒 mouse_event 抖动」覆盖 —— 不管触发者是谁，空闲计时永远不达标就不会锁。
