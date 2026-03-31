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
local LEVELUP_SOUND = "Interface\\AddOns\\UltimateGatheringCounter\\media\\LevelUp.ogg"
local FEED_SOUND = "Interface\\AddOns\\UltimateGatheringCounter\\media\\iEating1.ogg"
local LEVELUP_PARTICLES = {
    "Interface\\AddOns\\UltimateGatheringCounter\\media\\Misc_Holy_01.tga",
    "Interface\\AddOns\\UltimateGatheringCounter\\media\\Misc_Holy_02.tga",
}
local FEED_PARTICLES_BY_CATEGORY = {
    herbs = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\Leaf_01.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\Leaf_02.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\Leaf_03.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\Leaf_04.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\Leaf_05.tga",
    },
    ore = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\Stone_01.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\Stone_02.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\Stone_03.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\Stone_04.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\Stone_05.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\Stone_06.tga",
    },
    leather = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\Misc_Skinning_01.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\Misc_Skinning_02.tga",
    },
    fish = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\Misc_Skinning_01.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\Misc_Skinning_02.tga",
    },
}

local ART_BY_CATEGORY = {
    herbs = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_01",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_02",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_03",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_04",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\herbalism\\herb_05",
    },
    ore = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\mining_01.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\mining_02.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\mining_03.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\mining_04.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\mining\\mining_05.tga",
    },
    fish = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\fish\\fish_01.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\fish\\fish_02.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\fish\\fish_03.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\fish\\fish_04.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\fish\\fish_05.tga",
    },
    leather = {
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\skin_01.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\skin_02.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\skin_03.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\skin_04.tga",
        "Interface\\AddOns\\UltimateGatheringCounter\\media\\skin\\skin_05.tga",
    },
}

local CUTE_NAMES = {
    herbs = "Spriglet",
    ore = "Pebblin",
    fish = "Blooplet",
    leather = "Snugglehide",
}

local POPUP_HOLD_DURATION = 0.45
local POPUP_FADE_DURATION = 1.55
local ART_SIZE_SMALL = 168

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

    local bgTexture = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgTexture:SetAllPoints()
    bgTexture:SetTexture("Interface\\AddOns\\UltimateGatheringCounter\\media\\background.tga")
    bgTexture:SetTexCoord(0, 1, 0, 1)
    bgTexture:SetVertexColor(1, 1, 1, 0.88)

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
    art:SetSize(ART_SIZE_SMALL, ART_SIZE_SMALL)
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

    local bonusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bonusText:SetPoint("TOP", expBg, "BOTTOM", 0, -8)
    bonusText:SetTextColor(0.45, 0.75, 1.0)

    local popup = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    popup:SetPoint("CENTER", art, "CENTER", 0, 12)
    popup:SetDrawLayer("OVERLAY", 7)
    popup:SetTextColor(0.4, 1.0, 0.4)
    popup:SetAlpha(0)
    local popupAnim
    if popup.CreateAnimationGroup then
        popupAnim = popup:CreateAnimationGroup()
        local hold = popupAnim:CreateAnimation("Alpha")
        hold:SetFromAlpha(1)
        hold:SetToAlpha(1)
        hold:SetDuration(POPUP_HOLD_DURATION)
        hold:SetOrder(1)

        local fade = popupAnim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(POPUP_FADE_DURATION)
        fade:SetOrder(2)

        local drift = popupAnim:CreateAnimation("Translation")
        drift:SetOffset(0, 20)
        drift:SetDuration(POPUP_HOLD_DURATION + POPUP_FADE_DURATION)
        drift:SetOrder(2)

        popupAnim:SetScript("OnFinished", function()
            popup:SetAlpha(0)
            popup:ClearAllPoints()
            popup:SetPoint("CENTER", art, "CENTER", 0, 12)
        end)
    end

    local feedBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    feedBtn:SetSize(170, 24)
    feedBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    feedBtn:SetText("Feed with your EXP")
    feedBtn:SetScript("OnClick", function()
        Creatures:_Feed()
    end)

    local evolveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    evolveBtn:SetSize(170, 24)
    evolveBtn:SetPoint("BOTTOM", feedBtn, "TOP", 0, 6)
    evolveBtn:SetText("Evolve creature")
    evolveBtn:SetScript("OnClick", function()
        Creatures:_Evolve()
    end)

    local evolveOldFx = f:CreateTexture(nil, "HIGHLIGHT")
    evolveOldFx:SetAllPoints(art)
    evolveOldFx:SetBlendMode("ADD")
    evolveOldFx:SetAlpha(0)

    local evolveNewFx = f:CreateTexture(nil, "HIGHLIGHT")
    evolveNewFx:SetAllPoints(art)
    evolveNewFx:SetBlendMode("ADD")
    evolveNewFx:SetAlpha(0)

    local levelupShineFx = f:CreateTexture(nil, "OVERLAY")
    levelupShineFx:SetAllPoints(art)
    levelupShineFx:SetBlendMode("ADD")
    levelupShineFx:SetAlpha(0)

    self.frame = f
    self._art = art
    self._name = creatureName
    self._levelText = levelText
    self._expFill = expFill
    self._expBg = expBg
    self._expText = expText
    self._bonusText = bonusText
    self._popup = popup
    self._popupAnim = popupAnim
    self._feedBtn = feedBtn
    self._evolveBtn = evolveBtn
    self._evolveOldFx = evolveOldFx
    self._evolveNewFx = evolveNewFx
    self._levelupShineFx = levelupShineFx
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

    self._popup:ClearAllPoints()
    self._popup:SetPoint("CENTER", self._art, "CENTER", 0, 12)

    if self._popupAnim then
        self._popupAnim:Stop()
        self._popupAnim:Play()
    end
