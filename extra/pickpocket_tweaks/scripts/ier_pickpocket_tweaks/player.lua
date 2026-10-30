---@omw-context player

local core    = require 'openmw.core'
local I       = require 'openmw.interfaces'
local types   = require 'openmw.types'
local async   = require 'openmw.async'
local storage = require 'openmw.storage'
local ui      = require 'openmw.ui'
local util    = require 'openmw.util'
local omwself = require 'openmw.self'

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

local Toolkit    = I.UIToolkit
local T          = Toolkit.Templates
local H          = require 'scripts.UIToolkit.helpers'
local ColumnItem = require 'scripts.UIToolkit.components.list_items.column_item'
local l10n       = core.l10n(D.L10N)


local closeSection  = storage.playerSection(D.CloseSection)
local stealSection  = storage.playerSection(D.StealSection)
local equippedSection = storage.playerSection(D.EquippedSection)
local visibilitySection = storage.playerSection(D.VisibilitySection)
local potionsSection = storage.playerSection(D.PotionsSection)
local plantSection = storage.playerSection(D.PlantSection)
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
    plantDirection = true,
    plantBase = D.PlantBase.default,
    plantValueAdd = D.PlantValueAdd.default,
    plantValueExp = D.PlantValueExp.default,
    plantValueMult = D.PlantValueMult.default,
    plantWeightMult = D.PlantWeightMult.default,
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

    stored = plantSection:asTable()
    settings.plantDirection = stored.b_PlantDirection ~= false
    settings.plantBase = stored.n_PlanBase or D.PlantBase.default
    settings.plantValueAdd = stored.n_PlanValueAdd or D.PlantValueAdd.default
    settings.plantValueExp = stored.n_PlanValueExp or D.PlantValueExp.default
    settings.plantValueMult = stored.n_PlanValueMult or D.PlantValueMult.default
    settings.plantWeightMult = stored.n_PlanWeightMult or D.PlantWeightMult.default

    stored = potionsSection:asTable()
    settings.showAllPotions = stored.b_ShowAllPotions == true
end
readSettings()
closeSection:subscribe(async:callback(readSettings))
stealSection:subscribe(async:callback(readSettings))
equippedSection:subscribe(async:callback(readSettings))
visibilitySection:subscribe(async:callback(readSettings))
potionsSection:subscribe(async:callback(readSettings))
plantSection:subscribe(async:callback(readSettings))


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

-- the plant roll: value + weight only, no potion-effect term; prices the single planted item
local function getPlantChance(item, count)
    local record = item.type.record(item)
    local difficulty = settings.plantBase
        + math.max(0, record.value * count + settings.plantValueAdd) ^ settings.plantValueExp
            * settings.plantValueMult
        + record.weight * count * settings.plantWeightMult
    return util.clamp(getSkillTerm(omwself) * settings.ownSkillMult - difficulty, 0, 100)
end

-- the session NPC: windowArgs is last-known, the targetId guard is what makes it sound
local function sessionTarget(ctx)
    local target = ctx.windowArgs.Container
    if not target or not ctx.pickpocket or ctx.pickpocket.targetId ~= target.id then
        return nil
    end
    return target
end

-- the PlantChance column: the plant roll's number for this row, blank when there is no live
-- session to plant into
local fontRatio = Toolkit.getTheme().Sizes.textNormal / 16

---@param value any
---@return string
local function formatChance(value)
    if value == nil or value == '' then return '' end
    if type(value) == 'number' then
        return H.addSeparators(H.roundToPlaces(value, 2)) .. '%'
    end
    return tostring(value)
end

---@type UIToolkit.ListItem.Column.Renderer
local function renderPlantChance(data, cfg, height)
    local value = data[cfg.id]
    if type(value) == 'function' then
        value = value()
    end
    ---@type openmw.ui.Layout
    local layout = {
        name = cfg.id,
        template = T.text(),
        props = {
            textAlignV = ui.ALIGNMENT.Center,
            textAlignH = cfg.arg and cfg.arg.textAlignH or nil,
            autoSize = false,
            textSize = cfg.arg and cfg.arg.textSize or nil,
            text = formatChance(value),
        },
        userData = { colorable = true },
    }
    ColumnItem.applySize(layout, cfg, height)
    return layout
