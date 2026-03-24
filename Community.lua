-------------------------------------------------------------------------------
-- Community.lua
-- In-game only community sync via addon channel "UGC".
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Community = {}
local Community = UGC.Community

local PREFIX = "UGC_SYNC"
local CHANNEL_NAME = "UGC"
local VERSION = 1
local STALE_SECONDS = 7 * 24 * 3600
local THROTTLE_SECONDS = 20

Community._lastSendAt = 0

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
    }, "|")
end

local function decodePayload(msg)
    local parts = split(msg or "", "|")
    if #parts < 14 or parts[1] ~= "S" then
        return nil
    end
    if tonumber(parts[2]) ~= VERSION then
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
        }
    }
end

function Community:_getPlayerName()
    local n, realm = UnitName("player")
    if realm and realm ~= "" then
        return n .. "-" .. realm
    end
    return n or "Unknown"
end

function Community:_collectLocalSnapshot()
    local totals = UGC.DB:GetGatherActions("allTime")
    local levels = {}
    for _, cat in ipairs(UGC.CATEGORY_ORDER) do
        local p = UGC.Progression and UGC.Progression:GetProgress(cat) or { level = 1, title = "Novice" }
        levels[cat] = { level = p.level or 1, title = p.title or "Novice" }
    end
    return { totals = totals, levels = levels }
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
    UGC.DB:UpsertCommunityPeer(self:_getPlayerName(), {
        totals = snapshot.totals,
        levels = snapshot.levels,
        updatedAt = UGC.Compat:GetServerTime(),
    })

    self:_send(encodePayload(snapshot))
end

function Community:RequestSync()
    self:_send("R|" .. tostring(VERSION))
end

function Community:_joinChannel()
    if type(JoinChannelByName) ~= "function" then
        return
    end
    local id = GetChannelName(CHANNEL_NAME)
    if not id or id <= 0 then
        JoinChannelByName(CHANNEL_NAME)
    end

    if type(ChatFrame_RemoveChannel) == "function" then
        for i = 1, (NUM_CHAT_WINDOWS or 0) do
            local frame = _G["ChatFrame" .. i]
            if frame then
                ChatFrame_RemoveChannel(frame, CHANNEL_NAME)
            end
        end
    end
end

function Community:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end

    self:_joinChannel()
    C_Timer.After(2, function()
        Community:_joinChannel()
        Community:RequestSync()
        Community:BroadcastSnapshot(true)
    end)
end

function Community:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or not sender or sender == "" then return end

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
        updatedAt = UGC.Compat:GetServerTime(),
    })

    UGC.DB:PruneCommunityPeers(STALE_SECONDS)

    if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
        UGC.Details:Refresh()
    end
end
