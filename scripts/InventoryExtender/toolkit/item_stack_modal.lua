---@omw-context player

local ui = require('openmw.ui')
local util = require('openmw.util')
local input = require('openmw.input')
local I = require('openmw.interfaces')

local BUTTON = input.CONTROLLER_BUTTON

local Toolkit = I.UIToolkit
local T = Toolkit.Templates
local Components = Toolkit.Components
local Popups = Toolkit.Popups

local constants = require('scripts.InventoryExtender.util.constants')

local SLIDER_LENGTH = 360

local ItemStackModal = {}

---@param params InventoryExtenderRedone.ItemStackModalOpts
---@return fun() closes the popup. Closing does not confirm the count.
function ItemStackModal.show(params)
    local maxCount = params.maxCount or 1
    local onConfirm = params.onConfirm or function(count) end

    local selectedCount = params.selectedCount or maxCount

    local function validate(text)
        local number = tonumber(text)
        if not number then return false end
        return true, util.clamp(util.round(number), 1, maxCount)
    end

    local edit, slider

    edit = Components.textEdit {
        width = 100,
        default = selectedCount,
        validate = validate,
        onValueChanged = function(value)
            selectedCount = value
            slider:setPosition(value - 1, true)
        end,
    }

    -- the slider is a scrollbar: its position is the count minus one, so dragging and typing set the same value
    slider = Components.scrollBar {
        horizontal = true,
        length = SLIDER_LENGTH,
        maxScroll = math.max(0, maxCount - 1),
        handleSize = 32,
        width = 20,
        scrollStep = 1,
        onScroll = function(position)
            edit:setValue(position + 1)
            selectedCount = position + 1
        end,
    }
    -- the scrollbar starts at zero, but the count starts at maxCount: park the handle where it agrees
    slider:setPosition(selectedCount - 1, true)

    local body = {
        type = ui.TYPE.Flex,
        props = {
            align = ui.ALIGNMENT.Center,
        },
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    {
                        name = 'itemName',
                        template = T.text(),
                        props = {
                            text = params.itemName or '',
                        },
                    },
                    T.intervalH(8),
                    edit.element,
                },
            },
            T.intervalV(8),
            slider.element,
        },
    }

    local closePopup

    closePopup = Popups.show {
        title = constants.Strings.TAKE,
        body = body,
        buttons = {
            {
                text = constants.Strings.OK,
                -- the popup adds an Interface UI mode while it is open in interface mode,
                -- so the take action must run after the popup closed the mode back down
                noClose = true,
                onClicked = function()
                    closePopup()
                    onConfirm(selectedCount)
                end,
            },
            { text = constants.Strings.CANCEL },
        },
        onControllerButtonPress = function(button)
            if button == BUTTON.Y then
                closePopup()
            end
        end,
    }

    return closePopup
end

return ItemStackModal
