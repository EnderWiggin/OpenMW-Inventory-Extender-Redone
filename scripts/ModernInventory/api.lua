local core = require('openmw.core')
local self = require('openmw.self')
local util = require('openmw.util')
local ui = require('openmw.ui')
local types = require('openmw.types')
local storage = require('openmw.storage')
local input = require('openmw.input')
local I = require('openmw.interfaces')

local helpers = require('scripts.ModernInventory.util.helpers')
local constants = require('scripts.ModernInventory.util.constants')

local windowManager = require('scripts.ModernInventory.ui.windowManager')
local configPlayer = require('scripts.ModernInventory.config.player')

local l10n = core.l10n('ModernInventory')

local API = {}

API.VERSION = 1

API.Constants = constants

API.Templates = {
    BASE = require('scripts.ModernInventory.ui.templates.base'),
    MAGIC = require('scripts.ModernInventory.ui.templates.magic'),
}

API.TooltipBuilders = {
    TEXT = function(params)
        return API.Templates.MAGIC.tooltip(4, ui.content {
            {
                template = API.Templates.BASE.textParagraph,
                props = {
                    size = util.vector2(params.width or 300, 0),
                    text = params.text or '',
                    autoSize = true,
                }
            }
        })
    end,
    ITEM = function(item)
        return API.Templates.MAGIC.itemTooltip(item)
    end,
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

function API.onFrame()
    windowManager.onFrame()
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
    windowManager.onUiModeChanged(I.UI.getMode(), I.UI.getMode(), nil)
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

return {
    interfaceName = 'ModernInventory',
    interface = API,
    eventHandlers = {
        UiModeChanged = function(data)
            windowManager.onUiModeChanged(data.oldMode, data.newMode, data.arg)
        end,
        MI_Update = function()
            windowManager.update()
        end,
    },
}