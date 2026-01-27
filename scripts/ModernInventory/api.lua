local core = require('openmw.core')
local self = require('openmw.self')
local util = require('openmw.util')
local ui = require('openmw.ui')
local types = require('openmw.types')
local storage = require('openmw.storage')
local input = require('openmw.input')

local helpers = require('scripts.ModernInventory.util.helpers')
local constants = require('scripts.ModernInventory.util.constants')

local windowManager = require('scripts.ModernInventory.ui.windowManager')
local configPlayer = require('scripts.ModernInventory.config.player')

local l10n = core.l10n('ModernInventory')

local API = {}

API.VERSION = 1

API.Constants = constants

API.Templates = {
    BASE = require('scripts.ModernInventory.ui.templates.base'),
    MAGIC = require('scripts.ModernInventory.ui.templates.magic'),
}

API.TooltipBuilders = {
    TEXT = function(params)
        return API.Templates.MAGIC.tooltip(4, ui.content {
            {
                template = API.Templates.BASE.textParagraph,
                props = {
                    size = util.vector2(params.width or 300, 0),
                    text = params.text or '',
                    autoSize = true,
                }
            }
        })
    end,
    ACTIVE_EFFECT = function(effectId)
        return API.Templates.MAGIC.activeEffectTooltip(effectId)
    end,
    SPELL = function(spellId)
        return API.Templates.MAGIC.spellTooltip(spellId)
    end,
    ITEM = function(item)
        return API.Templates.MAGIC.itemTooltip(item)
    end,
}

API.LineBuilders = {
    POWER = function(powerId, editMode)
        local powerRecord = core.magic.spells.records[powerId]
        local override = API.Spells.getCustomSpell(powerId)
        local pinned = API.getStat(API.Constants.TrackedStats.PINNED) or {}
        return {
            id = powerId,
            icon = function()
                if configPlayer.tweaks.b_SpellIcons then
                    return (override and override.effects and override.effects[1].effect.icon) or powerRecord.effects[1].effect.icon
                elseif configPlayer.tweaks.b_PinnedSpellIcons and pinned['powers'] and pinned['powers'][powerId] and not editMode then
                    return 'textures/MagicWindowExtender/pinned_true.dds'
                else
                    return nil
                end
            end,
            label = override and override.name or powerRecord.name,
            value = function()
                if configPlayer.tweaks.b_MarkUsedPowers and not self.type.spells(self):canUsePower(powerId) then
                    return { string = ' ' ..l10n('PowerUsed'), color = API.Constants.Colors.DAMAGED }
                else
                    return { string = '' }
                end
            end,
            active = function()
                local selectedSpell = self.type.getSelectedSpell(self)
                return selectedSpell and selectedSpell.id == powerId
            end,
            disabled = function()
                return configPlayer.tweaks.b_MarkUsedPowers and not self.type.spells(self):canUsePower(powerId)
            end,
            onClick = function()
                if input.isShiftPressed() then
                    API.Templates.MAGIC.tryDelete(powerId)
                    return
                end
                self.type.setSelectedSpell(self, powerRecord)
                API.setDirtyDelayed()
            end,
            tooltip = function()
                return API.TooltipBuilders.SPELL(powerId)
            end,
            editInfo = {
                id = powerId,
                type = 'powers',
                editing = editMode == true,
            }
        }
    end,
    SPELL = function(spellId, editMode)
        local spellRecord = core.magic.spells.records[spellId]
        local override = API.Spells.getCustomSpell(spellId)
        local pinned = API.getStat(API.Constants.TrackedStats.PINNED) or {}
        return {
            id = spellId,
            icon = function()
                if configPlayer.tweaks.b_SpellIcons then
                    return (override and override.effects and override.effects[1].effect.icon) or spellRecord.effects[1].effect.icon
                elseif configPlayer.tweaks.b_PinnedSpellIcons and pinned['spells'] and pinned['spells'][spellId] and not editMode then
                    return 'textures/MagicWindowExtender/pinned_true.dds'
                else
                    return nil
                end
            end,
            label = override and override.name or spellRecord.name,
            value = function()
                local cost, chance = helpers.getModifiedSpellCost(spellId, false), helpers.getSpellCastChance(spellId)
                return { string = tostring(' ' ..util.round(cost)) .. '/' .. tostring(chance) }
            end,
            active = function()
                local selectedSpell = self.type.getSelectedSpell(self)
                return selectedSpell and selectedSpell.id == spellId
            end,
            onClick = function()
                if input.isShiftPressed() then
                    API.Templates.MAGIC.tryDelete(spellId)
                    return
                end
                self.type.setSelectedSpell(self, spellRecord)
                API.setDirtyDelayed()
            end,
            tooltip = function()
                return API.TooltipBuilders.SPELL(spellId)
            end,
            editInfo = {
                id = spellId,
                type = 'spells',
                editing = editMode == true,
            },
        }
    end,
    MAGIC_ITEM = function(item, editMode)
        local itemRecord = item.type.records[item.recordId]
        local label = itemRecord.name
        if item.count and item.count > 1 then
            label = label .. ' (' .. tostring(item.count) .. ')'
        end
        local pinned = API.getStat(API.Constants.TrackedStats.PINNED) or {}
        return {
            id = item.id,
            icon = function()
                if configPlayer.tweaks.b_SpellIcons then
                    local record = API.Spells.getCustomSpell(itemRecord.enchant) or core.magic.enchantments.records[itemRecord.enchant]
                    return record.effects[1].effect.icon
                elseif configPlayer.tweaks.b_PinnedSpellIcons and pinned['magicItems'] and pinned['magicItems'][item.id] and not editMode then
                    return 'textures/MagicWindowExtender/pinned_true.dds'
                else
                    return nil
                end
            end,
            label = label,
            value = function()
                local cost, charge
                if core.magic.enchantments.records[itemRecord.enchant].type == core.magic.ENCHANTMENT_TYPE.CastOnce then
                    cost, charge = 100, 100
                else
                    cost, charge = helpers.getModifiedSpellCost(itemRecord.enchant, true), math.floor(types.Item.itemData(item).enchantmentCharge)
                end
                return { string = tostring(' ' ..util.round(cost)) .. '/' .. tostring(charge) }
            end,
            active = function()
                local selectedItem = self.type.getSelectedEnchantedItem(self)
                return selectedItem and selectedItem.id == item.id
            end,
            disabled = function()
                return not self.type.hasEquipped(self, item)
            end,
            onClick = function()
                self.type.setSelectedEnchantedItem(self, item)
                API.setDirtyDelayed()
            end,
            tooltip = function()
                return API.TooltipBuilders.ITEM(item)
            end,
            editInfo = {
                id = item.id,
                type = 'magicItems',
                editing = editMode == true,
            },
        }
    end,
}

