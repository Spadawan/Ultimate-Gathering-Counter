-------------------------------------------------------------------------------
-- Overlay.lua
-- Main always-on overlay window. Draggable, scalable, color-coded by category.
-- Displays: item icon, name, bag count (+session gain), /hr rate, and value.
-- Requires Tracker.lua and Database.lua (already loaded earlier in .toc).
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Overlay = {}
local Overlay = UGC.Overlay

-- Layout constants
local OVERLAY_WIDTH  = 390
local OVERLAY_HEIGHT = 360   -- default; resizes based on content, capped
local MAX_HEIGHT     = 520
local MIN_HEIGHT     = 90
local ROW_HEIGHT     = 24
local HDR_HEIGHT     = 22
local PADDING        = 6

-- Question mark fallback icon
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_DETAILS = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_CONFIG  = "Interface\\Buttons\\UI-OptionsButton"
local ICON_ADDON   = "Interface\\Icons\\Ability_Tracking"  -- icône addon (tracking, dispo Classic+Retail)


-------------------------------------------------------------------------------
-- Coin formatter
-------------------------------------------------------------------------------
local function FormatCoin(copper)
    if not copper or copper <= 0 then return "|cff888888—|r" end
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop    = copper % 100
    if gold > 0 then
        return string.format("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r",
               gold, silver, cop)
    elseif silver > 0 then
        return string.format("|cffc7c7cf%ds|r |cffeda55f%dc|r", silver, cop)
    else
        return string.format("|cffeda55f%dc|r", cop)
    end
end

-------------------------------------------------------------------------------
-- Auctionator price helper (returns copper or nil)
-------------------------------------------------------------------------------
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
local function CreateItemRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    -- Subtle alternating-row bg (toggled externally)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0)  -- transparent by default

    -- Item icon (clickable for tooltip)
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.iconBtn:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.icon = row.iconBtn:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Quality stars (1★ bronze, 2★ argent, 3★ or) — FontString, fiable sans dépendance texture
    row.qualityGem = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.qualityGem:SetPoint("BOTTOMLEFT", row.iconBtn, "BOTTOMLEFT", -1, -3)
    row.qualityGem:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
    row.qualityGem:SetText("")

    row.iconBtn:SetScript("OnEnter", function(self)
        if row.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. row.itemID)
            GameTooltip:Show()
        end
    end)
    row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Item name
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", row.iconBtn, "RIGHT", 4, 0)
    row.nameText:SetWidth(155)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    -- Bag / session count
    row.bagText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.bagText:SetPoint("LEFT", row, "LEFT", 182, 0)
    row.bagText:SetWidth(60)
    row.bagText:SetJustifyH("RIGHT")

    -- Per-hour rate
    row.rateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rateText:SetPoint("LEFT", row, "LEFT", 248, 0)
    row.rateText:SetWidth(64)
    row.rateText:SetJustifyH("RIGHT")
    row.rateText:SetTextColor(0.65, 0.65, 0.65)

    -- Resell value
    row.valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.valueText:SetPoint("LEFT", row, "LEFT", 318, 0)
    row.valueText:SetWidth(66)
    row.valueText:SetJustifyH("RIGHT")

    return row
end

