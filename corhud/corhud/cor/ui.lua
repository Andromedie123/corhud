-- cor/ui.lua - the ImGui windows: Cards, Rolls, Reference, Wild Card, settings.

local imgui = require('imgui')
local D = require('cor.data')
local cards = require('cor.cards')
local rolls = require('cor.rolls')
local wildCard = require('cor.wild_card')
local merits = require('cor.merits')
local abilities = require('cor.abilities')
local cfg = require('cor.settings')

local M = {}

local COL_GOOD  = { 0.40, 0.85, 0.40, 1.0 }
local COL_WARN  = { 0.95, 0.80, 0.25, 1.0 }
local COL_BAD   = { 0.90, 0.35, 0.35, 1.0 }
local COL_DIM   = { 0.55, 0.55, 0.55, 1.0 }
local COL_LUCKY = { 0.35, 0.75, 1.00, 1.0 }

local OUTLINE_OFFSETS = {
    { -1, -1 }, { 0, -1 }, { 1, -1 },
    { -1,  0 },            { 1,  0 },
    { -1,  1 }, { 0,  1 }, { 1,  1 },
}
local PASS_COL = 0xFF000000 -- opaque: at 1px a translucent pass loses its edge

local textPushSize = imgui.GetFontSize() or 13
local textPassOff = 1
local function updateTextScale()
    local st = imgui.GetStyle()
    local own = cfg.settings.text_scale or 1.0
    local draw = own * (st.FontScaleMain or 1) * (st.FontScaleDpi or 1)
    textPushSize = (st.FontSizeBase or imgui.GetFontSize()) * own
    textPassOff = math.max(1, math.floor(draw + 0.5))
end

local function drawText(str, col)
    imgui.PushFont(nil, textPushSize)
    local w, h = imgui.CalcTextSize(str)
    local x, y = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    local style = cfg.settings.text_style
    if style == 'outline' then
        for _, off in ipairs(OUTLINE_OFFSETS) do
            dl:AddText({ x + off[1] * textPassOff, y + off[2] * textPassOff }, PASS_COL, str)
        end
    elseif style == 'shadow' then
        dl:AddText({ x + textPassOff, y + textPassOff }, PASS_COL, str)
    end
    local fill = col or { imgui.GetStyleColorVec4(ImGuiCol_Text) }
    dl:AddText({ x, y }, imgui.GetColorU32(fill), str)
    imgui.Dummy({ w, h })
    imgui.PopFont()
end

local function drawWindowHeader(title)
    if cfg.settings.compact_mode then return end
    drawText(title, { 0.8, 0.8, 1.0, 1.0 })
    imgui.Separator()
end

local function charName()
    return AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or 'Default'
end

local COR_JOB = 17
local function hasCorsairJob()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil then return false end
    return player:GetMainJob() == COR_JOB or player:GetSubJob() == COR_JOB
end

local function trackedWindow(id, posKey, flags, opacity, body)
    local s = cfg.settings
    if s.lock_positions then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove)
    end
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    local bg = { imgui.GetStyleColorVec4(ImGuiCol_WindowBg) }
    bg[4] = opacity or 0.85
    imgui.PushStyleColor(ImGuiCol_WindowBg, bg)

    local initKey = '_init_' .. posKey
    if not M[initKey] then
        imgui.SetNextWindowPos({ s[posKey][1], s[posKey][2] }, ImGuiCond_Always)
    else
        imgui.SetNextWindowPos({ s[posKey][1], s[posKey][2] }, ImGuiCond_FirstUseEver)
    end

    if imgui.Begin(id, true, flags) then
        updateTextScale()
        local pos = { imgui.GetWindowPos() }
        if M[initKey] then
            if pos[1] ~= s[posKey][1] or pos[2] ~= s[posKey][2] then
                s[posKey] = { pos[1], pos[2] }
                cfg.save()
            end
        else
            M[initKey] = true
        end
        body()
    end
    imgui.End()
    imgui.PopStyleColor()
    imgui.PopStyleVar()
