-------------------------------------------------------------------------------
-- Details.lua
-- Advanced statistics window with time-period tabs, category filters,
-- sortable columns, and a session summary bar.
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Details = {}
local Details = UGC.Details

local WINDOW_WIDTH  = 530
local WINDOW_HEIGHT = 480
local ROW_HEIGHT    = 22
local STAR_BRONZE   = "Interface\\AddOns\\UltimateGatheringCounter\\media\\star"
local STAR_SILVER   = "Interface\\AddOns\\UltimateGatheringCounter\\media\\star_silver"
local STAR_GOLD     = "Interface\\AddOns\\UltimateGatheringCounter\\media\\star_gold"
local STAR_FALLBACK = "Interface\\Common\\ReputationStar"

-- Quality star texture (same as overlay)
local QUALITY_COLORS = {
    [1] = { 0.80, 0.54, 0.20 },
    [2] = { 0.75, 0.75, 0.75 },
    [3] = { 1.00, 0.85, 0.00 },
}

-- Tab definitions
local TABS = {
    { key = "allTime",  label = "All Time"  },
    { key = "weekly",   label = "This Week" },
    { key = "daily",    label = "Today"     },
    { key = "lastHour", label = "Last Hour" },
    { key = "leaderboard", label = "Leaderboard" },
}

local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local PROF_ORDER = { "herbs", "ore", "fish", "leather" }

local function CreateProgressRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.label:SetWidth(138)
    row.label:SetJustifyH("LEFT")

    row.barBg = row:CreateTexture(nil, "BORDER")
    row.barBg:SetPoint("LEFT", row, "LEFT", 144, 0)
    row.barBg:SetHeight(11)
    row.barBg:SetColorTexture(0, 0, 0, 0.6)

    row.barFill = row:CreateTexture(nil, "ARTWORK")
    row.barFill:SetPoint("LEFT", row.barBg, "LEFT", 0, 0)
    row.barFill:SetHeight(11)

    row.barText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.barText:SetPoint("CENTER", row.barBg, "CENTER", 0, 0)
    row.barText:SetTextColor(0.92, 0.92, 0.92)

    row.gainText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.gainText:SetPoint("LEFT", row.barBg, "RIGHT", 6, 0)
    row.gainText:SetTextColor(0.2, 1.0, 0.2)
    row.gainText:SetText("")

    return row
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function GetCountForPeriod(period, itemID)
    if period == "allTime"  then return UGC.DB:GetAllTime(itemID)  end
    if period == "weekly"   then return UGC.DB:GetWeekly(itemID)   end
    if period == "daily"    then return UGC.DB:GetDaily(itemID)    end
    if period == "lastHour" then return UGC.DB:GetLastHour(itemID) end
    return 0
end

local function FormatCoin(copper)
    if not copper or copper <= 0 then return "|cff555555—|r" end
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop    = copper % 100
    if gold > 0 then
        return string.format("|cffffd700%dg|r %ds %dc", gold, silver, cop)
    elseif silver > 0 then
        return string.format("|cffc7c7cf%ds|r %dc", silver, cop)
    else
        return string.format("|cffeda55f%dc|r", cop)
    end
end

local function GetAuctionPrice(itemID)
    if not UGC.Compat:IsAddOnLoaded("Auctionator") then return nil end
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return nil
    end
    local ok, price = pcall(
        Auctionator.API.v1.GetAuctionPriceByItemID,
        UGC.ADDON_NAME, itemID
    )
    return ok and price or nil
end


local function SetDefaultIcon(texture)
    texture:SetTexture(ICON_UNKNOWN)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local function SetClassIcon(texture, classToken)
    local coords = classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
    if coords then
        texture:SetTexture(CLASS_ICON_TEXTURE)
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return
    end
    SetDefaultIcon(texture)
end

local function PrintLeaderboardChannelStatus(msg)
    print(string.format("|cff33E633UGC:|r %s", msg))
end

