local types = require('openmw.types')

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

    if not isGold(obj) then
        for _, item in ipairs(destinationInv:findAll(recordId)) do
            if itemDataEquals(item, obj) then
                resultingObj = item
                break
            end
        end
    elseif props.source and props.source ~= props.destination then
        local sourceInv = props.source.type.inventory(props.source)
        obj = sourceInv:find('gold_001') or obj
    end

    if props.count ~= obj.count or isGold(obj) then
        obj = obj:split(props.count or obj.count)
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

return {
    eventHandlers = {
        MI_Teleport = teleport,
        MI_MoveInto = moveInto,
        UseItem = function(props)
            props.actor:sendEvent('MI_Update')
        end,
    }
}