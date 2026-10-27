---@omw-context none

local MOD = 'InventoryExtender'
local function section(name)
    return string.format('Settings/%s/%s', MOD, name)
end
---@class IER.Config.Defaults
local M = {
    PageKey = MOD,
    L10N = 'InventoryExtenderRedone',
    Version = '0.0.8',
    API = 4,
    -- window ids and UIToolkit:WindowData keys must keep the pre-rename spelling (save identity)
    WindowIdPrefix = 'InventoryExtender:',
    -- window roles, in ui/roles.lua registration order
    Roles = {
        Inventory = 'Inventory',
        Trade     = 'Trade',
        Container = 'Container',
        Companion = 'Companion',
    },
    -- built-in mode keys; the values must equal the engine UI mode strings, because I.UI.removeMode
    -- and I.UI.getWindowsForMode are engine-side lookups. Pickpocket is the one exception: it is an
    -- IER-side key and is never passed to I.UI. Custom mode keys are mod-namespaced strings.
    Modes = {
        Interface  = 'Interface', -- also covers I.UI.getMode() == nil
        Container  = 'Container',
        Pickpocket = 'Pickpocket',
        Barter     = 'Barter',
        Companion  = 'Companion',
    },
    Section = {
        Keybinds    = section 'Keybinds',
        Window      = section 'Window',
        Tweaks      = section 'Tweaks',
        Integration = section 'Integration',
        Misc        = section 'Misc',
        Gameplay    = section 'Gameplay',
        Debug       = section 'Debug',
    },
    -- log verbosity threshold stored as an integer (n_LogLevel): rank <= threshold prints, error
    -- is least verbose, debug most. The dropdown stores the rank itself; labels come from the
    -- LogLevel_* l10n keys.
    LogLevels = {
        Error   = 1,
        Warning = 2,
        Info    = 3,
        Debug   = 4,
    },
    LogLevelDefault = 1, -- D.LogLevels.Error
    -- bounds feed renderer argument, storage defaults and descriptions
    GridIconScale = { default = 1, min = 0.5, max = 2 },
    TableRowHeightMult = { default = 1, min = 1, max = 2 },
    TableScrollStep = { default = 2, min = 1, max = 10 },
    Binds = {
        Activate      = 'c_Activate',
        Favorite      = 'c_Favorite',
        TransferAll      = 'c_TransferAll',
        Category_Prev = 'c_CatPrev',
        Category_Next = 'c_CatNext',
        Select_Up     = 'c_SelUp',
        Select_Down   = 'c_SelDown',
        Select_Left   = 'c_SelLeft',
        Select_Right  = 'c_SelRight',
    },
}

return M
