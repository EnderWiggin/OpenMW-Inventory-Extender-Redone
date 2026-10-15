---@omw-context menu
local core = require('openmw.core')
local I = require('openmw.interfaces')
local input = require('openmw.input')

local l10n = core.l10n('InventoryExtender')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

local renderers = require('scripts.InventoryExtenderRedone.ui.renderers')
local iconPack = require('scripts.InventoryExtenderRedone.util.iconPack')
local C = require('scripts.InventoryExtenderRedone.util.constants')

I.Settings.registerRenderer('InventoryExtender/inputKeySelection', renderers.inputKey)

-- Settings page
I.Settings.registerPage {
    key = D.PageKey,
    l10n = D.L10N,
    name = 'ConfigTitle',
    description = l10n('ConfigSummary'):gsub('%%{version}', D.Version),
}

I.Settings.registerGroup {
    key = 'Settings/InventoryExtender/1_Keybinds',
    page = D.PageKey,
    l10n = D.L10N,
    name = 'ConfigCategoryKeybinds',
    permanentStorage = true,
    settings = {
        {
            key = 'k_UseItem',
            renderer = 'InventoryExtender/inputKeySelection',
            name = 'KeybindUseItem',
            description = 'KeybindUseItemDesc',
            default = input.KEY.R
        },
        {
            key = 'b_SwapUsePickup',
            renderer = 'checkbox',
            name = 'SwapUsePickup',
            description = 'SwapUsePickupDesc',
            default = false,
        },
        {
            key = 'k_ToggleFavorite',
            renderer = 'InventoryExtender/inputKeySelection',
            name = 'KeybindToggleFavorite',
            description = 'KeybindToggleFavoriteDesc',
            default = input.KEY.F,
        },
    }
}

I.Settings.registerGroup {
    key = 'Settings/InventoryExtender/2_WindowOptions',
    page = D.PageKey,
    l10n = D.L10N,
    name = 'ConfigCategoryWindowOptions',
    permanentStorage = true,
    settings = {
        {
            key = 'b_EnableMod',
            renderer = 'checkbox',
            name = 'EnableMod',
            default = true,
        },
        {
            key = 's_ItemViewMode',
            renderer = 'select',
            name = 'ItemViewMode',
            description = 'ItemViewModeDesc',
            default = 'ItemViewMode_Table',
            argument = {
                l10n = D.L10N,
                items = {
                    'ItemViewMode_Table',
                    'ItemViewMode_Grid',
                },
            }
        },
        {
            key = 'n_GridIconScale',
            renderer = 'number',
            name = 'GridIconScale',
            description = 'GridIconScaleDesc',
            default = 1,
            argument = {
                min = 0.2,
                max = 5,
            }
        },
        {
            key = 'b_ShowViewModeButton',
            renderer = 'checkbox',
            name = 'ShowViewModeButton',
            description = 'ShowViewModeButtonDesc',
            default = true,
        },
        {
            key = 'f_TableRowHeightMult',
            renderer = 'number',
            name = 'TableRowHeightMult',
            description = 'TableRowHeightMultDesc',
            default = 1,
            argument = {
                min = 0.1,
            }
        },
        {
            key = 'i_TableScrollStep',
            renderer = 'number',
            name = 'TableScrollStep',
            description = 'TableScrollStepDesc',
            default = 2,
            argument = {
                min = 0.1,
            }
        },
        {
            key = 's_IconPack',
            renderer = 'select',
            name = 'IconPack',
            description = 'IconPackDesc',
            default = 'Base',
            argument = {
                l10n = D.L10N,
                items = iconPack.getAvailablePacks(),
            }
        },
        {
            key = C.OPT_KEYS.CompareItemsMode,
            renderer = 'select',
            name = 'ConfigCompareItemsMode',
            description = 'ConfigCompareItemsModeDesc',
            default = C.COMPARISON_OPTS.Never,
            argument = {
                l10n = D.L10N,
                items = { C.COMPARISON_OPTS.Never, C.COMPARISON_OPTS.ALT, C.COMPARISON_OPTS.Always },
            }
        },
        {
            key = C.OPT_KEYS.SortingBarterReverseEquipped,
            renderer = 'checkbox',
            name = 'ConfigSortingBarterReverseEquipped',
            default = false,
        },
        {
            key = C.OPT_KEYS.SortingBarterReverseFavorite,
            renderer = 'checkbox',
            name = 'ConfigSortingBarterReverseFavorite',
            default = false,
        },
    },
}

