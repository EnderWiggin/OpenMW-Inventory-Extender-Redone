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

local helpers = require('scripts.InventoryExtender.util.helpers')
local constants = require('scripts.InventoryExtender.util.constants')
local base = require("scripts.InventoryExtender.ui.windows.base")

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

    self.itemTable = ItemTable.create({
        columns = {
            {
                id = 'Icon',
                width = specialTemplates.LINE_HEIGHT * 1.5 + 8,
                renderer = function(row, width, height)
                    local iconDim = math.min(width, height) -- keep square
                    local visible = row.isBartered or (self.target.type.hasEquipped and self.target.type.hasEquipped(self.target, row.item) or false)
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
                                        path = row.isBartered and 'textures/menu_icon_barter.dds' or 'textures/menu_icon_equip.dds',
                                        size = v2(40, 40),
                                        offset = row.isBartered and v2(4, 4) or v2(2, 2),
                                    },
                                    position = v2((width - iconDim) / 2, (height - iconDim) / 2),
                                    size = v2(iconDim, iconDim),
                                    visible = visible,
                                }
                            },
                            {
                                name = 'itemIcon',
                                type = ui.TYPE.Image,
                                props = {
                                    resource = ui.texture { path = row.itemRecord.icon },
                                    position = v2((width - iconDim) / 2, (height - iconDim) / 2),
                                    size = v2(iconDim, iconDim),
                                }
                            },
                        },
                        userData = {
                            bgrVisible = visible,
                        }
                    }
                end
            },
            {
                id = 'Name',
                label = l10n('Column_Name'),
                renderer = function(row, width, height)
                    local nonDraggedCount = row.item.count
                    if self.ctx.dragAndDrop.draggingObject and self.ctx.dragAndDrop.draggingObject.id == row.item.id then
                        nonDraggedCount = nonDraggedCount - self.ctx.dragAndDrop.draggingCount
                    end

                    if self.ctx.uiMode == 'Barter' then
                        if row.isBartered then
                            if self.type == 'Inventory' then
                                nonDraggedCount = self.ctx.barterItems.buying[row.item.id] or 0
                            else
                                nonDraggedCount = self.ctx.barterItems.selling[row.item.id] or 0
                            end
                        else
                            if self.type == 'Inventory' then
                                nonDraggedCount = nonDraggedCount - (self.ctx.barterItems.selling[row.item.id] or 0)
                            elseif self.type == 'Trade' then
                                nonDraggedCount = nonDraggedCount - (self.ctx.barterItems.buying[row.item.id] or 0)
                            end
                        end
                    end

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
            },
            {
                id = 'Value',
                label = l10n('Column_Value'),
                width = w,
                textAlignH = ui.ALIGNMENT.End,
            },
            {
                id = 'V/W',
                label = l10n('Column_VW'),
                width = w,
                textAlignH = ui.ALIGNMENT.End,
            }
        },
        data = data,
        size = v2(600, 400),
        rowHeight = specialTemplates.LINE_HEIGHT * 1.5,
        defaultSortId = 'Icon',
        defaultSortIcon = 'icons/InventoryExtender/default_sort.dds',
        fallbackSort = function(a, b, sortDir)
            if not self.target then
                return false
            end

            if a.isBartered ~= b.isBartered then
                return a.isBartered
            end

            -- First, check if items are equipped
            if self.target.type.hasEquipped then
                local aEquipped = self.target.type.hasEquipped(self.target, a.item)
                local bEquipped = self.target.type.hasEquipped(self.target, b.item)
                if aEquipped ~= bEquipped then
                    return aEquipped -- equipped items come first (true > false)
                end
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
                return a.item.recordId < b.item.recordId
            end
            return nameA < nameB
        end,
        onRowClick = function(row, rowWidget)
            if ctx.dragAndDrop.draggingObject then
                return true
            end

            if helpers.isBoundItem(row.item) then
                return
            end

            self.itemTable.layout.userData.getState().lastUsedRowPos = rowWidget.layout.props.position - v2(0, (ctx.focusedScrollable and ctx.focusedScrollable.layout.userData.getScrollPos() or 0))

            local transfer = input.isAltPressed() or self.ctx.uiMode == 'Barter'
            local takeAll = input.isShiftPressed()
            local takeOne = input.isCtrlPressed()

            local itemCount = row.item.count
            if self.ctx.uiMode == 'Barter' then
                if row.isBartered then
                    if self.type == 'Inventory' then
                        itemCount = self.ctx.barterItems.buying[row.item.id] or 0
                    else
                        itemCount = self.ctx.barterItems.selling[row.item.id] or 0
                    end
                else
                    if self.type == 'Inventory' then
                        itemCount = itemCount - (self.ctx.barterItems.selling[row.item.id] or 0)
                    elseif self.type == 'Trade' then
                        itemCount = itemCount - (self.ctx.barterItems.buying[row.item.id] or 0)
                    end
                end
            end

            local function doAction(count)
                if transfer then
                    if ctx.uiMode == 'Container' then
                        if self.type == 'Inventory' and ctx.modeArgs.Container then
                            ctx.dragAndDrop:transferInto(row.item, ctx.modeArgs.Container, omwself, count)
                        elseif self.type == 'Container' then
                            ctx.dragAndDrop:transferInto(row.item, omwself, self.target, count)
                        end
                    elseif ctx.uiMode == 'Barter' then
                        if row.isBartered then
                            if self.type == 'Inventory' then
                                ctx.barterItems.buying[row.item.id] = ctx.barterItems.buying[row.item.id] - count
                                if ctx.barterItems.buying[row.item.id] <= 0 then
                                    ctx.barterItems.buying[row.item.id] = nil
                                end
                            else
                                ctx.barterItems.selling[row.item.id] = ctx.barterItems.selling[row.item.id] - count
                                if ctx.barterItems.selling[row.item.id] <= 0 then
                                    ctx.barterItems.selling[row.item.id] = nil
                                end
                            end
                        else
                            if self.type == 'Inventory' then
                                ctx.barterItems.selling[row.item.id] = (ctx.barterItems.selling[row.item.id] or 0) + count 
                            else
                                ctx.barterItems.buying[row.item.id] = (ctx.barterItems.buying[row.item.id] or 0) + count
                            end
                        end
                        local sound = helpers.getItemSound(row.item, 'down')
                        if sound then
                            ambient.playSound(sound)
                        end
                        omwself:sendEvent('MI_Update')
                    elseif ctx.uiMode == 'Interface' then
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
        onRowActivate = function(row, rowWidget)
            if self.ctx.uiMode ~= 'Interface' then
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
        end,
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
        self.itemTable.layout.userData.refresh()
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

        self.itemTable.layout.userData.refresh()
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
            layout = {
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

    if self.type == 'Container' then
        self.infoBar.layout.userData.addInfoLayout({ external = { grow = 1, stretch = 1 }})

        self.infoBar.layout.userData.addInfoLayout(specialTemplates.interactive({
            onClick = function()
                if ctx.uiMode == 'Container' and ctx.modeArgs.Container then
                    ctx.dragAndDrop:moveAll(self.target, omwself)
                    core.sendGlobalEvent('MI_DisposeOfCorpse', { target = ctx.modeArgs.Container })
                    I.UI.removeMode('Container')
                end
            end,
            parent = self.infoBar,
        }, baseTemplates.button(constants.Strings.DISPOSE_OF_CORPSE), ctx), function(layout)
            local visible = false
            if ctx.modeArgs.Container then
                visible = types.Actor.objectIsInstance(ctx.modeArgs.Container) and types.Actor.isDead(ctx.modeArgs.Container)
            end
            layout.props.visible = visible
            return layout
        end)

        self.infoBar.layout.userData.addInfoLayout(specialTemplates.interactive({
            onClick = function()
                if ctx.uiMode == 'Container' and ctx.modeArgs.Container then
                    ctx.dragAndDrop:moveAll(self.target, omwself)
                    I.UI.removeMode('Container')
                end
            end,
            parent = self.infoBar,
        }, baseTemplates.button(constants.Strings.TAKE_ALL), ctx))
        
        self.infoBar.layout.userData.addInfoLayout(specialTemplates.interactive({
            onClick = function()
                I.UI.removeMode('Container')
            end,
            parent = self.infoBar,
        }, baseTemplates.button(constants.Strings.CLOSE), ctx))

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
            return row.item.id ~= ctx.dragAndDrop.draggingObject.id or row.item.count > ctx.dragAndDrop.draggingCount
        end
        return true
    end)

    self.itemTable.layout.userData.setFilter('barterFilter', function(row)
        if self.ctx.uiMode == 'Barter' then
            if helpers.isGold(row.item) then
                return false
            end

            local barterNpc = self.ctx.modeArgs.Barter
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
                    return self.ctx.barterItems.buying[row.item.id] and self.ctx.barterItems.buying[row.item.id] > 0
                end

                local sellingCount = self.ctx.barterItems.selling[row.item.id] or 0
                return row.item.count > sellingCount
            elseif self.type == 'Trade' then
                if self.target.type.hasEquipped(self.target, row.item) then
                    return false
                end

                if row.isBartered then
                    return self.ctx.barterItems.selling[row.item.id] and self.ctx.barterItems.selling[row.item.id] > 0
                end

                local buyingCount = self.ctx.barterItems.buying[row.item.id] or 0
                return row.item.count > buyingCount
            end
        else
            return not row.isBartered
        end
    end)

    return self
