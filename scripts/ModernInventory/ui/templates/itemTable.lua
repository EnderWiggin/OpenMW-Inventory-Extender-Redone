-- filepath: c:\MorrowindMods\UserInterface\ModernInventory\scripts\ModernInventory\ui\templates\itemTable.lua
local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')

local constants = require('scripts.ModernInventory.util.constants')
local baseTemplates = require('scripts.ModernInventory.ui.templates.base')
local specialTemplates = require('scripts.ModernInventory.ui.templates.magic')

local ItemTable = {}

local function setColumnWidths(columns)
    local widths = {}
    for i, col in ipairs(columns) do
        widths[i] = col.width
    end
    return widths
end

-- Default sort comparator
local function compareItems(a, b, field, direction)
    local valA = a[field]
    local valB = b[field]
    
    -- Handle nils (push to bottom usually)
    if valA == nil and valB == nil then return false end
    if valA == nil then return false end
    if valB == nil then return true end
    
    if direction == 'asc' then
        return valA < valB
    else
        return valA > valB
    end
end

ItemTable.create = function(props)
    local columns = props.columns or {}
    local dataRows = props.data or {}
    local size = props.size or util.vector2(400, 300)
    local rowHeight = props.rowHeight or 30
    local onRowClick = props.onRowClick
    
    local headerHeight = 30
    local scrollbarWidth = 16
    
    local state = {
        sortedRows = {},      -- List of items after sorting
        sortColIndex = nil,   -- Index of currently sorted column
        sortDir = 'asc',      -- 'asc' or 'desc'
        columnWidths = {}
    }
    
    for _, item in ipairs(dataRows) do
        table.insert(state.sortedRows, item)
    end
    
    local scrollable
    local updateRows
    local sortRows
    
    local contentWidth = math.floor(math.max(0, size.x - scrollbarWidth))
    state.columnWidths = setColumnWidths(columns)
    
    sortRows = function()
        if not state.sortColIndex then return end
        
        local col = columns[state.sortColIndex]
        local field = col.id
        
        table.sort(state.sortedRows, function(a, b)
            if col.comparator then
                return col.comparator(a, b, state.sortDir)
            else
                return compareItems(a, b, field, state.sortDir)
            end
        end)
    end

    state.rowCache = {} -- Stores generated row layouts by item ID or index

    local function renderVisibleRows()
        if not scrollable then return end

        local contentLayer = scrollable.layout.content[1]
        contentLayer.type = ui.TYPE.Widget
        local viewHeight = size.y - headerHeight

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
            local item = state.sortedRows[i]
            if item then
                local cacheKey = item

                if not state.rowCache[cacheKey] then
                    local cells = {}

                    for cIdx, col in ipairs(columns) do
                        local w = state.columnWidths[cIdx] or 0
                        local cellContent

                        if col.renderer then
                            cellContent = col.renderer(item, w, rowHeight)
                        else
                            local val = item[col.id]
                            local textStr = val ~= nil and tostring(val) or ""
                            cellContent = {
                                template = baseTemplates.textNormal,
                                props = {
                                    text = textStr,
                                    size = util.vector2(w, rowHeight),
                                    autoSize = false,
                                },
                                external = {
                                    grow = (w == 0) and 1 or nil,
                                }
                            }
                        end

                        table.insert(cells, cellContent)
                    end

                    state.rowCache[cacheKey] = specialTemplates.interactive({ onClick = function() end }, {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                            size = util.vector2(contentWidth, rowHeight),
                            position = util.vector2(0, 0),
                        },
                        content = ui.content(cells),
                        events = {
                            mousePress = async:callback(function()
                                if onRowClick then onRowClick(item) end
                            end)
                        },
                        userData = { item = item }
                    })
                end

                local rowWidget = state.rowCache[cacheKey]
                local rowY = (i - 1) * rowHeight

                if rowWidget.layout.props.position.y ~= rowY then
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
        
        local viewHeight = size.y - headerHeight
        local totalHeight = math.floor(math.max(#state.sortedRows * rowHeight, viewHeight)) -- At least view height to prevent collapse
        
        scrollable.layout.userData.update(
            util.vector2(size.x, viewHeight), 
            util.vector2(size.x - scrollbarWidth, totalHeight)
        )
        
        renderVisibleRows()
    end

    local headerElements = {}
    for i, col in ipairs(columns) do
        local w = state.columnWidths[i] or 0
        local title = col.label or col.id
        
        if state.sortColIndex == i then
            title = title .. (state.sortDir == 'asc' and ' ^' or ' v')
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
                updateRows() 
            end
        }, {
            template = baseTemplates.textHeader,
            props = {
                text = title,
                size = util.vector2(w, headerHeight),
                autoSize = false,
            },
            external = {
                grow = (w == 0) and 1 or nil,
            }
        })
        table.insert(headerElements, btn)
    end
    
    local headerRow = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            size = util.vector2(contentWidth, headerHeight),
        },
        content = ui.content(headerElements)
    }

    local dummyContent = ui.content({}) 
    local totalY = #state.sortedRows * rowHeight
    local flexSize = util.vector2(contentWidth, totalY)
    
    scrollable = baseTemplates.scrollable(
        util.vector2(size.x, size.y - headerHeight),     -- Widget Size
        dummyContent,                                    -- Initial Content
        flexSize,                                        -- Inner scrollable area size
        0,                                               -- Padding
        0,                                               -- Border
        rowHeight,                                       -- Scroll Step
        true,                                           -- Always show bar
        function() end,                                  -- onFocusGain
        function() end,                                  -- onFocusLoss
        0,                                               -- Start pos
        'itemTable_Scroll'
    )
    
    local originalOnScroll = scrollable.layout.userData.onScroll
    scrollable.layout.userData.onScroll = function()
        originalOnScroll()
        renderVisibleRows()
    end
    
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
        }
    }
    
    return wrapper
end

return ItemTable