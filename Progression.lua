-------------------------------------------------------------------------------
-- Progression.lua
-- Profession XP/level progression for gathering categories.
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Progression = {}
local Progression = UGC.Progression

local MAX_LEVEL = 100
local XP_PER_HARVEST = 10
local GAIN_POPUP_SECONDS = 1.8
local CHAIN_WINDOW_SECONDS = 5 * 60
local CHAIN_BONUS_XP = 50

local CHAIN_REQUIREMENTS = {
    herbs = 10,
    ore = 10,
    leather = 10,
    fish = 15,
}
local BONUS_XP_BY_ITEM_ID = {
    [236780] = 100, -- Lotus nocturne
    [237366] = 100, -- Thorium éblouissant
}

local BASE_REQUIREMENTS = {
    [1] = 10,
    [2] = 20,
    [3] = 30,
    [4] = 40,
    [5] = 50,
    [6] = 60,
    [7] = 75,
    [8] = 80,
}

local MULTIPLIER_BY_CATEGORY = {
    herbs   = 1.0,
    ore     = 1.0,
    leather = 1.2,
    fish    = 0.5,
}

local TITLES = {
    herbs = {
        [5] = "Sprout Gatherer", [10] = "Field Herbalist", [15] = "Grove Tender",
        [20] = "Wildleaf Collector", [25] = "Root Seeker", [30] = "Greenwarden",
        [35] = "Bloomkeeper", [40] = "Thornwise", [45] = "Canopy Ranger",
        [50] = "Verdant Scholar", [55] = "Sap Sage", [60] = "Briar Master",
        [65] = "Petalbound", [70] = "Sylvan Adept", [75] = "Lifebloom Warden",
        [80] = "Ancient Grovekeeper", [85] = "Heartwood Mystic", [90] = "Archdruid of Herbs",
        [95] = "Eternal Botanist", [100] = "Prime Verdant",
    },
    ore = {
        [5] = "Rock Prospector", [10] = "Tunnel Worker", [15] = "Ore Seeker",
        [20] = "Vein Tracker", [25] = "Deep Delver", [30] = "Stonebreaker",
        [35] = "Ironpath Miner", [40] = "Bedrock Specialist", [45] = "Quarry Veteran",
        [50] = "Forgebound Excavator", [55] = "Crystal Delver", [60] = "Mithril Hunter",
        [65] = "Obsidian Cutter", [70] = "Runestone Miner", [75] = "Earthshaper",
        [80] = "Mountain Warden", [85] = "Deepcore Master", [90] = "High Prospector",
        [95] = "Legendary Excavator", [100] = "Prime Geomancer",
    },
    fish = {
        [5] = "Pond Angler", [10] = "River Caster", [15] = "Lake Fisher",
        [20] = "Tide Hooker", [25] = "Current Tracker", [30] = "Netwise",
        [35] = "Reef Seeker", [40] = "Deepwater Angler", [45] = "Stormline Fisher",
        [50] = "Master Caster", [55] = "Silverfin Hunter", [60] = "Abyssal Trawler",
        [65] = "Tidecaller", [70] = "Ocean Whisperer", [75] = "Kraken Baiter",
        [80] = "Sea Warden", [85] = "Leviathan Angler", [90] = "High Mariner",
        [95] = "Mythic Fisher", [100] = "Prime Tideborn",
    },
    leather = {
        [5] = "Hide Stripper", [10] = "Pelt Collector", [15] = "Fur Handler",
        [20] = "Leather Scout", [25] = "Hideworker", [30] = "Trackflayer",
        [35] = "Fang & Fur Cutter", [40] = "Peltcrafter", [45] = "Wildhide Specialist",
        [50] = "Beastflayer", [55] = "Ironhide Skiller", [60] = "Predator Skinner",
        [65] = "Alpha Tracker", [70] = "Trophy Flayer", [75] = "Savage Leathermaster",
        [80] = "Prime Hidewarden", [85] = "Apex Skinner", [90] = "Mythic Flayer",
        [95] = "Eternal Beastworker", [100] = "Prime Huntmaster",
    },
}


Progression._recentGain = {}
Progression._chainState = {}

function Progression:_GetChainBonusXP(category)
    local needed = CHAIN_REQUIREMENTS[category]
    if not needed then
        return 0
    end

    local now = GetTime()
    local chain = self._chainState[category]
    if not chain or (now - (chain.startTime or 0)) > CHAIN_WINDOW_SECONDS then
        chain = { startTime = now, count = 1 }
        self._chainState[category] = chain
    else
        chain.count = (chain.count or 0) + 1
    end

    if chain.count >= needed then
        self._chainState[category] = nil
        return CHAIN_BONUS_XP
    end

    return 0
end

