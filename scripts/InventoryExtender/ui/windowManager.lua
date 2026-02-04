local core = require('openmw.core')
local ui = require('openmw.ui')
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')
local util = require('openmw.util')
local omwself = require('openmw.self')
local async = require('openmw.async')
local storage = require('openmw.storage')
local input = require('openmw.input')
local v2 = util.vector2

local templates = require('scripts.InventoryExtender.ui.templates.magic')

local constants = require('scripts.InventoryExtender.util.constants')
local helpers = require('scripts.InventoryExtender.util.helpers')

local configPlayer = require('scripts.InventoryExtender.config.player')

local DragAndDrop = require('scripts.InventoryExtender.ui.dragAndDrop')

local InventoryWindow = require('scripts.InventoryExtender.ui.windows.inventory')

local function canShow()
    return not not I.UI.getWindowsForMode('Interface')['Magic']
end

local windowManager = {}

local validDragModes = {
    Interface = true,
    Container = true,
    Companion = true,
}

windowManager.windows = {
    Inventory = nil,
    Trade = nil,
    Container = nil,
    Companion = nil,
}

windowManager.ctx = {
    focusedScrollable = nil,
    modalElement = nil,
    activeTooltip = nil,
    tooltipModifiers = {},
    isConsoleOpen = false,
    dragAndDrop = DragAndDrop,
    windowArgs = {},
    modeArgs = {},
    lastUiMode = nil,
    stolenItems = {},
    barterState = {
        selling = {},
        buying = {},
        currentMerchantOffer = 0,
        currentBalance = 0,
        totalBalance = 0,
    },
    companionProfit = {},
    updateQueue = {},
}

local showing = {
    Inventory = false,
    Trade = false,
    Container = false,
    Companion = false,
}

windowManager.create = function(windowName)
    if windowName == 'Inventory' or windowName == 'Container' or windowName == 'Trade' or windowName == 'Companion' then
        windowManager.windows[windowName] = InventoryWindow:create(windowName, windowManager.ctx)
    end
    
    return windowManager.windows[windowName]
end

windowManager.init = function()
    for _, windowName in ipairs{"Inventory", "Trade", "Container", "Companion"} do
        windowManager.create(windowName)
    end
end

windowManager.update = function()
    for _, window in pairs(windowManager.windows) do
        if window then
            if window.updateData then
                window:updateData()
            else
                window:update()
            end
        end
    end
    if windowManager.ctx.activeTooltip then
        auxUi.deepDestroy(windowManager.ctx.activeTooltip)
        windowManager.ctx.activeTooltip = nil
    end
end

windowManager.show = function(windowName, arg)
    if windowManager.ctx.resettingMode then
        return
    end

    windowManager.ctx.windowArgs[windowName] = arg

    if not windowManager.windows[windowName] then
        windowManager.create(windowName)
    end

    showing[windowName] = true

    windowManager.windows[windowName]:loadState()
    windowManager.windows[windowName]:setVisible(true)
    windowManager.windows[windowName]:updateTarget()
end

windowManager.hide = function(windowName, arg, force)
    if windowManager.ctx.resettingMode then
        return
    end

    showing[windowName] = false
    local window = windowManager.windows[windowName]
    if not window or not window:isVisible() then return end

    window:saveState()

    if not (window:isPinned() and I.UI.getMode() == nil) or force then
        window:setVisible(false)
    end
    if windowManager.ctx.activeTooltip then
        auxUi.deepDestroy(windowManager.ctx.activeTooltip)
        windowManager.ctx.activeTooltip = nil
    end
end

