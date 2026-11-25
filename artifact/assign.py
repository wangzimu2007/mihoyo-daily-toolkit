# -*- coding: utf-8 -*-
"""按角色画像给未装备的 5★ 圣遗物做「可用性分配」，输出保留/分解候选/缺口。

输入：
    artifacts.json    扫描解析结果
    characters.yaml   角色画像（build_characters.py 生成）
输出（默认 ./output）：
    assigned.csv          已分配给某角色的件（含角色名与分数）
    unassigned.csv        没有任何角色能用（分解候选）
    character_gaps.md     每个角色的可用件数与缺口
    assign_report.md      汇总

规则：
    * 只为「未装备」的 5★ 件分配（已装备的视为在用）
    * 主词条必须在该角色对应部位的 mains 白名单里
    * 套装命中角色 sets → 加分；不命中也能用，但要靠分数过线
    * score = Σ(副词条数值 / 单次强化最大值) × 角色权重
    * 贪心分配：分数高的件优先，每个角色每部位最多 keep_per_slot 件
"""
import argparse
import csv
import io
import json
import os
import sys

BGI_HOME = os.environ.get('BGI_HOME', r'D:\software\BetterGI')
from collections import Counter, defaultdict

import yaml

ROLL_MAX = {'暴击率': 3.89, '暴击伤害': 7.77, '攻击力': 5.83, '生命值': 5.83,
            '防御力': 7.29, '元素精通': 23.31, '元素充能效率': 6.48}
PERCENT_ATTRS = {'攻击力', '生命值', '防御力'}
SLOTS = ['生之花', '死之羽', '时之沙', '空之杯', '理之冠']


def norm_attrs(item):
    out = {}
    for d in item.get('attr') or []:
        for k, v in d.items():
            if k == 'isPercent':
                continue
            s = str(v)
            is_pct = s.endswith('%')
            try:
                num = float(s.rstrip('%'))
            except ValueError:
                continue
            name = k + '%' if (is_pct and k in PERCENT_ATTRS) else k
            out[name] = out.get(name, 0) + num
    return out


def main_attr(item):
    m = item.get('main') or ''
    v = str(item.get('mainVal') or '')
    if m in PERCENT_ATTRS and v.endswith('%'):
        return m + '%'
    return m


