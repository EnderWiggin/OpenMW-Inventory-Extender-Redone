---@meta


---@class openmw.interfaces.Player
---@field InventoryExtenderRedone openmw.interfaces.InventoryExtenderRedone

---@class openmw.interfaces.InventoryExtenderRedone
---@field VERSION number
---@field Constants table? util/constants module (C.Colors, C.Strings, C.OPT_KEYS, …)
---@field Helpers table? util/helpers module (getItem*, isItemEquipped, doesItemFit, …)
---@field Roles table<string,InventoryExtenderRedone.Role> built-in window roles; the same table as config.defaults D.Roles, not a copy
---@field Modes table<string,InventoryExtenderRedone.ModeKey> built-in mode keys; the same table as config.defaults D.Modes, not a copy. Custom mode keys are mod-namespaced strings, never enum members
---@field allWindowsDisabled boolean live flag set by disableAllWindows; while true, show() is a no-op
---@field disableAllWindows fun(value:boolean) temporarily suppress IE windows; does NOT restore vanilla windows - nothing is shown
---@field show fun(windowName:InventoryExtenderRedone.Role, arg:any?) windowName is one of InventoryExtenderRedone.Role; arg is the target NPC/container/merchant
---@field hide fun(windowName:InventoryExtenderRedone.Role, arg:any?, force:boolean?)
---@field getWindow fun(windowName:InventoryExtenderRedone.Role):IER.Inventory? converts the name into UIToolkit's window id and asks its manager; returns the window's handler if that window is open, otherwise nil
---@field forEachOpenWindow fun(apply:fun(handler:IER.Inventory, wnd:UIToolkit.Window))
---@field getHoveredRow fun():InventoryExtenderRedone.RowData? the row under the cursor in the open IER window UIToolkit currently has input focus on, or nil when no window is focused, when the focused window belongs to another mod, or when it hovers nothing
---@field getContext fun():InventoryExtenderRedone.Context WindowManager.ctx - the shared mutable state, read by every toolkit file
---@field update fun() the single refresh trigger for all windows; mods that change item state or settings call this so tables rebuild
---@field resolveMode fun(role:InventoryExtenderRedone.Role, arg:any?, uiMode:string?):InventoryExtenderRedone.Mode?,InventoryExtenderRedone.Mode.RoleSpec? which mode governs this window role: applies() + priority winner, patches merged; returns the fully merged mode and that role's slots, or nil when no registered mode applies. uiMode is the engine UI mode at the moment the window opens (nil = interface) and is forwarded to applies(); the mode key is the value of handler.mode
---@field getCategories fun():InventoryExtenderRedone.Category[]
---@field getCategory fun(key:string):InventoryExtenderRedone.Category?
---@field getDraggingObject fun():openmw.Object? returns dragged object or nil if not dragging
---@field registerCategory fun(category:InventoryExtenderRedone.Category)
---@field unregisterCategory fun(key:string)
---@field isFavorite fun(itemOrId:string|openmw.Object):boolean
---@field registerEquippedOverride fun(id:string, handler:fun(item:openmw.Object, actor:openmw.Object):boolean?) called in reverse registration order until one returns non-nil
---@field registerRowDataModifier fun(id:string, handler:InventoryExtenderRedone.RowDataModifier)
---@field registerRowBadge fun(id:string, provider:InventoryExtenderRedone.RowBadgeProvider)
---@field registerRowUseHandler fun(id:string, handler:fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, role:InventoryExtenderRedone.Role):boolean?) called in reverse registration order until one returns false; handlers of the use/equip action (default: R, c_Activate, InfoBar "Use" button)
---@field registerRowPickupHandler fun(id:string, handler:fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, role:InventoryExtenderRedone.Role):boolean?) called in reverse registration order until one returns false; handlers of the pick-up action (default: left-click)
---@field registerMode fun(mode:InventoryExtenderRedone.Mode) register a custom mode spec into ctx.modes; a key colliding with a built-in is rejected (use patchMode to change a built-in)
---@field unregisterMode fun(key:InventoryExtenderRedone.ModeKey) drop a registered custom mode
---@field getMode fun(key:InventoryExtenderRedone.ModeKey):InventoryExtenderRedone.Mode? the spec as registered (built-in or custom), not the merged one
---@field getModes fun():InventoryExtenderRedone.Mode[] all registered specs, built-in and custom
---@field patchMode fun(key:InventoryExtenderRedone.ModeKey, patch:InventoryExtenderRedone.ModePatch) id-keyed patch merged into a built-in or custom mode at resolve time; list slots (sources/filters/infoBar) merge by id, other slots overwrite
---@field unpatchMode fun(key:InventoryExtenderRedone.ModeKey, id:string) remove a registered patch by the id passed to patchMode
---@field registerWindowRole fun(role:string, opts:InventoryExtenderRedone.RoleOpts) the only way to get a new window id (decision 1): registers role geometry and opens the window through UIToolkit; mode specs never register windows
---@field openMode fun(key:InventoryExtenderRedone.ModeKey, arg:any?) open the mode's role windows through UIToolkit.WindowManager.open only, never I.UI.setMode/addMode (decision 10); no-op while allWindowsDisabled
---@field closeMode fun(key:InventoryExtenderRedone.ModeKey, arg:any?) close the mode's role windows through UIToolkit; custom modes never call I.UI.removeMode
---@field getSellOffer fun(item:openmw.Object, count:number):number? predicted gold gain from selling count of item at the last-known Trade merchant (ctx.windowArgs.Trade, decision 1: one merchant at a time); nil when no merchant is known (0 would read as "free item"). Shares updateOffer's per-item math (effective value, getBarterOffer, 0.75 cap, NPC min) - price the queue plus a candidate and subtract the existing offer for incremental knapsacks
---@field getBuyOffer fun(item:openmw.Object, count:number):number? predicted gold spent buying count of item at the last-known Trade merchant; same math and nil-means-no-merchant contract as getSellOffer
---@field getSellRow fun(item:openmw.Object):InventoryExtenderRedone.RowData? the visible, enabled, not-yet-offered (isBartered false) row for item in the open Inventory window while its handler.mode snapshot is Barter; nil means "not tradeable right now": no window in Barter mode, filtered out of handler.table.filteredItems, or row.isDisabled(). Match is row.item.id == item.id or row.itemRecord.id == item.recordId (record fallback covers merged virtual merchant stacks)
---@field getBuyRow fun(item:openmw.Object):InventoryExtenderRedone.RowData? same query in the open Trade window while its handler.mode snapshot is Barter (the merchant side); the two sides are the two Barter role windows, requested directly by role
---@field queueSell fun(row:InventoryExtenderRedone.RowData, count:number) add count units to the sell side: records the InventoryExtenderRedone.BarterEntry { item, stacks = row.virtualStacks, count } keyed by row.item.id, clamped to row.getCount(), then reprices and fires IER_Update; pass a getSellRow row (isBartered false). Outside a trade (no known merchant in ctx.windowArgs.Trade) it does nothing and logs a warning
---@field queueBuy fun(row:InventoryExtenderRedone.RowData, count:number) same on the buy side (getBuyRow row); same no-merchant no-op + warning
---@field unqueueSell fun(row:InventoryExtenderRedone.RowData, count:number?) decrement the sell side by count, count omitted clears the entry; pass the offered (isBartered) row; same no-merchant no-op + warning
---@field unqueueBuy fun(row:InventoryExtenderRedone.RowData, count:number?) same on the buy side; same no-merchant no-op + warning
---@field clearBarterOffer fun() empty selling/buying and zero currentMerchantOffer/currentBalance in place (an open window's init-time closures keep holding the state table)
---@field offerBarter fun(opts:table?):boolean, skillGain:number? commit the current offer queue through the same sequence the Trade window's Offer button runs (empty check, gold caps, stolen interruption, haggle through the override chain, disposition, finalize, gold sound); merchant is ctx.windowArgs.Trade, refuses with a warning when no merchant is known; opts.closeWindow defaults true (Barter UI mode removal), false clears the queues in place instead; state.success is set in both cases
---@field registerHaggleOverride fun(id:string, handler:InventoryExtenderRedone.HaggleOverride) register a haggle modifier consulted before the acceptance dice roll, by both the Offer button and offerBarter; handlers run in reverse registration order, each non-nil return replaces the running chance and/or skillGain for its own field (stacking, last registered wins per field); returned chance clamped to [0,100] - 100 guarantees acceptance, 0 refusal; deliberately powerful, a mod can force-accept any offer


---@class InventoryExtenderRedone.Context
---@field handlers InventoryExtenderRedone.Handlers registered row action handlers, called in reverse registration order
---@field modifiers InventoryExtenderRedone.Modifiers registered modifiers
---@field overrides InventoryExtenderRedone.Overrides equipped-status overrides, called in reverse order until one returns non-nil
---@field modes table<string,InventoryExtenderRedone.Mode> custom mode specs registered through API.registerMode, keyed by mode key; built-in specs are not stored here, they live in toolkit/mode.lua Mode.Builtins
---@field modePatches table<string,InventoryExtenderRedone.ModePatch[]> registered mode patches per mode key, applied in reverse registration order
---@field dragAndDrop InventoryExtenderRedone.DragAndDrop ui/dragAndDrop.lua singleton (draggingObject, draggingCount, draggingActivationContext, lastHoveredObject, wrapper, …)
---@field windowArgs table<string,openmw.Object?> key is one of InventoryExtenderRedone.Role; value is the arg passed to show (target NPC/container/merchant)
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
---@field draggingActivationContext table? {role:InventoryExtenderRedone.Role, isBartered:boolean, modeKey:InventoryExtenderRedone.ModeKey} where the drag was started; modeKey is the IER mode that started it, read back by transferInto for autoEquip
---@field source openmw.Object? actor/container the dragged item came from
---@field resolveViewportDropTarget fun(self:InventoryExtenderRedone.DragAndDrop, position:openmw.util.Vector2, callback:fun(result, hitPos)) async raycast from viewport position; callback gets the raw hit and an eligible drop position (nil if surface too steep)
---@field getHoveredGameObject fun(self:InventoryExtenderRedone.DragAndDrop, position:openmw.util.Vector2) sets hoveredObject/hitPos from a viewport raycast
---@field startDrag fun(self:InventoryExtenderRedone.DragAndDrop, item:openmw.Object, source:openmw.Object?, count:number?, pickpocket:table?, activationContext:table?) sends IER_MoveInto with dragStart; lands as setDraggingObject via the IE_SetDraggingObject player event
---@field setDraggingObject fun(self:InventoryExtenderRedone.DragAndDrop, object:openmw.Object) enters drag state and creates ctx.cursorAttachedIcon (unless instantPickup)
---@field updatePosition fun(self:InventoryExtenderRedone.DragAndDrop) moves ctx.cursorAttachedIcon to the current cursor position
---@field transferInto fun(self:InventoryExtenderRedone.DragAndDrop, object:openmw.Object, destination:openmw.Object?, source:openmw.Object?, count:number?, pickpocket:InventoryExtenderRedone.Mode.PickpocketPayload?, modeKey:InventoryExtenderRedone.ModeKey?):boolean sends IER_MoveInto; autoEquip comes from that mode's drag slot, modeKey falls back to draggingActivationContext.modeKey; false if item doesn't fit or container is organic
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
---@field itemRecord {id:string, name:string, icon:string, isKey:boolean?, enchant:string?}
---@field getCount fun():number
---@field getNonDraggedCount fun():number
---@field StealChance number|fun():number pickpocket-only column: the steal-success chance for the stack
---@field sortCache table?
---@field SearchText string? lower-cased haystack for the search filter; the filter computes it lazily, a row data modifier may own the field to widen what search matches


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
---@alias InventoryExtenderRedone.Role 'Inventory'|'Container'|'Trade'|'Companion'
---@alias InventoryExtenderRedone.ModeKey 'Interface'|'Container'|'Pickpocket'|'Barter'|'Companion'|string


---@class InventoryExtenderRedone.RoleOpts window registration data for one role: identity and
---@field title string? window title; built-ins use the role name
---@field defaultPosition openmw.util.Vector2? layer-relative default position, converted by WindowManager.toAbsolute
---@field defaultSize openmw.util.Vector2? layer-relative default size
---@field minSize openmw.util.Vector2?
---@field draggable boolean?
---@field resizing boolean?
---@field pinnable boolean? built-ins all false; the Interface mode sets pinning at open


-- Mode specs are pure behavior: they never register windows, a new window role only comes
-- through API.registerWindowRole. Slots are keyed per window role because the Inventory
-- role appears in four modes and needs four different slot sets.
---@class InventoryExtenderRedone.Mode
---@field key InventoryExtenderRedone.ModeKey
---@field base InventoryExtenderRedone.ModeKey? inherit this mode's slots, e.g. Pickpocket base = Container
---@field title string? l10n key, or fun(handler:IER.Inventory, arg:any?):string
---@field applies fun(role:InventoryExtenderRedone.Role, arg:any?, ctx:InventoryExtenderRedone.Context, uiMode:string?):boolean? mode selection; the highest-priority applying mode wins
---@field priority number? higher wins when several modes apply; default 0
---@field syncCategory boolean? category switching syncs across open windows; default true
---@field drag InventoryExtenderRedone.Mode.Drag? mode-wide: drag is a ctx singleton, not per window
---@field lifecycle InventoryExtenderRedone.Mode.Lifecycle?
---@field event InventoryExtenderRedone.Mode.EventData? flat summary global.lua sees in event payloads
---@field roles table<string,InventoryExtenderRedone.Mode.RoleSpec> key is a window role

---@class InventoryExtenderRedone.Mode.RoleSpec one per window role in this mode
---@field sources InventoryExtenderRedone.Mode.Source[]? which items a window lists
---@field filters InventoryExtenderRedone.Mode.Filter[]? which of them are visible
---@field states InventoryExtenderRedone.Mode.State? per-row states (disabled/active/owned/badges)
---@field actions InventoryExtenderRedone.Mode.Actions? gate + effect only; shared row mechanics stay in the handler
---@field infoBar InventoryExtenderRedone.Mode.InfoBarSection[]? bottom strip sections, in order
---@field categories InventoryExtenderRedone.Mode.Categories?
---@field columns InventoryExtenderRedone.Mode.Columns?
---@field observer? fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):openmw.Object? observer for the row tooltip and AR. If absent or returns nil - player is used.
---@field hints InventoryExtenderRedone.Mode.Hints?
---@field pinnable boolean? default false; only the Interface Inventory window sets true
---@field storageSuffix string? built-ins keep the literal ':Container'/':Barter'/':Companion' - UIToolkit:WindowData keys are save identity, never derive from the mode key
---@field defaultStorage UIToolkit.WindowSaveData?

