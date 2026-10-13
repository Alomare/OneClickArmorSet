"""Rule 0 of build_set_table.py: the wiki's sets (fetch_wiki.py), matched to item ids by name.

Names: helmets, armors and capes by the kit dump's names (an unnamed kit by its name key in the game's English
strings, from HD2-Transmog's catalog); player cards by the name key in the game's card table (game.dll 0x32c9960, 90
entries of 24 bytes: item id, 0, three keys, the name key at +16 or +20), resolved in the same strings.
Sets: a wiki group's armor with the helmets of the same name (the only armor's, when the group has one), and the
group's capes and cards when it has one armor; a group without armor pairs capes with cards of the same name. Groups
naming the same armor merge (a campaign's helmet and another's armor). Several ownable copies of one armor (B-01
Tactical's 9) are split into one set per copy with the helmets of its dlc_id, the capes and cards shared by all.
"""
import collections
import difflib
import json
import re
import struct

CARD_TABLE, CARD_COUNT, CARD_STRIDE = 0x32c9960, 90, 24
SUFFIX = re.compile(r'\s+(armor|helmet|cape|player card)$')


def norm(name):
    s = SUFFIX.sub('', name.lower().replace('’', "'"))
    return re.sub(r'[^0-9a-z]+', '', s)


def english_strings(folder):
    text = {}
    for f in sorted(folder.glob('*.strings.json')):
        d = json.load(open(f, encoding='utf-8'))
        if isinstance(d, dict) and (d.get('Language') or {}).get('KnownName') == 'us':
            for it in d.get('Items', []):
                text.setdefault(it['Key'], it['Value'])
    return text


def card_names(dll, english):
    """Card item id -> English name, from the game's card table."""
    names = {}
    for n in range(CARD_COUNT):
        words = struct.unpack_from('<6I', dll, CARD_TABLE + n * CARD_STRIDE)
        name = english.get(words[4]) or english.get(words[5])
        if name:
            names[words[0]] = name
    return names


def kit_names(kits, kit_id, name_keys, english):
    """Kit item id -> name: the dump's, else (an unnamed kit) its name key in the game's strings."""
    names = {}
    for k in kits:
        i, name = kit_id(k), k['name']
        if re.fullmatch(r'[0-9a-f]{5,8}', name):
            key = name_keys.get(str(i), {}).get('name_upper')
            name = english.get(key) or name
        names[i] = name
    return names


class Index:
    """Matches wiki names to item ids per slot: exact (normalized), else one name containing the other, else a close
    spelling (the game's 'Rememberance'). Every copy of a name is returned."""

    def __init__(self, names_by_slot):
        self.by = {s: collections.defaultdict(list) for s in 'hbcp'}
        for s, names in names_by_slot.items():
            for i, name in names.items():
                self.by[s][norm(name)].append(i)

    def match(self, name, slot):
        table, n = self.by[slot], norm(name)
        if n in table:
            return sorted(table[n]), 'exact'
        contains = [k for k in table if len(k) >= 6 and (n in k or k in n)]
        if len(contains) == 1:
            return sorted(table[contains[0]]), 'contains'
        close = difflib.get_close_matches(n, list(table), n=2, cutoff=0.88)
        if len(close) == 1:
            return sorted(table[close[0]]), 'close'
        return [], 'unmatched' if not contains else 'ambiguous %s' % contains


def wiki_sets(groups, index, dlc_of, ownable, manual):
    """Returns ({set key: {item: slot}}, report lines, every item a wiki name matched)."""
    sets = collections.defaultdict(dict)
    shared = collections.defaultdict(dict)  # set key -> {item: slot} for capes/cards (shared when the set splits)
    report, named = [], set()

    def ids(name, slot, source):
        found, how = index.match(name, slot)
        if not found:
            report.append('%s: %s %r %s' % (source, slot, name, how))
        elif how != 'exact':
            report.append('%s: %s %r matched %s (%s)' % (source, slot, name, ['%08x' % i for i in found], how))
        named.update(found)
        return found

    for g in groups:
        src, armors, helmets = g['source'], g['armor'], g['helmet']
        keys = []
        for a in armors:
            key = norm(a)
            keys.append(key)
            for i in ids(a, 'b', src):
                sets[key][i] = 'b'
        for h in helmets:
            key = norm(h) if norm(h) in keys or len(keys) != 1 else keys[0]
            for i in ids(h, 'h', src):
                sets[key][i] = 'h'
            if key not in keys:
                keys.append(key)
        if len(set(keys)) == 1:
            for c in g['cape']:
                for i in ids(c, 'c', src):
                    shared[keys[0]][i] = 'c'
            for p in g['card']:
                for i in ids(p, 'p', src):
                    shared[keys[0]][i] = 'p'
            if not g['card']:  # a card named as the cape, which the wiki leaves out (Superstore page 4's Gilded Quill)
                for c in g['cape']:
                    found, how = index.match(c, 'p')
                    if how == 'exact':
                        named.update(found)
                        shared[keys[0]].update({i: 'p' for i in found})
                        report.append('%s: card %r joins its cape (not on the wiki)' % (src, c))
        elif not keys:
            for c in g['cape']:
                for i in ids(c, 'c', src):
                    sets[norm(c)][i] = 'c'
            for p in g['card']:
                for i in ids(p, 'p', src):
                    sets[norm(p)][i] = 'p'
        elif g['cape'] or g['card']:
            report.append('%s: capes/cards with several armors, left out: %s %s' % (src, g['cape'], g['card']))
    for armor_name, extra in manual.items():
        for slot, name in extra:
            for i in ids(name, slot, 'manual'):
                shared[norm(armor_name)][i] = slot
    out = {}
    for key, members in sets.items():
        bodies = sorted(i for i, s in members.items() if s == 'b' and i in ownable)
        if len({dlc_of[i] for i in bodies}) > 1:
            # One set per ownable copy, with the helmets of its dlc_id; the capes, cards and helmets of no copy's
            # dlc_id shared (the script prefers a set's own pieces).
            loose = {i: 'h' for i, s in members.items() if s == 'h' and dlc_of.get(i) not in {dlc_of[b] for b in bodies}}
            for b in bodies:
                part = {b: 'b'}
                part.update({i: 'h' for i, s in members.items() if s == 'h' and dlc_of.get(i) == dlc_of[b]})
                if len(part) == 1:  # a copy without a helmet of its own (B-24 Enforcer's free copies): the name's
                    part.update({i: 'h' for i, s in members.items() if s == 'h'})
                part.update(shared.get(key, {}))
                part.update(loose)
                out['%s#%08x' % (key, b)] = part
            if loose:
                report.append('%s: %d helmets without an armor copy of their dlc_id, shared' % (key, len(loose)))
        else:
            part = dict(members)
            part.update(shared.get(key, {}))
            out[key] = part
    for key, members in shared.items():
        if key not in sets:
            report.append('%s: capes/cards without its armor in the table' % key)
    return out, report, named
