---@omw-context player|menu
local async = require('openmw.async')
local storage = require('openmw.storage')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

---@class IER.Config.Player.Keybinds
---@field k_UseItem number
---@field k_ToggleFavorite number
---@field b_SwapUsePickup boolean

---@class IER.Config.Player.Window
---@field b_EnableMod boolean
---@field s_ItemViewMode string
---@field n_GridIconScale number
---@field f_TableRowHeightMult number
---@field i_TableScrollStep number
---@field b_ShowViewModeButton boolean
---@field s_IconPack string
---@field s_CompareItemsMode string
---@field b_SortingBarterReverseEquipped boolean
---@field b_SortingBarterReverseFavorite boolean

---@class IER.Config.Player.Tweaks
---@field b_InvertCategorySwitching boolean
---@field b_CompactCategoryFilter boolean
---@field b_VanillaCategoryIcons boolean
---@field b_CategoryBarBorders boolean
---@field b_StolenIndicator boolean
---@field b_ShowStolenInfo boolean
---@field s_EnchantedIndicatorMode string
---@field b_FilledGemsAppearEnchanted boolean

---@class IER.Config.Player.Integration
---@field b_InterfaceReimagined boolean
---@field b_TooltipsComplete boolean

---@class IER.Config.Player.Misc
---@field b_ShowControllerWarning boolean
---@field b_TooltipCompatibilityMode boolean

---@class IER.Config.Player
---@field keybinds IER.Config.Player.Keybinds
---@field window IER.Config.Player.Window
---@field tweaks IER.Config.Player.Tweaks
---@field modIntegration IER.Config.Player.Integration
---@field misc IER.Config.Player.Misc
---@field onUpdate fun(fn:fun()) register a callback re-run after any section changes

local configPlayer = {}
local updateFns = {}

---@param section openmw.storage.StorageSection
local function subscribe(section, name)
    section:subscribe(async:callback(function()
        configPlayer[name] = section:asTable()
        for i = 1, #updateFns do
            updateFns[i]()
        end
    end))
    configPlayer[name] = section:asTable()
end

subscribe(storage.playerSection(D.Section.Keybinds), 'keybinds')
subscribe(storage.playerSection(D.Section.Window), 'window')
subscribe(storage.playerSection(D.Section.Tweaks), 'tweaks')
subscribe(storage.playerSection(D.Section.Integration), 'modIntegration')
subscribe(storage.playerSection(D.Section.Misc), 'misc')

configPlayer.onUpdate = function(fn)
    table.insert(updateFns, fn)
end

return configPlayer --[[@as IER.Config.Player]]
