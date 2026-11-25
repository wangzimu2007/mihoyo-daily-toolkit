# -*- coding: utf-8 -*-
"""把 BetterGI OCRArtifacts 的扫描日志解析成结构化清单。

输入：D:\\software\\BetterGI\\User\\JsScript\\OCRArtifacts\\records\\artifact_log_*.txt
输出：同目录 artifacts.json（schema 兼容 score_artifacts.py）

用法：
    python parse_artifact_log.py [日志目录] [-o 输出路径] [--latest]

容错要点（2026-11-24 补）：
  * 主词条容错：日志里可能写「水元素伤害加成」，统一去掉「加成」再匹配
  * 部位/主词条允许中间夹 OCR 噪音行（如单独一个「可」）
  * 副词条允许丢「·」前缀
"""
import argparse
import glob
import io
import json
import os
import re
import sys

BGI_HOME = os.environ.get('BGI_HOME', r'D:\software\BetterGI')

SLOTS = ['生之花', '死之羽', '时之沙', '空之杯', '理之冠']
MAIN_ATTRS = ['生命值', '攻击力', '防御力', '元素精通', '元素充能效率', '暴击率', '暴击伤害',
              '治疗加成', '物理伤害', '火元素伤害', '水元素伤害', '冰元素伤害', '雷元素伤害',
              '风元素伤害', '岩元素伤害', '草元素伤害']
ATTR_NAMES = ['生命值', '元素精通', '暴击率', '暴击伤害', '防御力', '攻击力', '元素充能效率']

STAR_3_SETS = {'冒险家', '幸运儿', '游医'}
STAR_4_SETS = {'祭水之人', '祭火之人', '祭雷之人', '祭冰之人', '学士', '赌徒', '武人', '战狂',
               '流放者', '行者之心', '奇迹', '守护之心', '勇士之心', '教官'}

BLOCK_RE = re.compile(r'={10,}第\d+个圣遗物信息:')
LV_RE = re.compile(r'^\+(\d{1,2})$')
SUB_RE = re.compile(r'^(生命值|元素精通|暴击率|暴击伤害|防御力|攻击力|元素充能效率)\+[\d.]+%?$')


def normalize_main(s):
    s = str(s).strip()
    # 「水元素伤害加成」→「水元素伤害」；但「治疗加成」的「加成」不能删
    if s.endswith('伤害加成'):
        s = s[:-2]
    return s


def guess_star(set_type, lv):
    if set_type in STAR_3_SETS:
        return 3
    if set_type in STAR_4_SETS:
        return 4
    if lv is not None and lv >= 17:
        return 5
    return 5


def star_by_main_val(slot, main_val):
    try:
        v = float(str(main_val).replace(',', '').rstrip('%'))
    except ValueError:
        return None
    if slot == '生之花':
        return 5 if v >= 600 else 4
    if slot == '死之羽':
        return 5 if v >= 42 else 4
    return None


def parse_block(block):
    lines = [l.strip() for l in block.splitlines() if l.strip()]
    if len(lines) < 5:
        return None

    # 1) 找部位行（前 6 行内），允许前面夹噪音
    slot_idx = None
    for i, l in enumerate(lines[:6]):
        if l in SLOTS and i >= 1:
            slot_idx = i
            break
    if slot_idx is None:
        return None
    name = lines[slot_idx - 1]
    slot = lines[slot_idx]

    # 2) 部位之后 4 行内找主词条（跳过「可」这类噪音）
    main_idx = None
    main = ''
    for i in range(slot_idx + 1, min(slot_idx + 5, len(lines))):
        cand = normalize_main(lines[i])
        if cand in MAIN_ATTRS:
            main_idx = i
            main = cand
            break
    if main_idx is None:
        return None
    main_val = lines[main_idx + 1] if main_idx + 1 < len(lines) else ''

    # 3) 主词条之后：等级 / 副词条 / 套装名
    lv = None
    subs = []
    set_type = None
    equip = ''
    for l in lines[main_idx + 2:]:
        m = LV_RE.match(l)
        if m:
            lv = int(m.group(1))
            continue
        if l.startswith('·'):
            subs.append(l.lstrip('·').strip())
            continue
        if SUB_RE.match(l):
            subs.append(l)          # 丢了「·」前缀的情况
            continue
        if '已装备' in l:
            equip = l.replace('已装备', '').strip()
            continue
        if set_type is None and (l.endswith('：') or l.endswith(':')):
            cand = re.sub(r'[:：]', '', l).strip()
            if 2 <= len(cand) <= 12:
                set_type = cand
    if set_type is None:
        set_type = ''

    attrs = []
    for s in subs:
        for a in ATTR_NAMES:
            if a in s:
                m = re.search(r'\+([\d.]+)(%?)', s)
                if not m:
                    continue
                val = m.group(1) + ('%' if m.group(2) else '')
                d = {a: val}
                if m.group(2):
                    d['isPercent'] = True
                attrs.append(d)
                break

    star = guess_star(set_type, lv)
    sv = star_by_main_val(slot, main_val)
    if sv is not None:
        star = sv
    return {
        'name': name, 'slot': slot, 'main': main, 'mainVal': main_val,
        'lv': lv, 'star': star, 'setType': set_type, 'equip': equip, 'attr': attrs,
    }


def signature(a):
    subs = sorted('%s%s' % (k, v) for d in a['attr'] for k, v in d.items() if k != 'isPercent')
    return '|'.join([a['setType'], a['name'], a['slot'], a['main'], str(a['mainVal']),
                     str(a['lv']), ','.join(subs)])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('logdir', nargs='?',
                    default=r'D:\software\BetterGI\User\JsScript\OCRArtifacts\records')
    ap.add_argument('-o', '--out', default=None)
    ap.add_argument('--latest', action='store_true', help='只解析最新一份日志（当前背包快照）')
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.logdir, 'artifact_log_*.txt')))
    if args.latest and files:
        files = [max(files, key=os.path.getmtime)]
    if not files:
        print('没找到日志文件：%s' % args.logdir)
        return 1

    seen = {}
    stats = []
    for f in files:
        raw = io.open(f, encoding='utf-8', errors='replace').read()
        blocks = BLOCK_RE.split(raw)[1:]
        ok = 0
        for b in blocks:
            a = parse_block(b)
            if not a:
                continue
            ok += 1
            sig = signature(a)
            if sig not in seen:
                seen[sig] = a
        stats.append((os.path.basename(f), len(blocks), ok))

    items = list(seen.values())
    out = args.out or os.path.join(args.logdir, 'artifacts.json')
    with io.open(out, 'w', encoding='utf-8') as fh:
        json.dump(items, fh, ensure_ascii=False, indent=1)

    print('解析日志 %d 份：' % len(files))
    for name, total, ok in stats:
        print('  %-32s 块 %4d → 解析 %4d（失败 %d）' % (name, total, ok, total - ok))
    print('合并去重后：%d 件' % len(items))
    from collections import Counter
    print('  星级分布:', dict(sorted(Counter(i['star'] for i in items).items())))
    print('  部位分布:', dict(Counter(i['slot'] for i in items)))
    print('  输出:', out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
