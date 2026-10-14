---@omw-context player

local ui = require('openmw.ui')
local core = require('openmw.core')
local nearby = require('openmw.nearby')
local types = require('openmw.types')
local util = require('openmw.util')
local async = require('openmw.async')
local camera = require('openmw.camera')
local omwself = require('openmw.self')
local v2 = util.vector2
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')
local ambient = require('openmw.ambient')
local input = require('openmw.input')


local helpers = require('scripts.InventoryExtenderRedone.util.helpers')
local constants = require('scripts.InventoryExtenderRedone.util.constants')

local configPlayer = require('scripts.InventoryExtenderRedone.config.player')

local l10n = core.l10n('InventoryExtender')

if not ui.layers.indexOf('DragBlocker') then
    ui.layers.insertBefore('Windows', 'DragBlocker', { interactive = true })
end

local instantPickup = false

local DragAndDrop = {}

local function getViewportRaycastDistance(ctx)
    local dist = core.getGMST("iMaxActivateDist") + camera.getThirdPersonDistance()
    local telekinesis = types.Actor.activeEffects(omwself):getEffect(core.magic.EFFECT_TYPE.Telekinesis)
    if telekinesis then
        dist = dist + (telekinesis.magnitude * 22)
    end
    if ctx.isConsoleOpen then
        dist = dist * 10000
    end
    return dist
end

local function getEligibleDropPosition(result)
    if not result.hitNormal then
        return nil
    end

    local normalLength = result.hitNormal:length()
    if normalLength == 0 then
        return nil
    end

    local up = util.vector3(0, 0, 1)
    local normalizedNormal = result.hitNormal / normalLength
    local dotProduct = math.max(-1, math.min(1, normalizedNormal:dot(up)))
    if math.acos(dotProduct) < math.rad(30) then
        return result.hitPos
    end

    return nil
end

function DragAndDrop:resolveViewportDropTarget(position, callback)
    local pos = camera.getPosition()
    local v = camera.viewportToWorldVector(position)
    local dist = getViewportRaycastDistance(self.ctx)
    return nearby.asyncCastRenderingRay(async:callback(function(result)
        callback(result, getEligibleDropPosition(result))
    end), pos, pos + v * dist, { ignore = omwself })
end

function DragAndDrop:getHoveredGameObject(position)
    return self:resolveViewportDropTarget(position, function(result, hitPos)
        self.hoveredObject = result.hitObject
        self.hitPos = hitPos
    end)
end

function DragAndDrop:startDrag(item, source, count, pickpocket, activationContext)
    self.draggingCount = util.clamp(count or item.count, 1, item.count)
    self.draggingActivationContext = activationContext

    core.sendGlobalEvent('IER_MoveInto', {
        obj = item,
        count = self.draggingCount,
        source = source,
        destination = omwself,
        player = omwself,
        dragStart = true,
        pickpocket = pickpocket,
    })

    self.source = omwself
    if configPlayer.misc.b_TooltipCompatibilityMode then
        self:setWrapperEnabled(true)
    end
end

function DragAndDrop:updatePosition()
    local icon = self.ctx.cursorAttachedIcon
    if not icon then return end
    local props = icon.layout.props
    props.position = I.UIToolkit.getCursorPos()
    props.visible = I.UIToolkit.cursorPosIsFresh()
    I.UIToolkit.update(icon)
end

