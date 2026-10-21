local addon = RLBetterItem

-- ==================== EVENT FRAME ====================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
-- spec-change events only exist on newer clients; guard registration
pcall(eventFrame.RegisterEvent, eventFrame, "ACTIVE_TALENT_GROUP_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "SentinelUI" then
            -- merged into SentinelUI: the standalone copy would hook the same
            -- tooltips/events twice, so disable it once and warn
            local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
            local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
            if isLoaded and isLoaded("RLBetterItem") then
                if disable then disable("RLBetterItem") end
                print("|cffFFD700[SentinelUI]|r " .. addon:L("MSG_MERGED_NOTICE"))
            end
            local ok, err = pcall(function()
                addon:InitializeDB()
                addon:DetectScale()
                addon:CreateMinimapButton()
            end)
            if not ok then
                print("|cffff4040[SentinelUI]|r " .. addon:L("MSG_LOAD_ERROR") .. " " .. tostring(err))
            end
            addon.initialized = true
            addon:Print(addon:L("MSG_LOADED") .. addon.version)
            if not addon.GetItemStats then
                print("|cffff4040[SentinelUI]|r " .. addon:L("MSG_NO_ITEMSTATS"))
            end
        end
    elseif event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if addon.db and addon.db.autoDetect then
            local old = addon.detectedScale
            addon:DetectScale()
            if old ~= addon.detectedScale then
                addon:Debug("Detected scale changed to: " .. tostring(addon.detectedScale))
                if addon.RefreshSettings then addon:RefreshSettings() end
                if addon.ClearUpgradeCache then addon:ClearUpgradeCache() end
                if addon.AutoEquipForScale then addon:AutoEquipForScale() end
            end
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- equipped gear changed: cap context and baselines are stale
        if addon.ClearUpgradeCache then addon:ClearUpgradeCache() end
    end
end)

-- ==================== DIAGNOSTICS ====================
function addon:RunDiagnostics()
    self:Print("--- Diagnose ---")
    local apis = {
        "GetItemStats", "GetItemInfo", "GetItemInfoInstant",
        "GetCombatRating", "GetInventoryItemLink", "GetInventoryItemID",
        "GetTalentTabInfo", "CreateFrame", "hooksecurefunc",
    }
    for _, n in ipairs(apis) do
        print("  " .. n .. ": " .. (_G[n] and "|cff00ff00OK|r" or "|cffff4040FEHLT|r"))
    end
    print("  C_Item.GetItemStats: " .. ((C_Item and C_Item.GetItemStats) and "|cff00ff00OK|r" or "|cffff4040FEHLT|r"))
    print("  GetItemStats (aktiv): " .. (self.GetItemStats and "|cff00ff00OK|r" or "|cffff4040FEHLT|r"))
    print("  initialized: " .. tostring(self.initialized))
    print("  scale: " .. tostring(self:GetActiveScaleKey()))
    print("  db.showScore: " .. tostring(self.db and self.db.showScore))
    print("  db.showUpgrade: " .. tostring(self.db and self.db.showUpgrade))
    print("  TooltipDataProcessor: " .. (self.usedTooltipDataProcessor and "|cff00ff00AKTIV|r" or "|cffffff88alt (OnTooltipSetItem)|r"))

    -- test item: item under cursor, else Thunderfury
    local link
    if GameTooltip and GameTooltip:IsShown() then
        local _, l = GameTooltip:GetItem()
        link = l
    end
    if not link then link = "item:19019" end
    print("  Test-Item: " .. tostring(link))

    if self.GetItemStats then
        local ok, stats = pcall(self.GetItemStats, link)
        if ok and stats then
            local n = 0
            for k, v in pairs(stats) do
                n = n + 1
                print("    " .. tostring(k) .. " = " .. tostring(v))
            end
            print("  Stats gefunden: " .. n)
        else
            print("  |cffff4040GetItemStats lieferte nichts|r" .. (ok and "" or (" (" .. tostring(stats) .. ")")))
        end
        local ok2, score = pcall(self.GetItemScore, self, link, self:GetActiveScaleKey(), nil)
        print("  Score: " .. ((ok2 and score) and string.format("%.1f", score)
            or ("|cffff4040FEHLER: " .. tostring(ok2 and "nil" or score) .. "|r")))
    end

    local ok3, amounts = pcall(self.GetStatAmounts, self, link)
    if ok3 and amounts then
        local parts = {}
        for k, v in pairs(amounts) do table.insert(parts, k .. "=" .. v) end
        print("  ScanStats: " .. table.concat(parts, ", "))
    else
        print("  ScanStats: |cffff4040" .. tostring(amounts) .. "|r")
    end
end

