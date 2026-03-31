-------------------------------------------------------------------------------
-- Progression.lua
-- Profession XP/level progression for gathering categories.
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Progression = {}
local Progression = UGC.Progression

local MAX_LEVEL = 100
local CREATURE_MAX_LEVEL = 50
local XP_PER_HARVEST = 10
local GAIN_POPUP_SECONDS = 1.8
local CHAIN_WINDOW_SECONDS = 5 * 60
local FISH_CHAIN_WINDOW_SECONDS = 3 * 60
local CHAIN_BONUS_XP = 50
local FISH_SUPER_CHAIN_COUNT = 15
local FISH_SUPER_CHAIN_BONUS_XP = 100

local CHAIN_REQUIREMENTS = {
    herbs = 10,
    ore = 10,
    leather = 10,
    fish = 7,
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

local CREATURE_UNLOCK_LEVEL = 5
local FEED_COST_XP = 100
local CREATURE_XP_BONUS_PER_LEVEL = 0.01
local CREATURE_DEFAULT_NAMES = {
    herbs = "Spriglet",
    ore = "Pebblin",
    fish = "Blooplet",
    leather = "Snugglehide",
}

local function getCreaturePhaseForLevel(level)
    if level <= 5 then return 1 end
    if level <= 15 then return 2 end
    if level <= 25 then return 3 end
    if level <= 40 then return 4 end
    return 5
end

Progression._recentGain = {}
Progression._chainState = {}

function Progression:_IsProfessionOnlyMode()
    local s = UGC.DB and UGC.DB:GetSettings()
    return s and s.professionOnlyMode == true
end

function Progression:_GetChainBonusXP(category)
    local needed = CHAIN_REQUIREMENTS[category]
    if not needed then
        return 0
    end

    local now = GetTime()
    local chainWindow = CHAIN_WINDOW_SECONDS
    if category == "fish" then
        chainWindow = FISH_CHAIN_WINDOW_SECONDS
    end

    local chain = self._chainState[category]
    if not chain or (now - (chain.startTime or 0)) > chainWindow then
        chain = {
            startTime = now,
            count = 0,
            fishTierAwards = 0,
            fishSuperAwarded = false,
        }
        self._chainState[category] = chain
    end
    chain.count = (chain.count or 0) + 1

    if category == "fish" then
        local bonusXP = 0

        local earnedTiers = math.floor((chain.count or 0) / needed)
        local missingTierAwards = earnedTiers - (chain.fishTierAwards or 0)
        if missingTierAwards > 0 then
            bonusXP = bonusXP + (missingTierAwards * CHAIN_BONUS_XP)
            chain.fishTierAwards = earnedTiers
        end

        if chain.count >= FISH_SUPER_CHAIN_COUNT and not chain.fishSuperAwarded then
            bonusXP = bonusXP + FISH_SUPER_CHAIN_BONUS_XP
            chain.fishSuperAwarded = true
        end

        return bonusXP
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
        maxLevelReached = state.maxLevelReached or state.level,
        reqXP = reqXP,
        title = self:GetTitle(category, state.level),
        totalHarvests = state.totalHarvests,
        maxLevel = MAX_LEVEL,
    }
end

function Progression:GetCreatureXPRequirement(category, level)
    if level >= CREATURE_MAX_LEVEL then
        return 0
    end
    return self:GetXPRequirement(category, level)
end

function Progression:_AdvanceCreatureNonEvolutionLevels(category, creature)
    local changed = false
    while creature.level < CREATURE_MAX_LEVEL do
        local req = self:GetCreatureXPRequirement(category, creature.level)
        if req <= 0 or (creature.xp or 0) < req then
            break
        end

        local currentPhase = getCreaturePhaseForLevel(creature.level)
        local nextPhase = getCreaturePhaseForLevel(creature.level + 1)
        if nextPhase > currentPhase then
            break
        end

        creature.xp = creature.xp - req
        creature.level = creature.level + 1
        creature.maxLevelReached = math.max(creature.maxLevelReached or creature.level, creature.level)
        changed = true
    end

    if creature.level >= CREATURE_MAX_LEVEL then
        creature.level = CREATURE_MAX_LEVEL
        creature.xp = 0
        changed = true
    end

    return changed
