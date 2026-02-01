local ui = require('openmw.ui')
local util = require('openmw.util')
local v2 = util.vector2
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')

local baseTemplates = require('scripts.InventoryExtender.ui.templates.base')
local specialTemplates = require('scripts.InventoryExtender.ui.templates.magic')
local constants = require('scripts.InventoryExtender.util.constants')

local InfoBar = {}

function InfoBar.create(props, ctx)
    local maxHeight = props.maxHeight or 32

    local layout = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            autoSize = false,
            size = v2(0, maxHeight),
            relativeSize = v2(1, 0),
            align = ui.ALIGNMENT.Start,
            arrange = ui.ALIGNMENT.Center,
        },
        content = ui.content {
            baseTemplates.intervalH(8),
        },
        userData = {},
    }

    local state = {}

    state.element = ui.create(layout)
    state.ctx = ctx

    local function addInfoLayout(layout, updateFn)
        layout.userData = layout.userData or {}
        layout.userData.update = updateFn
        state.element.layout.content:add(layout)
        state.element.layout.content:add(baseTemplates.intervalH(8))
        state.element:update()
    end

    local function updateAll()
        for i, child in ipairs(state.element.layout.content) do
            if child.userData and child.userData.update then
                local updateFn = child.userData.update
                child = updateFn(child, state.ctx)
                child.userData = child.userData or {}
                child.userData.update = updateFn
                state.element.layout.content[i] = child
            end
        end
        state.element:update()
    end

    state.element.layout.userData.addInfoLayout = addInfoLayout
    state.element.layout.userData.updateAll = updateAll
    return state.element
end

return InfoBar