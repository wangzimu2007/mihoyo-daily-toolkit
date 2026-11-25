# 样例数据

| 文件 | 内容 |
|---|---|
| `artifact_log_sample.txt` | 6 件圣遗物的 BetterGI `OCRArtifacts` 日志片段（5★×3 / 4★×3，覆盖 5 个部位 + 元素伤害杯） |
| `SUMMARY.md` | 真实全量运行的最终结论（2607 件的保留/分解统计） |
| `lock_scheme.md` | 真实生成的游戏内锁定方案建议 |
| `offline-test.ps1` | **离线自测脚本**：不装游戏也能跑通整条流水线 |

## 离线自测

```powershell
cd <仓库根目录>
.\samples\offline-test.ps1                 # 用默认 python
.\samples\offline-test.ps1 -Python "C:\Python311\python.exe"
```

它会：

1. 在临时目录造一个 `BGI_HOME` 结构
2. 把 `artifact_log_sample.txt` 放进去
3. 依次跑 `parse` → `evaluate` → `assign` → `make_final_lists`
4. 打印产物路径，然后清理临时目录

预期结果：解析 **6/6 成功**，其中 3 件判「4★」、3 件「5★」，
评分后能产出 `output/report.md` 与 `final/SUMMARY.md`。

## 样例日志的格式说明

BetterGI 的 `OCRArtifacts` 日志是「一块一件」的纯文本：

```
=============================开始遍历第1页
===================第1个圣遗物信息:
<名称>
<部位>
<主词条>
<主词条数值>
<等级，如 +20>
·<副词条>+<数值>
...
<套装名>：
2 件套：<套装效果文本>
```

解析器的分隔符正则：`={10,}第\d+个圣遗物信息:`（注意 `第` 和 `个` 之间**不能有空格**）。