-------------------------------------------------------------------------------
-- Row factory
-------------------------------------------------------------------------------
function Details:_CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
    SetDefaultIcon(row.icon)

    -- Quality stars with a Retail mask path and a Classic-safe texture fallback.
    row.qualityStars = {}
    for i = 1, 3 do
        row.qualityStars[i] = UGC.Compat:CreateStarTexture(
            row,
            "BOTTOMLEFT",
            row.icon,
            (i - 1) * 7
        )

        local ok = row.qualityStars[i]:SetTexture("Interface\\AddOns\\UltimateGatheringCounter\\media\\star")
        if ok == false then
            row.qualityStars[i]:SetTexture("Interface\\Common\\ReputationStar")
        end
    end

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.nameText:SetWidth(160)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.countText:SetPoint("LEFT", row, "LEFT", 210, 0)
    row.countText:SetWidth(80)
    row.countText:SetJustifyH("RIGHT")

    row.valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.valueText:SetPoint("LEFT", row, "LEFT", 300, 0)
    row.valueText:SetWidth(120)
    row.valueText:SetJustifyH("RIGHT")

    row.pctText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.pctText:SetPoint("LEFT", row, "LEFT", 428, 0)
    row.pctText:SetWidth(80)
    row.pctText:SetJustifyH("RIGHT")
    row.pctText:SetTextColor(0.55, 0.55, 0.55)
    row.pctText:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            GameTooltip:Show()
            self.bg:SetColorTexture(1, 1, 1, 0.08)
            return
        end

        if self.leaderboardData then
            local d = self.leaderboardData
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(string.format("#%d %s", d.rank or 0, d.name or "Unknown"), 0.2, 1.0, 0.2)
            GameTooltip:AddLine(string.format("Number of Gathers: %d", d.total or 0), 1, 1, 1)
            GameTooltip:AddLine(string.format("Herbs: %d  Ore: %d  Fish: %d  Leather: %d",
                d.herbs or 0, d.ore or 0, d.fish or 0, d.leather or 0), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(string.format("Levels (sum): %s", d.levelSummary or "L0"), 0.8, 0.8, 1)
            if d.bestCreature and (d.bestCreature.level or 0) > 0 then
                GameTooltip:AddLine(string.format("Best creature: %s Lv.%d (%s)",
                    d.bestCreature.name or "Companion",
                    d.bestCreature.level or 0,
                    d.bestCreature.category or "?"), 0.6, 1, 0.6)
            end
            GameTooltip:AddLine("Titles:", 1, 0.82, 0.2)
            GameTooltip:AddLine(d.titles or "-", 0.92, 0.92, 0.92, true)
            GameTooltip:Show()
            self.bg:SetColorTexture(1, 1, 1, 0.08)
        end
    end)
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.bg:SetColorTexture(1, 1, 1, 0)
    end)

    return row
end

-------------------------------------------------------------------------------
-- Tab button helper
-------------------------------------------------------------------------------
function Details:_CreateTabButton(parent, label, index, total)
    local btn = CreateFrame("Button", nil, parent)
    local btnW = math.floor((WINDOW_WIDTH - 20) / total) - 3
    btn:SetSize(btnW, 22)
    if index == 1 then
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -2)
    else
        btn:SetPoint("LEFT", self._tabBtns[index - 1], "RIGHT", 3, 0)
    end

    -- Background
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.15, 0.15, 0.15, 1)

    btn.border = btn:CreateTexture(nil, "ARTWORK")
    btn.border:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, -1)
    btn.border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, -1)
    btn.border:SetHeight(1)
    btn.border:SetColorTexture(0.35, 0.35, 0.35, 1)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetAllPoints()
    btn.text:SetJustifyH("CENTER")
    btn.text:SetJustifyV("MIDDLE")
    btn.text:SetText(label)

    btn:SetScript("OnEnter", function(self)
        if self ~= Details._activeTab then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self ~= Details._activeTab then
            self.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        end
    end)

    return btn
end

function Details:_SetActiveTab(tabKey, btn)
    self._currentTab = tabKey
    for _, b in ipairs(self._tabBtns) do
        b.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        b.text:SetTextColor(0.75, 0.75, 0.75)
        b.border:SetColorTexture(0.35, 0.35, 0.35, 1)
    end
    btn.bg:SetColorTexture(0.08, 0.08, 0.08, 1)
    btn.text:SetTextColor(1, 1, 1)
    btn.border:SetColorTexture(0.33, 0.88, 0.33, 1)  -- green underline for active
    self._activeTab = btn
end

-------------------------------------------------------------------------------
-- Filter button helper
-------------------------------------------------------------------------------
function Details:_SetActiveFilter(key)
    self._currentFilter = key
    local CATS_ORDER = { "global", "all", "herbs", "ore", "fish", "leather" }
    for _, k in ipairs(CATS_ORDER) do
        local btn = self._filterBtns[k]
        if btn then
            if k == key then
                btn.bg:SetColorTexture(0.25, 0.55, 0.25, 0.9)
                btn.text:SetTextColor(1, 1, 1)
            else
                btn.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
                btn.text:SetTextColor(0.65, 0.65, 0.65)
            end
        end
    end
end

local function MakeFilterBtn(parent, label, xOff, yOff, width, catColor)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, 20)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.15, 0.15, 0.15, 1)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetAllPoints()
    btn.text:SetJustifyH("CENTER")
    btn.text:SetJustifyV("MIDDLE")
    btn.text:SetText(label)
    if catColor then
        btn.text:SetTextColor(catColor.r, catColor.g, catColor.b)
    else
        btn.text:SetTextColor(0.65, 0.65, 0.65)
    end

    return btn
end

-------------------------------------------------------------------------------
-- Sort state
-------------------------------------------------------------------------------
local SORT_COLUMN  = "count"  -- "count", "value", "name", "pct"
local SORT_REVERSE = false

local function SortData(data, col, rev)
    local fn
    if col == "value" then
        fn = function(a, b)
            if rev then return a.copper < b.copper end
            return a.copper > b.copper
        end
    elseif col == "name" then
        fn = function(a, b)
            if rev then return a.name > b.name end
            return a.name < b.name
        end
    else  -- default: count
        fn = function(a, b)
            if rev then return a.count < b.count end
            return a.count > b.count
        end
    end
    table.sort(data, fn)
end

