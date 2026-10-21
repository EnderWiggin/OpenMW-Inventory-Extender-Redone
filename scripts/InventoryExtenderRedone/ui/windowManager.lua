---@omw-context player

local core = require('openmw.core')
local ui = require('openmw.ui')
local I = require('openmw.interfaces')
local util = require('openmw.util')
local async = require('openmw.async')
local input = require('openmw.input')
local omwself = require('openmw.self')
local v2 = util.vector2


local Toolkit = I.UIToolkit
local Manager = Toolkit.WindowManager


local constants = require('scripts.InventoryExtenderRedone.util.constants')
local configPlayer = require('scripts.InventoryExtenderRedone.config.player')
local D = require('scripts.InventoryExtenderRedone.config.defaults')
local Pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')
local RoleRegistry = require('scripts.InventoryExtenderRedone.ui.roles')
local Mode = require('scripts.InventoryExtenderRedone.toolkit.mode')

local DragAndDrop = require('scripts.InventoryExtenderRedone.ui.dragAndDrop')


local InvHandler = require 'scripts.InventoryExtenderRedone.toolkit.inventory'


-- drag is only allowed in these UI modes; the table is replaced by Mode.drag.allowed
-- specs once the mode API is wired up
local validDragModes = {
    [D.Modes.Interface] = true,
    [D.Modes.Container] = true,
    [D.Modes.Companion] = true,
}

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
    lastUiMode = nil,
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

    self.ctx.lastUiMode = newMode

    if oldMode == 'Barter' and self.ctx.barterState.success then
        ui.showMessage(constants.Strings.BARTER_THANK_YOU, {
            showInDialogue = true,
        })
    end

    self.ctx.barterState = {
        selling = {},
        buying = {},
        currentMerchantOffer = 0,
        currentBalance = 0,
    }

    if newMode == nil and oldMode == 'Container' and self.ctx.windowArgs.Container then
        if self.ctx.pickpocket and self.ctx.pickpocket.active and not self.ctx.pickpocket.resolved and
            Pickpocket.isTarget(self.ctx.windowArgs.Container) then
            local success = Pickpocket.rollClose(omwself, self.ctx.windowArgs.Container)
            if not success then
                core.sendGlobalEvent('IER_CommitPickpocket', {
                    player = omwself,
                    target = self.ctx.windowArgs.Container,
                    victimAware = true,
                })
            end
        end
        self.ctx.pickpocket = nil
        self.ctx.windowArgs.Container:sendEvent('IER_ContainerClosed')
    end

    if self.ctx.dragAndDrop.wrapper then
        self.ctx.dragAndDrop:setWrapperEnabled(not configPlayer.misc.b_TooltipCompatibilityMode and
            validDragModes[newMode])
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

    if validDragModes[I.UI.getMode() or ''] then
        WindowManager.ctx.dragAndDrop:onControllerButtonPress(id)
    end
end

function WindowManager:onControllerButtonRelease(id)
    if not configPlayer.window.b_EnableMod then return end

    if validDragModes[I.UI.getMode() or ''] then
        WindowManager.ctx.dragAndDrop:onControllerButtonRelease(id)
    end
end

function WindowManager:onMouseButtonPress(button)
    if not configPlayer.window.b_EnableMod then return end

    if validDragModes[I.UI.getMode() or ''] then
        WindowManager.ctx.dragAndDrop:onMouseButtonPress(button)
    end
end

function WindowManager:onMouseButtonRelease(button)
    if not configPlayer.window.b_EnableMod then return end

    if validDragModes[I.UI.getMode() or ''] then
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
    if mode == 'Container' or mode == 'Barter' or mode == 'Companion' then
        I.UI.removeMode(mode)
        return false
    end
    return false
end))

return WindowManager
