---@omw-context player

local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local constants = require('scripts.InventoryExtenderRedone.util.constants')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

local windowManager = require('scripts.InventoryExtenderRedone.ui.windowManager')

local API = {}

API.VERSION = D.API

API.Constants = constants
API.Helpers = helpers

API.allWindowsDisabled = false

---Set to true to temporarily disable IE windows
---NOTE: it won't bring back default windows - no windows will be shown instead
--- Added on request of Quick Loot mod to temporarily disable UI when scripted containers/corpses are automatically activated
function API.disableAllWindows(value)
    API.allWindowsDisabled = value
end

function API.show(windowName, arg)
    if API.allWindowsDisabled then return end
    windowManager:show(windowName, arg)
end

function API.hide(windowName, arg, force)
    windowManager:hide(windowName, arg, force)
end

---@param apply fun(handler:IER.Inventory, wnd:UIToolkit.Window)
function API.forEachOpenWindow(apply)
    return windowManager:forEachOpenWindow(apply)
end

function API.getContext()
    return windowManager.ctx
end

function API.getDraggingObject()
    return windowManager.ctx.dragAndDrop.draggingObject
end

local lastCrimeLevel
local function checkCrimeLevel()
    local crimeLevel = types.Player.getCrimeLevel(self)
    if lastCrimeLevel and crimeLevel < lastCrimeLevel then
        core.sendGlobalEvent('IER_TryConfiscate', { player = self, stolenMap = windowManager.ctx.stolenItems })
    end

    lastCrimeLevel = crimeLevel
end

function API.onFrame()
    windowManager:onFrame()
    checkCrimeLevel()
end

function API.update()
    windowManager:update()
end

function API.setConsoleState(state)
    windowManager.ctx.isConsoleOpen = state
    windowManager.ctx.dragAndDrop.lastHoveredObject = nil
end

function API.getConsoleState()
    return windowManager.ctx.isConsoleOpen
end

local categories = {}
local categoriesChanged = false
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
            table.remove(categories, i)
            break
        end
    end
    categoriesChanged = true

    if category.prepend then
        table.insert(categories, 1, category)
    else
        table.insert(categories, category)
    end
end

function API.unregisterCategory(key)
    for i, existingCategory in ipairs(categories) do
        if existingCategory.key:lower() == key:lower() then
            table.remove(categories, i)
            return
        end
    end
    categoriesChanged = true
end

--- Register a function to override the equipped status of items in the inventory.
--- Handlers are called in reverse order of registration until one returns a non-nil value, at which point that value is used as the result.
--- If no handlers return a non-nil value, the default value is used.
--- @param id string A unique identifier for the override
--- @param handler fun(item: GameObject, actor: Actor):boolean|nil The override function
function API.registerEquippedOverride(id, handler)
    for _, existingHandler in ipairs(windowManager.ctx.overrides.equipped) do
        if existingHandler.id:lower() == id:lower() then
            existingHandler.handler = handler
            return
        end
    end
    table.insert(windowManager.ctx.overrides.equipped, { id = id, handler = handler })
end

--- Register a function to handle use actions (left-click, unless swapped) on item rows in the inventory.
--- By default, this equips or uses the item. In barter, it adds/removes the item from the current barter offer.
--- Handlers are called in reverse order of registration until one returns false, at which point the click is not processed further. If all handlers return true, the default click behavior is executed.
--- @param id string A unique identifier for the handler
--- @param handler fun(row: table, ctx: table, windowType: string):boolean? The handler function
function API.registerRowUseHandler(id, handler)
    for _, existingHandler in ipairs(windowManager.ctx.handlers.onRowUse) do
        if existingHandler.id:lower() == id:lower() then
            existingHandler.handler = handler
            return
        end
    end
    table.insert(windowManager.ctx.handlers.onRowUse, { id = id, handler = handler })
end

--- Register a function to handle pick-up actions (default: R, or left-click if swapped) on item rows in the inventory.
--- By default, this picks up the item or drops/transfers it if Alt is held. In barter, it is routed to the "use" handler.
--- Handlers are called in reverse order of registration until one returns false, at which point the activation is not processed further. If all handlers return true, the default activation behavior is executed.
--- @param id string A unique identifier for the handler
--- @param handler fun(row: table, ctx: table, windowType: string):boolean? The handler function
function API.registerRowPickupHandler(id, handler)
    for _, existingHandler in ipairs(windowManager.ctx.handlers.onRowPickup) do
        if existingHandler.id:lower() == id:lower() then
            existingHandler.handler = handler
            return
        end
    end
    table.insert(windowManager.ctx.handlers.onRowPickup, { id = id, handler = handler })
