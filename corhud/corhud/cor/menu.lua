-- cor/menu.lua - reads the game's open menu and expanded-chat state so the HUD can hide while the map or the expanded chat log is up.

local M = {}

local pGameMenu = ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0)

local pChatExpanded = ashita.memory.find('FFXiMain.dll', 0, '83EC??B9????????E8????????0FBF4C24??84C0', 0x04, 0)

local function isMapMenu(shortName)
    if shortName == '' then return false end
    return shortName:match('^map') ~= nil
        or shortName == 'cnqframe'
        or shortName == 'region'
end

local function readMenuName()
    local ok, name = pcall(function()
        if pGameMenu == nil or pGameMenu == 0 then return '' end
        local sub = ashita.memory.read_uint32(pGameMenu)
        if sub == 0 then return '' end
        local val = ashita.memory.read_uint32(sub)
        if val == 0 then return '' end
        local header = ashita.memory.read_uint32(val + 4)
        if header == 0 then return '' end
        return (ashita.memory.read_string(header + 0x46, 16):gsub('\x00', ''))
    end)
    if not ok then return '' end
    return name
end

function M.GetMenuShortName()
    local name = readMenuName():gsub('%s+$', '')
    if name == '' then return '' end
    return name:match('^menu%s+(.+)') or name
end

function M.IsMapOpen()
    return isMapMenu(M.GetMenuShortName())
end

function M.IsChatExpanded()
    if pChatExpanded == nil or pChatExpanded == 0 then return false end
    local ok, expanded = pcall(function()
        local ptr = ashita.memory.read_uint32(pChatExpanded)
        if ptr == 0 then return false end
        return ashita.memory.read_uint8(ptr + 0xF1) ~= 0
    end)
    return ok and expanded == true
end

function M.debug()
    local name = readMenuName()
    print(string.format('[corhud] menu: %q (short %q) - hides HUD: %s; signature: %s',
        name, M.GetMenuShortName(), M.IsMapOpen() and 'yes' or 'no',
        (pGameMenu ~= nil and pGameMenu ~= 0) and 'found' or 'FAILED'))
    print(string.format('[corhud] chat expanded: %s; signature: %s',
        M.IsChatExpanded() and 'yes' or 'no',
        (pChatExpanded ~= nil and pChatExpanded ~= 0) and 'found' or 'FAILED'))
end

return M
