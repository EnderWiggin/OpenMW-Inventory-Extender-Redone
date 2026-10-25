---@omw-context player

local util = require('openmw.util')
local v2 = util.vector2
local core = require('openmw.core')
local ui = require('openmw.ui')
local input = require('openmw.input')
local I = require('openmw.interfaces')

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local constants = require('scripts.InventoryExtenderRedone.util.constants')
local configPlayer = require('scripts.InventoryExtenderRedone.config.player')
local cfgUtil = require 'scripts.UIToolkit.config.utils'
local l10n = core.l10n(D.L10N)
local Roles = D.Roles
local Modes = D.Modes

local BUTTON = input.CONTROLLER_BUTTON


-- controller hints replace the base list: Activate offers instead of picking up, and B
-- closes the deal
---@param handler IER.Inventory
---@param ctx InventoryExtenderRedone.Context
---@param base UIToolkit.Controller.HintList
---@return UIToolkit.Controller.HintList
local function barterHints(handler, ctx, base)
    local binds = configPlayer.keybinds
    local find = cfgUtil.getFirstControllerInput
    local select = handler.table.showGrid
        and { find(binds.c_SelUp), find(binds.c_SelDown), find(binds.c_SelLeft), find(binds.c_SelRight) }
        or { find(binds.c_SelUp), find(binds.c_SelDown) }
    return {
        { text = core.getGMST('sBarter'), input = { { id = BUTTON.A }, find(binds.c_Activate) } },
        'separator',
        { text = l10n 'Hint_Category', input = select, },
        { text = l10n 'Hint_Select', input = { { id = BUTTON.DPadUp }, { id = BUTTON.DPadDown } }, },
        'separator',
        { text = constants.Strings.CLOSE, input = { id = input.CONTROLLER_BUTTON.B } },
    }
end


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
    -- leaving a successful barter says thanks, once, before windowManager resets barterState
    -- (built-in lifecycle.onClosing fires from UiModeChanged, decision 11)
    lifecycle = { {
        id = 'Barter',
        onClosing = function(handler, arg, newMode)
            local ctx = I.InventoryExtenderRedone.getContext()
            if ctx.barterState.success then
                ui.showMessage(constants.Strings.BARTER_THANK_YOU, {
                    showInDialogue = true,
                })
            end
        end,
    } },
    -- controller hints replace the base list: Activate offers instead of picking up, and B
    -- closes the deal
    roles = {
        [Roles.Inventory] = {
            storageSuffix = ':Barter',
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
            -- the player's stock plus the merchant's, marked as the other side of the offer
            sources = {
                { id = 'target' },
                { id = 'merchantOfOther' },
            },
            filters = { { id = 'barterAllowed' }, { id = 'barterOffered' }, { id = 'barterInventoryForeign' } },
            -- use is gated by which side of the offer the row sits on; pickup only ever
            -- adjusts the offer bookkeeping (drag is off in this mode)
            actions = {
                use = { id = 'useBarterInventory' },
                pickup = { id = 'pickupBarterInventory' },
            },
            -- bottom strip: same as the player's interface window
            infoBar = {
                { id = 'encumbrance' },
                { id = 'gold' },
                { id = 'armorRating' },
                { id = 'filler' },
                { id = 'use' },
            },
            hints = barterHints,
        },
        [Roles.Trade] = {
            -- the merchant's own stock, plus what the player is offering from their pockets
            sources = {
                { id = 'merchantOfTarget' },
                { id = 'self', isBartered = true },
            },
            filters = { { id = 'barterAllowed' }, { id = 'barterTradeEquipped' }, { id = 'barterOffered' }, { id = 'barterTraderForeign' } },
            actions = {
                use = { id = 'useBarterTrade' },
                pickup = { id = 'pickupBarterTrade' },
            },
            -- the merchant's strip: its gold plus the offer panel
            infoBar = {
                { id = 'gold' },
                { id = 'barterControls' },
                { id = 'barterCancel' },
            },
            hints = barterHints,
        },
    },
}
