---@omw-context player

local util = require('openmw.util')
local v2 = util.vector2

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Roles = D.Roles
local Modes = D.Modes


-- Looting a container: the player's window plus the container's own window.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Container,
    drag = { allowed = true },
    roles = {
        [Roles.Inventory] = {
            -- literal, never derived from the mode key: this is the UIToolkit:WindowData key,
            -- and losing it silently loses the saved position/size of the player's window
            storageSuffix = ':Container',
            -- getDefaultStorage: only the Inventory role gets defaults outside Interface mode
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
        },
        [Roles.Container] = {},
    },
}
