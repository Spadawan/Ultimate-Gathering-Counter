-------------------------------------------------------------------------------
-- Creatures.lua
-- Companion creatures tied to gathering categories.
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Creatures = {}
local Creatures = UGC.Creatures

local WINDOW_SIZE = 420
local TAB_ORDER = { "herbs", "ore", "fish", "leather" }
local ICON_PATH = "Interface\\AddOns\\UltimateGatheringCounter\\media\\monster"
local BUBBLE_TEXTURE = "Interface\\AddOns\\UltimateGatheringCounter\\media\\bubble"

local ART_BY_CATEGORY = {
    herbs = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_01",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_02",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_03",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_04",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_05",
    },
}

local CUTE_NAMES = {
    herbs = "Spriglet",
    ore = "Pebblin",
    fish = "Blooplet",
    leather = "Snugglehide",
}

local function getPhaseForLevel(level)
    if level <= 5 then return 1 end
    if level <= 15 then return 2 end
    if level <= 25 then return 3 end
    if level <= 40 then return 4 end
    return 5
end

function Creatures:IsAnyCreatureUnlocked()
    for _, cat in ipairs(TAB_ORDER) do
        local cp = UGC.Progression:GetCreatureProgress(cat)
        if cp.unlocked then
            return true
        end
    end
    return false
end

function Creatures:GetOverlayIconPath()
    return ICON_PATH
end

function Creatures:Init()
    local f = UGC.Compat:CreateBackdropFrame("Frame", "UGC_Creatures", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(WINDOW_SIZE, WINDOW_SIZE)
    f:SetPoint("CENTER", UIParent, "CENTER", 280, 40)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("Companion Creatures")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    self._tabs = {}
    for i, cat in ipairs(TAB_ORDER) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(92, 22)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + ((i - 1) * 98), -42)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(CUTE_NAMES[cat])
        btn.cat = cat
        btn:SetScript("OnClick", function(selfBtn)
            Creatures:_SetCategory(selfBtn.cat)
        end)
        self._tabs[cat] = btn
    end

    local art = f:CreateTexture(nil, "ARTWORK")
    art:SetSize(168, 168)
    art:SetPoint("TOP", f, "TOP", 0, -111)
    art:SetTexCoord(0.01, 0.99, 0.01, 0.99)

    local creatureName = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    creatureName:SetPoint("TOP", art, "BOTTOM", 0, -8)

    local levelText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelText:SetPoint("TOP", creatureName, "BOTTOM", 0, -4)

    local expBg = f:CreateTexture(nil, "BORDER")
    expBg:SetPoint("TOP", levelText, "BOTTOM", 0, -10)
    expBg:SetSize(260, 16)
    expBg:SetColorTexture(0, 0, 0, 0.65)

    local expFill = f:CreateTexture(nil, "ARTWORK")
    expFill:SetPoint("LEFT", expBg, "LEFT", 0, 0)
    expFill:SetHeight(16)
    expFill:SetColorTexture(0.25, 0.88, 0.25, 0.95)

    local expText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    expText:SetPoint("CENTER", expBg, "CENTER", 0, 0)

    local popup = f:CreateFontString(nil, "HIGHLIGHT", "GameFontNormalLarge")
    popup:SetPoint("CENTER", art, "TOP", 0, -5)
    popup:SetTextColor(0.4, 1.0, 0.4)
    popup:SetAlpha(0)
    local popupDriver = CreateFrame("Frame", nil, f)

    local feedBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    feedBtn:SetSize(170, 24)
    feedBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    feedBtn:SetText("Feed with your EXP")
    feedBtn:SetScript("OnClick", function(btn)
        Creatures:_Feed(btn)
    end)

    self.frame = f
    self._art = art
    self._name = creatureName
    self._levelText = levelText
    self._expFill = expFill
    self._expBg = expBg
    self._expText = expText
    self._popup = popup
    self._popupDriver = popupDriver
    self._feedBtn = feedBtn
    self._activeCategory = "herbs"
    self:_SetCategory("herbs")

    f:Hide()
end

function Creatures:_PlayPopup(text, color)
    if not self._popup then return end
    self._popup:SetText(text)
    if color then
        self._popup:SetTextColor(color[1], color[2], color[3])
    else
        self._popup:SetTextColor(0.4, 1.0, 0.4)
    end
    self._popup:SetAlpha(1)

    if self._popupDriver then
        self._popupDriver:SetScript("OnUpdate", nil)
    end

    local t0 = GetTime()
    local fs = self._popup
    if not self._popupDriver then return end

    self._popupDriver:SetScript("OnUpdate", function()
        local t = GetTime() - t0
        fs:SetAlpha(math.max(0, 1 - (t / 1.2)))
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", Creatures._art, "TOP", 0, -5 + (t * 24))
        if t >= 1.2 then
            fs:SetAlpha(0)
            Creatures._popupDriver:SetScript("OnUpdate", nil)
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", Creatures._art, "TOP", 0, -5)
        end
    end)
end

