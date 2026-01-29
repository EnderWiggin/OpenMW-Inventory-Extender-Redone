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

local baseTemplates = require('scripts.ModernInventory.ui.templates.base')
local specialTemplates = require('scripts.ModernInventory.ui.templates.magic')
local CategoryFilter = require('scripts.ModernInventory.ui.templates.categoryFilter')
local ItemTable = require('scripts.ModernInventory.ui.templates.itemTable')
local Window = require('scripts.ModernInventory.ui.windows.base')

local helpers = require('scripts.ModernInventory.util.helpers')

local l10n = core.l10n('ModernInventory')

local Inventory = Window:new()

local function createData()
    local data = {}
    for _, item in ipairs(omwself.type.inventory(omwself):getAll()) do
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
        })
    end
    return data
end

function Inventory:update(deep)
    self:updateData()
    Window.update(self, deep)
end

function Inventory:create(ctx)
    local self = setmetatable({}, {__index = Inventory})
    self.ctx = ctx

    local content = ui.content {}
    local data = createData()

    local w = 80 * baseTemplates.TEXT_SIZE / 16

    local itemTable = ItemTable.create({
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
                                type = ui.TYPE.Image,
                                props = {
                                    resource = ui.texture { path = row.itemRecord.icon },
                                    position = v2((width - iconDim) / 2, (height - iconDim) / 2),
                                    size = v2(iconDim, iconDim),
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
            -- First, check if items are equipped
            local aEquipped = omwself.type.hasEquipped(omwself, a.item)
            local bEquipped = omwself.type.hasEquipped(omwself, b.item)
            if aEquipped ~= bEquipped then
                return aEquipped -- equipped items come first (true > false)
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
            return nameA < nameB
        end,
        onRowClick = function(row)
            if ctx.dragAndDrop.draggingObject then
                return true
            end

            ctx.dragAndDrop:startDrag(row.item, omwself.type.inventory(omwself))
            self:refresh()
        end,
        onRowActivate = function(row)
            if omwself.type.hasEquipped(omwself, row.item) then
                local equipment = omwself.type.getEquipment(omwself)
                for slot, equippedItem in pairs(equipment) do
                    if equippedItem == row.item then
                        equipment[slot] = nil
                        omwself.type.setEquipment(omwself, equipment)
                        local sound = helpers.getItemSound(row.item, 'down')
                        if sound then
                            ambient.playSound(sound)
                        end
                        omwself:sendEvent('MI_Update')
                        break
                    end
                end
            else
                core.sendGlobalEvent('UseItem', { object = row.item, actor = omwself })
            end
        end,
    }, ctx)

    local categoryFilter = CategoryFilter.create({
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

        itemTable.layout.userData.setFilter('categoryFilter', function(row)
            if not category or not category.filter then
                return true
            end
            return category.filter(row.item)
        end)
        itemTable.layout.userData.resetScroll()
        itemTable.layout.userData.refresh()
    end, ctx)

    content:add(categoryFilter)

    content:add({
        template = I.MWUI.templates.horizontalLine,
        props = {
            size = v2(0, 2),
            relativeSize = v2(1, 0),
            position = v2(0, categoryFilter.layout.props.size.y),
        },
    })

    itemTable.layout.props.position = v2(0, categoryFilter.layout.props.size.y)
    content:add(itemTable)
    local element = baseTemplates.window(
        helpers.getEquippedName(), 
        content, 
        true, 
        function(layout)
            itemTable.layout.userData.resize(layout.userData.getInnerSize() - v2(0, categoryFilter.layout.props.size.y))
        end,
        storage.playerSection('Settings/ModernInventory/2_WindowOptions'):get('b_InventoryWindowPinned'),
        ctx)
    self.element = element
    self:loadState()
    itemTable.layout.userData.resize(self.element.layout.userData.getInnerSize() - v2(0, categoryFilter.layout.props.size.y))

    itemTable.layout.events.mouseRelease = async:callback(function(e)
        if e.button == 1 then
            if ctx.dragAndDrop.draggingObject then
                ctx.dragAndDrop:stopDrag()
                self:refresh()
                omwself:sendEvent('MI_Update')
            end
        end
    end)

    itemTable.layout.userData.setFilter('draggedItemFilter', function(row)
        if ctx.dragAndDrop.draggingObject then
            return row.item.id ~= ctx.dragAndDrop.draggingObject.id
        end
        return true
    end)

    return self
end

function Inventory:refresh()
    local itemTable = helpers.findInLayout(self.element, function(layout) return layout.name == 'itemTable' end)
    if not itemTable then return end
    itemTable.userData.refresh()
end

local trackedCounts = {}

function Inventory:updateData()
    local anyChanges = false
    local currentItems = omwself.type.inventory(omwself):getAll()

    local itemTable = helpers.findInLayout(self.element, function(layout) return layout.name == 'itemTable' end)
    if not itemTable then return end
    
    local currentItemIds = {}
    for _, item in ipairs(currentItems) do
        currentItemIds[item.id] = true
        if trackedCounts[item.id] ~= item.count then
            anyChanges = true
        end
        trackedCounts[item.id] = item.count
    end
    
    if not anyChanges then
        for id, _ in pairs(trackedCounts) do
            if not currentItemIds[id] then
                anyChanges = true
                trackedCounts[id] = nil
            end
        end
    end

    if not anyChanges then
        itemTable.userData.refresh()
        return
    end

    local data = createData()
    itemTable.userData.updateData(data)
end

function Inventory:saveState()
    if not self.element then return end

    local dims = self:getDimensions()
    if not dims then return end

    storage.playerSection('Settings/ModernInventory/2_WindowOptions'):set('d_InventoryWindowDimensions', dims)
    storage.playerSection('Settings/ModernInventory/2_WindowOptions'):set('b_InventoryWindowPinned', self.element.layout.userData.pinned)
end

function Inventory:loadState()
    if not self.element then return end

    local dims = storage.playerSection('Settings/ModernInventory/2_WindowOptions'):get('d_InventoryWindowDimensions')
    if not dims then return end

    self:setDimensions(dims)
end

return Inventory