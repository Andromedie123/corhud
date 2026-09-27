-- cor/cards.lua - counts how many of each Quick Draw card the player is
-- carrying. Scans inventory the same way packrat does (walk every slot,
-- resolve the item, tally by id) rather than reading fixed item ids, so
-- this keeps working even if a given server's card ids differ from
-- retail's - the lookup is by the item's resource NAME.
local ffi = require('ffi')
local d3d = require('d3d8')
local D = require('cor.data')
local cfg = require('cor.settings')
local d3d8dev = d3d.get_device()

local M = {}
M.itemTextures = T{}

local resourceManager = function() return AshitaCore:GetResourceManager() end
local inventoryManager = function() return AshitaCore:GetMemoryManager():GetInventory() end

-- Resolved once (name -> item resource) and cached, since ids never
-- change mid-session and this is called every draw frame.
local resolved = nil
local function cardResources()
    if resolved ~= nil then return resolved end
    resolved = T{}
    -- Item resources are dense in id space; rather than guess ids we scan
    -- the player's own inventory once for anything named like a card, and
    -- otherwise resolve names lazily the first time one is actually seen
    -- in a slot (see refresh()). This avoids hardcoding any item id.
    return resolved
end

-- name -> { id, count, item }. Rebuilt every call; cheap (81 inventory
-- slots) and simpler than trying to diff container update events.
M.counts = T{}

-- Quiver-style "X Card Case" items (e.g. 'Fire Card Case') each hold 99
-- cards in one slot; matched by name like the cards themselves. Like
-- ninhud's tool tracking, only the inventory and the satchel count -
-- cards or cases parked in the safe, storage or locker read as absent -
-- and the count is kept per element so each row can show its own case
-- count next to the loose cards.
local caseElements = T{} -- 'Fire Card Case' -> 'Fire Card'
for _, name in ipairs(D.CARD_NAMES) do caseElements[name .. ' Case'] = name end
-- The client's item resources truncate the longest case name.
caseElements['Thnd. Card Case'] = 'Thunder Card'
M.cases = 0        -- total cases across all elements
M.caseCounts = T{} -- element name -> { count, item }

M.removeMissingQuantities = function()
    for _, name in ipairs(D.CARD_NAMES) do
        if M.counts[name] ~= nil and M.counts[name].count <= 0 then
            M.counts[name] = nil
        end
    end
end

M.refresh = function()
    local inv = inventoryManager()
    if inv == nil then return end

    local wanted = T{}
    for _, name in ipairs(D.CARD_NAMES) do wanted[name] = true end

    -- Zero every tracked name first so one that hits 0 still shows.
    local seenThisPass = T{}
    for _, name in ipairs(D.CARD_NAMES) do
        seenThisPass[name] = 0
    end

    M.cases = 0
    M.caseCounts = T{}

    -- Loose cards are only usable from the inventory proper, so only
    -- container 0 counts them; cases are storage, and count from the
    -- inventory and the satchel like ninhud's toolbags. Anything in any
    -- other container is deliberately invisible to the addon.
    for _, container in ipairs({ 0, 5 }) do
        local okMax, maxSlots = pcall(function() return inv:GetContainerCountMax(container) end)
        if okMax and maxSlots ~= nil and maxSlots > 0 then
            for i = 1, math.min(80, maxSlots) do
                local ok, containerItem = pcall(function() return inv:GetContainerItem(container, i) end)
                if ok and containerItem ~= nil and containerItem.Id ~= 0 and containerItem.Count > 0 then
                    local item = resourceManager():GetItemById(containerItem.Id)
                    if item ~= nil and item.Name ~= nil then
                        local name = item.Name[1]
                        if container == 0 and wanted[name] then
                            seenThisPass[name] = (seenThisPass[name] or 0) + containerItem.Count
                            if M.counts[name] == nil then
                                M.counts[name] = { id = item.Id, count = 0, item = item }
                            end
                            M.counts[name].id = item.Id
                            M.counts[name].item = item
                        end
                        local element = caseElements[name]
                        if element ~= nil then
                            M.cases = M.cases + containerItem.Count
                            if M.caseCounts[element] == nil then
                                M.caseCounts[element] = { count = 0, item = item }
                            end
                            M.caseCounts[element].count = M.caseCounts[element].count + containerItem.Count
                            M.caseCounts[element].item = item
                        end
                    end
                end
            end
        end
    end

    for _, name in ipairs(D.CARD_NAMES) do
        if M.counts[name] == nil then
            M.counts[name] = { id = nil, count = 0, item = nil }
        end
        M.counts[name].count = seenThisPass[name] or 0
        -- No cards means no icon either; clear the cached item so the row
        -- draws exactly like a card that was never seen this session.
        if M.counts[name].count == 0 then
            M.counts[name].id = nil
            M.counts[name].item = nil
        end
    end

    if cfg.settings.hide_zero_cards then
        M.removeMissingQuantities()
    end
end

M.getTexture = function(item)
    if item == nil then return nil end
    if not M.itemTextures:containskey(item.Id) then
        local texturePointer = ffi.new('IDirect3DTexture8*[1]')
        if ffi.C.D3DXCreateTextureFromFileInMemory(d3d8dev, item.Bitmap, item.ImageSize, texturePointer) ~= ffi.C.S_OK then
            return nil
        end
        M.itemTextures[item.Id] = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texturePointer[0]))
    end
    return tonumber(ffi.cast('uint32_t', M.itemTextures[item.Id]))
end

M.total = function()
    local t = 0
    for _, name in ipairs(D.CARD_NAMES) do
        t = t + (M.counts[name] and M.counts[name].count or 0)
    end
    return t
end

return M
