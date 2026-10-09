---@omw-context player|menu

local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local v2 = util.vector2
local Class = require('scripts.UIToolkit.class')
local GridItemBase = require('scripts.UIToolkit.components.grid_item_provider')
local Component = require('scripts.UIToolkit.components.component')
local H = require('scripts.UIToolkit.helpers')

local helpers = require('scripts.InventoryExtender.util.helpers')
local configPlayer = require('scripts.InventoryExtender.config.player')
local Toolkit = I.UIToolkit


---@class InventoryExtenderRedone.GridIcon: UIToolkit.GridItem.Base
---@field new fun(self:InventoryExtenderRedone.GridIcon):InventoryExtenderRedone.GridIcon
local GridIcon = Class(GridItemBase)

function GridIcon:getItemSize()
    if not self.size then
        self.size = v2(42, 42) * configPlayer.window.n_GridIconScale
    end
    return self.size
end

---@param data InventoryExtenderRedone.RowData
---@return UIToolkit.Component
function GridIcon:makeComponent(data)
    local sz = self:getItemSize()
    local component = Component:new()
    local innerSz = sz - v2(4, 4)
    local iconSz = sz - v2(10, 10)
    local base = GridIcon.renderIcon(data, sz, iconSz, innerSz, data.showAsEnchanted(), true)

    --TODO: add favorites badge
    --TODO: add stolen badge

    local count = data.getCount()
    if count and count > 1 then
        base.content:add({
            type = ui.TYPE.Text,
            template = Toolkit.Templates.header(),
            props = {
                text = helpers.getCountString(count),
                anchor = util.vector2(1, 1),
                relativePosition = util.vector2(1, 1),
                position = v2(-4, -4),
                textShadow = true,
            }
        })
    end

    component:init(ui.create(base))
    return component
end

---@param data InventoryExtenderRedone.RowData
---@return UIToolkit.Component
function GridIcon:getComponent(data)
    local component = GridItemBase.getComponent(self, data) --[[@as UIToolkit.ListItem.ColumnComponent]]
    if component.dirty then
        self:refreshDirty(component, data)
    end
    return component
end

function GridIcon:markDirty()
    for id, cached in pairs(self.cache) do
        if cached:isDestroyed() then
            self.cache[id] = nil
        else
            cached.dirty = true
        end
    end
end

---@param component UIToolkit.Component
---@param data InventoryExtenderRedone.RowData
function GridIcon:refreshDirty(component, data)
    local ctx = I.InventoryExtender.getContext()
    local changed = false
    local equipped = helpers.isItemEquipped(data.item, data.item.parentContainer, ctx.overrides.equipped)
    local enchanted = data.showAsEnchanted()
    local bartered = data.isBartered
    local content = component.element.layout.content --[[@as openmw.ui.Content]]

    local props = H.props(content['itemIcon'])
    local tex = Toolkit.texture(data.itemRecord.icon)
    if props.resource ~= tex then
        changed = true
        props.resource = tex
        props = H.props(content['itemShadow'])
        props.resource = tex
    end

    props = H.props(content['itemBackground'])
    tex = GridIcon.getBackgroundTexture(bartered, equipped, enchanted)
    if props.resource ~= tex then
        changed = true
        props.resource = tex
    end

    --TODO: update count
    --TODO: update favorite
    --TODO: update stolen

    if changed then
        Toolkit.queueUpdate(component.element)
    end
end

function GridIcon:clear()
    GridItemBase.clear(self)
end

---@param data UIToolkit.ListData.Text
---@return UTKTooltips.AnyTooltip?
function GridIcon:getTooltip(data)
    return data.tooltip
end

local BGR_SZ = v2(40, 40)
local BGR_OFFSET = v2(2, 2)
local BGR_OFFSET_BARTER = v2(4, 4)

---@param bartered boolean
---@param equipped boolean
---@param enchanted boolean
---@return openmw.ui.TextureResource
function GridIcon.getBackgroundTexture(bartered, equipped, enchanted)
    local magic = enchanted and '_magic' or ''
    local suffix = '_none'
    if bartered then
        suffix = '_barter'
    elseif equipped then
        suffix = '_equip'
    elseif enchanted then
        suffix = ''
    end

    local bgrPath = string.format('textures/menu_icon%s%s.dds', magic, suffix)
    local offset = bgrPath == 'textures/menu_icon_barter.dds' and BGR_OFFSET_BARTER or BGR_OFFSET
    return Toolkit.texture(bgrPath, BGR_SZ, offset)
end

function GridIcon.renderIcon(data, outerSize, iconSize, bgSize, showEnchantSwirl, shadow)
    local ctx = I.InventoryExtender.getContext()

    local equipped = helpers.isItemEquipped(data.item, data.item.parentContainer, ctx.overrides.equipped)
    local content = ui.content {
        {
            name = 'itemBackground',
            type = ui.TYPE.Image,
            props = {
                resource = GridIcon.getBackgroundTexture(data.isBartered, equipped, showEnchantSwirl),
                anchor = v2(0.5, 0.5),
                relativePosition = v2(0.5, 0.5),
                size = bgSize,
            }
        },
        {
            name = 'itemIcon',
            type = ui.TYPE.Image,
            props = {
                resource = Toolkit.texture(data.itemRecord.icon),
                anchor = v2(0.5, 0.5),
                relativePosition = v2(0.5, 0.5),
                size = iconSize,
            }
        },
    }
    if shadow then
        content:insert(2, {
            name = 'itemShadow',
            type = ui.TYPE.Image,
            props = {
                resource = Toolkit.texture(data.itemRecord.icon),
                anchor = v2(0.5, 0.5),
                relativePosition = v2(0.5, 0.5),
                position = v2(4, 4),
                size = iconSize,
                color = util.color.rgb(0, 0, 0),
                alpha = 0.5,
            }
        })
    end
    return {
        name = 'Icon',
        props = {
            size = outerSize,
        },
        content = content,
    }
end

---@return openmw.ui.Element?
function GridIcon:getHighlightView()
    if not self.highlight then
        self.highlight = ui.create {
            name = 'item-highlight',
            type = ui.TYPE.Image,
            props = {
                resource = Toolkit.texture('textures/omw_menu_icon_active.dds'),
                size = self:getItemSize(),
            },
        }
    end
    return self.highlight
end

return GridIcon
