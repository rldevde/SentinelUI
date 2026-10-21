local addon = RLBetterItem

-- ==================== BAG UPGRADE ICONS ====================
local upgradeCache = {}

function addon:ClearUpgradeCache()
    wipe(upgradeCache)
end

local function ComputeUpgrade(link)
    local score, baseline = addon:GetUpgradeInfo(link)
    if not score then return false end
    return score > (baseline or 0)
end

function addon:IsBagUpgrade(link)
    if not link then return false end
    if not self.db or not self.db.showBagIcons then return false end
    local scaleKey = self:GetActiveScaleKey()
    if not scaleKey then return false end

    local key = scaleKey .. "|" .. link
    local cached = upgradeCache[key]
    if cached ~= nil then return cached end

    local ok, res = pcall(ComputeUpgrade, link)
    res = ok and res or false
    upgradeCache[key] = res
    return res
end

-- shared upgrade icon for bag / char / quest reward buttons
function addon:SetUpgradeIcon(button, show)
    if not button then return end
    if show then
        if not button.rlUpgradeIcon then
            local tex = button:CreateTexture(nil, "OVERLAY")
            tex:SetSize(16, 16)
            tex:SetPoint("TOPRIGHT", -2, -2)
            tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            button.rlUpgradeIcon = tex
        end
        button.rlUpgradeIcon:Show()
    elseif button.rlUpgradeIcon then
        button.rlUpgradeIcon:Hide()
    end
end

local function UpdateBagButton(button, link)
    addon:SetUpgradeIcon(button, link and addon:IsBagUpgrade(link))
    if addon.UpdateOutfitMark then addon.UpdateOutfitMark(button, link) end
end

local function GetBagItemLink(bagId, slotId)
    if not bagId or not slotId or slotId <= 0 then return nil end
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bagId, slotId)
    end
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagId, slotId)
        return info and info.hyperlink
    end
    if GetContainerItemLink then
        return GetContainerItemLink(bagId, slotId)
    end
    return nil
end
addon.GetBagItemLink = GetBagItemLink

-- iterate every item link in the player's bags: fn(link, bagId, slotId)
-- includeBank = also scan the bank while the bank frame is open
function addon:ForEachBagItemLink(fn, includeBank)
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not numSlots then return end
    local function ScanBag(bag)
        local slots = numSlots(bag) or 0
        for slot = 1, slots do
            local link = GetBagItemLink(bag, slot)
            if link then fn(link, bag, slot) end
        end
    end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        ScanBag(bag)
    end
    -- -1 = bank container, 5.. = bank bags (TBC/Wrath numbering)
    if includeBank and BankFrame and BankFrame:IsShown() then
        ScanBag(-1)
        for bag = 5, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 6) do
            ScanBag(bag)
        end
    end
end

local function UpdateButton(button, frameBagId)
    if not button or not button.GetID then return end
    local bagId = frameBagId
    if button.GetBagID then
        bagId = button:GetBagID()
    end
    UpdateBagButton(button, GetBagItemLink(bagId, button:GetID()))
end

-- update every item button of one container frame (classic named buttons
-- and modern pooled button lists)
local function UpdateContainerFrame(frame)
    if not frame or not frame:IsShown() then return end
    local frameBagId = frame.GetID and frame:GetID()

    if frame.Items then -- modern pooled item buttons
        for _, button in pairs(frame.Items) do
            UpdateButton(button, frameBagId)
        end
    end

    local name = frame:GetName()
    if name then -- classic "ContainerFrameXItemY" naming
        for i = 1, 40 do
            local button = _G[name .. "Item" .. i]
            if not button then break end
            UpdateButton(button, frameBagId)
        end
    end
end

-- merchant items + mob loot window + bank share the same upgrade icon
local function UpdateExtraFrames()
    if MerchantFrame and MerchantFrame:IsShown() and GetMerchantItemLink then
        for i = 1, 10 do
            local btn = _G["MerchantItem" .. i .. "ItemButton"]
            if not btn then break end
            addon:SetUpgradeIcon(btn, addon:IsBagUpgrade(GetMerchantItemLink(i)))
        end
    end
    if LootFrame and LootFrame:IsShown() and GetLootSlotLink then
        for i = 1, 4 do
            local btn = _G["LootButton" .. i]
            if not btn then break end
            addon:SetUpgradeIcon(btn, addon:IsBagUpgrade(GetLootSlotLink(i)))
        end
    end
end

local function UpdateAllBags()
    if not addon.initialized or not addon.db or not addon.db.showBagIcons then return end

    for i = 1, (NUM_CONTAINER_FRAMES or 6) do
        UpdateContainerFrame(_G["ContainerFrame" .. i])
    end
    UpdateContainerFrame(_G["ContainerFrameCombinedBags"]) -- modern combined bags

    -- bank main window: BankFrameItemN buttons, container id -1
    local bank = _G["BankFrame"]
    if bank and bank:IsShown() then
        local bankBag = BANK_CONTAINER or -1
        for i = 1, (NUM_BANKGENERIC_SLOTS or 28) do
            local btn = _G["BankFrameItem" .. i]
            if not btn then break end
            UpdateBagButton(btn, GetBagItemLink(bankBag, i))
        end
    end

    UpdateExtraFrames()
end
addon.UpdateAllBags = UpdateAllBags

-- classic hook (exists on some clients)
if ContainerFrame_Update then
    hooksecurefunc("ContainerFrame_Update", function()
        UpdateAllBags()
    end)
end

-- event-driven refresh (bags opening / items moving / new loot)
local bagFrame = CreateFrame("Frame")
bagFrame:RegisterEvent("BAG_UPDATE")
bagFrame:RegisterEvent("BAG_UPDATE_DELAYED")
bagFrame:RegisterEvent("BAG_OPEN")
bagFrame:RegisterEvent("BANKFRAME_OPENED")
bagFrame:RegisterEvent("MERCHANT_SHOW")
bagFrame:RegisterEvent("LOOT_OPENED")
bagFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
bagFrame:SetScript("OnEvent", function()
    UpdateAllBags()
end)

-- polling fallback: covers clients where neither the hook nor the events
-- fire reliably; throttled and cheap (early-out when no bag is shown)
local elapsed = 0
bagFrame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < 0.4 then return end
    elapsed = 0
    local anyOpen = false
    for i = 1, (NUM_CONTAINER_FRAMES or 6) do
        local f = _G["ContainerFrame" .. i]
        if f and f:IsShown() then anyOpen = true break end
    end
    local cb = _G["ContainerFrameCombinedBags"]
    if cb and cb:IsShown() then anyOpen = true end
    if anyOpen then UpdateAllBags() end
    -- merchant / loot windows also when no bag frame is open
    if not anyOpen and addon.initialized and addon.db and addon.db.showBagIcons then
        if (MerchantFrame and MerchantFrame:IsShown())
            or (LootFrame and LootFrame:IsShown()) then
            UpdateExtraFrames()
        end
    end
end)