end

function Progression:GetCreatureProgress(category)
    local st = UGC.DB:GetCreatureProgress(category)
    if category == "fish" and not st.unlocked then
        st.unlocked = true
        st.level = st.level or 1
        st.maxLevelReached = math.max(st.maxLevelReached or 1, st.level or 1)
        st.name = st.name or CREATURE_DEFAULT_NAMES[category] or "Gatherling"
        UGC.DB:SetCreatureProgress(category, st)
    end
    if self:_AdvanceCreatureNonEvolutionLevels(category, st) then
        UGC.DB:SetCreatureProgress(category, st)
    end
    local reqXP = self:GetCreatureXPRequirement(category, st.level)
    return {
        unlocked = st.unlocked == true,
        level = st.level,
        xp = st.xp,
        reqXP = reqXP,
        maxLevelReached = st.maxLevelReached or st.level,
        name = st.name or CREATURE_DEFAULT_NAMES[category] or "Gatherling",
        totalBonusXP = math.floor(st.totalBonusXP or 0),
        bonusPercent = ((st.unlocked == true) and ((st.level or 0) * CREATURE_XP_BONUS_PER_LEVEL * 100) or 0),
        maxLevel = CREATURE_MAX_LEVEL,
    }
end

function Progression:GetBestCreature()
    local best = nil
    for _, cat in ipairs(UGC.CATEGORY_ORDER or {}) do
        local cp = self:GetCreatureProgress(cat)
        if cp.unlocked then
            if not best
                or cp.level > best.level
                or (cp.level == best.level and cp.maxLevelReached > (best.maxLevelReached or best.level)) then
                best = {
                    category = cat,
                    level = cp.level,
                    maxLevelReached = cp.maxLevelReached,
                    name = cp.name,
                }
            end
        end
    end
    return best
end

function Progression:RenameCreature(category, newName)
    if type(newName) ~= "string" then return false end
    local cleaned = strtrim(newName)
    if cleaned == "" then return false end
    local st = UGC.DB:GetCreatureProgress(category)
    st.name = cleaned
    UGC.DB:SetCreatureProgress(category, st)
    return true
end

function Progression:_CanSpendProfessionXP(category, amount)
    local state = UGC.DB:GetProfessionProgress(category)
    local lvl = state.level
    local xp = state.xp
    local remaining = amount
    while remaining > 0 do
        if xp >= remaining then
            return true
        end
        remaining = remaining - xp
        if lvl <= 1 then
            return false
        end
        lvl = lvl - 1
        xp = self:GetXPRequirement(category, lvl)
    end
    return true
end

function Progression:_SpendProfessionXP(category, amount)
    local state = UGC.DB:GetProfessionProgress(category)
    local remaining = amount
    while remaining > 0 do
        if state.xp >= remaining then
            state.xp = state.xp - remaining
            remaining = 0
        else
            remaining = remaining - state.xp
            if state.level <= 1 then
                return false
            end
            state.level = state.level - 1
            state.xp = self:GetXPRequirement(category, state.level)
        end
    end
    UGC.DB:SetProfessionProgress(category, state)
    return true
end

