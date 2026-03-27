-------------------------------------------------------------------------------
-- Core.lua
-- Main event frame. Wires together all modules, handles WoW events, and
-- registers the /ugc slash command. Must load last (see .toc order).
-------------------------------------------------------------------------------

local UGC = _G.UGC

local eventFrame = CreateFrame("Frame", "UGC_CoreFrame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

-------------------------------------------------------------------------------
-- Event dispatcher
-------------------------------------------------------------------------------
eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" then
        -- Initialise database as soon as our SavedVariables are available
        if arg1 == UGC.ADDON_NAME then
            UGC.DB:Init()
        end

    elseif event == "PLAYER_LOGIN" then
        -- All saved variables are fully loaded at this point
        UGC.Tracker:Init()
        UGC.Overlay:Init()
        if UGC.Creatures then
            UGC.Creatures:Init()
        end
        UGC.Details:Init()
        UGC.Config:Init()
        if UGC.Community then
            UGC.Community:Init()
        end

        print(string.format(
            "|cff33E633Ultimate Gathering Counter|r v%s loaded.  "
            .. "Type |cffffd700/ugc help|r for commands.",
            UGC.VERSION))

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-baseline bags after loading screens/reloads so existing bag contents
        -- are not miscounted as newly gathered items.
        if UGC.Tracker and UGC.Session and UGC.Session.startTime > 0 then
            local isInitialLogin = arg1
            local isReloadingUi  = ...
            UGC.Tracker:RebaselineBags(not (isInitialLogin or isReloadingUi))
            if UGC.Overlay and UGC.Overlay.frame then
                UGC.Overlay:Refresh()
            end
            if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
                UGC.Details:Refresh()
            end
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        UGC.Tracker:ScanBags()
        if UGC.Overlay and UGC.Overlay.frame then
            UGC.Overlay:Refresh()
        end
        -- Propagate to Details if it's open
        if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
            UGC.Details:Refresh()
        end

    elseif event == "CHAT_MSG_LOOT" then
        UGC.Tracker:ParseLootMessage(arg1)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = arg1, ...
        if UGC.Community then
            UGC.Community:OnAddonMessage(prefix, message, channel, sender)
        end

    elseif event == "PLAYER_LOGOUT" then
        if UGC.Overlay then
            UGC.Overlay:SavePosition()
        end
    end
end)

-------------------------------------------------------------------------------
-- /ugc slash command
-------------------------------------------------------------------------------
SLASH_UGC1 = "/ugc"
SLASH_UGC2 = "/ultimategatheringcounter"

SlashCmdList["UGC"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "" then
        UGC.Overlay:Toggle()

    elseif cmd == "show" then
        UGC.Overlay:Show()
        print("|cff33E633UGC:|r Overlay shown.")

    elseif cmd == "hide" then
        UGC.Overlay:Hide()
        print("|cff33E633UGC:|r Overlay hidden. Type /ugc to show again.")

    elseif cmd == "config" or cmd == "options" or cmd == "settings" then
        UGC.Config:Toggle()

    elseif cmd == "details" or cmd == "stats" or cmd == "history" or cmd == "classement" or cmd == "leaderboard" then
        UGC.Details:Toggle()

    elseif cmd == "reset" then
        UGC.Tracker:ResetSession()
        if UGC.Overlay then UGC.Overlay:Refresh() end
        if UGC.Details and UGC.Details.frame and UGC.Details.frame:IsShown() then
            UGC.Details:Refresh()
        end
        print("|cff33E633UGC:|r Session data has been reset.")

    elseif cmd == "version" then
        print("|cff33E633Ultimate Gathering Counter|r v" .. UGC.VERSION)

    elseif cmd == "help" then
        print("|cff33E633————— Ultimate Gathering Counter " .. UGC.VERSION .. " —————|r")
        print("|cffffd700/ugc|r               Toggle main overlay")
        print("|cffffd700/ugc show|r           Show overlay")
        print("|cffffd700/ugc hide|r           Hide overlay")
        print("|cffffd700/ugc details|r        Open statistics window")
        print("|cffffd700/ugc config|r         Open settings panel")
        print("|cffffd700/ugc leaderboard|r    Open community leaderboard tab")
        print("|cffffd700/ugc reset|r          Reset current session counters")
        print("|cffffd700/ugc help|r           Show this help")
        if UGC.Compat:IsAddOnLoaded("Auctionator") then
            print("|cff33E633Auctionator|r detected — price data available.")
        else
            print("|cffff8800Auctionator|r not loaded — values will show as \"?\".")
        end

    else
        print("|cff33E633UGC:|r Unknown command: \"" .. cmd
              .. "\". Type |cffffd700/ugc help|r for available commands.")
    end
end
