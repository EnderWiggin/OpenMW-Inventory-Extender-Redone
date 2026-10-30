---@omw-context player

local I       = require 'openmw.interfaces'
local types   = require 'openmw.types'
local async   = require 'openmw.async'
local storage = require 'openmw.storage'

local Actor = types.Actor
local NPC   = types.NPC
local D   = require('scripts.ier_pickpocket_tweaks.config.defaults')
local L   = require('scripts.InventoryExtenderRedone.util.logger').get 'PickpocketTweaks'

local IER = I.InventoryExtenderRedone
if not IER then return end
local Pickpocket = IER.Pickpocket
if not Pickpocket then return end
local Helpers = IER.Helpers
if not Helpers then return end


local closeSection = storage.playerSection(D.CloseSection)
local stealSection = storage.playerSection(D.StealSection)
local settings = {
    closeSkillThreshold = D.CloseSkill.default,
    ownSkillMult = D.OwnSkillMult.default,
    baseDifficulty = D.BaseDifficulty.default,
    valueAdd = D.ValueAdd.default,
    valueExp = D.ValueExp.default,
    valueMult = D.ValueMult.default,
    weightMult = D.WeightMult.default,
    targetSkillMult = D.TargetSkillMult.default,
}

local function readSettings()
    local stored = closeSection:asTable()
    settings.closeSkillThreshold = stored.n_CloseSkillThreshold or D.CloseSkill.default

    stored = stealSection:asTable()
    settings.ownSkillMult = stored.n_QLPPOwnSkillMult or D.OwnSkillMult.default
    settings.baseDifficulty = stored.n_QLPPBaseDifficulty or D.BaseDifficulty.default
    settings.valueAdd = stored.n_QLPPValueAdd or D.ValueAdd.default
    settings.valueExp = stored.n_QLPPValueExp or D.ValueExp.default
    settings.valueMult = stored.n_QLPPValueMult or D.ValueMult.default
    settings.weightMult = stored.n_QLPPWeightMult or D.WeightMult.default
    settings.targetSkillMult = stored.n_QLPPTargetSkillMult or D.TargetSkillMult.default
end
readSettings()
closeSection:subscribe(async:callback(readSettings))
stealSection:subscribe(async:callback(readSettings))


local function getSneak(actor)
    return NPC.stats.skills.sneak(actor).modified
end

local function getAgility(actor)
    return Actor.stats.attributes.agility(actor).modified
end

local function getLuck(actor)
    return Actor.stats.attributes.luck(actor).modified
end

-- the same skill+fatigue term feeds both sides: own skill and the target's contribution
local function getSkillTerm(actor)
    return (0.2 * getAgility(actor) + 0.1 * getLuck(actor) + getSneak(actor))
        * Helpers.getFatigueTerm(actor)
end

-- the QLPP difficulty model minus facing/attempts: price, weight and the target's skill make
-- difficulty, own skill makes chance; the chain clamps the result to [0, 100]. Gold runs the
-- same formula: a full gold stack is simply hard to steal, a small one stays easy
local function getStealChance(player, target, item, count)
    local record = item.type.record(item)
    local difficulty = settings.baseDifficulty
        + math.max(0, record.value * count + settings.valueAdd) ^ settings.valueExp * settings.valueMult
        + record.weight * count * settings.weightMult
        + getSkillTerm(target) * settings.targetSkillMult
    return getSkillTerm(player) * settings.ownSkillMult - difficulty
end

local function tryInit()
    L.debug('register chance handlers')
    Pickpocket.registerCloseChance(D.PatchId, function(player, target, session, chance)
        if getSneak(player) >= settings.closeSkillThreshold then
            return 100
        end
    end)
    Pickpocket.registerStealChance(D.PatchId, function(player, target, item, count, chance)
        return getStealChance(player, target, item, count)
    end)
end

return {
    engineHandlers = {
        onInit = tryInit,
        onLoad = tryInit,
    },
}