function Progression:FeedCreature(category)
    local creature = UGC.DB:GetCreatureProgress(category)
    if not creature.unlocked then
        return false, "locked"
    end
    if creature.level >= CREATURE_MAX_LEVEL then
        return false, "max"
    end
    if not self:_CanSpendProfessionXP(category, FEED_COST_XP) then
        return false, "xp"
    end

    if not self:_SpendProfessionXP(category, FEED_COST_XP) then
        return false, "xp"
    end

    creature.xp = (creature.xp or 0) + FEED_COST_XP
    local leveled = self:_AdvanceCreatureNonEvolutionLevels(category, creature)

    UGC.DB:SetCreatureProgress(category, creature)

    if UGC.Community then
        UGC.Community:BroadcastSnapshot(true)
    end
    if creature.level < CREATURE_MAX_LEVEL then
        local req = self:GetCreatureXPRequirement(category, creature.level)
        local currentPhase = getCreaturePhaseForLevel(creature.level)
        local nextPhase = getCreaturePhaseForLevel(creature.level + 1)
        if req > 0 and creature.xp >= req and nextPhase > currentPhase then
            return true, "ready"
        end
    end
    if leveled then
        return true, "levelup"
    end
    return true, "xp"
end

function Progression:CanEvolveCreature(category)
    local creature = UGC.DB:GetCreatureProgress(category)
    if self:_AdvanceCreatureNonEvolutionLevels(category, creature) then
        UGC.DB:SetCreatureProgress(category, creature)
    end
    if not creature.unlocked or creature.level >= CREATURE_MAX_LEVEL then
        return false
    end
    local req = self:GetCreatureXPRequirement(category, creature.level)
    if req <= 0 or (creature.xp or 0) < req then
        return false
    end

    local currentPhase = getCreaturePhaseForLevel(creature.level)
    local nextPhase = getCreaturePhaseForLevel(creature.level + 1)
    return nextPhase > currentPhase
end

function Progression:EvolveCreature(category)
    local creature = UGC.DB:GetCreatureProgress(category)
    if self:_AdvanceCreatureNonEvolutionLevels(category, creature) then
        UGC.DB:SetCreatureProgress(category, creature)
    end
    if not creature.unlocked then
        return false, "locked"
    end
    if creature.level >= CREATURE_MAX_LEVEL then
        return false, "max"
    end

    local req = self:GetCreatureXPRequirement(category, creature.level)
    if req <= 0 or (creature.xp or 0) < req then
        return false, "xp"
    end
    local currentPhase = getCreaturePhaseForLevel(creature.level)
    local nextPhase = getCreaturePhaseForLevel(creature.level + 1)
    if nextPhase <= currentPhase then
        return false, "phase"
    end

    creature.xp = creature.xp - req
    creature.level = creature.level + 1
    creature.maxLevelReached = math.max(creature.maxLevelReached or creature.level, creature.level)

    if creature.level >= CREATURE_MAX_LEVEL then
        creature.level = CREATURE_MAX_LEVEL
        creature.xp = 0
    end

    UGC.DB:SetCreatureProgress(category, creature)
    if UGC.Community then
        UGC.Community:BroadcastSnapshot(true)
    end
    return true, "levelup"
end

function Progression:GrantProfessionXP(category, amount)
    if not category or not UGC.CATEGORIES[category] then
        return false, "category"
    end
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, "amount"
    end

    local state = UGC.DB:GetProfessionProgress(category)
    if state.level >= MAX_LEVEL then
        return false, "max"
    end

    state.xp = (state.xp or 0) + math.floor(amount)
    local leveledUp = false
    while state.level < MAX_LEVEL do
        local req = self:GetXPRequirement(category, state.level)
        if state.xp < req then
            break
        end
        state.xp = state.xp - req
        state.level = state.level + 1
        state.maxLevelReached = math.max(state.maxLevelReached or state.level, state.level)
        leveledUp = true
    end

    if state.level >= MAX_LEVEL then
        state.level = MAX_LEVEL
        state.xp = 0
    end

    UGC.DB:SetProfessionProgress(category, state)
    self._recentGain[category] = { amount = math.floor(amount), bonus = 0, t = GetTime() }

    if state.level >= CREATURE_UNLOCK_LEVEL then
        local creature = UGC.DB:GetCreatureProgress(category)
        if not creature.unlocked then
            creature.unlocked = true
            creature.level = creature.level or 1
            creature.maxLevelReached = math.max(creature.maxLevelReached or 1, creature.level or 1)
            creature.name = creature.name or CREATURE_DEFAULT_NAMES[category] or "Gatherling"
            UGC.DB:SetCreatureProgress(category, creature)
        end
    end

    return true, { level = state.level, xp = state.xp, leveledUp = leveledUp }
