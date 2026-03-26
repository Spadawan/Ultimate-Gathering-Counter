-------------------------------------------------------------------------------
-- Config.lua
-- Settings panel for UGC. Accessible via /ugc config or the ⚙ button on the
-- overlay. All changes apply immediately.
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Config = {}
local Config = UGC.Config

local WIN_WIDTH  = 370
local WIN_HEIGHT = 560

-------------------------------------------------------------------------------
-- UI helpers
-------------------------------------------------------------------------------

-- Creates a labeled section divider
local function MakeSection(parent, label, yOff)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT",  parent, "TOPLEFT",  10, yOff)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, yOff)
    bar:SetHeight(18)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.18, 0.18, 0.18, 1)

    local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", bar, "LEFT", 8, 0)
    fs:SetText(label)
    fs:SetTextColor(0.95, 0.85, 0.2)

    return bar, yOff - 20
end

-- Checkbox + label pair.  Returns (checkBtn, nextYOffset)
local function MakeCheckbox(parent, label, yOff, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOff)
    cb:SetChecked(getter())

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    lbl:SetTextColor(0.9, 0.9, 0.9)

    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() == true or self:GetChecked() == 1)
    end)

    return cb, yOff - 26
end

-- Slider with Low/High labels and a value display.
-- Returns (slider, nextYOffset)
local function MakeSlider(parent, name, label, yOff, minVal, maxVal, step,
                          getter, setter)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOff)
    lbl:SetText(label)
    lbl:SetTextColor(0.9, 0.9, 0.9)

    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOff - 16)
    slider:SetWidth(WIN_WIDTH - 40)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetValue(getter())
    _G[name .. "Low"]:SetText(tostring(minVal))
    _G[name .. "High"]:SetText(tostring(maxVal))
    _G[name .. "Text"]:SetText(tostring(getter()))

    slider:SetScript("OnValueChanged", function(self, value)
        -- Snap to step
        local snapped = math.floor(value / step + 0.5) * step
        snapped = math.max(minVal, math.min(maxVal, snapped))
        _G[name .. "Text"]:SetText(string.format("%.2f", snapped))
        setter(snapped)
    end)

    return slider, yOff - 46
end

-- Labeled numeric editbox
local function MakeNumericBox(parent, label, yOff, getter, setter)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOff)
    lbl:SetText(label)
    lbl:SetTextColor(0.9, 0.9, 0.9)

    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(70, 20)
    box:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(4)
    box:SetText(tostring(getter()))

    box:SetScript("OnEnterPressed", function(self)
        local val = math.max(0, math.min(9999, tonumber(self:GetText()) or 0))
        self:SetText(tostring(val))
        self:ClearFocus()
        setter(val)
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(self)
        local val = math.max(0, math.min(9999, tonumber(self:GetText()) or 0))
        self:SetText(tostring(val))
        setter(val)
    end)

    return box, yOff - 28
end

-- Standard UIPanelButton
local function MakeButton(parent, label, width, height, xOff, yOff, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, height)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

