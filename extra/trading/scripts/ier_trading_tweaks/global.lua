---@omw-context global

local core = require 'openmw.core'
local l10n = core.l10n 'ier_trading_tweaks'


local function applyInvestment(props)
    local trader = props.trader
    local current = trader.type.getBarterGold(trader)

    trader.type.setBarterGold(trader, current + props.investment)
    props.player:sendEvent('IER_Trading_RefreshInfoBar')
end

local function invest(props)
    local gold = props.player.type.inventory(props.player):find('gold_001')
    local increase = props.investment
    if not gold or gold.count < increase then
        props.player:sendEvent('ShowMessage', { message = l10n 'InvestmentLimitGold' })
        return
    end
    gold:remove(increase)
    local trader  = props.trader
    local current = trader.type.getBarterGold(trader)

    trader.type.setBarterGold(trader, current + props.investment)
    props.player:sendEvent('IER_Trading_Invest_Success', { id = trader.id, increase = increase })
end


return {
    eventHandlers = {
        IER_Trading_ApplyInvestment = applyInvestment,
        IER_Trading_Invest = invest,
    },
}
