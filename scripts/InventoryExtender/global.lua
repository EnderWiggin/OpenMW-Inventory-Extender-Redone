local types = require('openmw.types')
local I = require('openmw.interfaces')
local world = require('openmw.world')
local core = require('openmw.core')
local util = require('openmw.util')

local CellUtils = require('scripts.InventoryExtender.util.cell')

local helpers = require('scripts.InventoryExtender.util.helpers')

local disposedBodies = {}

local function isStealing(actor, ownerInfo)
    if not ownerInfo then
        return false
    end
    local victim = {}
    if ownerInfo.recordId and ownerInfo.recordId ~= actor.recordId then
        local isDead = disposedBodies[ownerInfo.recordId] or false
        for _, actor in ipairs(world.activeActors) do
            if actor.recordId == ownerInfo.recordId and types.Actor.isDead(actor) then
                isDead = true
                break
            end
        end

        if not isDead then
            victim.recordId = ownerInfo.recordId
        end
    end

    if ownerInfo.factionId then
        local reqRank = ownerInfo.factionRank or 1
        if types.NPC.getFactionRank(actor, ownerInfo.factionId) < reqRank then
            victim.factionId = ownerInfo.factionId
        end
    end
    return next(victim) and victim or false
end

local function teleport(props)
    if not props.obj or not props.position then return end
    local obj = props.obj
    local count = props.count or obj.count
    if helpers.isGold(obj) then
        obj = props.source.type.inventory(props.source):find('gold_001') or obj
    end

    if count ~= obj.count then
        obj = obj:split(count)
    end
    local cellOrName = props.cell or ''
    local position = props.position
    local options = props.options

    if props.dropping then
        local mwscript = world.mwscript.getLocalScript(obj)
        if mwscript and mwscript.variables.onpcdrop then
            mwscript.variables.onpcdrop = 1
        end
    end

    obj:teleport(cellOrName, position, options)
    core.sendGlobalEvent('MI_PostTeleport', {
        obj = obj,
        position = position,
        cell = cellOrName,
        options = options,
        player = props.player,
    })
end

local function postTeleport(props)
    local obj = props.obj
    local box = obj:getBoundingBox()
    local localCenter = box.center - obj.position
    local offset = util.vector3(0, 0, box.halfSize.z - localCenter.z)

    obj:teleport(obj.cell, obj.position + offset)

    props.player:sendEvent('MI_Update')
end

local function getCompanionProfit(npc)
    local script = world.mwscript.getLocalScript(npc)
    if script then
        return script.variables.minimumprofit
    end
    return nil
end

local function scriptedDragStart(props)
    if props.obj.parentContainer == nil then return end

    props.player:sendEvent('MI_SetDraggingObject', {
        obj = props.resultingObj,
        target = props.destination,
        resetMode = true,
    })
    props.player:sendEvent('MI_Update')
end

