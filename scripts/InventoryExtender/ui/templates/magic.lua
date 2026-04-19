local ui = require('openmw.ui')
local auxUi = require('openmw_aux.ui')
local util = require('openmw.util')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local types = require('openmw.types')
local omwself = require('openmw.self')
local async = require('openmw.async')
local ambient = require('openmw.ambient')

local omwConstants = require('scripts.omw.mwui.constants')

local BASE = require('scripts.InventoryExtender.ui.templates.base')
local helpers = require('scripts.InventoryExtender.util.helpers')
local constants = require('scripts.InventoryExtender.util.constants')

local configPlayer = require('scripts.InventoryExtender.config.player')

local v2 = util.vector2

local intRe = configPlayer.modIntegration.b_InterfaceReimagined

local Templates = {}

Templates.HEADER_HEIGHT = 20
Templates.BORDER_WIDTH_TOTAL = 4 * (intRe and 2 or 4)
Templates.TEXT_SIZE = BASE.TEXT_SIZE
Templates.LINE_HEIGHT = Templates.TEXT_SIZE + 2
Templates.SECTION_DIVIDER_HEIGHT = Templates.LINE_HEIGHT
Templates.SECTION_INDENT_L = 12
Templates.SECTION_INDENT_R = 4
Templates.BOX_OUTER_PADDING = 8
Templates.BOX_INNER_PADDING = omwConstants.padding
Templates.BORDER_THICKNESS = omwConstants.border
Templates.MIN_HEIGHT = 4 + 
    Templates.HEADER_HEIGHT + 
    Templates.BORDER_WIDTH_TOTAL + 
    Templates.BOX_OUTER_PADDING * 2 + 
    Templates.BOX_INNER_PADDING * 2 + 
    Templates.LINE_HEIGHT * 3
Templates.MIN_INNER_WIDTH = 60
Templates.MIN_WIDTH = 
    Templates.MIN_INNER_WIDTH + 
    Templates.BORDER_WIDTH_TOTAL + 
    Templates.BOX_OUTER_PADDING * 2

Templates.active = false
Templates.focusedLabel = nil
Templates.linesToProcess = {}
local lastMousePos = nil

Templates.createTexture = BASE.createTexture


