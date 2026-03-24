-------------------------------------------------------------------------------
-- Database.lua
-- Owns all UGC_DB reads/writes. No other module touches UGC_DB directly.
-- Must load second (after Data.lua).
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.DB = {}
local DB = UGC.DB

local SCHEMA_VERSION = 7

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
    professionProgressByCharacter = {},
    professionProgressLegacyMigrated = false,
    community = {
        peers = {},
        lastCleanup = 0,
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
    if ver < 5 then
        if not UGC_DB.community then
            UGC_DB.community = { peers = {}, lastCleanup = 0 }
        end
    end
    if ver < 6 then
        if not UGC_DB.professionProgressByCharacter then
            UGC_DB.professionProgressByCharacter = {}
        end
    end
    if ver < 7 then
        if UGC_DB.professionProgressLegacyMigrated == nil then
            UGC_DB.professionProgressLegacyMigrated = false
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

local function getLegacyNameKey()
    local full = GetUnitName and GetUnitName("player", true)
    if type(full) == "string" and full ~= "" then
        return full
    end

    local name, realm = UnitName("player")
    if not name or name == "" then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm:gsub("%s+", "")
    end
    return name
end

local function getCharacterKey()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then
        return guid
    end

    return getLegacyNameKey() or "Unknown"
end

local function createEmptyProfessionProgress()
    local out = {}
    for _, cat in ipairs(UGC.CATEGORY_ORDER or { "herbs", "ore", "fish", "leather" }) do
        out[cat] = ensureProfessionState(nil)
    end
    return out
end

local function hasLegacyProfessionProgress()
    local src = UGC_DB.professionProgress or {}
    for _, cat in ipairs(UGC.CATEGORY_ORDER or { "herbs", "ore", "fish", "leather" }) do
        local st = ensureProfessionState(src[cat])
        if (st.level or 1) > 1 or (st.xp or 0) > 0 or (st.totalHarvests or 0) > 0 then
            return true
        end
    end
    return false
end

local function cloneLegacyProfessionProgress()
    local out = {}
    local src = UGC_DB.professionProgress or {}
    for _, cat in ipairs(UGC.CATEGORY_ORDER or { "herbs", "ore", "fish", "leather" }) do
        local old = ensureProfessionState(src[cat])
        out[cat] = {
            level = old.level,
            xp = old.xp,
            totalHarvests = old.totalHarvests,
        }
    end
    return out
end

local function createCharacterProgressState()
    UGC_DB.professionProgressLegacyMigrated = (UGC_DB.professionProgressLegacyMigrated == true)

    if (not UGC_DB.professionProgressLegacyMigrated) and hasLegacyProfessionProgress() then
        UGC_DB.professionProgressLegacyMigrated = true
        return cloneLegacyProfessionProgress()
    end

    return createEmptyProfessionProgress()
end

function DB:GetProfessionProgress(category)
    UGC_DB.professionProgressByCharacter = UGC_DB.professionProgressByCharacter or {}

    local charKey = getCharacterKey()
    local state = UGC_DB.professionProgressByCharacter[charKey]
    if type(state) ~= "table" then
        local legacyNameKey = getLegacyNameKey()
        if legacyNameKey and type(UGC_DB.professionProgressByCharacter[legacyNameKey]) == "table" then
            state = UGC_DB.professionProgressByCharacter[legacyNameKey]
            UGC_DB.professionProgressByCharacter[charKey] = state
            UGC_DB.professionProgressByCharacter[legacyNameKey] = nil
        else
            state = createCharacterProgressState()
            UGC_DB.professionProgressByCharacter[charKey] = state
        end
    end

    state[category] = ensureProfessionState(state[category])
    return state[category]
end

function DB:SetProfessionProgress(category, state)
    UGC_DB.professionProgressByCharacter = UGC_DB.professionProgressByCharacter or {}

    local charKey = getCharacterKey()
    local charState = UGC_DB.professionProgressByCharacter[charKey]
    if type(charState) ~= "table" then
        local legacyNameKey = getLegacyNameKey()
        if legacyNameKey and type(UGC_DB.professionProgressByCharacter[legacyNameKey]) == "table" then
            charState = UGC_DB.professionProgressByCharacter[legacyNameKey]
            UGC_DB.professionProgressByCharacter[charKey] = charState
            UGC_DB.professionProgressByCharacter[legacyNameKey] = nil
        else
            charState = createCharacterProgressState()
            UGC_DB.professionProgressByCharacter[charKey] = charState
        end
    end

    charState[category] = ensureProfessionState(state)
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


-------------------------------------------------------------------------------
-- Community peer data
-------------------------------------------------------------------------------
local function _sanitizeClassToken(token)
    token = tostring(token or ""):upper()
    if token == "" then return nil end
    return token
end

local function _copyCounts(src)
    return {
        herbs = tonumber(src and src.herbs) or 0,
        ore = tonumber(src and src.ore) or 0,
        fish = tonumber(src and src.fish) or 0,
        leather = tonumber(src and src.leather) or 0,
    }
end

local function _copyProgress(src)
    local out = {}
    for _, cat in ipairs(UGC.CATEGORY_ORDER or { "herbs", "ore", "fish", "leather" }) do
        local p = src and src[cat] or {}
        out[cat] = {
            level = math.max(1, tonumber(p.level) or 1),
            title = tostring(p.title or "Novice"),
        }
    end
    return out
end

function DB:GetCommunityPeers()
    UGC_DB.community = UGC_DB.community or { peers = {}, lastCleanup = 0 }
    UGC_DB.community.peers = UGC_DB.community.peers or {}
    return UGC_DB.community.peers
end

function DB:UpsertCommunityPeer(name, payload)
    if type(name) ~= "string" or name == "" or type(payload) ~= "table" then return end
    local peers = self:GetCommunityPeers()

    local baseName = name:match("^([^%-]+)%-")
    if baseName and peers[baseName] then
        peers[baseName] = nil
    end

    peers[name] = {
        name = name,
        updatedAt = tonumber(payload.updatedAt) or UGC.Compat:GetServerTime(),
        totals = _copyCounts(payload.totals),
        levels = _copyProgress(payload.levels),
        classToken = _sanitizeClassToken(payload.classToken),
    }
end

function DB:PruneCommunityPeers(maxAgeSeconds)
    local peers = self:GetCommunityPeers()
    local now = UGC.Compat:GetServerTime()
    maxAgeSeconds = tonumber(maxAgeSeconds) or (7 * 24 * 3600)
    for name, peer in pairs(peers) do
        if not peer or (now - (tonumber(peer.updatedAt) or 0)) > maxAgeSeconds then
            peers[name] = nil
        end
    end
    UGC_DB.community.lastCleanup = now
end
