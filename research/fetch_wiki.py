"""Fetch the armor sets from the Helldivers 2 wiki (helldivers.wiki.gg) into _research/equip_set/wiki_sets.json.

A set is what the game sells together: one warbond page, one Superstore page, or one special source (Starter
Equipment, Liberty Day, a campaign...). Sources:
  - the wiki's Cargo tables Armor (armor and helmets) and Cosmetics (capes and player cards): each item's source, a
    warbond page or a special source;
  - each warbond's page, for the warbonds whose items the Cargo tables list without a page number: its "=== Page N ==="
    sections, the item kind from the image name (Helmet Render, Armor Render, Cape Render, Player Card Icon);
  - the Superstore page: one tab ("|-|Page N=") per set, items as "title: <name> (Armor|Helmet|Cape|Player Card)".
Output: {"groups": [{"source": ..., "armor": [...], "helmet": [...], "cape": [...], "card": [...]}]}, names as the wiki
writes them (build_set_table.py matches them to item ids).

Usage: python fetch_wiki.py
"""
import collections
import html
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
OUT = MOD.parents[1] / '_research' / 'equip_set' / 'wiki_sets.json'
API = 'https://helldivers.wiki.gg/api.php'
EXPORT = 'https://helldivers.wiki.gg/index.php'
HEADERS = {'User-Agent': 'OneClickArmorSet-research/1.0 (Helldivers 2 mod set table)'}
KIND = {'Helmet': 'helmet', 'Cape': 'cape', 'Player Card': 'card'}  # every other Armor type is armor
IMAGE_KIND = [(' Helmet Render', 'helmet'), (' Armor Render', 'armor'), (' Cape Render', 'cape'),
              (' Player Card Icon', 'card')]


def get(url, params):
    time.sleep(0.5)  # be gentle with the wiki
    req = urllib.request.Request(url + '?' + urllib.parse.urlencode(params), headers=HEADERS)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode('utf-8'))


def cargo(table, fields, where=None):
    params = {'title': 'Special:CargoExport', 'tables': table, 'fields': fields, 'limit': 5000, 'format': 'json'}
    if where:
        params['where'] = where
    return get(EXPORT, params)


def wikitext(page):
    return get(API, {'action': 'parse', 'page': page, 'prop': 'wikitext', 'format': 'json', 'formatversion': 2,
                     'redirects': 1})['parse']['wikitext']


def clean(name):
    return html.unescape(name).strip().replace('’', "'")


def strip_kind(name):
    """'TG-8 Sharpshooter Armor' -> 'TG-8 Sharpshooter' (some warbond pages name items with their kind)."""
    return re.sub(r'\s+(Armor|Helmet|Cape|Player Card)$', '', name)


def source_of(s):
    """(page title, section) of a Cargo source: '[[X Warbond#Page 2|X]] ...' -> ('X Warbond', 'Page 2')."""
    s = html.unescape(s or '')
    m = re.match(r'\[\[([^|\]#]+)(?:#([^|\]]+))?(?:\|[^\]]*)?\]\]', s)
    if m:
        return m.group(1).strip(), (m.group(2) or '').strip()
    return re.sub(r'<[^>]+>', '', s).strip(), ''


def warbond_pages(title):
    """{'Page N': {kind: [names]}} from a warbond page's sections."""
    text = wikitext(title)
    pages = {}
    parts = re.split(r'^===\s*(Page \d+)\s*===\s*$', text, flags=re.M)
    for name, body in zip(parts[1::2], parts[2::2]):
        body = body.split('\n== ')[0]
        items = collections.defaultdict(list)
        for m in re.finditer(r'\|\s*\d+_image\s*=\s*([^\n|]+?)\.png\s*\n(?:[^\n]*\n)*?\s*\|\s*\d+_name\s*=\s*([^\n]+)', body):
            image, label = m.group(1), clean(m.group(2))
            for suffix, kind in IMAGE_KIND:
                if image.endswith(suffix) and label not in items[kind]:
                    items[kind].append(label)
        pages[name] = dict(items)
    return pages


def superstore_sets():
    text = wikitext('Superstore')
    stock = text.split('== Stock ==', 1)[1].split('\n== ', 1)[0]
    sets = []
    for tab, body in re.findall(r'\|-\|([^=\n]+)=\n(.*?)(?=\n\|-\||\Z)', stock, flags=re.S):
        items = collections.defaultdict(list)
        for name, kind in re.findall(r'\|title:\s*(.+?)\s*\((Armor|Helmet|Cape|Player Card)\)', body):
            k = {'Armor': 'armor', 'Helmet': 'helmet', 'Cape': 'cape', 'Player Card': 'card'}[kind]
            if clean(name) not in items[k]:
                items[k].append(clean(name))
        if items:
            sets.append(('Superstore / ' + tab.strip(), dict(items)))
    return sets


def main():
    rows = [(r, 'armor' if r['type'] not in KIND else KIND[r['type']])
            for r in cargo('Armor', '_pageName=page,type,source')]
    rows += [(r, KIND[r['type']]) for r in cargo('Cosmetics', '_pageName=page,type,source',
                                                  'type="Cape" OR type="Player Card"')]
    groups = collections.OrderedDict()
    paged_later = collections.defaultdict(list)  # warbond -> its items listed without a page (read from its page)
    for r, kind in rows:
        page, section = source_of(r['source'])
        page = page.replace('’', "'")
        if page == 'Superstore':
            continue
        if 'Warbond' in page and not section:
            paged_later[page].append((kind, clean(r['page'])))
            continue
        key = page + (' / ' + section if section else '')
        groups.setdefault(key, collections.defaultdict(list))
        name = clean(r['page'])
        if name not in groups[key][kind]:
            groups[key][kind].append(name)
    for title in sorted(paged_later):
        placed = set()
        for section, items in warbond_pages(title).items():
            key = title + ' / ' + section
            g = groups.setdefault(key, collections.defaultdict(list))
            for kind, names in items.items():
                for n in names:
                    n = strip_kind(n)
                    placed.add((kind, n))
                    if n not in g[kind]:
                        g[kind].append(n)
        # Items its pages don't show (a page laid out otherwise): one group for the warbond.
        for kind, n in paged_later[title]:
            if (kind, n) not in placed:
                g = groups.setdefault(title, collections.defaultdict(list))
                if n not in g[kind]:
                    g[kind].append(n)
    out = [{'source': k, **{kind: v.get(kind, []) for kind in ('armor', 'helmet', 'cape', 'card')}}
           for k, v in groups.items()]
    out += [{'source': k, **{kind: v.get(kind, []) for kind in ('armor', 'helmet', 'cape', 'card')}}
            for k, v in superstore_sets()]
    OUT.write_text(json.dumps({'fetched': time.strftime('%Y-%m-%d'), 'groups': out}, indent=1, ensure_ascii=False),
                   encoding='utf-8')
    print('%d groups (%d Superstore pages, %d warbonds read page by page) -> %s'
          % (len(out), sum(1 for g in out if g['source'].startswith('Superstore')), len(paged_later), OUT))


if __name__ == '__main__':
    main()
