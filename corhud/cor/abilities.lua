-- cor/abilities.lua - recast countdowns for the Corsair merit job
-- abilities Fold and Snake Eye.
--
-- The countdown reads the client's own ability recast timers through
-- Ashita's recast memory manager - the same source the tTimers addon
-- uses. The client computes those timers with the player's merit points
-- baked in, so a merited Fold or Snake Eye counts down from the real,
-- reduced recast with no packet parsing or merit math in this addon.
-- (The action packet's recast field is not usable here: on Horizon it
-- carries the unreduced base value.)
local D = require('cor.data')
local cfg = require('cor.settings')

local M = {}

M.timers = T{} -- name -> remaining seconds (refreshed every frame)
M.seen = T{}   -- name -> true, once the client has shown the ability

-- Whether the player has spent merits in Fold / Snake Eye, so the Rolls
-- window can stay visible while either exists (their recast readouts
-- live in that window). Set from the character's own action packets -
-- using the ability is proof it is merited - and from the merit menu
-- packet parsed in cor/merits.lua. Persisted per character like the
-- Winning Streak value.
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

-- The action packet ability ids for the two merit abilities; the same
-- category-6 job ability result the rolls module reads (Fold's bust
-- removal handling lives there).
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

-- The client's 32 ability recast slots are keyed by each ability's own
-- recast timer id, which does not have to match the ability id the
-- action packets use - Fold and Snake Eye report their own timer ids.
-- Resolve the real ids once by scanning the resource manager for the two
-- abilities (the same search tTimers falls back to), keeping the packet
-- ids as the starting guess for clients where the scan finds nothing.
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

-- Called every frame from corhud.lua; walks the 32 ability recast slots
-- the client keeps and copies the ones this addon tracks. The timer
-- values come back in sixtieths of a second.
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
    -- An expired recast can drop out of the slot list entirely; once an
    -- ability has been seen, a missing slot means its recast is up.
    for name in pairs(M.seen) do
        if not found[name] then M.timers[name] = 0 end
    end
end

-- Seconds left on the ability's recast, or nil if the client has not
-- shown it yet this session.
M.getRemaining = function(name)
    if not M.seen[name] then return nil end
    return math.max(0, M.timers[name] or 0)
end

return M
