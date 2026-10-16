-- cor/merits.lua - Winning Streak merit detection and the roll duration it sets.

local D = require('cor.data')
local cfg = require('cor.settings')
local abilities = require('cor.abilities')

local M = {}

local BASE_DURATION = 300   -- seconds; Phantom Roll base duration on Horizon
local MERIT_SECONDS = 20    -- seconds added per Winning Streak merit
local MAX_MERITS = 5        -- group 2 merit cap
local PAIR_WINDOW = 3       -- seconds; an own roll packet must be this close
local TOLERANCE = 3         -- seconds of jitter on the wall-clock channel
local ICON_EMPTY = 0xFF00   -- sentinel the server fills unused slots with
local ICON_ROLL_FIRST, ICON_ROLL_LAST = 310, 339
local ICON_RUNEIST = 600    -- Runeist's Roll sits outside the main range

M.detected = cfg.settings.winning_streak -- 0..5, nil until first detection
M.zoning = false

local function chatHeader(name)
    return string.char(0x1E, 0x07) .. '[' .. name .. ']' .. string.char(0x1E, 0x01) .. ' '
end

local function partyMgr() return AshitaCore:GetMemoryManager():GetParty() end

local function isRollIcon(icon)
    return (icon >= ICON_ROLL_FIRST and icon <= ICON_ROLL_LAST) or icon == ICON_RUNEIST
end

local function meritsFromElapsed(elapsed)
    local k = math.floor((elapsed - BASE_DURATION) / MERIT_SECONDS + 0.5)
    if k < 0 or k > MAX_MERITS then return nil end
    if math.abs(elapsed - (BASE_DURATION + MERIT_SECONDS * k)) > TOLERANCE then return nil end
    return k
end

local function meritsFromDuration(seconds)
    if seconds == nil then return nil end
    local diff = seconds - BASE_DURATION
    if diff < 0 or diff % MERIT_SECONDS ~= 0 then return nil end
    local k = diff / MERIT_SECONDS
    if k > MAX_MERITS then return nil end
    return k
end

local timeLib = nil
do
    local ok, res = pcall(require, 'ffxi.time')
    if ok and type(res) == 'table' and res.get_calculated_status_time ~= nil then
        timeLib = res
    end
end

local MERIT_ID_WINNING_STREAK = 0xC04
local MERIT_LIST_OFFSET = 0x28A44

local function isPlausibleMeritList(list)
    local n = 0
    for id, points in pairs(list) do
        if id < 0x0400 or id > 0x1400 or points > 15 then return false end
        n = n + 1
    end
    return n >= 1
end

local function readMeritListAt(offset)
    if partyMgr():GetMemberTargetIndex(0) == 0 then return nil, 'not logged in' end
    local ptrMgr = AshitaCore:GetPointerManager()
    if ptrMgr == nil then return nil, 'no pointer manager' end
    local pInventory = ptrMgr:Get('inventory')
    if pInventory <= 0 then return nil, string.format('inventory pointer %08X', pInventory) end
    local base = ashita.memory.read_uint32(pInventory)
    if base == 0 then return nil, 'first deref is 0' end
    base = ashita.memory.read_uint32(base)
    if base == 0 then return nil, 'second deref is 0' end
    local header = base + offset
    local count = ashita.memory.read_uint16(header + 2)
    local entry = ashita.memory.read_uint32(header + 4)
    if count == 0 or count > 64 then
        return nil, string.format('count %d at %05X', count, offset)
    end
    if entry == 0 then return nil, string.format('entry pointer 0 at %05X', offset) end
    local list = T{}
    for _ = 1, count do
        list[ashita.memory.read_uint16(entry)] = ashita.memory.read_uint8(entry + 3)
        entry = entry + 4
    end
    if not isPlausibleMeritList(list) then
        return nil, string.format('entries at %05X do not look like merits', offset)
    end
    return list
end

local function readWinningStreakMerits()
    local list = readMeritListAt(MERIT_LIST_OFFSET)
    if list == nil then return nil end
    return list[MERIT_ID_WINNING_STREAK] or 0
end

local icons = T{}      -- icon id -> slot, the last 0x063 snapshot
local pending = T{}    -- icon id -> { at }, own rolls waiting to expire
local unpaired = T{}   -- icon id -> { at }, roll icons with no own roll seen yet
local removals = T{}   -- icon id -> { at, addedAt }, awaiting the deferred check
local lastRollAt = nil -- when our own roll last landed (0x028)

