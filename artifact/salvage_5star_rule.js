// BetterGI「分解圣遗物」规则 —— 用于筛出「垃圾 5★」
// 用法：BetterGI → 独立任务 → 分解圣遗物 → 设置里填入本段 JS
//       （官方文档：https://www.bettergi.com/feats/task/artifactSalvage.html）
//
// 重要前提（官方文档原文）：
//   * 逐行扫描时会【首先忽略已上锁的圣遗物】→ 所以必须先把要留的锁上
//   * 扫描完成后【不会自动点击分解】，需要你手动确认
//   * 4 级强化后的圣遗物无法识别初始词条数
//
// 可用字段（ArtifactStat）：
//   Name            名称（字符串，可用来反推套装，但需自建对照表）
//   MainAffix       主词缀 { Type, Value }        ← 部位/套装都不提供
//   MinorAffixes[]  副词缀数组 { Type, Value, IsUnactivated }
//   Level           等级
//
// 判定思路（近似「规则判分 + 无人可用」中的「规则判分」部分）：
//   1) 主词条是稀缺资源（暴击/暴伤/精通/充能/治疗/元素伤害）→ 不分解
//   2) 双暴分 = 暴伤 + 2×暴击率 ≥ 30 → 不分解
//   3) 有效副词条（暴击/暴伤/攻击%/充能/精通）条数 ≥ 2 → 不分解
//   4) 以上都不满足 → 判为垃圾（Output = true 表示"匹配"，即会被列出来分解）
//
// 注意：这里只能看单件属性，做不到「这个角色用不上」的判断；
//       那一层要靠 artfacts 流水线生成的 keep 清单 + 游戏内锁定来保证。

const SCARCE_MAINS = [
  'CRITRate', 'CRITDMG', 'ElementalMastery', 'EnergyRecharge', 'HealingBonus',
  'PyroDMGBonus', 'HydroDMGBonus', 'DendroDMGBonus', 'ElectroDMGBonus',
  'AnemoDMGBonus', 'CryoDMGBonus', 'GeoDMGBonus'
];

const USEFUL_SUBS = ['CRITRate', 'CRITDMG', 'ATKPercent', 'EnergyRecharge', 'ElementalMastery'];

const DOUBLE_CRIT_MIN = 30;    // 双暴分保底线（社区口径 30 分及格）
const MIN_USEFUL_SUBS = 2;     // 有效副词条少于 2 条才考虑分解

function findAffix(list, type) {
  for (let i = 0; i < list.length; i++) {
    if (list[i].Type === type) return list[i];
  }
  return null;
}

// 1) 稀缺主词条 → 一律保留
if (SCARCE_MAINS.indexOf(ArtifactStat.MainAffix.Type) >= 0) {
  Output = false;
} else {
  const subs = Array.from(ArtifactStat.MinorAffixes || []);

  // 2) 双暴分
  const cr = findAffix(subs, 'CRITRate');
  const cd = findAffix(subs, 'CRITDMG');
  const dualCrit = (cr ? cr.Value : 0) * 2 + (cd ? cd.Value : 0);

  // 3) 有效副词条条数
  let useful = 0;
  for (let i = 0; i < subs.length; i++) {
    if (USEFUL_SUBS.indexOf(subs[i].Type) >= 0) useful++;
  }

  // 4) 综合判定：双暴够 / 有效词条够 → 保留，否则判垃圾
  if (dualCrit >= DOUBLE_CRIT_MIN || useful >= MIN_USEFUL_SUBS) {
    Output = false;
  } else {
    Output = true;   // 匹配成功 = 进入待分解列表（仍需你手动确认）
  }
}
