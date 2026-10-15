---@omw-context player


local ambient   = require 'openmw.ambient'
local core      = require 'openmw.core'
local input     = require 'openmw.input'
local ui        = require 'openmw.ui'
local util      = require 'openmw.util'
local storage   = require 'openmw.storage'
local types     = require 'openmw.types'
local omwself   = require 'openmw.self'
local aux_util  = require 'openmw_aux.util'

local I         = require 'openmw.interfaces'
local v2        = util.vector2
local KEY       = input.KEY
local BUTTON    = input.CONTROLLER_BUTTON

local Actor     = types.Actor
local Container = types.Container
local Item      = types.Item
local NPC       = types.NPC


local configPlayer = require('scripts.InventoryExtenderRedone.config.player')
local D = require('scripts.InventoryExtenderRedone.config.defaults')
local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local barterUtils = require('scripts.InventoryExtenderRedone.util.barter')
local constants = require('scripts.InventoryExtenderRedone.util.constants')
local iconPack = require('scripts.InventoryExtenderRedone.util.iconPack')
local persistentCorpses = require('scripts.InventoryExtenderRedone.util.persistentCorpses')
local l10n = core.l10n(D.L10N)
local Pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')
local InfoBar = require('scripts.InventoryExtenderRedone.toolkit.info_bar')
local BarterControls = require('scripts.InventoryExtenderRedone.toolkit.barter_controls')
local GridIcon = require('scripts.InventoryExtenderRedone.toolkit.grid_icon_provider')
local ItemTable = require('scripts.InventoryExtenderRedone.toolkit.item_table')
local ItemStackModal = require('scripts.InventoryExtenderRedone.toolkit.item_stack_modal')


local H              = require 'scripts.UIToolkit.helpers'
local C              = require 'scripts.UIToolkit.constants'
local Class          = require 'scripts.UIToolkit.class'
local WindowHandler  = require 'scripts.UIToolkit.window_handler'
local ColumnItem     = require 'scripts.UIToolkit.components.list_items.column_item'
local CompoundFilter = require 'scripts.UIToolkit.compound_filter'
local Tooltips       = I.UTKTooltips
local Toolkit        = I.UIToolkit
local Components     = Toolkit.Components
local T              = Toolkit.Templates


local playerWindowSettings = storage.playerSection(D.Section.Window)
local windowOptionsSection = storage.playerSection('InventoryExtender')
local columnVisibilityKey  = 'ColumnVisibility'


---@class IER.Inventory.SaveData
---@field sortingColumn string?
---@field sortingDirection boolean?

local CategoryFilter = require('scripts.InventoryExtenderRedone.toolkit.categoryFilter')

local function getEnchantedIndicatorMode()
    return configPlayer.tweaks.s_EnchantedIndicatorMode or 'EnchantedIndicatorMode_Both'
end

local function shouldShowEnchantedSwirl()
    return getEnchantedIndicatorMode() ~= 'EnchantedIndicatorMode_Icon'
end

local function shouldShowEnchantedNameIcon()
    return getEnchantedIndicatorMode() ~= 'EnchantedIndicatorMode_Swirl'
end

local function getSyncedCategoryKey(categoryKey, targetWindow)
    if categoryKey == 'Favorites' and targetWindow and targetWindow.target ~= omwself then
        return 'All'
    end
    return categoryKey
end

---@type UIToolkit.ListItem.Column.Renderer
local function iconRenderer(data, cfg, height)
    ---@cast data InventoryExtenderRedone.RowData
    local width = cfg.width or height
    local sz = cfg.arg and cfg.arg.sz or math.min(height, width or height)
    local showEnchantSwirl = data.showAsEnchanted() and shouldShowEnchantedSwirl() or false
    return GridIcon.renderIcon(data, v2(width, height), v2(sz, sz), v2(sz, sz), showEnchantSwirl)
end

---@param data InventoryExtenderRedone.RowData
---@type UIToolkit.ListItem.Column.Updater
local function iconUpdater(part, data)
    local changed = false

    local props = H.props(part.content['itemIcon'])
    local tex = Toolkit.texture(data.itemRecord.icon)
    if tex ~= props.resource then
        props.resource = tex
        changed = true
    end

    local ctx = I.InventoryExtenderRedone.getContext()
    local showEnchantSwirl = data.showAsEnchanted() and shouldShowEnchantedSwirl() or false
    local equipped = helpers.isItemEquipped(data.item, data.item.parentContainer, ctx.overrides.equipped)
    props = H.props(part.content['itemBackground'])
    tex = GridIcon.getBackgroundTexture(data.isBartered, equipped, showEnchantSwirl)

    if tex ~= props.resource then
        props.resource = tex
        changed = true
    end

    return changed
end

---@param value any
---@return string
local function formatNumber(value)
    if type(value) == 'function' then
        value = value()
    end

    if value == 0 or value == nil then
        return '-'
    elseif type(value) == 'number' then
        return H.addSeparators(H.roundToPlaces(value, 2))
    end
    return tostring(value)
end

---@type UIToolkit.ListItem.Column.Renderer
local function renderNumber(data, cfg, height)
    local textSize = cfg.arg and cfg.arg.textSize or nil
    local textAlignH = cfg.arg and cfg.arg.textAlignH or nil
    ---@type openmw.ui.Layout
    local layout = {
        name = cfg.id,
        template = T.text(),
        props = {
            textAlignV = ui.ALIGNMENT.Center,
            textAlignH = textAlignH,
            autoSize = false,
            textSize = textSize,
            text = formatNumber(data[cfg.id]),
        },
        userData = { colorable = true },
    }

    ColumnItem.applySize(layout, cfg, height)
    return layout
end

---@type UIToolkit.ListItem.Column.Updater
local function updateNumber(part, data, cfg)
    local new = formatNumber(data[cfg.id])
    local props = H.props(part)
    if props.text == new then return false end
    props.text = new
    return true
end

---@param row InventoryExtenderRedone.RowData
---@param type string
local function getNonDraggedCount(row, type)
    local nonDraggedCount = row.getCount()
    local ctx = I.InventoryExtenderRedone.getContext()

    local drag = ctx.dragAndDrop
    if drag.draggingObject and drag.draggingObject.id == row.item.id then
        nonDraggedCount = nonDraggedCount - drag.draggingCount
    end

    if I.UI.getMode() == 'Barter' then
        local buying = ctx.barterState.buying
        local selling = ctx.barterState.selling
        if row.isBartered then
            if type == 'Inventory' then
                local buy = buying[row.item.id]
                nonDraggedCount = buy and buy.count or 0
            else
                local sell = selling[row.item.id]
                nonDraggedCount = sell and sell.count or 0
            end
        else
            if type == 'Inventory' then
                local sell = selling[row.item.id]
                if sell then
                    nonDraggedCount = nonDraggedCount - (sell.count or 0)
                end
            elseif type == 'Trade' then
                local buy = buying[row.item.id]
                if buy then
                    nonDraggedCount = nonDraggedCount - (buy.count or 0)
                end
            end
        end
    end
    return nonDraggedCount
end

local function isStealing(actor, ownerInfo, variable)
    if not ownerInfo then return false end

    local ctx = I.InventoryExtenderRedone.getContext()
    if variable then
        local value = ctx.containerVariables[variable]
        if value and value ~= 0 then return false end
    end

    if ownerInfo.recordId and ownerInfo.recordId ~= actor.recordId then
        return true
    end

    if ownerInfo.factionId then
        local reqRank = ownerInfo.factionRank or 1
        if NPC.getFactionRank(actor, ownerInfo.factionId) < reqRank then
            return true
        end
    end
    return false
end


