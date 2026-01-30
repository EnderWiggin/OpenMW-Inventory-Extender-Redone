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

local baseTemplates = require('scripts.ModernInventory.ui.templates.base')
local specialTemplates = require('scripts.ModernInventory.ui.templates.magic')
local CategoryFilter = require('scripts.ModernInventory.ui.templates.categoryFilter')
local ItemTable = require('scripts.ModernInventory.ui.templates.itemTable')
local InfoBar = require('scripts.ModernInventory.ui.templates.infoBar')
local Window = require('scripts.ModernInventory.ui.windows.base')

local helpers = require('scripts.ModernInventory.util.helpers')
local constants = require('scripts.ModernInventory.util.constants')

local l10n = core.l10n('ModernInventory')

local Inventory = Window:new()

function Inventory:update(deep)
    if self.updateSize then
        self:updateSize()
    end
    self:setTitle()
    self:setPinnable()
    Window.update(self, deep)
end

function Inventory:create(type, ctx)
    local self = setmetatable({}, {__index = Inventory})
    self.ctx = ctx

    self.type = type
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
                    return {
                        props = {
                            size = v2(width, height),
                        },
                        content = ui.content {
                            {
                                name = 'itemIcon',
                                type = ui.TYPE.Image,
                                props = {
                                    resource = ui.texture { path = row.itemRecord.icon },
                                    position = v2((width - iconDim) / 2, (height - iconDim) / 2),
                                    size = v2(iconDim, iconDim),
                                }
                            },
                            {
                                name = 'equippedOverlay',
                                type = ui.TYPE.Image,
                                props = {
                                    resource = ui.texture { 
                                        path = 'textures/menu_icon_equip.dds',
                                        size = v2(40, 40),
                                        offset = v2(2, 2),
                                    },
                                    position = v2((width - iconDim) / 2, (height - iconDim) / 2),
                                    size = v2(iconDim, iconDim),
                                    visible = self.target.type.hasEquipped and self.target.type.hasEquipped(self.target, row.item) or false,
                                }
                            }
                        }
                    }
                end
            },
            {
                id = 'Name',
                label = l10n('Column_Name'),
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
        defaultSortIcon = 'icons/ModernInventory/default_sort.dds',
        fallbackSort = function(a, b, sortDir)
            if not self.target then
                return false
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
            local categories = I.ModernInventory.getCategories()
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

            local nameA = a.Name:lower()
            local nameB = b.Name:lower()
            if nameA == nameB then
                return a.item.recordId < b.item.recordId
            end
            return nameA < nameB
        end,
        onRowClick = function(row)
            if ctx.dragAndDrop.draggingObject then
                return true
            end

            if input.isAltPressed() then
                if ctx.uiMode == 'Container' then
                    if self.type == 'Inventory' and ctx.modeArgs.Container then
                        ctx.dragAndDrop:transferInto(row.item, ctx.modeArgs.Container)
                    elseif self.type == 'Container' then
                        ctx.dragAndDrop:transferInto(row.item, omwself)
                    end
                end
            else
                ctx.dragAndDrop:startDrag(row.item, self.target)
            end
            self:refresh()
        end,
        onRowActivate = function(row)
            if self.ctx.uiMode ~= 'Interface' then
                return
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
                        self.target:sendEvent('MI_Update')
                        break
                    end
                end
            else
                core.sendGlobalEvent('UseItem', { object = row.item, actor = self.target })
            end
        end,
    }, ctx)

    if self.type == 'Inventory' then
        self.categoryFilter = CategoryFilter.create({
            maxHeight = 48,
        }, function(selectedCategory)
            local categories = I.ModernInventory.getCategories()
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
            self.itemTable.layout.userData.resetScroll()
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
    end

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
                self.infoBar.layout.props.position = categoryFilterSize + v2(0, self.itemTable.layout.props.size.y)
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
    if self.type ~= 'Barter' then
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
    if self.type == 'Inventory' then
        self.infoBar.layout.userData.addInfoLayout({}, function(layout)
            if not self.target then return {} end
            local goldAmount = self.target.type.inventory(self.target):countOf('gold_001')
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
        pinned = storage.playerSection('Settings/ModernInventory/2_WindowOptions'):get('b_InventoryWindowPinned')
    end

    local element = baseTemplates.window(
        helpers.getEquippedName(), 
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
            return row.item.id ~= ctx.dragAndDrop.draggingObject.id
        end
        return true
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
    local data = {}
    for _, item in ipairs(self.target.type.inventory(self.target):getAll()) do
        local record = item.type.record(item)
        local vw = record.weight > 0 and (record.value / record.weight) or 0
        local vwPrecision = vw > 10 and 0 or 1
        vw = helpers.roundToPlaces(vw, vwPrecision)
        
        table.insert(data, {
            id = item.id,
            Name = record.name .. (item.count > 1 and (' (%d)'):format(item.count) or ''),
            Value = helpers.roundToPlaces(record.value, 1),
            Weight = helpers.roundToPlaces(record.weight, 2),
            ['V/W'] = vw,
            item = item,
            itemRecord = record,
            disabledFn = function()
                if self.ctx.uiMode == 'Container' and self.type == 'Inventory' then
                    if not helpers.doesItemFit(item, self.ctx.modeArgs.Container) then
                        return true
                    end
                end
                return false
            end,
        })
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
        self.element.layout.userData.setTitle(helpers.getEquippedName())
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
    end

    if oldTarget ~= self.target then
        self.trackedCounts = nil
    end
    self:updateData()
end

function Inventory:getDimensionsKey()
    if self.type == 'Barter' then
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

    storage.playerSection('Settings/ModernInventory/2_WindowOptions'):set(self:getDimensionsKey(), dims)
    if self.type == 'Inventory' and self.ctx.uiMode == 'Interface' then
        storage.playerSection('Settings/ModernInventory/2_WindowOptions'):set('b_InventoryWindowPinned', self.element.layout.userData.pinned)
    end
end

function Inventory:loadState()
    if not self.element then return end

    local dims = storage.playerSection('Settings/ModernInventory/2_WindowOptions'):get(self:getDimensionsKey())
    if not dims then return end

    self:setDimensions(dims)
end

return Inventory