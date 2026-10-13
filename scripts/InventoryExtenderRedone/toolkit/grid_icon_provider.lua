---@omw-context player|menu

local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local v2 = util.vector2
local Class = require('scripts.UIToolkit.class')
local GridItemBase = require('scripts.UIToolkit.components.grid_item_provider')
local Component = require('scripts.UIToolkit.components.component')
local H = require('scripts.UIToolkit.helpers')

local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local configPlayer = require('scripts.InventoryExtenderRedone.config.player')
local iconPack = require('scripts.InventoryExtenderRedone.util.iconPack')
local constants = require('scripts.InventoryExtenderRedone.util.constants')
local Toolkit = I.UIToolkit


local SZ = 42
local INNER_SZ = SZ - 4
local ICON_SZ = SZ - 10

---@class InventoryExtenderRedone.GridIcon: UIToolkit.GridItem.Base
---@field new fun(self:InventoryExtenderRedone.GridIcon):InventoryExtenderRedone.GridIcon
---@field getBadges fun(row:InventoryExtenderRedone.RowData):table
local GridIcon = Class(GridItemBase)

function GridIcon:getItemSize()
    if not self.size then
        self.size = v2(1, 1) * util.round(SZ * configPlayer.window.n_GridIconScale)
    end
    return self.size
end

---@param data InventoryExtenderRedone.RowData
---@return UIToolkit.Component
function GridIcon:makeComponent(data)
    local sz = self:getItemSize()
    local component = Component:new()
    local innerSz = v2(1, 1) * util.round(INNER_SZ * configPlayer.window.n_GridIconScale)
    local iconSz = v2(1, 1) * util.round(ICON_SZ * configPlayer.window.n_GridIconScale)
    local base = GridIcon.renderIcon(data, sz, iconSz, innerSz, data.showAsEnchanted(), true)

    local badges = self:getBadgeLayouts(data)
    base.content:add {
        name = 'badges',
        type = ui.TYPE.Widget,
        props = {
            position = v2(1, 1) * math.floor(configPlayer.window.n_GridIconScale * (SZ - INNER_SZ) / 2),
            size = innerSz,
        },
        content = ui.content(badges),
    }

    local count = data.getCount()
    base.content:add({
        name = 'count',
        type = ui.TYPE.Text,
        template = Toolkit.Templates.header(),
        props = {
            text = helpers.getCountString(count),
            anchor = util.vector2(1, 1),
            relativePosition = util.vector2(1, 1),
            position = innerSz - sz,
            textShadow = true,
            visible = count and count > 1
        }
    })

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

function GridIcon:markAllDirty()
    for id, cached in pairs(self.cache) do
        if cached:isDestroyed() then
            self.cache[id] = nil
        else
            cached.dirty = true
        end
    end
end

function GridIcon:markDirty(idOrData)
    local id = type(idOrData) == 'string' and idOrData or idOrData.id
    local cached = self.cache[id]
    if not cached then return end
    if cached:isDestroyed() then
        self.cache[id] = nil
    else
        cached.dirty = true
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

    local badges = content['badges']
    local layouts, tmp = self:getBadgeLayouts(data, badges.content)
    if tmp then
        changed = tmp
        badges.content = ui.content(layouts)
    end

    local count = data.getCount()
    local text = helpers.getCountString(count)
    local visible = count and count > 1
    props = H.props(content['count'])
    if props.text ~= text or props.visible ~= visible then
        changed = true
        props.text = text
        props.visible = visible
    end

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

---@param name string
---@param path string
---@param color openmw.util.Color
---@param idx integer
---@param n integer
local function makeBadge(name, path, color, idx, n)
    local r = 1 / n
    local y = math.floor(idx / n)
    local x = idx - n * y
    return {
        name = name,
        type = ui.TYPE.Image,
        props = {
            resource = Toolkit.texture(path),
            relativePosition = v2(x, y) * r,
            relativeSize = v2(r, r),
            color = color,
        },
    }
end

---@param data InventoryExtenderRedone.RowData
---@param existing openmw.ui.Content?
---@return openmw.ui.Layout[] badges, boolean changed
function GridIcon:getBadgeLayouts(data, existing)
    local badges = self.getBadges(data)
    local layouts = {}
    local changed = not existing
    local n = 3

    local was = {}
    if existing then
        for i = 1, #existing do
            was[existing[i].name] = true
        end
    end

    if badges.favorite then
        layouts[#layouts + 1] = makeBadge('favorite', iconPack.getPath('item/favorited.dds'), constants.Colors.GOLD,
            #layouts, n)
        if not was['favorite'] then changed = true end
        was['favorite'] = nil
    end

    if badges.stolen then
        layouts[#layouts + 1] = makeBadge('stolen', iconPack.getPath('item/stolen.dds'), constants.Colors.DAMAGED,
            #layouts, n)
        if not was['stolen'] then changed = true end
        was['stolen'] = nil
    end

    if not changed and next(was) then
        changed = true
    end

    return layouts, changed
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

---@param data InventoryExtenderRedone.RowData
---@param outerSize openmw.util.Vector2
---@param iconSize openmw.util.Vector2
---@param bgSize openmw.util.Vector2
---@param showEnchantSwirl boolean
---@param shadow boolean?
---@return openmw.ui.Layout
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
