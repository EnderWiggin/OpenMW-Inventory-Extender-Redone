---@omw-context player

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Roles = D.Roles
local Modes = D.Modes


-- The player's own window.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Interface,
    -- lowest priority: Interface matches whenever nothing more specific applies
    priority = 0,
    -- the engine mode is nil in the plain interface and 'Interface' while an interface window
    -- (a popup) is open; both are this mode, and no other role has an interface window
    applies = function(role, arg, ctx, uiMode)
        if role ~= Roles.Inventory then return false end
        return uiMode == nil or uiMode == Modes.Interface
    end,
    drag = { allowed = true },
    roles = {
        [Roles.Inventory] = {
            -- the only pinnable window; no storageSuffix or defaultStorage here
            pinnable = true,
            -- the player's own inventory: for this role the target always is omwself
            sources = { { id = 'target' } },
            -- use is always allowed for the player's own window; a plain click drags and
            -- Alt+click drops the item in the world (favorites refuse)
            actions = {
                use = { id = 'usePlayer' },
                pickup = { id = 'pickupInterface' },
            },
            -- bottom strip: weight, gold, armor rating, the gap, the Use button
            infoBar = {
                { id = 'encumbrance' },
                { id = 'gold' },
                { id = 'armorRating' },
                { id = 'filler' },
                { id = 'use' },
            },
        },
    },
}
