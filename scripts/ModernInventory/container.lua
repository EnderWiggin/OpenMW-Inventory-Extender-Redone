local anim = require('openmw.animation')
local self = require('openmw.self')

return {
    eventHandlers = {
        MI_ContainerClosed = function()
            anim.playBlended(self, 'containerclose', { priority = anim.PRIORITY.Scripted })
        end
    }
}