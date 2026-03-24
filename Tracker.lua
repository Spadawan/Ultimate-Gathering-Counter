-------------------------------------------------------------------------------
-- Tracker.lua
-- Handles bag scanning, gathering gain detection, session counters, and
-- per-hour rate calculations. Must load third (after Database.lua).
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Tracker = {}
local Tracker = UGC.Tracker

-- Guard: prevents ScanBags from running before Init() completes
local _initialized = false
-- Suppresses gain recording on the very first scan after login.
-- On first BAG_UPDATE_DELAYED, GetItemInfo() may not have returned data for
-- all bag items during _buildSnapshot(), so the first scan re-seeds the
-- snapshot without counting anything as gained (avoids "+500 Hochenblume" on login).
local _firstScanDone = false
local LOOT_CONFIRM_WINDOW = 15
local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR = 4

-- In-memory session data — never persisted to SavedVariables
UGC.Session = {
    startTime    = 0,
    items        = {},        -- [itemID] = { gained = N, bagCount = N }
    bagSnapshot  = {},        -- [itemID] = count (result of last bag scan)
    pendingLoot  = {},        -- [itemID] = { count = N, category = "herbs", timestamp = T }
    gatherCount  = { herbs = 0, ore = 0, fish = 0, leather = 0 }, -- gathering actions this session
}

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
function Tracker:Init()
    _initialized  = false  -- block ScanBags during snapshot
    _firstScanDone = false -- next ScanBags call will re-seed, not record gains
    UGC.Session.startTime = GetTime()
    wipe(UGC.Session.items)
    wipe(UGC.Session.bagSnapshot)
    wipe(UGC.Session.pendingLoot)
    -- Build initial snapshot without recording gains
    self:_buildSnapshot()
    _initialized = true  -- safe to process bag events from now on
end

function Tracker:_isExcludedLeatherEquipment(itemID, category)
    if category ~= "leather" then
        return false
    end

    local _, _, _, _, classID = UGC.Compat:GetItemInfoInstant(itemID)
    return classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR
end

function Tracker:_captureSnapshot()
    local settings = UGC.DB:GetSettings()
    local snapshot = {}

    for bag = 0, 5 do
        local numSlots = UGC.Compat:GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemID, stackCount = self:_getSlotInfo(bag, slot)
                if itemID then
                    if UGC.ITEM_DB[itemID] then
                        local knownCategory = UGC.ITEM_DB[itemID].category
                        if not self:_isExcludedLeatherEquipment(itemID, knownCategory) then
                            snapshot[itemID] = (snapshot[itemID] or 0) + stackCount
                            if not UGC.DB:GetCachedItem(itemID) then
                                self:RequestItemCache(itemID)
                            end
                        else
                            UGC.ITEM_DB[itemID] = nil
                        end
                    else
                        -- Attempt dynamic detection without recording
                        local cat = self:DetectItemCategory(itemID)
                        if cat and settings.showCategories[cat] then
                            local cached = UGC.DB:GetCachedItem(itemID)
                            UGC.ITEM_DB[itemID] = {
                                category = cat,
                                hint     = cached and cached.name or ("Item " .. itemID),
                            }
                            snapshot[itemID] = (snapshot[itemID] or 0) + stackCount
                            self:RequestItemCache(itemID)
                        end
                    end
                end
            end
        end
    end

    return snapshot
end

-- Build bag snapshot without delta processing (used on first load)
function Tracker:_buildSnapshot()
    local snapshot = self:_captureSnapshot()

    -- Seed session bag counts
    for itemID, count in pairs(snapshot) do
        UGC.Session.items[itemID] = { gained = 0, bagCount = count }
    end
    UGC.Session.bagSnapshot = snapshot
end

