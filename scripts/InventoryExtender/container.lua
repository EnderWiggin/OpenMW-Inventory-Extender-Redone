local anim = require('openmw.animation')
local self = require('openmw.self')
local core = require('openmw.core')

return {
    engineHandlers = {
        onInactive = function()
            if self.recordId == 'stolen_goods' then
                core.sendGlobalEvent('MI_StolenChestInactive', self)
            end
        end
    },
    eventHandlers = {
        MI_ContainerClosed = function()
            anim.playBlended(self, 'containerclose', { priority = anim.PRIORITY.Scripted })
        end
    }
}