function DragAndDrop:setDraggingObject(object)
    self.draggingObject = object

    local upSound = helpers.getItemSound(object, 'up')
    if upSound then
        ambient.playSound(upSound)
    end

    if self.ctx.cursorAttachedIcon then
        auxUi.deepDestroy(self.ctx.cursorAttachedIcon)
        self.ctx.cursorAttachedIcon = nil
    end

    if instantPickup then
        self.draggingObject = nil
        instantPickup = false
        return
    end

    self.ctx.cursorAttachedIcon = ui.create({
        name = object.id .. '_dragIcon',
        layer = 'Notification',
        props = {
            size = v2(42, 42),
            position = I.UIToolkit.getCursorPos(),
        },
        content = ui.content {
            {
                name = 'itemShadow',
                type = ui.TYPE.Image,
                props = {
                    position = v2(9, 9),
                    size = v2(32, 32),
                    resource = ui.texture { path = object.type.record(object).icon },
                    color = util.color.rgb(0, 0, 0),
                    alpha = 0.5,
                }
            },
            {
                name = 'item',
                type = ui.TYPE.Image,
                props = {
                    position = v2(5, 5),
                    size = v2(32, 32),
                    resource = ui.texture { path = object.type.record(object).icon },
                }
            },
            {
                template = I.MWUI.templates.textHeader,
                props = {
                    relativePosition = v2(1, 1),
                    anchor = v2(1, 1),
                    autoSize = false,
                    size = v2(32, 18),
                    position = v2(-5, -5),
                    text = helpers.getCountString(self.draggingCount),
                    textShadow = true,
                    textAlignH = ui.ALIGNMENT.End,
                    textAlignV = ui.ALIGNMENT.Center,
                },
            }
        }
    })
end

function DragAndDrop:transferInto(object, destination, source, count, pickpocket)
    if types.Container.objectIsInstance(destination) then
        local destRecord = destination.type.record(destination)
        if destRecord.isOrganic then
            ui.showMessage(constants.Strings.CONTAINER_ORGANIC)
            return false
        end
    end

    if not helpers.doesItemFit(object, destination, count or self.draggingCount) then
        ui.showMessage(core.getGMST('sContentsMessage3')) -- "The item will not fit."
        return false
    end

    local downSound = helpers.getItemSound(object, 'down')
    if downSound then
        ambient.playSound(downSound)
    end

    if count then
        self.draggingCount = util.clamp(count, 1, object.count)
    end

    if source then
        self.source = source
    end

    if destination then
        local uiMode = I.UI.getMode()
        local autoEquip
        if uiMode == 'Companion' and (types.Armor.objectIsInstance(object) or types.Clothing.objectIsInstance(object) or types.Weapon.objectIsInstance(object)) then
            autoEquip = self.ctx.windowArgs['Companion']
        elseif uiMode == 'Container' then
            local target = self.ctx.windowArgs['Container']
            if types.NPC.objectIsInstance(target) then
                autoEquip = target
            end
        end

        core.sendGlobalEvent('IER_MoveInto', {
            obj = object,
            count = self.draggingCount or object.count,
            source = self.source,
            destination = destination,
            player = omwself,
            pickpocket = pickpocket,
            autoEquip = autoEquip,
        })
    end

    return true
end

function DragAndDrop:moveAll(source, destination, items)
    local first = items and items[1] or source.type.inventory(source):getAll()[1]
    if first then
        local upSound = helpers.getItemSound(first, 'up')
        if upSound then
            ambient.playSound(upSound)
        end
    end
    core.sendGlobalEvent('IER_MoveAll', {
        source = source,
        destination = destination,
        player = omwself,
        items = items,
    })
end

-- The library owns the tooltip element, so clear it only when it was made for our hit-test
-- object; otherwise it belongs to a window widget and must stay.
local function clearTooltipIfFor(hitObject)
    if not hitObject then return end
    local tip = I.UTKTooltips.currentTooltip()
    if tip and tip.object == hitObject then
        I.UTKTooltips.setTooltip(nil)
    end
end

function DragAndDrop:stopDrag(target)
    if target and self.draggingObject then
        if not self:transferInto(self.draggingObject, target) then
            return false
        end
    end
    self.draggingObject = nil
    self.draggingCount = nil
    self.draggingActivationContext = nil
    self.source = nil
    clearTooltipIfFor(self.lastHoveredObject)
    if self.ctx.cursorAttachedIcon then
        auxUi.deepDestroy(self.ctx.cursorAttachedIcon)
        self.ctx.cursorAttachedIcon = nil
    end
    if configPlayer.misc.b_TooltipCompatibilityMode then
        self:setWrapperEnabled(false)
    end
end

