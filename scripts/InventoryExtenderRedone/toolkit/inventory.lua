---@omw-context player


local ambient   = require 'openmw.ambient'
local core      = require 'openmw.core'
local input     = require 'openmw.input'
local ui        = require 'openmw.ui'
local util      = require 'openmw.util'
local storage   = require 'openmw.storage'
local types     = require 'openmw.types'
local omwself   = require 'openmw.self'

local I         = require 'openmw.interfaces'
local v2        = util.vector2
local cfgUtil   = require 'scripts.UIToolkit.config.utils'
local D         = require 'scripts.InventoryExtenderRedone.config.defaults'
local L         = require 'scripts.InventoryExtenderRedone.util.logger'.get 'INV'
local BINDING   = D.Binds
local BUTTON    = input.CONTROLLER_BUTTON

local Container = types.Container
local Item      = types.Item
local Player    = types.Player


local configPlayer = require('scripts.InventoryExtenderRedone.config.player')
local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local constants = require('scripts.InventoryExtenderRedone.util.constants')
local iconPack = require('scripts.InventoryExtenderRedone.util.iconPack')
local pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')
local l10n = core.l10n(D.L10N)
local Mode = require('scripts.InventoryExtenderRedone.toolkit.mode')
local InfoBar = require('scripts.InventoryExtenderRedone.toolkit.info_bar')
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


---@type table<string, string>
local openedCategory = {}


---@class IER.Inventory.SaveData
---@field sortingColumn string?
---@field sortingDirection boolean?

local CategoryFilter = require('scripts.InventoryExtenderRedone.toolkit.categoryFilter')

local function getEnchantedIndicatorMode()
    return configPlayer.tweaks.s_EnchantedIndicatorMode or 'EnchantedIndicatorMode_Both'
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

---@param row InventoryExtenderRedone.RowData
---@param type string
---@param mode string
local function getNonDraggedCount(row, type, mode)
    local nonDraggedCount = row.getCount()
    local ctx = I.InventoryExtenderRedone.getContext()

    local drag = ctx.dragAndDrop
    if drag.draggingObject and drag.draggingObject.id == row.item.id then
        nonDraggedCount = nonDraggedCount - drag.draggingCount
    end

    if mode ~= 'Barter' then return nonDraggedCount end

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
    return nonDraggedCount
end





local function getColumnVisibility()
    return windowOptionsSection:getCopy(columnVisibilityKey) or {}
end

---@param column InventoryExtenderRedone.Mode.Column resolved column part
---@param visible boolean
local function setColumnVisibility(column, visible)
    local visibility = getColumnVisibility()
    if visible then
        if column.optional then
            visibility[column.id] = true
        else
            visibility[column.id] = nil
        end
    else
        visibility[column.id] = false
    end
    windowOptionsSection:set(columnVisibilityKey, visibility)
end

local function resetHiddenColumns()
    windowOptionsSection:set(columnVisibilityKey, {})
end

---@param column InventoryExtenderRedone.Mode.Column resolved column part
---@param visibility table<string, boolean>?
---@return boolean
local function isColumnVisible(column, visibility)
    visibility = visibility or getColumnVisibility()
    if column.optional then
        return visibility[column.id] == true
    end
    return visibility[column.id] ~= false
end

---@param columns InventoryExtenderRedone.Mode.Column[] resolved column parts, in display order
---@param categoryHidden table<string, boolean>?
---@return table<string, boolean>
local function combineHiddenColumns(columns, categoryHidden)
    local hidden = {}
    local visibility = getColumnVisibility()
    local visible = 0

    for i = 1, #columns do
        local column = columns[i]
        if not isColumnVisible(column, visibility) then
            hidden[column.id] = true
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

--- The actor a window answers from: the target role slot if it names one, else the built-in
--- rule (the player for the Inventory role, the open argument for any other role).
local function resolveTarget(handler, slots, ctx)
    local targetFn = slots and slots.target
    local target = targetFn and targetFn(handler, ctx)
    if target then return target end
    return handler.role == D.Roles.Inventory and omwself or handler.arg
end

