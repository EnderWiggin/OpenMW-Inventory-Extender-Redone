local core = require('openmw.core')
local input = require('openmw.input')
local I = require('openmw.interfaces')

local l10n = core.l10n('ModernInventory')
local versionString = "1.0.0"

local renderers = require('scripts.ModernInventory.ui.renderers')

I.Settings.registerRenderer('windowDimensions', renderers.windowDimensions)

-- Settings page
I.Settings.registerPage {
    key = 'ModernInventory',
    l10n = 'ModernInventory',
    name = 'ConfigTitle',
    description = l10n('ConfigSummary'):gsub('%%{version}', versionString),
}

I.Settings.registerGroup {
    key = 'Settings/ModernInventory/2_WindowOptions',
    page = 'ModernInventory',
    l10n = 'ModernInventory',
    name = 'ConfigCategoryWindowOptions',
    description = 'RequiresReload',
    permanentStorage = true,
    settings = {
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
            default = {
                x = 0.015,
                y = 0.54,
                w = 0.45,
                h = 0.38,
            }
        },
        {
            key = 'd_BarterInventoryWindowDimensions',
            renderer = 'windowDimensions',
            name = 'BarterInventoryWindowDimensions',
            default = {
                x = 0.015,
                y = 0.54,
                w = 0.45,
                h = 0.38,
            }
        },
    },
}

I.Settings.registerGroup {
    key = 'Settings/ModernInventory/3_Tweaks',
    page = 'ModernInventory',
    l10n = 'ModernInventory',
    name = 'ConfigCategoryTweaks',
    description = 'RequiresReload',
    permanentStorage = true,
    settings = {
    },
}

I.Settings.registerGroup {
    key = 'Settings/ModernInventory/4_ModIntegration',
    page = 'ModernInventory',
    l10n = 'ModernInventory',
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
    },
}

I.Settings.registerGroup {
    key = 'Settings/ModernInventory/5_Misc',
    page = 'ModernInventory',
    l10n = 'ModernInventory',
    name = 'ConfigCategoryMisc',
    permanentStorage = true,
    settings = {
        {
            key = 'b_ShowControllerWarning',
            renderer = 'checkbox',
            name = 'ShowControllerWarning',
            description = 'ShowControllerWarningDesc',
            default = true,
        }
    },
}