end

--- Register a function to modify row data
--- Handlers are called in reverse order of registration.
--- @param id string A unique identifier for the handler
--- @param modifier InventoryExtenderRedone.RowDataModifier The modifier function
function API.registerRowDataModifier(id, modifier)
    local modifiers = windowManager.ctx.modifiers.data
    id = id:lower()
    for i = 1, #modifiers do
        local existing = modifiers[i]
        if existing.id == id then
            existing.modifier = modifier
            return
        end
    end
    table.insert(modifiers, { id = id, modifier = modifier })
end

---@param itemOrId string|openmw.Object
function API.isFavorite(itemOrId)
    if not itemOrId then return false end
    local ctx = windowManager.ctx
    local id
    if type(itemOrId) == 'string' then
        id = itemOrId
    else
        id = itemOrId.id
    end
    return ctx.favoriteItems[id] == true
end

local eventHandlers = {
    UiModeChanged = function(data)
        windowManager:onUiModeChanged(data.oldMode, data.newMode, data.arg)
        core.sendGlobalEvent('IER_UIModeChanged',
            { actor = self, oldMode = data.oldMode, newMode = data.newMode, arg = data.arg })
    end,
    IER_StoleItem = function(props)
        windowManager.ctx.stolenItems[props.recordId] = windowManager.ctx.stolenItems[props.recordId] or {}
        local id = props.victim.recordId or props.victim.factionId
        if id then
            windowManager.ctx.stolenItems[props.recordId][id] = (windowManager.ctx.stolenItems[props.recordId][id] or 0) +
                props.count
        end
    end,
    IER_ItemsConfiscated = function(props)
        --print(helpers.deepPrint(props.stolenMap))
        windowManager.ctx.stolenItems = props.stolenMap or windowManager.ctx.stolenItems
    end,
    IER_Update = function()
        windowManager:update()
    end,
    IER_CompanionProfit = function(props)
        windowManager.ctx.companionProfit[props.companion.id] = props.profit
    end,
    IER_SetDraggingObject = function(props)
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
    IER_BarterFinalized = function(props)
        if not props.skillGain or props.skillGain <= 0 then return end
        I.SkillProgression.skillUsed('mercantile', {
            scale = props.skillGain,
            useType = I.SkillProgression.SKILL_USE_TYPES.Mercantile_Success
        })
    end,
    IER_PickpocketSuccess = function()
        I.SkillProgression.skillUsed('sneak', {
            useType = I.SkillProgression.SKILL_USE_TYPES.Sneak_PickPocket
        })
    end,
    IER_ContainerVariable = function(data)
        windowManager.ctx.containerVariables[data.key] = data.value
        self:sendEvent('IER_Update')
    end,
}

require 'scripts.InventoryExtenderRedone.interop.utk_tooltips'

return {
    interfaceName = 'InventoryExtenderRedone',
    interface = API,
    engineHandlers = {
        onSave = function()
            local ctx = windowManager.ctx
            return {
                stolenItems = ctx.stolenItems,
                favoriteItems = ctx.favoriteItems,
                favoriteRevision = ctx.favoriteRevision,
                companionProfit = ctx.companionProfit,
                imported_ie_api = ctx.imported_ie_api,
            }
        end,
        onLoad = function(data)
            if data then
                local ctx = windowManager.ctx
                ctx.stolenItems = data.stolenItems or {}
                ctx.favoriteItems = data.favoriteItems or {}
                ctx.favoriteRevision = data.favoriteRevision or 0
                ctx.companionProfit = data.companionProfit or {}
                if data.imported_ie_api then
                    ctx.imported_ie_api = true
                end
            end
            windowManager:init()
        end,
        onInit = function()
            windowManager:init()
        end,
        onControllerButtonPress = function(id)
            windowManager:onControllerButtonPress(id)
        end,
        onControllerButtonRelease = function(id)
            windowManager:onControllerButtonRelease(id)
        end,
        onMouseButtonPress = function(button)
            windowManager:onMouseButtonPress(button)
        end,
        onMouseButtonRelease = function(button)
            windowManager:onMouseButtonRelease(button)
        end,
    },
    eventHandlers = eventHandlers,
}
