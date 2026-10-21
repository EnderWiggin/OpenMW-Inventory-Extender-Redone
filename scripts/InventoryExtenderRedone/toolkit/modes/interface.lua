---@omw-context player

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Roles = D.Roles
local Modes = D.Modes


-- The player's own window. Root spec: everything a custom mode does not name comes from
-- Mode.Defaults.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Interface,
    -- lowest priority: Interface matches whenever nothing more specific applies
    priority = 0,
    drag = { allowed = true },
    roles = {
        [Roles.Inventory] = {
            -- the only pinnable window (inventory.lua:519); no storageSuffix and no defaultStorage
            -- because getStorageSuffix and getDefaultStorage return nil only here
            pinnable = true,
        },
    },
}
