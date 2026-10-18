---@omw-context player

local core = require 'openmw.core'
local I    = require 'openmw.interfaces'
local l10n = core.l10n 'IER_Katars_Type'


local initialized = false

local function tryInit()
    if initialized then return end

    local IER = I.InventoryExtenderRedone
    if not IER or not IER.registerRowDataModifier then return end

    local H2H = I.H2HWeapons
    if not H2H or not H2H.getHybridDefForRecordId then return end

    initialized = true

    IER.registerRowDataModifier('katars', function(row)
        local hybrid = H2H.getHybridDefForRecordId(row.itemRecord.id)
        if not hybrid then return end
        if hybrid.primarySkill ~= 'handtohand' then return end
        local secondary = hybrid.secondarySkill
        if not secondary then
            row.Type = l10n 'Type_Fist'
        else
            secondary = secondary:lower()
            if secondary == 'shortblade' then
                row.Type = l10n 'Type_Katar'
            else
                row.Type = l10n 'Type_Fist'
            end
        end
    end)
end



return {
    engineHandlers = {
        onInit = tryInit,
        onLoad = tryInit,
    }
}
