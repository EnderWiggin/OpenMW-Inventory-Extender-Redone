---@omw-context player

local core    = require 'openmw.core'
local I       = require 'openmw.interfaces'
local types   = require 'openmw.types'
local async   = require 'openmw.async'
local storage = require 'openmw.storage'
local ui      = require 'openmw.ui'
local util    = require 'openmw.util'
local omwself = require 'openmw.self'

local Actor   = types.Actor
local NPC     = types.NPC
local IER     = I.InventoryExtenderRedone


if not IER then return end
local D          = require('scripts.ier_pickpocket_tweaks.config.defaults')
local L          = require('scripts.InventoryExtenderRedone.util.logger').get 'PickpocketTweaks'
local Pickpocket = IER.Pickpocket
local Helpers    = IER.Helpers


local Toolkit    = I.UIToolkit
local T          = Toolkit.Templates
local H          = require 'scripts.UIToolkit.helpers'
local ColumnItem = require 'scripts.UIToolkit.components.list_items.column_item'
local l10n       = core.l10n(D.L10N)


local general = storage.playerSection(D.Section.General)
local steal   = storage.playerSection(D.Section.Steal)
local plant   = storage.playerSection(D.Section.Plant)


---@class CFGGeneral
---@field closeSkillThreshold number
---@field equippedThreshold number
---@field visibleChanceThreshold number

---@class CFGSteal
---@field ownSkillMult number
---@field targetSkillMult number
---@field baseDifficulty number
---@field valueAdd number
---@field valueExp number
---@field valueMult number
---@field weightMult number
---@field equippedWeaponBonus number
---@field equippedJewelryBonus number
---@field equippedArmorBonus number
---@field merchantBonus number
---@field guardBonus number

---@class CFGPoison
---@field enabled boolean
---@field hideOther boolean
---@field ownSkillMult number
---@field targetSkillMult number
---@field baseDifficulty number
---@field weightMult number

---@type CFGGeneral
local cfgGeneral = general:asTable() --[@as CFGGeneral]]

---@type CFGSteal
local cfgSteal   = steal:asTable() --[@as CFGSteal]]

---@type CFGPoison
local cfgPoison  = plant:asTable() --[@as CFGPoison]]

general:subscribe(async:callback(function()
    cfgGeneral = general:asTable()
end))

steal:subscribe(async:callback(function()
    cfgSteal = steal:asTable()
end))

plant:subscribe(async:callback(function()
    cfgPoison = plant:asTable()
end))


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
        return cfgSteal.equippedWeaponBonus
    end
    if types.Clothing.objectIsInstance(item) then
        local recordType = item.type.record(item).type
        if recordType == types.Clothing.TYPE.Ring or recordType == types.Clothing.TYPE.Amulet then
            return cfgSteal.equippedJewelryBonus
        end
    end
    return cfgSteal.equippedArmorBonus
end

local function getStealCount(row)
    if Helpers.isGold(row.item) then return row.getCount() end
    return 1
end

local function getStealChance(player, target, item, count)
    local record = item.type.record(item)
    local value = util.clamp(record.value * count + cfgSteal.valueAdd, 5, 10000)
    local difficulty = cfgSteal.baseDifficulty
        --+ (math.max(0, record.value + cfgSteal.valueAdd) ^ cfgSteal.valueExp * cfgSteal.valueMult)
        + (math.log(value, 3) ^ cfgSteal.valueExp) * cfgSteal.valueMult
        + record.weight * cfgSteal.weightMult * count
        + getSkillTerm(target) * cfgSteal.targetSkillMult
    if Actor.hasEquipped(target, item) then
        if getSneak(player) < cfgGeneral.equippedThreshold then
            return 0
        end
        difficulty = difficulty + getEquippedBonus(item)
    end
    ---@type openmw.types.NpcRecord
    local targetRecord = target.type.record(target)
    local class = targetRecord.class
    if class == 'guard' or class == 'ordinator' then
        difficulty = difficulty + cfgSteal.guardBonus
    elseif targetRecord.servicesOffered.Barter then
        difficulty = difficulty + cfgSteal.merchantBonus
    end
    return util.round(getSkillTerm(player) * cfgSteal.ownSkillMult - difficulty)
end

-- pocket visibility is the Pickpocket mode's Container-role filters slot: replace the built-in
-- snapshot rule with a live deterministic one, the same chain number the column shows and the
-- roll runs against. No session: everything stays visible.
local function isVisibleToSteal(row, handler, ctx)
    local chance = Pickpocket.getStealChance(row.item, getStealCount(row))
    if chance == nil then return true end
    return chance >= cfgGeneral.visibleChanceThreshold
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

local function isVisibleToPlant(row)
    return not cfgPoison.hideOther or isHarmfulPotion(row.item)
end

-- the plant roll: value + weight only, no potion-effect term; prices the single planted item
local function getPlantChance(target, item)
    local record = item.type.record(item)

    local difficulty = cfgPoison.baseDifficulty
        + record.weight * cfgPoison.weightMult
        + getSkillTerm(target) * cfgPoison.targetSkillMult
    return util.round(util.clamp(getSkillTerm(omwself) * cfgPoison.ownSkillMult - difficulty, 0, 100))
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

    --TODO: favorite message
    if ctx.favoriteItems[row.item.id] then return false end

    if Helpers.isBoundItem(row.item) then
        ui.showMessage(core.getGMST('sContentsMessage1'))
        return false
    end

    if role == IER.Roles.Container then
        local count = getStealCount(row)
        local chance = Pickpocket.getStealChance(row.item, count)
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
        ctx.dragAndDrop:transferInto(row.item, omwself, target, count,
            { target = target }, IER.Modes.Pickpocket)
        return false
    end

    if role == IER.Roles.Inventory then
        if cfgPoison.enabled and math.random(100) > getPlantChance(target, row.item) then
            --failed to poison, report assault
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
        if getSneak(player) >= cfgGeneral.closeSkillThreshold then
            return 100
        end
        --TODO: use sliding scale from some min chance to 100 at threshold value
    end)
    Pickpocket.registerStealChance(D.PatchId, function(player, target, item, count, chance)
        if not Helpers.isGold(item) then count = 1 end
        return getStealChance(player, target, item, count)
    end)
    IER.patchMode(IER.Modes.Pickpocket, {
        id = D.PatchId,
        roles = {
            [IER.Roles.Container] = {
                filters = { replace = { { id = 'pickpocketVisibility', fn = isVisibleToSteal } } },
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
                filters = { add = { { id = D.PatchId .. '.PlantFilter', fn = isVisibleToPlant } } },
                columns = { add = { plantChanceColumn } },
            },
        },
    })
    -- the column's data, lazy so only visible rows price the plant roll
    IER.registerRowDataModifier(D.PatchId, function(row, ctx)
        row.PlantChance = function()
            if not cfgPoison.enabled then return nil end
            local target = sessionTarget(ctx)
            if not target then return nil end
            return getPlantChance(target, row.item)
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
