-- cor/data.lua - static reference data: the Quick Draw cards this addon
-- tracks, and the Corsair roll table (lucky/unlucky numbers, the bonus at
-- each of the eleven possible rolls, the Double-Up effect step, the bust
-- penalty and a short description of what the roll actually buffs).
--
-- The roll numbers are the long-standing community measurements used by
-- addons like RollTracker; they are not pulled from any packet. Treat the
-- 'Unknown' entries as literally unmeasured rather than zero.
local M = {}

M.WILD_CARD_ID = 96
M.FOLD_ID = 178
M.SNAKE_EYE_ID = 177

-- Client merit data ids for Fold and Snake Eye - the same id space as
-- Winning Streak's 0xC04, which the merit menu packet channel verified
-- in-game (2026-09-26). Group 2 merits step by 6 in menu order, so
-- Snake Eye sits two slots and Fold three slots after Winning Streak.
-- The exact pair order is unverified, but for the Rolls window's
-- visibility rule only "either has points" matters, and the ability-use
-- channel in abilities.lua does not depend on these at all.
M.MERIT_ABILITY_IDS = {
    [0xC10] = 'Snake Eye',
    [0xC16] = 'Fold',
}

-- Merit abilities whose recast the Rolls window can show a timer for
-- (Horizon: 15:00 base, -2:30 per merit; the packet carries the real,
-- merit-adjusted recast so no merit math lives in the addon).
M.ABILITY_RECAST_NAMES = {
    [M.FOLD_ID] = 'Fold',
    [M.SNAKE_EYE_ID] = 'Snake Eye',
}
-- Horizon's two Phantom Roll+ pieces, each worth +1 and stacking for
-- the current +2 cap. Each family matches by NAME where the client
-- resources carry the Horizon name, with the confirmed Horizon item ids
-- as a fallback for clients whose resources still carry the pre-rename
-- name (Horizon renamed Balder's Earring into Luzaf's Fang, ids kept -
-- so #26114/#26115 are Luzaf's Fang / +1, NOT the Culottes). A prefix
-- per family identifies a piece's NQ and +1 copies without
-- double-counting. The legs prefix stops at 15 chars because the client
-- truncates long resource names (the resources call 'Thunder Card Case'
-- 'Thnd. Card Case').
M.HORIZON_ROLL_PLUS = {
    ear = {
        name = "Luzaf's Fang", -- NQ / +1 ('Luzaf's Fang +1' is exactly 15)
        -- Confirmed on a friend's client via 0x050 packet data: the fang
        -- is 26114 (Horizon renamed Balder's Earring into it, ids kept).
        ids  = { [26114] = 1, [26115] = 1 },
    },
    legs = {
        name = "Corsair's Culo", -- 'Corsair's Culottes' NQ / +1, truncated
        -- 15601 confirmed as Corsair's Culottes on the friend's client
        -- (0x050); 16348 is presumed its +1 (same original id pair).
        ids  = { [15601] = 1, [16348] = 1 },
    },
}
M.WILD_CARD_RECAST = 2 * 60 * 60
-- Horizon's six Wild Card outcomes per the update patch notes (the
-- wiki-derived split between "some"/"all" abilities was wrong, and so
-- were the TP/MP amounts). Rolls 1-2 are identical.
M.WILD_CARD_EFFECTS = {
    [1] = 'All job abilities restored',
    [2] = 'All job abilities restored',
    [3] = 'All job abilities restored, +1000 TP',
    [4] = 'All job abilities restored, TP set to 3000',
    [5] = 'All job abilities and two-hour abilities restored, +33% max MP',
    [6] = 'All job abilities and two-hour abilities restored, MP set to 100%',
}

-- Confirmed HorizonXI main-job tables for the two Phantom Roll+ gear tiers.
-- Keys must match the ROLL_IDS names below exactly, or the plus lookup
-- silently misses and the base-table fallback is shown instead.
-- Missing entries are intentionally left out until verified - by the wiki,
-- or by in-game measurement (Gallant's +2 came from the user's friend).
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
    },
    ["Gallant's Roll"] = {
        plus_1 = { 52, 64, 204, 76, 92, 108, 36, 124, 144, 164, 244 }, bust_1 = -120,
        -- +2 measured in-game by the user's friend (2026-09-26): every cell
        -- is the +1 cell plus the 4-point effect step, exactly. The bust
        -- was not measured; -120 follows the base and +1 values (every
        -- other roll keeps the same bust across tiers).
        plus_2 = { 56, 68, 208, 80, 96, 112, 40, 128, 148, 168, 248 }, bust_2 = -120,
    },
    ["Evoker's Roll"] = {
        plus_1 = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 2, 4 }, bust_1 = -1,
        plus_2 = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 3, 4 }, bust_2 = -1,
    },
}

