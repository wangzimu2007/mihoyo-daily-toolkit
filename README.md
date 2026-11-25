# MiHoYo Daily Toolkit

中文 | [English](README.en.md)

米哈游三款游戏的**每日自动化可靠性工具集**，外加一套**圣遗物离线整理流水线**。

最初只做原神圣遗物，后来把绝区零、崩铁的每日链路和踩坑一起整理了进来 —— 三个游戏共用同一套「判据 + 保活 + 体检」思路，只是驱动方式不同。

> 所有工具只做「分析 + 报告 + 保活」。**不会自动分解、不会消耗任何游戏内资源。**

## 目录

| 目录 | 内容 | 依赖 |
|---|---|---|
| [`artifact/`](artifact/) | 原神圣遗物整理流水线（解析 → 评分 → 角色分配 → 清单 → 锁定建议） | Python 3.8+、PyYAML |
| [`games/genshin/`](games/genshin/) | 原神（BetterGI 一条龙）每日链路 | BetterGI |
| [`games/zzz/`](games/zzz/) | 绝区零（ZZZ-OneDragon）每日链路 + 手柄服务 + 后端启停 | ZZZ-OneDragon |
| [`games/hsr/`](games/hsr/) | 崩铁（March7thAssistant）每日链路与兜底 | March7thAssistant |
| [`reliability/`](reliability/) | 通用可靠性工具（会话保活、跑完体检、锁屏诊断、输入探针） | Windows PowerShell 5.1+ |
| [`scripts/`](scripts/) | 计划任务安装/卸载（一条命令注册守夜与每日自动化） | Windows |
| [`examples/`](examples/) | 跨游戏编排（总调度、提权 dispatcher、周扫描）**需改路径** | — |
| [`docs/`](docs/) | 踩坑记录 | — |
| [`samples/`](samples/) | 输出样例 + **可离线自测的样例日志** | — |

## 三个游戏的差异（这张表是全部设计的起点）

| | 原神 | 绝区零 | 崩铁 |
|---|---|---|---|
| 驱动工具 | BetterGI | ZZZ-OneDragon | March7thAssistant |
| 需要前台窗口 | ✅ 需要 | ✅ 需要 | ❌ 后台模式 |
| 需要会话解锁 | ✅ 需要 | ✅ 需要 | ❌ 锁屏也能跑 |
| 完成判据来源 | BGI 日志关键字 | `app_run_record/*.yml` 的 `run_status` | M7A `runs/*.log` |
| 主要失败模式 | 窗口没到前台 / 战斗策略文件缺失 | 后端未起 / 手柄服务被杀 | 背包满导致清体力失败 |
| 建议跑完动作 | 关游戏 | 停后端（省 1.6 GB） | 无需处理 |

**关键结论**：崩铁不需要守夜，另外两个需要。所以守夜只需覆盖原神 + 绝区零的时段。

## 快速开始

### 圣遗物：从扫描日志到清单

```bash
export BGI_HOME="/path/to/BetterGI"      # Windows: set BGI_HOME=D:\software\BetterGI
cd artifact
pip install -r requirements.txt
python parse_artifact_log.py --latest     # 日志 → artifacts.json
python evaluate.py                        # 规则评分 → keep/salvage/report
python build_characters.py                # 从已装备反推角色画像
python assign.py                          # 角色 × 圣遗物分配
python make_final_lists.py                # 最终清单 + 锁定方案建议
python four_star_rolling.py               # 四星滚动淘汰
```

Windows 一条命令：`.\artifact\run-pipeline.ps1 -BgiHome "D:\software\BetterGI"`

**没有游戏也能试**（自带样例日志）：

```powershell
.\samples\offline-test.ps1
```

### 每日自动化

```powershell
# 1) 装计划任务（守夜 + 每日自动化 + 周扫描，含开机自启）
.\scripts\install-tasks.ps1 -KeepAwake -DailyAll -WeeklyScan -ToolkitRoot "D:\tools\bgi-scan"

# 2) 手动跑一次
.\examples\run-daily-all.ps1              # 原神 → 绝区零
```

环境变量（可选，覆盖脚本里的默认安装目录）：

| 变量 | 作用 |
|---|---|
| `BGI_HOME` | BetterGI 安装目录 |
| `ZZZ_OD_ROOT` | 绝区零一条龙目录 |

### 可靠性工具

```powershell
.\reliability\keepawake.ps1 -Until 09:05 -AllowDisplayOff   # 防锁屏
.\reliability\post-run-audit.ps1 -Game genshin -SinceMinutes 45   # 跑完体检
.\reliability\lock-monitor.ps1 -UntilHour 12                # 锁屏诊断
```

## 三个最容易踩的坑

1. **`SetCursorPos` 不算用户输入** —— 防锁屏必须用 `mouse_event`/`SendInput`，否则空闲计时照样涨到锁屏阈值。见 [docs/pitfalls.md](docs/pitfalls.md#1-setcursorpos-不重置空闲计时)。
2. **锁屏后没有任何用户态办法解锁** —— 锁屏在独立安全上下文（微软 PowerToys Awake 官方文档确认），只能"防"不能"解"。
3. **判据只看日志最后 N 行会误判** —— 长流程写上千行会把关键证据冲掉，必须按运行起始时间过滤。

## 免责声明

- `games/` 与 `examples/` 里的脚本会**控制游戏窗口、模拟输入**，使用前请自行确认符合游戏的用户协议。
- 圣遗物流水线只产出建议清单；**分解不可逆**，请自行复核后再操作。
- 仓库内不含账号信息、UID、密码或 cookie；`characters.yaml` 是由「已装备圣遗物」反推的画像。

## License

MIT
