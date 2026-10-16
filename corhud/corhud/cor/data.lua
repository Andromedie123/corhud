-- cor/data.lua - static tables: roll values, bonuses, cards, Wild Card (HorizonXI).

local M = {}

M.WILD_CARD_ID = 96
M.FOLD_ID = 178
M.SNAKE_EYE_ID = 177

M.MERIT_ABILITY_IDS = {
    [0xC10] = 'Snake Eye',
    [0xC16] = 'Fold',
}

M.ABILITY_RECAST_NAMES = {
    [M.FOLD_ID] = 'Fold',
    [M.SNAKE_EYE_ID] = 'Snake Eye',
}
M.HORIZON_ROLL_PLUS = {
    ear = {
        name = "Luzaf's Fang", -- NQ / +1 ('Luzaf's Fang +1' is exactly 15)
        ids  = { [26114] = 1, [26115] = 1 },
    },
    legs = {
        name = "Corsair's Culo", -- 'Corsair's Culottes' NQ / +1, truncated
        ids  = { [15601] = 1, [16348] = 1 },
    },
}
M.WILD_CARD_RECAST = 2 * 60 * 60
M.WILD_CARD_EFFECTS = {
    [1] = 'All job abilities restored',
    [2] = 'All job abilities restored',
    [3] = 'All job abilities restored, +1000 TP',
    [4] = 'All job abilities restored, TP set to 3000',
    [5] = 'All job abilities and two-hour abilities restored, +33% max MP',
    [6] = 'All job abilities and two-hour abilities restored, MP set to 100%',
}

M.ROLL_PLUS_DATA = {
    ['Ninja Roll'] = {
        plus_1 = { 13, 16, 18, 43, 21, 23, 28, 8, 30, 33, 53 }, bust_1 = -15,
        plus_2 = { 16, 19, 21, 46, 24, 26, 31, 11, 33, 36, 56 }, bust_2 = -15,
    },
    ["Hunter's Roll"] = {
        plus_1 = { 13, 16, 18, 43, 21, 23, 28, 8, 30, 33, 53 }, bust_1 = -15,
        plus_2 = { 16, 19, 21, 46, 24, 26, 31, 11, 33, 36, 56 }, bust_2 = -15,
    },
    ['Chaos Roll'] = {
        plus_1 = { 31, 39, 42, 100, 49, 59, 66, 22, 69, 77, 121 }, bust_1 = -15,
        plus_2 = { 33, 42, 45, 108, 53, 62, 71, 23, 74, 83, 131 }, bust_2 = -15,
    },
    ["Healer's Roll"] = {
        plus_1 = { 3, 4, 11, 5, 5, 6, 2, 7, 7, 8, 13 }, bust_1 = -3,
        plus_2 = { 4, 5, 14, 6, 6, 7, 3, 8, 8, 9, 18 }, bust_2 = -3,
    },
    ["Gallant's Roll"] = {
        plus_1 = { 52, 64, 204, 76, 92, 108, 36, 124, 144, 164, 244 }, bust_1 = -120,
        plus_2 = { 56, 68, 208, 80, 96, 112, 40, 128, 148, 168, 248 }, bust_2 = -120,
    },
    ["Evoker's Roll"] = {
        plus_1 = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 2, 4 }, bust_1 = -1,
        plus_2 = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 3, 4 }, bust_2 = -1,
    },
    ['Drachen Roll'] = {
        plus_1 = { 6, 7, 8, 16, 9, 10, 11, 4, 13, 14, 18 }, bust_1 = 'No effect!',
        plus_2 = { 7, 8, 9, 19, 10, 11, 12, 5, 15, 16, 21 }, bust_2 = 'No effect!',
    },
    ['Beast Roll'] = {
        plus_1 = { 17, 23, 23, 53, 26, 31, 35, 12, 37, 41, 121 }, bust_1 = 'No effect!',
        plus_2 = { 19, 26, 26, 61, 30, 35, 40, 13, 42, 47, 131 }, bust_2 = 'No effect!',
    },
    ['Puppet Roll'] = {
        plus_1 = { 12, 16, 70, 24, 27, 35, 4, 43, 50, 58, 58 }, bust_1 = -8,
        plus_2 = { 12, 20, 70, 24, 31, 39, 8, 47, 54, 62, 62 }, bust_2 = -8,
    },
    ["Wizard's Roll"] = {
        plus_1 = { 7, 10, 14, 14, 35, 17, 21, 25, 3, 25, 42 }, bust_1 = -15,
        plus_2 = { 10, 10, 17, 17, 39, 21, 25, 28, 7, 28, 46 }, bust_2 = -15,
    },
}

