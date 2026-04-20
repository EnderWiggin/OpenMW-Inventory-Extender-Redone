local core = require('openmw.core')
local ui = require('openmw.ui')
local storage = require('openmw.storage')
local omwself = require('openmw.self')
local util = require('openmw.util')
local v2 = util.vector2
local I = require('openmw.interfaces')
local async = require('openmw.async')
local types = require('openmw.types')
local ambient = require('openmw.ambient')
local input = require('openmw.input')

local baseTemplates = require('scripts.InventoryExtender.ui.templates.base')
local specialTemplates = require('scripts.InventoryExtender.ui.templates.magic')
local CategoryFilter = require('scripts.InventoryExtender.ui.templates.categoryFilter')
local ItemTable = require('scripts.InventoryExtender.ui.templates.itemTable')
local InfoBar = require('scripts.InventoryExtender.ui.templates.infoBar')
local ItemStackModal = require('scripts.InventoryExtender.ui.templates.itemStackModal')
local Window = require('scripts.InventoryExtender.ui.windows.base')

local configPlayer = require('scripts.InventoryExtender.config.player')
local helpers = require('scripts.InventoryExtender.util.helpers')
local constants = require('scripts.InventoryExtender.util.constants')
local barterUtils = require('scripts.InventoryExtender.util.barter')
local persistentCorpses = require('scripts.InventoryExtender.util.persistentCorpses')

local l10n = core.l10n('InventoryExtender')

local Inventory = Window:new()

function Inventory:update(deep)
    if self.updateSize then
        self:updateSize()
    end
    self:setTitle()
    self:setPinnable()
    Window.update(self, deep)
end