end

function Inventory:refresh()
    if not self.itemTable then return end
    self.itemTable.layout.userData.refresh()
end

function Inventory:createData()
    if not self.target then
        return {}
    end
    
    local function createRowData(item, isBartered)
        local record = item.type.record(item)
        local value = helpers.getItemValue(item)
        local vw = record.weight > 0 and (value / record.weight) or 0
        local vwPrecision = vw > 10 and 0 or 1
        
        local rowData = {
            id = item.id,
            Name = helpers.getItemName(item),
            Value = helpers.roundToPlaces(value, 1),
            Weight = helpers.roundToPlaces(record.weight, 2),
            ['V/W'] = helpers.roundToPlaces(vw, vwPrecision),
            item = item,
            itemRecord = record,
            isBartered = isBartered,
        }
        
        if not isBartered and self.ctx.uiMode == 'Container' and self.type == 'Inventory' then
            rowData.disabledFn = function()
                return not helpers.doesItemFit(item, self.ctx.modeArgs.Container)
            end
        end
        
        -- if isBartered then
        --     rowData.activeFn = function() return true end
        -- end
        
        return rowData
    end
    
    local data = {}
    
    -- Add primary inventory
    local thisInv = self.type == 'Trade' 
        and helpers.getMerchantItems(self.target) 
        or self.target.type.inventory(self.target):getAll()
    
    for _, item in ipairs(thisInv) do
        table.insert(data, createRowData(item, false))
    end
    
    -- Add bartered items from other inventory
    if self.ctx.uiMode == 'Barter' then
        local otherInv = self.type == 'Inventory'
            and (self.ctx.modeArgs.Barter and helpers.getMerchantItems(self.ctx.modeArgs.Barter))
            or (self.type == 'Trade' and omwself.type.inventory(omwself):getAll())
        
        if otherInv then
            for _, item in ipairs(otherInv) do
                table.insert(data, createRowData(item, true))
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
    if self.ctx.uiMode == 'Barter' then
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

    if self.type == 'Inventory' and (not self.ctx.uiMode or self.ctx.uiMode == 'Interface') then
        self.element.layout.userData.setPinnable(true)
    else
        self.element.layout.userData.setPinnable(false)
    end