-- Section header (one per category group)
local function CreateSectionHeader(parent, cat)
    local catData = UGC.CATEGORIES[cat]
    local hdr = CreateFrame("Button", nil, parent)
    hdr:SetHeight(HDR_HEIGHT)
    hdr:RegisterForClicks("LeftButtonUp")

    hdr.bg = hdr:CreateTexture(nil, "BACKGROUND")
    hdr.bg:SetAllPoints()
    hdr.bg:SetColorTexture(
        catData.color.r * 0.25,
        catData.color.g * 0.25,
        catData.color.b * 0.25,
        0.7)

    -- Collapse/expand arrow indicator
    hdr.arrow = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr.arrow:SetPoint("LEFT", hdr, "LEFT", 6, 0)
    hdr.arrow:SetTextColor(0.8, 0.8, 0.8)
    hdr.arrow:SetText("-")

    hdr.label = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr.label:SetPoint("LEFT", hdr, "LEFT", 20, 0)
    hdr.label:SetTextColor(catData.color.r, catData.color.g, catData.color.b)

    hdr.count = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdr.count:SetPoint("RIGHT", hdr, "RIGHT", -8, 0)
    hdr.count:SetTextColor(0.75, 0.75, 0.75)

    -- Hover highlight
    hdr:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(
            catData.color.r * 0.4,
            catData.color.g * 0.4,
            catData.color.b * 0.4, 0.85)
    end)
    hdr:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(
            catData.color.r * 0.25,
            catData.color.g * 0.25,
            catData.color.b * 0.25, 0.7)
    end)

    -- Click toggles collapse state and refreshes
    hdr:SetScript("OnClick", function(self)
        local s = UGC.DB:GetSettings()
        s.collapsedCategories[self._cat] = not s.collapsedCategories[self._cat]
        Overlay:Refresh()
    end)

    return hdr
end

