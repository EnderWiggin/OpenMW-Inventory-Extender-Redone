---@omw-context player


local ambient   = require 'openmw.ambient'
local core      = require 'openmw.core'
local input     = require 'openmw.input'
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
local barterUtils = require('scripts.InventoryExtender.util.barter')
local constants = require('scripts.InventoryExtender.util.constants')
local iconPack = require('scripts.InventoryExtender.util.iconPack')
local l10n = core.l10n('InventoryExtender')
local Pickpocket = require('scripts.InventoryExtender.util.pickpocket')
local ItemStackModal = require('scripts.InventoryExtender.ui.templates.itemStackModal') --TODO: change to UI Toolkit popup
local InfoBar = require('scripts.InventoryExtender.toolkit.info_bar')


local H              = require 'scripts.UIToolkit.helpers'
local Class          = require 'scripts.UIToolkit.class'
local WindowHandler  = require 'scripts.UIToolkit.window_handler'
local ColumnItem     = require 'scripts.UIToolkit.components.list_items.column_item'
local CompoundFilter = require 'scripts.UIToolkit.compound_filter'
local Toolkit        = I.UIToolkit
local Components     = Toolkit.Components
local T              = Toolkit.Templates

local CategoryFilter = require('scripts.InventoryExtender.toolkit.categoryFilter')

local function getEnchantedIndicatorMode()
    return configPlayer.tweaks.s_EnchantedIndicatorMode or 'EnchantedIndicatorMode_Both'
end

local function shouldShowEnchantedSwirl(forceEnchantSwirl)
    return forceEnchantSwirl or getEnchantedIndicatorMode() ~= 'EnchantedIndicatorMode_Icon'
end

local function shouldShowEnchantedNameIcon()
    return getEnchantedIndicatorMode() ~= 'EnchantedIndicatorMode_Swirl'
end

---@type UIToolkit.ListItem.Column.Renderer
local function iconRenderer(data, cfg, height)
    ---@cast data InventoryExtenderRedone.RowData
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
                    resource = Toolkit.texture(bgrPath, v2(40, 40), bgrPath == 'textures/menu_icon_barter.dds' and v2(4, 4) or v2(2, 2)),
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
                    resource = Toolkit.texture(data.itemRecord.icon),
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

---@type UIToolkit.ListItem.Column.Renderer
local function renderNumber(data, cfg, height)
    local value = data[cfg.id] or ''
    if type(value) == 'function' then
        value = value()
    end

    if value == 0 or value == nil then
        value = '-'
    elseif type(value) == 'number' then
        value = H.addSeparators(H.roundToPlaces(value, 2))
    end
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
            text = tostring(value),
        },
        userData = { colorable = true },
    }

    ColumnItem.applySize(layout, cfg, height)
    return layout
end

local function getNonDraggedCount(row, type)
    local nonDraggedCount = row.getCount()
    local ctx = I.InventoryExtender.getContext()

    local drag = ctx.dragAndDrop
    if drag.draggingObject and drag.draggingObject.id == row.item.id then
        nonDraggedCount = nonDraggedCount - drag.draggingCount
    end

    if I.UI.getMode() == 'Barter' then
        local buying = ctx.barterState.buying
        local selling = ctx.barterState.selling
        if row.isBartered then
            if type == 'Inventory' then
                nonDraggedCount = (buying[row.item.id] or {}).count or 0
            else
                nonDraggedCount = (selling[row.item.id] or {}).count or 0
            end
        else
            if type == 'Inventory' then
                nonDraggedCount = nonDraggedCount - ((selling[row.item.id] or {}).count or 0)
            elseif type == 'Trade' then
                nonDraggedCount = nonDraggedCount - ((buying[row.item.id] or {}).count or 0)
            end
        end
    end

    return nonDraggedCount
end

local function isStealing(actor, ownerInfo, variable)
    if not ownerInfo then return false end

    local ctx = I.InventoryExtender.getContext()
    if variable then
        local value = ctx.containerVariables[variable]
        if value and value ~= 0 then return false end
    end

    if ownerInfo.recordId and ownerInfo.recordId ~= actor.recordId then
        return true
    end

    if ownerInfo.factionId then
        local reqRank = ownerInfo.factionRank or 1
        if types.NPC.getFactionRank(actor, ownerInfo.factionId) < reqRank then
            return true
        end
    end
    return false
