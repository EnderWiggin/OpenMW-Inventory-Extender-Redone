---@omw-context player

local util = require('openmw.util')
local v2 = util.vector2
local core = require('openmw.core')

local I = require('openmw.interfaces')
local types = require('openmw.types')
local omwself = require('openmw.self')

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local Pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')
local Roles = D.Roles
local Modes = D.Modes

local Container = types.Container
local NPC = types.NPC


-- Looting a container: the player's window plus the container's own window.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Container,
    -- beats Interface; Pickpocket beats this one when the target is a live NPC, so the Container
    -- role applies unconditionally and the NPC case is decided by the more specific spec
    priority = 1,
    applies = function(role, arg, ctx, uiMode)
        if role == Roles.Container then
            return true
        end
        return role == Roles.Inventory and uiMode == Modes.Container
    end,
    drag = {
        allowed = true,
        -- an NPC container partner auto-equips what it receives: this used to read the engine's
        -- Container mode at transfer time, the mode spec decides it now, keyed by the mode that
        -- started the transfer
        autoEquip = function(ctx, object, source, destination)
            local target = ctx.windowArgs[D.Roles.Container]
            if target and NPC.objectIsInstance(target) then
                return target
            end
        end,
    },
    -- opening anything that is not a pickpocket target ends a session: today windowManager:show
    -- cleared the flag on every Container-role show that did not create a new one
    lifecycle = {
        onOpened = function(handler, arg, saved)
            if not Pickpocket.isTarget(arg) then
                I.InventoryExtenderRedone.getContext().pickpocket = nil
            end
        end,
        -- the engine popped the Container mode: the session flag is cleared and the body plays
        -- its close animation (fires from UiModeChanged for built-ins, decision 11)
        onClosing = function(handler, arg, newMode)
            if newMode ~= nil or not arg then return end
            I.InventoryExtenderRedone.getContext().pickpocket = nil
            arg:sendEvent('IER_ContainerClosed')
        end,
    },
    roles = {
        [Roles.Inventory] = {
            -- literal, never derived from the mode key: this is the UIToolkit:WindowData key,
            -- and losing it silently loses the saved position/size of the player's window
            storageSuffix = ':Container',
            -- getDefaultStorage: only the Inventory role gets defaults outside Interface mode
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
            sources = { { id = 'target' } },
            actions = {
                use = { id = 'usePlayer' },
                pickup = { id = 'pickupContainerInventory' },
            },
            -- the player's window during a container encounter: same strip as the interface
            infoBar = {
                { id = 'encumbrance' },
                { id = 'gold' },
                { id = 'armorRating' },
                { id = 'filler' },
                { id = 'use' },
            },
            states = {
                -- the player's own rows in a chest: an organic container takes everything it
                -- is offered, otherwise only what fits
                isDisabled = function(row, handler, ctx)
                    if row.isBartered then return false end
                    local container = handler.arg
                    if Container.objectIsInstance(container) and Container.record(container).isOrganic then
                        return true
                    end
                    return not helpers.doesItemFit(row.item, container, 1)
                end,
            },
        },
        [Roles.Container] = {
            sources = { { id = 'target' } },
            actions = {
                use = { id = 'useTarget' },
                pickup = { id = 'pickupContainerTarget' },
            },
            -- the container's own strip: weight, the gap, dispose, take all, close (no gold:
            -- the original added gold only for the Inventory and Trade roles)
            infoBar = {
                { id = 'encumbrance' },
                { id = 'filler' },
                { id = 'dispose' },
                { id = 'takeAll' },
                { id = 'close' },
            },
            states = {
                -- tooltip ownership: whose contents this container holds
                isOwned = function(handler, ctx)
                    if Container.objectIsInstance(handler.target) then
                        return helpers.isStealing(omwself, handler.target.owner, handler.target.globalVariable)
                    end
                    return false
                end,
            },
        },
    },
}
