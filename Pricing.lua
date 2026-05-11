-------------------------------------------------------------------------------
-- Pricing.lua
-- Auction price provider abstraction.
-- Supports Auctionator first, then TradeSkillMaster (TSM) as a fallback.
-------------------------------------------------------------------------------

local UGC = _G.UGC

UGC.Pricing = {}
local Pricing = UGC.Pricing

local TSM_PRICE_SOURCE = "dbmarket"

local function NormalizePrice(price)
    if type(price) ~= "number" or price <= 0 then
        return nil
    end
    return math.floor(price + 0.5)
end

local function GetAuctionatorPrice(itemID)
    if not UGC.Compat:IsAddOnLoaded("Auctionator") then return nil end
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return nil
    end

    local ok, price = pcall(
        Auctionator.API.v1.GetAuctionPriceByItemID,
        UGC.ADDON_NAME, itemID
    )
    if not ok then return nil end
    return NormalizePrice(price)
end

local function GetTSMItemString(itemID)
    local itemString = "i:" .. tostring(itemID)

    if TSM_API and type(TSM_API.ToItemString) == "function" then
        local ok, converted = pcall(TSM_API.ToItemString, itemString)
        if ok and converted then
            return converted
        end
    end

    return itemString
end

local function GetTSMPrice(itemID)
    if not UGC.Compat:IsAddOnLoaded("TradeSkillMaster") then return nil end
    if not TSM_API or type(TSM_API.GetCustomPriceValue) ~= "function" then
        return nil
    end

    local itemString = GetTSMItemString(itemID)
    local ok, price = pcall(TSM_API.GetCustomPriceValue, TSM_PRICE_SOURCE, itemString)
    if not ok then return nil end
    return NormalizePrice(price)
end

function Pricing:GetAuctionPrice(itemID)
    return GetAuctionatorPrice(itemID) or GetTSMPrice(itemID)
end

function Pricing:GetProviderStatusText()
    local hasAuctionator = UGC.Compat:IsAddOnLoaded("Auctionator")
    local hasTSM = UGC.Compat:IsAddOnLoaded("TradeSkillMaster")

    if hasAuctionator and hasTSM then
        return "|cff33E633Auctionator and TSM detected.|r Auctionator prices are used first, with TSM dbmarket as fallback."
    elseif hasAuctionator then
        return "|cff33E633Auctionator detected.|r Price data is available."
    elseif hasTSM then
        return "|cff33E633TSM detected.|r Price data is available from dbmarket."
    end

    return "|cffff8800Auctionator or TSM not loaded.|r Values will show as \"?\"."
end

function Pricing:HasPriceProvider()
    return UGC.Compat:IsAddOnLoaded("Auctionator") or UGC.Compat:IsAddOnLoaded("TradeSkillMaster")
end
