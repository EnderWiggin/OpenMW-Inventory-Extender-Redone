---@omw-context player

local ui = require('openmw.ui')
local util = require('openmw.util')

local v2 = util.vector2

local I = require('openmw.interfaces')

local Class = require('scripts.UIToolkit.class')
local Component = require('scripts.UIToolkit.components.component')
local ItemList = require('scripts.UIToolkit.components.item_list')
local ColumnItemProvider = require('scripts.UIToolkit.components.list_items.column_item')
local GridIconProvider = require('scripts.InventoryExtenderRedone.toolkit.grid_icon_provider')
local L = require('scripts.InventoryExtenderRedone.util.logger').get 'IT'
local controllerMenus = I.GamepadControls.isControllerMenusEnabled()


---@class IER.CustomList: UIToolkit.ItemList
local CustomList = Class(ItemList)

---@param idOrIndex string|integer|nil
function CustomList:setHovered(idOrIndex)
    local row = self:getHovered() --[[@as InventoryExtenderRedone.RowData]]
    ItemList.setHovered(self, idOrIndex)
    if controllerMenus then
        self:updateActiveState(row, false)
        row = self:getHovered() --[[@as InventoryExtenderRedone.RowData]]
        self:updateActiveState(row, true)
    end
end

---@param row InventoryExtenderRedone.RowData?
---@param value boolean
function CustomList:updateActiveState(row, value)
    if not row then return end
    local wdg = self.state.provider:getCachedComponent(row.id)
    if not wdg then return end
    wdg:setActive(value)
end

---@class InventoryExtenderRedone.ItemTable : UIToolkit.Component
---@field new fun(self:InventoryExtenderRedone.ItemTable):InventoryExtenderRedone.ItemTable
local ItemTable = Class(Component)

---@param sort UIToolkit.ColumnComparator|UIToolkit.SimpleColumnComparatorConfig|nil
---@return UIToolkit.ColumnComparator|nil
local function convertSort(sort)
    if not sort then return nil end
    if type(sort) == 'function' then
        return sort
    end
    if type(sort) == 'table' then
        local _col = sort.col
        local numeric = sort.numeric
        return function(a, b, col)
            col = _col or col
            if not col then return 0 end
            local vA = a[col]
            local vB = b[col]
            if type(vA) == 'function' then vA = vA() end
            if type(vB) == 'function' then vB = vB() end

            if numeric then
                if type(vA) ~= 'number' then vA = tonumber(vA) or 0 end
                if type(vB) ~= 'number' then vB = tonumber(vB) or 0 end
            end

            if vA == vB then return 0 end
            return vA < vB and -1 or 1
        end
    end
    return nil
end

