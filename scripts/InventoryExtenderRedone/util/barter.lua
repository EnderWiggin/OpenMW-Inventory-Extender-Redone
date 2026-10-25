---@omw-context player
local types = require('openmw.types')
local util = require('openmw.util')
local self = require('openmw.self')
local core = require('openmw.core')
local ui = require('openmw.ui')
local ambient = require('openmw.ambient')
local I = require('openmw.interfaces')

local constants = require('scripts.InventoryExtenderRedone.util.constants')
local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local L = require('scripts.InventoryExtenderRedone.util.logger').get 'Barter'

local Weapon = types.Weapon
local Armor = types.Armor
local Lockpick = types.Lockpick
local Probe = types.Probe
local Repair = types.Repair
local Creature = types.Creature
local NPC = types.NPC
-- this file is player-context glue: omwself is always a Player, so the type table and the
-- player inventory object are cached once at load instead of re-derived per call
local Player = types.Player
local playerInventory = Player.inventory(self)

local function getEffectiveValue(item, count)
    local basePrice = item.type.record(item).value

    local itemData = item.type.itemData(item)
    local itemRecord = item.type.record(item)

    local x
    if Weapon.objectIsInstance(item) or Armor.objectIsInstance(item) then
        local condition = itemData.condition
        if condition then
            x = basePrice * (condition / itemRecord.health)
        else
            x = basePrice
        end
    elseif Lockpick.objectIsInstance(item) or Probe.objectIsInstance(item) or Repair.objectIsInstance(item) then
        local uses = itemData.condition or 0
        local maxUses = itemRecord.maxCondition
        x = basePrice * (uses / maxUses)
    elseif itemData.soul then
        x = helpers.getItemValue(item)
    else
        x = basePrice
    end
    return x * count
end

