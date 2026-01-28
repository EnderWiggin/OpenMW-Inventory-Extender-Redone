-- filepath: c:\MorrowindMods\UserInterface\ModernInventory\scripts\ModernInventory\ui\templates\itemTable.lua
local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')

local constants = require('scripts.ModernInventory.util.constants')
local baseTemplates = require('scripts.ModernInventory.ui.templates.base')
local specialTemplates = require('scripts.ModernInventory.ui.templates.magic')

local ItemTable = {}

local function setColumnWidths(columns, state)
    local contentWidth = math.floor(math.max(0, state.currentSize.x - 16)) -- scrollbarWidth = 16
    local widths = {}
    local fixedWidth = 0
    local flexCount = 0
    
    for i, col in ipairs(columns) do
        if col.width then
            widths[i] = col.width
            fixedWidth = fixedWidth + col.width
        else
            flexCount = flexCount + 1
        end
    end
    
    local remainingWidth = math.max(0, contentWidth - fixedWidth)
    local flexWidth = flexCount > 0 and math.floor(remainingWidth / flexCount) or 0
    
    for i, col in ipairs(columns) do
        if not col.width then
            widths[i] = flexWidth
        end
    end
    
    state.columnWidths = widths
end

-- Default sort comparator
local function compareItems(a, b, field, direction)
    local valA = a[field]
    local valB = b[field]

    if type(valA) == 'string' then valA = valA:lower() end
    if type(valB) == 'string' then valB = valB:lower() end
    
    if valA == nil and valB == nil then return false end
    if valA == nil then return false end
    if valB == nil then return true end
    
    if direction == 'asc' then
        return valA < valB
    else
        return valA > valB
    end
