# Public API — Inventory Extender Redone

Inventory Extender Redone is a UI + logic mod: it replaces OpenMW's `Inventory`, `Container`,
`Trade` (barter) and `Companion` windows with sortable, filterable, searchable item tables, plus
game-logic fixes around them. It ships no ESM and no records — everything is Lua.

Other mods consume it through one interface:

```lua
local IER = I.InventoryExtenderRedone
```

The authoritative shape of every public type lives in `libs/inventory_extender_redone.lua` (a
LuaLS `---@meta` file, not shipped); this document is its human-facing companion.

## Overview and quick start

This reference describes API version 4 (`IER.VERSION`). A mod that uses this surface should check
the version first, then extend the mod through the registration points below: `patchMode` to
change an existing mode, `registerMode` for a new behavior set, `registerWindowRole` for a new
window, `openMode` to open a custom mode's windows.

```lua
local IER = I.InventoryExtenderRedone

if IER.VERSION < 4 then
    return   -- this reference describes API version 4
end

-- Hide gold rows in the player's window
IER.patchMode(IER.Modes.Interface, {
    id = 'myMod_noGold',
    roles = {
        Inventory = {
            filters = { add = { {
                id = 'myMod_noGold',
                fn = function(row) return not IER.Helpers.isGold(row.item) end,
            } } },
        },
    },
})
```

## Concepts: windows (roles) and modes

Two concepts describe every window:

| Concept | Question it answers | How a mod changes it |
| --- | --- | --- |
| **Role** | *which window* is this? (`Inventory`, `Trade`, `Container`, `Companion`, or one you add) | `IER.registerWindowRole` |
| **Mode** | *which behavior set* governs it? (`Interface`, `Container`, `Pickpocket`, `Barter`, `Companion`, or one you add or patch) | `IER.patchMode` / `IER.registerMode` |

Both are decided when the window opens; they are not read from the engine while the window runs.
A mode spec is pure behavior — it never registers a window, and a new window role only comes
through `IER.registerWindowRole`. This is why a mode's slots are keyed per window role: the
`Inventory` role appears in four modes and needs a different slot set in each.

At open, `IER.resolveMode` picks the highest-priority mode whose `applies()` matches, merges its
`base` chain and any registered patches, and returns `(mode, roleSpec)`. The window handler
snapshots the result into `handler.mode` (the mode key) and `handler.slots` (that role's merged
`RoleSpec`). After that, read the snapshot: `handler.mode` tells you which behavior set the open
window is using. `I.UI.getMode()` can disagree — a pinned `Interface` window stays open while the
engine mode is `nil`, and during a pickpocket session the engine sits in `Container` mode while
`handler.mode` is `'Pickpocket'`.

Built-in mode keys equal the engine UI mode strings, so `I.UI.removeMode(IER.Modes.Container)`
works. `Pickpocket` and custom keys are IER-side only and are never passed to `I.UI`.

### Anatomy of a mode spec

A mode is an `InventoryExtenderRedone.Mode` table:

| Slot | Meaning |
| --- | --- |
| `key` | mode key; custom keys should be namespaced by your mod |
| `base` | inherit another mode's slots (e.g. `Pickpocket` inherits `Container`) |
| `applies(role, arg, ctx, uiMode)` | mode selection: which windows this mode governs |
| `priority` | higher wins when several modes apply (default 0). Equal priorities are unordered, so a custom mode that overlaps a built-in must out-prioritize it |
| `drag` | `{ allowed, autoEquip }` — whether dragging is allowed in this mode |
| `lifecycle` | `onOpened(handler, arg, saved)`, `onClosing(handler?, arg, newMode)` — pre-close, fires only when the engine's UI mode changes (built-in modes; `handler` is nil, and it also fires on mode-to-mode transitions); `onClosed(handler)` — post-close, once per closing window, on every close path including `IER.hide` and custom modes, but not for a pinned window. A chained list slot: entries chain instead of replacing each other, the chain runs the most recently merged entry first and the built-in entry (id = the mode key) last, and a callback returning `false` cuts the rest. A plain hook table is sugar for one added entry |
| `event` | `{ flags }` — serializable summary other mods see in event payloads |
| `roles` | `table<role, RoleSpec>` — one slot-set per window role |

