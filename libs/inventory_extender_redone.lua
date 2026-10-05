---@meta


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


---@class InventoryExtenderRedone.InfoBarOpts
---@field maxHeight number?

---@class InventoryExtenderRedone.InfoBar : UIToolkit.Component
---@field create fun(opts:InventoryExtenderRedone.InfoBarOpts):InventoryExtenderRedone.InfoBar
---@field addProvider fun(self:InventoryExtenderRedone.InfoBar, provider:InventoryExtenderRedone.InfoBar.Provider):InventoryExtenderRedone.InfoBar provider must return layout or element or nil. It is also responsible for destroying old element if necessary.

---@class InventoryExtenderRedone.ItemTableOpts: UIToolkit.SortedListOpts
---@field showGrid boolean?
---@field horizontalGrid boolean?


---@alias InventoryExtenderRedone.InfoBar.Provider fun(ctx:table):openmw.ui.LayoutOrElement?