--- Haggle override chain (ctx.overrides.haggle): handlers run in reverse registration order,
--- each non-nil return replaces the running value for its own field, so chance modifiers
--- stack and the last registered wins per field. Chance is clamped to [0, 100] after each
--- replacement, which makes 100 guaranteed acceptance and 0 guaranteed refusal with one
--- number. The chain runs before the dice are rolled, so a mod never sees or re-rolls them.
--- The vanilla early outs (offer already at/below the merchant's, creature merchants) have no
--- computed chance and bypass the chain.
---@param overrides InventoryExtenderRedone.HaggleOverrideEntry[]
---@param npc openmw.Object
---@param playerOffer number
---@param merchantOffer number
---@param chance number IER's computed acceptance threshold
---@return number chance the possibly replaced threshold
---@return number? skillGain the last registered replacement, nil when no handler forced one
local function applyHaggleOverrides(overrides, npc, playerOffer, merchantOffer, chance)
    local skillGain
    for i = #overrides, 1, -1 do
        local newChance, newGain = overrides[i].handler(npc, playerOffer, merchantOffer, chance)
        if newChance ~= nil then
            chance = util.clamp(newChance, 0, 100)
        end
        if newGain ~= nil then
            skillGain = newGain
        end
    end
    return chance, skillGain
end

local function haggle(npc, playerOffer, merchantOffer, ctx)
    if playerOffer <= merchantOffer then
        return true
    end

    if Creature.objectIsInstance(npc) then
        return false
    end

    local buying = merchantOffer < 0
    local a = math.abs(merchantOffer)
    local b = math.abs(playerOffer)
    local d = buying and math.modf(100 * (a - b) / a) or math.modf(100 * (b - a) / b)

    local clampedDisposition = util.clamp(npc.type.getDisposition(npc, self), 0, 100)

    local a1 = self.type.stats.skills.mercantile(self).modified
    local b1 = 0.1 * self.type.stats.attributes.luck(self).modified
    local c1 = 0.2 * self.type.stats.attributes.personality(self).modified
    local d1 = npc.type.stats.skills.mercantile(npc).modified
    local e1 = 0.1 * npc.type.stats.attributes.luck(npc).modified
    local f1 = 0.2 * npc.type.stats.attributes.personality(npc).modified

    local dispositionTerm = core.getGMST('fDispositionMod') * (clampedDisposition - 50)
    local pcTerm = (dispositionTerm + a1 + b1 + c1) * helpers.getFatigueTerm(self)
    local npcTerm = (d1 + e1 + f1) * helpers.getFatigueTerm(npc)
    local x = core.getGMST('fBargainOfferMulti') * d + core.getGMST('fBargainOfferBase') + math.modf(pcTerm - npcTerm)

    -- the override chain may replace the threshold and force a skill gain before the roll
    local forcedGain
    x, forcedGain = applyHaggleOverrides(ctx.overrides.haggle, npc, playerOffer, merchantOffer, x)

    local roll = math.random(1, 100)

    if roll > x or (merchantOffer < 0 and 0 < playerOffer) then
        return false
    end

    local skillGain = 0
    local finalPrice = math.abs(playerOffer)
    local initialMerchantOffer = math.abs(merchantOffer)

    if (not buying and (finalPrice > initialMerchantOffer)) then
        skillGain = math.floor(100 * (finalPrice - initialMerchantOffer) / finalPrice)
    elseif (buying and (finalPrice < initialMerchantOffer)) then
        skillGain = math.floor(100 * (initialMerchantOffer - finalPrice) / initialMerchantOffer)
    end

    -- a chain-forced gain replaces the price-delta-derived one (0 is a valid forced value)
    return true, forcedGain or skillGain
end

local function getBarterOffer(merchant, basePrice, buying)
    if basePrice == 0 then
        return basePrice
    end
    if Creature.objectIsInstance(merchant) then
        return math.max(1, math.modf(basePrice))
    end

    local clampedDisposition = util.clamp(merchant.type.getDisposition(merchant, self), 0, 100)
    local a = math.min(self.type.stats.skills.mercantile(self).modified, 100)
    local b = math.min(0.1 * self.type.stats.attributes.luck(self).modified, 10)
    local c = math.min(0.2 * self.type.stats.attributes.personality(self).modified, 10)
    local d = math.min(merchant.type.stats.skills.mercantile(merchant).modified, 100)
    local e = math.min(0.1 * merchant.type.stats.attributes.luck(merchant).modified, 10)
    local f = math.min(0.2 * merchant.type.stats.attributes.personality(merchant).modified, 10)
    local pcTerm = (clampedDisposition - 50 + a + b + c) * helpers.getFatigueTerm(self)
    local npcTerm = (d + e + f) * helpers.getFatigueTerm(merchant)
    local buyTerm = 0.01 * (100 - 0.5 * (pcTerm - npcTerm))
    local sellTerm = 0.01 * (50 - 0.5 * (npcTerm - pcTerm))
    local offerPrice = math.modf(basePrice * (buying and buyTerm or sellTerm))
    return math.max(1, offerPrice)
end

--- Price override chain (ctx.overrides.price): consulted inside itemOffer, so the queue
--- (updateOffer), the prediction exports and the committed gold (finalizeBarter) all see
--- the same repriced value - one implementation, no drift. Handlers run in reverse
--- registration order; each non-nil return replaces the running magnitude, so modifiers
--- compose and the last registered wins. buying is the barter direction - true when the
--- player BUYS item from npc (the buy side), false when the player SELLS it to npc (the
--- sell side) - so one handler can price the two directions differently. price is the
--- final per-item contribution magnitude (after the 0.75 cap and the NPC min/max rule);
--- updateOffer applies the sign per side. Returned price is clamped to [0, infinity):
--- 0 means a free item; a negative would flip the offer sign and corrupt the balance scalars.
---@param overrides InventoryExtenderRedone.PriceOverrideEntry[]
---@param npc openmw.Object
---@param item openmw.Object
---@param count number
---@param buying boolean
---@param price number
---@return number
local function applyPriceOverrides(overrides, npc, item, count, buying, price)
    for i = #overrides, 1, -1 do
        local newPrice = overrides[i].handler(npc, item, count, buying, price)
        if newPrice ~= nil then
            price = math.max(0, newPrice)
        end
    end
    return price
end

--- Per-item merchant-offer contribution: effective value -> getBarterOffer -> 0.75 cap ->
--- NPC min for selling, then the price override chain. updateOffer and the price exports
--- share this single implementation so the prediction cannot drift from what the queue
--- actually prices. Returns the positive magnitude; updateOffer applies the sign per side.
---@param npc openmw.Object
---@param item openmw.Object
---@param count number
---@param buying boolean true = player buying from npc (buy side), false = selling (sell side)
---@param ctx InventoryExtenderRedone.Context carrier for the price override chain
---@return number
local function itemOffer(npc, item, count, buying, ctx)
    local basePrice = getEffectiveValue(item, count)
    local cap = math.modf(math.max(1, 0.75 * basePrice))
    local offerPrice = getBarterOffer(npc, basePrice, buying)
    local price
    if buying then
        price = math.max(cap, offerPrice)
    elseif NPC.objectIsInstance(npc) then
        price = math.min(cap, offerPrice)
    else
        price = offerPrice
    end
    return applyPriceOverrides(ctx.overrides.price, npc, item, count, buying, price)
end

local function updateOffer(ctx)
    local state = ctx.barterState
    local merchant = ctx.windowArgs.Trade
    if not state or not merchant then
        return
    end

    local merchantOffer = 0
    for _, buyingData in pairs(state.buying) do
        merchantOffer = merchantOffer - itemOffer(merchant, buyingData.item, buyingData.count, true, ctx)
    end

    for _, sellingData in pairs(state.selling) do
        merchantOffer = merchantOffer + itemOffer(merchant, sellingData.item, sellingData.count, false, ctx)
    end

    local diff = merchantOffer - (state.currentMerchantOffer or 0)
    state.currentMerchantOffer = merchantOffer
    state.currentBalance = (state.currentBalance or 0) + diff
end

--- Offer queue entry: { item, stacks = row.virtualStacks, count } keyed by row.item.id.
--- stacks is nil on sell rows by construction; finalizeBarter walks entry.stacks restock-aware,
--- so a virtual row must carry its stacks or items silently mis-move.
local function offerIncrement(offer, row, count)
    local entry = offer[row.item.id]
    if not entry then
        entry = { item = row.item, stacks = row.virtualStacks, count = 0 }
        offer[row.item.id] = entry
    end
    entry.count = math.min(entry.count + count, row.getCount())
end

--- count omitted clears the entry.
local function offerDecrement(offer, row, count)
    local entry = offer[row.item.id]
    if not entry then
        return
    end
    entry.count = entry.count - (count or entry.count)
    if entry.count <= 0 then
        offer[row.item.id] = nil
    end
end

--- Shared tail: the row-action sound plus repricing and the window refresh trigger.
local function offerTail(row, ctx)
    local sound = helpers.getItemSound(row.item, 'down')
    if sound then
        ambient.playSound(sound)
    end
    updateOffer(ctx)
    self:sendEvent('IER_Update')
end

--- Row-action effect factory for the two Barter role parts (mode.lua Mode.Actions):
--- decrementTable is where a bartered row's units come back from, incrementTable where a
--- fresh offer is recorded; the parts differ only in which side of the offer they sit on.
---@param decrementTable string 'selling' or 'buying'
---@param incrementTable string the other side
---@return fun(row:InventoryExtenderRedone.RowData, handler:any?, ctx:InventoryExtenderRedone.Context, count:number)
local function barterOfferEffect(decrementTable, incrementTable)
    return function(row, _, ctx, count)
        if row.isBartered then
            offerDecrement(ctx.barterState[decrementTable], row, count)
        else
            offerIncrement(ctx.barterState[incrementTable], row, count)
        end
        offerTail(row, ctx)
    end
end

--- Queue ops for the public barter surface: the increment/decrement branch plus the shared
--- tail, with the side fixed by the operation instead of read from row.isBartered. Outside
--- a trade (no known merchant) they do nothing and only warn - the same nil-merchant
--- condition updateOffer early-returns on, so the offer scalars never go stale silently.
---@param ctx InventoryExtenderRedone.Context
---@param op string the operation name, for the warning
---@return boolean
local function tradeGuard(ctx, op)
    if ctx.windowArgs.Trade then
        return true
    end
    L.warn('no merchant for barter queue op:', op)
    return false
end

---@param ctx InventoryExtenderRedone.Context
---@param row InventoryExtenderRedone.RowData
---@param count number
local function queueSell(ctx, row, count)
    if not tradeGuard(ctx, 'queueSell') then return end
    offerIncrement(ctx.barterState.selling, row, count)
    offerTail(row, ctx)
end

---@param ctx InventoryExtenderRedone.Context
---@param row InventoryExtenderRedone.RowData
---@param count number
local function queueBuy(ctx, row, count)
    if not tradeGuard(ctx, 'queueBuy') then return end
    offerIncrement(ctx.barterState.buying, row, count)
    offerTail(row, ctx)
end

---@param ctx InventoryExtenderRedone.Context
---@param row InventoryExtenderRedone.RowData
---@param count number? omitted clears the entry
local function unqueueSell(ctx, row, count)
    if not tradeGuard(ctx, 'unqueueSell') then return end
    offerDecrement(ctx.barterState.selling, row, count)
    offerTail(row, ctx)
end

---@param ctx InventoryExtenderRedone.Context
---@param row InventoryExtenderRedone.RowData
---@param count number? omitted clears the entry
local function unqueueBuy(ctx, row, count)
    if not tradeGuard(ctx, 'unqueueBuy') then return end
    offerDecrement(ctx.barterState.buying, row, count)
    offerTail(row, ctx)
end

--- Reset the offer to empty. Mutates in place (unlike windowManager.lua:260, which replaces
--- the table on mode change while every window closes): the Trade window stays open across
--- this call, so its init-time closures holding the state table must keep seeing it.
---@param ctx InventoryExtenderRedone.Context
local function clearBarterOffer(ctx)
    local state = ctx.barterState
    state.selling = {}
    state.buying = {}
    state.currentMerchantOffer = 0
    state.currentBalance = 0
end

--- The whole Offer sequence, shared by the Trade window's Offer button and the future
--- offerBarter API (one implementation, two entry points).
---@param npc openmw.Object the merchant the Trade window is showing
---@param ctx InventoryExtenderRedone.Context
---@param opts table? { closeWindow = boolean? } default true; governs only the Barter UI
---  mode removal - when false, the offer queues are cleared and the offer scalars zeroed
---  instead, because finalizeBarter does not reset them and the window would otherwise
---  still show the just-moved items as offered
---@return boolean accepted
---@return number? skillGain
local function completeOffer(npc, ctx, opts)
    local state = ctx.barterState

    if not next(state.selling) and not next(state.buying) then
        ui.showMessage(constants.Strings.BARTER_NO_ITEMS)
        return false
    end

    local playerGold = playerInventory:countOf('gold_001')
    if state.currentBalance < 0 and playerGold < math.abs(state.currentBalance) then
        ui.showMessage(constants.Strings.BARTER_PC_TOO_POOR)
        return false
    end

    if state.currentBalance > 0 then
        local merchantGold = npc.type.getBarterGold(npc)
        if merchantGold < state.currentBalance then
            ui.showMessage(constants.Strings.BARTER_NPC_TOO_POOR)
            return false
        end
    end

    for _, entry in pairs(state.selling) do
        if ctx.stolenItems[entry.item.recordId] and ctx.stolenItems[entry.item.recordId][npc.recordId] then
            I.UI.setMode(nil)
            ui.showMessage(string.format(constants.Strings.THATS_MINE,
                entry.item.type.record(entry.item).name))
            core.sendGlobalEvent('IER_ConfiscateToOwner', {
                item = entry.item,
                count = entry.count,
                player = self,
                victim = npc,
                stolenMap = ctx.stolenItems,
            })
            return false
        end
    end

    local offerAccepted, skillGain = haggle(npc, state.currentBalance, state.currentMerchantOffer, ctx)
    if NPC.objectIsInstance(npc) then
        core.sendGlobalEvent('IER_ModDisposition', {
            target = npc,
            player = self,
            amount = offerAccepted
                and core.getGMST('iBarterSuccessDisposition')
                or core.getGMST('iBarterFailDisposition'),
        })
    end

    if not offerAccepted then
        ui.showMessage(constants.Strings.BARTER_REFUSED)
        return false
    end

    core.sendGlobalEvent('IER_FinalizeBarter', {
        player = self,
        merchant = npc,
        barterState = state,
        skillGain = skillGain,
    })

    ambient.playSound('item gold up')
    state.success = true

    if opts and opts.closeWindow == false then
        -- finalizeBarter does not clear the queues; on mode change windowManager does.
        -- Without the mode removal, reset them in place so the Trade window stops
        -- showing the moved items as offered.
        state.selling = {}
        state.buying = {}
        state.currentMerchantOffer = 0
        state.currentBalance = 0
    else
        I.UI.removeMode('Barter')
    end

    return true, skillGain
end

--- Predicted gold gain from selling count of item at npc: the per-item half of updateOffer's
--- selling loop (0.75 cap, NPC min). Incremental pricing for pre-commit knapsacks: price the
--- queue plus the candidate and subtract the existing offer.
---@param item openmw.Object
---@param count number
---@param npc openmw.Object? the module has no window, so the caller supplies the merchant
---@param ctx InventoryExtenderRedone.Context price override chain carrier
---@return number? nil when there is no merchant - 0 would read as "free item"
local function getSellOffer(item, count, npc, ctx)
    if not npc then
        return nil
    end
    return itemOffer(npc, item, count, false, ctx)
end

--- Predicted gold spent buying count of item at npc: the per-item half of updateOffer's
--- buying loop (0.75 cap floor via max).
---@param item openmw.Object
---@param count number
---@param npc openmw.Object? the merchant
---@param ctx InventoryExtenderRedone.Context price override chain carrier
---@return number? nil when there is no merchant - 0 would read as "free item"
local function getBuyOffer(item, count, npc, ctx)
    if not npc then
        return nil
    end
    return itemOffer(npc, item, count, true, ctx)
end

return {
    haggle = haggle,
    updateOffer = updateOffer,
    completeOffer = completeOffer,
    getSellOffer = getSellOffer,
    getBuyOffer = getBuyOffer,
    barterOfferEffect = barterOfferEffect,
    queueSell = queueSell,
    queueBuy = queueBuy,
    unqueueSell = unqueueSell,
    unqueueBuy = unqueueBuy,
    clearBarterOffer = clearBarterOffer,
}