A `Mode.RoleSpec` is the per-window behavior:

| Slot | Type | Meaning |
| --- | --- | --- |
| `sources` | `Mode.Source[]` | which items a window lists |
| `filters` | `Mode.Filter[]` | which of them are visible |
| `states` | `Mode.State` | per-row states (`isDisabled`, `isOwned`) |
| `actions` | `Mode.Actions` | gates and effects for the two row actions (`use`/`pickup`); the bulk affordances (`takeAll`, `dispose`, `close`) are `infoBar` sections and the favorite toggle is a shared handler mechanic, not a mode slot |
| `infoBar` | `Mode.InfoBarSection[]` | bottom-strip sections, in order |
| `columns` | `Mode.Column[]` | the window's columns, in display order; absent means the built-in default chain (all columns except `StealChance`) |
| `target` | `fun(handler, ctx): openmw.Object?` | the window's actor — whose inventory is listed, whose equipped gear/encumbrance/armor rating/gold the info bar and sorting read, whose name the title shows. Absent or returning `nil` means the built-in rule: the player for the `Inventory` role, the open argument for any other role. An open window is retargeted through `handler:setTarget` |
| `observer` | `fun(handler, ctx): openmw.Object?` | who the rows are read as — the actor whose active magic effects the `AR` column and the row tooltips are computed against. Absent or returning `nil` means the player. The `Companion` role's spec sets the window's target, so a companion's gear is rated as that NPC wears it |
| `hints` | `Mode.Hints` | controller hints |
| `pinnable` | boolean | only the `Interface` Inventory window sets true |
| `storageSuffix` | string | suffix of this window's saved data (see Notes) |
| `defaultStorage` | `UIToolkit.WindowSaveData` | saved-state fallbacks |

**List slots vs overwrite slots.** The list slots `sources`, `filters`, `infoBar`, `lifecycle` and
`columns` merge by id; every other slot is a whole-slot overwrite. A spec that wants part of a list
slot uses the patch list ops (`{ add, replace, remove, set }`); in a **spec** a plain array replaces
the whole slot, while in a **patch** a plain array is sugar for `{ add = array }` — a patch always
merges onto the resolved chain, and `{ set = … }` is the explicit whole-slot replacement.

**Specs name built-in parts by id.** A slot entry can name a built-in part by `id` or carry its
own behavior; when it does both, the entry's own fields win, so you can reuse a built-in part with
one field changed. The part library is reachable by a side-effect require:

```lua
local Mode = require('scripts.InventoryExtenderRedone.toolkit.mode')
-- Mode.Sources  : target, self, merchantOfTarget, merchantOfOther
-- Mode.Filters  : barterAllowed, barterOffered, barterInventoryForeign,
--                 barterTraderForeign, barterTradeEquipped, pickpocketVisibility
-- Mode.Actions  : usePlayer, useTarget, useTargetPickpocket, useBarterInventory, useBarterTrade,
--                 pickupInterface, pickupContainerInventory, pickupContainerTarget,
--                 pickupCompanionInventory, pickupCompanionTarget, pickupBarterInventory,
--                 pickupBarterTrade, pickpocketTake
-- Mode.Info     : encumbrance, gold, armorRating, filler, use, dispose, takeAll, putAll, profit,
--                 close, barterCancel, barterControls
-- Mode.Columns  : Icon, Name, Type, Class, AR, Damage, Quality, Condition, Weight,
--                 Weight_Total, Value, V/W, StealChance
```

## Changing window behavior

There are three registration points, and they compose at open time.

### Patch a mode — `IER.patchMode` (preferred)

```lua
---@param key InventoryExtenderRedone.ModeKey  built-in or custom mode key
---@param patch InventoryExtenderRedone.ModePatch  same shape as Mode
IER.patchMode(key, patch)
```

The patch merges into the spec at resolve time, in reverse registration order (the most recently
registered patch wins). A patch registered mid-session takes effect from the next open; it does not
change an already-open window's snapshot. Patches change slots, never which mode applies. The
patch's `id` is required if you want to remove it later with `unpatchMode`.

