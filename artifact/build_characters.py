# -*- coding: utf-8 -*-
"""从「已装备的圣遗物」反推每个角色的配装画像，生成/更新 characters.yaml。

输入：artifacts.json（含 equip 字段）
输出：characters.yaml

思路：不手写 92 条规则，而是从账号实际数据推断角色类型与常用套装，
      再按类型套用「主词条白名单 + 副词条权重」模板；手工校准项写在 overrides。
用法：
    python build_characters.py [--force]
"""
import argparse
import glob
import io
import json
import os
import sys

BGI_HOME = os.environ.get('BGI_HOME', r'D:\software\BetterGI')
from collections import Counter, defaultdict

import yaml

ELEM_CUPS = ['火元素伤害', '水元素伤害', '冰元素伤害', '雷元素伤害',
             '风元素伤害', '岩元素伤害', '草元素伤害', '物理伤害']

# 各类型的模板：主词条白名单 + 副词条权重 + 单件最低分 + 每部位保留上限
TEMPLATES = {
    'crit': {
        'mains': {
            '时之沙': ['攻击力%', '生命值%', '防御力%', '元素精通', '元素充能效率'],
            '空之杯': ['攻击力%'] + ELEM_CUPS,
            '理之冠': ['暴击率', '暴击伤害', '攻击力%', '元素精通'],
        },
        'weights': {'暴击率': 1.0, '暴击伤害': 1.0, '攻击力%': 0.6,
                    '元素充能效率': 0.4, '元素精通': 0.3, '生命值%': 0.2, '防御力%': 0.2},
        'min_score': 3.0, 'keep_per_slot': 3,
    },
    'atk': {
        'mains': {
            '时之沙': ['攻击力%'],
            '空之杯': ['攻击力%'] + ELEM_CUPS,
            '理之冠': ['攻击力%', '暴击率', '暴击伤害'],
        },
        'weights': {'攻击力%': 1.0, '暴击率': 0.7, '暴击伤害': 0.7,
                    '元素充能效率': 0.5, '元素精通': 0.3},
        'min_score': 3.0, 'keep_per_slot': 3,
    },
    'hp': {
        'mains': {
            '时之沙': ['生命值%', '元素充能效率'],
            '空之杯': ['生命值%', '元素精通'],
            '理之冠': ['生命值%', '治疗加成', '暴击率', '暴击伤害'],
        },
        'weights': {'生命值%': 1.0, '元素充能效率': 0.6, '元素精通': 0.3,
                    '暴击率': 0.2, '暴击伤害': 0.2},
        'min_score': 3.0, 'keep_per_slot': 3,
    },
    'em': {
        'mains': {
            '时之沙': ['元素精通', '元素充能效率'],
            '空之杯': ['元素精通'],
            '理之冠': ['元素精通', '暴击率', '暴击伤害'],
        },
        'weights': {'元素精通': 1.0, '元素充能效率': 0.7, '暴击率': 0.2, '暴击伤害': 0.2},
        'min_score': 3.0, 'keep_per_slot': 3,
    },
    'def': {
        'mains': {
            '时之沙': ['防御力%', '元素充能效率'],
            '空之杯': ['防御力%'],
            '理之冠': ['防御力%', '暴击率', '暴击伤害'],
        },
        'weights': {'防御力%': 1.0, '元素充能效率': 0.5, '暴击率': 0.3, '暴击伤害': 0.3},
        'min_score': 3.0, 'keep_per_slot': 3,
    },
    'heal': {
        'mains': {
            '时之沙': ['元素充能效率', '生命值%', '攻击力%'],
            '空之杯': ['生命值%', '攻击力%'],
            '理之冠': ['治疗加成', '生命值%'],
        },
        'weights': {'生命值%': 0.8, '元素充能效率': 0.9, '攻击力%': 0.5, '元素精通': 0.3},
        'min_score': 2.5, 'keep_per_slot': 3,
    },
    'aux': {
        'mains': {
            '时之沙': ['元素充能效率', '攻击力%', '生命值%', '元素精通'],
            '空之杯': ['攻击力%', '生命值%', '元素精通'] + ELEM_CUPS,
            '理之冠': ['暴击率', '暴击伤害', '攻击力%', '生命值%', '治疗加成'],
        },
        'weights': {'元素充能效率': 0.8, '攻击力%': 0.6, '元素精通': 0.6,
                    '暴击率': 0.5, '暴击伤害': 0.5, '生命值%': 0.4},
        'min_score': 2.5, 'keep_per_slot': 3,
    },
}

