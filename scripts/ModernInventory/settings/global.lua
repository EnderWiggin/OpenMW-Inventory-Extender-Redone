local core = require('openmw.core')
local I = require('openmw.interfaces')

local l10n = core.l10n('ModernInventory')

I.Settings.registerGroup {
    key = 'Settings/ModernInventory/6_Gameplay',
    page = 'ModernInventory',
    l10n = 'ModernInventory',
    name = 'ConfigCategoryGameplay',
    permanentStorage = true,
    settings = {
        {
            key = 'b_SoulGemValueRebalance',
            renderer = 'checkbox',
            name = 'SoulGemValueRebalance',
            description = 'SoulGemValueRebalanceDesc',
            default = true,
        },
    },
}