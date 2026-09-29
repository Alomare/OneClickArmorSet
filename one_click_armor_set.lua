-- HD2-Addon: mods/alomare/one_click_armor_set

-- One Click Armor Set. In the ship Armory and Character menus, when the viewed helmet, armor, cape or player
-- card belongs to a set with other items you own, the native bar beside EQUIP shows EQUIP <SET> SET (owned/total);
-- clicking it equips the set through the Armory's own commit, as the native EQUIP does.
--
-- Built on what the recons established (NOTES.md): the Armory controller (UI manager row type 224), its detail
-- panel and pending loadout, the offers table for item ids and ownership, and the purchase bar beside EQUIP,
-- driven through the game's own UI functions (the ones Mod Options Menu uses).
-- Options (Mod Options Menu, when installed): include the cape, include the player card (both on by default).
-- Log: %LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\OneClickArmorSet.log

if rawget(_G, 'OneClickArmorSet') then return end

local ffi = require('ffi')
local bit = require('bit')

local M = {version = '2', frames = 0, errors = 0}
rawset(_G, 'OneClickArmorSet', M)

local S = rawget(_G, 'stingray')
local loader = rawget(_G, 'CowboyBingusModLoader')

---------------------------------------------------------------------------------------
-- Game layout (Steam build 25480438)

-- Globals, each read from a rip-relative load (`at` = offset of the 7-byte mov in `text`).
local SIGS = {
    ui_manager = {rva = 0xb938d4, at = 0,
                  text = '48 8B 35 ?? ?? ?? ?? 33 FF 0F B6 EA 48 8B D9 39 BE 98 67 00 00 0F 86 9B 00 00 00 90 8B C7 48 05 7A 06 00 00 48 03 C0 81'},
    -- Optional: the engine root, whose +0x10 -> +0x3e8 is the localization lookup `const char *(uint32 key)`
    -- (the chain HD2-Transmog's extra_localized_text proves). Without it the set names are shown in English.
    engine_root = {rva = 0x17802e0, at = 6, optional = true,
                   text = '40 53 48 83 EC 20 48 8B 05 ?? ?? ?? ?? 8B D9 48 8B 48 10 48 8B 81 E8 03 00 00 8B CB FF D0'},
    -- Optional: from the native armor EQUIP's customization event (game.dll + 0x145801c): the players global, the
    -- "no local player" id and the component manager. Without them the 3D preview isn't redressed.
    players = {rva = 0x145801c, at = 0, optional = true, text = '48 8B 05 ?? ?? ?? ?? 39 90 88 00 00 00 74 0D 48 8B 80 E8 00 00 00 48 83 C0 08 EB 07 48 8D 05 ?? ?? ?? ?? '
                    .. '8B 00 3B 05 ?? ?? ?? ?? 0F 84 ?? ?? ?? ?? 4C 8B 15 ?? ?? ?? ?? 45 8B 4A 28 45 8B 5A 30 44 0F AF D8'},
    no_player = {rva = 0x145801c, at = 0x1c, optional = true, address = true, text = '48 8B 05 ?? ?? ?? ?? 39 90 88 00 00 00 74 0D 48 8B 80 E8 00 00 00 48 83 C0 08 EB 07 48 8D 05 ?? ?? ?? ?? '
                    .. '8B 00 3B 05 ?? ?? ?? ?? 0F 84 ?? ?? ?? ?? 4C 8B 15 ?? ?? ?? ?? 45 8B 4A 28 45 8B 5A 30 44 0F AF D8'},
    components = {rva = 0x145801c, at = 0x31, optional = true, text = '48 8B 05 ?? ?? ?? ?? 39 90 88 00 00 00 74 0D 48 8B 80 E8 00 00 00 48 83 C0 08 EB 07 48 8D 05 ?? ?? ?? ?? '
                    .. '8B 00 3B 05 ?? ?? ?? ?? 0F 84 ?? ?? ?? ?? 4C 8B 15 ?? ?? ?? ?? 45 8B 4A 28 45 8B 5A 30 44 0F AF D8'},
    -- Optional: the input system (its binding map at +0xa7ad0 is the one Mod Bindings Menu edits), from the prompt
    -- glyph refresh (0x17a3960). Without it the button shows no key glyph.
    input = {rva = 0x17a3992, at = 7, optional = true,
             text = '48 8B 91 28 1D 00 00 48 8B 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 85 C0 74 13 8B 10 44 0F B6 48 01 0F B7 48 04 C1 EA 04'},
    progression = {rva = 0x136f968, at = 8,
                   text = '00 00 00 4C 89 74 24 50 4C 8B 35 ?? ?? ?? ?? 49 03 D6 8B 8A F8 1C 00 00 83 F9 01 76 42 8D 41 FE A9 FD FF FF FF 75 1E 80'},
}
-- Native functions, verified by their first bytes before use. Addresses pass as integers.
local NATIVE = {
    set_visible = {0x144cfb0, '48 83 EC 28 44 8B 01 4C 8B D1 41 8B C0 45 8B C8', 'void (*)(uint64_t, uint8_t)'},
    set_label = {0x143bf90, '48 83 EC 28 4C 8B D9 39 91 10 01 00 00 0F 84 80', 'void (*)(uint64_t, uint32_t)'},
    set_string_arg = {0x143c950, '40 53 48 83 EC 20 48 8B D9 48 81 C1 10 01 00 00',
                      'void (*)(uint64_t, uint32_t, const char *)'},
    clear_args = {0x143a0f0, '80 B9 58 01 00 00 00 C6 81 58 01 00 00 00 0F 97', 'uint8_t (*)(uint64_t)'},
    -- The purchase bar's own "nothing to buy" update: hides its content groups.
    bar_empty = {0x1919250, '48 83 EC 28 8B 81 78 03 00 00 4C 8B C9 44 8B C0', 'void (*)(uint64_t)'},
    set_color = {0x1448690, '48 89 5C 24 10 48 89 6C 24 18 56 57 41 57 48 83 EC 20 F3 0F 10 41 48',
                 'void (*)(uint64_t, const float *)'},
    -- Posts a UI sound event; the first argument is unused.
    play_sound = {0x1327f50, '48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 20 48', 'void (*)(uint64_t, uint32_t)'},
    -- What the Armory runs when its equipped offer changes: the item's equip sound, then the grid's equipped
    -- offer and markers.
    equip_sound = {0x18d0210, '40 53 48 83 EC 20 4C 8B 0D ?? ?? ?? ?? 41 8B 81 B0 42 00 00', 'void (*)(uint64_t, uint32_t)'},
    -- Sets the EQUIP button's state (5 equippable, 6 equipped), as the detail panel does.
    button_state = {0x191a720, '48 89 5C 24 10 57 48 83 EC 20 8B FA 48 8B D9 83 FA 0B 77 2E', 'void (*)(uint64_t, uint32_t)'},
    -- The grid's highlight (grid, offer): focuses the offer's cell, as the cursor does when hovering it.
    highlight = {0x18d1280, '48 89 5C 24 18 55 56 57 48 83 EC 20 44 8B 89 14 1F 09 00 33 ED 48 8B F9 44 8B C5 8B F5 45 85 C9',
                 'uint8_t (*)(uint64_t, uint32_t)', optional = true},
    -- The Armory's hover refresh (preview manager = controller + 0x7f718): re-shows the hovered item's details and
    -- preview; the native EQUIP calls it after its commit.
    preview_notify = {0x18d7210, '40 57 48 83 EC 20 83 B9 88 8C 17 00 01 48 8B F9', 'void (*)(uint64_t)'},
    mark_equipped = {0x18d10d0, '48 89 4C 24 08 56 41 55 41 56 48 83 EC 30 33 F6 48 89 5C 24 58',
                     'void (*)(uint64_t, uint32_t)'},
    -- An image widget's material and texture (both resource hashes); the bar's icons and EQUIP's outline use it.
    set_image = {0x1450230, '48 89 5C 24 10 57 48 83 EC 30 49 8B D8 48 8B F9', 'void (*)(uint64_t, uint64_t, uint64_t, uint8_t)'},
    -- An image widget's crop: (widget, uv min, uv max).
    set_uv = {0x143eef0, '4C 89 44 24 18 48 89 54 24 10 48 83 EC 28 F3 0F 10 81 14 01 00 00',
              'void (*)(uint64_t, ESB_vec2, ESB_vec2)'},
    set_size = {0x1447160, '48 89 5C 24 18 48 89 6C 24 20 48 89 54 24 10 56 57 41 57 48 83 EC 20 F3 0F 10 41 0C',
                'void (*)(uint64_t, ESB_vec2)'},
    set_opacity = {0x1448ad0, '40 57 48 83 EC 20 F3 0F 10 41 44 48 8B F9 0F 2E', 'void (*)(uint64_t, float)'},
    -- A widget's anchor (+0x2c: where in the parent its position is measured from, 0..1) and pivot (+0x3c: which
    -- point of the widget sits there, 0..1).
    set_anchor = {0x144f160, '48 83 EC 28 F3 0F 10 41 2C 4C 8B C9 48 89 54 24 30 0F 2E 44 24 30 7A 10',
                  'void (*)(uint64_t, ESB_vec2)', optional = true},
    set_pivot = {0x144f0d0, '48 83 EC 28 F3 0F 10 41 3C 4C 8B C9 48 89 54 24 30 0F 2E 44 24 30 7A 10',
                 'void (*)(uint64_t, ESB_vec2)', optional = true},
    set_position = {0x14476a0, '48 89 5C 24 18 48 89 6C 24 20 48 89 54 24 10 56 57 41 57 48 83 EC 20 F3 0F 10 41 04',
                    'void (*)(uint64_t, ESB_vec2)'},
    -- Queues an entity event (entity id, event, component state); the native armor EQUIP posts 0xbd5b4583.
    entity_event = {0xfd97e0, '48 89 6C 24 18 56 41 56 41 57 48 83 EC 30 48 8B 05 ?? ?? ?? ?? 4D 8B F0',
                    'void (*)(uint32_t, uint32_t, uint64_t)', optional = true},
    -- Key glyphs, as the game's prompt buttons draw them (0x17a3960): the mapping of an input action {u32 group,
    -- u32 action} for the device used last (fallback: any), the glyph texture of a mapping (0 for keys drawn as a
    -- keycap with their name), and the name of a key. (The prompt's raw text setter 0x143dd60 is for its own text
-- widgets: on a label text it writes 0x325 bytes and wipes the next widget, so key names go through #COUNT.)
    find_mapping = {0x12f9540, '44 88 44 24 18 48 89 4C 24 08 53 55 56 57 41 54 41 55 41 56 41 57 48 83 EC 48',
                    'const uint8_t *(*)(uint64_t, uint64_t, uint8_t)', optional = true},
    glyph_texture = {0xaba910, '48 89 74 24 18 57 48 83 EC 20 45 0F B7 D0 41 8B F1 48 8B F9 83 FA 08 75 2B',
                     'uint64_t *(*)(uint64_t *, int32_t, uint16_t, uint32_t, uint32_t)', optional = true},
    key_name = {0xae47b0, '48 89 74 24 10 57 48 83 EC 20 8B F2 83 F9 08 0F 85 7B 01 00 00',
                'const char *(*)(int32_t, uint32_t, uint8_t)', optional = true},
    -- A shader variable of a widget's material (a float4 by name hash), cloning the material for the widget first;
    -- the prompt glyphs' material draws nothing without its variables (0x17a2fd0 sets them after set_image).
    set_variable = {0x14498c0, '48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 20 49 8B D8 8B FA 48 8B F1 E8',
                    'void (*)(uint64_t, uint32_t, const float *)', optional = true},
    -- A widget's draw layer (i16 at +0xbc): siblings on one layer draw in no set order, so the prompt puts its key
    -- name on the keycap's layer + 1.
    set_layer = {0x14491f0, '48 83 EC 28 4C 8B C9 66 39 91 BC 00 00 00 75 07 32 C0 48 83 C4 28 C3',
                 'uint8_t (*)(uint64_t, int16_t)', optional = true},
    -- The Armory's commit: copies the controller's pending loadout to the settings and applies it to the player.
    commit = {0x1455a90, '48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 48 89 7C 24 20 41 56 48 83 EC 20 48 8B 1D '
                         .. '?? ?? ?? ?? 40 32 FF 8B 81 90 00 00 00 44 0F B6 F2 39 43 40', 'void (*)(uint64_t, uint8_t)'},
}
local OFFERS = {count = 0x1ce0, entries = 0xb9ce4, entry_size = 24, states = 0x1ce4, state_size = 184, max = 8192,
                status = 0x14, disabled = 0xb4}
local UI = {count = 0x166c, rows = 0x1670, row_size = 16, max_rows = 64, armory_type = 224}
local CTL = {
    applied = 0x38, pending = 0x64, block = 0x2c,   -- loadout blocks: last applied, pending (commit copies one to other)
    detail = 0x119488,                               -- detail panel
    grid = 0x7fde8,                                  -- item grid (its equipped offer at +0x9298c)
    viewed = 0x136f5c,                               -- the viewed item (recon 1)
    preview_manager = 0x7f718,
}
local SLOT_FIELD = {h = 0x04, c = 0x08, b = 0x0c, p = 0x1c}  -- in a loadout block: helmet, cape, body, card id
local DETAIL = {offer = 0xbe00c, button = 0x49f0, bar = 0x91c0, preview = 0x20640}
local PREVIEW_KIT = 0xdc0  -- the preview's cached kit id
local WIDGET = {flags = 0, pos = 4, size = 12, color = 0x48, alpha = 84, scale_x = 100, scale_y = 140, x = 148, y = 156,
                visible = 0x10, label = 0x110}
-- Purchase bar children: the "locked" group is the one used, its padlock hidden and its text showing the label.
local BAR = {group = 0x378, icon = 0x488, text = 0x5e0,
             -- the other content group: its warning icon becomes the outline's right half, its text stays hidden
             group_b = 0x898, icon_b = 0x9a8, text_b = 0xb00, width = 656}
-- EQUIP's own outline: its button's texture C (material gui_white_alpha, 344x72: a 2-unit rectangle whose side edges
-- are columns 7-8 and 335-336, drawn at -7,-6 around the 330x60 button). The bar is 656 wide, so its outline spans
-- 670, drawn as two pieces of the texture on the padlock and warning images: the left one columns 0-330, the right
-- one columns 12-343, each cropped a few columns away from the other side's edge (the texture filter would blend
-- it into a faint line at the seam) and scaled 2% so they overlap; the side edges stay practically at native width.
local OUTLINE = {material = 0xf6978e86e4f4b0d5ull, texture = 0x0b6a14c35af5f4e4ull, tex_w = 344, h = 72, margin = 7,
                 left_cols = 331, right_from = 12, scale = 1.02}