# 手工校准：这些角色按攻略口径修正（键为中文名）
OVERRIDES = {
    '枫原万叶': {'role': 'em', 'weights': {'元素精通': 1.0, '元素充能效率': 0.9}, 'min_score': 2.0},
    '纳西妲': {'role': 'em', 'weights': {'元素精通': 1.0, '元素充能效率': 0.4}, 'min_score': 2.0},
    '珊瑚宫心海': {'role': 'hp', 'weights': {'生命值%': 1.0, '元素充能效率': 0.6}, 'min_score': 2.0},
    '妮露': {'role': 'hp', 'weights': {'生命值%': 1.0, '元素精通': 0.6}, 'min_score': 2.0},
    '钟离': {'role': 'hp', 'weights': {'生命值%': 1.0, '元素充能效率': 0.5}},
    '班尼特': {'role': 'heal', 'weights': {'元素充能效率': 1.0, '生命值%': 0.6}},
    '胡桃': {'role': 'crit', 'weights': {'暴击率': 1.0, '暴击伤害': 1.0, '生命值%': 0.7, '元素精通': 0.4}},
    '雷电将军': {'role': 'crit', 'weights': {'元素充能效率': 0.9, '暴击率': 1.0, '暴击伤害': 1.0, '攻击力%': 0.5}},
    '香菱': {'role': 'crit', 'weights': {'元素充能效率': 0.8, '暴击率': 1.0, '暴击伤害': 1.0, '元素精通': 0.5}},
    '行秋': {'role': 'crit', 'weights': {'元素充能效率': 0.9, '暴击率': 1.0, '暴击伤害': 1.0, '攻击力%': 0.5}},
    '夜兰': {'role': 'hp', 'weights': {'生命值%': 1.0, '暴击率': 0.8, '暴击伤害': 0.8, '元素充能效率': 0.6}},
    '那维莱特': {'role': 'hp', 'weights': {'生命值%': 1.0, '暴击率': 0.9, '暴击伤害': 0.9}},
    '千织': {'role': 'def', 'weights': {'防御力%': 1.0, '暴击率': 0.8, '暴击伤害': 0.8}},
    '希诺宁': {'role': 'def', 'weights': {'防御力%': 1.0, '元素充能效率': 0.5}},
    '阿蕾奇诺': {'role': 'crit', 'weights': {'暴击率': 1.0, '暴击伤害': 1.0, '攻击力%': 0.7, '元素精通': 0.3}},
    '芙宁娜': {'role': 'hp', 'weights': {'生命值%': 1.0, '元素充能效率': 0.8}},
}


def infer_role(mains, subs):
    if mains.get('元素精通', 0) >= 2:
        return 'em'
    if mains.get('治疗加成', 0) >= 1:
        return 'heal'
    if mains.get('元素充能效率', 0) >= 2:
        return 'aux'
    if mains.get('防御力', 0) >= 2:
        return 'def'
    if mains.get('生命值', 0) >= 3:
        return 'hp'
    if mains.get('暴击率', 0) + mains.get('暴击伤害', 0) >= 1:
        return 'crit'
    if mains.get('攻击力', 0) >= 2:
        return 'atk'
    return 'aux'


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('--artifacts', default=os.path.join(BGI_HOME, 'User', 'JsScript', 'OCRArtifacts', 'records', 'artifacts.json'))
    ap.add_argument('-o', '--out', default=os.path.join(here, 'characters.yaml'))
    ap.add_argument('--force', action='store_true', help='覆盖已有 characters.yaml')
    args = ap.parse_args()

    if os.path.exists(args.out) and not args.force:
        print('characters.yaml 已存在（用 --force 覆盖）：%s' % args.out)
        return 0

    items = json.load(io.open(args.artifacts, encoding='utf-8'))
    by = defaultdict(list)
    for it in items:
        e = (it.get('equip') or '').strip()
        if e:
            by[e].append(it)

    chars = {}
    for name, lst in sorted(by.items()):
        mains = Counter(x.get('main') for x in lst)
        sets = Counter(x.get('setType') for x in lst if x.get('setType'))
        role = infer_role(mains, Counter())
        tpl = TEMPLATES[role]
        entry = {
            'role': role,
            'equipped': len(lst),
            'sets': [s for s, n in sets.most_common(2) if n >= 2],
            'mains': {k: list(v) for k, v in tpl['mains'].items()},
            'weights': dict(tpl['weights']),
            'min_score': tpl['min_score'],
            'keep_per_slot': tpl['keep_per_slot'],
        }
        ov = OVERRIDES.get(name)
        if ov:
            entry['role'] = ov.get('role', entry['role'])
            if 'weights' in ov:
                entry['weights'] = dict(ov['weights'])
            if 'min_score' in ov:
                entry['min_score'] = ov['min_score']
            if 'sets' in ov:
                entry['sets'] = ov['sets']
            entry['tuned'] = True
        chars[name] = entry

    doc = {
        'version': 1,
        'note': '角色画像：由已装备圣遗物自动推断，OVERRIDES 里手工校准。可自行改权重/主词条/上限。',
        'characters': chars,
    }
    with io.open(args.out, 'w', encoding='utf-8') as fh:
        fh.write('# 角色画像（自动生成，可手工微调）\n')
        fh.write('# role: crit 双暴 / atk 攻击 / hp 生命 / em 精通 / def 防御 / heal 治疗 / aux 辅助\n')
        fh.write('# mains: 各部位可接受的主词条；weights: 副词条权重；min_score: 单件最低分；keep_per_slot: 每部位保留上限\n\n')
        yaml.safe_dump(doc, fh, allow_unicode=True, sort_keys=False, width=200)

    print('生成角色画像 %d 个 → %s' % (len(chars), args.out))
    from collections import Counter as C
    print('类型分布:', dict(C(v['role'] for v in chars.values())))
    return 0


if __name__ == '__main__':
    sys.exit(main())
