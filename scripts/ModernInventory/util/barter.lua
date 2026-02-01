local types = require('openmw.types')
local util = require('openmw.util')
local self = require('openmw.self')

local helpers = require('scripts.InventoryExtender.util.helpers')

local configGlobal = require('scripts.InventoryExtender.config.global')

local function barterOffer(npc, basePrice, buying)
    if types.Creature.objectIsInstance(npc) then return basePrice end

    local disposition = util.clamp(npc.type.getDisposition(npc, self), 0, 100)
    local a = math.min(self.type.stats.skills.mercantile(self).modified, 100)
    local b = math.min(0.1 * self.type.stats.attributes.luck(self).modified, 10)
    local c = math.min(0.2 * self.type.stats.attributes.personality(self).modified, 10)
    local d = math.min(npc.type.stats.skills.mercantile(npc).modified, 100)
    local e = math.min(0.1 * npc.type.stats.attributes.luck(npc).modified, 10)
    local f = math.min(0.2 * npc.type.stats.attributes.personality(npc).modified, 10)

    local pcTerm = (disposition - 50 + a + b + c) * helpers.getFatigueTerm(self)
    local npcTerm = (d + e + f) * helpers.getFatigueTerm(npc)

    local buyTerm = 0.01 * (100 - 0.5 * (pcTerm - npcTerm))
    local sellTerm = 0.01 * (50 - 0.5 * (npcTerm - pcTerm))

    local x
    if buying then
        x = buyTerm
    else
        x = math.min(buyTerm, sellTerm)
    end

    local offerPrice
    if x < 1 then
        offerPrice = math.modf(x * basePrice)
    else
        offerPrice = basePrice + math.modf((x - 1) * basePrice)
    end

    return math.max(1, offerPrice)
end

local function getAdjustedPrice(npc, item, count, buying)
    local basePrice = item.type.record(item).value

    local itemData = item.type.itemData(item)
    local itemRecord = item.type.record(item)

    local x
    if types.Weapon.objectIsInstance(item) or types.Armor.objectIsInstance(item) then
        local condition = itemData.condition or 0
        local maxCondition = itemRecord.health
        x = basePrice * (condition / maxCondition)
    elseif types.Lockpick.objectIsInstance(item) or types.Probe.objectIsInstance(item) or types.Repair.objectIsInstance(item) then
        local uses = itemData.condition or 0
        local maxUses = itemRecord.maxCondition
        x = basePrice * (uses / maxUses)
    elseif itemData.soul then
        x = helpers.getItemValue(item)
    else
        x = basePrice
    end

    if buying then
        return -barterOffer(npc, x * count, true)
    else
        return barterOffer(npc, x * count, false)
    end
end

local function getHaggleResult(npc, npcOffer, playerOffer)
    if playerOffer <= npcOffer then
        return true
    end

    if types.Creature.objectIsInstance(npc) then
        return false
    end

    local a = math.abs(npcOffer)
    local b = math.abs(playerOffer)
end