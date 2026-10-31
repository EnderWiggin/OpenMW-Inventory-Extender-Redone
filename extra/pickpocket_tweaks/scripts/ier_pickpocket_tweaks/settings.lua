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
    key = D.Section.General,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'GeneralGroupName',
    description = 'GeneralGroupDesc',
    order = 1,
    permanentStorage = true,
    settings = {
        slider('closeSkillThreshold', 'CloseSkillName', 'CloseSkillDesc', D.CloseSkill),
        slider('equippedThreshold', 'EquippedThresholdName', 'EquippedThresholdDesc', D.EquippedThreshold),
        slider('visibleChanceThreshold', 'VisibleChanceName', 'VisibleChanceDesc', D.VisibleChance),
    },
}

I.Settings.registerGroup {
    key = D.Section.Steal,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'StealGroupName',
    description = 'StealGroupDesc',
    order = 2,
    permanentStorage = true,
    settings = {
        slider('ownSkillMult', 'OwnSkillMultName', 'OwnSkillMultDesc', D.OwnSkillMult),
        slider('targetSkillMult', 'TargetSkillMultName', 'TargetSkillMultDesc', D.TargetSkillMult),
        slider('baseDifficulty', 'BaseDifficultyName', 'BaseDifficultyDesc', D.BaseDifficulty),
        slider('valueAdd', 'ValueAddName', 'ValueAddDesc', D.ValueAdd),
        slider('valueExp', 'ValueExpName', 'ValueExpDesc', D.ValueExp),
        slider('valueMult', 'ValueMultName', 'ValueMultDesc', D.ValueMult),
        slider('weightMult', 'WeightMultName', 'WeightMultDesc', D.WeightMult),
        slider('equippedWeaponBonus', 'EquippedWeaponBonusName', 'EquippedWeaponBonusDesc', D.EquippedWeaponBonus),
        slider('equippedJewelryBonus', 'EquippedJewelryBonusName', 'EquippedJewelryBonusDesc', D.EquippedJewelryBonus),
        slider('equippedArmorBonus', 'EquippedArmorBonusName', 'EquippedArmorBonusDesc', D.EquippedArmorBonus),
        slider('merchantBonus', 'MerchantBonusName', 'MerchantBonusDesc', D.MerchantBonus),
        slider('guardBonus', 'GuardBonusName', 'GuardBonusDesc', D.GuardBonus),
    },
}

I.Settings.registerGroup {
    key = D.Section.Plant,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'PlantGroupName',
    description = 'PlantGroupDesc',
    order = 3,
    permanentStorage = true,
    settings = {
        {
            key = 'enabled',
            renderer = 'checkbox',
            name = 'AllowPoisonName',
            description = 'AllowPoisonDesc',
            default = true,
        },
        {
            key = 'hideOther',
            renderer = 'checkbox',
            name = 'HideOtherName',
            description = 'HideOtherDesc',
            default = true,
        },
        slider('ownSkillMult', 'OwnSkillMultName', 'OwnSkillMultDesc', D.PlantOwnSkillMult),
        slider('targetSkillMult', 'TargetSkillMultName', 'TargetSkillMultDesc', D.PlantTargetSkillMult),
        slider('baseDifficulty', 'PlantBaseName', 'PlantBaseDesc', D.PlantBase),
        slider('weightMult', 'PlantWeightMultName', 'PlantWeightMultDesc', D.PlantWeightMult),
    },
}
