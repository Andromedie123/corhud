-- cor/rolls.lua - watches the 0x028 action packet for Phantom Rolls
-- landing, works out the bonus that roll actually gave, and keeps a
-- per-recipient table of what is currently active so the UI has
-- something to draw every frame.
--
-- Entries are keyed by the roll's recipient: the target block whose
-- message id (tTimers' applied-buff set: 420 roll result / 424 Double-Up
-- / 426 bust among others) says the effect landed on it. For a roll cast
-- on another member the packet leads with the caster's dice block (which
-- carries the roll number), so the recipient must come from the message,
-- not from block position - the same way tTimers' buff tracker
-- attributes every applied buff. When no block carries one (the packet
-- shapes vary), the roll is held pending and paired with the effect
-- icon that appears in the recipient's 0x076/0x063 snapshot within a
-- few seconds, in either arrival order - the same pairing merits.lua
-- uses. The same roll kept up on two party members at once stays as two
-- entries.
--
-- Whose rolls are tracked follows the tTimers-style setting
-- `roll_track_mode`: 'Self Only' (the default), 'Party' (any Corsair in
-- the party) or 'Alliance' (any alliance member). Rolls another Corsair
-- cast are flagged `foreign`: their bonus falls back to the base tables
-- (their Phantom Roll+ gear can't be read) and their countdown uses the
-- 5:00 base with a widened timeout (their Winning Streak merits can't
-- be read either).
--
-- Entries clear the moment the game reports the effect ended, per
-- channel:
--   * 0x076 party-buff snapshots are diffed per member: a roll's status
--     icon (cor/data.lua ROLL_STATUS_IDS) vanishing from a member's list
--     means that roll faded,
--   * 0x063 is the same snapshot for the local player,
--   * chat "loses the effect of <Roll>" lines are matched per name -
--     including another member's name,
--   * a duration-plus-grace timeout catches anything the above missed.
-- The game caps any one target at two rolls, and a third evicts the
-- oldest - the tracker mirrors that. A successful Double-Up arrives as
-- the roll's own ability id with message id 424 and re-rolls the
-- member's entry in place: new number, same expiry.
local D = require('cor.data')
local merits = require('cor.merits')
local cfg = require('cor.settings')

local M = {}
-- charId -> { rollName -> { number, bonus, icon, at, lucky, unlucky,
--                           bust, foreign, duration } }
M.active = T{}

-- Countdown and timeout for rolls another Corsair cast: their Winning
-- Streak merits (and therefore their roll duration) can't be read, so
-- the base 5:00 is used for the countdown and the timeout grace grows
-- to cover the full 5/5 range.
local FOREIGN_ROLL_DURATION = 300

-- Pairing state for roll packets whose target blocks can't be
-- attributed to a recipient (see the pairing section below). Declared
-- up here because M.expire prunes them.
local PAIR_WINDOW = 5 -- seconds
local pendingRolls = T{}   -- { rollName, abilityId, data, number, bonus, foreign, at }
local unpairedIcons = T{}  -- memberId -> { icon -> at }
local partyBuffIcons = T{} -- memberId -> { icon -> true }, last 0x076 lists

-- Timestamped log of every attribution decision (packets, icon
-- appearances, pairings, fades) for the /corhud rollpackets dump, so a
-- misbehaving roll is readable from one in-game run.
local eventLog = {}
local EVENT_MAX = 40
local function logEvent(fmt, ...)
    eventLog[#eventLog + 1] = string.format('%02d:%02d:%02d ', os.date('*t').hour, os.date('*t').min, os.date('*t').sec) .. string.format(fmt, ...)
    if #eventLog > EVENT_MAX then table.remove(eventLog, 1) end
end

local function partyMgr() return AshitaCore:GetMemoryManager():GetParty() end

local function selfId()
    local party = partyMgr()
    if party == nil then return nil end
    return party:GetMemberServerId(0)
end

-- Character id for a party member's name (chat lines), nil when no
-- member carries it.
local function memberIdByName(name)
    local party = partyMgr()
    if party == nil then return nil end
    for i = 0, 17 do
        if party:GetMemberName(i) == name then
            return party:GetMemberServerId(i)
        end
    end
    return nil
end

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
-- `plus` is the caster's Phantom Roll+ tier; nil means read it from the
-- local player's equipped gear (another Corsair's gear can't be read, so
-- their rolls use plus = 0 and the base tables).
local function bonusFor(rollName, number, data, plus)
    if plus == nil then plus = horizonGearRank() end
    local horizonData = D.HORIZON_ROLLS[rollName]
    local plusData = D.ROLL_PLUS_DATA[rollName]
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

-- Removes anything that ended (a fade channel missed it), that has been
-- sitting unconfirmed past its duration plus a short grace, or whose
-- member has left the party (their rolls left with them). Own rolls
-- time out at the detected duration; another Corsair's rolls at the
-- base 5:00 plus a grace that covers the full Winning Streak range,
-- since their merits can't be read.
M.expire = function()
    local now = os.time()
    local ownTimeout = merits.getDuration() + 10
    local foreignTimeout = FOREIGN_ROLL_DURATION + 100 + 10
    local party = partyMgr()
    local known = nil
    if party ~= nil then
        known = T{}
        for i = 0, 17 do
            local id = party:GetMemberServerId(i)
            if id ~= nil and id ~= 0 then known[id] = true end
        end
    end
    for charId, rollEntries in pairs(M.active) do
        if known ~= nil and not known[charId] then
            M.active[charId] = nil
        else
            for rollName, entry in pairs(rollEntries) do
                local timeout = entry.foreign and foreignTimeout or ownTimeout
                if now - entry.at >= timeout then rollEntries[rollName] = nil end
            end
            if next(rollEntries) == nil then M.active[charId] = nil end
        end
    end

    -- Unpaired roll packets and icons are only useful inside the pairing
    -- window; drop anything older.
    for i = #pendingRolls, 1, -1 do
        if now - pendingRolls[i].at > PAIR_WINDOW then
            logEvent('pending %s expired unpaired', pendingRolls[i].rollName)
            table.remove(pendingRolls, i)
        end
    end
    for memberId, memberIcons in pairs(unpairedIcons) do
        for icon, at in pairs(memberIcons) do
            if now - at > PAIR_WINDOW then memberIcons[icon] = nil end
        end
        if next(memberIcons) == nil then unpairedIcons[memberId] = nil end
    end
end

-- Fold removes a bust before normal rolls, choosing the bust with the
-- longest remaining duration (the oldest tracked bust).
M.removeBust = function()
    local oldest = nil
    for charId, rollEntries in pairs(M.active) do
        for rollName, entry in pairs(rollEntries) do
            if entry.bust and (oldest == nil or entry.at < oldest.at) then
                oldest = { charId = charId, rollName = rollName, at = entry.at }
            end
        end
    end
    if oldest ~= nil then
        M.active[oldest.charId][oldest.rollName] = nil
        if next(M.active[oldest.charId]) == nil then M.active[oldest.charId] = nil end
    end
end

-- Rows for the Rolls window. Same-name rolls group into ONE row with a
-- member count - the way tTimers' buff timers group a roll that several
-- members hold - while busts and single-member rolls keep one row each.
-- A group's primary entry is the member whose roll ends first (tTimers'
-- shortest-remaining rule), so the merged countdown is the one that
-- matters. Rows for members no longer in the party are dropped.
M.rows = function()
    local party = partyMgr()
    if party == nil then return {} end
    local me = party:GetMemberServerId(0)

    local groups = {}  -- rollName -> { name, members }
    local order = {}   -- first-seen order of groups
    local bustRows = {} -- { owner, slot, name, entry }
    for charId, rollEntries in pairs(M.active) do
        local slot = nil
        local owner = nil
        if charId == me then
            slot, owner = 0, 'You'
        else
            for i = 1, 17 do
                if party:GetMemberServerId(i) == charId then
                    slot = i
                    owner = party:GetMemberName(i) or 'Unknown'
                    break
                end
            end
        end
        if owner ~= nil then
            for name, entry in pairs(rollEntries) do
                if entry.bust then
                    -- A bust stays its own row even when a member also
                    -- has the same-name roll live.
                    bustRows[#bustRows + 1] = { owner = owner, slot = slot, name = name, entry = entry }
                else
                    local group = groups[name]
                    if group == nil then
                        group = { name = name, members = {} }
                        groups[name] = group
                        order[#order + 1] = group
                    end
                    group.members[#group.members + 1] = { owner = owner, slot = slot, entry = entry }
                end
            end
        end
    end

    local rows = {}
    for _, r in ipairs(bustRows) do rows[#rows + 1] = r end

    for _, group in ipairs(order) do
        local members = group.members
        table.sort(members, function(a, b)
            if a.entry.at ~= b.entry.at then return a.entry.at < b.entry.at end
            return a.owner < b.owner
        end)
        if #members == 1 then
            local m = members[1]
            rows[#rows + 1] = { owner = m.owner, slot = m.slot, name = group.name, entry = m.entry }
        else
            local primary = members[1]
            local primaryExpiry = primary.entry.at + (primary.entry.duration or 0)
            local minSlot = primary.slot
            for i = 2, #members do
                local m = members[i]
                if m.slot < minSlot then minSlot = m.slot end
                if m.entry.at + (m.entry.duration or 0) < primaryExpiry then
                    primary = m
                    primaryExpiry = m.entry.at + (m.entry.duration or 0)
                end
            end
            rows[#rows + 1] = {
                name    = group.name,
                entry   = primary.entry,
                merged  = members,
                slot    = minSlot,
                at      = primary.entry.at,
            }
        end
    end

    table.sort(rows, function(a, b)
        local sa = a.slot or 99
        local sb = b.slot or 99
        if sa ~= sb then return sa < sb end
        local ea = a.at or a.entry.at
        local eb = b.at or b.entry.at
        if ea ~= eb then return ea < eb end
        return a.name < b.name
    end)
    return rows
end

-- ---------------------------------------------------------- pairing --
-- When a roll packet's target blocks can't be attributed to a recipient
-- (the packet shapes vary), the roll is held and paired with the effect
-- snapshot instead: the member whose 0x076/0x063 buff list gains the
-- roll's status icon within a few seconds is the recipient. The server
-- applies the effect a moment before the action message reaches us, so
-- both orders occur - icons seen before their packet are remembered in
-- unpairedIcons the same way merits.lua pairs roll icons backwards.
-- (The state tables live at the top of the file; M.expire prunes them.)

-- Creates or refreshes one member's roll entry: the game's two-roll cap
-- evicts the member's oldest roll when a third, different one lands, a
-- same-name landing refreshes in place, and a Double-Up (message 424)
-- re-rolls the number while the roll keeps its original expiry.
local function placeRoll(charId, rollName, abilityId, data, number, bonusText, foreign, message, at)
    local targetRolls = M.active[charId]
    if targetRolls == nil then
        targetRolls = T{}
        M.active[charId] = targetRolls
    end

    local existing = targetRolls[rollName]
    if existing == nil then
        local count = 0
        local oldestName = nil
        local oldestAt = nil
        for name, entry in pairs(targetRolls) do
            if not entry.bust then
                count = count + 1
                if oldestAt == nil or entry.at < oldestAt then
                    oldestName = name
                    oldestAt = entry.at
                end
            end
        end
        if count >= 2 and oldestName ~= nil then
            targetRolls[oldestName] = nil
        end
    end

    local entry = {
        number   = number,
        bonus    = bonusText,
        bust     = false,
        lucky    = data.lucky,
        unlucky  = data.unlucky,
        desc     = data.desc,
        icon     = D.ROLL_STATUS_IDS[abilityId],
        foreign  = foreign,
        duration = foreign and FOREIGN_ROLL_DURATION or merits.getDuration(),
    }
    if existing ~= nil and message == 424 then
        -- A Double-Up re-rolls the number, but the roll keeps its
        -- original expiry (user-verified: Double-Up resets nothing).
        entry.at = existing.at
    else
        entry.at = at or os.time()
    end
    targetRolls[rollName] = entry
end

-- A roll icon appeared on `memberId`'s snapshot: either it pairs with a
-- pending roll (attributing it), or it is remembered for a roll packet
-- that has not arrived yet.
local function pairIconWithPending(memberId, icon)
    local now = os.time()
    for i, p in ipairs(pendingRolls) do
        if D.ROLL_STATUS_IDS[p.abilityId] == icon and now - p.at <= PAIR_WINDOW then
            table.remove(pendingRolls, i)
            placeRoll(memberId, p.rollName, p.abilityId, p.data, p.number, p.bonus, p.foreign, p.message, p.at)
            logEvent('paired pending %s (icon %d) -> member %d', p.rollName, icon, memberId)
            return
        end
    end
    local memberIcons = unpairedIcons[memberId]
    if memberIcons == nil then
        memberIcons = T{}
        unpairedIcons[memberId] = memberIcons
    end
    memberIcons[icon] = now
    logEvent('icon %d stashed for member %d (no pending roll)', icon, memberId)
end

-- ------------------------------------------------------------- 0x076 --
-- The party-buff snapshot. Layout per Thorny's tTimers (the working
-- reference on this client): five member blocks at 0x04 + i*0x30, each
-- holding the member's server id (u32), a 64-bit mask of the high two
-- bits of each of 32 buff icons, and the icons' low bytes; an icon id
-- 255 ends the list. The local player's block is skipped - our own
-- buffs come via 0x063. A tracked member whose roll icon has vanished
-- from their list has had that roll fade.
M.onPartyBuffs = function(e)
    local me = selfId()
    for i = 0, 4 do
        local memberOffset = 0x04 + i * 0x30 + 1 -- 1-based, tTimers' offset
        if #e.data < memberOffset + 0x2F then break end
        local memberId = struct.unpack('I', e.data, memberOffset)
        if memberId == 0 then
            -- Empty slot.
        elseif memberId == me then
            -- The local player's own buffs come via 0x063; whatever this
            -- packet holds for us must never clear or mispair self rows.
        else
            local hasIcon = T{}
            for j = 0, 31 do
                local high = ashita.bits.unpack_be(e.data_raw, memberOffset + 7, j * 2, 2)
                local low = struct.unpack('B', e.data, memberOffset + 0x10 + j)
                if low == 255 then break end
                hasIcon[high * 256 + low] = true
            end
            local iconCount = 0
            for _ in pairs(hasIcon) do iconCount = iconCount + 1 end
            logEvent('0x076 member %d: %d icons', memberId, iconCount)
            -- A roll icon that just appeared on the member pairs with a
            -- pending, unattributed roll packet.
            local prev = partyBuffIcons[memberId]
            if prev ~= nil then
                for icon in pairs(hasIcon) do
                    if not prev[icon] and D.ROLL_ICON_NAMES[icon] ~= nil then
                        pairIconWithPending(memberId, icon)
                    end
                end
            end
            partyBuffIcons[memberId] = hasIcon
            local rollEntries = M.active[memberId]
            if rollEntries ~= nil then
                for rollName, entry in pairs(rollEntries) do
                    if entry.icon ~= nil and not hasIcon[entry.icon] then
                        logEvent('fade: member %d lost %s (icon %d)', memberId, rollName, entry.icon)
                        rollEntries[rollName] = nil
                    end
                end
                if next(rollEntries) == nil then M.active[memberId] = nil end
            end
        end
    end
end

-- ------------------------------------------------------------- 0x063 --
-- The local player's own effect snapshot (the same packet merits.lua
-- watches): 32 big-endian 16-bit icon ids at byte 0x08, empty slots
-- 0xFF00. Diffing against the previous snapshot shows which of our own
-- effects ended - the bust icon 309 and the roll icons from
-- D.ROLL_ICON_NAMES clear the matching entries.
local selfIcons = T{} -- icon id -> true, the previous 0x063 snapshot
local ICON_EMPTY = 0xFF00

M.onSelfBuffs = function(e)
    if #e.data < 0x08 + 2 * 32 then return end
    local subtype = e.data:byte(0x04 + 1)

    local newIcons = T{}
    for slot = 0, 31 do
        local icon = e.data:byte(9 + slot * 2) * 256 + e.data:byte(10 + slot * 2)
        if icon ~= ICON_EMPTY then newIcons[icon] = true end
    end

    local me = selfId()

    -- A roll icon that just appeared on us pairs with a pending,
    -- unattributed roll packet (the snapshot often beats the packet).
    -- Run on any snapshot: a false positive just stashes an icon that
    -- expires unused.
    if me ~= nil then
        for icon in pairs(newIcons) do
            if not selfIcons[icon] and D.ROLL_ICON_NAMES[icon] ~= nil then
                logEvent('0x063 icon %d appeared on self', icon)
                pairIconWithPending(me, icon)
            end
        end
    end

    -- Fade clears and the diff baseline only follow the real effect
    -- snapshot (subtype 9, the same check tTimers makes); other 0x063
    -- subtypes carry other layouts and must never read as "the roll
    -- faded".
    if subtype ~= 9 then
        logEvent('0x063 subtype %d ignored for fades', subtype)
        return
    end
    selfIcons = newIcons
    local rollEntries = (me ~= nil) and M.active[me] or nil
    if rollEntries ~= nil then
        for icon in pairs(selfIcons) do
            if not newIcons[icon] then
                if icon == D.BUST_ICON then
                    for rollName, entry in pairs(rollEntries) do
                        if entry.bust then rollEntries[rollName] = nil end
                    end
                else
                    local rollName = D.ROLL_ICON_NAMES[icon]
                    if rollName ~= nil then
                        logEvent('fade: self lost %s (icon %d)', rollName, icon)
                        rollEntries[rollName] = nil
                    end
                end
            end
        end
        if next(rollEntries) == nil then M.active[me] = nil end
    end
end

-- ------------------------------------------------------------ death --
-- Death clears every effect - rolls included. The entity update packets
-- (0x00D non-PCs, 0x00E PCs) carry the death flag the same way tTimers
-- reads it: flag 0x20 at 0x0A, or an hp update (flag 0x04) with 0 hp at
-- 0x1E. The 0x029 action message repeats the death with the message ids
-- tTimers keys on. A dead tracked member's rolls drop with them, so
-- their entries clear instead of lingering until the timeout.
local DEATH_MSGS = T{ 6, 20, 113, 406, 605, 646 }

local function clearMemberRolls(charId)
    if M.active[charId] ~= nil then
        logEvent('death: cleared member %d rolls', charId)
        M.active[charId] = nil
    end
end

M.onEntityUpdate = function(e)
    if #e.data < 0x1F then return end
    local flags = struct.unpack('B', e.data, 0x0A + 1)
    local died = false
    if bit.band(flags, 0x20) == 0x20 then
        died = true
    elseif bit.band(flags, 0x04) == 0x04 then
        if struct.unpack('B', e.data, 0x1E + 1) == 0 then died = true end
    end
    if not died then return end
    clearMemberRolls(struct.unpack('I', e.data, 0x04 + 1))
end

M.onActionMessage = function(e)
    if #e.data < 0x1A then return end
    local messageId = bit.band(struct.unpack('H', e.data, 0x18 + 1), 0x7FFF)
    if DEATH_MSGS:hasval(messageId) then
        clearMemberRolls(struct.unpack('I', e.data, 0x08 + 1))
    end
end

-- ------------------------------------------------------------- 0x028 --
-- Walks the 0x028 target blocks per tTimers' action parse (the working
-- reference on this client): the target count is bits 72-77 (six bits),
-- blocks start at bit 150, each block holds a 32-bit character id plus
-- an action count, and each action carries the roll number in its param
-- (+27) and the result message id at +44. For a roll cast on another
-- member the packet leads with the CASTER's block (the dice roll, whose
-- param is the number), followed by the recipient's block whose message
-- id (tTimers' applied set, D.ROLL_RESULT_MSGS) says the effect landed -
-- so the recipient is read from the message, not from block position.
-- The first block stays the number source.
local function readTargetBlocks(e)
    local targetCount = ashita.bits.unpack_be(e.data_raw, 72, 6)
    if targetCount > 64 then targetCount = 64 end -- malformed-packet cap
    local blocks = {}
    local offset = 150
    for _ = 1, targetCount do
        local charId = ashita.bits.unpack_be(e.data_raw, offset, 32)
        local actionCount = ashita.bits.unpack_be(e.data_raw, offset + 32, 4)
        if actionCount > 8 then actionCount = 8 end -- malformed-packet cap
        offset = offset + 36
        local message = nil
        local param = nil
        for _ = 1, actionCount do
            param = ashita.bits.unpack_be(e.data_raw, offset + 27, 17)
            message = ashita.bits.unpack_be(e.data_raw, offset + 44, 10)
            if ashita.bits.unpack_be(e.data_raw, offset + 85, 1) == 1 then
                offset = offset + 37 -- additional effect block
            end
            offset = offset + 86
            if ashita.bits.unpack_be(e.data_raw, offset, 1) == 1 then
                offset = offset + 34 -- spikes effect block
            end
            offset = offset + 1
        end
        blocks[#blocks + 1] = { charId = charId, message = message, param = param }
    end
    return blocks
end

-- Whether the roll's actor should be tracked at all, per the
-- tTimers-style mode: 'Self Only' (the local player), 'Party' (any
-- Corsair in the party), or 'Alliance' (any alliance member).
local function shouldTrackActor(party, actor, me)
    local mode = cfg.settings.roll_track_mode or 'Self Only'
    if actor == me then return true end
    if mode == 'Self Only' then return false end
    local maxSlot = (mode == 'Party') and 5 or 17
    for i = 1, maxSlot do
        if party:GetMemberServerId(i) == actor then return true end
    end
    return false
end

-- ------------------------------------------------------------ debug --
-- The last few roll-related 0x028 packets, parsed and hex-dumped, for
-- the /corhud rollpackets command. One in-game run of a misbehaving
-- roll prints everything needed to fix the parse without guessing.
local recentPackets = {}
local RECENT_MAX = 8

local function chatHeader(name)
    return string.char(0x1E, 0x07) .. '[' .. name .. ']' .. string.char(0x1E, 0x01) .. ' '
end

local function recordPacket(e, actor, abilityId, blocks)
    local hex = {}
    local len = math.min(#e.data, 48)
    for i = 1, len do
        hex[#hex + 1] = string.format('%02X', e.data:byte(i))
    end
    recentPackets[#recentPackets + 1] = {
        at        = os.time(),
        actor     = actor,
        abilityId = abilityId,
        hex       = table.concat(hex, ' '),
        blocks    = blocks,
    }
    if #recentPackets > RECENT_MAX then
        table.remove(recentPackets, 1)
    end
end

M.debug = function()
    local lines = {}
    local function say(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end

    say('--- recent roll packets ---')
    if #recentPackets == 0 then
        say('(no roll packets seen yet this session)')
    end
    for i, p in ipairs(recentPackets) do
        say('%d. actor=%d ability=%d blocks=%d', i, p.actor, p.abilityId, #p.blocks)
        say('   hex: %s', p.hex)
        for bi, b in ipairs(p.blocks) do
            say('   block %d: char=%d msg=%s param=%s',
                bi, tostring(b.charId), tostring(b.message), tostring(b.param))
        end
    end
    say('--- attribution events (newest last) ---')
    if #eventLog == 0 then
        say('(none yet)')
    end
    for _, entry in ipairs(eventLog) do
        say(entry)
    end
    for _, line in ipairs(lines) do print(chatHeader('corhud') .. line) end
end

M.onPacketIn = function(e)
    -- 0x0B / 0x0A bracket a zone transition. All effects - rolls included -
    -- drop on zoning, so clear the tracked rolls along with the stale action
    -- stream instead of letting them linger until the timeout.
    if e.id == 0xB then
        M.zoning = true
        M.active = T{}
        equipSlots = T{} -- the new zone re-sends the 0x050 burst
        selfIcons = T{}
        partyBuffIcons = T{}
        pendingRolls = T{}
        unpairedIcons = T{}
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
    if e.id == 0x76 then M.onPartyBuffs(e); return end
    if e.id == 0x63 then M.onSelfBuffs(e); return end
    if e.id == 0xD or e.id == 0xE then M.onEntityUpdate(e); return end
    if e.id == 0x29 then M.onActionMessage(e); return end
    if e.id ~= 0x28 then return end

    M.expire()

    local actor = struct.unpack('I', e.data, 6)
    local party = partyMgr()
    local me = party:GetMemberServerId(0)
    if not shouldTrackActor(party, actor, me) then return end
    local foreign = actor ~= me

    local category = ashita.bits.unpack_be(e.data_raw, 82, 4)
    if category ~= 6 then return end -- 6 = Phantom Roll result

    local abilityId = ashita.bits.unpack_be(e.data_raw, 86, 10)
    if abilityId == D.FOLD_ID then
        -- Fold's own packet: only our own Fold removes our tracked busts.
        if not foreign then M.removeBust() end
        return
    end
    local rollName = D.ROLL_IDS[abilityId]
    if rollName == nil then return end
    local data = D.ROLL_DATA[rollName]
    if data == nil then return end

    local blocks = readTargetBlocks(e)
    if #blocks == 0 then return end
    recordPacket(e, actor, abilityId, blocks)
    local number = blocks[1].param
    if number == nil or number == 0 then
        for _, b in ipairs(blocks) do
            if b.param ~= nil and b.param > 0 then
                number = b.param
                break
            end
        end
    end
    if number == nil or number == 0 then return end
    logEvent('roll pkt %s=%d (ability %d): %d blocks', rollName, number, abilityId, #blocks)
    for bi, b in ipairs(blocks) do
        logEvent('  block %d: char=%s msg=%s param=%s', bi, tostring(b.charId), tostring(b.message), tostring(b.param))
    end

    -- Recipients are the blocks whose message says the roll landed on
    -- them (tTimers' applied-buff message set). The caster's own block
    -- is kept when it carries one - that is how a roll cast on yourself
    -- is attributed, exactly as tTimers records it.
    local recipients = {}
    local seen = T{}
    for _, b in ipairs(blocks) do
        if D.ROLL_RESULT_MSGS[b.message] and b.charId ~= nil and b.charId ~= 0
            and not seen[b.charId] then
            recipients[#recipients + 1] = { charId = b.charId, message = b.message }
            seen[b.charId] = true
        end
    end

    local bonusText, isBust = bonusFor(rollName, number, data, foreign and 0 or nil)
    local statusId = D.ROLL_STATUS_IDS[abilityId]

    if isBust then
        -- A bust cancels the rolled effect on everyone who held it. Only
        -- our own busts put the Bust debuff on us; another Corsair's
        -- bust just clears the member's entry (their debuff is theirs).
        for _, rec in ipairs(recipients) do
            local memberRolls = M.active[rec.charId]
            if memberRolls ~= nil then
                memberRolls[rollName] = nil
                if next(memberRolls) == nil then M.active[rec.charId] = nil end
            end
        end
        if foreign then return end
        local selfRolls = M.active[me]
        if selfRolls == nil then
            selfRolls = T{}
            M.active[me] = selfRolls
        end
        selfRolls[rollName] = {
            number   = number,
            bonus    = bonusText,
            bust     = true,
            lucky    = data.lucky,
            unlucky  = data.unlucky,
            desc     = data.desc,
            icon     = D.BUST_ICON,
            foreign  = false,
            duration = merits.getDuration(),
            at       = os.time(),
        }
        return
    end

    if #recipients > 0 then
        for _, rec in ipairs(recipients) do
            logEvent('attributed %s to member %d (msg %s)', rollName, rec.charId, tostring(rec.message))
            placeRoll(rec.charId, rollName, abilityId, data, number, bonusText, foreign, rec.message, os.time())
        end
        return
    end

    -- No attributable block (the packet only carries the caster's dice
    -- roll): pair the roll with the recipient's effect icon instead. The
    -- snapshot can beat the packet, so an icon seen earlier is matched
    -- first; otherwise the roll is held pending for the icon to appear.
    logEvent('no recipient block for %s; pairing needed', rollName)
    local now = os.time()
    for memberId, memberIcons in pairs(unpairedIcons) do
        local at = memberIcons[statusId]
        if at ~= nil and now - at <= PAIR_WINDOW then
            memberIcons[statusId] = nil
            logEvent('paired %s via earlier icon -> member %d', rollName, memberId)
            placeRoll(memberId, rollName, abilityId, data, number, bonusText, foreign, nil, at)
            return
        end
    end
    logEvent('held %s pending for an icon', rollName)
    pendingRolls[#pendingRolls + 1] = {
        rollName  = rollName,
        abilityId = abilityId,
        data      = data,
        number    = number,
        bonus     = bonusText,
        foreign   = foreign,
        message   = nil,
        at        = now,
    }
end

-- Clears the tracked roll the moment the game tells us it actually ended
-- in chat, rather than waiting on a snapshot diff or the timeout. FFXI's
-- own lines read "You lose the effect of Chaos Roll." for the local
-- player and "<Name> loses the effect of Chaos Roll." for party members
-- - each matched to that member's entries.
M.onTextIn = function(e)
    if e.message == nil then return end
    -- Only our own Fold removes our tracked busts (the packet channel
    -- in onPacketIn applies the same rule; a party/alliance Corsair's
    -- Fold is their own business).
    if e.message:match('^[Yy]ou use [Ff]old') then
        M.removeBust()
    end

    local me = selfId()
    local rollName = e.message:match('^[Yy]ou lose the effect of (.-[Rr]oll)%.')
    if rollName ~= nil and me ~= nil then
        local rollEntries = M.active[me]
        if rollEntries ~= nil then
            rollEntries[rollName] = nil
            if next(rollEntries) == nil then M.active[me] = nil end
        end
        return
    end

    local who, theirRoll = e.message:match('^(.-) loses the effect of (.-[Rr]oll)%.')
    if who ~= nil and theirRoll ~= nil then
        local charId = memberIdByName(who)
        if charId ~= nil then
            local rollEntries = M.active[charId]
            if rollEntries ~= nil then
                rollEntries[theirRoll] = nil
                if next(rollEntries) == nil then M.active[charId] = nil end
            end
        end
        return
    end

    -- A bust's own expiry message names no roll, so drop the oldest
    -- tracked bust on it (Fold does the same).
    if e.message:match('[Ll]oses? the effect of [Bb]ust%.') then
        M.removeBust()
    end
end

return M
