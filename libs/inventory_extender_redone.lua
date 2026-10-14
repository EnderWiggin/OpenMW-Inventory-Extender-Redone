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
---@field registerCategory fun(category:InventoryExtenderRedone.Category)
---@field unregisterCategory fun(key:string)
---@field isFavorite fun(itemOrId:string|openmw.Object):boolean
---@field registerEquippedOverride fun(id:string, handler:fun(item:openmw.Object, actor:openmw.Object):boolean?) called in reverse registration order until one returns non-nil
---@field registerRowUseHandler fun(id:string, handler:fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, windowType:string):boolean?) called in reverse registration order until one returns false
---@field registerRowPickupHandler fun(id:string, handler:fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, windowType:string):boolean?) called in reverse registration order until one returns false


---@class InventoryExtenderRedone.Context
---@field handlers InventoryExtenderRedone.Handlers registered row action handlers, called in reverse registration order
---@field overrides InventoryExtenderRedone.Overrides equipped-status overrides, called in reverse order until one returns non-nil
---@field dragAndDrop table ui/dragAndDrop.lua singleton (draggingObject, draggingCount, draggingActivationContext, lastHoveredObject, wrapper, …)
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
---@field onRowUse InventoryExtenderRedone.RowHandlerEntry[]
---@field onRowPickup InventoryExtenderRedone.RowHandlerEntry[]

---@class InventoryExtenderRedone.RowHandlerEntry
---@field id string
---@field handler fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, windowType:string):boolean?


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
---@field totalBalance number
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
