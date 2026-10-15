---@omw-context global|local|player
local async = require('openmw.async')
local storage = require('openmw.storage')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

---@class IER.Config.Global.Gameplay
---@field b_SoulGemValueRebalance boolean
---@field b_IgnoreChestCapacity boolean

---@class IER.Config.Global
---@field gameplay IER.Config.Global.Gameplay

local configGlobal = {}

---@param section openmw.storage.StorageSection
local function subscribe(section, name)
    section:subscribe(async:callback(function()
        configGlobal[name] = section:asTable()
    end))
    configGlobal[name] = section:asTable()
end

subscribe(storage.globalSection(D.Section.Gameplay), 'gameplay')

return configGlobal --[[@as IER.Config.Global]]
