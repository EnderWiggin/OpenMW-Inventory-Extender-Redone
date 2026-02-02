local core = require('openmw.core')
local self = require('openmw.self')
local util = require('openmw.util')
local ui = require('openmw.ui')
local types = require('openmw.types')
local storage = require('openmw.storage')
local input = require('openmw.input')
local I = require('openmw.interfaces')

local helpers = require('scripts.InventoryExtender.util.helpers')
local constants = require('scripts.InventoryExtender.util.constants')

local windowManager = require('scripts.InventoryExtender.ui.windowManager')
local configPlayer = require('scripts.InventoryExtender.config.player')

local l10n = core.l10n('InventoryExtender')

local API = {}

API.VERSION = 1

API.Constants = constants

API.Templates = {
    BASE = require('scripts.InventoryExtender.ui.templates.base'),
    MAGIC = require('scripts.InventoryExtender.ui.templates.magic'),
}

function API.show(windowName)
    windowManager.show(windowName)
end

function API.hide(windowName, force)
    windowManager.hide(windowName, force)
end

function API.getWindow(windowName)
    return windowManager.windows[windowName]
end

local lastCrimeLevel
local function checkCrimeLevel()
    local crimeLevel = types.Player.getCrimeLevel(self)
    if lastCrimeLevel and crimeLevel < lastCrimeLevel then
        core.sendGlobalEvent('MI_TryConfiscate', { player = self, stolenMap = windowManager.ctx.stolenItems })
    end
    
    lastCrimeLevel = crimeLevel
end

function API.onFrame()
    windowManager.onFrame()
    checkCrimeLevel()
end

function API.onMouseWheel(v, h)
    windowManager.onMouseWheel(v, h)
end

function API.update()
    windowManager.update()
end

function API.trackStat(statId, getter)
    windowManager.trackStat(statId, getter)
end

function API.untrackStat(statId)
    windowManager.untrackStat(statId)
end

function API.setStat(statId, value, forceUpdate)
    if forceUpdate or not helpers.tableEquals(value, windowManager.stats[statId]) then
        windowManager.changedStats[statId] = true
        windowManager.stats[statId] = value
        windowManager.updateTrackedSections()
    end
end

function API.getStat(statId)
    return windowManager.stats[statId]
end

function API.setDirty()
    windowManager.needsRedraw = true
end

function API.setDirtyDelayed()
    windowManager.needsRedrawDelayed = true
end

function API.getWindowElement()
    return windowManager.element
end

function API.setConsoleState(state)
    windowManager.ctx.isConsoleOpen = state
    windowManager.onUiModeChanged(I.UI.getMode(), I.UI.getMode(), windowManager.ctx.modeArgs[I.UI.getMode()])
end

function API.getConsoleState()
    return windowManager.ctx.isConsoleOpen
end

local categories = {}
function API.getCategories()
    return categories
end

function API.getCategory(key)
    for _, category in ipairs(categories) do
        if category.key:lower() == key:lower() then
            return category
        end
    end
    return nil
end

function API.registerCategory(category)
    for i, existingCategory in ipairs(categories) do
        if existingCategory.key:lower() == category.key:lower() then
            categories[i] = category
            return
        end
    end

    table.insert(categories, category)
end

function API.unregisterCategory(key)
    for i, existingCategory in ipairs(categories) do
        if existingCategory.key:lower() == key:lower() then
            table.remove(categories, i)
            return
        end
    end
end

-- Tooltip Modifiers
-- These are functions that take the base tooltip layout, make modifications, and return the modified layout
-- They are called in sequence when building tooltips
-- Signature: function(item, layout) -> layout
function API.registerTooltipModifier(id, modifier)
    for _, existingModifier in ipairs(windowManager.ctx.tooltipModifiers) do
        if existingModifier.id:lower() == id:lower() then
            existingModifier.modifier = modifier
            return
        end
    end
    table.insert(windowManager.ctx.tooltipModifiers, { id = id, modifier = modifier })
end

return {
    interfaceName = 'InventoryExtender',
    interface = API,
    engineHandlers = {
        onSave = function()
            return {
                stolenItems = windowManager.ctx.stolenItems,
                companionProfit = windowManager.ctx.companionProfit,
            }
        end,
        onLoad = function(data)
            if data then
                windowManager.ctx.stolenItems = data.stolenItems or {}
                windowManager.ctx.companionProfit = data.companionProfit or {}
            end
        end,
    },
    eventHandlers = {
        UiModeChanged = function(data)
            windowManager.onUiModeChanged(data.oldMode, data.newMode, data.arg)
            core.sendGlobalEvent('MI_UIModeChanged', { actor = self, oldMode = data.oldMode, newMode = data.newMode, arg = data.arg })
        end,
        MI_StoleItem = function(props)
            --print("Player stole item:", props.recordId, "count:", props.count, "victim:", props.victim)
            windowManager.ctx.stolenItems[props.recordId] = windowManager.ctx.stolenItems[props.recordId] or {}
            local id = props.victim.recordId or props.victim.factionId
            if id then
                windowManager.ctx.stolenItems[props.recordId][id] = (windowManager.ctx.stolenItems[props.recordId][id] or 0) + props.count 
            end
        end,
        MI_ItemsConfiscated = function(props)
            --print(helpers.deepPrint(props.stolenMap))
            windowManager.ctx.stolenItems = props.stolenMap or windowManager.ctx.stolenItems
        end,
        MI_Update = function()
            windowManager.update()
        end,
        MI_CompanionProfit = function(props)
            windowManager.ctx.companionProfit[props.companion.id] = props.profit
        end,
        MI_SetDraggingObject = function(props)
            local obj = props.obj
            if helpers.isGold(props.obj) then
                local targetInv = props.target.type.inventory(props.target)
                local foundGold = targetInv:find('gold_001')
                if foundGold then
                    obj = foundGold
                end
            end

            windowManager.ctx.dragAndDrop:setDraggingObject(obj)
        end,
        MI_BarterFinalized = function(props)
            I.SkillProgression.skillUsed('mercantile', {
                skillGain = props.skillGain,
                useType = I.SkillProgression.SKILL_USE_TYPES.Mercantile_Success
            })
        end,
    },
}