-- ---------------------------------------------------------------- cards --
M.CARD_NAMES = {
    'Light Card', 'Dark Card',
    'Fire Card', 'Ice Card', 'Wind Card', 'Earth Card',
    'Thunder Card', 'Water Card',
}

-- ----------------------------------------------------------------- rolls --
M.ROLL_IDS = {
    [98]  = "Fighter's Roll",     [99]  = "Monk's Roll",
    [100] = "Healer's Roll",      [101] = "Wizard's Roll",
    [102] = "Warlock's Roll",     [103] = "Rogue's Roll",
    [104] = "Gallant's Roll",     [105] = 'Chaos Roll',
    [106] = 'Beast Roll',         [107] = 'Choral Roll',
    [108] = "Hunter's Roll",      [109] = 'Samurai Roll',
    [110] = 'Ninja Roll',         [111] = 'Drachen Roll',
    [112] = "Evoker's Roll",      [113] = "Magus's Roll",
    [114] = "Corsair's Roll",     [115] = 'Puppet Roll',
    [116] = "Dancer's Roll",      [117] = "Scholar's Roll",
    [118] = "Bolter's Roll",      [119] = "Caster's Roll",
    [120] = "Courser's Roll",     [121] = "Blitzer's Roll",
    [122] = "Tactician's Roll",   [302] = "Allies' Roll",
    [303] = "Miser's Roll",       [304] = "Companion's Roll",
    [305] = "Avenger's Roll",     [390] = "Naturalist's Roll",
    [391] = "Runeist's Roll",
}

M.ROLL_STATUS_IDS = {
    [98]  = 310, [99]  = 311, [100] = 312, [101] = 313, [102] = 314,
    [103] = 315, [104] = 316, [105] = 317, [106] = 318, [107] = 319,
    [108] = 320, [109] = 321, [110] = 322, [111] = 323, [112] = 324,
    [113] = 325, [114] = 326, [115] = 327, [116] = 328, [117] = 329,
    [118] = 330, [119] = 331, [120] = 332, [121] = 333, [122] = 334,
    [302] = 335, [303] = 336, [304] = 337, [305] = 338,
    [390] = 339, [391] = 600,
}

M.BUST_ICON = 309

M.ROLL_RESULT_MSGS = {
    [100] = true, [205] = true, [230] = true, [266] = true, [280] = true,
    [319] = true, [420] = true, [421] = true, [424] = true, [425] = true,
    [426] = true,
}

M.ROLL_ICON_NAMES = {}
for abilityId, statusId in pairs(M.ROLL_STATUS_IDS) do
    local name = M.ROLL_IDS[abilityId]
    if name ~= nil then M.ROLL_ICON_NAMES[statusId] = name end
end

