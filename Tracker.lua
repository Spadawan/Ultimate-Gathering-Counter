-------------------------------------------------------------------------------
-- Tracker.lua
-- Handles bag scanning, gathering gain detection, session counters, and
-- per-hour rate calculations. Must load third (after Database.lua).
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Tracker = {}
local Tracker = UGC.Tracker

-- In-memory session data — never persisted to SavedVariables
UGC.Session = {
    startTime   = 0,
    items       = {},        -- [itemID] = { gained = N, bagCount = N }
    bagSnapshot = {},        -- [itemID] = count (result of last bag scan)
}

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
function Tracker:Init()
    UGC.Session.startTime = GetTime()
    wipe(UGC.Session.items)
    wipe(UGC.Session.bagSnapshot)
    -- Build initial snapshot without recording gains
    self:_buildSnapshot()
end

-- Build bag snapshot without delta processing (used on first load)
function Tracker:_buildSnapshot()
    local snapshot = {}
    for bag = 0, 5 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots(bag)
                         or GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemID, stackCount = self:_getSlotInfo(bag, slot)
                if itemID then
                    if UGC.ITEM_DB[itemID] then
                        snapshot[itemID] = (snapshot[itemID] or 0) + stackCount
                    else
                        -- Attempt dynamic detection without recording
                        local cat = self:DetectItemCategory(itemID)
                        if cat then
                            local settings = UGC.DB:GetSettings()
                            if settings.showCategories[cat] then
                                local cached = UGC.DB:GetCachedItem(itemID)
                                UGC.ITEM_DB[itemID] = {
                                    category = cat,
                                    hint     = cached and cached.name or ("Item "..itemID),
                                }
                                snapshot[itemID] = (snapshot[itemID] or 0) + stackCount
                            end
                        end
                    end
                    -- Pre-cache metadata
                    if UGC.ITEM_DB[itemID] and not UGC.DB:GetCachedItem(itemID) then
                        self:RequestItemCache(itemID)
                    end
                end
            end
        end
    end
    -- Seed session bag counts
    for itemID, count in pairs(snapshot) do
        UGC.Session.items[itemID] = { gained = 0, bagCount = count }
    end
    UGC.Session.bagSnapshot = snapshot
end

-------------------------------------------------------------------------------
-- Bag slot helper (abstracts old/new Container API)
-------------------------------------------------------------------------------
function Tracker:_getSlotInfo(bag, slot)
    if C_Container then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then
            return info.itemID, info.stackCount or 1
        end
    else
        local _, stackCount, _, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
        if itemLink then
            local itemID = tonumber(itemLink:match("|Hitem:(%d+)"))
            if itemID then
                return itemID, stackCount or 1
            end
        end
    end
    return nil, 0
end

-------------------------------------------------------------------------------
-- ScanBags — called on BAG_UPDATE_DELAYED
-------------------------------------------------------------------------------
function Tracker:ScanBags()
    local settings    = UGC.DB:GetSettings()
    local newSnapshot = {}

    for bag = 0, 5 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots(bag)
                         or GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemID, stackCount = self:_getSlotInfo(bag, slot)
                if itemID then
                    if UGC.ITEM_DB[itemID] then
                        newSnapshot[itemID] = (newSnapshot[itemID] or 0) + stackCount
                        if not UGC.DB:GetCachedItem(itemID) then
                            self:RequestItemCache(itemID)
                        end
                    else
                        -- Dynamic detection for unknown items
                        local cat = self:DetectItemCategory(itemID)
                        if cat and settings.showCategories[cat] then
                            local cached = UGC.DB:GetCachedItem(itemID)
                            UGC.ITEM_DB[itemID] = {
                                category = cat,
                                hint     = cached and cached.name or ("Item "..itemID),
                            }
                            newSnapshot[itemID] = (newSnapshot[itemID] or 0) + stackCount
                            self:RequestItemCache(itemID)
                        end
                    end
                end
            end
        end
    end

    -- Compute deltas against previous snapshot
    local oldSnapshot = UGC.Session.bagSnapshot
    for itemID, newCount in pairs(newSnapshot) do
        local oldCount = oldSnapshot[itemID] or 0
        local delta    = newCount - oldCount
        if delta > 0 then
            -- New items gained
            if not UGC.Session.items[itemID] then
                UGC.Session.items[itemID] = { gained = 0, bagCount = 0 }
            end
            UGC.Session.items[itemID].gained = UGC.Session.items[itemID].gained + delta
            UGC.DB:RecordGain(itemID, delta)
        end
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
-- Dynamic category detection via GetItemInfo class/subclass
-------------------------------------------------------------------------------
function Tracker:DetectItemCategory(itemID)
    local name, _, quality, _, _, _, _, _, _, texture, _, classID, subclassID =
        GetItemInfo(itemID)
    if not classID then return nil end

    local classMap = UGC.SUBCLASS_MAP[classID]
    if not classMap then return nil end

    local cat = classMap[subclassID]
    if cat and name and texture then
        UGC.DB:CacheItem(itemID, name, texture, quality)
    end
    return cat
end

-------------------------------------------------------------------------------
-- Async metadata caching (GetItemInfo may return nil on first call)
-------------------------------------------------------------------------------
function Tracker:RequestItemCache(itemID)
    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    if name and texture then
        UGC.DB:CacheItem(itemID, name, texture, quality or 1)
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
            UGC.DB:CacheItem(itemID, n, t, q or 1)
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

            -- Show item if it has been seen this session OR has enough in bag
            if gained > 0 or bagCount >= minQty then
                local cached = UGC.DB:GetCachedItem(itemID)
                local name   = (cached and cached.name) or data.hint or ("Item " .. itemID)
                local icon   = cached and cached.icon

                table.insert(result, {
                    itemID       = itemID,
                    name         = name,
                    icon         = icon,
                    category     = cat,
                    bagCount     = bagCount,
                    sessionGained = gained,
                    hourlyRate   = self:GetHourlyRate(itemID),
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
    if not UGC.DB:GetSettings().chatLootDetect then return end

    local itemLink = msg:match("|H(item:[^|]+)|h")
    if not itemLink then return end

    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return end

    -- If already tracked, nothing to do
    if UGC.ITEM_DB[itemID] then return end

    -- Try to detect and register for future bag scans
    local cat = self:DetectItemCategory(itemID)
    if cat then
        local settings = UGC.DB:GetSettings()
        if settings.showCategories[cat] then
            local cached = UGC.DB:GetCachedItem(itemID)
            UGC.ITEM_DB[itemID] = {
                category = cat,
                hint     = cached and cached.name or ("Item " .. itemID),
            }
        end
    end
end

-------------------------------------------------------------------------------
-- Reset session
-------------------------------------------------------------------------------
function Tracker:ResetSession()
    UGC.DB:ResetSession()
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
