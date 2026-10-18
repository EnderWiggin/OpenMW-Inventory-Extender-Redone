---@meta


---@class openmw.interfaces.Player
---@field InventoryExtenderRedone openmw.interfaces.InventoryExtenderRedone

---@class openmw.interfaces.InventoryExtenderRedone
---@field VERSION number
---@field Constants table? util/constants module (C.Colors, C.Strings, C.OPT_KEYS, …)
---@field Helpers table? util/helpers module (getItem*, isItemEquipped, doesItemFit, …)
---@field allWindowsDisabled boolean live flag set by disableAllWindows; while true, show() is a no-op
---@field disableAllWindows fun(value:boolean) temporarily suppress IE windows; does NOT restore vanilla windows - nothing is shown
---@field show fun(windowName:string, arg:any?) windowName is one of InventoryExtenderRedone.WindowType; arg is the target NPC/container/merchant
---@field hide fun(windowName:string, arg:any?, force:boolean?)
---@field forEachOpenWindow fun(apply:fun(handler:IER.Inventory, wnd:UIToolkit.Window))
---@field getContext fun():InventoryExtenderRedone.Context WindowManager.ctx - the shared mutable state, read by every toolkit file
---@field getCategories fun():InventoryExtenderRedone.Category[]
---@field getCategory fun(key:string):InventoryExtenderRedone.Category?
---@field getDraggingObject fun():openmw.Object? returns dragged object or nil if not dragging
---@field registerCategory fun(category:InventoryExtenderRedone.Category)
---@field unregisterCategory fun(key:string)
---@field isFavorite fun(itemOrId:string|openmw.Object):boolean
---@field registerEquippedOverride fun(id:string, handler:fun(item:openmw.Object, actor:openmw.Object):boolean?) called in reverse registration order until one returns non-nil
---@field registerRowDataModifier fun(id:string, handler:InventoryExtenderRedone.RowDataModifier)
---@field registerRowBadge fun(id:string, provider:InventoryExtenderRedone.RowBadgeProvider)
---@field registerRowUseHandler fun(id:string, handler:fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, windowType:string):boolean?) called in reverse registration order until one returns false; handlers of the use/equip action (default: R, c_Activate, InfoBar "Use" button)
---@field registerRowPickupHandler fun(id:string, handler:fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, windowType:string):boolean?) called in reverse registration order until one returns false; handlers of the pick-up action (default: left-click)


---@class InventoryExtenderRedone.Context
---@field handlers InventoryExtenderRedone.Handlers registered row action handlers, called in reverse registration order
---@field modifiers InventoryExtenderRedone.Modifiers registered modifiers
---@field overrides InventoryExtenderRedone.Overrides equipped-status overrides, called in reverse order until one returns non-nil
---@field dragAndDrop InventoryExtenderRedone.DragAndDrop ui/dragAndDrop.lua singleton (draggingObject, draggingCount, draggingActivationContext, lastHoveredObject, wrapper, …)
---@field windowArgs table<string,openmw.Object?> key is one of InventoryExtenderRedone.WindowType; value is the arg passed to show (target NPC/container/merchant)
---@field lastUiMode string? last known UI mode (nil = interface)
---@field stolenItems table<string,table<string,number>> recordId -> (victim recordId or factionId -> count)
---@field favoriteItems table<string,boolean> item.id -> favorited (saved; blocks transfers outside Interface mode)
---@field favoriteRevision number bumped when favorites change (saved)
---@field barterState InventoryExtenderRedone.BarterState
---@field companionProfit table<string,number> actorId -> profit (saved)
---@field pickpocket InventoryExtenderRedone.PickpocketSession? current pickpocket session or nil
---@field containerVariables table<string,any> vanilla-parity ownership globals
---@field isConsoleOpen boolean
---@field cursorAttachedIcon openmw.ui.Element? icon attached to the cursor while dragging
---@field syncingCategoryFilter boolean? guard set ad hoc by inventory.lua for recursive synced category switching


