-------------------------------------------------------------------------------
-- Data.lua
-- Creates the UGC global namespace and populates the item database.
-- Must load first (see .toc order).
-------------------------------------------------------------------------------

local UGC = {}
_G.UGC = UGC

UGC.ADDON_NAME = "UltimateGatheringCounter"
UGC.VERSION    = "1.0.0"

UGC.API = {}
local API = UGC.API

-------------------------------------------------------------------------------
-- Compatibility helpers for Retail / MoP Classic / Cata Classic / Wrath /
-- Burning Crusade Classic / Classic Era clients.
-------------------------------------------------------------------------------
function API:GetServerTime()
    if type(GetServerTime) == "function" then
        return GetServerTime()
    end
    return time()
end

function API:IsAddOnLoaded(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addonName)
    end
    return IsAddOnLoaded(addonName)
end

function API:SetTextureColor(texture, r, g, b, a)
    if not texture then return end
    if texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, a or 1)
    else
        texture:SetTexture(r, g, b, a or 1)
    end
end

function API:CreateFrame(frameType, name, parent, template)
    if template == "BackdropTemplate" and not BackdropTemplateMixin then
        template = nil
    end
    return CreateFrame(frameType, name, parent, template)
end

function API:SetResizeBounds(frame, minWidth, minHeight, maxWidth, maxHeight)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    else
        frame:SetMinResize(minWidth, minHeight)
        if maxWidth or maxHeight then
            frame:SetMaxResize(maxWidth or 10000, maxHeight or 10000)
        end
    end
end

function API:CreateQualityStars(parent, anchorTo, count, size, spacing, texturePath)
    local stars = {}
    local canMask = parent.CreateMaskTexture and texturePath and type(texturePath) == "string"

    for i = 1, count do
        local star = parent:CreateTexture(nil, "OVERLAY")
        star:SetSize(size, size)

        if canMask then
            star:SetTexture("Interface\\Buttons\\WHITE8X8")
            star:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT", (i - 1) * spacing, 0)

            local mask = parent:CreateMaskTexture()
            mask:SetTexture(texturePath, "CLAMPTOBLACK", "CLAMPTOBLACK")
            mask:SetSize(size, size)
            mask:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT", (i - 1) * spacing, 0)
            star:AddMaskTexture(mask)
            star._ugcMask = mask
        else
            star:SetTexture("Interface\\COMMON\\Indicator-Yellow")
            star:SetTexCoord(0.2, 0.8, 0.2, 0.8)
            star:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT", (i - 1) * spacing, 0)
        end

        star:Hide()
        stars[i] = star
    end

    return stars
end

-- Category definitions
UGC.CATEGORIES = {
    herbs   = { key = "herbs",   label = "Herbs",   color = { r = 0.2, g = 0.9, b = 0.2 }, hex = "33E633" },
    ore     = { key = "ore",     label = "Ore",     color = { r = 1.0, g = 0.8, b = 0.0 }, hex = "FFCC00" },
    fish    = { key = "fish",    label = "Fish",    color = { r = 0.3, g = 0.7, b = 1.0 }, hex = "4DB3FF" },
    leather = { key = "leather", label = "Leather", color = { r = 0.8, g = 0.5, b = 0.2 }, hex = "CC8033" },
}

-- Display order for categories
UGC.CATEGORY_ORDER = { "herbs", "ore", "fish", "leather" }

-- Dynamic detection: itemClassID -> subClassID -> categoryKey
-- classID 7 = Trade Goods / Reagent, classID 2 = Consumable
UGC.SUBCLASS_MAP = {
    [7] = {
        [7]  = "ore",      -- Metal & Stone
        [8]  = "leather",  -- Leather
        [9]  = "herbs",    -- Herb
        [18] = "leather",  -- Misc / skinning byproducts
    },
    [2] = {
        [47] = "fish",     -- Fish (Consumable subtype)
    },
}

-- Item database: [itemID] = { category = string, hint = string }
-- "hint" is a fallback display name used only before GetItemInfo resolves.
UGC.ITEM_DB = {}

local function addItems(category, tbl)
    for id, name in pairs(tbl) do
        UGC.ITEM_DB[id] = { category = category, hint = name }
    end
end

