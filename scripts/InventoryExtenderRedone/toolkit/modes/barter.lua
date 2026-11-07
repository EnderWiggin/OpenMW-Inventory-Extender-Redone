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
local barterUtils = require('scripts.InventoryExtenderRedone.util.barter')
local cfgUtil = require 'scripts.UIToolkit.config.utils'
local l10n = core.l10n(D.L10N)
local Roles = D.Roles
local Modes = D.Modes
local BINDING = D.Binds

local BUTTON = input.CONTROLLER_BUTTON
local AXIS = input.CONTROLLER_AXIS
local STR_BARTER = core.getGMST('sBarter')


-- controller hints replace the base list: Activate offers instead of picking up, and B
-- closes the deal
---@param handler IER.Inventory
---@param ctx InventoryExtenderRedone.Context
---@param base UIToolkit.Controller.HintList
---@return UIToolkit.Controller.HintList
local function barterHints(handler, ctx, base)
    local LT = ctx.axis.LT
    local RT = ctx.axis.RT
    local binds = configPlayer.keybinds
    local find = cfgUtil.getFirstControllerInput

    if LT and RT then
        return {
            { text = l10n 'Hint_BarterOne',   input = { id = BUTTON.A } },
            { text = l10n 'Hint_MakeOffer',   input = find(binds.c_Favorite) },
            { text = l10n 'Hint_OfferChange', input = { find(binds.c_SelLeft), find(binds.c_SelRight) } },
            { text = l10n 'Hint_OfferMax',    input = find(binds.c_SelUp) },
            { text = l10n 'Hint_OfferReset',  input = find(binds.c_SelDown) },
            'separator',
            { text = constants.Strings.CLOSE, input = { id = BUTTON.B } },
        }
    elseif LT then
        return {
            { text = l10n 'Hint_BarterOne',   input = { { id = BUTTON.A }, find(binds.c_Activate) } },
            { text = l10n 'Hint_MakeOffer',   input = find(binds.c_Favorite) },
            { text = l10n 'Hint_OfferChange', input = { find(binds.c_SelLeft), find(binds.c_SelRight) } },
            { text = l10n 'Hint_OfferMax',    input = find(binds.c_SelUp) },
            { text = l10n 'Hint_OfferReset',  input = find(binds.c_SelDown) },
            'separator',
            { text = l10n 'Hint_Columns',     input = { find(binds.c_CatPrev), find(binds.c_CatNext) }, },
            'separator',
            { text = constants.Strings.CLOSE, input = { id = BUTTON.B } },
        }
    elseif RT then
        return {
            { text = l10n 'Hint_BarterAll',   input = { { id = BUTTON.A }, find(binds.c_Activate) } },
            { text = l10n 'Hint_MakeOffer',   input = find(binds.c_Favorite) },
            { text = l10n 'Hint_OfferChange', input = { find(binds.c_SelLeft), find(binds.c_SelRight) } },
            { text = l10n 'Hint_OfferMax',    input = find(binds.c_SelUp) },
            { text = l10n 'Hint_OfferReset',  input = find(binds.c_SelDown) },
            'separator',
            { text = l10n 'Hint_Columns',     input = { find(binds.c_CatPrev), find(binds.c_CatNext) }, },
            'separator',
            { text = constants.Strings.CLOSE, input = { id = BUTTON.B } },
        }
    else
        local select = handler.table.showGrid
            and { find(binds.c_SelUp), find(binds.c_SelDown), find(binds.c_SelLeft), find(binds.c_SelRight) }
            or { find(binds.c_SelUp), find(binds.c_SelDown) }
        return {
            { text = STR_BARTER,           input = { { id = BUTTON.A }, find(binds.c_Activate) } },
            'separator',
            { text = l10n 'Hint_Category', input = { find(binds.c_CatPrev), find(binds.c_CatNext) }, },
            { text = l10n 'Hint_Select',   input = select, },
            'separator',
            { text = l10n 'Hint_More',         input = { { id = AXIS.TriggerLeft, axis = true }, { id = AXIS.TriggerRight, axis = true } } },
            { text = constants.Strings.CLOSE,  input = { id = input.CONTROLLER_BUTTON.B } },
            { text = l10n 'Hint_SwitchWindow', input = { id = BUTTON.Back } },
        }
    end
end

---@param handler IER.Inventory
---@param bind string?
---@param base fun(bind:string?) the rest of the chain, this window's own handling at the bottom
---@param repeating boolean? true on the key-repeat path
local function barterInput(handler, bind, base, repeating)
    local ctx = handler.ctx
    local LT = ctx.axis.LT
    local RT = ctx.axis.RT
    local changed = false

    if LT or RT then
        if bind == BINDING.Select_Left then
            barterUtils.adjustOffer(ctx, RT and -5 or -1)
            changed = true
        elseif bind == BINDING.Select_Right then
            barterUtils.adjustOffer(ctx, RT and 5 or 1)
            changed = true
        elseif not repeating then
            if bind == BINDING.Select_Up then
                local max = barterUtils.getMaxOffer(ctx)
                if max then
                    ctx.barterState.currentBalance = max
                    changed = true
                end
            elseif bind == BINDING.Select_Down then
                ctx.barterState.currentBalance = ctx.barterState.currentMerchantOffer
                changed = true
            elseif bind == BINDING.Favorite then
                I.InventoryExtenderRedone.Barter.offerBarter()
            end
        end
        if changed then
            I.InventoryExtenderRedone.forEachOpenWindow(function(h)
                h.infoBar:update()
            end)
        end
    end

    return base(bind)
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
    -- dragging is off for both roles; drag is a ctx singleton, so the flag is mode-wide
    drag = { allowed = false },
    -- leaving a successful barter says thanks, once, before windowManager resets barterState
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
            input = { { id = 'Barter', onInput = barterInput } },
        },
        [Roles.Trade] = {
            -- the merchant's own stock, plus what the item holder on the player's side is
            -- offering (the player in vanilla)
            sources = {
                { id = 'merchantOfTarget' },
                { id = 'partner',         isBartered = true },
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
            input = { { id = 'Barter', onInput = barterInput } },
        },
    },
}
