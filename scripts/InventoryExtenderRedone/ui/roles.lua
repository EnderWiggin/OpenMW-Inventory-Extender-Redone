---@omw-context player

local util = require('openmw.util')
local v2 = util.vector2
local D = require('scripts.InventoryExtenderRedone.config.defaults')


-- Window roles: which windows exist and how they are placed. Identity and geometry only;
-- behavior belongs to mode specs, and a new role comes only through API.registerWindowRole.
---@class InventoryExtenderRedone.RoleRegistry
---@field order InventoryExtenderRedone.Role[] registration order, drives update()/forEachOpenWindow
---@field byRole table<string,InventoryExtenderRedone.RoleOpts> role -> registration opts
---@field register fun(role:InventoryExtenderRedone.Role, opts:InventoryExtenderRedone.RoleOpts)
local Registry = {
    order = {},
    byRole = {},
}

---@param role InventoryExtenderRedone.Role
---@param opts InventoryExtenderRedone.RoleOpts
function Registry.register(role, opts)
    if Registry.byRole[role] then return end
    Registry.byRole[role] = opts
    Registry.order[#Registry.order + 1] = role
end

-- Default geometry is layer-relative, the format UIToolkit.WindowManager.toAbsolute expects.
-- These are the saved-state fallbacks: a player's saved position/size wins over them, so
-- changing a value only moves windows that were never moved by hand.
local MIN_SIZE = v2(300, 200)

-- Registration order is D.Roles order: the inventory window first, then the target windows.
Registry.register(D.Roles.Inventory, {
    title = D.Roles.Inventory,
    defaultPosition = v2(0.015, 0.54),
    defaultSize = v2(0.45, 0.38),
    minSize = MIN_SIZE,
    draggable = true,
    resizing = true,
    -- pinning is set at open by the Interface mode, not by window registration
    pinnable = false,
})
Registry.register(D.Roles.Trade, {
    title = D.Roles.Trade,
    defaultPosition = v2(0.5, 0.05),
    defaultSize = v2(0.45, 0.85),
    minSize = MIN_SIZE,
    draggable = true,
    resizing = true,
    pinnable = false,
})
Registry.register(D.Roles.Container, {
    title = D.Roles.Container,
    defaultPosition = v2(0.5, 0.05),
    defaultSize = v2(0.45, 0.85),
    minSize = MIN_SIZE,
    draggable = true,
    resizing = true,
    pinnable = false,
})
Registry.register(D.Roles.Companion, {
    title = D.Roles.Companion,
    defaultPosition = v2(0.5, 0.05),
    defaultSize = v2(0.45, 0.85),
    minSize = MIN_SIZE,
    draggable = true,
    resizing = true,
    pinnable = false,
})

return Registry
