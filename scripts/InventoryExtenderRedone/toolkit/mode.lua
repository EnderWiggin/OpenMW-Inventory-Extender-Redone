---@omw-context player

local I       = require('openmw.interfaces')
local core    = require('openmw.core')
local input   = require('openmw.input')
local omwself = require('openmw.self')
local types   = require('openmw.types')
local ui      = require('openmw.ui')
local util    = require('openmw.util')


local v2                = util.vector2
local D                 = require('scripts.InventoryExtenderRedone.config.defaults')
local helpers           = require('scripts.InventoryExtenderRedone.util.helpers')
local constants         = require('scripts.InventoryExtenderRedone.util.constants')
local pickpocket        = require('scripts.InventoryExtenderRedone.util.pickpocket')
local barterUtils       = require('scripts.InventoryExtenderRedone.util.barter')
local persistentCorpses = require('scripts.InventoryExtenderRedone.util.persistentCorpses')
local configPlayer      = require('scripts.InventoryExtenderRedone.config.player')
local l10n              = core.l10n(D.L10N)
local L                 = require('scripts.InventoryExtenderRedone.util.logger').get 'Mode'


local Toolkit        = I.UIToolkit
local Components     = Toolkit.Components
local T              = Toolkit.Templates
local H              = require 'scripts.UIToolkit.helpers'
local cfgUtil        = require 'scripts.UIToolkit.config.utils'
local BarterControls = require('scripts.InventoryExtenderRedone.toolkit.barter_controls')

local Actor          = types.Actor
local Container      = types.Container
local Player         = types.Player


-- the player inventory is a live handle on omwself, not a snapshot: :getAll() re-reads contents
local playerInventory = Player.inventory(omwself)


-- Mode specs are pure behavior: they never register windows, a new window role only comes
-- through API.registerWindowRole. Slots are keyed per window role because the Inventory role
-- appears in four modes and needs four different slot sets.
---@class InventoryExtenderRedone.Mode.Library
---@field Defaults InventoryExtenderRedone.Mode.Defaults
---@field Sources table<string,InventoryExtenderRedone.Mode.Source>
---@field Filters table<string,InventoryExtenderRedone.Mode.Filter>
---@field Actions table<string,InventoryExtenderRedone.Mode.Action>
---@field Info table<string,InventoryExtenderRedone.Mode.InfoBarSection>
---@field Builtins table<string,InventoryExtenderRedone.Mode>
---@field resolve fun(key:string, role:InventoryExtenderRedone.Role?):InventoryExtenderRedone.Mode?,InventoryExtenderRedone.Mode.RoleSpec?
---@field resolveMode fun(role:InventoryExtenderRedone.Role, arg:any?, uiMode:string?):InventoryExtenderRedone.Mode?,InventoryExtenderRedone.Mode.RoleSpec?
---@field resolveParts fun(library:table<string,any>, entries:any[]?):any[]
---@field resolvePart fun(library:table<string,any>, entry:any?):any
---@field statePredicate fun(state:InventoryExtenderRedone.Mode.State?, field:string):(fun(...):boolean)?
---@field merge fun(base:InventoryExtenderRedone.Mode?, patch:InventoryExtenderRedone.ModePatch|InventoryExtenderRedone.Mode):InventoryExtenderRedone.Mode
local Mode = {}


--- Slot defaults: what a mode gets when it does not name the slot. A custom mode that omits
--- an axis keeps today's behavior, which is what makes built-in specs and mod-added specs
--- one mechanism. Slots whose default is "absent" cannot be stored in a table and stay nil.
--- Function-bearing defaults arrive with the phase that owns the behavior.
Mode.Defaults = {
    priority = 0,
    syncCategory = true,
    drag = { allowed = true }, -- validDragModes today: Barter is the mode that forbids dragging
    RoleSpec = {
        pinnable = false,      -- only the Interface Inventory window is pinnable (inventory.lua:519)
    },
}

