---@omw-context player

local I = require('openmw.interfaces')


local types      = require('openmw.types')
local omwself    = require('openmw.self')

local D          = require('scripts.InventoryExtenderRedone.config.defaults')
local helpers    = require('scripts.InventoryExtenderRedone.util.helpers')
local constants  = require('scripts.InventoryExtenderRedone.util.constants')
local pickpocket = require('scripts.InventoryExtenderRedone.util.pickpocket')

local Player = types.Player
-- the player inventory is a live handle on omwself, not a snapshot: :getAll() re-reads contents
local playerInventory = Player.inventory(omwself)


-- Mode specs are pure behavior: they never register windows, a new window role only comes
-- through API.registerWindowRole. Slots are keyed per window role because the Inventory role
-- appears in four modes and needs four different slot sets.
---@class InventoryExtenderRedone.Mode.Library
---@field Defaults InventoryExtenderRedone.Mode.Defaults
---@field Sources table<string,InventoryExtenderRedone.Mode.Source>
---@field Filters table<string,InventoryExtenderRedone.Mode.Filter>
---@field Actions table<string,InventoryExtenderRedone.Mode.Action>
---@field Info table<string,InventoryExtenderRedone.Mode.InfoBarSection>
---@field Builtins table<string,InventoryExtenderRedone.Mode>
---@field resolve fun(key:string, role:InventoryExtenderRedone.Role?):InventoryExtenderRedone.Mode?,InventoryExtenderRedone.Mode.RoleSpec?
---@field resolveMode fun(role:InventoryExtenderRedone.Role, arg:any?, uiMode:string?):InventoryExtenderRedone.Mode?,InventoryExtenderRedone.Mode.RoleSpec?
---@field resolveParts fun(library:table<string,any>, entries:any[]?):any[]
---@field statePredicate fun(state:InventoryExtenderRedone.Mode.State?, field:string):(fun(...):boolean)?
---@field merge fun(base:InventoryExtenderRedone.Mode?, patch:InventoryExtenderRedone.ModePatch|InventoryExtenderRedone.Mode):InventoryExtenderRedone.Mode
local Mode = {}


--- Slot defaults: what a mode gets when it does not name the slot. A custom mode that omits
--- an axis keeps today's behavior, which is what makes built-in specs and mod-added specs
--- one mechanism. Slots whose default is "absent" cannot be stored in a table and stay nil.
--- Function-bearing defaults arrive with the phase that owns the behavior.
Mode.Defaults = {
    priority = 0,
    syncCategory = true,
    drag = { allowed = true }, -- validDragModes today: Barter is the mode that forbids dragging
    RoleSpec = {
        pinnable = false, -- only the Interface Inventory window is pinnable (inventory.lua:519)
    },
}

