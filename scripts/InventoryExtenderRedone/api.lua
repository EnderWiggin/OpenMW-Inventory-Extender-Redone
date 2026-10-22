---@omw-context player

local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local constants = require('scripts.InventoryExtenderRedone.util.constants')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

local windowManager = require('scripts.InventoryExtenderRedone.ui.windowManager')
local modeApi = require('scripts.InventoryExtenderRedone.toolkit.mode')
local L = require('scripts.InventoryExtenderRedone.util.logger').get 'API'

local Player = types.Player

local API = {}

API.VERSION = D.API

API.Constants = constants
API.Helpers = helpers
API.Roles = D.Roles
API.Modes = D.Modes

--- Which mode governs a window role right now: applies() + priority winner, patches merged.
--- Returns the fully merged mode and that role's slots, or nil when no registered mode applies.
--- The mode key is the value of handler.mode; the second return is what the handler snapshots
--- into its slots at open.
API.resolveMode = modeApi.resolveMode

--- Mode registry: the public surface over ctx.modes / ctx.modePatches. Built-in specs live
--- in toolkit/mode.lua Mode.Builtins and are never stored in ctx; a custom mode registers a
--- spec, a patch merges into a built-in or custom spec at resolve time.
function API.registerMode(mode)
    if not mode or not mode.key then return end
    -- a key that collides with a built-in must go through patchMode, not replace the spec
    if D.Modes[mode.key] then return end
    windowManager.ctx.modes[mode.key] = mode
end

function API.unregisterMode(key)
    windowManager.ctx.modes[key] = nil
end

---@param key InventoryExtenderRedone.ModeKey
---@return InventoryExtenderRedone.Mode? the spec as registered (built-in or custom), not the merged one
function API.getMode(key)
    return modeApi.Builtins[key] or windowManager.ctx.modes[key]
end