local function MakeSortHeader(parent, label, xOff, width, colKey, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, 14)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, 0)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH("RIGHT")
    fs:SetJustifyV("MIDDLE")
    fs:SetTextColor(0.55, 0.55, 0.55)
    fs:SetText(label)
    btn._label = fs

    btn:SetScript("OnClick", function()
        if SORT_COLUMN == colKey then
            SORT_REVERSE = not SORT_REVERSE
        else
            SORT_COLUMN  = colKey
            SORT_REVERSE = false
        end
        onClick()
    end)
    btn:SetScript("OnEnter", function(self)
        fs:SetTextColor(0.9, 0.9, 0.9)
    end)
    btn:SetScript("OnLeave", function(self)
        fs:SetTextColor(0.55, 0.55, 0.55)
    end)
    return btn
end

-------------------------------------------------------------------------------
-- Init — called on PLAYER_LOGIN
-------------------------------------------------------------------------------
function Details:Init()
    local settings = UGC.DB:GetSettings()
    local f = UGC.Compat:CreateBackdropFrame("Frame", "UGC_Details", UIParent)
    f:SetSize(settings.detailsWidth or WINDOW_WIDTH, settings.detailsHeight or WINDOW_HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(20)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "UGC_Details")

    -- Resize handle
    f:SetResizable(true)
    UGC.Compat:SetResizeBounds(f, 400, 280)
    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local s = UGC.DB:GetSettings()
        s.detailsWidth  = math.floor(f:GetWidth())
        s.detailsHeight = math.floor(f:GetHeight())
    end)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("|cff33E633UGC|r  —  Detailed Statistics")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -10)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetScript("OnClick", function() Details:Hide() end)

    -- ── Tabs ──────────────────────────────────────────────────────────
    self._tabBtns    = {}
    self._currentTab = "allTime"

    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT",  f, "TOPLEFT",   6, -26)
    tabBar:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -6, -26)
    tabBar:SetHeight(24)

    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints()
    tabBarBg:SetColorTexture(0.1, 0.1, 0.1, 1)

    for i, tab in ipairs(TABS) do
        local btn = self:_CreateTabButton(tabBar, tab.label, i, #TABS)
        local tabKey = tab.key
        btn:SetScript("OnClick", function()
            Details:_SetActiveTab(tabKey, btn)
            Details:Refresh()
        end)
        self._tabBtns[i] = btn
    end
    self:_SetActiveTab("allTime", self._tabBtns[1])

    -- ── Category filter row ───────────────────────────────────────────
    local filterRow = CreateFrame("Frame", nil, f)
    filterRow:SetPoint("TOPLEFT",  f, "TOPLEFT",   6, -52)
    filterRow:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -6, -52)
    filterRow:SetHeight(24)

    local filterBg = filterRow:CreateTexture(nil, "BACKGROUND")
    filterBg:SetAllPoints()
    filterBg:SetColorTexture(0.06, 0.06, 0.06, 1)

    local filterLbl = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLbl:SetPoint("LEFT", filterRow, "LEFT", 6, 0)
    filterLbl:SetText("Filter:")
    filterLbl:SetTextColor(0.5, 0.5, 0.5)

    local FILTER_DEFS = {
        { key = "global",  label = "Global",  color = nil,                          xOff = 48,  w = 52 },
        { key = "all",     label = "All",     color = nil,                          xOff = 104, w = 40 },
        { key = "herbs",   label = "Herbs",   color = UGC.CATEGORIES.herbs.color,   xOff = 148, w = 50 },
        { key = "ore",     label = "Ore",     color = UGC.CATEGORIES.ore.color,     xOff = 202, w = 40 },
        { key = "fish",    label = "Fish",    color = UGC.CATEGORIES.fish.color,    xOff = 246, w = 40 },
        { key = "leather", label = "Leather", color = UGC.CATEGORIES.leather.color, xOff = 290, w = 55 },
    }
    self._filterBtns   = {}
    self._currentFilter = "global"

    for _, fd in ipairs(FILTER_DEFS) do
        local btn = MakeFilterBtn(filterRow, fd.label, fd.xOff, -2, fd.w, fd.color)
        local fKey = fd.key
        btn:SetScript("OnClick", function()
            Details:_SetActiveFilter(fKey)
            Details:Refresh()
        end)
        self._filterBtns[fd.key] = btn
    end
    self:_SetActiveFilter("global")

    -- ── Column headers ────────────────────────────────────────────────
    local profPanel = CreateFrame("Frame", nil, f)
    profPanel:SetPoint("TOPLEFT",  f, "TOPLEFT",  6, -78)
    profPanel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -78)
    profPanel:SetHeight(84)

    local profBg = profPanel:CreateTexture(nil, "BACKGROUND")
    profBg:SetAllPoints()
    profBg:SetColorTexture(0.04, 0.04, 0.04, 0.95)

    self._professionRows = {}
    for i, cat in ipairs(PROF_ORDER) do
        local row = CreateProgressRow(profPanel)
        row:SetPoint("TOPLEFT", profPanel, "TOPLEFT", 4, -((i - 1) * 20 + 2))
        row:SetPoint("TOPRIGHT", profPanel, "TOPRIGHT", -6, -((i - 1) * 20 + 2))
        self._professionRows[cat] = row
    end

    local colHdr = CreateFrame("Frame", nil, f)
    colHdr:SetPoint("TOPLEFT",  f, "TOPLEFT",   6, -164)
    colHdr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -164)
    colHdr:SetHeight(16)

    local colHdrBg = colHdr:CreateTexture(nil, "BACKGROUND")
    colHdrBg:SetAllPoints()
    colHdrBg:SetColorTexture(0.0, 0.0, 0.0, 0.5)

    -- Static "Item" label
    local itemColLbl = colHdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemColLbl:SetPoint("LEFT", colHdr, "LEFT", 26, 0)
    itemColLbl:SetWidth(160)
    itemColLbl:SetJustifyH("LEFT")
    itemColLbl:SetTextColor(0.55, 0.55, 0.55)
    itemColLbl:SetText("Item")
    self._itemColLabel = itemColLbl

    -- Sortable headers
    self._countHeader = MakeSortHeader(colHdr, "Count",   208,  80, "count",  function() Details:Refresh() end)
    self._valueHeader = MakeSortHeader(colHdr, "Value",   298, 120, "value",  function() Details:Refresh() end)
    self._pctHeader   = MakeSortHeader(colHdr, "% Total", 426,  80, "pct",    function() Details:Refresh() end)

    -- Divider
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT",  f, "TOPLEFT",   8, -181)
    div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -181)
    div:SetHeight(1)
    div:SetColorTexture(0.35, 0.35, 0.35, 0.6)

    -- ── Scroll frame ──────────────────────────────────────────────────
    local scrollFrame = CreateFrame("ScrollFrame", "UGC_DetailsScroll", f,
                                    "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",    6, -184)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 96)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(WINDOW_WIDTH - 34)
    content:SetHeight(20)
    scrollFrame:SetScrollChild(content)

    -- ── Summary bar (2 lines) ─────────────────────────────────────────
    local summaryBar = CreateFrame("Frame", nil, f)
    summaryBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   6, 40)
    summaryBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  -6, 40)
    summaryBar:SetHeight(52)

    local sumBg = summaryBar:CreateTexture(nil, "BACKGROUND")
    sumBg:SetAllPoints()
    sumBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    self._summaryLine1 = summaryBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self._summaryLine1:SetPoint("TOPLEFT",  summaryBar, "TOPLEFT",  8, -6)
    self._summaryLine1:SetPoint("TOPRIGHT", summaryBar, "TOPRIGHT", -8, -6)
    self._summaryLine1:SetJustifyH("LEFT")
    self._summaryLine1:SetTextColor(0.85, 0.85, 0.85)

    self._summaryLine2 = summaryBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self._summaryLine2:SetPoint("BOTTOMLEFT",  summaryBar, "BOTTOMLEFT",  8, 6)
    self._summaryLine2:SetPoint("BOTTOMRIGHT", summaryBar, "BOTTOMRIGHT", -8, 6)
    self._summaryLine2:SetJustifyH("LEFT")
    self._summaryLine2:SetTextColor(0.75, 0.75, 0.75)

    -- ── Bottom buttons ────────────────────────────────────────────────
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 24)
    resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 10)
    resetBtn:SetText("Reset Session")
    resetBtn:SetScript("OnClick", function()
        UGC.Tracker:ResetSession()
        if UGC.Overlay then UGC.Overlay:Refresh() end
        Details:Refresh()
        print("|cff33E633UGC:|r Session data reset.")
    end)

    local closeBtn2 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn2:SetSize(130, 24)
    closeBtn2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 10)
    closeBtn2:SetText("Close")
    closeBtn2:SetScript("OnClick", function() Details:Hide() end)

    local leaderboardChannelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    leaderboardChannelBtn:SetSize(170, 24)
    leaderboardChannelBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    leaderboardChannelBtn:SetText("Join Leaderboard")
    leaderboardChannelBtn:SetScript("OnClick", function()
        if not UGC.Community then
            return
        end
        if UGC.Community:IsJoined() then
            local didLeave = UGC.Community:LeaveLeaderboardChannel()
            if didLeave then
                leaderboardChannelBtn:SetText("Join Leaderboard")
                PrintLeaderboardChannelStatus("You left the leaderboard channel.")
            else
                PrintLeaderboardChannelStatus("Unable to leave the leaderboard channel.")
            end
        else
            local didJoin = UGC.Community:JoinLeaderboardChannel()
            if didJoin then
                leaderboardChannelBtn:SetText("Leave Leaderboard")
                PrintLeaderboardChannelStatus("You joined the leaderboard channel.")
            else
                PrintLeaderboardChannelStatus("Unable to join the leaderboard channel.")
            end
        end
        C_Timer.After(0.2, function()
            if Details and Details.frame and Details.frame:IsShown() then
                Details:Refresh()
            end
        end)
    end)
    leaderboardChannelBtn:Hide()

    -- ── Store refs ────────────────────────────────────────────────────
    self.frame   = f
    self.content = content
    self.rows    = {}
    self._profPanel = profPanel
    self._detailsColHdr = colHdr
    self._detailsDivider = div
    self._detailsScrollFrame = scrollFrame
    self._leaderboardChannelBtn = leaderboardChannelBtn

    f:Hide()
