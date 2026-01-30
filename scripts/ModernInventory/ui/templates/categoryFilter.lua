local ui = require('openmw.ui')
local util = require('openmw.util')
local v2 = util.vector2
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')

local baseTemplates = require('scripts.ModernInventory.ui.templates.base')
local specialTemplates = require('scripts.ModernInventory.ui.templates.magic')
local constants = require('scripts.ModernInventory.util.constants')

local CategoryFilter = {}

function CategoryFilter.create(props, onChange, ctx)
    local maxHeight = props.maxHeight or 48

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
        content = ui.content {},
        userData = {},
    }

    local state = {
        selectedCategory = nil,
    }

    local element = ui.create(layout)

    local updateCategories

    updateCategories = function()
        for i = #element.layout.content, 1, -1 do
            auxUi.deepDestroy(element.layout.content[i])
        end

        element.layout.content = ui.content {}

        local categories = I.ModernInventory.getCategories()
        if not state.selectedCategory then
            state.selectedCategory = categories[1] and categories[1].key or nil
        end

        for i, category in ipairs(categories) do
            local isSelected = state.selectedCategory == category.key
            element.layout.content:add({ external = { grow = 1, stretch = 1, } })
            element.layout.content:add(specialTemplates.interactive({
                onClick = function()
                    if state.selectedCategory ~= category.key then
                        state.selectedCategory = category.key
                        updateCategories()
                        if onChange then
                            onChange(state.selectedCategory)
                        end
                    end
                end,
                name = category.key,
            }, {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = category.icon },
                    size = v2(maxHeight - 16, maxHeight - 16),
                    color = isSelected and constants.Colors.ACTIVE or constants.Colors.DEFAULT,
                },
                userData = {
                    colorable = true,
                    active = isSelected,
                    tooltipFn = function()
                        return specialTemplates.tooltip(4, ui.content {
                            {
                                template = baseTemplates.textNormal,
                                props = {
                                    text = category.name,
                                }
                            }
                        }, category.key)
                    end,
                }
            }, ctx))
            if i == #categories then
                element.layout.content:add({ external = { grow = 1, stretch = 1, } })
            end
        end

        element:update()
    end

    updateCategories()

    element.layout.userData.updateCategories = updateCategories

    local function resizeImages(totalWidth)
        local categories = I.ModernInventory.getCategories()
        if #categories == 0 then return end
        
        local maxSizePerCategory = totalWidth / #categories
        local imageSize = math.min(maxHeight - 16, maxSizePerCategory)
        local imageSizeVec = v2(imageSize, imageSize)
        
        local anyChanged = false
        for _, child in ipairs(element.layout.content) do
            if child.layout and child.layout.type == ui.TYPE.Image then
                if child.layout.props.size ~= imageSizeVec then
                    anyChanged = true
                    child.layout.props.size = imageSizeVec
                    child:update()
                end
            end
        end
        
        if anyChanged then
            element.layout.props.size = v2(0, imageSize + 16)
            element:update()
        end
    end

    element.layout.userData.resizeImages = resizeImages

    return element
end

return CategoryFilter