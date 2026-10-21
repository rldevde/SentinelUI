local addon = RLBetterItem

-- ==================== QUEST REWARD MARKERS ==========================
-- green check on quest rewards that are upgrades + vendor price on
-- every reward, the most valuable *choice* item gets a golden border

local function RewardLink(button)
    if button.itemLink then return button.itemLink end
    local t = button.type -- "choice" or "reward" ("spell" etc. yield nil links)
    local idx = (button.GetID and button:GetID()) or button.index
    if t and idx and GetQuestItemLink then
        local ok, link = pcall(GetQuestItemLink, t, idx)
        if ok and link then return link end
    end
    return nil
end

local function MoneyStr(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return string.format("%dg %ds", g, s) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return c .. "c"
end

local function CheckButton(button)
    local link = RewardLink(button)
    addon:SetUpgradeIcon(button, link and addon:IsBagUpgrade(link))

    -- upgrade percentage of this reward (nil when not comparable)
    local pct
    if link then
        local score, baseline = addon:GetUpgradeInfo(link)
        if score then
            pct = (baseline and baseline > 0)
                and ((score - baseline) / baseline * 100)
                or math.huge -- empty slot = always an upgrade
        end
    end

    -- vendor price under the button
    local fs = button.rlPriceText
    local price = link and select(11, GetItemInfo(link)) or 0
    if not link or price <= 0 then
        if fs then fs:Hide() end
        return nil, button.type == "choice", pct
    end
    if not fs then
        fs = button:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        fs:SetPoint("TOP", button, "BOTTOM", 0, -1)
        button.rlPriceText = fs
    end
    fs:SetText("|cffdddddd" .. MoneyStr(price) .. "|r")
    fs:Show()
    return price, button.type == "choice", pct
end

-- colored border on the recommended choice reward
local function Border(button, key, r, g, b)
    local tex = button[key]
    if not tex then
        tex = button:CreateTexture(nil, "OVERLAY", nil, 3)
        tex:SetAllPoints()
        tex:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        button[key] = tex
    end
    tex:SetVertexColor(r, g, b)
    tex:Show()
end

local function GoldBorder(button)
    Border(button, "rlGoldBorder", 1, 0.82, 0)
end

local function GreenBorder(button)
    Border(button, "rlGreenBorder", 0.1, 1, 0.1)
end

local function HideGoldBorder(button)
    if button.rlGoldBorder then button.rlGoldBorder:Hide() end
    if button.rlGreenBorder then button.rlGreenBorder:Hide() end
end

local function Refresh()
    if not addon.initialized or not addon.db or not addon.db.questMarkers then return end

    local buttons = {}
    -- classic quest info buttons
    for i = 1, 12 do
        local b = _G["QuestInfoItem" .. i]
        if not b then break end
        if b:IsShown() then buttons[#buttons + 1] = b end
    end
    -- modern pooled reward buttons
    local qrf = _G["QuestInfoRewardsFrame"]
    if qrf and qrf.ItemButtons then
        for _, b in pairs(qrf.ItemButtons) do
            if b and b.IsShown and b:IsShown() then buttons[#buttons + 1] = b end
        end
    end

    local bestUpBtn, bestUpPct, bestBtn, bestPrice
    for _, b in ipairs(buttons) do
        HideGoldBorder(b)
        local price, isChoice, pct = CheckButton(b)
        if isChoice then
            if pct and pct > 0 and (not bestUpPct or pct > bestUpPct) then
                bestUpBtn, bestUpPct = b, pct
            end
            if price and (not bestPrice or price > bestPrice) then
                bestBtn, bestPrice = b, price
            end
        end
    end
    -- recommendation: a real upgrade beats vendor value; only when no
    -- reward upgrades us does the highest price get the gold frame
    if bestUpBtn then
        GreenBorder(bestUpBtn)
        if bestUpBtn.rlPriceText then
            local price = select(11, GetItemInfo(RewardLink(bestUpBtn))) or 0
            local tag = bestUpPct ~= math.huge
                and ("+" .. string.format("%.0f", bestUpPct) .. "% ")
                or ""
            bestUpBtn.rlPriceText:SetText("|cff00ff00▲ " .. tag ..
                MoneyStr(price) .. "|r")
        end
    elseif bestBtn then
        GoldBorder(bestBtn)
        -- mark the price text gold as well
        if bestBtn.rlPriceText then
            local price = select(11, GetItemInfo(RewardLink(bestBtn))) or 0
            bestBtn.rlPriceText:SetText("|cffffd700" .. MoneyStr(price) .. "|r")
        end
    end
end
addon.RefreshQuestRewards = Refresh

local f = CreateFrame("Frame")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("QUEST_ITEM_UPDATE")
f:RegisterEvent("QUEST_PROGRESS")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, Refresh) -- rewards fill in asynchronously
    else
        Refresh()
    end
end)

-- polling fallback while a quest turn-in window is open
local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < 0.5 then return end
    elapsed = 0
    local panel = _G["QuestFrameRewardPanel"] or _G["QuestFrameDetailPanel"]
        or _G["QuestFrameProgressPanel"] or _G["QuestFrame"]
    if panel and panel.IsShown and panel:IsShown() then Refresh() end
end)
