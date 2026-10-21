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
    priority = 1,
    -- the Trade window is only ever opened by a barter, so it needs no further test; the player's
    -- window is in this mode while the engine sits in Barter
    applies = function(role, arg, ctx, uiMode)
        if role == Roles.Trade then
            return true
        end
        return role == Roles.Inventory and uiMode == Modes.Barter
    end,
    -- validDragModes has no Barter key: dragging is off for both roles, and drag is a ctx
    -- singleton, so the flag is mode-wide rather than per role
    drag = { allowed = false },
    roles = {
        [Roles.Inventory] = {
            storageSuffix = ':Barter',
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
            -- the player's stock plus the merchant's, marked as the other side of the offer
            sources = {
                { id = 'target' },
                { id = 'merchantOfOther' },
            },
            filters = { { id = 'barterOffer' } },
        },
        [Roles.Trade] = {
            -- the merchant's own stock, plus what the player is offering from their pockets
            sources = {
                { id = 'merchantOfTarget' },
                { id = 'self', isBartered = true },
            },
            filters = { { id = 'barterTradeOffer' } },
        },
    },
}