function Inventory:create(windowType, ctx)
    local self = setmetatable({}, {__index = Inventory})
    self.ctx = ctx

    self.type = windowType
    if self.type == 'Inventory' then
        self.target = omwself
    end

    local content = ui.content {}
    local data = self:createData()

    local w = 60 * baseTemplates.TEXT_SIZE / 16

    local function onRowActivate(row, rowWidget)
        if I.UI.getMode() ~= 'Interface' then
            return
        end

        self.itemTable.layout.userData.getState().lastUsedRowPos = rowWidget.layout.props.position - v2(0, (ctx.focusedScrollable and ctx.focusedScrollable.layout.userData.getScrollPos() or 0))

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
                    self.target:sendEvent('MI_Update')
                    break
                end
            end
        else
            core.sendGlobalEvent('UseItem', { object = row.item, actor = self.target })
        end
    end

    local iconRenderer = function(row, width, height)
        local iconDim = math.min(width, height)
        local equipped = helpers.isItemEquipped(row.item, self.target, ctx.overrides.equipped)
        local bgrVisible = row.isBartered or equipped
        local magicString = row.itemRecord.enchant and '_magic' or ''
        local postString = (row.isBartered and '_barter') or (equipped and '_equip') or (magicString ~= '' and '') or '_none'
        local bgrPath = 'textures/menu_icon' .. magicString .. postString .. '.dds'
        return {
            props = {
                size = v2(width, height),
            },
            content = ui.content {
                {
                    name = 'itemBackground',
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { 
                            path = bgrPath,
                            size = v2(40, 40),
                            offset = bgrPath == 'textures/menu_icon_barter.dds' and v2(4, 4) or v2(2, 2),
                        },
                        anchor = v2(0.5, 0.5),
                        relativePosition = v2(0.5, 0.5),
                        size = v2(iconDim, iconDim),
                        visible = bgrVisible,
                    }
                },
                {
                    name = 'itemIcon',
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { path = row.itemRecord.icon },
                        anchor = v2(0.5, 0.5),
                        relativePosition = v2(0.5, 0.5),
                        size = v2(iconDim, iconDim),
                    }
                },
            },
            userData = {
                bgrVisible = bgrVisible,
                bgrPath = bgrPath,
            }
        }
    end

    local function getNonDraggedCount(row)
        local nonDraggedCount = row.getCount()
        if self.ctx.dragAndDrop.draggingObject and self.ctx.dragAndDrop.draggingObject.id == row.item.id then
            nonDraggedCount = nonDraggedCount - self.ctx.dragAndDrop.draggingCount
        end

        if I.UI.getMode() == 'Barter' then
            if row.isBartered then
                if self.type == 'Inventory' then
                    nonDraggedCount = (self.ctx.barterState.buying[row.item.id] or {}).count or 0
                else
                    nonDraggedCount = (self.ctx.barterState.selling[row.item.id] or {}).count or 0
                end
            else
                if self.type == 'Inventory' then
                    nonDraggedCount = nonDraggedCount - ((self.ctx.barterState.selling[row.item.id] or {}).count or 0)
                elseif self.type == 'Trade' then
                    nonDraggedCount = nonDraggedCount - ((self.ctx.barterState.buying[row.item.id] or {}).count or 0)
                end
            end
        end

        return nonDraggedCount
    end

    self.itemTable = ItemTable.create({
        columns = {
            {
                id = 'Icon',
                width = specialTemplates.LINE_HEIGHT * 1.5 + 8,
                renderer = iconRenderer,
            },
            {
                id = 'Name',
                label = l10n('Column_Name'),
                renderer = function(row, width, height)
                    local nonDraggedCount = getNonDraggedCount(row)

                    local text = helpers.getItemName(row.item) .. (nonDraggedCount > 1 and (' (%d)'):format(nonDraggedCount) or '')

                    local stolen = false
                    local enchanted = false
                    if self.type == 'Inventory' and self.ctx.stolenItems then
                        stolen = self.ctx.stolenItems[row.item.recordId] ~= nil
                    end
                    if row.itemRecord.enchant then
                        enchanted = true
                    end

                    local content = ui.content {
                        {
                            template = baseTemplates.textNormal,
                            props = {
                                text = text,
                            },
                            userData = {
                                colorable = true,
                            }
                        },
                    }
                    local iconSize = math.min(specialTemplates.LINE_HEIGHT, 12)
                    if stolen then
                        content:add(baseTemplates.intervalH(8))
                        content:add({
                            type = ui.TYPE.Image,
                            props = {
                                resource = ui.texture { path = 'icons/InventoryExtender/item/stolen.dds' },
                                size = v2(iconSize, iconSize),
                                color = constants.Colors.DAMAGED,
                            },
                        })
                    end
                    if enchanted then
                        content:add(baseTemplates.intervalH(8))
                        content:add({
                            type = ui.TYPE.Image,
                            props = {
                                resource = ui.texture { path = 'icons/InventoryExtender/item/enchanted.dds' },
                                size = v2(iconSize, iconSize),
                                color = constants.Colors.BAR_MAGIC,
                            },
                        })
                    end

                    return {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                            arrange = ui.ALIGNMENT.Center,
                            autoSize = false,
                            size = v2(width, height),
                        },
                        content = content,
                        userData = {
                            text = text,
                            stolen = stolen,
                            enchanted = enchanted,
                        }
                    }
                end,
            },
            {
                id = 'Weight',
                label = l10n('Column_Weight'),
                width = w,
                textAlignH = ui.ALIGNMENT.End,
                defaultOrder = 'desc',
            },
            {
                id = 'Value',
                label = l10n('Column_Value'),
                width = w,
                textAlignH = ui.ALIGNMENT.End,
                defaultOrder = 'desc',
            },
            {
                id = 'V/W',
                label = l10n('Column_VW'),
                width = w,
                textAlignH = ui.ALIGNMENT.End,
                defaultOrder = 'desc',
            }
        },
        data = data,
        size = v2(600, 400),
        rowHeight = specialTemplates.LINE_HEIGHT * configPlayer.window.f_TableRowHeightMult,
        defaultSortId = 'Icon',
        defaultSortIcon = 'icons/InventoryExtender/default_sort.dds',
        fallbackSort = function(a, b, sortDir)
            if not self.target then
                return false
            end

            if a.isBartered ~= b.isBartered then
                return a.isBartered
            end

            local aEquipped = helpers.isItemEquipped(a.item, self.target, ctx.overrides.equipped)
            local bEquipped = helpers.isItemEquipped(b.item, self.target, ctx.overrides.equipped)
            if aEquipped ~= bEquipped then
                return aEquipped -- equipped items come first (true > false)
            end
            
            -- Second, sort by Category
            local categories = I.InventoryExtender.getCategories()
            local indexA, indexB = nil, nil
            for i, category in ipairs(categories) do
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
            if indexA ~= indexB then
                if sortDir == 'asc' then
                    return (indexA or math.huge) < (indexB or math.huge)
                else
                    return (indexA or math.huge) > (indexB or math.huge)
                end
            end

            local nameA = (type(a.Name) == "function" and a.Name() or a.Name):lower()
            local nameB = (type(b.Name) == "function" and b.Name() or b.Name):lower()
            if nameA == nameB then
                if a.item.recordId == b.item.recordId then
                    return a.item.id < b.item.id
                end
                return a.item.recordId < b.item.recordId
            end
            return nameA < nameB
        end,
        onRowClick = function(row, rowWidget)
            for i = #ctx.handlers.onRowClick, 1, -1 do
                local handler = ctx.handlers.onRowClick[i]
                if handler.handler(row, ctx) == false then
                    return false
                end
            end

            if ctx.dragAndDrop.draggingObject then
                return true
            end

            if helpers.isBoundItem(row.item) then
                return
            end

            if not rowWidget then
                return
            end

            self.itemTable.layout.userData.getState().lastUsedRowPos = rowWidget.layout.props.position - v2(0, (ctx.focusedScrollable and ctx.focusedScrollable.layout.userData.getScrollPos() or 0))

            local transfer = input.isAltPressed() or I.UI.getMode() == 'Barter'
            local takeAll = input.isShiftPressed() or input.getAxisValue(input.CONTROLLER_AXIS.TriggerRight) > 0.5
            local takeOne = input.isCtrlPressed() or input.getAxisValue(input.CONTROLLER_AXIS.TriggerLeft) > 0.5

            if takeAll and takeOne then
                onRowActivate(row, rowWidget)
                return
            end

            local itemCount = row.getCount()
            if I.UI.getMode() == 'Barter' then
                if row.isBartered then
                    if self.type == 'Inventory' then
                        itemCount = (self.ctx.barterState.buying[row.item.id] or {}).count or 0
                    else
                        itemCount = (self.ctx.barterState.selling[row.item.id] or {}).count or 0
                    end
                else
                    if self.type == 'Inventory' then
                        itemCount = itemCount - ((self.ctx.barterState.selling[row.item.id] or {}).count or 0)
                    elseif self.type == 'Trade' then
                        itemCount = itemCount - ((self.ctx.barterState.buying[row.item.id] or {}).count or 0)
                    end
                end
            end

            local function doAction(count)
                if transfer then
                    local mode = I.UI.getMode()
                    if mode == 'Container' or mode == 'Companion' then
                        if self.type == 'Inventory' then
                            if ctx.windowArgs[mode] then
                                ctx.dragAndDrop:transferInto(row.item, ctx.windowArgs[mode], omwself, count)
                            end
                        else
                            ctx.dragAndDrop:transferInto(row.item, omwself, self.target, count)
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
                            table[row.item.id] = table[row.item.id] or { item = row.item, stacks = row.virtualStacks, count = 0 }
                            table[row.item.id].count = math.min(table[row.item.id].count + count, row.getCount())
                        end
                        local sound = helpers.getItemSound(row.item, 'down')
                        if sound then
                            ambient.playSound(sound)
                        end
                        barterUtils.updateOffer(ctx)
                        omwself:sendEvent('MI_Update')
                    elseif mode == 'Interface' then
                        ctx.dragAndDrop:dropAtFeet(row.item, count) 
                    end
                else
                    ctx.dragAndDrop:startDrag(row.item, self.target, count)
                end
                self:refresh()
            end

            if itemCount > 1 and not takeAll and not takeOne then
                self.itemTable.layout.userData.getState().lastUsedRowPos = nil
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
        end,
        onRowActivate = onRowActivate,
        viewMode = configPlayer.window.s_ItemViewMode,
        gridItemRenderer = function(row, itemSize)
            local base = iconRenderer(row, itemSize, itemSize)

            base.content.itemIcon.props.size = v2(itemSize - 8, itemSize - 8)
            base.content.itemBackground.props.visible = true

            local count = getNonDraggedCount(row)
            if count and count > 1 then
                base.content:add({
                    type = ui.TYPE.Text,
                    template = baseTemplates.textNormal,
                    props = {
                        text = tostring(count),
                        textSize = 12,
                        anchor = util.vector2(1, 1),
                        relativePosition = util.vector2(1, 1),
                        textColor = constants.Colors.DEFAULT_LIGHT,
                        textShadow = true,
                    }
                })
            end
            base.userData.count = count
            base.userData.bgrVisible = true
            return base
        end,
        parentWindow = self,
    }, ctx)

    self.categoryFilter = CategoryFilter.create({
        maxHeight = 72,
    }, function(selectedCategory)
        local categories = I.InventoryExtender.getCategories()
        local category = nil
        for _, cat in ipairs(categories) do
            if cat.key == selectedCategory then
                category = cat
                break
            end
        end

        self.itemTable.layout.userData.setFilter('categoryFilter', function(row)
            if not category or not category.filter then
                return true
            end
            return category.filter(row.item)
        end)

        self.itemTable.layout.userData.getState().lastUsedRowPos = nil

        self.itemTable.layout.userData.resetScroll()
        self:refresh()
    end, 
    function(searchText)
        self.itemTable.layout.userData.setFilter('searchFilter', function(row)
            if not searchText or searchText == '' then
                return true
            end
            local name = helpers.getItemName(row.item):lower()
            local searchLower = searchText:lower()
            return name:find(searchLower, 1, true) ~= nil
        end)

        self:refresh()
    end, ctx)

    content:add(self.categoryFilter)

    self.categoryFilterDivider = {
        template = I.MWUI.templates.horizontalLine,
        props = {
            size = v2(0, 2),
            relativeSize = v2(1, 0),
            position = v2(0, self.categoryFilter.layout.props.size.y),
        }
    }
    content:add(self.categoryFilterDivider)

    self.updateSize = function(self)
        if self.element then
            if self.categoryFilter then
                self.categoryFilter.layout.userData.resizeImages(self.element.layout.userData.getInnerSize().x)
            end

            local categoryFilterSize = v2(0, self.categoryFilter and self.categoryFilter.layout.props.size.y or 0)
            local infoBarSize = v2(0, self.infoBar and self.infoBar.layout.props.size.y or 0)
            self.itemTable.layout.props.position = categoryFilterSize
            self.itemTable.layout.userData.resize(self.element.layout.userData.getInnerSize() - categoryFilterSize - infoBarSize)
            if self.infoBar then
                self.infoBar.layout.props.position = categoryFilterSize + v2(0, self.itemTable.layout.props.size.y + 1)
                self.infoBar:update()
            end
            if self.infoBarDivider then
                self.infoBarDivider.props.position = v2(0, self.itemTable.layout.props.size.y + self.itemTable.layout.props.position.y)
            end
            if self.categoryFilterDivider then
                self.categoryFilterDivider.props.position = v2(0, self.categoryFilter.layout.props.size.y)
            end
        end
    end

    content:add(self.itemTable)

    self.infoBar = InfoBar.create({
        maxHeight = specialTemplates.LINE_HEIGHT + 12,
    }, ctx)
    if self.type ~= 'Trade' then
        self.infoBar.layout.userData.addInfoLayout({}, function(layout)
            if not self.target then return {} end
            if self.type == 'Container' and types.Container.objectIsInstance(self.target) and types.Container.record(self.target).isOrganic then return {} end
            layout = {
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
                            resource = ui.texture { path = 'icons/weight.dds'},
                            size = v2(16, 16),
                        }
                    },
                    baseTemplates.intervalH(4),
                    specialTemplates.progressBar{
                        size = v2(100, specialTemplates.LINE_HEIGHT + 4),
                        color = constants.Colors.BAR_MAGIC,
                        value = self.target.type.getEncumbrance(self.target),
                        maxValue = self.target.type.getCapacity(self.target),
                    }
                }
            }
            return layout
        end)
    end
    if self.type == 'Inventory' or self.type == 'Trade' then
        self.infoBar.layout.userData.addInfoLayout({}, function(layout)
            if not self.target then return {} end
            local goldAmount
            if self.type == 'Inventory' then
                goldAmount = self.target.type.inventory(self.target):countOf('gold_001')
            else
                goldAmount = self.target.type.getBarterGold(self.target)
            end
            layout = {
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
                            resource = ui.texture { path = 'icons/gold.dds'},
                            size = v2(16, 16),
                        }
                    },
                    baseTemplates.intervalH(4),
                    {
                        template = baseTemplates.textNormal,
                        props = {
                            text = tostring(goldAmount),
                        }
                    }
                }
            }
            return layout
        end) 
    end
    if self.type == 'Inventory' then
        self.infoBar.layout.userData.addInfoLayout({}, function(layout)
            if not self.target then return {} end
            layout = {
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
                            resource = ui.texture { path = 'icons/a/a_cuirass_ebon.dds'},
                            size = v2(16, 16),
                        }
                    },
                    baseTemplates.intervalH(4),
                    {
                        template = baseTemplates.textNormal,
                        props = {
                            text = tostring(math.floor(I.Combat.getArmorRating(self.target))),
                        }
                    }
                }
            }
            return layout
        end)
    end

    if self.type == 'Container' or self.type == 'Companion' then
        self.infoBar.layout.userData.addInfoLayout({ external = { grow = 1, stretch = 1 }})

        if self.type == 'Container' then
            self.infoBar.layout.userData.addInfoLayout(specialTemplates.interactive({
                onClick = function()
                    if I.UI.getMode() == 'Container' and ctx.windowArgs.Container then
                        ctx.dragAndDrop:moveAll(self.target, omwself)
                        
                        if persistentCorpses[self.target.recordId] then
                            ui.showMessage(constants.Strings.DISPOSE_CORPSE_FAIL)
                        else
                            core.sendGlobalEvent('MI_DisposeOfCorpse', { target = ctx.windowArgs.Container })
                        end
                        I.UI.removeMode('Container')
                    end
                end,
                parent = self.infoBar,
            }, baseTemplates.button(constants.Strings.DISPOSE_OF_CORPSE), ctx), function(layout)
                local visible = false
                if ctx.windowArgs.Container then
                    visible = types.Actor.objectIsInstance(ctx.windowArgs.Container) and types.Actor.isDead(ctx.windowArgs.Container)
                end
                layout.props.visible = visible
                return layout
            end)

            self.infoBar.layout.userData.addInfoLayout(specialTemplates.interactive({
                onClick = function()
                    if I.UI.getMode() == 'Container' and ctx.windowArgs.Container then
                        ctx.dragAndDrop:moveAll(self.target, omwself)
                        I.UI.removeMode('Container')
                    end
                end,
                parent = self.infoBar,
            }, baseTemplates.button(constants.Strings.TAKE_ALL), ctx))
        end

        if self.type == 'Companion' then
            self.infoBar.layout.userData.addInfoLayout({
                template = baseTemplates.textNormal,
                props = {},
            }, function(layout)
                if self.target == nil then return layout end
                local profit = ctx.companionProfit[self.target.id]
                layout.props.text = profit and (constants.Strings.PROFIT_VALUE .. ': ' .. tostring(profit)) or ''
                return layout
            end)
        end
        
        self.infoBar.layout.userData.addInfoLayout(specialTemplates.interactive({
            onClick = function()
                I.UI.removeMode(self.type)
            end,
            parent = self.infoBar,
        }, baseTemplates.button(constants.Strings.CLOSE), ctx))

        self.infoBar.layout.userData.addInfoLayout({})
    end

    if self.type == 'Trade' then
        self.infoBar.layout.userData.addInfoLayout({
            name = 'barterControls',
            type = ui.TYPE.Flex,
            external = {
                grow = 1,
                stretch = 1,
            },
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
                align = ui.ALIGNMENT.End,
                autoSize = false,
            },
            content = ui.content {
                { external = { grow = 1, stretch = 1 } },
                {
                    name = 'totalBalanceLabel',
                    template = baseTemplates.textNormal,
                    props = {
                        text = l10n('UI_Barter_Gain'),
                    },
                },
                baseTemplates.intervalH(8),
                specialTemplates.interactive({
                    onClick = function()
                        if ctx.barterState.totalBalance == 0 then
                            ctx.barterState.currentBalance = 0
                        end
                        if ctx.barterState.currentBalance < 0 then
                            ctx.barterState.currentBalance = ctx.barterState.currentBalance + 1
                        else
                            ctx.barterState.currentBalance = ctx.barterState.currentBalance - 1
                        end
                        self.infoBar.layout.userData.updateAll()
                    end,
                    --parent = self.infoBar,
                }, baseTemplates.button('-'), ctx),
                baseTemplates.intervalH(4),
                {
                    name = 'totalBalanceBox',
                    template = I.MWUI.templates.box,
                    content = ui.content {
                        {
                            template = I.MWUI.templates.padding,
                            content = ui.content {
                                {
                                    name = 'totalBalanceEdit',
                                    template = baseTemplates.textEditLine,
                                    props = {
                                        size = v2(80, specialTemplates.LINE_HEIGHT),
                                        text = tostring(ctx.barterState.currentBalance),
                                    },
                                    events = {
                                        textChanged = async:callback(function(text, layout)
                                            layout.props.text = text
                                            local num = tonumber(text)
                                            if num then
                                                local previousBalance = ctx.barterState.currentBalance

                                                ctx.barterState.currentBalance = (previousBalance >= 0 and 1 or -1) * math.floor(num)
                                                if ctx.barterState.currentBalance == 0 then
                                                    --ctx.barterState.currentBalance = previousBalance
                                                end

                                                local changed = num ~= math.abs(num)
                                                layout.props.text = tostring(math.abs(num))
                                                if changed then
                                                    self.infoBar.layout.userData.updateAll() 
                                                end
                                            end
                                        end),
                                    },
                                }
                            }
                        }
                    }
                },
                baseTemplates.intervalH(4),
                specialTemplates.interactive({
                    onClick = function()
                        if ctx.barterState.totalBalance == 0 then
                            ctx.barterState.currentBalance = 0
                        end
                        if ctx.barterState.currentBalance < 0 then
                            ctx.barterState.currentBalance = ctx.barterState.currentBalance - 1
                        else
                            ctx.barterState.currentBalance = ctx.barterState.currentBalance + 1
                        end
                        self.infoBar.layout.userData.updateAll()
                    end,
                    --parent = self.infoBar,
                }, baseTemplates.button('+'), ctx),
                baseTemplates.intervalH(4),
                specialTemplates.interactive({
                    onClick = function()
                        ctx.barterState.currentBalance = types.Actor.getBarterGold(self.target)
                        self.infoBar.layout.userData.updateAll()
                    end,
                    --parent = self.infoBar,
                }, baseTemplates.button(l10n('UI_Barter_Max')), ctx),
                { external = { grow = 1, stretch = 1 } },
                specialTemplates.interactive({
                    onClick = function()
                        if ctx.barterState.totalBalance == 0 then
                            ctx.barterState.currentBalance = 0
                        end

                        if not next(ctx.barterState.selling) and not next(ctx.barterState.buying) then
                            ui.showMessage(constants.Strings.BARTER_NO_ITEMS)
                            return
                        end

                        local playerGold = omwself.type.inventory(omwself):countOf('gold_001')
                        if ctx.barterState.currentBalance < 0 and playerGold < math.abs(ctx.barterState.currentBalance) then
                            ui.showMessage(constants.Strings.BARTER_PC_TOO_POOR)
                            return
                        end

                        if ctx.barterState.currentBalance > 0 then
                            local merchantGold = self.target.type.getBarterGold(self.target)
                            if merchantGold < ctx.barterState.currentBalance then
                                ui.showMessage(constants.Strings.BARTER_NPC_TOO_POOR)
                                return
                            end
                        end

                        for _, entry in pairs(ctx.barterState.selling) do
                            if ctx.stolenItems[entry.item.recordId] and ctx.stolenItems[entry.item.recordId][self.target.recordId] then
                                I.UI.setMode(nil)
                                ui.showMessage(string.format(constants.Strings.THATS_MINE, entry.item.type.record(entry.item).name))
                                core.sendGlobalEvent('MI_ConfiscateToOwner', {
                                    item = entry.item,
                                    count = entry.count,
                                    player = omwself,
                                    victim = self.target,
                                    stolenMap = ctx.stolenItems,
                                })
                                return
                            end
                        end

                        local offerAccepted, skillGain = barterUtils.haggle(self.target, ctx.barterState.currentBalance, ctx.barterState.currentMerchantOffer)
                        if types.NPC.objectIsInstance(self.target) then
                            local dispositionDelta = offerAccepted and core.getGMST('iBarterSuccessDisposition') or core.getGMST('iBarterFailDisposition')
                            core.sendGlobalEvent('MI_ModDisposition', {
                                target = self.target,
                                player = omwself,
                                amount = dispositionDelta,
                            })
                        end

                        if not offerAccepted then
                            ui.showMessage(constants.Strings.BARTER_REFUSED)
                            return
                        end

                        core.sendGlobalEvent('MI_FinalizeBarter', {
                            player = omwself,
                            merchant = self.target,
                            barterState = ctx.barterState,
                            skillGain = skillGain,
                        })

                        ambient.playSound('item gold up')
                        ctx.barterState.success = true
                        I.UI.removeMode('Barter')
                    end,
                    parent = self.infoBar,
                }, baseTemplates.button(constants.Strings.OFFER), ctx),
                baseTemplates.intervalH(8),
                specialTemplates.interactive({
                    onClick = function()
                        I.UI.removeMode('Barter')
                    end,
                    parent = self.infoBar,
                }, baseTemplates.button(constants.Strings.CANCEL), ctx),
            }
        }, function(layout)
            if not next(ctx.barterState.selling) and not next(ctx.barterState.buying) then
                ctx.barterState.currentBalance = 0
            end

            if ctx.barterState.currentBalance < 0 then
                layout.content.totalBalanceLabel.props.text = l10n('UI_Barter_Spend')
            else
                layout.content.totalBalanceLabel.props.text = l10n('UI_Barter_Gain')
            end

            layout.content.totalBalanceBox.content[1].content.totalBalanceEdit.props.text = tostring(math.abs(ctx.barterState.currentBalance))
            return layout
        end)
        self.infoBar.layout.userData.addInfoLayout({})
    end

    self.infoBar.layout.userData.updateAll()

    content:add(self.infoBar)
    self.infoBarDivider = {
        template = I.MWUI.templates.horizontalLine,
        props = {
            size = v2(0, 2),
            relativeSize = v2(1, 0),
        },
    }
    content:add(self.infoBarDivider)

    local pinned
    if self.type == 'Inventory' then
        pinned = storage.playerSection('Settings/InventoryExtender/2_WindowOptions'):get('b_InventoryWindowPinned')
    end

    local element = baseTemplates.window(
        helpers.getEquippedName(omwself), 
        content, 
        true, 
        function(layout)
            self:updateSize()
        end,
        pinned,
        ctx)
    self.element = element
    self:loadState()
    self:updateSize()

    self.itemTable.layout.events.mouseRelease = async:callback(function(e)
        if e.button == 1 then
            if ctx.dragAndDrop.draggingObject then
                ctx.dragAndDrop:stopDrag(self.target)
            end
        end
    end)

    self.itemTable.layout.userData.setFilter('draggedItemFilter', function(row)
        if ctx.dragAndDrop.draggingObject then
            return row.item.id ~= ctx.dragAndDrop.draggingObject.id or row.getCount() > ctx.dragAndDrop.draggingCount
        end
        return true
    end)

    self.itemTable.layout.userData.setFilter('barterFilter', function(row)
        if I.UI.getMode() == 'Barter' then
            if helpers.isGold(row.item) then
                return false
            end
            
            if row.item.type.record(row.item).isKey then
                return false
            end

            local barterNpc = self.ctx.windowArgs.Trade
            if not barterNpc then
                return false
            end
            local services = barterNpc.type.record(barterNpc).servicesOffered

            local canTrade = true
            if services.MagicItems and row.itemRecord.enchant then
                canTrade = true
            else
                for t, serviceName in pairs(constants.TypeToService) do
                    if types[t].objectIsInstance(row.item) then
                        if not services[serviceName] then
                            return false
                        end
                        break
                    end
                end 
            end
        
            if self.type == 'Inventory' then
                if row.isBartered then
                    return self.ctx.barterState.buying[row.item.id] and self.ctx.barterState.buying[row.item.id].count > 0
                end

                local sellingCount = self.ctx.barterState.selling[row.item.id] and self.ctx.barterState.selling[row.item.id].count or 0
                return row.getCount() > sellingCount
            elseif self.type == 'Trade' then
                if self.target.type.hasEquipped(self.target, row.item) then
                    return false
                end

                if row.isBartered then
                    return self.ctx.barterState.selling[row.item.id] and self.ctx.barterState.selling[row.item.id].count > 0
                end

                local buyingCount = self.ctx.barterState.buying[row.item.id] and self.ctx.barterState.buying[row.item.id].count or 0
                return row.getCount() > buyingCount
            end
        else
            return not row.isBartered
        end
    end)

    self:setPinnable()
    if self:isPinnable() and self:isPinned() then
        self:setVisible(true)
    else
        self:setVisible(false)
    end

    return self
