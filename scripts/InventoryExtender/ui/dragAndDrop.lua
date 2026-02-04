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

local baseTemplates = require('scripts.InventoryExtender.ui.templates.base')
local specialTemplates = require('scripts.InventoryExtender.ui.templates.magic')

local helpers = require('scripts.InventoryExtender.util.helpers')
local constants = require('scripts.InventoryExtender.util.constants')

local configPlayer = require('scripts.InventoryExtender.config.player')

if not ui.layers.indexOf('DragBlocker') then
    ui.layers.insertBefore('Windows', 'DragBlocker', { interactive = true })
end

local DragAndDrop = {}

function DragAndDrop:getHoveredGameObject(position)
    local pos = camera.getPosition()
    local v = camera.viewportToWorldVector(position)
	local dist = core.getGMST("iMaxActivateDist") + camera.getThirdPersonDistance()
    local telekinesis = types.Actor.activeEffects(omwself):getEffect(core.magic.EFFECT_TYPE.Telekinesis)
    if telekinesis then
        dist = dist + (telekinesis.magnitude * 22)
    end
    if self.ctx.isConsoleOpen then
        dist = dist * 10000
    end
	return nearby.asyncCastRenderingRay(async:callback(function(result)
        self.hoveredObject = result.hitObject
        if result.hitNormal then
            local up = util.vector3(0, 0, 1)
            local normalLength = result.hitNormal:length()
            local normalizedNormal = result.hitNormal / normalLength
            local dotProduct = normalizedNormal:dot(up)
            
            if math.acos(dotProduct) < math.rad(30) then
                self.hitPos = result.hitPos
            else
                self.hitPos = nil
            end
        else
            self.hitPos = nil
        end
    end), pos, pos + v * dist)
end

function DragAndDrop:startDrag(item, source, count)
    local upSound = helpers.getItemSound(item, 'up')
    if upSound then
        ambient.playSound(upSound)
    end

    self.draggingCount = util.clamp(count or item.count, 1, item.count)

    core.sendGlobalEvent('MI_MoveInto', {
        obj = item,
        count = self.draggingCount,
        source = source,
        destination = omwself,
        player = omwself,
        dragStart = true,
    })   
    
    self.source = omwself
end

function DragAndDrop:setDraggingObject(object, resetMode)
    self.draggingObject = object

    if self.ctx.cursorAttachedIcon then
        auxUi.deepDestroy(self.ctx.cursorAttachedIcon)
        self.ctx.cursorAttachedIcon = nil
    end
    self.ctx.cursorAttachedIcon = ui.create({
        name = object.id .. '_dragIcon',
        layer = 'Notification',
        props = {
            size = v2(42, 42),
            position = self.ctx.lastCursorPos or v2(0, 0),
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = {
                    size = v2(42, 42),
                    resource = ui.texture { path = object.type.record(object).icon },
                }
            },
            {
                template = baseTemplates.textNormal,
                props = {
                    anchor = v2(1, 1),
                    relativePosition = v2(1, 1),
                    text = self.draggingCount > 1 and tostring(self.draggingCount) or '',
                    textColor = constants.Colors.DEFAULT_LIGHT,
                    textShadow = true,
                },
            }
        }
    })

    if resetMode then
        local mode = I.UI.getMode()
        local modeArgs = self.ctx.modeArgs[mode] and { target = self.ctx.modeArgs[mode] } or nil
        self.ctx.resettingMode = true
        I.UI.removeMode(mode)
        I.UI.addMode(mode, modeArgs)
    end
end

function DragAndDrop:transferInto(object, destination, source, count)
    if types.Container.objectIsInstance(destination) then
        local destRecord = destination.type.record(destination)
        if destRecord.isOrganic then
            ui.showMessage(constants.Strings.CONTAINER_ORGANIC)
            return false
        end
    end
    
    if not helpers.doesItemFit(object, destination) then
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
        core.sendGlobalEvent('MI_MoveInto', {
            obj = object,
            count = self.draggingCount or object.count,
            source = self.source,
            destination = destination,
            player = omwself,
        })
    end

    return true
end

function DragAndDrop:moveAll(source, destination)
    local first = source.type.inventory(source):getAll()[1]
    if first then
        local upSound = helpers.getItemSound(first, 'up')
        if upSound then
            ambient.playSound(upSound)
        end
    end
    core.sendGlobalEvent('MI_MoveAll', {
        source = source,
        destination = destination,
        player = omwself,
    })
end

function DragAndDrop:stopDrag(target)
    if target and self.draggingObject then
        if not self:transferInto(self.draggingObject, target) then
            return false
        end
    end
    self.draggingObject = nil
    self.draggingCount = nil
    self.source = nil
    if self.ctx.activeTooltip and self.ctx.activeTooltip.layout then
        self.ctx.activeTooltip.layout.props.visible = false
        self.ctx.activeTooltip:update()
    end
    if self.ctx.cursorAttachedIcon then
        auxUi.deepDestroy(self.ctx.cursorAttachedIcon)
        self.ctx.cursorAttachedIcon = nil
    end
end