M.ROLL_DATA = {
    ["Corsair's Roll"] = { lucky = 5, unlucky = 9, effect = 2, bust = 6, percent = true,
        desc = 'Experience / Capacity Points',
        rolls = { 10, 11, 11, 12, 20, 13, 15, 16, 8, 17, 24 } },
    ['Ninja Roll'] = { lucky = 4, unlucky = 8, effect = 2, bust = 10, percent = false,
        desc = 'Evasion',
        rolls = { 4, 6, 8, 25, 10, 12, 14, 2, 17, 20, 30 } },
    ["Hunter's Roll"] = { lucky = 4, unlucky = 8, effect = 5, bust = 15, percent = false,
        desc = 'Accuracy',
        rolls = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50 } },
    ['Chaos Roll'] = { lucky = 4, unlucky = 8, effect = 3, bust = 10, percent = true,
        desc = 'Attack',
        rolls = { 6.3, 7.8, 9.4, 25, 10.9, 12.5, 15.6, 3.1, 17.2, 18.8, 31.2 } },
    ["Magus's Roll"] = { lucky = 2, unlucky = 6, effect = 2, bust = 8, percent = false,
        desc = 'Magic Defense Bonus',
        rolls = { 5, 20, 6, 8, 9, 3, 10, 13, 14, 15, 25 } },
    ["Healer's Roll"] = { lucky = 3, unlucky = 7, effect = 1, bust = -3, percent = false,
        desc = 'MP recovered while healing',
        rolls = { 2, 3, 10, 4, 4, 5, 1, 6, 6, 7, 12 } },
    ['Drachen Roll'] = { lucky = 4, unlucky = 8, effect = 5, bust = 15, percent = false,
        desc = 'Pet: Accuracy / Ranged Accuracy',
        rolls = { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 } },
    ['Choral Roll'] = { lucky = 2, unlucky = 6, effect = 4, bust = 25, percent = true,
        desc = 'Spell Interruption Rate Down',
        rolls = { 8, 42, 11, 15, 19, 4, 23, 27, 31, 35, 50 } },
    ["Monk's Roll"] = { lucky = 3, unlucky = 7, effect = 5, bust = 10, percent = false,
        desc = 'Subtle Blow',
        rolls = { 8, 10, 32, 12, 14, 16, 4, 20, 22, 24, 40 } },
    ['Beast Roll'] = { lucky = 4, unlucky = 8, effect = 3, bust = 10, percent = true,
        desc = 'Pet: Attack / Ranged Attack',
        rolls = { 6, 8, 9, 25, 11, 13, 16, 3, 17, 19, 31 } },
    ['Samurai Roll'] = { lucky = 2, unlucky = 6, effect = 4, bust = 10, percent = false,
        desc = 'Store TP',
        rolls = { 8, 32, 10, 12, 14, 4, 16, 20, 22, 24, 40 } },
    ["Evoker's Roll"] = { lucky = 5, unlucky = 9, effect = 1, bust = 'Unknown', percent = false,
        desc = 'Refresh',
        rolls = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 2, 4 } },
    ["Rogue's Roll"] = { lucky = 5, unlucky = 9, effect = 1, bust = 5, percent = true,
        desc = 'Critical Hit Rate',
        rolls = { 1, 2, 3, 4, 10, 5, 6, 7, 1, 8, 14 } },
    ["Warlock's Roll"] = { lucky = 4, unlucky = 8, effect = 1, bust = 5, percent = false,
        desc = 'Magic Accuracy',
        rolls = { 2, 3, 4, 12, 5, 6, 7, 1, 8, 9, 15 } },
    ["Fighter's Roll"] = { lucky = 5, unlucky = 9, effect = 1, bust = 'Unknown', percent = true,
        desc = 'Double Attack',
        rolls = { 1, 2, 3, 4, 10, 5, 6, 6, 1, 7, 15 } },
    ['Puppet Roll'] = { lucky = 3, unlucky = 7, effect = 3, bust = 12, percent = false,
        desc = 'Pet: Magic Accuracy / Magic Attack Bonus',
        rolls = { 5, 8, 35, 11, 14, 18, 2, 22, 26, 30, 40 } },
    ["Gallant's Roll"] = { lucky = 3, unlucky = 7, effect = 1, bust = -120, percent = false,
        desc = 'Defense',
        rolls = { 48, 60, 200, 72, 88, 104, 32, 120, 140, 160, 240 } },
    ["Wizard's Roll"] = { lucky = 5, unlucky = 9, effect = 2, bust = 10, percent = false,
        desc = 'Magic Attack Bonus',
        rolls = { 4, 6, 8, 10, 25, 12, 14, 17, 2, 20, 30 } },
    ["Dancer's Roll"] = { lucky = 3, unlucky = 7, effect = 2, bust = 4, percent = false,
        desc = 'Regen',
        rolls = { 3, 4, 12, 5, 6, 7, 1, 8, 9, 10, 16 } },
    ["Scholar's Roll"] = { lucky = 2, unlucky = 6, effect = 'Unknown', bust = 3, percent = false,
        desc = 'Conserve MP',
        rolls = { 2, 10, 3, 4, 4, 1, 5, 6, 7, 7, 12 } },
    ["Naturalist's Roll"] = { lucky = 3, unlucky = 7, effect = 1, bust = 5, percent = false,
        desc = 'Enhancing Magic Duration',
        rolls = { 6, 7, 15, 8, 9, 10, 5, 11, 12, 13, 20 } },
    ["Runeist's Roll"] = { lucky = 4, unlucky = 8, effect = 2, bust = 10, percent = false,
        desc = 'Magic Evasion',
        rolls = { 4, 6, 8, 25, 10, 12, 14, 2, 17, 20, 30 } },
    ["Bolter's Roll"] = { lucky = 3, unlucky = 9, effect = 4, bust = 0, percent = false,
        desc = 'Movement Speed',
        rolls = { 6, 6, 16, 8, 8, 10, 10, 12, 4, 14, 20 } },
    ["Caster's Roll"] = { lucky = 2, unlucky = 7, effect = 3, bust = 10, percent = false,
        desc = 'Fast Cast',
        rolls = { 6, 15, 7, 8, 9, 10, 5, 11, 12, 13, 20 } },
    ["Courser's Roll"] = { lucky = 3, unlucky = 9, effect = 'Unknown', bust = 'Unknown', percent = false,
        desc = 'Snapshot',
        rolls = { 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown',
                  'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown' } },
    ["Blitzer's Roll"] = { lucky = 4, unlucky = 9, effect = 1, bust = 'Unknown', percent = false,
        desc = 'Haste',
        rolls = { 2, 3, 4, 11, 5, 6, 7, 8, 1, 10, 12 } },
    ["Tactician's Roll"] = { lucky = 5, unlucky = 8, effect = 2, bust = 10, percent = false,
        desc = 'Regain',
        rolls = { 10, 10, 10, 10, 30, 10, 10, 0, 20, 20, 40 } },
    ["Allies' Roll"] = { lucky = 3, unlucky = 10, effect = 1, bust = 5, percent = false,
        desc = 'Skillchain Damage / Accuracy',
        rolls = { 2, 3, 20, 5, 7, 9, 11, 13, 15, 1, 25 } },
    ["Miser's Roll"] = { lucky = 5, unlucky = 7, effect = 15, bust = 0, percent = false,
        desc = 'Save TP',
        rolls = { 30, 50, 70, 90, 200, 110, 20, 130, 150, 170, 250 } },
    ["Avenger's Roll"] = { lucky = 4, unlucky = 8, effect = 'Unknown', bust = 'Unknown', percent = false,
        desc = 'Counter Rate',
        rolls = { 'Unknown', 'Unknown', 'Unknown', 14, 'Unknown', 'Unknown',
                  'Unknown', 'Unknown', 'Unknown', 'Unknown', 16 } },
    ["Companion's Roll"] = { lucky = 2, unlucky = 10, effect = '5,2', bust = '0,0', percent = false,
        desc = 'Pet: Regain / Regen', dual = true,
        rolls = { '20,4', '50,20', '20,6', '20,8', '30,10', '30,12', '30,14',
                  '40,16', '40,18', '10,3', '60,25' } },
}

