---@omw-context local
local anim = require('openmw.animation')
local self = require('openmw.self')
local core = require('openmw.core')

local eventHandlers = {
    IER_ContainerClosed = function()
        anim.playBlended(self, 'containerclose', { priority = anim.PRIORITY.Scripted })
    end,
}

return {
    engineHandlers = {
        onInactive = function()
            if self.recordId == 'stolen_goods' then
                core.sendGlobalEvent('IER_StolenChestInactive', self)
            end
        end
    },
    eventHandlers = eventHandlers,
}