local function ALL_COLUMNS(defaultSort, nameRenderer, nameUpdater)
    local theme = Toolkit.getTheme()
    local textSize = theme.Sizes.textNormal
    local lineHeight = textSize + 2
    local fontRatio = textSize / 16
    local w = 60 * fontRatio

    ---@type UIToolkit.SortedList.Column[]
    return {
        {
            id = 'Icon',
            width = lineHeight * 1.5 + 8,
            sort = defaultSort,
            render = iconRenderer,
            update = iconUpdater,
        },
        {
            id = 'Name',
            name = l10n('Column_Name'),
            sort = { numeric = false },
            render = nameRenderer,
            update = nameUpdater,
        },
        {
            id = 'Type',
            name = l10n('Column_Type'),
            sort = { numeric = false },
            width = 90 * fontRatio,
            align = ui.ALIGNMENT.End,
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Class',
            name = l10n('Column_Class'),
            sort = { numeric = false },
            width = 60 * fontRatio,
            align = ui.ALIGNMENT.End,
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'AR',
            name = l10n('Column_AR'),
            sort = { numeric = true },
            width = 50 * fontRatio,
            align = ui.ALIGNMENT.End,
            descending = true,
            render = renderNumber,
            update = updateNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Damage',
            name = l10n('Column_Damage'),
            sort = { numeric = true },
            width = 60 * fontRatio,
            align = ui.ALIGNMENT.End,
            descending = true,
            render = renderNumber,
            update = updateNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Quality',
            name = l10n('Column_Quality'),
            sort = { numeric = true },
            width = 60 * fontRatio,
            align = ui.ALIGNMENT.End,
            descending = true,
            render = renderNumber,
            update = updateNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Condition',
            name = l10n('Column_Condition'),
            width = 55 * fontRatio,
            align = ui.ALIGNMENT.End,
            descending = true,
            render = renderNumber,
            update = updateNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
            ---@param a InventoryExtenderRedone.RowData
            ---@param b InventoryExtenderRedone.RowData
            sort = function(a, b)
                local aValue = helpers.getConditionPercent(a.item)
                local bValue = helpers.getConditionPercent(b.item)

                if aValue == bValue then
                    return 0
                end
                if aValue == nil then
                    return -1
                end
                if bValue == nil then
                    return 1
                end

                return aValue < bValue and -1 or 1
            end,
        },
        {
            id = 'Weight',
            name = l10n('Column_Weight'),
            sort = { numeric = true },
            width = w,
            align = ui.ALIGNMENT.End,
            descending = true,
            render = renderNumber,
            update = updateNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Weight_Total',
            name = l10n('Column_Weight_Total'),
            sort = { numeric = true },
            width = 70 * fontRatio,
            align = ui.ALIGNMENT.End,
            descending = true,
            render = renderNumber,
            update = updateNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Value',
            name = l10n('Column_Value'),
            sort = { numeric = true },
            width = w,
            align = ui.ALIGNMENT.End,
            descending = true,
            render = renderNumber,
            update = updateNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'V/W',
            name = l10n('Column_VW'),
            sort = { numeric = true },
            width = w,
            align = ui.ALIGNMENT.End,
            descending = true,
            render = renderNumber,
            update = updateNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        }
    }
end

local OptionalColumns = {
    Condition = true,
    Weight_Total = true,
    ['V/W'] = true,
}

local EditableColumns = {
    'Type',
    'Damage',
    'Class',
    'AR',
    'Quality',
    'Condition',
    'Weight',
    'Weight_Total',
    'Value',
    'V/W',
}

local function getColumnVisibility()
    return windowOptionsSection:getCopy(columnVisibilityKey) or {}
end

local function setColumnVisibility(columnId, visible)
    local visibility = getColumnVisibility()
    if visible then
        if OptionalColumns[columnId] then
            visibility[columnId] = true
        else
            visibility[columnId] = nil
        end
    else
        visibility[columnId] = false
    end
    windowOptionsSection:set(columnVisibilityKey, visibility)
end

local function resetHiddenColumns()
    windowOptionsSection:set(columnVisibilityKey, {})
end

local function isColumnVisible(columnId, visibility)
    visibility = visibility or getColumnVisibility()
    if OptionalColumns[columnId] then
        return visibility[columnId] == true
    end
    return visibility[columnId] ~= false
end

---@param columns {id:string}[]
---@param categoryHidden table<string, boolean>?
---@return table<string, boolean>
local function combineHiddenColumns(columns, categoryHidden)
    local hidden = {}
    local visibility = getColumnVisibility()
    local visible = 0

    for i = 1, #columns do
        local id = columns[i].id
        if not isColumnVisible(id, visibility) then
            hidden[id] = true
        else
            visible = visible + 1
        end
    end

    if categoryHidden then
        for k, v in pairs(categoryHidden) do
            if v then hidden[k] = true end
        end
    end

    if visible == 0 and columns[1] then
        hidden[columns[1].id] = nil
    end

    return hidden
end

local function getStorageSuffix(type)
    if type ~= 'Inventory' then return nil end
    local mode = I.UI.getMode()
    if mode == 'Barter' or mode == 'Container' or mode == 'Companion' then
        return ':' .. mode
    end
    return nil
end

local function canPickupItem(row, windowType, allowOutsideInterface)
    local mode = I.UI.getMode()
    if mode == 'Interface' then
        return true
    end

    if not allowOutsideInterface then
        return false
    end

    if mode == 'Container' or mode == 'Companion' then
        return true
    end

    if mode == 'Barter' then
        local effectiveWindowType = windowType
        if effectiveWindowType == 'Inventory' then
            return not row.isBartered
        end
        if effectiveWindowType == 'Trade' then
            return row.isBartered == true
        end
    end

    return false
end

---@class IER.Inventory: UIToolkit.WindowHandler
---@field new fun(self:IER.Inventory):IER.Inventory
---@field arg table
---@field wnd UIToolkit.Window
local Inventory = Class(WindowHandler)

function Inventory:init(type)
    self.type = type
end

