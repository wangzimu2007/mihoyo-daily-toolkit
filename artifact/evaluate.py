# -*- coding: utf-8 -*-
"""按规则给圣遗物打分分级，输出「保留清单 / 分解候选 / 报告」。

输入：artifacts.json（parse_artifact_log.py 产出）+ rules.yaml
输出（默认 ./output）：
    artifacts_scored.csv   全部件数明细
    keep.csv               建议保留
    salvage.csv            建议分解（仅供人工复核，绝不自动执行）
    report.md              汇总报告

口径：
  * 双暴分 = 暴击率*2 + 暴击伤害
  * 有效词条数 = Σ(副词条数值 / 该词条单次强化最大期望)，只累计「有效词条」
  * 判定顺序见 rules.yaml 顶部注释
"""
import argparse
import csv
import io
import json
import os
import sys

BGI_HOME = os.environ.get('BGI_HOME', r'D:\software\BetterGI')
from collections import Counter

import yaml

PERCENT_ATTRS = {'攻击力', '生命值', '防御力'}


def load_rules(path):
    with io.open(path, encoding='utf-8') as fh:
        return yaml.safe_load(fh)


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


def roll_count(attrs, useful, roll_max):
    total = 0.0
    for k, v in attrs.items():
        if k not in useful:
            continue
        base = k[:-1] if k.endswith('%') else k
        mx = roll_max.get(base) or roll_max.get(k)
        if not mx:
            continue
        total += v / float(mx)
    return round(total, 1)


def tier_of(score, tiers):
    for name in ('S', 'A', 'B'):
        if score >= float(tiers[name]):
            return name
    return 'C'


def evaluate(items, rules):
    roll_max = rules['roll_max']
    useful_generic = set(rules.get('useful_generic') or [])
    gate = rules.get('main_gate') or {}
    scarce = gate.get('无条件保留') or {}
    gated = gate.get('需要评分达标') or {}
    min_rolls = float(gated.get('min_rolls', 2.5))
    sets_cfg = rules.get('sets') or {}
    never_keep = set(rules.get('never_keep_sets') or [])
    always_keep = set(rules.get('always_keep_sets') or [])
    low_star = set(rules.get('low_star_sets') or [])
    min_star = int(rules.get('salvage_below_star') or 1)
    relax_sets = set(rules.get('relax_sets') or [])
    relax_min = float(rules.get('relax_min_rolls') or 0)
    dual_min = float(rules.get('keep_dual_min') or 1e9)
    four_star_keep = rules.get('four_star_keep') or {}
    support_sets = set(rules.get('support_sets') or [])
    support_subs = list(rules.get('support_keep_subs') or [])
    er_min = float(rules.get('support_er_min_rolls') or 0) * float(roll_max.get('元素充能效率', 6.48))
    default_cfg = four_star_keep.get('_default')
    tiers = rules['tiers']

    rows = []
    for it in items:
        attrs = norm_attrs(it)
        set_type = it.get('setType') or ''
        slot = it.get('slot') or ''
        mainv = main_attr(it)
        cfg = sets_cfg.get(set_type) or {}
        useful = set(cfg.get('useful') or []) | useful_generic
        score = roll_count(attrs, useful, roll_max)
        tier = tier_of(score, tiers)
        cr = attrs.get('暴击率', 0.0)
        cd = attrs.get('暴击伤害', 0.0)

        try:
            star = int(it.get('star') or 5)
        except (TypeError, ValueError):
            star = 5
        try:
            lv_num = int(it.get('lv') or 0)
        except (TypeError, ValueError):
            lv_num = 0
        if set_type in never_keep:
            keep, reason = False, 'never_keep_set'
        elif set_type in always_keep:
            keep, reason = True, 'always_keep_set'
        elif star < min_star or set_type in low_star:
            keep, reason = False, 'low_star_item'
        elif mainv in (scarce.get(slot) or []):
            keep, reason = True, 'main_scarce'
        # 辅助套的充能 / 套装必留词条，必须排在「主词条门槛」之前：
        # 否则 千岩 生命沙带充能 这类会被 main_gate_fail 抢先判分解（2026-11-24 修）
        elif (cfg.get('keep_if_any') or []) and any(k in attrs for k in cfg['keep_if_any']):
            keep, reason = True, 'set_keep_if_any'
        elif (set_type in support_sets and any(k in attrs for k in support_subs)
              and (lv_num == 0 or attrs.get('元素充能效率', 0) >= er_min)):
            keep, reason = True, 'support_er'
        elif mainv in (gated.get(slot) or []):
            if score >= min_rolls:
                keep, reason = True, 'main_gate_pass'
            else:
                keep, reason = False, 'main_gate_fail'
        elif cr * 2 + cd >= dual_min:
            keep, reason = True, 'dual_keep'
        elif set_type in relax_sets and score >= relax_min:
            keep, reason = True, 'set_relax'
        elif tier in ('S', 'A', 'B'):
            keep, reason = True, 'tier_' + tier
        else:
            keep, reason = False, 'low_score'

        rows.append({
            'set': set_type, 'name': it.get('name'), 'slot': slot,
            'main': mainv, 'mainVal': it.get('mainVal'), 'lv': it.get('lv'),
            'star': it.get('star'), 'equip': it.get('equip') or '',
            'dual': round(cr * 2 + cd, 1), 'rolls': score, 'tier': tier,
            'keep': '留' if keep else '分', 'reason': reason,
            'subs': '; '.join('%s+%s' % (k, v) for k, v in attrs.items()),
            '_attrs': attrs,
        })

    # 四星例外：教官/流放者等按部位限量保留（覆盖上面的低星判定）
    if four_star_keep:
        buckets = {}
        for r in rows:
            cfg = four_star_keep.get(r['set'])
            if not cfg:
                continue
            hit_main = r['main'] in (cfg.get('mains') or [])
            hit_sub = any(k in r['_attrs'] for k in (cfg.get('sub_any') or []))
            if hit_main or hit_sub:
                buckets.setdefault((r['set'], r['slot']), []).append(r)
        for (set_name, slot), lst in buckets.items():
            limit = int((four_star_keep[set_name] or {}).get('max_per_slot', 3))
            lst.sort(key=lambda x: (x['rolls'], x['dual']), reverse=True)
            for i, r in enumerate(lst):
                if i < limit:
                    r['keep'], r['reason'] = '留', 'four_star_keep'
                else:
                    r['keep'], r['reason'] = '分', 'four_star_over_quota'
    for r in rows:
        r.pop('_attrs', None)
    return rows


