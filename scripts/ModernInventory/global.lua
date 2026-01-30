return {
    eventHandlers = {
        MI_Teleport = function(props)
            if not props.obj or not props.position then return end
            local obj = props.obj
            local cellOrName = props.cell or ''
            local position = props.position
            local options = props.options
            obj:teleport(cellOrName, position, options)
            props.player:sendEvent('MI_Update')
        end,
        MI_MoveInto = function(props)
            if not props.obj or not props.destination then return end
            local obj = props.obj
            local destination = props.destination
            obj:moveInto(destination)
            props.player:sendEvent('MI_Update')
        end,
        UseItem = function(props)
            props.actor:sendEvent('MI_Update')
        end,
    }
}