-------------------------------------------------------------------------------
-- Database.lua
-- Owns all UGC_DB reads/writes. No other module touches UGC_DB directly.
-- Must load second (after Data.lua).
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.DB = {}
local DB = UGC.DB

local SCHEMA_VERSION = 4

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
        overlayMinimized    = false, -- true = title bar only
        overlayHeight       = 360,  -- user-resized height
        detailsWidth        = 530,  -- user-resized details window size
        detailsHeight       = 480,
    },
    allTime        = {},
    weekly         = { weekStart = 0 },
    daily          = { dayStart  = 0 },
    hourlyBuckets  = {},
    itemCache      = {},
    gatherActions  = {
        allTime = { herbs = 0, ore = 0, fish = 0, leather = 0 },
        daily   = { dayStart = 0, herbs = 0, ore = 0, fish = 0, leather = 0 },
        weekly  = { weekStart = 0, herbs = 0, ore = 0, fish = 0, leather = 0 },
    },
    professionProgress = {
        herbs   = { level = 1, xp = 0, totalHarvests = 0 },
        ore     = { level = 1, xp = 0, totalHarvests = 0 },
        fish    = { level = 1, xp = 0, totalHarvests = 0 },
        leather = { level = 1, xp = 0, totalHarvests = 0 },
    },
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

    -- Schema migrations
    local ver = UGC_DB.version or 1
    if ver < 2 then
        if not UGC_DB.hourlyBuckets then UGC_DB.hourlyBuckets = {} end
        if not UGC_DB.itemCache      then UGC_DB.itemCache      = {} end
    end
    if ver < 3 then
        if not UGC_DB.gatherActions then
            UGC_DB.gatherActions = {
                allTime = { herbs=0, ore=0, fish=0, leather=0 },
                daily   = { dayStart=0, herbs=0, ore=0, fish=0, leather=0 },
                weekly  = { weekStart=0, herbs=0, ore=0, fish=0, leather=0 },
            }
        end
    end
    if ver < 4 then
        if not UGC_DB.professionProgress then
            UGC_DB.professionProgress = {
                herbs   = { level = 1, xp = 0, totalHarvests = 0 },
                ore     = { level = 1, xp = 0, totalHarvests = 0 },
                fish    = { level = 1, xp = 0, totalHarvests = 0 },
                leather = { level = 1, xp = 0, totalHarvests = 0 },
            }
        end
    end
    if ver < SCHEMA_VERSION then
        UGC_DB.version = SCHEMA_VERSION
    end

    -- Reset stale daily/weekly data based on server time
    local now      = UGC.Compat:GetServerTime()
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

    -- Reset stale gatherActions daily/weekly
    local ga = UGC_DB.gatherActions
    if ga then
        if ga.daily.dayStart ~= dayStart then
            local ds = dayStart
            wipe(ga.daily)
            ga.daily.dayStart = ds
        end
        if ga.weekly.weekStart ~= weekStart then
            local ws = weekStart
            wipe(ga.weekly)
            ga.weekly.weekStart = ws
        end
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
    local bucket = self:_ensureHourlyBucket(UGC.Compat:GetServerTime())
    local id = tostring(itemID)
    bucket.items[id] = (bucket.items[id] or 0) + delta
end

-------------------------------------------------------------------------------
-- Record gain (call this whenever a gathering item is acquired)
-------------------------------------------------------------------------------
function DB:RecordGain(itemID, delta)
    if not delta or delta <= 0 then return end
    local id  = tostring(itemID)
    local now = UGC.Compat:GetServerTime()

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
    local now    = UGC.Compat:GetServerTime()
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
-- Gather actions (count of gathering events, not item quantities)
-------------------------------------------------------------------------------
function DB:RecordGatherAction(category)
    if not category then return end
    local ga = UGC_DB.gatherActions
    ga.allTime[category]  = (ga.allTime[category]  or 0) + 1
    ga.daily[category]    = (ga.daily[category]    or 0) + 1
    ga.weekly[category]   = (ga.weekly[category]   or 0) + 1
end

-- Returns { herbs, ore, fish, leather, total } for the given period key.
-- period: "allTime" | "daily" | "weekly"
function DB:GetGatherActions(period)
    local ga = UGC_DB.gatherActions
    local t  = (ga and ga[period]) or {}
    local h  = t.herbs   or 0
    local o  = t.ore     or 0
    local f  = t.fish    or 0
    local l  = t.leather or 0
    return { herbs = h, ore = o, fish = f, leather = l, total = h + o + f + l }
end

-------------------------------------------------------------------------------
-- Profession progression state
-------------------------------------------------------------------------------
local function ensureProfessionState(state)
    if type(state) ~= "table" then
        state = {}
    end
    if type(state.level) ~= "number" or state.level < 1 then
        state.level = 1
    end
    if type(state.xp) ~= "number" or state.xp < 0 then
        state.xp = 0
    end
    if type(state.totalHarvests) ~= "number" or state.totalHarvests < 0 then
        state.totalHarvests = 0
    end
    return state
end

function DB:GetProfessionProgress(category)
    UGC_DB.professionProgress = UGC_DB.professionProgress or {}
    UGC_DB.professionProgress[category] =
        ensureProfessionState(UGC_DB.professionProgress[category])
    return UGC_DB.professionProgress[category]
end

function DB:SetProfessionProgress(category, state)
    UGC_DB.professionProgress = UGC_DB.professionProgress or {}
    UGC_DB.professionProgress[category] = ensureProfessionState(state)
end

-------------------------------------------------------------------------------
-- Reset
-------------------------------------------------------------------------------
function DB:ResetSession()
    if UGC.Session then
        UGC.Session.startTime = GetTime()
        wipe(UGC.Session.items)
        UGC.Session.bagSnapshot = {}
        if UGC.Session.gatherCount then
            wipe(UGC.Session.gatherCount)
        end
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
    -- Reset gatherActions
    local ga = UGC_DB.gatherActions
    if ga then
        local ws2 = ga.weekly.weekStart
        local ds2 = ga.daily.dayStart
        wipe(ga.allTime)
        wipe(ga.daily)
        wipe(ga.weekly)
        ga.daily.dayStart   = ds2
        ga.weekly.weekStart = ws2
    end
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
        quality  = quality,  -- nil if not yet loaded; shown only when known
        cachedAt = UGC.Compat:GetServerTime(),
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