---@class IER.Inventory: UIToolkit.WindowHandler
---@field new fun(self:IER.Inventory):IER.Inventory
---@field arg table
---@field wnd UIToolkit.Window
---@field target openmw.Object? the actor this window answers from: whose inventory is listed and whose equipped gear, encumbrance and gold the info bar and sorting read; set at open from the target role slot and changeable through setTarget
---@field table InventoryExtenderRedone.ItemTable? the column/grid component, set at open; public so external consumers can read hovered-row state through getWindow
---@field infoBar InventoryExtenderRedone.InfoBarPrivate? the bottom strip, set at open; public so external consumers can measure and extend it
---@field role InventoryExtenderRedone.Role
---@field mode InventoryExtenderRedone.ModeKey? the mode key this window snapshotted at open
---@field slots InventoryExtenderRedone.Mode.RoleSpec? this role's slots from that mode
---@field actions InventoryExtenderRedone.Mode.Actions? use/pickup parts resolved from that role's slots
---@field sources InventoryExtenderRedone.Mode.Source[] those slots' sources, parts resolved at open
---@field columns InventoryExtenderRedone.Mode.Column[]? column parts resolved at open, in display order, with the handler's Icon/Name closures merged over them
---@field infoBarSections InventoryExtenderRedone.Mode.InfoBarSection[]? info bar sections, parts resolved at open, in slot order
---@field drag InventoryExtenderRedone.Mode.Drag? the mode's drag snapshot at open (mode-wide, not per role)
---@field suffix string? the UIToolkit:WindowData suffix snapshotted from that role's slots at open
local Inventory = Class(WindowHandler)

function Inventory:init(role)
    self.role = role
end