end

function Progression:GetRecentGain(category)
    local g = self._recentGain[category]
    if not g then return nil end
    if (GetTime() - (g.t or 0)) > GAIN_POPUP_SECONDS then
        return nil
    end
    return g
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

    local petBonusGranted = 0
    local creature = UGC.DB:GetCreatureProgress(category)
    if creature and creature.unlocked and (creature.level or 0) > 0 then
        local bonusMultiplier = (creature.level or 0) * CREATURE_XP_BONUS_PER_LEVEL
        local remainder = creature.bonusXPFraction or 0
        local exactBonus = (xpGain * bonusMultiplier) + remainder
        petBonusGranted = math.floor(exactBonus)
        creature.bonusXPFraction = exactBonus - petBonusGranted
        creature.totalBonusXP = math.floor((creature.totalBonusXP or 0) + petBonusGranted)
        UGC.DB:SetCreatureProgress(category, creature)
    end
    xpGain = xpGain + petBonusGranted

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
        state.maxLevelReached = math.max(state.maxLevelReached or state.level, state.level)
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

    if state.level >= CREATURE_UNLOCK_LEVEL then
        local creature = UGC.DB:GetCreatureProgress(category)
        if not creature.unlocked then
            creature.unlocked = true
            creature.level = creature.level or 1
            creature.maxLevelReached = math.max(creature.maxLevelReached or 1, creature.level or 1)
            creature.name = creature.name or CREATURE_DEFAULT_NAMES[category] or "Gatherling"
            UGC.DB:SetCreatureProgress(category, creature)
            if not self:_IsProfessionOnlyMode() then
                self:_AnnounceCenter(string.format("NEW CREATURE FOUND! %s companion unlocked.", catLabel))
            end
        end
    end

    local reqXP = self:GetXPRequirement(category, state.level)
    local gainLabel = string.format("+%d", xpGain)
    if bonusXPGain > 0 then
        gainLabel = string.format("+%d (%d bonus chain)", xpGain, bonusXPGain)
    end
    if petBonusGranted > 0 then
        gainLabel = string.format("%s |cff4da6ff(+%d exp)|r", gainLabel, petBonusGranted)
    end

    if not self:_IsProfessionOnlyMode() then
        print(string.format("|cff33E633UGC|r |cffffffff%s %s EXP|r (%d/%d)",
            gainLabel, catLabel, state.xp, reqXP))
    end

    if leveledUp and not self:_IsProfessionOnlyMode() then
        self:_AnnounceCenter(string.format("LEVEL UP! %s reached Level %d", catLabel, state.level))
    end

    if bonusXPGain > 0 and not self:_IsProfessionOnlyMode() then
        self:_AnnounceCenter(string.format("BONUS CHAIN! +%d %s EXP", bonusXPGain, catLabel))
    end

    if not self:_IsProfessionOnlyMode() then
        for _, t in ipairs(unlockedTitles) do
            self:_AnnounceCenter(string.format("NEW TITLE UNLOCKED! %s: \"%s\"", catLabel, t.title))
        end
    end

    self._recentGain[category] = { amount = xpGain, bonus = petBonusGranted, t = GetTime() }

    C_Timer.After(GAIN_POPUP_SECONDS + 0.1, function()
        if UGC.Overlay and UGC.Overlay.frame and UGC.Overlay.frame:IsShown() then
            UGC.Overlay:Refresh()
        end
        if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
            UGC.Details:Refresh()
        end
        if UGC.Creatures and UGC.Creatures.frame and UGC.Creatures.frame:IsShown() then
            UGC.Creatures:Refresh()
        end
    end)
end


function Progression:ResetChainState()
    wipe(self._chainState)
end
