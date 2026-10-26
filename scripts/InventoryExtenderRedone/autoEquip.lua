---@omw-context local
local types = require('openmw.types')
local self = require('openmw.self')
local core = require('openmw.core')
local I = require('openmw.interfaces')

local helpers = require('scripts.InventoryExtenderRedone.util.helpers')

local NPC = types.NPC
local Item = types.Item
local Actor = types.Actor
local Weapon = types.Weapon
local Armor = types.Armor
local Clothing = types.Clothing

local WeaponType = Weapon.TYPE
local ArmorType = Armor.TYPE
local EQUIPMENT_SLOT = Actor.EQUIPMENT_SLOT

local function getSkillValue(skill)
    if not NPC.objectIsInstance(self) then
        return 0
    end

    local skillGetter = NPC.stats.skills[skill]
    if not skillGetter then
        return 0
    end

    local stat = skillGetter(self)
    return stat and stat.modified or 0
end

local function getItemCondition(item)
    local itemData = Item.itemData(item)
    if itemData and itemData.condition ~= nil and itemData.condition ~= -1 then
        return itemData.condition
    end

    local itemRecord = item.type.record(item)
    return itemRecord.health or itemRecord.maxCondition or itemRecord.duration or 0
end

local function autoEquipWeapon(slots)
    if not NPC.objectIsInstance(self) then
        local services = self.type.record(self).servicesOffered or {}
        if services['Weapon'] or services['MagicItems'] then
            return
        end
    end

    local weaponSkills = {
        'longblade',
        'axe',
        'spear',
        'shortblade',
        'marksman',
        'bluntweapon',
    }

    local weaponSkillVisited = {}
    local arrowMax = 0
    local boltMax = 0
    local bestArrow = nil
    local bestBolt = nil
    local inventory = Actor.inventory(self)

    for _, item in ipairs(inventory:getAll()) do
        if Weapon.objectIsInstance(item) then
            local weaponRecord = item.type.record(item)
            if weaponRecord.type == WeaponType.Arrow then
                if weaponRecord.chopMaxDamage >= arrowMax then
                    arrowMax = weaponRecord.chopMaxDamage
                    bestArrow = item
                end
            elseif weaponRecord.type == WeaponType.Bolt then
                if weaponRecord.chopMaxDamage >= boltMax then
                    boltMax = weaponRecord.chopMaxDamage
                    bestBolt = item
                end
            end
        end
    end

    for _ = 1, #weaponSkills do
        local maxSkill = -1
        local maxWeaponSkill = nil

        for i, skill in ipairs(weaponSkills) do
            local skillValue = getSkillValue(skill)
            if skillValue > maxSkill and not weaponSkillVisited[i] then
                maxSkill = skillValue
                maxWeaponSkill = i
            end
        end

        if not maxWeaponSkill then
            break
        end

        local bestWeapon = nil
        local bestDamage = 0
        for _, item in ipairs(inventory:getAll()) do
            if Weapon.objectIsInstance(item) then
                local weaponInfo = helpers.getWeaponInfo(item)
                local weaponType = item.type.record(item).type
                local damage = helpers.getWeaponDamage(item) or 0
                if weaponInfo
                    and weaponType ~= WeaponType.Arrow
                    and weaponType ~= WeaponType.Bolt
                    and weaponInfo.skill == weaponSkills[maxWeaponSkill] then
                    if damage >= bestDamage then
                        bestDamage = damage
                        bestWeapon = item
                    end
                end
            end
        end

        if bestWeapon then
            local hasAmmo = true
            local weaponRecord = bestWeapon.type.record(bestWeapon)
            if weaponRecord.type == WeaponType.MarksmanBow then
                if bestArrow then
                    slots[EQUIPMENT_SLOT.Ammunition] = bestArrow
                else
                    hasAmmo = false
                end
            elseif weaponRecord.type == WeaponType.MarksmanCrossbow then
                if bestBolt then
                    slots[EQUIPMENT_SLOT.Ammunition] = bestBolt
                else
                    hasAmmo = false
                end
            end

            if hasAmmo then
                slots[EQUIPMENT_SLOT.CarriedRight] = bestWeapon
                if weaponRecord.type ~= WeaponType.MarksmanBow and weaponRecord.type ~= WeaponType.MarksmanCrossbow then
                    slots[EQUIPMENT_SLOT.Ammunition] = nil
                end
                break
            end
        end

        weaponSkillVisited[maxWeaponSkill] = true
    end
