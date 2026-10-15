---@omw-context player
local I = require 'openmw.interfaces'

-- This file is used to import save data from IE's API save
-- Needed for smooth mid-playthrough switch to IER
-- otherwise favorites, stolen info and companion share is lost
-- also allows to return to IE, although losing any changes to the above info made while playing with IER

local save
return {
    engineHandlers = {
        onSave = function() return save end,
        onLoad = function(data)
            if not data then return end
            save = data
            local ctx = I.InventoryExtenderRedone.getContext()
            if ctx.imported_ie_api then return end
            ctx.imported_ie_api = true

            if data.stolenItems then
                ctx.stolenItems = data.stolenItems
            end
            if data.favoriteItems then
                ctx.favoriteItems = data.favoriteItems
            end
            if data.favoriteRevision then
                ctx.favoriteRevision = data.favoriteRevision
            end
            if data.companionProfit then
                ctx.companionProfit = data.companionProfit
            end
        end,
    },
}
