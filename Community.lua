-------------------------------------------------------------------------------
-- Community.lua
-- In-game only community sync via addon channel "UGC".
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Community = {}
local Community = UGC.Community

local PREFIX = "UGC_SYNC"
local CHANNEL_NAME = "UGC"
local TARGET_CHAT_FRAME_ID = 6
local VERSION = 3
local STALE_SECONDS = 7 * 24 * 3600
local THROTTLE_SECONDS = 20
local STATE_GRACE_SECONDS = 2.0

Community._lastSendAt = 0
Community._pendingJoinUntil = 0
Community._pendingLeaveUntil = 0
Community._lastLocalPlayerName = nil

local function split(str, sep)
    local out = {}
    if type(str) ~= "string" or str == "" then
        return out
    end
    local pat = string.format("([^%s]+)", sep)
    for token in string.gmatch(str, pat) do
        table.insert(out, token)
    end
    return out
end

local function encodePayload(data)
    return table.concat({
        "S",
        tostring(VERSION),
        tostring(data.totals.herbs or 0),
        tostring(data.totals.ore or 0),
        tostring(data.totals.fish or 0),
        tostring(data.totals.leather or 0),
        tostring(data.levels.herbs.level or 1),
        tostring(data.levels.ore.level or 1),
        tostring(data.levels.fish.level or 1),
        tostring(data.levels.leather.level or 1),
        tostring(data.levels.herbs.title or "Novice"),
        tostring(data.levels.ore.title or "Novice"),
        tostring(data.levels.fish.title or "Novice"),
        tostring(data.levels.leather.title or "Novice"),
        tostring(data.classToken or ""),
        tostring(data.bestCreature and data.bestCreature.category or ""),
        tostring(data.bestCreature and data.bestCreature.level or 0),
        tostring(data.bestCreature and data.bestCreature.name or ""),
    }, "|")
end

local function decodePayload(msg)
    local parts = split(msg or "", "|")
    if #parts < 14 or parts[1] ~= "S" then
        return nil
    end

    local messageVersion = tonumber(parts[2]) or 0
    if messageVersion < 1 or messageVersion > VERSION then
        return nil
    end
    return {
        totals = {
            herbs = tonumber(parts[3]) or 0,
            ore = tonumber(parts[4]) or 0,
            fish = tonumber(parts[5]) or 0,
            leather = tonumber(parts[6]) or 0,
        },
        levels = {
            herbs = { level = tonumber(parts[7]) or 1, title = parts[11] or "Novice" },
            ore = { level = tonumber(parts[8]) or 1, title = parts[12] or "Novice" },
            fish = { level = tonumber(parts[9]) or 1, title = parts[13] or "Novice" },
            leather = { level = tonumber(parts[10]) or 1, title = parts[14] or "Novice" },
        },
        classToken = parts[15],
        bestCreature = {
            category = parts[16] or "",
            level = tonumber(parts[17]) or 0,
            name = parts[18] or "",
        },
    }
end

local function getChannelOrder()
    if type(GetChannelList) ~= "function" then
        return {}
    end

    local raw = { GetChannelList() }
    local out = {}
    for i = 1, #raw, 3 do
        local id = tonumber(raw[i])
        local name = tostring(raw[i + 1] or "")
        if id and id > 0 and name ~= "" then
            out[#out + 1] = { id = id, name = name }
        end
    end
    return out
end

function Community:_reorderChannelLast(maxPasses)
    if type(C_ChatInfo) ~= "table"
        or type(C_ChatInfo.SwapChatChannelsByChannelIndex) ~= "function" then
        return
    end

    local passes = tonumber(maxPasses) or 1
    for _ = 1, passes do
        local order = getChannelOrder()
        local ugcIndex
        for idx, channel in ipairs(order) do
            if channel.name == CHANNEL_NAME then
                ugcIndex = idx
                break
            end
        end

        if not ugcIndex then
            return
        end
        if ugcIndex >= #order then
            return
        end

        C_ChatInfo.SwapChatChannelsByChannelIndex(order[ugcIndex].id, order[ugcIndex + 1].id)
    end
end

function Community:_scheduleReorderChannelLast()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self:_reorderChannelLast(8)
        return
    end

    local delays = { 0.2, 1.0, 2.0, 4.0 }
    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            Community:_reorderChannelLast(8)
        end)
    end
end

function Community:_getPlayerName()
    local full = GetUnitName and GetUnitName("player", true)
    if full and full ~= "" then
        return full
    end

    local n, realm = UnitName("player")
    if realm and realm ~= "" then
        return n .. "-" .. realm:gsub("%s+", "")
    end
    return n or "Unknown"
end

function Community:_normalizePlayerName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local n, realm = string.match(name, "^([^%-]+)%-(.+)$")
    if n and realm then
        return n .. "-" .. realm:gsub("%s+", "")
    end

    local playerRealm = GetRealmName and GetRealmName() or ""
    playerRealm = tostring(playerRealm):gsub("%s+", "")
    if playerRealm ~= "" then
        return name .. "-" .. playerRealm
    end
    return name
end

