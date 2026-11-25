# -*- coding: utf-8 -*-
"""把社区推荐（community_sets.yaml）合并进 characters.yaml。

community_sets.yaml 结构（手填或调研产出）：
    雷电将军:
      sets: [绝缘之旗印]
      mains: {时之沙: [元素充能效率, 攻击力%], 空之杯: [雷元素伤害, 攻击力%], 理之冠: [暴击率, 暴击伤害]}
      weights: {元素充能效率: 0.9, 暴击率: 1.0, 暴击伤害: 1.0, 攻击力%: 0.5}
      er: 200                # 可选，仅做记录
      note: 绝缘四件 + 充能沙
      confidence: 多来源一致

规则：
  * 只覆盖提供的字段（sets/mains/weights/min_score），其余保留
  * 标记 source: community + confidence，便于区分「数据推断」和「社区推荐」
用法：
    python apply_community_sets.py [--apply]
"""
import argparse
import io
import os
import shutil
import sys

BGI_HOME = os.environ.get('BGI_HOME', r'D:\software\BetterGI')

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-c', '--characters', default=os.path.join(HERE, 'characters.yaml'))
    ap.add_argument('-m', '--community', default=os.path.join(HERE, 'community_sets.yaml'))
    ap.add_argument('--apply', action='store_true', help='真正写入（否则只预览）')
    args = ap.parse_args()

    if not os.path.exists(args.community):
        print('缺少 %s' % args.community)
        return 1

    doc = yaml.safe_load(io.open(args.characters, encoding='utf-8'))
    comm = yaml.safe_load(io.open(args.community, encoding='utf-8'))
    chars = doc['characters']

    changed, missing = [], []
    for name, rec in comm.items():
        if name not in chars:
            missing.append(name)
            continue
        cfg = chars[name]
        if rec.get('mains'):
            cfg['mains_fallback'] = cfg.get('mains')   # 模板词条作兜底（低优先）
            cfg['mains'] = rec['mains']
        for k in ('sets', 'weights', 'min_score', 'keep_per_slot'):
            if k in rec and rec[k] is not None:
                cfg[k] = rec[k]
        cfg['source'] = 'community'
        if 'confidence' in rec:
            cfg['confidence'] = rec['confidence']
        if 'note' in rec:
            cfg['note'] = rec['note']
        if 'er' in rec:
            cfg['er'] = rec['er']
        changed.append(name)

    print('将更新 %d 个角色：%s' % (len(changed), '、'.join(changed[:20])))
    if missing:
        print('⚠ characters.yaml 里没有这些角色（跳过）：%s' % '、'.join(missing))

    if not args.apply:
        print('（预览模式，未写入；加 --apply 生效）')
        return 0

    bak = args.characters + '.bak'
    shutil.copyfile(args.characters, bak)
    with io.open(args.characters, 'w', encoding='utf-8') as fh:
        fh.write('# 角色画像（数据推断 + 社区推荐校准）\n')
        fh.write('# source: data = 从已装备反推；community = 社区推荐覆盖过\n\n')
        yaml.safe_dump(doc, fh, allow_unicode=True, sort_keys=False, width=200)
    print('已写入 %s（备份 %s）' % (args.characters, bak))
    return 0


if __name__ == '__main__':
    sys.exit(main())
