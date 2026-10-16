-- cor/settings.lua - persisted per-character settings and their defaults.

local settings = require('settings')

local default_settings = T{
    show_cards      = true,
    show_rolls      = true,
    show_wild_card  = true,
    lock_positions  = false,  -- NoMove on every window so the layout can't be dragged
    cards_pos       = { 160, 440 },
    cards_opacity   = 0.85,
    hide_zero_cards = false,  -- hide cards with zero quantity from the list
    show_cards_total = true,  -- the "Total: N" footer line
    show_card_cases  = true,  -- the "Cases: N" footer line
    rolls_pos       = { 160, 320 },
    rolls_opacity   = 0.85,
    roll_track_mode = 'Self Only',
    reference_pos   = { 160, 180 },
    show_reference  = false,   -- the full roll -> bonus table
    wild_card_pos       = { 160, 220 },
    wild_card_opacity   = 0.85,
    show_ability_timers = true,
    fold_merits      = 0,
    snake_eye_merits = 0,
    compact_mode     = false,
    text_style      = 'outline', -- HUD text effect: 'off' | 'outline' | 'shadow'
    text_scale      = 1.0,      -- HUD text size multiplier (config window excluded)
    config_pos      = { 100, 175 },
}

local M = {}
M.settings = settings.load(default_settings)

local migrated = false
if M.settings.text_outline ~= nil or M.settings.text_shadow ~= nil then
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
