local addon = RLBetterItem

-- ==================== VENDOR SELL BUTTON ====================
-- small button pinned to the open bag frame (Blizzard containers,
-- combined bags, third-party bag addons) that sells all items up to a
-- configurable max quality. Right-click cycles the quality.

local QUALITY_COLOR = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1.00, 1.00, 1.00 },
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
}
local QUALITY_KEY = {
    [0] = "QUALITY_GRAY", [1] = "QUALITY_WHITE",
    [2] = "QUALITY_GREEN", [3] = "QUALITY_BLUE",
}

local btn
local rbtn -- repair button (merchant only)

local function MaxQuality()
    return math.min(3, math.max(0, (addon.db and addon.db.sellQuality) or 0))
end

local function MoneyStr(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return c .. "c"
end

-- item classes that must NEVER be auto-sold at ANY quality
local NEVER_SELL_CLASS = {
    [0] = true,  -- Consumable: food, water, potions, poisons
    [1] = true,  -- Container: bags
    [3] = true,  -- Gem
    [5] = true,  -- Reagent: candles, ankhs, symbols
    [6] = true,  -- Projectile: arrows & bullets (thousands of white ammo!)
    [7] = true,  -- Tradeskill: crafting materials
    [9] = true,  -- Recipe: patterns, schematics, formulas
    [11] = true, -- Quiver / ammo pouch
    [12] = true, -- Quest
    [13] = true, -- Key
}

-- quality > gray: ONLY weapons (2) and armor (4) may be sold.
-- everything else above gray is gear-adjacent junk or worse.

-- specific items that must NEVER be sold regardless of class:
-- profession tools, hearthstone, fishing poles, enchanting rods
local NEVER_SELL_ID = {
    [6948] = true,   -- Hearthstone
    [2901] = true,   -- Mining Pick
    [5956] = true,   -- Blacksmith Hammer
    [7005] = true,   -- Skinning Knife
    [856] = true,    -- Herbalist's Spade
    [6219] = true,   -- Arclight Spanner
    [10498] = true,  -- Gyromatic Micro-Adjustor
    [20815] = true,  -- Jeweler's Kit
    [20824] = true,  -- Simple Grinder
    [15846] = true,  -- Salt Shaker
    [6218] = true,   -- Runed Copper Rod
    [6339] = true,   -- Runed Silver Rod
    [11128] = true,  -- Runed Golden Rod
    [11144] = true,  -- Runed Truesilver Rod
    [16207] = true,  -- Runed Arcanite Rod
    [22461] = true,  -- Runed Fel Iron Rod
    [22462] = true,  -- Runed Adamantite Rod
    [22463] = true,  -- Runed Eternium Rod
    [6256] = true,   -- Fishing Pole
    [6365] = true,   -- Strong Fishing Pole
    [12225] = true,  -- Blump Family Fishing Pole
    [6366] = true,   -- Darkwood Fishing Pole
    [6367] = true,   -- Big Iron Fishing Pole
    [19970] = true,  -- Arcanite Fishing Pole
    [25978] = true,  -- Seth's Graphite Fishing Pole
}

local function MaySell(quality, classID, id)
    if id and NEVER_SELL_ID[id] then return false end
    if NEVER_SELL_CLASS[classID] then return false end
    if quality == 0 then return true end -- gray = junk
    return classID == 2 or classID == 4
end

-- collect sellable items: quality <= setting, has sell price,
-- never materials/reagents/quest/profession tools/outfit-protected
local function CollectSellables()
    local items = {}
    local maxQ = MaxQuality()
    addon:ForEachBagItemLink(function(link, bag, slot)
        local _, _, quality, _, _, _, _, _, _, _, sellPrice, classID = GetItemInfo(link)
        quality = quality or 0
        sellPrice = sellPrice or 0
        if sellPrice <= 0 or quality > maxQ then return end
        local id = LinkToItemIDSafe(link)
        local outfitProtected = addon.db.protectOutfitItems and id
            and #addon:GetOutfitsForItemID(id) > 0
        if not outfitProtected and MaySell(quality, classID, id) then
            table.insert(items, { bag = bag, slot = slot, quality = quality, link = link })
        end
    end)
    return items
end

local function SellItems(items)
    local sell = (C_Container and C_Container.UseContainerItem) or UseContainerItem
    if not sell then return end
    local total = 0
    local log = (not addon.db or addon.db.sellLog ~= false) and {} or nil
    for _, it in ipairs(items) do
        total = total + (select(11, GetItemInfo(it.link)) or 0)
        if log then log[it.link] = (log[it.link] or 0) + 1 end
        sell(it.bag, it.slot)
    end
    addon:Print(string.format(addon:L("MSG_SOLD"), #items, MoneyStr(total)))
    -- receipt: one chat line per distinct item sold
    if log then
        for link, n in pairs(log) do
            addon:Print("   " .. link .. (n > 1 and (" ×" .. n) or ""))
        end
    end
end

StaticPopupDialogs["RLBI_SELL_CONFIRM"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    timeout = 0,
    hideOnEscape = true,
    whileDead = false,
    OnAccept = function()
        SellItems(addon._pendingSell or {})
        addon._pendingSell = nil
    end,
}

local function DoSell()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        addon:Print(addon:L("MSG_NO_MERCHANT"))
        return
    end
    local items = CollectSellables()
    if #items == 0 then
        addon:Print(addon:L("MSG_NOTHING_SOLD"))
        return
    end
    -- safety: items above gray need a confirmation
    local valuable = 0
    for _, it in ipairs(items) do
        if it.quality > 0 then valuable = valuable + 1 end
    end
    if valuable > 0 then
        addon._pendingSell = items
        StaticPopup_Show("RLBI_SELL_CONFIRM",
            string.format(addon:L("SELL_CONFIRM"), valuable))
        return
    end
    SellItems(items)
end

-- SentinelUI's own bag window first, then classic container frames
local BAG_HOSTS = {
    "SentinelUIBags", "SentinelUIBank", "ContainerFrameCombinedBags",
}

local bagsOpen = false

local function FindBagHost()
    -- merchant open: pin the button straight to the vendor window
    if MerchantFrame and MerchantFrame:IsShown() then
        return MerchantFrame, true
    end
    -- our own bag window / combined-bags frame
    for _, name in ipairs(BAG_HOSTS) do
        local f = _G[name]
        if f and f:IsShown() then return f end
    end
    -- classic container frames
    for i = 1, (NUM_CONTAINER_FRAMES or 6) do
        local f = _G["ContainerFrame" .. i]
        if f and f:IsShown() then return f end
    end
    -- last resort: any visible window that looks like a bag frame
    -- (catches unknown/custom bag frame names). UIParent children are
    -- not all frames (animation groups, regions): GetName can throw
    -- "bad self" on them, so the whole probe goes through pcall
    for _, f in ipairs({ UIParent:GetChildren() }) do
        local ok, n, shown = pcall(function()
            return f:GetName(), f:IsShown()
        end)
        if ok and n and shown
            and (n:find("ContainerFrame") or n:find("BagFrame")
                or n:find("BagsFrame") or n:find("InventoryFrame")) then
            return f
        end
    end
    return nil
end

local function RefreshButtonLook()
    if not btn then return end
    local q = MaxQuality()
    local c = QUALITY_COLOR[q]
    btn.icon:SetVertexColor(c[1], c[2], c[3])
end

local function UpdateButton()
    if not btn then return end
    if btn._dragging then return end -- never fight an active drag
    if not (addon.db and addon.db.sellButtonShow) then
        btn:Hide()
        return
    end
    -- user-dragged position wins over auto-docking
    local p = addon.db.sellBtnPoint
    if p then
        btn:SetParent(UIParent)
        btn:ClearAllPoints()
        btn:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        btn:SetFrameStrata("DIALOG")
        btn:SetFrameLevel(100)
        RefreshButtonLook()
        btn:Show()
        return
    end
    local host, isMerchant = FindBagHost()
    if host then
        if btn:GetParent() ~= host then
            btn:SetParent(host)
        end
        btn:ClearAllPoints()
        -- next to the close button on the merchant, top-right on bags
        btn:SetPoint("TOPRIGHT", host, "TOPRIGHT", isMerchant and -52 or -26, -4)
        -- must sit above every child of the host frame (some bag addons
        -- use high frame levels and would swallow the clicks)
        btn:SetFrameStrata("DIALOG")
        btn:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 0) + 100)
        btn:EnableMouse(true)
        RefreshButtonLook()
        btn:Show()
    elseif bagsOpen or (MerchantFrame and MerchantFrame:IsShown()) then
        -- no known bag frame found (custom UI): float on the right side
        -- of the screen so the user can grab and place it
        btn:SetParent(UIParent)
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", UIParent, "RIGHT", -90, 0)
        btn:SetFrameStrata("DIALOG")
        btn:SetFrameLevel(100)
        RefreshButtonLook()
        btn:Show()
    else
        btn:Hide()
    end
    -- repair button only while the merchant window is open (independent of the sell button)
    if rbtn then
        local show = MerchantFrame and MerchantFrame:IsShown()
        if show then
            rbtn:SetParent(UIParent)
            rbtn:SetFrameStrata("DIALOG")
            rbtn:SetFrameLevel(200)
            rbtn:ClearAllPoints()
            if btn and btn:IsShown() then
                rbtn:SetPoint("RIGHT", btn, "LEFT", -4, 0)
            else
                rbtn:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -52, -4)
            end
            rbtn:Show()
        else
            rbtn:Hide()
        end
    end
