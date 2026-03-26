-------------------------------------------------------------------------------
-- Compat.lua
-- Cross-version compatibility helpers for Retail + Classic clients.
--
-- IMPORTANT MAINTENANCE NOTE:
-- Keep this file focused on API compatibility shims only (Retail vs Classic
-- client API differences). Do not add gameplay/business logic here.
-- Reason: gameplay logic belongs in core runtime modules (Tracker/Overlay/etc.)
-- so behavior remains centralized and consistent across builds.
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Compat = {}
local Compat = UGC.Compat

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then
        return a, b, c, d, e
    end
    return nil
end

function Compat:IsAddOnLoaded(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addonName)
    end
    if IsAddOnLoaded then
        return IsAddOnLoaded(addonName)
    end
    return false
end

function Compat:GetServerTime()
    if GetServerTime then
        return GetServerTime()
    end
    return time()
end

function Compat:CreateBackdropFrame(frameType, name, parent)
    if BackdropTemplateMixin then
        return CreateFrame(frameType, name, parent, "BackdropTemplate")
    end
    return CreateFrame(frameType, name, parent)
end

function Compat:SetResizeBounds(frame, minWidth, minHeight, maxWidth, maxHeight)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    elseif frame.SetMinResize then
        frame:SetMinResize(minWidth, minHeight)
        if maxWidth and maxHeight and frame.SetMaxResize then
            frame:SetMaxResize(maxWidth, maxHeight)
        end
    end
end

function Compat:CreateStarTexture(parent, anchor, relativeTo, xOffset)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetSize(9, 9)
    tex:SetPoint(anchor, relativeTo, anchor, xOffset or 0, 0)
    tex:SetTexture("Interface\\Common\\ReputationStar")
    tex:Hide()
    return tex
end

function Compat:GetItemInfoInstant(itemID)
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(itemID)
    end
    if GetItemInfoInstant then
        return GetItemInfoInstant(itemID)
    end
    return nil
end

function Compat:GetContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(bag)
    end
    return 0
end

function Compat:GetContainerItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then
            return info.itemID, info.stackCount or info.quantity or 1
        end
    end

    if GetContainerItemInfo then
        local icon, itemCount, locked, quality, readable, lootable, itemLink = GetContainerItemInfo(bag, slot)
        if itemLink then
            local itemID = tonumber(itemLink:match("|Hitem:(%d+)"))
            if itemID then
                return itemID, itemCount or 1, icon, quality, locked, readable, lootable, itemLink
            end
        end
    end

    return nil, 0
end

function Compat:GetItemCategoryFromInfo(itemID)
    local _, _, _, _, _, itemType, itemSubType, _, _, _, _, classID, subClassID = GetItemInfo(itemID)

    -- Legacy helper kept for compatibility only.
    -- Category/gameplay logic should live in Tracker.lua.
    if type(itemType) == "string" and type(itemSubType) == "string" then
        local haystack = string.lower(itemType .. "|" .. itemSubType)
        if haystack:find("herb", 1, true) or haystack:find("herbe", 1, true) then
            return "herbs"
        end
        if haystack:find("metal", 1, true) or haystack:find("stone", 1, true)
            or haystack:find("métal", 1, true) or haystack:find("pierre", 1, true)
            or haystack:find("ore", 1, true) or haystack:find("minerai", 1, true) then
            return "ore"
        end
        if haystack:find("fish", 1, true) or haystack:find("poisson", 1, true) then
            return "fish"
        end
        if haystack:find("leather", 1, true) or haystack:find("cuir", 1, true)
            or haystack:find("hide", 1, true) or haystack:find("peau", 1, true)
            or haystack:find("scale", 1, true) or haystack:find("écaille", 1, true)
            or haystack:find("bone", 1, true) or haystack:find("os", 1, true) then
            return "leather"
        end
    end

    if classID and subClassID then
        local classMap = UGC.SUBCLASS_MAP[classID]
        if classMap and classMap[subClassID] then
            return classMap[subClassID]
        end
    end

    return nil
end

function Compat:GetReagentQuality(itemID)
    if C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
        return SafeCall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, itemID)
    end
    return nil
end
