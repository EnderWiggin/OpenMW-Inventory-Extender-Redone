---@omw-context player

local I       = require 'openmw.interfaces'
local types   = require 'openmw.types'
local async   = require 'openmw.async'
local storage = require 'openmw.storage'

local NPC = types.NPC
local D   = require('scripts.ier_pickpocket_tweaks.config.defaults')
local L   = require('scripts.InventoryExtenderRedone.util.logger').get 'PickpocketTweaks'

local IER        = I.InventoryExtenderRedone
local Pickpocket = IER and IER.Pickpocket
if not Pickpocket then return end


local closeSection = storage.playerSection(D.CloseSection)
local settings = {
    closeSkillThreshold = D.CloseSkill.default,
}

local function readSettings()
    local stored = closeSection:asTable()
    settings.closeSkillThreshold = stored.n_CloseSkillThreshold or D.CloseSkill.default
end
readSettings()
closeSection:subscribe(async:callback(readSettings))


local function getSneak(actor)
    return NPC.stats.skills.sneak(actor).modified
end

local function tryInit()
    L.debug('register close chance handler')
    Pickpocket.registerCloseChance(D.PatchId, function(player, target, session, chance)
        if getSneak(player) >= settings.closeSkillThreshold then
            return 100
        end
    end)
end

return {
    engineHandlers = {
        onInit = tryInit,
        onLoad = tryInit,
    },
}
