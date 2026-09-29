"""Test an automatic set rule on the offers table (EquipSetButton_offers.log from a recon build).

Rule: the game lists each release's player cards and capes, then its armor+helmet pairs. Walking the table,
capes and cards collect in order; when a run of armor/helmet pairs follows, the k-th pending cape and the
k-th pending card go to the k-th pair. Pending items are cleared after each run of pairs.

The truth for checking: developer names (armor_/helmet_/cape_/banner_warbond_<group>_<n>).
Usage: python infer_offer_sets.py <armor_sets.json> <EquipSetButton_offers.log>
"""
import collections
import json
import re
import struct
import sys

from crack_kit_names import thin

SLOT = {'Helmet': 'h', 'Armor': 'b', 'Cape': 'c'}


def load(kits_path, offers_path):
    kits = {}
    truth = {}
    for k in json.load(open(kits_path, encoding='utf-8')):
        i = int(k['id'], 16) if k['id'].startswith('0x') else thin(k['id'])
        kits[i] = (SLOT[k['kit_type']], k['name'])
        m = re.fullmatch(r'(armor|helmet|cape)_warbond_(.+)', k['id'])
        if m:
            truth[i] = m.group(2)
            truth[thin('banner_warbond_' + m.group(2))] = m.group(2)
    rows = []
    for line in open(offers_path, encoding='utf-8'):
        if line.startswith('#'):
            continue
        i, e, _, s = line.split()
        e, s = bytes.fromhex(e), bytes.fromhex(s)
        item, kind = struct.unpack_from('<I', e, 8)[0], struct.unpack_from('<I', s, 12)[0]
        slot = kits[item][0] if item in kits else ('p' if kind == 9 else None)
        rows.append((int(i), item, slot))
    return kits, truth, rows


def infer(rows):
    groups, pending, pairs = [], {'c': [], 'p': []}, []
    i = 0
    while i < len(rows):
        _, item, slot = rows[i]
        if slot in ('c', 'p'):
            pending[slot].append(item)
            i += 1
            continue
        if slot in ('b', 'h'):
            run = []
            while i < len(rows) and rows[i][2] in ('b', 'h'):
                run.append(rows[i])
                i += 1
            members = [[r[1] for r in run[j:j + 2]] for j in range(0, len(run), 2)]
            for k, pair in enumerate(members):
                group = list(pair)
                for s in ('c', 'p'):
                    if k < len(pending[s]):
                        group.append(pending[s][k])
                groups.append(group)
            pending = {'c': [], 'p': []}
            continue
        i += 1
    return groups


def main():
    kits, truth, rows = load(sys.argv[1], sys.argv[2])
    groups = infer(rows)
    right = wrong = 0
    wrong_list = []
    for g in groups:
        keys = {truth.get(x) for x in g if x in truth}
        body = next((x for x in g if kits.get(x, ('',))[0] in 'bh'), None)
        if body in truth:
            extra = [x for x in g if kits.get(x, ('p',))[0] in 'cp']
            if all(truth.get(x) == truth[body] for x in extra) and extra:
                right += 1
            elif extra:
                wrong += 1
                wrong_list.append([kits.get(x, ('p', '%08x' % x))[1] for x in g])
    print('warbond groups checked against names: %d right, %d wrong' % (right, wrong))
    for w in wrong_list:
        print('  WRONG', w)
    print('Groups with capes/cards for kits without developer names:')
    for g in groups:
        if not any(x in truth for x in g) and len(g) > 2:
            print('  ', ' | '.join(kits[x][1] if x in kits else 'card %08x' % x for x in g))


if __name__ == '__main__':
    main()
