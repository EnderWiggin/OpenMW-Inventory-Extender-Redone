---@omw-context player

-- Bridge between QuestItemMarker (QIM) and Inventory Extender Redone.
-- QIM's own integration speaks the legacy Inventory Extender API (I.InventoryExtender,
-- registerTooltipModifier, registerCellContentModifier), none of which exists in Redone:
-- the interface was renamed with no alias, tooltips are UTKTooltips recipes and row badges
-- are a first-class axis. This module re-expresses the same three features on the Redone
-- surface and consumes QIM only through its public interface, so it survives QIM refactors.

local core                     = require 'openmw.core'
local ui                       = require 'openmw.ui'
local storage                  = require 'openmw.storage'
local async                    = require 'openmw.async'
local I                        = require 'openmw.interfaces'

-- QIM ships no LuaLS meta, so the surface this bridge consumes is declared here.
---@class openmw.interfaces.QuestItemMarker
---@field isQuestItem fun(item:openmw.Object):boolean
---@field getQuestDetails fun(itemOrId:string|openmw.Object, maxQuests:number?):{quests:InventoryExtenderRedone.QuestDetail[]}
---@field getFormattedBadgeLines fun(itemOrId:string|openmw.Object, showFaction:boolean, maxQuests:number):string[]
---@field getMenuColor fun(itemOrId:string|openmw.Object|nil):openmw.util.Color

---@class openmw.interfaces.Player
---@field QuestItemMarker openmw.interfaces.QuestItemMarker

---@class InventoryExtenderRedone.QuestDetail
---@field cleanTitle string?
---@field name string?

local BADGE_ID                 = 'QuestItemMarker'
local BADGE_ICON               = 'icons/QuestItemMarker/quest_badge.dds'
local TAB_ICON                 = 'icons/QuestItemMarker/quest_tab.dds'
local QUEST_CATEGORY_KEY       = 'QuestItems'

-- QIM's own storage sections: detection and display toggles live there, and QIM's public
-- interface does not expose the ie* display toggles, so they are read directly. Each key
-- belongs to exactly one section, so reads name that section instead of probing all six.
local qimMain       = storage.playerSection('Settings_QuestItemMarker_Main')
local qimDetection  = storage.playerSection('Settings_QuestItemMarker_Detection')
local qimCategories = storage.playerSection('Settings_QuestItemMarker_Categories')
local qimHud        = storage.playerSection('Settings_QuestItemMarker_HUD')
local qimMenus      = storage.playerSection('Settings_QuestItemMarker_Menus')
local qimAdvanced   = storage.playerSection('Settings_QuestItemMarker_Advanced')

-- IER-only extras: legacy IE has no equivalent, so QIM has no settings keys for them.
-- Selling to a merchant and handing items to a companion are refused for quest items. Like
-- the favorite transfer block, the refusal belongs to the window the item leaves from, so it
-- is the player's own window only: the merchant, companion and container windows still give.
local BLOCK_SELLING            = false
local BLOCK_COMPANION_TRANSFER = false
local SEARCH_BY_QUEST          = true

local l10nQim                  = core.l10n and core.l10n('QuestItemMarker')
local l10n                     = core.l10n('ier_qim_bridge')

local registered               = false
local questTitleCache          = {}

-- all six are subscribed: detection, category and advanced toggles change which items count
-- as quest items, so a change anywhere in QIM's settings can stale the badges and the tab
local qimSections = { qimMain, qimDetection, qimCategories, qimHud, qimMenus, qimAdvanced }

-- reads one key from the section it belongs to, falling back to QuestItemMarker's own
-- default for that key: the same shape its config.getCfg uses
local function qimCfg(section, key, default)
    local value = section:get(key)
    if value == nil then return default end
    return value
end

-- QIM settings are cached, never read per row: the badge provider, the row data modifier and
-- the category filter all run per row per refresh, so storage reads happen only at bridge time
-- and on a settings change. The table is mutated in place, never replaced, so the closures
-- registered at bridge time keep seeing current values. Defaults live in the refresh below,
-- one source, and it runs before any of those closures exists.
local qimSettings = {}

