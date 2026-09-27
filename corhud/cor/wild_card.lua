local D = require('cor.data')

local M = {}
M.latest = nil
M.zoning = false
M.POPUP_DURATION = 10

local function partyMgr()
    return AshitaCore:GetMemoryManager():GetParty()
end

local function record(number)
    if number == nil or number < 1 or number > 6 then return false end
    M.latest = {
        number = number,
        effect = D.WILD_CARD_EFFECTS[number],
        at = os.time(),
    }
    return true
end

M.onPacketIn = function(e)
    if e.id == 0xB then M.zoning = true; return end
    if e.id == 0xA then M.zoning = false; return end
    if M.zoning or e.id ~= 0x28 then return end

    local party = partyMgr()
    local actor = struct.unpack('I', e.data, 6)
    local playerId = party:GetMemberServerId(0)

    if actor ~= playerId then return end

    -- Wild Card lands as a job ability result (category 6). The first
    -- target block (the caster - the ability is cast on <me>) carries the
    -- roll in several fields, per upstream LandSandBoat's action_t layout
    -- (which matches the pre-update packet bit-for-bit):
    --   bit 191-202: animation = 132 + roll - 1       (132..137)
    --   bit 203-207: info      = roll (action:info)   (5 bits)
    --   bit 208-209: hit distortion, bit 210-212: knockback
    --   bit 213-229: param     = Horizon's roll slot  (17 bits; Phantom
    --                            Rolls put their number here)
    --   bit 230-239: messageID = 435/437/439          (tier pair)
    -- Before the 2026-09 update the roll was read from bits 203-209 as one
    -- 7-bit value. Post-update capture (2026-09-26, roll 2): param=2
    -- info5=2 spec7=2 anim=133 msg=435 - the update added the param carrier
    -- (it was 0 before) and kept info, so read all three carriers and take
    -- the first valid 1-6, arbitrated by the message tier when they disagree.
    local category = ashita.bits.unpack_be(e.data_raw, 82, 4)
    local abilityId = ashita.bits.unpack_be(e.data_raw, 86, 10)
    if category ~= 6 or abilityId ~= D.WILD_CARD_ID then return end

    local animation = ashita.bits.unpack_be(e.data_raw, 191, 12)
    local info      = ashita.bits.unpack_be(e.data_raw, 203, 5)
    local param     = ashita.bits.unpack_be(e.data_raw, 213, 17)
    local msg       = ashita.bits.unpack_be(e.data_raw, 230, 10)

    local candidates = {
        param,
        info,
        animation >= 132 and animation <= 137 and (animation - 131) or nil,
    }

    local result = nil
    for _, roll in ipairs(candidates) do
        if roll ~= nil and roll >= 1 and roll <= 6 then
            result = roll
            break
        end
    end

    -- Message ids 435/437/439 each cover a pair of rolls ({1,2}/{3,4}/{5,6});
    -- when the first carrier disagrees with that tier, prefer one that agrees.
    if result ~= nil and msg >= 435 and msg <= 439 then
        local tier = (msg - 435) / 2
        local low, high = tier * 2 + 1, tier * 2 + 2
        if result < low or result > high then
            local fixed = nil
            for _, roll in ipairs(candidates) do
                if roll ~= nil and roll >= low and roll <= high then
                    fixed = roll
                    break
                end
            end
            if fixed ~= nil then result = fixed end
        end
    end

    if result ~= nil then record(result) end
end

-- No chat fallback: the client's Wild Card log lines ("...uses Wild Card! ...")
-- carry no roll number, so matching digits in text could only pick up party
-- chat. The packet field above is the only source.

M.clear = function()
    M.latest = nil
end

return M