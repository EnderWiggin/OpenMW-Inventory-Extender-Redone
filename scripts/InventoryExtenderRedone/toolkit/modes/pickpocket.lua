---@omw-context player

local I = require('openmw.interfaces')
local core = require('openmw.core')
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
    -- drag stays allowed and nothing here may call I.UI with it. The drag slot is inherited
    -- from Container outright, autoEquip included: the same NPC-partner rule applies here.
    -- the session used to be created in windowManager:show before the window opened; it lives
    -- here now, keyed by the target so reopening either window of this mode does not re-roll
    -- which items the sneak check left visible
    lifecycle = { {
        id = 'Pickpocket',
        -- a spec's own lifecycle array replaces the base's entries, and this spec names both
        -- hooks, so Container's entry is not in the chain here
        onOpened = function(handler, arg, saved)
            local ctx = I.InventoryExtenderRedone.getContext()
            if Pickpocket.isTarget(arg) and (not ctx.pickpocket or ctx.pickpocket.targetId ~= arg.id) then
                ctx.pickpocket = Pickpocket.createSession(omwself, arg)
            end
        end,
        -- leaving the session without resolving it rolls the close sneak check: failing alerts
        -- the victim; either way the flag clears and the body plays its close animation
        -- (windowManager dispatches this spec while a session is active, decision 11)
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
    -- only the Container role is ever in this mode: the player's own window keeps Container's
    -- slots during a pickpocket session, which is what it did before the mode existed
    roles = {
        [Roles.Container] = {
            -- list-slot op: this spec inherits Container's Container-role filters and adds one
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