local function absToRel(absPos)
    local layerSize = ui.layers[ui.layers.indexOf('DragBlocker')].size
    return v2(
        absPos.x / layerSize.x,
        absPos.y / layerSize.y
    )
end

local function createObjectTooltip(hitObject, position, ctx)
    -- Check if it's an item
    if types.Item.isCarriable(hitObject) then
        ctx.activeTooltip = ui.create(specialTemplates.itemTooltip(hitObject, true, ctx))
    elseif ctx.isConsoleOpen then
        ctx.activeTooltip = ui.create(specialTemplates.lineTooltip('"' .. hitObject.recordId .. '"', hitObject.id))
    end
    
    if ctx.activeTooltip then
        ctx.activeTooltip.layout.name = hitObject.id
        ctx.activeTooltip.layout.props.anchor = v2(absToRel(position).x, 0)
        ctx.activeTooltip.layout.props.position = v2(position.x, position.y + 32)
        ctx.activeTooltip:update()
    end
end

function DragAndDrop:dropAt(object, count, position)
    local downSound = helpers.getItemSound(object, 'down')
    if downSound then
        ambient.playSound(downSound)
    end

    local boundingBox = object:getBoundingBox()
    local offset = util.vector3(0, 0, boundingBox.halfSize.z - boundingBox.center.z)
    local targetPos = position + offset
    core.sendGlobalEvent('MI_Teleport', {
        obj = object,
        count = count or object.count,
        source = self.source or omwself,
        cell = (not omwself.cell.isExterior) and omwself.cell.name or '',
        position = targetPos,
        options = {
            rotation = util.transform.rotateZ(camera.getYaw()),
        },
        player = omwself,
    })
end

function DragAndDrop:dropAtFeet(object, count)
    local res = nearby.castRay(omwself.position, omwself.position + util.vector3(0, 0, -100000000000))
    local targetPos = res.hitPos or omwself.position
    self:dropAt(object, count, targetPos)
end

function DragAndDrop:init(ctx)
    if not configPlayer.window.b_EnableMod then return end

    self.hoveredObject = nil
    self.lastHoveredObject = nil
    self.draggingObject = nil
    self.source = nil
    self.ctx = ctx

    self.wrapper = ui.create{
        layer = 'DragBlocker',
        props = {
            relativeSize = v2(1, 1),
            propagateEvents = false,
        },
        content = ui.content {
            {
                name = 'dropPointer',
                props = {
                    relativeSize = v2(0, 0),
                    pointer = 'drop_ground',
                    propagateEvents = true,
                }
            }
        }
    }
    self.wrapper.layout.events = {
        mouseMove = async:callback(function(e)
            local layerSize = ui.layers[ui.layers.indexOf('DragBlocker')].size
            self:getHoveredGameObject(v2(e.position.x / layerSize.x, e.position.y / layerSize.y))
            self.ctx.lastCursorPos = e.position
            -- Update tooltip based on hovered object
            if self.draggingObject then
                if self.ctx.activeTooltip and self.ctx.activeTooltip.layout then
                    auxUi.deepDestroy(self.ctx.activeTooltip)
                    self.ctx.activeTooltip = nil
                end
            else
                if self.hoveredObject ~= self.lastHoveredObject then
                    -- Object changed, remake tooltip
                    if self.ctx.activeTooltip and self.ctx.activeTooltip.layout then
                        auxUi.deepDestroy(self.ctx.activeTooltip)
                        self.ctx.activeTooltip = nil
                    end
                    
                    if self.hoveredObject then
                        createObjectTooltip(self.hoveredObject, e.position, self.ctx)
                    end
                    
                    self.lastHoveredObject = self.hoveredObject
                elseif self.ctx.activeTooltip and self.ctx.activeTooltip.layout and self.hoveredObject then
                    -- Same object, just update position
                    local distToBottom = layerSize.y - e.position.y
                    if distToBottom < layerSize.y / 2 then
                        self.ctx.activeTooltip.layout.props.anchor = v2(absToRel(e.position).x, 1)
                        self.ctx.activeTooltip.layout.props.position = v2(e.position.x, e.position.y - 32)
                    else
                        self.ctx.activeTooltip.layout.props.anchor = v2(absToRel(e.position).x, 0)
                        self.ctx.activeTooltip.layout.props.position = v2(e.position.x, e.position.y + 32)
                    end
                    self.ctx.activeTooltip:update()
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
            if self.ctx.activeTooltip and self.ctx.activeTooltip.layout then
                auxUi.deepDestroy(self.ctx.activeTooltip)
                self.ctx.activeTooltip = nil
            end
            self.lastHoveredObject = nil
            if self.ctx.cursorAttachedIcon then
                self.ctx.cursorAttachedIcon.layout.props.visible = false
                self.ctx.cursorAttachedIcon:update()
            end
        end),
        mousePress = async:callback(function(e)
            if e.button ~= 1 then return end 
            if self.draggingObject then
                if not self.hitPos then
                    self:dropAtFeet(self.draggingObject, self.draggingCount)
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
                    end
                else
                    ui.setConsoleSelectedObject(self.hoveredObject)
                end
            end
        end)
    }
end

return DragAndDrop