---@class InventoryExtenderRedone.Mode.Drag
---@field allowed boolean?
---@field autoEquip? fun(ctx:InventoryExtenderRedone.Context, object:openmw.Object, source:openmw.Object?, destination:openmw.Object?):openmw.Object?

---@class InventoryExtenderRedone.Mode.Lifecycle
---@field onOpened fun(handler:IER.Inventory, arg:any?, saved:table?)?
---@field onClosing fun(handler:IER.Inventory?, arg:any?, newMode:string?)? built-in modes fire from UiModeChanged (the window is already closed, so handler is nil), custom modes fire from WindowHandler:onClosed; newMode is the engine UI mode after the change (nil = mode stack empty)
---@field onClosed fun(handler:IER.Inventory)?

---@class InventoryExtenderRedone.Mode.EventData
---@field flags table<string,boolean> serializable summary (isBarter, isPickpocket, isCompanion, canTransfer, ...); key and role are stamped at open time

---@class InventoryExtenderRedone.ModePatch same shape as InventoryExtenderRedone.Mode; list slots become InventoryExtenderRedone.Mode.PatchList
---@field id string? required for API.unpatchMode
---@field key InventoryExtenderRedone.ModeKey? target mode key; set by API.patchMode when omitted
---@field title string?
---@field applies? fun(role:InventoryExtenderRedone.Role, arg:any?, ctx:InventoryExtenderRedone.Context, uiMode:string?):boolean? same call shape as Mode.applies; selection consults registered specs, so a patch normally omits it
---@field priority number?
---@field syncCategory boolean?
---@field drag InventoryExtenderRedone.Mode.Drag?
---@field lifecycle InventoryExtenderRedone.Mode.Lifecycle?
---@field event InventoryExtenderRedone.Mode.EventData?
---@field roles table<string,InventoryExtenderRedone.Mode.RoleSpecPatch>? key is a window role
---@field disable string[]? slot names to drop from the merged spec