end

function Creatures:_PlayLevelupSound()
    if PlaySoundFile and PlaySoundFile(LEVELUP_SOUND, "SFX") then
        return
    end
    if PlaySound then
        if SOUNDKIT and SOUNDKIT.UI_PLAYER_LEVEL_UP then
            PlaySound(SOUNDKIT.UI_PLAYER_LEVEL_UP)
        else
            PlaySound("LEVELUP")
        end
    end
end

function Creatures:_PlayFeedSound()
    if PlaySoundFile and PlaySoundFile(FEED_SOUND, "SFX") then
        return
    end
end

function Creatures:_PlayFeedReaction()
    if not self._art then return end
    if not self._feedReactAnim then
        self._feedReactAnim = self._art:CreateAnimationGroup()

        local scaleUp = self._feedReactAnim:CreateAnimation("Scale")
        scaleUp:SetScale(1.05, 1.05)
        scaleUp:SetOrigin("CENTER", 0, 0)
        scaleUp:SetDuration(0.12)
        scaleUp:SetOrder(1)

        local jiggleRight = self._feedReactAnim:CreateAnimation("Translation")
        jiggleRight:SetOffset(2, 0)
        jiggleRight:SetDuration(0.05)
        jiggleRight:SetOrder(1)

        local jiggleLeft = self._feedReactAnim:CreateAnimation("Translation")
        jiggleLeft:SetOffset(-4, 0)
        jiggleLeft:SetDuration(0.08)
        jiggleLeft:SetOrder(2)

        local jiggleCenter = self._feedReactAnim:CreateAnimation("Translation")
        jiggleCenter:SetOffset(2, 0)
        jiggleCenter:SetDuration(0.05)
        jiggleCenter:SetOrder(3)

        local scaleDown = self._feedReactAnim:CreateAnimation("Scale")
        scaleDown:SetScale(1 / 1.05, 1 / 1.05)
        scaleDown:SetOrigin("CENTER", 0, 0)
        scaleDown:SetDuration(0.18)
        scaleDown:SetOrder(2)
    end

    self._feedReactAnim:Stop()
    self._feedReactAnim:Play()
end

function Creatures:_PlayLevelupShine()
    if not self._levelupShineFx then return end
    self._levelupShineFx:SetTexture(self._art:GetTexture())
    self._levelupShineFx:SetVertexColor(1.0, 0.92, 0.25, 1)
    self._levelupShineFx:SetAlpha(0)

    if not self._levelupShineAnim then
        self._levelupShineAnim = self._levelupShineFx:CreateAnimationGroup()
        local fadeIn = self._levelupShineAnim:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(0.78)
        fadeIn:SetDuration(0.12)
        fadeIn:SetOrder(1)
        local fadeOut = self._levelupShineAnim:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(0.78)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(1.15)
        fadeOut:SetOrder(2)
        self._levelupShineAnim:SetScript("OnFinished", function()
            if Creatures._levelupShineFx then
                Creatures._levelupShineFx:SetAlpha(0)
            end
        end)
    end

    self._levelupShineAnim:Stop()
    self._levelupShineAnim:Play()
end