-- The two icons' own images, restored afterwards (the bar's init: material gui_diffuse_map).
local ICON_IMAGES = {[0x488] = {0x57fcf14ad069020bull, 0x30d59fcc1d991407ull}, [0x9a8] = {0x57fcf14ad069020bull, 0x61c5699658bec440ull}}
local IMAGE_UV, IMAGE_TEXTURE, IMAGE_MATERIAL = 0x114, 0x150, 0x148
local LAYOUT = {anchor = 0x2c, pivot = 0x3c, layer = 0xbc}
local DIFFUSE_MATERIAL = 0x57fcf14ad069020bull  -- the bar's images' material (its init)
-- The bar's price group (hidden for owned items, built by 0x19176a0): its first currency icon (+0x1968, an image)
-- becomes the key glyph or keycap, and its amount text (+0x2ae0, a label added after it, so drawn above it) the
-- key's name. (+0x1598 is a plain background rectangle, not an image.)
local PRICE = {group = 0xdb8, border = 0xec8, image = 0x1968, text = 0x2ae0}
-- A widget's children (add_child 0x144c5c0): first child at +0xe0, next sibling at +0xe8, in address order.
local CHILD = {first = 0xe0, next = 0xe8, max = 64}
-- Widget types (flags bits 18-21): only images take set_image, only label texts take labels.
local WIDGET_TYPE = {image = 3, text = 7}
-- EQUIP's own prompt (button + 0x520, built by 0x17a2fd0): glyph image +0x330, keycap +0x488, key name +0x610.
local PROMPT = {offset = 0x520, glyph = 0x330, keycap = 0x488, name = 0x610, texture = 0x1d10, action = 0x1d28}
-- The glyph's colors: EQUIP's own prompt (glyph and keycap white, key name dark gray).
local GLYPH_COLOR, KEYCAP_TEXT_COLOR = {1, 1, 1}, {0.2, 0.2, 0.2}  -- EQUIP's prompt: glyph white, key name dark gray
local KEYCAP = {min = 16, h = 32}  -- the game's keycap sizing constants (0x17a48a0)
local TEXT_MARGIN = 0.5  -- the text moves to this fraction of its x (it made room for the padlock, now hidden)
local OPACITY = 0x44
local TEXT_TEMPLATE, TEXT_KEY = 0xc67c7faf, 0xab2a7b35  -- '#COUNT' and the COUNT key: shows any string
-- Feedback: the EQUIP button's own hover sound (its set_hovered, 0x191a6b0, plays +0x47bc when hover starts and
-- nothing when it ends), text colors, and how long a click flashes.
local EQUIP_HOVER_SOUND = 0x47bc
local DEFAULT_HOVER_SOUND = 0x65e34ad8  -- what the button class sets there
local CARD_EQUIP_SOUND = 0x80680c11      -- the Character menu plays it when a player card is equipped
local EQUIPPED_STATE = 6  -- EQUIP button state for "equipped" (5: equippable)
local COLORS = {hover = {1, 1, 1}, press = {1, 0.85, 0.25}}
local FLASH_FRAMES = 12
local SLOT_NAMES = {h = 'HELMET', b = 'ARMOR', c = 'CAPE', p = 'CARD'}
local SLOT_ORDER = {'h', 'b', 'c', 'p'}
-- The label per game language: {with the set name, without}, then " (owned/total)". The game has no word for
-- "set", so these are the mod's own; the language is recognized by the game's text for key 0x1b5b48a1.
local LANGUAGE_KEY = 0x1b5b48a1
local LANGUAGES = {
    ['LOW FUNDS'] = 'en', ['SALDO INSUFICIENTE'] = 'bp', ['POUCOS FUNDOS'] = 'pt', ['DINERO INSUFICIENTE'] = 'es',
    ['POCOS FONDOS'] = 'ms', ['FONDS FAIBLES'] = 'fr', ['FEHLENDE MITTEL'] = 'de', ['FONDI INSUFFICIENTI'] = 'it',
    ['MAŁO FUNDUSZY'] = 'pl', ['НЕ ХВАТАЕТ СРЕДСТВ'] = 'ru', ['資金不足'] = 'jp', ['자금 부족'] = 'ko',
    ['資金短缺'] = 'tc',
}
local LABELS = {
    en = {'EQUIP %s SET', 'EQUIP SET'},
    bp = {'EQUIPAR CONJUNTO %s', 'EQUIPAR CONJUNTO'}, pt = {'EQUIPAR CONJUNTO %s', 'EQUIPAR CONJUNTO'},
    es = {'EQUIPAR CONJUNTO %s', 'EQUIPAR CONJUNTO'}, ms = {'EQUIPAR CONJUNTO %s', 'EQUIPAR CONJUNTO'},
    fr = {"ÉQUIPER L'ENSEMBLE %s", "ÉQUIPER L'ENSEMBLE"}, de = {'%s-SET AUSRÜSTEN', 'SET AUSRÜSTEN'},
    it = {'EQUIPAGGIA SET %s', 'EQUIPAGGIA SET'}, pl = {'WYPOSAŻ ZESTAW %s', 'WYPOSAŻ ZESTAW'},
    ru = {'ПРИМЕНИТЬ КОМПЛЕКТ %s', 'ПРИМЕНИТЬ КОМПЛЕКТ'}, jp = {'%sセットを装備', 'セットを装備'},
    ko = {'%s 세트 장착', '세트 장착'}, tc = {'裝備%s套裝', '裝備套裝'},
}
-- Mod Options Menu toggles: slot -> option id. Without the menu every slot is included.
local OPTIONS = {
    c = {id = 'alomare.one_click_armor_set.cape', label = 'Include Cape',
         description = 'EQUIP SET also equips the cape of the set.'},
    p = {id = 'alomare.one_click_armor_set.card', label = 'Include Player Card',
         description = 'EQUIP SET also equips the player card of the set.'},
}