local function moveInto(props)
    if not props.obj or not props.destination then return end
    local obj = props.obj
    local destination = props.destination
    local recordId = obj.recordId

    local resultingObj = obj
    local destinationInv = destination.type.inventory(destination)

    local isEquipped = false
    if props.source and types.Actor.objectIsInstance(props.source) then
        isEquipped = props.source.type.hasEquipped(props.source, obj)
    end

    if not helpers.isGold(obj) then
        for _, item in ipairs(destinationInv:findAll(recordId)) do
            if not destination.type.hasEquipped or not destination.type.hasEquipped(destination, item) and not isEquipped then
                if helpers.itemDataEquals(item, obj) then
                    resultingObj = item
                    break
                end
            end
        end
    else
        if props.source and props.source ~= props.destination then
            local sourceInv = props.source.type.inventory(props.source)
            obj = sourceInv:find('gold_001') or obj
        end
        resultingObj = destinationInv:find('gold_001') or resultingObj
    end

    local ownerInfo
    if props.source and types.Container.objectIsInstance(props.source) then
        ownerInfo = props.source.owner
    else
        ownerInfo = obj.owner
    end
    local victimInfo = isStealing(props.player, ownerInfo)
    local victimActor
    if victimInfo then
        if victimInfo.recordId then
            for _, actor in ipairs(world.activeActors) do
                if actor.recordId == victimInfo.recordId then
                    victimActor = actor
                    break
                end
            end
        end
        if not helpers.isGold(obj) then
            props.player:sendEvent('MI_StoleItem', { recordId = obj.recordId, count = props.count, victim = victimInfo })
        end
    end

    if types.Player.objectIsInstance(props.destination) and props.source ~= props.destination then
        local mwscript = world.mwscript.getLocalScript(props.destination)
        if mwscript and mwscript.variables.onpcadd then
            mwscript.variables.onpcadd = 1
        end
    end

    if props.dragStart and not props.source then
        local mwscript = obj.type.record(obj).mwscript
        if mwscript then
            local scriptRecord = core.mwscripts.records[mwscript]
            if scriptRecord and scriptRecord.text:lower():find('onactivate') then
                world._runStandardActivationAction(obj, props.player)
                core.sendGlobalEvent('MI_ScriptedDragStart', { player = props.player, obj = obj, resultingObj = resultingObj, target = destination })
                return
            end
        end
    end

    if victimInfo then
        I.Crimes.commitCrime(props.player, {
            type = types.Player.OFFENSE_TYPE.Theft,
            arg = helpers.getItemValue(obj) * props.count,
            faction = victimInfo.factionId,
            victim = victimActor,
        })
    end

    if props.source then
        local profit = getCompanionProfit(props.source)
        if profit then
            profit = profit - (helpers.getItemValue(obj) * props.count)
            world.mwscript.getLocalScript(props.source).variables.minimumprofit = profit
            props.player:sendEvent('MI_CompanionProfit', {
                companion = props.source,
                profit = profit,
            })
        end
    end
    if props.destination ~= props.source then
        local profit = getCompanionProfit(props.destination)
        if profit then
            profit = profit + (helpers.getItemValue(obj) * props.count)
            world.mwscript.getLocalScript(props.destination).variables.minimumprofit = profit
            props.player:sendEvent('MI_CompanionProfit', {
                companion = props.destination,
                profit = profit,
            })
        end
    end

    if props.count ~= obj.count or helpers.isGold(obj) then
        obj = obj:split(props.count or obj.count)
        if props.source ~= props.destination then
            resultingObj = obj
        end
    end

    obj:moveInto(destination)
    
    if props.dragStart and helpers.isGold(obj) then
        local foundGold = destinationInv:find('gold_001')
        if foundGold then
            resultingObj = foundGold
        end
    end

    if props.dragStart then
        props.player:sendEvent('MI_SetDraggingObject', {
            obj = resultingObj,
            target = destination,
        })
    end
    props.player:sendEvent('MI_Update')
    
    return obj
end

local function moveAll(props)
    if not props.source or not props.destination then return end

    local sourceInv = props.source.type.inventory(props.source)
    local items = sourceInv:getAll()

    local victimInfo = isStealing(props.player, props.source.owner)
    local victimActor
    if victimInfo then
        if victimInfo.recordId then
            for _, actor in ipairs(world.activeActors) do
                if actor.recordId == victimInfo.recordId then
                    victimActor = actor
                    break
                end
            end
        end
    end

    local totalCrimeValue = 0
    for _, item in ipairs(items) do
        if types.Item.isCarriable(item) then
            if victimInfo then
                if not helpers.isGold(item) then
                    props.player:sendEvent('MI_StoleItem', { recordId = item.recordId, count = item.count, victim = victimInfo })
                end
                totalCrimeValue = totalCrimeValue + (helpers.getItemValue(item) * item.count)
            end
            item:moveInto(props.destination)
        end
    end

    if victimInfo then
        I.Crimes.commitCrime(props.player, {
            type = types.Player.OFFENSE_TYPE.Theft,
            arg = totalCrimeValue,
            faction = victimInfo.factionId,
            victim = victimActor,
        })
    end
end

