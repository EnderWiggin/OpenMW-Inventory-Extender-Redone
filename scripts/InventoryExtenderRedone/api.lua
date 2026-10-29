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
local barterUtils = require('scripts.InventoryExtenderRedone.util.barter')
local L = require('scripts.InventoryExtenderRedone.util.logger').get 'API'

local Player = types.Player

local API = {}

API.VERSION = D.API

API.Constants = constants
API.Helpers = helpers
API.Roles = D.Roles
API.Modes = D.Modes

--- Which mode governs a window role right now, and that role's slots: the highest-priority
--- registered mode whose applies() matches, with its patches merged. nil when none applies.
API.resolveMode = modeApi.resolveMode

--- Turns a plain hook table in a lifecycle slot into a one-entry list, so hooks chain
--- instead of replacing each other. Entry lists and ops tables pass through untouched.
---@param value any? lifecycle slot as authored: entry list, ops table, or one plain hook table
---@param id string id for the entry the sugar produces
---@param asOp boolean? a patch's entry must come in as an add op, since a plain array replaces the slot
---@return any?
local function lifecycleSugar(value, id, asOp)
    if not value then return nil end
    if value[1] ~= nil or value.add or value.replace or value.remove then return value end
    local entry = {
        id = id,
        onOpened = value.onOpened,
        onClosing = value.onClosing,
        onClosed = value.onClosed,
    }
    return asOp and { add = { entry } } or { entry }
end

--- A patch's plain-array `columns` means "add these columns": it becomes `{ add = array }`, so a
--- patch always merges onto the window's resolved chain and cannot replace it by accident. An ops
--- table (add/replace/remove/set) passes through untouched.
---@param patch InventoryExtenderRedone.ModePatch
local function columnsSugar(patch)
    if not patch.roles then return end
    for _, spec in pairs(patch.roles) do
        local columns = spec.columns
        if columns and (columns[1] ~= nil or next(columns) == nil)
            and not columns.add and not columns.replace and not columns.remove and not columns.set
        then
            spec.columns = { add = columns }
        end
    end
end

function API.registerMode(mode)
    if not mode or not mode.key then return end
    -- a key colliding with a built-in has to go through patchMode
    if D.Modes[mode.key] then return end
    mode.lifecycle = lifecycleSugar(mode.lifecycle, mode.key)
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

