# Genshin Artifact Toolkit

原神圣遗物整理 + 游戏自动化可靠性工具集。

针对两个真实痛点：

1. **圣遗物背包满了没法判断该留什么** —— 用 BetterGI 的 OCR 扫描日志，离线算出「哪些留、哪些可分解、每个角色能用什么」，并生成游戏内锁定方案建议。
2. **无人值守的每日自动化经常失败，但失败是静默的** —— 提供判据、体检、会话保活等工具，让"跑没跑成"变成一条可查询的记录。

> 所有工具只做「分析 + 报告 + 保活」，**不会自动分解、不会自动消耗任何游戏内资源**。

## 目录

| 目录 | 内容 | 依赖 |
|---|---|---|
| [`artifact/`](artifact/) | 圣遗物整理流水线（解析 → 评分 → 角色分配 → 清单 → 锁定建议） | Python 3.8+、PyYAML |
| [`reliability/`](reliability/) | 自动化可靠性工具（会话保活、跑完体检、锁屏诊断） | Windows PowerShell 5.1+ |
| [`examples/`](examples/) | 真实在用的编排脚本（原神/绝区零/崩铁的调度链）**需按自己环境改路径** | BetterGI / ZZZ-OneDragon / March7thAssistant |
| [`docs/`](docs/) | 踩坑记录与设计说明 | — |
| [`samples/`](samples/) | 输出样例（报告、锁定方案） | — |

## 快速开始

### 圣遗物：从扫描日志到清单

前置：BetterGI + `OCRArtifacts` 脚本扫过背包，日志在
`<BetterGI>/User/JsScript/OCRArtifacts/records/artifact_log_*.txt`。

```bash
export BGI_HOME="D:/software/BetterGI"      # Windows: set BGI_HOME=D:\software\BetterGI

cd artifact
python parse_artifact_log.py --latest        # 日志 → artifacts.json
python evaluate.py                           # 规则评分 → keep/salvage/report
python build_characters.py                   # 从已装备反推角色画像 → characters.yaml
python assign.py                             # 角色 × 圣遗物分配
python make_final_lists.py                   # 最终清单 + 锁定方案建议
python four_star_rolling.py                  # 四星滚动淘汰
```

输出在各自的 `output/` 与 `final/` 下，核心是 `report.md` 和 `salvage.csv`。

### 可靠性：让凌晨的自动化真的能跑

```powershell
# 1) 会话保活（关键：防自动锁屏导致输入被拒）
.\reliability\keepawake.ps1 -Until 09:05 -AllowDisplayOff

# 2) 跑完体检（9 项：窗口可见性/前台/输入/显示器/锁/判据/日志关键字）
.\reliability\post-run-audit.ps1 -Game genshin -SinceMinutes 45

# 3) 锁屏根源诊断（记录状态变化 + 前台窗口 + 显示器数量）
.\reliability\lock-monitor.ps1 -UntilHour 12
```

## 三个最容易踩的坑（都在这套工具里解决了）

1. **`SetCursorPos` 不算用户输入** —— 想靠"移动鼠标防锁屏"，必须用 `mouse_event`/`SendInput`，否则空闲计时照样涨到锁屏阈值。见 [docs/pitfalls.md](docs/pitfalls.md#1-setcursorpos-不重置空闲计时)。
2. **锁屏后没有任何用户态办法解锁** —— 锁屏跑在独立安全上下文（微软官方确认 PowerToys Awake 在锁屏时也无效），所以只能"防"，不能"解"。
3. **判据只看日志最后 N 行会误判** —— 长流程会写上千行，前面的关键证据会被冲掉，必须按时间窗过滤。

## 免责声明

- `examples/` 里的脚本会**控制游戏窗口、模拟输入**，使用前请自行确认符合游戏的用户协议。
- 圣遗物流水线只产出建议清单；**分解动作不可逆**，请自行复核后再操作。
- 仓库内不含任何账号信息、密码或 cookie；`characters.yaml` 是按「已装备圣遗物反推」生成的画像，不含 UID。

## License

MIT