windowManager.onUiModeChanged = function(oldMode, newMode, arg)
    if windowManager.ctx.resettingMode then
        return
    end

    windowManager.ctx.lastUiMode = newMode

    if arg then
        windowManager.ctx.modeArgs[newMode] = arg
    end

    if oldMode == 'Barter' and windowManager.ctx.barterState.success then
        ui.showMessage(constants.Strings.BARTER_THANK_YOU, {
            showInDialogue = true,
        })
    end

    windowManager.ctx.barterState = {
        selling = {},
        buying = {},
        currentMerchantOffer = 0,
        currentBalance = 0,
    }

    if oldMode == 'Container' and windowManager.ctx.windowArgs.Container then
        windowManager.ctx.windowArgs.Container:sendEvent('MI_ContainerClosed')
    end

    if windowManager.ctx.modalElement then
        auxUi.deepDestroy(windowManager.ctx.modalElement)
        windowManager.ctx.modalElement = nil
    end
    if windowManager.ctx.activeTooltip then
        auxUi.deepDestroy(windowManager.ctx.activeTooltip)
        windowManager.ctx.activeTooltip = nil
    end
    if windowManager.ctx.dragAndDrop.wrapper then
        windowManager.ctx.dragAndDrop.wrapper.layout.props.relativeSize = validDragModes[newMode] and v2(1, 1) or v2(0, 0)
        windowManager.ctx.dragAndDrop.wrapper:update() 
        windowManager.ctx.dragAndDrop.lastHoveredObject = nil
    end
    windowManager.ctx.dragAndDrop:stopDrag()

    for windowName, window in pairs(windowManager.windows) do
        window:loadState()
        if not window:isPinnable() and window:isVisible() and not showing[windowName] and newMode ~= nil then
            window:setVisible(false)
        elseif window:isPinnable() and window:isPinned() and not window:isVisible() and newMode == nil then
            window:setVisible(true)
            window:updateData()
        end
    end
end

windowManager.onMouseWheel = function(v, h)
    if windowManager.ctx.focusedScrollable and windowManager.ctx.focusedScrollable.layout then
        local layout = windowManager.ctx.focusedScrollable.layout
        local pos = layout.content[1].props.position
        layout.content[1].props.position = util.vector2(
            pos.x,
            util.clamp(pos.y + v * layout.userData.scrollStep, -layout.userData.scrollLimit, 0)
        )
        layout.userData.onScroll()
    end
end

local updateInt = 0.5
local updateTimer = 0

windowManager.onFrame = function()
    if windowManager.ctx.resettingModeProcessed then
        windowManager.ctx.resettingModeProcessed = false
        windowManager.ctx.resettingMode = false
        return
    end

    if windowManager.ctx.resettingMode then
        windowManager.ctx.resettingModeProcessed = true
    end

    for element in pairs(windowManager.ctx.updateQueue) do
        element:update()
    end
    windowManager.ctx.updateQueue = {}

    local dt = core.getRealFrameDuration()

    if windowManager.ctx.focusedScrollable and windowManager.ctx.focusedScrollable.layout then
        local rightStick = input.getAxisValue(input.CONTROLLER_AXIS.RightY)
        if math.abs(rightStick) > 0.2 then
            local layout = windowManager.ctx.focusedScrollable.layout
            local pos = layout.content[1].props.position
            layout.content[1].props.position = util.vector2(
                pos.x,
                util.clamp(pos.y - rightStick * layout.userData.scrollStep / 4 * dt * 60, -layout.userData.scrollLimit, 0)
            )
            layout.userData.onScroll()
        end
    end

    -- if updateTimer > 0 then
    --     updateTimer = updateTimer - dt
    -- else
    --     updateTimer = updateInt
    --     windowManager.update()
    -- end
end

windowManager.onControllerButtonPress = function(id)
    if id == input.CONTROLLER_BUTTON.Y and windowManager.ctx.modalElement then
        auxUi.deepDestroy(windowManager.ctx.modalElement)
        windowManager.ctx.modalElement = nil
        return
    end

    for _, window in pairs(windowManager.windows) do
        if window:isFocused() then
            window:onControllerButtonPress(id)
            return
        end
    end
end

windowManager.ctx.dragAndDrop:init(windowManager.ctx)

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
    if windowManager.ctx.focusedInteractive and windowManager.ctx.focusedInteractive.layout and
       windowManager.ctx.focusedInteractive.layout.userData.onRowActivate then
        windowManager.ctx.focusedInteractive.layout.userData.onRowActivate()
        return true
    end
    return false
end))

return windowManager