function Creatures:_SpawnBubbleFeedAnimation(sourceBtn)
    if not self.frame or not self._art or not sourceBtn then return end

    local function toUIParentCoords(frame)
        local x, y = frame:GetCenter()
        if not (x and y) then return nil, nil end
        local frameScale = frame:GetEffectiveScale() or 1
        local parentScale = UIParent:GetEffectiveScale() or 1
        return (x * frameScale) / parentScale, (y * frameScale) / parentScale
    end

    local sx, sy = toUIParentCoords(sourceBtn)
    local dx, dy = toUIParentCoords(self._art)
    if not (sx and sy and dx and dy) then return end

    for i = 1, 14 do
        local b = CreateFrame("Frame", nil, UIParent)
        b:SetFrameStrata("HIGH")
        local size = 12 + math.random(0, 10)
        b:SetSize(size, size)
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(BUBBLE_TEXTURE)
        tex:SetBlendMode("BLEND")
        b.tex = tex

        local startX = sx + math.random(-12, 12)
        local startY = sy + math.random(-8, 8)
        local c1x = startX + math.random(-70, 70)
        local c1y = startY + 60 + math.random(0, 50)
        local c2x = dx + math.random(-70, 70)
        local c2y = dy + 40 + math.random(0, 70)
        local duration = 0.8 + math.random() * 0.3
        local t0 = GetTime() + (i * 0.01)

        b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", startX, startY)
        b:SetAlpha(0.9)

        b:SetScript("OnUpdate", function(self)
            local t = (GetTime() - t0) / duration
            if t <= 0 then return end

            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                self:SetParent(nil)
                return
            end

            local u = 1 - t
            local uu = u * u
            local tt = t * t
            local ax = uu * u * startX + 3 * uu * t * c1x + 3 * u * tt * c2x + tt * t * dx
            local ay = uu * u * startY + 3 * uu * t * c1y + 3 * u * tt * c2y + tt * t * dy

            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ax, ay)
            self:SetAlpha(1 - t * 0.9)
            self:SetScale(1 - t * 0.45)
        end)
    end
end

function Creatures:_Feed(btn)
    local cat = self._activeCategory
    if not cat then return end

    local ok, result = UGC.Progression:FeedCreature(cat)
    if not ok then
        if result == "locked" then
            self:_PlayPopup("Creature locked", { 1, 0.2, 0.2 })
        elseif result == "xp" then
            self:_PlayPopup("Not enough profession EXP", { 1, 0.2, 0.2 })
        elseif result == "max" then
            self:_PlayPopup("Max creature level", { 1, 0.9, 0.2 })
        end
        return
    end

    self:_SpawnBubbleFeedAnimation(btn)
    if result == "levelup" then
        self:_PlayPopup("Level up!", { 0.4, 1.0, 0.3 })
    else
        self:_PlayPopup("+100 EXP", { 0.4, 1.0, 0.3 })
    end

    self:Refresh()
    if UGC.Overlay then UGC.Overlay:Refresh() end
    if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
        UGC.Details:Refresh()
    end
end

function Creatures:_RenameCurrent()
    if not self._activeCategory then return end
    local category = self._activeCategory
    local cp = UGC.Progression:GetCreatureProgress(category)

    StaticPopupDialogs["UGC_RENAME_CREATURE"] = {
        text = "Rename creature",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = 1,
        maxLetters = 24,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
        OnShow = function(self)
            self.editBox:SetText(cp.name or "")
            self.editBox:SetFocus()
            self.editBox:HighlightText()
        end,
        OnAccept = function(self)
            local value = self.editBox:GetText() or ""
            if UGC.Progression:RenameCreature(category, value) then
                Creatures:Refresh()
                if UGC.Overlay then UGC.Overlay:Refresh() end
                if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
                    UGC.Details:Refresh()
                end
                if UGC.Community then
                    UGC.Community:BroadcastSnapshot(true)
                end
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            parent.button1:Click()
        end,
    }

    StaticPopup_Show("UGC_RENAME_CREATURE")
end

function Creatures:_SetCategory(category)
    self._activeCategory = category
    self:Refresh()
end

function Creatures:Refresh()
    if not self.frame then return end

    local active = self._activeCategory or "herbs"

    for _, cat in ipairs(TAB_ORDER) do
        local btn = self._tabs[cat]
        local cp = UGC.Progression:GetCreatureProgress(cat)
        local enabled = cp.unlocked
        btn:SetEnabled(enabled)
        if enabled then
            if cat == active then
                btn.bg:SetColorTexture(0.25, 0.55, 0.25, 0.95)
                btn.text:SetTextColor(1, 1, 1)
            else
                btn.bg:SetColorTexture(0.16, 0.16, 0.16, 1)
                btn.text:SetTextColor(0.8, 0.8, 0.8)
            end
        else
            btn.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            btn.text:SetTextColor(0.45, 0.45, 0.45)
        end

        local labelName = cp.name and cp.name ~= "" and cp.name or CUTE_NAMES[cat]
        btn.text:SetText(labelName)
    end

    local cp = UGC.Progression:GetCreatureProgress(active)
    local prof = UGC.Progression:GetProgress(active)
    local artList = ART_BY_CATEGORY[active]

    if not cp.unlocked then
        self._art:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        self._name:SetText("Locked - reach level 5 in this profession")
        self._levelText:SetText("")
        self._expFill:SetWidth(1)
        self._expText:SetText("")
        self._feedBtn:Disable()
        return
    end

    local phase = getPhaseForLevel(cp.level)
    local texturePath = (artList and artList[phase]) or "Interface\\Icons\\INV_Misc_QuestionMark"
    self._art:SetTexture(texturePath)

    self._name:SetText(cp.name)
    self._levelText:SetText(string.format(
        "|cff33ff33Creature Lv.%d|r  |cff9f9f9fBest Lv.%d|r   •   |cff33ff33Profession Lv.%d|r  |cff9f9f9fBest Lv.%d|r",
        cp.level, cp.maxLevelReached or cp.level, prof.level, prof.maxLevelReached or prof.level))

    local pct = (cp.reqXP > 0) and math.min(1, cp.xp / cp.reqXP) or 0
    local w = self._expBg:GetWidth() or 260
    self._expFill:SetWidth(math.max(1, w * pct))
    self._expText:SetText(string.format("%d / %d EXP", cp.xp, cp.reqXP))

    self._feedBtn:SetEnabled(cp.level < cp.maxLevel)
end

function Creatures:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:Refresh()
    end
end
