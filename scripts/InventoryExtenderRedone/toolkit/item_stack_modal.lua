---@omw-context player

local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')
local input = require('openmw.input')
local I = require('openmw.interfaces')

local BUTTON = input.CONTROLLER_BUTTON
local KEY = input.KEY
local v2 = util.vector2
local D = require('scripts.InventoryExtenderRedone.config.defaults')
local l10n = core.l10n(D.L10N)

local Toolkit = I.UIToolkit
local T = Toolkit.Templates
local Components = Toolkit.Components
local Popups = Toolkit.Popups

local constants = require('scripts.InventoryExtenderRedone.util.constants')

local HANDLE_SIZE = 32
local SLIDER_LENGTH = 400
local SLIDER_WIDTH = 18

local ItemStackModal = {}

---@param opts InventoryExtenderRedone.ItemStackModalOpts
---@return fun() closes the popup. Closing does not confirm the count.
function ItemStackModal.show(opts)
    local maxCount = opts.maxCount
    local onConfirm = opts.onConfirm
    assert(maxCount)
    assert(onConfirm)

    local selectedCount = opts.selectedCount or maxCount

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
        textAlignH = ui.ALIGNMENT.Center,
        onValueChanged = function(value)
            selectedCount = value
            slider:setPosition(value - 1, true)
        end,
    }
    local editHeight = edit.element.layout.props.size.y
    local textSize = Toolkit.getTheme().Sizes.textNormal

    -- the slider is a scrollbar: its position is the count minus one, so dragging and typing set the same value
    slider = Components.scrollBar {
        horizontal = true,
        length = SLIDER_LENGTH,
        maxScroll = math.max(0, maxCount - 1),
        handleSize = HANDLE_SIZE,
        width = SLIDER_WIDTH,
        scrollStep = 1,
        onScroll = function(position)
            selectedCount = position + 1
            edit:setValue(selectedCount)
        end,
    }
    -- the scrollbar starts at zero, but the count starts at maxCount
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
                    size = v2(SLIDER_LENGTH, editHeight),
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    {
                        name = 'itemName',
                        template = T.text(),
                        props = {
                            text = opts.itemName or '',
                            size = v2(0, textSize),
                            autoSize = false,
                        },
                        external = { grow = 1 },
                    },
                    edit.element,
                },
            },
            T.intervalV(8),
            slider.element,
        },
    }

    local closePopup
    local function onButton(button)
        if button == BUTTON.Y then
            closePopup()
        elseif button == BUTTON.X then
            onConfirm(selectedCount)
            closePopup()
        elseif button == BUTTON.LeftShoulder then
            if selectedCount <= 1 then return end
            slider:setPosition(selectedCount - 2) --slider's position needs to be 1 lower that selected count
        elseif button == BUTTON.RightShoulder then
            if selectedCount >= maxCount then return end
            slider:setPosition(selectedCount) --slider's position needs to be 1 lower that selected count
        end
    end
    local function onKey(key)
        if key == KEY.R then
            closePopup()
        elseif key == KEY.E then
            onConfirm(selectedCount)
            closePopup()
        elseif key == KEY.A then
            if selectedCount <= 1 then return end
            slider:setPosition(selectedCount - 2) --slider's position needs to be 1 lower that selected count
        elseif key == KEY.D then
            if selectedCount >= maxCount then return end
            slider:setPosition(selectedCount) --slider's position needs to be 1 lower that selected count
        end
    end

    closePopup = Popups.show {
        title = constants.Strings.TAKE,
        body = body,
        buttons = {
            {
                text = constants.Strings.OK,
                onClicked = function()
                    onConfirm(selectedCount)
                end,
            },
            { text = constants.Strings.CANCEL },
        },
        onControllerButtonPress = onButton,
        onControllerButtonRepeat = onButton,
        onKeyboardButtonPress = onKey,
        onKeyboardButtonRepeat = onKey,
        controllerHints = {
            { text = constants.Strings.OK,     input = { id = BUTTON.X } },
            { text = constants.Strings.CANCEL, input = { id = BUTTON.Y } },
            { text = l10n 'Hint_Count',        input = { { id = BUTTON.LeftShoulder }, { id = BUTTON.RightShoulder } } },
        },
    }

    return closePopup
end

return ItemStackModal
