---@omw-context player

local ui = require('openmw.ui')
local util = require('openmw.util')
local v2 = util.vector2
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')
local async = require('openmw.async')
local core = require('openmw.core')

local specialTemplates = require('scripts.InventoryExtender.ui.templates.magic')
local constants = require('scripts.InventoryExtender.util.constants')
local iconPack = require('scripts.InventoryExtender.util.iconPack')
local configPlayer = require('scripts.InventoryExtender.config.player')

local l10n = core.l10n('InventoryExtender')


local Toolkit   = I.UIToolkit
local T         = Toolkit.Templates
local H         = require 'scripts.UIToolkit.helpers'
local Class     = require 'scripts.UIToolkit.class'
local Component = require 'scripts.UIToolkit.components.component'


---@class InventoryExtenderRedone.CategoryFilter : UIToolkit.Component
---@field new fun(self:InventoryExtenderRedone.CategoryFilter):InventoryExtenderRedone.CategoryFilter
local CategoryFilter = Class(Component)

---@param props any
---@param onCategoryChange any
---@param onSearchChange any
---@return InventoryExtenderRedone.CategoryFilter
function CategoryFilter.create(props, onCategoryChange, onSearchChange)
    local filter = CategoryFilter:new()
    filter:init(props, onCategoryChange, onSearchChange)

    return filter
end

