"""Derive armor sets from the game's customization kit table.

Input: the JSON written by FileDiver's armor-set-json-dumper
  (go run ./cmd/tools/components/armor-set-json-dumper > _research/equip_set/armor_sets.json)
Output: a review list of sets (stdout, or --out FILE).

Rules found so far (build 25480438):
  - A helmet and a body of one set share dlc_id (and, when released, the same name).
  - A cape belongs to a set only when it shares a dlc_id with its body, or shares a nonzero set_id
    that isn't the catch-all set (0 holds 105 loose capes, 934502665 holds default/NPC kits).
  - Kits whose name is an unresolved hash are unreleased or internal; the ownership check at runtime
    drops them anyway, so they're listed separately here.
Player cards aren't in this table.
"""
import argparse, collections, json, re, sys

CATCH_ALL_SETS = {0, 934502665}
SLOT = {'Helmet': 'helmet', 'Armor': 'body', 'Cape': 'cape'}


def unnamed(kit):
    return re.fullmatch(r'[0-9a-f]{5,8}', kit['name']) is not None


def derive(kits):
    by_dlc = collections.defaultdict(list)
    for k in kits:
        by_dlc[k['dlc_id']].append(k)
    sets = []
    for dlc, group in by_dlc.items():
        if dlc == 0:
            continue
        slots = collections.defaultdict(list)
        for k in group:
            slots[SLOT[k['kit_type']]].append(k)
        sets.append({'dlc_id': dlc, 'set_id': group[0]['set_id'], 'slots': slots, 'source': 'dlc_id'})
    # Capes linked only through a bundle set_id.
    by_set = collections.defaultdict(list)
    for s in sets:
        by_set[s['set_id']].append(s)
    for s in sets:
        if s['slots'].keys() == {'cape'} and s['set_id'] not in CATCH_ALL_SETS:
            partners = [o for o in by_set[s['set_id']] if o is not s and 'body' in o['slots']]
            if len(partners) == 1:
                partners[0]['slots']['cape'] += s['slots']['cape']
                partners[0]['source'] += '+set_id cape'
                s['merged'] = True
    return [s for s in sets if not s.get('merged')]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('kits_json')
    ap.add_argument('--out')
    a = ap.parse_args()
    kits = json.load(open(a.kits_json, encoding='utf-8'))
    sets = derive(kits)
    lines, counts = [], collections.Counter()
    for s in sorted(sets, key=lambda s: min(k['name'] for v in s['slots'].values() for k in v)):
        items = [k for v in s['slots'].values() for k in v]
        named = [k for k in items if not unnamed(k)]
        kind = '+'.join(sorted(s['slots']))
        if not named:
            counts['internal'] += 1
            continue
        multi = len(items) >= 2
        counts[('set ' if multi else 'solo ') + kind] += 1
        lines.append('%-5s %-22s dlc=%-10d set=%-10d %s' % (
            'SET' if multi else 'solo', kind, s['dlc_id'], s['set_id'],
            ' | '.join('%s:%s[%s]' % (SLOT[k['kit_type']], k['name'], k['id']) for k in items)))
    text = '\n'.join(['# ' + ', '.join('%s=%d' % kv for kv in sorted(counts.items()))] + lines) + '\n'
    (open(a.out, 'w', encoding='utf-8') if a.out else sys.stdout).write(text)


if __name__ == '__main__':
    main()