-------------------------------------------------------------------------------
-- HERBS
-------------------------------------------------------------------------------
addItems("herbs", {
    -- Classic / Vanilla
    [765]    = "Silverleaf",
    [785]    = "Mageroyal",
    [2447]   = "Peacebloom",
    [2449]   = "Earthroot",
    [2450]   = "Briarthorn",
    [2452]   = "Swiftthistle",
    [2453]   = "Bruiseweed",
    [3355]   = "Wild Steelbloom",
    [3356]   = "Kingsblood",
    [3357]   = "Liferoot",
    [3358]   = "Khadgar's Whisker",
    [3369]   = "Grave Moss",
    [3818]   = "Fadeleaf",
    [3819]   = "Dragon's Teeth",
    [3821]   = "Goldthorn",
    [3820]   = "Stranglekelp",
    [4625]   = "Firebloom",
    [8153]   = "Wildvine",
    [8831]   = "Purple Lotus",
    [8836]   = "Arthas' Tears",
    [8838]   = "Sungrass",
    [8839]   = "Blindweed",
    [8845]   = "Ghost Mushroom",
    [8846]   = "Gromsblood",
    [13463]  = "Sorrowmoss",
    [13464]  = "Golden Sansam",
    [13465]  = "Dreamfoil",
    [13466]  = "Mountain Silversage",
    [13467]  = "Plaguebloom",
    [13468]  = "Icecap",
    [13469]  = "Black Lotus",
    -- TBC
    [22785]  = "Felweed",
    [22786]  = "Dreaming Glory",
    [22787]  = "Ragveil",
    [22789]  = "Terocone",
    [22790]  = "Ancient Lichen",
    [22791]  = "Netherbloom",
    [22792]  = "Nightmare Vine",
    [22793]  = "Mana Thistle",
    -- WotLK
    [36901]  = "Goldclover",
    [36903]  = "Tiger Lily",
    [36904]  = "Talandra's Rose",
    [36905]  = "Lichbloom",
    [36906]  = "Icethorn",
    [36907]  = "Deadnettle",
    [37921]  = "Adder's Tongue",
    [39970]  = "Fire Leaf",
    -- Cataclysm
    [52983]  = "Azshara's Veil",
    [52984]  = "Stormvine",
    [52985]  = "Cinderbloom",
    [52986]  = "Heartblossom",
    [52987]  = "Whiptail",
    [52988]  = "Twilight Jasmine",
    -- MoP
    [72234]  = "Green Tea Leaf",
    [72235]  = "Silkweed",
    [72237]  = "Snow Lily",
    [79010]  = "Rain Poppy",
    [79011]  = "Fool's Cap",
    [89639]  = "Golden Lotus",
    -- WoD
    [109124] = "Frostweed",
    [109125] = "Gorgrond Flytrap",
    [109126] = "Talador Orchid",
    [109127] = "Starflower",
    [109128] = "Fireweed",
    [109129] = "Nagrand Arrowbloom",
    -- Legion
    [124101] = "Aethril",
    [124102] = "Dreamleaf",
    [124103] = "Foxflower",
    [124104] = "Fjarnskaggl",
    [124105] = "Starlight Rose",
    [128304] = "Felwort",
    -- BfA
    [152505] = "Anchor Weed",
    [152506] = "Sea Stalk",
    [152507] = "Siren's Pollen",
    [152508] = "Riverbud",
    [152509] = "Winter's Kiss",
    [152510] = "Akunda's Bite",
    -- Shadowlands
    [168583] = "Marrowroot",
    [168584] = "Rising Glory",
    [168585] = "Vigil's Torch",
    [168586] = "Widowbloom",
    [168589] = "Death Blossom",
    [169701] = "Night Shade",
    -- Dragonflight
    [190316] = "Hochenblume",
    [190317] = "Saxifrage",
    [190318] = "Bubble Poppy",
    [190319] = "Writhebark",
    [190320] = "Thunderbloom",
    [190321] = "Abyssal Bloom",
    -- The War Within
    [210775] = "Luredrop",
    [210776] = "Blessing Blossom",
    [224965] = "Ironcap Mushroom",
    [224966] = "Arathor's Spear",
    [224967] = "Galesong Orchid",
    -- Midnight (placeholder IDs — auto-detected via subclass map when encountered)
})