function Tracker:RebaselineBags(keepFirstScanState)
    local snapshot = self:_captureSnapshot()
    wipe(UGC.Session.pendingLoot)

    for itemID, count in pairs(snapshot) do
        if not UGC.Session.items[itemID] then
            UGC.Session.items[itemID] = { gained = 0, bagCount = 0 }
        end
        UGC.Session.items[itemID].bagCount = count
    end

    for itemID, data in pairs(UGC.Session.items) do
        if data then
            data.bagCount = snapshot[itemID] or 0
        end
    end

    UGC.Session.bagSnapshot = snapshot
    -- During initial login / UI reload, item data can still be streaming in.
    -- Allow one more BAG_UPDATE_DELAYED pass to re-seed the snapshot without
    -- recording gains so existing bag contents are never added to session/all-time.
    _firstScanDone = keepFirstScanState and true or false
end

-------------------------------------------------------------------------------
-- Bag slot helper (abstracts old/new Container API)
-------------------------------------------------------------------------------
function Tracker:_getSlotInfo(bag, slot)
    return UGC.Compat:GetContainerItemInfo(bag, slot)
end

function Tracker:_clearExpiredPendingLoot(now)
    now = now or GetTime()
    for itemID, pending in pairs(UGC.Session.pendingLoot) do
        if not pending or (now - (pending.timestamp or 0)) > LOOT_CONFIRM_WINDOW then
            UGC.Session.pendingLoot[itemID] = nil
        end
    end
end

function Tracker:_consumePendingLoot(itemID, delta, now)
    self:_clearExpiredPendingLoot(now)

    local pending = UGC.Session.pendingLoot[itemID]
    if not pending or not pending.count or pending.count <= 0 then
        return 0, nil
    end

    local confirmed = math.min(delta, pending.count)
    pending.count = pending.count - confirmed
    local category = pending.category

    if pending.count <= 0 then
        UGC.Session.pendingLoot[itemID] = nil
    end

    return confirmed, category
end