-- ui/dragAndDrop.lua module table used as a singleton (not a Class() prototype):
-- state is set via init(ctx) and mutated in place; methods are called with `:`.
---@class InventoryExtenderRedone.DragAndDrop
---@field init fun(self:InventoryExtenderRedone.DragAndDrop, ctx:InventoryExtenderRedone.Context) attaches ctx, creates the DragBlocker wrapper element and its mouseMove/focusLoss/mousePress events
---@field ctx InventoryExtenderRedone.Context? set by init
---@field wrapper openmw.ui.Element? DragBlocker layer element; dropPointer child shows the drop cursor while dragging
---@field hoveredObject openmw.Object? last object under the cursor from the viewport raycast
---@field lastHoveredObject openmw.Object? object the current tooltip was made for (tooltip ownership check)
---@field hitPos openmw.util.Vector3? eligible world drop position from the last raycast (flat-enough surface)
---@field draggingObject openmw.Object? item currently dragged, nil when not dragging
---@field draggingCount number? number of units being dragged
---@field draggingActivationContext table? {windowType, isBartered} where the drag was started
---@field source openmw.Object? actor/container the dragged item came from
---@field resolveViewportDropTarget fun(self:InventoryExtenderRedone.DragAndDrop, position:openmw.util.Vector2, callback:fun(result, hitPos)) async raycast from viewport position; callback gets the raw hit and an eligible drop position (nil if surface too steep)
---@field getHoveredGameObject fun(self:InventoryExtenderRedone.DragAndDrop, position:openmw.util.Vector2) sets hoveredObject/hitPos from a viewport raycast
---@field startDrag fun(self:InventoryExtenderRedone.DragAndDrop, item:openmw.Object, source:openmw.Object?, count:number?, pickpocket:table?, activationContext:table?) sends IER_MoveInto with dragStart; lands as setDraggingObject via the IE_SetDraggingObject player event
---@field setDraggingObject fun(self:InventoryExtenderRedone.DragAndDrop, object:openmw.Object) enters drag state and creates ctx.cursorAttachedIcon (unless instantPickup)
---@field updatePosition fun(self:InventoryExtenderRedone.DragAndDrop) moves ctx.cursorAttachedIcon to the current cursor position
---@field transferInto fun(self:InventoryExtenderRedone.DragAndDrop, object:openmw.Object, destination:openmw.Object?, source:openmw.Object?, count:number?, pickpocket:table?):boolean sends IER_MoveInto; false if item doesn't fit or container is organic
---@field moveAll fun(self:InventoryExtenderRedone.DragAndDrop, source:openmw.Object, destination:openmw.Object, items:openmw.Object[]?) sends IER_MoveAll (Take All / dispose)
---@field stopDrag fun(self:InventoryExtenderRedone.DragAndDrop, target:openmw.Object?):boolean? transfers into target if given, then clears drag state and cursor icon; false if the transfer failed
---@field dropAt fun(self:InventoryExtenderRedone.DragAndDrop, object:openmw.Object, count:number?, position:openmw.util.Vector3) sends IER_Teleport to drop the item in the world at position
---@field dropAtViewportPosition fun(self:InventoryExtenderRedone.DragAndDrop, object:openmw.Object, count:number?, position:openmw.util.Vector2, fallbackToFeet:boolean?, callback:fun()?) resolves a viewport drop target, falls back to dropAtFeet when allowed
---@field dropAtFeet fun(self:InventoryExtenderRedone.DragAndDrop, object:openmw.Object, count:number?, callback:fun()?) drops at a raycast point below the actor
---@field setWrapperEnabled fun(self:InventoryExtenderRedone.DragAndDrop, enabled:boolean) shows/hides the DragBlocker wrapper (tooltip compatibility mode only)
---@field onMouseButtonPress fun(self:InventoryExtenderRedone.DragAndDrop, button:number)
---@field onMouseButtonRelease fun(self:InventoryExtenderRedone.DragAndDrop, button:number)
---@field onControllerButtonPress fun(self:InventoryExtenderRedone.DragAndDrop, id:number)
---@field onControllerButtonRelease fun(self:InventoryExtenderRedone.DragAndDrop, id:number)


