-- cor/rolls.lua - Phantom Roll tracking: packets, per-member entries, expiry.

local D = require('cor.data')
local merits = require('cor.merits')
local cfg = require('cor.settings')

local M = {}
M.active = T{}

local FOREIGN_ROLL_DURATION = 300

local BUST_DURATION = 300

local FRESH_ROLL_LEAD = 1 -- seconds the server's roll clock leads its packet

local PAIR_WINDOW = 5 -- seconds
local pendingRolls = T{}   -- { rollName, abilityId, data, number, bonus, foreign, at }
local unpairedIcons = T{}  -- memberId -> { icon -> at }
local partyBuffIcons = T{} -- memberId -> { icon -> true }, last 0x076 lists
local memberRollIcons = T{} -- memberId -> last logged 0x076 roll-icon list
local seenRollIcons = T{}  -- memberId -> { icon -> true }, roll icons EVER in that member's list
local unseenLogged = T{}   -- memberId -> { icon -> true }, "kept" notes already printed
local selfBlockRolls = {}  -- roll icons in the local player's own 0x076 block (probe)

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

local equipSlots = T{}

local function equippedItem(slot)
    local inventory = AshitaCore:GetMemoryManager():GetInventory()
    if inventory == nil then return nil end

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

local function matchesRollPlusFamily(item, family)
    return hasPrefix(item.name, family.name)
        or (family.ids ~= nil and family.ids[item.id] ~= nil)
end

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

local function bonusFor(rollName, number, data, plus)
    if plus == nil then plus = horizonGearRank() end
    local horizonData = D.HORIZON_ROLLS[rollName]
    local plusData = D.ROLL_PLUS_DATA[rollName]
    local activeData = horizonData or data
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

    if number < 1 or number > 11 then
        local bust = bustData or activeData.bust
        local bustText = tostring(bust)
        if activeData.percent and tonumber(bust) ~= nil then
            bustText = bustText .. '%'
        end
        return bustText, true -- (text, isBust)
    end

    if data.dual then
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

M.expire = function()
    local now = os.time()
    local ownTimeout = merits.getDuration() + 100 + 10
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
            logEvent('prune: member %d is not in the party table', charId)
            M.active[charId] = nil
        else
            for rollName, entry in pairs(rollEntries) do
                local timeout = entry.bust and (BUST_DURATION + 10)
                    or (entry.foreign and foreignTimeout or ownTimeout)
                if now - entry.at >= timeout then
                    logEvent('expire: member %d %s timed out (age %ds > timeout %ds)',
                        charId, rollName, now - entry.at, timeout)
                    rollEntries[rollName] = nil
                end
            end
            if next(rollEntries) == nil then M.active[charId] = nil end
        end
    end

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