---@class InventoryExtenderRedone.Mode.RoleSpecPatch
---@field sources InventoryExtenderRedone.Mode.PatchList?
---@field filters InventoryExtenderRedone.Mode.PatchList?
---@field states InventoryExtenderRedone.Mode.State?
---@field actions InventoryExtenderRedone.Mode.Actions?
---@field infoBar InventoryExtenderRedone.Mode.PatchList?
---@field categories InventoryExtenderRedone.Mode.Categories?
---@field columns InventoryExtenderRedone.Mode.Columns?
---@field observer? fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):openmw.Object? observer for the row tooltip and AR. If absent or returns nil - player is used.
---@field hints InventoryExtenderRedone.Mode.Hints?
---@field pinnable boolean?
---@field storageSuffix string?
---@field defaultStorage UIToolkit.WindowSaveData?
---@field disable string[]? slot names to drop from the merged spec

---@class InventoryExtenderRedone.Mode.PatchList
---@field add any[]? appended
---@field replace any[]? id-keyed: replaces the entry with the same id, appends when the id is new
---@field remove string[]? ids to drop

---@class InventoryExtenderRedone.Mode.Source
---@field id string
---@field get? fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):openmw.Object[]? virtual sources return {stacks:openmw.Object[], totalCount:number} instead
---@field virtual boolean?
---@field isBartered boolean? the "other side" flag
---@field isOwned? boolean?|fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):boolean?
---@field enabled? fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):boolean?
---@field filter? fun(item:openmw.Object, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):boolean?

