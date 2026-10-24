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

`enabled`, `ieRowBadge`, `ieCategory`, `ieTooltip`, `menuShowFaction` and `menuMaxQuests` are
read from QuestItemMarker's own storage sections, so QuestItemMarker's settings page drives the
three features that mirror its IE integration. The two extras have no QuestItemMarker key: flip
`BLOCK_SELLING`, `BLOCK_COMPANION_TRANSFER` and `SEARCH_BY_QUEST` at the top of
`scripts/ier_qim_bridge/player.lua`.

`BLOCK_SELLING` refuses the click action on the player's side of a barter (selling), `BLOCK_COMPANION_TRANSFER`
refuses handing items to a companion. Container and pickpocket clicks stay allowed: looting is
how a quest item gets acquired in the first place.

The `Quest Items` tab follows the setting structurally: with `ieCategory` or the master `enabled`
switch off, the tab is unregistered, not left greyed out — a greyed tab would be one you can
select and that matches nothing. Turning either one back on re-registers it. The bridge subscribes
to QuestItemMarker's storage sections and refreshes the windows through Redone's `update()`, so
flipping a setting on QuestItemMarker's page takes effect without reopening the window; if the
removed tab was the selected category, the bar falls back to the default category.

## Caveats

- If QuestItemMarker later grows its own Redone path, this bridge detects it (the badge id
  `questitemmarker` is already registered) and disables itself.
- The tooltip feature needs the `UIToolkit` library mod, which Inventory Extender Redone
  already requires.
- The block message is English-only here; the tab name reuses QuestItemMarker's own
  `Category_QuestItems` key, which ships in six languages.