local function refreshQimSettings()
    qimSettings.enabled = qimCfg(qimMain, 'enabled', true)
    qimSettings.ieRowBadge = qimCfg(qimMenus, 'ieRowBadge', true)
    qimSettings.ieCategory = qimCfg(qimMenus, 'ieCategory', true)
    qimSettings.ieTooltip = qimCfg(qimMenus, 'ieTooltip', true)
    qimSettings.menuShowFaction = qimCfg(qimMenus, 'menuShowFaction', false) == true
    qimSettings.menuMaxQuests = tonumber(qimCfg(qimMenus, 'menuMaxQuests', 3)) or 0
end

local function findByName(items, name)
    if not items then return nil, 0 end
    for i = 1, #items do
        if items[i].name == name then return items[i], i end
    end
    return nil, 0
end

-- Quest titles per recordId. QIM drops completed and locked-out quests from the details, so
-- the set is captured at first lookup; stale titles in the search box are harmless, and a
-- finished quest is still a way to find the item that belonged to it.
local function questTitles(QIM, recordId)
    if not recordId then return '' end
    local cached = questTitleCache[recordId]
    if cached then return cached end
    local text = ''
    local details = QIM.getQuestDetails(recordId, 0)
    for _, quest in ipairs(details and details.quests or {}) do
        local title = quest.cleanTitle or quest.name
        if title and title ~= '' then
            text = text ~= '' and (text .. '\n' .. title) or title
        end
    end
    questTitleCache[recordId] = text
    return text
end