-- UTKTooltips positions the tooltip itself (cursor-follow or world-object viewport) each frame,
-- so no anchor/position math here. The console line tooltip keeps `object` so clearTooltipIfFor
-- can still match it by identity.
local function createObjectTooltip(hitObject, ctx)
    if types.Item.isCarriable(hitObject) then
        I.UTKTooltips.setTooltip({ object = hitObject, observer = omwself })
    elseif ctx.isConsoleOpen then
        I.UTKTooltips.setTooltip({
            object = hitObject,
            recipe = { items = { { text = '"' .. hitObject.recordId .. '"' } } },
        })
    end
end

function DragAndDrop:dropAt(object, count, position)
    local downSound = helpers.getItemSound(object, 'down')
    if downSound then
        ambient.playSound(downSound)
    end

    core.sendGlobalEvent('IER_Teleport', {
        obj = object,
        count = count or object.count,
        source = self.source or omwself,
        cell = (not omwself.cell.isExterior) and omwself.cell.name or '',
        position = position + util.vector3(0, 0, 0.1),
        options = {
            rotation = util.transform.rotateZ(camera.getYaw()),
        },
        player = omwself,
        dropping = true,
    })

    if configPlayer.misc.b_TooltipCompatibilityMode then
        self:setWrapperEnabled(false)
    end

    omwself:sendEvent('BreakInvisibility')
end

function DragAndDrop:dropAtViewportPosition(object, count, position, fallbackToFeet, callback)
    return self:resolveViewportDropTarget(position, function(_, hitPos)
        if hitPos then
            self:dropAt(object, count, hitPos)
            if callback then
                callback()
            end
            return
        end

        if fallbackToFeet then
            self:dropAtFeet(object, count, callback)
            return
        end

        if callback then
            callback()
        end
    end)
end

function DragAndDrop:dropAtFeet(object, count, callback)
    return nearby.asyncCastRenderingRay(
        async:callback(function(result)
            local targetPos = result.hitPos or omwself.position
            self:dropAt(object, count, targetPos)
            if callback then
                callback()
            end
        end),
        omwself.position + util.vector3(0, 0, omwself:getBoundingBox().halfSize.z),
        omwself.position + util.vector3(0, 0, -100000000000),
        { ignore = omwself }
    )
end

function DragAndDrop:setWrapperEnabled(enabled)
    self.wrapper.layout.props.relativeSize = enabled and v2(1, 1) or v2(0, 0)
    self.wrapper:update()
end