end

local function CreateButton()
    btn = CreateFrame("Button", "RLBetterItemSellButton", UIParent)
    btn:SetSize(22, 22)
    btn:Hide()
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    btn:SetScript("OnClick", function(_, button)
        if btn.dragged then
            btn.dragged = nil -- mouse released after a drag, not a click
            return
        end
        if button == "RightButton" then
            local q = (MaxQuality() + 1) % 4
            addon.db.sellQuality = q
            RefreshButtonLook()
            addon:Print(addon:L("SELL_QUALITY") .. " " .. addon:L(QUALITY_KEY[q]))
        elseif button == "MiddleButton" then
            addon.db.sellBtnPoint = nil -- back to auto-docking
            UpdateButton()
        else
            DoSell()
        end
    end)

    -- free-drag: detach from the docked frame, then move on UIParent
    btn:SetScript("OnDragStart", function(self)
        self.dragged = true
        self._dragging = true -- UpdateButton must not re-dock mid-drag
        local cx, cy = self:GetCenter()
        local scale = self:GetEffectiveScale()
        self:SetParent(UIParent)
        self:SetFrameStrata("DIALOG")
        self:SetFrameLevel(200)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            cx * scale / UIParent:GetEffectiveScale(),
            cy * scale / UIParent:GetEffectiveScale())
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._dragging = nil
        local point, _, relPoint, x, y = self:GetPoint()
        addon.db.sellBtnPoint = { point, "UIParent", relPoint, x, y }
        UpdateButton()
    end)

    btn:SetScript("OnEnter", function(self)
        local q = MaxQuality()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(addon:L("SELL_TT_TITLE"))
        GameTooltip:AddLine(string.format(addon:L("SELL_TT_MAX"),
            addon:L(QUALITY_KEY[q])), 1, 1, 1)
        GameTooltip:AddLine(addon:L("SELL_TT_LMB"), 0.7, 0.7, 0.7)
        GameTooltip:AddLine(addon:L("SELL_TT_RMB"), 0.7, 0.7, 0.7)
        GameTooltip:AddLine(addon:L("SELL_TT_DRAG"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- repair-all button: only shown while a merchant is open
    rbtn = CreateFrame("Button", "RLBetterItemRepairButton", UIParent)
    rbtn:SetSize(22, 22)
    rbtn:Hide()
    rbtn.icon = rbtn:CreateTexture(nil, "ARTWORK")
    rbtn.icon:SetAllPoints()
    rbtn.icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    local rhl = rbtn:CreateTexture(nil, "HIGHLIGHT")
    rhl:SetAllPoints()
    rhl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    rhl:SetBlendMode("ADD")
    rbtn:RegisterForClicks("LeftButtonUp")
    rbtn:SetScript("OnClick", function()
        if not (CanMerchantRepair and CanMerchantRepair()) then return end
        local cost = GetRepairAllCost and GetRepairAllCost() or 0
        if cost <= 0 then
            addon:Print(addon:L("MSG_NO_REPAIR"))
            return
        end
        RepairAllItems()
        addon:Print(string.format(addon:L("MSG_REPAIRED"), MoneyStr(cost)))
    end)
    rbtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(addon:L("REPAIR_TT"))
        local cost = GetRepairAllCost and GetRepairAllCost() or 0
        GameTooltip:AddLine(cost > 0 and MoneyStr(cost) or addon:L("MSG_NO_REPAIR"),
            1, 0.82, 0)
        GameTooltip:Show()
    end)
    rbtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- item id from link (local copy so the file has no load-order dependency)
function LinkToItemIDSafe(link)
    if not link then return nil end
    if GetItemInfoInstant then
        local id = GetItemInfoInstant(link)
        if id then return id end
    end
    local id = string.match(link, "item:(%d+)")
    return id and tonumber(id) or nil
end

-- keep the button pinned to whichever bag UI is currently visible
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_OPEN")
f:RegisterEvent("BAG_CLOSED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if not btn and addon.db then CreateButton() end
    elseif event == "BAG_OPEN" then
        bagsOpen = true
    elseif event == "BAG_CLOSED" then
        bagsOpen = false
    end
    UpdateButton()
end)
local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < 0.5 then return end
    elapsed = 0
    UpdateButton()
end)
