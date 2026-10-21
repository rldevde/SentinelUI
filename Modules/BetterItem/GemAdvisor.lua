local addon = RLBetterItem

-- ==================== GEM ADVISOR ===================================
-- when the socketing window is open, every socket shows the best gem
-- stat for the active scale ("→ Kritwertung")

local SOCK_KEY = {
    Red = "SocketRed",
    Yellow = "SocketYellow",
    Blue = "SocketBlue",
    Meta = "SocketMeta",
    Hydraulic = "SocketAny", -- Cata+ "cogwheel"-ish sockets: any gem
    Prismatic = "SocketAny",
}

local function UpdateSockets()
    for i = 1, (MAX_NUM_SOCKETS or 3) do
        local btn = _G["ItemSocketingSocket" .. i]
        if not btn then break end
        local fs = btn.rlGemHint
        local show = addon.initialized and addon.db and addon.db.gemAdvisor
            and ItemSocketingFrame and ItemSocketingFrame:IsShown()
        local sockType = show and GetSocketTypes and GetSocketTypes(i)
        local sockKey = sockType and SOCK_KEY[sockType]
        local label
        if sockKey then
            local gemID, stat = addon:GetBestGemID(sockKey,
                addon:GetActiveScaleKey())
            local name = gemID and GetItemInfo and (GetItemInfo(gemID))
            label = name or (stat and addon.StatName(stat))
            if not label and gemID then label = "#" .. gemID end
        end
        if label then
            if not fs then
                fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("TOP", btn, "BOTTOM", 0, -2)
                btn.rlGemHint = fs
            end
            fs:SetText("|cff00ff00→ " .. label .. "|r")
            fs:Show()
        elseif fs then
            fs:Hide()
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("SOCKET_INFO_UPDATE")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == "Blizzard_ItemSocketingUI" and ItemSocketingFrame then
            ItemSocketingFrame:HookScript("OnShow", UpdateSockets)
        end
    else
        UpdateSockets()
    end
end)
-- socketing UI may already be loaded
if ItemSocketingFrame then
    ItemSocketingFrame:HookScript("OnShow", UpdateSockets)
end
