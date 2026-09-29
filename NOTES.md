# Equip Helldiver Set (formerly Equip Set Button): research notes

Goal: an **EQUIP SET** button next to the native EQUIP button in the ship Armory and Character menus, shown when
the viewed helmet, body, cape or player card has at least one other owned item in its thematic set. The button shows
icons for the set's slots and equips all of them.

## 1. Can sets be identified from game data? (build 25480438)

Source: the game's customization kit table, `generated_customization_armor_sets.dl_bin` (411 kits: 135 bodies,
158 helmets, 118 capes). Dump it with FileDiver's
`go run ./cmd/tools/components/armor-set-json-dumper > _research/equip_set/armor_sets.json`, then
`research/derive_sets.py` groups it. Each kit has `id` (thin hash of an internal name), `dlc_id`, `set_id`, name, type.

- **Helmet + body: reliable.** 125 `dlc_id` groups are exactly one body and one helmet with the same name. A few
  groups hold extra variants (FS-05 Marksman, SC-30, SC-34: one body plus several helmet variants), and the
  B-01 Tactical kits are many default/NPC copies. Only owned items matter at runtime, which filters most of these.
- **Loners are recognizable.** IX-VOIDWALKER and B-02 Gloom Warden are alone in their `dlc_id` (both in the catch-all
  set 934502665), matching the expected "no set" behavior.
- **`set_id` is too coarse on its own.** Set 0 holds 105 loose capes; set 934502665 holds default/NPC kits; some
  sets pair two unrelated armors (FS-38 Eradicator with B-08 Light Gunner, one set per store rotation or bundle).
- **Capes: only partly in data, but the internal names help a lot.**
  - Resolved internal ids follow a developer naming scheme, `armor_warbond_16_1`, `helmet_warbond_16_1`,
    `cape_warbond_16_1`, and the `<group>_<n>` suffix pairs the cape with its armor. Example: warbond 16 set 1 is
    DS-42 Federation's Blade + Rightful Occupier; set 2 is DS-191 Scorpion + Windswept Wayfinder. This covers every
    warbond from 5 (Polar Patriots) onward, plus the named warbonds (driver, helghast, jungle, mech, nacho, shark,
    siege, spec_ops, tank, trench): 45 bodies, 45 helmets and 78 capes resolve.
  - Only 6 other capes are linked through `dlc_id`/`set_id`, all edition/DLC bundles: Liberty's Herald with
    FS-05 Marksman, Cresting Honor with SC-30, Agent of Oblivion with FS-61 Dreadnought, Will of the People with
    SC-37 Legionnaire, Tyranny's Bane, Tideturner.
  - The other 243 ids (the first warbonds, Superstore items, early capes) didn't crack with the tried patterns
    (`research/crack_kit_names.py`). Their cape pairings need a curated table.
- **Player cards are not in local data at all.** No table, type or resource name covers them (only a texture
  name `playercard_texture`). Their item ids have to come from the live progression catalog (below).

**Conclusion: a combination.** Helmet/body pairs come from game data (and could be read live, so new armors
work without a mod update). Capes come from the internal names where they resolve, plus a curated table for older
and Superstore items. Player cards need a curated table keyed by item id, built after recon finds those ids.

## 2. Native pieces found so far

From Transmog (`_examples/HD2-Transmog`, all signature-scanned there):
- **Ownership:** the progression manager holds an offers table (`+0x1ce0` count, entries of 24 bytes at `+0xb9ce4`
  with item id at `+8`, per-offer state of 184 bytes at `+0x1ce4`: status `+0x14` = 2 or 4 and enabled byte `+0xb4`
  = 0 means owned). This table covers every item type, so it should list capes and player cards too, and may carry a
  warbond/page grouping (to be checked).
- **Equipping armor:** the native setter `deployment_commit(profile, player, item_id)` writes
  `[profile + player*64 + 0xa88]` and is what the Armory's own Apply uses.
- **Drawn UI with the game's font:** Transmog resolves the game's font, atlas and material globals and reads native
  widget rectangles, so a drawn button can be matched to the native EQUIP button's position and style.

