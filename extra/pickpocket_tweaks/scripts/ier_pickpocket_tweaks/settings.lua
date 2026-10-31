---@omw-context menu
local I = require 'openmw.interfaces'

local D = require('scripts.ier_pickpocket_tweaks.config.defaults')

I.Settings.registerPage {
    key = D.PageKey,
    l10n = D.L10N,
    name = 'PageName',
    description = 'PageDesc',
}

local function slider(key, name, description, knob)
    return {
        key = key,
        renderer = 'UIToolkit/Slider',
        name = name,
        description = description,
        default = knob.default,
        ---@type UIToolkit.SettingRenderer.Slider
        argument = {
            min = knob.min,
            max = knob.max,
            default = knob.default,
            step = knob.step,
            integer = knob.integer,
        },
    }
end

I.Settings.registerGroup {
    key = D.CloseSection,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'CloseGroupName',
    description = 'CloseGroupDesc',
    order = 1,
    permanentStorage = true,
    settings = {
        slider('n_CloseSkillThreshold', 'CloseSkillName', 'CloseSkillDesc', D.CloseSkill),
    },
}

I.Settings.registerGroup {
    key = D.StealSection,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'StealGroupName',
    description = 'StealGroupDesc',
    order = 2,
    permanentStorage = true,
    settings = {
        slider('n_QLPPOwnSkillMult', 'OwnSkillMultName', 'OwnSkillMultDesc', D.OwnSkillMult),
        slider('n_QLPPTargetSkillMult', 'TargetSkillMultName', 'TargetSkillMultDesc', D.TargetSkillMult),
        slider('n_QLPPBaseDifficulty', 'BaseDifficultyName', 'BaseDifficultyDesc', D.BaseDifficulty),
        slider('n_QLPPValueAdd', 'ValueAddName', 'ValueAddDesc', D.ValueAdd),
        slider('n_QLPPValueExp', 'ValueExpName', 'ValueExpDesc', D.ValueExp),
        slider('n_QLPPValueMult', 'ValueMultName', 'ValueMultDesc', D.ValueMult),
        slider('n_QLPPWeightMult', 'WeightMultName', 'WeightMultDesc', D.WeightMult),
    },
}

I.Settings.registerGroup {
    key = D.EquippedSection,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'EquippedGroupName',
    description = 'EquippedGroupDesc',
    order = 3,
    permanentStorage = true,
    settings = {
        slider('n_EquippedSkillThreshold', 'EquippedThresholdName', 'EquippedThresholdDesc', D.EquippedThreshold),
        slider('n_EquippedWeaponBonus', 'EquippedWeaponBonusName', 'EquippedWeaponBonusDesc', D.EquippedWeaponBonus),
        slider('n_EquippedJewelryBonus', 'EquippedJewelryBonusName', 'EquippedJewelryBonusDesc', D.EquippedJewelryBonus),
        slider('n_EquippedArmorBonus', 'EquippedArmorBonusName', 'EquippedArmorBonusDesc', D.EquippedArmorBonus),
    },
}

I.Settings.registerGroup {
    key = D.VisibilitySection,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'VisibilityGroupName',
    description = 'VisibilityGroupDesc',
    order = 4,
    permanentStorage = true,
    settings = {
        slider('n_VisibleChanceThreshold', 'VisibleChanceName', 'VisibleChanceDesc', D.VisibleChance),
    },
}

I.Settings.registerGroup {
    key = D.PlantSection,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'PlantGroupName',
    description = 'PlantGroupDesc',
    order = 5,
    permanentStorage = true,
    settings = {
        {
            key = 'b_PlantDirection',
            renderer = 'checkbox',
            name = 'PlantDirectionName',
            description = 'PlantDirectionDesc',
            default = true,
        },
        slider('n_PlanOwnSkillMult', 'OwnSkillMultName', 'OwnSkillMultDesc', D.PlantOwnSkillMult),
        slider('n_PlanTargetSkillMult', 'TargetSkillMultName', 'TargetSkillMultDesc', D.PlantTargetSkillMult),
        slider('n_PlanBase', 'PlantBaseName', 'PlantBaseDesc', D.PlantBase),
        slider('n_PlanValueAdd', 'PlantValueAddName', 'PlantValueAddDesc', D.PlantValueAdd),
        slider('n_PlanValueExp', 'PlantValueExpName', 'PlantValueExpDesc', D.PlantValueExp),
        slider('n_PlanValueMult', 'PlantValueMultName', 'PlantValueMultDesc', D.PlantValueMult),
        slider('n_PlanWeightMult', 'PlantWeightMultName', 'PlantWeightMultDesc', D.PlantWeightMult),
    },
}

I.Settings.registerGroup {
    key = D.PotionsSection,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'PotionsGroupName',
    description = 'PotionsGroupDesc',
    order = 6,
    permanentStorage = true,
    settings = {
        {
            key = 'b_ShowAllPotions',
            renderer = 'checkbox',
            name = 'ShowAllPotionsName',
            description = 'ShowAllPotionsDesc',
            default = false,
        },
    },
}
