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
        ['option.cape.description'] = 'EQUIP SET also equips the cape of the set.',
        ['option.card.label'] = 'Include Player Card',
        ['option.card.description'] = 'EQUIP SET also equips the player card of the set.',
        -- The key binding's name in Mod Bindings Menu.
        ['binding.equip_set'] = 'Equip Set',
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
              ['option.card.label'] = 64, ['option.card.description'] = 400, ['binding.equip_set'] = 64},
}