--- Patch a built-in or custom mode with the same shape as Mode: list slots (sources/filters/
--- infoBar/lifecycle/columns) merge by id, every other slot overwrites. Patches apply at resolve
--- time, in reverse registration order.
---@param key InventoryExtenderRedone.ModeKey
---@param patch InventoryExtenderRedone.ModePatch
function API.patchMode(key, patch)
    if not key or not patch then return end
    local patches = windowManager.ctx.modePatches[key]
    if not patches then
        patches = {}
        windowManager.ctx.modePatches[key] = patches
    end
    -- an id-less patch gets a generated one, so its entry chains onto the built-in entry
    -- instead of replacing it
    patch.lifecycle = lifecycleSugar(patch.lifecycle, patch.id or (key .. '#' .. (#patches + 1)), true)
    columnsSugar(patch)
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

--- Registers a new window role (its geometry) and opens its window through UIToolkit. The only
--- way to get a new window id; mode specs never register windows.
---@param role string
---@param opts InventoryExtenderRedone.RoleOpts
function API.registerWindowRole(role, opts)
    windowManager:registerWindowRole(role, opts)
end

--- Opens the windows of a mode through UIToolkit only, without touching the engine UI mode.
--- No-op while all windows are disabled.
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

--- Set to true to temporarily disable IE windows.
--- NOTE: it won't bring back default windows - no windows will be shown instead.
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

---@return InventoryExtenderRedone.RowData? the row under the cursor in the window that owns scroll focus, nil when no window is focused or nothing is hovered
function API.getHoveredRow()
    return windowManager:getHoveredRow()
end

--- Barter API: barter-related methods, grouped so the interface root stays about windows,
--- modes and categories. Consumed as IER.Barter.getSellRow(item).
local Barter = {}
API.Barter = Barter

--- The row that feeds the sell side of an offer: the visible, enabled, not-yet-offered row for
--- item in the open Inventory window, while that window's mode is Barter. nil means "not
--- tradeable right now".
---@param item openmw.Object
---@return InventoryExtenderRedone.RowData?
function Barter.getSellRow(item)
    return windowManager:getSellRow(item)
end

--- The row that feeds the buy side of an offer: same query in the open Trade window.
---@param item openmw.Object
---@return InventoryExtenderRedone.RowData?
function Barter.getBuyRow(item)
    return windowManager:getBuyRow(item)
end

--- Add count units of row to the sell side of the offer, clamped to row.getCount(). Pass a row
--- from getSellRow.
---@param row InventoryExtenderRedone.RowData
---@param count number
function Barter.queueSell(row, count)
    barterUtils.queueSell(windowManager.ctx, row, count)
end

---@param row InventoryExtenderRedone.RowData
---@param count number
function Barter.queueBuy(row, count)
    barterUtils.queueBuy(windowManager.ctx, row, count)
end

--- Take count units of an offered row back out of the sell side; count omitted clears the
--- entry. Pass the offered (isBartered) row.
---@param row InventoryExtenderRedone.RowData
---@param count number? omitted clears the entry
function Barter.unqueueSell(row, count)
    barterUtils.unqueueSell(windowManager.ctx, row, count)
end

---@param row InventoryExtenderRedone.RowData
---@param count number? omitted clears the entry
function Barter.unqueueBuy(row, count)
    barterUtils.unqueueBuy(windowManager.ctx, row, count)
end

--- Empty the offer queues and zero the offer scalars, leaving any open window alone.
function Barter.clearBarterOffer()
    barterUtils.clearBarterOffer(windowManager.ctx)
end

--- Name the actors a barter runs between, so an offer can price against one merchant and move
--- items to and from another actor. pricing is the merchant (haggle, per-item offer, the barter
--- gold pool, disposition, stolen victim, sell destination); party is the item holder on the
--- player's side (sell source and buy destination); gold is the pocket a negative balance is
--- paid from and a positive one received into. Omitted party and gold mean the player; omitted
--- pricing means the last-known Trade merchant. An empty descriptor is not the same as clearing:
--- it still fills party and gold with the player. Does not refresh the windows.
---@param descriptor InventoryExtenderRedone.BarterPartner?
function Barter.setPartner(descriptor)
    barterUtils.setPartner(windowManager.ctx, descriptor)
end

--- The stored descriptor, or nil when none was set. Do not mutate what this returns: it is the
--- stored table, normalized when it was set.
---@return InventoryExtenderRedone.BarterPartner?
function Barter.getPartner()
    return windowManager.ctx.barterState.partner
end

--- Drop the descriptor, so the next barter uses vanilla actors. Does not refresh the windows.
function Barter.clearPartner()
    barterUtils.setPartner(windowManager.ctx, nil)
end

--- Commit the current offer queue: transfer items, adjust gold, apply mercantile gain.
--- opts.closeWindow defaults true (leaves the Barter UI mode); with false the queues are
--- cleared in place so an open Trade window shows an empty offer.
---@param opts table? { closeWindow = boolean? }
---@return boolean accepted
---@return number? skillGain
function Barter.offerBarter(opts)
    local merchant = windowManager.ctx.windowArgs.Trade
    if not merchant then
        L.warn('Barter.offerBarter: no known merchant, refusing')
        return false
    end
    return barterUtils.completeOffer(windowManager.ctx, opts)
end

--- Predicted gold gain from selling count of item at the last-known Trade merchant
--- (ctx.windowArgs.Trade: one merchant at a time).
---@param item openmw.Object
---@param count number
---@return number? nil when no merchant is known - 0 would read as "free item"
function Barter.getSellOffer(item, count)
    return barterUtils.getSellOffer(item, count, windowManager.ctx.windowArgs.Trade, windowManager.ctx)
end

--- Current offer balance in gold: what committing the queue now would net the player
--- (negative means spending). 0 when no trade has priced anything yet.
---@return number
function Barter.getBarterBalance()
    return windowManager.ctx.barterState.currentBalance or 0
end

--- Predicted gold spent buying count of item at the last-known Trade merchant.
---@param item openmw.Object
---@param count number
---@return number? nil when no merchant is known - 0 would read as "free item"
function Barter.getBuyOffer(item, count)
    return barterUtils.getBuyOffer(item, count, windowManager.ctx.windowArgs.Trade, windowManager.ctx)
end

--- Register a haggle modifier, consulted when an offer is committed (by the Trade window's Offer
--- button and by Barter.offerBarter). Handlers run in reverse registration order; each non-nil
--- return replaces the running chance and/or skillGain, so modifiers stack and the last
--- registered wins per field. The returned chance is clamped to [0, 100].
--- @param id string A unique identifier for the override
--- @param handler fun(npc:openmw.Object, playerOffer:number, merchantOffer:number, chance:number):chance:number?, skillGain:number? The override function
function Barter.registerHaggleOverride(id, handler)
    for _, existingHandler in ipairs(windowManager.ctx.overrides.haggle) do
        if existingHandler.id:lower() == id:lower() then
            existingHandler.handler = handler
            return
        end
    end
    table.insert(windowManager.ctx.overrides.haggle, { id = id, handler = handler })
end

--- Register a repricing modifier, consulted by the offer price, the price predictions and the
--- committed gold. Handlers run in reverse registration order; each non-nil return replaces the
--- running per-item price, so modifiers compose and the last registered wins. buying is true
--- when the player buys item from the merchant, false when selling to it. price is the final
--- per-item contribution magnitude; the returned price is clamped to [0, infinity).
--- @param id string A unique identifier for the override
--- @param handler fun(npc:openmw.Object, item:openmw.Object, count:number, buying:boolean, price:number):price:number? The override function
function Barter.registerPriceOverride(id, handler)
    for _, existingHandler in ipairs(windowManager.ctx.overrides.price) do
        if existingHandler.id:lower() == id:lower() then
            existingHandler.handler = handler
            return
        end
    end
    table.insert(windowManager.ctx.overrides.price, { id = id, handler = handler })
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

--- Register a function to handle the drop action (clicking a row while an item is being dragged) on item rows in the inventory.
--- By default, this ends the drag and transfers the dragged item into the window's target.
--- Handlers are called in reverse order of registration until one returns false, at which point the drop is not processed further and the item stays dragged. If all handlers return true, the default drop behavior is executed.
--- @param id string A unique identifier for the handler
--- @param handler InventoryExtenderRedone.RowDropHandler
function API.registerRowDropHandler(id, handler)
    for _, existingHandler in ipairs(windowManager.ctx.handlers.onRowDrop) do
        if existingHandler.id:lower() == id:lower() then
            existingHandler.handler = handler
            return
        end
    end
    table.insert(windowManager.ctx.handlers.onRowDrop, { id = id, handler = handler })
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