In a patch's list slot, a plain array is sugar for `{ add = array }` so the patch always merges onto
the resolved chain; a table with `add`/`replace`/`remove`/`set` applies operations
(`InventoryExtenderRedone.Mode.PatchList`):

- `add` — append entries. An entry can carry `before`/`after` to position itself against an existing
  id. Ordering is load-bearing for `infoBar` (the `filler` stretch gap lays out the strip), for
  `columns` (left-to-right display order) and for `lifecycle` (the chain runs in reverse merged order
  so a later entry can veto the built-in hook).
- `replace` — id-keyed: replaces the entry with the same id, appends when the id is new.
- `remove` — ids to drop.
- `set` — explicit whole-chain replacement; `add`/`replace`/`remove` then apply on top of it.
- `disable` — on a patch or a role patch: whole slot names to drop from the merged spec.

Example: add a Crafting Framework button to the bottom strip of the player's window. `create`
builds the part once per open and returns the per-frame provider; the provider returns `nil` to
hide the section; `cleanup` runs when the info bar is destroyed.

```lua
IER.patchMode(IER.Modes.Interface, {
    id = 'myMod_cf_button',                       -- id is required for unpatchMode
    roles = {
        Inventory = {
            infoBar = { add = { {                 -- list-slot op: append a section
                id = 'ier_cf',
                create = function(handler, ctx)
                    btn = I.UIToolkit.Components.imageButton {
                        name = 'open_cf', icon = 'icons/m/misc_hammer10.dds',
                        onClick = function() IER.hide(IER.Roles.Inventory); CF.openCraftingWindow() end,
                    }
                    return function()
                        if not btn then return nil end
                        if IER.getDraggingObject() then return nil end   -- provider returns nil to hide
                        return btn.element
                    end
                end,
                cleanup = function()
                    if not btn then return end
                    I.UIToolkit.queueDestroy(btn.element); btn = nil
                end,
            } } },
        },
    },
})
```

A patch can also replace a built-in part with its own behavior and add lifecycle callbacks. `lifecycle`
is a chained list slot: a patch writing a plain hook table becomes one entry added to the chain, so
the built-in hooks stay — the chain runs the most recently merged entry first and the built-in entry
(its id is the mode key) last, and returning `false` from a hook cuts the rest, which is how a mod
vetoes a built-in hook without re-declaring it.

```lua
IER.patchMode(IER.Modes.Barter, {
    id = 'ier-trade-redone',
    lifecycle = { onOpened = function(handler, trader) ... end, onClosed = function(handler) ... end },
    roles = {
        Trade = {
            filters = { replace = { { id = 'barterOffered', fn = function(row, handler, ctx)
                return mercantile.base >= ALL_ITEMS_SKILL or barterOffered(row, handler, ctx)
            end } } },
            infoBar = { add = { { id = 'ier_trade_invest', before = 'barterCancel', create = ..., cleanup = ... } } },
        },
    },
})
```

Name the entry explicitly (`lifecycle = { add = { { id = 'myMod_close', onClosed = ... } } }`) only when
you need to position against, replace or remove a built-in entry by id — `remove = { 'Barter' }` drops
that mode's built-in hooks.

`columns` is a list slot too, so a patch adds to the window's resolved chain rather than replacing it.
The row data behind a new column id comes from `registerRowDataModifier`:

```lua
IER.patchMode(IER.Modes.Pickpocket, {
    id = 'myMod_charges',
    roles = { Container = { columns = { add = { {
        id = 'Charges', name = 'Column_Charges', sort = { numeric = true },
        width = 60, align = ui.ALIGNMENT.End, descending = true, after = 'Value',
        render = ..., update = ...,
    } } } } },
})
```

Remove a patch by the id passed to `patchMode`:

```lua
IER.unpatchMode(IER.Modes.Interface, 'myMod_cf_button')
```

### Register a whole custom mode — `IER.registerMode`

A custom mode is a new behavior set with its own `applies()` and `priority`. If it overlaps a
built-in, it must out-prioritize it. Its windows open through `IER.openMode`; the engine UI mode
is not touched.

