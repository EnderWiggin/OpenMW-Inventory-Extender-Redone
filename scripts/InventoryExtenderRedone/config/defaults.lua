---@omw-context none

local MOD = 'InventoryExtender'
local function section(name)
    return string.format('Settings/%s/%s', MOD, name)
end
---@class IER.Config.Defaults
local M = {
    PageKey = MOD,
    L10N = 'InventoryExtenderRedone',
    Version = '0.0.3',
    API = 1,
    Section = {
        Keybinds    = section 'Keybinds',
        Window      = section 'Window',
        Tweaks      = section 'Tweaks',
        Integration = section 'Integration',
        Misc        = section 'Misc',
        Gameplay    = section 'Gameplay',
    },
    -- bounds feed renderer argument, storage defaults and descriptions
    GridIconScale = { default = 1, min = 0.5, max = 2 },
    TableRowHeightMult = { default = 1, min = 1, max = 2 },
    TableScrollStep = { default = 2, min = 1, max = 10 },
    Binds = {
        Activate      = 'c_Activate',
        Favorite      = 'c_Favorite',
        Category_Prev = 'c_CatPrev',
        Category_Next = 'c_CatNext',
        Select_Up     = 'c_SelUp',
        Select_Down   = 'c_SelDown',
        Select_Left   = 'c_SelLeft',
        Select_Right  = 'c_SelRight',
    },
}

return M
