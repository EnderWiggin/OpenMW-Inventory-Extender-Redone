---@omw-context player

local I = require('openmw.interfaces')
local async = require('openmw.async')
local input = require('openmw.input')
local omwself = require('openmw.self')


local Toolkit = I.UIToolkit
local Manager = Toolkit.WindowManager


local configPlayer = require('scripts.InventoryExtenderRedone.config.player')
local D = require('scripts.InventoryExtenderRedone.config.defaults')
local RoleRegistry = require('scripts.InventoryExtenderRedone.ui.roles')
local Mode = require('scripts.InventoryExtenderRedone.toolkit.mode')
local L = require('scripts.InventoryExtenderRedone.util.logger').get 'WM'

local DragAndDrop = require('scripts.InventoryExtenderRedone.ui.dragAndDrop')


local InvHandler = require 'scripts.InventoryExtenderRedone.toolkit.inventory'


local WindowManager = {}

---@type InventoryExtenderRedone.Context
WindowManager.ctx = {
    overrides = {
        equipped = {},
        haggle = {},
        price = {},
    },
    handlers = {
        onRowUse = {},
        onRowPickup = {},
    },
    modifiers = {
        data = {},
        badge = {},
    },
    -- custom modes and id-keyed patches registered by other mods
    modes = {},
    modePatches = {},
    isConsoleOpen = false,
    dragAndDrop = DragAndDrop,
    windowArgs = {},
    stolenItems = {},
    favoriteItems = {},
    favoriteRevision = 0,
    barterState = {
        selling = {},
        buying = {},
        currentMerchantOffer = 0,
        currentBalance = 0,
    },
    companionProfit = {},
    pickpocket = nil,
    containerVariables = {},
}

---@param role InventoryExtenderRedone.Role
---@return string windowId id in UIToolkit.WindowManager and the UIToolkit:WindowData key
local function getWindowId(role)
    return D.WindowIdPrefix .. role
end

-- drag gating reads the open windows' mode snapshots, not the engine mode: a pinned window
-- keeps drag alive while the engine mode stack is empty
local function dragAllowed()
    for i = 1, #RoleRegistry.order do
        local windowId = getWindowId(RoleRegistry.order[i])
        if Manager.getWindow(windowId) then
            local handler = Manager.getHandler(windowId) --[[@as IER.Inventory]]
            if handler and handler.drag and handler.drag.allowed then
                return true
            end
        end
    end
    return false
end

-- a role's window is registered at most once: init() runs at onLoad and onInit, and
-- registerWindowRole may add a role after init already ran
local windowRegistered = {}

-- ids this repo registered into UIToolkit's manager: membership says a focused window is ours
local ierWindowIds = {}

local function registerWindow(role)
    if windowRegistered[role] then return end
    local opts = RoleRegistry.byRole[role]
    if not opts then return end
    windowRegistered[role] = true

    local handler = InvHandler:new()
    handler:init(role)
    local windowId = getWindowId(role)
    ierWindowIds[windowId] = true
    Manager.register(windowId, {
        title = opts.title,
        handler = handler,
        draggable = opts.draggable,
        resizing = opts.resizing,
        pinnable = opts.pinnable,
        position = Manager.toAbsolute(opts.defaultPosition),
        size = Manager.toAbsolute(opts.defaultSize),
        minSize = opts.minSize,
    })
end

function WindowManager:init()
    for i = 1, #RoleRegistry.order do
        registerWindow(RoleRegistry.order[i])
    end
end

--- Registers a new window role and its window. The only way to get a new window id; mode specs
--- never register windows.
---@param role string
---@param opts InventoryExtenderRedone.RoleOpts
function WindowManager:registerWindowRole(role, opts)
    RoleRegistry.register(role, opts)
    registerWindow(role)
end

--- Opens the windows of a mode through UIToolkit only, without changing the engine UI mode.
---@param key InventoryExtenderRedone.ModeKey
---@param arg any?
function WindowManager:openMode(key, arg)
    local mode = Mode.resolve(key)
    if not mode then return end
    for role in pairs(mode.roles or {}) do
        WindowManager:show(role, arg)
    end
