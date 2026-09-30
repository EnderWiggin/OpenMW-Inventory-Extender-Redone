---@omw-context player
local ui        = require('openmw.ui')
local util      = require('openmw.util')
local I         = require('openmw.interfaces')
local v2        = util.vector2

local H         = require 'scripts.UIToolkit.helpers'
local C         = require 'scripts.UIToolkit.constants'
local Toolkit   = I.UIToolkit
local T         = Toolkit.Templates
local Class     = require 'scripts.UIToolkit.class'
local Component = require 'scripts.UIToolkit.components.component'



---@class InventoryExtenderRedone.InfoBarPrivate : InventoryExtenderRedone.InfoBar
---@field new fun(self:InventoryExtenderRedone.InfoBar):InventoryExtenderRedone.InfoBarPrivate
---@field providers InventoryExtenderRedone.InfoBar.Provider[]
local InfoBar = Class(Component)

---@param opts InventoryExtenderRedone.InfoBarOpts
---@return InventoryExtenderRedone.InfoBar
function InfoBar.create(opts)
    local infoBar = InfoBar:new()
    infoBar:init(opts)
    return infoBar
end

---@param opts InventoryExtenderRedone.InfoBarOpts
function InfoBar:init(opts)
    local maxHeight = opts.maxHeight or 32
    self.providers = {}
    local gap = C.API.GAP and Toolkit.getTheme().Sizes.standardGap or nil

    Component.init(self, ui.create {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            autoSize = false,
            gap = gap,
            size = v2(0, maxHeight),
            relativeSize = v2(1, 0),
            align = ui.ALIGNMENT.Start,
            arrange = ui.ALIGNMENT.Center,
        },
        content = ui.content {},
        userData = {},
    })
end

---@param provider InventoryExtenderRedone.InfoBar.Provider
function InfoBar:addProvider(provider)
    if not provider then return end
    self.providers[#self.providers + 1] = provider
    local layout = provider(I.InventoryExtender.getContext())
    if not layout then return end
    if not C.API.GAP then --TODO: remove when 0.52 is released
        self.element.layout.content:add(T.intervalH(Toolkit.getTheme().Sizes.standardGap))
    end
    self.element.layout.content:add(layout)
    Toolkit.queueUpdate(self.element)
end

---@return number
function InfoBar:getHeight()
    return self.element.layout.props.size.y
end

function InfoBar:update()
    local ctx = I.InventoryExtender.getContext()
    local content = ui.content {}
    self.element.layout.content = content
    local gap = Toolkit.getTheme().Sizes.standardGap
    for i = 1, #self.providers do
        local provider = self.providers[i]
        local layout = provider(ctx)
        if layout then
            if not C.API.GAP then --TODO: remove when 0.52 is released
                self.element.layout.content:add(T.intervalH(gap))
            end
            self.element.layout.content:add(layout)
        end
    end
    Toolkit.queueUpdate(self.element)
end

return InfoBar