-- ---------------------------------------------------------------- cards --
-- The ammo Quick Draw consumes. Tracked by NAME (not item id) so this works
-- unmodified across any FFXI item resource set. This order is also the
-- display order in the cards window; Light and Dark are intentionally first.
M.CARD_NAMES = {
    'Light Card', 'Dark Card',
    'Fire Card', 'Ice Card', 'Wind Card', 'Earth Card',
    'Thunder Card', 'Water Card',
}

-- ----------------------------------------------------------------- rolls --
-- Maps the Phantom Roll ability id (as seen in the 0x028 action packet,
-- category 6) to the roll's display name.
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

-- The status-effect icon id each roll occupies on this client, so a
-- roll's icon disappearing from the 0x076 party-buff snapshot (or the
-- 0x063 self snapshot) can be matched back to the roll. Values are the
-- Horizon timers fork's CorsairRolls table, cross-checked by the 0x063
-- packet capture (Chaos Roll = 317, the fork's 105).
M.ROLL_STATUS_IDS = {
    [98]  = 310, [99]  = 311, [100] = 312, [101] = 313, [102] = 314,
    [103] = 315, [104] = 316, [105] = 317, [106] = 318, [107] = 319,
    [108] = 320, [109] = 321, [110] = 322, [111] = 323, [112] = 324,
    [113] = 325, [114] = 326, [115] = 327, [116] = 328, [117] = 329,
    [118] = 330, [119] = 331, [120] = 332, [121] = 333, [122] = 334,
    [302] = 335, [303] = 336, [304] = 337, [305] = 338,
    [390] = 339, [391] = 600,
}

-- The Bust debuff's icon id (also on the timers fork; sits just below
-- the roll range, so merits.lua's roll detection never confuses it).
M.BUST_ICON = 309

-- First-target-action message ids that mean "the effect landed on this
-- target block's character" - tTimers' applied-buff message set (the
-- working reference on this client) plus 426, the timers fork's bust
-- id. The recipient of a roll is whichever block carries one of these;
-- for a roll cast on another member the packet leads with the caster's
-- dice block instead.
M.ROLL_RESULT_MSGS = {
    [100] = true, [205] = true, [230] = true, [266] = true, [280] = true,
    [319] = true, [420] = true, [421] = true, [424] = true, [425] = true,
    [426] = true,
}

-- Inverse map for the snapshot diffs: icon id -> roll name.
M.ROLL_ICON_NAMES = {}
for abilityId, statusId in pairs(M.ROLL_STATUS_IDS) do
    local name = M.ROLL_IDS[abilityId]
    if name ~= nil then M.ROLL_ICON_NAMES[statusId] = name end
end

-- Per roll: lucky/unlucky call-out numbers, the bonus granted at each roll
-- of 1-11 ('rolls'), the per-tier Double-Up 'effect' step used by certain
-- neck/ring gear that boosts the 11 (see cor/rolls.lua bonus()), the bust
-- penalty applied on a roll over 11, and what stat the roll actually buffs.
-- Percent-based rolls are flagged so the UI can append a '%'.
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
    -- Two values per roll: Regain / Regen.
    ["Companion's Roll"] = { lucky = 2, unlucky = 10, effect = '5,2', bust = '0,0', percent = false,
        desc = 'Pet: Regain / Regen', dual = true,
        rolls = { '20,4', '50,20', '20,6', '20,8', '30,10', '30,12', '30,14',
                  '40,16', '40,18', '10,3', '60,25' } },
}

