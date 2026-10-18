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
local Pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')

local DragAndDrop = require('scripts.InventoryExtenderRedone.ui.dragAndDrop')


local InvHandler = require 'scripts.InventoryExtenderRedone.toolkit.inventory'


local DefaultPosition = {
    ['InventoryExtender:Inventory'] = v2(0.015, 0.54),
    ['InventoryExtender:Container'] = v2(0.5, 0.05),
    ['InventoryExtender:Trade'] = v2(0.5, 0.05),
    ['InventoryExtender:Companion'] = v2(0.5, 0.05),
}

local DefaultDimensions = {
    ['InventoryExtender:Inventory'] = v2(0.45, 0.38),
    ['InventoryExtender:Container'] = v2(0.45, 0.85),
    ['InventoryExtender:Trade'] = v2(0.45, 0.85),
    ['InventoryExtender:Companion'] = v2(0.45, 0.85),
}

local validDragModes = {
    Interface = true,
    Container = true,
    Companion = true,
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

local allToolkitWindows = {}

local WINDOW_TYPES = { "Inventory", "Trade", "Container", "Companion" }
local function getWindowId(type)
    return 'InventoryExtender:' .. type
end

function WindowManager:init()
    for i = 1, #WINDOW_TYPES do
        local windowName = WINDOW_TYPES[i]
        local handler = InvHandler:new()
        handler:init(windowName)

        local manager = Manager
        local windowId = getWindowId(windowName)
        allToolkitWindows[#allToolkitWindows + 1] = windowId
        manager.register(windowId, {
            title = windowName,
            handler = handler,
            draggable = true,
            resizing = true,
            pinnable = false,
            position = manager.toAbsolute(DefaultPosition[windowId]),
            size = manager.toAbsolute(DefaultDimensions[windowId]),
            minSize = v2(300, 200),
        })
    end
end

function WindowManager:update()
    for i = 1, #allToolkitWindows do
        local handler = Manager.getHandler(allToolkitWindows[i]) --[[@as IER.Inventory]]
        if handler then
            handler:update()
        end
    end
end

function WindowManager:show(windowName, arg)
    if windowName == 'Container' then
        if Pickpocket.isTarget(arg) then
            self.ctx.pickpocket = Pickpocket.createSession(omwself, arg)
        else
            self.ctx.pickpocket = nil
        end
    end

    self.ctx.windowArgs[windowName] = arg or self.ctx.windowArgs[windowName]

    --TODO: do not close if not Inventory or same mode?
    --TODO: or maybe invent mode switching for inventory?
    local windowId = getWindowId(windowName)
    Manager.close(windowId, true)
    local _, handler = Manager.open(windowId, arg)
    ---@cast handler IER.Inventory
    omwself:sendEvent('IER_Window_Opened', {
        id = windowId,
        type = handler.type,
        mode = handler.mode,
    })
end

function WindowManager:hide(windowName, arg, force)
    Manager.close(getWindowId(windowName))
end

---@param apply fun(handler:IER.Inventory, wnd:UIToolkit.Window)
function WindowManager:forEachOpenWindow(apply)
    for i = 1, #WINDOW_TYPES do
        local windowName = WINDOW_TYPES[i]
        local windowId = getWindowId(windowName)
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
