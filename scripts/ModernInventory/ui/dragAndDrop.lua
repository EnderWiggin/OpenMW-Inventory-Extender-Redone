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

local specialTemplates = require('scripts.ModernInventory.ui.templates.magic')

local helpers = require('scripts.ModernInventory.util.helpers')

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

function DragAndDrop:startDrag(item, sourceInventory)
    self.draggingObject = item
    self.sourceInventory = sourceInventory
    
    if self.draggingObject then
        local upSound = helpers.getItemSound(self.draggingObject, 'up')
        if upSound then
            ambient.playSound(upSound)
        end
    end
    self.ctx.cursorAttachedIcon = ui.create({
        name = item.id .. '_dragIcon',
        layer = 'Notification',
        type = ui.TYPE.Image,
        props = {
            size = v2(42, 42),
            resource = ui.texture { path = item.type.record(item).icon },
            position = self.lastCursorPos or v2(0, 0),
        }
    })
end

function DragAndDrop:stopDrag()
    if self.draggingObject then
        local downSound = helpers.getItemSound(self.draggingObject, 'down')
        if downSound then
            ambient.playSound(downSound)
        end
    end
    self.draggingObject = nil
    self.sourceInventory = nil
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
        ctx.activeTooltip = ui.create(specialTemplates.itemTooltip(hitObject, true))
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

function DragAndDrop:init(ctx)
    self.lastCursorPos = nil
    self.hoveredObject = nil
    self.lastHoveredObject = nil
    self.draggingObject = nil
    self.sourceInventory = nil
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
            self.lastCursorPos = e.position
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
                local cell = omwself.cell
                local targetPos = self.hitPos or omwself.position
                local boundingBox = self.draggingObject:getBoundingBox()
                local offset = util.vector3(0, 0, boundingBox.halfSize.z - boundingBox.center.z)
                targetPos = targetPos + offset
                core.sendGlobalEvent('MI_Teleport', {
                    obj = self.draggingObject,
                    cell = (not cell.isExterior) and cell.name or '',
                    position = targetPos,
                    options = {
                        onGround = true,
                        rotation = util.transform.rotateZ(camera.getYaw()),
                    }
                })
                self:stopDrag()
                self.wrapper.layout.content.dropPointer.props.relativeSize = v2(0, 0)
                self.wrapper:update()
                omwself:sendEvent('MI_Update')
            elseif self.hoveredObject then
                if not self.ctx.isConsoleOpen then
                    if types.Item.isCarriable(self.hoveredObject) then
                        self:startDrag(self.hoveredObject, nil)
                        core.sendGlobalEvent('MI_MoveInto', {
                            obj = self.hoveredObject,
                            destination = omwself,
                        })
                    end
                else
                    ui.setConsoleSelectedObject(self.hoveredObject)
                end
            end
        end)
    }
end

return DragAndDrop