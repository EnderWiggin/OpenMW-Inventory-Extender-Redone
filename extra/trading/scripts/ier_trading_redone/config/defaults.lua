---@omw-context none

-- bounds feed renderer argument, storage defaults and descriptions

---@class IERTrading.Config.Defaults.Skill
---@field default number
---@field min number
---@field max number

---@class IERTrading.Config.Defaults
---@field PageKey string settings page id
---@field L10N string l10n namespace
---@field Section string storage section holding the two skill thresholds
---@field InvestSkill IERTrading.Config.Defaults.Skill
---@field AllItemsSkill IERTrading.Config.Defaults.Skill
local M = {
    PageKey = 'ier_trading_redone',
    L10N = 'ier_trading_redone',
    Section = 'Settings/ier_trading_redone/Mercantile',
    InvestSkill = { default = 25, min = 1, max = 100 },
    AllItemsSkill = { default = 90, min = 1, max = 100 },
}

return M
