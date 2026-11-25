# -*- coding: utf-8 -*-
"""四星圣遗物「滚动淘汰」评估。

规则来源：rules.yaml 的 four_star_keep（每套每部位限量 + 主词条/副词条条件）
淘汰机制：同一 (套装, 部位) 内按质量排序，只留前 N 件；新件更好就把旧件挤掉。
排除：已装备的不参与（游戏快速分解也选不到已装备的）。

质量排序：先比有效词条数（充能/精通/双暴/攻击%），再比双暴分，再比等级。

输出（默认 ./final）：
    four_star_keep.csv     本轮应保留（需要在游戏里锁住）
    four_star_salvage.csv  本轮可清理
    four_star_report.md    按套装/部位的保留淘汰明细
用法：
    python four_star_rolling.py
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

HERE = os.path.dirname(os.path.abspath(__file__))
PERCENT_ATTRS = {'攻击力', '生命值', '防御力'}
USEFUL = ['元素充能效率', '元素精通', '暴击率', '暴击伤害', '攻击力%']


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


def quality(item):
    """质量分：有效词条条数为主，其次双暴，其次等级"""
    attrs = norm_attrs(item)
    useful = sum(1 for k in attrs if k in USEFUL)
    cr = attrs.get('暴击率', 0.0)
    cd = attrs.get('暴击伤害', 0.0)
    er = attrs.get('元素充能效率', 0.0)
    try:
        lv = int(item.get('lv') or 0)
    except (TypeError, ValueError):
        lv = 0
    return (useful, round(cr * 2 + cd, 1), round(er, 1), lv)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--artifacts', default=r'D:\software\BetterGI\User\JsScript\OCRArtifacts\records\artifacts.json')
    ap.add_argument('-r', '--rules', default=os.path.join(HERE, 'rules.yaml'))
    ap.add_argument('-o', '--outdir', default=os.path.join(HERE, 'final'))
    args = ap.parse_args()

    rules = yaml.safe_load(io.open(args.rules, encoding='utf-8'))
    fs = rules.get('four_star_keep') or {}
    default_cfg = fs.get('_default') or {}
    low_star = set(rules.get('low_star_sets') or [])

    items = json.load(io.open(args.artifacts, encoding='utf-8'))
    low = []
    equipped = 0
    for it in items:
        if int(it.get('star') or 5) >= 5:
            continue
        if (it.get('equip') or '').strip():
            equipped += 1        # 已装备：不参与，也不建议动
            continue
        low.append(it)

    # 分桶：(套装, 部位) -> 候选（命中 four_star_keep 条件）
    buckets = defaultdict(list)
    rejected = []
    for it in low:
        set_type = it.get('setType') or ''
        slot = it.get('slot') or ''
        mainv = main_attr(it)
        attrs = norm_attrs(it)
        cfg = fs.get(set_type)
        if cfg is None and set_type in low_star:
            cfg = default_cfg
        if not cfg:
            rejected.append(it)      # 不在任何规则里 → 直接可清理
            continue
        hit_main = mainv in (cfg.get('mains') or [])
        hit_sub = any(k in attrs for k in (cfg.get('sub_any') or []))
        if not (hit_main or hit_sub):
            rejected.append(it)
            continue
        buckets[(set_type, slot)].append(it)

    keep, drop = [], list(rejected)
    detail = []
    for (set_type, slot), lst in sorted(buckets.items()):
        cfg = fs.get(set_type) or default_cfg
        limit = int(cfg.get('max_per_slot') or 2)
        lst.sort(key=lambda x: quality(x), reverse=True)
        for i, it in enumerate(lst):
            if i < limit:
                keep.append((it, quality(it)))
            else:
                drop.append(it)
        detail.append((set_type, slot, len(lst), min(limit, len(lst)), [quality(x) for x in lst[:limit]]))

    if not os.path.isdir(args.outdir):
        os.makedirs(args.outdir)

    def row(it):
        attrs = norm_attrs(it)
        return {
            'set': it.get('setType'), 'slot': it.get('slot'), 'main': main_attr(it),
            'mainVal': it.get('mainVal'), 'lv': it.get('lv'),
            'useful': quality(it)[0], 'dual': quality(it)[1], 'er': quality(it)[2],
            'subs': '; '.join('%s+%s' % (k, v) for k, v in attrs.items()),
        }

    fields = ['set', 'slot', 'main', 'mainVal', 'lv', 'useful', 'dual', 'er', 'subs']
    with io.open(os.path.join(args.outdir, 'four_star_keep.csv'), 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=fields); w.writeheader()
        for it, _q in sorted(keep, key=lambda x: (x[0].get('setType'), x[0].get('slot'))):
            w.writerow(row(it))
    with io.open(os.path.join(args.outdir, 'four_star_salvage.csv'), 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=fields); w.writeheader()
        for it in sorted(drop, key=lambda x: (x.get('setType'), x.get('slot'))):
            w.writerow(row(it))

    md = ['# 四星圣遗物 · 滚动淘汰结果\n']
    md.append('- 四星未装备：%d 件（已装备 %d 件不参与）' % (len(low), equipped))
    md.append('- **本轮保留：%d 件**（需在游戏里锁住）' % len(keep))
    md.append('- **本轮可清理：%d 件**' % len(drop))
    md.append('')
    md.append('## 按套装/部位（留 N 件）\n')
    md.append('| 套装 | 部位 | 命中候选 | 保留 | 淘汰 |')
    md.append('|---|---|---|---|---|')
    for set_type, slot, n, k, _q in sorted(detail, key=lambda x: -x[2]):
        md.append('| %s | %s | %d | %d | %d |' % (set_type, slot, n, k, n - k))
    by_set = Counter(it.get('setType') for it, _ in keep)
    md.append('\n## 保留件按套装\n')
    md.append('| 套装 | 保留件数 |')
    md.append('|---|---|')
    for k, v in by_set.most_common():
        md.append('| %s | %d |' % (k, v))
    with io.open(os.path.join(args.outdir, 'four_star_report.md'), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(md) + '\n')

    print('四星未装备 %d ｜保留 %d ｜可清理 %d ｜已装备排除 %d' % (len(low), len(keep), len(drop), equipped))
    print('保留按套装:', dict(Counter(it.get('setType') for it, _ in keep).most_common()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
