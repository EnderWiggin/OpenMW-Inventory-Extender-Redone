---@omw-context player

local core    = require 'openmw.core'
local I       = require 'openmw.interfaces'
local types   = require 'openmw.types'
local async   = require 'openmw.async'
local storage = require 'openmw.storage'
local omwself = require 'openmw.self'


local NPC = types.NPC
local D   = require('scripts.ier_party_barter.config.defaults')
local L   = require('scripts.InventoryExtenderRedone.util.logger').get 'PartyBarter'


local IER        = I.InventoryExtenderRedone
local FDU        = I['FollowerDetectionUtil']
local Toolkit    = I.UIToolkit
local Components = Toolkit.Components

if not IER or not FDU or not Toolkit then return end


local settingsSection = storage.playerSection(D.Section)
local settings = {
    enabled = true,
    offerNonNpc = false,
}

local function readSettings()
    local stored = settingsSection:asTable()
    settings.enabled = stored.b_EnablePartyBarter ~= false
    settings.offerNonNpc = stored.b_OfferNonNpcFollowers == true
end
readSettings()
settingsSection:subscribe(async:callback(readSettings))


local box
local state

local function isValidActor(actor)
    return actor == omwself or (actor:isValid() and actor.enabled)
end

local function selectPartner(actor)
    local wnd = IER.getWindow(IER.Roles.Inventory)
    if not wnd then return end

    local ctx = IER.getContext()
    local partner = ctx.barterState.partner

    if actor then
        if not isValidActor(actor) then return end
        if wnd.target == actor and partner and partner.party == actor then return end
    else
        if wnd.target == omwself and not partner then return end
    end

    IER.Barter.clearBarterOffer()
    if actor then
        IER.Barter.setPartner({ party = actor, gold = omwself })
        wnd:setTarget(actor)
    else
        IER.Barter.clearPartner()
        wnd:setTarget(nil)
    end
    IER.update()
end

local function collectCandidates()
    if not FDU or not FDU.getFollowerList or not FDU.follows then return nil end

    local followers = FDU.getFollowerList()
    local ids = {}
    local actorById = {}
    local nameById = {}

    if followers then
        for _, followerState in pairs(followers) do
            local actor = followerState.actor
            if actor and actor ~= omwself and actor.id
                and not followerState.isSummon
                and actor.enabled
                and isValidActor(actor)
                and FDU.follows(followerState, omwself)
            then
                local isNpc = NPC.objectIsInstance(actor)
                if settings.offerNonNpc or isNpc then
                    local actorType = actor.type
                    local record = actorType and actorType.record and actorType.record(actor)
                    if record then
                        local id = actor.id
                        ids[#ids + 1] = id
                        actorById[id] = actor
                        nameById[id] = record.name or id
                    end
                end
            end
        end
    end

    table.sort(ids)

    local items = { { id = D.PlayerRowId, text = omwself.type.record(omwself).name } }
    for _, id in ipairs(ids) do
        items[#items + 1] = {
            id = id,
            text = nameById[id],
            isDisabled = function()
                local actor = actorById[id]
                return not actor or not isValidActor(actor)
            end,
        }
    end

    local signature = string.format('%s|%s', D.PlayerRowId, table.concat(ids, '|'))

    return items, actorById, signature
end

local function onItemSelected(item, _)
    if not state or not item or not item.id then return end

    if item.id == D.PlayerRowId then
        state.selectedId = D.PlayerRowId
        state.selectedActor = nil
        selectPartner(nil)
        return
    end

    local actor = state.actorById[item.id]
    state.selectedId = item.id
    state.selectedActor = actor
    selectPartner(actor)
end

local function createSection(handler, _)
    local items, actorById, signature = collectCandidates()
    if not items then return nil end

    state = {
        actorById = actorById,
        signature = signature,
        selectedId = D.PlayerRowId,
        selectedActor = nil,
        clearing = false,
    }

    box = Components.dropbox {
        items = items,
        onItemSelected = onItemSelected,
    }

    return function(_)
        if not box or box:isDestroyed() then return nil end
        if not settings.enabled then
            box:closePopup()
            return nil
        end
        if handler.role ~= IER.Roles.Inventory or handler.mode ~= IER.Modes.Barter then
            box:closePopup()
            return nil
        end

        local newItems, newActorById, newSignature = collectCandidates()
        if not newItems then
            box:closePopup()
            return nil
        end

        if newSignature ~= state.signature then
            local selected = box:getSelectedItem()
            local selectedId = selected and selected.id or D.PlayerRowId

            box:setItems(newItems)
            state.actorById = newActorById
            state.signature = newSignature

            if selectedId ~= D.PlayerRowId then
                box:selectById(selectedId)
            end

            selected = box:getSelectedItem()
            state.selectedId = selected and selected.id or D.PlayerRowId
            state.selectedActor = state.selectedId ~= D.PlayerRowId
                and state.actorById[state.selectedId]
                or nil
        end

        if state.selectedActor and not isValidActor(state.selectedActor) then
            state.selectedId = D.PlayerRowId
            state.selectedActor = nil
            box:selectById(D.PlayerRowId)

            if not state.clearing then
                state.clearing = true
                selectPartner(nil)
                state.clearing = false
            end
        end

        if #box.items <= 1 then return nil end

        return box.element
    end
end

local function cleanupSection()
    if not box then return end
    Toolkit.queueDestroy(box.element)
    box = nil
end

local initialized = false

local function tryInit()
    if initialized then return end
    initialized = true
    L.debug('register party barter patch')

    IER.patchMode(IER.Modes.Barter, {
        id = D.PatchId,
        roles = {
            [IER.Roles.Inventory] = {
                infoBar = {
                    add = { {
                        id = D.PatchId,
                        create = createSection,
                        cleanup = cleanupSection,
                    } },
                },
            },
            [IER.Roles.Trade] = {
                observer = function()
                    return state and state.selectedActor
                end,
            },
        },
    })
end

return {
    engineHandlers = {
        onInit = tryInit,
        onLoad = tryInit,
    },
    eventHandlers = {
        IER_BarterFinalized = function()
            local selected = state and state.selectedActor
            if selected and selected ~= omwself then
                core.sendGlobalEvent('IER_AutoEquip', { target = selected })
            end
            state = nil
        end,
    },
}
