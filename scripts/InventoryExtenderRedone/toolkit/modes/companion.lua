---@omw-context player

local util = require('openmw.util')
local v2 = util.vector2

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Roles = D.Roles
local Modes = D.Modes


-- Transferring to a companion: the player's window plus the companion's window.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Companion,
    drag = { allowed = true },
    roles = {
        [Roles.Inventory] = {
            storageSuffix = ':Companion',
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
        },
        [Roles.Companion] = {},
    },
}