-------------------------------------------------------------------------------
-- Init — called on PLAYER_LOGIN
-------------------------------------------------------------------------------
function Overlay:Init()
    local settings = UGC.DB:GetSettings()

    local f = CreateFrame("Frame", "UGC_Overlay", UIParent, "BackdropTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:SetSize(OVERLAY_WIDTH, OVERLAY_HEIGHT)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.88)
    f:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    f:SetAlpha(settings.overlayAlpha or 1.0)
    f:SetClampedToScreen(true)

    -- Restore saved position
    local p = settings.overlayPoint or {}
    f:SetPoint(p.point or "CENTER", UIParent, p.point or "CENTER",
               p.x or 0, p.y or 100)
    f:SetScale(settings.overlayScale or 1.0)

    -- Dragging
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not UGC.DB:GetSettings().overlayLocked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Overlay:SavePosition()
    end)

    -- ── Title bar ────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  6, -6)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    titleBar:SetHeight(20)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 6, 0)
    titleText:SetText("|cff33E633UGC|r  Ultimate Gathering Counter")

    -- Icône addon (visible uniquement en mode minimisé)
    local addonIcon = titleBar:CreateTexture(nil, "OVERLAY")
    addonIcon:SetSize(14, 14)
    addonIcon:SetPoint("LEFT", titleBar, "LEFT", 4, 0)
    addonIcon:SetTexture(ICON_ADDON)
    addonIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addonIcon:Hide()

    -- ── Header buttons ────────────────────────────────────────────────
    -- Close
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", -2, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetScript("OnClick", function() Overlay:Hide() end)
    closeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Hide overlay\n|cff888888/ugc to show again|r")
        GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Details
    local detailsBtn = CreateFrame("Button", nil, f)
    detailsBtn:SetSize(16, 16)
    detailsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    detailsBtn:SetNormalTexture(ICON_DETAILS)
    detailsBtn:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    detailsBtn:SetHighlightTexture(ICON_DETAILS, "ADD")
    detailsBtn:GetHighlightTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    detailsBtn:SetScript("OnClick", function() UGC.Details:Toggle() end)
    detailsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Open detailed statistics\n|cff888888/ugc details|r")
        GameTooltip:Show()
    end)
    detailsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Config
    local configBtn = CreateFrame("Button", nil, f)
    configBtn:SetSize(16, 16)
    configBtn:SetPoint("RIGHT", detailsBtn, "LEFT", -4, 0)
    configBtn:SetNormalTexture(ICON_CONFIG)
    configBtn:SetHighlightTexture(ICON_CONFIG, "ADD")
    configBtn:SetScript("OnClick", function() UGC.Config:Toggle() end)
    configBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Settings\n|cff888888/ugc config|r")
        GameTooltip:Show()
    end)
    configBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Réduire / Restaurer
    local minimizeBtn = CreateFrame("Button", nil, f)
    minimizeBtn:SetSize(16, 16)
    minimizeBtn:SetPoint("RIGHT", configBtn, "LEFT", -4, 0)
    minimizeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
    minimizeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Down")
    minimizeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up", "ADD")
    minimizeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Réduire l'overlay")
        GameTooltip:Show()
    end)
    minimizeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Reset session
    local resetBtn = CreateFrame("Button", nil, f)
    resetBtn:SetSize(16, 16)
    resetBtn:SetPoint("RIGHT", minimizeBtn, "LEFT", -4, 0)
    resetBtn:SetNormalTexture("Interface\\TimeManager\\ResetButton")
    resetBtn:SetHighlightTexture("Interface\\TimeManager\\ResetButton", "ADD")
    resetBtn:SetScript("OnClick", function()
        UGC.Tracker:ResetSession()
        Overlay:Refresh()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Reset session\n|cff888888/ugc reset|r")
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Column header row ─────────────────────────────────────────────
    local colHdr = CreateFrame("Frame", nil, f)
    colHdr:SetPoint("TOPLEFT",  f, "TOPLEFT",   6, -28)
    colHdr:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -6, -28)
    colHdr:SetHeight(14)

    local colHdrBg = colHdr:CreateTexture(nil, "BACKGROUND")
    colHdrBg:SetAllPoints()
    colHdrBg:SetColorTexture(0.0, 0.0, 0.0, 0.4)

    local function MakeColHdr(text, xOff, width, justify)
        local fs = colHdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", colHdr, "LEFT", xOff, 0)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetTextColor(0.45, 0.45, 0.45)
        fs:SetText(text)
    end
    MakeColHdr("Item",   26,  155, "LEFT")
    MakeColHdr("Bags",  182,   60, "RIGHT")
    MakeColHdr("Rate",  248,   64, "RIGHT")
    MakeColHdr("Value", 318,   66, "RIGHT")

    -- ── Scroll frame ──────────────────────────────────────────────────
    local scrollFrame = CreateFrame("ScrollFrame", "UGC_OverlayScroll", f,
                                    "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",    6, -44)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 34)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(OVERLAY_WIDTH - 34)
    content:SetHeight(20)
    scrollFrame:SetScrollChild(content)

    -- ── Total value bar ───────────────────────────────────────────────
    local totalBar = CreateFrame("Frame", nil, f)
    totalBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   6,  5)
    totalBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6,  5)
    totalBar:SetHeight(26)

    local totalBarBg = totalBar:CreateTexture(nil, "BACKGROUND")
    totalBarBg:SetAllPoints()
    totalBarBg:SetColorTexture(0.05, 0.05, 0.05, 0.85)

    local totalLabel = totalBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalLabel:SetPoint("LEFT", totalBar, "LEFT", 8, 0)
    totalLabel:SetText("Estimated total:")
    totalLabel:SetTextColor(0.75, 0.75, 0.75)

    local totalValue = totalBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    totalValue:SetPoint("RIGHT", totalBar, "RIGHT", -8, 0)

    -- ── Store references ──────────────────────────────────────────────
    self.frame       = f
    self.content     = content
    self.scrollFrame = scrollFrame
    self.totalValue  = totalValue
    self.rows        = {}
    self.headers     = {}

    -- ── Mode minimisé ─────────────────────────────────────────────────
    local function ApplyMinimized(minimized)
        UGC.DB:GetSettings().overlayMinimized = minimized
        if minimized then
            colHdr:Hide()
            scrollFrame:Hide()
            totalBar:Hide()
            titleText:SetText("|cff33E633UGC|r")
            addonIcon:Show()
            f:SetHeight(32)
            minimizeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
            minimizeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Down")
            minimizeBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:SetText("Restaurer l'overlay")
                GameTooltip:Show()
            end)
        else
            colHdr:Show()
            scrollFrame:Show()
            totalBar:Show()
            titleText:SetText("|cff33E633UGC|r  Ultimate Gathering Counter")
            addonIcon:Hide()
            minimizeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
            minimizeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Down")
            minimizeBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:SetText("Réduire l'overlay")
                GameTooltip:Show()
            end)
            Overlay:Refresh()
        end
    end

    minimizeBtn:SetScript("OnClick", function()
        ApplyMinimized(not UGC.DB:GetSettings().overlayMinimized)
    end)

    if not settings.overlayVisible then
        f:Hide()
    end

    if settings.overlayMinimized then
        ApplyMinimized(true)
    end

    -- Fade to 50% opacity when mouse is not over the overlay (checked at ~10 Hz)
    local _fadeTimer = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        _fadeTimer = _fadeTimer + elapsed
        if _fadeTimer < 0.1 then return end
        _fadeTimer = 0
        local s = UGC.DB:GetSettings()
        local base = s.overlayAlpha or 1.0
        if s.fadeWhenUnfocused then
            self:SetAlpha(self:IsMouseOver() and base or base * 0.5)
        else
            self:SetAlpha(base)
        end
    end)

    -- Refresh per-hour rates every 30 s regardless of bag events
    C_Timer.NewTicker(30, function()
        if Overlay.frame and Overlay.frame:IsShown() then
            Overlay:Refresh()
        end
    end)

    self:Refresh()