--- Built-in part library. The namespaces are declared here so the contract resolves; the
--- phase that owns the behavior fills them: sources and filters arrived with Phase 2, actions
--- come with Phase 3 and the info bar with Phase 4. Specs reference parts by id, never by
--- inlining behavior, and a part never branches on handler.role - which RoleSpec names the
--- part decides that.
local function merchantItems(npc)
    local merged = helpers.getMerchantItems(npc)
    local flat = {}
    for _, stacks in pairs(merged) do
        for i = 1, #stacks do
            flat[#flat + 1] = stacks[i]
        end
    end
    return flat
end

--- Do not allow trading gold and keys
---@param row InventoryExtenderRedone.RowData
---@param npc openmw.Object?
---@return boolean
local function isAllowedToTrade(row, npc)
    if not npc then return false end
    if helpers.isGold(row.item) then return false end
    if row.itemRecord.isKey then return false end

    return true
end

--- item's service must be offered by the merchant unless it is enchanted and MagicItems is offered.
---@param row InventoryExtenderRedone.RowData
---@param npc openmw.Object?
---@return boolean
local function isOfferedByMerchant(row, npc)
    if not npc then return false end

    local services = npc.type.record(npc).servicesOffered
    if not services.MagicItems or not row.itemRecord.enchant then
        for serviceName, serviceType in pairs(constants.ServiceToType) do
            if serviceType.objectIsInstance(row.item) then
                if not services[serviceName] then
                    return false
                end
                break
            end
        end
    end
    return true
end

Mode.Sources = {
    -- the window's own target inventory: the player's for the Inventory role, the container's or
    -- the companion's for its own role
    target = {
        id = 'target',
        get = function(handler, _)
            return handler.target.type.inventory(handler.target):getAll()
        end,
    },
    -- always the player's own inventory, whichever window asks for the other side of a barter
    self = {
        id = 'self',
        get = function(_, _)
            return playerInventory:getAll()
        end,
    },
    -- merchant stock merged into virtual stacks; the two ids differ only in which NPC is asked,
    -- and merchantOfOther keeps the ctx.windowArgs fallback because the engine may open the
    -- player's window before the Trade window has recorded the merchant
    --TODO: consider removing ctx.windowArgs
    merchantOfTarget = {
        id = 'merchantOfTarget',
        virtual = true,
        get = function(handler, _)
            return merchantItems(handler.target)
        end,
    },
    merchantOfOther = {
        id = 'merchantOfOther',
        virtual = true,
        -- this side is always the far end of an offer: the rows exist to show what the other
        -- window is holding out for
        isBartered = true,
        get = function(handler, ctx)
            local barterNpc = ctx.windowArgs[D.Roles.Trade] or handler.arg
            if not barterNpc then return {} end
            return merchantItems(barterNpc)
        end,
    },
}

Mode.Filters = {
    -- disallow gold and keys
    barterAllowed = {
        id = 'barterAllowed',
        fn = function(row, handler, _)
            return isAllowedToTrade(row, handler.arg)
        end,
    },
    -- allow only items in merchant's service list
    barterOffered = {
        id = 'barterOffered',
        fn = function(row, handler, _)
            return isOfferedByMerchant(row, handler.arg)
        end,
    },
    -- show merchant's items in inventory when buying
    barterInventoryForeign = {
        id = 'barterInventoryForeign',
        fn = function(row, _, ctx)
            local item = row.item
            local buying = ctx.barterState.buying
            local selling = ctx.barterState.selling
            if row.isBartered then
                return buying[item.id] and buying[item.id].count > 0
            end
            local sellingCount = selling[item.id] and selling[item.id].count or 0
            return row.getCount() > sellingCount
        end,
    },
    -- show player's items in trade when selling
    barterTraderForeign = {
        id = 'barterTraderForeign',
        fn = function(row, _, ctx)
            local item = row.item
            local buying = ctx.barterState.buying
            local selling = ctx.barterState.selling
            if row.isBartered then
                return selling[item.id] and selling[item.id].count > 0
            end
            local buyingCount = buying[item.id] and buying[item.id].count or 0
            return row.getCount() > buyingCount
        end,
    },
    -- hide merchant's equipped items
    barterTradeEquipped = {
        id = 'barterTradeEquipped',
        fn = function(row, handler, _)
            return not handler.target.type.hasEquipped(handler.target, row.item)
        end,
    },
    -- only the items the sneak roll left visible; a nil session means everything is visible
    pickpocketVisibility = {
        id = 'pickpocketVisibility',
        fn = function(row, _, ctx)
            return pickpocket.isVisible(ctx.pickpocket, row.item)
        end,
    },
}
-- Built-in row actions: gate + effect only. The shared row mechanics (bound-item and favorite
-- guards, Alt/Shift/Ctrl modifiers, the stack-count popup) stay in the handler and call these
-- parts with (row, handler, ctx, count); perform is the default effect, transfer the Alt-held
-- variant. use parts also carry the IER_UseItem payload providers: which inventory the item
-- moves from first and, during a pickpocket session, whose session the roll belongs to.
local function useSourceSelf(row, _, _)
    return row.item.parentContainer or omwself
end

local function useSourceTarget(row, handler, _)
    return row.item.parentContainer or handler.target
end

local function usePickpocketSession(_, handler, ctx)
    local session = ctx.pickpocket
    if session and session.active then
        return { target = handler.target }
    end
    return nil
end

-- the shared drag start: every mode that allows dragging lands here; the activation context
-- carries modeKey so the dragAndDrop singleton can find this spec back for autoEquip
local function dragStart(row, handler, ctx, count, pickpocketCtx)
    ctx.dragAndDrop:startDrag(
        row.item,
        handler.target,
        count,
        pickpocketCtx,
        {
            role = handler.role,
            isBartered = row.isBartered,
            modeKey = handler.mode,
        }
    )
end

local function performDrag(row, handler, ctx, count)
    return dragStart(row, handler, ctx, count, nil)
end

local function performPickpocketDrag(row, handler, ctx, count)
    local session = ctx.pickpocket
    return dragStart(row, handler, ctx, count,
        session and session.active and { target = handler.target } or nil)
end

-- Alt+click from the player's window hands the row to the mode's other window
local function transferIntoWindow(role, modeKey)
    return function(row, _, ctx, count)
        local target = ctx.windowArgs[role]
        if target then
            ctx.dragAndDrop:transferInto(row.item, target, omwself, count, nil, modeKey)
        end
    end
end

-- Alt+click from a target window hands the row to the player
local function transferToPlayer(modeKey)
    return function(row, handler, ctx, count)
        ctx.dragAndDrop:transferInto(row.item, omwself, handler.target, count, nil, modeKey)
    end
end

local function transferPickpocketToPlayer(row, handler, ctx, count)
    local session = ctx.pickpocket
    ctx.dragAndDrop:transferInto(row.item, omwself, handler.target, count,
        session and session.active and { target = handler.target } or nil,
        D.Modes.Pickpocket)
end

-- the pickpocket take roll runs before either pickup effect: a failed roll resolves the
-- session, alerts the victim and closes the window, and stops the action
local function rollPickpocketTake(row, handler, ctx)
    local session = ctx.pickpocket
    if session and session.active then
        local success = pickpocket.rollTake(omwself, handler.target, row.item, row.getCount())
        if not success then
            session.resolved = true
            core.sendGlobalEvent('IER_CommitPickpocket', {
                player = omwself,
                target = handler.target,
                victimAware = true,
            })
            I.UI.removeMode(D.Modes.Container)
            return false
        end
    end
    return true
end

-- Interface world drop: favorite items refuse to leave the pockets
local function worldDrop(row, handler, ctx, count)
    if not handler:isFavorite(row.item) then
        ctx.dragAndDrop:dropAtViewportPosition(row.item, count, v2(0.5, 0.5), true)
    else
        ui.showMessage(l10n('UI_Msg_FavoriteItem'))
    end
end

Mode.Actions = {
    -- use gate + payload for windows whose target is the actor themselves
    usePlayer = {
        enabled = function() return true end,
        source = useSourceSelf,
    },
    -- use gate + payload for target windows: the item must move to the window's owner first
    useTarget = {
        enabled = function() return true end,
        source = useSourceTarget,
    },
    -- the pickpocket Container role: same use as a target window, plus the session the roll
    -- belongs to, carried into the IER_UseItem payload
    useTargetPickpocket = {
        enabled = function() return true end,
        source = useSourceTarget,
        pickpocket = usePickpocketSession,
    },
    -- Barter: the player's window may use only what they are not offering; the merchant's
    -- only what they have already bought
    useBarterInventory = {
        enabled = function(row) return not row.isBartered end,
        source = useSourceSelf,
    },
    useBarterTrade = {
        enabled = function(row) return row.isBartered == true end,
        source = useSourceSelf,
    },
    -- the default drag effect is shared; the transfer variant is per mode and per role
    pickupInterface = {
        perform = performDrag,
        transfer = worldDrop,
    },
    pickupContainerInventory = {
        perform = performDrag,
        transfer = transferIntoWindow(D.Roles.Container, D.Modes.Container),
    },
    pickupContainerTarget = {
        perform = performDrag,
        transfer = transferToPlayer(D.Modes.Container),
    },
    pickupCompanionInventory = {
        perform = performDrag,
        transfer = transferIntoWindow(D.Roles.Companion, D.Modes.Companion),
    },
    pickupCompanionTarget = {
        perform = performDrag,
        transfer = transferToPlayer(D.Modes.Companion),
    },
    -- Barter never drags (drag.allowed is false), so only the transfer effect exists;
    -- the effect lives in util/barter.lua shared with the queue API (decrementTable first)
    pickupBarterInventory = {
        transfer = barterUtils.barterOfferEffect('buying', 'selling'),
    },
    pickupBarterTrade = {
        transfer = barterUtils.barterOfferEffect('selling', 'buying'),
    },
    -- pickpocket takes roll the sneak check before the drag/transfer lands
    pickpocketTake = {
        perform = function(row, handler, ctx, count)
            if not rollPickpocketTake(row, handler, ctx) then return false end
            return performPickpocketDrag(row, handler, ctx, count)
        end,
        transfer = function(row, handler, ctx, count)
            if not rollPickpocketTake(row, handler, ctx) then return false end
            return transferPickpocketToPlayer(row, handler, ctx, count)
        end,
    },
}
-- InfoBar sections: `create` builds the once-per-open part (buttons, bars, layouts) and hands
-- back the per-frame provider; `provider` alone is a stateless section. The handler feeds both
-- to InfoBar:addProvider in slot order, so the filler (stretch) position stays load-bearing.
local function createDraggedActivationRow(ctx, item)
    local activationContext = ctx.dragAndDrop.draggingActivationContext or {}
    return {
        id = item.id,
        item = item,
        itemRecord = item.type.record(item),
        isBartered = activationContext.isBartered,
        getCount = function()
            return ctx.dragAndDrop.draggingCount or item.count
        end,
    }
end

Mode.Info = {
    -- weight bar: hidden for organic containers and during a pickpocket session
    encumbrance = {
        id = 'encumbrance',
        create = function(handler, _)
            local theme = Toolkit.getTheme()
            local bar = Components.progressBar {
                width = 100,
                color = theme.Colors.MAGICK,
                clamp = false,
            }
            local layout = {
                name = 'encumbrance',
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = {
                            resource = Toolkit.texture 'icons/weight.dds',
                            size = v2(1, 1) * theme.Sizes.textNormal,
                        }
                    },
                    T.intervalH(4),
                    bar.element,
                }
            }
            return function(c)
                if not handler.target then return nil end
                if handler.role == D.Roles.Container and
                    (Container.objectIsInstance(handler.target) and Container.record(handler.target).isOrganic)
                    or (c.pickpocket and c.pickpocket.active)
                then
                    return nil
                end
                local targetType = handler.target.type
                bar:setMax(util.round(targetType.getCapacity(handler.target)))
                bar:setValue(util.round(targetType.getEncumbrance(handler.target)))
                return layout
            end
        end,
    },
    -- gold the window's actor carries: pocket gold for the Inventory role, the merchant's
    -- remaining offer for Trade
    gold = {
        id = 'gold',
        create = function(handler, _)
            local theme = Toolkit.getTheme()
            local props = { text = '' }
            local layout = {
                name = 'gold',
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = {
                            resource = ui.texture { path = 'icons/gold.dds' },
                            size = v2(1, 1) * theme.Sizes.textNormal,
                        }
                    },
                    T.intervalH(4),
                    {
                        template = T.text(),
                        props = props,
                    }
                }
            }
            return function(_)
                if not handler.target then return nil end
                local goldAmount
                if handler.role == D.Roles.Inventory then
                    goldAmount = handler.target.type.inventory(handler.target):countOf('gold_001')
                else
                    goldAmount = handler.target.type.getBarterGold(handler.target)
                end
                props.text = H.addSeparators(goldAmount)
                return layout
            end
        end,
    },
    -- worn armor rating, the player's own window only
    armorRating = {
        id = 'armorRating',
        create = function(handler, _)
            local theme = Toolkit.getTheme()
            local props = { text = '' }
            local layout = {
                name = 'armorRating',
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = {
                            resource = ui.texture { path = 'icons/a/a_cuirass_ebon.dds' },
                            size = v2(1, 1) * theme.Sizes.textNormal,
                        }
                    },
                    T.intervalH(4),
                    {
                        template = T.text(),
                        props = props,
                    }
                }
            }
            return function(_)
                if not handler.target then return nil end
                props.text = H.addSeparators(math.floor(I.Combat.getArmorRating(handler.target)))
                return layout
            end
        end,
    },
    -- stretching gap; its position in the slot list is what lays the strip out
    filler = {
        id = 'filler',
        provider = function(_)
            return { external = { grow = 1, stretch = 1 } }
        end,
    },
    -- use the dragged item: the button only shows while a drag is active
    use = {
        id = 'use',
        create = function(handler, ctx)
            local theme = Toolkit.getTheme()
            local btnUse = Components.textButton {
                name = 'use',
                style = theme.IntRe and 'empty' or 'thin',
                text = core.getGMST('sUse'),
                onClick = function()
                    local draggedItem = ctx.dragAndDrop.draggingObject
                    if not draggedItem then return end
                    local result = handler:onRowUse(createDraggedActivationRow(ctx, draggedItem))
                    if result ~= false then
                        ctx.dragAndDrop:stopDrag()
                        handler.infoBar:update()
                        --handler:refresh()
                    end
                end,
                tooltip = function()
                    if configPlayer.keybinds.b_SwapUsePickup then
                        return l10n('UI_Tooltip_UseButton_Swapped')
                    end
                    local key = cfgUtil.getFirstKeyboardInput(configPlayer.keybinds.c_Activate).id
                    if not key then return nil end
                    return l10n('UI_Tooltip_UseButton', { key = input.getKeyName(key) })
                end,
            }
            return function(c)
                btnUse:setVisible(c.dragAndDrop.draggingObject ~= nil)
                return btnUse.element
            end
        end,
    },
    -- loot a dead body and end the encounter: the button only shows on dead actors
    dispose = {
        id = 'dispose',
        create = function(handler, ctx)
            local theme = Toolkit.getTheme()
            local btnDispose = Components.textButton {
                name = 'dispose',
                style = theme.IntRe and 'empty' or 'thin',
                text = constants.Strings.DISPOSE_OF_CORPSE,
                onClick = function()
                    -- the window's own snapshot decides: during a pickpocket session the
                    -- engine sits in Container mode but the mode key is Pickpocket
                    local mode = handler.mode
                    if mode ~= D.Modes.Container and mode ~= D.Modes.Pickpocket then return end
                    if not ctx.windowArgs[D.Roles.Container] then return end
                    ctx.dragAndDrop:moveAll(handler.target, omwself)
                    if persistentCorpses(handler.target) then
                        ui.showMessage(constants.Strings.DISPOSE_CORPSE_FAIL)
                    else
                        core.sendGlobalEvent('IER_DisposeOfCorpse', {
                            target = ctx.windowArgs[D.Roles.Container],
                        })
                    end
                    I.UI.removeMode(D.Modes.Container)
                end,
            }
            return function(c)
                local visible = false
                if c.windowArgs[D.Roles.Container] then
                    visible = Actor.objectIsInstance(c.windowArgs[D.Roles.Container])
                        and Actor.isDead(c.windowArgs[D.Roles.Container])
                end
                btnDispose:setVisible(visible)
                return btnDispose.element
            end
        end,
    },
    -- take everything: Shift takes only what the filters left visible and keeps the window open
    takeAll = {
        id = 'takeAll',
        create = function(handler, ctx)
            local theme = Toolkit.getTheme()
            local btnTakeAll = Components.textButton {
                name = 'takeAll',
                style = theme.IntRe and 'empty' or 'thin',
                text = constants.Strings.TAKE_ALL,
                onClick = function()
                    local mode = handler.mode
                    if mode ~= D.Modes.Container and mode ~= D.Modes.Pickpocket then return end
                    if not ctx.windowArgs[D.Roles.Container] then return end
                    local visibleOnly = input.isShiftPressed()
                    local items = nil

                    if visibleOnly then
                        local visibleItems = handler.table.filteredItems
                        items = {}
                        for i = 1, #visibleItems do
                            local row = visibleItems[i]
                            if row and row.item then
                                items[#items + 1] = row.item
                            end
                        end
                    end

                    if not items or #items > 0 then
                        ctx.dragAndDrop:moveAll(handler.target, omwself, items)
                    end

                    if not visibleOnly then
                        I.UI.removeMode(D.Modes.Container)
                    end
                end,
                tooltip = l10n('UI_Tooltip_TakeAllButton_Shift'),
            }
            return function(c)
                btnTakeAll:setVisible(not (c.pickpocket and c.pickpocket.active))
                return btnTakeAll.element
            end
        end,
    },
    -- what a companion has gained from the player, only on its window
    profit = {
        id = 'profit',
        create = function(handler, _)
            local props = {}
            local layout = {
                template = T.text(),
                props = props,
            }
            return function(c)
                if handler.target == nil then return nil end
                local profit = c.companionProfit[handler.target.id] or 0
                props.text = constants.Strings.PROFIT_VALUE .. ': ' .. H.addSeparators(profit)
                return layout
            end
        end,
    },
    -- close the target window: built-in roles close through the engine mode; a custom role's
    -- close arrives with API.closeMode (Phase 5)
    close = {
        id = 'close',
        create = function(handler, _)
            local theme = Toolkit.getTheme()
            local btnClose = Components.textButton {
                name = 'close',
                style = theme.IntRe and 'empty' or 'thin',
                text = constants.Strings.CLOSE,
                onClick = function()
                    I.UI.removeMode(handler.role)
                end,
            }
            return function(_)
                return btnClose.element
            end
        end,
    },
    barterCancel = {
        id = 'barterCancel',
        create = function(_, _)
            local theme = Toolkit.getTheme()
            local btn = Components.textButton {
                name = 'close',
                style = theme.IntRe and 'empty' or 'thin',
                text = constants.Strings.CANCEL,
                onClick = function()
                    I.UI.removeMode('Barter')
                end,
            }
            return function(_)
                return btn.element
            end
        end,
    },
    -- the offer panel: −, amount, +, Max, Offer, Cancel
    barterControls = {
        id = 'barterControls',
        create = function(handler, _)
            local barterControls = BarterControls:new()
            barterControls:init(handler)
            return function(c)
                barterControls:update(c)
                return barterControls.element
            end
        end,
    },
}