local function bridge()
    if registered then return end

    local QIM = I.QuestItemMarker
    local IER = I.InventoryExtenderRedone
    if not QIM or not IER or not IER.registerRowBadge or not IER.registerCategory then return end
    if not IER.unregisterCategory or not IER.getCategories then return end

    local ierCtx = IER.getContext and IER.getContext()
    if not ierCtx then return end

    -- QIM grew its own Redone path: its badge id is already registered, so do not double up.
    for _, badge in ipairs(ierCtx.modifiers.badge) do
        if badge.id == BADGE_ID:lower() then
            registered = true
            return
        end
    end

    -- the cache is filled before any hook closure exists
    refreshQimSettings()

    local function menuColor(item)
        return QIM.getMenuColor(item)
    end

    -- Row badge: Redone owns placement and draws it in the list AND grid views, next to the
    -- favorite/stolen/enchanted badges; the provider only names the icon and its color.
    IER.registerRowBadge(BADGE_ID, function(row, _)
        if not qimSettings.enabled or not qimSettings.ieRowBadge then return end
        local item = row.item
        if not item or not QIM.isQuestItem(item) then return end
        return BADGE_ICON, menuColor(item)
    end)

    -- Quest Items tab. The tab is structural, not a toggle inside the filter: when QIM's
    -- ieCategory or master enabled switch is off, unregisterCategory removes it, so the bar
    -- never shows a greyed-out tab that can never match. registerCategory dedupes by key and
    -- unregisterCategory removes it; while the tab is the selected category, the filter bar
    -- re-resolves through resolveCategoryKey, so removing it mid-session falls back to the
    -- default category instead of leaving a stale selection.
    local questCategory = {
        key = QUEST_CATEGORY_KEY,
        name = l10nQim and l10nQim('Category_QuestItems') or 'Quest Items',
        icon = TAB_ICON,
        hiddenColumns = {
            Class = true,
            AR = true,
            Damage = true,
            Quality = true,
            Condition = true,
        },
        filter = function(item)
            return QIM.isQuestItem(item)
        end,
    }

    local function syncQuestCategory()
        local wanted = qimSettings.enabled and qimSettings.ieCategory
        local present = false
        for _, category in ipairs(IER.getCategories()) do
            if category.key:lower() == QUEST_CATEGORY_KEY:lower() then
                present = true
                break
            end
        end
        if wanted and not present then
            IER.registerCategory(questCategory)
        elseif not wanted and present then
            IER.unregisterCategory(QUEST_CATEGORY_KEY)
        end
    end

    syncQuestCategory()

    -- Tooltip: Redone tooltips are UTKTooltips recipes, not MWUI layouts. Insert the badge
    -- lines before the Footer block, the same spot Redone's own stolen-info section uses.
    local UTK = I.UTKTooltips
    if UTK and UTK.addPreCreateTooltipHandler then
        UTK.addPreCreateTooltipHandler(function(recipe, tooltip)
            if not qimSettings.enabled or not qimSettings.ieTooltip then return end
            local item = tooltip.object
            if not item or not QIM.isQuestItem(item) then return end

            local lines = QIM.getFormattedBadgeLines(item,
                qimSettings.menuShowFaction, qimSettings.menuMaxQuests)
            if not lines or #lines == 0 then return end
            local color = menuColor(item)

            local items = recipe and recipe.items
            if not items then return end
            local found, index = findByName(items, (UTK.CONTENT and UTK.CONTENT.Footer) or 'Footer')
            if not found then
                index = #items + 1
            else
                index = index - 1
            end

            table.insert(items, index, { type = 'gap', size = 4 })
            for i = #lines, 1, -1 do
                table.insert(items, index, {
                    type = 'text',
                    text = lines[i],
                    color = color,
                    name = 'qimQuestLine' .. i,
                })
            end
        end)
    end

    -- IER-only: the search box matches quest titles as well as item names. Redone's search
    -- filter only computes SearchText when nothing has set it, so a modifier owns the field.
    if SEARCH_BY_QUEST and IER.registerRowDataModifier and IER.Helpers then
        IER.registerRowDataModifier(BADGE_ID, function(row, _, _)
            if not qimSettings.enabled then return end
            if not QIM.isQuestItem(row.item) then return end
            local titles = questTitles(QIM, row.item.recordId)
            if titles == '' then return end
            row.SearchText = (IER.Helpers.getItemSearchText(row.item) .. '\n' .. titles):lower()
        end)
    end

    -- IER-only: refuse the click action on quest items where it would move the item away
    -- from the player. Like the favorite transfer block in the handler, the guard is keyed to
    -- the window the item leaves from: only the player's own window (the Inventory role) refuses,
    -- so the target window of the same mode still hands the item over — buying from a merchant,
    -- taking it back from a companion and looting a container stay allowed. Returning false
    -- stops the default activation, which also stops the drag that a plain click would start.
    if BLOCK_SELLING or BLOCK_COMPANION_TRANSFER then
        IER.registerRowPickupHandler(BADGE_ID, function(row, _, role)
            if not qimSettings.enabled then return end
            if not row or not row.item or row.isBartered then return end
            local wnd = IER.getWindow(role)
            if not wnd then return end
            local mode = wnd.mode
            local blocked = role == IER.Roles.Inventory
                and ((BLOCK_SELLING and mode == IER.Modes.Barter)
                    or (BLOCK_COMPANION_TRANSFER and mode == IER.Modes.Companion))
            if not blocked then return end
            if not QIM.isQuestItem(row.item) then return end
            ui.showMessage(string.format(l10n('Msg_QuestItemBlocked'), IER.Helpers.getItemName(row.item)))
            return false
        end)
    end

    -- QIM's settings drive its detection caches and the ieCategory toggle; the cached copy is
    -- refreshed first, then the category is synced, then Redone windows rebuild, so the refresh
    -- sees the final settings and category list. Without this the badges and the tab go stale.
    if IER.update then
        for _, section in ipairs(qimSections) do
            section:subscribe(async:callback(function()
                refreshQimSettings()
                syncQuestCategory()
                IER.update()
            end))
        end
    end

    registered = true
end

return {
    engineHandlers = {
        onInit = bridge,
        onLoad = bridge,
        -- interfaces appear once their scripts load; retry until both sides are present
        onFrame = function()
            if not registered then bridge() end
        end,
    },
}
