---@omw-context player

local util = require('openmw.util')
local v2 = util.vector2
local types = require('openmw.types')

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Roles = D.Roles
local Modes = D.Modes

local Armor    = types.Armor
local Clothing = types.Clothing
local Weapon   = types.Weapon


-- Transferring to a companion: the player's window plus the companion's window.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Companion,
    priority = 1,
    -- the Companion window is only ever opened by a companion transfer; the player's window is in
    -- this mode while the engine sits in Companion
    applies = function(role, arg, ctx, uiMode)
        if role == Roles.Companion then
            return true
        end
        return role == Roles.Inventory and uiMode == Modes.Companion
    end,
    drag = {
        allowed = true,
        -- a companion auto-equips armor/clothing/weapons it receives: this used to read the
        -- engine's Companion mode at transfer time, the mode spec decides it now, keyed by
        -- the mode that started the transfer
        autoEquip = function(ctx, object, source, destination)
            if Armor.objectIsInstance(object) or Clothing.objectIsInstance(object) or Weapon.objectIsInstance(object) then
                return ctx.windowArgs[D.Roles.Companion]
            end
        end,
    },
    roles = {
        [Roles.Inventory] = {
            storageSuffix = ':Companion',
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
            sources = { { id = 'target' } },
            actions = {
                use = { id = 'usePlayer' },
                pickup = { id = 'pickupCompanionInventory' },
            },
            -- the player's window during a companion transfer: same strip as the interface
            infoBar = {
                { id = 'encumbrance' },
                { id = 'gold' },
                { id = 'armorRating' },
                { id = 'filler' },
                { id = 'use' },
            },
        },
        [Roles.Companion] = {
            sources = { { id = 'target' } },
            actions = {
                use = { id = 'useTarget' },
                pickup = { id = 'pickupCompanionTarget' },
            },
            -- the companion's strip: weight, the gap, what it gained from the player, close (no gold:
            -- the original added gold only for the Inventory and Trade roles)
            infoBar = {
                { id = 'encumbrance' },
                { id = 'filler' },
                { id = 'profit' },
                { id = 'close' },
            },
        },
    },
}
