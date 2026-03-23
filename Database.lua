-------------------------------------------------------------------------------
-- Database.lua
-- Owns all UGC_DB reads/writes. No other module touches UGC_DB directly.
-- Must load second (after Data.lua).
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.DB = {}
local DB = UGC.DB

local SCHEMA_VERSION = 2

local DEFAULTS = {
    version  = SCHEMA_VERSION,
    settings = {
        overlayVisible   = true,
        overlayLocked    = false,
        overlayScale     = 1.0,
        overlayPoint     = { point = "CENTER", x = 0, y = 100 },
        showCategories   = { herbs = true, ore = true, fish = true, leather = true },
        showPerHourRates = true,
        showValues       = true,
        minimumQty          = 0,
        chatLootDetect      = true,
        collapsedCategories = {},   -- [catKey] = true when collapsed
        fadeWhenUnfocused   = true, -- fade overlay to 50% when mouse is not over it
        overlayAlpha        = 1.0,  -- base opacity (0.1–1.0)
    },
    allTime        = {},
    weekly         = { weekStart = 0 },
    daily          = { dayStart  = 0 },
    hourlyBuckets  = {},
    itemCache      = {},
}

-- Recursively fills in missing keys from defaults without overwriting existing data
local function deepMerge(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            deepMerge(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
function DB:Init()
    if type(UGC_DB) ~= "table" then
        UGC_DB = {}
    end

    deepMerge(UGC_DB, DEFAULTS)

    -- Schema migration from v1
    if (UGC_DB.version or 1) < SCHEMA_VERSION then
        -- v1 → v2: hourlyBuckets and itemCache are new
        if not UGC_DB.hourlyBuckets then UGC_DB.hourlyBuckets = {} end
        if not UGC_DB.itemCache      then UGC_DB.itemCache      = {} end
        UGC_DB.version = SCHEMA_VERSION
    end

    -- Reset stale daily/weekly data based on server time
    local now      = GetServerTime()
    local dayStart = now - (now % 86400)
    local wday     = tonumber(date("%w", now)) -- 0 = Sunday, 1 = Monday …
    local daysSinceMon = (wday == 0) and 6 or (wday - 1)
    local weekStart = dayStart - (daysSinceMon * 86400)

    if UGC_DB.daily.dayStart ~= dayStart then
        local ds = dayStart
        wipe(UGC_DB.daily)
        UGC_DB.daily.dayStart = ds
    end

    if UGC_DB.weekly.weekStart ~= weekStart then
        local ws = weekStart
        wipe(UGC_DB.weekly)
        UGC_DB.weekly.weekStart = ws
    end

    self:_ensureHourlyBucket(now)
end

-------------------------------------------------------------------------------
-- Hourly bucket helpers
-------------------------------------------------------------------------------
function DB:_ensureHourlyBucket(now)
    local hourEpoch = now - (now % 3600)
    for _, bucket in ipairs(UGC_DB.hourlyBuckets) do
        if bucket.hourEpoch == hourEpoch then
            return bucket
        end
    end
    local bucket = { hourEpoch = hourEpoch, items = {} }
    table.insert(UGC_DB.hourlyBuckets, bucket)
    -- Keep only the last 24 hourly buckets
    while #UGC_DB.hourlyBuckets > 24 do
        table.remove(UGC_DB.hourlyBuckets, 1)
    end
    return bucket
end

function DB:TickHourlyBucket(itemID, delta)
    local bucket = self:_ensureHourlyBucket(GetServerTime())
    local id = tostring(itemID)
    bucket.items[id] = (bucket.items[id] or 0) + delta
end

-------------------------------------------------------------------------------
-- Record gain (call this whenever a gathering item is acquired)
-------------------------------------------------------------------------------
function DB:RecordGain(itemID, delta)
    if not delta or delta <= 0 then return end
    local id  = tostring(itemID)
    local now = GetServerTime()

    -- All-time
    if not UGC_DB.allTime[id] then
        UGC_DB.allTime[id] = { count = 0, firstSeen = now, lastSeen = 0 }
    end
    UGC_DB.allTime[id].count   = UGC_DB.allTime[id].count + delta
    UGC_DB.allTime[id].lastSeen = now

    -- Weekly
    if not UGC_DB.weekly[id] then
        UGC_DB.weekly[id] = { count = 0 }
    end
    UGC_DB.weekly[id].count = UGC_DB.weekly[id].count + delta

    -- Daily
    if not UGC_DB.daily[id] then
        UGC_DB.daily[id] = { count = 0 }
    end
    UGC_DB.daily[id].count = UGC_DB.daily[id].count + delta

    -- Hourly bucket
    self:TickHourlyBucket(itemID, delta)
end

-------------------------------------------------------------------------------
-- Getters
-------------------------------------------------------------------------------
function DB:GetAllTime(itemID)
    local d = UGC_DB.allTime[tostring(itemID)]
    return d and d.count or 0
end

function DB:GetWeekly(itemID)
    local d = UGC_DB.weekly[tostring(itemID)]
    return d and d.count or 0
end

function DB:GetDaily(itemID)
    local d = UGC_DB.daily[tostring(itemID)]
    return d and d.count or 0
end

function DB:GetLastHour(itemID)
    local now    = GetServerTime()
    local cutoff = now - 3600
    local id     = tostring(itemID)
    local total  = 0
    for _, bucket in ipairs(UGC_DB.hourlyBuckets) do
        if bucket.hourEpoch >= cutoff then
            total = total + (bucket.items[id] or 0)
        end
    end
    return total
end

function DB:GetAllTimeFirstSeen(itemID)
    local d = UGC_DB.allTime[tostring(itemID)]
    return d and d.firstSeen or 0
end

-------------------------------------------------------------------------------
-- Reset
-------------------------------------------------------------------------------
function DB:ResetSession()
    if UGC.Session then
        UGC.Session.startTime = GetTime()
        wipe(UGC.Session.items)
        UGC.Session.bagSnapshot = {}
    end
end

function DB:ResetAllTime()
    wipe(UGC_DB.allTime)
    local ws = UGC_DB.weekly.weekStart
    local ds = UGC_DB.daily.dayStart
    wipe(UGC_DB.weekly)
    wipe(UGC_DB.daily)
    wipe(UGC_DB.hourlyBuckets)
    UGC_DB.weekly.weekStart = ws
    UGC_DB.daily.dayStart   = ds
    self:ResetSession()
end

-------------------------------------------------------------------------------
-- Item metadata cache
-------------------------------------------------------------------------------
function DB:CacheItem(itemID, name, icon, quality)
    if not itemID or not name then return end
    UGC_DB.itemCache[tostring(itemID)] = {
        name     = name,
        icon     = icon,
        quality  = quality or 1,
        cachedAt = GetServerTime(),
    }
end

function DB:GetCachedItem(itemID)
    return UGC_DB.itemCache[tostring(itemID)]
end

-------------------------------------------------------------------------------
-- Settings access
-------------------------------------------------------------------------------
function DB:GetSettings()
    return UGC_DB.settings
end