local meritListRead = false      -- once a valid read happened (or gave up)
local meritListAttempts = 0
local MERIT_LIST_ATTEMPT_LIMIT = 600 -- ~10s of frames for pointers to appear
local lastMeritPacket = nil      -- raw 0x08C, for the debug dump
local lastMeritMenu = nil        -- parsed 0x08C entries (id -> points)

local function setDetected(k, source)
    if k == M.detected then return end
    M.detected = k
    cfg.settings.winning_streak = k
    cfg.save()
    print(chatHeader('corhud') .. string.format('Winning Streak detected: %d/5', k)
        .. (source and (' (' .. source .. ')') or ''))
end

M.onPacketIn = function(e)
    if e.id == 0xB then
        M.zoning = true
        icons = T{}
        pending = T{}
        unpaired = T{}
        removals = T{}
        lastRollAt = nil
        return
    end
    if e.id == 0xA then M.zoning = false; return end
    if M.zoning then return end

    if e.id == 0x8C then
        if e.data ~= nil and #e.data >= 5 then
            lastMeritPacket = e.data
            local count = struct.unpack('B', e.data, 0x04 + 1)
            if count <= 64 and #e.data >= 0x08 + 4 * count then
                local k = nil
                lastMeritMenu = T{}
                for i = 1, count do
                    local id = struct.unpack('H', e.data, 0x04 + 4 * i + 1)
                    local pts = struct.unpack('B', e.data, 0x04 + 4 * i + 4)
                    lastMeritMenu[id] = pts
                    if id == MERIT_ID_WINNING_STREAK then k = pts end
                end
                if k ~= nil and k <= MAX_MERITS then
                    meritListRead = true -- memory channel no longer needed
                    setDetected(k, 'merit menu')
                end
                for id, name in pairs(D.MERIT_ABILITY_IDS) do
                    local pts = lastMeritMenu[id]
                    if pts ~= nil and pts >= 1 then abilities.markMerited(name, pts) end
                end
            end
        end
        return
    end

    if e.id == 0x28 then
        local actor = struct.unpack('I', e.data, 6)
        local party = partyMgr()
        if actor ~= party:GetMemberServerId(0) then return end
        local category = ashita.bits.unpack_be(e.data_raw, 82, 4)
        if category ~= 6 then return end
        local abilityId = ashita.bits.unpack_be(e.data_raw, 86, 10)
        if D.ROLL_IDS[abilityId] == nil then return end
        lastRollAt = os.time()

        for icon, entry in pairs(unpaired) do
            if lastRollAt - entry.at <= PAIR_WINDOW then
                pending[icon] = entry
                unpaired[icon] = nil
            elseif lastRollAt - entry.at > PAIR_WINDOW * 3 then
                unpaired[icon] = nil -- someone else's roll; drop it
            end
        end
        return
    end

    if e.id ~= 0x63 then return end

    local len = #e.data
    if len < 0x08 + 2 * 32 then return end

    local now = os.time()
    local newIcons = T{}
    for slot = 0, 31 do
        local icon = e.data:byte(9 + slot * 2) * 256 + e.data:byte(10 + slot * 2)
        if icon ~= ICON_EMPTY then newIcons[icon] = slot end
    end

    for icon, slot in pairs(newIcons) do
        if icons[icon] == nil and isRollIcon(icon) then
            local entry = { at = now }
            if lastRollAt ~= nil and now - lastRollAt <= PAIR_WINDOW then
                pending[icon] = entry
                if timeLib ~= nil and len >= 0x48 + 4 * 32 then
                    local stamp = struct.unpack('I', e.data, 0x48 + slot * 4 + 1)
                    if stamp ~= 0x7FFFFFFF then -- permanent-effect marker
                        local k = meritsFromDuration(timeLib.get_calculated_status_time(stamp))
                        if k ~= nil then setDetected(k) end
                    end
                end
            else
                unpaired[icon] = entry
            end
        end
    end

    for icon in pairs(icons) do
        if newIcons[icon] == nil then
            local entry = pending[icon]
            pending[icon] = nil
            if entry ~= nil then
                removals[icon] = { at = now, addedAt = entry.at }
            end
        end
    end

    icons = newIcons
end

