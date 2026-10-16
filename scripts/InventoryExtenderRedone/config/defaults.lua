---@omw-context none

local MOD = 'InventoryExtender'
local function section(name)
    return string.format('Settings/%s/%s', MOD, name)
end
---@class IER.Config.Defaults
local M = {
    PageKey = MOD,
    L10N = 'InventoryExtenderRedone',
    Version = '0.0.1',
    API = 1,
    Section = {
        Keybinds    = section 'Keybinds',
        Window      = section 'Window',
        Tweaks      = section 'Tweaks',
        Integration = section 'Integration',
        Misc        = section 'Misc',
        Gameplay    = section 'Gameplay',
    },
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
