# 圣遗物整理流水线

输入 BetterGI `OCRArtifacts` 的扫描日志，输出「保留 / 分解候选 / 锁定方案建议」。

**只出清单，不做任何游戏内操作。**

## 前置

1. BetterGI 装有 `OCRArtifacts` 脚本，背包扫过一遍，日志在
   `<BGI_HOME>/User/JsScript/OCRArtifacts/records/artifact_log_*.txt`
2. Python 3.8+ 与 PyYAML
3. 设置环境变量（或直接改脚本里的默认值）：

```bash
export BGI_HOME="/path/to/BetterGI"        # Windows: set BGI_HOME=D:\software\BetterGI
```

## 五步

```bash
python parse_artifact_log.py --latest    # 1. 日志 → artifacts.json（自动容错 + 去重）
python evaluate.py                       # 2. 规则评分 → output/{keep,salvage,report}
python build_characters.py               # 3. 已装备反推角色画像 → characters.yaml
python apply_community_sets.py           # 3b. 可选：合并社区推荐（需自备 community_sets.yaml）
python assign.py                         # 4. 角色 × 圣遗物分配 → output/{assigned,unassigned}
python make_final_lists.py               # 5. 最终清单 + lock_scheme.md
python four_star_rolling.py              # 6. 可选：四星滚动淘汰
```

## 输出说明

| 文件 | 内容 |
|---|---|
| `output/artifacts_scored.csv` | 全量明细：双暴分 / 有效词条 / 档位 / 判定原因 |
| `output/keep.csv` · `salvage.csv` | 规则法的保留 / 分解候选 |
| `output/assigned.csv` · `unassigned.csv` | 分配法：有角色能用 / 没人能用 |
| `final/keep_final.csv` · `salvage_5star.csv` | **双条件最终清单**（规则判分 **且** 无人可用） |
| `final/lock_scheme.md` | 游戏内「圣遗物锁定方案」建议（按套装给主词条/副词条条件） |
| `final/four_star_*` | 四星滚动淘汰结果 |

## 规则口径

### 有效词条数

```
有效词条数 = Σ(副词条数值 ÷ 该词条单次强化最大值)    只累计「有效词条」
```

单次强化最大值（5★ 实测上限）：

| 词条 | 值 |
|---|---|
| 暴击率 | 3.89% |
| 暴击伤害 | 7.77% |
| 攻击力% / 生命值% | 5.83% |
| 防御力% | 7.29% |
| 元素精通 | 23.31 |
| 元素充能效率 | 6.48% |

5★ 满级共 9 次强化，所以有效词条理论上限约 9。社区分档：**S≥8 / A≥7 / B 5~6 / C≤4**。

### 双暴分

```
双暴分 = 暴击伤害 + 2 × 暴击率      （只算副词条）
```

30~35 及格、40+ 保留（社区口径）。

### 判定顺序（`rules.yaml`）

1. 指定永久分解 / 永久保留的套装
2. 星级低于阈值 → 分解
3. **稀缺主词条**（元素伤害杯、精通沙、充能沙、暴击/暴伤头、治疗头）→ 直接保留
4. **辅助套装 + 充能副词条**（已强化的要求 ≥2 条）→ 保留
5. 常见主词条（攻击/生命/防御%）→ 有效词条够门槛才保留
6. 双暴保底线 / 热门套装放宽
7. 分档 S/A/B 保留，C → 分解候选

### 双条件分解口径

```python
分解候选 = （规则判分） 且 （没有任何角色能用）
```

单用规则会误杀"胚子"和"未来角色可用"的件；单用分配会漏掉"暂时没人用但值得囤"的。

## 角色画像（characters.yaml）

`build_characters.py` 从「已装备的圣遗物」反推每个角色的：

- 类型（crit / hp / em / def / heal / atk / aux）
- 常用套装
- 主词条白名单
- 副词条权重
- 每部位保留上限

理由是：**不存在权威的「角色→权重」表**（GOOD 只是背包/配装格式；各家权重闭源或需 UID），
从账号实际配装反推比抄通用表更贴合。

手工校准写在 `build_characters.py` 的 `OVERRIDES` 里，社区推荐放 `community_sets.yaml`，
用 `apply_community_sets.py` 合并（社区主词条作为"优先加分"，类型模板作为兜底）。

## 已知限制

- **星级是推测的**：OCR 日志不含星级，靠「套装是否只存在低星」+「花/羽主词条数值」推断。
- **4★ 无法用锁定方案保护**：游戏的锁定方案只对五星生效，四星只能逐件手动锁。
- **解析率依赖 OCR 质量**：本机实测 2610/2610 可解析，但极端字体/语言会掉。
