---@omw-context global


local function applyInvestment(props)
    local trader = props.trader
    local current  = trader.type.getBarterGold(trader)

    trader.type.setBarterGold(trader, current + props.investment)
    props.player:sendEvent('IER_Trading_RefreshInfoBar')
end


return {
    eventHandlers = {
        IER_Trading_ApplyInvestment = applyInvestment,
    },
}
