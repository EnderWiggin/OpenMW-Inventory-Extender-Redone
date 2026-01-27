local core = require('openmw.core')
local util = require('openmw.util')
local self = require('openmw.self')
local debug = require('openmw.debug')
local I = require('openmw.interfaces')
local types = require('openmw.types')

local C = require('scripts.ModernInventory.util.constants')

local Helpers = {}

Helpers.shallowCopy = function(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

Helpers.deepCopy = function(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            copy[k] = Helpers.deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

Helpers.deepPrint = function(tbl, indent)
    if type(tbl) ~= 'table' then return tostring(tbl) end
    indent = indent or 0
    local toprint = string.rep(" ", indent) .. "{\n"
    indent = indent + 2 
    for k, v in pairs(tbl) do
        toprint = toprint .. string.rep(" ", indent)
        if (type(k) == "number") then
            toprint = toprint .. "[" .. k .. "] = "
        elseif (type(k) == "string") then
            toprint = toprint  .. k ..  " = "   
        end
        if (type(v) == "number") then
            toprint = toprint .. v .. ",\n"
        elseif (type(v) == "string") then
            toprint = toprint .. "\"" .. v .. "\",\n"
        elseif (type(v) == "table") then
            toprint = toprint .. Helpers.deepPrint(v, indent + 2) .. ",\n"
        else
            toprint = toprint .. "\"" .. tostring(v) .. "\",\n"
        end
    end
    toprint = toprint .. string.rep(" ", indent-2) .. "}"
    return toprint
end

Helpers.uiDeepPrint = function(layoutOrElement, lvl)
    lvl = lvl or 0
    local isElement = type(layoutOrElement) == 'userdata'
    local layout = isElement and layoutOrElement.layout or layoutOrElement
    if layout.name then
        print(string.rep('-', lvl), layoutOrElement, layout.name)
    end
    if layout.userData then
        print(string.rep(' ', lvl), 'UserData:', Helpers.deepPrint(layout.userData))
    end
    if layout.content then
        for _, child in pairs(layout.content) do
            Helpers.uiDeepPrint(child, lvl + 1)
        end
    end
end

Helpers.forEachInLayout = function(layoutOrElement, func)
    local isElement = type(layoutOrElement) == 'userdata'
    local layout = isElement and layoutOrElement.layout or layoutOrElement
    func(layout)
    if layout.content then
        for _, child in pairs(layout.content) do
            Helpers.forEachInLayout(child, func)
        end
    end
end

Helpers.findInLayout = function(layoutOrElement, predicate)
    local isElement = type(layoutOrElement) == 'userdata'
    local layout = isElement and layoutOrElement.layout or layoutOrElement
    if predicate(layout) then
        return layout
    end
    if layout.content then
        for _, child in pairs(layout.content) do
            local result = Helpers.findInLayout(child, predicate)
            if result then
                return result
            end
        end
    end
    return nil
end

-- Checks if two tables contain the same elements (ignoring order)
Helpers.tableEquals = function(t1, t2)
    if (type(t1) ~= "table" and type(t1) ~= "userdata") or (type(t2) ~= "table" and type(t2) ~= "userdata") then
        return t1 == t2
    end
    if t1.id and t2.id then
        local sameCount = true
        if t1.count and t2.count then
            sameCount = t1.count == t2.count
        end
        return t1.id == t2.id and sameCount
    end
    local t1Keys = {}
    local t2Keys = {}
    for k in pairs(t1) do table.insert(t1Keys, k) end
    for k in pairs(t2) do table.insert(t2Keys, k) end
    table.sort(t1Keys)
    table.sort(t2Keys)
    if #t1Keys ~= #t2Keys then return false end
    for i = 1, #t1Keys do
        if t1Keys[i] ~= t2Keys[i] then return false end
        if not Helpers.tableEquals(t1[t1Keys[i]], t2[t2Keys[i]]) then return false end
    end
    return true
end

Helpers.mapEquals = function(m1, m2)
    for k, v in pairs(m1) do
        if type(v) == 'table' and type(m2[k]) == 'table' then
            if not Helpers.mapEquals(v, m2[k]) then
                return false
            end
        else
            if m2[k] ~= v then
                return false
            end
        end
    end
    for k, v in pairs(m2) do
        if type(v) == 'table' and type(m1[k]) == 'table' then
            if not Helpers.mapEquals(v, m1[k]) then
                return false
            end
        else
            if m1[k] ~= v then
                return false
            end
        end
    end
    return true
end

Helpers.mergeTables = function(t1, t2)
    local merged = Helpers.shallowCopy(t1)
    for k, v in pairs(t2) do
        merged[k] = v
    end
    return merged
end

Helpers.roundToPlaces = function(num, places)
    local mult = 10^(places or 0)
    return math.floor(num * mult + 0.5) / mult
end

return Helpers