--- Built-in part library. The namespaces are declared here so the contract resolves; the
--- phase that owns the behavior fills them: sources and filters arrived with Phase 2, actions
--- come with Phase 3 and the info bar with Phase 4. Specs reference parts by id, never by
--- inlining behavior, and a part never branches on handler.role - which RoleSpec names the
--- part decides that.
local function merchantItems(npc)
    local merged = helpers.getMerchantItems(npc)
    local flat = {}
    for _, stacks in pairs(merged) do
        for i = 1, #stacks do
            flat[#flat + 1] = stacks[i]
        end
    end
    return flat
end

--- The merchant-services gate both barter roles share: gold and keys are never offered, and an
--- item's service must be offered by the merchant unless it is enchanted and MagicItems is.
---@param row InventoryExtenderRedone.RowData
---@param npc openmw.Object?
---@return boolean
local function isOfferedByMerchant(row, npc)
    if not npc then return false end
    if helpers.isGold(row.item) then return false end
    if row.itemRecord.isKey then return false end

    local services = npc.type.record(npc).servicesOffered
    if not services.MagicItems or not row.itemRecord.enchant then
        for serviceName, serviceType in pairs(constants.ServiceToType) do
            if serviceType.objectIsInstance(row.item) then
                if not services[serviceName] then
                    return false
                end
                break
            end
        end
    end
    return true
end

Mode.Sources = {
    -- the window's own target inventory: the player's for the Inventory role, the container's or
    -- the companion's for its own role
    target = {
        id = 'target',
        get = function(handler, ctx)
            return handler.target.type.inventory(handler.target):getAll()
        end,
    },
    -- always the player's own inventory, whichever window asks for the other side of a barter
    self = {
        id = 'self',
        get = function(handler, ctx)
            return playerInventory:getAll()
        end,
    },
    -- merchant stock merged into virtual stacks; the two ids differ only in which NPC is asked,
    -- and merchantOfOther keeps the ctx.windowArgs fallback because the engine may open the
    -- player's window before the Trade window has recorded the merchant
    --TODO: consider removing ctx.windowArgs
    merchantOfTarget = {
        id = 'merchantOfTarget',
        virtual = true,
        get = function(handler, ctx)
            return merchantItems(handler.target)
        end,
    },
    merchantOfOther = {
        id = 'merchantOfOther',
        virtual = true,
        -- this side is always the far end of an offer: the rows exist to show what the other
        -- window is holding out for
        isBartered = true,
        get = function(handler, ctx)
            local barterNpc = ctx.windowArgs[D.Roles.Trade] or handler.arg
            if not barterNpc then return {} end
            return merchantItems(barterNpc)
        end,
    },
}

Mode.Filters = {
    -- the player's window in Barter mode: what may be sold, plus what the merchant already bought
    barterOffer = {
        id = 'barterOffer',
        fn = function(row, handler, ctx)
            if not isOfferedByMerchant(row, handler.arg) then return false end
            local item = row.item
            local buying = ctx.barterState.buying
            local selling = ctx.barterState.selling
            if row.isBartered then
                return buying[item.id] and buying[item.id].count > 0
            end
            local sellingCount = selling[item.id] and selling[item.id].count or 0
            return row.getCount() > sellingCount
        end,
    },
    -- the merchant's window in Barter mode: its own stock minus what it wears, plus the player's offers
    barterTradeOffer = {
        id = 'barterTradeOffer',
        fn = function(row, handler, ctx)
            if handler.target.type.hasEquipped(handler.target, row.item) then return false end
            if not isOfferedByMerchant(row, handler.arg) then return false end
            local item = row.item
            local buying = ctx.barterState.buying
            local selling = ctx.barterState.selling
            if row.isBartered then
                return selling[item.id] and selling[item.id].count > 0
            end
            local buyingCount = buying[item.id] and buying[item.id].count or 0
            return row.getCount() > buyingCount
        end,
    },
    -- only the items the sneak roll left visible; a nil session means everything is visible
    pickpocketVisibility = {
        id = 'pickpocketVisibility',
        fn = function(row, handler, ctx)
            return pickpocket.isVisible(ctx.pickpocket, row.item)
        end,
    },
}
Mode.Actions = {}
Mode.Info = {}

--- Built-in specs, keyed by mode key. Custom specs live in ctx.modes and are never stored here.
Mode.Builtins = {
    Interface  = require('scripts.InventoryExtenderRedone.toolkit.modes.interface'),
    Container  = require('scripts.InventoryExtenderRedone.toolkit.modes.container'),
    Pickpocket = require('scripts.InventoryExtenderRedone.toolkit.modes.pickpocket'),
    Barter     = require('scripts.InventoryExtenderRedone.toolkit.modes.barter'),
    Companion  = require('scripts.InventoryExtenderRedone.toolkit.modes.companion'),
}


-- List slots merge through id-keyed ops; everything else is a whole-slot overwrite. A plain
-- array in a patch replaces the whole slot, a { add/remove/replace } table applies ops.
local LIST_SLOTS = { 'sources', 'filters', 'infoBar' }
local ROLE_SLOTS = { 'states', 'actions', 'categories', 'columns', 'hints', 'pinnable', 'storageSuffix', 'defaultStorage' }
local MODE_SLOTS = { 'title', 'applies', 'priority', 'syncCategory', 'drag', 'lifecycle', 'event' }


local function isPatchList(op)
    return op.add ~= nil or op.remove ~= nil or op.replace ~= nil
end

--- `after`/`before` on an entry position it against an existing id; entries without them keep
--- insertion order. Ordering only matters for infoBar sections, whose filler (stretch) position
--- is load-bearing for layout.
---@param ordered string[] ids in order, no duplicates
---@param id string
---@param after string? put directly after this id
---@param before string? put directly before this id
local function insertOrdered(ordered, id, after, before)
    for i = 1, #ordered do
        if ordered[i] == id then
            table.remove(ordered, i)
            break
        end
    end
    local anchor = after or before
    if anchor then
        for i = 1, #ordered do
            if ordered[i] == anchor then
                table.insert(ordered, after and i + 1 or i, id)
                return
            end
        end
    end
    ordered[#ordered + 1] = id
end

---@param base any[]?
---@param op any[]|InventoryExtenderRedone.Mode.PatchList
---@return any[]
local function mergeList(base, op)
    if not op then return base or {} end
    if not isPatchList(op) then return op end

    local ordered = {}
    local byId = {}
    for i = 1, #(base or {}) do
        local entry = base[i]
        if entry and entry.id and not byId[entry.id] then
            ordered[#ordered + 1] = entry.id
            byId[entry.id] = entry
        end
    end

    local function put(entry)
        if not entry or not entry.id then return end
        if byId[entry.id] then
            byId[entry.id] = entry
            return
        end
        insertOrdered(ordered, entry.id, entry.after, entry.before)
        byId[entry.id] = entry
    end

    for _, entry in ipairs(op.replace or {}) do put(entry) end
    for _, entry in ipairs(op.add or {}) do put(entry) end

    local removed = {}
    for _, id in ipairs(op.remove or {}) do removed[id] = true end

    local result = {}
    for _, id in ipairs(ordered) do
        local entry = byId[id]
        if entry and not removed[id] then
            result[#result + 1] = entry
        end
    end
    return result
end

---@param base InventoryExtenderRedone.Mode.RoleSpec?
---@param patch InventoryExtenderRedone.Mode.RoleSpecPatch|InventoryExtenderRedone.Mode.RoleSpec?
---@return InventoryExtenderRedone.Mode.RoleSpec
local function mergeRoleSpec(base, patch)
    local merged = {}
    for key, value in pairs(base or {}) do merged[key] = value end
    if not patch then return merged end

    for _, slot in ipairs(LIST_SLOTS) do
        if patch[slot] then merged[slot] = mergeList(merged[slot], patch[slot]) end
    end
    for _, slot in ipairs(ROLE_SLOTS) do
        if patch[slot] ~= nil then merged[slot] = patch[slot] end
    end
    for _, slot in ipairs(patch.disable or {}) do merged[slot] = nil end
    return merged
end

--- Merge a patch (or another spec) over a base spec. `roles` merges per role; every other slot
--- is a whole-slot overwrite, so a mode that wants part of a slot uses the list-slot ops.
---@param base InventoryExtenderRedone.Mode?
---@param patch InventoryExtenderRedone.ModePatch|InventoryExtenderRedone.Mode
---@return InventoryExtenderRedone.Mode
function Mode.merge(base, patch)
    local merged = {}
    for key, value in pairs(base or {}) do merged[key] = value end
    if not patch then return merged end

    if patch.key then merged.key = patch.key end
    for _, slot in ipairs(MODE_SLOTS) do
        if patch[slot] ~= nil then merged[slot] = patch[slot] end
    end
    if patch.roles then
        local roles = {}
        for role, spec in pairs(merged.roles or {}) do roles[role] = spec end
        for role, patchSpec in pairs(patch.roles) do
            roles[role] = mergeRoleSpec(roles[role], patchSpec)
        end
        merged.roles = roles
    end
    for _, slot in ipairs(patch.disable or {}) do merged[slot] = nil end
    return merged
end

--- A spec's own slots win over its base chain, which wins over Mode.Defaults.
---@param spec InventoryExtenderRedone.Mode.RoleSpec?
---@return InventoryExtenderRedone.Mode.RoleSpec
local function applyRoleDefaults(spec)
    local merged = {}
    for key, value in pairs(Mode.Defaults.RoleSpec) do merged[key] = value end
    for key, value in pairs(spec or {}) do merged[key] = value end
    return merged
end

---@param mode InventoryExtenderRedone.Mode
---@return InventoryExtenderRedone.Mode
local function applyModeDefaults(mode)
    if mode.priority == nil then mode.priority = Mode.Defaults.priority end
    if mode.syncCategory == nil then mode.syncCategory = Mode.Defaults.syncCategory end
    if not mode.drag then
        mode.drag = { allowed = Mode.Defaults.drag.allowed }
    elseif mode.drag.allowed == nil then
        mode.drag.allowed = Mode.Defaults.drag.allowed
    end
    return mode
end

--- Resolve a mode key to its fully merged spec: base chain, then registered patches in
--- reverse registration order, like every other id-keyed extension list in the repo.
---@param key InventoryExtenderRedone.ModeKey
---@param ctx InventoryExtenderRedone.Context
---@param visited table<string,boolean>? guards a mod-supplied base cycle
---@return InventoryExtenderRedone.Mode? nil when the key is not registered
local function resolveSpec(key, ctx, visited)
    local spec = Mode.Builtins[key] or ctx.modes[key]
    if not spec then return nil end
    if visited and visited[key] then return nil end

    local base
    if spec.base then
        visited = visited or {}
        visited[key] = true
        base = resolveSpec(spec.base, ctx, visited)
    end

    local merged = Mode.merge(base, spec)
    local patches = ctx.modePatches[key]
    if patches then
        for i = #patches, 1, -1 do
            merged = Mode.merge(merged, patches[i])
        end
    end
    return applyModeDefaults(merged)
end

--- Nothing calls this yet: the phase that wires mode resolution into windowManager:show owns
--- the call. Reopen must compare against an already-open window's snapshot, not re-resolve it.
---@param key InventoryExtenderRedone.ModeKey
---@param role InventoryExtenderRedone.Role? when given, also return this role's merged slots
---@return InventoryExtenderRedone.Mode? mode
---@return InventoryExtenderRedone.Mode.RoleSpec? roleSpec
function Mode.resolve(key, role)
    local mode = resolveSpec(key, I.InventoryExtenderRedone.getContext())
    if not mode then return nil end
    if not role then return mode end

    local spec = mode.roles and mode.roles[role]
    if not spec then return mode end
    return mode, applyRoleDefaults(spec)
end


--- A spec entry may name a built-in part by id or carry its own behavior; the entry's own fields
--- win over the library part, so a mod can reuse a built-in with one field changed. Resolved once
--- at open, like the rest of the snapshot.
---@param library table<string,any> Mode.Sources, Mode.Filters, …
---@param entries any[]?
---@return any[]
function Mode.resolveParts(library, entries)
    local resolved = {}
    for _, entry in ipairs(entries or {}) do
        local part = library[entry.id]
        if part then
            local merged = {}
            for key, value in pairs(part) do merged[key] = value end
            for key, value in pairs(entry) do merged[key] = value end
            resolved[#resolved + 1] = merged
        else
            resolved[#resolved + 1] = entry
        end
    end
    return resolved
end

--- A state slot names either one predicate or a list of States whose same-named predicates are
--- OR-ed. Returns nil when the slot does not name the field at all.
---@param state InventoryExtenderRedone.Mode.State?
---@param field string
---@return (fun(...):boolean)?
function Mode.statePredicate(state, field)
    local value = state and state[field]
    if value == nil then return nil end
    if type(value) == 'function' then return value end

    return function(row, handler, ctx)
        for i = 1, #value do
            local nested = value[i] and value[i][field]
            if nested and nested(row, handler, ctx) then return true end
        end
        return false
    end
end

--- Selection step, before Mode.resolve: which mode governs this window role. Built-in specs match
--- through applies(), which is provided by inventory on open. 
--- Highest priority wins; equal priorities are not ordered, so a custom mode that overlaps
--- a built-in must out-prioritize it. Selection consults registered specs, not patched ones:
--- patchMode changes slots, never which mode applies.
---@param role InventoryExtenderRedone.Role
---@param arg any? the target NPC/container/merchant
---@param uiMode string? UI mode when window opened
---@return InventoryExtenderRedone.Mode? mode fully merged
---@return InventoryExtenderRedone.Mode.RoleSpec? roleSpec this role's merged slots
function Mode.resolveMode(role, arg, uiMode)
    local ctx = I.InventoryExtenderRedone.getContext()

    local bestKey
    local bestPriority
    for key, spec in pairs(Mode.Builtins) do
        if spec.applies and spec.applies(role, arg, ctx, uiMode) then
            local priority = spec.priority or Mode.Defaults.priority
            if not bestKey or priority > bestPriority then
                bestKey = key
                bestPriority = priority
            end
        end
    end
    for key, spec in pairs(ctx.modes) do
        if spec.applies and spec.applies(role, arg, ctx, uiMode) then
            local priority = spec.priority or Mode.Defaults.priority
            if not bestKey or priority > bestPriority then
                bestKey = key
                bestPriority = priority
            end
        end
    end

    if not bestKey then return nil end
    return Mode.resolve(bestKey, role)
end


return Mode
