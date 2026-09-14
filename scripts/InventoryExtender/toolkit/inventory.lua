---@omw-context player


local core      = require 'openmw.core'
local ui        = require 'openmw.ui'
local util      = require 'openmw.util'
local types     = require 'openmw.types'
local omwself   = require 'openmw.self'
local aux_util  = require 'openmw_aux.util'

local I         = require 'openmw.interfaces'
local v2        = util.vector2

local Container = types.Container


local configPlayer = require('scripts.InventoryExtender.config.player')
local helpers = require('scripts.InventoryExtender.util.helpers')
local l10n = core.l10n('InventoryExtender')


local Class          = require 'scripts.UIToolkit.class'
local WindowHandler  = require 'scripts.UIToolkit.window_handler'
local ColumnItem     = require 'scripts.UIToolkit.components.list_items.column_item'
local CompoundFilter = require 'scripts.UIToolkit.compound_filter'

local CategoryFilter = require('scripts.InventoryExtender.toolkit.categoryFilter')

local function getEnchantedIndicatorMode()
    return configPlayer.tweaks.s_EnchantedIndicatorMode or 'EnchantedIndicatorMode_Both'
end

local function shouldShowEnchantedSwirl(forceEnchantSwirl)
    return forceEnchantSwirl or getEnchantedIndicatorMode() ~= 'EnchantedIndicatorMode_Icon'
end

---@type UIToolkit.ListItem.Column.Renderer
local function iconRenderer(data, cfg, height)
    local width = cfg.width
    local sz = cfg.arg and cfg.arg.sz or math.min(height, width or height)
    local options = cfg.arg or {}
    local ctx = I.InventoryExtender.getContext()

    local equipped = helpers.isItemEquipped(data.item, data.item.parentContainer, ctx.overrides.equipped)
    local showEnchantSwirl = data.showAsEnchanted() and shouldShowEnchantedSwirl(options.forceEnchantSwirl) or false
    local bgrVisible = data.isBartered or equipped or showEnchantSwirl
    local magicString = showEnchantSwirl and '_magic' or ''
    local postString = (data.isBartered and '_barter') or (equipped and '_equip') or (magicString ~= '' and '') or
        '_none'
    local bgrPath = 'textures/menu_icon' .. magicString .. postString .. '.dds'
    return {
        name = 'Icon',
        props = {
            size = v2(width, height),
        },
        content = ui.content {
            {
                name = 'itemBackground',
                type = ui.TYPE.Image,
                props = {
                    resource = I.UIToolkit.texture(bgrPath, v2(40, 40), bgrPath == 'textures/menu_icon_barter.dds' and v2(4, 4) or v2(2, 2)),
                    anchor = v2(0.5, 0.5),
                    relativePosition = v2(0.5, 0.5),
                    size = v2(sz, sz),
                    visible = bgrVisible,
                }
            },
            {
                name = 'itemIcon',
                type = ui.TYPE.Image,
                props = {
                    resource = I.UIToolkit.texture(data.itemRecord.icon),
                    anchor = v2(0.5, 0.5),
                    relativePosition = v2(0.5, 0.5),
                    size = v2(sz, sz),
                }
            },
        },
        userData = {
            bgrVisible = bgrVisible,
            bgrPath = bgrPath,
        }
    }
end

local function ALL_COLUMNS()
    local theme = I.UIToolkit.getTheme()
    local textSize = theme.Sizes.textNormal
    local lineHeight = textSize + 2
    local fontRatio = textSize / 16
    local w = 60 * fontRatio

    ---@type UIToolkit.SortedList.Column[]
    return {
        {
            id = 'Icon',
            width = lineHeight * 1.5 + 8,
            render = iconRenderer,
        },
        {
            id = 'Name',
            name = l10n('Column_Name'),
            sort = { numeric = false },
            render = ColumnItem.renderText,
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
            defaultOrder = 'desc',
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Damage',
            name = l10n('Column_Damage'),
            sort = { numeric = true },
            width = 60 * fontRatio,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Quality',
            name = l10n('Column_Quality'),
            sort = { numeric = true },
            width = 60 * fontRatio,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Condition',
            name = l10n('Column_Condition'),
            width = 55 * fontRatio,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
            sort = function(a, b)
                local aValue = helpers.getConditionPercent(a.item)
                local bValue = helpers.getConditionPercent(b.item)

                if aValue == bValue then
                    return 0
                end
                if aValue == nil then
                    return 1
                end
                if bValue == nil then
                    return -1
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
            defaultOrder = 'desc',
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Weight_Total',
            name = l10n('Column_Weight_Total'),
            sort = { numeric = true },
            width = 70 * fontRatio,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Value',
            name = l10n('Column_Value'),
            sort = { numeric = true },
            width = w,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'V/W',
            name = l10n('Column_VW'),
            sort = { numeric = true },
            width = w,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
        }
    }
end

local function getAvailableCategories()
    local categories = I.InventoryExtender.getCategories()
    local filteredCategories = {}
    for _, category in ipairs(categories) do
        if category.key ~= 'Favorites' --[[ or (self.target == omwself and hasFavorites()) ]] then
            table.insert(filteredCategories, category)
        end
    end
    return filteredCategories
end

---@class IER.Inventory: UIToolkit.WindowHandler
---@field new fun(self:IER.Inventory):IER.Inventory
---@field arg table
---@field wnd UIToolkit.Window
local Inventory = Class(WindowHandler)

function Inventory:init(type)
    self.type = type
end