end


local function ALL_COLUMNS(defaultSort, nameRenderer)
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
        },
        {
            id = 'Name',
            name = l10n('Column_Name'),
            sort = { numeric = false },
            render = nameRenderer,
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
            render = renderNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Damage',
            name = l10n('Column_Damage'),
            sort = { numeric = true },
            width = 60 * fontRatio,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = renderNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Quality',
            name = l10n('Column_Quality'),
            sort = { numeric = true },
            width = 60 * fontRatio,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = renderNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Condition',
            name = l10n('Column_Condition'),
            width = 55 * fontRatio,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = renderNumber,
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
            render = renderNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Weight_Total',
            name = l10n('Column_Weight_Total'),
            sort = { numeric = true },
            width = 70 * fontRatio,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = renderNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'Value',
            name = l10n('Column_Value'),
            sort = { numeric = true },
            width = w,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = renderNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        },
        {
            id = 'V/W',
            name = l10n('Column_VW'),
            sort = { numeric = true },
            width = w,
            align = ui.ALIGNMENT.End,
            defaultOrder = 'desc',
            render = renderNumber,
            arg = { textAlignH = ui.ALIGNMENT.End },
        }
    }
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

function Inventory:onOpened(wnd, data, saved)
    self.arg = data
    self.wnd = wnd
    self.suffix = getStorageSuffix(self.type)
    local IE = I.InventoryExtender
    local ctx = IE.getContext()

    if self.type == 'Inventory' then
        self.target = omwself
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
            for t, serviceName in pairs(constants.TypeToService) do
                if types[t].objectIsInstance(item) then
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

    local inner = wnd:getInnerSize()
    local theme = Toolkit.getTheme()
    local textSize = theme.Sizes.textNormal
    local rowHeight = util.round(1.5 * (textSize + 2))
    local texture = Toolkit.texture

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

        local mode = I.UI.getMode()
        local inBarterMode = mode == 'Barter'

        local aEquipped = helpers.isItemEquipped(a.item, self.target, ctx.overrides.equipped)
        local bEquipped = helpers.isItemEquipped(b.item, self.target, ctx.overrides.equipped)

        local aFavorited = isFavorited(a.item)
        local bFavorited = isFavorited(b.item)

        if inBarterMode then
            local config = helpers.getWindowSettings()
            local reverseEquipped = config:get(constants.OPT_KEYS.SortingBarterReverseEquipped)
            local reverseFavorite = config:get(constants.OPT_KEYS.SortingBarterReverseFavorite)

            if reverseFavorite and not reverseEquipped then
                -- if only favorites are reversed, prioritize sorting by favorite status
                if aFavorited ~= bFavorited then
                    -- favorited items come last (true > false)
                    return bFavorited and -1 or 1
                end

                if aEquipped ~= bEquipped then
                    -- equipped items come first (true > false)
                    return aEquipped and -1 or 1
                end
            else
                if aEquipped ~= bEquipped then
                    -- equipped items come first (true > false), unless we reverse it
                    if reverseEquipped then
                        return bEquipped and -1 or 1
                    else
                        return aEquipped and -1 or 1
                    end
                end

                if aFavorited ~= bFavorited then
                    -- favorited items come first (true > false), unless we reverse it
                    if reverseFavorite then
                        return bFavorited and -1 or 1
                    else
                        return aFavorited and -1 or 1
                    end
                end
            end
        else
            if aEquipped ~= bEquipped then
                -- equipped items come first (true > false)
                return aEquipped and -1 or 1
            end

            if aFavorited ~= bFavorited then
                -- favorited items come first (true > false)
                return aFavorited and -1 or 1
            end
        end

        -- Second, sort by Category
        local categories = IE.getCategories()
        local indexA, indexB = nil, nil
        for i, category in ipairs(categories) do
            if category.key ~= 'Favorites' then
                if category.filter then
                    if category.filter(a.item) then
                        indexA = i
                    end
                    if category.filter(b.item) then
                        indexB = i
                    end
                    if indexA and indexB then
                        break
                    end
                end
            end
        end
        if indexA ~= indexB then
            return ((indexA or math.huge) < (indexB or math.huge)) and -1 or 1
        end

        local typeA = (type(a.Type) == 'function' and a.Type() or a.Type or ''):lower()
        local typeB = (type(b.Type) == 'function' and b.Type() or b.Type or ''):lower()
        if typeA ~= typeB then
            return typeA < typeB and -1 or 1
        end

        local nameA = (type(a.Name) == "function" and a.Name() or a.Name):lower()
        local nameB = (type(b.Name) == "function" and b.Name() or b.Name):lower()
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
            --TODO: update sort column
        end, function(text)
            print('----', 'SEARCH', text)
        end
    )

    ---@param row InventoryExtenderRedone.RowData
    ---@param windowType string
    ---@return openmw.Object
    local function getUseItemSource(row, windowType)
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
    local function getUseItemPickpocket(row, windowType)
        local effectiveWindowType = windowType
        local mode = I.UI.getMode()
        if mode == 'Container' and effectiveWindowType == 'Container' and ctx.pickpocket and ctx.pickpocket.active then
            return { target = self.target }
        end
        return nil
    end

    local function isFavoriteTransferBlocked(row)
        return self.target == omwself
            and row and row.item ~= nil
            and not row.isBartered
            and isFavorited(row.item)
            and I.UI.getMode() ~= 'Interface'
    end

    local function getItemBadgeState(row)
        local favorite = isFavorited(row.item)
        local stolen = false

        if configPlayer.tweaks.b_StolenIndicator then
            if self.type == 'Inventory' and ctx.stolenItems then
                stolen = ctx.stolenItems[row.item.recordId] ~= nil
            elseif self.type == 'Container' then
                if ctx.pickpocket and ctx.pickpocket.active then
                    stolen = true
                elseif types.Container.objectIsInstance(self.target) then
                    stolen = isStealing(omwself, self.target.owner, self.target.globalVariable)
                end
            end
        end

        return {
            favorite = favorite,
            stolen = stolen,
        }
    end
    ---@type UIToolkit.ListItem.Column.Renderer
    local function nameRenderer(row, cfg, height)
        ---@cast row InventoryExtenderRedone.RowData
        local nonDraggedCount = getNonDraggedCount(row)

        local text = helpers.getItemName(row.item) ..
            (nonDraggedCount > 1 and (' (%s)'):format(helpers.addSeparators(nonDraggedCount)) or '')

        local badgeState = getItemBadgeState(row)
        local enchanted = false
        if row.showAsEnchanted() and shouldShowEnchantedNameIcon() then
            enchanted = true
        end

        local content = ui.content {
            {
                template = T.text(),
                props = {
                    text = text,
                },
                userData = {
                    colorable = true,
                }
            },
        }
        local iconSize = math.min(rowHeight, 12)
        if badgeState.favorite then
            content:add(T.intervalH(8))
            content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = texture(iconPack.getPath('item/favorited.dds')),
                    size = v2(iconSize, iconSize),
                    color = constants.Colors.GOLD,
                },
            })
        end
        if badgeState.stolen then
            content:add(T.intervalH(8))
            content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = texture(iconPack.getPath('item/stolen.dds')),
                    size = v2(iconSize, iconSize),
                    color = constants.Colors.DAMAGED,
                },
            })
        end
        if enchanted then
            content:add(T.intervalH(8))
            content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = texture(iconPack.getPath('item/enchanted.dds')),
                    size = v2(iconSize, iconSize),
                    color = constants.Colors.BAR_MAGIC,
                },
            })
        end

        local layout = {
            name = 'Name',
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
                autoSize = false,
            },
            content = content,
            userData = {
                text = text,
                favorite = badgeState.favorite,
                stolen = badgeState.stolen,
                enchanted = enchanted,
            }
        }
        ColumnItem.applySize(layout, cfg, height)
        return layout
    end

    local onRowUse, onRowPickup

    ---@param row InventoryExtenderRedone.RowData
    ---@param windowType string
    ---@param allowOutsideInterface boolean
    onRowPickup = function(row, windowType, allowOutsideInterface)
        if I.UI.getMode() == 'Barter' then
            return onRowUse(row, true, true)
        end

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
                    omwself:sendEvent('IE_Update')
                    break
                end
            end
        else
            core.sendGlobalEvent('IE_UseItem', {
                object = row.item,
                actor = omwself,
                source = getUseItemSource(row, windowType),
                pickpocket = getUseItemPickpocket(row, windowType),
            })
        end
    end

    onRowUse = function(row, fromKBMKeybind, forceBarterAction)
        if ctx.dragAndDrop.draggingObject then
            if fromKBMKeybind then
                ctx.dragAndDrop:stopDrag(self.target)
            end
            return true
        end

        if configPlayer.keybinds.b_SwapUsePickup and not fromKBMKeybind then
            return onRowPickup(row, self.type, true)
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

        if isFavoriteTransferBlocked(row) then
            ui.showMessage(l10n('UI_Msg_FavoriteItem'))
            return false
        end

        local transfer = input.isAltPressed() or I.UI.getMode() == 'Barter'
        local takeAll = input.isShiftPressed() or input.getAxisValue(input.CONTROLLER_AXIS.TriggerRight) > 0.5
        local takeOne = input.isCtrlPressed() or input.getAxisValue(input.CONTROLLER_AXIS.TriggerLeft) > 0.5

        if takeAll and takeOne and not forceBarterAction then
            onRowPickup(row, self.type, false)
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
                    core.sendGlobalEvent('IE_CommitPickpocket', {
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
                    omwself:sendEvent('IE_Update')
                elseif mode == 'Interface' then
                    if not isFavorited(row.item) then
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
            local modal = ItemStackModal.create({
                itemName = row.itemRecord.name,
                maxCount = itemCount,
                onConfirm = function(count)
                    doAction(count)
                end,
            }, ctx)
            ctx.modalElement = modal
        else
            doAction(takeOne and 1 or itemCount)
        end
    end

    self.infoBar = InfoBar.create({}) --[[@as InventoryExtenderRedone.InfoBarPrivate  ]]

    local infoHeight = self.infoBar:getHeight()
    local topBarHeight = self.categoryFilter:getSize().y
    self.list = Components.sortedList {
        columns = ALL_COLUMNS(fallBackSort, nameRenderer),
        size = v2(inner.x, inner.y - topBarHeight - infoHeight - 4),
        noBorder = true,
        onItemClicked = function(row)
            onRowUse(row, false, false)
        end
    }
    self.list:updateProps { position = v2(0, topBarHeight + 2) }
    self.list:setFilter(self.filter)
    local categoryKey = self.categoryFilter:getCategory()
    local category = categoryKey and IE.getCategory(categoryKey)
    if category then self.list:setHiddenColumns(category.hiddenColumns) end
    self.list:setItems(self:createData())
    --TODO: update sort column

    self.infoBar:updateProps({
        relativePosition = v2(0, 1),
        anchor = v2(0, 1)
    })

    self:initInfoBar(ctx)

    wnd:setContent(ui.content {
        self.categoryFilter.element,
        { template = I.MWUI.templates.horizontalLine, props = { position = v2(0, topBarHeight), } },
        self.list.element,
        { template = I.MWUI.templates.horizontalLine, props = { position = v2(0, -infoHeight), relativePosition = v2(0, 1), anchor = v2(0, 1), } },
        self.infoBar.element,
    })
    self:updateTitle()
end

function Inventory:onClosed()
    self.wnd = nil
    self.arg = nil
end

function Inventory:onResized(inner)
    local infoHeight = self.infoBar:getHeight()
    local topBarHeight = self.categoryFilter:getSize().y

    self.list:setSize(inner - v2(0, topBarHeight + infoHeight + 4))
end

function Inventory:getStorageSuffix()
    if self.wnd then return self.suffix end
    return getStorageSuffix(self.type)
end

function Inventory:update()
    self.list:filter()
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

    ---@param item openmw.Object|{stacks:openmw.Object[], totalCount:number}
    ---@param isBartered boolean
    ---@param isVirtual boolean
    ---@return InventoryExtenderRedone.RowData
    local function createRowData(item, isBartered, isVirtual)
        ---@type openmw.Object
        local itemStack = isVirtual and item.stacks[1] or item --[[@as openmw.Object]]

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

        ---@type InventoryExtenderRedone.RowData
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
            isDisabled = function()
                if not isBartered and self.type == 'Inventory' and I.UI.getMode() == 'Container' then
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

---@private
function Inventory:initInfoBar(ctx)
    local theme = Toolkit.getTheme()

    --Encumbrance
    if self.type ~= 'Trade' then
        self.encumbranceBar = Components.progressBar {
            width = 100,
            color = theme.Colors.MAGICK,
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
                (types.Container.objectIsInstance(self.target) and types.Container.record(self.target).isOrganic)
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
end

return Inventory