end

function Inventory:setVisible(visible)
    if self.categoryFilter then
        self.categoryFilter.layout.userData.clearSearch()
    end
    Window.setVisible(self, visible)
end

function Inventory:updateTarget()
    local oldTarget = self.target
    if self.type == 'Inventory' then
        self.target = omwself
    elseif self.type == 'Container' then
        local modeArgs = self.ctx.modeArgs
        if modeArgs and modeArgs.Container then
            self.target = modeArgs.Container
        else
            self.target = nil
        end
    elseif self.type == 'Trade' then
        local modeArgs = self.ctx.modeArgs
        if modeArgs and modeArgs.Barter then
            self.target = modeArgs.Barter
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
        if self.ctx.uiMode == 'Barter' then
            return 'd_InventoryBarterWindowDimensions'
        elseif self.ctx.uiMode == 'Container' then
            return 'd_InventoryContainerWindowDimensions'
        elseif self.ctx.uiMode == 'Companion' then
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

    storage.playerSection('Settings/InventoryExtender/2_WindowOptions'):set(self:getDimensionsKey(), dims)
    if self.type == 'Inventory' and self.ctx.uiMode == 'Interface' then
        storage.playerSection('Settings/InventoryExtender/2_WindowOptions'):set('b_InventoryWindowPinned', self.element.layout.userData.pinned)
    end
end

function Inventory:loadState()
    if not self.element then return end

    local dims = storage.playerSection('Settings/InventoryExtender/2_WindowOptions'):get(self:getDimensionsKey())
    if not dims then return end

    self:setDimensions(dims)
end

return Inventory