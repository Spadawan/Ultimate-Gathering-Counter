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
local SKILLLINE_BY_CATEGORY = {
    herbs   = 182, -- Herbalism
    ore     = 186, -- Mining
    fish    = 356, -- Fishing
    leather = 393, -- Skinning
}

local EXCLUDED_NAME_PATTERNS = {
    -- Pattern/Patron recipe-like reagents in multiple locales.
    "%f[%a]patron%f[%A]",
    "%f[%a]pattern%f[%A]",
    "%f[%a]patr[oó]n%f[%A]",
    "%f[%a]padr[aã]o%f[%A]",  -- PT-BR (Padrão)
    "%f[%a]mod[eè]le%f[%A]",
    "%f[%a]muster%f[%A]",
    "%f[%a]sch[eé]ma%f[%A]",
    "%f[%a]schema%f[%A]",
    -- Schematics (engineering recipes) in multiple locales.
    "%f[%a]schematic%f[%A]",  -- EN
    "%f[%a]esquema%f[%A]",    -- ES
    "%f[%a]bauplan%f[%A]",    -- DE
    -- Prototype items in multiple locales.
    "%f[%a]prototyp[eo]%f[%A]", -- EN/FR (Prototype), DE (Prototyp), ES/IT (Prototipo)
    -- Crest/Ecu-like currencies that should never be tracked.
    "%f[%a]crest%f[%A]",
    "%f[%a][eéÉ]cu%f[%A]",
    "%f[%a]escudo%f[%A]",
}

local function _nameMatchesExcludedPattern(name)
    if type(name) ~= "string" or name == "" then
        return false
    end

    local lowered = string.lower(name)
    for _, pattern in ipairs(EXCLUDED_NAME_PATTERNS) do
        if lowered:find(pattern) then
            return true
        end
    end

    return false
end

local function _extractLootPrefix(fmt)
    if type(fmt) ~= "string" or fmt == "" then
        return nil
    end
    local sPos = fmt:find("%%s", 1, true)
    local dPos = fmt:find("%%d", 1, true)
    local cut = nil
    if sPos and dPos then
        cut = math.min(sPos, dPos)
    else
        cut = sPos or dPos
    end
    if not cut then
        return fmt
    end
    return fmt:sub(1, cut - 1)
end

local NON_GATHER_PREFIXES = {
    _extractLootPrefix(_G.LOOT_ITEM_PUSHED_SELF),
    _extractLootPrefix(_G.LOOT_ITEM_PUSHED_SELF_MULTIPLE),
}

local function _isNonGatherReceiveMessage(msg)
    if type(msg) ~= "string" or #msg == 0 then return false end
    for _, prefix in ipairs(NON_GATHER_PREFIXES) do
        if prefix and #prefix > 0 and string.find(msg, prefix, 1, true) == 1 then
            return true
        end
    end
    return false
end

local function _isNonGatherContextOpen()
    if MailFrame and MailFrame.IsShown and MailFrame:IsShown() then
        return true
    end
    if OpenMailFrame and OpenMailFrame.IsShown and OpenMailFrame:IsShown() then
        return true
    end
    if SendMailFrame and SendMailFrame.IsShown and SendMailFrame:IsShown() then
        return true
    end
    if TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown() then
        return true
    end
    return false
end

local function GetDynamicCategoryFromItemInfo(itemID)
    local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(itemID)

    -- Retail-first strict detection based on profession reagent source.
    if C_TradeSkillUI and C_TradeSkillUI.IsReagentInSkillLine then
        for cat, skillLineID in pairs(SKILLLINE_BY_CATEGORY) do
            local ok, isInSkillLine = pcall(C_TradeSkillUI.IsReagentInSkillLine, itemID, skillLineID)
            if ok and isInSkillLine then
                return cat
            end
        end
    end

    -- Fallback classifier (localized type/subtype + class/subclass mapping).
    if UGC.Compat and UGC.Compat.GetItemCategoryFromInfo then
        local cat = UGC.Compat:GetItemCategoryFromInfo(itemID)
        if cat then
            return cat
        end
    end

    if classID and subClassID then
        local classMap = UGC.SUBCLASS_MAP[classID]
        if classMap and classMap[subClassID] then
            return classMap[subClassID]
        end
    end

    return nil
end

local function GetItemClassInfo(itemID)
    local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(itemID)
    if classID and subClassID then
        return classID, subClassID
    end

    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, _, _, _, _, _, _, cID, scID = C_Item.GetItemInfoInstant(itemID)
        if cID or scID then
            return cID, scID
        end
        local _, _, _, _, _, legacyCID, legacySCID = C_Item.GetItemInfoInstant(itemID)
        return legacyCID, legacySCID
    end

    if GetItemInfoInstant then
        local _, _, _, _, _, _, _, _, _, _, _, cID, scID = GetItemInfoInstant(itemID)
        if cID or scID then
            return cID, scID
        end
        local _, _, _, _, _, legacyCID, legacySCID = GetItemInfoInstant(itemID)
        return legacyCID, legacySCID
    end

    return nil, nil