---@param wnd UIToolkit.Window
---@param data any
---@param saved IER.Inventory.SaveData
function Inventory:onOpened(wnd, data, saved)
    self.arg = data
    self.wnd = wnd
    local IE = I.InventoryExtenderRedone
    local ctx = IE.getContext()
    self.ctx = ctx

    -- snapshotted here: a mode patched later affects the next open, not this window
    local mode, roleSpec = Mode.resolveMode(self.role, self.arg, I.UI.getMode())
    self.mode = mode and mode.key or nil
    L.info('onOpened', self.role, self.mode)
    self.slots = roleSpec
    -- the open window answers from these snapshots, never from the engine mode
    self.suffix = roleSpec and roleSpec.storageSuffix or nil
    self.drag = mode and mode.drag or nil
    self.infoBarSections = roleSpec and Mode.resolveParts(Mode.Info, roleSpec.infoBar) or nil
    self.sources = Mode.resolveParts(Mode.Sources, roleSpec and roleSpec.sources)
    local modeFilters = Mode.resolveParts(Mode.Filters, roleSpec and roleSpec.filters)
    -- a role spec without columns gets the built-in chain; the handler merges its Icon/Name
    -- closures over these parts at open, below where those closures are defined
    self.columns = Mode.resolveParts(Mode.Columns, roleSpec and roleSpec.columns
        or Mode.Defaults.RoleSpec.columns)
    -- the actions slot is a whole overwrite per role: entry ids resolve against the parts
    -- library here, the handler dispatches to them per row action
    local actions = roleSpec and roleSpec.actions
    self.actions = actions and {
        use = Mode.resolvePart(Mode.Actions, actions.use),
        pickup = Mode.resolvePart(Mode.Actions, actions.pickup),
    } or nil
    L.debug('slots', self.role, self.mode, self.suffix, self.drag and self.drag.allowed,
        self.sources and #self.sources or 0, #modeFilters)

    -- a lifecycle table may name only some hooks (Barter has onClosing but no onOpened), so
    -- guard the field itself, not just the table
    if mode and mode.lifecycle and mode.lifecycle.onOpened then
        mode.lifecycle.onOpened(self, self.arg, saved)
    end

    -- the window's actor: the target role slot's default, else the built-in rule
    self.target = resolveTarget(self, self.slots, self.ctx)
    -- pinnable comes from the role slot: only the Interface spec names it
    if self.role == D.Roles.Inventory and roleSpec and roleSpec.pinnable then
        self.wnd:setPinnable(true)
    end
    self.filter = CompoundFilter:new()
    self.filter:add('draggedItemFilter', function(row)
        local drag = ctx.dragAndDrop
        if drag.draggingObject then
            return row.item.id ~= drag.draggingObject.id or row.getCount() > drag.draggingCount
        end
        return true
    end)

    -- mode-provided row filters, between the structural ones: the dragged item, the search text
    -- and the selected category are window-level, not mode behavior
    for i = 1, #modeFilters do
        local filter = modeFilters[i]
        if filter.fn then
            local fn = filter.fn
            self.filter:add(filter.id, function(row)
                return fn(row, self, ctx)
            end)
        end
    end

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
            self.columns,
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

        for i = 1, #self.columns do
            local column = self.columns[i]
            if column.editable then
                if #elements > 0 then
                    elements[#elements + 1] = T.intervalV(4)
                end
                local id = column.id
                elements[#elements + 1] = Toolkit.Components.checkbox {
                    name = id,
                    text = column.name,
                    width = 200,
                    default = isColumnVisible(column),
                    accentedCheckmark = true,
                    onValueChanged = function(value)
                        setColumnVisibility(column, value)
                        updateHiddenColumns()
                    end,
                }.element
            end
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
            handler:updateInputHints()
            if handler ~= self then
                handler.categoryFilter.updateViewModeButton()
            end
        end)
    end

    -- the key this window's opened category is remembered under
    local function getOpenedCategoryKey()
        --TODO: check trader services?
        return self.mode
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
            self.table:setHiddenColumns(combineHiddenColumns(self.columns, category.hiddenColumns))
            self.table:setPosition(0)

            self:updateTitle()

            local rememberedMode = getOpenedCategoryKey()
            if rememberedMode then
                openedCategory[rememberedMode] = category.key
            end
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
            if self.role == 'Inventory' and ctx.stolenItems then
                stolen = ctx.stolenItems[row.item.recordId] ~= nil
            elseif self.role == 'Container' then
                if ctx.pickpocket and ctx.pickpocket.active then
                    stolen = true
                elseif Container.objectIsInstance(self.target) then
                    stolen = helpers.isStealing(omwself, self.target.owner, self.target.globalVariable)
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
    ---@param color openmw.util.Color?
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

        local custom = ctx.modifiers.badge
        for i = 1, #custom do
            local badge = custom[i]
            local name = badge.id
            local icon, color = badge.provider(row, ctx)
            if icon then
                layouts[#layouts + 1] = makeBadge(name, icon, color, sz, #layouts)
                if not was[name] then changed = true end
                was[name] = nil
            end
        end

        if not changed and next(was) then
            changed = true
        end

        return layouts, changed
    end

    ---@type UIToolkit.ListItem.Column.Renderer
    local function nameRenderer(row, cfg, height)
        ---@cast row InventoryExtenderRedone.RowData
        local nonDraggedCount = getNonDraggedCount(row, self.role, self.mode)

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
        local nonDraggedCount = getNonDraggedCount(row, self.role, self.mode)

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

    -- Icon/Name behavior closes over the handler: merge its open-time closures over the
    -- resolved parts by id; width/sort only fill in when absent, so a patch can replace them
    for i = 1, #self.columns do
        local column = self.columns[i]
        if column.id == 'Icon' then
            if not column.width then
                column.width = rowHeight + 8
            end
            if not column.sort then
                column.sort = fallBackSort
            end
        elseif column.id == 'Name' then
            if not column.sort then
                column.sort = { numeric = false }
            end
            column.render = nameRenderer
            column.update = nameUpdater
        end
    end

    local infoHeight = self.infoBar:getHeight()
    local topBarHeight = self:getTopBarHeight()
    self.table = ItemTable:new()
    self.table:init {
        columns = self.columns --[[@as UIToolkit.SortedList.Column[] ]],
        defaultColumn = 'Icon',
        showGrid = getItemViewMode() == 'ItemViewMode_Grid',
        getBadges = getItemBadgeState,
        horizontalGrid = configPlayer.window.b_HorizontalGrid,
        size = v2(inner.x, inner.y - topBarHeight - infoHeight - 4),
        rowHeight = rowHeight,
        scrollStep = configPlayer.window.i_TableScrollStep,
        noBorder = true,
        onListClicked = function(button)
            if button ~= 1 then return end
            if not ctx.dragAndDrop.draggingObject then return end
            ctx.dragAndDrop:stopDrag(self.target)
        end,
        onItemClicked = function(row)
            ---@cast row InventoryExtenderRedone.RowData
            self:onRowPickup(row, false, false)
        end
    }
    local column = saved and saved.sortingColumn or 'Icon'
    local sortDir = saved and saved.sortingDirection
    if column then self.table.header:toggleColumn(column, sortDir ~= false) end
    self.table:updateProps { position = v2(0, topBarHeight + 2) }
    self.table:setFilter(self.filter --[[@as UIToolkit.SortedList.Filter]])
    local categoryKey = openedCategory[getOpenedCategoryKey()]
    if categoryKey then
        self.categoryFilter:setCategory(categoryKey)
    end
    categoryKey = self.categoryFilter:getCategory()
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

    self:updateInputHints()
end

--- Points this window at another actor, so its rows, info bar and sorting follow that actor.
--- With nil it re-applies the role's default from the target slot, the same rule onOpened used;
--- a non-nil actor must be a live object, otherwise this throws. Does not refresh the window:
--- batch the writes, then call IER.update() once and only read rows after that.
---@param actor openmw.Object?
function Inventory:setTarget(actor)
    if not actor then
        self.target = resolveTarget(self, self.slots, self.ctx)
        return
    end
    -- omwself is a SelfObject and has no isValid; enabled is read-only outside global scripts
    if actor ~= omwself and not (actor:isValid() and actor.enabled) then
        error('InventoryExtenderRedone setTarget: invalid actor', 2)
    end
    self.target = actor
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
    -- the mode's post-close hook: the only close path a custom mode has, since it never changes
    -- the engine UI mode. Runs while this window's open-time snapshot is still readable, once per
    -- closing window (a two-role mode fires twice), including the close that precedes a reopen.
    local mode = self.mode and Mode.resolve(self.mode)
    if mode and mode.lifecycle and mode.lifecycle.onClosed then
        L.debug('lifecycle.onClosed', self.role, self.mode)
        mode.lifecycle.onClosed(self)
    end
    self.wnd = nil
    self.arg = nil
    local column, asc = self.table.header:getActiveColumn()
    L.info('onClosed', self.role, self.mode, column, asc)
    ---@type IER.Inventory.SaveData
    return {
        sortingColumn = column,
        sortingDirection = asc,
    }
end

function Inventory:onResized(inner)
    local infoHeight = self.infoBar:getHeight()
    local topBarHeight = self:getTopBarHeight()
    local tableSize = inner - v2(0, topBarHeight + infoHeight + 4)
    L.debug('onResized', self.role, self.mode, inner, infoHeight, topBarHeight, tableSize)
    self.table:setSize(tableSize)
end

function Inventory:getTopBarHeight()
    return self.categoryFilter:getSize().y
end

function Inventory:updateInputHints()
    local binds = configPlayer.keybinds
    local find = cfgUtil.getFirstControllerInput
    local select = self.table.showGrid
        and { find(binds.c_SelUp), find(binds.c_SelDown), find(binds.c_SelLeft), find(binds.c_SelRight) }
        or { find(binds.c_SelUp), find(binds.c_SelDown) }
    local swap = configPlayer.keybinds.b_SwapUsePickup

    -- the base list is the interface default; the hints role slot replaces it wholesale
    local hints = {
        { text = l10n(swap and 'Hint_Use' or 'Hint_Pickup'), input = { id = BUTTON.A } },
        { text = l10n(swap and 'Hint_Pickup' or 'Hint_Use'), input = find(binds.c_Activate) },
        'separator',
        { text = l10n 'Hint_Category', input = { find(binds.c_CatPrev), find(binds.c_CatNext) }, },
        { text = l10n 'Hint_Select',   input = select, },
        'separator',
        { text = constants.Strings.CLOSE, input = { id = input.CONTROLLER_BUTTON.B } },
    }
    local hintsFn = self.slots and self.slots.hints
    if hintsFn then
        hints = hintsFn(self, self.ctx, hints) or hints
    end
    -- the favorite hint is a shared row mechanic, not mode behavior: it prefixes whichever list
    -- the mode left in place, for the player's own window
    if self.target == omwself then
        table.insert(hints, 1, { text = l10n 'Hint_Favorite', input = find(binds.c_Favorite) })
    end
    self.wnd:setControllerHints(hints)
end

---@param bind string?
function Inventory:onInput(bind)
    if I.UI.getMode() == nil then return end
    --TODO: add binds to toggle view mode (select?)
    --TODO: add binds to open column config popup (R-Stick?) (and add binds to popup itself)
    if bind == BINDING.Category_Prev then
        self.categoryFilter:cycleCategory(-1)
    elseif bind == BINDING.Category_Next then
        self.categoryFilter:cycleCategory(1)
    elseif bind == BINDING.Select_Up then
        self.table:shiftHoveredItem(v2(0, -1)) --TODO: consider diagonals?
    elseif bind == BINDING.Select_Down then
        self.table:shiftHoveredItem(v2(0, 1))
    elseif bind == BINDING.Select_Left then
        self.table:shiftHoveredItem(v2(-1, 0))
    elseif bind == BINDING.Select_Right then
        self.table:shiftHoveredItem(v2(1, 0))
    elseif bind == BINDING.Favorite then
        self:toggleFavorite()
    elseif bind == BINDING.TransferAll then
        self:transferAll()
    elseif bind == BINDING.Activate then
        local ctx = self.ctx
        local row = self.table:getHovered()
        if configPlayer.keybinds.b_SwapUsePickup then
            if ctx.dragAndDrop.draggingObject then
                ctx.dragAndDrop:stopDrag(self.target)
            elseif row then
                self:onRowPickup(row, true, false)
            end
        elseif row then
            self:onRowUse(row)
        end
    end
end

function Inventory:onInputRepeat(bind)
    if bind == BINDING.Select_Up or bind == BINDING.Select_Down
        or bind == BINDING.Select_Left or bind == BINDING.Select_Right
    then
        self:onInput(bind)
    end
end

function Inventory:onKeyboardButtonPress(key)
    self:onInput(cfgUtil.findMatchingKeyboard(key, configPlayer.keybinds))
end

function Inventory:onKeyboardButtonRepeat(key)
    self:onInputRepeat(cfgUtil.findMatchingKeyboard(key, configPlayer.keybinds))
end

function Inventory:onControllerButtonPress(button)
    if button == input.CONTROLLER_BUTTON.A then
        local focused = I.UIToolkit.getCtx().focusedScrollable
        if focused ~= self.table:currentScrollable() then
            local row = self.table:getHovered()
            if not configPlayer.keybinds.b_SwapUsePickup then
                local ctx = self.ctx
                if ctx.dragAndDrop.draggingObject then
                    ctx.dragAndDrop:stopDrag(self.target)
                elseif row then
                    self:onRowPickup(row, true, false)
                end
            elseif row then
                self:onRowUse(row)
            end
        end
    end
    self:onInput(cfgUtil.findMatchingController(button, configPlayer.keybinds))
end

function Inventory:onControllerButtonRepeat(button)
    self:onInputRepeat(cfgUtil.findMatchingController(button, configPlayer.keybinds))
end

function Inventory:getStorageSuffix()
    if self.wnd then return self.suffix end
    -- not open yet: UIToolkit asks before onOpened, so resolve against the engine mode the
    -- window is about to open in (the same read onOpened makes)
    local _, roleSpec = Mode.resolveMode(self.role, nil, I.UI.getMode())
    return roleSpec and roleSpec.storageSuffix
end

function Inventory:getDefaultStorage()
    if self.wnd then return self.slots and self.slots.defaultStorage end
    local _, roleSpec = Mode.resolveMode(self.role, nil, I.UI.getMode())
    return roleSpec and roleSpec.defaultStorage
end

function Inventory:update()
    self.table.provider:markCacheDirty()
    self.table.gridProvider:markAllDirty()
    local data = self:createData()
    self.table:setItems(data)
    self.categoryFilter.updateCategories()
    if self.infoBar then self.infoBar:update() end
    L.debug('refresh', self.role, self.mode, #data, #self.table.filteredItems)
end

--- The row under the cursor in this window, or nil when nothing is hovered or the window
--- is not open.
---@return InventoryExtenderRedone.RowData?
function Inventory:getHoveredRow()
    if not self.table then return nil end
    return self.table:getHovered()
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
        and self.mode ~= D.Modes.Interface
end

function Inventory:transferAll()
    if self.mode ~= D.Modes.Container then return end
    if not self.arg then return end

    local ctx = self.ctx
    I.InventoryExtenderRedone.forEachOpenWindow(function(handler)
        if handler.target == omwself then return end

        local items = {}
        local visibleItems = handler.table.filteredItems
        for i = 1, #visibleItems do
            local row = visibleItems[i]
            if row and row.item and not row:isDisabled() then
                items[#items + 1] = row.item
            end
        end

        if not items or #items > 0 then
            ctx.dragAndDrop:moveAll(handler.target, omwself, items)
        end
    end)


    I.UI.removeMode(D.Modes.Container)
end

---@param row InventoryExtenderRedone.RowData
function Inventory:onRowUse(row)
    if self.mode == D.Modes.Barter then
        return self:onRowPickup(row, true, true)
    end
    local ctx = self.ctx
    for i = #ctx.handlers.onRowUse, 1, -1 do
        local handler = ctx.handlers.onRowUse[i]
        if handler.handler(row, ctx, self.role) == false then
            return false
        end
    end

    local use = self.actions and self.actions.use
    if not use or not use.enabled(row, self, ctx) then
        return false
    end

    if Player.hasEquipped(omwself, row.item) then
        local equipment = Player.getEquipment(omwself) --[[@as openmw.types.EquipmentTable]]
        for slot, equippedItem in pairs(equipment) do
            if equippedItem == row.item then
                equipment[slot] = nil
                Player.setEquipment(omwself, equipment)
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
            source = use.source and use.source(row, self, ctx) or row.item.parentContainer or omwself,
            pickpocket = use.pickpocket and use.pickpocket(row, self, ctx) or nil,
        })
    end
end

---@param row InventoryExtenderRedone.RowData
---@param fromKBMKeybind boolean? true when the action came from a keyboard/controller bind
---@param forceBarterAction boolean? set when delegated from the use action; keeps the delegation one-way
function Inventory:onRowPickup(row, fromKBMKeybind, forceBarterAction)
    local ctx = self.ctx
    L.info('onRowPickup', self.role, self.mode, row.id, row.getCount())
    if ctx.dragAndDrop.draggingObject then
        if fromKBMKeybind then
            ctx.dragAndDrop:stopDrag(self.target)
        end
        L.debug('pickup: already dragging', self.role, self.mode, ctx.dragAndDrop.draggingObject.id)
        return true
    end

    if configPlayer.keybinds.b_SwapUsePickup and not fromKBMKeybind then
        L.debug('pickup: swapped to use action', self.role, self.mode)
        return self:onRowUse(row)
    end

    for i = #ctx.handlers.onRowPickup, 1, -1 do
        local handler = ctx.handlers.onRowPickup[i]
        if handler.handler(row, ctx, self.role) == false then
            L.debug('pickup: stopped by registered handler', self.role, self.mode, handler.id)
            return false
        end
    end

    if helpers.isBoundItem(row.item) then
        L.debug('pickup: bound item', self.role, self.mode, row.item.recordId)
        local gmst
        if self.mode == D.Modes.Barter then
            if self.role == 'Trade' then
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
        L.debug('pickup: favorite transfer blocked', self.role, self.mode, row.item.id)
        ui.showMessage(l10n('UI_Msg_FavoriteItem'))
        return false
    end

    local transfer = input.isAltPressed() or self.mode == D.Modes.Barter
    local takeAll = input.isShiftPressed() or input.getAxisValue(input.CONTROLLER_AXIS.TriggerRight) > 0.5
    local takeOne = input.isCtrlPressed() or input.getAxisValue(input.CONTROLLER_AXIS.TriggerLeft) > 0.5

    if takeAll and takeOne and not forceBarterAction then
        self:onRowUse(row)
        return
    end

    local itemCount = row.getCount()
    if self.mode == D.Modes.Barter then
        if row.isBartered then
            if self.role == 'Inventory' then
                itemCount = (ctx.barterState.buying[row.item.id] or {}).count or 0
            else
                itemCount = (ctx.barterState.selling[row.item.id] or {}).count or 0
            end
        else
            if self.role == 'Inventory' then
                itemCount = itemCount - ((ctx.barterState.selling[row.item.id] or {}).count or 0)
            elseif self.role == 'Trade' then
                itemCount = itemCount - ((ctx.barterState.buying[row.item.id] or {}).count or 0)
            end
        end
    end

    -- the mode's pickup part carries the mode-specific effect: perform for a plain action,
    -- transfer for the Alt-held variant; the pickpocket roll and the barter offer bookkeeping
    -- live inside the parts, not here
    local function doAction(count)
        local pickup = self.actions and self.actions.pickup
        if not pickup then
            L.debug('doAction: mode names no pickup part', self.role, self.mode)
            return false
        end
        local action = transfer and pickup.transfer or pickup.perform
        if not action then
            L.debug('doAction: pickup part names no action', self.role, self.mode, transfer)
            return false
        end
        L.debug('doAction', self.role, self.mode, transfer and 'transfer' or 'perform', count)
        return action(row, self, ctx, count)
    end

    if itemCount > 1 and not takeAll and not takeOne then
        L.debug('pickup: stack popup', self.role, self.mode, itemCount)
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
    -- the window's own mode snapshot decides: a pinned Interface window keeps this title while
    -- the engine mode stack is empty
    if self.mode == D.Modes.Interface then
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
        L.warn('createData: no target', self.role, self.mode)
        return {}
    end

    local ctx = self.ctx
    local modifiers = ctx.modifiers.data

    ---@type fun(...):boolean
    local rowIsDisabled
    local observer = omwself --[[@as openmw.Object]]
    -- per-row state predicates come from the mode's states slot; a list of States ORs together
    local slots = self.slots
    if slots then
        rowIsDisabled = Mode.statePredicate(slots.states, 'isDisabled')
        local observerFn = slots.observer
        observer = observerFn and observerFn(self, ctx) or observer
    end
    --context data for the tooltip
    --[[
    local IER = {
        window = self.role,
        mode = self.mode,
        arg = self.arg,
    }
    ]]

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

        local baseTip = {
            object = itemStack,
            observer = observer,
            owned = isOwned,
            --IER = IER,
        }
        local function tooltip()
            local comparison = getEquippedItemsForComparison(itemStack, ctx)
            if not comparison or #comparison <= 0 then return baseTip end
            local tips = { Tooltips.createTooltipLayout(baseTip) }
            for i = 1, #comparison do
                table.insert(tips, 1, Tooltips.createTooltipLayout({
                    object = comparison[i],
                    observer = observer,
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
        local rowData
        rowData = {
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
                return helpers.getArmorRating(itemStack, observer)
            end,
            Condition = function()
                return helpers.getConditionPercentLabel(itemStack)
            end,
            Quality = record.quality and helpers.roundToPlaces(record.quality, 3),
            Value = helpers.roundToPlaces(value, 1),
            Weight = helpers.roundToPlaces(record.weight, 2),
            Weight_Total = helpers.roundToPlaces(record.weight * getItemCount(), 2),
            ['V/W'] = helpers.roundToPlaces(vw, vwPrecision),
            StealChance = function()
                return pickpocket.getStealChance(omwself, self.target, itemStack, getItemCount())
            end,
            item = itemStack,
            itemRecord = record,
            isBartered = isBartered,
            virtualStacks = isVirtual and item.stacks or nil,
            getCount = getItemCount,
            getNonDraggedCount = function()
                return getNonDraggedCount(rowData, self.role, self.mode)
            end,
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
                if not rowIsDisabled then return false end
                return rowIsDisabled(rowData, self, ctx) == true
            end,
        }

        --[[ uncomment to have bartered items look active
        if isBartered then
            rowData.isActive = function() return true end
        end
        ]]

        for i = 1, #modifiers do
            modifiers[i].modifier(rowData, ctx, self.role)
        end

        return rowData
    end

    local data = {}

    -- whose contents these rows are, for the tooltip badge: the mode's states slot decides
    local states = self.slots and self.slots.states
    local isOwnedState = states and states.isOwned
    local isOwned = false
    if isOwnedState then
        isOwned = isOwnedState(self, ctx) == true
    end

    -- rows come from the mode's sources: which inventories feed this window, in order
    local sources = self.sources or {}
    for i = 1, #sources do
        local source = sources[i]
        if not (source.enabled and not source.enabled(self, ctx)) then
            local items = source.get and source.get(self, ctx) or {}
            local isBartered = source.isBartered == true
            local isVirtual = source.virtual == true
            local owned = isOwned
            if source.isOwned ~= nil then
                if type(source.isOwned) == 'function' then
                    owned = source.isOwned(self, ctx) == true
                else
                    owned = source.isOwned == true
                end
            end

            for j = 1, #items do
                local item = items[j]
                if not (source.filter and not source.filter(item, self, ctx)) then
                    data[#data + 1] = createRowData(item, isBartered, isVirtual, owned)
                end
            end
        end
    end

    return data
end

---@private
function Inventory:initInfoBar()
    local sections = self.infoBarSections
    if not sections then return end
    local ctx = self.ctx
    -- sections come from this role's infoBar slot, in slot order: create builds the once-per-open
    -- part and returns the per-frame provider; a provider-only section is stateless, and cleanup
    -- runs when the bar is destroyed
    for i = 1, #sections do
        local section = sections[i]
        local provider = section.provider
        if section.create then
            provider = section.create(self, ctx)
        end
        self.infoBar:addProvider(provider --[[@as InventoryExtenderRedone.InfoBar.Provider]], section.cleanup)
    end
end

return Inventory