---@param opts InventoryExtenderRedone.ItemTableOpts
function ItemTable:init(opts)
    self.size = opts.size
    self.defaultSort = convertSort(opts.defaultSort)
    ---@type UIToolkit.ColumnComparator[]
    self.comparators = {}
    ---@type InventoryExtenderRedone.RowData[]
    self.allItems = {}
    ---@type InventoryExtenderRedone.RowData[]
    self.filteredItems = {}
    ---@type UIToolkit.SortedList.Filter?
    self._filter = nil
    self.showGrid = opts.showGrid == true

    local theme = I.UIToolkit.getTheme()
    local rowHeight = opts.rowHeight or util.round(theme.Sizes.listRowScale * theme.Sizes.lineHeight)

    self.provider = ColumnItemProvider:new()

    ---@type UIToolkit.ListData.ColumnConfig[]
    local providerColumns = {}
    ---@type UIToolkit.ColumnSorter.Column[]
    local headerColumns = {}

    for i = 1, #opts.columns do
        local cfg = opts.columns[i]

        providerColumns[#providerColumns + 1] = {
            id = cfg.id,
            width = cfg.width,
            auto = cfg.auto,
            render = cfg.render,
            update = cfg.update,
            arg = cfg.arg,
        }

        headerColumns[#headerColumns + 1] = {
            id = cfg.id,
            name = cfg.name,
            width = cfg.width,
            auto = cfg.auto,
            align = cfg.align,
            inactive = not cfg.sort,
            descending = cfg.descending,
        }

        self.comparators[cfg.id] = convertSort(cfg.sort)
    end

    self.provider:init(providerColumns, rowHeight)
    self.provider:setHiddenColumns(opts.hiddenColumns)

    self.list = CustomList:new()
    self.list:init {
        size = self:getListSize(),
        provider = self.provider,
        onItemClicked = opts.onItemClicked,
        onItemRClicked = opts.onItemRClicked,
        onItemClickedAny = opts.onItemClickedAny,
        onListClicked = opts.onListClicked,
        scrollWidth = opts.scrollWidth,
        slimScroll = opts.slimScroll,
        noBorder = opts.noBorder,
        -- rows per arrow click; library default is 2, nil keeps it
        scrollStep = opts.scrollStep,
    }

    self.gridProvider = GridIconProvider:new()
    self.gridProvider.getBadges = opts.getBadges

    self.list:setVisible(not self.showGrid)

    self.grid = I.UIToolkit.Components.itemGrid {
        size = self:getListSize(),
        provider = self.gridProvider,
        horizontal = opts.horizontalGrid == true,
        onItemClicked = opts.onItemClicked,
        onItemRClicked = opts.onItemRClicked,
        onItemClickedAny = opts.onItemClickedAny,
        onListClicked = opts.onListClicked,
        scrollWidth = opts.scrollWidth,
        slimScroll = opts.slimScroll,
        noBorder = opts.noBorder,
        -- same setting as the list, but counted in icons here
        scrollStep = opts.scrollStep,
    }
    self.grid:setVisible(self.showGrid)

    self.header = I.UIToolkit.Components.columnSorter {
        columns = headerColumns,
        default = opts.defaultColumn,
        hidden = opts.hiddenColumns,
        onChanged = function() self:sort() end,
    }

    self.header:updateProps {
        position = v2(opts.noBorder and 0 or theme.Sizes.border + theme.Sizes.padding, 0),
    }

    self.list:updateProps { position = v2(0, rowHeight) }
    self.grid:updateProps { position = v2(0, rowHeight) }

    Component.init(self, ui.create {
        props = {
            size = opts.size,
        },
        content = ui.content {
            self.header.element,
            self.list.element,
            self.grid.element,
        }
    })

    self:setSize(opts.size)
end

function ItemTable:refresh()
    if self.showGrid then
        self.grid:setItems(self.filteredItems)
    else
        self.list:setItems(self.filteredItems)
    end
end

function ItemTable:setShowGrid(value)
    local p = self.showGrid and self.grid:getPosition() or self.list:getPosition()
    self.showGrid = value
    self.list:setVisible(not value)
    self.grid:setVisible(value)
    self:refresh()
    if value then
        self.grid:setSize(self:getListSize())
        self.grid:setPosition(p)
    else
        self.list:setSize(self:getListSize())
        self.list:setPosition(p)
    end
    self.header:updateProps { size = self:getHeaderSize() }
    I.UIToolkit.queueUpdate(self.header.element)
end

---@param refresh boolean?
function ItemTable:sort(refresh)
    local items = self.filteredItems
    local col, asc = self.header:getActiveColumn()
    local comparator = col ~= nil and self.comparators[col]
    table.sort(items, function(a, b)
        local result = 0

        if comparator then result = comparator(a, b, col) end

        if result == 0 and self.defaultSort then result = self.defaultSort(a, b, col) end

        if result ~= 0 then
            if not asc then result = -result end
            return result < 0
        end
        return a.id < b.id
    end)

    if refresh ~= false then self:refresh() end
end

---@param filter UIToolkit.SortedList.Filter|nil
function ItemTable:setFilter(filter)
    if self._filter == filter then return end
    self._filter = filter
    self:filter(false)
    self:refresh()
end

