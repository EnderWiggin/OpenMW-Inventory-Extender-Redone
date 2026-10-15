---@omw-context none

local MOD = 'InventoryExtender'
local function section(name)
    return string.format('Settings/%s/%s', MOD, name)
end
---@class IER.Config.Defaults
local M = {
    PageKey = MOD,
    L10N = 'InventoryExtender',
    Version = '0.0.1',
    API = 1,
    Section = {
    },
}

return M