Offline (`_research/game_25480438.dll`): the per-player loadout record has a family of setters next to the armor one,
all of the same shape (compare, write, then notify): `+0xa84` (helmet, fn ~0x875ec0), `+0xa88` (body, ~0x8760b0),
`+0xa8c`, `+0xa90`, `+0xaa4`, `+0xaa8` (~0x876a50), `+0xaac` (~0x876cf0). Cape and player card are likely among them.

The menus are NoesisGUI XAML (`content/ui/shared/xaml/...`, e.g. `component_acquisitions_items_armory`,
`component_button_related_warbond`). Adding a real XAML button is possible in principle but it would need a C++
command binding; a drawn overlay (Transmog's approach) is the practical route.

## 3. Recon 1 results (1-recon1, 2026-09-28)

Tools: `research/name_recon_log.py` names the ids in `EquipSetButton.log`; output in
`_research/equip_set/recon1_named.txt`.

- **Loadout record** (profile object = `[game.dll+0x33264f8]`, player 0 at `+0xa80`, stride 64): `+0x00` helmet id,
  `+0x04` cape id, `+0x08` body id, `+0x34` **player card index** (not an id), `+0x38` title index (likely). A second
  copy sits at `+0x970`..`+0x9a0`. (So the offline `+0xa84` setter is the cape one, and payload `+4` → 0x875cd0
  is the helmet setter.)
- **Viewed item:** the Armory controller (UI manager row with type 224, `[game.dll+0x3326e68]` rows at `+0x1670`)
  holds the item being viewed at **`+0x136f5c`** (mirror at `+0x13a888`), in the Armory and the Character menu
  alike, for helmets, bodies, capes and player cards. It matched every item viewed, in order. No instruction uses
  that displacement directly (a sub-object), so it still needs a code-derived path.
- **Offers table:** 2928 entries. Entry: `@0` index, `@4` offer id, `@8` item id, `@12`/`@16` 1/2 on armor and
  helmet offers. State (184 bytes): `+0x0c` item type (3 = armor kit of any slot, 9 = player card, 87 cards),
  `+0x14` status (2 = owned/available). No explicit set or warbond id, but the table is ordered by release: each
  warbond's cards, capes, armors and helmets are neighbors.
- **Player card index = the card's position among type-9 offers** (Federation's Embrace: 53rd card, loadout 53).
- **Player cards follow the kit naming scheme:** `banner_warbond_<group>_<n>` (43 of 87 cracked). So a warbond set is
  `armor_/helmet_/cape_/banner_warbond_<group>_<n>`, e.g. 13_1: RE-2310 Honorary Guard, Federation's Embrace cape
  and Federation's Embrace card. Card and cape names often match too.

## 4. Recon 2 targets and design rules

