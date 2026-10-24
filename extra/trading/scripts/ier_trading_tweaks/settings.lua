---@omw-context menu
local I = require 'openmw.interfaces'

local D = require('scripts.ier_trading_tweaks.config.defaults')

I.Settings.registerPage {
    key = D.PageKey,
    l10n = D.L10N,
    name = 'PageName',
    description = 'PageDesc',
}

I.Settings.registerGroup {
    key = D.Section,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'SettingsName',
    description = 'SettingsDesc',
    order = 1,
    permanentStorage = true,
    settings = {
        {
            key = 'i_InvestSkillRequirement',
            renderer = 'UIToolkit/Slider',
            name = 'InvestSkillName',
            description = 'InvestSkillDesc',
            default = D.InvestSkill.default,
            ---@type UIToolkit.SettingRenderer.Slider
            argument = {
                min = D.InvestSkill.min,
                max = D.InvestSkill.max,
                default = D.InvestSkill.default,
                integer = true,
                step = 1,
            }
        },
        {
            key = 'i_AllItemsSkillRequirement',
            renderer = 'UIToolkit/Slider',
            name = 'AllItemsSkillName',
            description = 'AllItemsSkillDesc',
            default = D.AllItemsSkill.default,
            ---@type UIToolkit.SettingRenderer.Slider
            argument = {
                min = D.AllItemsSkill.min,
                max = D.AllItemsSkill.max,
                default = D.AllItemsSkill.default,
                integer = true,
                step = 1,
            }
        },
    },
}