```lua
---@param mode InventoryExtenderRedone.Mode  must carry a key; a key colliding with a built-in is rejected
IER.registerMode(mode)
IER.unregisterMode(key)
```

```lua
local spec = {
    key = 'MyMod_Stash',
    -- base = ... optional: inherit another mode's slots
    applies = function(role, arg, ctx, uiMode)
        return role == 'Stash'                    -- governs the new role
    end,
    priority = 1,
    roles = {
        Stash = {
            sources = { { id = 'target' } },      -- reuse a built-in source part
            filters = { add = { { id = 'myNoGold', fn = function(row, handler, ctx)
                return not IER.Helpers.isGold(row.item) end } } },   -- inline behavior
            infoBar = { { id = 'encumbrance' }, { id = 'filler' }, { id = 'close' } },
        },
    },
}
IER.registerMode(spec)
```

Open and close a custom mode's windows purely IER-side, through the window manager of the UI
library:

```lua
IER.openMode('MyMod_Stash', targetContainer)   -- no-op while allWindowsDisabled
IER.closeMode('MyMod_Stash', targetContainer)
```

### Register a new window role — `IER.registerWindowRole`

```lua
---@param role string
---@param opts InventoryExtenderRedone.RoleOpts  geometry: title, defaultPosition, defaultSize,
---          minSize, draggable, resizing, pinnable
IER.registerWindowRole(role, opts)
```

Default geometry is layer-relative and converted to absolute pixels by the UI library; a player's
saved position/size wins over these fallbacks. The window id is always `InventoryExtender:<Role>`.

```lua
local util = require 'openmw.util'
IER.registerWindowRole('Stash', {
    title = 'Stash',
    defaultPosition = util.v2(0.5, 0.5),
    defaultSize     = util.v2(0.4, 0.4),
    minSize         = util.v2(300, 200),
    draggable = true,
    resizing  = true,
    pinnable  = false,
})
```

A new role has no behavior until a mode spec names it in its `roles[<Role>]` slot — see above.

## How a mode is resolved when a window opens

```lua
---@param role InventoryExtenderRedone.Role
---@param arg any?  the target NPC/container/merchant
---@param uiMode string?  engine UI mode at the moment the window opens (nil = interface)
---@return InventoryExtenderRedone.Mode?  fully merged mode, nil when nothing applies
---@return InventoryExtenderRedone.Mode.RoleSpec?  this role's merged slots
local mode, roleSpec = IER.resolveMode(IER.Roles.Inventory, arg, I.UI.getMode())
```

The resolution has four steps:

1. **Selection** — every registered mode (built-in and custom) is asked
   `applies(role, arg, ctx, uiMode)`; the highest-`priority` match wins. Equal priorities are
   unordered, so a custom mode that overlaps a built-in must out-prioritize it.
2. **Spec merge** — the mode's `base` chain first (own slots win over the base's), then the
   patches registered for the mode key, applied in reverse registration order.
3. **Role defaults** — the role's slot set is filled in with defaults for anything it does not
   name.
4. **Part resolution** — each `sources`/`filters`/`actions`/`infoBar` entry is resolved against
   the part library; the entry's own fields win over the library part. This happens once at open.

`IER.getMode(key)` returns the spec as registered (built-in or custom), not the merged one.
`IER.getModes()` returns all registered specs.

## Row hooks

These hooks wrap the default row behavior for every window, regardless of mode. They are global
registration lists, called in reverse registration order. Re-registering the same `id` replaces
the existing entry (`id`s are case-insensitive).

| Function | Handler signature | Default behavior | Chain stops when a handler returns |
| --- | --- | --- | --- |
| `IER.registerRowUseHandler(id, fn)` | `fn(row, ctx, role): boolean?` | equip/use the item (R, or left-click when swapped) | `false` |
| `IER.registerRowPickupHandler(id, fn)` | `fn(row, ctx, role): boolean?` | pick up the item (Alt transfers; in barter, add/remove from the offer) | `false` |
| `IER.registerRowDataModifier(id, fn)` | `fn(row, ctx, role)` | mutate `RowData` fields (e.g. `row.Type`) | — |
| `IER.registerRowBadge(id, fn)` | `fn(row, ctx): string?, color?` | draw a row badge; return an icon path (+ optional color) or `nil` | — |
| `IER.registerEquippedOverride(id, fn)` | `fn(item, actor): boolean?` | override equipped status | first non-`nil` return wins |