function Community:_collectLocalSnapshot()
    local totals = UGC.DB:GetGatherActions("allTime")
    local levels = {}
    for _, cat in ipairs(UGC.CATEGORY_ORDER) do
        local p = UGC.Progression and UGC.Progression:GetProgress(cat) or { level = 1, title = "Novice" }
        levels[cat] = { level = p.level or 1, title = p.title or "Novice" }
    end
    local _, classToken = UnitClass("player")
    local bestCreature = UGC.Progression and UGC.Progression.GetBestCreature and UGC.Progression:GetBestCreature() or nil
    return { totals = totals, levels = levels, classToken = classToken, bestCreature = bestCreature }
end

function Community:_send(msg)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end

    local channelID = GetChannelName(CHANNEL_NAME)
    if channelID and channelID > 0 then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "CHANNEL", channelID)
    end
end

function Community:BroadcastSnapshot(force)
    local now = GetTime()
    if not force and (now - (self._lastSendAt or 0)) < THROTTLE_SECONDS then
        return
    end
    self._lastSendAt = now

    local snapshot = self:_collectLocalSnapshot()
    local localName = self:_normalizePlayerName(self:_getPlayerName())
    if self._lastLocalPlayerName and self._lastLocalPlayerName ~= localName then
        UGC.DB:RemoveCommunityPeer(self._lastLocalPlayerName)
    end
    self._lastLocalPlayerName = localName

    UGC.DB:UpsertCommunityPeer(localName, {
        totals = snapshot.totals,
        levels = snapshot.levels,
        classToken = snapshot.classToken,
        bestCreature = snapshot.bestCreature,
        updatedAt = UGC.Compat:GetServerTime(),
    })

    self:_send(encodePayload(snapshot))
end

function Community:RequestSync()
    self:_send("R|" .. tostring(VERSION))
end

function Community:_joinChannel()
    if type(JoinChannelByName) ~= "function" then
        return false
    end
    JoinChannelByName(CHANNEL_NAME, nil, TARGET_CHAT_FRAME_ID)
    self:_scheduleReorderChannelLast()

    if type(ChatFrame_RemoveChannel) == "function" then
        for i = 1, (NUM_CHAT_WINDOWS or 0) do
            local frame = _G["ChatFrame" .. i]
            if frame then
                ChatFrame_RemoveChannel(frame, CHANNEL_NAME)
            end
        end
    end
    return true
end

function Community:IsJoined()
    local now = GetTime and GetTime() or 0
    if (self._pendingLeaveUntil or 0) > now then
        return false
    end
    if (self._pendingJoinUntil or 0) > now then
        return true
    end

    local id = GetChannelName(CHANNEL_NAME)
    return id and id > 0
end

function Community:JoinLeaderboardChannel()
    local didRequest = self:_joinChannel()
    if not didRequest then
        return false
    end

    local settings = UGC.DB and UGC.DB.GetSettings and UGC.DB:GetSettings()
    if type(settings) == "table" then
        settings.leaderboardAutoJoin = true
    end

    local now = GetTime and GetTime() or 0
    self._pendingJoinUntil = now + STATE_GRACE_SECONDS
    self._pendingLeaveUntil = 0

    C_Timer.After(0.4, function()
        Community:RequestSync()
        Community:BroadcastSnapshot(true)
        if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
            UGC.Details:Refresh()
        end
    end)
    return true
end

function Community:LeaveLeaderboardChannel()
    if type(LeaveChannelByName) ~= "function" then
        return false
    end
    local id = GetChannelName(CHANNEL_NAME)
    if id and id > 0 then
        LeaveChannelByName(CHANNEL_NAME)
        local settings = UGC.DB and UGC.DB.GetSettings and UGC.DB:GetSettings()
        if type(settings) == "table" then
            settings.leaderboardAutoJoin = false
        end
        local now = GetTime and GetTime() or 0
        self._pendingLeaveUntil = now + STATE_GRACE_SECONDS
        self._pendingJoinUntil = 0
        return true
    end
    return false
end

function Community:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end

    local settings = UGC.DB and UGC.DB.GetSettings and UGC.DB:GetSettings()
    local shouldAutoJoin = type(settings) == "table" and settings.leaderboardAutoJoin
    if shouldAutoJoin then
        C_Timer.After(1.2, function()
            Community:JoinLeaderboardChannel()
        end)
    end

    C_Timer.After(2, function()
        if Community:IsJoined() then
            Community:RequestSync()
            Community:BroadcastSnapshot(true)
        end
    end)
end

function Community:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or not sender or sender == "" then return end
    sender = self:_normalizePlayerName(sender)
    if not sender then return end

    local msgType = tostring(message or ""):match("^([A-Z])")
    if msgType == "R" then
        self:BroadcastSnapshot(false)
        return
    end

    local payload = decodePayload(message)
    if not payload then return end

    UGC.DB:UpsertCommunityPeer(sender, {
        totals = payload.totals,
        levels = payload.levels,
        classToken = payload.classToken,
        bestCreature = payload.bestCreature,
        updatedAt = UGC.Compat:GetServerTime(),
    })

    UGC.DB:PruneCommunityPeers(STALE_SECONDS)

    if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
        UGC.Details:Refresh()
    end
end
