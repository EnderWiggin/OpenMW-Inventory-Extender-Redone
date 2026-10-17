---@omw-context player

local I    = require 'openmw.interfaces'
local util = require 'openmw.util'
local v2   = util.vector2


return {
    eventHandlers = {
        IER_Window_Opened = function(data)
            local CF = I.CraftingFramework
            if not CF or not CF.openCraftingWindow then return end
            if data.type ~= 'Inventory' or data.mode ~= 'Interface' then return end

            local handler = assert(I.UIToolkit.WindowManager.getHandler(data.id)) --[[@as  IER.Inventory]]
            local sz = handler.infoBar:getHeight()

            ---@type UIToolkit.ImageButton?
            local btn = I.UIToolkit.Components.imageButton {
                name = 'open_cf',
                style = 'empty',
                icon = 'icons/m/misc_hammer10.dds',
                size = v2(1, 1) * sz,
                onClick = function()
                    I.InventoryExtenderRedone.hide(data.type)
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
