-- cor/settings.lua - the persisted, per-character settings and their
-- defaults. Loaded once by corhud.lua via Ashita's `settings` library, and
-- shared (by reference) with every other module that needs to read or
-- flip one of these.
local settings = require('settings')

local default_settings = T{
    -- window visibility
    show_cards      = true,
    show_rolls      = true,
    show_wild_card  = true,
    lock_positions  = false,  -- NoMove on every window so the layout can't be dragged
    -- Cards window
    cards_pos       = { 160, 440 },
    cards_opacity   = 0.85,
    hide_zero_cards = false,  -- hide cards with zero quantity from the list
    show_cards_total = true,  -- the "Total: N" footer line
    show_card_cases  = true,  -- the "Cases: N" footer line
    -- Rolls window
    rolls_pos       = { 160, 320 },
    rolls_opacity   = 0.85,
    -- Roll reference window (its own window so it can stay up with no rolls)
    reference_pos   = { 160, 180 },
    show_reference  = false,   -- the full roll -> bonus table
    -- Wild Card window
    wild_card_pos       = { 160, 220 },
    wild_card_opacity   = 0.85,
    -- Fold / Snake Eye recast readouts at the top of the Rolls window
    show_ability_timers = true,
    -- Whether Fold / Snake Eye are merited (>= 1 point); detected from
    -- the character's own ability use and the merit menu packet, and
    -- what keeps the Rolls window visible with no rolls active.
    fold_merits      = 0,
    snake_eye_merits = 0,
    text_style      = 'outline', -- HUD text effect: 'off' | 'outline' | 'shadow'
    text_scale      = 1.0,      -- HUD text size multiplier (config window excluded)
    -- shared config window
    config_pos      = { 100, 175 },
}

local M = {}
M.settings = settings.load(default_settings)

-- settings.load merges the defaults over the saved file. Fold older
-- saved keys into the current ones, drop the stale keys, and save the
-- result back so later character switches need no migration.
local migrated = false
if M.settings.text_outline ~= nil or M.settings.text_shadow ~= nil then
    -- Pre-1.10 per-effect booleans -> single style: outline wins when
    -- both were on; a 1.7-era `text_shadow` keeps its meaning.
    if M.settings.text_outline == true then
        M.settings.text_style = 'outline'
    elseif M.settings.text_shadow == true then
        M.settings.text_style = 'shadow'
    else
        M.settings.text_style = 'off'
    end
    M.settings.text_outline = nil
    M.settings.text_shadow = nil
    migrated = true
end
if M.settings.roll_timeout ~= nil then
    -- 1.13: the auto-clear timeout is gone; expiry always follows the
    -- auto-detected roll duration now.
    M.settings.roll_timeout = nil
    migrated = true
end
if migrated then settings.save() end

settings.register('settings', 'corhud_settings_update', function(s)
    if s then
        M.settings = s
    end
end)

M.save = function() settings.save() end

return M