---@class InventoryExtenderRedone.Mode.Filter
---@field id string
---@field fn? fun(row:InventoryExtenderRedone.RowData, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):boolean?
---@field structural boolean? true for the window-level filters that stay in the handler (search/category/draggedItem)

---@class InventoryExtenderRedone.Mode.State
---@field isDisabled? fun(row:InventoryExtenderRedone.RowData, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):boolean?|InventoryExtenderRedone.Mode.State[] OR-ed when a list
---@field isActive? fun(row:InventoryExtenderRedone.RowData, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):boolean?
---@field isOwned? fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):boolean? tooltip ownership
---@field badges InventoryExtenderRedone.RowBadgeProvider[]? mode-scoped sugar over API.registerRowBadge

---@class InventoryExtenderRedone.Mode.PickpocketPayload
---@field target openmw.Object the session the roll belongs to

---@class InventoryExtenderRedone.Mode.Action
---@field enabled? fun(row:InventoryExtenderRedone.RowData, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):boolean?
---@field perform? fun(row:InventoryExtenderRedone.RowData, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context, count:number?):boolean? default effect; false stops the chain
---@field transfer? fun(row:InventoryExtenderRedone.RowData, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context, count:number?):boolean? the Alt-held variant
---@field source? fun(row:InventoryExtenderRedone.RowData, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):openmw.Object? IER_UseItem payload: which inventory the item moves from first
---@field pickpocket? fun(row:InventoryExtenderRedone.RowData, handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):InventoryExtenderRedone.Mode.PickpocketPayload? IER_UseItem payload: the session the roll belongs to