-------------------------------------------------------------------------------
-- ORE
-------------------------------------------------------------------------------
addItems("ore", {
    -- Classic
    [2770]   = "Copper Ore",
    [2771]   = "Tin Ore",
    [2772]   = "Iron Ore",
    [3858]   = "Mithril Ore",
    [7911]   = "Truesilver Ore",
    [10620]  = "Thorium Ore",
    [11370]  = "Dark Iron Ore",
    -- TBC
    [23424]  = "Fel Iron Ore",
    [23425]  = "Adamantite Ore",
    [23426]  = "Eternium Ore",
    [23427]  = "Khorium Ore",
    -- WotLK
    [36909]  = "Cobalt Ore",
    [36910]  = "Titanium Ore",
    [36912]  = "Saronite Ore",
    -- Cataclysm
    [52183]  = "Obsidium Ore",
    [52185]  = "Elementium Ore",
    [52186]  = "Pyrite Ore",
    -- MoP
    [72092]  = "Ghost Iron Ore",
    [72093]  = "Kyparite",
    [72103]  = "White Trillium Ore",
    [72104]  = "Black Trillium Ore",
    -- WoD
    [109103] = "True Iron Ore",
    [109104] = "Blackrock Ore",
    -- Legion
    [123918] = "Felslate",
    [123919] = "Leystone Ore",
    -- BfA
    [152512] = "Storm Silver Ore",
    [152513] = "Monelite Ore",
    [152579] = "Platinum Ore",
    -- Shadowlands
    [171828] = "Oxxein Ore",
    [171829] = "Solenium Ore",
    [171830] = "Sinvyr Ore",
    [171831] = "Elethium Ore",
    [171832] = "Phaedrum Ore",
    [171833] = "Laestrite Ore",
    -- Dragonflight
    [188658] = "Serevite Ore",
    [188659] = "Draconium Ore",
    [190394] = "Khaz'gorite Ore",
    -- The War Within
    [210814] = "Ironclaw Ore",
    [224854] = "Bismuth Ore",
    [224855] = "Null Stone",
})

-------------------------------------------------------------------------------
-- FISH
-------------------------------------------------------------------------------
addItems("fish", {
    -- Classic
    [6291]   = "Raw Bristle Whisker Catfish",
    [6300]   = "Raw Mithril Head Trout",
    [6302]   = "Raw Slitherskin Mackerel",
    [6303]   = "Raw Longjaw Mud Snapper",
    [6308]   = "Raw Brilliant Smallfish",
    [6317]   = "Raw Loch Frenzy",
    [6318]   = "Oily Blackmouth",
    [6360]   = "Steelscale Crushfish",
    [6358]   = "Firefin Snapper",
    [6361]   = "Raw Rainbow Fin Albacore",
    [6362]   = "Raw Rockscale Cod",
    [6363]   = "Raw Whitescale Salmon",
    [6364]   = "Raw Greater Sagefish",
    [13754]  = "Raw Glossy Mightfish",
    [13755]  = "Winter Squid",
    [13756]  = "Raw Summer Bass",
    [13757]  = "Lightning Eel",
    [13758]  = "Raw Redgill",
    [13759]  = "Raw Nightfin Snapper",
    [13760]  = "Raw Sunscale Salmon",
    [13888]  = "Darkclaw Lobster",
    [13889]  = "Raw Whitescale Salmon",
    [13893]  = "Large Raw Mightfish",
    [13894]  = "Raw Greater Sagefish",
    [21153]  = "Raw Sagefish",
    [21154]  = "Raw Greater Sagefish",
    [6522]   = "Deviate Fish",
    -- TBC
    [27422]  = "Barbed Gill Trout",
    [27425]  = "Spotted Feltail",
    [27429]  = "Zangarian Sporefish",
    [27435]  = "Figluster's Mudfish",
    [27437]  = "Icefin Bluefish",
    [27438]  = "Golden Darter",
    [34861]  = "Furious Crawdad",
    -- WotLK
    [41800]  = "Deep Sea Monsterbelly",
    [41801]  = "Moonglow Cuttlefish",
    [41802]  = "Imperial Manta Ray",
    [41803]  = "Rockfin Grouper",
    [41805]  = "Nettlefish",
    [41806]  = "Glassfin Minnow",
    [43568]  = "Fangtooth Herring",
    -- Cataclysm
    [53301]  = "Algaefin Rockfish",
    [53302]  = "Deepsea Sagefish",
    [53303]  = "Fathom Eel",
    [53304]  = "Highland Guppy",
    [53305]  = "Lavascale Catfish",
    -- MoP
    [74681]  = "Giant Mantis Shrimp",
    [74682]  = "Jade Lungfish",
    [74683]  = "Krasarang Paddlefish",
    [74684]  = "Redbelly Mandarin",
    [74685]  = "Reef Octopus",
    [74686]  = "Spinefish",
    -- WoD
    [111828] = "Blind Lake Sturgeon",
    [111829] = "Fat Sleeper",
    [111830] = "Fire Ammonite",
    [111831] = "Frostdeep Minnow",
    [111832] = "Jawless Skulker",
    [111833] = "Sea Scorpion",
    -- Legion
    [133556] = "Cursed Queenfish",
    [133557] = "Highmountain Salmon",
    [133558] = "Mossgill Perch",
    [133559] = "Runescale Koi",
    [133560] = "Silver Mackerel",
    [133561] = "Stormray",
    -- BfA
    [162522] = "Redtail Loach",
    [162523] = "Frenzied Fangtooth",
    [162524] = "Lane Snapper",
    [162525] = "Tiragarde Perch",
    [162527] = "Great Sea Catfish",
    -- Shadowlands
    [173033] = "Lost Sole",
    [173034] = "Riftmouth Snapper",
    [173035] = "Elysian Thade",
    [173036] = "Pocked Bonefish",
    -- Dragonflight
    [194963] = "Aileron Seamoth",
    [194964] = "Cerulean Spinefish",
    [194965] = "Islefin Dorado",
    [194966] = "Temporal Dragonhead",
    [194967] = "Thousandbite Piranha",
    -- The War Within
    [210815] = "Gloaming Cavefish",
    [224857] = "Deep Void Eel",
    [224858] = "Earthen Carp",
})

