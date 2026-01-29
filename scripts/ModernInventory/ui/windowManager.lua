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

local templates = require('scripts.ModernInventory.ui.templates.magic')

local constants = require('scripts.ModernInventory.util.constants')
local helpers = require('scripts.ModernInventory.util.helpers')

local configPlayer = require('scripts.ModernInventory.config.player')

local DragAndDrop = require('scripts.ModernInventory.ui.dragAndDrop')

local InventoryWindow = require('scripts.ModernInventory.ui.windows.inventory')

local modeArgs = {}

local function canShow()
    return not not I.UI.getWindowsForMode('Interface')['Magic']
end

local windowManager = {}

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
}

windowManager.create = function(windowName)
    if windowName == 'Inventory' then
        windowManager.windows[windowName] = InventoryWindow:create(windowManager.ctx)
        return windowManager.windows[windowName]
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
end

windowManager.show = function(windowName)
    if not windowManager.windows[windowName] then
        windowManager.create(windowName)
    end

    windowManager.windows[windowName]:setVisible(true)
end

windowManager.hide = function(windowName, force)
    local window = windowManager.windows[windowName]
    if not window or not window:isVisible() then return end

    if not window:isPinned() or force then
        window:setVisible(false)
        --omwself:sendEvent(constants.Events.WINDOW_HIDDEN)
    end
    if windowManager.ctx.activeTooltip then
        auxUi.deepDestroy(windowManager.ctx.activeTooltip)
        windowManager.ctx.activeTooltip = nil
    end
    window:saveState()
end

windowManager.onUiModeChanged = function(oldMode, newMode, arg)
    if newMode then
        modeArgs[newMode] = arg
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
        windowManager.ctx.dragAndDrop.wrapper.layout.props.relativeSize = newMode == 'Interface' and v2(1, 1) or v2(0, 0)
        windowManager.ctx.dragAndDrop.wrapper:update() 
        windowManager.ctx.dragAndDrop.lastHoveredObject = nil
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
    for _, el in ipairs(templates.updateQueue) do
        el:update()
    end
    templates.updateQueue = {}

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
    if windowManager.ctx.focusedInteractive and windowManager.ctx.focusedInteractive.layout and
       windowManager.ctx.focusedInteractive.layout.userData.onActivate then
        windowManager.ctx.focusedInteractive.layout.userData.onActivate()
        return true
    end
    return false
end))

return windowManager