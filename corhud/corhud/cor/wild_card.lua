-- cor/wild_card.lua - Wild Card result capture and its popup window state.

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

M.clear = function()
    M.latest = nil
end

return M