def score_for(attrs, weights):
    tot = 0.0
    for k, v in attrs.items():
        w = weights.get(k)
        if not w:
            continue
        base = k[:-1] if k.endswith('%') else k
        mx = ROLL_MAX.get(base) or ROLL_MAX.get(k)
        if not mx:
            continue
        tot += (v / float(mx)) * float(w)
    return round(tot, 2)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('--artifacts', default=r'D:\software\BetterGI\User\JsScript\OCRArtifacts\records\artifacts.json')
    ap.add_argument('-c', '--characters', default=os.path.join(here, 'characters.yaml'))
    ap.add_argument('-o', '--outdir', default=os.path.join(here, 'output'))
    args = ap.parse_args()

    items = json.load(io.open(args.artifacts, encoding='utf-8'))
    doc = yaml.safe_load(io.open(args.characters, encoding='utf-8'))
    chars = doc['characters']

    free = []
    equipped = 0
    for it in items:
        if (it.get('equip') or '').strip():
            equipped += 1
            continue
        if int(it.get('star') or 5) < 5:
            continue
        free.append(it)

    print('总件数 %d ｜已装备 %d ｜未装备 5★ %d ｜角色 %d' % (len(items), equipped, len(free), len(chars)))

    # 先算每个角色的候选池（不算容量）
    pool = defaultdict(list)     # name -> [(score, idx, set_hit)]
    cands = []                   # (score, idx, char, set_hit)
    for idx, it in enumerate(free):
        slot = it.get('slot') or ''
        mainv = main_attr(it)
        attrs = norm_attrs(it)
        set_type = it.get('setType') or ''
        for name, cfg in chars.items():
            pref = (cfg.get('mains') or {}).get(slot) or []
            fallback = (cfg.get('mains_fallback') or {}).get(slot) or []
            allowed = list(pref) + [m for m in fallback if m not in pref]
            if mainv not in allowed:
                continue
            main_bonus = 0.8 if mainv in pref else 0.0
            w = cfg.get('weights') or {}
            try:
                lv_num = int(it.get('lv') or 0)
            except (TypeError, ValueError):
                lv_num = 0
            if lv_num == 0:
                useful = sum(1 for k in attrs if w.get(k))
                strong = sum(1 for k in attrs if (w.get(k) or 0) >= 0.6)
                if useful < 2 or strong < 1:
                    continue
                sc = score_for(attrs, w) + 1.0 + main_bonus
                sets0 = cfg.get('sets') or []
                hit0 = bool(sets0) and set_type in sets0
                if hit0:
                    sc += 0.5
                elif sets0:
                    sc -= 0.2
                cands.append((sc, idx, name, hit0))
                continue
            sc = score_for(attrs, w)
            sets = cfg.get('sets') or []
            hit = bool(sets) and set_type in sets
            if sets and not hit:
                sc *= 0.75           # 套装不对降权
            if hit:
                sc += 0.5
            if sc < float(cfg.get('min_score') or 0):
                continue
            cands.append((sc, idx, name, hit))

    cands.sort(key=lambda x: -x[0])

    used = {}
    per_slot = defaultdict(int)   # (char, slot) -> count
    assigned = []

    def try_assign(idx, name, sc, hit):
        it = free[idx]
        slot = it.get('slot') or ''
        cap = int((chars[name].get('keep_per_slot') or 3))
        if idx in used or per_slot[(name, slot)] >= cap:
            return False
        used[idx] = name
        per_slot[(name, slot)] += 1
        assigned.append({'char': name, 'score': sc, 'set_hit': '是' if hit else '否', **it})
        return True

    # 阶段 1：保底 —— 每个角色每个部位先分到 1 件（按该角色该部位的最高分）
    # 避免「攻/攻/攻」型角色被双暴角色抢光
    by_char_slot = defaultdict(list)
    for sc, idx, name, hit in cands:
        by_char_slot[(name, free[idx].get('slot') or '')].append((sc, idx, name, hit))
    for key in by_char_slot:
        by_char_slot[key].sort(key=lambda x: -x[0])
    for name in sorted(chars):
        for slot in SLOTS:
            lst = by_char_slot.get((name, slot)) or []
            for sc, idx, nm, hit in lst:
                if idx not in used and per_slot[(name, slot)] == 0:
                    try_assign(idx, nm, sc, hit)
                    break

    # 阶段 2：剩余按分数填充
    for sc, idx, name, hit in cands:
        try_assign(idx, name, sc, hit)

    unassigned = [it for idx, it in enumerate(free) if idx not in used]

    if not os.path.isdir(args.outdir):
        os.makedirs(args.outdir)

    def row(it, extra=None):
        attrs = norm_attrs(it)
        d = {
            'set': it.get('setType'), 'slot': it.get('slot'),
            'main': main_attr(it), 'mainVal': it.get('mainVal'), 'lv': it.get('lv'),
            'subs': '; '.join('%s+%s' % (k, v) for k, v in attrs.items()),
        }
        if extra:
            d.update(extra)
        return d

    fields = ['char', 'score', 'set_hit', 'set', 'slot', 'main', 'mainVal', 'lv', 'subs']
    with io.open(os.path.join(args.outdir, 'assigned.csv'), 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for a in assigned:
            w.writerow(row(a, {'char': a['char'], 'score': a['score'], 'set_hit': a['set_hit']}))

    fields2 = ['set', 'slot', 'main', 'mainVal', 'lv', 'subs']
    with io.open(os.path.join(args.outdir, 'unassigned.csv'), 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=fields2)
        w.writeheader()
        for it in unassigned:
            w.writerow(row(it))

    # 每个角色的可用件数（分配前）
    avail = Counter(c[2] for c in cands)
    took = Counter()
    for (nm, _slot), cnt in per_slot.items():
        took[nm] += cnt
    md = ['# 圣遗物 × 角色 分配报告\n']
    md.append('- 未装备 5★：%d 件' % len(free))
    md.append('- 已分配：**%d** 件 ｜ 无人可用（分解候选）：**%d** 件\n' % (len(assigned), len(unassigned)))
    zero = [n for n in chars if took.get(n, 0) == 0]
    lack = [n for n in chars if 0 < took.get(n, 0) < 4]
    md.append('## 缺口：一件都没分到的角色（%d 人）\n' % len(zero))
    if zero:
        md.append('| 角色 | 类型 | 主词条需求 |')
        md.append('|---|---|---|')
        for n in zero:
            cfg = chars[n]
            wants = '、'.join(sorted({m for lst in (cfg.get('mains') or {}).values() for m in lst}))[:60]
            md.append('| %s | %s | %s |' % (n, cfg.get('role'), wants))
    md.append('\n## 分到不足 4 件的角色（%d 人）\n' % len(lack))
    if lack:
        md.append('| 角色 | 类型 | 已分配 |')
        md.append('|---|---|---|')
        for n in sorted(lack, key=lambda x: took.get(x, 0)):
            md.append('| %s | %s | %d |' % (n, chars[n].get('role'), took.get(n, 0)))
    md.append('\n## 分到最多的 15 个角色\n')
    md.append('| 角色 | 类型 | 已分配 | 主词条匹配池 |')
    md.append('|---|---|---|---|')
    for n, k in took.most_common(15):
        md.append('| %s | %s | %d | %d |' % (n, chars[n].get('role'), k, avail.get(n, 0)))

    with io.open(os.path.join(args.outdir, 'assign_report.md'), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(md) + '\n')

    print('已分配 %d ｜无人可用 %d' % (len(assigned), len(unassigned)))
    print('角色缺口(<5 件) %d 人' % len([1 for n in chars if avail.get(n, 0) < 5]))
    print('输出:', args.outdir)
    return 0


if __name__ == '__main__':
    sys.exit(main())
