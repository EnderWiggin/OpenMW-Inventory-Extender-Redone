---@omw-context none

-- bounds feed renderer argument, storage defaults and descriptions

---@class IERPartyBarter.Config.Defaults
---@field PageKey string settings page id
---@field L10N string l10n namespace
---@field Section string storage section holding the two toggles
---@field PatchId string id of the Barter-mode patch
---@field PlayerRowId string dropbox row id meaning "no partner"
---@field MinIERVersion number minimum Inventory Extender Redone API version
---@field MinFDUVersion number minimum Follower Detection Util interface version
local M = {
    PageKey = 'ier_party_barter',
    L10N = 'ier_party_barter',
    Section = 'Settings/ier_party_barter/Party',
    PatchId = 'ier_party_barter',
    PlayerRowId = 'ier_party_barter_player',
    MinIERVersion = 4,
    MinFDUVersion = 5,
}

return M
