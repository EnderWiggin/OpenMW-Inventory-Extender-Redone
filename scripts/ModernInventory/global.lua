local types = require('openmw.types')
local I = require('openmw.interfaces')
local world = require('openmw.world')
local core = require('openmw.core')

local CellUtils = require('scripts.ModernInventory.util.cell')

local function isGold(item)
    local id = item.recordId:lower()
    return id == 'gold_001' or id == 'gold_005' or id == 'gold_010' or id == 'gold_025' or id == 'gold_100'
end

local function itemDataEquals(a, b)
    if not types.Item.objectIsInstance(a) or not types.Item.objectIsInstance(b) then
        return false
    end

    local itemDataA = types.Item.itemData(a)
    local itemDataB = types.Item.itemData(b)

    local fieldsToCheck = {
        'condition',
        'enchantmentCharge',
        'soul',
    }

    for _, field in ipairs(fieldsToCheck) do
        if itemDataA[field] ~= itemDataB[field] then
            return false
        end
    end
    return true
end

local function isStealing(actor, ownerInfo)
    local victim = {}
    if ownerInfo.recordId and ownerInfo.recordId ~= actor.recordId then
        victim.recordId = ownerInfo.recordId
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
    if isGold(obj) then
        obj = props.source.type.inventory(props.source):find('gold_001') or obj
    end

    if count ~= obj.count then
        obj = obj:split(count)
    end
    local cellOrName = props.cell or ''
    local position = props.position
    local options = props.options
    obj:teleport(cellOrName, position, options)
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

    if not isGold(obj) then
        for _, item in ipairs(destinationInv:findAll(recordId)) do
            if not destination.type.hasEquipped or not destination.type.hasEquipped(destination, item) and not isEquipped then
                if itemDataEquals(item, obj) then
                    resultingObj = item
                    break
                end
            end
        end
    elseif props.source and props.source ~= props.destination then
        local sourceInv = props.source.type.inventory(props.source)
        obj = sourceInv:find('gold_001') or obj
    end

    if props.count ~= obj.count or isGold(obj) then
        obj = obj:split(props.count or obj.count)
        if props.source ~= props.destination then
            resultingObj = obj
        end
    end

    local ownerInfo
    if props.source and types.Container.objectIsInstance(props.source) then
        ownerInfo = props.source.owner
    else
        ownerInfo = obj.owner
    end
    local victimInfo = isStealing(props.player, ownerInfo)
    if victimInfo and not isGold(obj) then
        local victimActor
        if victimInfo.recordId then
            for _, actor in ipairs(world.activeActors) do
                if actor.recordId == victimInfo.recordId then
                    victimActor = actor
                    break
                end
            end
        end
        props.player:sendEvent('MI_StoleItem', { recordId = obj.recordId, count = props.count, victim = victimInfo })
        I.Crimes.commitCrime(props.player, {
            type = types.Player.OFFENSE_TYPE.Theft,
            arg = obj.type.record(obj).value * props.count,
            faction = victimInfo.factionId,
            victim = victimActor,
        })
    end

    obj:moveInto(destination)
    
    if props.dragStart and isGold(obj) then
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

local checkStolenNextUpdate = {}
local checkStolenNextNextUpdate = {}
local checkStolenBooks = {}
local function onItemActivated(item, actor)
    if not types.Item.isCarriable(item) then return true end
    local victim = isStealing(actor, item.owner)
    if victim and not isGold(item) then
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
        local cell = world.getCellById(id)
        if cell then
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

    local cell = world.getCellById(closestMarker.interior)
    if not cell then
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
                        if toConfiscate < itemCount then
                            item = item:split(toConfiscate)
                        end
                        item:moveInto(container, toConfiscate)
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
                data.player:sendEvent('MI_ItemsConfiscated', { container = container, stolenMap = data.stolenMap })
                return
            end
            break
        end
    end
end

return {
    engineHandlers = {
        onInit = initChestLocks,
        onSave = function()
            return {
                containerMemory = containerMemory,
            }
        end,
        onLoad = function(data)
            initChestLocks()
            if data and data.containerMemory then
                containerMemory = data.containerMemory
            end
        end,
        onUpdate = onUpdate,
    },
    eventHandlers = {
        MI_TryConfiscate = confiscateStolenItems,
        MI_Teleport = teleport,
        MI_MoveInto = moveInto,
        MI_UIModeChanged = onUiModeChanged,
        MI_StolenChestInactive = updateChestMemory,
        UseItem = function(props)
            props.actor:sendEvent('MI_Update')
        end,
    }
}