end

local function autoEquipArmor(slots)
    local actorIsNpc = NPC.objectIsInstance(self)
    local unarmoredRating = 0

    if actorIsNpc then
        local fUnarmoredBase1 = core.getGMST('fUnarmoredBase1')
        local fUnarmoredBase2 = core.getGMST('fUnarmoredBase2')
        local unarmoredSkill = getSkillValue('unarmored')
        unarmoredRating = math.max((fUnarmoredBase1 * unarmoredSkill) * (fUnarmoredBase2 * unarmoredSkill), 0)
    end

    local function shouldEquipClothing(item, oldItem, slot)
        if not Clothing.objectIsInstance(oldItem) then
            return false
        end

        if slot == EQUIPMENT_SLOT.LeftRing then
            local rightRing = slots[EQUIPMENT_SLOT.RightRing]
            if not rightRing then
                return false
            end
            if helpers.getItemValue(rightRing) <= helpers.getItemValue(oldItem) then
                return false
            end
        end

        return helpers.getItemValue(item) > helpers.getItemValue(oldItem)
    end

    local function shouldEquipArmor(item, oldItem)
        if not Armor.objectIsInstance(oldItem) then
            return true
        end

        if actorIsNpc then
            return (I.Combat.getEffectiveArmorRating(item, self) or 0) >
                (I.Combat.getEffectiveArmorRating(oldItem, self) or 0)
        end
        return getItemCondition(item) > getItemCondition(oldItem)
    end

    -- equipped items are part of inventory():getAll(), so an item already worn in one slot must
    -- not be offered to the sibling slots: a ring in LeftRing would otherwise be re-placed into a
    -- free RightRing and end up equipped twice, which also steals the slot from the next ring
    local function isEquippedElsewhere(item, slot)
        for equippedSlot, equipped in pairs(slots) do
            if equippedSlot ~= slot and equipped == item then
                return true
            end
        end
        return false
    end

    local function processItem(item)
        local isArmor = Armor.objectIsInstance(item)
        local isClothing = actorIsNpc and Clothing.objectIsInstance(item)

        if not (isArmor or isClothing) then
            return
        end

        if isArmor then
            local armorRecord = item.type.record(item)
            if actorIsNpc then
                if (I.Combat.getEffectiveArmorRating(item, self) or 0) <= unarmoredRating then
                    return
                end
            elseif armorRecord.type ~= ArmorType.Shield then
                return
            end
        end

        local itemSlots = helpers.getEquipmentSlots(item) or {}
        for _, slot in ipairs(itemSlots) do
            local oldItem = slots[slot]
            local canEquip = not isEquippedElsewhere(item, slot)

            if canEquip and oldItem then
                if isArmor then
                    canEquip = shouldEquipArmor(item, oldItem)
                else
                    canEquip = shouldEquipClothing(item, oldItem, slot)
                end
            end

            if canEquip then
                slots[slot] = item
                break
            end
        end
    end

    for _, item in ipairs(Actor.inventory(self):getAll()) do
        processItem(item)
    end
end

local function autoEquip(player)
    local slots = Actor.getEquipment(self) --[[@as openmw.types.EquipmentTable]]
    autoEquipWeapon(slots)
    autoEquipArmor(slots)
    Actor.setEquipment(self, slots)

    if player then
        player:sendEvent('IER_Update')
    end
end

return {
    engineHandlers = {
        onInit = function(data)
            autoEquip(data and data.player)
        end,
    },
}