Templates.interactive = function(props, layout, ctx)
    local function absToRel(absPos)
        local layerSize = ui.layers[ui.layers.indexOf('Notification')].size
        return v2(
            absPos.x / layerSize.x,
            absPos.y / layerSize.y
        )
    end

    local function createTooltip(layout)
        if ctx.modalElement then
            return nil
        end

        ctx.activeTooltip = ui.create(layout.userData.tooltipFn())
        ctx.activeTooltip.layout.name = props.name
        if lastMousePos then
            ctx.activeTooltip.layout.props.anchor = v2(absToRel(lastMousePos).x, 0)
            ctx.activeTooltip.layout.props.position = v2(lastMousePos.x, lastMousePos.y + 32)
        end
        ctx.activeTooltip:update()
        return ctx.activeTooltip
    end

    local element = layout.layout and layout or ui.create(layout)

    element.layout.userData = element.layout.userData or {}
    element.layout.userData.interactive = true

    element.layout.events = element.layout.events or {}
    element.layout.events.mousePress = async:callback(function(e, layout)
        if e.button ~= 1 then
            return false
        end
        if props.onClick then
            if props.canClick and not props.canClick() then
                return false
            end
            element.layout.userData.pressed = true
            ambient.playSound('menu click')
            helpers.forEachInLayout(element.layout, function(l)
                if l.userData and l.userData.colorable then
                    l.props = l.props or {}
                    if l.type == ui.TYPE.Text or l.type == ui.TYPE.TextEdit then
                        l.props.textColor = helpers.getInteractiveTextColor(layout)
                    elseif l.type == ui.TYPE.Image then
                        l.props.color = helpers.getInteractiveTextColor(element.layout)
                    end
                end
            end)
            element:update()

            if props.parent then
                ctx.updateQueue[props.parent] = true
            end
            return true
        end
        return false
    end)
    element.layout.events.mouseRelease = async:callback(function(e, layout)
        if e.button ~= 1 then
            return false
        end
        if props.onClick then
            if not element.layout.userData.pressed then
                return false
            end
            element.layout.userData.pressed = false
            helpers.forEachInLayout(element.layout, function(l)
                if l.userData and l.userData.colorable then
                    l.props = l.props or {}
                    if l.type == ui.TYPE.Text or l.type == ui.TYPE.TextEdit then
                        l.props.textColor = helpers.getInteractiveTextColor(layout)
                    elseif l.type == ui.TYPE.Image then
                        l.props.color = helpers.getInteractiveTextColor(element.layout)
                    end
                end
            end)
            local result = props.onClick()
            element:update()

            if props.parent then
                ctx.updateQueue[props.parent] = true
            end
            return result
        end
        return false
    end)
    element.layout.events.focusLoss = async:callback(function()
        ctx.focusedInteractive = nil
        element.layout.userData.hovering = false
        if element.layout.userData.tooltipFn then
            if ctx.activeTooltip and ctx.activeTooltip.layout then
                ctx.activeTooltip.layout.props.visible = false
                ctx.updateQueue[ctx.activeTooltip] = true
            end
        end

        if props.onClick then
            helpers.forEachInLayout(element.layout, function(l)
                if l.userData and l.userData.colorable then
                    l.props = l.props or {}
                    if l.type == ui.TYPE.Text or l.type == ui.TYPE.TextEdit then
                        l.props.textColor = helpers.getInteractiveTextColor(layout)
                    elseif l.type == ui.TYPE.Image then
                        l.props.color = helpers.getInteractiveTextColor(element.layout)
                    end
                end
            end)
            ctx.updateQueue[element] = true

            if props.parent then
                ctx.updateQueue[props.parent] = true
            end
        end
        return true
    end)
    element.layout.events.focusGain = async:callback(function(e, layout)
        ctx.focusedInteractive = element
        if props.onClick then
            helpers.forEachInLayout(element.layout, function(l)
                if l.userData and l.userData.colorable then
                    l.props = l.props or {}
                    if l.type == ui.TYPE.Text or l.type == ui.TYPE.TextEdit then
                        l.props.textColor = helpers.getInteractiveTextColor(layout)
                    elseif l.type == ui.TYPE.Image then
                        l.props.color = helpers.getInteractiveTextColor(element.layout)
                    end
                end
            end)
            ctx.updateQueue[element] = true

            if props.parent then
                ctx.updateQueue[props.parent] = true
            end
        end
        return true
    end)
    element.layout.events.mouseMove = async:callback(function(e, layout)
        element.layout.userData.hovering = true
        if element.layout.userData.tooltipFn then
            if not ctx.activeTooltip or not ctx.activeTooltip.layout then
                ctx.activeTooltip = createTooltip(layout)
            elseif ctx.activeTooltip.layout.name ~= props.name then
                auxUi.deepDestroy(ctx.activeTooltip)
                ctx.activeTooltip = createTooltip(layout)
            end
            if ctx.activeTooltip then
                ctx.activeTooltip.layout.props.visible = true
                local distToBottom = ui.layers[ui.layers.indexOf('Notification')].size.y - (e.position.y - e.offset.y)
                if distToBottom < ui.layers[ui.layers.indexOf('Notification')].size.y / 2 then
                    ctx.activeTooltip.layout.props.anchor = v2(absToRel(e.position).x, 1)
                    ctx.activeTooltip.layout.props.position = v2(e.position.x, e.position.y - 32)
                else
                    ctx.activeTooltip.layout.props.anchor = v2(absToRel(e.position).x, 0)
                    ctx.activeTooltip.layout.props.position = v2(e.position.x, e.position.y + 32)
                end
                ctx.activeTooltip:update()
                lastMousePos = e.position
            end
        end
        return true
    end)
    return element
end