function Creatures:_SpawnLevelupParticles()
    if not self.frame or not self._art then return end
    for i = 1, 22 do
        local tex = self.frame:CreateTexture(nil, "OVERLAY")
        tex:SetDrawLayer("OVERLAY", 6)
        tex:SetTexture(LEVELUP_PARTICLES[((i - 1) % #LEVELUP_PARTICLES) + 1])
        tex:SetBlendMode("ADD")
        local size = math.random(14, 30)
        tex:SetSize(size, size)
        tex:SetPoint("CENTER", self._art, "CENTER", math.random(-40, 40), math.random(-28, 28))
        tex:SetAlpha(0)

        local ag = tex:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(0.95)
        fadeIn:SetDuration(0.2 + math.random() * 0.12)
        fadeIn:SetOrder(1)

        local drift = ag:CreateAnimation("Translation")
        drift:SetOffset(math.random(-45, 45), math.random(36, 90))
        drift:SetDuration(1.0 + math.random() * 0.6)
        drift:SetOrder(1)

        local hold = ag:CreateAnimation("Alpha")
        hold:SetFromAlpha(0.95)
        hold:SetToAlpha(0.95)
        hold:SetDuration(0.24 + math.random() * 0.16)
        hold:SetOrder(2)

        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(0.95)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.9 + math.random() * 0.6)
        fadeOut:SetOrder(3)

        local shrink = ag:CreateAnimation("Scale")
        shrink:SetScale(0.6, 0.6)
        shrink:SetOrigin("CENTER", 0, 0)
        shrink:SetDuration(1.2 + math.random() * 0.5)
        shrink:SetOrder(3)

        ag:SetScript("OnFinished", function()
            tex:Hide()
            tex:SetTexture(nil)
        end)
        ag:Play()
    end
end

function Creatures:_SpawnFeedLeafParticles()
    if not self.frame or not self._art then return end
    local category = self._activeCategory or "herbs"
    local feedParticles = FEED_PARTICLES_BY_CATEGORY[category] or FEED_PARTICLES_BY_CATEGORY.herbs
    for i = 1, 30 do
        local tex = self.frame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(feedParticles[math.random(1, #feedParticles)])
        tex:SetBlendMode("BLEND")
        local size = math.random(9, 15)
        tex:SetSize(size, size)
        tex:SetRotation(math.rad(math.random(0, 359)))
        tex:SetPoint("CENTER", self._art, "CENTER", math.random(-22, 22), math.random(-18, 18))
        tex:SetAlpha(0)

        local ag = tex:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(0.8)
        fadeIn:SetDuration(0.06 + math.random() * 0.08)
        fadeIn:SetOrder(1)

        local pop = ag:CreateAnimation("Translation")
        pop:SetOffset(math.random(-24, 24), math.random(8, 26))
        pop:SetDuration(0.12 + math.random() * 0.08)
        pop:SetOrder(1)

        local fall = ag:CreateAnimation("Translation")
        fall:SetOffset(math.random(-65, 65), -math.random(35, 95))
        fall:SetDuration(0.55 + math.random() * 0.45)
        fall:SetOrder(2)

        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(0.8)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.65 + math.random() * 0.45)
        fadeOut:SetOrder(2)

        ag:SetScript("OnFinished", function()
            tex:Hide()
            tex:SetTexture(nil)
        end)
        ag:Play()
    end
end

function Creatures:_Feed()
    local cat = self._activeCategory
    if not cat then return end
    if UGC.Progression:CanEvolveCreature(cat) then
        self:_PlayPopup("Evolve creature first", { 1.0, 0.9, 0.2 })
        return
    end

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

    if result == "ready" then
        self:_PlayPopup("Ready to evolve!", { 1.0, 0.9, 0.3 })
    elseif result == "levelup" then
        self:_PlayPopup("Level up!", { 0.4, 1.0, 0.3 })
        self:_PlayLevelupShine()
        self:_SpawnLevelupParticles()
        self:_PlayLevelupSound()
    else
        self:_PlayPopup("+100 EXP", { 0.4, 1.0, 0.3 })
    end
    self:_PlayFeedSound()
    self:_PlayFeedReaction()
    self:_SpawnFeedLeafParticles()

    self:Refresh()
    if UGC.Overlay then UGC.Overlay:Refresh() end
    if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
        UGC.Details:Refresh()
    end
end

function Creatures:_PlayEvolutionAnimation(oldTexture, newTexture)
    if not (self._evolveOldFx and self._evolveNewFx and oldTexture and newTexture) then return end

    local oldFx = self._evolveOldFx
    local newFx = self._evolveNewFx

    oldFx:SetTexture(oldTexture)
    oldFx:SetVertexColor(1, 1, 1, 1)
    oldFx:SetAlpha(0.95)

    newFx:SetTexture(newTexture)
    newFx:SetVertexColor(1, 1, 1, 1)
    newFx:SetAlpha(0)

    if not self._evolveOldAnim then
        self._evolveOldAnim = oldFx:CreateAnimationGroup()
        local oldFade = self._evolveOldAnim:CreateAnimation("Alpha")
        oldFade:SetFromAlpha(0.95)
        oldFade:SetToAlpha(0)
        oldFade:SetDuration(0.65)
        oldFade:SetOrder(1)
        self._evolveOldAnim:SetScript("OnFinished", function()
            oldFx:SetAlpha(0)
        end)
    end

    if not self._evolveNewAnim then
        self._evolveNewAnim = newFx:CreateAnimationGroup()
        local newIn = self._evolveNewAnim:CreateAnimation("Alpha")
        newIn:SetFromAlpha(0)
        newIn:SetToAlpha(1)
        newIn:SetDuration(0.2)
        newIn:SetOrder(1)
        local newOut = self._evolveNewAnim:CreateAnimation("Alpha")
        newOut:SetFromAlpha(1)
        newOut:SetToAlpha(0)
        newOut:SetDuration(1.1)
        newOut:SetOrder(2)
        self._evolveNewAnim:SetScript("OnFinished", function()
            newFx:SetAlpha(0)
        end)
    end

    self._evolveOldAnim:Stop()
    self._evolveNewAnim:Stop()
    self._evolveOldAnim:Play()
    self._evolveNewAnim:Play()
end

function Creatures:_Evolve()
    local cat = self._activeCategory
    if not cat then return end

    local before = UGC.Progression:GetCreatureProgress(cat)
    local artList = ART_BY_CATEGORY[cat]
    local oldPhase = getPhaseForLevel(before.level)
    local oldTexture = (artList and artList[oldPhase]) or "Interface\\Icons\\INV_Misc_QuestionMark"

    local ok, result = UGC.Progression:EvolveCreature(cat)
    if not ok then
        if result == "xp" then
            self:_PlayPopup("Not enough creature EXP", { 1, 0.2, 0.2 })
        elseif result == "max" then
            self:_PlayPopup("Max creature level", { 1, 0.9, 0.2 })
        elseif result == "phase" then
            self:_PlayPopup("Evolution not available at this level", { 1, 0.9, 0.2 })
        else
            self:_PlayPopup("Creature locked", { 1, 0.2, 0.2 })
        end
        return
    end

    local after = UGC.Progression:GetCreatureProgress(cat)
    local newPhase = getPhaseForLevel(after.level)
    local newTexture = (artList and artList[newPhase]) or "Interface\\Icons\\INV_Misc_QuestionMark"

    self:Refresh()
    self:_PlayEvolutionAnimation(oldTexture, newTexture)
    self:_PlayLevelupShine()
    self:_SpawnLevelupParticles()
    self:_PlayLevelupSound()
    self:_PlayPopup("Level up!", { 0.4, 1.0, 0.3 })

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
        self._art:SetSize(ART_SIZE_SMALL, ART_SIZE_SMALL)
        self._art:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        self._name:SetText("Locked - reach level 5 in this profession")
        self._levelText:SetText("")
        self._expFill:SetWidth(1)
        self._expText:SetText("")
        self._bonusText:SetText("")
        self._feedBtn:Disable()
        self._evolveBtn:Hide()
        return
    end

    local phase = getPhaseForLevel(cp.level)
    self._art:SetSize(ART_SIZE_SMALL, ART_SIZE_SMALL)
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
    self._bonusText:SetText(string.format("XP bonus: +%.0f%%  •  Total generated: %d EXP", cp.bonusPercent or 0, cp.totalBonusXP or 0))

    local canEvolve = UGC.Progression:CanEvolveCreature(active)
    self._feedBtn:SetEnabled(cp.level < cp.maxLevel and not canEvolve)
    if canEvolve then
        self._evolveBtn:Show()
        self._evolveBtn:Enable()
    else
        self._evolveBtn:Hide()
    end
end

function Creatures:Toggle()
    if not self.frame then return end
    if UGC.DB and UGC.DB:GetSettings().professionOnlyMode then
        return
    end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:Refresh()
    end
end
