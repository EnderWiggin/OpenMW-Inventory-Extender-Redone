---@omw-context player

local I     = require('openmw.interfaces')
local core  = require('openmw.core')
local util  = require('openmw.util')
local v2    = util.vector2
local types = require('openmw.types')
local ui    = require 'openmw.ui'


local C     = require('scripts.InventoryExtenderRedone.util.constants')
local D     = require('scripts.InventoryExtenderRedone.config.defaults')
local Roles = D.Roles
local Modes = D.Modes
local l10n  = core.l10n(D.L10N)


local Toolkit    = I.UIToolkit
local Components = Toolkit.Components
local T          = Toolkit.Templates
local Armor      = types.Armor
local Clothing   = types.Clothing
local Weapon     = types.Weapon
local NPC        = types.NPC
local Creature   = types.Creature
local NPCSkills  = NPC.stats.skills

---@return {name:string, get:fun(obj:openmw.Object):openmw.types.SkillStat}[]
local function makeSkillList(...)
    local ids = { ... }
    local result = {}
    for i = 1, #ids do
        local id = ids[i]
        result[#result + 1] = {
            name = core.stats.Skill.records[id].name,
            get = NPCSkills[id],
        }
    end
    return result
end

local WEAPON = makeSkillList('axe', 'bluntweapon', 'longblade', 'marksman', 'shortblade', 'spear')
local ARMOR = makeSkillList('block', 'heavyarmor', 'lightarmor', 'mediumarmor', 'unarmored')
local MAGIC = makeSkillList('alteration', 'conjuration', 'destruction', 'illusion', 'mysticism', 'restoration')


local closePopup
local function tryClosePopup()
    if not closePopup then return end
    closePopup()
    closePopup = nil
end

---@param name string
---@param skills {name:string, get:fun(obj:openmw.Object):openmw.types.SkillStat}[]
---@param target openmw.Object
---@return openmw.ui.Layout
local function makePane(name, skills, target)
    ---@type openmw.ui.Layout[]
    local content = { {
        template = T.header(),
        props = { text = name },
    } }

    local values = {}
    for i = 1, #skills do
        local skill = skills[i]
        values[#values + 1] = { name = skill.name, value = skill.get(target).modified }
    end

    table.sort(values, function(a, b)
        if a.value == b.value then
            return a.name > b.name
        end
        return a.value > b.value
    end)

    for i = 1, #values do
        local skill = values[i]
        content[#content + 1] = {
            template = T.text(),
            props = { text = skill.name .. ': ' .. skill.value },
        }
    end

    return {
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
        },
        content = ui.content(content),
    }
end

---@param companion openmw.Object
local function showStatsPopup(companion)
    tryClosePopup()
    if not NPC.objectIsInstance(companion) then
        ui.showMessage 'Implemented for NPC only for now!'
        return
    end

    local panes = {
        makePane(l10n 'Category_Weapon', WEAPON, companion),
        T.intervalH(8),
        makePane(l10n 'Category_Armor', ARMOR, companion),
        T.intervalH(8),
        makePane(l10n 'Category_Magic', MAGIC, companion),
    }
    --TODO: add known spells?


    closePopup = Toolkit.Popups.show {
        title = NPC.records[companion.recordId].name,
        body = {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
            },
            content = ui.content(panes),
        },
        buttons = { { text = C.Strings.CLOSE } },
    }
end


-- Transferring to a companion: the player's window plus the companion's window.
---@type InventoryExtenderRedone.Mode
return {
    key = Modes.Companion,
    priority = 1,
    -- the Companion window is only ever opened by a companion transfer; the player's window is in
    -- this mode while the engine sits in Companion
    applies = function(role, arg, ctx, uiMode)
        if role == Roles.Companion then
            return true
        end
        return role == Roles.Inventory and uiMode == Modes.Companion
    end,
    drag = {
        allowed = true,
        -- a companion auto-equips armor/clothing/weapons it receives: this used to read the
        -- engine's Companion mode at transfer time, the mode spec decides it now, keyed by
        -- the mode that started the transfer
        autoEquip = function(ctx, object, source, destination)
            if Armor.objectIsInstance(object) or Clothing.objectIsInstance(object) or Weapon.objectIsInstance(object) then
                return ctx.windowArgs[D.Roles.Companion]
            end
        end,
    },
    roles = {
        [Roles.Inventory] = {
            storageSuffix = ':Companion',
            defaultStorage = { position = v2(0.05, 0.05), size = v2(0.45, 0.85) },
            sources = { { id = 'target' } },
            actions = {
                use = { id = 'usePlayer' },
                pickup = { id = 'pickupCompanionInventory' },
            },
            -- the player's window during a companion transfer: same strip as the interface
            infoBar = {
                { id = 'encumbrance' },
                { id = 'gold' },
                { id = 'armorRating' },
                { id = 'filler' },
                { id = 'use' },
            },
        },
        [Roles.Companion] = {
            sources = { { id = 'target' } },
            actions = {
                use = { id = 'useTarget' },
                pickup = { id = 'pickupCompanionTarget' },
            },
            -- the companion's strip: weight, the gap, what it gained from the player, close (no gold:
            -- the original added gold only for the Inventory and Trade roles)
            infoBar = {
                { id = 'encumbrance' },
                { id = 'armorRating' },
                { id = 'filler' },
                { id = 'profit' },
                -- relevant companion stats
                {
                    id = 'companionStats',
                    create = function(handler, _)
                        local theme = Toolkit.getTheme()
                        local btn = Components.textButton {
                            name = 'stats',
                            style = theme.IntRe and 'empty' or 'thin',
                            text = C.Strings.STATS,
                            onClick = function()
                                showStatsPopup(handler.arg)
                            end,
                            tooltip = l10n 'UI_Tooltip_Companion_Stats',
                        }
                        return function(_)
                            return btn.element
                        end
                    end,
                    cleanup = tryClosePopup,
                },
                { id = 'close' },
            },
        },
    },
}