```lua
-- katars: re-types hand-to-hand weapon rows
IER.registerRowDataModifier('katars', function(row)
    local hybrid = H2H.getHybridDefForRecordId(row.itemRecord.id)
    if hybrid and hybrid.primarySkill == 'handtohand' then
        row.Type = l10n 'Type_Katar'
    end
end)

-- toxicology: a poison badge on coated weapons
IER.registerRowBadge('toxicology-coatings', function(row)
    if Weapon.objectIsInstance(row.item) and toxicology.getActivePoisons(row.item) then
        return 'icons/Toxicology/poison_badge.dds'
    end
end)
```

About `RowData` rows:

- A field value may be a plain value or a function; every consumer must handle both
  (`type(v) == 'function' and v() or v`).
- `row.id` is the item-object id (stack identity); `row.itemRecord.id` is the record id. Do not
  mix them.

## Categories

Twelve built-in categories exist: `Favorites`, `All`, `Weapon`, `Armor`, `Clothing`, `Potion`,
`Ingredient`, `Scroll`, `Book`, `Key`, `Tool`, `Misc`. Mods may add or remove them.

```lua
IER.getCategories()             -- InventoryExtenderRedone.Category[]
IER.getCategory(key)            -- case-insensitive lookup -> Category?
IER.registerCategory(category)  -- replaces an existing category with the same key; prepend puts it first
IER.unregisterCategory(key)     -- case-insensitive
```

A `Category` is `{ key, name, icon | iconPackRelativePath, filter, hiddenColumns, prepend,
defaultSelected }`. `iconPackRelativePath` resolves against the active icon pack (preferred);
`icon` is an absolute path. `Favorites` has no filter and applies only to the player's own
window; in other windows it behaves like `All`.

## Barter API

All barter-related methods live in the `IER.Barter` subtable, so the interface root stays about
windows, modes and categories. One merchant at a time: no barter function takes a role or merchant
parameter. The merchant is `ctx.windowArgs.Trade` — the `arg` last passed to `show(IER.Roles.Trade, merchant)`.
**Last-known, not current**: `show` with a nil `arg` keeps the previous value, and nothing clears it
when the window closes, so it may name a merchant whose window is gone. With no merchant known, the
queue functions do nothing and log a warning, and the price queries return `nil` (`0` would read as
"free item"). A mod that needs a merchant other than that one names it through `setPartner` (below).

### Find the row for an item

```lua
---@param item openmw.Object
---@return InventoryExtenderRedone.RowData?
IER.Barter.getSellRow(item)   -- your side: the row in the open Inventory window while its mode is Barter
IER.Barter.getBuyRow(item)    -- merchant side: the row in the open Trade window while its mode is Barter
```

A row comes back only while it is visible and enabled (in `handler.table.filteredItems`,
`row.isDisabled()` false); `nil` means "not tradeable right now": no window in Barter mode,
filtered out, or disabled. The queries are split because the two windows apply different filter
sets and an already-offered item is hidden in your window but visible in the merchant's as an
`isBartered` row. Matching falls back to the record id, so a merged virtual merchant stack matches
any object of that record.

### Predict the price

```lua
---@param item openmw.Object
---@param count number
---@return number?  nil when no merchant is known
IER.Barter.getSellOffer(item, count)   -- predicted gold gain from selling
IER.Barter.getBuyOffer(item, count)    -- predicted gold spent buying
IER.Barter.getBarterBalance()          -- current offer balance in gold (committing now nets this)
```

These share `updateOffer`'s per-item math (effective value, merchant offer, 0.75 cap, NPC rule), so
a mod can price a candidate against the current queue before committing: price the queue plus the
candidate and subtract the existing offer.

### Repricing — `IER.Barter.registerPriceOverride`

```lua
---@param id string
---@param handler fun(npc, item, count, buying, price): price?
IER.Barter.registerPriceOverride(id, handler)
```

