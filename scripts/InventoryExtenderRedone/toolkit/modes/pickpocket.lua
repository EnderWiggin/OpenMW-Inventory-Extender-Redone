---@omw-context player

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')
local Roles = D.Roles
local Modes = D.Modes


-- Pickpocketing a live NPC. Same windows as Container, and it inherits Container's slots:
-- what changes is visibility, ownership, the take action and the closing roll, all of which
-- arrive with the phase that owns that behavior.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Pickpocket,
    base = Modes.Container,
    -- beats Container when the target is a live NPC; the Inventory role window is in this mode
    -- while a session is active, which today is only the ctx.pickpocket.active flag
    -- (windowManager.lua:119-125, inventory.lua:853)
    applies = function(role, arg, ctx)
        if role == Roles.Container then
            return Pickpocket.isTarget(arg)
        end
        local session = ctx.pickpocket
        return session ~= nil and session.active == true
    end,
    priority = 1,
    -- the engine never sees this key: pickpocket runs under the engine's Container mode, so
    -- drag stays allowed and nothing here may call I.UI with it
    drag = { allowed = true },
    roles = {
        [Roles.Inventory] = {},
        [Roles.Container] = {},
    },
}