---@class InventoryExtenderRedone.Mode.Actions
---@field use InventoryExtenderRedone.Mode.Action?
---@field pickup InventoryExtenderRedone.Mode.Action?
---@field favorite InventoryExtenderRedone.Mode.Action?
---@field takeAll InventoryExtenderRedone.Mode.Action?
---@field dispose InventoryExtenderRedone.Mode.Action?
---@field close InventoryExtenderRedone.Mode.Action?

---@class InventoryExtenderRedone.Mode.InfoBarSection
---@field id string encumbrance, gold, armorRating, filler, use, dispose, takeAll, profit, barterControls, close
---@field create? fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):InventoryExtenderRedone.InfoBar.Provider build-once part (buttons, bars); returns the per-frame provider
---@field provider? InventoryExtenderRedone.InfoBar.Provider per-frame value/visibility, returns nil to hide (stateless sections use this directly)
---@field cleanup fun()? runs in InfoBar:beforeElementDestroy()
---@field before string? order before this section id
---@field after string? order after this section id

---@class InventoryExtenderRedone.Mode.Categories
---@field available? fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context):InventoryExtenderRedone.Category[]? default I.InventoryExtenderRedone.getCategories()
---@field default string?
---@field map table<string,string>? role -> categoryKey, replaces getSyncedCategoryKey + getOpenedCategoryKey

