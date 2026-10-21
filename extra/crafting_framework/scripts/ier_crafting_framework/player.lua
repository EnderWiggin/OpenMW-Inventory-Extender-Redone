---@omw-context player

local core = require 'openmw.core'
local I    = require 'openmw.interfaces'
local util = require 'openmw.util'
local v2   = util.vector2
local l10n = core.l10n 'ier_crafting_framework'

local CF = I.CraftingFramework
if not CF or not CF.getItemQuality or not CF.openCraftingWindow then return end

local Tooltips = I.UTKTooltips
local helpers  = require 'scripts.UIToolkit.tooltips.utils'

Tooltips.addPreCreateTooltipHandler(function(recipe, tooltip)
    local id = tooltip.object and tooltip.object.recordId or tooltip.key
    if not id then return end
    local quality = CF.getItemQuality(id)
    if not quality or quality == 1 then return end

    local items = recipe.items
    local found, index = helpers.findByName(items, Tooltips.CONTENT.Condition)
    if not found then
        found, index = helpers.findByName(items, Tooltips.CONTENT.Footer)
        if not found then
            index = #items + 1
        end
    else
        index = index + 1
    end

    table.insert(items, index,
        { text = string.format(l10n('Quality'), util.round(100 * quality)), name = 'CFQuality' })
end)

return {
    eventHandlers = {
        IER_Window_Opened = function(data)
            if data.role ~= 'Inventory' or data.mode ~= 'Interface' then return end

            local handler = assert(I.UIToolkit.WindowManager.getHandler(data.id)) --[[@as  IER.Inventory]]
            local sz = handler.infoBar:getHeight()

            ---@type UIToolkit.ImageButton?
            local btn = I.UIToolkit.Components.imageButton {
                name = 'open_cf',
                style = 'empty',
                icon = 'icons/m/misc_hammer10.dds',
                size = v2(1, 1) * sz,
                onClick = function()
                    I.InventoryExtenderRedone.hide(data.role)
                    CF.openCraftingWindow()
                end,
                colorable = false,
                highlight = true,
                tooltip = 'Crafting', --TODO: add L10N
            }

            handler.infoBar:addProvider(
                function()
                    if not btn then return nil end
                    if I.InventoryExtenderRedone.getDraggingObject() then return nil end
                    return btn.element
                end,
                function()
                    if not btn then return end
                    I.UIToolkit.queueDestroy(btn.element)
                    btn = nil
                end)
        end,
    },
}