--- Built-in specs, keyed by mode key. Custom specs live in ctx.modes and are never stored here.
Mode.Builtins = {
    Interface  = require('scripts.InventoryExtenderRedone.toolkit.modes.interface'),
    Container  = require('scripts.InventoryExtenderRedone.toolkit.modes.container'),
    Pickpocket = require('scripts.InventoryExtenderRedone.toolkit.modes.pickpocket'),
    Barter     = require('scripts.InventoryExtenderRedone.toolkit.modes.barter'),
    Companion  = require('scripts.InventoryExtenderRedone.toolkit.modes.companion'),
}


-- List slots merge through id-keyed ops; everything else is a whole-slot overwrite. A plain
-- array in a patch replaces the whole slot, a { add/remove/replace } table applies ops.
local LIST_SLOTS = { 'sources', 'filters', 'infoBar' }
local ROLE_SLOTS = { 'states', 'actions', 'categories', 'columns', 'observer', 'hints', 'pinnable', 'storageSuffix', 'defaultStorage' }
local MODE_SLOTS = { 'title', 'applies', 'priority', 'syncCategory', 'drag', 'lifecycle', 'event' }


local function isPatchList(op)
    return op.add ~= nil or op.remove ~= nil or op.replace ~= nil
end

--- `after`/`before` on an entry position it against an existing id; entries without them keep
--- insertion order. Ordering only matters for infoBar sections, whose filler (stretch) position
--- is load-bearing for layout.
---@param ordered string[] ids in order, no duplicates
---@param id string
---@param after string? put directly after this id
---@param before string? put directly before this id
local function insertOrdered(ordered, id, after, before)
    for i = 1, #ordered do
        if ordered[i] == id then
            table.remove(ordered, i)
            break
        end
    end
    local anchor = after or before
    if anchor then
        for i = 1, #ordered do
            if ordered[i] == anchor then
                table.insert(ordered, after and i + 1 or i, id)
                return
            end
        end
    end
    ordered[#ordered + 1] = id
end

---@param base any[]?
---@param op any[]|InventoryExtenderRedone.Mode.PatchList
---@return any[]
local function mergeList(base, op)
    if not op then return base or {} end
    if not isPatchList(op) then return op end

    local ordered = {}
    local byId = {}
    if base then
        for i = 1, #base do
            local entry = base[i]
            if entry and entry.id and not byId[entry.id] then
                ordered[#ordered + 1] = entry.id
                byId[entry.id] = entry
            end
        end
    end

    local function put(entry)
        if not entry or not entry.id then return end
        if byId[entry.id] then
            byId[entry.id] = entry
            return
        end
        insertOrdered(ordered, entry.id, entry.after, entry.before)
        byId[entry.id] = entry
    end

    for _, entry in ipairs(op.replace or {}) do put(entry) end
    for _, entry in ipairs(op.add or {}) do put(entry) end

    local removed = {}
    for _, id in ipairs(op.remove or {}) do removed[id] = true end

    local result = {}
    for _, id in ipairs(ordered) do
        local entry = byId[id]
        if entry and not removed[id] then
            result[#result + 1] = entry
        end
    end
    return result
end

---@param base InventoryExtenderRedone.Mode.RoleSpec?
---@param patch InventoryExtenderRedone.Mode.RoleSpecPatch|InventoryExtenderRedone.Mode.RoleSpec?
---@return InventoryExtenderRedone.Mode.RoleSpec
local function mergeRoleSpec(base, patch)
    local merged = {}
    for key, value in pairs(base or {}) do merged[key] = value end
    if not patch then return merged end

    for _, slot in ipairs(LIST_SLOTS) do
        if patch[slot] then merged[slot] = mergeList(merged[slot], patch[slot]) end
    end
    for _, slot in ipairs(ROLE_SLOTS) do
        if patch[slot] ~= nil then merged[slot] = patch[slot] end
    end
    for _, slot in ipairs(patch.disable or {}) do merged[slot] = nil end
    return merged
end

--- Merge a patch (or another spec) over a base spec. `roles` merges per role; every other slot
--- is a whole-slot overwrite, so a mode that wants part of a slot uses the list-slot ops.
---@param base InventoryExtenderRedone.Mode?
---@param patch InventoryExtenderRedone.ModePatch|InventoryExtenderRedone.Mode
---@return InventoryExtenderRedone.Mode
function Mode.merge(base, patch)
    local merged = {}
    for key, value in pairs(base or {}) do merged[key] = value end
    if not patch then return merged end

    if patch.key then merged.key = patch.key end
    for _, slot in ipairs(MODE_SLOTS) do
        if patch[slot] ~= nil then merged[slot] = patch[slot] end
    end
    if patch.roles then
        local roles = {}
        for role, spec in pairs(merged.roles or {}) do roles[role] = spec end
        for role, patchSpec in pairs(patch.roles) do
            roles[role] = mergeRoleSpec(roles[role], patchSpec)
        end
        merged.roles = roles
    end
    for _, slot in ipairs(patch.disable or {}) do merged[slot] = nil end
    return merged
end

--- A spec's own slots win over its base chain, which wins over Mode.Defaults.
---@param spec InventoryExtenderRedone.Mode.RoleSpec?
---@return InventoryExtenderRedone.Mode.RoleSpec
local function applyRoleDefaults(spec)
    local merged = {}
    for key, value in pairs(Mode.Defaults.RoleSpec) do merged[key] = value end
    for key, value in pairs(spec or {}) do merged[key] = value end
    return merged
end

---@param mode InventoryExtenderRedone.Mode
---@return InventoryExtenderRedone.Mode
local function applyModeDefaults(mode)
    if mode.priority == nil then mode.priority = Mode.Defaults.priority end
    if mode.syncCategory == nil then mode.syncCategory = Mode.Defaults.syncCategory end
    if not mode.drag then
        mode.drag = { allowed = Mode.Defaults.drag.allowed }
    elseif mode.drag.allowed == nil then
        mode.drag.allowed = Mode.Defaults.drag.allowed
    end
    return mode
end

--- Resolve a mode key to its fully merged spec: base chain, then registered patches in
--- reverse registration order, like every other id-keyed extension list in the repo.
---@param key InventoryExtenderRedone.ModeKey
---@param ctx InventoryExtenderRedone.Context
---@param visited table<string,boolean>? guards a mod-supplied base cycle
---@return InventoryExtenderRedone.Mode? nil when the key is not registered
local function resolveSpec(key, ctx, visited)
    local spec = Mode.Builtins[key] or ctx.modes[key]
    if not spec then return nil end
    if visited and visited[key] then return nil end

    local base
    if spec.base then
        visited = visited or {}
        visited[key] = true
        base = resolveSpec(spec.base, ctx, visited)
    end

    local merged = Mode.merge(base, spec)
    local patches = ctx.modePatches[key]
    if patches then
        for i = #patches, 1, -1 do
            merged = Mode.merge(merged, patches[i])
        end
    end
    return applyModeDefaults(merged)
end

--- Nothing calls this yet: the phase that wires mode resolution into windowManager:show owns
--- the call. Reopen must compare against an already-open window's snapshot, not re-resolve it.
---@param key InventoryExtenderRedone.ModeKey
---@param role InventoryExtenderRedone.Role? when given, also return this role's merged slots
---@return InventoryExtenderRedone.Mode? mode
---@return InventoryExtenderRedone.Mode.RoleSpec? roleSpec
function Mode.resolve(key, role)
    local mode = resolveSpec(key, I.InventoryExtenderRedone.getContext())
    if not mode then return nil end
    if not role then return mode end

    local spec = mode.roles and mode.roles[role]
    if not spec then return mode end
    return mode, applyRoleDefaults(spec)
end

--- A spec entry may name a built-in part by id or carry its own behavior; the entry's own fields
--- win over the library part, so a mod can reuse a built-in with one field changed. Resolved once
--- at open, like the rest of the snapshot.
---@param library table<string,any> Mode.Sources, Mode.Filters, Mode.Actions, …
---@param entry any?
---@return any
function Mode.resolvePart(library, entry)
    if not entry then return nil end
    local part = library[entry.id]
    if not part then return entry end
    local merged = {}
    for key, value in pairs(part) do merged[key] = value end
    for key, value in pairs(entry) do merged[key] = value end
    return merged
end

---@param library table<string,any> Mode.Sources, Mode.Filters, Mode.Actions, …
---@param entries any[]?
---@return any[]
function Mode.resolveParts(library, entries)
    local resolved = {}
    for _, entry in ipairs(entries or {}) do
        resolved[#resolved + 1] = Mode.resolvePart(library, entry)
    end
    return resolved
end

--- A state slot names either one predicate or a list of States whose same-named predicates are
--- OR-ed. Returns nil when the slot does not name the field at all.
---@param state InventoryExtenderRedone.Mode.State?
---@param field string
---@return (fun(...):boolean)?
function Mode.statePredicate(state, field)
    local value = state and state[field]
    if value == nil then return nil end
    if type(value) == 'function' then return value end

    return function(row, handler, ctx)
        for i = 1, #value do
            local nested = value[i] and value[i][field]
            if nested and nested(row, handler, ctx) then return true end
        end
        return false
    end
end

--- Selection step, before Mode.resolve: which mode governs this window role. Built-in specs match
--- through applies(), which is handed the engine UI mode by the caller: resolveMode takes uiMode and
--- forwards it, so specs never call I.UI themselves and the mode cannot be stale at open.
--- Highest priority wins; equal priorities are not ordered, so a custom mode that overlaps
--- a built-in must out-prioritize it. Selection consults registered specs, not patched ones:
--- patchMode changes slots, never which mode applies.
---@param role InventoryExtenderRedone.Role
---@param arg any? the target NPC/container/merchant
---@param uiMode string? engine UI mode when the window opened (nil = interface)
---@return InventoryExtenderRedone.Mode? mode fully merged
---@return InventoryExtenderRedone.Mode.RoleSpec? roleSpec this role's merged slots
function Mode.resolveMode(role, arg, uiMode)
    local ctx = I.InventoryExtenderRedone.getContext()

    local bestKey
    local bestPriority
    for key, spec in pairs(Mode.Builtins) do
        if spec.applies and spec.applies(role, arg, ctx, uiMode) then
            local priority = spec.priority or Mode.Defaults.priority
            if not bestKey or priority > bestPriority then
                bestKey = key
                bestPriority = priority
            end
        end
    end
    for key, spec in pairs(ctx.modes) do
        if spec.applies and spec.applies(role, arg, ctx, uiMode) then
            local priority = spec.priority or Mode.Defaults.priority
            if not bestKey or priority > bestPriority then
                bestKey = key
                bestPriority = priority
            end
        end
    end

    if not bestKey then
        L.debug('resolveMode: no mode applies', role, uiMode)
        return nil
    end
    -- observability: which spec won selection and at what priority; a probe forcing a
    -- custom mode that loses priority shows up here as the built-in key
    L.debug('resolveMode', role, uiMode, bestKey, bestPriority)
    return Mode.resolve(bestKey, role)
end

return Mode
