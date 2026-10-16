-- cor/cards.lua - Quick Draw card and card-case counts (inventory + satchel).

local ffi = require('ffi')
local d3d = require('d3d8')
local D = require('cor.data')
local cfg = require('cor.settings')
local d3d8dev = d3d.get_device()

local M = {}
M.itemTextures = T{}

local resourceManager = function() return AshitaCore:GetResourceManager() end
local inventoryManager = function() return AshitaCore:GetMemoryManager():GetInventory() end

local resolved = nil
local function cardResources()
    if resolved ~= nil then return resolved end
    resolved = T{}
    return resolved
end

M.counts = T{}

local caseElements = T{} -- 'Fire Card Case' -> 'Fire Card'
for _, name in ipairs(D.CARD_NAMES) do caseElements[name .. ' Case'] = name end
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

    local seenThisPass = T{}
    for _, name in ipairs(D.CARD_NAMES) do
        seenThisPass[name] = 0
    end

    M.cases = 0
    M.caseCounts = T{}

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