---@class InventoryExtenderRedone.Category
---@field key string
---@field name string
---@field icon string
---@field filter? fun(item:openmw.Object):boolean
---@field prepend boolean?
---@field hiddenColumns? table<string, boolean>


---@class InventoryExtenderRedone.RowData : UIToolkit.ListData.Column
---@field item openmw.Object
---@field Name string|fun():string
---@field Type string|fun():string
---@field isBartered boolean
---@field showAsEnchanted fun():boolean
---@field itemRecord {id:string, name:string, icon:string}
---@field getCount fun():number
---@field sortCache table?


---@class InventoryExtenderRedone.InfoBarOpts
---@field maxHeight number?

---@class InventoryExtenderRedone.InfoBar : UIToolkit.Component
---@field create fun(opts:InventoryExtenderRedone.InfoBarOpts):InventoryExtenderRedone.InfoBar
---@field addProvider fun(self:InventoryExtenderRedone.InfoBar, provider:InventoryExtenderRedone.InfoBar.Provider):InventoryExtenderRedone.InfoBar provider must return layout or element or nil. It is also responsible for destroying old element if necessary.

---@class InventoryExtenderRedone.ItemTableOpts: UIToolkit.SortedListOpts
---@field showGrid boolean?
---@field horizontalGrid boolean?
---@field getBadges fun(row:InventoryExtenderRedone.RowData):table


---@class InventoryExtenderRedone.ItemStackModalOpts
---@field itemName string?
---@field maxCount number
---@field selectedCount number?
---@field onConfirm fun(count:number) called after the popup is closed with the count confirmed


---@alias InventoryExtenderRedone.InfoBar.Provider fun(ctx:table):openmw.ui.LayoutOrElement?
---@alias InventoryExtenderRedone.WindowType 'Inventory'|'Container'|'Trade'|'Companion'


---@class InventoryExtenderRedone.Handlers
---@field onRowUse InventoryExtenderRedone.RowHandlerEntry[] handlers run by Inventory:onRowUse (use/equip action)
---@field onRowPickup InventoryExtenderRedone.RowHandlerEntry[] handlers run by Inventory:onRowPickup (pick-up action)

---@class InventoryExtenderRedone.RowHandlerEntry
---@field id string
---@field handler fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, windowType:string):boolean?


---@class InventoryExtenderRedone.Modifiers
---@field data InventoryExtenderRedone.RowDataModifierEntry[]
---@field badge InventoryExtenderRedone.RowBadgeModifierEntry[]

---@class InventoryExtenderRedone.RowDataModifierEntry
---@field id string
---@field modifier InventoryExtenderRedone.RowDataModifier The modifier function

---@alias InventoryExtenderRedone.RowDataModifier fun(row: InventoryExtenderRedone.RowData, ctx: InventoryExtenderRedone.Context, windowType: string)

---@class InventoryExtenderRedone.RowBadgeModifierEntry
---@field id string
---@field provider InventoryExtenderRedone.RowBadgeProvider The provider function. Must return icon path with optional color, or nil if no need for a badge.

---@alias InventoryExtenderRedone.RowBadgeProvider fun(row: InventoryExtenderRedone.RowData, ctx: InventoryExtenderRedone.Context):string|nil, openmw.util.Color?


---@class InventoryExtenderRedone.Overrides
---@field equipped InventoryExtenderRedone.EquippedOverrideEntry[]

---@class InventoryExtenderRedone.EquippedOverrideEntry
---@field id string
---@field handler fun(item:openmw.Object, actor:openmw.Object):boolean?


---@class InventoryExtenderRedone.BarterState
---@field selling table<string,InventoryExtenderRedone.BarterEntry?> keyed by item.id
---@field buying table<string,InventoryExtenderRedone.BarterEntry?> keyed by item.id
---@field currentMerchantOffer number
---@field currentBalance number
---@field success boolean?

---@class InventoryExtenderRedone.BarterEntry
---@field item openmw.Object
---@field stacks table?
---@field count number


---@class InventoryExtenderRedone.PickpocketSession
---@field active boolean
---@field resolved boolean
---@field targetId string
---@field visibleItems table<string,boolean>
