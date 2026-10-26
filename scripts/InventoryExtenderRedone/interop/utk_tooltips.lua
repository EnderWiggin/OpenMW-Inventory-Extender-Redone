---@omw-context player

local core      = require 'openmw.core'
local types     = require 'openmw.types'
local ui        = require 'openmw.ui'
local I         = require 'openmw.interfaces'

local helpers   = require 'scripts.UIToolkit.tooltips.utils'
local D         = require('scripts.InventoryExtenderRedone.config.defaults')
local l10n      = core.l10n(D.L10N)
local Interface = I.UTKTooltips
local Toolkit   = I.UIToolkit
local T         = Toolkit.Templates
local cfgPlayer = require 'scripts.InventoryExtenderRedone.config.player'
local constants = require 'scripts.InventoryExtenderRedone.util.constants'
local NPC       = types.NPC


-- Stolen-info tooltip section
local function stolenInfoCompare(a, b)
    local ra = a.record
    local rb = b.record

    if ra.ranks and not rb.ranks then return false end
    if rb.ranks and not ra.ranks then return true end

    if ra.name ~= rb.name then return ra.name < rb.name end

    return ra.id < rb.id
end

Interface.registerBuilder('ie-stolen-info', function(item)
    local stolenRecords = item.records
    local innerContent = ui.content {}

    innerContent:add {
        name = 'stolen',
        template = T.text(),
        props = {
            text = l10n('StolenTooltipText'),
            textColor = constants.Colors.RED_DESAT,
        },
    }
    local stolenContent = ui.content {}
    for i = 1, #stolenRecords do
        local r = stolenRecords[i].record
        local c = stolenRecords[i].count
        stolenContent:add {
            name = r.id,
            template = T.text(),
            props = {
                text = r.name .. ': ' .. c,
                textColor = r.ranks
                    and constants.Colors.ACTIVE
                    or constants.Colors.DISABLED,
            },
        }
    end

    innerContent:add {
        name = 'stolen',
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
            align = ui.ALIGNMENT.Center,
            arrange = ui.ALIGNMENT.End,
        },
        external = {
            stretch = 1,
        },
        content = stolenContent
    }

    return {
        name = 'ie-stolen-info',
        type = ui.TYPE.Flex,
        props = {
            align = ui.ALIGNMENT.Center,
            arrange = ui.ALIGNMENT.Center,
        },
        content = innerContent,
    }
end)

Interface.addPreCreateTooltipHandler(function(recipe, tooltip)
    if not cfgPlayer.tweaks.b_ShowStolenInfo then return end
    local item = tooltip.object
    if not item then return end

    local ctx = I.InventoryExtenderRedone.getContext()

    local stolen = ctx.stolenItems[item.recordId]
    if not stolen then return end

    local stolenRecords = {}
    for victim, count in pairs(stolen) do
        local record = NPC.records[victim]
        if not record then
            record = core.factions.records[victim]
        end
        if record then
            stolenRecords[#stolenRecords + 1] = { record = record, count = count }
        end
    end
    if #stolenRecords <= 0 then return end

    table.sort(stolenRecords, stolenInfoCompare)

    local found, index = helpers.findByName(recipe.items, Interface.CONTENT.Footer)
    if not found then index = #recipe.items + 1 else index = index - 1 end

    table.insert(recipe.items, index, { type = 'ie-stolen-info', records = stolenRecords })
    table.insert(recipe.items, index, { type = 'gap', size = 4 })
end)

Interface.addPreCreateTooltipHandler(function(recipe, tooltip)
    if not tooltip['markEquipped'] then return end
    local items = recipe.items

    items[#items + 1] = { type = 'gap', size = 4 }
    items[#items + 1] = { type = 'text', text = l10n 'UI_Tooltip_Equipped', color = constants.Colors.GRAY }
end)
