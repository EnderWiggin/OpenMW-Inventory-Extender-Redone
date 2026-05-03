local core = require('openmw.core')
local I = require('openmw.interfaces')

local l10n = core.l10n('InventoryExtender')
local versionString = "1.0.0"

local renderers = require('scripts.InventoryExtender.ui.renderers')
local iconPack = require('scripts.InventoryExtender.util.iconPack')

I.Settings.registerRenderer('windowDimensions', renderers.windowDimensions)

-- Settings page
I.Settings.registerPage {
    key = 'InventoryExtender',
    l10n = 'InventoryExtender',
    name = 'ConfigTitle',
    description = l10n('ConfigSummary'):gsub('%%{version}', versionString),
}

I.Settings.registerGroup {
    key = 'Settings/InventoryExtender/2_WindowOptions',
    page = 'InventoryExtender',
    l10n = 'InventoryExtender',
    name = 'ConfigCategoryWindowOptions',
    description = 'RequiresReload',
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
                l10n = 'InventoryExtender',
                items = {
                    'ItemViewMode_Table',
                    'ItemViewMode_Grid',
                },
            }
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
            key = 'i_TextSizeOverride',
            renderer = 'number',
            name = 'TextSizeOverride',
            description = 'TextSizeOverrideDesc',
            default = 0,
            argument = {
                integer = true,
                min = 0,
            }
        },
        {
            key = 's_IconPack',
            renderer = 'select',
            name = 'IconPack',
            description = 'IconPackDesc',
            default = 'base',
            argument = {
                l10n = 'InventoryExtender',
                items = iconPack.getAvailablePacks(),
            }
        },
        {
            key = 'b_InventoryWindowPinned',
            renderer = 'checkbox',
            name = 'InventoryWindowPinned',
            default = false,
        },
        {
            key = 'd_InventoryWindowDimensions',
            renderer = 'windowDimensions',
            name = 'InventoryWindowDimensions',
            default = { x = 0.015, y = 0.54, w = 0.45, h = 0.38, }
        },
        {
            key = 'd_InventoryContainerWindowDimensions',
            renderer = 'windowDimensions',
            name = 'InventoryContainerWindowDimensions',
            default = { x = 0.05, y = 0.05, w = 0.45, h = 0.85, }
        },
        {
            key = 'd_InventoryBarterWindowDimensions',
            renderer = 'windowDimensions',
            name = 'InventoryBarterWindowDimensions',
            default = { x = 0.05, y = 0.05, w = 0.45, h = 0.85, }
        },
        {
            key = 'd_InventoryCompanionWindowDimensions',
            renderer = 'windowDimensions',
            name = 'InventoryCompanionWindowDimensions',
            default = { x = 0.05, y = 0.05, w = 0.45, h = 0.85, }
        },
        {
            key = 'd_ContainerWindowDimensions',
            renderer = 'windowDimensions',
            name = 'ContainerWindowDimensions',
            default = { x = 0.5, y = 0.05, w = 0.45, h = 0.85, }
        },
        {
            key = 'd_BarterWindowDimensions',
            renderer = 'windowDimensions',
            name = 'BarterWindowDimensions',
            default = { x = 0.5, y = 0.05, w = 0.45, h = 0.85, }
        },
        {
            key = 'd_CompanionWindowDimensions',
            renderer = 'windowDimensions',
            name = 'CompanionWindowDimensions',
            default = { x = 0.5, y = 0.05, w = 0.45, h = 0.85, }
        },
    },
}

I.Settings.registerGroup {
    key = 'Settings/InventoryExtender/3_Tweaks',
    page = 'InventoryExtender',
    l10n = 'InventoryExtender',
    name = 'ConfigCategoryTweaks',
    description = 'RequiresReload',
    permanentStorage = true,
    settings = {
        {
            key = 'b_CondensedWeightValue',
            renderer = 'checkbox',
            name = 'CondensedWeightValue',
            description = 'CondensedWeightValueDesc',
            default = true,
        },
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
            default = true,
        },
        {
            key = 'b_VanillaCategoryIcons',
            renderer = 'checkbox',
            name = 'VanillaCategoryIcons',
            description = 'VanillaCategoryIconsDesc',
            default = false,
        },
        {
            key = 'b_CategoryBarBorders',
            renderer = 'checkbox',
            name = 'CategoryBarBorders',
            description = 'CategoryBarBordersDesc',
            default = true,
        },
        {
            key = 's_EnchantedIndicatorMode',
            renderer = 'select',
            name = 'EnchantedIndicatorMode',
            description = 'EnchantedIndicatorModeDesc',
            default = 'EnchantedIndicatorMode_Swirl',
            argument = {
                l10n = 'InventoryExtender',
                items = {
                    'EnchantedIndicatorMode_Swirl',
                    'EnchantedIndicatorMode_Icon',
                    'EnchantedIndicatorMode_Both',
                },
            }
        },
    },
}

I.Settings.registerGroup {
    key = 'Settings/InventoryExtender/4_ModIntegration',
    page = 'InventoryExtender',
    l10n = 'InventoryExtender',
    name = 'ConfigCategoryModIntegration',
    description = 'RequiresReload',
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
    page = 'InventoryExtender',
    l10n = 'InventoryExtender',
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