end

-- ---------------------------------------------------------------- cards --
local MAX_NAME_LEN = 12 -- 'Thunder Card'

local function drawCardRow(name)
    local entry = cards.counts[name]
    local count = entry and entry.count or 0
    local tex = entry and cards.getTexture(entry.item) or nil
    local caseEntry = cards.caseCounts[name]
    local caseCount = caseEntry and caseEntry.count or 0
    local caseTex = caseEntry and cards.getTexture(caseEntry.item) or nil

    if tex then
        imgui.Image(tex, { 16, 16 })
    else
        imgui.Dummy({ 16, 16 })
    end
    imgui.SameLine()

    local col = (count == 0) and COL_BAD or (count <= 12 and COL_WARN or nil)
    if col then imgui.PushStyleColor(ImGuiCol_Text, col) end
    drawText(string.format('%3d', count))
    if col then imgui.PopStyleColor() end

    imgui.SameLine()
    drawText(name .. string.rep(' ', MAX_NAME_LEN - #name + 1))

    if cfg.settings.show_card_cases and (count > 0 or caseCount > 0) then
        local caseText = string.format('(%d)', caseCount)
            .. string.rep(' ', math.max(0, 2 - #tostring(caseCount)))
        local caseCol = (caseCount == 0) and COL_BAD or (caseCount <= 3 and COL_WARN or nil)
        if caseCol then imgui.PushStyleColor(ImGuiCol_Text, caseCol) end
        imgui.SameLine()
        drawText(caseText)
        if caseCol then imgui.PopStyleColor() end

        imgui.SameLine()
        if caseTex then
            imgui.Image(caseTex, { 16, 16 })
        else
            imgui.Dummy({ 16, 16 })
        end
    end
end

M.drawCardsWindow = function()
    if not cfg.settings.show_cards then return end
    if not hasCorsairJob() and not M.showConfig[1] then return end
    cards.refresh()

    local windowName = string.format('COR Cards###corhud_cards_%s', charName())
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
                           ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav)

    trackedWindow(windowName, 'cards_pos', flags, cfg.settings.cards_opacity, function()
        drawWindowHeader('Quick Draw Cards')
        for _, name in ipairs(D.CARD_NAMES) do
            local count = cards.counts[name] and cards.counts[name].count or 0
            local caseCount = cards.caseCounts[name] and cards.caseCounts[name].count or 0
            local hasCases = cfg.settings.show_card_cases and caseCount > 0
            if not cfg.settings.hide_zero_cards or count > 0 or hasCases then
                drawCardRow(name)
            end
        end
        imgui.Separator()
        if cfg.settings.show_cards_total then
            drawText(string.format('Total: %d', cards.total()))
        end
        if cfg.settings.show_card_cases then
            drawText(string.format('Cases: %d', cards.cases))
        end
    end)
end

-- ----------------------------------------------------------------- rolls --
local function drawActiveRoll(row)
    local name = row.name
    local entry = row.entry
    local owner = row.owner
    local members = row.merged

    local elapsed = os.time() - entry.at
    local remaining = math.max(0, (entry.duration or merits.getDuration()) - elapsed)
    local mm = math.floor(remaining / 60)
    local ss = math.floor(remaining % 60)

    local statusText, statusColor
    if entry.bust then
        statusText, statusColor = 'BUST!', COL_BAD
    elseif entry.number == entry.lucky or entry.number == 11 then
        statusText, statusColor = 'LUCKY!', COL_LUCKY
    elseif entry.number == entry.unlucky then
        statusText, statusColor = 'UNLUCKY!', COL_BAD
    else
        statusText = 'NORMAL'
    end

    if owner ~= nil then
        drawText(owner .. ' ·')
        imgui.SameLine()
    end
    drawText(name, statusColor or { 1, 1, 1, 1 })
    if members ~= nil then
        imgui.SameLine()
        drawText(string.format('[%d]', #members))
    end
    imgui.SameLine()
    if not entry.bust then
        drawText(string.format('== %d ==', entry.number))
        imgui.SameLine()
        drawText('(')
        imgui.SameLine(0, 1)
        drawText(string.format('L:%d', entry.lucky), COL_LUCKY)
        imgui.SameLine(0, 1)
        drawText('/')
        imgui.SameLine(0, 1)
        drawText(string.format('U:%d', entry.unlucky), COL_BAD)
        imgui.SameLine(0, 1)
        drawText(')')
        imgui.SameLine()
    end
    drawText(string.format('%02d:%02d', mm, ss))

    if not cfg.settings.compact_mode then
        if statusColor then
            drawText(statusText, statusColor)
        else
            drawText(statusText)
        end
        imgui.SameLine()
        if entry.desc and entry.desc ~= '' then
            drawText(entry.desc)
            imgui.SameLine()
        end
        local bonusText = entry.bonus or ''
        if not entry.bust and bonusText:match('^%d') then
            bonusText = '+' .. bonusText
        end
        drawText(bonusText, statusColor or { 1, 1, 1, 1 })
    end

    if not cfg.settings.compact_mode then imgui.Separator() end
end

local function drawAbilityTimer(name, valueX, remaining)
    drawText(name .. ':')
    imgui.SameLine(valueX)
    if remaining == nil then
        drawText('--')
    elseif remaining == 0 then
        drawText('Ready', COL_GOOD)
    else
        local mm = math.floor(remaining / 60)
        local ss = math.floor(remaining % 60)
        drawText(string.format('%02d:%02d', mm, ss))
    end
end

local function drawReferenceRow(name)
    local data = D.HORIZON_ROLLS[name] or D.ROLL_DATA[name]
    local baseData = D.ROLL_DATA[name]
    drawText(name)
    imgui.SameLine(160)
    drawText(tostring(data.lucky or baseData.lucky), COL_LUCKY)
    imgui.SameLine(200)
    drawText(tostring(data.unlucky or baseData.unlucky), COL_BAD)
    imgui.SameLine(240)
    if data.dual then
        drawText(tostring(data.rolls[11]))
    else
        local v = data.rolls[11]
        drawText(tostring(v) .. (data.percent and '%' or ''))
    end
    imgui.SameLine(320)
    drawText(data.desc)
end

M.drawRollsWindow = function()
    if not cfg.settings.show_rolls then return end
    if not hasCorsairJob() and not M.showConfig[1] then return end
    rolls.expire()

    local hasRolls = next(rolls.active) ~= nil
    local foldLeft = abilities.getRemaining('Fold')
    local snakeLeft = abilities.getRemaining('Snake Eye')
    local hasCooldown = (foldLeft ~= nil and foldLeft > 0) or (snakeLeft ~= nil and snakeLeft > 0)
    local hasMeritAbilities = abilities.isMerited('Fold') or abilities.isMerited('Snake Eye')
    if not hasRolls and not hasCooldown and not hasMeritAbilities and not M.showConfig[1] then return end

    local windowName = string.format('COR Rolls###corhud_rolls_%s', charName())
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
                           ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav)

    trackedWindow(windowName, 'rolls_pos', flags, cfg.settings.rolls_opacity, function()
        drawWindowHeader('Active Rolls')
        if cfg.settings.show_ability_timers then
            drawAbilityTimer('Fold', 55, abilities.getRemaining('Fold'))
            imgui.SameLine(130)
            drawAbilityTimer('Snake Eye', 210, abilities.getRemaining('Snake Eye'))
        end
        if hasRolls then
            for _, row in ipairs(rolls.rows()) do
                drawActiveRoll(row)
            end
        else
            drawText('(no active rolls)')
        end
    end)
end

M.drawReferenceWindow = function()
    if not cfg.settings.show_reference then return end
    if not hasCorsairJob() and not M.showConfig[1] then return end

    local windowName = string.format('COR Roll Reference###corhud_reference_%s', charName())
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
                           ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav)

    trackedWindow(windowName, 'reference_pos', flags, cfg.settings.rolls_opacity, function()
        drawWindowHeader('Roll Reference')
        drawText('Roll                Lucky Unlck  @11   Effect')
        for _, name in ipairs(D.ORDER) do
            drawReferenceRow(name)
        end
    end)
end

-- ----------------------------------------------------------- wild card --
M.drawWildCardWindow = function()
    if not cfg.settings.show_wild_card then return end
    if not hasCorsairJob() and not M.showConfig[1] then return end
    local stale = wildCard.latest == nil or os.time() - wildCard.latest.at >= wildCard.POPUP_DURATION
    if stale and not M.showConfig[1] then return end

    local windowName = string.format('COR Wild Card###corhud_wild_card_%s', charName())
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
                           ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav)

    trackedWindow(windowName, 'wild_card_pos', flags, cfg.settings.wild_card_opacity, function()
        drawWindowHeader('Wild Card')
        if wildCard.latest == nil then
            drawText('No result tracked yet this session.')
            return
        end

        local elapsed = os.time() - wildCard.latest.at
        local mm = math.floor(elapsed / 60)
        local ss = math.floor(elapsed % 60)
        drawText(string.format('Result: %d / 6', wildCard.latest.number))
        drawText(wildCard.latest.effect)
        local remaining = math.max(0, D.WILD_CARD_RECAST - elapsed)
        if remaining == 0 then
            drawText('Recast: Ready', COL_GOOD)
        else
            local hh = math.floor(remaining / 3600)
            local remMinutes = math.floor((remaining % 3600) / 60)
            local remSeconds = math.floor(remaining % 60)
            drawText(string.format('Recast: %02d:%02d:%02d', hh, remMinutes, remSeconds))
        end
    end)
end

-- -------------------------------------------------------------- settings --
M.showConfig = { false }

M.drawConfigWindow = function()
    if not M.showConfig[1] then return end
    local windowName = string.format('CorHUD Settings###corhud_config_%s', charName())

    if not M._configInit then
        imgui.SetNextWindowPos({ cfg.settings.config_pos[1], cfg.settings.config_pos[2] }, ImGuiCond_Always)
    else
        imgui.SetNextWindowPos({ cfg.settings.config_pos[1], cfg.settings.config_pos[2] }, ImGuiCond_FirstUseEver)
    end

    if imgui.Begin(windowName, M.showConfig,
        bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav,
            cfg.settings.lock_positions and ImGuiWindowFlags_NoMove or 0)) then

        local pos = { imgui.GetWindowPos() }
        if M._configInit then
            if pos[1] ~= cfg.settings.config_pos[1] or pos[2] ~= cfg.settings.config_pos[2] then
                cfg.settings.config_pos = { pos[1], pos[2] }
                cfg.save()
            end
        else
            M._configInit = true
        end

        if not hasCorsairJob() then
            imgui.TextDisabled('COR windows hide on other jobs; they appear while this window is open so they can be moved.')
        end

        local showCards = { cfg.settings.show_cards }
        if imgui.Checkbox('Show Cards window', showCards) then
            cfg.settings.show_cards = showCards[1]
            cfg.save()
        end

        local showRolls = { cfg.settings.show_rolls }
        if imgui.Checkbox('Show Rolls window', showRolls) then
            cfg.settings.show_rolls = showRolls[1]
            cfg.save()
        end

        local trackModes = { 'Self Only', 'Party', 'Alliance' }
        local trackIdx = { 0 }
        for i, name in ipairs(trackModes) do
            if name == (cfg.settings.roll_track_mode or 'Self Only') then trackIdx[1] = i - 1 end
        end
        if imgui.Combo('Track rolls', trackIdx, 'Self Only\0Party\0Alliance\0\0') then
            cfg.settings.roll_track_mode = trackModes[trackIdx[1] + 1] or 'Self Only'
            cfg.save()
        end
        imgui.TextDisabled('  which Corsairs\' rolls to follow')

        local showWildCard = { cfg.settings.show_wild_card }
        if imgui.Checkbox('Show Wild Card window', showWildCard) then
            cfg.settings.show_wild_card = showWildCard[1]
            cfg.save()
        end

        local hideZeroCards = { cfg.settings.hide_zero_cards }
        if imgui.Checkbox('Hide zero-quantity cards', hideZeroCards) then
            cfg.settings.hide_zero_cards = hideZeroCards[1]
            cfg.save()
        end

        local showCardsTotal = { cfg.settings.show_cards_total }
        if imgui.Checkbox('Show card total', showCardsTotal) then
            cfg.settings.show_cards_total = showCardsTotal[1]
            cfg.save()
        end

        local showCardCases = { cfg.settings.show_card_cases }
        if imgui.Checkbox('Show card cases', showCardCases) then
            cfg.settings.show_card_cases = showCardCases[1]
            cfg.save()
        end

        local showReference = { cfg.settings.show_reference }
        if imgui.Checkbox('Show Reference window', showReference) then
            cfg.settings.show_reference = showReference[1]
            cfg.save()
        end

        local showAbilityTimers = { cfg.settings.show_ability_timers }
        if imgui.Checkbox('Show Fold/Snake Eye timers', showAbilityTimers) then
            cfg.settings.show_ability_timers = showAbilityTimers[1]
            cfg.save()
        end

        local compactMode = { cfg.settings.compact_mode }
        if imgui.Checkbox('Compact mode', compactMode) then
            cfg.settings.compact_mode = compactMode[1]
            cfg.save()
        end
        imgui.TextDisabled('  no window headers; rolls lose their status/effect line')

        local lockPositions = { cfg.settings.lock_positions }
        if imgui.Checkbox('Lock window positions', lockPositions) then
            cfg.settings.lock_positions = lockPositions[1]
            cfg.save()
        end

        imgui.Separator()

        local cOpac = { cfg.settings.cards_opacity }
        if imgui.SliderFloat('Cards opacity', cOpac, 0.0, 1.0, '%.2f') then
            cfg.settings.cards_opacity = cOpac[1]
            cfg.save()
        end

        local rOpac = { cfg.settings.rolls_opacity }
        if imgui.SliderFloat('Rolls opacity', rOpac, 0.0, 1.0, '%.2f') then
            cfg.settings.rolls_opacity = rOpac[1]
            cfg.save()
        end

        local wcOpac = { cfg.settings.wild_card_opacity }
        if imgui.SliderFloat('Wild Card opacity', wcOpac, 0.0, 1.0, '%.2f') then
            cfg.settings.wild_card_opacity = wcOpac[1]
            cfg.save()
        end

        local styleNames = { 'off', 'outline', 'shadow' }
        local styleIdx = { 0 }
        for i, name in ipairs(styleNames) do
            if name == cfg.settings.text_style then styleIdx[1] = i - 1 end
        end
        if imgui.Combo('Text style', styleIdx, 'None\0Outline\0Shadow\0\0') then
            cfg.settings.text_style = styleNames[styleIdx[1] + 1] or 'outline'
            cfg.save()
        end
        imgui.TextDisabled('  outline/shadow keep text readable at 0.00 opacity')

        local textScale = { cfg.settings.text_scale }
        if imgui.SliderFloat('Text scale', textScale, 0.75, 1.50, '%.2f') then
            cfg.settings.text_scale = textScale[1]
            cfg.save()
        end

        imgui.Separator()
        imgui.TextDisabled('/corhud or /ch - toggle this window')
        imgui.TextDisabled('/corhud cards     - toggle Cards window')
        imgui.TextDisabled('/corhud rolls     - toggle Rolls window')
        imgui.TextDisabled('/corhud reference - toggle Reference window')
        imgui.TextDisabled('/corhud wildcard  - toggle Wild Card window')
        imgui.TextDisabled('/corhud compact   - toggle Compact mode')
        imgui.TextDisabled('/corhud merits     - debug: dump the merit list read')
        imgui.TextDisabled('/corhud rollpackets - debug: dump recent roll packets')
    end
    imgui.End()
end

return M