---@return InventoryExtenderRedone.Mode[] built-in and custom specs
function API.getModes()
    local list = {}
    for _, spec in pairs(modeApi.Builtins) do list[#list + 1] = spec end
    for _, spec in pairs(windowManager.ctx.modes) do list[#list + 1] = spec end
    return list
end

--- Patch a built-in or custom mode. The patch has the same shape as Mode; list slots
--- (sources/filters/infoBar) merge by id, every other slot overwrites. Patches apply at
--- resolve time in reverse registration order, so a mid-session patch affects the next open,
--- not an already-open window's snapshot.
---@param key InventoryExtenderRedone.ModeKey
---@param patch InventoryExtenderRedone.ModePatch
function API.patchMode(key, patch)
    if not key or not patch then return end
    local patches = windowManager.ctx.modePatches[key]
    if not patches then
        patches = {}
        windowManager.ctx.modePatches[key] = patches
    end
    patches[#patches + 1] = patch
end

---@param key InventoryExtenderRedone.ModeKey
---@param id string the patch's id given at patchMode
function API.unpatchMode(key, id)
    local patches = windowManager.ctx.modePatches[key]
    if not patches then return end
    for i = #patches, 1, -1 do
        if patches[i].id == id then
            table.remove(patches, i)
            return
        end
    end
end

--- The only way to get a new window id (decision 1): mode specs stay pure behavior and never
--- register windows, so a new role comes through here with its geometry.
---@param role string
---@param opts InventoryExtenderRedone.RoleOpts
function API.registerWindowRole(role, opts)
    windowManager:registerWindowRole(role, opts)
end

--- Purely IER-side (decision 10): opens the mode's role windows through UIToolkit only, never
--- I.UI.setMode/addMode. The mode governs each window through its applies(); openMode forces the
--- open, not the mode onto a window whose applies does not match the arg. No-op while disabled.
---@param key InventoryExtenderRedone.ModeKey
---@param arg any?
function API.openMode(key, arg)
    if API.allWindowsDisabled then return end
    windowManager:openMode(key, arg)
end

---@param key InventoryExtenderRedone.ModeKey
---@param arg any?
function API.closeMode(key, arg)
    windowManager:closeMode(key, arg)
end

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

---@param windowName InventoryExtenderRedone.Role
---@return IER.Inventory? handler the window's handler, nil if the window is not open
function API.getWindow(windowName)
    return windowManager:getWindow(windowName)
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
    local crimeLevel = Player.getCrimeLevel(self)
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

--- Register a function to handle use actions (default: R, or left-click if swapped) on item rows in the inventory.
--- By default, this equips or uses the item. In barter, the use action is routed to the pick-up handler.
--- Handlers are called in reverse order of registration until one returns false, at which point the activation is not processed further. If all handlers return true, the default activation behavior is executed.
--- @param id string A unique identifier for the handler
--- @param handler fun(row: table, ctx: table, role: string):boolean? The handler function
function API.registerRowUseHandler(id, handler)
    for _, existingHandler in ipairs(windowManager.ctx.handlers.onRowUse) do
        if existingHandler.id:lower() == id:lower() then
            existingHandler.handler = handler
            return
        end
    end
    table.insert(windowManager.ctx.handlers.onRowUse, { id = id, handler = handler })
end

--- Register a function to handle pick-up actions (left-click, unless swapped) on item rows in the inventory.
--- By default, this picks up the item or drops/transfers it if Alt is held. In barter, it adds/removes the item from the current barter offer.
--- Handlers are called in reverse order of registration until one returns false, at which point the click is not processed further. If all handlers return true, the default click behavior is executed.
--- @param id string A unique identifier for the handler
--- @param handler fun(row: table, ctx: table, role: string):boolean? The handler function
function API.registerRowPickupHandler(id, handler)
    for _, existingHandler in ipairs(windowManager.ctx.handlers.onRowPickup) do
        if existingHandler.id:lower() == id:lower() then
            existingHandler.handler = handler
            return
        end
    end
    table.insert(windowManager.ctx.handlers.onRowPickup, { id = id, handler = handler })
end

--TODO: registerRowDropHandler(id, fn(row, draggedItem, ctx, role)) is a PLANNED FUTURE addition, not
--      yet implemented. The drop/transfer action belongs on the Actions axis (Mode.Actions.pickup.transfer);
--      design and implement it when we plan the drop handler. AGENTS.md lists it as future API.

--- Register a function to modify row data
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

--- Register a function to provide row badges
--- @param id string A unique identifier for the handler
--- @param provider InventoryExtenderRedone.RowBadgeProvider The provider function. Must return icon path with optional color, or nil if no need for a badge.
function API.registerRowBadge(id, provider)
    local badges = windowManager.ctx.modifiers.badge
    id = id:lower()
    for i = 1, #badges do
        local existing = badges[i]
        if existing.id == id then
            existing.provider = provider
            return
        end
    end
    table.insert(badges, { id = id, provider = provider })
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
        L.info('UiModeChanged', data.oldMode, data.newMode)
        windowManager:onUiModeChanged(data.oldMode, data.newMode, data.arg)
        core.sendGlobalEvent('IER_UIModeChanged',
            { actor = self, oldMode = data.oldMode, newMode = data.newMode, arg = data.arg })
    end,
    IER_StoleItem = function(props)
        local id = props.victim.recordId or props.victim.factionId
        L.info('IER_StoleItem', props.recordId, props.count, id)
        windowManager.ctx.stolenItems[props.recordId] = windowManager.ctx.stolenItems[props.recordId] or {}
        if id then
            windowManager.ctx.stolenItems[props.recordId][id] = (windowManager.ctx.stolenItems[props.recordId][id] or 0) +
                props.count
        end
    end,
    IER_ItemsConfiscated = function(props)
        L.info('IER_ItemsConfiscated')
        windowManager.ctx.stolenItems = props.stolenMap or windowManager.ctx.stolenItems
    end,
    IER_Update = function()
        -- observability: the single refresh trigger for all windows; a refresh gap between
        -- an item change and the next window update explains a stale-table probe failure
        L.debug('IER_Update')
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
            L.debug('IER_SetDraggingObject: gold remap', props.obj.id, obj and obj.id)
        end
        -- observability: the player-side landing of the drag chain; the matching DnD
        -- setDraggingObject line is what the probe waits for
        L.info('IER_SetDraggingObject', obj and obj.id, props.resetMode)

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
        L.debug('IER_ContainerVariable', data.key, data.value)
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
