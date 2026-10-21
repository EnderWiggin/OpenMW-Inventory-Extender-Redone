---@omw-context player

local util = require('openmw.util')
local v2 = util.vector2

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Roles = D.Roles
local Modes = D.Modes


-- Bartering with an NPC: the player's window plus the merchant's window. Both sides see each
-- other's items cross-fed, which is why the mode has two roles.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Barter,
    -- validDragModes has no Barter key: dragging is off for both roles, and drag is a ctx
    -- singleton, so the flag is mode-wide rather than per role
    drag = { allowed = false },
    roles = {
        [Roles.Inventory] = {
            storageSuffix = ':Barter',
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
        },
        [Roles.Trade] = {},
    },
}
