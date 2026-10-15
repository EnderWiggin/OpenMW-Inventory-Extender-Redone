---@omw-context player
local core = require 'openmw.core'

-- This file is used to import save data from IE's global save
-- Needed for smooth mid-playthrough switch to IER
-- otherwise info about disposed bodies and stolen goods containers is lost
-- also allows to return to IE, although losing any changes to the above info made while playing with IER

local save
return {
    engineHandlers = {
        onSave = function() return save end,
        onLoad = function(data)
            if not data then return end
            save = data
            core.sendGlobalEvent('IER_IMPORT_IE_GLOBAL', data)
        end,
    },
}
