---@omw-context player

local storage = require 'openmw.storage'
local types   = require 'openmw.types'

local Weapon  = types.Weapon
local Potion  = types.Potion

local WeaponType = Weapon.TYPE


local M = {}


-- Toxicology owns coating state in a globalSection it writes from its GLOBAL script; player scripts
-- can only observe it. Keys are namespaced per load (see liveKey below), so the live namespace has
-- to be resolved on every read and never cached.
local poisonSection = storage.globalSection('Runtime_ToxicologyWeaponPoison')

local THROWN_POISON_PREFIX = 'thrown:'
local NAMESPACE_KEY = '__activeNamespace'


-- Shape of one entry in Runtime_ToxicologyWeaponPoison, as written by Toxicology's global.lua
-- (copyWeaponPoisonData there is the authority for these fields). A coating is active when any of
-- the three poisonId fields is set; charges count successful hits that still carry the payload and
-- are cleared to nil once a layer runs out, so a layer is either fully present or fully absent.
-- Layers 2 and 3 only exist while Compound Blend is unlocked (Toxicology skill 50+).
---@class IERToxicologyInterop.PoisonData
---@field poisonId string? record id of the potion applied as coating 1
---@field charges number? hits left in coating 1
---@field layer2PoisonId string? record id of coating 2, when Compound Blend is active
---@field layer2Charges number? hits left in coating 2
---@field layer3PoisonId string? record id of coating 3, when Compound Blend is active
---@field layer3Charges number? hits left in coating 3
---@field snapshot IERToxicologyInterop.PoisonSnapshotMap? poisonId -> payload captured at apply time

---@class IERToxicologyInterop.PoisonSnapshotMap table<string, IERToxicologyInterop.PoisonSnapshot>

---@class IERToxicologyInterop.PoisonSnapshot
---@field name string? potion name as it was when the coating was applied
---@field effects table? effects the coating fires on a hit

---@class IERToxicologyInterop.PoisonLayer
---@field name string? potion name as recorded when the coating was applied
---@field charges number? hits left in this coating

---@param item openmw.Object
---@return string? storage key without the load namespace
local function poisonStorageKey(item)
    if not Weapon.objectIsInstance(item) then return nil end
    local rec = Weapon.record(item)
    if not rec then return nil end
    -- Thrown weapons are keyed by record id: the thrown object leaves the inventory before the
    -- projectile lands, so an object-id key would be gone by the time the hit resolves.
    if rec.type == WeaponType.MarksmanThrown then
        return THROWN_POISON_PREFIX .. tostring(item.recordId)
    end
    return item.id
end


---@param key string?
---@return string? fully qualified section key; nil while Toxicology has not allocated a load namespace
local function liveKey(key)
    if not key then return nil end
    local namespace = poisonSection:get(NAMESPACE_KEY)
    if namespace == nil then return nil end
    return tostring(namespace) .. '|' .. tostring(key)
end

--- Never hand a nil key to :get(), and never cache the qualified key across frames.
---@param key string?
---@return table? read-only userdata, nil when the entry is absent
local function readPoisonData(key)
    local qualifiedKey = liveKey(key)
    if not qualifiedKey then return nil end
    return poisonSection:get(qualifiedKey)
end


-- Layer keys, mirroring LAYER_KEYS in Toxicology's global.lua.
local LAYER_KEYS = {
    { poison = 'poisonId',       charges = 'charges' },
    { poison = 'layer2PoisonId', charges = 'layer2Charges' },
    { poison = 'layer3PoisonId', charges = 'layer3Charges' },
}


--- Potion name behind a coating id.
--- Brewed potions get dynamic record ids that stop resolving after save/reload, so the apply-time
--- snapshot is the fallback; without it a coating would have no displayable name at all.
---@param raw IERToxicologyInterop.PoisonData?
---@param poisonId string
---@return string?
local function poisonName(raw, poisonId)
    local record = Potion.records[poisonId]
    if record then return record.name end
    if not raw then return nil end
    local snapshot = raw.snapshot and raw.snapshot[poisonId]
    return snapshot and snapshot.name or nil
end


--- Present layers of a coating entry, flattened to what a UI consumer needs.
--- This is also where the read-only section value stops being tied to the section: a layer is
--- either fully present or fully absent, so an id alone marks the layer and nil means no coating.
---@param raw IERToxicologyInterop.PoisonData?
---@return IERToxicologyInterop.PoisonLayer[]? nil when no layer holds a poison
local function collectPoisonLayers(raw)
    if not raw then return nil end
    local layers
    for i = 1, #LAYER_KEYS do
        local key = LAYER_KEYS[i]
        local poisonId = raw[key.poison]
        if poisonId ~= nil then
            local charges = tonumber(raw[key.charges]) or 0
            if charges > 0 then
                local name = poisonName(raw, poisonId)
                if name then
                    layers = layers or {}
                    layers[#layers + 1] = {
                        name = name,
                        charges = charges,
                    }
                end
            end
        end
    end
    return layers
end


--- Active coatings on a weapon.
--- poisonStorageKey already splits thrown records from object-keyed coatings, so the caller just
--- hands over the weapon: a coating belongs to that instance, not to its record.
---@param item openmw.Object
---@return IERToxicologyInterop.PoisonLayer[]? nil when the weapon carries no coating
function M.getActivePoisons(item)
    local key = poisonStorageKey(item)
    if not key then return nil end
    return collectPoisonLayers(readPoisonData(key))
end

return M
