-- cor/abilities.lua - Fold / Snake Eye recast timers and their merit detection.

local D = require('cor.data')
local cfg = require('cor.settings')

local M = {}

M.timers = T{} -- name -> remaining seconds (refreshed every frame)
M.seen = T{}   -- name -> true, once the client has shown the ability

M.merited = T{}
M.merited['Fold'] = cfg.settings.fold_merits or 0
M.merited['Snake Eye'] = cfg.settings.snake_eye_merits or 0

M.markMerited = function(name, count)
    count = count or 1
    if count < 1 then count = 1 end
    if (M.merited[name] or 0) < count then
        M.merited[name] = count
        if name == 'Fold' then cfg.settings.fold_merits = count end
        if name == 'Snake Eye' then cfg.settings.snake_eye_merits = count end
        cfg.save()
    end
end

M.isMerited = function(name)
    return (M.merited[name] or 0) >= 1
end

local ABILITY_NAMES = {
    [D.FOLD_ID] = 'Fold',
    [D.SNAKE_EYE_ID] = 'Snake Eye',
}

M.onPacketIn = function(e)
    if e.id ~= 0x28 then return end
    local actor = struct.unpack('I', e.data, 6)
    if actor ~= AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) then return end
    if ashita.bits.unpack_be(e.data_raw, 82, 4) ~= 6 then return end
    local name = ABILITY_NAMES[ashita.bits.unpack_be(e.data_raw, 86, 10)]
    if name ~= nil then M.markMerited(name) end
end

local NAMES_BY_TIMER_ID = (function()
    local map = {}
    for id, name in pairs(D.ABILITY_RECAST_NAMES) do map[id] = name end

    local wanted = {}
    for _, name in pairs(D.ABILITY_RECAST_NAMES) do wanted[name:lower()] = name end

    local resMgr = AshitaCore:GetResourceManager()
    if resMgr == nil then return map end

    for x = 0, 0x6FF do
        local res = resMgr:GetAbilityById(x)
        if res ~= nil and res.Name ~= nil and res.RecastTimerId ~= nil and res.RecastTimerId > 0 then
            local resName = res.Name[1]
            if resName ~= nil then
                local display = wanted[resName:lower():match('^%s*(.-)%s*$')]
                if display ~= nil then
                    map[res.RecastTimerId] = display
                end
            end
        end
    end
    return map
end)()

M.onFrame = function()
    local recast = AshitaCore:GetMemoryManager():GetRecast()
    if recast == nil then return end

    local found = T{}
    for slot = 0, 31 do
        local name = NAMES_BY_TIMER_ID[recast:GetAbilityTimerId(slot)]
        if name ~= nil then
            M.timers[name] = recast:GetAbilityTimer(slot) / 60
            M.seen[name] = true
            found[name] = true
        end
    end
    for name in pairs(M.seen) do
        if not found[name] then M.timers[name] = 0 end
    end
end

M.getRemaining = function(name)
    if not M.seen[name] then return nil end
    return math.max(0, M.timers[name] or 0)
end

return M