end

-------------------------------------------------------------------------------
-- Show / Hide / Toggle
-------------------------------------------------------------------------------
function Details:Show()
    if self.frame then
        self.frame:Show()
        self:Refresh()
    end
end

function Details:Hide()
    if self.frame then self.frame:Hide() end
end

function Details:Toggle()
    if self.frame then
        if self.frame:IsShown() then
            self:Hide()
        else
            self:Show()
        end
    end
end



function Details:_ApplyRowLayout(mode)
    local isLeaderboard = (mode == "leaderboard")
    local contentWidth = (self.content and self.content:GetWidth()) or (WINDOW_WIDTH - 34)
    local settings = UGC.DB:GetSettings()
    local headerY = (settings and settings.professionOnlyMode) and -78 or -164

    local nameWidth = isLeaderboard and 130 or 160
    local countX = isLeaderboard and 170 or 210
    local countW = isLeaderboard and 120 or 80
    local valueX = countX + countW + 8
    local valueW = isLeaderboard and 70 or 120
    local pctX = valueX + valueW + 8
    local pctW = math.max(isLeaderboard and 240 or 80, contentWidth - pctX - 8)

    if self._itemColLabel then
        self._itemColLabel:SetWidth(nameWidth)
        self._itemColLabel:ClearAllPoints()
        self._itemColLabel:SetPoint("LEFT", self.frame, "TOPLEFT", 32, headerY)
        self._itemColLabel:SetPoint("TOP", self.frame, "TOP", 0, headerY)
        if isLeaderboard then
            self._itemColLabel:SetText("Player")
        else
            self._itemColLabel:SetText("Item")
        end
    end

    if self._countHeader then
        self._countHeader:SetWidth(countW)
        self._countHeader:ClearAllPoints()
        self._countHeader:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 6 + countX, headerY)
    end
    if self._valueHeader then
        self._valueHeader:SetWidth(valueW)
        self._valueHeader:ClearAllPoints()
        self._valueHeader:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 6 + valueX, headerY)
    end
    if self._pctHeader then
        self._pctHeader:SetWidth(pctW)
        self._pctHeader:ClearAllPoints()
        self._pctHeader:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 6 + pctX, headerY)
    end

    for _, row in ipairs(self.rows or {}) do
        row.nameText:SetWidth(nameWidth)

        row.countText:ClearAllPoints()
        row.countText:SetPoint("LEFT", row, "LEFT", countX, 0)
        row.countText:SetWidth(countW)

        row.valueText:ClearAllPoints()
        row.valueText:SetPoint("LEFT", row, "LEFT", valueX, 0)
        row.valueText:SetWidth(valueW)

        row.pctText:ClearAllPoints()
        row.pctText:SetPoint("LEFT", row, "LEFT", pctX, 0)
        row.pctText:SetWidth(pctW)
    end
