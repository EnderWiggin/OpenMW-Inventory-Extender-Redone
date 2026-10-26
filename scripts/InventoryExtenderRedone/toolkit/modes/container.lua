---@omw-context player

local util = require('openmw.util')
local v2 = util.vector2
local core = require('openmw.core')

local I = require('openmw.interfaces')
local types = require('openmw.types')
local omwself = require('openmw.self')
local input = require('openmw.input')

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local Pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')
local Roles = D.Roles
local Modes = D.Modes

local constants = require('scripts.InventoryExtenderRedone.util.constants')
local configPlayer = require('scripts.InventoryExtenderRedone.config.player')
local cfgUtil = require 'scripts.UIToolkit.config.utils'
local l10n = core.l10n(D.L10N)

local BUTTON = input.CONTROLLER_BUTTON

local Container = types.Container
local NPC = types.NPC


-- controller hints replace the base list: Activate offers instead of picking up, and B
-- closes the deal
---@param handler IER.Inventory
---@param ctx InventoryExtenderRedone.Context
---@param base UIToolkit.Controller.HintList
---@return UIToolkit.Controller.HintList
local function containerHints(handler, ctx, base)
    local binds = configPlayer.keybinds
    local find = cfgUtil.getFirstControllerInput
    local select = handler.table.showGrid
        and { find(binds.c_SelUp), find(binds.c_SelDown), find(binds.c_SelLeft), find(binds.c_SelRight) }
        or { find(binds.c_SelUp), find(binds.c_SelDown) }
    local swap = configPlayer.keybinds.b_SwapUsePickup
    return {
        { text = l10n(swap and 'Hint_Use' or 'Hint_Pickup'), input = { id = BUTTON.A } },
        { text = l10n(swap and 'Hint_Pickup' or 'Hint_Use'), input = find(binds.c_Activate) },
        { text = l10n 'Hint_TransferAll_Container',          input = find(binds.c_TransferAll) },
        'separator',
        { text = l10n 'Hint_Category', input = { find(binds.c_CatPrev), find(binds.c_CatNext) }, },
        { text = l10n 'Hint_Select',   input = select, },
        'separator',
        { text = constants.Strings.CLOSE, input = { id = input.CONTROLLER_BUTTON.B } },
    }
end

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
        -- an NPC container partner auto-equips what it receives
        autoEquip = function(ctx, object, source, destination)
            local target = ctx.windowArgs[D.Roles.Container]
            if target and NPC.objectIsInstance(target) then
                return target
            end
        end,
    },
    -- opening anything that is not a pickpocket target ends a pickpocket session
    lifecycle = { {
        id = 'Container',
        onOpened = function(handler, arg, saved)
            if not Pickpocket.isTarget(arg) then
                I.InventoryExtenderRedone.getContext().pickpocket = nil
            end
        end,
        -- the engine popped the Container mode: clear the session and play the close animation
        onClosing = function(handler, arg, newMode)
            if newMode ~= nil or not arg then return end
            I.InventoryExtenderRedone.getContext().pickpocket = nil
            arg:sendEvent('IER_ContainerClosed')
        end,
    } },
    roles = {
        [Roles.Inventory] = {
            -- the UIToolkit:WindowData key: literal, never derived from the mode key
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
                { id = 'putAll' },
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
            -- the container's own strip: weight, the gap, dispose, take all, close
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
            hints = containerHints,
        },
    },
}
