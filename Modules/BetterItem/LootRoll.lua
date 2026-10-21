local addon = RLBetterItem

-- ==================== GROUP LOOT ROLL HINT ====================
-- "▲ +34%" on the roll frame plus colored Need/Greed/Pass buttons
local function MoneyStr(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    if g > 0 then return string.format("%dg %ds", g, s) end
    if s > 0 then return s .. "s" end
    return copper .. "c"
end

local function Tint(btn, r, g, b)
    if not btn then return end
    if not btn.rlTint then
        btn.rlTint = btn:CreateTexture(nil, "BACKGROUND")
        btn.rlTint:SetAllPoints()
        btn.rlTint:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    end
    if r then
        btn.rlTint:SetVertexColor(r, g, b)
        btn.rlTint:Show()
    else
        btn.rlTint:Hide()
    end
end

local function TintRollButtons(frame, state)
    if not (addon.db and addon.db.rollButtonColors) then state = nil end
    local name = frame.GetName and frame:GetName()
    local need  = frame.NeedButton  or (name and _G[name .. "NeedButton"])
    local greed = frame.GreedButton or (name and _G[name .. "GreedButton"])
    local pass  = frame.PassButton  or (name and _G[name .. "PassButton"])
    local de    = frame.DisenchantButton
        or (name and _G[name .. "DisenchantButton"])
    if state == "up" then
        Tint(need, 0, 1, 0)        -- need it!
        Tint(greed)
        Tint(pass, 1, 0.3, 0.3)
        Tint(de)
    elseif state == "down" then
        Tint(need, 1, 0.3, 0.3)
        Tint(greed, 0.9, 0.65, 0)  -- vendor/disenchant material
        Tint(pass, 0, 1, 0)
        Tint(de, 0.7, 0.4, 1)      -- purple: disenchant me
    else
        Tint(need); Tint(greed); Tint(pass); Tint(de)
    end
end

local function UpdateRollFrame(frame)
    if not frame then return end
    local fs = frame.rlRollHint

    local on = addon.initialized and addon.db and addon.db.lootRollHints
    if not on or not frame:IsShown() or not frame.rollID then
        if fs then fs:Hide() end
        TintRollButtons(frame, nil)
        return
    end

    local link = GetLootRollItemLink and GetLootRollItemLink(frame.rollID)
    if not link then
        if fs then fs:Hide() end
        TintRollButtons(frame, nil)
        return
    end

    local score, baseline = addon:GetUpgradeInfo(link)
    if not score then
        if fs then fs:Hide() end
        TintRollButtons(frame, nil)
        return
    end

    if not fs then
        fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", frame, "RIGHT", 4, 0)
        frame.rlRollHint = fs
    end

    -- second line: what the item is worth if you don't need it
    local fs2 = frame.rlRollHint2
    if not fs2 then
        fs2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs2:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -1)
        frame.rlRollHint2 = fs2
    end

    local pct
    if baseline and baseline > 0 then
        pct = (score - baseline) / baseline * 100
        if pct >= 0 then
            fs:SetText("|TInterface\\COMMON\\Indicator-Green:12|t |cff00ff00+" ..
                string.format("%.0f", pct) .. "%|r")
        else
            fs:SetText("|TInterface\\COMMON\\Indicator-Red:12|t |cffff4040" ..
                string.format("%.0f", pct) .. "%|r")
        end
        TintRollButtons(frame, pct >= 0 and "up" or "down")
    else
        fs:SetText("|TInterface\\COMMON\\Indicator-Green:12|t |cff00ff00" ..
            addon:L("TT_UPGRADE") .. "|r")
        TintRollButtons(frame, "up")
    end
    fs:Show()

    -- value hint on downgrades: disenchant result or vendor price
    if pct and pct < 0 then
        local de = addon.DisenchantPreview and addon:DisenchantPreview(link)
        local price = select(11, GetItemInfo(link)) or 0
        if de then
            fs2:SetText("|cffb67fff" .. addon:L("TT_DE") .. " " .. de .. "|r")
            fs2:Show()
        elseif price > 0 then
            fs2:SetText("|cff888888" .. MoneyStr(price) .. "|r")
            fs2:Show()
        else
            fs2:Hide()
        end
    else
        fs2:Hide()
    end
end

local function UpdateAllRollFrames()
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        UpdateRollFrame(_G["GroupLootFrame" .. i])
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("START_LOOT_ROLL")
f:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, UpdateAllRollFrames)
    else
        UpdateAllRollFrames()
    end
end)

-- polling fallback while any roll frame is visible
local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < 0.5 then return end
    elapsed = 0
    UpdateAllRollFrames()
end)
