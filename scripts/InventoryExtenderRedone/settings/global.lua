---@omw-context global
local I = require('openmw.interfaces')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

I.Settings.registerGroup {
    key = D.Section.Gameplay,
    order = 3,
    page = D.PageKey,
    l10n = D.L10N,
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
        {
            key = 'b_IgnoreChestCapacity',
            renderer = 'checkbox',
            name = 'IgnoreChestCapacity',
            description = 'IgnoreChestCapacityDesc',
            default = false,
        },
    },
}
