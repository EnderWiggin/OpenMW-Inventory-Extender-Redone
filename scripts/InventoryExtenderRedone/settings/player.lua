---@omw-context menu
local core = require('openmw.core')
local I = require('openmw.interfaces')
local input = require('openmw.input')

local D = require('scripts.InventoryExtenderRedone.config.defaults')
local H = require 'scripts.UIToolkit.helpers'
local Device = require 'scripts.UIToolkit.config.defaults'.Device
local KEY = input.KEY
local BUTTON = input.CONTROLLER_BUTTON
local l10n = core.l10n(D.L10N)

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
    key = D.Section.Keybinds,
    order = 5,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'ConfigCategoryKeybinds',
    permanentStorage = true,
    settings = {
        {
            key = 'b_SwapUsePickup',
            renderer = 'checkbox',
            name = 'SwapUsePickup',
            description = 'SwapUsePickupDesc',
            default = false,
        },
        {
            key = 'c_Activate',
            renderer = 'UIToolkit/BindCustom',
            name = 'KeybindUseItem',
            description = 'KeybindUseItemDesc',
            default = {
                { device = Device.Controller, code = BUTTON.X },
                { device = Device.Keyboard,   code = KEY.R },
            },
        },
        {
            key = 'c_Favorite',
            renderer = 'UIToolkit/BindCustom',
            name = 'KeybindToggleFavorite',
            description = 'KeybindToggleFavoriteDesc',
            default = {
                { device = Device.Controller, code = BUTTON.Y },
                { device = Device.Keyboard,   code = KEY.F },
            },
        },
        {
            key = 'c_CatPrev',
            renderer = 'UIToolkit/BindCustom',
            name = 'KeybindCatPrev',
            default = {
                { device = Device.Controller, code = BUTTON.LeftShoulder },
                { device = Device.Keyboard,   code = KEY.Z },
            },
        },
        {
            key = 'c_CatNext',
            renderer = 'UIToolkit/BindCustom',
            name = 'KeybindCatNext',
            default = {
                { device = Device.Controller, code = BUTTON.RightShoulder },
                { device = Device.Keyboard,   code = KEY.C },
            },
        },
        {
            key = 'c_SelUp',
            renderer = 'UIToolkit/BindCustom',
            name = 'KeybindSelUp',
            default = {
                { device = Device.Controller, code = BUTTON.DPadUp },
                { device = Device.Keyboard,   code = KEY.W },
            },
        },
        {
            key = 'c_SelDown',
            renderer = 'UIToolkit/BindCustom',
            name = 'KeybindSelDown',
            default = {
                { device = Device.Controller, code = BUTTON.DPadDown },
                { device = Device.Keyboard,   code = KEY.S },
            },
        },
        {
            key = 'c_SelLeft',
            renderer = 'UIToolkit/BindCustom',
            name = 'KeybindSelLeft',
            default = {
                { device = Device.Controller, code = BUTTON.DPadLeft },
                { device = Device.Keyboard,   code = KEY.A },
            },
        },
        {
            key = 'c_SelRight',
            renderer = 'UIToolkit/BindCustom',
            name = 'KeybindSelRight',
            default = {
                { device = Device.Controller, code = BUTTON.DPadRight },
                { device = Device.Keyboard,   code = KEY.D },
            },
        },
    }
}

I.Settings.registerGroup {
    key = D.Section.Window,
    order = 1,
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
            renderer = 'UIToolkit/Dropbox',
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
            renderer = 'UIToolkit/Slider',
            name = 'GridIconScale',
            description = l10n('GridIconScaleDesc', H.mergeTables(H.TextColorParams, D.GridIconScale)),
            default = D.GridIconScale.default,
            ---@type UIToolkit.SettingRenderer.Slider
            argument = {
                min = D.GridIconScale.min,
                max = D.GridIconScale.max,
                default = D.GridIconScale.default,
                step = 0.05,
                roundToStep = true,
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
            renderer = 'UIToolkit/Slider',
            name = 'TableRowHeightMult',
            description = l10n('TableRowHeightMultDesc', H.mergeTables(H.TextColorParams, D.TableRowHeightMult)),
            default = D.TableRowHeightMult.default,
            ---@type UIToolkit.SettingRenderer.Slider
            argument = {
                min = D.TableRowHeightMult.min,
                max = D.TableRowHeightMult.max,
                default = D.TableRowHeightMult.default,
                step = 0.05,
                roundToStep = true,
            }
        },
        {
            key = 'i_TableScrollStep',
            renderer = 'UIToolkit/Slider',
            name = 'TableScrollStep',
            description = l10n('TableScrollStepDesc', H.mergeTables(H.TextColorParams, D.TableScrollStep)),
            default = D.TableScrollStep.default,
            ---@type UIToolkit.SettingRenderer.Slider
            argument = {
                min = D.TableScrollStep.min,
                max = D.TableScrollStep.max,
                default = D.TableScrollStep.default,
                integer = true,
                step = 1,
            }
        },
        {
            key = 's_IconPack',
            renderer = 'UIToolkit/Dropbox',
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
            renderer = 'UIToolkit/Dropbox',
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
    key = D.Section.Tweaks,
    order = 2,
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
    key = D.Section.Integration,
    order = 4,
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
    key = D.Section.Misc,
    order = 6,
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