Templates.progressBar = function(props)
    props.value = math.floor(props.value or 0)
    props.maxValue = math.floor(props.maxValue or 100)
    props.size = props.size or v2(100, Templates.LINE_HEIGHT)
    props.color = props.color or constants.Colors.RED
    props.textColor = props.textColor or constants.Colors.DEFAULT

    local percentage = props.maxValue ~= 0 and math.min(math.max(props.value / props.maxValue, 0), 1) or 1

    return {
        name = 'value',
        template = I.MWUI.templates.borders,
        props = {
            size = props.size,
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = {
                    relativeSize = v2(percentage, 1),
                    resource = BASE.createTexture('textures/menu_bar_gray.dds'),
                    color = props.color,
                }
            },
            {
                template = BASE.textNormal,
                props = {
                    anchor = v2(0.5, 0.5),
                    relativePosition = v2(0.5, 0.5),
                    text = props.text or tostring(props.value .. '/' .. props.maxValue),
                    textColor = props.textColor,
                    textSize = Templates.TEXT_SIZE,
                }
            },
        }
    }
end

Templates.tooltip = function(padding, content, name)
    return {
        layer = 'Notification',
        name = name,
        template = BASE.boxSolid,
        props = {
        },
        content = ui.content {
            {
                name = 'padding',
                template = BASE.padding(padding),
                content = content or ui.content {},
            }
        }
    }
end

Templates.lineTooltip = function(text, name)
    return Templates.tooltip(4, ui.content {
        {
            template = BASE.textNormal,
            props = {
                text = text or '',
                autoSize = true,
            }
        }
    }, name)
end

local tooltipData = require('scripts.InventoryExtender.interop.tooltips')