---@class InventoryExtenderRedone.Mode.Columns
---@field hiddenColumns table<string,boolean>? columnId -> hidden, merged with user visibility

---@alias InventoryExtenderRedone.Mode.Hints fun(handler:IER.Inventory, ctx:InventoryExtenderRedone.Context, base:UIToolkit.Controller.HintList):UIToolkit.Controller.HintList?

---@class InventoryExtenderRedone.Mode.Defaults what a mode gets when it omits a slot
---@field priority number?
---@field syncCategory boolean?
---@field drag InventoryExtenderRedone.Mode.Drag?
---@field RoleSpec InventoryExtenderRedone.Mode.RoleSpec? per-role slot defaults, applied under every RoleSpec


---@class InventoryExtenderRedone.Handlers
---@field onRowUse InventoryExtenderRedone.RowHandlerEntry[] handlers run by Inventory:onRowUse (use/equip action)
---@field onRowPickup InventoryExtenderRedone.RowHandlerEntry[] handlers run by Inventory:onRowPickup (pick-up action)

---@class InventoryExtenderRedone.RowHandlerEntry
---@field id string
---@field handler fun(row:InventoryExtenderRedone.RowData, ctx:InventoryExtenderRedone.Context, role:InventoryExtenderRedone.Role):boolean?


---@class InventoryExtenderRedone.Modifiers
---@field data InventoryExtenderRedone.RowDataModifierEntry[]
---@field badge InventoryExtenderRedone.RowBadgeModifierEntry[]

---@class InventoryExtenderRedone.RowDataModifierEntry
---@field id string
---@field modifier InventoryExtenderRedone.RowDataModifier The modifier function

---@alias InventoryExtenderRedone.RowDataModifier fun(row: InventoryExtenderRedone.RowData, ctx: InventoryExtenderRedone.Context, role: InventoryExtenderRedone.Role)

---@class InventoryExtenderRedone.RowBadgeModifierEntry
---@field id string
---@field provider InventoryExtenderRedone.RowBadgeProvider The provider function. Must return icon path with optional color, or nil if no need for a badge.

---@alias InventoryExtenderRedone.RowBadgeProvider fun(row: InventoryExtenderRedone.RowData, ctx: InventoryExtenderRedone.Context):string|nil, openmw.util.Color?


---@class InventoryExtenderRedone.Overrides
---@field equipped InventoryExtenderRedone.EquippedOverrideEntry[]
---@field haggle InventoryExtenderRedone.HaggleOverrideEntry[]

---@class InventoryExtenderRedone.EquippedOverrideEntry
---@field id string
---@field handler fun(item:openmw.Object, actor:openmw.Object):boolean?

---@class InventoryExtenderRedone.HaggleOverrideEntry
---@field id string
---@field handler InventoryExtenderRedone.HaggleOverride

---@alias InventoryExtenderRedone.HaggleOverride fun(npc:openmw.Object, playerOffer:number, merchantOffer:number, chance:number):chance:number?, skillGain:number? chance is IER's computed acceptance threshold (roll > chance refuses, roll in [1,100]); a returned chance replaces the running value and is clamped to [0,100] by the chain, a returned skillGain replaces the price-delta-derived gain


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

-- util/logger module: a tagged printer (get(tag)) or the bare module both expose these level
-- methods; each takes varargs and prints like print, prefixing "<E> "/"<W> "/"<I> "/"<D> "
-- (the level letter) and "[tag] " when tagged.
---@class InventoryExtenderRedone.Printer
---@field error fun(...:any)
---@field warn fun(...:any)
---@field info fun(...:any)
---@field debug fun(...:any)

---@class InventoryExtenderRedone.Logger : InventoryExtenderRedone.Printer
---@field get fun(tag:string):InventoryExtenderRedone.Printer