---@param refresh boolean?
function ItemTable:filter(refresh)
    local filter = self._filter
    if filter then
        local filtered = {}
        for i = 1, #self.allItems do
            local item = self.allItems[i]
            if filter(item) then filtered[#filtered + 1] = item end
        end
        self.filteredItems = filtered
    else
        self.filteredItems = self.allItems
    end
    self:sort(false)

    if refresh ~= false then self:refresh() end
end

---@param hidden? table<string, boolean>
function ItemTable:setHiddenColumns(hidden)
    if self:isDestroyed() then return end
    self.header:setHiddenColumns(hidden)
    self.provider:setHiddenColumns(hidden)
    self:refresh()
end

function ItemTable:getVisibleColumnIds()
    local visible = {}
    local columns = self.header.columns
    local hidden = self.header.hidden
    for i = 1, #columns do
        local id = columns[i].id
        if not hidden[id] then
            visible[#visible + 1] = id
        end
    end
    return visible
end

function ItemTable:nextActiveColumn(asc)
    if self:isDestroyed() then return end
    local id = self.header:getActiveColumn()
    local visible = self:getVisibleColumnIds()
    local nextId = nil
    if id then
        local found = false
        for i = 1, #visible do
            if found then
                nextId = visible[i]
                break
            elseif visible[i] == id then
                found = true
            end
        end
    end
    nextId = nextId or visible[1]

    self.header:toggleColumn(nextId, asc)
end

function ItemTable:prevActiveColumn(asc)
    if self:isDestroyed() then return end
    local id = self.header:getActiveColumn()
    local visible = self:getVisibleColumnIds()
    local prevId = nil
    if id then
        local found = false
        for i = #visible, 1, -1 do
            if found then
                prevId = visible[i]
                break
            elseif visible[i] == id then
                found = true
            end
        end
    end
    prevId = prevId or visible[#visible]

    self.header:toggleColumn(prevId, asc)
end

---@param items UIToolkit.ListData.Column[]
function ItemTable:setItems(items)
    self.allItems = items
    self:filter()
    for i = 1, #self.filteredItems do
        local row = self.filteredItems[i]
        local cached = self.provider:getCachedComponent(row.id)
        if cached and cached:isActive() then cached:setActive(false) end
    end
    L.debug('setItems', #items, #self.filteredItems, self.showGrid)
end

---@param size openmw.util.Vector2
function ItemTable:setSize(size)
    self.size = size

    if self.showGrid then
        self.grid:setSize(self:getListSize())
    else
        self.list:setSize(self:getListSize())
    end
    L.debug('setSize', size, self:getListSize())

    self.header:updateProps { size = self:getHeaderSize() }
    I.UIToolkit.queueUpdate(self.header.element)

    self:updateProps { size = size }
    I.UIToolkit.queueUpdate(self.element)
end

function ItemTable:setPosition(p)
    if self.showGrid then
        self.grid:setPosition(p)
    else
        self.list:setPosition(p)
    end
end

---@return InventoryExtenderRedone.RowData?, integer?
function ItemTable:getHovered()
    local row, idx
    if self.showGrid then
        row, idx = self.grid:getHovered()
    else
        row, idx = self.list:getHovered()
    end
    ---@cast row InventoryExtenderRedone.RowData?
    return row, idx
end

---@param id string
---@return InventoryExtenderRedone.RowData?, integer?
function ItemTable:getItemById(id)
    local row, idx
    if self.showGrid then
        row, idx = self.grid:getItemById(id)
    else
        row, idx = self.list:getItemById(id)
    end
    ---@cast row InventoryExtenderRedone.RowData?
    return row, idx
end

---@param idOrIndex string|integer|nil
---@param highlight boolean? if true and mode is grid - will highlight item
function ItemTable:setHovered(idOrIndex, highlight)
    if self.showGrid then
        return self.grid:setHovered(idOrIndex, highlight)
    else
        return self.list:setHovered(idOrIndex)
    end
end

---@param shift openmw.util.Vector2
function ItemTable:shiftHoveredItem(shift)
    if self.showGrid then
        return self.grid:shiftHoveredItem(shift)
    else
        return self.list:shiftHoveredItem(shift.y)
    end
end

---@param idOrIndex string|integer
---@param strict boolean? if true, only fully visible items count as in view. Defaults to true
---@return boolean scrolled
function ItemTable:scrollIntoView(idOrIndex, strict)
    if self.showGrid then
        return self.grid:scrollIntoView(idOrIndex, strict)
    else
        return self.list:scrollIntoView(idOrIndex, strict)
    end
end

---@return UIToolkit.Scrollable
function ItemTable:currentScrollable()
    if self.showGrid then
        return self.grid
    else
        return self.list
    end
end

---@return openmw.util.Vector2
function ItemTable:getListSize()
    return self.size - v2(0, self.provider.rowHeight)
end

---@return openmw.util.Vector2
function ItemTable:getHeaderSize()
    if self.showGrid then
        return v2(self.grid:getContentSize().x, self.provider.rowHeight)
    else
        return v2(self.list:getContentWidth(), self.provider.rowHeight)
    end
end

return ItemTable