Templates.itemTooltip = function(item, showIcon, ctx)
    local function textNormal(name, text)
        return { name = name, template = BASE.textNormal, props = { text = text } }
    end
    local function textHeader(name, text)
        return { name = name, template = BASE.textHeader, props = { text = text } }
    end

    local itemRecord = item.type.record(item)
    local itemData = types.Item.itemData(item)

    local nameString = helpers.getItemName(item)
    if item.count > 1 then
        nameString = nameString .. ' (' .. item.count .. ')'
    end

    local innerContent = ui.content {}

    if not showIcon then
        innerContent:add(textHeader('name', nameString)) 
    else
        innerContent:add({
            name = 'name',
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        size = v2(32, 32),
                        resource = BASE.createTexture(itemRecord.icon),
                    }
                },
                BASE.intervalH(4),
                textHeader('name', nameString),
                BASE.intervalH(4),
            }
        }) 
    end

    innerContent:add(BASE.intervalV(4))

    local conditionString
    local condition = types.Item.itemData(item).condition
    local maxCondition = itemRecord.health
    if condition and maxCondition then
        conditionString = constants.Strings.CONDITION .. ': ' .. util.round(condition) .. '/' .. util.round(maxCondition)
    end

    if types.Armor.objectIsInstance(item) then
        if configPlayer.tweaks.b_CondensedWeightValue then
            local skillString = core.getGMST('sSkill' .. I.Combat.getArmorSkill(item))
            innerContent:add(textNormal('type', constants.Strings.TYPE .. ' ' .. skillString))
        end
        innerContent:add(textNormal('armorRating', constants.Strings.ARMOR_RATING .. ': ' .. math.modf(I.Combat.getEffectiveArmorRating(item, omwself))))
        innerContent:add(textNormal('condition', conditionString))
    end

    if types.Weapon.objectIsInstance(item) then
        local weaponInfo = helpers.getWeaponInfo(item)
        if weaponInfo then
            innerContent:add(textNormal('type', constants.Strings.TYPE .. ' ' .. core.getGMST('sSkill' .. weaponInfo.skill)))
            
            if weaponInfo.class == constants.WeaponClass.Melee then
                local handedString = weaponInfo.isTwoHanded and constants.Strings.TWO_HANDED or constants.Strings.ONE_HANDED
                innerContent.type.props.text = innerContent.type.props.text .. ', ' .. handedString
                innerContent:add(textNormal('chop', constants.Strings.CHOP .. ': ' .. itemRecord.chopMinDamage .. ' - ' .. itemRecord.chopMaxDamage))
                innerContent:add(textNormal('slash', constants.Strings.SLASH .. ': ' .. itemRecord.slashMinDamage .. ' - ' .. itemRecord.slashMaxDamage))
                innerContent:add(textNormal('thrust', constants.Strings.THRUST .. ': ' .. itemRecord.thrustMinDamage .. ' - ' .. itemRecord.thrustMaxDamage))
            else
                local attackMin, attackMax = itemRecord.chopMinDamage, itemRecord.chopMaxDamage
                if weaponInfo.class == constants.WeaponClass.Thrown then
                    attackMin = attackMin * 2
                    attackMax = attackMax * 2
                end
                innerContent:add(textNormal('attack', constants.Strings.ATTACK .. ': ' .. attackMin .. ' - ' .. attackMax)) 
            end

            if weaponInfo.class == constants.WeaponClass.Melee or weaponInfo.class == constants.WeaponClass.Ranged then
                innerContent:add(textNormal('condition', conditionString))
            end

            if weaponInfo.class == constants.WeaponClass.Melee then
                innerContent:add(textNormal('range', constants.Strings.RANGE .. ': ' .. helpers.roundToPlaces(helpers.getWeaponRangeInFeet(item), 1) .. ' ' .. constants.Strings.FEET)) 
            end

            if weaponInfo.class ~= constants.WeaponClass.Ammo then
                innerContent:add(textNormal('speed', constants.Strings.SPEED .. ': ' .. util.round(itemRecord.speed * 100) .. '%')) 
            end
        end
    end

    if itemRecord.maxCondition then
        innerContent:add(textNormal('condition', constants.Strings.USES .. ': ' .. itemData.condition))
    end

    if itemRecord.quality then
        innerContent:add(textNormal('quality', constants.Strings.QUALITY .. ': ' .. helpers.roundToPlaces(itemRecord.quality, 3)))
    end

    if itemRecord.weight > 0 then
        innerContent:add(textNormal('weight', constants.Strings.WEIGHT .. ': ' .. helpers.roundToPlaces(itemRecord.weight, 3)))
        if types.Armor.objectIsInstance(item) then
            local skill = I.Combat.getArmorSkill(item)
            local skillString
            if skill == 'lightarmor' then
                skillString = constants.Strings.LIGHT
            elseif skill == 'mediumarmor' then
                skillString = constants.Strings.MEDIUM
            elseif skill == 'heavyarmor' then
                skillString = constants.Strings.HEAVY
            else
                skillString = core.getGMST('sSkill' .. skill)
            end
            innerContent.weight.props.text = innerContent.weight.props.text .. ' (' .. skillString .. ')'
        end
    end

    local value = helpers.getItemValue(item)
    if value > 0 and itemRecord.id ~= 'gold_001' then
        innerContent:add(textNormal('value', constants.Strings.VALUE .. ': ' .. (value)))
    end

    local enchantment
    local castTypeString
    local doCharge
    local maxCharge
    if itemRecord.enchant then
        enchantment = core.magic.enchantments.records[itemRecord.enchant]
        if enchantment then
            if enchantment.type == core.magic.ENCHANTMENT_TYPE.CastOnStrike then
                castTypeString = constants.Strings.ITEM_CAST_WHEN_STRIKES
                doCharge = true
            elseif enchantment.type == core.magic.ENCHANTMENT_TYPE.CastOnUse then
                castTypeString = constants.Strings.ITEM_CAST_WHEN_USED
                doCharge = true
            elseif enchantment.type == core.magic.ENCHANTMENT_TYPE.CastOnce then
                castTypeString = constants.Strings.ITEM_CAST_ONCE
            elseif enchantment.type == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
                castTypeString = constants.Strings.ITEM_CAST_CONSTANT
            end

            if enchantment.autocalcFlag then
                maxCharge = helpers.getEnchantMaxCharge(enchantment)
            else
                maxCharge = enchantment.charge
            end
        end
    end

    if castTypeString then
        innerContent:add(textNormal('castType', castTypeString))
    end

    -- Handle effects for enchantments, potions, and ingredients
    local effectsToShow = {}
    
    if enchantment then
        -- Enchantment effects
        local override = I.MagicWindow and I.MagicWindow.Spells.getCustomSpell(itemRecord.enchant)
        --effectsToShow = override and override.effects or enchantment.effects
        for i, effect in ipairs(override and override.effects or enchantment.effects) do
            table.insert(effectsToShow, { effect = effect })
        end
    elseif types.Potion.objectIsInstance(item) or types.Ingredient.objectIsInstance(item) then
        -- Potion effects with visibility based on alchemy skill
        local alchemy = omwself.type.stats.skills.alchemy(omwself).base
        local threshold = core.getGMST('fWortChanceValue')
        local visibleEffectCount = math.floor(alchemy / threshold)
        if types.Potion.objectIsInstance(item) then
            visibleEffectCount = visibleEffectCount * 2
        end
        for i, effect in ipairs(itemRecord.effects) do
            table.insert(effectsToShow, {
                effect = effect,
                visible = i <= visibleEffectCount
            })
        end
    end
    
    -- Build effect layouts if we have any effects
    if #effectsToShow > 0 then
        local effectLayouts = {}
        for i, effectData in ipairs(effectsToShow) do
            local effect = effectData.effect
            local isVisible = effectData.visible ~= false
            local content = ui.content {}
            
            if isVisible then
                content:add(Templates.effectIcon(effect.id))
                content:add(BASE.intervalH(4))
                local effectText
                if types.Potion.objectIsInstance(item) then
                    effectText = helpers.createSpellEffectString(effect, false, true)
                elseif types.Ingredient.objectIsInstance(item) then
                    effectText = helpers.getMagicEffectString(effect)
                else
                    -- Enchantment
                    effectText = helpers.createSpellEffectString(effect, enchantment.type == core.magic.ENCHANTMENT_TYPE.ConstantEffect)
                end
                content:add(textNormal('effect_' .. i, effectText))
            else
                content:add(textNormal('effect_' .. i, '?'))
            end
            
            local effectLayout = {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                },
                content = content,
            }
            
            if i ~= 1 then
                table.insert(effectLayouts, BASE.intervalV(8))
            end
            table.insert(effectLayouts, effectLayout)
        end
        
        innerContent:add(BASE.intervalV(4))
        innerContent:add({
            name = 'effects',
            type = ui.TYPE.Flex,
            props = {
                arrange = enchantment and ui.ALIGNMENT.Start or ui.ALIGNMENT.Center,
            },
            content = ui.content {
                table.unpack(effectLayouts)
            }
        })
    end

    if doCharge then
        innerContent:add(BASE.intervalV(8))
        innerContent:add({
            name = 'charge',
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                textNormal(nil, constants.Strings.CHARGE),
                BASE.intervalH(5),
                Templates.progressBar {
                    value = itemData.enchantmentCharge or 0,
                    maxValue = maxCharge,
                    size = v2(204, Templates.LINE_HEIGHT),
                    color = constants.Colors.BAR_HEALTH,
                    textColor = constants.Colors.DEFAULT,
                }
            }
        })
    end

    if configPlayer.modIntegration.b_TooltipsComplete and tooltipData[item.recordId] then
        innerContent:add(BASE.intervalV(12))
        innerContent:add({
            template = I.MWUI.templates.horizontalLine,
            props = {
                size = v2(280, 2),
                position = v2(20, 0),
            }
        })
        innerContent:add(BASE.intervalV(12))
        innerContent:add({
            name = 'lore',
            template = BASE.textParagraph,
            props = {
                text = tooltipData[item.recordId],
                textColor = constants.Colors.DISABLED,
                autoSize = true,
                size = v2(320, 0),
            }
        })
    end

    if configPlayer.tweaks.b_CondensedWeightValue then
        if innerContent:indexOf('weight') then
            innerContent.weight = nil
        end
        if innerContent:indexOf('value') then
            innerContent.value = nil
        end

        local flexContent = ui.content {}

        if value > 0 and itemRecord.id ~= 'gold_001' then
            flexContent:add({
                type = ui.TYPE.Image,
                props = {
                    size = v2(16, 16),
                    resource = BASE.createTexture('icons/gold.dds'),
                }
            })
            flexContent:add(textNormal(nil, ' ' .. util.round(value)))
        end

        if itemRecord.weight > 0 then
            if #flexContent > 0 then
                flexContent:add(BASE.intervalH(4))
            end
            flexContent:add({
                type = ui.TYPE.Image,
                props = {
                    size = v2(16, 16),
                    resource = BASE.createTexture('icons/weight.dds'),
                }
            })
            flexContent:add(textNormal(nil, ' ' .. helpers.roundToPlaces(itemRecord.weight, 2)))
        end

        if #flexContent > 0 then
            local flex = {
                name = 'weightValue',
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    align = ui.ALIGNMENT.End,
                    arrange = ui.ALIGNMENT.Center,
                },
                external = {
                    stretch = 1,
                },
                content = flexContent
            }
            innerContent:add(BASE.intervalV(8))
            innerContent:add(flex)
        end
    end

    if #innerContent == 2 then
        innerContent[2] = nil -- remove extra interval if no details
    end

    local layout = Templates.tooltip(8, ui.content {
        {
            name = 'tooltip',
            type = ui.TYPE.Flex,
            props = {
                align = ui.ALIGNMENT.Center,
                arrange = ui.ALIGNMENT.Center,
            },
            content = innerContent,
        }
    }, item.id)

    if ctx and ctx.tooltipModifiers then
        for _, modifier in ipairs(ctx.tooltipModifiers) do
            layout = modifier.modifier(item, layout) or layout
        end
    end

    return layout
