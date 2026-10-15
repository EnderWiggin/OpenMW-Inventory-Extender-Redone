---@omw-context player

local I = require('openmw.interfaces')
local core = require('openmw.core')
local input = require('openmw.input')
local async = require('openmw.async')
local storage = require('openmw.storage')
local ui = require('openmw.ui')
local types = require('openmw.types')
local util = require('openmw.util')

local API = I.InventoryExtenderRedone

local configPlayer = require('scripts.InventoryExtenderRedone.config.player')
local D = require('scripts.InventoryExtenderRedone.config.defaults')
local constants = require("scripts.InventoryExtenderRedone.util.constants")
local helpers = require("scripts.InventoryExtenderRedone.util.helpers")
local iconPack = require('scripts.InventoryExtenderRedone.util.iconPack')

local l10n = core.l10n('InventoryExtender')

local function isFavorited(item)
    local ctx = API.getContext and API.getContext()
    if not ctx or not ctx.favoriteItems or not item then
        return false
    end
    return ctx.favoriteItems[item.id] == true
end

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
            I.UI.registerWindow(windowName, function(arg) API.show(windowName, arg) end,
                function(arg) API.hide(windowName, arg) end)
        end
    elseif configPlayer.misc.b_ShowControllerWarning then
        storage.playerSection(D.Section.Misc):set('b_ShowControllerWarning', false)
        local msg =
        'NOTICE:\nInventory Extender is not compatible with controller menus.\nThis message will only appear once.'
        if I.UI.showInteractiveMessage then -- OpenMW 0.50+
            I.UI.showInteractiveMessage(msg, {})
        else
            ui.showMessage(msg)
        end
    end
end

local generalHiddenColumns = {
    Class = true,
    AR = true,
    Damage = true,
    Quality = true,
    Condition = true,
}

local noTypeHiddenColumns = {
    Type = true,
    Class = true,
    AR = true,
    Damage = true,
    Quality = true,
    Condition = true,
}

local defaultCategories = {
    {
        key = 'Favorites',
        filter = isFavorited,
        prepend = true,
        defaultSelected = false,
        hiddenColumns = generalHiddenColumns,
    },
    {
        key = 'All',
        hiddenColumns = generalHiddenColumns,
    },
    {
        key = 'Weapon',
        filter = types.Weapon.objectIsInstance,
        hiddenColumns = {
            Class = true,
            AR = true,
            Quality = true,
        },
    },
    {
        key = 'Armor',
        filter = types.Armor.objectIsInstance,
        hiddenColumns = {
            Damage = true,
            Quality = true,
        }
    },
    {
        key = 'Clothing',
        filter = types.Clothing.objectIsInstance,
        hiddenColumns = generalHiddenColumns,
    },
    {
        key = 'Potion',
        filter = types.Potion.objectIsInstance,
        hiddenColumns = noTypeHiddenColumns,
    },
    {
        key = 'Ingredient',
        filter = types.Ingredient.objectIsInstance,
        hiddenColumns = noTypeHiddenColumns,
    },
    {
        key = 'Scroll',
        filter = function(item)
            if types.Book.objectIsInstance(item) then
                local record = types.Book.records[item.recordId]
                return record and record.enchant
            end
        end,
        hiddenColumns = noTypeHiddenColumns,
    },
    {
        key = 'Book',
        filter = function(item)
            if types.Book.objectIsInstance(item) then
                local record = types.Book.records[item.recordId]
                return record and not record.enchant
            end
        end,
        hiddenColumns = noTypeHiddenColumns,
    },
    {
        key = 'Key',
        filter = function(item)
            if types.Miscellaneous.objectIsInstance(item) then
                local record = types.Miscellaneous.records[item.recordId]
                return record and record.isKey
            end
        end,
        hiddenColumns = noTypeHiddenColumns,
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
        hiddenColumns = {
            Class = true,
            AR = true,
            Damage = true,
        },
    },
    {
        key = 'Misc',
        filter = function(item)
            return types.Miscellaneous.objectIsInstance(item) and not types.Miscellaneous.records[item.recordId].isKey
        end,
        hiddenColumns = noTypeHiddenColumns,
    }
}

for _, category in ipairs(defaultCategories) do
    local categoryIconRelativePath = 'categories/' .. category.key:lower() .. '.dds'

    API.registerCategory {
        key = category.key,
        name = l10n('Category_' .. category.key),
        icon = iconPack.getPath(categoryIconRelativePath),
        iconPackRelativePath = categoryIconRelativePath,
        filter = category.filter,
        prepend = category.prepend,
        defaultSelected = category.defaultSelected,
        hiddenColumns = category.hiddenColumns,
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
    },
}
