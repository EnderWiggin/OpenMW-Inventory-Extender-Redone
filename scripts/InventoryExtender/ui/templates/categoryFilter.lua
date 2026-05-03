local ui = require('openmw.ui')
local util = require('openmw.util')
local v2 = util.vector2
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')
local async = require('openmw.async')
local core = require('openmw.core')

local baseTemplates = require('scripts.InventoryExtender.ui.templates.base')
local specialTemplates = require('scripts.InventoryExtender.ui.templates.magic')
local constants = require('scripts.InventoryExtender.util.constants')

local l10n = core.l10n('InventoryExtender')

local CategoryFilter = {}

function CategoryFilter.create(props, onCategoryChange, onSearchChange, ctx)
    local maxHeight = props.maxHeight or 48
    local compact = props.compact == true
    local vanillaStyle = props.vanillaStyle == true

    local topBarHeight = specialTemplates.LINE_HEIGHT * 1.5
    local categoryBarHeight = compact and (topBarHeight - 4) or (maxHeight - topBarHeight)
    local elementHeight = compact and (topBarHeight + 8) or maxHeight
    local compactIconPadding = compact and 8 or 16
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

    local function replaceSearchBar(text)
        local indexOfBar = element.layout.content.topBar.content:indexOf('searchBar')
        local indexOfProxy = element.layout.content.topBar.content:indexOf('searchBarProxy')

        element.layout.content.topBar.content.searchBar = nil
        element.layout.content.topBar.content.searchBarProxy = nil

        element.layout.content.topBar.content:insert(indexOfBar, { name = 'searchBarProxy' })
        element.layout.content.topBar.content:insert(indexOfProxy, createSearchBar(text))
        ctx.updateQueue[element] = true
    end

    createSearchBar = function(text)
        return {
            name = 'searchBar',
            template = I.MWUI.templates.box,
            content = ui.content {
                {
                    name = 'padding',
                    template = I.MWUI.templates.padding,
                    content = ui.content {
                        {
                            name = 'textEdit',
                            template = baseTemplates.textEditLine,
                            props = {
                                size = v2(200, topBarHeight - 12),
                                text = text,
                                textColor = text == placeholder and constants.Colors.DISABLED or constants.Colors.DEFAULT,
                            },
                            events = {
                                textChanged = async:callback(function(text, layout)
                                    layout.props.text = text
                                    if layout.props.textColor == constants.Colors.DISABLED then
                                        layout.props.textColor = constants.Colors.DEFAULT
                                        element:update()
                                    end
                                    if onSearchChange then
                                        onSearchChange(text)
                                    end
                                end),
                                focusGain = async:callback(function(_, layout)
                                    if layout.props.text == placeholder then
                                        layout.props.text = ''
                                        element:update()
                                    end
                                end),
                                focusLoss = async:callback(function(_, layout)
                                    if layout.props.text == '' then
                                        layout.props.text = placeholder
                                    end
                                    replaceSearchBar(layout.props.text)
                                end),
                            }
                        }
                    }
                }
            },
        }
    end

    local categoryBarLayout = {
        name = 'categoryBar',
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            autoSize = false,
            position = compact and v2(0, 0) or v2(0, topBarHeight),
            size = v2(0, categoryBarHeight),
            align = ui.ALIGNMENT.Start,
            arrange = ui.ALIGNMENT.Center,
            anchor = compact and nil or v2(0.5, 0),
            relativePosition = compact and nil or v2(0.5, 0),
        },
        external = compact and { grow = 1, stretch = 1, } or nil,
        content = ui.content {},
    }
    if compact then
        categoryBarLayout.props.relativeSize = v2(0, 0)
    end

    local topBarContent = ui.content {
        baseTemplates.intervalH(8),
    }
    if compact then
        topBarContent:add(categoryBarLayout)
        topBarContent:add(baseTemplates.intervalH(8))
    else
        topBarContent:add({
            name = 'selectedCategoryName',
            template = baseTemplates.textHeader,
            props = {
                text = '',
                textSize = topBarHeight,
            },
        })
        topBarContent:add({
            external = { grow = 1, stretch = 1, }
        })
    end
    topBarContent:add(createSearchBar(placeholder))
    topBarContent:add({
        name = 'searchBarProxy', -- when destroying the search bar, flip the indices of these to force focus loss and free the keyboard
    })
    if props.onOpenSettings then
        topBarContent:add(baseTemplates.intervalH(4))
        topBarContent:add(specialTemplates.interactive({
            onClick = function()
                props.onOpenSettings()
            end,
            name = 'columnSettings',
        }, {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
                align = ui.ALIGNMENT.Center,
                autoSize = false,
                size = v2(topBarHeight - 4, topBarHeight - 4),
            },
            content = ui.content {
                baseTemplates.imageButton('icons/InventoryExtender/edit_mode.dds', v2(topBarHeight - 12, topBarHeight - 12), nil, 'columnSettingsButton'),
            },
            userData = {
                tooltipFn = function()
                    return specialTemplates.tooltip(4, ui.content {
                        {
                            template = baseTemplates.textNormal,
                            props = {
                                text = l10n('UI_ColumnSettingsTitle'),
                            }
                        }
                    }, 'columnSettings')
                end,
            },
        }, ctx))
    end
    topBarContent:add(baseTemplates.intervalH(8))

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

    element = ui.create({
        props = {
            size = v2(0, elementHeight),
            relativeSize = v2(1, 0),
        },
        content = compact and ui.content { topBarLayout } or ui.content {
            topBarLayout,
            categoryBarLayout,
        },
        userData = {},
    })

    local updateCategories

    local function isCategoryDisabled(category, categoryDisabledLookup)
        if categoryDisabledLookup then
            return categoryDisabledLookup[category.key] == true
        elseif props.isCategoryDisabled then
            return props.isCategoryDisabled(category)
        end
        return false
    end

    local function getCategoryBarContent()
        if compact then
            return element.layout.content.topBar.content.categoryBar.content
        end
        return element.layout.content.categoryBar.content
    end

    updateCategories = function()
        local categoryBarContent = getCategoryBarContent()
        for i = #categoryBarContent, 1, -1 do
            auxUi.deepDestroy(categoryBarContent[i])
        end

        if compact then
            element.layout.content.topBar.content.categoryBar.content = ui.content {}
            categoryBarContent = element.layout.content.topBar.content.categoryBar.content
        else
            element.layout.content.categoryBar.content = ui.content {}
            categoryBarContent = element.layout.content.categoryBar.content
        end

        local categories = I.InventoryExtender.getCategories()
        local categoryDisabledLookup = props.getCategoryDisabledLookup and props.getCategoryDisabledLookup() or nil
        if not state.selectedCategory then
            state.selectedCategory = categories[1] and categories[1].key or nil
        end

        for i, category in ipairs(categories) do
            local isSelected = state.selectedCategory == category.key
            local isDisabled = isCategoryDisabled(category, categoryDisabledLookup)
            local iconSize = v2(categoryBarHeight - compactIconPadding, categoryBarHeight - compactIconPadding)
            local iconAlpha = isSelected and vanillaOpacityStates.active or ((isDisabled and not isSelected) and vanillaOpacityStates.disabled or vanillaOpacityStates.default)
            local buttonContent

            if vanillaStyle then
                buttonContent = ui.content {
                    {
                        name = 'categoryBackground',
                        type = ui.TYPE.Image,
                        props = {
                            resource = baseTemplates.createTexture('icons/InventoryExtender/category_bgr.dds'),
                            relativeSize = v2(1, 0),
                            size = v2(-4, iconSize.y + 8),
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
                            resource = ui.texture { path = category.icon },
                            size = iconSize,
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
                            resource = ui.texture { path = category.icon },
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

            categoryBarContent:add(specialTemplates.interactive({
                canClick = function()
                    return not isDisabled
                end,
                onClick = function()
                    if state.selectedCategory ~= category.key then
                        state.selectedCategory = category.key
                        if onCategoryChange then
                            onCategoryChange(state.selectedCategory)
                        else
                            updateCategories()
                        end
                    end
                end,
                name = category.key,
            }, {
                external = { grow = 1, stretch = 1, },
                content = buttonContent,
                userData = {
                    active = isSelected,
                    disabled = isDisabled and not isSelected,
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
        end

        if not compact then
            element.layout.content.topBar.content.selectedCategoryName.props.text = state.selectedCategory and (I.InventoryExtender.getCategory(state.selectedCategory).name or '') or ''
        end

        element:update()
    end

    updateCategories()

    element.layout.userData.updateCategories = updateCategories

    local function resizeImages(totalWidth)
        local categories = I.InventoryExtender.getCategories()
        if #categories == 0 then return end

        local availableWidth = totalWidth
        local barWidth = nil
        if compact then
            availableWidth = math.max(0, totalWidth - 240)
        else
            local widthPerCategory = math.max(1, math.floor(totalWidth / #categories))
            barWidth = widthPerCategory * #categories
            availableWidth = barWidth
        end

        local maxSizePerCategory = availableWidth / #categories
        local imageSize = math.min(categoryBarHeight - compactIconPadding, maxSizePerCategory)
        local imageSizeVec = v2(imageSize, imageSize)

        local anyChanged = false
        if not compact and element.layout.content.categoryBar.props.size.x ~= barWidth then
            anyChanged = true
            element.layout.content.categoryBar.props.size = v2(barWidth, categoryBarHeight)
        end
        for _, child in ipairs(getCategoryBarContent()) do
            if child.layout and child.layout.content.categoryIcon then
                if child.layout.content.categoryIcon.props.size ~= imageSizeVec then
                    anyChanged = true
                    child.layout.content.categoryIcon.props.size = imageSizeVec
                    if child.layout.content.categoryBackground then
                        child.layout.content.categoryBackground.props.size = v2(-4, imageSizeVec.y + 8)
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

    local function cycleCategory(i)
        local categories = I.InventoryExtender.getCategories()
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
            local isDisabled = button and button.layout and button.layout.userData and button.layout.userData.disabled or false
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
            onCategoryChange(state.selectedCategory)
        else
            updateCategories()
        end

        replaceSearchBar(element.layout.content.topBar.content.searchBar.content.padding.content.textEdit.props.text)
    end
    element.layout.userData.cycleCategory = cycleCategory

    element.layout.userData.setCategory = function(categoryKey)
        if state.selectedCategory ~= categoryKey then
            state.selectedCategory = categoryKey
            if onCategoryChange then
                onCategoryChange(state.selectedCategory)
            else
                updateCategories()
            end
        end
    end

    element.layout.userData.getCategory = function()
        return state.selectedCategory
    end

    return element
end

return CategoryFilter