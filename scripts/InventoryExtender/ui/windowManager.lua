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
    isConsoleOpen = false,
    dragAndDrop = DragAndDrop,
    modeArgs = {},
    uiMode = nil,
    stolenItems = {},
    barterState = {
        selling = {},
        buying = {},
        currentMerchantOffer = 0,
        currentBalance = 0,
        totalBalance = 0,
    },
    updateQueue = {},
}

local showing = {
    Inventory = false,
    Trade = false,
    Container = false,
    Companion = false,
}

windowManager.create = function(windowName)
    if windowName == 'Inventory' or windowName == 'Container' or windowName == 'Trade' then
        windowManager.windows[windowName] = InventoryWindow:create(windowName, windowManager.ctx)
    end
    
    return windowManager.windows[windowName]
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

windowManager.show = function(windowName)
    if not windowManager.windows[windowName] then
        windowManager.create(windowName)
    end

    showing[windowName] = true
end

windowManager.hide = function(windowName, force)
    local window = windowManager.windows[windowName]
    if not window or not window:isVisible() then return end

    if not window:isPinned() or force then
        showing[windowName] = false
    end
    if windowManager.ctx.activeTooltip then
        auxUi.deepDestroy(windowManager.ctx.activeTooltip)
        windowManager.ctx.activeTooltip = nil
    end
    window:saveState()
end

windowManager.onUiModeChanged = function(oldMode, newMode, arg)
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

    if oldMode == 'Container' and windowManager.ctx.modeArgs.Container then
        windowManager.ctx.modeArgs.Container:sendEvent('MI_ContainerClosed')
    end

    if newMode then
        windowManager.ctx.modeArgs[newMode] = arg
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
    windowManager.ctx.uiMode = newMode
    for name, window in pairs(windowManager.windows) do
        if window then
            if showing[name] then
                window:loadState()
                window:setVisible(true)
            else
                window:setVisible(false)
            end
            window:updateTarget()
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

windowManager.ctx.dragAndDrop:init(windowManager.ctx)

input.registerTriggerHandler('Activate', async:callback(function()
    if windowManager.ctx.uiMode == 'Container' or windowManager.ctx.uiMode == 'Barter' or windowManager.ctx.uiMode == 'Companion' then
        I.UI.removeMode(windowManager.ctx.uiMode)
        return false
    end
    if windowManager.ctx.focusedInteractive and windowManager.ctx.focusedInteractive.layout and
       windowManager.ctx.focusedInteractive.layout.userData.onActivate then
        windowManager.ctx.focusedInteractive.layout.userData.onActivate()
        return true
    end
    return false
end))

return windowManager