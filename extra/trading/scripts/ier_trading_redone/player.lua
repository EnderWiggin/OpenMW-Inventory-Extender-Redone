---@omw-context player

local ambient = require 'openmw.ambient'
local I       = require 'openmw.interfaces'
local core    = require 'openmw.core'
local player  = require 'openmw.self'
local ui      = require 'openmw.ui'
local util    = require 'openmw.util'


local H          = require('scripts.UIToolkit.helpers')
local Mode       = require('scripts.InventoryExtenderRedone.toolkit.mode')
local L          = require 'scripts.InventoryExtenderRedone.util.logger'.get 'TradeRedone'
local l10n       = core.l10n 'ier_trading_redone'
local v2         = util.vector2
local IER        = I.InventoryExtenderRedone
local Toolkit    = I.UIToolkit
local T          = Toolkit.Templates
local Components = Toolkit.Components


local barterOffered = assert(Mode.Filters.barterOffered.fn)
local INVEST_SKILL = 25    --TODO: add setting?
local ALL_ITEMS_SKILL = 90 --TODO: add setting?

---@type openmw.types.SkillStat
local mercantile = player.type.stats.skills.mercantile(player)
local REFRESH_DELAY = (core.getGMST('fBarterGoldResetDelay') or 24) * 3600
local HANDLE_SIZE = 32
local SLIDER_LENGTH = 400
local SLIDER_WIDTH = 18

local investments = {}
local applied = {}
local closePopup


local function getMaxInvestment()
    local skill = mercantile.base
    if skill >= 100 then return 100 * skill end
    -- 100 at 0, 1000 at 50, 10000 at 100
    return util.round(100 * 10 ^ (skill / 50))
end

local function showInvestPopup(trader)
    if not trader then return end
    local id = trader.id
    local invested = investments[id] or 0
    local maxInvestment = getMaxInvestment()
    if invested >= maxInvestment then
        ui.showMessage(l10n 'InvestmentLimitReached')
        return
    end
    maxInvestment = maxInvestment - invested
    --TODO: limit by player coins

    local increase = maxInvestment

    local function validate(text)
        local number = tonumber(text)
        if not number then return false end
        return true, util.clamp(util.round(number), 1, maxInvestment)
    end

    local edit, slider

    edit = Components.textEdit {
        width = 100,
        default = increase,
        validate = validate,
        textAlignH = ui.ALIGNMENT.Center,
        onValueChanged = function(value)
            increase = value
            slider:setPosition(value - 1, true)
        end,
    }
    local editHeight = edit.element.layout.props.size.y
    local textSize = Toolkit.getTheme().Sizes.textNormal

    -- the slider is a scrollbar: its position is the count minus one, so dragging and typing set the same value
    slider = Components.scrollBar {
        horizontal = true,
        length = SLIDER_LENGTH,
        maxScroll = math.max(0, maxInvestment - 1),
        handleSize = HANDLE_SIZE,
        width = SLIDER_WIDTH,
        scrollStep = 1,
        onScroll = function(position)
            increase = position + 1
            edit:setValue(increase)
        end,
    }
    -- the scrollbar starts at zero, but the count starts at maxCount
    slider:setPosition(increase - 1, true)

    local body = {
        type = ui.TYPE.Flex,
        props = {
            align = ui.ALIGNMENT.Center,
        },
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    size = v2(SLIDER_LENGTH, editHeight),
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    {
                        name = 'label',
                        template = T.text(),
                        props = {
                            text = l10n 'InvestmentLine',
                            size = v2(0, textSize),
                            autoSize = false,
                        },
                        external = { grow = 1 },
                    },
                    edit.element,
                },
            },
            T.intervalV(8),
            slider.element,
        },
    }

    closePopup = Toolkit.Popups.show {
        title = l10n 'Invest',
        body = body,
        onClosed = function()
            closePopup = nil
        end,
        buttons = { { text = l10n 'Invest', onClicked = function()
            L.info('make investment', invested, increase)
            investments[id] = invested + increase
            applied[id] = core.getGameTime()
            ambient.playSound('item gold up')
            core.sendGlobalEvent('IER_Trading_ApplyInvestment', {
                trader = trader,
                player = player,
                investment = increase
            })
        end }, { text = l10n 'Cancel' } }
    }
end

local btn
IER.patchMode(IER.Modes.Barter, {
    id = 'ier-trade-redone',
    lifecycle = {
        onOpened = function(handler, trader)
            L.info('onOpened', handler.role)
            if handler.role ~= 'Trade' or not trader then return end
            local id = trader.id
            local invested = investments[id]
            if not invested then return end

            local now = core.getGameTime()
            local last = applied[id]
            if last and (now - last) < REFRESH_DELAY then return end
            applied[id] = now

            core.sendGlobalEvent('IER_Trading_ApplyInvestment', {
                trader = trader,
                player = player,
                investment = invested
            })
        end,
        onClosed = function()
            if closePopup then closePopup() end
            closePopup = nil
        end
    },
    roles = {
        Trade = {
            filters = {
                replace = { {
                    id = 'barterOffered',
                    fn = function(row, handler, ctx)
                        return mercantile.base >= ALL_ITEMS_SKILL or barterOffered(row, handler, ctx)
                    end
                } },
            },
            infoBar = {
                add = { {
                    id = 'ier_trade_invest',
                    before = 'offer',
                    create = function(handler)
                        if mercantile.base < INVEST_SKILL then return nil end
                        L.info('create invest button')
                        local theme = Toolkit.getTheme()
                        local sz = handler.infoBar:getHeight()
                        btn = Toolkit.Components.textButton {
                            name = 'ier_trade_invest',
                            text = l10n 'Invest',
                            style = theme.IntRe and 'empty' or 'thin',
                            size = v2(1, 1) * sz,
                            onClick = function()
                                local trader = handler.arg

                                showInvestPopup(trader)
                            end,
                            tooltip = function()
                                local amount = investments[handler.arg.id]
                                return {
                                    width = 300,
                                    body = amount
                                        and l10n('InvestTipMore', { amount = H.addSeparators(amount) })
                                        or l10n 'InvestTipFirst'
                                }
                            end
                        }
                        return function()
                            if not btn then return nil end
                            if IER.getDraggingObject() then return nil end
                            return btn.element
                        end
                    end,
                    cleanup = function()
                        if not btn then return end
                        Toolkit.queueDestroy(btn.element)
                        btn = nil
                    end,
                } }
            },
        },
    },
})

local function refreshInfoBar()
    local handler = IER.getWindow('Trade')
    if not handler then return end
    L.info('applied: refreshing info bar')
    handler.infoBar:update()
end

local function onLoad(save)
    if not save then return end
    investments = save.investments or investments
    applied = save.applied or applied
end

local function onSave()
    return {
        investments = investments,
        applied = applied,
    }
end


return {
    engineHandlers = {
        onInit = onLoad,
        onLoad = onLoad,
        onSave = onSave,
    },
    eventHandlers = {
        IER_Trading_RefreshInfoBar = refreshInfoBar,
    },
}