local checkStolenNextUpdate = {}
local checkStolenNextNextUpdate = {}
local checkStolenBooks = {}
local function onItemActivated(item, actor)
    if not types.Item.isCarriable(item) then return true end
    local victim = isStealing(actor, item.owner)
    if victim and not helpers.isGold(item) then
        if types.Book.objectIsInstance(item) then
            checkStolenBooks[actor.id] = checkStolenBooks[actor.id] or {}
            table.insert(checkStolenBooks[actor.id], { actor = actor, item = item, victim = victim, prevCount = actor.type.inventory(actor):countOf(item.recordId) })
        else
            checkStolenNextNextUpdate = checkStolenNextNextUpdate or {}
            checkStolenNextNextUpdate[actor.id] = checkStolenNextNextUpdate[actor.id] or {}
            table.insert(checkStolenNextNextUpdate[actor.id], { actor = actor, item = item, victim = victim, prevCount = actor.type.inventory(actor):countOf(item.recordId) })
        end
    end
end

local function onUpdate(dt)
    if core.isWorldPaused() then
        return
    end
    
    if checkStolenNextUpdate and next(checkStolenNextUpdate) ~= nil then
        for actorId, entries in pairs(checkStolenNextUpdate) do
            for i = #entries, 1, -1 do
                local entry = entries[i]
                local actor = entry.actor
                local item = entry.item
                local victim = entry.victim
                local prevCount = entry.prevCount
                local currentCount = actor.type.inventory(actor):countOf(item.recordId)
                if currentCount > prevCount then
                    local stolenCount = currentCount - prevCount
                    actor:sendEvent('MI_StoleItem', { recordId = item.recordId, count = stolenCount, victim = victim })
                end
                table.remove(entries, i)
            end
            if #entries == 0 then
                checkStolenNextUpdate[actorId] = nil
            end
        end
    end

    checkStolenNextUpdate = checkStolenNextNextUpdate
    checkStolenNextNextUpdate = nil
end

local lastInteractedContainer = {}
local containerMemory = {}

local MI_LOCK_LEVEL = 49
local VANILLA_LOCK_LEVEL = 50

local function updateChestMemory(chest)
    if chest.cell.isExterior then return end
    if chest.recordId ~= 'stolen_goods' then return end
    local cellId = chest.cell.id:lower()
    containerMemory[cellId] = {}
    for _, item in ipairs(chest.type.inventory(chest):getAll()) do
        containerMemory[cellId][item.recordId] = (containerMemory[cellId][item.recordId] or 0) + item.count
    end
    if types.Lockable.getLockLevel(chest) == VANILLA_LOCK_LEVEL then
        types.Lockable.lock(chest, MI_LOCK_LEVEL)
    end
end

local function onUiModeChanged(data)
    if data.oldMode == 'Container' then
        local container = lastInteractedContainer[data.actor.id]
        if container then
            if container.recordId == 'stolen_goods' then
                updateChestMemory(container)
            end
            lastInteractedContainer[data.actor.id] = nil
        end
    end
    if data.newMode == 'Container' then
        lastInteractedContainer[data.actor.id] = data.arg
    end

    if data.oldMode == 'Book' or data.oldMode == 'Scroll' then
        if checkStolenBooks and checkStolenBooks[data.actor.id] then
            local entries = checkStolenBooks[data.actor.id]
            for i = #entries, 1, -1 do
                local entry = entries[i]
                local item = entry.item
                local victim = entry.victim
                local prevCount = entry.prevCount
                local currentCount = data.actor.type.inventory(data.actor):countOf(item.recordId)
                if currentCount > prevCount then
                    local stolenCount = currentCount - prevCount
                    data.actor:sendEvent('MI_StoleItem', { recordId = item.recordId, count = stolenCount, victim = victim })
                end
                table.remove(entries, i)
            end
            if #entries == 0 then
                checkStolenBooks[data.actor.id] = nil
            end
        end
    end
end

for _, type in pairs(types) do
    if type.baseType == types.Item then
        I.Activation.addHandlerForType(type, onItemActivated)
    end
end