end

---@param key InventoryExtenderRedone.ModeKey
---@param arg any?
function WindowManager:closeMode(key, arg)
    local mode = Mode.resolve(key)
    if not mode then return end
    for role in pairs(mode.roles or {}) do
        WindowManager:hide(role, arg)
    end
end

function WindowManager:update()
    for i = 1, #RoleRegistry.order do
        local windowId = getWindowId(RoleRegistry.order[i])
        local handler = Manager.getHandler(windowId) --[[@as IER.Inventory]]
        if handler then
            L.debug('update', windowId)
            handler:update()
        end
    end
end

---@return InventoryExtenderRedone.RowData?
function WindowManager:getHoveredRow()
    local handler, windowId = Manager.getFocusedWindowHandler()
    if not windowId or not ierWindowIds[windowId] then return nil end
    ---@cast handler IER.Inventory
    return handler:getHoveredRow()
end

--- Barter row query for one window role: the sell side is the Inventory window, the buy side is
--- the Trade window. Answers only while that window's mode is Barter.
--- nil means "not tradeable right now": no window in Barter mode, the row is filtered out, or
--- row.isDisabled().
---@param role InventoryExtenderRedone.Role
---@param item openmw.Object
---@return InventoryExtenderRedone.RowData?
local function findBarterRow(role, item)
    local handler = Manager.getHandler(getWindowId(role)) --[[@as IER.Inventory]]
    if not handler or handler.mode ~= D.Modes.Barter then return nil end

    local rows = handler.table and handler.table.filteredItems
    if not rows then return nil end

    for r = 1, #rows do
        local row = rows[r]
        -- virtual merchant rows are merged stacks, so match the record too, not only the object
        if not row.isBartered and row.item
            and (row.item.id == item.id or row.itemRecord.id == item.recordId)
            and not row.isDisabled() then
            return row
        end
    end
    return nil
end

---@param item openmw.Object
---@return InventoryExtenderRedone.RowData? the row in the open Inventory window under the Barter mode, nil when not tradeable right now
function WindowManager:getSellRow(item)
    return findBarterRow(D.Roles.Inventory, item)
end

---@param item openmw.Object
---@return InventoryExtenderRedone.RowData? the row in the open Trade window under the Barter mode, nil when not tradeable right now
function WindowManager:getBuyRow(item)
    return findBarterRow(D.Roles.Trade, item)
end

---@param role InventoryExtenderRedone.Role
---@param arg any? the target NPC/container/merchant
function WindowManager:show(role, arg)
    -- when returning from other mode to Container mode arg is nil - try retrieving previous one
    arg = arg or self.ctx.windowArgs[role]
    self.ctx.windowArgs[role] = arg

    -- which behavior set this window gets
    local mode = Mode.resolveMode(role, arg)
    L.info('show', role, mode and mode.key)

    local windowId = getWindowId(role)
    local handler = Manager.getHandler(windowId) --[[@as IER.Inventory?]]
    -- the Inventory role stays open across mode changes, so its slots snapshot of the previous
    -- mode is stale: close it here and let the new mode reopen it. Target windows are opened and
    -- closed by their own mode, so an already-open one keeps its snapshot.
    if handler and role == D.Roles.Inventory and mode and handler.mode ~= mode.key then
        L.info('show: reopen for mode change', role, handler.mode, mode.key)
        Manager.close(windowId, true)
        handler = nil
    end
    if not handler then
        _, handler = Manager.open(windowId, arg) --[[@as any]]
        ---@cast handler IER.Inventory
        L.info('opened', windowId, handler.role, handler.mode)
        -- flags is the mode's serializable summary (Mode.EventData.flags); built-ins define none
        local openedMode = Mode.resolve(handler.mode)
        omwself:sendEvent('IER_Window_Opened', {
            id = windowId,
            role = handler.role,
            mode = handler.mode,
            flags = openedMode and openedMode.event and openedMode.event.flags,
        })
    end
end