function DragAndDrop:init(ctx)
    self.hoveredObject = nil
    self.lastHoveredObject = nil
    self.draggingObject = nil
    self.draggingActivationContext = nil
    self.source = nil
    self.ctx = ctx

    local pointerProps = {
        relativeSize = v2(0, 0),
        propagateEvents = true,
    }
    I.UIToolkit.Cursors.applyCursor(pointerProps, 'drop_ground')
    self.wrapper = ui.create {
        layer = 'DragBlocker',
        props = {
            relativeSize = v2(0, 0),
            propagateEvents = false,
        },
        content = ui.content {
            {
                name = 'dropPointer',
                props = pointerProps
            }
        }
    }
    self.wrapper.layout.events = {
        mouseMove = async:callback(function(e)
            local layerSize = ui.layers[ui.layers.indexOf('DragBlocker')].size
            self:getHoveredGameObject(v2(e.position.x / layerSize.x, e.position.y / layerSize.y))
            I.UIToolkit.setCursorPos(e.position)
            -- Update tooltip based on hovered object
            if self.draggingObject then
                clearTooltipIfFor(self.lastHoveredObject)
            else
                if self.hoveredObject ~= self.lastHoveredObject then
                    -- Object changed, remake tooltip
                    -- repositions its element every frame.
                    clearTooltipIfFor(self.lastHoveredObject)

                    if self.hoveredObject then
                        createObjectTooltip(self.hoveredObject, self.ctx)
                    end

                    self.lastHoveredObject = self.hoveredObject
                end
            end

            if self.draggingObject and not self.hitPos then
                self.wrapper.layout.content.dropPointer.props.relativeSize = v2(1, 1)
                self.wrapper:update()
            else
                self.wrapper.layout.content.dropPointer.props.relativeSize = v2(0, 0)
                self.wrapper:update()
            end

            if self.ctx.cursorAttachedIcon then
                self.ctx.cursorAttachedIcon.layout.props.visible = true
                self.ctx.cursorAttachedIcon.layout.props.position = e.position
                self.ctx.cursorAttachedIcon:update()
            end
        end),
        focusLoss = async:callback(function()
            clearTooltipIfFor(self.lastHoveredObject)
            self.lastHoveredObject = nil
            if self.ctx.cursorAttachedIcon then
                self.ctx.cursorAttachedIcon.layout.props.visible = false
                self.ctx.cursorAttachedIcon:update()
            end
        end),
        mousePress = async:callback(function(e)
            if e.button ~= 1 then return end
            if self.draggingObject then
                if self.ctx.favoriteItems[self.draggingObject.id] == true then
                    ui.showMessage(l10n('UI_Msg_FavoriteItem'))
                    return
                end

                if not self.hitPos then
                    local object = self.draggingObject
                    local count = self.draggingCount
                    self:dropAtFeet(object, count, function()
                        self:stopDrag()
                        self.wrapper.layout.content.dropPointer.props.relativeSize = v2(0, 0)
                        self.wrapper:update()
                    end)
                    return
                else
                    self:dropAt(self.draggingObject, self.draggingCount, self.hitPos)
                end
                self:stopDrag()
                self.wrapper.layout.content.dropPointer.props.relativeSize = v2(0, 0)
                self.wrapper:update()
            elseif self.hoveredObject then
                if not self.ctx.isConsoleOpen then
                    if types.Item.isCarriable(self.hoveredObject) then
                        self:startDrag(self.hoveredObject, nil)
                        if input.isAltPressed() then
                            instantPickup = true
                        end
                        omwself:sendEvent('BreakInvisibility')
                    end
                else
                    ui.setConsoleSelectedObject(self.hoveredObject)
                end
            end
        end)
    }
end

function DragAndDrop:_onPress()
    if not configPlayer.misc.b_TooltipCompatibilityMode then return end

    self._lastInvState = {}
    local inventory = types.Player.inventory(omwself):getAll()
    for i = 1, #inventory do
        local item = inventory[i]
        self._lastInvState[item.id] = { recordId = item.recordId, count = item.count }
    end
end

function DragAndDrop:_onRelease()
    if not configPlayer.misc.b_TooltipCompatibilityMode then return end

    if not self._lastInvState then return end

    if self.draggingObject then
        self._lastInvState = nil
        return
    end

    local instant = input.isAltPressed()
    local inventory = types.Player.inventory(omwself):getAll()
    for i = 1, #inventory do
        local item = inventory[i]
        local lastState = self._lastInvState[item.id]
        if not lastState or lastState.count < item.count then
            if not instant then
                self.draggingCount = item.count - (lastState and lastState.count or 0)
                self:setDraggingObject(item)
                self:setWrapperEnabled(true)
                self.ctx.cursorAttachedIcon.layout.props.visible = false
            end
            omwself:sendEvent('IER_Update')
            core.sendGlobalEvent('IER_ItemPickedUp', {
                recordId = item.recordId,
                count = item.count - (lastState and lastState.count or 0),
                player = omwself,
            })
            break
        end
    end
    self._lastInvState = nil
end

function DragAndDrop:onMouseButtonPress(button)
    if button == 1 then
        self:_onPress()
    end
end

function DragAndDrop:onMouseButtonRelease(button)
    if button == 1 then
        self:_onRelease()
    end
end

function DragAndDrop:onControllerButtonPress(id)
    if id == input.CONTROLLER_BUTTON.A then
        self:_onPress()
    end
end

function DragAndDrop:onControllerButtonRelease(id)
    if id == input.CONTROLLER_BUTTON.A then
        self:_onRelease()
    end
end

return DragAndDrop
