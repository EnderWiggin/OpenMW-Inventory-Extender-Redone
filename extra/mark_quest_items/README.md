# QuestItemMarker ↔ Inventory Extender Redone bridge

Installs QuestItemMarker's inventory features into **Inventory Extender Redone** without
touching QuestItemMarker. QuestItemMarker only knows the legacy Inventory Extender API
(`I.InventoryExtender`, `registerTooltipModifier`, `registerCellContentModifier`); Redone
renamed its interface with no alias and replaced those hooks, so against Redone QuestItemMarker
currently does nothing in the inventory windows.

## What it adds

| Feature | Redone hook |
| --- | --- |
| Quest icon on item rows, **list and grid views** | `registerRowBadge` |
| `Quest Items` category tab (with the noisy columns hidden), registered or removed as the setting says | `registerCategory` / `unregisterCategory` |
| Quest badge + quest titles in item tooltips | `I.UTKTooltips.addPreCreateTooltipHandler` |
| Search box also matches **quest titles** (IER-only, no IE equivalent) | `registerRowDataModifier` |
| Barter/companion clicks on quest items are refused (IER-only) | `registerRowPickupHandler` |

## Install

Add to your `openmw.cfg` after Inventory Extender Redone and QuestItemMarker:

```text
data=".../InventoryExtenderRedone/extra/qim_ier_bridge"
content=IER_QimBridge.omwscripts
```

Requires both QuestItemMarker and Inventory Extender Redone installed; it stays inert with
either missing, and does nothing when legacy Inventory Extender is the one installed.

## Tuning

Each setting is read once from the one QuestItemMarker section it belongs to, with QuestItemMarker's
own default used when the key was never stored — the same lookup its `config.getCfg` does. The
values are cached for the whole session and refreshed only when a QuestItemMarker section changes,
never re-read per item row:

| Key | Section |
| --- | --- |
| `enabled` | `Settings_QuestItemMarker_Main` |
| `ieRowBadge`, `ieCategory`, `ieTooltip`, `menuShowFaction`, `menuMaxQuests` | `Settings_QuestItemMarker_Menus` |

So QuestItemMarker's settings page drives the three features that mirror its IE integration. The
two extras have no QuestItemMarker key: flip `BLOCK_SELLING`, `BLOCK_COMPANION_TRANSFER` and
`SEARCH_BY_QUEST` at the top of `scripts/ier_qim_bridge/player.lua`.

`BLOCK_SELLING` refuses selling a quest item to a merchant, `BLOCK_COMPANION_TRANSFER` refuses
handing one to a companion. Both work like the favorite transfer block: they key on the window
the item leaves from, so only the player's own window refuses. The other windows still hand the
item over — buying it back from a merchant, taking it back from a companion and looting a
container or an NPC stay allowed, which is also how a quest item gets acquired in the first
place. A refused click stops the action before it can start a drag, so the item never leaves
the pockets by either path.

The `Quest Items` tab follows the setting structurally: with `ieCategory` or the master `enabled`
switch off, the tab is unregistered, not left greyed out — a greyed tab would be one you can
select and that matches nothing. Turning either one back on re-registers it. The bridge subscribes
to all six QuestItemMarker sections — reads are section-specific, but a detection, category or
advanced toggle changes which items count as quest items, so a change anywhere has to refresh the
cached settings and then the windows through Redone's `update()`; flipping a setting on QuestItemMarker's
page takes effect without reopening the window, and the cache, the category list and the table
are refreshed in that order, so the rebuild sees the final settings and category list. If the
removed tab was the selected category, the bar falls back to the default category.

## Caveats

- If QuestItemMarker later grows its own Redone path, this bridge detects it (the badge id
  `questitemmarker` is already registered) and disables itself.
- The tooltip feature needs the `UIToolkit` library mod, which Inventory Extender Redone
  already requires.
- The block message is English-only here; the tab name reuses QuestItemMarker's own
  `Category_QuestItems` key, which ships in six languages.
