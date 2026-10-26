---@omw-context player

local I = require('openmw.interfaces')
local core = require('openmw.core')
local omwself = require('openmw.self')

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')
local Roles = D.Roles
local Modes = D.Modes


-- Pickpocketing a live NPC: same windows as Container, inheriting its slots.
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
    -- must beat Container (priority 1) outright, since a live NPC target matches both specs
    priority = 2,
    -- the engine never sees this key: pickpocket runs under the engine's Container mode, so
    -- nothing here may call I.UI with it. The drag slot, autoEquip included, is inherited
    -- from Container.
    -- the session is created when this mode's window opens, keyed by the target so reopening
    -- either window does not re-roll which items the sneak check left visible
    lifecycle = { {
        id = 'Pickpocket',
        -- this spec names both hooks, so Container's lifecycle entry is not in the chain here
        onOpened = function(handler, arg, saved)
            local ctx = I.InventoryExtenderRedone.getContext()
            if Pickpocket.isTarget(arg) and (not ctx.pickpocket or ctx.pickpocket.targetId ~= arg.id) then
                ctx.pickpocket = Pickpocket.createSession(omwself, arg)
            end
        end,
        -- leaving the session without resolving it rolls the close sneak check: failing alerts
        -- the victim; either way the flag clears and the body plays its close animation
        onClosing = function(handler, arg, newMode)
            if newMode ~= nil or not arg then return end
            local ctx = I.InventoryExtenderRedone.getContext()
            if ctx.pickpocket and ctx.pickpocket.active and not ctx.pickpocket.resolved and
                Pickpocket.isTarget(arg)
            then
                local success = Pickpocket.rollClose(omwself, arg)
                if not success then
                    core.sendGlobalEvent('IER_CommitPickpocket', {
                        player = omwself,
                        target = arg,
                        victimAware = true,
                    })
                end
            end
            ctx.pickpocket = nil
            arg:sendEvent('IER_ContainerClosed')
        end,
    } },
    -- only the Container role is in this mode: the player's own window keeps Container's slots
    roles = {
        [Roles.Container] = {
            -- inherits Container's Container-role filters and adds the visibility one
            filters = { add = { { id = 'pickpocketVisibility' } } },
            -- the take roll runs before either effect lands; use carries the session the roll
            -- belongs to into the IER_UseItem payload
            actions = {
                use = { id = 'useTargetPickpocket' },
                pickup = { id = 'pickpocketTake' },
            },
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
