---@omw-context player

local I     = require 'openmw.interfaces'
local types = require 'openmw.types'
local ui    = require 'openmw.ui'
local util  = require 'openmw.util'


local toxicology = require 'scripts.ier_toxicology_interop.toxicology'
local helpers    = require 'scripts.UIToolkit.tooltips.utils'


local Weapon   = types.Weapon
local Tooltips = I.UTKTooltips
local NAME     = 'toxicology-poisons'
local ICON     = 'icons/Toxicology/poison_badge.dds'
local COLOR    = util.color.rgb(110 / 255, 148 / 255, 87 / 255)
local BUILDERS = Tooltips.builders


Tooltips.registerBuilder(NAME, function(item)
    local layers = item.layers --[[@as {name:string, charges:number}[] ]]
    local innerContent = ui.content {}

    innerContent:add(BUILDERS.value { value = 'Poison coatings:', image = ICON, name = 'title' })

    local layerContent = ui.content {}
    for i = 1, #layers do
        local layer = layers[i]
        layerContent:add(BUILDERS.default { text = layer.name, value = layer.charges, color = COLOR })
    end

    innerContent:add {
        name = 'coatings',
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
            align = ui.ALIGNMENT.Center,
            arrange = ui.ALIGNMENT.End,
        },
        external = {
            stretch = 1,
        },
        content = layerContent
    }

    return {
        name = NAME,
        type = ui.TYPE.Flex,
        props = {
            align = ui.ALIGNMENT.Center,
            arrange = ui.ALIGNMENT.Center,
        },
        content = innerContent,
    }
end)

Tooltips.addPreCreateTooltipHandler(function(recipe, tooltip)
    local object = tooltip.object
    if not object then return end

    local data = toxicology.getActivePoisons(object)
    if not data or not Weapon.objectIsInstance(object) then return end

    local items = recipe.items
    local found, index = helpers.findByName(items, Tooltips.CONTENT.Footer)
    if not found then index = #items + 1 else index = index - 1 end

    table.insert(items, index, { type = NAME, layers = data })
    table.insert(items, index, { type = 'gap', size = 4 })
end)

return {
    engineHandlers = {},
}