M.HORIZON_ROLLS = {
    ["Fighter's Roll"] = { rolls = { 2, 2, 3, 4, 12, 5, 6, 6, 1, 9, 18 }, bust = -6, effect = 1, percent = true, desc = 'Double Attack' },
    ["Monk's Roll"] = { rolls = { 8, 10, 32, 12, 14, 16, 4, 20, 22, 24, 40 }, bust = -11, effect = 4, percent = false, desc = 'Subtle Blow' },
    ["Wizard's Roll"] = { rolls = { 7, 10, 14, 14, 35, 17, 21, 25, 3, 25, 42 }, bust = -15, effect = 2, percent = false, desc = 'Magic Attack Bonus' },
    ["Warlock's Roll"] = { rolls = { 2, 3, 4, 12, 5, 6, 7, 1, 8, 9, 15 }, bust = -5, effect = 1, percent = false, desc = 'Magic Accuracy' },
    ["Rogue's Roll"] = { rolls = { 2, 2, 3, 4, 12, 5, 6, 6, 1, 8, 19 }, bust = -6, effect = 1, percent = true, desc = 'Critical Hit Rate' },
    ["Beast Roll"] = { rolls = { 15, 20, 20, 45, 22, 27, 30, 11, 32, 35, 111 }, bust = 'No effect!', effect = 3, percent = false, desc = 'Pet: Attack / Ranged Attack' },
    ['Choral Roll'] = { rolls = { -13, -55, -17, -20, -25, -8, -30, -35, -40, -45, -65 }, bust = 25, effect = 4, percent = false, desc = 'Spell Interruption Rate Down' },
    ["Hunter's Roll"] = { rolls = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50 }, bust = -15, effect = 5, percent = false, desc = 'Accuracy' },
    ['Samurai Roll'] = { rolls = { 8, 32, 10, 12, 14, 4, 16, 20, 22, 24, 40 }, bust = -5, effect = 4, percent = false, desc = 'Store TP' },
    ['Ninja Roll'] = { rolls = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50 }, bust = -15, effect = 2, percent = false, desc = 'Evasion' },
    ['Drachen Roll'] = { rolls = { 5, 6, 7, 13, 8, 9, 10, 3, 11, 12, 15 }, bust = 'No effect!', effect = 3, percent = false, desc = 'Pet: Accuracy / Ranged Accuracy' },
    ["Magus's Roll"] = { rolls = { 5, 20, 6, 8, 9, 3, 10, 13, 14, 15, 25 }, bust = -5, effect = 2, percent = false, desc = 'Magic Defense Bonus' },
    ["Corsair's Roll"] = { rolls = { 10, 11, 11, 12, 20, 13, 15, 16, 8, 17, 24 }, bust = 6, effect = 2, percent = true, desc = 'Experience / Capacity Points' },
    ['Puppet Roll'] = { rolls = { 8, 16, 66, 20, 27, 35, 4, 43, 50, 58, 58 }, bust = -8, effect = 3, percent = false, desc = 'Pet: Magic Accuracy / Magic Attack Bonus' },
    ["Dancer's Roll"] = { rolls = { 3, 4, 12, 5, 6, 7, 1, 8, 9, 10, 16 }, bust = 4, effect = 2, percent = false, desc = 'Regen' },
    ["Scholar's Roll"] = { rolls = { 2, 9, 3, 4, 5, 2, 6, 6, 7, 9, 14 }, bust = 4, effect = 1, percent = false, desc = 'Conserve MP' },
    ["Bolter's Roll"] = { rolls = { 6, 6, 16, 8, 8, 10, 10, 12, 4, 14, 20 }, bust = 0, effect = 4, percent = true, desc = 'Movement Speed' },
    ["Caster's Roll"] = { rolls = { 6, 15, 7, 8, 9, 10, 5, 11, 12, 13, 20 }, bust = -10, effect = 3, percent = true, desc = 'Fast Cast' },
    ["Courser's Roll"] = { rolls = { 2, 3, 11, 4, 5, 6, 7, 8, 1, 10, 12 }, bust = -5, effect = 1, percent = true, desc = 'Snapshot' },
    ["Blitzer's Roll"] = { rolls = { -2, -3, -4, -11, -5, -6, -7, -8, -1, -10, -12 }, bust = 3, effect = -1, percent = true, desc = 'Attack Delay' },
    ["Tactician's Roll"] = { rolls = { 10, 10, 10, 10, 30, 10, 10, 0, 20, 20, 40 }, bust = -10, effect = 2, percent = false, desc = 'Regain' },
    ["Allies' Roll"] = { rolls = { 2, 3, 20, 5, 7, 9, 11, 13, 15, 1, 25 }, bust = -5, effect = 1, percent = true, desc = 'Skillchain Damage / Accuracy' },
    ["Miser's Roll"] = { rolls = { 30, 50, 70, 90, 200, 110, 20, 130, 150, 170, 250 }, bust = 0, effect = 15, percent = false, desc = 'Save TP' },
    ["Companion's Roll"] = { rolls = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }, bust = 0, effect = 10, percent = false, unknown = true, desc = 'Pet Regen (unverified)' },
    ["Avenger's Roll"] = { rolls = { 2, 2, 3, 12, 4, 5, 6, 1, 7, 9, 18 }, bust = 6, effect = 1, percent = true, desc = 'Counter Rate' },
    ["Naturalist's Roll"] = { rolls = { 6, 7, 15, 8, 9, 10, 5, 11, 12, 13, 20 }, bust = -5, effect = 1, percent = true, desc = 'Enhancing Magic Duration' },
    ["Runeist's Roll"] = { rolls = { 4, 6, 8, 25, 10, 12, 14, 2, 17, 20, 30 }, bust = -10, effect = 2, percent = false, desc = 'Magic Evasion' },
    ['Chaos Roll'] = { rolls = { 29, 36, 39, 92, 45, 54, 61, 21, 64, 71, 111 }, bust = -15, effect = 3, percent = false, desc = 'Attack' },
    ["Gallant's Roll"] = { rolls = { 48, 60, 200, 72, 88, 104, 32, 120, 140, 160, 240 }, bust = -120, effect = 4, percent = false, desc = 'Defense' },
    ["Healer's Roll"] = { rolls = { 2, 3, 10, 4, 4, 5, 1, 6, 6, 7, 12 }, bust = -3, effect = 3, percent = false, desc = 'MP recovered while healing' },
    ["Evoker's Roll"] = { rolls = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 2, 4 }, bust = -1, effect = 1, percent = false, desc = 'Refresh' },
}

M.ORDER = {
    "Corsair's Roll", "Ninja Roll", "Hunter's Roll", "Chaos Roll", "Magus's Roll",
    "Healer's Roll", "Drachen Roll", "Choral Roll", "Monk's Roll", "Beast Roll",
    "Samurai Roll", "Evoker's Roll", "Rogue's Roll", "Warlock's Roll", "Fighter's Roll",
    "Puppet Roll", "Gallant's Roll", "Wizard's Roll",
}

return M