-------------------------------------------------------------------------------
-- LEATHER / SKINS
-------------------------------------------------------------------------------
addItems("leather", {
    -- Classic
    [783]    = "Light Hide",
    [2318]   = "Light Leather",
    [2319]   = "Medium Leather",
    [4232]   = "Medium Hide",
    [4234]   = "Heavy Leather",
    [4235]   = "Heavy Hide",
    [4304]   = "Thick Leather",
    [8169]   = "Thick Hide",
    [8170]   = "Rugged Leather",
    [8171]   = "Rugged Hide",
    [15408]  = "Heavy Scorpid Scale",
    [15410]  = "Scale of Onyxia",
    [15412]  = "Green Dragonscale",
    [15414]  = "Red Dragonscale",
    [15415]  = "Blue Dragonscale",
    [15416]  = "Black Dragonscale",
    [17012]  = "Core Leather",
    -- TBC
    [25649]  = "Knothide Leather",
    [25650]  = "Knothide Leather Scraps",
    [25699]  = "Crystallized Fel Scales",
    [25700]  = "Fel Scales",
    [33567]  = "Wind Scales",
    [33568]  = "Cobra Scales",
    -- WotLK
    [38425]  = "Borean Leather",
    [38426]  = "Borean Leather Scraps",
    [44128]  = "Heavy Borean Leather",
    [44205]  = "Arctic Fur",
    -- Cataclysm
    [52976]  = "Savage Leather",
    [52977]  = "Savage Leather Scraps",
    [52980]  = "Pristine Hide",
    [67557]  = "Blackened Dragonscale",
    -- MoP
    [72437]  = "Exotic Leather",
    [72438]  = "Sha-Touched Leather",
    [72439]  = "Magnificent Hide",
    [94113]  = "Prismatic Scale",
    -- WoD
    [110611] = "Raw Beast Hide",
    [110612] = "Raw Beast Hide Scraps",
    [111556] = "Burnished Leather",
    -- Legion
    [134954] = "Stormscale",
    [134955] = "Stonehide Leather",
    [151568] = "Fiendish Leather",
    -- BfA
    [152542] = "Coarse Leather",
    [152543] = "Coarse Leather Scraps",
    [152544] = "Shimmerscale",
    [152545] = "Tempest Hide",
    -- Shadowlands
    [172057] = "Pallid Bone",
    [172058] = "Heavy Callous Hide",
    [172059] = "Desolate Leather",
    [172060] = "Thick Murid Leather",
    -- Dragonflight
    [193230] = "Adamant Scales",
    [193231] = "Robust Fur",
    [193232] = "Resilient Leather",
    [193233] = "Flashfrozen Fur",
    [201746] = "Rockfang Leather",
    -- The War Within
    [210816] = "Hollow Carapace",
    [224859] = "Void-Touched Hide",
    [224860] = "Earthen Scale",
})