end

function Inventory:onControllerButtonPress(id)
    if id == input.CONTROLLER_BUTTON.LeftShoulder then
        if self.categoryFilter then
            self.categoryFilter.layout.userData.cycleCategory(-1)
            return
        end
    elseif id == input.CONTROLLER_BUTTON.RightShoulder then
        if self.categoryFilter then
            self.categoryFilter.layout.userData.cycleCategory(1)
            return
        end
    elseif id == input.CONTROLLER_BUTTON.A then
        if self.ctx.focusedInteractive and self.ctx.focusedInteractive.layout and self.ctx.focusedInteractive.layout.userData.onRowActivate then
            self.ctx.focusedInteractive.layout.userData.onRowActivate()
            return
        end
    elseif id == input.CONTROLLER_BUTTON.Y then
        if self.ctx.dragAndDrop.draggingObject then
            self.ctx.dragAndDrop:stopDrag(self.target)
            return
        end
        if self.ctx.focusedInteractive and self.ctx.focusedInteractive.layout and self.ctx.focusedInteractive.layout.userData.onRowClick then
            self.ctx.focusedInteractive.layout.userData.onRowClick()
            return
        end
    end
end

function Inventory:refresh()
    if not self.itemTable then return end
    self.itemTable.layout.userData.refresh()