---@param props any
---@param onCategoryChange fun(category:InventoryExtenderRedone.Category)
---@param onSearchChange any
function CategoryFilter:init(props, onCategoryChange, onSearchChange)
    local maxHeight = props.maxHeight or 48
    local compact = props.compact == true
    local vanillaStyle = props.vanillaStyle == true

    local topBarHeight = util.round(specialTemplates.LINE_HEIGHT * 1.5)
    local categoryBarHeight = compact and (topBarHeight - 4) or (maxHeight - topBarHeight)
    local elementHeight = compact and (topBarHeight + 8) or maxHeight + 8
    local compactIconPadding = 8
    local vanillaOpacityStates = {
        default = 0.45,
        hover = 0.7,
        pressed = 0.85,
        active = 1,
        activeHover = 1,
        activePressed = 0.9,
        disabled = 0.2,
        disabledHover = 0.2,
        disabledPressed = 0.2,
    }

    local element, createSearchBar
    local placeholder = l10n('UI_SearchBarPlaceholder')
    local toolbarButtonSize = v2(topBarHeight - 4, topBarHeight - 4)

    local function getViewMode()
        if props.getViewMode then
            return props.getViewMode()
        end
        return 'ItemViewMode_Table'
    end

    local function getViewModeToggleIconPath()
        if getViewMode() == 'ItemViewMode_Grid' then
            return iconPack.getPath('view_table.dds')
        end
        return iconPack.getPath('view_grid.dds')
    end

    local categoryBarLayout = {
        name = 'categoryBar',
        template = configPlayer.tweaks.b_CategoryBarBorders and T.border { padding = 0 } or nil,
        content = ui.content {
            {
                name = 'categoryBarButtons',
                type = ui.TYPE.Widget,
                props = {
                    relativeSize = v2(1, 1),
                },
                content = ui.content {},
            }
        },
        props = {
            position = compact and v2(0, 0) or v2(0, topBarHeight + 8),
            size = v2(compact and 0 or -16, categoryBarHeight - 4),
            anchor = not compact and v2(0.5, 0) or nil,
            relativeSize = not compact and v2(1, 0) or nil,
            relativePosition = not compact and v2(0.5, 0) or nil,
        },
        external = compact and { grow = 1, stretch = 1, } or nil,
    }

    local topBarContent = ui.content { T.intervalH(8), }
    if compact then
        topBarContent:add(categoryBarLayout)
        topBarContent:add(T.intervalH(8))
    else
        topBarContent:add({
            name = 'selectedCategoryName',
            template = T.header(),
            props = {
                text = '',
                textSize = topBarHeight,
            },
        })
        topBarContent:add({
            external = { grow = 1, stretch = 1, }
        })
    end
    topBarContent:add(I.UIToolkit.Components.textEdit {
        width = compact and 150 or 200,
        placeholder = placeholder,
        onValueChanged = onSearchChange,
        showClearButton = true,
    }.element)
    if props.onOpenSettings then
        topBarContent:add(T.intervalH(4))
        topBarContent:add(Toolkit.Components.imageButton {
            icon = iconPack.getPath('edit_mode.dds'),
            size = toolbarButtonSize,
            onClick = function()
                props.onOpenSettings()
            end,
            tooltip = l10n('UI_Tooltip_ColumnSettings'),
            name = 'columnSettings',
        }.element)
    end

    local viewModeButton
    local function updateViewModeButton()
        if not viewModeButton then return end
        viewModeButton:setIcon(getViewModeToggleIconPath())
    end
    if props.onToggleView and configPlayer.window.b_ShowViewModeButton then
        local function getTooltip()
            return getViewMode() == 'ItemViewMode_Grid'
                and l10n('UI_Tooltip_TableView')
                or l10n('UI_Tooltip_GridView')
        end
        viewModeButton = Toolkit.Components.imageButton {
            icon = getViewModeToggleIconPath(),
            size = toolbarButtonSize,
            onClick = function()
                props.onToggleView()
                updateViewModeButton()
                I.UTKTooltips.setTooltip(getTooltip())
            end,
            tooltip = getTooltip,
            name = 'columnSettings',
        }
        topBarContent:add(T.intervalH(4))
        topBarContent:add(viewModeButton.element)
    end
    topBarContent:add(T.intervalH(8))

    local topBarLayout = {
        name = 'topBar',
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            autoSize = false,
            size = v2(0, topBarHeight),
            relativeSize = v2(1, 0),
            position = v2(0, 4),
            align = ui.ALIGNMENT.Start,
            arrange = ui.ALIGNMENT.Center,
        },
        content = topBarContent,
    }

    local state = {
        selectedCategory = nil,
    }
    self.state = state

    local function getCategories()
        if props.getCategories then
            return props.getCategories() or {}
        end
        return I.InventoryExtender.getCategories()
    end

    local function getCategoryIconPath(category)
        if not category then
            return nil
        end
        if category.iconPackRelativePath then
            return iconPack.getPath(category.iconPackRelativePath)
        end
        return category.icon
    end

    element = ui.create {
        props = {
            size = v2(0, elementHeight),
            relativeSize = v2(1, 0),
        },
        content = compact
            and ui.content { topBarLayout }
            or ui.content { topBarLayout, categoryBarLayout, },
        userData = {},
    }

    local updateCategories

    local function isCategoryDisabled(category, categoryDisabledLookup)
        if categoryDisabledLookup then
            return categoryDisabledLookup[category.key] == true
        elseif props.isCategoryDisabled then
            return props.isCategoryDisabled(category)
        end
        return false
    end

    local function getDefaultCategoryKey(categories, categoryDisabledLookup)
        for _, category in ipairs(categories) do
            if category.defaultSelected ~= false and not isCategoryDisabled(category, categoryDisabledLookup) then
                return category.key, category
            end
        end
        local category = categories[1]
        return category and category.key or nil, category
    end

    local function resolveCategoryKey(categoryKey, categories, categoryDisabledLookup)
        categories = categories or getCategories()
        for _, category in ipairs(categories) do
            if category.key == categoryKey then
                return categoryKey, category
            end
        end

        return getDefaultCategoryKey(categories, categoryDisabledLookup)
    end

    local function getCategoryBarContent()
        if compact then
            return element.layout.content.topBar.content.categoryBar.content.categoryBarButtons.content
        end
        return element.layout.content.categoryBar.content.categoryBarButtons.content
    end

    updateCategories = function()
        local categoryBarContent = getCategoryBarContent()
        for i = #categoryBarContent, 1, -1 do
            auxUi.deepDestroy(categoryBarContent[i])
        end

        categoryBarContent = ui.content {}
        if compact then
            element.layout.content.topBar.content.categoryBar.content.categoryBarButtons.content = categoryBarContent
        else
            element.layout.content.categoryBar.content.categoryBarButtons.content = categoryBarContent
        end

        local categories = getCategories()
        local categoryDisabledLookup = props.getCategoryDisabledLookup and props.getCategoryDisabledLookup() or nil
        state.selectedCategory = resolveCategoryKey(state.selectedCategory, categories, categoryDisabledLookup)

        for i, category in ipairs(categories) do
            local isSelected = state.selectedCategory == category.key
            local isDisabled = isCategoryDisabled(category, categoryDisabledLookup)
            local imageSize = categoryBarHeight - compactIconPadding
            local iconSize = v2(imageSize, imageSize)
            local iconAlpha = isSelected and vanillaOpacityStates.active or
                ((isDisabled and not isSelected) and vanillaOpacityStates.disabled or vanillaOpacityStates.default)
            local buttonContent
            local categoryIconPath = getCategoryIconPath(category)

            if vanillaStyle then
                buttonContent = ui.content {
                    {
                        name = 'categoryBackground',
                        type = ui.TYPE.Image,
                        props = {
                            resource = Toolkit.texture(iconPack.getPath('category_bgr.dds')),
                            relativeSize = v2(1, 0),
                            size = v2(0, iconSize.y + (compact and 6 or -2)),
                            relativePosition = v2(0.5, 0.5),
                            anchor = v2(0.5, 0.5),
                            alpha = iconAlpha,
                        },
                        userData = {
                            opacityStates = vanillaOpacityStates,
                        },
                    },
                    {
                        name = 'categoryIcon',
                        type = ui.TYPE.Image,
                        props = {
                            resource = ui.texture { path = categoryIconPath },
                            size = iconSize + (compact and v2(4, 4) or v2(-4, -4)),
                            relativePosition = v2(0.5, 0.5),
                            anchor = v2(0.5, 0.5),
                            color = util.color.rgb(0.01, 0.01, 0.01),
                            alpha = 1,
                        },
                    }
                }
            else
                buttonContent = ui.content {
                    {
                        name = 'categoryIcon',
                        type = ui.TYPE.Image,
                        props = {
                            resource = ui.texture { path = categoryIconPath },
                            size = iconSize,
                            relativePosition = v2(0.5, 0.5),
                            anchor = v2(0.5, 0.5),
                            color = isSelected and constants.Colors.ACTIVE or (isDisabled and constants.Colors.DISABLED or constants.Colors.DEFAULT),
                            alpha = isDisabled and 0.5 or 1,
                        },
                        userData = {
                            colorable = true,
                        }
                    }
                }
            end

            categoryBarContent:add(I.UIToolkit.Interactive.makeInteractive({
                canClick = function()
                    return not isDisabled
                end,
                onClick = function()
                    if state.selectedCategory ~= category.key then
                        state.selectedCategory = category.key
                        if onCategoryChange then
                            onCategoryChange(category)
                        end
                        updateCategories()
                    end
                end,
                tooltip = category.name,
                name = category.key,
            }, {
                external = { grow = 1, stretch = 1, },
                content = buttonContent,
                userData = {
                    active = isSelected,
                    disabled = isDisabled and not isSelected,
                },
                props = {
                    anchor = v2(0.5, 0),
                    relativeSize = v2(1 / #categories, 1),
                    relativePosition = v2((i - 0.5) / #categories, 0),
                }
            }))
        end

        if not compact then
            element.layout.content.topBar.content.selectedCategoryName.props.text = state.selectedCategory and
                (I.InventoryExtender.getCategory(state.selectedCategory).name or '') or ''
        end

        updateViewModeButton()

        element:update()
    end

    updateCategories()

    self.updateCategories = updateCategories

    self.updateViewModeButton = updateViewModeButton

    local function resizeImages(totalWidth)
        local categories = getCategories()
        if #categories == 0 then return end

        local availableWidth = totalWidth
        local barWidth = nil
        if compact then
            availableWidth = math.max(0, totalWidth - 240)
        else
            local widthPerCategory = math.max(1, math.floor(totalWidth / #categories))
            barWidth = widthPerCategory * #categories - 8
            availableWidth = barWidth
        end

        local maxSizePerCategory = availableWidth / #categories
        local imageSize = math.min(categoryBarHeight - compactIconPadding, maxSizePerCategory)
        local imageSizeVec = v2(imageSize, imageSize)

        local anyChanged = false
        if not compact and element.layout.content.categoryBar.props.size.x ~= barWidth then
            anyChanged = true
            element.layout.content.categoryBar.props.size = v2(barWidth, categoryBarHeight - 4)
        end
        for _, child in ipairs(getCategoryBarContent()) do
            if child.layout and child.layout.content:indexOf('categoryIcon') then
                if child.layout.content.categoryIcon.props.size ~= imageSizeVec then
                    anyChanged = true
                    child.layout.content.categoryIcon.props.size = imageSizeVec + (compact and v2(4, 4) or v2(-4, -4))
                    if child.layout.content:indexOf('categoryBackground') then
                        child.layout.content.categoryBackground.props.size = v2(0, imageSizeVec.y + (compact and 6 or -2))
                    end
                    child:update()
                end
            end
        end

        if anyChanged and not compact then
            element.layout.props.size = v2(0, topBarHeight + imageSize + 16)
            element:update()
        elseif anyChanged then
            element:update()
        end
    end

    element.layout.userData.resizeImages = resizeImages

    local function clearSearch()
        element.layout.content.topBar.content.searchBar = createSearchBar(placeholder)
        element:update()
        if onSearchChange then
            onSearchChange('')
        end
    end
    element.layout.userData.clearSearch = clearSearch

    function self.cycleCategory(self, i)
        local categories = getCategories()
        if #categories == 0 then return end
        local buttons = getCategoryBarContent()

        local currentIndex = 1
        for index, category in ipairs(categories) do
            if category.key == state.selectedCategory then
                currentIndex = index
                break
            end
        end

        local newIndex = currentIndex
        local foundEnabled = false
        for _ = 1, #categories do
            newIndex = newIndex + i
            if newIndex < 1 then
                newIndex = #categories
            elseif newIndex > #categories then
                newIndex = 1
            end

            local button = buttons[newIndex]
            local isDisabled = button and button.layout and button.layout.userData and button.layout.userData.disabled or
                false
            if not isDisabled then
                foundEnabled = true
                break
            end
        end

        if not foundEnabled then
            return
        end

        state.selectedCategory = categories[newIndex].key
        if onCategoryChange then
            onCategoryChange(categories[newIndex])
        end
        updateCategories()
    end

    function self.setCategory(self, categoryKey)
        local categories = getCategories()
        local categoryDisabledLookup = props.getCategoryDisabledLookup and props.getCategoryDisabledLookup() or nil
        local resolvedCategoryKey, category = resolveCategoryKey(categoryKey, categories, categoryDisabledLookup)
        if state.selectedCategory ~= resolvedCategoryKey then
            state.selectedCategory = resolvedCategoryKey
            if onCategoryChange then
                onCategoryChange(category)
            end
            updateCategories()
        end
    end

    Component.init(self, element)
end

function CategoryFilter:getCategory()
    return self.state.selectedCategory
end

function CategoryFilter:getSize()
    return self.element.layout.props.size
end

return CategoryFilter
