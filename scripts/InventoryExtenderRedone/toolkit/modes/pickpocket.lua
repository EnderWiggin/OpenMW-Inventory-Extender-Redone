---@omw-context player

local I = require('openmw.interfaces')
local omwself = require('openmw.self')

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
    -- beats Container when the target is a live NPC; the Container role applies unconditionally,
    -- so the NPC case is decided by this more specific spec
    applies = function(role, arg, ctx, uiMode)
        if role ~= Roles.Container then return false end
        return Pickpocket.isTarget(arg)
    end,
    -- must beat Container (priority 1) outright: a live NPC target matches both specs, and the
    -- more specific one wins
    priority = 2,
    -- the engine never sees this key: pickpocket runs under the engine's Container mode, so
    -- drag stays allowed and nothing here may call I.UI with it
    drag = { allowed = true },
    -- the session used to be created in windowManager:show before the window opened; it lives
    -- here now, keyed by the target so reopening either window of this mode does not re-roll
    -- which items the sneak check left visible
    lifecycle = {
        onOpened = function(handler, arg, saved)
            local ctx = I.InventoryExtenderRedone.getContext()
            if Pickpocket.isTarget(arg) and (not ctx.pickpocket or ctx.pickpocket.targetId ~= arg.id) then
                ctx.pickpocket = Pickpocket.createSession(omwself, arg)
            end
        end,
    },
    -- only the Container role is ever in this mode: the player's own window keeps Container's
    -- slots during a pickpocket session, which is what it did before the mode existed
    roles = {
        [Roles.Container] = {
            -- list-slot op: this spec inherits Container's Container-role filters and adds one
            filters = { add = { { id = 'pickpocketVisibility' } } },
            -- everything in an NPC's pockets is owned by that NPC, not by the player: the tooltip
            -- says "yours" for the duration of the session
            states = {
                isOwned = function(handler, ctx)
                    return true
                end,
            },
        },
    },
}