---@param wnd UIToolkit.Window
---@param data any
---@param saved IER.Inventory.SaveData
function Inventory:onOpened(wnd, data, saved)
    self.arg = data
    self.wnd = wnd
    self.suffix = getStorageSuffix(self.type)
    local IE = I.InventoryExtenderRedone
    local ctx = IE.getContext()
    self.ctx = ctx
    self.mode = I.UI.getMode()

    if self.type == 'Inventory' then
        self.target = omwself
        if self.mode == 'Interface' then
            self.wnd:setPinnable(true)
        end
    else
        self.target = data
    end
    self.filter = CompoundFilter:new()
    self.filter:add('draggedItemFilter', function(row)
        local drag = ctx.dragAndDrop
        if drag.draggingObject then
            return row.item.id ~= drag.draggingObject.id or row.getCount() > drag.draggingCount
        end
        return true
    end)

    self.filter:add('barterFilter', function(row)
        if I.UI.getMode() ~= 'Barter' then return not row.isBartered end

        local item = row.item
        if helpers.isGold(item) then return false end

        if item.type.record(item).isKey then return false end

        local barterNpc = self.arg
        if not barterNpc then return false end
        local services = barterNpc.type.record(barterNpc).servicesOffered

        if not services.MagicItems or not row.itemRecord.enchant then
            for serviceName, type in pairs(constants.ServiceToType) do
                if type.objectIsInstance(item) then
                    if not services[serviceName] then
                        return false
                    end
                    break
                end
            end
        end

        local buying = ctx.barterState.buying
        local selling = ctx.barterState.selling

        if self.type == 'Inventory' then
            if row.isBartered then
                return buying[item.id] and buying[item.id].count > 0
            end

            local sellingCount = selling[item.id] and selling[item.id].count or 0
            return row.getCount() > sellingCount
        elseif self.type == 'Trade' then
            if self.target.type.hasEquipped(self.target, item) then
                return false
            end

            if row.isBartered then
                return selling[item.id] and selling[item.id].count > 0
            end

            local buyingCount = buying[item.id] and buying[item.id].count or 0
            return row.getCount() > buyingCount
        end
        return true
    end)

    self.filter:add('pickpocketVisibilityFilter', function(row)
        if self.type ~= 'Container' or I.UI.getMode() ~= 'Container' then
            return true
        end

        return Pickpocket.isVisible(ctx.pickpocket, row.item)
    end)

    ---@type string|nil
    local searchText = nil
    self.filter:add('search', function(row)
        if not searchText or searchText == '' then return true end

        if not row.SearchText then
            row.SearchText = helpers.getItemSearchText(row.item):lower()
        end
        return row.SearchText:find(searchText, 1, true) ~= nil
    end)

    local inner = wnd:getInnerSize()
    local theme = Toolkit.getTheme()
    local rowHeight = util.round(theme.Sizes.lineHeight * configPlayer.window.f_TableRowHeightMult)

    local function isFavorited(item)
        return item ~= nil and ctx.favoriteItems[item.id] == true
    end

    ---@param a InventoryExtenderRedone.RowData
    ---@param b InventoryExtenderRedone.RowData
    ---@type UIToolkit.ColumnComparator
    local function fallBackSort(a, b)
        if not self.target then
            return 0
        end

        if a.isBartered ~= b.isBartered then
            return a.isBartered and -1 or 1
        end

        local mode = self.mode
        local inBarterMode = mode == 'Barter'

        a.sortCache = a.sortCache or {}
        local aCache = a.sortCache --[[@as table]]
        b.sortCache = b.sortCache or {}
        local bCache = b.sortCache --[[@as table]]

        if aCache.isEquipped == nil then
            aCache.isEquipped = helpers.isItemEquipped(a.item, self.target, ctx.overrides.equipped)
        end
        if bCache.isEquipped == nil then
            bCache.isEquipped = helpers.isItemEquipped(b.item, self.target, ctx.overrides.equipped)
        end
        local aEquipped = aCache.isEquipped
        local bEquipped = bCache.isEquipped

        local aFavorite = isFavorited(a.item)
        local bFavorite = isFavorited(b.item)

        if inBarterMode then
            local config = configPlayer.window
            local reverseEquipped = config.b_SortingBarterReverseEquipped
            local reverseFavorite = config.b_SortingBarterReverseFavorite

            if reverseFavorite and not reverseEquipped then
                -- if only favorites are reversed, prioritize sorting by favorite status
                if aFavorite ~= bFavorite then
                    -- favorite items come last
                    return bFavorite and -1 or 1
                end

                if aEquipped ~= bEquipped then
                    -- equipped items come first
                    return aEquipped and -1 or 1
                end
            else
                if aEquipped ~= bEquipped then
                    -- equipped items come first, unless we reverse it
                    if reverseEquipped then
                        return bEquipped and -1 or 1
                    else
                        return aEquipped and -1 or 1
                    end
                end

                if aFavorite ~= bFavorite then
                    -- favorite items come first, unless we reverse it
                    if reverseFavorite then
                        return bFavorite and -1 or 1
                    else
                        return aFavorite and -1 or 1
                    end
                end
            end
        else
            if aEquipped ~= bEquipped then
                -- equipped items come first
                return aEquipped and -1 or 1
            end

            if aFavorite ~= bFavorite then
                -- favorite items come first
                return aFavorite and -1 or 1
            end
        end

        -- Second, sort by Category
        local indexA, indexB = aCache.category, bCache.category
        if not indexA or not indexB then
            local categories = IE.getCategories()
            for i = 1, #categories do
                local category = categories[i]
                if category.key ~= 'Favorites' and category.filter then
                    if not indexA and category.filter(a.item) then
                        indexA = i
                    end
                    if not indexB and category.filter(b.item) then
                        indexB = i
                    end
                end
                if indexA and indexB then
                    break
                end
            end
            indexA = indexA or math.huge
            indexB = indexB or math.huge
            aCache.category = indexA
            bCache.category = indexB
        end
        if indexA ~= indexB then
            return (indexA < indexB) and -1 or 1
        end

        if not aCache.type then aCache.type = (type(a.Type) == 'function' and a.Type() or a.Type or ''):lower() end
        local typeA = aCache.type
        if not bCache.type then bCache.type = (type(b.Type) == 'function' and b.Type() or b.Type or ''):lower() end
        local typeB = bCache.type
        if typeA ~= typeB then
            return typeA < typeB and -1 or 1
        end


        if not aCache.name then aCache.name = (type(a.Name) == "function" and a.Name() or a.Name):lower() end
        local nameA = aCache.name
        if not bCache.name then bCache.name = (type(b.Name) == "function" and b.Name() or b.Name):lower() end
        local nameB = bCache.name
        if nameA == nameB then
            if a.item.recordId == b.item.recordId then
                return a.item.id < b.item.id and -1 or 1
            end
            return a.item.recordId < b.item.recordId and -1 or 1
        end
        return nameA < nameB and -1 or 1
    end


    local function hasFavorites()
        for _, isFavorite in pairs(ctx.favoriteItems or {}) do
            if isFavorite then
                return true
            end
        end
        return false
    end

    local function getAvailableCategories()
        local categories = IE.getCategories()
        local filteredCategories = {}
        for _, category in ipairs(categories) do
            if category.key ~= 'Favorites' or (self.target == omwself and hasFavorites()) then
                table.insert(filteredCategories, category)
            end
        end
        return filteredCategories
    end

    local function trySyncedCategorySwitch(category)
        if ctx.syncingCategoryFilter then return end

        local invert = configPlayer.tweaks.b_InvertCategorySwitching
        local shouldSync = invert and input.isShiftPressed() or not invert and not input.isShiftPressed()
        if not shouldSync then return end

        ctx.syncingCategoryFilter = true
        I.InventoryExtenderRedone.forEachOpenWindow(function(targetWnd)
            ---@cast targetWnd IER.Inventory
            if targetWnd == self then return end
            targetWnd.categoryFilter:setCategory(getSyncedCategoryKey(category, targetWnd))
        end)
        ctx.syncingCategoryFilter = false
    end

    local function updateHiddenColumns(category)
        if not category then
            local categoryKey = self.categoryFilter:getCategory()
            category = categoryKey and IE.getCategory(categoryKey)
        end
        self.table:setHiddenColumns(combineHiddenColumns(
            self.table.header.columns,
            category and category.hiddenColumns
        ))
    end

    local function openColumnSettings()
        if self._closeSettingsPopup then
            self._closeSettingsPopup()
            self._closeSettingsPopup = nil
        end
        ---@type openmw.ui.LayoutOrElement[]
        local elements = {}

        for i = 1, #EditableColumns do
            if i > 1 then
                elements[#elements + 1] = T.intervalV(4)
            end
            local id = EditableColumns[i]
            local column = self.table.header:getColumnConfig(id)
            assert(column)

            elements[#elements + 1] = Toolkit.Components.checkbox {
                name = id,
                text = column.name,
                width = 200,
                default = isColumnVisible(id),
                accentedCheckmark = true,
                onValueChanged = function(value)
                    setColumnVisibility(id, value)
                    updateHiddenColumns()
                end,
            }.element
        end
        self._closeSettingsPopup = I.UIToolkit.Popups.show {
            title = l10n('UI_ColumnSettingsTitle'),
            body = {
                template = T.box { padding = 4 },
                props = {},
                content = ui.content { {
                    type = ui.TYPE.Flex,
                    props = {},
                    content = ui.content(elements)
                } }
            },
            buttons = { { text = constants.Strings.OK }, { text = l10n 'Popup_BTN_Defaults', onClicked = function()
                resetHiddenColumns()
                updateHiddenColumns()
            end } },
        }
    end

    local function getItemViewMode()
        return playerWindowSettings:getCopy('s_ItemViewMode')
    end

    local function toggleItemViewMode()
        local showGrid = getItemViewMode() ~= 'ItemViewMode_Grid'
        local newMode = showGrid and 'ItemViewMode_Grid' or 'ItemViewMode_Table'

        playerWindowSettings:set('s_ItemViewMode', newMode)

        I.InventoryExtenderRedone.forEachOpenWindow(function(handler)
            handler.table:setShowGrid(showGrid)
            if handler ~= self then
                handler.categoryFilter.updateViewModeButton()
            end
        end)
    end

    self.categoryFilter = CategoryFilter.create({
            maxHeight = 72,
            compact = configPlayer.tweaks.b_CompactCategoryFilter,
            vanillaStyle = configPlayer.tweaks.b_VanillaCategoryIcons,
            getCategories = getAvailableCategories,
            getCategoryDisabledLookup = function()
                if not self.table then return nil end

                self.filter:disable('category', true)
                local rows = self.filter:filter(self.table.allItems) --[[@as InventoryExtenderRedone.RowData[] ]]
                self.filter:disable('category', false)

                local categories = getAvailableCategories()
                local disabledLookup = {}

                for i = 1, #categories do
                    local category = categories[i]
                    if category.filter ~= nil then
                        disabledLookup[category.key] = true
                        for j = 1, #rows do
                            local item = rows[j].item
                            if category.filter(item) then
                                disabledLookup[category.key] = nil
                                break
                            end
                        end
                    end
                end

                return disabledLookup
            end,
            onOpenSettings = openColumnSettings,
            onToggleView = toggleItemViewMode,
            getViewMode = getItemViewMode,
        },
        ---@param category InventoryExtenderRedone.Category
        function(category)
            if category.filter then
                self.filter:add('category', function(row)
                    return category.filter(row.item)
                end)
            else
                self.filter:remove('category')
            end

            self.table:filter(false)
            self.table:setHiddenColumns(combineHiddenColumns(self.table.header.columns, category.hiddenColumns))
            self.table:setPosition(0)

            self:updateTitle()

            trySyncedCategorySwitch(category.key)
        end, function(text)
            searchText = text and text:lower()
            self.table:filter()
            self.categoryFilter.updateCategories()
        end
    )

    local function getItemBadgeState(row)
        local favorite = isFavorited(row.item)
        local stolen = false

        if configPlayer.tweaks.b_StolenIndicator then
            if self.type == 'Inventory' and ctx.stolenItems then
                stolen = ctx.stolenItems[row.item.recordId] ~= nil
            elseif self.type == 'Container' then
                if ctx.pickpocket and ctx.pickpocket.active then
                    stolen = true
                elseif Container.objectIsInstance(self.target) then
                    stolen = isStealing(omwself, self.target.owner, self.target.globalVariable)
                end
            end
        end

        return {
            favorite = favorite,
            stolen = stolen,
        }
    end

    ---@param name string
    ---@param path string
    ---@param color openmw.util.Color
    ---@param sz number
    ---@param idx integer
    local function makeBadge(name, path, color, sz, idx)
        return {
            name = name,
            type = ui.TYPE.Image,
            props = {
                resource = Toolkit.texture(path),
                position = v2(idx * (sz + 4), 0),
                anchor = v2(0, 0.5),
                relativePosition = v2(0, 0.5),
                size = v2(sz, sz),
                color = color,
            },
        }
    end

    ---@param row InventoryExtenderRedone.RowData
    ---@param sz number
    ---@param existing openmw.ui.Content?
    ---@return openmw.ui.Layout[] badges, boolean changed
    local function getBadgeLayouts(row, sz, existing)
        local badges = getItemBadgeState(row)
        local layouts = {}
        local changed = not existing
        local was = {}
        if existing then
            for i = 1, #existing do
                was[existing[i].name] = true
            end
        end

        if badges.favorite then
            layouts[#layouts + 1] = makeBadge('favorite', iconPack.getPath('item/favorited.dds'),
                constants.Colors.GOLD, sz, #layouts)
            if not was['favorite'] then changed = true end
            was['favorite'] = nil
        end

        if badges.stolen then
            layouts[#layouts + 1] = makeBadge('stolen', iconPack.getPath('item/stolen.dds'),
                constants.Colors.DAMAGED, sz, #layouts)
            if not was['stolen'] then changed = true end
            was['stolen'] = nil
        end

        if row.showAsEnchanted() and shouldShowEnchantedNameIcon() then
            layouts[#layouts + 1] = makeBadge('enchanted', iconPack.getPath('item/enchanted.dds'),
                constants.Colors.BAR_MAGIC, sz, #layouts)
            if not was['stolen'] then changed = true end
            was['stolen'] = nil
        end


        if not changed and next(was) then
            changed = true
        end

        return layouts, changed
    end

    ---@type UIToolkit.ListItem.Column.Renderer
    local function nameRenderer(row, cfg, height)
        ---@cast row InventoryExtenderRedone.RowData
        local nonDraggedCount = getNonDraggedCount(row, self.type)

        local text = helpers.getItemName(row.item) ..
            (nonDraggedCount > 1 and (' (%s)'):format(H.addSeparators(nonDraggedCount)) or '')

        local content = ui.content {
            {
                name = 'name',
                template = T.text(),
                props = {
                    text = text,
                },
                userData = {
                    colorable = true,
                }
            },
        }
        local iconSize = util.round(theme.Sizes.lineHeight * 0.75)
        if not C.API.GAP then content:add(T.intervalH(8)) end

        local badges = getBadgeLayouts(row, iconSize)
        content:add {
            name = 'badges',
            type = ui.TYPE.Widget,
            props = {},
            external = { grow = 1, stretch = 1 },
            content = ui.content(badges),
        }

        local layout = {
            name = 'Name',
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
                autoSize = false,
                gap = C.API.GAP and 8 or nil,
            },
            content = content,
        }
        ColumnItem.applySize(layout, cfg, height)
        return layout
    end

    ---@type UIToolkit.ListItem.Column.Updater
    local function nameUpdater(part, row, cfg)
        local changed = false
        ---@cast row InventoryExtenderRedone.RowData
        local nonDraggedCount = getNonDraggedCount(row, self.type)

        local text = helpers.getItemName(row.item) ..
            (nonDraggedCount > 1 and (' (%s)'):format(H.addSeparators(nonDraggedCount)) or '')

        local props = H.props(part.content['name'])
        if props.text ~= text then
            props.text = text
            changed = true
        end

        local iconSize = util.round(theme.Sizes.lineHeight * 0.75)
        local badgesPart = part.content['badges']
        local badges, badgesChanged = getBadgeLayouts(row, iconSize, badgesPart.content)
        if badgesChanged then
            badgesPart.content = ui.content(badges)
            changed = true
        end

        return changed
    end


    self.infoBar = InfoBar.create({}) --[[@as InventoryExtenderRedone.InfoBarPrivate  ]]

    local infoHeight = self.infoBar:getHeight()
    local topBarHeight = self:getTopBarHeight()
    self.table = ItemTable:new()
    self.table:init {
        columns = ALL_COLUMNS(fallBackSort, nameRenderer, nameUpdater),
        defaultColumn = 'Icon',
        showGrid = getItemViewMode() == 'ItemViewMode_Grid',
        getBadges = getItemBadgeState,
        horizontalGrid = false, --TODO: read from settings
        size = v2(inner.x, inner.y - topBarHeight - infoHeight - 4),
        rowHeight = rowHeight,
        noBorder = true,
        onListClicked = function(button)
            if button ~= 1 then return end
            if not ctx.dragAndDrop.draggingObject then return end
            ctx.dragAndDrop:stopDrag(self.target)
        end,
        onItemClicked = function(row)
            self:onRowUse(row, false, false)
        end
    }
    local column = saved and saved.sortingColumn or 'Icon'
    local sortDir = saved and saved.sortingDirection
    if column then self.table.header:toggleColumn(column, sortDir ~= false) end
    self.table:updateProps { position = v2(0, topBarHeight + 2) }
    self.table:setFilter(self.filter --[[@as UIToolkit.SortedList.Filter]])
    local categoryKey = self.categoryFilter:getCategory()
    local category = categoryKey and IE.getCategory(categoryKey)
    if category then updateHiddenColumns(category) end
    self.table:setItems(self:createData())

    self.infoBar:updateProps({
        relativePosition = v2(0, 1),
        anchor = v2(0, 1)
    })

    self:initInfoBar()

    wnd:setContent(ui.content {
        self.categoryFilter.element,
        { template = I.MWUI.templates.horizontalLine, props = { position = v2(0, topBarHeight), } },
        self.table.element,
        { template = I.MWUI.templates.horizontalLine, props = { position = v2(0, -infoHeight), relativePosition = v2(0, 1), anchor = v2(0, 1), } },
        self.infoBar.element,
    })
    self:updateTitle()
    self.categoryFilter.updateCategories()

    local swap = configPlayer.keybinds.b_SwapUsePickup
    ---@type UIToolkit.Controller.HintList
    local hints
    if I.UI.getMode() == 'Barter' then
        hints = {
            { text = core.getGMST('sBarter'), input = { { id = BUTTON.A }, { id = BUTTON.X } } },
            'separator',
            { text = l10n 'Hint_Category',    input = { { id = BUTTON.LeftShoulder }, { id = BUTTON.RightShoulder } }, },
            { text = l10n 'Hint_Select',      input = { { id = BUTTON.DPadUp }, { id = BUTTON.DPadDown } }, },
            'separator',
            { text = constants.Strings.CLOSE, input = { id = input.CONTROLLER_BUTTON.B } },
        }
    else
        hints = {
            { text = l10n(swap and 'Hint_Use' or 'Hint_Pickup'), input = { id = BUTTON.A } },
            { text = l10n(swap and 'Hint_Pickup' or 'Hint_Use'), input = { id = BUTTON.X } },
            'separator',
            { text = l10n 'Hint_Category', input = { { id = BUTTON.LeftShoulder }, { id = BUTTON.RightShoulder } }, },
            { text = l10n 'Hint_Select',   input = { { id = BUTTON.DPadUp }, { id = BUTTON.DPadDown } }, },
            'separator',
            { text = constants.Strings.CLOSE, input = { id = input.CONTROLLER_BUTTON.B } },
        }
    end
    if self.target == omwself then
        table.insert(hints, 1, { text = l10n 'Hint_Favorite', input = { id = BUTTON.Y } })
    end
    wnd:setControllerHints(hints)
end

function Inventory:onClosed()
    if self._closeSettingsPopup then
        self._closeSettingsPopup()
        self._closeSettingsPopup = nil
    end
    if self._closeItemStackPopup then
        self._closeItemStackPopup()
        self._closeItemStackPopup = nil
    end
    if self.ctx.dragAndDrop.draggingObject then
        self.ctx.dragAndDrop:stopDrag()
    end
    self.wnd = nil
    self.arg = nil
    local column, asc = self.table.header:getActiveColumn()
    ---@type IER.Inventory.SaveData
    return {
        sortingColumn = column,
        sortingDirection = asc,
    }
end

function Inventory:onResized(inner)
    local infoHeight = self.infoBar:getHeight()
    local topBarHeight = self:getTopBarHeight()

    self.table:setSize(inner - v2(0, topBarHeight + infoHeight + 4))
end

function Inventory:getTopBarHeight()
    return self.categoryFilter:getSize().y
end

function Inventory:onKeyboardButtonPress(key)
    if I.UI.getMode() == nil then return end
    --TODO: add bindings for these
    if key == KEY.Z then
        self.categoryFilter:cycleCategory(-1)
    elseif key == KEY.C then
        self.categoryFilter:cycleCategory(1)
    elseif key == KEY.W then
        self.table:shiftHoveredItem(v2(0, -1)) --TODO: consider diagonals
    elseif key == KEY.S then
        self.table:shiftHoveredItem(v2(0, 1))
    elseif key == KEY.A then
        self.table:shiftHoveredItem(v2(-1, 0))
    elseif key == KEY.D then
        self.table:shiftHoveredItem(v2(1, 0))
    elseif key == (configPlayer.keybinds.k_ToggleFavorite or input.KEY.F) then
        self:toggleFavorite()
    elseif key == configPlayer.keybinds.k_UseItem then
        local ctx = self.ctx
        local row = self.table:getHovered()
        if configPlayer.keybinds.b_SwapUsePickup then
            if ctx.dragAndDrop.draggingObject then
                ctx.dragAndDrop:stopDrag(self.target)
            elseif row then
                self:onRowUse(row, true, false)
            end
        elseif row then
            self:onRowPickup(row, self.type, false)
        end
    end
end

function Inventory:onKeyboardButtonRepeat(key)
    --TODO: add bindings for these
    if key == KEY.W or key == KEY.S or key == KEY.A or key == KEY.D then
        self:onKeyboardButtonPress(key)
    end
end

function Inventory:onControllerButtonPress(button)
    if I.UI.getMode() == nil then return end
    --TODO: add bindings for these
    local ctx = self.ctx
    if button == BUTTON.LeftShoulder then
        self.categoryFilter:cycleCategory(-1)
    elseif button == BUTTON.RightShoulder then
        self.categoryFilter:cycleCategory(1)
    elseif button == BUTTON.DPadUp then --TODO: consider diagonals
        self.table:shiftHoveredItem(v2(0, -1))
    elseif button == BUTTON.DPadDown then
        self.table:shiftHoveredItem(v2(0, 1))
    elseif button == BUTTON.DPadLeft then
        self.table:shiftHoveredItem(v2(-1, 0))
    elseif button == BUTTON.DPadRight then
        self.table:shiftHoveredItem(v2(1, 0))
    elseif button == BUTTON.Y then
        self:toggleFavorite()
    elseif button == BUTTON.X then
        local row = self.table:getHovered()
        if configPlayer.keybinds.b_SwapUsePickup then
            if ctx.dragAndDrop.draggingObject then
                ctx.dragAndDrop:stopDrag(self.target)
            elseif row then
                self:onRowUse(row, true, false)
            end
        elseif row then
            self:onRowPickup(row, self.type, false)
        end
    elseif button == BUTTON.A and I.UIToolkit.getCtx().focusedScrollable ~= self.table:currentScrollable() then
        local row = self.table:getHovered()
        if not configPlayer.keybinds.b_SwapUsePickup then
            if ctx.dragAndDrop.draggingObject then
                ctx.dragAndDrop:stopDrag(self.target)
            elseif row then
                self:onRowUse(row, true, false)
            end
        elseif row then
            self:onRowPickup(row, self.type, false)
        end
    end
end

function Inventory:onControllerButtonRepeat(button)
    --TODO: add bindings for these
    if button == BUTTON.DPadDown or button == BUTTON.DPadUp
        or button == BUTTON.DPadLeft or button == BUTTON.DPadRight then
        self:onControllerButtonPress(button)
    end
end

function Inventory:getStorageSuffix()
    if self.wnd then return self.suffix end
    return getStorageSuffix(self.type)
end

function Inventory:getDefaultStorage()
    if self.type ~= 'Inventory' or I.UI.getMode() == 'Interface' then return nil end
    return { position = v2(0.05, 0.05), size = v2(0.45, 0.85) }
end

function Inventory:update()
    self.table.provider:markCacheDirty()
    self.table.gridProvider:markAllDirty()
    local data = self:createData()
    self.table:setItems(data)
    self.categoryFilter.updateCategories()
    if self.infoBar then self.infoBar:update() end
end

function Inventory:isFavorite(item)
    return item ~= nil and self.ctx.favoriteItems[item.id] == true
end

---@param row InventoryExtenderRedone.RowData?
function Inventory:toggleFavorite(row)
    if not row then
        row = self.table:getHovered()
    end
    if not row then return end
    local item = row.item
    if not item then return end
    if not self:canToggleFavoriteRow(row) then return end
    local ctx = self.ctx
    local currentValue = ctx.favoriteItems[item.id] == true

    if currentValue then
        ctx.favoriteItems[item.id] = nil
    else
        ctx.favoriteItems[item.id] = true
    end

    ctx.favoriteRevision = (ctx.favoriteRevision or 0) + 1
    self.table.provider:refreshColumns(row, 'Name')
    self.table.gridProvider:markDirty(row)
    self.table:setHovered(nil)
    self.table:sort()
end

function Inventory:canToggleFavoriteRow(row)
    return self.target == omwself and row and row.item ~= nil and not row.isBartered
        and not self.ctx.dragAndDrop.draggingObject
end

function Inventory:isFavoriteTransferBlocked(row)
    return self.target == omwself
        and row and row.item ~= nil
        and not row.isBartered
        and self:isFavorite(row.item)
        and I.UI.getMode() ~= 'Interface'
end

---@param row InventoryExtenderRedone.RowData
---@param windowType string
---@return openmw.Object
function Inventory:getUseItemSource(row, windowType)
    local effectiveWindowType = windowType
    if row.item.parentContainer ~= nil then
        return row.item.parentContainer
    end
    if effectiveWindowType == 'Container' or effectiveWindowType == 'Companion' then
        return self.target
    end
    return omwself
end

---@param row InventoryExtenderRedone.RowData
---@param windowType string
---@return {target:openmw.Object}|nil
function Inventory:getUseItemPickpocket(row, windowType)
    local effectiveWindowType = windowType
    local ctx = self.ctx
    local mode = I.UI.getMode()
    if mode == 'Container' and effectiveWindowType == 'Container' and ctx.pickpocket and ctx.pickpocket.active then
        return { target = self.target }
    end
    return nil
end

---@param row InventoryExtenderRedone.RowData
---@param windowType string
---@param allowOutsideInterface boolean
function Inventory:onRowPickup(row, windowType, allowOutsideInterface)
    if I.UI.getMode() == 'Barter' then
        return self:onRowUse(row, true, true)
    end
    local ctx = self.ctx
    for i = #ctx.handlers.onRowPickup, 1, -1 do
        local handler = ctx.handlers.onRowPickup[i]
        if handler.handler(row, ctx, self.type) == false then
            return false
        end
    end

    if not canPickupItem(row, windowType, allowOutsideInterface) then
        return false
    end

    if omwself.type.hasEquipped and omwself.type.hasEquipped(omwself, row.item) then
        local equipment = omwself.type.getEquipment(omwself)
        for slot, equippedItem in pairs(equipment) do
            if equippedItem == row.item then
                equipment[slot] = nil
                omwself.type.setEquipment(omwself, equipment)
                local sound = helpers.getItemSound(row.item, 'down')
                if sound then
                    ambient.playSound(sound)
                end
                omwself:sendEvent('IER_Update')
                break
            end
        end
    else
        core.sendGlobalEvent('IER_UseItem', {
            object = row.item,
            actor = omwself,
            source = self:getUseItemSource(row, windowType),
            pickpocket = self:getUseItemPickpocket(row, windowType),
        })
    end
end

function Inventory:onRowUse(row, fromKBMKeybind, forceBarterAction)
    local ctx = self.ctx
    if ctx.dragAndDrop.draggingObject then
        if fromKBMKeybind then
            ctx.dragAndDrop:stopDrag(self.target)
        end
        return true
    end

    if configPlayer.keybinds.b_SwapUsePickup and not fromKBMKeybind then
        return self:onRowPickup(row, self.type, true)
    end

    for i = #ctx.handlers.onRowUse, 1, -1 do
        local handler = ctx.handlers.onRowUse[i]
        if handler.handler(row, ctx, self.type) == false then
            return false
        end
    end

    if helpers.isBoundItem(row.item) then
        local gmst
        if I.UI.getMode() == 'Barter' then
            if self.type == 'Trade' then
                gmst = 'sBarterDialog10' --can't buy summoned items
            else
                gmst = 'sBarterDialog9'  --can't sell summoned items
            end
        else
            gmst = 'sContentsMessage1' --can't remove summoned item
        end
        if gmst then ui.showMessage(core.getGMST(gmst)) end
        return
    end

    if self:isFavoriteTransferBlocked(row) then
        ui.showMessage(l10n('UI_Msg_FavoriteItem'))
        return false
    end

    local transfer = input.isAltPressed() or I.UI.getMode() == 'Barter'
    local takeAll = input.isShiftPressed() or input.getAxisValue(input.CONTROLLER_AXIS.TriggerRight) > 0.5
    local takeOne = input.isCtrlPressed() or input.getAxisValue(input.CONTROLLER_AXIS.TriggerLeft) > 0.5

    if takeAll and takeOne and not forceBarterAction then
        self:onRowPickup(row, self.type, false)
        return
    end

    local itemCount = row.getCount()
    if I.UI.getMode() == 'Barter' then
        if row.isBartered then
            if self.type == 'Inventory' then
                itemCount = (ctx.barterState.buying[row.item.id] or {}).count or 0
            else
                itemCount = (ctx.barterState.selling[row.item.id] or {}).count or 0
            end
        else
            if self.type == 'Inventory' then
                itemCount = itemCount - ((ctx.barterState.selling[row.item.id] or {}).count or 0)
            elseif self.type == 'Trade' then
                itemCount = itemCount - ((ctx.barterState.buying[row.item.id] or {}).count or 0)
            end
        end
    end

    local function doAction(count)
        local mode = I.UI.getMode()
        local pickpocket = ctx.pickpocket
        local isPickpocketTake = mode == 'Container' and self.type == 'Container' and pickpocket and
            pickpocket.active

        if isPickpocketTake then
            local success = Pickpocket.rollTake(omwself, self.target, row.item, row.getCount())
            if not success then
                pickpocket.resolved = true
                core.sendGlobalEvent('IER_CommitPickpocket', {
                    player = omwself,
                    target = self.target,
                    victimAware = true,
                })
                I.UI.removeMode('Container')
                return false
            end
        end

        if transfer then
            if mode == 'Container' or mode == 'Companion' then
                if self.type == 'Inventory' then
                    if ctx.windowArgs[mode] then
                        ctx.dragAndDrop:transferInto(row.item, ctx.windowArgs[mode], omwself, count)
                    end
                else
                    ctx.dragAndDrop:transferInto(row.item, omwself, self.target, count,
                        isPickpocketTake and { target = self.target } or nil)
                end
            elseif mode == 'Barter' then
                if row.isBartered then
                    local table = self.type == 'Inventory' and ctx.barterState.buying or ctx.barterState.selling
                    if table[row.item.id] then
                        table[row.item.id].count = table[row.item.id].count - count
                        if table[row.item.id].count <= 0 then
                            table[row.item.id] = nil
                        end
                    end
                else
                    local table = self.type == 'Inventory' and ctx.barterState.selling or ctx.barterState.buying
                    table[row.item.id] = table[row.item.id] or
                        { item = row.item, stacks = row.virtualStacks, count = 0 }
                    table[row.item.id].count = math.min(table[row.item.id].count + count, row.getCount())
                end
                local sound = helpers.getItemSound(row.item, 'down')
                if sound then
                    ambient.playSound(sound)
                end
                barterUtils.updateOffer(ctx)
                omwself:sendEvent('IER_Update')
            elseif mode == 'Interface' then
                if not self:isFavorite(row.item) then
                    ctx.dragAndDrop:dropAtViewportPosition(row.item, count, v2(0.5, 0.5), true)
                else
                    ui.showMessage(l10n('UI_Msg_FavoriteItem'))
                end
            end
        else
            ctx.dragAndDrop:startDrag(
                row.item,
                self.target,
                count,
                isPickpocketTake and { target = self.target } or nil,
                {
                    windowType = self.type,
                    isBartered = row.isBartered,
                }
            )
        end
        return true
    end

    if itemCount > 1 and not takeAll and not takeOne then
        self._closeItemStackPopup = ItemStackModal.show({
            itemName = row.itemRecord.name,
            maxCount = itemCount,
            onConfirm = function(count)
                doAction(count)
            end,
        })
    else
        doAction(takeOne and 1 or itemCount)
    end
end

---@private
function Inventory:updateTitle()
    local title
    if I.UI.getMode() == 'Interface' then
        title = helpers.getEquippedName(omwself)
    else
        local target = self.target or omwself
        title = target.type.record(target).name
    end

    if configPlayer.tweaks.b_CompactCategoryFilter then
        local categoryKey = self.categoryFilter:getCategory()
        local category = categoryKey and I.InventoryExtenderRedone.getCategory(categoryKey)
        if category and category.name then
            title = title and (title .. ' - ' .. category.name) or category.name
        end
    end

    if title then
        self.wnd:setTitle(title)
    end
end

local function getEquippedItemsForComparison(item, ctx)
    local mode = configPlayer.window.s_CompareItemsMode
    if mode == constants.COMPARISON_OPTS.ALT then
        if not input.isAltPressed() then return nil end
    elseif mode == constants.COMPARISON_OPTS.Always then
        --do nothing - this always should pass
    else
        -- either Never or unknown - skip
        return nil
    end

    local actor = omwself
    local overrides = ctx.overrides.equipped

    if helpers.isItemEquipped(item, actor, overrides) then
        return nil
    end

    local slots = helpers.getEquipmentSlots(item)
    local equipped = helpers.getEquippedItems(slots, actor, overrides)

    return equipped
end

---@private
function Inventory:createData()
    if not self.target then
        return {}
    end

    local ctx = self.ctx
    local modifiers = ctx.modifiers.data

    ---@param item openmw.Object|{stacks:openmw.Object[], totalCount:number}
    ---@param isBartered boolean
    ---@param isVirtual boolean
    ---@param isOwned boolean
    ---@return InventoryExtenderRedone.RowData?
    local function createRowData(item, isBartered, isVirtual, isOwned)
        ---@type openmw.Object
        local itemStack = isVirtual and item.stacks[1] or item --[[@as openmw.Object]]

        if not Item.isCarriable(itemStack) then return nil end

        local record = itemStack.type.record(itemStack)
        local value = helpers.getItemValue(itemStack)
        local vw = record.weight > 0 and (value / record.weight) or 0
        local vwPrecision = vw > 10 and 0 or 1
        local getItemCount = function()
            if isVirtual then
                return item.totalCount
            else
                return itemStack.count
            end
        end

        local function tooltip()
            local baseTip = { object = itemStack, observer = omwself, owned = isOwned }
            local comparison = getEquippedItemsForComparison(itemStack, ctx)
            if not comparison or #comparison <= 0 then return baseTip end
            local tips = { Tooltips.createTooltipLayout(baseTip) }
            for i = 1, #comparison do
                table.insert(tips, 1, Tooltips.createTooltipLayout({
                    object = comparison[i],
                    observer = omwself,
                    isOwned = false,
                    markEquipped = true,
                }))
            end
            local layout = {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                },
                content = ui.content(tips),
            }
            return { layout = layout }
        end

        ---@type InventoryExtenderRedone.RowData
        local rowData = {
            id = itemStack.id,
            Name = helpers.getItemName(itemStack),
            Type = function()
                return helpers.getItemTypeLabel(itemStack) or '-'
            end,
            Damage = function()
                return helpers.getWeaponDamage(itemStack)
            end,
            Class = function()
                return helpers.getArmorClassLabel(itemStack)
            end,
            AR = function()
                return helpers.getArmorRating(itemStack, omwself)
            end,
            Condition = function()
                return helpers.getConditionPercentLabel(itemStack)
            end,
            Quality = record.quality and helpers.roundToPlaces(record.quality, 3),
            Value = helpers.roundToPlaces(value, 1),
            Weight = helpers.roundToPlaces(record.weight, 2),
            Weight_Total = helpers.roundToPlaces(record.weight * getItemCount(), 2),
            ['V/W'] = helpers.roundToPlaces(vw, vwPrecision),
            item = itemStack,
            itemRecord = record,
            isBartered = isBartered,
            virtualStacks = isVirtual and item.stacks or nil,
            getCount = getItemCount,
            tooltip = tooltip,
            showAsEnchanted = function()
                if record.enchant then
                    return true
                end
                if configPlayer.tweaks.b_FilledGemsAppearEnchanted and Item.itemData(itemStack).soul then
                    return true
                end
                return false
            end,
            isDisabled = function()
                if not isBartered and self.type == 'Inventory' and self.mode == 'Container' then
                    local container = self.arg
                    if Container.objectIsInstance(container) and Container.record(container).isOrganic then
                        return true
                    end
                    return not helpers.doesItemFit(itemStack, container, 1)
                end
                return false
            end,
        }

        --[[ uncomment to have bartered items look active
        if isBartered then
            rowData.isActive = function() return true end
        end
        ]]

        for i = #modifiers, 1, -1 do
            modifiers[i].modifier(rowData, ctx, self.type)
        end

        return rowData
    end

    local data = {}

    local isOwned = false
    if self.type == 'Container' then
        if ctx.pickpocket and ctx.pickpocket.active then
            isOwned = true
        elseif Container.objectIsInstance(self.target) then
            isOwned = isStealing(omwself, self.target.owner, self.target.globalVariable)
        end
    end

    -- Add primary inventory
    if self.type ~= 'Trade' then
        local allItems = self.target.type.inventory(self.target):getAll()
        for i = 1, #allItems do
            data[#data + 1] = createRowData(allItems[i], false, false, isOwned)
        end
    else
        for _, recordId in pairs(helpers.getMerchantItems(self.target)) do
            for i = 1, #recordId do
                table.insert(data, createRowData(recordId[i], false, true, isOwned))
            end
        end
    end

    -- Add bartered items from other inventory
    if self.mode == 'Barter' then
        if self.type == 'Trade' then
            local ownItems = omwself.type.inventory(omwself):getAll()
            for i = 1, #ownItems do
                table.insert(data, createRowData(ownItems[i], true, false, isOwned))
            end
        else
            local barterNpc = ctx.windowArgs.Trade or self.arg --TODO: consider removing `ctx.windowArgs`
            if barterNpc then
                for _, recordId in pairs(helpers.getMerchantItems(barterNpc)) do
                    for i = 1, #recordId do
                        table.insert(data, createRowData(recordId[i], true, true, isOwned))
                    end
                end
            end
        end
    end

    return data
end

local function createDraggedActivationRow(ctx, item)
    local activationContext = ctx.dragAndDrop.draggingActivationContext or {}
    return {
        id = item.id,
        item = item,
        itemRecord = item.type.record(item),
        isBartered = activationContext.isBartered,
        getCount = function()
            return ctx.dragAndDrop.draggingCount or item.count
        end,
    }
end

---@private
function Inventory:initInfoBar()
    local ctx = self.ctx
    local theme = Toolkit.getTheme()

    --Encumbrance
    if self.type ~= 'Trade' then
        self.encumbranceBar = Components.progressBar {
            width = 100,
            color = theme.Colors.MAGICK,
            clamp = false,
        }
        local encumbranceLayout = {
            name = 'encumbrance',
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = Toolkit.texture 'icons/weight.dds',
                        size = v2(1, 1) * theme.Sizes.textNormal,
                    }
                },
                T.intervalH(4),
                self.encumbranceBar.element,
            }
        }
        self.infoBar:addProvider(function()
            if not self.target then return nil end
            if self.type == 'Container' and
                (Container.objectIsInstance(self.target) and Container.record(self.target).isOrganic)
                or (ctx.pickpocket and ctx.pickpocket.active)
            then
                return nil
            end
            local type = self.target.type
            self.encumbranceBar:setMax(util.round(type.getCapacity(self.target)))
            self.encumbranceBar:setValue(util.round(type.getEncumbrance(self.target)))
            return encumbranceLayout
        end)
    end

    --Gold
    if self.type == 'Inventory' or self.type == 'Trade' then
        local goldProps = { text = '' }
        local goldLayout = {
            name = 'gold',
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { path = 'icons/gold.dds' },
                        size = v2(1, 1) * theme.Sizes.textNormal,
                    }
                },
                T.intervalH(4),
                {
                    template = T.text(),
                    props = goldProps,
                }
            }
        }
        self.infoBar:addProvider(function()
            if not self.target then return nil end
            local goldAmount
            if self.type == 'Inventory' then
                goldAmount = self.target.type.inventory(self.target):countOf('gold_001')
            else
                goldAmount = self.target.type.getBarterGold(self.target)
            end
            goldProps.text = H.addSeparators(goldAmount)
            return goldLayout
        end)
    end

    local filler = { external = { grow = 1, stretch = 1 } }

    if self.type == 'Inventory' then
        -- Armor rating
        local armorProps = { text = '' }
        local armorLayout = {
            name = 'armorRating',
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { path = 'icons/a/a_cuirass_ebon.dds' },
                        size = v2(1, 1) * theme.Sizes.textNormal,
                    }
                },
                T.intervalH(4),
                {
                    template = T.text(),
                    props = armorProps,
                }
            }
        }

        self.infoBar:addProvider(function()
            if not self.target then return nil end
            armorProps.text = H.addSeparators(math.floor(I.Combat.getArmorRating(self.target)))
            return armorLayout
        end)

        --Stretching filler
        self.infoBar:addProvider(function() return filler end)

        --use item
        local btnUse = Components.textButton {
            name = 'use',
            style = theme.IntRe and 'empty' or 'thin',
            text = core.getGMST('sUse'),
            onClick = function()
                local draggedItem = ctx.dragAndDrop.draggingObject
                if not draggedItem then return end
                local activationContext = ctx.dragAndDrop.draggingActivationContext or {}
                local result = self:onRowPickup(createDraggedActivationRow(ctx, draggedItem),
                    activationContext.windowType, true)
                if result ~= false then
                    ctx.dragAndDrop:stopDrag()
                    self.infoBar:update()
                    --self:refresh()
                end
            end,
            tooltip = function()
                if configPlayer.keybinds.b_SwapUsePickup then
                    return l10n('UI_Tooltip_UseButton_Swapped')
                end
                return l10n('UI_Tooltip_UseButton', { key = input.getKeyName(configPlayer.keybinds.k_UseItem) })
            end,
        }

        self.infoBar:addProvider(function()
            btnUse:setVisible(ctx.dragAndDrop.draggingObject ~= nil)
            return btnUse.element
        end)

        --self.infoBar.layout.userData.addInfoLayout({})
    end

    if self.type == 'Container' or self.type == 'Companion' then
        --Stretching filler
        self.infoBar:addProvider(function() return filler end)

        if self.type == 'Container' then
            --dispose
            local btnDispose = Components.textButton {
                name = 'dispose',
                style = theme.IntRe and 'empty' or 'thin',
                text = constants.Strings.DISPOSE_OF_CORPSE,
                onClick = function()
                    if I.UI.getMode() ~= 'Container' or not ctx.windowArgs.Container then return end
                    ctx.dragAndDrop:moveAll(self.target, omwself)

                    if persistentCorpses(self.target) then
                        ui.showMessage(constants.Strings.DISPOSE_CORPSE_FAIL)
                    else
                        core.sendGlobalEvent('IER_DisposeOfCorpse', { target = ctx.windowArgs.Container })
                    end
                    I.UI.removeMode('Container')
                end,
            }

            self.infoBar:addProvider(function()
                local visible = false
                if ctx.windowArgs.Container then
                    visible = Actor.objectIsInstance(ctx.windowArgs.Container)
                        and Actor.isDead(ctx.windowArgs.Container)
                end
                btnDispose:setVisible(visible)
                return btnDispose.element
            end)

            --Take All
            local btnTakeAll = Components.textButton {
                name = 'takeAll',
                style = theme.IntRe and 'empty' or 'thin',
                text = constants.Strings.TAKE_ALL,
                onClick = function()
                    if I.UI.getMode() ~= 'Container' or not ctx.windowArgs.Container then return end
                    local visibleOnly = input.isShiftPressed()
                    local items = nil

                    if visibleOnly then
                        local visibleItems = self.table.filteredItems
                        items = {}
                        for i = 1, #visibleItems do
                            local row = visibleItems[i]
                            if row and row.item then
                                table.insert(items, row.item)
                            end
                        end
                    end

                    if not items or #items > 0 then
                        ctx.dragAndDrop:moveAll(self.target, omwself, items)
                    end

                    if not visibleOnly then
                        I.UI.removeMode('Container')
                    end
                end,
                tooltip = l10n('UI_Tooltip_TakeAllButton_Shift'),
            }
            self.infoBar:addProvider(function()
                btnTakeAll:setVisible(not (ctx.pickpocket and ctx.pickpocket.active))
                return btnTakeAll.element
            end)
        end

        --companion profit value
        if self.type == 'Companion' then
            local profitProps = {}
            local profitLayout = {
                template = T.text(),
                props = profitProps,
            }

            self.infoBar:addProvider(function()
                if self.target == nil then return nil end
                local profit = ctx.companionProfit[self.target.id] or 0
                profitProps.text = constants.Strings.PROFIT_VALUE .. ': ' .. H.addSeparators(profit)
                return profitLayout
            end)
        end

        ---close
        local btnClose = Components.textButton {
            name = 'close',
            style = theme.IntRe and 'empty' or 'thin',
            text = constants.Strings.CLOSE,
            onClick = function()
                I.UI.removeMode(self.type)
            end,
        }

        self.infoBar:addProvider(function() return btnClose.element end)

        --self.infoBar.layout.userData.addInfoLayout({})
    end

    if self.type == 'Trade' then
        --Barter controls
        local barterControls = BarterControls:new()
        barterControls:init(self)

        self.infoBar:addProvider(function()
            barterControls:update(ctx)
            return barterControls.element
        end)

        --self.infoBar.layout.userData.addInfoLayout({})
    end
end

return Inventory
