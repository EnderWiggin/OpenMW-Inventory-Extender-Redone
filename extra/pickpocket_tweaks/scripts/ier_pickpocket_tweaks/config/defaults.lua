---@omw-context none

-- bounds feed renderer argument, storage defaults and descriptions

---@class IERPickpocketTweaks.Config.Defaults.Knob
---@field default number
---@field min number
---@field max number
---@field step number?
---@field integer boolean?

---@class IERPickpocketTweaks.Config.Defaults
---@field PageKey string settings page id
---@field L10N string l10n namespace
---@field PatchId string id used for every patchMode call and chain registration
---@field MinIERVersion number minimum Inventory Extender Redone API version
---@field CloseSection string storage section for the close-chance group
---@field StealSection string storage section for the steal-chance formula group
---@field EquippedSection string storage section for the equipped-items group
---@field VisibilitySection string storage section for the visibility group
---@field PlantSection string storage section for the plant-direction group
---@field PotionsSection string storage section for the player-side filter group
---@field CloseSkill IERPickpocketTweaks.Config.Defaults.Knob
---@field OwnSkillMult IERPickpocketTweaks.Config.Defaults.Knob
---@field BaseDifficulty IERPickpocketTweaks.Config.Defaults.Knob
---@field ValueAdd IERPickpocketTweaks.Config.Defaults.Knob
---@field ValueExp IERPickpocketTweaks.Config.Defaults.Knob
---@field ValueMult IERPickpocketTweaks.Config.Defaults.Knob
---@field WeightMult IERPickpocketTweaks.Config.Defaults.Knob
---@field TargetSkillMult IERPickpocketTweaks.Config.Defaults.Knob
---@field EquippedThreshold IERPickpocketTweaks.Config.Defaults.Knob
---@field EquippedWeaponBonus IERPickpocketTweaks.Config.Defaults.Knob
---@field EquippedJewelryBonus IERPickpocketTweaks.Config.Defaults.Knob
---@field EquippedArmorBonus IERPickpocketTweaks.Config.Defaults.Knob
---@field VisibleChance IERPickpocketTweaks.Config.Defaults.Knob
---@field PlantBase IERPickpocketTweaks.Config.Defaults.Knob
---@field PlantValueAdd IERPickpocketTweaks.Config.Defaults.Knob
---@field PlantValueExp IERPickpocketTweaks.Config.Defaults.Knob
---@field PlantValueMult IERPickpocketTweaks.Config.Defaults.Knob
---@field PlantWeightMult IERPickpocketTweaks.Config.Defaults.Knob
local M = {
    PageKey = 'ier_pickpocket_tweaks',
    L10N = 'ier_pickpocket_tweaks',
    PatchId = 'ier_pickpocket_tweaks',
    MinIERVersion = 4,

    Section = {
        General = 'Settings/ier_pickpocket_tweaks/General',
        Steal = 'Settings/ier_pickpocket_tweaks/Steal',
        Plant = 'Settings/ier_pickpocket_tweaks/Plant',
    },

    CloseSkill = { default = 25, min = 0, max = 100, integer = true },
    EquippedThreshold = { default = 90, min = 0, max = 100, integer = true },
    VisibleChance = { default = 10, min = 0, max = 100, integer = true },

    OwnSkillMult = { default = 1.25, min = 0, max = 10, step = 0.05 },
    TargetSkillMult = { default = 0.75, min = 0, max = 10, step = 0.05 },
    BaseDifficulty = { default = 10, min = -100, max = 100, integer = true },
    ValueAdd = { default = 10, min = -100, max = 100, integer = true },
    ValueExp = { default = 2, min = 0.2, max = 4, step = 0.01 },
    ValueMult = { default = 0.5, min = 0, max = 10, step = 0.05 },
    WeightMult = { default = 0.25, min = 0, max = 10, step = 0.05 },

    EquippedWeaponBonus = { default = 55, min = 0, max = 200, integer = true },
    EquippedJewelryBonus = { default = 25, min = 0, max = 200, integer = true },
    EquippedArmorBonus = { default = 45, min = 0, max = 200, integer = true },

    MerchantBonus = { default = 20, min = 0, max = 100, integer = true },
    GuardBonus = { default = 50, min = 0, max = 100, integer = true },


    PlantOwnSkillMult = { default = 1, min = 0, max = 10, step = 0.05 },
    PlantTargetSkillMult = { default = 0.75, min = 0, max = 10, step = 0.05 },
    PlantBase = { default = 25, min = -100, max = 100, integer = true },
    PlantValueAdd = { default = 0, min = -100, max = 100, integer = true },
    PlantValueExp = { default = 1, min = 0, max = 2, step = 0.01 },
    PlantValueMult = { default = 0, min = 0, max = 10, step = 0.05 },
    PlantWeightMult = { default = 10, min = 0, max = 30, step = 0.05 },
}

return M
