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

local IER = I.InventoryExtenderRedone

-- The Crafting Framework button is a patch on the Interface mode's info bar, not an event
-- listener: create builds the button once per open, the returned provider hides it while
-- dragging, cleanup destroys it when the bar is destroyed. Slots are keyed per window role,
-- so the patch names the Inventory role's infoBar; patchMode merges the section by id into
-- that role's strip in order.
local btn
IER.patchMode(IER.Modes.Interface, {
    roles = {
        Inventory = {
            infoBar = { add = { {
                id = 'ier_cf',
                create = function(handler, ctx)
                    local sz = handler.infoBar:getHeight()
                    btn = I.UIToolkit.Components.imageButton {
                        name = 'open_cf',
                        style = 'empty',
                        icon = 'icons/m/misc_hammer10.dds',
                        size = v2(1, 1) * sz,
                        onClick = function()
                            IER.hide(IER.Roles.Inventory)
                            CF.openCraftingWindow()
                        end,
                        colorable = false,
                        highlight = true,
                        tooltip = 'Crafting', --TODO: add L10N
                    }
                    return function()
                        if not btn then return nil end
                        if IER.getDraggingObject() then return nil end
                        return btn.element
                    end
                end,
                cleanup = function()
                    if not btn then return end
                    I.UIToolkit.queueDestroy(btn.element)
                    btn = nil
                end,
            } } },
        },
    },
})

return {}
