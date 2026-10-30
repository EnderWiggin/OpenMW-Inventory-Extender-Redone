---@omw-context global

local I     = require 'openmw.interfaces'
local types = require 'openmw.types'

local OFFENSE_TYPE = types.Player.OFFENSE_TYPE

return {
    eventHandlers = {
        -- a failed plant assaults the NPC: I.Crimes is global-context-only, which is why the
        -- mini-mod ships this GLOBAL script
        IERPT_Assault = function(props)
            if not props.player or not props.target then return end
            I.Crimes.commitCrime(props.player, {
                type = OFFENSE_TYPE.Assault,
                victim = props.target,
            })
        end,
    },
}
