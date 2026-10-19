---@omw-context player


local ambient     = require('openmw.ambient')
local core        = require('openmw.core')
local input       = require('openmw.input')
local omwself     = require 'openmw.self'
local types       = require('openmw.types')
local ui          = require('openmw.ui')
local I           = require('openmw.interfaces')

local D           = require('scripts.InventoryExtenderRedone.config.defaults')
local l10n        = core.l10n(D.L10N)

local Toolkit     = I.UIToolkit
local T           = Toolkit.Templates
local Class       = require 'scripts.UIToolkit.class'
local Component   = require 'scripts.UIToolkit.components.component'
local constants   = require('scripts.InventoryExtenderRedone.util.constants')
local barterUtils = require('scripts.InventoryExtenderRedone.util.barter')

local Actor       = types.Actor
local NPC         = types.NPC


local LBL_SPEND = l10n('UI_Barter_Spend')
local LBL_GAIN  = l10n('UI_Barter_Gain')
local BTN_MAX   = l10n('UI_Barter_Max')


---@class InventoryExtenderRedone.BarterControls : UIToolkit.Component
---@field new fun(self:InventoryExtenderRedone.BarterControls):InventoryExtenderRedone.BarterControls
local BarterControls = Class(Component)

local function validate(text)
    local num = tonumber(text)
    if not num then return false, nil end
    return true, num
end

local function getLabelText(barterState)
    if barterState.currentBalance < 0 then
        return LBL_SPEND
    end
    return LBL_GAIN
end

---@param wnd IER.Inventory
function BarterControls:init(wnd)
    local ctx = I.InventoryExtenderRedone.getContext()

    self.labelProps = {
        text = getLabelText(ctx.barterState)
    }
    self.labelElement = ui.create {
        name = 'totalBalanceLabel',
        template = T.text(),
        props = self.labelProps,
    }

    local txtAmount = Toolkit.Components.textEdit {
        width = 80,
        default = function() return math.abs(ctx.barterState.currentMerchantOffer) end,
        validate = validate,
        onValueChanged = function(num)
            local previousBalance = ctx.barterState.currentBalance

            ctx.barterState.currentBalance = (previousBalance >= 0 and 1 or -1) * math.floor(num)
            if num ~= math.abs(num) then
                self.labelProps.text = getLabelText(ctx.barterState)
                Toolkit.queueUpdate(self.labelElement)
            end
        end
    }
    self.txtAmount = txtAmount

    local function modifyBalance(barterState, delta)
        if barterState.currentBalance < 0 then
            barterState.currentBalance = barterState.currentBalance - delta
        else
            barterState.currentBalance = barterState.currentBalance + delta
        end
        txtAmount:setValue(math.abs(barterState.currentBalance))
    end

    local btnMinus = Toolkit.Components.textButton {
        name = 'btn-minus',
        text = '-',
        style = 'thin',
        onClick = function()
            modifyBalance(ctx.barterState, input.isShiftPressed() and -5 or -1)
        end,
    }

    local btnPlus = Toolkit.Components.textButton {
        name = 'btn-plus',
        text = '+',
        style = 'thin',
        onClick = function()
            modifyBalance(ctx.barterState, input.isShiftPressed() and 5 or 1)
        end,
    }

    local btnMax = Toolkit.Components.textButton {
        name = 'btn-max',
        text = BTN_MAX,
        style = 'thin',
        onClick = function()
            local barterGold = Actor.getBarterGold(wnd.target)
            ctx.barterState.currentBalance = barterGold
            txtAmount:setValue(barterGold)
        end,
    }

    local btnOffer = Toolkit.Components.textButton {
        name = 'btn-offer',
        text = constants.Strings.OFFER,
        style = 'thin',
        onClick = function()
            local state = ctx.barterState
            local target = wnd.target

            if not next(state.selling) and not next(state.buying) then
                ui.showMessage(constants.Strings.BARTER_NO_ITEMS)
                return
            end

            local playerGold = omwself.type.inventory(omwself):countOf('gold_001')
            if state.currentBalance < 0 and playerGold < math.abs(state.currentBalance) then
                ui.showMessage(constants.Strings.BARTER_PC_TOO_POOR)
                return
            end

            if state.currentBalance > 0 then
                local merchantGold = target.type.getBarterGold(target)
                if merchantGold < state.currentBalance then
                    ui.showMessage(constants.Strings.BARTER_NPC_TOO_POOR)
                    return
                end
            end

            for _, entry in pairs(state.selling) do
                if ctx.stolenItems[entry.item.recordId] and ctx.stolenItems[entry.item.recordId][target.recordId] then
                    I.UI.setMode(nil)
                    ui.showMessage(string.format(constants.Strings.THATS_MINE,
                        entry.item.type.record(entry.item).name))
                    core.sendGlobalEvent('IER_ConfiscateToOwner', {
                        item = entry.item,
                        count = entry.count,
                        player = omwself,
                        victim = target,
                        stolenMap = ctx.stolenItems,
                    })
                    return
                end
            end

            local offerAccepted, skillGain = barterUtils.haggle(target, state.currentBalance, state.currentMerchantOffer)
            if NPC.objectIsInstance(target) then
                core.sendGlobalEvent('IER_ModDisposition', {
                    target = target,
                    player = omwself,
                    amount = offerAccepted
                        and core.getGMST('iBarterSuccessDisposition')
                        or core.getGMST('iBarterFailDisposition'),
                })
            end

            if not offerAccepted then
                ui.showMessage(constants.Strings.BARTER_REFUSED)
                return
            end

            core.sendGlobalEvent('IER_FinalizeBarter', {
                player = omwself,
                merchant = target,
                barterState = state,
                skillGain = skillGain,
            })

            ambient.playSound('item gold up')
            state.success = true
            I.UI.removeMode('Barter')
        end,
    }

    local btnClose = Toolkit.Components.textButton {
        name = 'btn-close',
        text = constants.Strings.CANCEL,
        style = 'thin',
        onClick = function()
            I.UI.removeMode('Barter')
        end,
    }

    Component.init(self, ui.create {
        name = 'barterControls',
        type = ui.TYPE.Flex,
        external = { grow = 1, stretch = 1, },
        props = {
            horizontal = true,
            arrange = ui.ALIGNMENT.Center,
            align = ui.ALIGNMENT.End,
            autoSize = false,
        },
        content = ui.content {
            { external = { grow = 1, stretch = 1 } },
            self.labelElement,
            T.intervalH(8),
            btnMinus.element,
            T.intervalH(4),
            txtAmount.element,
            T.intervalH(4),
            btnPlus.element,
            T.intervalH(4),
            btnMax.element,
            { external = { grow = 1, stretch = 1 } },
            btnOffer.element,
            T.intervalH(8),
            btnClose.element,
        }
    })
end

function BarterControls:update(ctx)
    local state = ctx.barterState
    if not next(state.selling) and not next(state.buying) then
        state.currentBalance = 0
    end
    self.labelProps.text = getLabelText(state)
    Toolkit.queueUpdate(self.labelElement)

    self.txtAmount:setValue(math.abs(state.currentBalance))
end

return BarterControls