end

Templates.sectionDivider = {
    props = {
        relativeSize = v2(1, 0),
        size = v2(0, Templates.SECTION_DIVIDER_HEIGHT),
    },
    content = ui.content {
        {
            template = I.MWUI.templates.horizontalLine,
            props = {
                anchor = v2(0, 0.5),
                relativePosition = v2(0, 0.5),
                size = v2(-4, 2),
                position = v2(2, 0),
            },
        }
    }
}

Templates.modal = function(content)
    return {
        layer = "Windows",
        props = {
            relativeSize = v2(1, 1), -- Block input for entire layer
        },
        content = ui.content {
            {
                template = BASE.boxSolidThick,
                props = {
                    anchor = v2(0.5, 0.5),
                    relativePosition = v2(0.5, 0.5),
                },
                content = ui.content(content)
            }
        }
    }
end

Templates.choiceModal = function(headerLayout, choices, ctx)
    -- example: choices = { { text = "Yes", onClick = fn }, { text = "No", onClick = fn } }
    local choiceButtons = {}
    for i, choice in ipairs(choices) do
        table.insert(choiceButtons, Templates.interactive({
            onClick = function()
                if ctx.modalElement then
                    auxUi.deepDestroy(ctx.modalElement)
                    ctx.modalElement = nil
                end
                choice.onClick()
            end,
        }, BASE.button(choice.text, choice.onClick), ctx))
        if i ~= #choices then
            table.insert(choiceButtons, BASE.intervalH(8))
        end
    end
    local content = {
        {
            template = BASE.padding(8),
            content = ui.content {
                {
                    name = 'modalContent',
                    type = ui.TYPE.Flex,
                    props = {
                        arrange = ui.ALIGNMENT.Center,
                    },
                    content = ui.content {
                        headerLayout or {},
                        BASE.intervalV(8),
                        {
                            type = ui.TYPE.Flex,
                            props = {
                                horizontal = true,
                                arrange = ui.ALIGNMENT.Center,
                            },
                            content = ui.content {
                                table.unpack(choiceButtons)
                            }
                        }
                    }
                }
            }
        }
    }
    return Templates.modal(content)
end

Templates.effectIcon = function(effectId)
    local effectRecord = core.magic.effects.records[effectId] or (I.MagicWindow and I.MagicWindow.Spells.getCustomEffect(effectId))
    local layout = {
        type = ui.TYPE.Image,
        props = {
            size = v2(16, 16),
            resource = BASE.createTexture(effectRecord.icon),
        },
    }
    return layout
end

return Templates