---@param role InventoryExtenderRedone.Role
function WindowManager:hide(role, arg, force)
    L.info('hide', role)
    Manager.close(getWindowId(role))
end

---@param role InventoryExtenderRedone.Role
---@return IER.Inventory? handler the window's handler, nil if the window is not open
function WindowManager:getWindow(role)
    return Manager.getHandler(getWindowId(role)) --[[@as  IER.Inventory?]]
end

---@param apply fun(handler:IER.Inventory, wnd:UIToolkit.Window)
function WindowManager:forEachOpenWindow(apply)
    for i = 1, #RoleRegistry.order do
        local windowId = getWindowId(RoleRegistry.order[i])
        local wnd = Manager.getWindow(windowId)
        if wnd then
            local handler = Manager.getHandler(windowId) --[[@as IER.Inventory]]
            apply(handler, wnd)
        end
    end
end

function WindowManager:onUiModeChanged(oldMode, newMode, arg)
    if not configPlayer.window.b_EnableMod then
        return
    end
    L.debug('onUiModeChanged', oldMode, newMode, arg)

    -- the transition decides which spec's lifecycle.onClosing fires: a pickpocket session closing
    -- under the engine's Container mode belongs to the Pickpocket spec, which overrides
    -- Container's onClosing. closingArg is what the closing mode's target role was showing.
    if oldMode then
        local closingMode
        if oldMode == D.Modes.Container and self.ctx.pickpocket then
            closingMode = Mode.resolve(D.Modes.Pickpocket)
        else
            closingMode = Mode.resolve(oldMode)
        end
        if closingMode and closingMode.lifecycle and closingMode.lifecycle.onClosing then
            local closingArg
            for role in pairs(closingMode.roles or {}) do
                if role ~= D.Roles.Inventory then
                    closingArg = self.ctx.windowArgs[role]
                end
            end
            closingMode.lifecycle.onClosing(nil, closingArg, newMode)
        end
    end

    self.ctx.barterState = {
        selling = {},
        buying = {},
        currentMerchantOffer = 0,
        currentBalance = 0,
    }

    if self.ctx.dragAndDrop.wrapper then
        self.ctx.dragAndDrop:setWrapperEnabled(not configPlayer.misc.b_TooltipCompatibilityMode and
            dragAllowed())
        self.ctx.dragAndDrop.lastHoveredObject = nil
    end
    self.ctx.dragAndDrop:stopDrag()
end

function WindowManager:onFrame()
    if not configPlayer.window.b_EnableMod then return end

    local mouseMoved = I.UIToolkit.cursorMovedThisFrame()

    if mouseMoved then
        self.ctx.dragAndDrop:updatePosition()
    end
end

function WindowManager:onControllerButtonPress(id)
    if not configPlayer.window.b_EnableMod then return end

    if dragAllowed() then
        WindowManager.ctx.dragAndDrop:onControllerButtonPress(id)
    end
end

function WindowManager:onControllerButtonRelease(id)
    if not configPlayer.window.b_EnableMod then return end

    if dragAllowed() then
        WindowManager.ctx.dragAndDrop:onControllerButtonRelease(id)
    end
end

function WindowManager:onMouseButtonPress(button)
    if not configPlayer.window.b_EnableMod then return end

    if dragAllowed() then
        WindowManager.ctx.dragAndDrop:onMouseButtonPress(button)
    end
end

function WindowManager:onMouseButtonRelease(button)
    if not configPlayer.window.b_EnableMod then return end

    if dragAllowed() then
        WindowManager.ctx.dragAndDrop:onMouseButtonRelease(button)
    end
end

WindowManager.ctx.dragAndDrop:init(WindowManager.ctx)

input.registerTriggerHandler('Activate', async:callback(function()
    for _, button in pairs(input.CONTROLLER_BUTTON) do
        if input.isControllerButtonPressed(button) then
            return
        end
    end

    local mode = I.UI.getMode()
    if mode and (mode == D.Modes.Container or mode == D.Modes.Barter or mode == D.Modes.Companion) then
        I.UI.removeMode(mode)
        return false
    end
    return false
end))

return WindowManager