-- HorizonXI Wiki Main Job values, kept separate from the retail/reference
-- table above so the server-era behavior is explicit and easy to update.
M.HORIZON_ROLLS = {
    ["Fighter's Roll"] = { rolls = { 2, 2, 3, 4, 12, 5, 6, 6, 1, 9, 18 }, bust = -6, effect = 1, percent = true, desc = 'Double Attack' },
    ["Monk's Roll"] = { rolls = { 8, 10, 32, 12, 14, 16, 4, 20, 22, 24, 40 }, bust = -11, effect = 4, percent = false, desc = 'Subtle Blow' },
    ["Wizard's Roll"] = { rolls = { 2, 3, 4, 4, 10, 5, 6, 7, 1, 7, 12 }, bust = -4, effect = 2, percent = false, desc = 'Magic Attack Bonus' },
    ["Warlock's Roll"] = { rolls = { 2, 3, 4, 12, 5, 6, 7, 1, 8, 9, 15 }, bust = -5, effect = 1, percent = false, desc = 'Magic Accuracy' },
    ["Rogue's Roll"] = { rolls = { 2, 2, 3, 4, 12, 5, 6, 6, 1, 8, 19 }, bust = -6, effect = 1, percent = true, desc = 'Critical Hit Rate' },
    ["Beast Roll"] = { rolls = { 16, 20, 24, 64, 28, 32, 40, 8, 44, 48, 80 }, bust = 'No effect!', effect = 3, percent = false, desc = 'Pet: Attack / Ranged Attack' },
    ['Choral Roll'] = { rolls = { -13, -55, -17, -20, -25, -8, -30, -35, -40, -45, -65 }, bust = 25, effect = 4, percent = false, desc = 'Spell Interruption Rate Down' },
    ["Hunter's Roll"] = { rolls = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50 }, bust = -15, effect = 5, percent = false, desc = 'Accuracy' },
    ['Samurai Roll'] = { rolls = { 8, 32, 10, 12, 14, 4, 16, 20, 22, 24, 40 }, bust = -5, effect = 4, percent = false, desc = 'Store TP' },
    ['Ninja Roll'] = { rolls = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50 }, bust = -15, effect = 2, percent = false, desc = 'Evasion' },
    ['Drachen Roll'] = { rolls = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50 }, bust = 'No effect!', effect = 5, percent = false, desc = 'Pet: Accuracy / Ranged Accuracy' },
    ["Magus's Roll"] = { rolls = { 5, 20, 6, 8, 9, 3, 10, 13, 14, 15, 25 }, bust = -5, effect = 2, percent = false, desc = 'Magic Defense Bonus' },
    ["Corsair's Roll"] = { rolls = { 10, 11, 11, 12, 20, 13, 15, 16, 8, 17, 24 }, bust = 6, effect = 2, percent = true, desc = 'Experience / Capacity Points' },
    ['Puppet Roll'] = { rolls = { 4, 5, 18, 7, 9, 10, 2, 11, 13, 15, 22 }, bust = -8, effect = 3, percent = false, desc = 'Pet: Magic Accuracy / Magic Attack Bonus' },
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

-- Rolls that are already stated in whole numbers rather than percent, for
-- the reference table's '%' suffix.
-- HorizonXI's eighteen Phantom Rolls, in reference-window order. The
-- thirteen retail-era rolls below are commented out because those
-- abilities do not exist on Horizon (kept here for if they are added).
M.ORDER = {
    "Corsair's Roll", "Ninja Roll", "Hunter's Roll", "Chaos Roll", "Magus's Roll",
    "Healer's Roll", "Drachen Roll", "Choral Roll", "Monk's Roll", "Beast Roll",
    "Samurai Roll", "Evoker's Roll", "Rogue's Roll", "Warlock's Roll", "Fighter's Roll",
    "Puppet Roll", "Gallant's Roll", "Wizard's Roll",
    -- Not on HorizonXI:
    -- "Dancer's Roll", "Scholar's Roll",
    -- "Naturalist's Roll", "Runeist's Roll", "Bolter's Roll", "Caster's Roll",
    -- "Courser's Roll", "Blitzer's Roll", "Tactician's Roll", "Allies' Roll",
    -- "Miser's Roll", "Avenger's Roll", "Companion's Roll",
}

return M