-- BEGIN SET TABLE (generated by research/build_set_table.py)
-- [item id] = {set, slot}: slot h helmet, b body, c cape, p player card
local SETS = {
    [0xb407147e] = {'A-35 Recon', 'h'},
    [0xd879973a] = {'A-35 Recon', 'b'},
    [0xe4c12748] = {'A-35 Recon', 'c'},
    [0x1a96ce6b] = {'A-35 Recon', 'p'},
    [0x9f3f8a17] = {'A-9 Helljumper', 'h'},
    [0x16e1b9d3] = {'A-9 Helljumper', 'b'},
    [0x52f858a8] = {'A-9 Helljumper', 'c'},
    [0x1ad21eb0] = {'A-9 Helljumper', 'p'},
    [0xae8f7b4c] = {'AC-1 Dutiful', 'h'},
    [0xac4235b3] = {'AC-1 Dutiful', 'b'},
    [0x38068beb] = {'AC-1 Dutiful', 'c'},
    [0x3683736d] = {'AC-1 Dutiful', 'p'},
    [0x289884f4] = {'AC-2 Obedient', 'h'},
    [0x55fd699b] = {'AC-2 Obedient', 'b'},
    [0x4260b28c] = {'AC-2 Obedient', 'c'},
    [0xbf6672b5] = {'AC-2 Obedient', 'p'},
    [0x24e765ba] = {'AD-11 Livewire', 'h'},
    [0xf8fadb6c] = {'AD-11 Livewire', 'b'},
    [0xf625724c] = {'AD-11 Livewire', 'c'},
    [0x1de8ce83] = {'AD-11 Livewire', 'p'},
    [0xdcce533f] = {'AD-26 Bleeding Edge', 'h'},
    [0x01c2a674] = {'AD-26 Bleeding Edge', 'b'},
    [0xebb26e73] = {'AD-26 Bleeding Edge', 'c'},
    [0x5e2635d0] = {'AD-26 Bleeding Edge', 'p'},
    [0xf8c6437f] = {'AD-49 Apollonian', 'h'},
    [0x0a18c237] = {'AD-49 Apollonian', 'b'},
    [0x1674440a] = {'AD-49 Apollonian', 'c'},
    [0x75a963d5] = {'AD-49 Apollonian', 'p'},
    [0x2f748b84] = {'AF-02 Haz-Master', 'h'},
    [0xe9add047] = {'AF-02 Haz-Master', 'b'},
    [0xfc920ae4] = {'AF-02 Haz-Master', 'c'},
    [0xce411f5e] = {'AF-02 Haz-Master', 'p'},
    [0xde575ea9] = {'AF-50 Noxious Ranger', 'h'},
    [0x5cc09255] = {'AF-50 Noxious Ranger', 'b'},
    [0x14712621] = {'AF-50 Noxious Ranger', 'c'},
    [0x093eb870] = {'AF-50 Noxious Ranger', 'p'},
    [0x9ad6358e] = {'AF-52 Lockdown', 'h'},
    [0xf6303500] = {'AF-52 Lockdown', 'b'},
    [0xdf5f7ccb] = {'AF-91 Field Chemist', 'h'},
    [0x100a5dcd] = {'AF-91 Field Chemist', 'b'},
    [0xfdbf4741] = {'B-01 Tactical (1)', 'h'},
    [0x1369b95b] = {'B-01 Tactical (1)', 'b'},
    [0x40a7d694] = {'B-01 Tactical (2)', 'h'},
    [0x1d0e3431] = {'B-01 Tactical (2)', 'b'},
    [0x2180eb8d] = {'B-01 Tactical (3)', 'h'},
    [0x250fd6c1] = {'B-01 Tactical (3)', 'b'},
    [0x261c4a52] = {'B-01 Tactical (4)', 'h'},
    [0x61b31723] = {'B-01 Tactical (4)', 'b'},
    [0x45d80a38] = {'B-01 Tactical (5)', 'h'},
    [0x4f7fb2bd] = {'B-01 Tactical (5)', 'b'},
    [0xb4027b70] = {'B-01 Tactical (6)', 'h'},
    [0x6351a9aa] = {'B-01 Tactical (6)', 'b'},
    [0xdf8e4ada] = {'B-01 Tactical (7)', 'h'},
    [0x6d30f386] = {'B-01 Tactical (7)', 'b'},
    [0x8ce73dae] = {'B-01 Tactical (8)', 'h'},
    [0x708451e9] = {'B-01 Tactical (8)', 'b'},
    [0xee7019ed] = {'B-01 Tactical (9)', 'h'},
    [0xd59566d5] = {'B-01 Tactical (9)', 'b'},
    [0x48226e8f] = {'B-08 Light Gunner', 'h'},
    [0x1d20d6ee] = {'B-08 Light Gunner', 'b'},
    [0x95ac1cfd] = {'B-16 Battle-Scarred Veteran', 'h'},
    [0xb08e0939] = {'B-16 Battle-Scarred Veteran', 'b'},
    [0xec49526f] = {'B-22 Model Citizen', 'h'},
    [0xcb7e9736] = {'B-22 Model Citizen', 'b'},
    [0x41211c7f] = {'B-24 Enforcer', 'h'},
    [0x803276ce] = {'B-24 Enforcer', 'b'},
    [0xd11da85b] = {'B-27 Fortified Commando', 'h'},
    [0xd2c578e1] = {'B-27 Fortified Commando', 'b'},
    [0x2d61f0f9] = {'BFM-16 Tanker', 'h'},
    [0x8c6ae37c] = {'BFM-16 Tanker', 'b'},
    [0x4dcec343] = {'BFM-16 Tanker', 'c'},
    [0xc815b857] = {'BFM-16 Tanker', 'p'},
    [0x37c61642] = {'BFM-220 Ironclad', 'h'},
    [0xf8b8cf9b] = {'BFM-220 Ironclad', 'b'},
    [0x8a1d4c1c] = {'BFM-220 Ironclad', 'c'},
    [0xb84034ef] = {'BFM-220 Ironclad', 'p'},
    [0xede9d6b7] = {'BFM-77 Reformer', 'h'},
    [0x3412f5e4] = {'BFM-77 Reformer', 'b'},
    [0x1a0297e0] = {'BFM-77 Reformer', 'c'},
    [0xcdea8cb2] = {'BFM-77 Reformer', 'p'},
    [0x3b5af7c7] = {'BP-20 Correct Officer', 'h'},
    [0x40c6635c] = {'BP-20 Correct Officer', 'b'},
    [0x4470f6ff] = {'BP-20 Correct Officer', 'c'},
    [0x0b9d123e] = {'BP-20 Correct Officer', 'p'},
    [0x7fa97f66] = {'BP-32 Jackboot', 'h'},
    [0x09b08ec4] = {'BP-32 Jackboot', 'b'},
    [0x3bf70de7] = {'BP-32 Jackboot', 'c'},
    [0x79d2f37d] = {'BP-32 Jackboot', 'p'},
    [0x1805a245] = {'BP-77 Grand Juror', 'h'},
    [0xf4598295] = {'BP-77 Grand Juror', 'b'},
    [0xb545a9bf] = {'BP-77 Grand Juror', 'c'},
    [0x61334e4b] = {'BP-77 Grand Juror', 'p'},
    [0x65c07df2] = {'CE-07 Demolition Specialist', 'h'},
    [0x5a17d6d6] = {'CE-07 Demolition Specialist', 'b'},
    [0x79a037c0] = {'CE-07 Demolition Specialist', 'c'},
    [0x89b1b9e3] = {'CE-101 Guerilla Gorilla ', 'h'},
    [0xdee800a8] = {'CE-101 Guerilla Gorilla ', 'b'},
    [0xac5d49f9] = {'CE-27 Ground Breaker', 'h'},
    [0x7edf6505] = {'CE-27 Ground Breaker', 'b'},
    [0x1264718e] = {'CE-27 Ground Breaker', 'c'},
    [0xaffb955b] = {'CE-35 Trench Engineer', 'h'},
    [0xfb4b1254] = {'CE-35 Trench Engineer', 'b'},
    [0x8a5ec750] = {'CE-35 Trench Engineer', 'c'},
    [0x4e0785ae] = {'CE-64 Grenadier', 'h'},
    [0x674671a0] = {'CE-64 Grenadier', 'b'},
    [0x97d7668f] = {'CE-67 Titan', 'h'},
    [0xf34064ac] = {'CE-67 Titan', 'b'},
    [0xee2e8ce0] = {'CE-74 Breaker', 'h'},
    [0x26bf31fe] = {'CE-74 Breaker', 'b'},
    [0xfcde237a] = {'CE-81 Juggernaut', 'h'},
    [0x97cf0a8a] = {'CE-81 Juggernaut', 'b'},
    [0xc25abb74] = {'CM-09 Bonesnapper (1)', 'h'},
    [0x1c6c05fa] = {'CM-09 Bonesnapper (1)', 'b'},
    [0xee755525] = {'CM-09 Bonesnapper (1)', 'c'},
    [0x4db09ca4] = {'CM-09 Bonesnapper (2)', 'h'},
    [0x7d96d0c6] = {'CM-09 Bonesnapper (2)', 'b'},
    [0xb18b6c66] = {'CM-10 Clinician', 'h'},
    [0x7a07031f] = {'CM-10 Clinician', 'b'},
    [0x203f720c] = {'CM-14 Physician', 'h'},
    [0x38aa207d] = {'CM-14 Physician', 'b'},
    [0xf8ea01ad] = {'CM-14 Physician', 'c'},
    [0xa67010e7] = {'CM-17 Butcher', 'h'},
    [0x95903adf] = {'CM-17 Butcher', 'b'},
    [0xbd1e5e84] = {'CM-21 Trench Paramedic', 'h'},
    [0xd52bb413] = {'CM-21 Trench Paramedic', 'b'},
    [0xfdb93622] = {'CPG-48 Sapper', 'h'},
    [0x5f075dc5] = {'CPG-48 Sapper', 'b'},
    [0x9cc5cc35] = {'CPG-48 Sapper', 'c'},
    [0xb24c362e] = {'CPG-48 Sapper', 'p'},
    [0x37442029] = {'CPH-26 Commandant', 'h'},
    [0x242702a5] = {'CPH-26 Commandant', 'b'},
    [0x3d7e4ac7] = {'CPH-26 Commandant', 'c'},
    [0x0669be82] = {'CPH-26 Commandant', 'p'},
    [0xa5574ac2] = {'CPR-80 Bulwark', 'h'},
    [0x9c0bbe91] = {'CPR-80 Bulwark', 'b'},
    [0xb46ba4f4] = {'CPR-80 Bulwark', 'c'},
    [0xc9030903] = {'CPR-80 Bulwark', 'p'},
    [0x91d773c8] = {'CW-22 Kodiak', 'h'},
    [0x69bc2d4a] = {'CW-22 Kodiak', 'b'},
    [0xab29952a] = {'CW-22 Kodiak', 'c'},
    [0x24143cc1] = {'CW-22 Kodiak', 'p'},
    [0xcd3d20dc] = {'CW-36 Winter Warrior', 'h'},
    [0x0b5cd386] = {'CW-36 Winter Warrior', 'b'},
    [0xff46327a] = {'CW-36 Winter Warrior', 'c'},
    [0xcb8352fe] = {'CW-36 Winter Warrior', 'p'},
    [0x63aa42c5] = {'CW-4 Arctic Ranger', 'h'},
    [0xb92e1781] = {'CW-4 Arctic Ranger', 'b'},
    [0xe8072038] = {'CW-4 Arctic Ranger', 'c'},
    [0x398cf58e] = {'CW-4 Arctic Ranger', 'p'},
    [0x7c59469b] = {'CW-9 White Wolf', 'h'},
    [0xb3deb5d9] = {'CW-9 White Wolf', 'b'},
    [0x584ab37b] = {'DP-00 Tactical', 'h'},
    [0x3f1bec1a] = {'DP-00 Tactical', 'b'},
    [0xef6d2ad3] = {'DP-11 Champion of the People', 'h'},
    [0xe3aaa79d] = {'DP-11 Champion of the People', 'b'},
    [0x6e72f493] = {'DP-11 Champion of the People', 'c'},
    [0xdbf9ca34] = {'DP-11 Champion of the People', 'c'},
    [0x5c3087d2] = {'DP-40 Hero of the Federation', 'h'},
    [0xb513fd54] = {'DP-40 Hero of the Federation', 'b'},
    [0xa5a700cb] = {'DP-40 Hero of the Federation', 'c'},
    [0xf5dd3c6f] = {'DP-40 Hero of the Federation', 'c'},
    [0x085838c1] = {'DP-53 Savior of the Free', 'h'},
    [0xfd456de0] = {'DP-53 Savior of the Free', 'b'},
    [0x77ae3af0] = {'DP-53 Savior of the Free', 'c'},
    [0xb19d6c0a] = {'DP-8 Mountain-Scaled', 'h'},
    [0xa9a71fe7] = {'DP-8 Mountain-Scaled', 'b'},
    [0x5a32915a] = {'DP-8 Mountain-Scaled', 'c'},
    [0x1ae319b6] = {'DP-8 Mountain-Scaled', 'p'},
    [0x52791e64] = {'DS-10 Big Game Hunter', 'h'},
    [0xc60c706d] = {'DS-10 Big Game Hunter', 'b'},
    [0xf511b688] = {'DS-10 Big Game Hunter', 'c'},
    [0xe330c30d] = {'DS-10 Big Game Hunter', 'p'},
    [0xf2dcc254] = {'DS-191 Scorpion', 'h'},
    [0x0ade6719] = {'DS-191 Scorpion', 'b'},
    [0x7eee690b] = {'DS-191 Scorpion', 'c'},
    [0xf20e11d6] = {'DS-191 Scorpion', 'p'},
    [0xee2e3efa] = {'DS-42 Federation\'s Blade', 'h'},
    [0x4a545f06] = {'DS-42 Federation\'s Blade', 'b'},
    [0x30d1157a] = {'DS-42 Federation\'s Blade', 'c'},
    [0x60bc39e8] = {'DS-42 Federation\'s Blade', 'p'},
    [0xd1a64ac3] = {'EX-00 Prototype X', 'h'},
    [0xd7b2fd5d] = {'EX-00 Prototype X', 'b'},
    [0xf509b363] = {'EX-00 Prototype X', 'c'},
    [0x8abccc54] = {'EX-03 Prototype 3', 'h'},
    [0x24e3d6ba] = {'EX-03 Prototype 3', 'b'},
    [0x2bcc4463] = {'EX-03 Prototype 3', 'c'},
    [0x212df664] = {'EX-16 Prototype 16', 'h'},
    [0xaa32b384] = {'EX-16 Prototype 16', 'b'},
    [0xc1105fbc] = {'EX-16 Prototype 16', 'c'},
    [0x0c0af708] = {'FS-05 Marksman (1)', 'h'},
    [0x0f41a67e] = {'FS-05 Marksman (1)', 'h'},
    [0x36456057] = {'FS-05 Marksman (1)', 'h'},
    [0x4452e375] = {'FS-05 Marksman (1)', 'h'},
    [0x529efe65] = {'FS-05 Marksman (1)', 'h'},
    [0xd915a671] = {'FS-05 Marksman (1)', 'h'},
    [0xe417ae7b] = {'FS-05 Marksman (1)', 'h'},
    [0xecabadbf] = {'FS-05 Marksman (1)', 'b'},
    [0xd45f0974] = {'FS-05 Marksman (1)', 'c'},
    [0x7b6406da] = {'FS-05 Marksman (2)', 'h'},
    [0x58dbdacd] = {'FS-05 Marksman (2)', 'b'},
    [0x5642fa1a] = {'FS-11 Executioner', 'h'},
    [0x77947add] = {'FS-11 Executioner', 'b'},
    [0x1e9444f9] = {'FS-23 Battle Master', 'h'},
    [0x26d572a4] = {'FS-23 Battle Master', 'b'},
    [0xc24b74f5] = {'FS-23 Battle Master', 'c'},
    [0x38b05b83] = {'FS-34 Exterminator', 'h'},
    [0x8bd85dd2] = {'FS-34 Exterminator', 'b'},
    [0x7934ed8b] = {'FS-37 Ravager', 'h'},
    [0x1f9bfa78] = {'FS-37 Ravager', 'b'},
    [0xda64ee0d] = {'FS-38 Eradicator', 'h'},
    [0x20a85cc1] = {'FS-38 Eradicator', 'b'},
    [0x056848e9] = {'FS-55 Devastator', 'h'},
    [0xd3461392] = {'FS-55 Devastator', 'b'},
    [0x7d1003d0] = {'FS-55 Devastator', 'c'},
    [0x2e15716b] = {'FS-61 Dreadnought', 'h'},
    [0x537e8e45] = {'FS-61 Dreadnought', 'b'},
    [0x175295c9] = {'FS-61 Dreadnought', 'c'},
    [0x58d5cd85] = {'GS-11 Democracy\'s Deputy', 'h'},
    [0x407ab98a] = {'GS-11 Democracy\'s Deputy', 'b'},
    [0x1af6ba63] = {'GS-11 Democracy\'s Deputy', 'c'},
    [0x0b6d654d] = {'GS-11 Democracy\'s Deputy', 'p'},
    [0xf646f083] = {'GS-17 Frontier Marshal', 'h'},
    [0x16eeb860] = {'GS-17 Frontier Marshal', 'b'},
    [0xbca406f6] = {'GS-17 Frontier Marshal', 'c'},
    [0x36957094] = {'GS-17 Frontier Marshal', 'p'},
    [0x24fdb2c0] = {'GS-66 Lawmaker', 'h'},
    [0xb482b460] = {'GS-66 Lawmaker', 'b'},
    [0x3a28a2e7] = {'GS-66 Lawmaker', 'c'},
    [0xd79f3388] = {'GS-66 Lawmaker', 'p'},
    [0xb1d021ff] = {'I-09 Heatseeker', 'h'},
    [0x2d1dd830] = {'I-09 Heatseeker', 'b'},
    [0x099116e7] = {'I-09 Heatseeker', 'c'},
    [0xe0722d23] = {'I-09 Heatseeker', 'p'},
    [0x73893816] = {'I-102 Draconaught', 'h'},
    [0x5662c173] = {'I-102 Draconaught', 'b'},
    [0xe67e5867] = {'I-102 Draconaught', 'c'},
    [0x38f7ea58] = {'I-102 Draconaught', 'p'},
    [0xd0ce5bc7] = {'I-44 Salamander', 'h'},
    [0x223a3b4b] = {'I-44 Salamander', 'b'},
    [0xfd428984] = {'I-92 Fire Fighter', 'h'},
    [0x8c83c789] = {'I-92 Fire Fighter', 'b'},
    [0x8af14536] = {'IE-12 Righteous', 'h'},
    [0x9fa96490] = {'IE-12 Righteous', 'b'},
    [0x08cbb74b] = {'IE-12 Righteous', 'c'},
    [0x1bb1bd7b] = {'IE-12 Righteous', 'p'},
    [0x542c752e] = {'IE-3 Martyr', 'h'},
    [0xb028b970] = {'IE-3 Martyr', 'b'},
    [0x391bc756] = {'IE-3 Martyr', 'c'},
    [0xe67b6d82] = {'IE-3 Martyr', 'p'},
    [0x930dc02f] = {'IE-57 Hell-Bent', 'h'},
    [0xe1d53693] = {'IE-57 Hell-Bent', 'b'},
    [0x457526d1] = {'IE-57 Hell-Bent', 'c'},
    [0x47756764] = {'IE-57 Hell-Bent', 'p'},
    [0xd2a83ca7] = {'KDM-500 Outrider', 'h'},
    [0xae5978b1] = {'KDM-500 Outrider', 'b'},
    [0xef4fa522] = {'KDM-500 Outrider', 'c'},
    [0xce25cfe2] = {'KDM-500 Outrider', 'p'},
    [0xf5cb7633] = {'KDM-73 Dragoon', 'h'},
    [0x1b8329ab] = {'KDM-73 Dragoon', 'b'},
    [0x144c1d6f] = {'KDM-73 Dragoon', 'c'},
    [0x0ac2166d] = {'KDM-73 Dragoon', 'p'},
    [0x71e406e4] = {'KDM-763 Pacesetter', 'h'},
    [0x1e28f118] = {'KDM-763 Pacesetter', 'b'},
    [0xbed85953] = {'KDM-763 Pacesetter', 'c'},
    [0x02817bbe] = {'KDM-763 Pacesetter', 'p'},
    [0xe1ca6837] = {'O-2 Heavy Operator', 'h'},
    [0x2e706db8] = {'O-2 Heavy Operator', 'b'},
    [0xba9e281b] = {'O-2 Heavy Operator', 'c'},
    [0xf69d5ffb] = {'O-2 Heavy Operator', 'p'},
    [0x8d06ea5a] = {'O-3 Free Spirit', 'h'},
    [0xf7e6f127] = {'O-3 Free Spirit', 'b'},
    [0x86ca918c] = {'O-3 Free Spirit', 'c'},
    [0x23f53a60] = {'O-3 Free Spirit', 'p'},
    [0x41dd184d] = {'O-44 Bonded Pilot', 'h'},
    [0xbc5cf836] = {'O-44 Bonded Pilot', 'b'},
    [0xa7945016] = {'O-44 Bonded Pilot', 'c'},
    [0x4379a101] = {'O-44 Bonded Pilot', 'p'},
    [0x57a7f31d] = {'PH-202 Twigsnapper', 'h'},
    [0xde631a28] = {'PH-202 Twigsnapper', 'b'},
    [0x115d8156] = {'PH-202 Twigsnapper', 'c'},
    [0x02766dd2] = {'PH-202 Twigsnapper', 'p'},
    [0xf06ad8d7] = {'PH-56 Jaguar', 'h'},
    [0x23d0e15c] = {'PH-56 Jaguar', 'b'},
    [0x1b2fde48] = {'PH-9 Predator', 'h'},
    [0x72b472a7] = {'PH-9 Predator', 'b'},
    [0x9dbd09d7] = {'PH-9 Predator', 'c'},
    [0xe8484a23] = {'PH-9 Predator', 'p'},
    [0x677bee02] = {'RE-1861 Parade Commander', 'h'},
    [0xc71dbba4] = {'RE-1861 Parade Commander', 'b'},
    [0x55d5144b] = {'RE-1861 Parade Commander', 'c'},
    [0x0e259f44] = {'RE-1861 Parade Commander', 'p'},
    [0x6809ad22] = {'RE-2310 Honorary Guard', 'h'},
    [0x30e54b57] = {'RE-2310 Honorary Guard', 'b'},
    [0x1b3bd8a1] = {'RE-2310 Honorary Guard', 'c'},
    [0x5a578409] = {'RE-2310 Honorary Guard', 'p'},
    [0xa8bf0ccb] = {'RE-824 Bearer of the Standard', 'h'},
    [0xfde8f657] = {'RE-824 Bearer of the Standard', 'b'},
    [0x9fb9d7b0] = {'RE-824 Bearer of the Standard', 'c'},
    [0x61efc052] = {'RE-824 Bearer of the Standard', 'p'},
    [0x47bcec20] = {'RS-100 Sanctioner', 'h'},
    [0x4dd749c6] = {'RS-100 Sanctioner', 'b'},
    [0xe4e2b61b] = {'RS-20 Constrictor', 'h'},
    [0xec4638af] = {'RS-20 Constrictor', 'b'},
    [0xf35eca5b] = {'RS-20 Constrictor', 'c'},
    [0x48877339] = {'RS-20 Constrictor', 'p'},
    [0xed2350ca] = {'RS-40 Beast of Prey', 'h'},
    [0xdbc21a99] = {'RS-40 Beast of Prey', 'b'},
    [0x64d8ba07] = {'RS-40 Beast of Prey', 'c'},
    [0x8de52780] = {'RS-40 Beast of Prey', 'p'},
    [0xbd177f77] = {'RS-6 Fiend Destroyer', 'h'},
    [0x98e86082] = {'RS-6 Fiend Destroyer', 'b'},
    [0x10fd9607] = {'RS-6 Fiend Destroyer', 'c'},
    [0xaf41aee1] = {'RS-6 Fiend Destroyer', 'p'},
    [0x58716e11] = {'RS-67 Null Cipher', 'h'},
    [0xca092176] = {'RS-67 Null Cipher', 'b'},
    [0x06d37083] = {'RS-67 Null Cipher', 'c'},
    [0x0b743373] = {'RS-67 Null Cipher', 'p'},
    [0xd05754cd] = {'RS-89 Shadow Paragon', 'h'},
    [0xaed67d10] = {'RS-89 Shadow Paragon', 'b'},
    [0x4f079d05] = {'RS-89 Shadow Paragon', 'c'},
    [0xdda351e5] = {'RS-89 Shadow Paragon', 'p'},
    [0x4e8f9f4f] = {'SA-04 Combat Technician', 'h'},
    [0xc9d2ad39] = {'SA-04 Combat Technician', 'b'},
    [0x32451e35] = {'SA-04 Combat Technician', 'c'},
    [0x8cd3973b] = {'SA-12 Servo-Assisted', 'h'},
    [0xf2b7d3f5] = {'SA-12 Servo-Assisted', 'b'},
    [0xa3a7e93d] = {'SA-25 Steel Trooper', 'h'},
    [0xdae4a744] = {'SA-25 Steel Trooper', 'b'},
    [0x4100af4b] = {'SA-25 Steel Trooper', 'c'},
    [0xf3bcf18e] = {'SA-32 Dynamo', 'h'},
    [0x3c3ebaf0] = {'SA-32 Dynamo', 'b'},
    [0x9e29ea2f] = {'SA-32 Dynamo', 'c'},
    [0x9e987d5e] = {'SA-7 Headfirst', 'h'},
    [0xc7a5782f] = {'SA-7 Headfirst', 'b'},
    [0x9488c3db] = {'SA-7 Headfirst', 'c'},
    [0x27bce184] = {'SA-7 Headfirst', 'p'},
    [0x790c1b61] = {'SA-8 Ram', 'h'},
    [0xb69df10d] = {'SA-8 Ram', 'b'},
    [0x22ecc10e] = {'SA-8 Ram', 'c'},
    [0xe8894665] = {'SA-8 Ram', 'p'},
    [0x8166c1cc] = {'SC-15 Drone Master', 'h'},
    [0xf57d61ce] = {'SC-15 Drone Master', 'b'},
    [0x020a57a8] = {'SC-30 Trailblazer Scout (1)', 'h'},
    [0x52045a9b] = {'SC-30 Trailblazer Scout (1)', 'h'},
    [0x5aaf5d66] = {'SC-30 Trailblazer Scout (1)', 'h'},
    [0x782087b2] = {'SC-30 Trailblazer Scout (1)', 'h'},
    [0x7fa29b61] = {'SC-30 Trailblazer Scout (1)', 'h'},
    [0x8507bb35] = {'SC-30 Trailblazer Scout (1)', 'h'},
    [0xdb7db6aa] = {'SC-30 Trailblazer Scout (1)', 'h'},
    [0x1d60fc90] = {'SC-30 Trailblazer Scout (1)', 'b'},
    [0x53b64bf8] = {'SC-30 Trailblazer Scout (1)', 'c'},
    [0x9b5bc520] = {'SC-30 Trailblazer Scout (2)', 'h'},
    [0x756159e4] = {'SC-30 Trailblazer Scout (2)', 'b'},
    [0x0542e6f1] = {'SC-34 Infiltrator', 'h'},
    [0x126f9cb6] = {'SC-34 Infiltrator', 'h'},
    [0x5c1a87d2] = {'SC-34 Infiltrator', 'h'},
    [0x68aa2d85] = {'SC-34 Infiltrator', 'h'},
    [0xa2f4f328] = {'SC-34 Infiltrator', 'h'},
    [0xb6a2f46a] = {'SC-34 Infiltrator', 'h'},
    [0xda8bbeaa] = {'SC-34 Infiltrator', 'h'},
    [0x5bb4bbb0] = {'SC-34 Infiltrator', 'b'},
    [0x2cd5cfb0] = {'SC-34 Infiltrator', 'c'},
    [0x5facabb9] = {'SC-37 Legionnaire', 'h'},
    [0x14209e3a] = {'SC-37 Legionnaire', 'b'},
    [0xdc7304b9] = {'SR-18 Roadblock', 'h'},
    [0xd63ffdd3] = {'SR-18 Roadblock', 'b'},
    [0xf89e3f1e] = {'SR-18 Roadblock', 'c'},
    [0x5de4038d] = {'SR-18 Roadblock', 'p'},
    [0x93ad3833] = {'SR-24 Street Scout', 'h'},
    [0x05e56ee5] = {'SR-24 Street Scout', 'b'},
    [0xd1c109de] = {'SR-24 Street Scout', 'c'},
    [0xc2e80e84] = {'SR-24 Street Scout', 'p'},
    [0x735a0c0b] = {'SR-64 Cinderblock', 'h'},
    [0x5096bce9] = {'SR-64 Cinderblock', 'b'},
    [0x42f33241] = {'SR-64 Cinderblock', 'c'},
    [0xf70af02a] = {'SR-64 Cinderblock', 'p'},
    [0xc1611ac9] = {'TG-122 Demo-Trooper', 'h'},
    [0xa45385cd] = {'TG-122 Demo-Trooper', 'b'},
    [0x9a42a639] = {'TG-122 Demo-Trooper', 'c'},
    [0x9a1f6d54] = {'TG-122 Demo-Trooper', 'p'},
    [0x0b66fc55] = {'TG-8 Sharpshooter', 'h'},
    [0x5d0d8002] = {'TG-8 Sharpshooter', 'b'},
    [0x724501be] = {'TG-8 Sharpshooter', 'c'},
    [0xb3cddbf3] = {'TG-8 Sharpshooter', 'p'},
    [0x2f51d8dc] = {'TR-117 Alpha Commander', 'h'},
    [0x9f73133e] = {'TR-117 Alpha Commander', 'b'},
    [0xf9d912a7] = {'TR-40 Gold Eagle', 'h'},
    [0x1c089a28] = {'TR-40 Gold Eagle', 'b'},
    [0x3313a0ec] = {'TR-62 Knight', 'h'},
    [0x7346edc6] = {'TR-62 Knight', 'b'},
    [0x35e8934f] = {'TR-7 Ambassador of the Brand', 'h'},
    [0x8a957897] = {'TR-7 Ambassador of the Brand', 'b'},
    [0xeeb4c2de] = {'TR-9 Cavalier of Democracy', 'h'},
    [0x940716d6] = {'TR-9 Cavalier of Democracy', 'b'},
    [0xd270fccc] = {'UF-16 Inspector', 'h'},
    [0xb661572a] = {'UF-16 Inspector', 'b'},
    [0xec5c680e] = {'UF-16 Inspector', 'c'},
    [0x0904eefa] = {'UF-16 Inspector', 'p'},
    [0x0e3b10bf] = {'UF-50 Bloodhound', 'h'},
    [0xb3550d20] = {'UF-50 Bloodhound', 'b'},
    [0x43265392] = {'UF-50 Bloodhound', 'c'},
    [0x23d37b2f] = {'UF-50 Bloodhound', 'p'},
    [0x05720b46] = {'UF-84 Doubt Killer', 'h'},
    [0x2521d401] = {'UF-84 Doubt Killer', 'b'},
    [0x03f9d46b] = {'UF-84 Doubt Killer', 'c'},
    [0x642b6946] = {'UF-84 Doubt Killer', 'p'},
    [0xf6ae9439] = {'Unnamed 2011781480', 'h'},
    [0x732693a1] = {'Unnamed 2011781480', 'b'},
    [0xa57e78ba] = {'Unnamed 251087110', 'h'},
    [0x9f212504] = {'Unnamed 251087110', 'b'},
    [0x12832e96] = {'Unnamed 2578478819', 'h'},
    [0xa574d33d] = {'Unnamed 2578478819', 'b'},
    [0xb64637ab] = {'Unnamed 2578478819', 'c'},
    [0x44d93620] = {'Unnamed 3385747670', 'h'},
    [0x9bc153c0] = {'Unnamed 3385747670', 'b'},
    [0xe406ced0] = {'Unnamed 3923064864', 'h'},
    [0xc2a2375f] = {'Unnamed 3923064864', 'b'},
}
-- [set] = {localization key of its armor name, English name}
local SET_NAMES = {
    ['A-35 Recon'] = {0xeba56d1e, 'A-35 RECON'},
    ['A-9 Helljumper'] = {0x16406c29, 'A-9 HELLJUMPER'},
    ['AC-1 Dutiful'] = {0x1b90dd6b, 'AC-1 DUTIFUL'},
    ['AC-2 Obedient'] = {0xd88d07c0, 'AC-2 OBEDIENT'},
    ['AD-11 Livewire'] = {0x6d46efd0, 'AD-11 LIVEWIRE'},
    ['AD-26 Bleeding Edge'] = {0xa0dd7490, 'AD-26 BLEEDING EDGE'},
    ['AD-49 Apollonian'] = {0x3898f66d, 'AD-49 APOLLONIAN'},
    ['AF-02 Haz-Master'] = {0xbe426d82, 'AF-02 HAZ-MASTER'},
    ['AF-50 Noxious Ranger'] = {0xa63a7419, 'AF-50 NOXIOUS RANGER'},
    ['AF-52 Lockdown'] = {0x66971bc4, 'AF-52 LOCKDOWN'},
    ['AF-91 Field Chemist'] = {0xecd813ed, 'AF-91 FIELD CHEMIST'},
    ['B-01 Tactical (1)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-01 Tactical (2)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-01 Tactical (3)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-01 Tactical (4)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-01 Tactical (5)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-01 Tactical (6)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-01 Tactical (7)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-01 Tactical (8)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-01 Tactical (9)'] = {0x4dda521c, 'B-01 TACTICAL'},
    ['B-08 Light Gunner'] = {0x834249d7, 'B-08 LIGHT GUNNER'},
    ['B-16 Battle-Scarred Veteran'] = {0xcf2e86c0, 'B-16 BATTLE-SCARRED VETERAN'},
    ['B-22 Model Citizen'] = {0x007f2b8d, 'B-22 MODEL CITIZEN'},
    ['B-24 Enforcer'] = {0x4053d39c, 'B-24 ENFORCER'},
    ['B-27 Fortified Commando'] = {0x46a2ac16, 'B-27 FORTIFIED COMMANDO'},
    ['BFM-16 Tanker'] = {0x63b8230b, 'BFM-16 TANKER'},
    ['BFM-220 Ironclad'] = {0xdcdd1a52, 'BFM-220 IRONCLAD'},
    ['BFM-77 Reformer'] = {0xe87685f3, 'BFM-77 REFORMER'},
    ['BP-20 Correct Officer'] = {0x6743230b, 'BP-20 CORRECT OFFICER'},
    ['BP-32 Jackboot'] = {0x2c943c22, 'BP-32 JACKBOOT'},
    ['BP-77 Grand Juror'] = {0x2cca9fbc, 'BP-77 GRAND JUROR'},
    ['CE-07 Demolition Specialist'] = {0xb3ceb8ab, 'CE-07 DEMOLITION SPECIALIST'},
    ['CE-101 Guerilla Gorilla '] = {0x3036c10d, 'CE-101 GUERILLA GORILLA '},
    ['CE-27 Ground Breaker'] = {0xc2ce5c3f, 'CE-27 GROUND BREAKER'},
    ['CE-35 Trench Engineer'] = {0x951f1a2d, 'CE-35 TRENCH ENGINEER'},
    ['CE-64 Grenadier'] = {0x580ae8ad, 'CE-64 GRENADIER'},
    ['CE-67 Titan'] = {0xb983cd9f, 'CE-67 TITAN'},
    ['CE-74 Breaker'] = {0xb49ef9c0, 'CE-74 BREAKER'},
    ['CE-81 Juggernaut'] = {0xeb3b540f, 'CE-81 JUGGERNAUT'},
    ['CM-09 Bonesnapper (1)'] = {0x8ba8dc8c, 'CM-09 BONESNAPPER'},
    ['CM-09 Bonesnapper (2)'] = {0x8ba8dc8c, 'CM-09 BONESNAPPER'},
    ['CM-10 Clinician'] = {0x691e6f1f, 'CM-10 CLINICIAN'},
    ['CM-14 Physician'] = {0xb59730a7, 'CM-14 PHYSICIAN'},
    ['CM-17 Butcher'] = {0x81c9e99d, 'CM-17 BUTCHER'},
    ['CM-21 Trench Paramedic'] = {0xd993b601, 'CM-21 TRENCH PARAMEDIC'},
    ['CPG-48 Sapper'] = {0x7448bebf, 'CPG-48 SAPPER'},
    ['CPH-26 Commandant'] = {0xf5b9f7ab, 'CPH-26 COMMANDANT'},
    ['CPR-80 Bulwark'] = {0x0519070c, 'CPR-80 BULWARK'},
    ['CW-22 Kodiak'] = {0xaa765236, 'CW-22 KODIAK'},
    ['CW-36 Winter Warrior'] = {0x7fabe2e1, 'CW-36 WINTER WARRIOR'},
    ['CW-4 Arctic Ranger'] = {0xc0585368, 'CW-4 ARCTIC RANGER'},
    ['CW-9 White Wolf'] = {0x8719929a, 'CW-9 WHITE WOLF'},
    ['DP-00 Tactical'] = {0x3deb1116, 'DP-00 TACTICAL'},
    ['DP-11 Champion of the People'] = {0xd3ec9d96, 'DP-11 CHAMPION OF THE PEOPLE'},
    ['DP-40 Hero of the Federation'] = {0xd05440ae, 'DP-40 HERO OF THE FEDERATION'},
    ['DP-53 Savior of the Free'] = {0xe4ccb5a9, 'DP-53 SAVIOR OF THE FREE'},
    ['DP-8 Mountain-Scaled'] = {0xf5cfa8a9, 'DP-8 MOUNTAIN-SCALED'},
    ['DS-10 Big Game Hunter'] = {0x176c67a2, 'DS-10 BIG GAME HUNTER'},
    ['DS-191 Scorpion'] = {0x67601daf, 'DS-191 SCORPION'},
    ['DS-42 Federation\'s Blade'] = {0x78f02349, 'DS-42 FEDERATION\'S BLADE'},
    ['EX-00 Prototype X'] = {0xdfbf12ae, 'EX-00 PROTOTYPE X'},
    ['EX-03 Prototype 3'] = {0xba8d2504, 'EX-03 PROTOTYPE 3'},
    ['EX-16 Prototype 16'] = {0xc7375979, 'EX-16 PROTOTYPE 16'},
    ['FS-05 Marksman (1)'] = {0x850b33c3, 'FS-05 MARKSMAN'},
    ['FS-05 Marksman (2)'] = {0x850b33c3, 'FS-05 MARKSMAN'},
    ['FS-11 Executioner'] = {0xb6492fda, 'FS-11 EXECUTIONER'},
    ['FS-23 Battle Master'] = {0x1e335547, 'FS-23 BATTLE MASTER'},
    ['FS-34 Exterminator'] = {0xb8a0704e, 'FS-34 EXTERMINATOR'},
    ['FS-37 Ravager'] = {0x60c107c2, 'FS-37 RAVAGER'},
    ['FS-38 Eradicator'] = {0xa0b2e4dd, 'FS-38 ERADICATOR'},
    ['FS-55 Devastator'] = {0xc080d226, 'FS-55 DEVASTATOR'},
    ['FS-61 Dreadnought'] = {0xf4a053bd, 'FS-61 DREADNOUGHT'},
    ['GS-11 Democracy\'s Deputy'] = {0x84b0338f, 'GS-11 DEMOCRACY\'S DEPUTY'},
    ['GS-17 Frontier Marshal'] = {0x04f7f62f, 'GS-17 FRONTIER MARSHAL'},
    ['GS-66 Lawmaker'] = {0x88774cd4, 'GS-66 LAWMAKER'},
    ['I-09 Heatseeker'] = {0x6c2dd68f, 'I-09 HEATSEEKER'},
    ['I-102 Draconaught'] = {0x4aca545f, 'I-102 DRACONAUGHT'},
    ['I-44 Salamander'] = {0x2da94851, 'I-44 SALAMANDER'},
    ['I-92 Fire Fighter'] = {0xb3b51618, 'I-92 FIRE FIGHTER'},
    ['IE-12 Righteous'] = {0x9dd2e7dd, 'IE-12 RIGHTEOUS'},
    ['IE-3 Martyr'] = {0xe38754b1, 'IE-3 MARTYR'},
    ['IE-57 Hell-Bent'] = {0x522264c5, 'IE-57 HELL-BENT'},
    ['KDM-500 Outrider'] = {0xfa6eba5c, 'KDM-500 OUTRIDER'},
    ['KDM-73 Dragoon'] = {0x0892df1a, 'KDM-73 DRAGOON'},
    ['KDM-763 Pacesetter'] = {0xa8bda11c, 'KDM-763 PACESETTER'},
    ['O-2 Heavy Operator'] = {0xb0553531, 'O-2 HEAVY OPERATOR'},
    ['O-3 Free Spirit'] = {0x76ece5ea, 'O-3 FREE SPIRIT'},
    ['O-44 Bonded Pilot'] = {0x23164bed, 'O-44 BONDED PILOT'},
    ['PH-202 Twigsnapper'] = {0xe3aeaa5e, 'PH-202 TWIGSNAPPER'},
    ['PH-56 Jaguar'] = {0xe8b8702b, 'PH-56 JAGUAR'},
    ['PH-9 Predator'] = {0x195c1d46, 'PH-9 PREDATOR'},
    ['RE-1861 Parade Commander'] = {0x5dd31360, 'RE-1861 PARADE COMMANDER'},
    ['RE-2310 Honorary Guard'] = {0xf3550896, 'RE-2310 HONORARY GUARD'},
    ['RE-824 Bearer of the Standard'] = {0x6e80edd5, 'RE-824 BEARER OF THE STANDARD'},
    ['RS-100 Sanctioner'] = {0x329edcd8, 'RS-100 SANCTIONER'},
    ['RS-20 Constrictor'] = {0xe27d68c8, 'RS-20 CONSTRICTOR'},
    ['RS-40 Beast of Prey'] = {0xc234e55e, 'RS-40 BEAST OF PREY'},
    ['RS-6 Fiend Destroyer'] = {0x1fc92d85, 'RS-6 FIEND DESTROYER'},
    ['RS-67 Null Cipher'] = {0x5377983f, 'RS-67 NULL CIPHER'},
    ['RS-89 Shadow Paragon'] = {0x3bc06aa5, 'RS-89 SHADOW PARAGON'},
    ['SA-04 Combat Technician'] = {0x44b51381, 'SA-04 COMBAT TECHNICIAN'},
    ['SA-12 Servo-Assisted'] = {0x9515604a, 'SA-12 SERVO-ASSISTED'},
    ['SA-25 Steel Trooper'] = {0x6791a155, 'SA-25 STEEL TROOPER'},
    ['SA-32 Dynamo'] = {0x85d75690, 'SA-32 DYNAMO'},
    ['SA-7 Headfirst'] = {0x772603a0, 'SA-7 HEADFIRST'},
    ['SA-8 Ram'] = {0x3fcc9cc7, 'SA-8 RAM'},
    ['SC-15 Drone Master'] = {0x1f4c8787, 'SC-15 DRONE MASTER'},
    ['SC-30 Trailblazer Scout (1)'] = {0xb59455b5, 'SC-30 TRAILBLAZER SCOUT'},
    ['SC-30 Trailblazer Scout (2)'] = {0xb59455b5, 'SC-30 TRAILBLAZER SCOUT'},
    ['SC-34 Infiltrator'] = {0x51ee71b6, 'SC-34 INFILTRATOR'},
    ['SC-37 Legionnaire'] = {0xdb15fb1a, 'SC-37 LEGIONNAIRE'},
    ['SR-18 Roadblock'] = {0x3b2437c7, 'SR-18 ROADBLOCK'},
    ['SR-24 Street Scout'] = {0x3a050bed, 'SR-24 STREET SCOUT'},
    ['SR-64 Cinderblock'] = {0x5fc896da, 'SR-64 CINDERBLOCK'},
    ['TG-122 Demo-Trooper'] = {0xdb9719b6, 'TG-122 DEMO-TROOPER'},
    ['TG-8 Sharpshooter'] = {0x220e81f2, 'TG-8 SHARPSHOOTER'},
    ['TR-117 Alpha Commander'] = {0x18cb9b58, 'TR-117 ALPHA COMMANDER'},
    ['TR-40 Gold Eagle'] = {0xf1223f38, 'TR-40 GOLD EAGLE'},
    ['TR-62 Knight'] = {0xe7f6e4b0, 'TR-62 KNIGHT'},
    ['TR-7 Ambassador of the Brand'] = {0xa8840186, 'TR-7 AMBASSADOR OF THE BRAND'},
    ['TR-9 Cavalier of Democracy'] = {0xd6181127, 'TR-9 CAVALIER OF DEMOCRACY'},
    ['UF-16 Inspector'] = {0x4cef3d2c, 'UF-16 INSPECTOR'},
    ['UF-50 Bloodhound'] = {0x4ed3a09e, 'UF-50 BLOODHOUND'},
    ['UF-84 Doubt Killer'] = {0xd7bdf2be, 'UF-84 DOUBT KILLER'},
}
-- END SET TABLE

