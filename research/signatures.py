"""One Click Armor Set's code signatures (NOTES.md): checked against the game.dll dump and written into
one_click_armor_set.lua between the SIGNATURES markers, with the shared signature engine (tools/sigscan.lua)
between the SIGNATURE ENGINE markers.

Globals and offsets are read from the matched code (rip-relative operands, displacements); functions are found by
their own first instructions, or by a call to them where their bodies aren't unique. Optional signatures turn off
only what needs them (the key glyph, the 3D preview refresh, localized set names, the Hellpod button).

Usage (from the workspace root): python -B mods/OneClickArmorSet/research/signatures.py [--check]
  --check   only verify: every signature matches once and the script's blocks are current (exit 1 otherwise)
"""
import sys
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import sigspec  # noqa: E402

SCRIPT = MOD / 'one_click_armor_set.lua'


def function(name, start, end, optional=False):
    """A native function, found by its first instructions (the match is the function's address)."""
    return {'name': name, 'start': start, 'end': end, 'optional': optional}


def called(name, start, end, target, optional=False):
    """A native function found through a call to it (its own body isn't unique): field `name` is its address."""
    return {'name': 'call_' + name, 'start': start, 'end': end, 'optional': optional, 'fields': {name: (target, 'call')}}


SPECS = [
    # Globals.
    {'name': 'ui_manager', 'start': 0xb938d4, 'end': 0xb938e0, 'fields': {'ui_manager': (0x3326e68, 'rip')}},
    {'name': 'progression', 'start': 0x136f96b, 'end': 0x136f97a, 'fields': {'progression': (0x347cef8, 'rip')}},
    # The engine root, whose +0x10 -> +0x3e8 is the localization lookup `const char *(uint32 key)` (the chain
    # HD2-Transmog's extra_localized_text proves). Without it the set names are shown in English.
    {'name': 'engine_root', 'start': 0x17802e0, 'end': 0x17802fd, 'optional': True,
     'fields': {'engine_root': (0x3326308, 'rip'), 'engine_sub': (0x10, 'u8'), 'localize_slot': (0x3e8, 'u32')}},
    # The native armor EQUIP's customization event (0x145801c): the players global (local player record), the "no
    # local player" id and the component manager. Without them the 3D preview isn't redressed.
    {'name': 'players', 'start': 0x145801c, 'end': 0x145805e, 'optional': True,
     'fields': {'players': (0x3326468, 'rip'), 'local_active': (0x88, 'u32'), 'local_record': (0xe8, 'u32'),
                'no_player': (0x3483c34, 'rip'), 'components': (0x3326a50, 'rip'), 'comp_capacity': (0x28, 'u8'),
                'comp_multiplier': (0x30, 'u8')}},
    # The prompt glyph refresh (0x17a3960): the input system (its binding map is the one Mod Bindings Menu edits),
    # the prompt's input action, and find_mapping. Without it the button shows no key glyph.
    {'name': 'input', 'start': 0x17a3992, 'end': 0x17a39b8, 'optional': True,
     'fields': {'prompt_action': (0x1d28, 'u32'), 'input': (0x347cf18, 'rip'), 'find_mapping': (0x12f9540, 'call')}},

    # The item browser (Armory and Hellpod loadout alike): its grid and its detail panel (EQUIP and the purchase bar).
    {'name': 'browser_grid', 'start': 0x18d52ea, 'end': 0x18d52f7, 'fields': {'browser_grid': (0x6d0, 'u32')}},
    {'name': 'browser_detail', 'start': 0x18d53ee, 'end': 0x18d53f9, 'fields': {'browser_detail': (0x99d70, 'u32')}},
    # The Armory controller builds its browser at +0x7f718.
    {'name': 'armory_browser', 'start': 0x14564f4, 'end': 0x1456512,
     'fields': {'armory_browser': (0x7f718, 'u32'), 'browser_init': (0x18d50f0, 'call')}},

    # The Hellpod loadout screen (optional: without these the button is in the Armory only). Its screen query:
    # [[stack] + slot] when the stack's type is the loadout screen, and the local player's index.
    {'name': 'screen', 'start': 0x1082ef0, 'end': 0x1082f09, 'optional': True,
     'fields': {'stack': (0x347ce38, 'rip'), 'slot': (0xb0, 'u32'), 'local_index': (0x27d0, 'u32')}},
    # ... it builds its browser at +0xd2850 ...
    {'name': 'hellpod_browser', 'start': 0x1466de6, 'end': 0x1466df6, 'optional': True,
     'fields': {'hellpod_browser': (0xd2850, 'u32'), 'browser_init': (0x18d50f0, 'call')}},
    # ... its equip handler reads the category (3 = armor) and refreshes the browser's detail panel ...
    {'name': 'hellpod_head', 'start': 0x146e0bc, 'end': 0x146e0e4, 'optional': True,
     'fields': {'hellpod_browser': (0xd2850, 'u32'), 'category': (0x2818, 'u32'), 'hellpod_detail': (0x16c5c0, 'u32')}},
    # ... and per player keeps a pending loadout block (screen + base + index * stride) ...
    {'name': 'hellpod_blocks', 'start': 0x146e677, 'end': 0x146e6a3, 'optional': True,
     'fields': {'local_index': (0x27d0, 'u32'), 'list': (0xd2f20, 'u32'), 'block_stride': (0x9f0, 'u32'),
                'block_base': (0x10, 'u8'), 'refresh': (0x18d1890, 'call')}, 'wild': (0xd2850,)},
    # ... where an armor piece goes by sub-slot (+0x281c: 0 body, 1 helmet, 2 cape): its block field, then the native
    # setter (profile, player, item), as the Armory's commit applies them.
    {'name': 'hellpod_equip', 'start': 0x146e785, 'end': 0x146e7e5, 'optional': True,
     'fields': {'subslot': (0x281c, 'u32'), 'profile': (0x33264f8, 'rip'), 'pending_cape': (0x128, 'u32'),
                'pending_helmet': (0x124, 'u32'), 'pending_body': (0x12c, 'u32'), 'set_cape': (0x875ec0, 'call'),
                'set_helmet': (0x875cd0, 'call'), 'set_body': (0x8760b0, 'call')}},
    # The player card (optional: without these the Hellpod sets leave the card out). The Hellpod has no card list,
    # so the card goes on as the game's own loadout appliers do it: the Armory's apply (0x18dd650) finds the card's
    # index in the static card table (90 entries of 24 bytes, item id first) and calls the card setter
    # (player record + 0x34, entity event 0xbc362ac5) ...
    {'name': 'card_apply', 'start': 0x18dd87c, 'end': 0x18dd8ab, 'optional': True, 'wild': (0x60, 0x58),
     'fields': {'card_table': (0x32c9960, 'rip'), 'card_stride': (0x18, 'u8'), 'card_count': (0x5a, 'u8'),
                'set_card': (0x876ed0, 'call')}},
    # ... and the loadout applier 0x103d790 does the same inline, then saves the card's item id in the settings
    # object's saved loadout ([0x347cdd8] + 0x168, which the game re-applies and validates at load, 0x1750870).
    # Its table fields have their own names, compared by the mod: a mismatch turns off only the card, where a shared
    # name would be a signature problem that turns off the whole mod.
    {'name': 'card_saved', 'start': 0x103da4b, 'end': 0x103dab2, 'optional': True,
     'fields': {'saved_table': (0x32c9960, 'rip'), 'saved_stride': (0x18, 'u8'), 'saved_count': (0x5a, 'u8'),
                'settings': (0x347cdd8, 'rip'), 'saved_card': (0x168, 'u32')}},

    # Native UI functions (the ones Mod Options Menu uses), found by their bodies, or through a call.
    called('set_visible', 0x1932c0e, 0x1932c1e, 0x144cfb0),
    called('set_label', 0x1910b35, 0x1910b44, 0x143bf90),
    called('set_string_arg', 0x178a31e, 0x178a330, 0x143c950),
    function('clear_args', 0x143a0f0, 0x143a101),
    function('bar_empty', 0x1919250, 0x1919260),        # the purchase bar's own "nothing to buy" update
    function('set_color', 0x1448690, 0x14486a7),
    function('play_sound', 0x1327f50, 0x1327f84),       # posts a UI sound event; the first argument is unused
    function('equip_sound', 0x18d0210, 0x18d0224),      # the item's equip sound (grid, offer)
    function('button_state', 0x191a720, 0x191a732),     # EQUIP's state (5 equippable, 6 equipped)
    function('highlight', 0x18d1280, 0x18d1293, optional=True),  # the grid's highlight (grid, offer)
    function('preview_notify', 0x18d7210, 0x18d7220),   # the browser's hover refresh (details and preview)
    function('mark_equipped', 0x18d10d0, 0x18d10e0),    # the grid's equipped offer and markers
    function('set_image', 0x1450230, 0x1450244),
    function('set_uv', 0x143eef0, 0x143ef06),
    function('set_size', 0x1447160, 0x144717c),
    function('set_opacity', 0x1448ad0, 0x1448ae1),
    function('set_anchor', 0x144f160, 0x144f171, optional=True),
    function('set_pivot', 0x144f0d0, 0x144f0e1, optional=True),
    function('set_position', 0x14476a0, 0x14476bc),
    function('entity_event', 0xfd97e0, 0xfd97f5, optional=True),
    function('find_mapping', 0x12f9540, 0x12f955a, optional=True),
    function('glyph_texture', 0xaba910, 0xaba921, optional=True),
    function('key_name', 0xae47b0, 0xae47c5, optional=True),
    function('set_variable', 0x14498c0, 0x14498fb, optional=True),
    function('set_layer', 0x14491f0, 0x1449200, optional=True),
    function('commit', 0x1455a90, 0x1455ab4),           # the Armory's commit of its pending loadout
]


def main():
    rows = sigspec.build(SPECS)
    sigspec.report(rows)
    if '--check' in sys.argv:
        problems = sigspec.check(SCRIPT, rows)
        for p in problems:
            print('STALE:', p)
        sys.exit(1 if problems else 0)
    sigspec.write(SCRIPT, rows)
    print('written to', SCRIPT.name)


if __name__ == '__main__':
    main()
