-- cor/rolls.lua - watches the 0x028 action packet for the local player's
-- own Phantom Rolls landing, works out the bonus that roll actually gave
-- (including the selected main-job Phantom Roll+ table), and keeps a small table of
-- what is currently active so the UI has something to draw every frame.
--
-- This only tracks rolls YOU cast (the packet's actor must be the local
-- player), the same restriction the RollTracker addon this was adapted
-- from used - a Corsair cares about the rolls they are the source of.
local D = require('cor.data')
local merits = require('cor.merits')

local M = {}
-- name -> { number, bonus, at (os.time()), lucky, unlucky, bust }
M.active = T{}
-- The game caps any one target at two rolls, but a Corsair rotating
-- parties can keep several of their own rolls alive on different groups
-- at once. How many depends on the roll duration against the 1:00
-- recast - 5:00 base holds five, and each Winning Streak merit's +20s
-- holds one more - so the cap is derived from the detected duration:
-- 5 at the base, up to 7 at 5/5 merits. The tracker evicts the oldest
-- before refusing a roll the player can genuinely hold.
local function maxActiveRolls()
    -- Rolls land 60s apart and the oldest expires after the full
    -- duration, so the number alive at once is floor((duration-1)/60)+1.
    return math.floor((merits.getDuration() - 1) / 60) + 1
end

local function partyMgr() return AshitaCore:GetMemoryManager():GetParty() end

-- slot+1 -> { container, index } from incoming 0x050 "equip update"
-- packets. The server sends one whenever gear changes (including the
-- burst after zoning) and they say where each equipped item actually
-- lives. The packets are the only reliable source on Horizon -
-- IInventory:GetEquippedItem's memory offset is wrong on its client
-- build and surfaces bag items as equipped ones.
local equipSlots = T{}

-- Reads one equipment slot and resolves it to its client-side resource:
-- the raw item id plus the resource name. nil when the slot is empty,
-- or when no 0x050 has arrived for it yet (only right after loading the
-- addon mid-zone; the next zone or equip change fills it in).
--
-- Slots use the 0x050 /equip order, NOT the equipment-window order:
-- 0=main, 1=sub, 2=ranged, 3=ammo, 4=head, 5=body, 6=hands, 7=legs,
-- 8=feet, 9=neck, 10=waist, 11=ear1, 12=ear2, 13=ring1, 14=ring2,
-- 15=back (proven by packet capture: the culottes arrived as slot 7
-- and the fang as slot 12).
local function equippedItem(slot)
    local inventory = AshitaCore:GetMemoryManager():GetInventory()
    if inventory == nil then return nil end

    -- nil = no 0x050 yet; index 0 = the server says unequipped.
    local loc = equipSlots[slot + 1]
    if loc == nil or loc.index == 0 then return nil end

    local containerItem = inventory:GetContainerItem(loc.container, loc.index)
    if containerItem == nil or containerItem.Id == 0 then return nil end
    local item = AshitaCore:GetResourceManager():GetItemById(containerItem.Id)
    if item == nil or item.Name == nil then return nil end
    return { id = containerItem.Id, name = item.Name[1] }
end

