-- cor/merits.lua - auto-detects the local player's Winning Streak merit
-- level from the duration of their own Phantom Roll effects. Horizon's
-- rolls last 300 seconds plus 20 seconds per merit (max 5, the group 2
-- cap), and the COR receives their own rolls like any other party member
-- in range, so the addon only ever has to watch the local player.
--
-- Effect changes reach the client as packet 0x063: a snapshot of the 32
-- status effect icons (uint16 each at byte 0x08, empty slots 0x00FF) plus
-- one expiry timestamp per slot (uint32 at byte 0x48 - `(remaining +
-- vana time) * 60`, wrapped to 32 bits), the same layout LandSandBoat's
-- status_effects.cpp writes. Diffing consecutive snapshots shows exactly
-- which effects appeared and disappeared.
--
-- Detection has four channels:
--  * the 0x08C merit menu packet - server data, no memory offsets; it
--    arrives whenever the Merit Points menu is opened and also feeds
--    the Fold / Snake Eye merited flags in abilities.lua,
--  * the client's merit points list in memory (below) - instant at load,
--    the same source the Horizon timers fork reads (offset 0x28A44, not
--    retail tTimers' 0x2CFF4). The merit id is client data, not
--    server data, but it is still only trusted as the initial value and
--    can always be overwritten by a measurement,
--  * wall-clock time between our own roll icon appearing and disappearing
--    - the ground truth channel; it needs the roll to end naturally, so
--    the first measurement takes one full roll (~5-6 minutes),
--  * decoding the packet timestamp with Ashita's ffxi.time library - an
--    instant read, when the library's patterns match the client in use.
-- The two measuring channels must produce a value that is exactly
-- 300 + 20n seconds before it is accepted, and either one overwrites the
-- merit-list value, so a wrong merit id can only ever be wrong until the
-- first natural roll. Rolls that end early (Fold, bust, eviction by a
-- new roll, zoning) are off the 300 + 20n ladder and get rejected, so a
-- wrong read can never set a wrong value. The accepted value is saved
-- per character, so later sessions start with the countdown already
-- correct.
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

-- One coloured tag for the detection message; not worth pulling in the
-- `chat` module for a single line (same call corhud.lua makes).
local function chatHeader(name)
    return string.char(0x1E, 0x07) .. '[' .. name .. ']' .. string.char(0x1E, 0x01) .. ' '
end

local function partyMgr() return AshitaCore:GetMemoryManager():GetParty() end

local function isRollIcon(icon)
    return (icon >= ICON_ROLL_FIRST and icon <= ICON_ROLL_LAST) or icon == ICON_RUNEIST
end

-- The packet channel reads whole values only; the wall-clock channel sees
-- the same values plus network and clock grain, hence the tolerance.
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

-- ffxi.time decodes the packet timestamp into remaining seconds, but its
-- memory patterns target specific client builds; when they do not match
-- the client in use the module throws at load and only the wall-clock
-- channel stays active. Both channels validate against the 300 + 20n
-- ladder, so a bad decode can never set a wrong value.
local timeLib = nil
do
    local ok, res = pcall(require, 'ffxi.time')
    if ok and type(res) == 'table' and res.get_calculated_status_time ~= nil then
        timeLib = res
    end
end

-- Merit list channel: the client keeps a flat array of {merit id
-- (uint16), points spent (uint8)} pairs behind the inventory pointer.
-- The layout matches tTimers, but the offset is the one the Horizon
-- fork (timers) reads - 0x28A44 - not retail tTimers' 0x2CFF4, which
-- points at unrelated data on this client build. Winning Streak is the
-- client's own data id 0xC04 - not the server's ability id, which on
-- Horizon is renumbered - so it is only used as the initial value; the
-- ladder channels below overwrite it with a real measurement.
local MERIT_ID_WINNING_STREAK = 0xC04
local MERIT_LIST_OFFSET = 0x28A44

-- A list read from memory is only believed when every entry looks like
-- a merit: an id in the merit range and at most 15 points spent. A
-- wrong offset reads unrelated data, so this rejects it instead of
-- seeding the countdown with garbage.
local function isPlausibleMeritList(list)
    local n = 0
    for id, points in pairs(list) do
        if id < 0x0400 or id > 0x1400 or points > 15 then return false end
        n = n + 1
    end
    return n >= 1
end

-- Walks the pointer chain to the merit list at `offset`. Returns the
-- list (merit id -> points) or nil plus a reason, so a broken offset
-- can be told apart from broken pointers. Reads can throw on odd
-- pointer states, so callers pcall.
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

-- nil when the list could not be read, otherwise the points spent in
-- Winning Streak (0 when the list has no entry for it - a COR who has
-- not spent any).
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
    -- 0x0B / 0x0A bracket a zone transition. All effects drop on zoning,
    -- so forget everything in flight. The detected value itself is kept -
    -- it is a merit, not an effect.
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
        -- Merit menu packet: the server sends its own merit list (count
        -- at byte 0x04, then 4-byte {id uint16, points uint8} entries
        -- from 0x08) whenever the Merit Points menu opens - the same
        -- parse tTimers and the timers fork use. Server data, so it
        -- works no matter what the client build does with the in-memory
        -- list.
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
                -- Fold / Snake Eye merit counts feed the Rolls window's
                -- visibility rule (their recast readouts live there).
                for id, name in pairs(D.MERIT_ABILITY_IDS) do
                    local pts = lastMeritMenu[id]
                    if pts ~= nil and pts >= 1 then abilities.markMerited(name, pts) end
                end
            end
        end
        return
    end

    if e.id == 0x28 then
        -- Note our own rolls (the same category/ability fields rolls.lua
        -- uses) so effect arrivals around this moment can be attributed
        -- to us; another COR's roll landing on us must never be measured.
        local actor = struct.unpack('I', e.data, 6)
        local party = partyMgr()
        if actor ~= party:GetMemberServerId(0) then return end
        local category = ashita.bits.unpack_be(e.data_raw, 82, 4)
        if category ~= 6 then return end
        local abilityId = ashita.bits.unpack_be(e.data_raw, 86, 10)
        if D.ROLL_IDS[abilityId] == nil then return end
        lastRollAt = os.time()

        -- The server applies the effect a moment before the action
        -- message reaches us, so its 0x063 can arrive first: pair up any
        -- unpaired roll icons from the last few seconds instead of
        -- letting them sit.
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

    -- 0x063 status effect snapshot. The server always fills all 32 icon
    -- slots (empty ones with 0x00FF) and writes one u32 expiry timestamp
    -- per slot; diffing against the previous snapshot reveals the change.
    local len = #e.data
    if len < 0x08 + 2 * 32 then return end

    local now = os.time()
    local newIcons = T{}
    for slot = 0, 31 do
        -- Icons are big-endian 16-bit values at raw byte 8 + 2*slot with
        -- 0xFF00 as the empty sentinel (a friend's packet dump showed
        -- Food as FD 00 = 0x00FD and Chaos Roll as 3D 01 = 317; the old
        -- struct.unpack reads were endian-flipped and one byte off, so
        -- this channel never fired). e.data:byte is 1-based: 9 + 2*slot.
        local icon = e.data:byte(9 + slot * 2) * 256 + e.data:byte(10 + slot * 2)
        if icon ~= ICON_EMPTY then newIcons[icon] = slot end
    end

    for icon, slot in pairs(newIcons) do
        if icons[icon] == nil and isRollIcon(icon) then
            local entry = { at = now }
            if lastRollAt ~= nil and now - lastRollAt <= PAIR_WINDOW then
                pending[icon] = entry
                -- Timestamp channel: read the full duration the instant
                -- the effect lands, when ffxi.time loaded.
                if timeLib ~= nil and len >= 0x48 + 4 * 32 then
                    -- struct.unpack offsets are 1-based (the same +1
                    -- convention as the 0x050 parse), and stamp for
                    -- slot s starts at byte 0x48 + 4*s.
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

-- Removal measurements are deferred past the pairing window so a roll
-- cast around the removal - a bust or an eviction both remove rolls
-- early - can be ruled out before the wall clock is trusted. Called
-- every frame from corhud.lua.
M.onFrame = function()
    -- Merit list channel: keep trying at startup until the list has
    -- been read once; a ladder measurement afterwards still wins. A
    -- clear (/corhud clear) resets the detected value but not this
    -- flag, so the ladder re-detects instead of the memory read.
    -- Attempts only count while logged in, so sitting at character
    -- select does not burn the retry budget.
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
            -- Too fresh: a bust/eviction's 0x028 may not have arrived yet.
        elseif lastRollAt ~= nil and math.abs(lastRollAt - entry.at) <= PAIR_WINDOW then
            removals[icon] = nil -- our own roll ended it early; not a natural expiry
        else
            removals[icon] = nil
            local k = meritsFromElapsed(entry.at - entry.addedAt)
            if k ~= nil then setDetected(k) end
        end
    end
end

-- The duration a fresh roll should get from this player: the 300 second
-- base plus their detected merits. Falls back to the base (0 merits)
-- until detection happens.
M.getDuration = function()
    return BASE_DURATION + MERIT_SECONDS * (M.detected or 0)
end

-- /corhud clear: forget the detected value (including the saved copy) so
-- the next roll re-detects it from scratch.
M.clear = function()
    M.detected = nil
    cfg.settings.winning_streak = nil
    cfg.save()
end

-- Debug helper: scans a region of the character data for a header that
-- looks like the merit list container - a small count (uint16 at +2)
-- followed by an entry pointer (uint32 at +4) whose entries all read as
-- merit ids with at most 15 points spent. Returns up to 8 candidate
-- offsets from the region's start.
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

-- /corhud merits - one-shot debug: prints the pointer chain step by
-- step, what each candidate offset yields, and scans the character data
-- for a merit-list header, so a moved offset can be found in one
-- in-game run.
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