The chain is consulted **inside `itemOffer`**, so the queue (`updateOffer`), the prediction
exports and the committed gold (`finalizeBarter`) all see the same repriced value — one
implementation, no drift. Handlers receive the barter direction: `buying` is true when the
player buys `item` from the merchant (the buy side), false when selling it to the merchant
(the sell side) — one handler can price the two directions differently. `price` is the final
per-item contribution magnitude (after the 0.75 cap and the NPC min/max rule; `updateOffer`
applies the sign per side). Handlers run in reverse registration order; each non-nil return
replaces the running magnitude, so modifiers **compose** and the last registered wins.
Returned prices are clamped to `[0, infinity)`: `0` means a free item; a negative would flip
the offer sign and corrupt the balance scalars.

```lua
-- a generous trader: 10% cheaper when selling to them, 10% pricier when buying from them
IER.Barter.registerPriceOverride('myMod_generousTrader', function(npc, item, count, buying, price)
    return buying and price * 1.1 or price * 0.9
end)
```

### Name the participants — `IER.Barter.setPartner`

By default a barter runs entirely between the player and `ctx.windowArgs.Trade`. A **partner
descriptor** names the actors it runs between, so an offer can price against one merchant and move
items to and from another actor — a follower's goods sold to the merchant, the merchant's stock
bought into the follower's inventory, while every price still uses the player's mercantile.

```lua
---@param descriptor InventoryExtenderRedone.BarterPartner?  { pricing, party, gold }, all optional
IER.Barter.setPartner(descriptor)   -- nil clears it
IER.Barter.clearPartner()           -- back to vanilla actors
IER.Barter.getPartner()             -- the stored descriptor, or nil; do not mutate what this returns
```

| Field | Drives | Omitted means |
| --- | --- | --- |
| `pricing` | haggle, per-item offer, the merchant's barter-gold pool, disposition change, stolen victim, sell destination | `ctx.windowArgs.Trade`, read when the offer is priced |
| `party` | sell source, buy destination | the player |
| `gold` | who pays a negative balance and who receives a positive one | the player |

`pricing` is resolved when the offer is priced, never stored when the descriptor is set, so a mod
that does not name it follows the last-known merchant. `party` and `gold` are filled with the player
at set time — `setPartner({})` is therefore **not** the same observable state as clearing: with a
descriptor present the Inventory window's gold readout names the descriptor's gold actor, with none
it falls back to the window's own actor. Pass `gold` explicitly when that readout matters.

The merchant's own barter pool stays bound to `pricing`: `getBarterGold`/`setBarterGold` read the
NPC that priced the offer, and pricing one merchant while draining another has no coherent meaning.

The descriptor only says where items go; the window still has to show them, and that is what
`handler:setTarget` does (see *Windows and context*). The Barter mode's Inventory role lists its
target's items plus the merchant's stock, and the Trade role lists the merchant's stock plus the
descriptor's `party` as offered rows:

```lua
IER.show(IER.Roles.Trade, merchant)                    -- opens both Barter windows
IER.getWindow(IER.Roles.Inventory):setTarget(follower) -- the sell side is the follower's items
IER.Barter.setPartner({ party = follower })            -- pricing stays the last-known merchant
IER.update()                                           -- one refresh after the batch of writes
```

`setPartner` does not refresh the windows, same as `clearBarterOffer`.

### Queue the offer

```lua
IER.Barter.queueSell(row, count)      -- add to the sell side (row from getSellRow, isBartered false)
IER.Barter.queueBuy(row, count)       -- add to the buy side (row from getBuyRow)
IER.Barter.unqueueSell(row, count?)   -- retract from the sell side (the offered, isBartered row)
IER.Barter.unqueueBuy(row, count?)    -- retract from the buy side; count omitted clears the entry
IER.Barter.clearBarterOffer()         -- empty both sides and zero the scalars, leaving any open window alone
```

Input is a `RowData`, not a raw item: `row.virtualStacks` is carried into the queue entry
`{ item, stacks, count }` keyed by `item.id`, and `finalizeBarter` walks `entry.stacks` restock-aware
— a missing `stacks` on a virtual row silently mis-moves items. Counts clamp to `row.getCount()`.
Queueing reprices the offer and refreshes the windows.

