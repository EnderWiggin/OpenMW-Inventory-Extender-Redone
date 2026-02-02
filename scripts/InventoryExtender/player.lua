local I = require('openmw.interfaces')
local self = require('openmw.self')
local core = require('openmw.core')
local input = require('openmw.input')
local async = require('openmw.async')
local storage = require('openmw.storage')
local ui = require('openmw.ui')
local types = require('openmw.types')

local util = require('openmw.util')
local auxUtil = require('openmw_aux.util')
local v2 = util.vector2

local API = I.InventoryExtender

local configPlayer = require('scripts.InventoryExtender.config.player')
local helpers = require('scripts.InventoryExtender.util.helpers')

local l10n = core.l10n('InventoryExtender')

local function init()
    if not configPlayer.window.b_EnableMod then
        return
    end
    if not I.GamepadControls.isControllerMenusEnabled or not I.GamepadControls.isControllerMenusEnabled() then
        local overrides = {
            'Inventory',
            'Trade',
            'Container',
            'Companion',
        }
        for _, windowName in ipairs(overrides) do
            I.UI.registerWindow(windowName, function() API.show(windowName) end, function() API.hide(windowName) end)
        end
    elseif configPlayer.misc.b_ShowControllerWarning then
        storage.playerSection('Settings/InventoryExtender/5_Misc'):set('b_ShowControllerWarning', false)
        local msg = 'NOTICE:\nInventory Extender is not compatible with controller menus.\nThis message will only appear once.'
        if I.UI.showInteractiveMessage then -- OpenMW 0.50+
            I.UI.showInteractiveMessage(msg, {})
        else
            ui.showMessage(msg)
        end
    end
end

local defaultCategories = {
    {
        key = 'All',
    },
    {
        key = 'Weapon',
        filter = types.Weapon.objectIsInstance,
    },
    {
        key = 'Armor',
        filter = types.Armor.objectIsInstance,
    },
    {
        key = 'Clothing',
        filter = types.Clothing.objectIsInstance,
    },
    {
        key = 'Potion',
        filter = types.Potion.objectIsInstance,
    },
    {
        key = 'Ingredient',
        filter = types.Ingredient.objectIsInstance,
    },
    {
        key = 'Scroll',
        filter = function(item)
            if types.Book.objectIsInstance(item) then
                local record = types.Book.records[item.recordId]
                return record and record.enchant
            end
        end,
    },
    {
        key = 'Book',
        filter = function(item)
            if types.Book.objectIsInstance(item) then
                local record = types.Book.records[item.recordId]
                return record and not record.enchant
            end
        end,
    },
    {
        key = 'Key',
        filter = function(item)
            if types.Miscellaneous.objectIsInstance(item) then
                local record = types.Miscellaneous.records[item.recordId]
                return record and record.isKey
            end
        end,
    },
    {
        key = 'Tool',
        filter = function(item)
            return types.Lockpick.objectIsInstance(item) or
                   types.Probe.objectIsInstance(item) or
                   types.Light.objectIsInstance(item) or
                   types.Apparatus.objectIsInstance(item) or
                   types.Repair.objectIsInstance(item)
        end,
    },
    {
        key = 'Misc',
        filter = function(item)
            return types.Miscellaneous.objectIsInstance(item) and not types.Miscellaneous.records[item.recordId].isKey
        end,
    }
}

for _, category in ipairs(defaultCategories) do
    API.registerCategory{
        key = category.key,
        name = l10n('Category_' .. category.key),
        icon = 'icons/InventoryExtender/categories/' .. category.key .. '.dds',
        filter = category.filter,
    }
end

local wasConsolePressed, wasGameMenuPressed = false, false

input.registerTriggerHandler('Console', async:callback(function()
    if not API.getConsoleState() then
        API.setConsoleState(true)
        wasConsolePressed = true
    end
end))

return {
    engineHandlers = {
        onInit = init,
        onLoad = init,
        onFrame = function()
            API.onFrame()

            local consolePressed = input.isActionPressed(input.ACTION.Console)
            local gameMenuPressed = input.isActionPressed(input.ACTION.GameMenu)

            if API.getConsoleState() then
                if (consolePressed and not wasConsolePressed) or (gameMenuPressed and not wasGameMenuPressed) then
                    API.setConsoleState(false)
                end
            end

            wasConsolePressed = consolePressed
            wasGameMenuPressed = gameMenuPressed
        end,
        onMouseWheel = function(v, h)
            API.onMouseWheel(v, h)
        end,
    },
}