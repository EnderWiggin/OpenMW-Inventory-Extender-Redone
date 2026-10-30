---@omw-context none

---@class IERPickpocketTweaks.Config.Defaults
---@field PageKey string settings page id
---@field L10N string l10n namespace
---@field PatchId string id used for every patchMode call and chain registration
---@field MinIERVersion number minimum Inventory Extender Redone API version
local M = {
    PageKey = 'ier_pickpocket_tweaks',
    L10N = 'ier_pickpocket_tweaks',
    PatchId = 'ier_pickpocket_tweaks',
    MinIERVersion = 4,
}

return M
