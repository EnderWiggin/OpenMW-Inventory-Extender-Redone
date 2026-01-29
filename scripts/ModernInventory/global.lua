local core = require('openmw.core')
local world = require('openmw.world')
local types = require('openmw.types')

return {
    eventHandlers = {
        MI_Teleport = function(props)
            if not props.obj or not props.position then return end
            local obj = props.obj
            local cellOrName = props.cell or ''
            local position = props.position
            local options = props.options
            print("Teleporting object:", obj.id, "to cell:", cellOrName, "at position:", position.x, position.y, position.z)
            obj:teleport(cellOrName, position, options)
        end,
        MI_MoveInto = function(props)
            if not props.obj or not props.destination then return end
            local obj = props.obj
            local destination = props.destination
            obj:moveInto(destination)
        end
    }
}