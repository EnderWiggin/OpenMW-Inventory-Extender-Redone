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
    priority = 1,
    -- the Companion window is only ever opened by a companion transfer; the player's window is in
    -- this mode while the engine sits in Companion
    applies = function(role, arg, ctx)
        if role == Roles.Companion then
            return true
        end
        return role == Roles.Inventory and ctx.lastUiMode == Modes.Companion
    end,
    drag = { allowed = true },
    roles = {
        [Roles.Inventory] = {
            storageSuffix = ':Companion',
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
            sources = { { id = 'target' } },
        },
        [Roles.Companion] = {
            sources = { { id = 'target' } },
        },
    },
}
