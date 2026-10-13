<img width="1920" height="1080" alt="thumbnail2" src="https://github.com/user-attachments/assets/6449e6c1-6a6a-42cc-9d5f-59251f0a23e2" />

# One Click Armor Set

A Helldivers 2 Lua mod for [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader) that adds an EQUIP SET button beside EQUIP: one click equips the matching helmet, armor, cape and player card you own.

## Features

- In the ship **Armory** and **Character** menus, and in the **Hellpod loadout's** helmet, armor and cape lists, an EQUIP SET button appears when the item you're looking at belongs to a set and you own at least one other piece of it.
- The button names the set and counts its pieces: **EQUIP KODIAK SET (4/4)**. When every piece is already on it says **KODIAK SET EQUIPPED (4/4)**, greyed out, until something changes.
- A click (or a [Mod Bindings Menu](https://github.com/CowboyBingus/ModBindingsMenu) key, whose key or gamepad button shows on the button) equips the set the way the game's own EQUIP does: saved like any equip, seen by other players as usual. A press is taken at most every half second.
- 131 sets, 456 items: every warbond page, Superstore set and special set (starter, Liberty Day, anniversary, campaigns) with its helmet, armor, cape and player card.
- **Randomize Armor**, a second Mod Bindings Menu key: in any of those lists, it puts on a random set you own at least two pieces of, or a random piece per slot.
- [Mod Options Menu](https://github.com/CowboyBingus/ModOptionsMenu) options: include the cape, include the player card (both on by default), Randomization Mode (Whole Sets or Each Piece) and Keep Armor Weight (random armor of the weight class you wear).
- The button, the options and the binding follow the game's Text Language.

## Installation

1. Install [Bingus Shared Loader](https://www.nexusmods.com/helldivers2/mods/16292) (v17 or newer).
2. Optional: [Mod Options Menu](https://www.nexusmods.com/helldivers2/mods/16625) to change the settings, and [Mod Bindings Menu](https://www.nexusmods.com/helldivers2/mods/16478) for a key or gamepad button.
3. Install the ZIP from [Releases](https://github.com/Alomare/OneClickArmorSet/releases) with [HD2 Arsenal](https://www.nexusmods.com/helldivers2/mods/4664) (or HD2 Mod Manager) and deploy. Keep Bingus Shared Loader last in the mod order, so it loads first.

The verdict is the first line of `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\OneClickArmorSet_STATUS.log`.

## Technical Details

- **Sets.** A table of 131 sets (456 items) is built into the script by `research/build_set_table.py`: the sets come from the [Helldivers 2 wiki](https://helldivers.wiki.gg) (`research/fetch_wiki.py`: every warbond page, Superstore page and special source), matched by name to the game's customization kits (dumped with FileDiver) and to its player cards (the game's card table names each card through the game's own strings). Pieces several armor copies share (the starter cape and card on every B-01 Tactical) belong to each. Items the wiki doesn't name fall back to the game data rules: developer names, shared `dlc_id`, and the Superstore's release order and price tiers. Set names use the armor's localization key, shown without the designation.
- **Random armor.** Every kit's slot and weight class is generated with the set table (the class is the armory's: the torso piece's weight; a helmet takes its set's armor class); player cards are found by their offer type at runtime. The draw is uniform, from the mod's own generator.
- **The item browser.** The Armory controller (found through the UI manager) and the Hellpod loadout screen embed the same item browser class: a grid and a detail panel with EQUIP and a purchase bar. The detail panel holds the viewed offer; the progression offers table maps offers to item ids and tells which items are owned.
- **The button.** The purchase bar, which the game hides for owned items, is shown and relabeled through the game's own UI functions (visibility, `#COUNT` label, color, images), with EQUIP's outline texture drawn over it; everything is restored when the viewed item changes or the list closes.
- **Equipping.** In the Armory: the owned set members go into its pending loadout, then the Armory's own commit, as the native EQUIP does. In the Hellpod loadout: each piece goes into the player's loadout block, then the game's own armor setter, as its equip handler does; the player card (the Hellpod has no card list) goes through the game's card setter with its index in the game's card table, then into the saved loadout, as the game's own loadout appliers do. Then the item's equip sound, the grid's equipped marker, and a hover away and back so the 3D preview redresses. "Equipped" compares the set with the applied loadout.
- **Finding the game's code.** Every global, native function and browser offset comes from code signatures generated in one block by `research/signatures.py` from a game.dll dump (functions by their own first instructions, or through a call where their bodies aren't unique). At startup each is tried at the known build's address, else game.dll is searched over a few frames; a signature must match exactly once and shared values must agree. Missing optional code turns off only its part (the key glyph, the 3D preview refresh, translated set names, the Hellpod button, the Hellpod's player card). The search engine (`tools/sigscan.lua` in the author's workspace) is shared with the author's other mods.
- **Texts.** `locales/en.lua` is the English source and `locales/<tag>.lua` the bundled translations, resolved by CowboyBingus' `src/bingus_text.lua` against the game's Text Language; the build places both ahead of the script.
- **Memory access.** Reads and writes go through `ReadProcessMemory` / `WriteProcessMemory` on the game's own process; per frame it reads one span covering the watched widgets into a reused buffer.
- **Tests.** `tests/test_release.py` runs the built entry under LuaJIT against a game.dll dump (not included), with the Armory, the Hellpod screen, the offers table and the game's language setting simulated.

Research notes: [NOTES.md](NOTES.md). Release notes: [CHANGELOG.md](CHANGELOG.md).

## Credits

- Built on [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader), [Mod Options Menu](https://github.com/CowboyBingus/ModOptionsMenu) and [Mod Bindings Menu](https://github.com/CowboyBingus/ModBindingsMenu) by CowboyBingus, whose `bingus_text.lua` provides the translations.
- The Armory research builds on tyrypyrking's [HD2-Transmog](https://github.com/tyrypyrking/HD2-Transmog).
- Kit data from [FileDiver](https://github.com/xypwn/filediver); set lists from the [Helldivers 2 wiki](https://helldivers.wiki.gg); armor weight classes checked against SkyeShade's [HD2Runtime](https://github.com/SkyeShade/HD2Runtime).
- Developed with Claude Opus 5.5 and the [HD2 Lua Mod Skill](https://github.com/MrChengl11/hd2-lua-mod-skill).

## License

Copyright (C) 2026 Alomare. Licensed under the [GNU General Public License v3.0 or later](LICENSE): you're free to use, study, change and share this mod, and anything you distribute that includes or changes its code must use the same license and come with its source. `src/bingus_text.lua` is CowboyBingus's, under the Zero-Clause BSD license.