-------------------------------------------------------------------------------
-- Init — called on PLAYER_LOGIN
-------------------------------------------------------------------------------
function Config:Init()
    local f = UGC.Compat:CreateBackdropFrame("Frame", "UGC_Config", UIParent)
    f:SetSize(WIN_WIDTH, WIN_HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(30)
    f:SetPoint("CENTER", UIParent, "CENTER", 220, 0)
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
    tinsert(UISpecialFrames, "UGC_Config")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("|cff33E633UGC|r  —  Settings")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -10)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetScript("OnClick", function() Config:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", "UGC_ConfigScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 30)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() or 0
        local child = self:GetScrollChild()
        local childHeight = child and child:GetHeight() or 0
        local frameHeight = self:GetHeight() or 0
        local maxScroll = math.max(0, childHeight - frameHeight)
        local nextVal = math.max(0, math.min(maxScroll, cur - (delta * 30)))
        self:SetVerticalScroll(nextVal)
    end)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(WIN_WIDTH - 40)
    content:SetHeight(20)
    scrollFrame:SetScrollChild(content)

    local s  = UGC.DB:GetSettings()
    local yOff = -4

    -- ════════════════════════════════════════════════════
    -- SECTION: Display
    -- ════════════════════════════════════════════════════
    local _, y = MakeSection(content, "Display", yOff)
    yOff = y

    -- Show overlay
    _, yOff = MakeCheckbox(content, "Show overlay on login", yOff,
        function() return s.overlayVisible end,
        function(v)
            s.overlayVisible = v
            if v then UGC.Overlay:Show() else UGC.Overlay:Hide() end
        end)

    -- Lock position
    _, yOff = MakeCheckbox(content, "Lock overlay position (disable dragging)", yOff,
        function() return s.overlayLocked end,
        function(v) s.overlayLocked = v end)

    -- Show per-hour rates
    _, yOff = MakeCheckbox(content, "Show per-hour rates in overlay", yOff,
        function() return s.showPerHourRates end,
        function(v)
            s.showPerHourRates = v
            if UGC.Overlay then UGC.Overlay:Refresh() end
        end)

    -- Show auction values
    _, yOff = MakeCheckbox(content, "Show Auctionator values", yOff,
        function() return s.showValues end,
        function(v)
            s.showValues = v
            if UGC.Overlay then UGC.Overlay:Refresh() end
        end)

    -- Overlay scale slider
    _, yOff = MakeSlider(content, "UGC_ScaleSlider", "Overlay scale:", yOff,
        0.5, 2.0, 0.05,
        function() return s.overlayScale or 1.0 end,
        function(v)
            s.overlayScale = v
            if UGC.Overlay then UGC.Overlay:SetScale(v) end
        end)
    yOff = yOff - 2

    -- Minimum qty
    _, yOff = MakeNumericBox(content,
        "Minimum bag qty to display (0 = show all):", yOff,
        function() return s.minimumQty or 0 end,
        function(v)
            s.minimumQty = v
            if UGC.Overlay then UGC.Overlay:Refresh() end
        end)
    yOff = yOff - 4

    -- Fade overlay when unfocused
    _, yOff = MakeCheckbox(content, "Fade overlay to 50% when mouse is not over it", yOff,
        function() return s.fadeWhenUnfocused end,
        function(v)
            s.fadeWhenUnfocused = v
            if UGC.Overlay and UGC.Overlay.frame then
                local base = s.overlayAlpha or 1.0
                UGC.Overlay.frame:SetAlpha(v and base * 0.5 or base)
            end
        end)
    yOff = yOff - 4

    -- Overlay base transparency slider
    _, yOff = MakeSlider(content, "UGC_AlphaSlider", "Overlay transparency:", yOff,
        0.1, 1.0, 0.05,
        function() return s.overlayAlpha or 1.0 end,
        function(v)
            s.overlayAlpha = v
            if UGC.Overlay and UGC.Overlay.frame then
                local base = v
                if s.fadeWhenUnfocused and not UGC.Overlay.frame:IsMouseOver() then
                    UGC.Overlay.frame:SetAlpha(base * 0.5)
                else
                    UGC.Overlay.frame:SetAlpha(base)
                end
            end
        end)
    yOff = yOff - 4

    _, yOff = MakeCheckbox(content, "Profession-only mode (hide XP/chains/creatures)", yOff,
        function() return s.professionOnlyMode == true end,
        function(v)
            s.professionOnlyMode = v
            if v and UGC.Creatures and UGC.Creatures.frame then
                UGC.Creatures.frame:Hide()
            end
            if UGC.Overlay then UGC.Overlay:Refresh() end
            if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
                UGC.Details:Refresh()
            end
        end)
    yOff = yOff - 4

    -- ════════════════════════════════════════════════════
    -- SECTION: Categories
    -- ════════════════════════════════════════════════════
    _, y = MakeSection(content, "Categories to Track", yOff)
    yOff = y

    local catDefs = {
        { key = "herbs",   label = "Herbs   (herbalism)"  },
        { key = "ore",     label = "Ore     (mining)"     },
        { key = "fish",    label = "Fish    (fishing)"    },
        { key = "leather", label = "Leather (skinning)"   },
    }
    for _, cd in ipairs(catDefs) do
        local catKey  = cd.key
        local catData = UGC.CATEGORIES[catKey]
        local cb
        cb, yOff = MakeCheckbox(content,
            string.format("|cff%s%s|r", catData.hex, cd.label),
            yOff,
            function() return s.showCategories[catKey] end,
            function(v)
                s.showCategories[catKey] = v
                if UGC.Overlay then UGC.Overlay:Refresh() end
            end)
    end
    yOff = yOff - 2

    -- ════════════════════════════════════════════════════
    -- SECTION: Detection
    -- ════════════════════════════════════════════════════
    _, y = MakeSection(content, "Detection", yOff)
    yOff = y

    _, yOff = MakeCheckbox(content,
        "Secondary loot detection via chat (item discovery only)", yOff,
        function() return s.chatLootDetect end,
        function(v) s.chatLootDetect = v end)

    local chatHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    chatHint:SetPoint("TOPLEFT", content, "TOPLEFT", 36, yOff + 4)
    chatHint:SetWidth(WIN_WIDTH - 46)
    chatHint:SetText("When enabled, detects new item types from loot messages.\nCounting now requires a loot message and a matching bag update to avoid false positives on login.")
    chatHint:SetJustifyH("LEFT")
    chatHint:SetTextColor(0.45, 0.45, 0.45)
    yOff = yOff - 28

    -- ════════════════════════════════════════════════════
    -- SECTION: Data Management
    -- ════════════════════════════════════════════════════
    _, y = MakeSection(content, "Data Management", yOff)
    yOff = y - 6

    MakeButton(content, "Reset Session", 140, 24, 10, yOff, function()
        UGC.Tracker:ResetSession()
        if UGC.Overlay then UGC.Overlay:Refresh() end
        if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
            UGC.Details:Refresh()
        end
        print("|cff33E633UGC:|r Session counters reset.")
    end)

    if not StaticPopupDialogs["UGC_CONFIRM_RESET_DATA"] then
        StaticPopupDialogs["UGC_CONFIRM_RESET_DATA"] = {
            text         = "|cffff4444Warning!|r\nThis will permanently delete ALL gathered statistics and session data. This cannot be undone.\n\nAre you sure?",
            button1      = "Yes, reset data",
            button2      = "Cancel",
            OnAccept     = function()
                UGC.DB:ResetAllTime()
                if UGC.Overlay then UGC.Overlay:Refresh() end
                if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
                    UGC.Details:Refresh()
                end
                print("|cff33E633UGC:|r All gathered data has been permanently deleted.")
            end,
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
    end

    MakeButton(content, "Reset Data", 155, 24, 160, yOff, function()
        StaticPopup_Show("UGC_CONFIRM_RESET_DATA")
    end)

    local resetHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    resetHint:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yOff - 30)
    resetHint:SetWidth(WIN_WIDTH - 28)
    resetHint:SetJustifyH("LEFT")
    resetHint:SetText("Reset Data deletes all saved statistics (all-time, weekly, daily, hourly) after confirmation.")
    resetHint:SetTextColor(0.45, 0.45, 0.45)
    yOff = yOff - 52

    -- Auctionator status note
    local aucNote = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    aucNote:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yOff)
    aucNote:SetWidth(WIN_WIDTH - 28)
    aucNote:SetJustifyH("LEFT")

    local function UpdateAucNote()
        if UGC.Compat:IsAddOnLoaded("Auctionator") then
            aucNote:SetText("|cff33E633Auctionator detected.|r Price data is available.")
        else
            aucNote:SetText("|cffff8800Auctionator not loaded.|r Values will show as \"?\".")
        end
    end
    UpdateAucNote()

    -- Version line
    local verLine = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    verLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    verLine:SetText("Ultimate Gathering Counter v" .. UGC.VERSION)
    verLine:SetTextColor(0.3, 0.3, 0.3)

    content:SetHeight(math.max(20, -yOff + 50))

    self.frame = f
    f:Hide()
end

-------------------------------------------------------------------------------
-- Show / Hide / Toggle
-------------------------------------------------------------------------------
function Config:Show()
    if self.frame then self.frame:Show() end
end

function Config:Hide()
    if self.frame then self.frame:Hide() end
end

function Config:Toggle()
    if self.frame then
        if self.frame:IsShown() then self:Hide() else self:Show() end
    end
end