end

function Details:_SetLeaderboardVisualState(isJoined)
    if self.content then
        self.content:SetAlpha(isJoined and 1 or 0.45)
    end

    local headerR, headerG, headerB = 1, 1, 1
    if not isJoined then
        headerR, headerG, headerB = 0.6, 0.6, 0.6
    end

    if self._itemColLabel then
        self._itemColLabel:SetTextColor(headerR, headerG, headerB)
    end
    if self._countHeader and self._countHeader._label then
        self._countHeader._label:SetTextColor(headerR, headerG, headerB)
    end
    if self._valueHeader and self._valueHeader._label then
        self._valueHeader._label:SetTextColor(headerR, headerG, headerB)
    end
    if self._pctHeader and self._pctHeader._label then
        self._pctHeader._label:SetTextColor(headerR, headerG, headerB)
    end
end

function Details:_RefreshLeaderboard()
    local peers = UGC.DB:GetCommunityPeers() or {}
    local isJoined = UGC.Community and UGC.Community.IsJoined and UGC.Community:IsJoined()
    local activeFilter = self._currentFilter or "global"
    local localName = (UGC.Community and UGC.Community._normalizePlayerName and UGC.Community:_normalizePlayerName(UGC.Community:_getPlayerName()))
        or (UGC.Community and UGC.Community:_getPlayerName())
        or UnitName("player")
        or "You"
    local rows = {}

    for name, peer in pairs(peers) do
        local t = peer.totals or {}
        local levels = peer.levels or {}
        local levelSum = 0
        local titleParts = {}
        for _, cat in ipairs(PROF_ORDER) do
            local lvl = tonumber(levels[cat] and levels[cat].level) or 1
            levelSum = levelSum + lvl
            local title = tostring(levels[cat] and levels[cat].title or "Novice")
            local c = UGC.CATEGORIES[cat]
            table.insert(titleParts, string.format("|cff%s%s|r:%s", c.hex, c.label:sub(1,1), title))
        end
        local total = (t.herbs or 0) + (t.ore or 0) + (t.fish or 0) + (t.leather or 0)
        local filteredTotal = total
        if activeFilter == "global" then
            filteredTotal = levelSum
        elseif activeFilter ~= "all" then
            filteredTotal = tonumber(t[activeFilter]) or 0
        end

        table.insert(rows, {
            name = name,
            total = filteredTotal,
            totalAll = total,
            levelTotal = levelSum,
            totals = t,
            levelSummary = string.format("L%d", levelSum),
            titles = table.concat(titleParts, " | "),
            updatedAt = tonumber(peer.updatedAt) or 0,
            classToken = peer.classToken,
            bestCreature = peer.bestCreature,
        })
    end

    table.sort(rows, function(a, b)
        if a.name == localName and b.name ~= localName then
            return true
        end
        if b.name == localName and a.name ~= localName then
            return false
        end
        if a.levelTotal == b.levelTotal then
            if a.total == b.total then
                return a.name < b.name
            end
            return a.total > b.total
        end
        return a.levelTotal > b.levelTotal
    end)

    for _, row in ipairs(self.rows) do row:Hide() end

    local yOffset = 0
    local grandTotal = 0
    local playerRank = nil

    for i, entry in ipairs(rows) do
        grandTotal = grandTotal + (entry.total or 0)
        if entry.name == localName then
            playerRank = i
        end

        local row = self.rows[i]
        if not row then
            row = self:_CreateRow(self.content)
            self.rows[i] = row
        end

        row.itemID = nil
        row.leaderboardData = nil
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -yOffset)
        row:SetWidth(self.content:GetWidth())

        if entry.name == localName then
            row.bg:SetColorTexture(0.2, 0.45, 0.12, 0.35)
        elseif i % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.03)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        SetClassIcon(row.icon, entry.classToken)
        for k = 1, 3 do row.qualityStars[k]:Hide() end

        local t = entry.totals
        local playerNameColor = (entry.name == localName) and "ff66ff66" or "ff33E633"
        row.nameText:SetText(string.format("#%d |c%s%s|r  |cff888888(H:%d O:%d F:%d L:%d)|r",
            i, playerNameColor, entry.name, t.herbs or 0, t.ore or 0, t.fish or 0, t.leather or 0))
        row.countText:SetText(tostring(entry.total))
        row.valueText:SetText(entry.levelSummary)
        row.pctText:SetText(entry.titles)
        row.pctText:SetJustifyH("LEFT")
        row.leaderboardData = {
            rank = i,
            name = entry.name,
            total = entry.total,
            totalAll = entry.totalAll,
            herbs = t.herbs or 0,
            ore = t.ore or 0,
            fish = t.fish or 0,
            leather = t.leather or 0,
            levelSummary = entry.levelSummary,
            titles = entry.titles,
            bestCreature = entry.bestCreature,
        }

        row:Show()
        yOffset = yOffset + ROW_HEIGHT + 1
    end

    if #rows == 0 then
        if not self._emptyText then
            self._emptyText = self.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            self._emptyText:SetPoint("TOP", self.content, "TOP", 0, -20)
            self._emptyText:SetJustifyH("CENTER")
            self._emptyText:SetWidth(self.content:GetWidth())
        end
        if isJoined then
            self._emptyText:SetText("No community data received on the UGC channel yet.")
        else
            self._emptyText:SetText("You are not connected to the UGC leaderboard channel.")
        end
        self._emptyText:Show()
        yOffset = 50
    elseif self._emptyText then
        self._emptyText:Hide()
    end

    self.content:SetHeight(math.max(yOffset, 20))

    if self._countHeader and self._countHeader._label then
        if activeFilter == "global" then
            self._countHeader._label:SetText("Global Score")
        else
            self._countHeader._label:SetText("Number of Gathers")
        end
    end
    if self._valueHeader and self._valueHeader._label then self._valueHeader._label:SetText("Levels") end
    if self._pctHeader and self._pctHeader._label then self._pctHeader._label:SetText("Titles") end

    local rankText = playerRank and ("#" .. playerRank) or "N/A"
    local filterLabel = "Global (Level Sum)"
    if activeFilter == "all" then
        filterLabel = "All"
    elseif UGC.CATEGORIES and UGC.CATEGORIES[activeFilter] then
        filterLabel = UGC.CATEGORIES[activeFilter].label
    end
    self._summaryLine1:SetText(string.format(
        "Channel |cff33E633UGC|r  |  Players: %d  |  Shared gathers (%s): %d",
        #rows, filterLabel, grandTotal))
    if isJoined then
        self._summaryLine2:SetText(string.format(
            "Your rank: |cffffd700%s|r  |  Tip: ask more players to join the UGC channel.",
            rankText))
    else
        self._summaryLine2:SetText("Join the UGC leaderboard channel to sync community data.")
    end

    if self._leaderboardChannelBtn then
        if isJoined then
            self._leaderboardChannelBtn:SetText("Leave Leaderboard")
        else
            self._leaderboardChannelBtn:SetText("Join Leaderboard")
        end
    end

    self:_SetLeaderboardVisualState(isJoined)
end

-------------------------------------------------------------------------------
-- Refresh — rebuilds table from current data/filter/tab
-------------------------------------------------------------------------------
function Details:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    local settings  = UGC.DB:GetSettings()
    local professionOnly = settings.professionOnlyMode == true

    if self._profPanel and self._detailsColHdr and self._detailsDivider and self._detailsScrollFrame then
        if professionOnly then
            self._profPanel:Hide()
            self._detailsColHdr:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",   6, -78)
            self._detailsColHdr:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -22, -78)
            self._detailsDivider:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",   8, -95)
            self._detailsDivider:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -22, -95)
            self._detailsScrollFrame:SetPoint("TOPLEFT",     self.frame, "TOPLEFT",    6, -98)
            self._detailsScrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -22, 96)
        else
            self._profPanel:Show()
            self._detailsColHdr:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",   6, -164)
            self._detailsColHdr:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -22, -164)
            self._detailsDivider:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",   8, -181)
            self._detailsDivider:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -22, -181)
            self._detailsScrollFrame:SetPoint("TOPLEFT",     self.frame, "TOPLEFT",    6, -184)
            self._detailsScrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -22, 96)
        end
    end

    if self._professionRows and UGC.Progression and not professionOnly then
        for _, cat in ipairs(PROF_ORDER) do
            local row = self._professionRows[cat]
            local catData = UGC.CATEGORIES[cat]
            local prog = UGC.Progression:GetProgress(cat)
            local pct = (prog.reqXP > 0) and math.min(1, prog.xp / prog.reqXP) or 0

            row.label:SetText(string.format("|cff%s%s|r |cff33ff33Lv.%d|r |cff9f9f9f(Best %d)|r • %s",
                catData.hex, catData.label, prog.level, prog.maxLevelReached or prog.level, prog.title))

            local rowWidth = row:GetWidth()
            local barWidth = math.max(80, rowWidth - 240)
            row.barBg:SetWidth(barWidth)
            row.barFill:SetWidth(math.max(1, barWidth * pct))
            row.barFill:SetColorTexture(catData.color.r, catData.color.g, catData.color.b, 0.95)
            row.barText:SetText(string.format("%d / %d EXP", prog.xp, prog.reqXP))

            local recentGain = UGC.Progression:GetRecentGain(cat)
            if recentGain then
                if (recentGain.bonus or 0) > 0 then
                    row.gainText:SetText(string.format("+%d EXP |cff4da6ff(+%d exp)|r", recentGain.amount or 0, recentGain.bonus or 0))
                else
                    row.gainText:SetText(string.format("+%d EXP", recentGain.amount or 0))
                end
            else
                row.gainText:SetText("")
            end
        end
    end

    -- Hide all pooled rows
    for _, row in ipairs(self.rows) do row:Hide() end

    local period    = self._currentTab    or "allTime"
    local catFilter = ((self._currentFilter ~= "all") and (self._currentFilter ~= "global")) and self._currentFilter or nil
    if self._countHeader and self._countHeader._label then self._countHeader._label:SetText("Count") end
    if self._valueHeader and self._valueHeader._label then self._valueHeader._label:SetText("Value") end
    if self._pctHeader and self._pctHeader._label then self._pctHeader._label:SetText("% Total") end

    if period == "leaderboard" then
        if self._leaderboardChannelBtn then
            self._leaderboardChannelBtn:Show()
        end
        self:_ApplyRowLayout("leaderboard")
        self:_RefreshLeaderboard()
        return
    end

    if self._leaderboardChannelBtn then
        self._leaderboardChannelBtn:Hide()
    end
    self:_SetLeaderboardVisualState(true)

    self:_ApplyRowLayout("items")

    -- Collect data
    local data        = {}
    local totalCount  = 0
    local totalCopper = 0

    for itemID, itemData in pairs(UGC.ITEM_DB) do
        if not (UGC.EXCLUDED_ITEM_IDS and UGC.EXCLUDED_ITEM_IDS[itemID]) then
        local cat = itemData.category
        if (not catFilter or cat == catFilter)
           and settings.showCategories[cat] then

            local count = GetCountForPeriod(period, itemID)
            if count > 0 then
                local cached  = UGC.DB:GetCachedItem(itemID)
                local name    = (cached and cached.name) or itemData.hint or ("Item " .. itemID)
                local icon    = cached and cached.icon
                local quality = cached and cached.quality
                local price   = GetAuctionPrice(itemID)
                local copper  = price and (price * count) or 0

                totalCount  = totalCount + count
                totalCopper = totalCopper + copper

                table.insert(data, {
                    itemID   = itemID,
                    name     = name,
                    icon     = icon,
                    quality  = quality,
                    category = cat,
                    count    = count,
                    copper   = copper,
                    hasPrice = (price ~= nil),
                })
            end
        end
        end
    end

    -- Sort
    SortData(data, SORT_COLUMN, SORT_REVERSE)

    -- Build rows
    local yOffset = 0
    for i, item in ipairs(data) do
        local row = self.rows[i]
        if not row then
            row = self:_CreateRow(self.content)
            self.rows[i] = row
        end

        row.itemID = item.itemID
        row.leaderboardData = nil
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -yOffset)
        row:SetWidth(self.content:GetWidth())

        -- Alternating bg
        if i % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.03)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        -- Icon
        if item.icon then
            row.icon:SetTexture(item.icon)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            SetDefaultIcon(row.icon)
        end

        -- Quality icons:
        -- 1 => bronze star, 2 => silver icon, 3 => gold icon.
        local q = item.quality
        for i = 1, 3 do
            row.qualityStars[i]:Hide()
        end

        if q == 1 then
            local col = QUALITY_COLORS[1]
            local ok = row.qualityStars[1]:SetTexture(STAR_BRONZE)
            if ok == false then
                row.qualityStars[1]:SetTexture(STAR_FALLBACK)
            end
            row.qualityStars[1]:SetVertexColor(col[1], col[2], col[3])
            row.qualityStars[1]:Show()
        elseif q == 2 then
            local ok = row.qualityStars[1]:SetTexture(STAR_SILVER)
            if ok == false then
                row.qualityStars[1]:SetTexture(STAR_FALLBACK)
            end
            row.qualityStars[1]:SetVertexColor(1, 1, 1)
            row.qualityStars[1]:Show()
        elseif q == 3 then
            local ok = row.qualityStars[1]:SetTexture(STAR_GOLD)
            if ok == false then
                row.qualityStars[1]:SetTexture(STAR_FALLBACK)
            end
            row.qualityStars[1]:SetVertexColor(1, 1, 1)
            row.qualityStars[1]:Show()
        end

        -- Name (color-coded by category)
        local catData = UGC.CATEGORIES[item.category]
        row.nameText:SetText(string.format("|cff%s%s|r", catData.hex, item.name))

        -- Count
        row.countText:SetText(tostring(item.count))

        -- Value
        if item.hasPrice then
            row.valueText:SetText(FormatCoin(item.copper))
        else
            row.valueText:SetText("|cffff8800Unknown value|r")
        end

        row.pctText:SetJustifyH("RIGHT")

        -- Percent of total
        if totalCount > 0 then
            row.pctText:SetText(string.format("%.1f%%", (item.count / totalCount) * 100))
        else
            row.pctText:SetText("")
        end

        row:Show()
        yOffset = yOffset + ROW_HEIGHT + 1
    end

    -- Empty state
    if #data == 0 then
        if not self._emptyText then
            self._emptyText = self.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            self._emptyText:SetPoint("TOP", self.content, "TOP", 0, -20)
            self._emptyText:SetText("No data for this period / filter.")
            self._emptyText:SetJustifyH("CENTER")
            self._emptyText:SetWidth(self.content:GetWidth())
        end
        self._emptyText:Show()
        yOffset = 50
    elseif self._emptyText then
        self._emptyText:Hide()
    end

    self.content:SetHeight(math.max(yOffset, 20))

    -- Summary bar
    local sessionDur = UGC.Tracker:GetSessionDuration()
    local durStr     = UGC.Tracker:FormatDuration(sessionDur)
    local rateStr    = ""
    if sessionDur > 60 then
        local itemsPerHour = (totalCount / sessionDur) * 3600
        rateStr = string.format("  |  |cffffd700%.0f items/h|r", itemsPerHour)
    end

    local periodLabel = "All Time"
    for _, t in ipairs(TABS) do
        if t.key == period then periodLabel = t.label break end
    end

    local topEarner = ""
    if #data > 0 then
        local best = data[1]  -- already sorted by count or value
        for _, d in ipairs(data) do
            if d.copper > best.copper then best = d end
        end
        if best.hasPrice and best.copper > 0 then
            topEarner = string.format("  |  Top earner: |cff33E633%s|r (%s)",
                                      best.name, FormatCoin(best.copper))
        end
    end

    self._summaryLine1:SetText(string.format(
        "Session: %s  |  Period: |cffffd700%s|r  |  Items: %d  |  Value: %s%s%s",
        durStr, periodLabel, totalCount,
        totalCopper > 0 and FormatCoin(totalCopper) or "|cff888888Unknown|r",
        rateStr, topEarner))

    -- Gather actions line
    local sc = UGC.Session.gatherCount
    local sessTotal = (sc.herbs or 0) + (sc.ore or 0) + (sc.fish or 0) + (sc.leather or 0)
    local cats = UGC.CATEGORIES

    -- Map period tab to gatherActions period (lastHour has no action bucket → use daily)
    local gaPeriod = (period == "lastHour") and "daily"
                  or (period == "weekly")   and "weekly"
                  or (period == "daily")    and "daily"
                  or "allTime"
    local ga = UGC.DB:GetGatherActions(gaPeriod)
    local gaPeriodLabel = (gaPeriod == "allTime") and "all time"
                       or (gaPeriod == "daily")   and "today"
                       or "this week"

    self._summaryLine2:SetText(string.format(
        "|cff888888Actions session:|r %d  "..
        "(|cff%s%dH|r  |cff%s%dO|r  |cff%s%dF|r  |cff%s%dL|r)"..
        "   |cff888888%s:|r %d  "..
        "(|cff%s%dH|r  |cff%s%dO|r  |cff%s%dF|r  |cff%s%dL|r)",
        sessTotal,
        cats.herbs.hex,   sc.herbs   or 0,
        cats.ore.hex,     sc.ore     or 0,
        cats.fish.hex,    sc.fish    or 0,
        cats.leather.hex, sc.leather or 0,
        gaPeriodLabel, ga.total,
        cats.herbs.hex,   ga.herbs,
        cats.ore.hex,     ga.ore,
        cats.fish.hex,    ga.fish,
        cats.leather.hex, ga.leather))
end