local function GetIncrementForLevel(level)
    if level <= 20 then return 15 end
    if level <= 40 then return 20 end
    if level <= 60 then return 25 end
    if level <= 80 then return 35 end
    return 50
end

function Progression:GetBaseHarvestRequirement(level)
    if level >= MAX_LEVEL then return 0 end
    if BASE_REQUIREMENTS[level] then
        return BASE_REQUIREMENTS[level]
    end

    local req = BASE_REQUIREMENTS[8]
    for l = 9, level do
        req = req + GetIncrementForLevel(l)
    end
    return req
end

function Progression:GetHarvestRequirement(category, level)
    local base = self:GetBaseHarvestRequirement(level)
    local mult = MULTIPLIER_BY_CATEGORY[category] or 1.0
    return math.max(1, math.ceil(base * mult))
end

function Progression:GetXPRequirement(category, level)
    return self:GetHarvestRequirement(category, level) * XP_PER_HARVEST
end

function Progression:GetTitle(category, level)
    local titles = TITLES[category] or {}
    local best = nil
    for lvl = 5, MAX_LEVEL, 5 do
        if level >= lvl and titles[lvl] then
            best = titles[lvl]
        end
    end
    return best or "Novice"
end

function Progression:GetProgress(category)
    local state = UGC.DB:GetProfessionProgress(category)
    local reqXP = self:GetXPRequirement(category, state.level)
    return {
        level = state.level,
        xp = state.xp,
        reqXP = reqXP,
        title = self:GetTitle(category, state.level),
        totalHarvests = state.totalHarvests,
        maxLevel = MAX_LEVEL,
    }
end

function Progression:GetRecentGain(category)
    local g = self._recentGain[category]
    if not g then return nil end
    if (GetTime() - (g.t or 0)) > GAIN_POPUP_SECONDS then
        return nil
    end
    return g.amount
end

function Progression:_AnnounceCenter(message)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["SYSTEM"])
    end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(message, 0.2, 1.0, 0.2, 1.5)
    end
end

function Progression:GetGatherXPGain(itemID)
    if itemID and BONUS_XP_BY_ITEM_ID[itemID] then
        return BONUS_XP_BY_ITEM_ID[itemID]
    end
    return XP_PER_HARVEST
end

function Progression:AddGatherAction(category, itemID)
    if not category or not UGC.CATEGORIES[category] then return end

    local state = UGC.DB:GetProfessionProgress(category)
    if state.level >= MAX_LEVEL then
        return
    end

    local baseXPGain = self:GetGatherXPGain(itemID)
    local bonusXPGain = self:_GetChainBonusXP(category)
    local xpGain = baseXPGain + bonusXPGain

    state.totalHarvests = (state.totalHarvests or 0) + 1
    state.xp = (state.xp or 0) + xpGain

    local unlockedTitles = {}
    local leveledUp = false

    while state.level < MAX_LEVEL do
        local req = self:GetXPRequirement(category, state.level)
        if state.xp < req then
            break
        end
        state.xp = state.xp - req
        state.level = state.level + 1
        leveledUp = true

        if state.level % 5 == 0 then
            local title = self:GetTitle(category, state.level)
            table.insert(unlockedTitles, { level = state.level, title = title })
        end
    end

    if state.level >= MAX_LEVEL then
        state.level = MAX_LEVEL
        state.xp = 0
    end

    UGC.DB:SetProfessionProgress(category, state)

    local catLabel = UGC.CATEGORIES[category].label
    local reqXP = self:GetXPRequirement(category, state.level)
    local gainLabel = string.format("+%d", xpGain)
    if bonusXPGain > 0 then
        gainLabel = string.format("+%d (%d bonus chain)", xpGain, bonusXPGain)
    end

    print(string.format("|cff33E633UGC|r |cffffffff%s %s EXP|r (%d/%d)",
        gainLabel, catLabel, state.xp, reqXP))

    if leveledUp then
        self:_AnnounceCenter(string.format("LEVEL UP! %s reached Level %d", catLabel, state.level))
    end

    if bonusXPGain > 0 then
        self:_AnnounceCenter(string.format("BONUS CHAIN! +%d %s EXP", bonusXPGain, catLabel))
    end

    for _, t in ipairs(unlockedTitles) do
        self:_AnnounceCenter(string.format("NEW TITLE UNLOCKED! %s: \"%s\"", catLabel, t.title))
    end

    self._recentGain[category] = { amount = xpGain, t = GetTime() }

    C_Timer.After(GAIN_POPUP_SECONDS + 0.1, function()
        if UGC.Overlay and UGC.Overlay.frame and UGC.Overlay.frame:IsShown() then
            UGC.Overlay:Refresh()
        end
        if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
            UGC.Details:Refresh()
        end
    end)
end


function Progression:ResetChainState()
    wipe(self._chainState)
end
