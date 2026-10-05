---@omw-context player|menu

local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local v2 = util.vector2
local Class = require('scripts.UIToolkit.class')
local GridItemBase = require('scripts.UIToolkit.components.grid_item_provider')
local Component = require('scripts.UIToolkit.components.component')

local helpers = require('scripts.InventoryExtender.util.helpers')
local configPlayer = require('scripts.InventoryExtender.config.player')
local Toolkit = I.UIToolkit


---@class InventoryExtenderRedone.GridIcon: UIToolkit.GridItem.Base
---@field new fun(self:InventoryExtenderRedone.GridIcon):InventoryExtenderRedone.GridIcon
local GridIcon = Class(GridItemBase)

function GridIcon:getItemSize()
    if not self.size then
        self.size = v2(40, 40) * configPlayer.window.n_GridIconScale
    end
    return self.size
end

---@param data InventoryExtenderRedone.RowData
---@return UIToolkit.Component
function GridIcon:makeComponent(data)
    local sz = self:getItemSize()
    local component = Component:new()
    local base = GridIcon.renderIcon(data, sz, sz - v2(8, 8), sz, data.showAsEnchanted())

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
                textShadow = true,
            }
        })
    end

    component:init(ui.create(base))
    return component
end

---@param data UIToolkit.ListData.Text
---@return UTKTooltips.AnyTooltip?
function GridIcon:getTooltip(data)
    return data.tooltip
end

function GridIcon.renderIcon(data, outerSize, iconSize, bgSize, showEnchantSwirl)
    local ctx = I.InventoryExtender.getContext()

    local equipped = helpers.isItemEquipped(data.item, data.item.parentContainer, ctx.overrides.equipped)
    local bgrVisible = data.isBartered or equipped or showEnchantSwirl
    local magicString = showEnchantSwirl and '_magic' or ''
    local postString = (data.isBartered and '_barter') or (equipped and '_equip') or (magicString ~= '' and '') or
        '_none'
    local bgrPath = 'textures/menu_icon' .. magicString .. postString .. '.dds'
    return {
        name = 'Icon',
        props = {
            size = outerSize,
        },
        content = ui.content {
            {
                name = 'itemBackground',
                type = ui.TYPE.Image,
                props = {
                    resource = Toolkit.texture(bgrPath, v2(40, 40), bgrPath == 'textures/menu_icon_barter.dds' and v2(4, 4) or v2(2, 2)),
                    anchor = v2(0.5, 0.5),
                    relativePosition = v2(0.5, 0.5),
                    size = bgSize,
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
                    size = iconSize,
                }
            },
        },
        userData = {
            bgrVisible = bgrVisible,
            bgrPath = bgrPath,
        }
    }
end

return GridIcon
