local ui = require('openmw.ui')
local storage = require('openmw.storage')
local this = require('openmw.self')

local baseTemplates = require('scripts.ModernInventory.ui.templates.base')
local ItemTable = require('scripts.ModernInventory.ui.templates.itemTable')
local Window = require('scripts.ModernInventory.ui.windows.base')

local helpers = require('scripts.ModernInventory.util.helpers')

local Inventory = Window:new()

function Inventory:create(ctx)
    local self = setmetatable({}, {__index = Inventory})

    local content = ui.content {}
    local data = {}
    for _, item in ipairs(this.type.inventory(this):getAll()) do
        local record = item.type.record(item)
        table.insert(data, {
            Name = record.name,
            Value = helpers.roundToPlaces(record.value, 1),
            Weight = helpers.roundToPlaces(record.weight, 3),
            ['V/W'] = helpers.roundToPlaces((record.weight > 0) and (record.value / record.weight) or 0, 3),
        })
    end
    local itemTable = ItemTable.create({
        columns = {
            {
                id = 'Name',
            },
            {
                id = 'Value',
                width = 128,
            },
            {
                id = 'Weight',
                width = 128,
            },
            {
                id = 'V/W',
                width = 128,
            }
        },
        data = data
    })
    content:add(itemTable)
    local element = baseTemplates.window('Inventory', content, true, ctx.pinned)
    self.element = element
    self:loadState()

    return self
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