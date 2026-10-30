---@omw-context player
local core = require('openmw.core')
local I = require('openmw.interfaces')
local types = require('openmw.types')
local util = require('openmw.util')

local helpers = require('scripts.InventoryExtenderRedone.util.helpers')

local NPC = types.NPC
local Actor = types.Actor
local Item = types.Item
local iPickMinChance = core.getGMST('iPickMinChance')
local iPickMaxChance = core.getGMST('iPickMaxChance')

local Pickpocket = {}

local function getSneak(actor)
    return NPC.stats.skills.sneak(actor).modified
end

local function getAgility(actor)
    return Actor.stats.attributes.agility(actor).modified
end

local function getLuck(actor)
    return Actor.stats.attributes.luck(actor).modified
end

local function getChance(player, target, valueTerm)
    local pcSneak = getSneak(player)
    local x = (0.2 * getAgility(player) + 0.1 * getLuck(player) + pcSneak) * helpers.getFatigueTerm(player)
    local y = (valueTerm + getSneak(target) + 0.2 * getAgility(target) + 0.1 * getLuck(target)) * helpers.getFatigueTerm(target)
    local t = x - y + x

    local minChance = pcSneak / iPickMinChance
    if t < minChance then
        return math.max(0, math.floor(minChance))
    end

    return math.max(0, math.floor(math.min(iPickMaxChance, t)))
end

function Pickpocket.isTarget(target)
    return target ~= nil and NPC.objectIsInstance(target) and not Actor.isDead(target)
end

function Pickpocket.createSession(player, target)
    local visibleItems = {}
    local pcSneak = getSneak(player)

    for _, item in ipairs(target.type.inventory(target):getAll()) do
        if Item.isCarriable(item) and not target.type.hasEquipped(target, item) and math.random(100) <= pcSneak then
            visibleItems[item.id] = true
        end
    end

    return {
        active = true,
        resolved = false,
        targetId = target.id,
        visibleItems = visibleItems,
    }
end

function Pickpocket.isVisible(session, item)
    return session == nil or not session.active or session.visibleItems[item.id] == true
end

-- the steal chance for one stack: the same number rollTake rolls against, exposed without the
-- roll so the pickpocket window can show it as a column. The registered steal-chance chain runs
-- here, so the displayed chance and the actual roll agree: handlers receive the running chance
-- and each non-nil return replaces it, clamped to [0, 100]
function Pickpocket.getStealChance(player, target, item, stackCount)
    local stackValue = item.type.record(item).value * stackCount
    local valueTerm = 10 * core.getGMST('fPickPocketMod') * stackValue
    local chance = getChance(player, target, valueTerm)

    local overrides = I.InventoryExtenderRedone.getContext().overrides.stealChance
    for i = #overrides, 1, -1 do
        local newChance = overrides[i].handler(player, target, item, stackCount, chance)
        if newChance ~= nil then
            chance = util.clamp(newChance, 0, 100)
        end
    end
    return chance
end

function Pickpocket.rollTake(player, target, item, stackCount)
    local chance = Pickpocket.getStealChance(player, target, item, stackCount)
    return math.random(100) <= chance, chance
end

-- the caught-on-close check: the vanilla sneak number is handed to the registered close-chance
-- chain, whose result the same default roll runs against, so a mod retunes the odds rather than
-- replacing the roll
function Pickpocket.rollClose(player, target)
    local chance = getChance(player, target, 0)

    local ctx = I.InventoryExtenderRedone.getContext()
    local overrides = ctx.overrides.closeChance
    for i = #overrides, 1, -1 do
        local newChance = overrides[i].handler(player, target, ctx.pickpocket, chance)
        if newChance ~= nil then
            chance = util.clamp(newChance, 0, 100)
        end
    end

    return math.random(100) <= chance, chance
end

return Pickpocket