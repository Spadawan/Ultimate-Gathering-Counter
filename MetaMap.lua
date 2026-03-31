-------------------------------------------------------------------------------
-- MetaMap.lua
-- Anonymous community heatmap (grid-based, privacy-preserving) for map/minimap.
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.MetaMap = {}
local MetaMap = UGC.MetaMap

local PROTOCOL_VERSION = 1
local MSG_TYPE_HEAT = "H"

local CELL_SIZE = 0.05            -- 20x20 grid per map
local SEND_INTERVAL = 30          -- sec (quasi real-time)
local RENDER_INTERVAL = 5         -- sec
local MAX_CELLS_PER_PACKET = 16
local RETAIN_SECONDS = 24 * 3600
local MINIMAP_PIXELS_PER_CELL = 10

local WINDOW_SECONDS = {
    short = 30 * 60,
    medium = 2 * 3600,
    long = 24 * 3600,
}

MetaMap._dirtyCells = {}
MetaMap._lastSend = 0
MetaMap._lastRender = 0
MetaMap._worldDots = {}
MetaMap._miniDots = {}
MetaMap._recentPings = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function split(str, sep)
    local out = {}
    if type(str) ~= "string" or str == "" then
        return out
    end
    local pat = string.format("([^%s]+)", sep)
    for token in string.gmatch(str, pat) do
        out[#out + 1] = token
    end
    return out
end

local function getMapContextKey(mapID)
    local _, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    instanceID = tonumber(instanceID) or 0
    return string.format("%d:%d:%d", tonumber(mapID) or 0, difficultyID, instanceID)
end

local function getPlayerMapPosition()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
        return nil
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end

    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end

    local x, y
    if type(pos) == "table" and pos.GetXY then
        x, y = pos:GetXY()
    elseif type(pos) == "table" then
        x, y = pos.x, pos.y
    end

    if not x or not y then return nil end
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end

    return mapID, x, y
end

local function makeCellXY(x, y)
    local cx = clamp(math.floor((x or 0) / CELL_SIZE), 0, math.floor(1 / CELL_SIZE) - 1)
    local cy = clamp(math.floor((y or 0) / CELL_SIZE), 0, math.floor(1 / CELL_SIZE) - 1)
    return cx, cy
end

local function makeCellKey(cx, cy, category)
    return string.format("%d,%d,%s", tonumber(cx) or 0, tonumber(cy) or 0, tostring(category or ""))
end

function MetaMap:_getSettings()
    local s = UGC.DB:GetSettings()
    s.metaMapEnabled = s.metaMapEnabled ~= false
    s.metaMapWindow = s.metaMapWindow or "medium"
    s.metaMapCategory = s.metaMapCategory or "all"
    s.metaMapOnMinimap = s.metaMapOnMinimap ~= false
    s.metaMapOnWorldMap = s.metaMapOnWorldMap ~= false
    return s
end

function MetaMap:RecordGather(category)
    local s = self:_getSettings()
    if not s.metaMapEnabled then return end

    local mapID, x, y = getPlayerMapPosition()
    if not mapID then return end

    local cx, cy = makeCellXY(x, y)
    local ctx = getMapContextKey(mapID)
    local key = string.format("%s|%s", ctx, makeCellKey(cx, cy, category))

    local now = UGC.Compat:GetServerTime()
    local pending = self._dirtyCells[key]
    if not pending then
        pending = {
            mapID = mapID,
            context = ctx,
            cx = cx,
            cy = cy,
            category = category,
            count = 0,
            ts = now,
        }
        self._dirtyCells[key] = pending
    end
    pending.count = pending.count + 1
    pending.ts = now

    UGC.DB:UpsertCommunityHeatCell(ctx, cx, cy, category, 1, now, true)
    self._recentPings[#self._recentPings + 1] = {
        context = ctx,
        x = (cx + 0.5) * CELL_SIZE,
        y = (cy + 0.5) * CELL_SIZE,
        ts = now,
    }
    self:Refresh(true)
end

local function encodeHeatPacket(cells)
    local body = {}
    for _, c in ipairs(cells) do
        body[#body + 1] = string.format("%d,%d,%s,%d,%d", c.cx, c.cy, c.category, c.count, c.ts)
    end

    local first = cells[1]
    return table.concat({
        MSG_TYPE_HEAT,
        tostring(PROTOCOL_VERSION),
        tostring(first.mapID or 0),
        tostring(first.context or "0:0:0"),
        table.concat(body, ";"),
    }, "|")
end

function MetaMap:FlushNetwork(force)
    if not UGC.Community or not UGC.Community.IsJoined or not UGC.Community:IsJoined() then
        return
    end

    local now = GetTime()
    if not force and (now - (self._lastSend or 0)) < SEND_INTERVAL then
        return
    end

    local byContext = {}
    for key, cell in pairs(self._dirtyCells) do
        if cell and cell.count and cell.count > 0 then
            local bucketKey = string.format("%d|%s", tonumber(cell.mapID) or 0, tostring(cell.context))
            byContext[bucketKey] = byContext[bucketKey] or {}
            byContext[bucketKey][#byContext[bucketKey] + 1] = cell
        end
        self._dirtyCells[key] = nil
    end

    for _, cells in pairs(byContext) do
        local idx = 1
        while idx <= #cells do
            local payload = {}
            for i = idx, math.min(idx + MAX_CELLS_PER_PACKET - 1, #cells) do
                payload[#payload + 1] = cells[i]
            end
            idx = idx + MAX_CELLS_PER_PACKET
            if #payload > 0 then
                UGC.Community:_send(encodeHeatPacket(payload))
            end
        end
    end

    self._lastSend = now
end

function MetaMap:OnHeatPacket(message)
    local parts = split(message or "", "|")
    if #parts < 5 or parts[1] ~= MSG_TYPE_HEAT then
        return false
    end

    local pVer = tonumber(parts[2]) or 0
    if pVer ~= PROTOCOL_VERSION then
        return true
    end

    local mapID = tonumber(parts[3]) or 0
    local context = tostring(parts[4] or "")
    local body = tostring(parts[5] or "")
    if mapID <= 0 or context == "" or body == "" then
        return true
    end

    local now = UGC.Compat:GetServerTime()
    for _, rawCell in ipairs(split(body, ";")) do
        local c = split(rawCell, ",")
        local cx = tonumber(c[1])
        local cy = tonumber(c[2])
        local category = c[3]
        local count = tonumber(c[4]) or 0
        local ts = tonumber(c[5]) or now
        if cx and cy and category and category ~= "" and count > 0 then
            UGC.DB:UpsertCommunityHeatCell(context, cx, cy, category, count, ts, false)
        end
    end

    return true
end

function MetaMap:GetCellScore(cell, windowSec)
    local now = UGC.Compat:GetServerTime()
    local age = math.max(0, now - (cell.lastUpdate or now))
    if age > windowSec then
        return 0
    end

    local recency = 1 - (age / windowSec)
    local density = math.min(1.0, (cell.count or 0) / 12)
    local quality = math.min(1.0, (cell.samples or 0) / 4)

    return density * (0.45 + 0.55 * recency) * (0.6 + 0.4 * quality)
end

local function colorFromScore(score)
    local s = clamp(score or 0, 0, 1)
    local r = clamp((s - 0.25) * 2, 0, 1)
    local g = clamp(1 - math.abs((s * 2) - 1), 0.15, 1)
    local b = clamp((0.6 - s) * 1.8, 0, 1)
    local a = 0.18 + (s * 0.45)
    return r, g, b, a
end

local function pruneRecentPings(list, now)
    for i = #list, 1, -1 do
        local p = list[i]
        if not p or (now - (p.ts or 0)) > 20 then
            tremove(list, i)
        end
    end
end

local function ensureDot(pool, parent)
    local dot = tremove(pool)
    if dot and dot.SetParent then
        dot:SetParent(parent)
        return dot
    end
    dot = parent:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    return dot
end

local function paintDot(dot, r, g, b, a)
    if dot.SetColorTexture then
        dot:SetColorTexture(r, g, b, a)
        return
    end
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    if dot.SetVertexColor then
        dot:SetVertexColor(r, g, b, a or 1)
    end
    if dot.SetAlpha then
        dot:SetAlpha(a or 1)
    end
end

local function recycleDots(active, pool)
    for i = 1, #active do
        local d = active[i]
        if d and d.Hide then
            d:Hide()
            pool[#pool + 1] = d
        end
    end
    wipe(active)
end

function MetaMap:_renderWorldMap(cells)
    if not WorldMapFrame then
        return
    end
    local parent = (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)
        or WorldMapDetailFrame
        or WorldMapButton
    if not parent then
        return
    end
    recycleDots(self._worldActiveDots or {}, self._worldDots)
    self._worldActiveDots = self._worldActiveDots or {}

    for _, c in ipairs(cells) do
        local dot = ensureDot(self._worldDots, parent)
        dot:SetSize(14, 14)
        dot:SetPoint("CENTER", parent, "TOPLEFT", c.x * parent:GetWidth(), -c.y * parent:GetHeight())
        paintDot(dot, c.r, c.g, c.b, c.a)
        dot:Show()
        self._worldActiveDots[#self._worldActiveDots + 1] = dot
    end
end

function MetaMap:_renderMinimap(cells, playerX, playerY)
    if not Minimap then return end
    if not playerX or not playerY then return end
    recycleDots(self._miniActiveDots or {}, self._miniDots)
    self._miniActiveDots = self._miniActiveDots or {}

    for _, c in ipairs(cells) do
        local dxCells = (c.x - playerX) / CELL_SIZE
        local dyCells = (playerY - c.y) / CELL_SIZE
        local dx = dxCells * MINIMAP_PIXELS_PER_CELL
        local dy = dyCells * MINIMAP_PIXELS_PER_CELL
        if (dx * dx + dy * dy) <= (80 * 80) then
            local dot = ensureDot(self._miniDots, Minimap)
            dot:SetSize(9, 9)
            dot:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
            paintDot(dot, c.r, c.g, c.b, c.a)
            dot:Show()
            self._miniActiveDots[#self._miniActiveDots + 1] = dot
        end
    end
end

function MetaMap:Refresh(force)
    local s = self:_getSettings()
    if not s.metaMapEnabled then
        recycleDots(self._worldActiveDots or {}, self._worldDots)
        recycleDots(self._miniActiveDots or {}, self._miniDots)
        return
    end

    local now = GetTime()
    if not force and (now - (self._lastRender or 0)) < RENDER_INTERVAL then
        return
    end

    local mapID, playerX, playerY = getPlayerMapPosition()
    if not mapID then return end

    local windowSec = WINDOW_SECONDS[s.metaMapWindow] or WINDOW_SECONDS.medium
    local context = getMapContextKey(mapID)
    local rawCells = UGC.DB:GetCommunityHeatCells(context)
    local prepared = {}
    local nowServer = UGC.Compat:GetServerTime()
    pruneRecentPings(self._recentPings, nowServer)

    for _, cell in ipairs(rawCells) do
        if s.metaMapCategory == "all" or cell.category == s.metaMapCategory then
            local score = self:GetCellScore(cell, windowSec)
            if score > 0.05 then
                local r, g, b, a = colorFromScore(score)
                prepared[#prepared + 1] = {
                    x = (cell.cx + 0.5) * CELL_SIZE,
                    y = (cell.cy + 0.5) * CELL_SIZE,
                    r = r, g = g, b = b, a = a,
                }
            end
        end
    end

    for _, ping in ipairs(self._recentPings) do
        if ping.context == context then
            prepared[#prepared + 1] = {
                x = ping.x,
                y = ping.y,
                r = 1.0, g = 0.95, b = 0.2, a = 0.95,
            }
        end
    end

    if s.metaMapOnWorldMap then
        self:_renderWorldMap(prepared)
    else
        recycleDots(self._worldActiveDots or {}, self._worldDots)
    end

    if s.metaMapOnMinimap then
        self:_renderMinimap(prepared, playerX, playerY)
    else
        recycleDots(self._miniActiveDots or {}, self._miniDots)
    end

    UGC.DB:PruneCommunityHeatCells(RETAIN_SECONDS)
    self._lastRender = now
end

function MetaMap:ToggleEnabled()
    local s = self:_getSettings()
    s.metaMapEnabled = not s.metaMapEnabled
    self:Refresh(true)
end

function MetaMap:Init()
    self:_getSettings()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(5, function()
            MetaMap:FlushNetwork(false)
            MetaMap:Refresh(false)
        end)
    else
        local ticker = CreateFrame("Frame")
        local elapsed = 0
        ticker:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + (dt or 0)
            if elapsed >= 5 then
                elapsed = 0
                MetaMap:FlushNetwork(false)
                MetaMap:Refresh(false)
            end
        end)
    end
end