function API.show(staticMode)
    windowManager.show(staticMode)
end

function API.hide(force)
    windowManager.hide(force)
end

function API.toggle(staticMode)
    windowManager.toggle(staticMode)
end

function API.isVisible()
    return windowManager.isVisible()
end

function API.isPinned()
    return windowManager.isPinned()
end

function API.onFrame()
    windowManager.onFrame()
end

function API.onMouseWheel(v, h)
    windowManager.onMouseWheel(v, h)
end

function API.update()
    windowManager.update()
end

function API.trackStat(statId, getter)
    windowManager.trackStat(statId, getter)
end

function API.untrackStat(statId)
    windowManager.untrackStat(statId)
end

function API.setStat(statId, value, forceUpdate)
    if forceUpdate or not helpers.tableEquals(value, windowManager.stats[statId]) then
        windowManager.changedStats[statId] = true
        windowManager.stats[statId] = value
        windowManager.updateTrackedSections()
    end
end

function API.getStat(statId)
    return windowManager.stats[statId]
end

function API.setDirty()
    windowManager.needsRedraw = true
end

function API.setDirtyDelayed()
    windowManager.needsRedrawDelayed = true
end

function API.getWindowElement()
    return windowManager.element
end

local consoleState = false
function API.setConsoleState(state)
    consoleState = state
end

function API.getConsoleState()
    return consoleState
end

return {
    interfaceName = 'ModernInventory',
    interface = API,
    eventHandlers = {
        UiModeChanged = function(data)
            windowManager.onUiModeChanged(data.oldMode, data.newMode, data.arg)
        end,
    },
}