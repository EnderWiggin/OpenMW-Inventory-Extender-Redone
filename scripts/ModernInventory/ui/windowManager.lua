local core = require('openmw.core')
local ui = require('openmw.ui')
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')
local util = require('openmw.util')
local omwself = require('openmw.self')
local async = require('openmw.async')
local storage = require('openmw.storage')
local input = require('openmw.input')

local templates = require('scripts.ModernInventory.ui.templates.magic')

local constants = require('scripts.ModernInventory.util.constants')
local helpers = require('scripts.ModernInventory.util.helpers')

local configPlayer = require('scripts.ModernInventory.config.player')

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

windowManager.create = function(windowName)
    if windowName == 'Inventory' then
        windowManager.windows[windowName] = InventoryWindow:create{
            pinned = configPlayer.window.b_InventoryWindowPinned,
        }
        return windowManager.windows[windowName]
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
    if templates.activeTooltip then
        auxUi.deepDestroy(templates.activeTooltip)
        templates.activeTooltip = nil
    end
    window:saveState()
end

windowManager.onUiModeChanged = function(oldMode, newMode, arg)
    if newMode then
        modeArgs[newMode] = arg
    end
    if templates.modalElement then
        auxUi.deepDestroy(templates.modalElement)
        templates.modalElement = nil
    end
end

windowManager.onMouseWheel = function(v, h)
    if templates.focusedScrollable and templates.focusedScrollable.layout then
        local layout = templates.focusedScrollable.layout
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

    -- if templates.active then
    --     if not canShow() then
    --         windowManager.hide(true)
    --         return
    --     end

    --     if templates.focusedScrollable and templates.focusedScrollable.layout then
    --         local rightStick = input.getAxisValue(input.CONTROLLER_AXIS.RightY)
    --         if math.abs(rightStick) > 0.2 then
    --             local layout = templates.focusedScrollable.layout
    --             local pos = layout.content[1].props.position
    --             layout.content[1].props.position = util.vector2(
    --                 pos.x,
    --                 util.clamp(pos.y - rightStick * layout.userData.scrollStep / 4 * dt * 60, -layout.userData.scrollLimit, 0)
    --             )
    --             layout.userData.onScroll()
    --         end

    --         storedScrollPos[templates.focusedScrollable.layout.name] = templates.focusedScrollable.layout.content[1].props.position.y
    --     end

    --     if windowManager.needsRedraw then
    --         windowManager.create()
    --         windowManager.needsRedraw = false
    --     elseif updateTimer >= updateInt then
    --         updateTimer = 0
    --     else
    --         updateTimer = updateTimer + dt
    --     end

    --     if windowManager.needsRedrawDelayed then
    --         windowManager.needsRedrawDelayed = false
    --         windowManager.needsRedraw = true
    --     end
    -- end
end

return windowManager