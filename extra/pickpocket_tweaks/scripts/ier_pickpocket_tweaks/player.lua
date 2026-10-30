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


local closeSection  = storage.playerSection(D.CloseSection)
local stealSection  = storage.playerSection(D.StealSection)
local equippedSection = storage.playerSection(D.EquippedSection)
local visibilitySection = storage.playerSection(D.VisibilitySection)
local potionsSection = storage.playerSection(D.PotionsSection)
local settings = {
    closeSkillThreshold = D.CloseSkill.default,
    ownSkillMult = D.OwnSkillMult.default,
    baseDifficulty = D.BaseDifficulty.default,
    valueAdd = D.ValueAdd.default,
    valueExp = D.ValueExp.default,
    valueMult = D.ValueMult.default,
    weightMult = D.WeightMult.default,
    targetSkillMult = D.TargetSkillMult.default,
    visibleChanceThreshold = D.VisibleChance.default,
    equippedThreshold = D.EquippedThreshold.default,
    equippedWeaponBonus = D.EquippedWeaponBonus.default,
    equippedJewelryBonus = D.EquippedJewelryBonus.default,
    equippedArmorBonus = D.EquippedArmorBonus.default,
    showAllPotions = false,
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

    stored = equippedSection:asTable()
    settings.equippedThreshold = stored.n_EquippedSkillThreshold or D.EquippedThreshold.default
    settings.equippedWeaponBonus = stored.n_EquippedWeaponBonus or D.EquippedWeaponBonus.default
    settings.equippedJewelryBonus = stored.n_EquippedJewelryBonus or D.EquippedJewelryBonus.default
    settings.equippedArmorBonus = stored.n_EquippedArmorBonus or D.EquippedArmorBonus.default

    stored = visibilitySection:asTable()
    settings.visibleChanceThreshold = stored.n_VisibleChanceThreshold or D.VisibleChance.default

    stored = potionsSection:asTable()
    settings.showAllPotions = stored.b_ShowAllPotions == true
end
readSettings()
closeSection:subscribe(async:callback(readSettings))
stealSection:subscribe(async:callback(readSettings))
equippedSection:subscribe(async:callback(readSettings))
visibilitySection:subscribe(async:callback(readSettings))
potionsSection:subscribe(async:callback(readSettings))


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
local function getEquippedBonus(item)
    if types.Weapon.objectIsInstance(item) then
        return settings.equippedWeaponBonus
    end
    if types.Clothing.objectIsInstance(item) then
        local recordType = item.type.record(item).type
        if recordType == types.Clothing.TYPE.Ring or recordType == types.Clothing.TYPE.Amulet then
            return settings.equippedJewelryBonus
        end
    end
    return settings.equippedArmorBonus
end

local function getStealChance(player, target, item, count)
    local record = item.type.record(item)
    local difficulty = settings.baseDifficulty
        + math.max(0, record.value * count + settings.valueAdd) ^ settings.valueExp * settings.valueMult
        + record.weight * count * settings.weightMult
        + getSkillTerm(target) * settings.targetSkillMult
    if Actor.hasEquipped(target, item) then
        if getSneak(player) < settings.equippedThreshold then
            return 0
        end
        difficulty = difficulty + getEquippedBonus(item)
    end
    return getSkillTerm(player) * settings.ownSkillMult - difficulty
end

-- pocket visibility is the Pickpocket mode's Container-role filters slot: replace the built-in
-- snapshot rule with a live deterministic one, the same chain number the column shows and the
-- roll runs against. No session: everything stays visible.
local function isVisible(row, handler, ctx)
    local session = ctx.pickpocket
    if not session or not session.active then return true end
    local chance = Pickpocket.getStealChance(row.item, row.getCount())
    if chance == nil then return true end
    return chance >= settings.visibleChanceThreshold
end

-- during a live session the player's own window is governed by the Container spec's Inventory
-- role: narrow it to harmful potions so only plant candidates stay listed. The predicate
-- self-guards the session identity: outside a pickpocket session nothing is hidden.
local function isHarmfulPotion(item)
    if not types.Potion.objectIsInstance(item) then return false end
    local effects = item.type.record(item).effects
    for i = 1, #effects do
        local effect = effects[i]
        if effect and effect.effect.harmful then
            return true
        end
    end
    return false
end

local function isPlantCandidate(row, handler, ctx)
    local session = ctx.pickpocket
    local target = ctx.windowArgs.Container
    if not session or not session.active or not target or session.targetId ~= target.id then
        return true
    end
    if settings.showAllPotions then return true end
    return isHarmfulPotion(row.item)
end

local initialized = false

local function tryInit()
    if initialized then return end
    initialized = true

    L.debug('register chance handlers + visibility patches')
    Pickpocket.registerCloseChance(D.PatchId, function(player, target, session, chance)
        if getSneak(player) >= settings.closeSkillThreshold then
            return 100
        end
    end)
    Pickpocket.registerStealChance(D.PatchId, function(player, target, item, count, chance)
        return getStealChance(player, target, item, count)
    end)
    IER.patchMode(IER.Modes.Pickpocket, {
        id = D.PatchId,
        roles = {
            [IER.Roles.Container] = {
                filters = { replace = { { id = 'pickpocketVisibility', fn = isVisible } } },
            },
        },
    })
    -- add (not replace): CompoundFilter ANDs the named filters, this only narrows what the
    -- Container role left visible
    IER.patchMode(IER.Modes.Container, {
        id = D.PatchId,
        roles = {
            [IER.Roles.Inventory] = {
                filters = { add = { { id = D.PatchId .. '.PlantFilter', fn = isPlantCandidate } } },
            },
        },
    })
end

return {
    engineHandlers = {
        onInit = tryInit,
        onLoad = tryInit,
    },
}