end
ItemTable.create = function(props, ctx)
    local columns = props.columns or {}
    local dataRows = props.data or {}
    local size = props.size or util.vector2(400, 300)
    local rowHeight = props.rowHeight or 30
    local onRowClick = props.onRowClick

    -- New props for default sort logic
    local defaultSortId = props.defaultSortId
    local defaultSortIcon = props.defaultSortIcon
    local fallbackSort = props.fallbackSort
    
    local headerHeight = 30
    local scrollbarWidth = 16
    
    local state = {
        sortedRows = {},      -- List of items after sorting
        sortColIndex = nil,   -- Index of currently sorted column
        sortDir = 'asc',      -- 'asc' or 'desc'
        columnWidths = {},
        currentSize = size,   
    }

    setColumnWidths(columns, state)
    
    -- Initialize defaults
    for i, col in ipairs(columns) do
        if col.id == defaultSortId then
            state.sortColIndex = i
            break
        end 
    end
    
    for _, item in ipairs(dataRows) do
        table.insert(state.sortedRows, item)
    end
    
    local scrollable
    local updateRows
    local sortRows
    local headerRow
    
    local function getContentWidth()
        return math.floor(math.max(0, state.currentSize.x - scrollbarWidth))
    end
    
    sortRows = function()
        if not state.sortColIndex then return end
        
        local col = columns[state.sortColIndex]
        local field = col.id
        local isDefaultCol = (col.id == defaultSortId)
        
        table.sort(state.sortedRows, function(a, b)
            -- Case 1: If sorting by the default column, strictly use fallback sorter
            if isDefaultCol and fallbackSort then
                return fallbackSort(a, b, state.sortDir)
            end

            -- Case 2: Standard comparison with tiebreaker
            local result
            local areEqual = false
            
            if col.comparator then
                if col.comparator(a, b, state.sortDir) then return true end
                if col.comparator(b, a, state.sortDir) then return false end
                areEqual = true
            else
                local valA = a[field]
                local valB = b[field]
                if valA == valB then 
                    areEqual = true 
                else
                    result = compareItems(a, b, field, state.sortDir)
                end
            end

            -- Use fallbackSort as tiebreaker
            if areEqual and fallbackSort then
                return fallbackSort(a, b, state.sortDir)
            end
            
            return result
        end)
    end

    state.rowCache = {} -- Stores generated row layouts by item ID or index

    local function renderVisibleRows()
        if not scrollable then return end

        local contentLayer = scrollable.layout.content[1]
        contentLayer.type = ui.TYPE.Widget
        local viewHeight = state.currentSize.y - headerHeight
        local contentWidth = getContentWidth()

        -- Virtualization mathematics
        -- contentLayer.props.position.y is negative when scrolled down
        local scrollY = -contentLayer.props.position.y
        local startIndex = math.floor(scrollY / rowHeight)
        local visibleCount = math.ceil(viewHeight / rowHeight)
        
        -- Add buffer to render slightly outside viewport for smoothness
        local buffer = 1
        local indexFrom = math.max(1, startIndex + 1 - buffer)
        local indexTo = math.min(#state.sortedRows, startIndex + visibleCount + buffer)
        
        local newRowElements = {}

        local currentContent = contentLayer.content
        local k = 1

        for i = indexFrom, indexTo do
            local row = state.sortedRows[i]
            if row then
                local cacheKey = row

                if not state.rowCache[cacheKey] then
                    local cells = {}

                    local totalW = 0
                    for cIdx, col in ipairs(columns) do
                        local w = state.columnWidths[cIdx] or 0
                        local cellContent

                        if col.renderer then
                            cellContent = col.renderer(row, w, rowHeight)
                        else
                            local val = row[col.id]
                            local textStr = val ~= nil and tostring(val) or ""
                            cellContent = {
                                template = baseTemplates.textNormal,
                                props = {
                                    text = textStr,
                                    size = util.vector2(w, rowHeight),
                                    autoSize = false,
                                },
                                userData = {
                                    colorable = true,
                                }
                            }
                        end
                        cellContent.props.position = util.vector2(totalW, 0)
                        totalW = totalW + w

                        table.insert(cells, cellContent)
                    end

                    state.rowCache[cacheKey] = specialTemplates.interactive({ 
                        onClick = function() end,
                        name = row.item.id,
                    }, {
                        props = {
                            size = util.vector2(contentWidth, rowHeight),
                            position = util.vector2(0, 0),
                        },
                        content = ui.content(cells),
                        events = {
                            mousePress = async:callback(function()
                                if onRowClick then onRowClick(row) end
                            end)
                        },
                        userData = { 
                            item = row,
                            tooltipFn = function()
                                return specialTemplates.itemTooltip(row.item)
                            end,
                        }
                    })
                else
                    local totalW = 0
                    for cIdx, col in ipairs(columns) do
                        local w = state.columnWidths[cIdx] or 0
                        local cellContent = state.rowCache[cacheKey].layout.content[cIdx]
                        local helpers = require('scripts.ModernInventory.util.helpers')
                        cellContent.props.size = util.vector2(w, rowHeight)
                        cellContent.props.position = util.vector2(totalW, 0)
                        totalW = totalW + w
                    end
                end

                local rowWidget = state.rowCache[cacheKey]
                local rowY = (i - 1) * rowHeight

                if rowWidget.layout.props.size.x ~= contentWidth or rowWidget.layout.props.position.y ~= rowY then
                    rowWidget.layout.props.size = util.vector2(contentWidth, rowHeight)
                    rowWidget.layout.props.position = util.vector2(0, rowY)
                    rowWidget:update()
                end

                if currentContent[k] ~= rowWidget then
                    currentContent[k] = rowWidget
                end
                k = k + 1
            end
        end

        while k <= #currentContent do
            currentContent[k] = nil
            k = k + 1
        end

        for i = 1, k - 1 do
            newRowElements[i] = currentContent[i]
        end

        contentLayer.content = ui.content(newRowElements)
        scrollable:update()
    end
    
    updateRows = function()
        if not scrollable then return end
        
        local viewHeight = state.currentSize.y - headerHeight
        local totalHeight = math.floor(math.max(#state.sortedRows * rowHeight, viewHeight))
        
        scrollable.layout.userData.update(
            util.vector2(state.currentSize.x, viewHeight), 
            util.vector2(state.currentSize.x - scrollbarWidth, totalHeight)
        )
        
        renderVisibleRows()
    end

    local function updateHeader()
        if not headerRow then return end
        
        local contentWidth = getContentWidth()
        headerRow.props.size = util.vector2(contentWidth, headerHeight)
        
        for i, headerCell in ipairs(headerRow.content) do
            local w = state.columnWidths[i] or 0
            if headerCell.layout and headerCell.layout.props.size.x ~= w then
                headerCell.layout.props.size = util.vector2(w, headerHeight)
                headerCell:update()
            end
        end
    end

    local headerElements = {}
    for i, col in ipairs(columns) do
        local w = state.columnWidths[i] or 0
        local title = col.label or col.id
        local isDefaultCol = (col.id == defaultSortId)
        
        local headerWidget
        
        if isDefaultCol and defaultSortIcon then
            headerWidget = {
                type = ui.TYPE.Flex,
                props = {
                    size = util.vector2(w, headerHeight),
                    horizontal = true,
                    align = ui.ALIGNMENT.Center,
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content({
                    {
                        type = ui.TYPE.Image,
                        props = {
                            resource = ui.texture { path = defaultSortIcon },
                            size = util.vector2(16, 16),
                        }
                    }
                }),
            }
        else
            if state.sortColIndex == i then
                title = title .. (state.sortDir == 'asc' and ' ^' or ' v')
            end
            
            headerWidget = {
                template = baseTemplates.textHeader,
                props = {
                    text = title,
                    size = util.vector2(w, headerHeight),
                    autoSize = false,
                    textAlignV = ui.ALIGNMENT.Center,
                },
            }
        end
        
        local btn = specialTemplates.interactive({
            onClick = function()
            if state.sortColIndex == i then
                state.sortDir = (state.sortDir == 'asc') and 'desc' or 'asc'
            else
                state.sortColIndex = i
                state.sortDir = 'asc'
            end
            
            sortRows()
            
            -- Scroll to top when sort changes
            if scrollable and scrollable.layout.content[1] then
                scrollable.layout.content[1].props.position = util.vector2(0, 0)
            end
            
            updateRows()
            end
        }, headerWidget)
        table.insert(headerElements, btn)
    end
    
    headerRow = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            size = util.vector2(getContentWidth(), headerHeight),
        },
        content = ui.content(headerElements)
    }

    local dummyContent = ui.content({}) 
    local totalY = #state.sortedRows * rowHeight
    local flexSize = util.vector2(getContentWidth(), totalY)
    
    scrollable = baseTemplates.scrollable(
        util.vector2(size.x, size.y - headerHeight),
        dummyContent,
        flexSize,
        0,
        0,
        rowHeight * 2,
        true,
        function(e)
            ctx.focusedScrollable = e
        end,
        function()
            ctx.focusedScrollable = nil
        end,
        0,
        'itemTable_Scroll'
    )
    
    local originalOnScroll = scrollable.layout.userData.onScroll
    scrollable.layout.userData.onScroll = function()
        originalOnScroll()
        renderVisibleRows()
    end
    
    sortRows()
    updateRows()

    local wrapper = ui.create {
        type = ui.TYPE.Flex, 
        props = {
            vertical = true,
            size = size,
        },
        content = ui.content {
            headerRow,
            scrollable
        },
        userData = {},
    }
    
    wrapper.layout.userData.resize = function(newSize)
        state.currentSize = newSize
        setColumnWidths(columns, state)
        wrapper.layout.props.size = newSize
        updateHeader()
        updateRows()
        wrapper:update()
    end
    
    return wrapper
end

return ItemTable