end

---@type UIToolkit.ListItem.Column.Updater
local function updatePlantChance(part, data, cfg)
    local value = data[cfg.id]
    if type(value) == 'function' then
        value = value()
    end
    local new = formatChance(value)
    local props = H.props(part)
    if props.text == new then return false end
    props.text = new
    return true
end

---@type InventoryExtenderRedone.Mode.Column
local plantChanceColumn = {
    id = 'PlantChance',
    name = l10n('Column_PlantChance'),
    sort = { numeric = true },
    width = 60 * fontRatio,
    align = ui.ALIGNMENT.End,
    descending = true,
    render = renderPlantChance,
    update = updatePlantChance,
    arg = { textAlignH = ui.ALIGNMENT.End },
    editable = true,
}

-- the always-transfer model: during a session a row click never drags and never shows the
-- stack popup — the takeover owns the count (full stack out of the pockets, one item in).
-- It runs before the default bound-item and favorite guards, so it replicates both; the
-- steal roll and its failure resolution mirror the built-in pickpocketTake.
local function takeover(row, ctx, role)
    local session = ctx.pickpocket
    if not session or not session.active then return end
    local target = sessionTarget(ctx)
    if not target then return end

    if Helpers.isBoundItem(row.item) then
        ui.showMessage(core.getGMST('sContentsMessage1'))
        return false
    end

    if role == IER.Roles.Container then
        if ctx.favoriteItems[row.item.id] then return false end
        local chance = Pickpocket.getStealChance(row.item, row.getCount())
        if chance == nil then return end
        if math.random(100) > chance then
            session.resolved = true
            core.sendGlobalEvent('IER_CommitPickpocket', {
                player = omwself,
                target = target,
                victimAware = true,
            })
            I.UI.removeMode(IER.Modes.Container)
            return false
        end
        omwself:sendEvent('IER_PickpocketSuccess', { item = row.item, target = target })
        ctx.dragAndDrop:transferInto(row.item, omwself, target, row.getCount(),
            { target = target }, IER.Modes.Pickpocket)
        return false
    end

    if role == IER.Roles.Inventory and settings.plantDirection then
        if ctx.favoriteItems[row.item.id] then return false end
        if math.random(100) > getPlantChance(row.item, 1) then
            session.resolved = true
            I.UI.removeMode(IER.Modes.Container)
            core.sendGlobalEvent('IERPT_Assault', {
                player = omwself,
                target = target,
            })
            return false
        end
        ctx.dragAndDrop:transferInto(row.item, target, omwself, 1,
            { target = target }, IER.Modes.Container)
        return false
    end
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
    -- Container role left visible. The PlantChance column rides the same patch: it is the
    -- player's own window, so both belong to the Container spec's Inventory role.
    IER.patchMode(IER.Modes.Container, {
        id = D.PatchId,
        roles = {
            [IER.Roles.Inventory] = {
                filters = { add = { { id = D.PatchId .. '.PlantFilter', fn = isPlantCandidate } } },
                columns = { add = { plantChanceColumn } },
            },
        },
    })
    -- the column's data, lazy so only visible rows price the plant roll
    IER.registerRowDataModifier(D.PatchId, function(row, ctx)
        row.PlantChance = function()
            if not settings.plantDirection or not sessionTarget(ctx) then return nil end
            return getPlantChance(row.item, 1)
        end
    end)
    -- one closure on both lists: use/k_UseItem/swap behave like pickup during a session
    IER.registerRowPickupHandler(D.PatchId, takeover)
    IER.registerRowUseHandler(D.PatchId, takeover)
    -- apply on success: the planted potion has already landed in the NPC, so the engine's own
    -- use path makes it drink it — no moveInto needed
    Pickpocket.registerTransferHandler(D.PatchId, function(payload)
        if not payload.planted or not types.Potion.objectIsInstance(payload.item) then
            return
        end
        core.sendGlobalEvent('UseItem', { object = payload.item, actor = payload.target })
    end)
end

return {
    engineHandlers = {
        onInit = tryInit,
        onLoad = tryInit,
    },
}
