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

-- Quality star texture (same as overlay)
local STAR_TEX = "Interface\\AddOns\\UltimateGatheringCounter\\media\\star.tga"
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
}

local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

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
    if not C_AddOns.IsAddOnLoaded("Auctionator") then return nil end
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return nil
    end
    local ok, price = pcall(
        Auctionator.API.v1.GetAuctionPriceByItemID,
        UGC.ADDON_NAME, itemID
    )
    return ok and price or nil
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
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Quality stars — star.tga en masque alpha sur quad blanc coloré via SetVertexColor
    row.qualityStars = {}
    for i = 1, 3 do
        local s = row:CreateTexture(nil, "OVERLAY")
        s:SetSize(6, 6)
        s:SetColorTexture(1, 1, 1, 1)
        s:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", (i - 1) * 7 - 1, -2)
        local mask = row:CreateMaskTexture()
        mask:SetTexture(STAR_TEX, "CLAMPTOBLACK", "CLAMPTOBLACK")
        mask:SetAllPoints(s)
        s:AddMaskTexture(mask)
        s:Hide()
        row.qualityStars[i] = s
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

    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
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
    local CATS_ORDER = { "all", "herbs", "ore", "fish", "leather" }
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
    local f = CreateFrame("Frame", "UGC_Details", UIParent, "BackdropTemplate")
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
    f:SetResizeBounds(400, 280)
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
        { key = "all",     label = "All",     color = nil,                    xOff = 48,  w = 40 },
        { key = "herbs",   label = "Herbs",   color = UGC.CATEGORIES.herbs.color,   xOff = 92,  w = 50 },
        { key = "ore",     label = "Ore",     color = UGC.CATEGORIES.ore.color,     xOff = 146, w = 40 },
        { key = "fish",    label = "Fish",    color = UGC.CATEGORIES.fish.color,    xOff = 190, w = 40 },
        { key = "leather", label = "Leather", color = UGC.CATEGORIES.leather.color, xOff = 234, w = 55 },
    }
    self._filterBtns   = {}
    self._currentFilter = "all"

    for _, fd in ipairs(FILTER_DEFS) do
        local btn = MakeFilterBtn(filterRow, fd.label, fd.xOff, -2, fd.w, fd.color)
        local fKey = fd.key
        btn:SetScript("OnClick", function()
            Details:_SetActiveFilter(fKey)
            Details:Refresh()
        end)
        self._filterBtns[fd.key] = btn
    end
    self:_SetActiveFilter("all")

    -- ── Column headers ────────────────────────────────────────────────
    local colHdr = CreateFrame("Frame", nil, f)
    colHdr:SetPoint("TOPLEFT",  f, "TOPLEFT",   6, -78)
    colHdr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -78)
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

    -- Sortable headers
    MakeSortHeader(colHdr, "Count",   208,  80, "count",  function() Details:Refresh() end)
    MakeSortHeader(colHdr, "Value",   298, 120, "value",  function() Details:Refresh() end)
    MakeSortHeader(colHdr, "% Total", 426,  80, "pct",    function() Details:Refresh() end)

    -- Divider
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT",  f, "TOPLEFT",   8, -95)
    div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -95)
    div:SetHeight(1)
    div:SetColorTexture(0.35, 0.35, 0.35, 0.6)

    -- ── Scroll frame ──────────────────────────────────────────────────
    local scrollFrame = CreateFrame("ScrollFrame", "UGC_DetailsScroll", f,
                                    "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",    6, -98)
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

    -- ── Store refs ────────────────────────────────────────────────────
    self.frame   = f
    self.content = content
    self.rows    = {}

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

-------------------------------------------------------------------------------
-- Refresh — rebuilds table from current data/filter/tab
-------------------------------------------------------------------------------
function Details:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    -- Hide all pooled rows
    for _, row in ipairs(self.rows) do row:Hide() end

    local period    = self._currentTab    or "allTime"
    local catFilter = (self._currentFilter ~= "all") and self._currentFilter or nil
    local settings  = UGC.DB:GetSettings()

    -- Collect data
    local data        = {}
    local totalCount  = 0
    local totalCopper = 0

    for itemID, itemData in pairs(UGC.ITEM_DB) do
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
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -yOffset)
        row:SetWidth(self.content:GetWidth())

        -- Alternating bg
        if i % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.03)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        -- Icon
        row.icon:SetTexture(item.icon or ICON_UNKNOWN)

        -- Quality stars
        local q   = item.quality
        local col = q and QUALITY_COLORS[q]
        for i = 1, 3 do
            if col and i <= q then
                row.qualityStars[i]:SetVertexColor(col[1], col[2], col[3])
                row.qualityStars[i]:Show()
            else
                row.qualityStars[i]:Hide()
            end
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
