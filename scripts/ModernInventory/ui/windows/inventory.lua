local core = require('openmw.core')
local ui = require('openmw.ui')
local storage = require('openmw.storage')
local this = require('openmw.self')
local util = require('openmw.util')
local v2 = util.vector2

local baseTemplates = require('scripts.ModernInventory.ui.templates.base')
local specialTemplates = require('scripts.ModernInventory.ui.templates.magic')
local ItemTable = require('scripts.ModernInventory.ui.templates.itemTable')
local Window = require('scripts.ModernInventory.ui.windows.base')

local helpers = require('scripts.ModernInventory.util.helpers')

local l10n = core.l10n('ModernInventory')

local Inventory = Window:new()

function Inventory:create(ctx)
    local self = setmetatable({}, {__index = Inventory})

    local content = ui.content {}
    local data = {}
    for _, item in ipairs(this.type.inventory(this):getAll()) do
        local record = item.type.record(item)
        table.insert(data, {
            Name = record.name .. (item.count > 1 and (' (%d)'):format(item.count) or ''),
            Value = helpers.roundToPlaces(record.value, 1),
            Weight = helpers.roundToPlaces(record.weight, 3),
            ['V/W'] = helpers.roundToPlaces((record.weight > 0) and (record.value / record.weight) or 0, 2),
            item = item,
            itemRecord = record,
        })
    end
    local itemTable = ItemTable.create({
        columns = {
            {
                id = 'Icon',
                width = 24,
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
                width = 64,
            },
            {
                id = 'Value',
                label = l10n('Column_Value'),
                width = 64,
            },
            {
                id = 'V/W',
                label = l10n('Column_VW'),
                width = 64,
            }
        },
        data = data,
        size = v2(600, 400),
        rowHeight = specialTemplates.LINE_HEIGHT,
        defaultSortId = 'Icon',
        defaultSortIcon = 'icons/ModernInventory/default_sort.dds',
        fallbackSort = function(a, b, sortDir)
            local nameA = a.Name:lower()
            local nameB = b.Name:lower()
            if sortDir == 'asc' then
                return nameA < nameB
            else
                return nameA > nameB
            end
        end,
    })
    content:add(itemTable)
    local element = baseTemplates.window(helpers.getEquippedName(), content, true, ctx.pinned)
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