local function initChestLocks()
    local prisonCells = CellUtils.getPrisonCells()
    for id in pairs(prisonCells) do
        local success, cell = pcall(world.getCellById, id)
        if success and cell then
            for _, container in ipairs(cell:getAll(types.Container)) do
                if container.recordId == 'stolen_goods' then
                    if types.Lockable.getLockLevel(container) == VANILLA_LOCK_LEVEL then
                        types.Lockable.lock(container, MI_LOCK_LEVEL)
                    end
                    break
                end
            end
        end
    end
end

local function confiscateStolenItems(data)
    local closestMarker = CellUtils.getClosestMarker(data.player)
    if not closestMarker then
        return
    end

    local success, cell = pcall(world.getCellById, closestMarker.interior)
    if not success or not cell then
        return
    end

    data.stolenMap = data.stolenMap or {}

    for _, container in ipairs(cell:getAll(types.Container)) do
        if container.recordId == 'stolen_goods' then
            if types.Lockable.getLockLevel(container) == VANILLA_LOCK_LEVEL then
                --print("Confiscating goods to", container)

                -- compare with memory
                local cellId = container.cell.id:lower()
                local memory = containerMemory[cellId] or {}
                local current = {}
                for _, item in ipairs(container.type.inventory(container):getAll()) do
                    current[item.recordId] = (current[item.recordId] or 0) + item.count
                end
                local delta = {}
                for recordId, count in pairs(current) do
                    local memCount = memory[recordId] or 0
                    if count > memCount then
                        delta[recordId] = count - memCount
                        --print("newly confiscated item:", recordId, "count:", delta[recordId])
                    end
                end

                local playerInv = data.player.type.inventory(data.player)
                for recordId, victimCounts in pairs(data.stolenMap) do
                    local totalToConfiscate = 0
                    for victimId, count in pairs(victimCounts) do
                        totalToConfiscate = totalToConfiscate + count
                    end
                    local totalConfiscated = delta[recordId] or 0
                    for _, item in ipairs(playerInv:findAll(recordId)) do
                        if totalConfiscated >= totalToConfiscate then
                            break
                        end
                        local itemCount = item.count
                        local toConfiscate = math.min(itemCount, totalToConfiscate - totalConfiscated)
                        local toMove = item
                        if toConfiscate < itemCount then
                            toMove = item:split(toConfiscate)
                        end
                        toMove:moveInto(container, toConfiscate)
                        current[recordId] = (current[recordId] or 0) + toConfiscate
                        totalConfiscated = totalConfiscated + toConfiscate
                    end
                    if (totalConfiscated - (delta[recordId] or 0)) > 0 then
                        --print("Script confiscated item:", recordId, "count:", (totalConfiscated - (delta[recordId] or 0)))
                    end
                    for victimId, count in pairs(victimCounts) do
                        if totalConfiscated >= count then
                            totalConfiscated = totalConfiscated - count
                            victimCounts[victimId] = nil
                        else
                            victimCounts[victimId] = count - totalConfiscated
                            break
                        end
                    end
                    if not next(victimCounts) then
                        data.stolenMap[recordId] = nil
                    end
                end

                containerMemory[cellId] = current

                types.Lockable.lock(container, MI_LOCK_LEVEL)
                data.player:sendEvent('MI_ItemsConfiscated', { stolenMap = data.stolenMap })
                return
            end
            break
        end
    end
end

local function confiscateToOwner(data)
    if not data.stolenMap[data.item.recordId] then
        return
    end

    local toRemove = math.min(data.count, data.stolenMap[data.item.recordId][data.victim.recordId] or 0)
    data.stolenMap[data.item.recordId][data.victim.recordId] = (data.stolenMap[data.item.recordId][data.victim.recordId] or 0) - toRemove
    if data.stolenMap[data.item.recordId][data.victim.recordId] <= 0 then
        data.stolenMap[data.item.recordId][data.victim.recordId] = nil
    end
    if not next(data.stolenMap[data.item.recordId]) then
        data.stolenMap[data.item.recordId] = nil
    end

    I.Crimes.commitCrime(data.player, {
        type = types.Player.OFFENSE_TYPE.Theft,
        arg = helpers.getItemValue(data.item) * toRemove,
        victim = data.victim,
        victimAware = true,
    })
    data.item:split(toRemove):moveInto(types.Actor.inventory(data.victim))
    data.player:sendEvent('MI_ItemsConfiscated', { stolenMap = data.stolenMap })
