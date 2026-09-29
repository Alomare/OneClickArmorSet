# One Click Armor Set

A Helldivers 2 Lua mod (Bingus Shared Loader) that adds an EQUIP SET button beside EQUIP in the ship Armory and
Character menus: one click equips the matching helmet, armor, cape and player card you own.

## Technical Description

- **Sets.** A table of 129 sets (417 items) is built into the script by `research/build_set_table.py` from the game's
  customization kit table (dumped with FileDiver): warbond items share developer names
  (`armor_/helmet_/cape_/banner_warbond_<group>_<n>`), other helmets and armors share a `dlc_id`, Superstore capes and
  cards are matched to their armor by release order and Super Credits price tier in the offers table, and the first
  warbonds' capes are paired by warbond page. Set names use the armor's localization key, so they follow the game
  language.
- **The viewed item and ownership.** The Armory controller (found through the UI manager) holds the viewed offer;
  the progression offers table maps offers to item ids and tells which items are owned.
- **The button.** The detail panel's purchase bar, which the game hides for owned items, is shown and relabeled
  through the game's own UI functions (visibility, `#COUNT` label, color, images), with EQUIP's outline texture drawn
  over it. Everything is restored when the viewed item changes.
- **Equipping.** A click writes the owned set members into the Armory's pending loadout and calls the Armory's own
  commit, like the native EQUIP; then the item's equip sound, the grid's equipped marker, and a hover away and back
  so the 3D preview redresses.
- **Options and keybind.** [Mod Options Menu](https://github.com/CowboyBingus/ModOptionsMenu) toggles for the cape and
  the card; a [Mod Bindings Menu](https://github.com/CowboyBingus/ModBindingsMenu) binding whose key or pad glyph is
  drawn with the game's prompt textures.
- **Game version.** Native functions and globals are checked against build 25480438's code at startup; on any
  mismatch the mod turns itself off.
- **Memory access.** Reads and writes go through `ReadProcessMemory` / `WriteProcessMemory` on the game's own
  process; per frame it reads one span covering the watched widgets into a reused buffer.
- **Status.** `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\OneClickArmorSet_STATUS.log`, first line = verdict.

Research notes: [NOTES.md](NOTES.md). The offline test (`research/test_release.py`) runs the script under LuaJIT
against a game.dll dump, and the set table generator needs FileDiver's kit table dump; neither is included.

## Credits

- Built on [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader),
  [Mod Options Menu](https://github.com/CowboyBingus/ModOptionsMenu) and
  [Mod Bindings Menu](https://github.com/CowboyBingus/ModBindingsMenu) by CowboyBingus.
- The Armory research builds on tyrypyrking's [HD2-Transmog](https://github.com/tyrypyrking/HD2-Transmog).
- Kit data from [FileDiver](https://github.com/xypwn/filediver).
- Developed with Claude Opus 5.5 and the [HD2 Lua Mod Skill](https://github.com/MrChengl11/hd2-lua-mod-skill).

## Nexus

https://www.nexusmods.com/helldivers2/mods/16713