I.Settings.registerGroup {
    key = 'Settings/InventoryExtender/3_Tweaks',
    page = D.PageKey,
    l10n = D.L10N,
    name = 'ConfigCategoryTweaks',
    permanentStorage = true,
    settings = {
        {
            key = 'b_InvertCategorySwitching',
            renderer = 'checkbox',
            name = 'InvertCategorySwitching',
            description = 'InvertCategorySwitchingDesc',
            default = false,
        },
        {
            key = 'b_CompactCategoryFilter',
            renderer = 'checkbox',
            name = 'CompactCategoryFilter',
            description = 'CompactCategoryFilterDesc',
            default = false,
        },
        {
            key = 'b_VanillaCategoryIcons',
            renderer = 'checkbox',
            name = 'VanillaCategoryIcons',
            description = 'VanillaCategoryIconsDesc',
            default = true,
        },
        {
            key = 'b_CategoryBarBorders',
            renderer = 'checkbox',
            name = 'CategoryBarBorders',
            description = 'CategoryBarBordersDesc',
            default = true,
        },
        {
            key = 'b_StolenIndicator',
            renderer = 'checkbox',
            name = 'StolenIndicator',
            description = 'StolenIndicatorDesc',
            default = true,
        },
        {
            key = 'b_ShowStolenInfo',
            renderer = 'checkbox',
            name = 'ShowStolenInfo',
            description = 'ShowStolenInfoDesc',
            default = true,
        },
        {
            key = 's_EnchantedIndicatorMode',
            renderer = 'select',
            name = 'EnchantedIndicatorMode',
            description = 'EnchantedIndicatorModeDesc',
            default = 'EnchantedIndicatorMode_Swirl',
            argument = {
                l10n = D.L10N,
                items = {
                    'EnchantedIndicatorMode_Swirl',
                    'EnchantedIndicatorMode_Icon',
                    'EnchantedIndicatorMode_Both',
                },
            }
        },
        {
            key = 'b_FilledGemsAppearEnchanted',
            renderer = 'checkbox',
            name = 'FilledGemsAppearEnchanted',
            description = 'FilledGemsAppearEnchantedDesc',
            default = true,
        },
    },
}

I.Settings.registerGroup {
    key = 'Settings/InventoryExtender/4_ModIntegration',
    page = D.PageKey,
    l10n = D.L10N,
    name = 'ConfigCategoryModIntegration',
    permanentStorage = true,
    settings = {
        {
            key = 'b_InterfaceReimagined',
            renderer = 'checkbox',
            name = 'InterfaceReimagined',
            description = 'InterfaceReimaginedDesc',
            default = false,
        },
        {
            key = 'b_TooltipsComplete',
            renderer = 'checkbox',
            name = 'TooltipsComplete',
            description = 'TooltipsCompleteDesc',
            default = true,
        }
    },
}

I.Settings.registerGroup {
    key = 'Settings/InventoryExtender/5_Misc',
    page = D.PageKey,
    l10n = D.L10N,
    name = 'ConfigCategoryMisc',
    permanentStorage = true,
    settings = {
        {
            key = 'b_ShowControllerWarning',
            renderer = 'checkbox',
            name = 'ShowControllerWarning',
            description = 'ShowControllerWarningDesc',
            default = true,
        },
        {
            key = 'b_TooltipCompatibilityMode',
            renderer = 'checkbox',
            name = 'TooltipCompatibilityMode',
            description = 'TooltipCompatibilityModeDesc',
            default = false,
        }
    },
}