end

local function setItemData(item, data)
    local itemData = types.Item.itemData(item)
    if data.condition then
        itemData.condition = data.condition
    end
    if data.enchantmentCharge then
        itemData.enchantmentCharge = data.enchantmentCharge
    end
    if data.soul then
        itemData.soul = data.soul
    end
end

local function finalizeBarter(props)
    local function transferItems(entries, destination, restock)
        for _, entry in pairs(entries) do
            local remainingCount = entry.count
            
            if entry.count > 0 then
                if entry.stacks then
                    for _, stackItem in ipairs(entry.stacks) do
                        if remainingCount <= 0 then break end

                        local takeCount = math.min(stackItem.count, remainingCount)
                        local item = takeCount < stackItem.count and stackItem:split(takeCount) or stackItem

                        if restock and stackItem.parentContainer and types.Item.isRestocking(stackItem) then
                            local newItem = world.createObject(stackItem.recordId, takeCount)
                            setItemData(newItem, stackItem.type.itemData(stackItem))
                            newItem:moveInto(destination)
                        else
                            item:moveInto(destination)
                        end
                        remainingCount = remainingCount - takeCount
                    end
                else
                    local item = entry.count < entry.item.count and entry.item:split(entry.count) or entry.item

                    if restock and entry.item.parentContainer and types.Item.isRestocking(entry.item) then
                        local newItem = world.createObject(entry.item.recordId, entry.count)
                        setItemData(newItem, entry.item.type.itemData(entry.item))
                        newItem:moveInto(destination)
                    else
                        item:moveInto(destination)
                    end
                end
            end
        end
    end
    
    transferItems(props.barterState.selling, props.merchant, false)
    transferItems(props.barterState.buying, props.player, true)
    
    if props.barterState.currentBalance ~= 0 then
        if props.barterState.currentBalance < 0 then
            local gold = types.Actor.inventory(props.player):find('gold_001')
            if gold then
                gold:remove(-props.barterState.currentBalance)
            end
            types.NPC.setBarterGold(props.merchant, types.NPC.getBarterGold(props.merchant) + -props.barterState.currentBalance)
        else
            local gold = world.createObject('gold_001', props.barterState.currentBalance)
            gold:moveInto(types.Actor.inventory(props.player))
            types.NPC.setBarterGold(props.merchant, types.NPC.getBarterGold(props.merchant) - props.barterState.currentBalance)
        end
    end
    props.player:sendEvent('MI_BarterFinalized', {
        skillGain = props.skillGain,
    })
end

return {
    engineHandlers = {
        onInit = initChestLocks,
        onSave = function()
            return {
                containerMemory = containerMemory,
                disposedBodies = disposedBodies,
            }
        end,
        onLoad = function(data)
            initChestLocks()
            if data then
                containerMemory = data.containerMemory or {}
                disposedBodies = data.disposedBodies or {}
            end
        end,
        onUpdate = onUpdate,
    },
    eventHandlers = {
        MI_TryConfiscate = confiscateStolenItems,
        MI_ConfiscateToOwner = confiscateToOwner,
        MI_Teleport = teleport,
        MI_PostTeleport = postTeleport,
        MI_ScriptedDragStart = scriptedDragStart,
        MI_MoveInto = moveInto,
        MI_MoveAll = moveAll,
        MI_FinalizeBarter = finalizeBarter,
        MI_UIModeChanged = onUiModeChanged,
        MI_StolenChestInactive = updateChestMemory,
        MI_DisposeOfCorpse = function(props)
            disposedBodies[props.target.recordId] = true
            props.target:remove()
        end,
        MI_ModDisposition = function(props)
            types.NPC.modifyBaseDisposition(props.target, props.player, props.amount)
        end,
        UseItem = function(props)
            props.actor:sendEvent('MI_Update')
        end,
    }
}