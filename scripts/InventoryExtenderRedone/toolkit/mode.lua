---@omw-context player

local I = require('openmw.interfaces')


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
---@field resolve fun(key:string, role:InventoryExtenderRedone.Role?):InventoryExtenderRedone.Mode,InventoryExtenderRedone.Mode.RoleSpec
---@field merge fun(base:InventoryExtenderRedone.Mode?, patch:InventoryExtenderRedone.ModePatch):InventoryExtenderRedone.Mode
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
--- phase that owns the behavior fills them: Phase 2 sources/filters/states, Phase 3 actions,
--- Phase 4 info bar. Specs reference parts by id, never by inlining behavior.
Mode.Sources = {}
Mode.Filters = {}
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


return Mode
