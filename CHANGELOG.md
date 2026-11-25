# Changelog

## v1.0.0 (2026-11-25)

首个公开版本。所有内容来自一套实际运行的原神/绝区零/崩铁每日自动化环境。

### 圣遗物流水线（artifact/）

- `parse_artifact_log.py`：BetterGI `OCRArtifacts` 扫描日志 → 结构化 `artifacts.json`
  - 主词条容错（`水元素伤害加成` → `水元素伤害`，但保留 `治疗加成`）
  - 允许部位/主词条之间夹 OCR 噪音行
  - 允许副词条丢失 `·` 前缀
  - 本机实测 2610/2610 块全部解析
- `evaluate.py`：规则评分（有效词条 / 双暴 / 主词条白名单 / 辅助套装充能 / 套装放宽）
- `build_characters.py`：从「已装备的圣遗物」反推角色画像（类型 / 常用套装 / 主词条 / 副词条权重）
- `apply_community_sets.py`：合并社区推荐（社区主词条作为加分项，类型模板作兜底）
- `assign.py`：角色 × 圣遗物分配，含「每部位保底 1 件」避免饿死单一类型角色
- `make_final_lists.py`：双条件最终清单 + 游戏内锁定方案建议
- `four_star_rolling.py`：四星滚动淘汰（每部位限量，新件更好会挤掉旧件）
- `salvage_5star_rule.js`：BetterGI「分解圣遗物」任务用的 JS 规则（保守口径）

### 可靠性工具（reliability/）

- `keepawake.ps1`：会话保活
  - 每 45 秒 `mouse_event` 抖动（**关键**：`SetCursorPos` 不重置空闲计时）
  - `SetThreadExecutionState` 防睡眠；`-AllowDisplayOff` 允许关屏
  - 单实例保护、到期主动锁屏
- `post-run-audit.ps1`：跑完 9 项体检（进程 / 窗口可见性 / DWM 隐藏 / 前台 / 输入 / 显示模式 / 锁 / 判据 / 日志关键字）
  - 声明 DPI 感知，避免 150% 缩放下窗口尺寸误读
  - 用 `GetForegroundWindow()==0` 判断锁屏，避免提权窗口造成的 UIPI 误报
- `lock-monitor.ps1`：锁屏状态变化诊断（只记变化，带前台进程与显示器数量）
- `input-probe.ps1`：输入可用性探针（OK / PARTIAL / BLOCKED）
- `screensaver.ps1`：屏保开关（含夜间保护窗口，防止脚本提前把屏保开回来）
- `remote-test-monitor.ps1`：远程控制断开后的会话状态监控

### 编排示例（examples/）

- `run-daily-all.ps1`：原神 → 绝区零串行调度
- `run-with-restore.ps1`：单游戏包装器（切 1080p → 启动 → 聚焦 → 跑 → 判据 → 关游戏 → 还原 4K）
- `dispatcher.ps1`：提权调度器（读 `request.json` 执行启动游戏/关 BGI/聚焦等动作）
- `weekly-artifact-scan.ps1`：周扫描全链路
- `zzz-focus.ps1` / `zzz-stop-flag.ps1` / `m7a-*.ps1` / `pad-service-run.ps1` / `release-keys.ps1`

### 文档

- `docs/pitfalls.md`：9 条实测踩坑，每条含现象、根因、验证方法
- `samples/`：真实报告与锁定方案样例

### 已知限制

- 星级由「套装是否只存在低星」+「花/羽主词条数值」推断，混装 4★ 可能误判为 5★
- 4★ 无法用游戏的锁定方案保护（游戏锁定方案只对五星生效）
- 分解动作不可逆，本仓库只产出建议清单