M.rows = function()
    local party = partyMgr()
    if party == nil then return {} end
    local me = party:GetMemberServerId(0)

    local groups = {}  -- rollName -> { [number] = subgroup }
    local order = {}   -- first-seen order of subgroups
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
                    bustRows[#bustRows + 1] = { owner = owner, slot = slot, name = name, entry = entry }
                else
                    local byNumber = groups[name]
                    if byNumber == nil then
                        byNumber = {}
                        groups[name] = byNumber
                    end
                    local subgroup = byNumber[entry.number]
                    if subgroup == nil then
                        subgroup = { name = name, members = {} }
                        byNumber[entry.number] = subgroup
                        order[#order + 1] = subgroup
                    end
                    subgroup.members[#subgroup.members + 1] = { owner = owner, slot = slot, entry = entry }
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
            local minNumberAt = primary.entry.numberAt or primary.entry.at
            for i = 2, #members do
                local m = members[i]
                if m.slot < minSlot then minSlot = m.slot end
                local mat = m.entry.numberAt or m.entry.at
                if mat < minNumberAt then minNumberAt = mat end
                if m.entry.at + (m.entry.duration or 0) < primaryExpiry then
                    primary = m
                    primaryExpiry = m.entry.at + (m.entry.duration or 0)
                end
            end
            rows[#rows + 1] = {
                name     = group.name,
                entry    = primary.entry,
                merged   = members,
                slot     = minSlot,
                numberAt = minNumberAt,
            }
        end
    end

    table.sort(rows, function(a, b)
        local ea = a.entry.at + (a.entry.duration or 0)
        local eb = b.entry.at + (b.entry.duration or 0)
        if ea ~= eb then return ea < eb end
        local na = a.numberAt or a.entry.numberAt or a.entry.at
        local nb = b.numberAt or b.entry.numberAt or b.entry.at
        if na ~= nb then return na < nb end
        local sa = a.slot or 99
        local sb = b.slot or 99
        if sa ~= sb then return sa < sb end
        return a.name < b.name
    end)
    return rows
end

-- ---------------------------------------------------------- pairing --

local function placeRoll(charId, rollName, abilityId, data, number, bonusText, foreign, at)
    local targetRolls = M.active[charId]
    if targetRolls == nil then
        targetRolls = T{}
        M.active[charId] = targetRolls
    end

    local existing = targetRolls[rollName]
    if existing == nil then
        local count = 0
        local evictName = nil
        local evictExpiry = nil
        for name, entry in pairs(targetRolls) do
            if not entry.bust and entry.foreign == foreign then
                count = count + 1
                local expiry = entry.at + (entry.duration or merits.getDuration())
                if evictExpiry == nil or expiry < evictExpiry then
                    evictName = name
                    evictExpiry = expiry
                end
            end
        end
        if count >= 2 and evictName ~= nil then
            logEvent('cap: %s on member %d evicts %s (shortest remaining)', rollName, charId, evictName)
            targetRolls[evictName] = nil
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
    local now = at or os.time()
    entry.at = now
    entry.numberAt = now
    targetRolls[rollName] = entry
end

local function pairIconWithPending(memberId, icon)
    local now = os.time()
    for i, p in ipairs(pendingRolls) do
        if D.ROLL_STATUS_IDS[p.abilityId] == icon and now - p.at <= PAIR_WINDOW then
            table.remove(pendingRolls, i)
            placeRoll(memberId, p.rollName, p.abilityId, p.data, p.number, p.bonus, p.foreign,
                p.startAt or p.at)
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
M.onPartyBuffs = function(e)
    local me = selfId()
    for i = 0, 4 do
        local memberOffset = 0x04 + i * 0x30 + 1 -- 1-based, tTimers' offset
        if #e.data < memberOffset + 0x2F then break end
        local memberId = struct.unpack('I', e.data, memberOffset)
        if memberId == 0 then
        elseif memberId == me then
            local rollsHere = {}
            for j = 0, 31 do
                local high = ashita.bits.unpack_be(e.data_raw, memberOffset + 7, j * 2, 2)
                local low = struct.unpack('B', e.data, memberOffset + 0x10 + j)
                if low == 255 then break end
                local icon = high * 256 + low
                if D.ROLL_ICON_NAMES[icon] ~= nil or icon == D.BUST_ICON then
                    rollsHere[#rollsHere + 1] = icon
                end
            end
            local same = #rollsHere == #selfBlockRolls
            if same then
                for k, icon in ipairs(rollsHere) do
                    if selfBlockRolls[k] ~= icon then same = false; break end
                end
            end
            if not same then
                logEvent('0x076 self block rolls: %s',
                    #rollsHere > 0 and table.concat(rollsHere, ',') or '(none)')
                selfBlockRolls = rollsHere
            end
        else
            local hasIcon = T{}
            for j = 0, 31 do
                local high = ashita.bits.unpack_be(e.data_raw, memberOffset + 7, j * 2, 2)
                local low = struct.unpack('B', e.data, memberOffset + 0x10 + j)
                if low == 255 then break end
                hasIcon[high * 256 + low] = true
            end
            local iconCount = 0
            local rollsHere = {}
            local seen = seenRollIcons[memberId]
            if seen == nil then
                seen = T{}
                seenRollIcons[memberId] = seen
            end
            for icon in pairs(hasIcon) do
                iconCount = iconCount + 1
                if D.ROLL_ICON_NAMES[icon] ~= nil or icon == D.BUST_ICON then
                    rollsHere[#rollsHere + 1] = icon
                    seen[icon] = true
                end
            end
            table.sort(rollsHere)
            local rollsText = #rollsHere > 0 and table.concat(rollsHere, ',') or '(none)'
            if memberRollIcons[memberId] ~= rollsText then
                logEvent('0x076 member %d: %d icons, rolls %s', memberId, iconCount, rollsText)
                memberRollIcons[memberId] = rollsText
            end
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
                        if seen[entry.icon] then
                            logEvent('fade: member %d lost %s (icon %d, ran %ds of %ds)',
                                memberId, rollName, entry.icon, os.time() - entry.at, entry.duration or 0)
                            rollEntries[rollName] = nil
                        else
                            local noted = unseenLogged[memberId]
                            if noted == nil then
                                noted = T{}
                                unseenLogged[memberId] = noted
                            end
                            if not noted[entry.icon] then
                                noted[entry.icon] = true
                                logEvent('0x076: member %d never showed %s (icon %d); kept for the other fade channels',
                                    memberId, rollName, entry.icon)
                            end
                        end
                    end
                end
                if next(rollEntries) == nil then M.active[memberId] = nil end
            end
        end
    end
end

-- ------------------------------------------------------------- 0x063 --
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

    if me ~= nil then
        for icon in pairs(newIcons) do
            if not selfIcons[icon] and D.ROLL_ICON_NAMES[icon] ~= nil then
                logEvent('0x063 icon %d appeared on self', icon)
                pairIconWithPending(me, icon)
            end
        end
    end

    if subtype ~= 9 then
        logEvent('0x063 subtype %d ignored for fades', subtype)
        return
    end
    local prevIcons = selfIcons
    selfIcons = newIcons
    local rollEntries = (me ~= nil) and M.active[me] or nil
    if rollEntries ~= nil then
        for icon in pairs(prevIcons) do
            if not newIcons[icon] then
                if icon == D.BUST_ICON then
                    for rollName, entry in pairs(rollEntries) do
                        if entry.bust then rollEntries[rollName] = nil end
                    end
                else
                    local rollName = D.ROLL_ICON_NAMES[icon]
                    if rollName ~= nil then
                        local entry = rollEntries[rollName]
                        if entry ~= nil and not entry.bust then
                            logEvent('fade: self lost %s (icon %d, ran %ds of %ds)',
                                rollName, icon, os.time() - entry.at, entry.duration or 0)
                            rollEntries[rollName] = nil
                        end
                    end
                end
            end
        end
        if next(rollEntries) == nil then M.active[me] = nil end
    end
end

-- ------------------------------------------------------------ death --
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
    if messageId == 206 then
        local charId = struct.unpack('I', e.data, 0x08 + 1)
        local icon = struct.unpack('H', e.data, 0x0C + 1)
        local rollEntries = M.active[charId]
        if rollEntries ~= nil then
            if icon == D.BUST_ICON then
                for rollName, entry in pairs(rollEntries) do
                    if entry.bust then
                        logEvent('fade: 206 bust off %d (ran %ds of %ds)',
                            charId, os.time() - entry.at, entry.duration or 0)
                        rollEntries[rollName] = nil
                    end
                end
            else
                local rollName = D.ROLL_ICON_NAMES[icon]
                if rollName ~= nil then
                    local entry = rollEntries[rollName]
                    if entry ~= nil and not entry.bust then
                        logEvent('fade: 206 cleared %s on %d (icon %d, ran %ds of %ds)',
                            rollName, charId, icon, os.time() - entry.at, entry.duration or 0)
                        rollEntries[rollName] = nil
                    end
                end
            end
            if next(rollEntries) == nil then M.active[charId] = nil end
        end
        return
    end
    if DEATH_MSGS:hasval(messageId) then
        clearMemberRolls(struct.unpack('I', e.data, 0x08 + 1))
    end
end

-- ------------------------------------------------------------- 0x028 --
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
        msgId     = e.data ~= nil and #e.data >= 0x1A and bit.band(struct.unpack('H', e.data, 0x18 + 1), 0x7FFF) or nil,
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
        local natural = p.msgId ~= nil and math.floor(p.msgId / 2048) or nil
        say('%d. actor=%d ability=%d msgId=%s natural=%s blocks=%d',
            i, p.actor, p.abilityId, tostring(p.msgId), tostring(natural), #p.blocks)
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

    say('--- tracked state ---')
    local me = selfId()
    say('me = %s', tostring(me))
    local anyTracked = false
    for charId, rollEntries in pairs(M.active) do
        anyTracked = true
        local name = nil
        if charId == me then
            name = 'You'
        else
            local party = partyMgr()
            if party ~= nil then
                for i = 1, 17 do
                    if party:GetMemberServerId(i) == charId then
                        name = party:GetMemberName(i) or 'Unknown'
                        break
                    end
                end
            end
        end
        local icons = partyBuffIcons[charId]
        local rolls = {}
        if icons ~= nil then
            for icon in pairs(icons) do
                if D.ROLL_ICON_NAMES[icon] ~= nil or icon == D.BUST_ICON then
                    rolls[#rolls + 1] = icon
                end
            end
            table.sort(rolls)
        end
        say('member %d (%s): last 0x076 rolls %s', charId, name or 'NOT IN PARTY',
            icons == nil and 'never seen' or (#rolls > 0 and table.concat(rolls, ',') or '(none)'))
        for rollName, entry in pairs(rollEntries) do
            say('   %s #%s, age %ds of %ds, icon %s%s%s', rollName, tostring(entry.number),
                os.time() - entry.at, entry.duration or 0, tostring(entry.icon),
                entry.bust and ' BUST' or '', entry.foreign and ' foreign' or '')
        end
    end
    if not anyTracked then say('(no tracked rolls)') end
    say('--- rows (what the window draws) ---')
    local rows = M.rows()
    if #rows == 0 then say('(no rows)') end
    for _, r in ipairs(rows) do
        say('%s #%s -> %s, %ds left', r.name, tostring(r.entry.number),
            r.merged ~= nil and string.format('%d members', #r.merged) or tostring(r.owner),
            (r.entry.at + (r.entry.duration or 0)) - os.time())
    end

    local path = string.gsub(addon.path, '\\\\', '\\') .. 'rollpackets.log'
    local fileLines = { '--- /corhud rollpackets ' .. os.date('%Y-%m-%d %H:%M:%S') .. ' ---' }
    for _, line in ipairs(lines) do
        fileLines[#fileLines + 1] = line
    end
    fileLines[#fileLines + 1] = ''
    local f = io.open(path, 'a')
    if f ~= nil then
        f:write(table.concat(fileLines, '\n'))
        f:close()
        print(chatHeader('corhud') .. string.format(
            'rollpackets dump (%d lines) written to %s', #lines, path))
    else
        for _, line in ipairs(lines) do print(chatHeader('corhud') .. line) end
    end
end

M.onPacketIn = function(e)
    if e.id == 0xB then
        M.zoning = true
        if next(M.active) ~= nil then logEvent('zone: cleared all tracked rolls') end
        M.active = T{}
        equipSlots = T{} -- the new zone re-sends the 0x050 burst
        selfIcons = T{}
        partyBuffIcons = T{}
        memberRollIcons = T{}
        seenRollIcons = T{}
        unseenLogged = T{}
        pendingRolls = T{}
        unpairedIcons = T{}
        return
    end
    if e.id == 0xA then M.zoning = false; return end
    if M.zoning then return end

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
            duration = BUST_DURATION,
            at       = os.time(),
        }
        return
    end

    local isDoubleUp = false
    for _, b in ipairs(blocks) do
        if b.message == 424 then
            isDoubleUp = true
            break
        end
    end
    if not isDoubleUp and #recipients == 0 then
        local actorRolls = M.active[actor]
        local held = actorRolls ~= nil and actorRolls[rollName] or nil
        if held ~= nil and not held.bust and number > held.number then
            isDoubleUp = true
            logEvent('Double-Up inferred for caster %d (%s %d -> %d)', actor, rollName, held.number, number)
        end
    end

    if #recipients > 0 or isDoubleUp then
        local startAt = os.time() - (isDoubleUp and 0 or FRESH_ROLL_LEAD)
        for _, rec in ipairs(recipients) do
            logEvent('attributed %s to member %d (msg %s)', rollName, rec.charId, tostring(rec.message))
            placeRoll(rec.charId, rollName, abilityId, data, number, bonusText, foreign, startAt)
        end
        if isDoubleUp then
            local actorRolls = M.active[actor]
            if actorRolls == nil or actorRolls[rollName] == nil then
                logEvent('Double-Up: attributed to caster %d (no applied block)', actor)
                placeRoll(actor, rollName, abilityId, data, number, bonusText, foreign, startAt)
            end
        end
        return
    end

    logEvent('no recipient block for %s; pairing needed', rollName)
    local now = os.time()
    for memberId, memberIcons in pairs(unpairedIcons) do
        local at = memberIcons[statusId]
        if at ~= nil and now - at <= PAIR_WINDOW then
            memberIcons[statusId] = nil
            logEvent('paired %s via earlier icon -> member %d', rollName, memberId)
            placeRoll(memberId, rollName, abilityId, data, number, bonusText, foreign,
                math.min(at, now - FRESH_ROLL_LEAD))
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
        at        = now,
        startAt   = now - FRESH_ROLL_LEAD,
    }
end

M.onTextIn = function(e)
    if e.message == nil then return end
    local msg = e.message:gsub('%c', '')
    if e.message:find('wears off', 1, true) or e.message:find('loses the effect of', 1, true)
        or e.message:find('effect disappears', 1, true) then
        logEvent('chat: %s', (e.message:gsub('%c', function(c)
            return string.format('\\%02X', string.byte(c))
        end)))
    end
    if msg:match('[Yy]ou use [Ff]old') then
        M.removeBust()
    end

    local me = selfId()
    local rollName = msg:match('[Yy]ou lose the effect of (.-[Rr]oll)%.')
    if rollName == nil then
        rollName = msg:match('[Yy]our (.-[Rr]oll) effect wears off%.')
    end
    if rollName ~= nil and me ~= nil then
        local rollEntries = M.active[me]
        if rollEntries ~= nil then
            if rollEntries[rollName] ~= nil then
                logEvent('chat: cleared %s on self', rollName)
            end
            rollEntries[rollName] = nil
            if next(rollEntries) == nil then M.active[me] = nil end
        end
        return
    end

    local who, theirRoll = msg:match('([%a]+) loses the effect of (.-[Rr]oll)%.')
    if who == nil then
        who, theirRoll = msg:match("([%a]+)'s (.-[Rr]oll) effect wears off%.")
    end
    if who ~= nil and theirRoll ~= nil then
        local charId = memberIdByName(who)
        if charId ~= nil then
            local rollEntries = M.active[charId]
            if rollEntries ~= nil then
                if rollEntries[theirRoll] ~= nil then
                    logEvent('chat: cleared %s on member %d', theirRoll, charId)
                end
                rollEntries[theirRoll] = nil
                if next(rollEntries) == nil then M.active[charId] = nil end
            end
        else
            logEvent('chat: no party member named %s', who)
        end
        return
    end

    local bustFaded =
        msg:match('[Yy]our [Bb]ust effect wears off%.') ~= nil
    if not bustFaded then
        local who = msg:match("([%a]+)'s [Bb]ust effect wears off%.")
        bustFaded = who ~= nil and me ~= nil and memberIdByName(who) == me
    end
    if bustFaded then
        M.removeBust()
    end
end

return M