### Commit — `IER.Barter.offerBarter`

```lua
---@param opts table?  { closeWindow = boolean? } default true
---@return boolean accepted
---@return number? skillGain
IER.Barter.offerBarter(opts)
```

Runs the same sequence the Trade window's Offer button runs: empty check, PC/NPC gold caps, stolen
"that's mine" interruption, haggle (through the override chain below), disposition change, refusal
message, transfer, gold sound. `closeWindow = true` removes the Barter UI mode as usual; `false`
clears the queues in place instead so an open Trade window shows an empty offer. `barterState.success`
is set in both cases, so the "thanks" line still fires when the player eventually leaves.

Typical autosell shape:

```lua
IER.show(IER.Roles.Trade, merchant)              -- opens both Barter windows
for _, item in ipairs(junk) do
    local row = IER.Barter.getSellRow(item)
    if row then
        -- incremental pricing: value of queue + candidate minus current offer
        local gain = IER.Barter.getSellOffer(item, row.getCount()) - IER.Barter.getBarterBalance()
        if worth(gain) then
            IER.Barter.queueSell(row, row.getCount())
        end
    end
end
local accepted = IER.Barter.offerBarter({ closeWindow = false })
IER.hide(IER.Roles.Trade)                        -- close the windows yourself
```

### Haggle override — `IER.Barter.registerHaggleOverride`

```lua
---@param id string
---@param handler fun(npc, playerOffer, merchantOffer, chance): chance?, skillGain?
IER.Barter.registerHaggleOverride(id, handler)
```