end

function Inventory:createData()
    if not self.target then
        return {}
    end
    
    local function createRowData(item, isBartered, isVirtual)
        local itemStack = isVirtual and item.stacks[1] or item

        if not types.Item.isCarriable(itemStack) then return nil end

        local record = itemStack.type.record(itemStack)
        local value = helpers.getItemValue(itemStack)
        local vw = record.weight > 0 and (value / record.weight) or 0
        local vwPrecision = vw > 10 and 0 or 1
        
        local rowData = {
            id = itemStack.id,
            Name = helpers.getItemName(itemStack),
            Value = helpers.roundToPlaces(value, 1),
            Weight = helpers.roundToPlaces(record.weight, 2),
            ['V/W'] = helpers.roundToPlaces(vw, vwPrecision),
            item = itemStack,
            itemRecord = record,
            isBartered = isBartered,
            virtualStacks = isVirtual and item.stacks or nil,
            getCount = function()
                if isVirtual then
                    return item.totalCount
                else
                    return itemStack.count
                end
            end,
            disabledFn = function()
                if not isBartered and I.UI.getMode() == 'Container' and self.type == 'Inventory' then
                    if self.ctx.windowArgs.Container and types.Container.objectIsInstance(self.ctx.windowArgs.Container) and types.Container.record(self.ctx.windowArgs.Container).isOrganic then
                        return true
                    end
                    return not helpers.doesItemFit(itemStack, self.ctx.windowArgs.Container, 1)
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
            local barterNpc = self.ctx.windowArgs.Trade
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

function Inventory:updateData()
    if not self.target then return end
    self:setTitle()
    self:setPinnable()
    if self.infoBar then
        self.infoBar.layout.userData.updateAll()
    end

    local anyChanges = false
    if I.UI.getMode() == 'Barter' or self.ctx.lastUiMode == 'Barter' then
        anyChanges = true
    end

    if not self.trackedCounts then
        self.trackedCounts = {}
        anyChanges = true
    end
    local currentItems = self.target.type.inventory(self.target):getAll()

    if not self.itemTable then return end

    local currentItemIds = {}
    for _, item in ipairs(currentItems) do
        currentItemIds[item.id] = true
        if self.trackedCounts[item.id] ~= item.count then
            anyChanges = true
        end
        self.trackedCounts[item.id] = item.count
    end
    
    if not anyChanges then
        for id, _ in pairs(self.trackedCounts) do
            if not currentItemIds[id] then
                anyChanges = true
                self.trackedCounts[id] = nil
            end
        end
    end

    if not anyChanges then
        self.itemTable.layout.userData.refresh()
        return
    end

    local data = self:createData()
    self.itemTable.layout.userData.updateData(data)
end

function Inventory:setTitle()
    if self.type == 'Inventory' then
        self.element.layout.userData.setTitle(helpers.getEquippedName(omwself))
    elseif self.target then
        self.element.layout.userData.setTitle(self.target.type.record(self.target).name)
    end
end

function Inventory:setPinnable()
    if not self.element then return end

    local mode = I.UI.getMode()
    if self.type == 'Inventory' and (not mode or mode == 'Interface') then
        self.element.layout.userData.setPinnable(true)
    else
        self.element.layout.userData.setPinnable(false)
    end
end

function Inventory:setVisible(visible)
    if self.categoryFilter then
        self.categoryFilter.layout.userData.clearSearch()
        self.categoryFilter.layout.userData.updateCategories()
    end
    Window.setVisible(self, visible)
end

function Inventory:updateTarget()
    local oldTarget = self.target
    if self.type == 'Inventory' then
        self.target = omwself
    else
        local windowArgs = self.ctx.windowArgs
        if windowArgs and windowArgs[self.type] then
            self.target = windowArgs[self.type]
        else
            self.target = nil
        end
    end

    if oldTarget ~= self.target then
        self.trackedCounts = nil
    end

    if self.itemTable then
        self.itemTable.layout.userData.getState().lastUsedRowPos = nil
    end

    self:updateData()
end

function Inventory:getDimensionsKey()
    if self.type == 'Trade' then
        return 'd_BarterWindowDimensions'
    elseif self.type == 'Container' then
        return 'd_ContainerWindowDimensions'
    elseif self.type == 'Companion' then
        return 'd_CompanionWindowDimensions'
    else
        if I.UI.getMode() == 'Barter' then
            return 'd_InventoryBarterWindowDimensions'
        elseif I.UI.getMode() == 'Container' then
            return 'd_InventoryContainerWindowDimensions'
        elseif I.UI.getMode() == 'Companion' then
            return 'd_InventoryCompanionWindowDimensions'
        else
            return 'd_InventoryWindowDimensions'
        end
    end
end

function Inventory:saveState()
    if not self.element then return end

    local dims = self:getDimensions()
    if not dims then return end

    storage.playerSection('Settings/InventoryExtender/2_WindowOptions'):set(self.stateKey, dims)
    if self.type == 'Inventory' and self:isPinnable() then
        storage.playerSection('Settings/InventoryExtender/2_WindowOptions'):set('b_InventoryWindowPinned', self.element.layout.userData.pinned)
    end
end

function Inventory:loadState()
    if not self.element then return end

    if self.itemTable then
        self.itemTable.layout.userData.setViewMode(configPlayer.window.s_ItemViewMode)
    end

    self.stateKey = self:getDimensionsKey()
    local dims = storage.playerSection('Settings/InventoryExtender/2_WindowOptions'):get(self.stateKey)
    if not dims then return end

    self:setDimensions(dims)
end

return Inventory