def write_csv(path, rows, fields):
    with io.open(path, 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in fields})


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('artifacts', nargs='?',
                    default=os.path.join(BGI_HOME, 'User', 'JsScript', 'OCRArtifacts', 'records', 'artifacts.json'))
    ap.add_argument('-r', '--rules', default=os.path.join(here, 'rules.yaml'))
    ap.add_argument('-o', '--outdir', default=os.path.join(here, 'output'))
    args = ap.parse_args()

    rules = load_rules(args.rules)
    items = json.load(io.open(args.artifacts, encoding='utf-8'))
    print('载入 %d 件，规则 v%s' % (len(items), rules.get('version')))

    rows = evaluate(items, rules)
    if not os.path.isdir(args.outdir):
        os.makedirs(args.outdir)

    fields = ['set', 'name', 'slot', 'main', 'mainVal', 'lv', 'star', 'equip',
              'dual', 'rolls', 'tier', 'keep', 'reason', 'subs']
    write_csv(os.path.join(args.outdir, 'artifacts_scored.csv'), rows, fields)
    keep = [r for r in rows if r['keep'] == '留']
    salv = [r for r in rows if r['keep'] == '分']
    write_csv(os.path.join(args.outdir, 'keep.csv'), keep, fields)
    write_csv(os.path.join(args.outdir, 'salvage.csv'), salv, fields)

    tier_ct = Counter(r['tier'] for r in rows)
    reason_ct = Counter(r['reason'] for r in rows)

    md = ['# 圣遗物整理报告\n',
          '- 输入：`%s`' % args.artifacts,
          '- 规则：`%s`（v%s）' % (args.rules, rules.get('version')),
          '- 总计 **%d** 件：建议保留 **%d**、分解候选 **%d**\n' % (len(rows), len(keep), len(salv)),
          '## 分档\n', '| 档位 | 件数 |', '|---|---|']
    for t in ('S', 'A', 'B', 'C'):
        md.append('| %s | %d |' % (t, tier_ct.get(t, 0)))
    md += ['\n## 判定原因\n', '| 原因 | 件数 |', '|---|---|']
    for k, v in reason_ct.most_common():
        md.append('| %s | %d |' % (k, v))

    md += ['\n## 分解候选（按有效词条升序，仅作复核）\n',
           '| 套装 | 部位 | 主词条 | 等级 | 双暴 | 有效词条 | 副词条 |', '|---|---|---|---|---|---|---|']
    for r in sorted(salv, key=lambda x: (x['rolls'], x['dual']))[:30]:
        md.append('| %s | %s | %s %s | +%s | %s | %s | %s |' % (
            r['set'], r['slot'], r['main'], r['mainVal'], r['lv'], r['dual'], r['rolls'], r['subs']))

    fs_rows = [r for r in rows if str(r['reason']).startswith('four_star')]
    if fs_rows:
        md += ['\n## 四星例外（教官/流放者，按副词条质量排序）\n',
               '| 判定 | 套装 | 部位 | 主词条 | 等级 | 有效词条 | 双暴 | 副词条 |',
               '|---|---|---|---|---|---|---|---|']
        for r in sorted(fs_rows, key=lambda x: (x['slot'], -x['rolls'], -x['dual'])):
            md.append('| %s | %s | %s | %s %s | +%s | %s | %s | %s |' % (
                r['keep'], r['set'], r['slot'], r['main'], r['mainVal'], r['lv'],
                r['rolls'], r['dual'], r['subs']))
        md.append('')

    md += ['\n## 保留（按有效词条降序）\n',
           '| 套装 | 部位 | 主词条 | 等级 | 双暴 | 有效词条 | 原因 |', '|---|---|---|---|---|---|---|']
    for r in sorted(keep, key=lambda x: -x['rolls'])[:30]:
        md.append('| %s | %s | %s %s | +%s | %s | %s | %s |' % (
            r['set'], r['slot'], r['main'], r['mainVal'], r['lv'], r['dual'], r['rolls'], r['reason']))

    with io.open(os.path.join(args.outdir, 'report.md'), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(md) + '\n')

    print('保留 %d / 分解候选 %d' % (len(keep), len(salv)))
    print('分档:', dict(tier_ct))
    print('原因:', dict(reason_ct))
    print('输出:', args.outdir)
    return 0


if __name__ == '__main__':
    sys.exit(main())