function Inventory:onOpened(wnd, data, saved)
    self.arg = data
    self.wnd = wnd

    if self.type == 'Inventory' then
        self.target = omwself
    else
        self.target = data
    end
    self.filter = CompoundFilter:new()

    local inner = wnd:getInnerSize()
    local theme = I.UIToolkit.getTheme()
    local textSize = theme.Sizes.textNormal
    local rowHeight = util.round(1.5 * (textSize + 2))

    self.categoryFilter = CategoryFilter.create({
            maxHeight = 72,
            compact = configPlayer.tweaks.b_CompactCategoryFilter,
            vanillaStyle = configPlayer.tweaks.b_VanillaCategoryIcons,
            getCategories = getAvailableCategories,
            getCategoryDisabledLookup = function()
                return {}
            end,
            onOpenSettings = openColumnSettings,
            onToggleView = toggleItemViewMode,
            getViewMode = getItemViewMode,
        },
        ---@param category InventoryExtenderRedone.Category
        function(category)
            print('----', 'CATEGORY', helpers.deepPrint(category))

            if category.filter then
                self.filter:add('category', function(row)
                    return category.filter(row.item)
                end)
            else
                self.filter:remove('category')
            end

            self.list:filter(false)
            self.list:setHiddenColumns(category.hiddenColumns)

            self:updateTitle()
        end, function(text)
            print('----', 'SEARCH', text)
        end)

    self.list = I.UIToolkit.Components.sortedList {
        columns = ALL_COLUMNS(),
        size = v2(inner.x, inner.y - rowHeight - 10),
        noBorder = true,
    }
    self.list:updateProps { position = v2(0, rowHeight + 10) }
    self.list:setFilter(self.filter)
    local categoryKey = self.categoryFilter.layout.userData.getCategory()
    local category = categoryKey and I.InventoryExtender.getCategory(categoryKey)
    if category then self.list:setHiddenColumns(category.hiddenColumns) end
    self.list:setItems(self:createData())

    wnd:setContent(ui.content {
        self.categoryFilter,
        { template = I.MWUI.templates.horizontalLine, props = { position = v2(0, rowHeight + 8), } },
        self.list.element,
    })
    self:updateTitle()
end

function Inventory:onClosed()
    self.wnd = nil
    self.arg = nil
end

function Inventory:onResized(inner)
    local theme = I.UIToolkit.getTheme()
    local textSize = theme.Sizes.textNormal
    local rowHeight = util.round(1.5 * (textSize + 2))

    self.list:setSize(inner - v2(0, rowHeight + 10))
end

function Inventory:getStorageSuffix()
    if self.type ~= 'Inventory' then return nil end
    local mode = I.UI.getMode()
    if mode == 'Barter' or mode == 'Container' or mode == 'Companion' then
        return ':' .. mode
    end
    return nil
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

    if configPlayer.tweaks.b_CompactCategoryFilter and self.categoryFilter and self.categoryFilter.layout and self.categoryFilter.layout.userData.getCategory then
        local categoryKey = self.categoryFilter.layout.userData.getCategory()
        local category = categoryKey and I.InventoryExtender.getCategory(categoryKey)
        if category and category.name then
            title = title and (title .. ' - ' .. category.name) or category.name
        end
    end

    if title then
        self.wnd:setTitle(title)
    end
end

---@private
function Inventory:createData()
    if not self.target then
        return {}
    end

    local ctx = I.InventoryExtender.getContext()

    local function createRowData(item, isBartered, isVirtual)
        local itemStack = isVirtual and item.stacks[1] or item

        if not types.Item.isCarriable(itemStack) then return nil end

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

        local rowData = {
            id = itemStack.id,
            Name = helpers.getItemName(itemStack),
            SearchText = helpers.getItemSearchText(itemStack):lower(),
            Type = function()
                return helpers.getItemTypeLabel(itemStack)
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
            tooltip = { object = itemStack, observer = omwself },
            showAsEnchanted = function()
                if record.enchant then
                    return true
                end
                if configPlayer.tweaks.b_FilledGemsAppearEnchanted and types.Item.itemData(itemStack).soul then
                    return true
                end
                return false
            end,
            disabledFn = function()
                if not isBartered and I.UI.getMode() == 'Container' and self.type == 'Inventory' then
                    local container = ctx.windowArgs.Container
                    if Container.objectIsInstance(container) and Container.record(container).isOrganic then
                        return true
                    end
                    return not helpers.doesItemFit(itemStack, ctx.windowArgs.Container, 1)
                end
            end,
        }

        -- if isBartered then
        --     rowData.activeFn = function() return true end
        -- end

        return rowData
    end

    local data = {}

    -- Add primary inventory
    if self.type ~= 'Trade' then
        for _, item in ipairs(self.target.type.inventory(self.target):getAll()) do
            table.insert(data, createRowData(item, false, false))
        end
    else
        for _, recordId in pairs(helpers.getMerchantItems(self.target)) do
            for _, virtualItem in ipairs(recordId) do
                table.insert(data, createRowData(virtualItem, false, true))
            end
        end
    end

    -- Add bartered items from other inventory
    if I.UI.getMode() == 'Barter' then
        if self.type == 'Trade' then
            for _, item in ipairs(omwself.type.inventory(omwself):getAll()) do
                table.insert(data, createRowData(item, true, false))
            end
        else
            local barterNpc = ctx.windowArgs.Trade or self.arg --TODO: consider removing `ctx.windowArgs`
            if barterNpc then
                for _, recordId in pairs(helpers.getMerchantItems(barterNpc)) do
                    for _, virtualItem in ipairs(recordId) do
                        table.insert(data, createRowData(virtualItem, true, true))
                    end
                end
            end
        end
    end

    return data
end

return Inventory