end

-------------------------------------------------------------------------------
-- Show / Hide / Toggle
-------------------------------------------------------------------------------
function Overlay:Show()
    if self.frame then
        self.frame:Show()
        UGC.DB:GetSettings().overlayVisible = true
    end
end

function Overlay:Hide()
    if self.frame then
        self.frame:Hide()
        UGC.DB:GetSettings().overlayVisible = false
    end
end

function Overlay:Toggle()
    if self.frame then
        if self.frame:IsShown() then
            self:Hide()
        else
            self:Show()
            self:Refresh()
        end
    end
end

function Overlay:SetScale(scale)
    if self.frame then
        self.frame:SetScale(scale)
    end
end

function Overlay:SavePosition()
    if not self.frame then return end
    local settings = UGC.DB:GetSettings()
    local point, _, _, x, y = self.frame:GetPoint()
    settings.overlayPoint = { point = point or "CENTER", x = x or 0, y = y or 100 }
end

-------------------------------------------------------------------------------
-- Refresh — rebuilds all rows from current data
-------------------------------------------------------------------------------
function Overlay:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    local settings = UGC.DB:GetSettings()
    local items    = UGC.Tracker:GetTrackedItems()

    -- Hide all pooled rows and headers
    for _, row in ipairs(self.rows)    do row:Hide()    end
    for _, hdr in ipairs(self.headers) do hdr:Hide()    end

    local rowIdx  = 0
    local hdrIdx  = 0
    local yOffset = 0

    local totalCopper  = 0
    local hasUnknown   = false
    local currentCat   = nil
    local catCounts    = {}   -- category -> count of visible items

    -- Pre-count items per category for header labels
    for _, item in ipairs(items) do
        catCounts[item.category] = (catCounts[item.category] or 0) + 1
    end

    for rowNum, item in ipairs(items) do
        -- ── Category section header ────────────────────────────────
        if item.category ~= currentCat then
            currentCat = item.category
            hdrIdx = hdrIdx + 1

            local hdr = self.headers[hdrIdx]
            if not hdr then
                hdr = CreateSectionHeader(self.content, currentCat)
                self.headers[hdrIdx] = hdr
            end

            hdr._cat = currentCat  -- used by the OnClick handler

            local catData   = UGC.CATEGORIES[currentCat]
            local collapsed = settings.collapsedCategories[currentCat]
            hdr.arrow:SetText(collapsed and "+" or "-")
            hdr.label:SetText(catData.label:upper())
            hdr.label:SetTextColor(catData.color.r, catData.color.g, catData.color.b)
            hdr.bg:SetColorTexture(
                catData.color.r * 0.25, catData.color.g * 0.25,
                catData.color.b * 0.25, 0.7)
            hdr.count:SetText(catCounts[currentCat] .. " items")

            hdr:SetPoint("TOPLEFT",  self.content, "TOPLEFT",  0, -yOffset)
            hdr:SetWidth(self.content:GetWidth())
            hdr:Show()
            yOffset = yOffset + HDR_HEIGHT + 1
        end

        -- ── Item row (skipped if category is collapsed) ────────────
        if not settings.collapsedCategories[item.category] then
            rowIdx = rowIdx + 1
            local row = self.rows[rowIdx]
            if not row then
                row = CreateItemRow(self.content)
                self.rows[rowIdx] = row
            end

            row.itemID = item.itemID
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -yOffset)
            row:SetWidth(self.content:GetWidth())

            -- Alternating row background
            if rowNum % 2 == 0 then
                row.bg:SetColorTexture(1, 1, 1, 0.04)
            else
                row.bg:SetColorTexture(0, 0, 0, 0)
            end

            -- Icon
            row.icon:SetTexture(item.icon or ICON_UNKNOWN)

            -- Quality stars (1★ bronze, 2★ argent, 3★ or)
            local QUALITY_STARS = {
                [1] = "|cffcc8832★|r",
                [2] = "|cffc0c0c0★★|r",
                [3] = "|ffffd700★★★|r",
            }
            row.qualityGem:SetText(item.quality and QUALITY_STARS[item.quality] or "")

            -- Name
            row.nameText:SetText(item.name)
            row.nameText:SetTextColor(1, 1, 1)

            -- Bag + session gain
            if item.sessionGained > 0 then
                row.bagText:SetText(string.format(
                    "|cff00dd00+%d|r |cff888888(%d)|r",
                    item.sessionGained, item.bagCount))
            elseif item.bagCount > 0 then
                row.bagText:SetText(tostring(item.bagCount))
            else
                row.bagText:SetText("|cff555555—|r")
            end

            -- Per-hour rate
            if settings.showPerHourRates and item.hourlyRate >= 0.5 then
                row.rateText:SetText(string.format("%.0f/h", item.hourlyRate))
                row.rateText:Show()
            else
                row.rateText:SetText("")
            end

            -- Value (price × bag count)
            if settings.showValues then
                local unitPrice = GetAuctionPrice(item.itemID)
                if unitPrice and unitPrice > 0 and item.bagCount > 0 then
                    local itemCopper = unitPrice * item.bagCount
                    totalCopper = totalCopper + itemCopper
                    row.valueText:SetText(FormatCoin(itemCopper))
                elseif unitPrice and unitPrice > 0 then
                    row.valueText:SetText("|cff555555—|r")
                else
                    row.valueText:SetText("|cffff8800?|r")
                    hasUnknown = true
                end
            else
                row.valueText:SetText("")
            end

            row:Show()
            yOffset = yOffset + ROW_HEIGHT + 1
        end
    end

    -- ── Empty state ────────────────────────────────────────────────
    if rowIdx == 0 then
        if not self._emptyText then
            self._emptyText = self.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            self._emptyText:SetPoint("TOP", self.content, "TOP", 0, -16)
            self._emptyText:SetText("No gathering items found.\nStart farming to see results!")
            self._emptyText:SetJustifyH("CENTER")
            self._emptyText:SetWidth(self.content:GetWidth())
        end
        self._emptyText:Show()
        yOffset = 56
    elseif self._emptyText then
        self._emptyText:Hide()
    end

    -- ── Resize frame to fit content ────────────────────────────────
    self.content:SetHeight(math.max(yOffset, 20))
    local newH = math.max(MIN_HEIGHT,
                 math.min(MAX_HEIGHT, yOffset + 44 + 34))
    self.frame:SetHeight(newH)

    -- ── Total value bar ────────────────────────────────────────────
    if rowIdx > 0 then
        local totalStr = FormatCoin(totalCopper)
        if hasUnknown then
            totalStr = totalStr .. " |cffff8800(partial)|r"
        end
        self.totalValue:SetText(totalStr)
    else
        self.totalValue:SetText("|cff555555N/A|r")
    end
end
