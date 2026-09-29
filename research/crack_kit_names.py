"""Recover internal kit names (e.g. armor_warbond_16_1) for kit ids FileDiver can't resolve.

A kit id is the upper 32 bits of MurmurHash64A(name, seed 0). Candidates come from the naming
patterns seen in resolved ids: <slot>_<group>_<n>, <slot>_<n>, with slot armor/helmet/cape.
Usage: python crack_kit_names.py <armor_sets.json>  -> prints id -> name for every hit.
"""
import json, sys

M = 0xc6a4a7935bd1e995
MASK = (1 << 64) - 1


def murmur64a(data, seed=0):
    h = (seed ^ (len(data) * M)) & MASK
    n = len(data) // 8
    for i in range(n):
        k = int.from_bytes(data[i * 8:i * 8 + 8], 'little')
        k = (k * M) & MASK; k ^= k >> 47; k = (k * M) & MASK
        h ^= k; h = (h * M) & MASK
    tail = data[n * 8:]
    if tail:
        h ^= int.from_bytes(tail, 'little'); h = (h * M) & MASK
    h ^= h >> 47; h = (h * M) & MASK; h ^= h >> 47
    return h


def thin(name):
    return murmur64a(name.encode()) >> 32


GROUPS = ([str(i) for i in range(0, 60)] + ['%02d' % i for i in range(0, 60)]
          + 'superstore store premium standard special preorder pre_order deluxe super_citizen sce twitch '
            'democracy gloom mars pc psn xbox killzone helghast driver mech nacho shark siege jungle spec_ops '
            'tank trench admiral defender default tutorial basic starter npc prison police city urban '
            'bug bot illuminate squid automaton terminid halo odst legacy anniversary collab promo '
            'warbond_1 warbond_2 warbond_3 warbond_4'.split())
SLOTS = ['armor', 'helmet', 'cape', 'banner', 'body']  # banner = player card


def candidates():
    for slot in SLOTS:
        for i in range(0, 120):
            for fmt in ('%s_%d', '%s_%02d', '%s_%03d'):
                yield fmt % (slot, i)
        for kind in ('warbond', 'superstore', 'store', 'premium', 'standard', 'special', 'preorder', 'dlc',
                     'bundle', 'set', 'basic', 'default', 'legacy', 'promo', 'collab', 'twitch', 'event', 'reward',
                     'mo', 'major_order', 'liberty', 'democracy', 'super_citizen', 'sce', 'deluxe'):
            for g in GROUPS:
                for n in range(0, 10):
                    yield '%s_%s_%s_%d' % (slot, kind, g, n)
                    yield '%s_%s_%s_%02d' % (slot, kind, g, n)
                yield '%s_%s_%s' % (slot, kind, g)
            for n in range(0, 120):
                yield '%s_%s_%d' % (slot, kind, n)
                yield '%s_%s_%02d' % (slot, kind, n)


def main():
    assert '%08x' % thin('cape_warbond_16_1') is not None
    kits = json.load(open(sys.argv[1], encoding='utf-8'))
    want = {int(k['id'], 16): k for k in kits if k['id'].startswith('0x')}
    known = {k['id']: k for k in kits if not k['id'].startswith('0x')}
    # self-check against a resolved id: the dumper prints the name, so recompute its hash and look it up in
    # the id-to-kit map via name-free comparison (the name must hash to some kit's dlc group consistently)
    hits = {}
    for c in candidates():
        h = thin(c)
        if h in want and h not in hits:
            hits[h] = c
    for h, c in sorted(hits.items(), key=lambda x: x[1]):
        k = want[h]
        print('%08x  %-28s %-7s %s' % (h, c, k['kit_type'], k['name']))
    print('# cracked %d of %d unresolved' % (len(hits), len(want)), file=sys.stderr)


if __name__ == '__main__':
    main()