local function hasPrefix(name, prefix)
    return name:sub(1, #prefix) == prefix
end

-- True when the equipped item belongs to a Phantom Roll+ family: either
-- its resource name carries the Horizon name, or its id is one of the
-- confirmed Horizon ids (see D.HORIZON_ROLL_PLUS).
local function matchesRollPlusFamily(item, family)
    return hasPrefix(item.name, family.name)
        or (family.ids ~= nil and family.ids[item.id] ~= nil)
end

-- Total Phantom Roll+ tier from equipped gear. The two Horizon pieces
-- (ear and legs) stack with each other - +2 with both worn, the current
-- Horizon cap. Slot numbers are the 0x050 /equip order (11/12 = the two
-- ears, 7 = legs). Luzaf's Fang is right-ear only, but both ear slots
-- are checked so the item is found whichever way the client numbers
-- them.
local function horizonGearRank()
    local rank = 0
    for _, slot in ipairs({ 11, 12 }) do
        local item = equippedItem(slot)
        if item ~= nil and matchesRollPlusFamily(item, D.HORIZON_ROLL_PLUS.ear) then
            rank = rank + 1
            break
        end
    end
    local legs = equippedItem(7)
    if legs ~= nil and matchesRollPlusFamily(legs, D.HORIZON_ROLL_PLUS.legs) then
        rank = rank + 1
    end
    return rank
end

-- Returns the bonus text for a landed roll: a plain number/percent for a
-- normal roll, "regain / regen" pair for Companion's Roll, or 'Unknown'.
local function bonusFor(rollName, number, data)
    local horizonData = D.HORIZON_ROLLS[rollName]
    local plusData = D.ROLL_PLUS_DATA[rollName]
    local plus = horizonGearRank()
    local activeData = horizonData or data
    -- Use the highest tier table the wiki has actually verified at or
    -- below the equipped rank. Some rolls are missing +2 (and a few +1)
    -- cells - the wiki marks them "Verification Needed" - so a missing
    -- tier falls back to the best confirmed table instead of guessing.
    local plusTable = nil
    local usedTier = 0
    if plusData ~= nil then
        for tier = plus, 1, -1 do
            if plusData['plus_' .. tier] ~= nil then
                plusTable = plusData['plus_' .. tier]
                usedTier = tier
                break
            end
        end
    end
    local tableData = plusTable or (horizonData and horizonData.rolls)
    local bustData = (usedTier > 0 and plusData['bust_' .. usedTier])
        or (horizonData and horizonData.bust)

    if activeData.unknown then return 'Unknown', false end

    -- The result table contains only rolls 1-11. Any larger packet value is
    -- the game's bust marker and must never be used as a table index.
    if number < 1 or number > 11 then
        local bust = bustData or activeData.bust
        local bustText = tostring(bust)
        if activeData.percent and tonumber(bust) ~= nil then
            bustText = bustText .. '%'
        end
        return bustText, true -- (text, isBust)
    end

    if data.dual then
        -- "20,4" style: split into the two halves for Companion's Roll.
        local base = data.rolls[number]
        local b1, b2 = base:match('([^,]+),([^,]+)')
        local n1, n2 = tonumber(b1), tonumber(b2)
        return string.format('%s Regain / %s Regen', n1 or b1, n2 or b2), false
    end

    local base = tableData and tableData[number] or activeData.rolls[number]
    if base == 'Unknown' then return 'Unknown', false end

    local bonus = base
    if horizonData and plus > 0 and plusTable == nil
        and horizonData.effect ~= nil and tonumber(base) ~= nil then
        bonus = bonus + horizonData.effect * plus
    end

    if activeData.percent then
        return string.format('%.1f%%', bonus), false
    end
    return tostring(bonus), false
end

-- Removes anything that ended (loses-effect message already matched it),
-- or that has simply been sitting unconfirmed past the detected roll
-- duration plus a short grace - a safety net for a missed "loses the
-- effect" line (e.g. it scrolled past while the roller was zoning).
-- getDuration falls back to the 5:00 base until detection happens, so
-- the net always sits just past a roll's real end.
M.expire = function()
    local now = os.time()
    local timeout = merits.getDuration() + 10
    local drop = {}
    for name, entry in pairs(M.active) do
        if now - entry.at >= timeout then
            drop[#drop + 1] = name
        end
    end
    for _, name in ipairs(drop) do M.active[name] = nil end
end

-- Fold removes a bust before normal rolls, choosing the bust with the
-- longest remaining duration (the oldest tracked bust).
M.removeBust = function()
    local oldestName = nil
    local oldestAt = nil
    for name, entry in pairs(M.active) do
        if entry.bust and (oldestAt == nil or entry.at < oldestAt) then
            oldestName = name
            oldestAt = entry.at
        end
    end
    if oldestName ~= nil then
        M.active[oldestName] = nil
    end
end

M.onPacketIn = function(e)
    -- 0x0B / 0x0A bracket a zone transition. All effects - rolls included -
    -- drop on zoning, so clear the tracked rolls along with the stale action
    -- stream instead of letting them linger until the timeout.
    if e.id == 0xB then
        M.zoning = true
        M.active = T{}
        equipSlots = T{} -- the new zone re-sends the 0x050 burst
        return
    end
    if e.id == 0xA then M.zoning = false; return end
    if M.zoning then return end

    -- 0x050 "equip update": record where each equipped item lives, per
    -- the server. Same offsets the timers addon parses (slot at 0x05,
    -- container at 0x06, index at 0x04).
    if e.id == 0x50 then
        if e.data ~= nil and #e.data >= 7 then
            local slot      = struct.unpack('B', e.data, 0x05 + 1)
            local container = struct.unpack('B', e.data, 0x06 + 1)
            local index     = struct.unpack('B', e.data, 0x04 + 1)
            equipSlots[slot + 1] = { container = container, index = index }
        end
        return
    end
    if e.id ~= 0x28 then return end

    M.expire()

    local actor = struct.unpack('I', e.data, 6)
    local party = partyMgr()
    if actor ~= party:GetMemberServerId(0) then return end -- only our own rolls

    local category = ashita.bits.unpack_be(e.data_raw, 82, 4)
    if category ~= 6 then return end -- 6 = Phantom Roll result

    local abilityId = ashita.bits.unpack_be(e.data_raw, 86, 10)
    if abilityId == D.FOLD_ID then
        M.removeBust()
        return
    end
    local number     = ashita.bits.unpack_be(e.data_raw, 213, 17)
    local rollName = D.ROLL_IDS[abilityId]
    if rollName == nil or number == nil or number == 0 then return end

    local data = D.ROLL_DATA[rollName]
    if data == nil then return end

    if M.active[rollName] == nil then
        local maxRolls = maxActiveRolls()
        local count = 0
        local oldestName = nil
        local oldestAt = nil
        for name, entry in pairs(M.active) do
            count = count + 1
            if not entry.bust and (oldestAt == nil or entry.at < oldestAt) then
                oldestName = name
                oldestAt = entry.at
            end
        end
        if count >= maxRolls and oldestName ~= nil then
            M.active[oldestName] = nil
        elseif count >= maxRolls then
            return
        end
    end

    local bonusText, isBust = bonusFor(rollName, number, data)

    M.active[rollName] = {
        number  = number,
        bonus   = bonusText,
        bust    = isBust,
        lucky   = data.lucky,
        unlucky = data.unlucky,
        desc    = data.desc,
        at      = os.time(),
    }
end

-- Clears the tracked roll the moment the game tells us it actually ended,
-- rather than waiting on the timeout. FFXI's own line reads e.g.
-- "You lose the effect of Chaos Roll." - captured whole so it matches a
-- D.ROLL_DATA key directly.
M.onTextIn = function(e)
    if e.message == nil then return end
    if e.message:match('[Ff]old') then
        M.removeBust()
    end
    local rollName = e.message:match('[Ll]oses? the effect of (.-[Rr]oll)%.')
    if rollName ~= nil and M.active[rollName] ~= nil then
        M.active[rollName] = nil
    end
    -- A bust's own expiry message names no roll, so drop the oldest
    -- tracked bust on it (Fold does the same).
    if e.message:match('[Ll]oses? the effect of [Bb]ust%.') then
        M.removeBust()
    end
end

return M