function Tracker:_extractLootQuantity(msg, itemLink)
    if not msg or not itemLink then return 1 end

    local quotedLink = itemLink:gsub("([%%%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local qty = msg:match(quotedLink .. "%s*[xX×](%d+)")
            or msg:match("[xX×](%d+)%s*%p?$")
            or msg:match("(%d+)%s*[xX×]%s*" .. quotedLink)

    qty = tonumber(qty)
    if qty and qty > 0 then
        return qty
    end

    return 1
end

function Tracker:_queuePendingLoot(itemID, quantity, category)
    if not itemID or not category or quantity <= 0 then return end

    local pending = UGC.Session.pendingLoot[itemID]
    if pending and pending.category == category then
        pending.count = pending.count + quantity
        pending.timestamp = GetTime()
        return
    end

    UGC.Session.pendingLoot[itemID] = {
        count = quantity,
        category = category,
        timestamp = GetTime(),
    }
end

-------------------------------------------------------------------------------
-- ScanBags — called on BAG_UPDATE_DELAYED
-------------------------------------------------------------------------------
function Tracker:ScanBags()
    if not _initialized then return end  -- ignore pre-login BAG_UPDATE_DELAYED events
    local now = GetTime()
    local newSnapshot = self:_captureSnapshot()

    -- First scan after login: re-seed snapshot without recording gains.
    -- _buildSnapshot() may have missed items whose GetItemInfo() wasn't ready yet;
    -- this second pass catches them before any delta logic runs.
    if not _firstScanDone then
        _firstScanDone = true
        for itemID in pairs(UGC.ITEM_DB) do
            if not UGC.Session.items[itemID] then
                UGC.Session.items[itemID] = { gained = 0, bagCount = 0 }
            end
            UGC.Session.items[itemID].bagCount = newSnapshot[itemID] or 0
        end
        UGC.Session.bagSnapshot = newSnapshot
        return
    end

    -- Compute deltas against previous snapshot
    local oldSnapshot = UGC.Session.bagSnapshot
    local gainedCats  = {}  -- categories with positive delta this scan
    for itemID, newCount in pairs(newSnapshot) do
        local oldCount = oldSnapshot[itemID] or 0
        local delta    = newCount - oldCount
        if delta > 0 then
            local confirmedDelta, cat = self:_consumePendingLoot(itemID, delta, now)
            if confirmedDelta > 0 then
                if not UGC.Session.items[itemID] then
                    UGC.Session.items[itemID] = { gained = 0, bagCount = 0 }
                end
                UGC.Session.items[itemID].gained = UGC.Session.items[itemID].gained + confirmedDelta
                UGC.DB:RecordGain(itemID, confirmedDelta)
                if cat then
                    gainedCats[cat] = true
                end
            end
        end
    end
    -- One gathering action per category with gains in this scan
    for cat in pairs(gainedCats) do
        UGC.DB:RecordGatherAction(cat)
        UGC.Session.gatherCount[cat] = (UGC.Session.gatherCount[cat] or 0) + 1
    end

    -- Update all tracked items' bag counts
    for itemID in pairs(UGC.ITEM_DB) do
        if not UGC.Session.items[itemID] then
            UGC.Session.items[itemID] = { gained = 0, bagCount = 0 }
        end
        UGC.Session.items[itemID].bagCount = newSnapshot[itemID] or 0
    end

    UGC.Session.bagSnapshot = newSnapshot
end

-------------------------------------------------------------------------------
-- Item display quality
-- Prefer profession reagent quality when the client exposes it, because item
-- rarity is not the same thing as reagent quality tiers on modern expansions.
-------------------------------------------------------------------------------
local function GetDisplayQuality(itemID, itemQuality)
    local reagentQuality = UGC.Compat:GetReagentQuality(itemID)
    if type(reagentQuality) == "number" and reagentQuality > 0 then
        return reagentQuality
    end

    if type(itemQuality) == "number" and itemQuality >= 1 and itemQuality <= 3 then
        return itemQuality
    end

    return nil
end

-------------------------------------------------------------------------------
-- Dynamic category detection via GetItemInfo class/subclass
-------------------------------------------------------------------------------
function Tracker:DetectItemCategory(itemID)
    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    local cat = UGC.Compat:GetItemCategoryFromInfo(itemID)

    if self:_isExcludedLeatherEquipment(itemID, cat) then
        return nil
    end

    if cat and name and texture then
        UGC.DB:CacheItem(itemID, name, texture, GetDisplayQuality(itemID, quality))
    end
    return cat
end

-------------------------------------------------------------------------------
-- Async metadata caching (GetItemInfo may return nil on first call)
-------------------------------------------------------------------------------
function Tracker:RequestItemCache(itemID)
    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    if name and texture then
        UGC.DB:CacheItem(itemID, name, texture, GetDisplayQuality(itemID, quality))
        -- Update hint in ITEM_DB
        if UGC.ITEM_DB[itemID] then
            UGC.ITEM_DB[itemID].hint = name
        end
        return
    end
    -- Item data not loaded yet — retry after client cache populates
    C_Timer.After(2.0, function()
        local n, _, q, _, _, _, _, _, _, t = GetItemInfo(itemID)
        if n and t then
            UGC.DB:CacheItem(itemID, n, t, GetDisplayQuality(itemID, q))
            if UGC.ITEM_DB[itemID] then
                UGC.ITEM_DB[itemID].hint = n
            end
            if UGC.Overlay and UGC.Overlay.frame and UGC.Overlay.frame:IsShown() then
                UGC.Overlay:Refresh()
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- Per-hour rate for a given item this session
-------------------------------------------------------------------------------
function Tracker:GetHourlyRate(itemID)
    local elapsed = (GetTime() - UGC.Session.startTime) / 3600
    if elapsed < (1 / 60) then return 0 end  -- less than 1 minute
    local gained = UGC.Session.items[itemID] and UGC.Session.items[itemID].gained or 0
    return gained / elapsed
end

-------------------------------------------------------------------------------
-- GetTrackedItems — returns sorted list for display
-- categoryFilter: optional string to restrict to one category
-- sortBy: "session" (default), "bags", "rate", "name"
-------------------------------------------------------------------------------
function Tracker:GetTrackedItems(categoryFilter, sortBy)
    local settings  = UGC.DB:GetSettings()
    local minQty    = settings.minimumQty or 0
    local result    = {}

    for itemID, data in pairs(UGC.ITEM_DB) do
        local cat = data.category
        if (not categoryFilter or categoryFilter == cat)
           and settings.showCategories[cat] then

            local sess      = UGC.Session.items[itemID] or { gained = 0, bagCount = 0 }
            local bagCount  = sess.bagCount
            local gained    = sess.gained

            -- Only show items currently in the bag; must also meet quantity threshold
            if bagCount > 0 and (gained > 0 or bagCount >= minQty) then
                local cached  = UGC.DB:GetCachedItem(itemID)
                local name    = (cached and cached.name) or data.hint or ("Item " .. itemID)
                local icon    = cached and cached.icon
                local quality = cached and cached.quality  -- nil = unknown, no gem shown

                table.insert(result, {
                    itemID        = itemID,
                    name          = name,
                    icon          = icon,
                    quality       = quality,
                    category      = cat,
                    bagCount      = bagCount,
                    sessionGained = gained,
                    hourlyRate    = self:GetHourlyRate(itemID),
                })
            end
        end
    end

    -- Sort: primary by category order, secondary by sessionGained desc, tertiary bagCount
    local catOrder = {}
    for i, c in ipairs(UGC.CATEGORY_ORDER) do catOrder[c] = i end

    local sortFn
    if sortBy == "name" then
        sortFn = function(a, b)
            local ca, cb = catOrder[a.category] or 99, catOrder[b.category] or 99
            if ca ~= cb then return ca < cb end
            return a.name < b.name
        end
    elseif sortBy == "bags" then
        sortFn = function(a, b)
            local ca, cb = catOrder[a.category] or 99, catOrder[b.category] or 99
            if ca ~= cb then return ca < cb end
            return a.bagCount > b.bagCount
        end
    else
        -- Default: session gained desc
        sortFn = function(a, b)
            local ca, cb = catOrder[a.category] or 99, catOrder[b.category] or 99
            if ca ~= cb then return ca < cb end
            if a.sessionGained ~= b.sessionGained then
                return a.sessionGained > b.sessionGained
            end
            return a.bagCount > b.bagCount
        end
    end

    table.sort(result, sortFn)
    return result
end

-------------------------------------------------------------------------------
-- Secondary loot detection via CHAT_MSG_LOOT
-- Used only for item discovery (adds to ITEM_DB), not for counting.
-- All counting is done by bag diff to avoid double-counting.
-------------------------------------------------------------------------------
function Tracker:ParseLootMessage(msg)
    if not msg then return end

    local itemLink = msg:match("|H(item:[^|]+)|h")
    if not itemLink then return end

    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return end

    local settings = UGC.DB:GetSettings()
    local cat
    if UGC.ITEM_DB[itemID] then
        cat = UGC.ITEM_DB[itemID].category
        if self:_isExcludedLeatherEquipment(itemID, cat) then
            UGC.ITEM_DB[itemID] = nil
            cat = nil
        end
    elseif settings.chatLootDetect then
        -- Try to detect and register for future bag scans
        cat = self:DetectItemCategory(itemID)
        if cat then
            if settings.showCategories[cat] then
                local cached = UGC.DB:GetCachedItem(itemID)
                UGC.ITEM_DB[itemID] = {
                    category = cat,
                    hint     = cached and cached.name or ("Item " .. itemID),
                }
            end
        end
    end

    if cat then
        self:_queuePendingLoot(itemID, self:_extractLootQuantity(msg, itemLink), cat)
    end
end

-------------------------------------------------------------------------------
-- Reset session
-------------------------------------------------------------------------------
function Tracker:ResetSession()
    UGC.DB:ResetSession()
    wipe(UGC.Session.gatherCount)
    wipe(UGC.Session.pendingLoot)
    self:_buildSnapshot()
end

-------------------------------------------------------------------------------
-- Session duration helpers
-------------------------------------------------------------------------------
function Tracker:GetSessionDuration()
    return GetTime() - UGC.Session.startTime
end

function Tracker:FormatDuration(seconds)
    seconds = math.floor(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh %02dm", math.floor(seconds / 3600),
               math.floor((seconds % 3600) / 60))
    end
end