Armory controller layout (Transmog's proven shapes, confirmed or matched in recon 1): grid = ctl + 0x7fde8, preview
manager = ctl + 0x7f718, detail widget = ctl + 0x119488; highlighted offer ctl + 0x112770, equipped offer
ctl + 0x112774, detail offer detail + 0xbe00c (= ctl + 0x1d7494), EQUIP button widget detail + 0x49f0 (state
+0x47b8, 6 = equipped; geometry: size +12/+16 or +36/+40, scale +100/+140, position +148/+156, alpha +84).
Offer → item: offers entry `@4` offer id → `@8` item id (armor/helmet offer ids differ from item ids; capes and
cards don't). Slot: entry `@12` 1 = body, 2 = helmet, 0 = cape (type 3); type 9 = card.
Armory commit (`0x1455a90`, `commit(ctl, 0)`): copies ctl + 0x90/94/98 and the 0x2c-byte block at ctl + 0x64 to the
settings object, then applies the block to the player through `0x18dd650` (which calls the helmet/cape/body setters).

Performance rules (the user found Transmog's UI jittery and the menus slower):
- Resolve code once; per frame read only a few small spans (the button widget, a handful of dwords).
- One persistent immediate-mode GUI, drawn every frame; never destroy/recreate it on content changes.
- Read the button position in the same frame it is drawn, so the button moves with native animations.
- No per-frame scans of the offers table: map offers once per Armory visit, re-map only when the count changes.

## 5. Recon 2 results and the native-button plan

- The EQUIP widget's position (+148/+156) and size (+12/+16 × scale) are already screen coordinates in Stingray's
  Gui space (no flip). The green outline fit in every tab and the Character menu, at 3440x1440, 1920x1080 and windowed.
- Pending loadout in the Armory controller: helmet `+0x3c`, cape `+0x40`, body `+0x44`, player card **item id**
  `+0x54`; mirrored in the block at `+0x64` (`+0x68/+0x6c/+0x70/+0x80`). Each native equip changed exactly its field
  and the loadout record. Controller `+0x30` (1 = Armory, 2 = Character?) and `+0x34` (page active).
- Category `ctl + 0x1f83ac`: 0 armor, 1 helmet, 2 cape. The offer entry's `@12` is **not** the slot.
- The Character menu reuses the same controller and detail panel; types 8 and 13 appear there (emotes/titles?).

Native UI (Bingus' way, from ModOptionsMenu): reuse widgets the game already has, set their text with the
`#COUNT` template (label 0xc67c7faf + a string argument), show/hide them with the game's own set_visible /
set_opacity, and read input from the game's action states. The game then renders, scales, animates and sounds them.
Its native helpers (build 25480438): set_visible 0x144cfb0, set_label 0x143bf90, set_string_arg 0x143c950,
clear_args 0x143a0f0, set_opacity 0x1448ad0, set_position 0x14476a0, set_size 0x1447160, add_child 0x144c5c0,
play_sound 0x1327f50.
Candidate: the detail panel's second button, `detail + 0x91c0` (built by 0x19176a0, updated by 0x1919250, faded
together with EQUIP), probably the purchase/price bar that sits hatched and empty beside EQUIP for owned items.
Recon 3 outlines it (cyan) and dumps both widgets (F7) for owned/unowned items.

## 6. Recon 4 results (label test) and the prototype (recon 5)

The purchase bar (detail + 0x91c0, 656x60 local units) is only in the Armory and Character menus (Warbond and
Superstore pages are other screens). Its children: background `+0x220` (the hatching); group A `+0x378` = padlock
image `+0x488` + gray text `+0x5e0` (the "locked" layout); group B `+0x898` = red warning icon `+0x9a8` + text
`+0xb00` ("This item is temporarily disabled"); `+0xdb8`/`+0xec8`/`+0xfd8`/`+0x16b0` others. set_visible on a
group plus the `#COUNT` text on its text widget rendered natively in every tab, with no crash; the game's own
bar update (0x1919250) hides the groups again.

Prototype: group A with the padlock hidden and the text `EQUIP SET · <other owned slots>`, the bar shrunk to
EQUIP's width (set_size on the bar and its full-width children) and moved right by the difference (set_position,
local position at widget +4/+8), everything restored when the item changes. Click in the bar's screen rect →
write the owned set members into the pending loadout (ctl + 0x64: helmet +4, cape +8, body +0xc, card +0x1c) and
call the Armory's commit (0x1455a90, `commit(ctl, 0)`), only while the pending block equals the applied one
(ctl + 0x38). The set table is generated into the script by `research/build_set_table.py` (130 sets, 371 items).

## 7. New sets after game updates (recon 5 feedback)

- Superstore capes and cards are not linked to their armor anywhere in game data. In the offers table they carry
  a Super Credits price (state `+0x1c` currency 0xcf875032, `+0x20` amount) and often sit next to their armor
  (BFM-77 Reformer: armor 250, helmet 125, cape Tread of Liberty 100, card 0xcdea8cb2 35, contiguous).
  `research/infer_offer_sets.py` tests an order rule ("k-th pending cape/card → k-th armor pair"): wrong for
  warbonds (2 right, 6 wrong against the developer names) and self-contradictory for some Superstore items
  (Diagram of the Noblest Payload lands on KDM-500 Outrider, but shares a priced run with O-44). So Superstore
  capes/cards need the curated table; the script's output is a candidate list for it.
- What can adapt without a mod update: helmet+armor pairs (read the live kit catalog's dlc_id, as Transmog reads
  kits live), numbered warbonds (hash `<slot>_warbond_<n>_<k>` at runtime). What can't: warbonds with new group
  names (recent ones are named: tank, trench, ...), Superstore capes/cards. Code changes are handled by signatures.
- Options: Mod Options Menu toggles `alomare.equip_set_button.cape` / `.card` (default on); without the menu,
  everything is included.

## 8. Button feedback (recon 7)

From the Armory's input handler (0x191c290) and init code: set_color 0x1448690 `(widget, float rgb[3])`, color at
widget +0x48; the bar's text starts gray (0.694). The EQUIP widget's sound ids: +0x47bc = hover (set_hovered 0x191a6b0 plays it when hover starts, nothing on
leave; the button class init writes 0x65e34ad8 there), +0x47c0 = the hold-to-confirm sound (the "hold to unlock"
sound; recon 7 used it for hover by mistake), +0x47c4/+0x47c8 = state-change sounds; play_sound 0x1327f50 (first
argument unused). After a native equip the Armory calls equip_sound 0x18d0210 `(grid, offer)` (the item's own
sound, by category) and mark_equipped 0x18d10d0 `(grid, offer)` (grid equipped offer +0x9298c and the grid cells'
markers); grid = ctl + 0x7fde8. Recon 8: hover = white text + +0x47bc, leave = gray, click = yellow flash, commit, equip sound,
equipped marker, then button_state 0x191a720 `(EQUIP widget, 6)` so EQUIP shows its equipped look (recon 7 left
it until EQUIP was clicked). Recon 8 also renamed the mod: Equip Helldiver Set, mods/alomare/equip_helldiver_set.

## 9. Recon 9: counter label, stripe crop, preview refresh (icons dropped)

- Image widgets (type 0xc0000): set_image 0x1450230 `(widget, material hash, texture hash, 0)` (material e.g.
  content/ui/shared/material/gui_diffuse_map; texture = a UI texture path hash, e.g. content/ui/shared/misc/check_yes).
  Crop `+0x114` (u0,v0,u1,v1), atlas region `+0x134` (x,y,w,h), final UVs `+0x124`, recomputed by 0x143f3c0;
  set_uv 0x143eef0 `(widget, vec2 min, vec2 max)` sets the crop and redraws. The hatching is `+0x220` of the bar
  (texture 0x604f438cc567d479, 656x60): recon 9 crops it to width/656 instead of squeezing it.
- Large preview = detail + 0x20640; kit setter 0x192adb0 `(preview, kit)` skips when `+0xdc0` equals the kit, else
  picks the mode by kit type and rebuilds (0x192b010). After EQUIP SET: write 0 to `+0xdc0`, call it with the kit.
- Icons: the game has ItemtypeHelmet/Armor/Cape/Playercard as XAML vector icons
  (content/ui/shared/resources/generated_icons/item_type_icons.xaml), but native image widgets take texture paths,
  mostly unnamed. Dropped by the user: texture ids shift with game updates. The label is a counter instead:
  `EQUIP SET (owned/total)` over the set's slots that are included in the options.

## 10. Recon 10: set names, full width, card sounds, preview via the native path

- The native armor EQUIP (0x1457a10, branch 0x1457f86..0x14580ed): writes the pending slot (+0x68/+0x6c/+0x70 by
  category), posts event 0xbd5b4583 to the player's entity, commits (0x1455a90), then calls
  **preview_notify(ctl + 0x7f718)** (0x18d7210), the hover refresh that re-shows the details and the 3D preview.
  Recon 9's direct preview kit set (0x192adb0) only drives the preview camera mode, so it didn't redress the model.
- The player card branch (0x1457e36) writes +0x80 and plays sound **0x80680c11** before its commit; the item equip
  sound (0x18d0210) plays nothing for cards. The EQUIP hover field can be empty there: fall back to 0x65e34ad8.
- Localization: [game.dll+0x3326308] (engine root, from Transmog's extra_localized_text shape at 0x17802e0) → +0x10 →
  +0x3e8 = `const char *(uint32 key)`; the target is checked to be committed executable image code before the call.
  Set names use the armor's name_upper key (from Transmog's catalog, generated into SET_NAMES with an English
  fallback). Label: `EQUIP <NAME> SET (owned/total)`, bar at full width (no resize/crop).

## 11. Recon 11: customization event, label language, outline, margin

- Recon 10's preview_notify alone didn't redress the 3D preview. The other native step (0x145801c..0x14580d7): local
  player id = [[players+0xe8]+8] if [players+0x88] != 0 (players = [game.dll+0x3326468], "none" = [0x3483c34]);
  component manager [0x3326a50]: open-addressing table keys [+0x20] (8-byte {id, index}), capacity [+0x28] (power of
  two), empty key [+0x2c], hash = [+0x30] * id (u32), probe (hash + i) & (capacity - 1); index -1 = none. State =
  [+0x50] + index*36 + 0x20: clear bit 0, add 2, set bit 0; entity id = [[+0x38] + index*8] + 0x10; then
  0xfd97e0(entity, 0xbd5b4583, state) queues the event. Recon 11 does this before the commit for armor pieces.
- Language: localized text of key 0x1b5b48a1 ("LOW FUNDS") differs in every game language (only us/gb share it).
  The game has no "set" string (all 14 languages' string tables searched, `_research/equip_set/strings`), so the
  label patterns are the mod's own per language.
- Outline: the bar's +0x110 child is a border widget (type 0x80000) created with opacity 0; recon 11 shows it in the
  text color. Margin: the text (+0x5e0, local x 55 for the padlock at 20 + 30) moves to half.

## 12. Recon 12: the real border, language per Armory visit

- The bar's +0x110 child is a background tint (showing it lit up the hatching), not a border. The border is group
  +0xec8 (color 0.27, four 3-px image lines: +0xfd8 bottom, +0x1130 top, +0x1288 left, +0x13e0 right) inside group
  +0xdb8 (opacity 0), which also holds +0x1598 and the text +0x16b0 (price widgets). Recon 12 shows +0xdb8, hides
  those two, and tints +0xec8 with the text color (gray / white on hover / yellow on click).
- Language and localized names are detected again each time the Armory opens (in-game language switch).
- Preview: recon 11's customization event was posted ("customization event posted"), and the model still didn't
  change. Note: recon 1's "viewed mirror" ctl + 0x13a888 is the preview kit cache (detail + 0x20640 + 0xdc0), already
  cleared since recon 10. Recon 12 logs the viewed item and preview kit for 3 s after each equip.

## 13. Recon 13: EQUIP's outline, preview via a changed item

- Preview: hovering away and back redresses it (user test), and so does switching tabs after a native equip. The
  detail function skips dressing the 3D model when the new item equals the shown one: at 0x191d631
  `cmp edi (old +0xbe00c), ebx (new)` → skip `0x18ebfc0(detail + 0x1fc88)`. Recon 13 writes 0 to detail + 0xbe00c
  before preview_notify, which then re-shows the hovered item as a new one.
- The recon 12 border lines are brush images (no texture hash, material pointer at +0x148): thick and "dirty".
  EQUIP (button init 0x1919710) draws its outline with image +0x110: material gui_white_alpha
  (0xf6978e86e4f4b0d5), texture A 0x9c02d37a657590d7, 330x60, tinted green; +0x24c0 texture B (yellow, equipped),
  +0x4398 texture C (344x72 glow). Image layout: material handle +0x148, texture hash +0x150.
  set_image 0x1450230 `(widget, material, texture, 0)`. Recon 13 puts texture A on the bar's two icon images
  (padlock +0x488, warning +0x9a8, group B shown with its text +0xb00 hidden): each shows half of A (set_uv) at
  328x60 side by side, so the edges keep EQUIP's thickness. Restored to their own images afterwards.

## 14. Recon 14: the real outline texture, a hover away and back

- Recon 13's texture A (0x9c02d37a657590d7) is EQUIP's hatching, not its outline: the bar got a second hatching.
  FileDiver extracts these UI textures by hash (`-i "*<hash>*" --texture-format png`, in
  `_research/equip_set/equip_textures`): texture C 0x0b6a14c35af5f4e4 is the outline, 344x72 grayscale-as-alpha, a
  2-px rectangle at x 7-8 / 335-336 and y 6-7 / 64-65. Recon 14 draws it at native scale in two 335-wide pieces:
  left = columns 0..334 at x -7, right = columns 9..343 at x 328 (edges at bar x 0 and 654), 72 tall, centered.
- Preview: recon 13's same-item reset ran (log) and the model still didn't change, so the redress isn't in the
  detail function. A real hover changes the grid's highlighted offer: highlight 0x18d1280 `(grid, offer)` (focus
  +0x928e8, highlighted +0x92988; returns 0 when the offer isn't in the grid). Recon 14 highlights another item of
  the same grid (the viewed slot's previous item, else the first ones in the grid's offer list at grid + 0x92990)
  one frame after the equip, then the viewed item again two frames later, each with preview_notify; the bar logic
  waits meanwhile.

## 15. Recon 15: keeping the outline, the card tab

- Recon 14 in game: the hover away and back redresses the 3D model in the armor, helmet and cape tabs (all 71 hovers
  logged ok). The outline showed full rectangles: the crops didn't hold (set_image seems to load the texture
  asynchronously and reset the crop), and the hover's own bar refresh hid group B (the right piece).
  Recon 15 checks the pieces each frame (texture +0x150, crop +0x114, size, position, visibility, group B) and puts
  back whatever differs.
- Card tab: hovering cards never redresses the model (only a hovered kit does, per frame in the Armory's update);
  highlight 0x18d1280 → 0x18d1c00 (scroll to focus) → 0x18d2b60 (grid cell layout, reads the settings for markers)
  is not the avatar. Open: what redresses the Character menu's model (it does on a tab switch).

## 16. Recon 16: seam, cadence, measured cost

- The faint line at the seam was texture filtering at a crop placed right against the other side's edge column.
  Pieces now: left columns 0..330, right 12..343, both scaled 1.02 so they still overlap (left at x -7, right ending
  at 663); side edges 2.04 units.
- Outline upkeep: every frame for 30 frames after the bar is applied or the hover away/back ends (when the game
  resets things), every 10 frames otherwise. The mod logs its own time per frame in the Armory every 600 frames
  (QueryPerformanceCounter) as "Cost in the Armory".
- Card tab model refresh: dropped by the user for now.

## 17. Release 1

- Measured cost of recon 16 in the Armory: 18-80 us per frame on average (mostly 30-45 us), rare 1-3 ms peaks
  (Armory open: the 2928-entry offers table; equip).
- Performance pass: small memory reads share one 4 KB buffer (no allocation per frame); outside the Armory the
  controller is looked for every 10 frames; the viewed item's plan is cached per item and option state and
  re-evaluated every 30 frames (ownership).
- Removed for release: the cost logging and the post-equip preview field logging. Test: `research/test_release.py`.
- Renamed to One Click Armor Set before release: module `mods/alomare/one_click_armor_set`, entry
  `one_click_armor_set.lua`, logs `OneClickArmorSet*.log`, options `alomare.one_click_armor_set.cape/.card`; the
  guid is unchanged. Earlier sections and research files use the old names.
- Loader v18 (shared LuaJIT code cache) needs no change; per its authoring notes the update hook no longer creates a
  closure every frame.
- Next version: a Mod Options Menu option to equip the set when the armor is changed in the Hellpod loadout screen.

## 18. Controller support (revisions)

- Keybind: Mod Bindings Menu `register_binding('alomare.one_click_armor_set.equip_set', 'Equip Set', nil,
  {category = 'One Click Armor Set'})` (automatic slot, no default key); its native {group, action} is read from
  `ModBindingsMenu.assignments`. A press (edge) does what a click does.
- Glyphs are native: EQUIP's prompt (button + 0x520, init 0x17a2fd0) keeps an input action {u32 group, u32 action}
  at +0x1d28 (EQUIP: 0/10); refresh 0x17a3960 asks find_mapping 0x12f9540 (input system [0x347cf18], key
  group<<16|action, the device used last, fallback any) and glyph_texture 0xaba910 (kind = byte0>>4, key u16 @4,
  byte1): pad buttons (0-0xf PlayStation, 0x10-0x1f Xbox), mouse and special keys have textures
  (content/ui/shared/input/*, material 0xc0f3797849262087); other keys get button_key_blank with key_name 0xae47b0,
  keycap width max(16, fitted text width) + 16, height 32 (0x17a48a0, fit_text 0x144e1a0). With the mouse, EQUIP shows
  the left mouse button glyph.
- Revision 1 crashed the game: the glyph used the price group's +0x1598, which is a type-5 background rectangle,
  not an image; set_image on it (restore) corrupted it. Widget type = flags bits 18-21 (3 image, 0xb nine-slice
  image, 7 text, 5 rectangle). Revision 2 uses the first currency icon +0x1968 (type 3; ten at +0x1968 + i*0x158,
  texts at +0x2ae0 + i*0x2b8) and checks the type before every set_image/set_text.
- Revisions 2-3: the pink square and missing keycap were the raw text setter 0x143dd60: it belongs to the prompt's
  type-9 text widgets (0x480 bytes) and copies/zero-fills 0x325 bytes at +0x11c; on the price text (a type-7 label,
  0x2b8 bytes) it wiped the next widget, the currency icon (type 0, material gone = pink). Revision 3's own mapping
  selection works (keyboard F, Xbox X resolved and placed on the padlock's center). Revision 4 sets the key name
  with the #COUNT label on the icon's own amount text (+0x2ae0, drawn above the icon) and never uses 0x143dd60.
- Revision 4 showed the price group's other children (PRICE label, empty currency icons = pink); revision 5 hides
  every other child of +0xdb8 (child list: first +0xe0, next sibling +0xe8, parent +0xf0, address order).
- Revision 5 placement: screen y points up (the bar spans abs y 141..221), and the price refresh re-lays the
  currency icon out right-aligned (anchor/pivot x 1), so correcting from screen positions jittered. Widget layout:
  position +4, size +0xc, anchor +0x2c (set_anchor 0x144f160), pivot +0x3c (set_pivot 0x144f0d0), in parent units.
  Revision 6 sets anchor (0, 0.5), pivot (0.5, 0.5), position (padlock center x 35, 0) and size every frame when
  they differ, and uses EQUIP's prompt colors (glyph/keycap white, name 0.2 gray) instead of the bar's gray.
- Revision 6 test: placement right, but neither the keycap nor the pad glyph drew (log: visible, opacity 1, color 1,
  32x32, right texture). The prompt glyph material 0xc0f3797849262087 needs shader variables the prompt sets right
  after set_image (0x17a2fd0): 0x28723f4d = (1, 1, 0.914, 0) (rva 0x21e2e70), tint 0x851fd4fd = (1, 0.929, 0.929,
  0.929) (+0x1d4c, from rva 0x21e4230), 0x10c353af = 0 (+0x1d6c), via the material of 0x1449400 and the vtable of
  global rva 0x3326308 (+0x28, slot 0x18). Revision 7 draws with the icon's gui_diffuse_map instead (no variables)
  and the tint 0.93 as the widget color.
- Revision 7 test: both drew, but raw: the input textures are channel-packed (black background, green box, dark blue
  outline), so the glyph material's shader is required (the dark name on black was invisible). The variable helper is
  0x14498c0 `(widget, u32 name, const float4 *)`: material via 0x144f6e0 (+0x148 for types 3/0xb), cloned for the
  widget on first use by 0x1449400 (flag 0x40), then the vtable setter. set_image (0x1450230 -> 0x145f0b0) releases
  that clone (0x14692e0) when the material resource changes and keeps it when it's the same, so restoring
  gui_diffuse_map is clean. Revision 8: glyph material + the three variables after set_image, color white.
- Revision 8 test: keycap and pad glyph right, key name hidden under the keycap (log: name visible, opacity 1, 0.2
  gray, 15 wide, centered). Draw layer: i16 at +0xbc, set by 0x14491f0 `(widget, i16)` (the bar init gives each
  icon and its amount the same layer; siblings on one layer draw in no set order). The prompt puts the text over its
  keycap with layer + 1 (0x17a2fd0). 0x1448ad0 is opacity (+0x44), 0x1448690 color (+0x48). The bar text uses font
  style 4 (0x11f79b0) like the prompt's name. Revision 9: name layer = keycap layer + 1 (restored after), and the
  bar text 8 units further right with a glyph (plus half of a keycap's extra width over 32).
- Revision 9 test: all correct. Revision 10, cost: the per-frame upkeep read each widget separately (each read a
  syscall plus a Lua string: 22 reads per Armory frame in the harness). Now one ReadProcessMemory per frame of the
  range covering every watched widget (bar text, price group, its children; computed once per bar) into a reused
  buffer read through float/u32/i16 pointers, no allocation; 9 reads per frame in all (8 are release 1's). The
  device check (every 10 frames) reads the binding bucket into a fixed buffer and keeps the glyph while the chosen
  mapping (byte 0, byte 1, key) is the same. Debug dumps (describe, prompt, lookup trace) removed. Temporary
  "Cost in the Armory" log (QueryPerformanceCounter, every 600 frames); the harness requires it in test builds and
  forbids it in a release.
- Revision 10 test: all correct; 9 binding presses equipped their sets. Measured cost in the Armory 50-110 us per
  frame on average (idle ~70 us; release 1 measured 18-80, mostly 30-45), peaks 0.4-4 ms. Mod Bindings Menu's
  is_down (called every frame for the press) does 4 reads with fresh ffi buffers each. First Armory open of the
  session: "Glyph: none" for ~2 s (3 bars), then correct from the next open (unknown cause: device not yet known or
  the binding bucket not yet filled; the lookup trace was removed).
- Shipped as version 1 (cost log removed; revision zips deleted).

## 20. Version 2: Superstore capes and cards

- Superstore capes and cards are still not linked anywhere in game data. Checked again: capes share no asset hash
  (material/pattern/cape LUTs, decals, paths) with their armor, not even in warbond sets whose pairing is known, and
  the cape texture names aren't in FileDiver's dictionary.
- But the offers table (recon 1 dump, now `_research/equip_set/offers_25480438.log`) shows the release order: from
  warbond 9 on, each release block holds the warbond's items plus one Super Credits armor with a Super Credits cape
  and card (card, cape, armor near each other), and the prices come in tiers: armor/helmet 250/125 -> cape 100,
  card 35; 300/150 -> 120, 40; 400/200 -> 250, 75. `research/build_set_table.py` rule 3 joins a Super Credits cape
  or card without a set to the Super Credits armor of its tier within 16 offers when that pairing is the only one
  on both sides. Every window from 14 to 30 gives the same 25 links; 12 misses two cards 13 offers away. Names agree
  (Stone-Wrought Perseverance / SR-64 Cinderblock, Diagram of the Noblest Payload / O-44 Bonded Pilot, Schema Laid
  Bare / AD-11 Livewire, Badge of Order / BP-77 Grand Juror). Eternal Corona (120, beside BP-77's 250 block) and
  Gilded Quill (50+ offers from any 250 armor) stay out.
- Rule 4 (free sets): a free armor with no cape or card, and exactly one cape and one card without a set within 3
  offers, with no other armor that near: only KDM-500 Outrider (Scraps of Sovereignty and its card). A looser rule
  (a lone card) put a card on FS-05 Marksman, so both are required.
- Rule 5 (`CAPE_PAIRINGS`): capes paired by hand with the armor on the same warbond page or in the same edition,
  from the user's list and the HD2 wiki (2026-09-29): Helldivers Mobilize! P1-P10, Steeled Veterans P1/P3, Cutting
  Edge P1-P3, Democratic Detonation P1-P3, Super Citizen Edition (DP-53 + Will of the People), and Eternal Corona with
  DS-10 Big Game Hunter (user; same 300 tier, 188 offers apart). Steeled Veterans P2 (SA-12) has two capes (Cloak of
  Posterity's Gratitude, Drape of Glory): left out. Each cape goes to the set of the body copy that is in the offers
  table. This fixed a v1 bug: Liberty's Herald and Cresting Honor were linked (dlc/bundle rule) to FS-05 Marksman
  and SC-30 copies that aren't in the offers table, so no player could get their button.
- Player cards stay out: the offer states hold no name keys (checked against the kits' name keys) and the game data
  has no card names, so a card can't be matched to a name reliably.
- Result: 129 sets, 417 items (v1: 371). v1 sets unchanged except the two above (their unownable copies dropped). Set keys are now readable labels (the armor's
  English name, numbered when shared, e.g. B-01 Tactical (1)..(9)); the script treats them as opaque strings.
- A player-editable set table (a CSV read from the log folder) was built and dropped at the user's request.
- `research/test_release.py`: 56 checks, including BFM-77 Reformer's cape and card and Liberty's Herald joining
  their sets.

## 19. Open questions for recon

1. ~~Loadout fields for cape and card~~, ~~card ids~~, ~~viewed item~~ (recon 1).
2. A code-derived path to the viewed item (controller sub-object), and which Armory tab/screen is open.
3. The EQUIP button's rectangle and visibility, to place the drawn button beside it.
4. The helmet, cape and card setters: call them the way the native EQUIP does (UI refresh, sound, save).
5. Names for the older kits and cards (first warbonds, Superstore): curated table.
