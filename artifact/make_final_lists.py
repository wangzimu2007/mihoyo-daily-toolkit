# -*- coding: utf-8 -*-
"""生成最终交付物：可安全分解清单 + 保留清单 + 游戏内锁定方案。

口径：
  * 5★：保留 = 规则法判留 或 分配法有主；分解候选 = 规则判分 且 无人可用（双条件）
  * 4★/3★：分配器不参与（只处理 5★），沿用规则法的 four_star_keep 判断
  * 已装备的件：视为在用，单独归入 keep（不参与分解）

输出（默认 ./final）：
    keep_final.csv          最终保留（含来源标记与理由）
    salvage_5star.csv       5★ 可安全分解（双条件）
    salvage_lowstar.csv     4★/3★ 可分解
    lock_scheme.md          按套装的游戏内「圣遗物锁定方案」建议
    SUMMARY.md              总览
"""
import argparse
import csv
import io
import os
import sys

BGI_HOME = os.environ.get('BGI_HOME', r'D:\software\BetterGI')
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))


def load_csv(p):
    return list(csv.DictReader(io.open(p, encoding='utf-8-sig')))


def key_of(r):
    return (r['slot'], r['main'], r['mainVal'], r['lv'], r['subs'])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default=os.path.join(HERE, 'output'))
    ap.add_argument('-o', '--outdir', default=os.path.join(HERE, 'final'))
    args = ap.parse_args()

    scored = load_csv(os.path.join(args.dir, 'artifacts_scored.csv'))
    assigned = load_csv(os.path.join(args.dir, 'assigned.csv'))
    unassigned = load_csv(os.path.join(args.dir, 'unassigned.csv'))

    asg_keys = {key_of(r) for r in assigned}
    una_keys = {key_of(r) for r in unassigned}

    if not os.path.isdir(args.outdir):
        os.makedirs(args.outdir)

    keep, salv5, salv_low, note_equipped = [], [], [], 0
    for r in scored:
        k = key_of(r)
        star = int(r['star'] or 5)
        equipped = bool((r.get('equip') or '').strip())
        if equipped:
            note_equipped += 1
            keep.append({**r, 'final': '留', 'why': '已装备在用'})
            continue
        if star < 5:
            if r['keep'] == '留':
                keep.append({**r, 'final': '留', 'why': '四星规则/' + r['reason']})
            else:
                salv_low.append({**r, 'final': '分', 'why': r['reason']})
            continue
        rule_keep = r['keep'] == '留'
        has_owner = k in asg_keys
        nobody = k in una_keys
        if rule_keep or has_owner:
            keep.append({**r, 'final': '留', 'why': '规则留' if rule_keep else '有角色可用'})
        elif nobody:
            salv5.append({**r, 'final': '分', 'why': '规则分+无人用'})
        else:
            # 既不在分配表里（可能 star 判定或数据错位）→ 保守保留
            keep.append({**r, 'final': '留', 'why': '数据未覆盖-保守保留'})

    fields = ['final', 'why', 'set', 'slot', 'main', 'mainVal', 'lv', 'star', 'equip', 'dual', 'rolls', 'tier', 'subs']

    def dump(path, rows):
        with io.open(path, 'w', encoding='utf-8-sig', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=fields)
            w.writeheader()
            for r in rows:
                w.writerow({k: r.get(k) for k in fields})

    dump(os.path.join(args.outdir, 'keep_final.csv'), keep)
    dump(os.path.join(args.outdir, 'salvage_5star.csv'), salv5)
    dump(os.path.join(args.outdir, 'salvage_lowstar.csv'), salv_low)

    # 锁定方案：按套装汇总保留件的条件（花/羽主词条固定，不列主词条条件）
    by_set = defaultdict(lambda: {'n': 0, 'mains': Counter(), 'subs': Counter(),
                                  'flower_feather': 0})
    for r in keep:
        s = r['set'] or '(无套装)'
        g = by_set[s]
        g['n'] += 1
        if r['slot'] in ('生之花', '死之羽'):
            g['flower_feather'] += 1
        else:
            g['mains'][r['main']] += 1
        for part in (r['subs'] or '').split(';'):
            name = part.split('+')[0].strip()
            if name:
                g['subs'][name] += 1

    md = ['# 游戏内「圣遗物锁定方案」建议\n',
          '用法：游戏 → 背包 → 圣遗物 → 锁定 → 新建方案，按下面的「主词条」勾选；',
          '没有逐条锁定功能的套装，用「追加属性包含任意 2 条」兜底。\n']
    md.append('| 套装 | 保留件数 | 主要主词条（按件数） | 建议锁定条件 |')
    md.append('|---|---|---|---|')
    for s, g in sorted(by_set.items(), key=lambda kv: -kv[1]['n']):
        mains = '、'.join('%s×%d' % (k, v) for k, v in g['mains'].most_common(5))
        top_mains = [k for k, v in g['mains'].most_common(6)]
        parts = []
        if top_mains:
            parts.append('沙/杯/冠 主词条 ∈ {' + '、'.join(top_mains) + '}')
        if g['flower_feather']:
            parts.append('花/羽 %d 件（主词条固定，按副词条锁）' % g['flower_feather'])
        parts.append('副词条含 暴击率/暴击伤害/元素充能效率/元素精通 任意 2 条')
        md.append('| %s | %d | %s | %s |' % (s, g['n'], mains or '—', '；'.join(parts)))
    with io.open(os.path.join(args.outdir, 'lock_scheme.md'), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(md) + '\n')

    summary = ['# 圣遗物整理 · 最终结论\n']
    summary.append('- 总件数：%d（其中已装备 %d）' % (len(scored), note_equipped))
    summary.append('- **最终保留：%d 件**' % len(keep))
    summary.append('- **5★ 可安全分解：%d 件**' % len(salv5))
    summary.append('- **4★/3★ 可分解：%d 件**' % len(salv_low))
    summary.append('')
    summary.append('## 保留构成\n')
    summary.append('| 来源 | 件数 |')
    summary.append('|---|---|')
    for k, v in Counter(r['why'] for r in keep).most_common():
        summary.append('| %s | %d |' % (k, v))
    summary.append('')
    summary.append('## 分解候选的档位分布\n')
    summary.append('| 档位 | 件数 |')
    summary.append('|---|---|')
    for k, v in Counter(r['tier'] for r in salv5).most_common():
        summary.append('| %s | %d |' % (k, v))
    with io.open(os.path.join(args.outdir, 'SUMMARY.md'), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(summary) + '\n')

    print('保留 %d ｜5★可分解 %d ｜4★/3★可分解 %d ｜已装备 %d' % (len(keep), len(salv5), len(salv_low), note_equipped))
    print('输出目录:', args.outdir)
    return 0


if __name__ == '__main__':
    sys.exit(main())