The chain is consulted by both the Offer button and `Barter.offerBarter`, **before the acceptance dice are
rolled** — a mod never sees or re-rolls them. `chance` is IER's computed acceptance threshold
(`roll > chance` refuses, `roll` in `[1, 100]`). Handlers run in reverse registration order; each
non-nil return replaces the running value for its own field, so chance modifiers **stack** and the
last registered wins per field (this is replace-per-field on purpose: chance modifiers compose,
unlike eligibility chains such as `registerEquippedOverride` where the first non-nil decides).
The returned chance is clamped to `[0, 100]`: `100` guarantees acceptance, `0` guarantees refusal —
one number covers "raise the chance" tweaks and force-decide. A returned `skillGain` replaces the
price-delta-derived gain when a mod forced acceptance and the derived value would be wrong. The
vanilla early outs (offer already at/below the merchant's, creature merchants) have no computed
chance and bypass the chain.

**Deliberately powerful:** a handler can force-accept any offer. Use it for tweaks, not as a gate
other mods must respect.

## Windows and context

```lua
IER.show(role, arg)                 -- open a role's window (arg = target NPC/container/merchant)
IER.hide(role, arg, force)          -- close it
IER.getWindow(role)                 -- the open window's handler (IER.Inventory), or nil
IER.forEachOpenWindow(apply)        -- apply(handler, wnd) over every open window
IER.update()                        -- refresh every open window now (what sending IER_Update does)
IER.getContext()                    -- the shared mutable context table
IER.getDraggingObject()             -- the object being dragged, or nil
IER.isFavorite(itemOrId)            -- string id or object -> boolean
IER.disableAllWindows(value)        -- temporarily suppress the mod's windows; does NOT restore vanilla windows
IER.allWindowsDisabled              -- live flag; while true, show() and openMode() do nothing
```

`getWindow(role)` looks the window up by its id in the UI library's window manager. Handlers
expose `infoBar` and `table` as public fields for external consumers
(`handler.infoBar:getHeight()`, `handler.table.size`).

### Retarget an open window — `handler:setTarget`

```lua
---@param actor openmw.Object?  nil re-applies the role's default
IER.getWindow(IER.Roles.Inventory):setTarget(actor)
```

`getWindow(role)` returns the open window's handler, so the setter is reached through it. `setTarget`
points the window at another actor: its rows, its info bar (encumbrance, gold, armor rating,
companion profit) and its sorting follow that actor, and its title shows the actor's record name.
With `nil` it re-applies the role's default from the mode's `target` slot — the same rule the window
used when it opened — which for the built-in modes is the player for the Inventory role and the open
argument for any other role.

A non-`nil` actor must be a live object (`isValid()` and `enabled`); otherwise this **throws**. That
is the one exception to the refuse-and-return style of the barter surface: passing a dead or removed
object is a programming error. A mod retargeting to an actor that may go dead mid-trade re-checks
before calling.

It does not refresh: batch the writes, then call `IER.update()` once and only read rows after that.
Rows are rebuilt fresh on every refresh, so one update after a batch is enough, and refreshing per
write would re-price per write. Between a write and that update the tables still show the previous
actor's rows, so `Barter.getSellRow`/`getBuyRow` can name rows the window no longer offers.

### Shared context (`IER.getContext()`)

One mutable table shared with the mod's own code. Read it fresh each frame; do not cache its
fields across frames without invalidation.

| Field | Meaning |
| --- | --- |
| `stolenItems[recordId][victimId or factionId]` | stolen-item counts: badges, confiscation, "that's mine" barter interruption |
| `favoriteItems[item.id]`, `favoriteRevision` | favorites; favorites refuse transfers outside Interface mode |
| `barterState` | `{ selling, buying, currentMerchantOffer, currentBalance, success, partner }`, entries `{ item, stacks, count }` keyed by `item.id`; `partner` is the descriptor set by `Barter.setPartner`, `nil` in vanilla, cleared by the fresh table at a mode change |
| `pickpocket` | the current pickpocket session, or `nil` |
| `companionProfit[actorId]` | profit a companion gained from the player |
| `containerVariables[name]` | vanilla-parity ownership globals |
| `windowArgs[role]` | the `arg` last passed to `show` for that role — **last-known, not current**: `show` with a nil `arg` keeps the previous value and nothing clears it on close, so `windowArgs.Trade` may name a merchant whose window is gone |
| `modes[modeKey]` | custom mode specs registered through `registerMode` |
| `modePatches[modeKey]` | registered patches per mode key |
| `dragAndDrop` | drag state: `draggingObject`, `draggingCount`, `draggingActivationContext` (carries `role` and `modeKey` of the mode that started the drag) |

## Events

Events are named `IER_*`; `MI_*` aliases are still accepted, so mods listening to the old names
keep working.

What external mods typically interact with:

- **`IER_Window_Opened`** — fired on every window open with payload `{ id, role, mode, flags }`
  (`role` is the window role, `mode` the mode key, `flags` the mode's `event.flags`, `nil` for
  built-ins). Prefer `IER.patchMode` over listening to this event: a patch is id-keyed, removable,
  and runs at the right phase.
- **`IER_Update`** — the single refresh trigger for all windows. After changing inventory, send
  `omwself:sendEvent('IER_Update')` so the open tables refresh.

## Constants and helpers

```lua
IER.VERSION       -- API version (currently 4)
IER.Constants     -- shared constants: C.Colors, C.Strings (GMST-backed), C.OPT_KEYS,
                    C.ServiceToType, C.BoundItemIDs
IER.Helpers       -- item inspection helpers: getItem*, isItemEquipped, doesItemFit, isGold,
                    isStealing, ...
IER.Roles         -- built-in window roles: Inventory, Trade, Container, Companion
IER.Modes         -- built-in mode keys: Interface, Container, Pickpocket, Barter, Companion
```

## Notes for mod authors

- **Window ids and storage keys are fixed.** Window ids and `UIToolkit:WindowData` keys are
  spelled `InventoryExtender:<Role>`, and saved window data uses the literal `:Container`/
  `:Barter`/`:Companion` suffixes. These spellings are save identity: they do not follow the mod's
  name, and mods should not rely on renaming them or deriving them from a mode key.
- **Popup quirk:** while a popup is open in interface mode, the UI library's `Popups.show` sets
  the engine UI mode to `'Interface'` (`I.UI.getMode()` returns `'Interface'`, not `nil`). The
  handler's mode snapshot is unaffected — read `handler.mode` rather than re-resolving.
- **`I.UIToolkit`** is a separate installed library mod. `I.UIToolkit` exists in both MENU and
  PLAYER contexts, but `I.UIToolkit.WindowManager` and `I.UIToolkit.Popups` are player-only.
