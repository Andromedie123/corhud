addon.name    = 'corhud'
addon.author  = 'Andromedie, Claude'
addon.version = '1.2'
addon.desc    = 'Corsair HUD: Quick Draw cards, Phantom Roll tracking, and Winning Streak merit auto-detect.'
addon.link    = ''

require('common')
local imgui = require('imgui')

local cards = require('cor.cards')
local rolls = require('cor.rolls')
local wildCard = require('cor.wild_card')
local merits = require('cor.merits')
local abilities = require('cor.abilities')
local ui    = require('cor.ui')
local cfg   = require('cor.settings')

-- One coloured tag for the load message; not worth pulling in the `chat`
-- module for a single line.
local function chatHeader(name)
    return string.char(0x1E, 0x07) .. '[' .. name .. ']' .. string.char(0x1E, 0x01) .. ' '
end

ashita.events.register('d3d_present', 'corhud_present', function()
    merits.onFrame()
    abilities.onFrame()

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil or player:GetMainJob() <= 0 or player:GetIsZoning() ~= 0 then
        return
    end

    ui.drawConfigWindow()
    ui.drawCardsWindow()
    ui.drawRollsWindow()
    ui.drawReferenceWindow()
    ui.drawWildCardWindow()
end)

ashita.events.register('packet_in', 'corhud_packet_in', function(e)
    rolls.onPacketIn(e)
    merits.onPacketIn(e)
    wildCard.onPacketIn(e)
    abilities.onPacketIn(e)
end)

ashita.events.register('text_in', 'corhud_text_in', function(e)
    rolls.onTextIn(e)
    -- Never swallow chat; this addon only listens.
    return false
end)

ashita.events.register('command', 'corhud_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end

    if args[1] ~= '/corhud' and args[1] ~= '/ch' then return end
    e.blocked = true

    if args[2] == 'cards' then
        cfg.settings.show_cards = not cfg.settings.show_cards
        cfg.save()
    elseif args[2] == 'rolls' then
        cfg.settings.show_rolls = not cfg.settings.show_rolls
        cfg.save()
    elseif args[2] == 'reference' then
        cfg.settings.show_reference = not cfg.settings.show_reference
        cfg.save()
    elseif args[2] == 'wildcard' then
        cfg.settings.show_wild_card = not cfg.settings.show_wild_card
        cfg.save()
    elseif args[2] == 'clear' then
        rolls.active = T{}
        wildCard.clear()
        merits.clear()
    elseif args[2] == 'merits' then
        merits.debug()
    elseif args[2] == 'rollpackets' then
        rolls.debug()
    else
        ui.showConfig[1] = not ui.showConfig[1]
    end
end)

ashita.events.register('load', 'corhud_load', function()
    print(chatHeader('corhud') .. 'loaded. /corhud (or /ch) for settings.')
end)