local MEMBERS = {}  -- set key -> list of {item, slot}
for item, entry in pairs(SETS) do
    local list = MEMBERS[entry[1]]
    if not list then list = {}; MEMBERS[entry[1]] = list end
    list[#list + 1] = {item = item, slot = entry[2]}
end
for _, list in pairs(MEMBERS) do table.sort(list, function(a, b) return a.item < b.item end) end

---------------------------------------------------------------------------------------
-- Logs

local function open_log(name)
    if loader and type(loader.open_log) == 'function' then
        local ok, f = pcall(loader.open_log, name)
        if ok then return f end
    end
end

local log_file = open_log('OneClickArmorSet.log')
local log_lines = 0

local function note(msg)
    if not log_file or log_lines >= 20000 then return end
    log_lines = log_lines + 1
    pcall(function()
        log_file:write(string.format('[f%d t%.1f] %s\n', M.frames, os.clock(), msg))
        log_file:flush()
    end)
end

local function write_file(name, lines)
    local f = open_log(name)
    if not f then return end
    pcall(function()
        f:write(table.concat(lines, '\n') .. '\n')
        f:close()
    end)
end

---------------------------------------------------------------------------------------
-- Native memory (ReadProcessMemory / WriteProcessMemory on our own process: a bad address fails instead of crashing)

local native = {}

local function init_native()
    for _, decl in ipairs({
        'void *GetCurrentProcess(void);',
        'void *GetModuleHandleA(const char *name);',
        'int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);',
        'int WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);',
    }) do pcall(ffi.cdef, decl) end
    pcall(ffi.cdef, 'size_t VirtualQuery(const void *address, void *buffer, size_t length);')
    if not pcall(ffi.typeof, 'ESB_vec2') then ffi.cdef('typedef struct { float x, y; } ESB_vec2;') end
    local ok, k32 = pcall(ffi.load, 'kernel32')
    if not ok then return false, 'kernel32 unavailable' end
    native.k32, native.process = k32, k32.GetCurrentProcess()
    local game = k32.GetModuleHandleA('game.dll')
    if game == nil then return false, 'game.dll not loaded' end
    native.base = tonumber(ffi.cast('uint64_t', game))
    native.got = ffi.new('size_t[1]')
    native.word = ffi.new('uint32_t[1]')
    native.vec = ffi.new('ESB_vec2')
    native.vec2 = ffi.new('ESB_vec2')
    return true
end

-- Small reads (every frame) share one buffer instead of allocating: only the offers table is read into a new one.
local SCRATCH_SIZE = 4096
local scratch = ffi.new('uint8_t[?]', SCRATCH_SIZE)

local function read(address, size)
    if not address then return nil end
    local buf = size <= SCRATCH_SIZE and scratch or ffi.new('uint8_t[?]', size)
    if native.k32.ReadProcessMemory(native.process, ffi.cast('const void *', address), buf, size, native.got) == 0
       or tonumber(native.got[0]) ~= size then
        return nil
    end
    return ffi.string(buf, size)
end

local function write32(address, value)
    native.word[0] = value
    return native.k32.WriteProcessMemory(native.process, ffi.cast('void *', address), native.word, 4, native.got) ~= 0
           and tonumber(native.got[0]) == 4
end

local function u32(blob, offset)
    offset = offset or 0
    if not blob or #blob < offset + 4 then return nil end
    local a, b, c, d = blob:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function i16(blob, offset)
    offset = offset or 0
    if not blob or #blob < offset + 2 then return nil end
    local a, b = blob:byte(offset + 1, offset + 2)
    local v = a + b * 256
    return v >= 32768 and v - 65536 or v
end

local function i32(blob, offset)
    local v = u32(blob, offset)
    if v and v >= 2147483648 then v = v - 4294967296 end
    return v
end

local F32 = ffi.new('float[1]')
local function f32(blob, offset)
    if not blob or #blob < offset + 4 then return nil end
    ffi.copy(F32, blob:sub(offset + 1, offset + 4), 4)
    local v = tonumber(F32[0])
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function pointer(blob, offset)
    local lo, hi = u32(blob, offset or 0), u32(blob, (offset or 0) + 4)
    if not lo or not hi or hi >= 0x8000 then return nil end
    local a = hi * 4294967296 + lo
    return a >= 0x10000 and a or nil
end

local function read32(address) return u32(read(address, 4)) end

local function matches_at(address, text)
    local want = {}
    for part in text:gmatch('%S+') do want[#want + 1] = part ~= '??' and tonumber(part, 16) or false end
    local blob = read(address, #want)
    if not blob then return false end
    for i, b in ipairs(want) do
        if b and blob:byte(i) ~= b then return false end
    end
    return true
end

---------------------------------------------------------------------------------------
-- Resolution

local globals, calls = {}, nil

local function resolve()
    local lines = {}
    local without = {engine_root = ', set names in English', input = ', no key glyph'}
    for _, name in ipairs({'ui_manager', 'progression', 'engine_root', 'players', 'no_player', 'components', 'input'}) do
        local sig = SIGS[name]
        if matches_at(native.base + sig.rva, sig.text) then
            local at = sig.rva + sig.at
            globals[name] = native.base + at + 7 + i32(read(native.base + at + 3, 4))  -- a value's address for `address`
            lines[#lines + 1] = name .. ': OK'
        else
            lines[#lines + 1] = name .. ': NOT FOUND (game updated?)'
                                .. (without[name] or (sig.optional and ', 3D preview not redressed' or ''))
        end
    end
    local GLYPH_FNS = {find_mapping = true, glyph_texture = true, key_name = true, set_anchor = true, set_pivot = true,
                       set_variable = true, set_layer = true}
    local fns = {}
    for name, entry in pairs(NATIVE) do
        if matches_at(native.base + entry[1], entry[2]) then
            fns[name] = ffi.cast(entry[3], native.base + entry[1])
        elseif entry.optional then
            lines[#lines + 1] = 'native ' .. name .. ': CHANGED, '
                                .. (GLYPH_FNS[name] and 'no key glyph' or '3D preview not redressed')
        else
            lines[#lines + 1] = 'native ' .. name .. ': CHANGED (game updated?)'
            fns = nil
            break
        end
    end
    calls = fns
    if calls then lines[#lines + 1] = 'native functions: OK' end
    return lines, (globals.ui_manager and globals.progression and calls) and true or false
end

local function object(name)
    local g = globals[name]
    return g and pointer(read(g, 8))
end

---------------------------------------------------------------------------------------
-- Offers: offer id -> item, and which items are owned

local offers = {count = 0, map = {}, owned = {}, offer_of = {}}

local function load_offers()
    local prog = object('progression')
    local count = prog and read32(prog + OFFERS.count)
    if not count or count < 1 or count > OFFERS.max then return false end
    local entries = read(prog + OFFERS.entries, count * OFFERS.entry_size)
    local states = read(prog + OFFERS.states, count * OFFERS.state_size)
    if not entries or not states then return false end
    local map, owned, offer_of = {}, {}, {}
    for i = 0, count - 1 do
        local e = i * OFFERS.entry_size
        local index, id, item = u32(entries, e), u32(entries, e + 4), u32(entries, e + 8)
        if index < count then
            local s = index * OFFERS.state_size
            local status = u32(states, s + OFFERS.status)
            map[id] = item
            if offer_of[item] == nil then offer_of[item] = id end
            if (status == 2 or status == 4) and states:byte(s + OFFERS.disabled + 1) == 0 then owned[item] = true end
        end
    end
    offers.count, offers.map, offers.owned, offers.offer_of = count, map, owned, offer_of
    note(string.format('Offers read: %d', count))
    return true
end

---------------------------------------------------------------------------------------
-- The Armory controller and its widgets

local function armory_controller()
    local mgr = object('ui_manager')
    local count = mgr and read32(mgr + UI.count)
    if not count or count < 1 or count > UI.max_rows then return nil end
    local rows = read(mgr + UI.rows, count * UI.row_size)
    local found
    for i = 0, count - 1 do
        if u32(rows, i * UI.row_size + 8) == UI.armory_type then
            if found then return nil end  -- ambiguous
            found = pointer(rows, i * UI.row_size)
        end
    end
    return found
end

local function widget(address)
    local w = read(address, 0xa0)
    if not w then return nil end
    return {
        flags = u32(w, WIDGET.flags), alpha = f32(w, WIDGET.alpha),
        px = f32(w, WIDGET.pos), py = f32(w, WIDGET.pos + 4), w = f32(w, WIDGET.size), h = f32(w, WIDGET.size + 4),
        sx = f32(w, WIDGET.scale_x), sy = f32(w, WIDGET.scale_y), x = f32(w, WIDGET.x), y = f32(w, WIDGET.y),
    }
end

local function visible(w)
    return w and w.flags and w.flags % (2 * WIDGET.visible) >= WIDGET.visible
end

-- A widget's type, from its flags (bits 18-21): 3 image, 7 text, 5 plain rectangle...
local function widget_type(address)
    local flags = read32(address)
    return flags and math.floor(flags / 262144) % 16
end

-- Localized text through the game's own lookup (engine root +0x10 -> +0x3e8), checked to be executable image code.
local loc = {cache = {}}

local function executable_image(address)
    local mbi = ffi.new('uint8_t[48]')
    if native.k32.VirtualQuery(ffi.cast('const void *', address), mbi, 48) ~= 48 then return false end
    local m = ffi.string(mbi, 48)
    local protect = u32(m, 36)
    return u32(m, 32) == 0x1000 and u32(m, 40) == 0x1000000
           and (protect == 0x10 or protect == 0x20 or protect == 0x40 or protect == 0x80)
end

local function localize(key)
    if not key or key == 0 or not globals.engine_root then return nil end
    local cached = loc.cache[key]
    if cached ~= nil then return cached or nil end
    local root = object('engine_root')
    local engine = root and pointer(read(root + 0x10, 8))
    local fn = engine and pointer(read(engine + 0x3e8, 8))
    if not fn or not executable_image(fn) then return nil end
    if fn ~= loc.fn then loc.fn, loc.call = fn, ffi.cast('const char *(*)(uint32_t)', fn) end
    local at = loc.call(key)
    local text = at ~= nil and read(tonumber(ffi.cast('uint64_t', at)), 128)
    text = text and text:match('^([^%z]*)%z')
    if not text or text == '' or text:find('^#ID%[') or #text > 64 then
        loc.cache[key] = false
        return nil
    end
    text = text:gsub('%c', ' ')
    loc.cache[key] = text
    return text
end

-- The game's language, recognized once through a localized text.
local function language()
    if loc.language then return loc.language end
    local text = localize(LANGUAGE_KEY)
    if text then
        loc.language = LANGUAGES[text] or 'en'
        note('Language: ' .. loc.language)
    end
    return loc.language or 'en'
end

local function vec(x, y)
    native.vec.x, native.vec.y = x, y
    return native.vec
end

local function vec2(x, y)  -- a second argument alongside vec()
    native.vec2.x, native.vec2.y = x, y
    return native.vec2
end

local color_buffers = {}
local function color_buffer(rgb)
    local key = table.concat(rgb, ',')
    local b = color_buffers[key]
    if not b then b = ffi.new('float[3]', rgb); color_buffers[key] = b end
    return b
end

local texts = {}  -- string buffers stay alive for the whole session (a widget may keep pointing at one)
local function text_buffer(s)
    local b = texts[s]
    if not b then b = ffi.new('char[?]', #s + 1, s); texts[s] = b end
    return b
end

---------------------------------------------------------------------------------------
-- Sets

local options = {registered = false}

-- Registers the toggles once Mod Options Menu is there (the two addons load in either order).
local function register_options()
    local menu = rawget(_G, 'ModOptionsMenu')
    if options.registered or not menu or menu.api ~= 1 then return end
    options.registered, options.menu = true, menu
    for _, slot in ipairs({'c', 'p'}) do
        local o = OPTIONS[slot]
        local ok, res, why = pcall(menu.register_option, o.id, {type = 'toggle', label = o.label,
            mod = 'One Click Armor Set', default = true, description = o.description})
        note(string.format('Option %s: %s', o.id, (ok and res) and 'registered' or tostring(why or res)))
    end
end

local function included(slot)
    local o, menu = OPTIONS[slot], options.menu
    if not o or not menu then return true end
    local ok, value = pcall(menu.get, o.id)
    return not ok or value ~= false
end

-- The set the viewed item belongs to, with one owned item per included slot (the viewed item for its own slot).
local function plan_for(offer)
    local item = offer and offers.map[offer]
    local entry = item and SETS[item]
    if not entry or not offers.owned[item] then return nil end
    local chosen = {[entry[2]] = item}
    for _, m in ipairs(MEMBERS[entry[1]]) do
        if not chosen[m.slot] and offers.owned[m.item] and included(m.slot) then chosen[m.slot] = m.item end
    end
    local owned, total, present = 0, 0, {}
    for slot in pairs(chosen) do owned = owned + 1 end
    for _, m in ipairs(MEMBERS[entry[1]]) do
        if not present[m.slot] and (m.slot == entry[2] or included(m.slot)) then
            present[m.slot] = true
            total = total + 1
        end
    end
    if owned < 2 then return nil end
    local names = SET_NAMES[entry[1]]
    local name = names and (localize(names[1]) or names[2])
    local labels = LABELS[language()] or LABELS.en
    local text = name and string.format(labels[1], name) or labels[2]
    return {offer = offer, item = item, set = entry[1], slot = entry[2], slots = chosen,
            label = string.format('%s (%d/%d)', text, owned, total)}
end

---------------------------------------------------------------------------------------
-- The bar

local bar = {applied = nil}
local glyph_save, glyph_restore  -- defined with the keybind below
local BINDING_ID = 'alomare.one_click_armor_set.equip_set'
local binding = {tried = false, was_down = false, code = nil, next_lookup = 0}

local function bar_restore(why)
    local a = bar.applied
    bar.applied = nil
    if not a then return end
    glyph_restore(a)
    if a.color then calls.set_color(a.bar + BAR.text, color_buffer(a.color)) end
    calls.clear_args(a.bar + BAR.text + WIDGET.label)
    calls.set_label(a.bar + BAR.text, a.text_label)
    if a.outline then
        for offset, s in pairs(a.outline) do
            local image = ICON_IMAGES[offset]
            calls.set_image(a.bar + offset, image[1], image[2], 0)
            if s.uv[1] then calls.set_uv(a.bar + offset, vec(s.uv[1], s.uv[2]), vec2(s.uv[3], s.uv[4])) end
            calls.set_size(a.bar + offset, vec(s.w, s.h))
            if s.px then calls.set_position(a.bar + offset, vec(s.px, s.py)) end
            if s.color[1] then calls.set_color(a.bar + offset, color_buffer(s.color)) end
            calls.set_visible(a.bar + offset, s.shown and 1 or 0)
        end
        calls.set_visible(a.bar + BAR.text_b, a.text_b_shown and 1 or 0)
    end
    if a.text_pos then calls.set_position(a.bar + BAR.text, vec(a.text_pos[1], a.text_pos[2])) end
    calls.bar_empty(a.bar)
    note('Bar restored (' .. why .. ')')
end

local function near(a, b) return a and b and math.abs(a - b) < 0.0005 end

local TEXTURE_BYTES = ffi.string(ffi.new('uint64_t[1]', OUTLINE.texture), 8)

local MAINTAIN_BURST, MAINTAIN_EVERY = 30, 10

local function outline_maintain(a)
    if not a.pieces then return end
    if M.frames - (a.touched or 0) > MAINTAIN_BURST and M.frames % MAINTAIN_EVERY ~= 0 then return end
    if not visible(widget(a.bar + BAR.group_b)) then calls.set_visible(a.bar + BAR.group_b, 1) end
    if visible(widget(a.bar + BAR.text_b)) then calls.set_visible(a.bar + BAR.text_b, 0) end
    for _, piece in ipairs(a.pieces) do
        local at = a.bar + piece.offset
        local w = widget(at)
        local uv = read(at + IMAGE_UV, 16)
        if read(at + IMAGE_TEXTURE, 8) ~= TEXTURE_BYTES then
            calls.set_image(at, OUTLINE.material, OUTLINE.texture, 0)
            a.fixes = (a.fixes or 0) + 1
        end
        if not (uv and near(f32(uv, 0), piece.u0) and near(f32(uv, 8), piece.u1) and near(f32(uv, 4), 0)
                and near(f32(uv, 12), 1)) then
            calls.set_uv(at, vec(piece.u0, 0), vec2(piece.u1, 1))
            a.fixes = (a.fixes or 0) + 1
        end
        if w and not (near(w.w, piece.w) and near(w.h, OUTLINE.h)) then calls.set_size(at, vec(piece.w, OUTLINE.h)) end
        if w and not (near(w.px, piece.x) and near(w.py, 0)) then calls.set_position(at, vec(piece.x, 0)) end
        if w and not visible(w) then calls.set_visible(at, 1) end
    end
    if a.fixes and not a.fixes_logged and a.fixes >= 4 then
        a.fixes_logged = true
        note('Outline: the game reset the outline images; they are kept as set')
    end
end

local function bar_apply(ctl, plan)
    local detail = ctl + CTL.detail
    local text_label = read32(detail + DETAIL.bar + BAR.text + WIDGET.label)
    if not text_label then return end
    local color = read(detail + DETAIL.bar + BAR.text + WIDGET.color, 12)
    local a = {bar = detail + DETAIL.bar, offer = plan.offer, text_label = text_label,
               color = color and {f32(color, 0), f32(color, 4), f32(color, 8)} or nil, hovered = false, flash = 0}
    calls.set_visible(a.bar + BAR.group, 1)
    -- The glyph's place: the padlock's horizontal center, in the bar's own units, at the bar's vertical middle.
    local group, pad = widget(a.bar + BAR.group), widget(a.bar + BAR.icon)
    -- Only a padlock-sized reading counts (while an outline piece, it is 337 wide); else the last one, else 35
    -- (the padlock at 20, 30 wide).
    if group and group.px and pad and pad.px and pad.w and pad.w > 0 and pad.w <= 64 then
        bar.pad_x = group.px + pad.px + pad.w / 2
    end
    a.pad_x = bar.pad_x or 35
    if binding.menu and calls.find_mapping and globals.input then a.glyph_saved = glyph_save(a) end
    -- Outline: EQUIP's outline texture in two halves on the bar's two icon images, in the text's color.
    a.outline = {}
    for i, offset in ipairs({BAR.icon, BAR.icon_b}) do
        if widget_type(a.bar + offset) ~= WIDGET_TYPE.image then
            note('Outline off: bar icon +' .. string.format('%x', offset) .. ' is not an image (game updated?)')
            a.outline = nil
            break
        end
        local w, extra = widget(a.bar + offset), read(a.bar + offset + WIDGET.color, 12)
        local uv = read(a.bar + offset + IMAGE_UV, 16)
        if not (w and w.w and extra and uv) then a.outline = nil; break end
        a.outline[offset] = {px = w.px, py = w.py, w = w.w, h = w.h, color = {f32(extra, 0), f32(extra, 4), f32(extra, 8)},
                             uv = {f32(uv, 0), f32(uv, 4), f32(uv, 8), f32(uv, 12)}, shown = visible(w)}
    end
    if a.outline then
        a.text_b_shown = visible(widget(a.bar + BAR.text_b))
        calls.set_visible(a.bar + BAR.group_b, 1)
        calls.set_visible(a.bar + BAR.text_b, 0)
        local o = OUTLINE
        local span = BAR.width + 2 * o.margin
        local right_w = (o.tex_w - o.right_from) * o.scale
        a.pieces = {
            {offset = BAR.icon, u0 = 0, u1 = o.left_cols / o.tex_w, x = -o.margin, w = o.left_cols * o.scale},
            {offset = BAR.icon_b, u0 = o.right_from / o.tex_w, u1 = 1, x = -o.margin + span - right_w, w = right_w},
        }
        for _, piece in ipairs(a.pieces) do
            local at = a.bar + piece.offset
            calls.set_image(at, o.material, o.texture, 0)
            calls.set_uv(at, vec(piece.u0, 0), vec2(piece.u1, 1))
            calls.set_size(at, vec(piece.w, o.h))
            calls.set_position(at, vec(piece.x, 0))
            calls.set_visible(at, 1)
            if a.color then calls.set_color(at, color_buffer(a.color)) end
        end
    end
    -- Half the text's left margin: it made room for the padlock.
    local text_pos = read(a.bar + BAR.text + WIDGET.pos, 8)
    if text_pos then
        a.text_pos = {f32(text_pos, 0), f32(text_pos, 4)}
        if a.text_pos[1] and a.text_pos[2] then
            calls.set_position(a.bar + BAR.text, vec(a.text_pos[1] * TEXT_MARGIN, a.text_pos[2]))  -- glyph: full
        else
            a.text_pos = nil
        end
    end
    calls.set_label(a.bar + BAR.text, TEXT_TEMPLATE)
    calls.set_string_arg(a.bar + BAR.text, TEXT_KEY, text_buffer(plan.label))
    a.plan, a.label, a.touched = plan, plan.label, M.frames
    bar.applied = a
    local parts = {}
    for _, slot in ipairs(SLOT_ORDER) do
        if plan.slots[slot] then parts[#parts + 1] = SLOT_NAMES[slot] end
    end
    note(string.format('Bar shown for set %s (item %08x: %s) "%s"', plan.set, plan.item, table.concat(parts, ' '),
                       plan.label))
end

---------------------------------------------------------------------------------------
-- Equipping

-- A hover away and back (the only thing that redresses the 3D model after a change of equipment): the grid
-- highlights another item for a few frames, then the viewed one again, each followed by the hover refresh.
local hover = {}
local HOVER_FRAMES = 2
local GRID_OFFERS, GRID_CANDIDATES = 0x92990, 8  -- the grid's offers, in list order (HD2-Transmog)

local function hover_step(ctl)
    if not hover.stage then return false end
    if ctl ~= hover.ctl then hover.stage = nil; return false end
    local grid = ctl + CTL.grid
    if hover.stage == 1 and M.frames > hover.frame then
        local away
        for _, offer in ipairs(hover.candidates) do
            if calls.highlight(grid, offer) ~= 0 then away = offer; break end
        end
        if not away then
            note('Hover away: no other item in this list')
            hover.stage = nil
            return false
        end
        calls.preview_notify(ctl + CTL.preview_manager)
        note(string.format('Hover away to %08x', away))
        hover.stage, hover.frame = 2, M.frames
    elseif hover.stage == 2 and M.frames >= hover.frame + HOVER_FRAMES then
        local ok = calls.highlight(grid, hover.back)
        calls.preview_notify(ctl + CTL.preview_manager)
        note(string.format('Hover back to %08x: %s', hover.back, ok ~= 0 and 'ok' or 'failed'))
        hover.stage = nil
        if bar.applied then bar.applied.touched = M.frames end  -- the game refreshed the bar meanwhile
    end
    return true
end

local CUSTOMIZATION_EVENT = 0xbd5b4583
local NO_INDEX = 0xffffffff

-- What the native armor EQUIP does before its commit (game.dll + 0x145801c): find the local player's customization
-- component, bump its version and queue the customization event, which redresses the Armory's 3D preview.
local function customization_event()
    if not (calls.entity_event and globals.players and globals.no_player and globals.components) then return false end
    local players = object('players')
    if not players then return false end
    local id
    if read32(players + 0x88) ~= 0 then
        local p = pointer(read(players + 0xe8, 8))
        id = p and read32(p + 8)
    end
    local none = read32(globals.no_player)
    id = id or none
    if not id or id == none then return false end
    local cm = object('components')
    local capacity, empty, mult = cm and read32(cm + 0x28), cm and read32(cm + 0x2c), cm and read32(cm + 0x30)
    local keys = cm and pointer(read(cm + 0x20, 8))
    if not (capacity and capacity > 0 and capacity <= 0x100000 and empty and mult and keys) then return false end
    local hash = tonumber(ffi.cast('uint32_t', ffi.new('uint64_t', mult) * id))
    local index
    for i = 0, capacity - 1 do
        local slot = (hash + i) % capacity
        local entry = read(keys + slot * 8, 8)
        local key = u32(entry, 0)
        if not key then return false end
        if key == id then index = u32(entry, 4); break end
        if key == empty then return false end
    end
    if not index or index == NO_INDEX or index >= 0x1000000 then return false end
    local states, entities = pointer(read(cm + 0x50, 8)), pointer(read(cm + 0x38, 8))
    local entity_ptr = entities and pointer(read(entities + index * 8, 8))
    local entity = entity_ptr and read32(entity_ptr + 0x10)
    if not (states and entity) then return false end
    local state = states + index * 36 + 0x20
    local version = read32(state)
    if not version then return false end
    local bumped = tonumber(ffi.cast('uint32_t', bit.bor(bit.band(version, 0xfffffffe) + 2, 1)))
    if not write32(state, bumped) then return false end
    calls.entity_event(entity, CUSTOMIZATION_EVENT, state)
    return true
end

local function equip(ctl, plan)
    local applied, pending = read(ctl + CTL.applied, CTL.block), read(ctl + CTL.pending, CTL.block)
    local previous = applied and u32(applied, SLOT_FIELD[plan.slot])  -- the viewed slot's item before the equip
    if not applied or applied ~= pending then
        note('Equip skipped: the Armory has an unapplied change')
        return
    end
    for slot, item in pairs(plan.slots) do
        if not offers.owned[item] then note('Equip skipped: ownership changed'); return end
    end
    for slot, item in pairs(plan.slots) do
        if not write32(ctl + CTL.pending + SLOT_FIELD[slot], item) then
            note('Equip failed: pending loadout not writable')
            return
        end
    end
    local evented = (plan.slots.h or plan.slots.b or plan.slots.c) and customization_event()
    calls.commit(ctl, 0)
    local after = read(ctl + CTL.applied, CTL.block)
    local parts = {}
    for _, slot in ipairs(SLOT_ORDER) do
        local item = plan.slots[slot]
        if item then
            parts[#parts + 1] = string.format('%s %08x %s', SLOT_NAMES[slot], item,
                                              u32(after, SLOT_FIELD[slot]) == item and 'ok' or 'NOT APPLIED')
        end
    end
    note('Equipped set ' .. plan.set .. ': ' .. table.concat(parts, ', '))
    -- As after a native EQUIP: the viewed item's equip sound, then the grid's equipped marker.
    if plan.slot == 'p' then
        calls.play_sound(0, CARD_EQUIP_SOUND)  -- as the Character menu's own card equip
    else
        calls.equip_sound(ctl + CTL.grid, plan.offer)
    end
    calls.mark_equipped(ctl + CTL.grid, plan.offer)
    calls.button_state(ctl + CTL.detail + DETAIL.button, EQUIPPED_STATE)
    -- As the native EQUIP after its commit: the hover refresh, which re-shows the details and the preview. The
    -- preview only rebuilds its model when its kit differs, so the cached kit is cleared first.
    local kit_at = ctl + CTL.detail + DETAIL.preview + PREVIEW_KIT
    local kit = read32(kit_at)
    if kit and kit ~= 0 then write32(kit_at, 0) end
    -- The detail panel only dresses the 3D model when the shown item changes (game.dll + 0x191d631), as when hovering
    -- away and back: forget the shown item first.
    write32(ctl + CTL.detail + DETAIL.offer, 0)
    calls.preview_notify(ctl + CTL.preview_manager)
    -- Hover away and back: to an item of the same grid (the one the viewed slot had, else the grid's first items).
    local candidates = {}
    if previous and previous ~= plan.item and offers.offer_of[previous] then candidates[1] = offers.offer_of[previous] end
    local list = read(ctl + CTL.grid + GRID_OFFERS, 4 * GRID_CANDIDATES)
    for i = 0, GRID_CANDIDATES - 1 do
        local offer = u32(list, i * 4)
        if offer and offer ~= 0 and offer ~= plan.offer then candidates[#candidates + 1] = offer end
    end
    if calls.highlight and #candidates > 0 then
        hover.ctl, hover.candidates, hover.back, hover.stage, hover.frame = ctl, candidates, plan.offer, 1, M.frames
    end
    note(string.format('Preview refreshed (kit %08x -> %08x, customization event %s)', kit or 0, read32(kit_at) or 0,
                       evented and 'posted' or 'not posted'))
end

-- Hover: white text and the EQUIP button's hover sound; a click flashes the text before equipping.
local function feedback(ctl, a, hovered)
    if hovered ~= a.hovered then
        a.hovered = hovered
        if hovered then
            local id = read32(ctl + CTL.detail + DETAIL.button + EQUIP_HOVER_SOUND)
            calls.play_sound(0, (id and id ~= 0) and id or DEFAULT_HOVER_SOUND)
        end
    end
    local want = a.flash > 0 and COLORS.press or (hovered and COLORS.hover) or a.color
    if a.flash > 0 then a.flash = a.flash - 1 end
    if want and want ~= a.shown_color then
        calls.set_color(a.bar + BAR.text, color_buffer(want))
        if a.outline then
            for offset in pairs(a.outline) do calls.set_color(a.bar + offset, color_buffer(want)) end
        end
        a.shown_color = want
    end
end

---------------------------------------------------------------------------------------
-- Input

local input = {}

-- Returns whether the cursor is over the widget, and whether the left button went down this frame.
local function mouse_on(w)
    local m = S and S.Mouse
    if not (m and w and w.x and w.w and type(m.pressed) == 'function') then return false, false end
    if input.mouse == nil then
        local ok, left = pcall(m.button_id, 'left')
        local ok2, cursor = pcall(m.axis_id, 'cursor')
        input.mouse = ok and ok2 and {left = left, cursor = cursor} or false
    end
    if not input.mouse then return false, false end
    local ok, pos = pcall(m.axis, input.mouse.cursor)
    if not ok or not pos then return false, false end
    local x, y = pos.x, pos.y
    local over = x >= w.x and x < w.x + w.w * (w.sx or 1) and y >= w.y and y < w.y + w.h * (w.sy or 1)
    if not over then return false, false end
    local ok2, down = pcall(m.pressed, input.mouse.left)
    return true, ok2 and down and true or false
end

---------------------------------------------------------------------------------------
-- Keybind (Mod Bindings Menu) and its glyph on the bar

-- The binding is registered without a slot: Mod Bindings Menu assigns a free native input action and the player sets
-- its key on the MODS tab of the bindings pages (automatic bindings have no default key).

local function register_binding()
    if binding.tried then return end
    local menu = rawget(_G, 'ModBindingsMenu')
    if not menu or menu.api ~= 1 or type(menu.register_binding) ~= 'function' then return end
    binding.tried = true
    local ok, res, why = pcall(menu.register_binding, BINDING_ID, 'Equip Set', nil, {category = 'One Click Armor Set'})
    if ok and res then binding.menu = menu end
    note('Binding ' .. BINDING_ID .. ': ' .. ((ok and res) and 'registered' or tostring(why or res)))
end

-- Whether the binding went down this frame (Press and Tap are one-frame pulses; Hold stays down: edge only).
local function binding_pressed()
    local menu = binding.menu
    if not menu then return false end
    local ok, down = pcall(menu.is_down, BINDING_ID)
    down = ok and down == true
    local edge = down and not binding.was_down
    binding.was_down = down
    return edge
end

-- The native action Mod Bindings Menu assigned, from its assignments file (id, group, action per line): the game
-- keys input actions by {u32 group, u32 action}.
local function binding_action()
    if binding.code or not binding.menu or M.frames < binding.next_lookup then return binding.code end
    binding.next_lookup = M.frames + 300
    local dir = loader and type(loader.log_directory) == 'string' and loader.log_directory ~= '' and loader.log_directory
    if not dir then
        local base = os.getenv('LOCALAPPDATA')
        dir = base and base .. '/CowboyBingus/Helldivers2'
    end
    local f = dir and io.open(dir .. '/ModBindingsMenu.assignments', 'rb')
    if not f then return nil end
    local text = f:read('*a') or ''
    f:close()
    for id, group, action in text:gmatch('([^\t\r\n]+)\t(%d+)\t(%d+)') do
        if id == BINDING_ID then
            binding.code = {group = tonumber(group), action = tonumber(action)}
            note(string.format('Binding action: group %d, action %d', binding.code.group, binding.code.action))
        end
    end
    return binding.code
end

-- What the game's prompt buttons show for an action (0x17a3960 / 0x17a45c0): the mapping for the device used last,
-- then either a glyph texture (gamepad buttons, mouse, special keys) or, for a key, the blank keycap with its name.
local GLYPH_MATERIAL = 0xc0f3797849262087ull  -- the prompt glyphs' material (its textures are channel-packed)
local KEYCAP_TEXTURE = 0x60116f30f97f2f5aull  -- content/ui/shared/input/button_key_blank
-- The glyph material's variables, as the prompt sets them (0x17a2fd0): 0x28723f4d (rva 0x21e2e70), the tint
-- 0x851fd4fd (its +0x1d4c, from rva 0x21e4230) and 0x10c353af (its +0x1d6c, zero).
local GLYPH_VARIABLES = {
    {0x28723f4d, ffi.new('float[4]', 1, 1, 0.914, 0)},
    {0x851fd4fd, ffi.new('float[4]', 1, 237 / 255, 237 / 255, 237 / 255)},
    {0x10c353af, ffi.new('float[4]', 0, 0, 0, 0)},
}
local glyph_out = ffi.new('uint64_t[1]')

-- The binding table (input system + 0xa7ad0, as Mod Bindings Menu reads it): 0x148-byte buckets {u32 group * 65536 +
-- action, u32 count, 16 x 20-byte mappings}; a mapping's byte 0 is kind * 16 + device (1 PlayStation pad, 2 Xbox
-- pad, 3 keyboard, 4 mouse), its u16 at 4 the key.
local MAP = {buckets = 0xa7ad0, capacity = 0xa7ad8, bucket = 0x148, count = 4, first = 8, size = 20, max = 16}
local FAMILY = {[1] = 'pad', [2] = 'pad', [3] = 'kbm', [4] = 'kbm'}
local EQUIP_ACTION = 10 * 4294967296  -- {group 0, action 10}: what EQUIP's prompt shows

-- The binding's bucket, read into one buffer (every GLYPH_EVERY frames).
local bucket_buf = ffi.new('uint8_t[?]', MAP.bucket)
local bucket_words = ffi.cast('uint32_t *', bucket_buf)

local function load_bucket(bucket, key)
    return bucket ~= nil and native.k32.ReadProcessMemory(native.process, ffi.cast('const void *', bucket), bucket_buf,
                                                          MAP.bucket, native.got) ~= 0 and bucket_words[0] == key
end

-- The binding's mapping count (the mappings are in bucket_buf), or nil.
local function binding_mappings(input, code)
    local key = code.group * 65536 + code.action
    if not load_bucket(binding.bucket, key) then
        binding.bucket = nil
        local buckets, capacity = pointer(read(input + MAP.buckets, 8)), read32(input + MAP.capacity)
        if not buckets or not capacity or capacity < 1 or capacity > 4096 then return nil end
        local bucket
        for i = 0, capacity - 1 do
            if read32(buckets + i * MAP.bucket) == key then bucket = buckets + i * MAP.bucket; break end
        end
        if not load_bucket(bucket, key) then return nil end
        binding.bucket = bucket
    end
    local count = bucket_words[MAP.count / 4]
    return count <= MAP.max and count or nil
end

local NO_GLYPH = {id = 'none'}

local function resolve_glyph()
    local code = binding_action()
    if not (code and calls.find_mapping and calls.glyph_texture and calls.key_name and calls.set_anchor
            and calls.set_pivot and calls.set_variable and calls.set_layer) then return nil end
    local input = object('input')
    if not input then return nil end
    -- The device in use: the one of the mapping the game picks for EQUIP (it shows the device used last).
    local equip = calls.find_mapping(input, EQUIP_ACTION, 1)
    local device = equip ~= nil and equip[0] % 16 or nil
    local count = binding_mappings(input, code)
    if not (count and device) then return NO_GLYPH end
    local chosen
    for i = 0, count - 1 do
        local at = MAP.first + i * MAP.size
        if bucket_buf[at] % 16 == device then chosen = at; break end
    end
    if not chosen then
        for i = 0, count - 1 do
            local at = MAP.first + i * MAP.size
            local family = FAMILY[bucket_buf[at] % 16]
            if family and family == FAMILY[device] then chosen = at; break end
        end
    end
    if not chosen then return NO_GLYPH end
    local b0, extra = bucket_buf[chosen], bucket_buf[chosen + 1]
    local key = bucket_buf[chosen + 4] + bucket_buf[chosen + 5] * 256
    local signature = b0 * 16777216 + extra * 65536 + key  -- the same mapping shows the same glyph
    if signature == binding.signature then return binding.glyph end
    local kind = bit.band(bit.rshift(b0, 4), 0xf)
    local g
    glyph_out[0] = 0
    calls.glyph_texture(glyph_out, kind, key, extra, 0)
    local texture = glyph_out[0]
    if texture ~= 0 then
        g = {id = string.format('glyph %x', tonumber(bit.band(texture, 0xffffffffULL))), texture = texture,
             device = b0 % 16, kind = kind, key = key}
    else
        local name = calls.key_name(kind, key, 0)
        name = name ~= nil and ffi.string(name) or '?'
        if name == '' or #name > 24 then name = '?' end
        g = {id = 'key ' .. name, name = name, device = b0 % 16, kind = kind, key = key}
    end
    binding.signature, binding.glyph = signature, g
    return g
end

-- The upkeep reads every widget it checks with one call per frame, into one buffer (no allocation per frame).
local VIEW_MAX = 0x10000
local view = {size = 0}

local function view_load(lo, size)
    if size > view.size then
        view.buf = ffi.new('uint8_t[?]', size)
        view.size, view.f, view.u = size, ffi.cast('float *', view.buf), ffi.cast('uint32_t *', view.buf)
        view.h = ffi.cast('int16_t *', view.buf)
    end
    if native.k32.ReadProcessMemory(native.process, ffi.cast('const void *', lo), view.buf, size, native.got) == 0
       or tonumber(native.got[0]) ~= size then
        return false
    end
    view.lo = lo
    return true
end

local function vf(address) return view.f[(address - view.lo) / 4] end
local function vh(address) return view.h[(address - view.lo) / 2] end
local function vshown(address) return bit.band(view.u[(address - view.lo) / 4], WIDGET.visible) ~= 0 end

-- The price group's other children (the PRICE label, the other currency icons and amounts, the background...),
-- hidden while the glyph shows. Nil when the list doesn't look like the group's own.
local function group_others(a)
    local group = a.bar + PRICE.group
    local list, c = {}, pointer(read(group + CHILD.first, 8))
    while c do
        if c <= group or c >= a.bar + 0x8000 or #list >= CHILD.max then return nil end
        if c ~= a.bar + PRICE.image and c ~= a.bar + PRICE.text then list[#list + 1] = c end
        c = pointer(read(c + CHILD.next, 8))
    end
    return list
end

-- Saves what the glyph changes, once per bar application.
glyph_save = function(a)
    local image_type, text_type = widget_type(a.bar + PRICE.image), widget_type(a.bar + PRICE.text)
    if image_type ~= WIDGET_TYPE.image or text_type ~= WIDGET_TYPE.text then
        note(string.format('Glyph off: price widgets of type %s/%s, not image/text (game updated?)',
                           tostring(image_type), tostring(text_type)))
        return nil
    end
    local g = {}
    for _, off in ipairs({PRICE.group, PRICE.border, PRICE.image, PRICE.text}) do
        local w = widget(a.bar + off)
        if not (w and w.w) then return nil end
        local c = read(a.bar + off + WIDGET.color, 12)
        local ap = read(a.bar + off + LAYOUT.anchor, 0x18)
        g[off] = {px = w.px, py = w.py, w = w.w, h = w.h, shown = visible(w),
                  anchor = ap and {f32(ap, 0), f32(ap, 4)}, pivot = ap and {f32(ap, 0x10), f32(ap, 0x14)},
                  opacity = f32(read(a.bar + off + OPACITY, 4), 0),
                  color = c and {f32(c, 0), f32(c, 4), f32(c, 8)} or {}}
    end
    local others = group_others(a)
    if not others then
        note('Glyph off: the price group children are not as expected')
        return nil
    end
    g.others = {}
    for i, c in ipairs(others) do g.others[i] = {address = c, shown = visible(widget(c)) and true or false} end
    local t = read(a.bar + PRICE.image + IMAGE_TEXTURE, 8)
    if t then
        local b = ffi.new('uint64_t[1]')
        ffi.copy(b, t, 8)
        g.texture = b[0]
    end
    g.label = read32(a.bar + PRICE.text + WIDGET.label)
    g.text_layer = i16(read(a.bar + PRICE.text + LAYOUT.layer, 2))
    -- Everything the upkeep checks, as one range read once per frame (addresses 4-aligned: the view indexes words).
    local lo, hi = math.huge, 0
    local watched = {a.bar + PRICE.group, a.bar + PRICE.image, a.bar + PRICE.text, a.bar + BAR.text}
    for _, o in ipairs(g.others) do watched[#watched + 1] = o.address end
    for _, w in ipairs(watched) do lo, hi = math.min(lo, w), math.max(hi, w) end
    for _, w in ipairs(watched) do
        if (w - lo) % 4 ~= 0 then note('Glyph off: unaligned widgets'); return nil end
    end
    g.view_lo, g.view_size = lo, hi + LAYOUT.layer + 2 - lo
    if g.view_size > VIEW_MAX then note('Glyph off: widgets too far apart'); return nil end
    return g
end

glyph_restore = function(a)
    local g = a.glyph_saved
    if not g then return end
    for _, o in ipairs(g.others) do
        if o.shown ~= (visible(widget(o.address)) and true or false) then calls.set_visible(o.address, o.shown and 1 or 0) end
    end
    for _, off in ipairs({PRICE.image, PRICE.text, PRICE.border, PRICE.group}) do
        local s = g[off]
        if s.anchor and s.anchor[1] and s.anchor[2] then calls.set_anchor(a.bar + off, vec(s.anchor[1], s.anchor[2])) end
        if s.pivot and s.pivot[1] and s.pivot[2] then calls.set_pivot(a.bar + off, vec(s.pivot[1], s.pivot[2])) end
        if s.px then calls.set_position(a.bar + off, vec(s.px, s.py)) end
        calls.set_size(a.bar + off, vec(s.w, s.h))
        if s.color[1] then calls.set_color(a.bar + off, color_buffer(s.color)) end
        if s.opacity then calls.set_opacity(a.bar + off, s.opacity) end
        calls.set_visible(a.bar + off, s.shown and 1 or 0)
    end
    if g.texture and g.texture ~= 0 and widget_type(a.bar + PRICE.image) == WIDGET_TYPE.image then
        calls.set_image(a.bar + PRICE.image, DIFFUSE_MATERIAL, g.texture, 0)
    end
    if g.label and g.label ~= 0 and widget_type(a.bar + PRICE.text) == WIDGET_TYPE.text then
        calls.clear_args(a.bar + PRICE.text + WIDGET.label)
        calls.set_label(a.bar + PRICE.text, g.label)
    end
    if g.text_layer and i16(read(a.bar + PRICE.text + LAYOUT.layer, 2)) ~= g.text_layer then
        calls.set_layer(a.bar + PRICE.text, g.text_layer)
    end
end

-- The glyph's size: EQUIP's own glyph (local units), else the prompt glyphs' 40-unit canvas.
local function prompt_size(ctl)
    local w = widget(ctl + CTL.detail + DETAIL.button + PROMPT.offset + PROMPT.glyph)
    local size = w and w.h and w.h >= 12 and w.h <= 96 and w.h or 40
    return size
end

-- The text's x: half its margin without a glyph (it made room for the padlock); with one, its full margin plus a
-- gap and whatever a keycap is wider than the 32-unit glyph (its right edge moves by half of that).
local GLYPH_GAP = 8
local function text_x(a, glyph_shown, glyph_w)
    if not a.text_pos then return nil end
    if not glyph_shown then return a.text_pos[1] * TEXT_MARGIN end
    return a.text_pos[1] + GLYPH_GAP + math.max(0, ((glyph_w or KEYCAP.h) - KEYCAP.h) / 2)
end

local function set_text_position(a, glyph_shown, glyph_w)
    local x = text_x(a, glyph_shown, glyph_w)
    if x then calls.set_position(a.bar + BAR.text, vec(x, a.text_pos[2])) end
end

-- Shows the glyph for `g` (from resolve_glyph), or hides it.
local function glyph_draw(a, g, size)
    local image, text = a.bar + PRICE.image, a.bar + PRICE.text
    if widget_type(image) ~= WIDGET_TYPE.image or widget_type(text) ~= WIDGET_TYPE.text then
        note('Glyph off: the price widgets changed type')
        g = nil
    end
    if not g or not (g.texture or g.name) then
        note('Glyph: ' .. (g and g.id or 'unavailable') .. ', hidden')
        calls.set_visible(a.bar + PRICE.group, 0)
        set_text_position(a, false)
        a.glyph = nil
        return
    end
    for _, o in ipairs(a.glyph_saved.others) do calls.set_visible(o.address, 0) end
    calls.set_opacity(a.bar + PRICE.group, 1)
    calls.set_visible(a.bar + PRICE.group, 1)
    -- The prompts' own material and variables (the textures are channel-packed: gui_diffuse_map shows them raw).
    calls.set_image(image, GLYPH_MATERIAL, g.texture or KEYCAP_TEXTURE, 0)
    if (read32(image + IMAGE_MATERIAL) or 0) + (read32(image + IMAGE_MATERIAL + 4) or 0) > 0 then
        for _, v in ipairs(GLYPH_VARIABLES) do calls.set_variable(image, v[1], v[2]) end
    else
        note('Glyph: no material after set_image')
    end
    calls.set_size(image, g.name and vec(KEYCAP.h, KEYCAP.h) or vec(size, size))
    calls.set_visible(image, 1)
    calls.set_opacity(image, 1)
    if g.name then
        calls.clear_args(text + WIDGET.label)
        calls.set_label(text, TEXT_TEMPLATE)
        calls.set_string_arg(text, TEXT_KEY, text_buffer(g.name))
        calls.set_opacity(text, 1)
        calls.set_visible(text, 1)
        calls.set_color(text, color_buffer(KEYCAP_TEXT_COLOR))
    else
        calls.set_visible(text, 0)
    end
    calls.set_color(image, color_buffer(GLYPH_COLOR))
    set_text_position(a, true)
    a.glyph, a.glyph_size = g, size
    note(string.format('Glyph: %s (device %d, kind %d, key %d), size %d', g.id, g.device or -1, g.kind or -1,
                       g.key or -1, size))
end

-- Puts a widget's center at x (bar units) and the bar's vertical middle: anchor (0, 0.5), pivot (0.5, 0.5), and
-- optionally its size. The game's price refresh re-lays the currency icon out (right-aligned), so this runs every
-- frame and only calls what differs.
local function place(address, x, w, h)
    local anchor, pivot, pos, size = address + LAYOUT.anchor, address + LAYOUT.pivot, address + WIDGET.pos,
                                      address + WIDGET.size
    if not (near(vf(anchor), 0) and near(vf(anchor + 4), 0.5)) then calls.set_anchor(address, vec(0, 0.5)) end
    if not (near(vf(pivot), 0.5) and near(vf(pivot + 4), 0.5)) then calls.set_pivot(address, vec(0.5, 0.5)) end
    if not (near(vf(pos), x) and near(vf(pos + 4), 0)) then calls.set_position(address, vec(x, 0)) end
    if w and not (near(vf(size), w) and near(vf(size + 4), h)) then calls.set_size(address, vec(w, h)) end
end

local GLYPH_EVERY = 10  -- the device used last is looked up every 10 frames

local function glyph_maintain(ctl, a)
    if not a.glyph_saved or not a.pad_x then return end
    if M.frames % GLYPH_EVERY == 0 or a.glyph == nil and not a.glyph_checked then
        a.glyph_checked = true
        local g = resolve_glyph()
        local id = g and g.id or 'unavailable'
        if id ~= a.glyph_id then
            a.glyph_id = id
            glyph_draw(a, g, prompt_size(ctl))
        end
    end
    if not a.glyph then return end
    -- Every frame, from one read: the game's price refresh re-shows children and re-lays the icon out.
    local g = a.glyph_saved
    if not view_load(g.view_lo, g.view_size) then return end
    local group, image, text = a.bar + PRICE.group, a.bar + PRICE.image, a.bar + PRICE.text
    if not vshown(group) then calls.set_visible(group, 1) end
    for _, o in ipairs(g.others) do
        if vshown(o.address) then calls.set_visible(o.address, 0) end
    end
    local width = a.glyph_size
    if a.glyph.name then
        -- The keycap fits the name as the game's does (0x17a48a0): width max(16, text width) + 16, height 32
        -- (a label text measures itself: its width is the text's).
        width = math.max(KEYCAP.min, vf(text + WIDGET.size)) + KEYCAP.min
        place(image, a.pad_x, width, KEYCAP.h)
        place(text, a.pad_x)
        if not vshown(text) then calls.set_visible(text, 1) end
        local layer = vh(image + LAYOUT.layer)
        if layer < 32767 and vh(text + LAYOUT.layer) ~= layer + 1 then
            calls.set_layer(text, layer + 1)  -- the name over its keycap
        end
    else
        place(image, a.pad_x, width, width)
    end
    if not vshown(image) then calls.set_visible(image, 1) end
    local x, pos = text_x(a, true, width), a.bar + BAR.text + WIDGET.pos
    if x and not (near(vf(pos), x) and near(vf(pos + 4), a.text_pos[2])) then
        calls.set_position(a.bar + BAR.text, vec(x, a.text_pos[2]))
    end
end

---------------------------------------------------------------------------------------
-- Frame step

local seen = {ctl = nil}

local IDLE_EVERY = 10    -- outside the Armory, look for it every 10 frames
local PLAN_EVERY = 30    -- the viewed item's set is re-evaluated every 30 frames (options, ownership)
local plan_cache = {frame = -math.huge}

local function cached_plan(offer)
    local c = plan_cache
    local slots = (included('c') and 'c' or '') .. (included('p') and 'p' or '')  -- an option change applies at once
    if offer ~= c.offer or slots ~= c.slots or M.frames - c.frame >= PLAN_EVERY then
        c.offer, c.slots, c.frame, c.plan = offer, slots, M.frames, plan_for(offer)
    end
    return c.plan
end

local function step()
    if not seen.ctl and M.frames % IDLE_EVERY ~= 0 then return end
    register_options()
    register_binding()
    local ctl = armory_controller()
    if ctl ~= seen.ctl then
        seen.ctl = ctl
        bar.applied = nil  -- a new or closed Armory: its widgets are the game's to rebuild
        loc.language, loc.cache = nil, {}  -- the language may have changed in the options
        plan_cache.frame = -math.huge
        if ctl then load_offers() end
    end
    if not ctl then return end
    if M.frames % 120 == 0 then
        local prog = object('progression')
        local count = prog and read32(prog + OFFERS.count)
        if count and count ~= offers.count and load_offers() then plan_cache.frame = -math.huge end
    end

    if hover_step(ctl) then return end  -- the bar waits while the hover away and back runs
    local detail = ctl + CTL.detail
    local root = widget(detail + DETAIL.bar)
    if not (visible(root) and root.alpha and root.alpha > 0.5) then return end  -- hidden or fading: the game's
    local plan = cached_plan(read32(detail + DETAIL.offer))
    local a = bar.applied
    if a and (not plan or plan.offer ~= a.offer) then bar_restore(plan and 'item changed' or 'no set') end
    if bar.applied and plan then  -- options or ownership may change the members
        bar.applied.plan = plan
        if plan.label ~= bar.applied.label then
            calls.set_string_arg(bar.applied.bar + BAR.text, TEXT_KEY, text_buffer(plan.label))
            bar.applied.label = plan.label
        end
    end
    if plan and not bar.applied then bar_apply(ctl, plan) end
    a = bar.applied
    if not a then binding.was_down = false end
    if a then
        if not visible(widget(a.bar + BAR.group)) then
            calls.set_visible(a.bar + BAR.group, 1)  -- the game re-hid it (a refresh of the same item)
        end
        outline_maintain(a)
        glyph_maintain(ctl, a)
        local over, pressed = mouse_on(widget(a.bar))
        if binding_pressed() then
            pressed = true
            note('Binding pressed')
        end
        if pressed then
            a.flash = FLASH_FRAMES
            equip(ctl, a.plan)
        end
        feedback(ctl, a, over)
    end
end

local function start()
    local ok, why = init_native()
    if not ok then
        write_file('OneClickArmorSet_STATUS.log', {'NOT AVAILABLE - ' .. why, 'One Click Armor Set ' .. M.version})
        return false
    end
    local lines, ready = resolve()
    local n = 0
    for _ in pairs(SETS) do n = n + 1 end
    table.insert(lines, 1, (ready and 'OK' or 'NOT AVAILABLE') .. ' - One Click Armor Set ' .. M.version)
    lines[#lines + 1] = string.format('set table: %d items', n)
    write_file('OneClickArmorSet_STATUS.log', lines)
    for _, l in ipairs(lines) do note(l) end
    return ready
end

-- Defined once: a closure created every frame would keep the shared JIT from compiling the hook (loader v18 notes).
local function frame()
    M.frames = M.frames + 1
    if M.frames == 1 then
        if not start() then M.retired = true end
    else
        step()
    end
end

local original_update = rawget(_G, 'update')
update = function(dt, ...)
    if not M.retired then
        local ok, err = xpcall(frame, debug.traceback)
        if not ok then
            M.errors = M.errors + 1
            note('Error: ' .. tostring(err))
            if M.errors >= 5 then M.retired = true; note('Stopped after repeated errors') end
        end
    end
    if type(original_update) == 'function' then return original_update(dt, ...) end
end

note('One Click Armor Set ' .. M.version .. ' loaded')
M._test = {bar = bar, offers = offers, SETS = SETS}
return M
