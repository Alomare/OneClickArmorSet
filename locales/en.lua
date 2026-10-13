-- One Click Armor Set: English texts, the source of every translation.
-- Translators: see TRANSLATING.md in Mod Options Menu's repository (the same files and tool work for this mod).
-- Option texts show in Mod Options Menu (escape menu > MODS), which upper-cases the mod name; the binding shows in
-- Mod Bindings Menu; the button texts show on the bar beside the Armory's EQUIP button, in the game's font.
return {
    mod = 'one_click_armor_set',
    title = 'One Click Armor Set',
    language = 'en',
    strings = {
        -- The mod's name: its category button in Mod Options Menu and its section in Mod Bindings Menu.
        ['option.mod'] = 'One Click Armor Set',
        -- The two toggles and the text shown beside each.
        ['option.cape.label'] = 'Include Cape',
        ['option.cape.description'] = 'EQUIP SET also equips the cape of the set, and Randomize Armor changes the cape too.',
        ['option.card.label'] = 'Include Player Card',
        ['option.card.description'] = 'EQUIP SET also equips the player card of the set, and Randomize Armor changes the player card too.',
        -- A choice: what Randomize Armor puts on, and its two choices (shown in upper case).
        ['option.random_mode.label'] = 'Randomization Mode',
        ['option.random_mode.description'] = 'What the Randomize Armor key puts on: a whole set you own at least two pieces of, or a random helmet, armor, cape and player card, each on its own.',
        ['option.random_mode.sets'] = 'Whole Sets',
        ['option.random_mode.pieces'] = 'Each Piece',
        -- A toggle: Randomize Armor keeps the weight class (light, medium, heavy) of the armor worn.
        ['option.keep_weight.label'] = 'Keep Armor Weight',
        ['option.keep_weight.description'] = 'Randomize Armor only picks armor of the weight you are wearing (light, medium or heavy), and with Each Piece only helmets of that weight too.',
        -- The key binding's name in Mod Bindings Menu.
        ['binding.equip_set'] = 'Equip Set',
        -- The second key binding's name: it puts on random armor (a whole set or each piece, as the option below says).
        ['binding.randomize'] = 'Randomize Armor',
        -- The button. {name} is the armor's name without its designation (KODIAK for CW-22 KODIAK), {owned} how many
        -- pieces of the set you own and {total} how many it has. Upper case, like the game's own EQUIP.
        ['button.equip_named'] = 'EQUIP {name} SET ({owned}/{total})',
        -- When the set has no name in the game's texts.
        ['button.equip'] = 'EQUIP SET ({owned}/{total})',
        -- When every piece you own is already equipped (the button is greyed out).
        ['button.equipped_named'] = '{name} SET EQUIPPED ({owned}/{total})',
        ['button.equipped'] = 'SET EQUIPPED ({owned}/{total})',
    },
    -- Mod Options Menu's and Mod Bindings Menu's limits, in characters.
    limits = {['option.mod'] = 40, ['option.cape.label'] = 64, ['option.cape.description'] = 400,
              ['option.card.label'] = 64, ['option.card.description'] = 400, ['binding.equip_set'] = 64,
              ['option.random_mode.label'] = 64, ['option.random_mode.description'] = 400,
              ['option.random_mode.sets'] = 48, ['option.random_mode.pieces'] = 48,
              ['option.keep_weight.label'] = 64, ['option.keep_weight.description'] = 400,
              ['binding.randomize'] = 64},
}