-- ==================== SLASH COMMANDS ====================
SLASH_RLBETTERITEM1 = "/rlbi"
SLASH_RLBETTERITEM2 = "/rlbetteritem"
SlashCmdList["RLBETTERITEM"] = function(msg)
    msg = string.lower(msg or "")

    if msg == "debug" then
        addon.debugMode = not addon.debugMode
        addon:Print(addon.debugMode and addon:L("MSG_DEBUG_ON") or addon:L("MSG_DEBUG_OFF"))
    elseif msg == "log" or msg == "errors" then
        if addon.ShowErrorLog then addon:ShowErrorLog() end
    elseif msg == "bug" or msg == "bugs" or msg == "bugtracker" then
        if addon.ShowBugtracker then addon:ShowBugtracker() end
    elseif msg == "test" then
        addon:RunDiagnostics()
    elseif msg == "scale" then
        local key = addon:GetActiveScaleKey()
        local scale = addon:GetScale(key)
        addon:Print(addon:L("OPT_SCALE") .. " " .. addon:GetScaleName(scale) ..
            " (" .. tostring(key) .. ")")

    elseif msg == "caps" then
        -- how close the player is to each capped stat of the active scale
        local key = addon:GetActiveScaleKey()
        local scale = addon:GetScale(key)
        addon:Print(addon:L("MSG_CAPS"))
        local any = false
        for _, stat in ipairs({ "Hit", "SpellHit", "Expertise", "Defense" }) do
            local cap = addon:GetCap(key, stat)
            if cap and cap > 0 then
                any = true
                local cur = addon:GetPlayerRating(key, stat)
                local pct = math.min(100, cur / cap * 100)
                local color = cur >= cap and "|cff00ff00" or "|cffffff00"
                print("  " .. tostring(addon.StatName and addon.StatName(stat) or stat) ..
                    ": " .. color .. cur .. "/" .. cap .. " (" ..
                    string.format("%.0f", pct) .. "%)|r")
            end
        end
        if not any then print("  |cff888888-|r") end

    elseif msg == "weakest" then
        -- the 3 weakest equipped items
        local key = addon:GetActiveScaleKey()
        local list = {}
        for slotId = 1, 18 do
            if slotId ~= 4 then -- shirt never matters
                local link = GetInventoryItemLink("player", slotId)
                local score = link and addon:GetItemScore(link, key) or 0
                table.insert(list, { slot = slotId, link = link, score = score })
            end
        end
        table.sort(list, function(a, b) return a.score < b.score end)
        addon:Print(addon:L("MSG_WEAKEST"))
        for i = 1, math.min(3, #list) do
            local e = list[i]
            print("  " .. i .. ". " .. (e.link or ("|cff666666(slot " .. e.slot .. ")|r")) ..
                "  |cffffffff" .. string.format("%.1f", e.score) .. "|r")
        end

    elseif string.match(msg, "^compare") then
        -- /rlbi compare <link1> <link2>
        local links = {}
        for l in string.gmatch(msg, "(|c%x+|Hitem:[^|]+|h%[[^%]]-%]|h|r)") do
            table.insert(links, l)
        end
        if #links == 0 then
            for l in string.gmatch(msg, "(|Hitem:[^|]-|h%[[^%]]-%]|h)") do
                table.insert(links, l)
            end
        end
        if #links < 2 then
            addon:Print(addon:L("MSG_COMPARE_USAGE"))
        else
            local key = addon:GetActiveScaleKey()
            local s1 = addon:GetItemScore(links[1], key) or 0
            local s2 = addon:GetItemScore(links[2], key) or 0
            print("  " .. links[1] .. "  |cffffffff" .. string.format("%.1f", s1) .. "|r")
            print("  " .. links[2] .. "  |cffffffff" .. string.format("%.1f", s2) .. "|r")
            if s1 > 0 and s2 > 0 then
                local hi, lo = math.max(s1, s2), math.min(s1, s2)
                addon:Print(string.format("%s  %.1f%%", addon:L("MSG_BETTER"),
                    (hi - lo) / lo * 100))
            end
        end

    elseif string.match(msg, "^savescale%s+(.+)$") then
        local name = string.match(msg, "^savescale%s+(.+)$")
        local key = addon:SaveScaleLibrary(name)
        addon:Print(key and (addon:L("MSG_SCALE_SAVED") .. " " .. name)
            or "|cffff4040Fehler|r")

    elseif string.match(msg, "^delscale%s+(.+)$") then
        local name = string.match(msg, "^delscale%s+(.+)$")
        local key = "Custom_" .. name:gsub("[^%w]", "")
        addon:DeleteScaleLibrary(key)
        addon:Print(addon:L("MSG_SCALE_DELETED") .. " " .. name)

    elseif msg == "scales" then
        addon:Print(addon:L("MSG_SCALES"))
        for _, scale in ipairs(addon:GetScalesForClass(select(2, UnitClass("player")))) do
            print("  " .. addon:GetScaleName(scale) .. " (" .. scale.key .. ")")
        end

    elseif string.match(msg, "^share") then
        local channel = string.match(msg, "^share%s+(%a+)") or
            (IsInGuild and IsInGuild() and "GUILD") or
            (IsInGroup and IsInGroup() and "PARTY") or "SAY"
        channel = string.upper(channel)
        if SendChatMessage then
            SendChatMessage(addon:ExportWeights(), channel)
            addon:Print(addon:L("MSG_SHARED") .. " → " .. channel)
        end

    elseif msg == "panel" then
        addon.db.showStatPanel = not addon.db.showStatPanel
        addon:UpdateStatsPanelVisibility()
        addon:Print(addon:L("OPT_STAT_PANEL") .. " " ..
            (addon.db.showStatPanel and "|cff00ff00ON|r" or "|cffff4040OFF|r"))

    elseif string.match(msg, "^equip%s+(.+)$") then
        addon:EquipOutfit(string.match(msg, "^equip%s+(.+)$"))
    else
        if not addon.mainFrame then
            addon:CreateMainFrame()
        end
        if addon.mainFrame:IsShown() then
            addon.mainFrame:Hide()
        else
            addon.mainFrame:Show()
        end
    end
end
