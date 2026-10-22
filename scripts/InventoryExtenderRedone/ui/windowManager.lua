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

local DragAndDrop = require('scripts.InventoryExtenderRedone.ui.dragAndDrop')


local InvHandler = require 'scripts.InventoryExtenderRedone.toolkit.inventory'


local WindowManager = {}

---@type InventoryExtenderRedone.Context
WindowManager.ctx = {
    overrides = {
        equipped = {},
    },
    handlers = {
        onRowUse = {},
        onRowPickup = {},
    },
    modifiers = {
        data = {},
        badge = {},
    },
    -- custom modes and id-keyed patches registered by other mods; built-in specs
    -- live in toolkit/mode.lua Mode.Builtins and are never stored here
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

-- drag gating reads the open windows' mode snapshots, not the engine mode: a pinned Interface
-- window keeps drag alive while the engine mode stack is empty, and a Barter window kills it
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

function WindowManager:init()
    local manager = Manager
    for i = 1, #RoleRegistry.order do
        local role = RoleRegistry.order[i]
        local opts = RoleRegistry.byRole[role]
        local handler = InvHandler:new()
        handler:init(role)

        manager.register(getWindowId(role), {
            title = opts.title,
            handler = handler,
            draggable = opts.draggable,
            resizing = opts.resizing,
            pinnable = opts.pinnable,
            position = manager.toAbsolute(opts.defaultPosition),
            size = manager.toAbsolute(opts.defaultSize),
            minSize = opts.minSize,
        })
    end
end

function WindowManager:update()
    for i = 1, #RoleRegistry.order do
        local handler = Manager.getHandler(getWindowId(RoleRegistry.order[i])) --[[@as IER.Inventory]]
        if handler then
            handler:update()
        end
    end
end

---@param role InventoryExtenderRedone.Role
---@param arg any? the target NPC/container/merchant
function WindowManager:show(role, arg)
    self.ctx.windowArgs[role] = arg or self.ctx.windowArgs[role]

    -- which behavior set this window gets; the pickpocket session is no longer created here, it
    -- comes from the Pickpocket spec's lifecycle.onOpened, and the Container spec clears it when
    -- a real chest window opens
    local mode = Mode.resolveMode(role, arg)

    local windowId = getWindowId(role)
    local handler = Manager.getHandler(windowId) --[[@as IER.Inventory?]]
    -- only the Inventory role needs this: the engine re-shows it when the UI mode changes but
    -- leaves it open, so its snapshot of the previous mode's slots is stale. The target windows
    -- are opened and closed by their own mode, so an already-open one keeps its snapshot and is
    -- never reopened from here.
    if handler and role == D.Roles.Inventory and mode and handler.mode ~= mode.key then
        Manager.close(windowId, true)
        handler = nil
    end
    if not handler then
        _, handler = Manager.open(windowId, arg) --[[@as any]]
        ---@cast handler IER.Inventory
        omwself:sendEvent('IER_Window_Opened', {
            id = windowId,
            role = handler.role,
            mode = handler.mode,
        })
    end
end

---@param role InventoryExtenderRedone.Role
function WindowManager:hide(role, arg, force)
    Manager.close(getWindowId(role))
end

---@param role InventoryExtenderRedone.Role
---@return IER.Inventory? handler the window's handler, nil if the window is not open
function WindowManager:getWindow(role)
    return Manager.getWindow(getWindowId(role)) --[[@as  IER.Inventory?]]
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

    -- built-in lifecycle.onClosing fires from the mode change (decision 11): the transition
    -- decides which spec closes, and a pickpocket session closing under the engine's Container
    -- mode belongs to the Pickpocket spec, which overrides Container's onClosing. The arg is
    -- what the closing mode's target role was showing; built-in modes have one target role each.
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

    -- I.Cursor when??? (:
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