end

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

    if UGC.EXCLUDED_ITEM_IDS then
        for itemID in pairs(UGC.EXCLUDED_ITEM_IDS) do
            UGC.ITEM_DB[itemID] = nil
        end
    end

    UGC.Session.startTime = GetTime()
    wipe(UGC.Session.items)
    wipe(UGC.Session.bagSnapshot)
    wipe(UGC.Session.pendingLoot)
    if UGC.Progression and UGC.Progression.ResetChainState then
        UGC.Progression:ResetChainState()
    end
    -- Build initial snapshot without recording gains
    self:_buildSnapshot()
    _initialized = true  -- safe to process bag events from now on
end

function Tracker:_isExcludedLeatherEquipment(itemID, category)
    if category ~= "leather" then
        return false
    end

    local classID = GetItemClassInfo(itemID)
    if classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR then
        return true
    end

    -- Fallback when class info is unavailable/incomplete on some clients.
    local _, _, _, _, _, itemType = GetItemInfo(itemID)

    if type(itemType) == "string" then
        local t = string.lower(itemType)
        if t == "weapon" or t == "arme" or t == "waffe"
            or t == "armor" or t == "armure" or t == "rüstung" then
            return true
        end
    end

    return false
end

local EXCLUDED_ICON_PATTERNS = { "gizmo", "engineering" }

local function _iconMatchesExcludedPattern(icon)
    if type(icon) ~= "string" or icon == "" then
        return false
    end
    local lower = string.lower(icon)
    for _, pat in ipairs(EXCLUDED_ICON_PATTERNS) do
        if lower:find(pat, 1, true) then
            return true
        end
    end
    return false
end

function Tracker:_isExcludedItem(itemID, itemName)
    if UGC.EXCLUDED_ITEM_IDS and UGC.EXCLUDED_ITEM_IDS[itemID] then
        return true
    end

    local name = itemName
    local cached = UGC.DB and UGC.DB.GetCachedItem and UGC.DB:GetCachedItem(itemID)
    if not name and cached then
        name = cached.name
    end

    if cached and _iconMatchesExcludedPattern(cached.icon) then
        return true
    end

    return _nameMatchesExcludedPattern(name)
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
                    if self:_isExcludedItem(itemID) then
                        UGC.ITEM_DB[itemID] = nil
                    elseif UGC.ITEM_DB[itemID] then
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
    local gainedCats  = {}  -- [cat] = { itemID = bestItemID, xpGain = N }
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
                    local xpGain = 10
                    if UGC.Progression and UGC.Progression.GetGatherXPGain then
                        xpGain = UGC.Progression:GetGatherXPGain(itemID)
                    end

                    local existing = gainedCats[cat]
                    if not existing or xpGain > (existing.xpGain or 0) then
                        gainedCats[cat] = { itemID = itemID, xpGain = xpGain }
                    end
                end
            end
        end
    end
    -- One gathering action per category with gains in this scan
    local hadGatherUpdate = false
    for cat, gainInfo in pairs(gainedCats) do
        UGC.DB:RecordGatherAction(cat)
        UGC.Session.gatherCount[cat] = (UGC.Session.gatherCount[cat] or 0) + 1
        hadGatherUpdate = true
        if UGC.Progression then
            UGC.Progression:AddGatherAction(cat, gainInfo and gainInfo.itemID)
        end
    end
    if hadGatherUpdate and UGC.Community then
        UGC.Community:BroadcastSnapshot(false)
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
    if self:_isExcludedItem(itemID, name) then
        UGC.ITEM_DB[itemID] = nil
        return nil
    end

    local cat = GetDynamicCategoryFromItemInfo(itemID)

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
    if self:_isExcludedItem(itemID, name) then
        UGC.ITEM_DB[itemID] = nil
        return
    end

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
        if self:_isExcludedItem(itemID, n) then
            UGC.ITEM_DB[itemID] = nil
            return
        end

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
        if self:_isExcludedItem(itemID, data.hint) then
            UGC.ITEM_DB[itemID] = nil
        else
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
    if _isNonGatherReceiveMessage(msg) then
        return
    end
    if _isNonGatherContextOpen() then
        return
    end

    local itemLink = msg:match("|H(item:[^|]+)|h")
    if not itemLink then return end

    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return end
    local itemName = msg:match("|h%[([^%]]+)%]|h")
    if self:_isExcludedItem(itemID, itemName) then
        return
    end

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
    if UGC.Progression and UGC.Progression.ResetChainState then
        UGC.Progression:ResetChainState()
    end
    self:_buildSnapshot()
    if UGC.Community then
        UGC.Community:BroadcastSnapshot(true)
    end
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