M.onFrame = function()
    if not meritListRead and M.detected == nil
        and partyMgr():GetMemberTargetIndex(0) ~= 0 then
        meritListAttempts = meritListAttempts + 1
        local ok, k = pcall(readWinningStreakMerits)
        if ok and k ~= nil then
            meritListRead = true
            if k >= 0 and k <= MAX_MERITS then
                setDetected(k, 'merit list')
            end
        elseif meritListAttempts >= MERIT_LIST_ATTEMPT_LIMIT then
            meritListRead = true -- give up; the ladder channels still work
            print(chatHeader('corhud') .. 'merit list channel unavailable; the ladder channels will detect instead.')
        end
    end

    if next(removals) == nil then return end
    local now = os.time()
    for icon, entry in pairs(removals) do
        if now - entry.at <= PAIR_WINDOW then
        elseif lastRollAt ~= nil and math.abs(lastRollAt - entry.at) <= PAIR_WINDOW then
            removals[icon] = nil -- our own roll ended it early; not a natural expiry
        else
            removals[icon] = nil
            local k = meritsFromElapsed(entry.at - entry.addedAt)
            if k ~= nil then setDetected(k) end
        end
    end
end

M.getDuration = function()
    return BASE_DURATION + MERIT_SECONDS * (M.detected or 0)
end

M.clear = function()
    M.detected = nil
    cfg.settings.winning_streak = nil
    cfg.save()
end

local function scanForMeritHeader(root)
    local found = {}
    for off = 0, 0x400000, 4 do
        local count = ashita.memory.read_uint16(root + off + 2)
        if count >= 1 and count <= 64 then
            local entry = ashita.memory.read_uint32(root + off + 4)
            local okEntries = 0
            for _ = 1, count do
                local ok, id = pcall(ashita.memory.read_uint16, entry)
                local ok2, points
                if ok then ok2, points = pcall(ashita.memory.read_uint8, entry + 3) end
                if not ok or not ok2 or id < 0x0400 or id > 0x1400 or points > 15 then
                    okEntries = -1
                    break
                end
                okEntries = okEntries + 1
                entry = entry + 4
            end
            if okEntries == count then
                found[#found + 1] = off
                if #found >= 8 then break end
            end
        end
    end
    return found
end

M.debug = function()
    local lines = {}
    local function say(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end

    local roots = {} -- { label, address } of scan roots, nil addresses dropped
    if partyMgr():GetMemberTargetIndex(0) == 0 then
        say('not logged in (party target index 0).')
    else
        local ptrMgr = AshitaCore:GetPointerManager()
        local pInventory = ptrMgr ~= nil and ptrMgr:Get('inventory') or 0
        say('inventory pointer: %08X', pInventory)
        if pInventory <= 0 then
            say('no inventory pointer.')
        else
            local first = ashita.memory.read_uint32(pInventory)
            say('first deref: %08X', first)
            if first == 0 then
                say('first deref is 0.')
            else
                roots[#roots + 1] = { 'first deref', first }
                local second = ashita.memory.read_uint32(first)
                say('second deref: %08X', second)
                if second == 0 then
                    say('second deref is 0.')
                else
                    roots[#roots + 1] = { 'second deref', second }
                end
            end
        end
    end

    for _, off in ipairs({ MERIT_LIST_OFFSET, 0x2CFF4 }) do
        local ok, list, reason = pcall(readMeritListAt, off)
        if not ok then
            say('offset %05X: read threw (%s)', off, list)
        elseif list ~= nil then
            local parts = {}
            for id, points in pairs(list) do
                parts[#parts + 1] = string.format('%04X:%d', id, points)
            end
            table.sort(parts)
            say('offset %05X: %s', off, table.concat(parts, ' '))
        else
            say('offset %05X: %s', off, reason)
        end
    end

    for _, root in ipairs(roots) do
        local ok, found = pcall(scanForMeritHeader, root[2])
        if not ok then
            say('scan from %s stopped early (%s)', root[1], found)
        elseif #found == 0 then
            say('scan from %s: no plausible merit-list header found', root[1])
        else
            local parts = {}
            for _, off in ipairs(found) do parts[#parts + 1] = string.format('%05X', off) end
            say('scan from %s, candidate offset(s): %s', root[1], table.concat(parts, ' '))
        end
    end

    if lastMeritPacket ~= nil then
        local parts = {}
        for i = 1, math.min(#lastMeritPacket, 40) do
            parts[#parts + 1] = string.format('%02X', lastMeritPacket:byte(i))
        end
        say('last 0x08C (%d bytes): %s', #lastMeritPacket, table.concat(parts, ' '))
    end
    if lastMeritMenu ~= nil then
        local parts = {}
        for id, points in pairs(lastMeritMenu) do
            parts[#parts + 1] = string.format('%04X:%d', id, points)
        end
        table.sort(parts)
        say('0x08C entries: %s', table.concat(parts, ' '))
    end

    for _, line in ipairs(lines) do print(chatHeader('corhud') .. line) end
end

return M
