local addon = RLBetterItem

-- ==================== CHARACTER SLOT ARROWS + SCORES + ILVL ==========
-- marks paper-doll slots when a better item is sitting in the bags,
-- shows the score and item level of each equipped item on its slot,
-- plus a GS/iLvl summary on the character and inspect frames
local SLOT_SHORT = {
    "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet",
    "Wrist", "Hands", "Finger0", "Finger1", "Trinket0", "Trinket1",
    "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard",
}

local function ScoreText(button, unit, slotId, enabled)
    if not button then return end
    local fs = button.rlScoreText
    if not enabled then
        if fs then fs:Hide() end
        return
    end
    local link = GetInventoryItemLink(unit, slotId)
    local score = link and addon:GetItemScore(link, addon:GetActiveScaleKey()) or 0
    if not link or not score or score <= 0 then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        fs = button:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        fs:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
        button.rlScoreText = fs
    end
    fs:SetText(string.format("%.0f", score))
    fs:Show()
end

-- small item-level number in the top-left of the slot, colored by
-- the item's quality (per-slot iLvl display)
local function ILvlText(button, unit, slotId, enabled)
    if not button then return end
    local fs = button.rlILvlText
    if not enabled then
        if fs then fs:Hide() end
        return
    end
    local link = GetInventoryItemLink(unit, slotId)
    local ilvl = link and (
        (addon.ItemLevelOf and addon.ItemLevelOf(link))
        or select(4, GetItemInfo(link)))
    if not ilvl or ilvl <= 0 then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        fs = button:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.rlILvlText = fs
    end
    local quality = select(3, GetItemInfo(link))
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then
        fs:SetText(c.hex .. ilvl .. "|r")
    else
        fs:SetText("|cffffffff" .. ilvl .. "|r")
    end
    fs:Show()
end

-- slots that can carry a real enchant in TBC (rings/neck skipped —
-- ring enchants are enchanter-only, neck has none)
local ENCHANT_SLOTS = {
    [1] = true, [3] = true, [5] = true, [7] = true, [8] = true,
    [9] = true, [10] = true, [15] = true, [16] = true,
}

-- missingEnchant, emptySocketCount, link — shared with the shopping list
function addon:SlotNeedsAttention(unit, slotId)
    local link = GetInventoryItemLink(unit, slotId)
    if not link then return false, 0, nil end
    -- item link fields: item:id:enchant:gem1:gem2:gem3:gem4
    local ench, g1, g2, g3, g4 =
        link:match("item:%d+:(%d*):(%d*):(%d*):(%d*):(%d*)")
    local missingEnchant =
        ENCHANT_SLOTS[slotId] and (tonumber(ench) or 0) == 0
    local needSockets = 0
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if getStats then
        local stats = getStats(link)
        if stats then
            for k in pairs(stats) do
                if tostring(k):find("EMPTY_SOCKET") then
                    needSockets = needSockets + 1
                end
            end
        end
    end
    local filled = 0
    for _, g in ipairs({ g1, g2, g3, g4 }) do
        if (tonumber(g) or 0) > 0 then filled = filled + 1 end
    end
    return missingEnchant, math.max(0, needSockets - filled), link
end

-- slot border: while an outfit is active, green = item matches the
-- outfit (or the outfit doesn't define this slot), red = wrong item
-- equipped; without an active outfit, red/orange warn about missing
-- enchants / empty sockets (if enabled)
local function WarnTexture(button, unit, slotId, enabled)
    if not button then return end
    local tex = button.rlWarnTex
    if not tex then
        tex = button:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:SetAllPoints()
        tex:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        button.rlWarnTex = tex
    end
    tex:Hide()

    -- outfit-conformity borders (player only, needs an active outfit)
    local db = addon.db
    local outfit = db and db.outfitMatchBorders ~= false
        and db.activeOutfit and db.outfits
        and db.outfits[db.activeOutfit]
    if outfit and unit == "player" then
        local wantID = outfit.items and outfit.items[slotId]
        local link = GetInventoryItemLink("player", slotId)
        local haveID = link and tonumber(link:match("item:(%d+)"))
        if not haveID then return end -- empty slot: no border
        if wantID and wantID ~= haveID then
            tex:SetVertexColor(1, 0.2, 0.1)   -- red: wrong item
        else
            tex:SetVertexColor(0.1, 0.9, 0.2) -- green: matches/none set
        end
        tex:Show()
        return
    end

    -- fallback: enchant/socket warnings
    if not enabled then return end
    local missingEnchant, emptySockets =
        addon:SlotNeedsAttention(unit, slotId)
    if not (missingEnchant or emptySockets > 0) then return end
    -- red = no enchant, orange = empty socket(s)
    tex:SetVertexColor(1, missingEnchant and 0.25 or 0.6, 0.1)
    tex:Show()
end

-- small durability percentage, only when an item needs repair
local function DurabilityText(button, slotId, enabled)
    if not button then return end
    local fs = button.rlDurText
    local function Hide()
        if fs then fs:Hide() end
    end
    if not enabled or not GetInventoryItemDurability then return Hide() end
    local cur, max = GetInventoryItemDurability(slotId)
    if not (cur and max and max > 0) then return Hide() end
    local pct = cur / max * 100
    if pct >= 60 then return Hide() end -- only warn below 60%
    if not fs then
        fs = button:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        fs:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
        button.rlDurText = fs
    end
    fs:SetText((pct < 25 and "|cffff4040" or "|cffffcc00") ..
        string.format("%.0f%%", pct) .. "|r")
    fs:Show()
end

-- "% vs your item" on inspect slots (would this be an upgrade for me?)
local function CompareText(button, unit, slotId, enabled)
    if not button then return end
    local fs = button.rlCmpText
    local function Hide()
        if fs then fs:Hide() end
    end
    if unit == "player" or not enabled then return Hide() end
    local link = GetInventoryItemLink(unit, slotId)
    if not link then return Hide() end
    local score, baseline = addon:GetUpgradeInfo(link)
    if not score then return Hide() end
    if not fs then
        fs = button:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.rlCmpText = fs
    end
    if baseline and baseline > 0 then
        local pct = (score - baseline) / baseline * 100
        fs:SetText((pct >= 0 and "|cff00ff00+" or "|cffff4040") ..
            string.format("%.0f", pct) .. "%|r")
    else
        fs:SetText("|cff00ff00▲|r")
    end
    fs:Show()
end

local function DecorateSlots(prefix, unit, showScores, showILvl)
    local isPlayer = (unit == "player")
    local showWarn = isPlayer and addon.db and addon.db.enchantWarn
    local showDur = isPlayer and addon.db and addon.db.durabilityWarn
    local showCmp = (not isPlayer) and addon.db and addon.db.inspectCompare
    for slotId, short in ipairs(SLOT_SHORT) do
        local button = _G[prefix .. short .. "Slot"]
        ScoreText(button, unit, slotId, showScores)
        ILvlText(button, unit, slotId, showILvl)
        WarnTexture(button, unit, slotId, showWarn)
        DurabilityText(button, slotId, showDur)
        CompareText(button, unit, slotId, showCmp)
    end
end

-- ==================== FRAME SUMMARY TEXTS ============================
-- the summary sits on a small draggable holder so the text can be
-- positioned freely when "unlock" is enabled in the settings
local function EnsureSummary(parent, attr)
    if not parent then return nil end
    local holder = parent[attr .. "Holder"]
    if not holder then
        holder = CreateFrame("Button", nil, parent)
        holder:SetSize(240, 16)
        local pos = addon.db and addon.db.gearTextPos
        holder:SetPoint("BOTTOM", parent, "BOTTOM",
            pos and pos.x or 0, pos and pos.y or 18)
        holder:RegisterForDrag("LeftButton")
        holder:SetMovable(true)
        holder.anchor = parent
        local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER")
        holder.fs = fs
        holder.hl = holder:CreateTexture(nil, "BACKGROUND")
        holder.hl:SetAllPoints()
        holder.hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        holder.hl:SetVertexColor(0, 1, 0, 0.15)
        holder.hl:Hide()
        holder:SetScript("OnDragStart", function(self)
            if addon.db and addon.db.gearTextUnlock then
                self:StartMoving()
            end
        end)
        holder:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- store the offset from the parent's bottom-center
            local p = self.anchor
            if not (p.GetLeft and p:GetLeft()) then return end
            local x = ((self:GetLeft() + self:GetRight()) / 2)
                - ((p:GetLeft() + p:GetRight()) / 2)
            local y = self:GetBottom() - p:GetBottom()
            addon.db.gearTextPos = { x = x, y = y }
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", p, "BOTTOM", x, y)
        end)
        parent[attr .. "Holder"] = holder
    end
    if holder.hl then
        local unlock = addon.db and addon.db.gearTextUnlock
        holder.hl:SetShown(unlock)
        -- only swallow mouse while unlocked, otherwise clicks must
        -- pass through to the frame/tab buttons underneath
        holder:EnableMouse(unlock and true or false)
    end
    return holder.fs
end

-- hunter: equipped ammo count; warlock: soul shard count
local function ResourceText()
    if not (addon.db and addon.db.ammoCounter) then return "" end
    local _, class = UnitClass("player")
    if class == "HUNTER" then
        local ammoID = GetInventoryItemID and GetInventoryItemID("player", 0)
        if ammoID and GetItemCount then
            local name = GetItemInfo(ammoID) or "?"
            return "    |cff888888" .. tostring(GetItemCount(ammoID)) ..
                "× " .. name .. "|r"
        end
    elseif class == "WARLOCK" then
        local n = GetItemCount and GetItemCount(6265) or 0 -- soul shard
        local name = GetItemInfo and (GetItemInfo(6265)) or "Seelensplitter"
        return "    |cff888888" .. n .. "× " .. name .. "|r"
    end
    return ""
end

local function GearSummaryText(unit)
    local info = addon:ComputeUnitGear(unit)
    if not info or info.ilvl <= 0 then return nil end
    local extra = (unit == "player") and ResourceText() or ""
    local r, g, b = addon.GSQualityColor and addon:GSQualityColor(info.score) or 1, 1, 1
    return string.format("|cffffd700GS:|r |cff%02x%02x%02x%.0f|r    |cffffd700Ø iLvl:|r |cffffffff%.1f|r%s",
        r * 255, g * 255, b * 255, info.score, info.ilvl, extra)
end

-- quick scale switch: "Schutz ▾" next to the score line, opens the
-- same scale menu the settings tab uses
local scaleBtn
local function EnsureScaleButton(anchor)
    if scaleBtn then return scaleBtn end
    scaleBtn = CreateFrame("Button", "RLBIScaleQuickBtn", anchor)
    scaleBtn:SetSize(120, 14)
    scaleBtn.fs = scaleBtn:CreateFontString(nil, "OVERLAY",
        "GameFontHighlightSmall")
    scaleBtn.fs:SetAllPoints()
    scaleBtn.fs:SetJustifyH("LEFT")
    scaleBtn:EnableMouse(true)
    scaleBtn:SetScript("OnClick", function(self)
        addon:ToggleScaleMenu(self)
    end)
    scaleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("SentinelUI BetterItem")
        GameTooltip:AddLine(addon:L("SCALE_BTN_TT"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    scaleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return scaleBtn
end

local function UpdateCharSummary()
    local anchor = PaperDollFrame or CharacterFrame
    if not addon.db or not addon.db.charGearText then
        local fs = anchor and anchor.rlGearSummary
        if fs then fs:Hide() end
        if scaleBtn then scaleBtn:Hide() end
        return
    end
    local fs = EnsureSummary(anchor, "rlGearSummary")
    if not fs then return end
    fs:SetText(GearSummaryText("player") or "")
    fs:Show()

    -- scale button hangs off the movable summary holder so it never
    -- collides with the frame's own layout
    local holder = anchor and anchor.rlGearSummaryHolder
    if holder and addon.db.charScaleBtn then
        local sb = EnsureScaleButton(anchor)
        sb:SetParent(anchor)
        sb:ClearAllPoints()
        sb:SetPoint("LEFT", holder, "RIGHT", 8, 0)
        local name = addon:GetScaleName(addon:GetScale(addon:GetActiveScaleKey()))
        local short = string.match(name or "", ":%s*(.+)$") or name or "?"
        sb.fs:SetText("|cff888888" .. short .. " ▾|r")
        sb:Show()
    elseif scaleBtn then
        scaleBtn:Hide()
    end
end

local function UpdateInspectSummary(unit)
    if not addon.db or not addon.db.charGearText then return end
    local fs = EnsureSummary(InspectPaperDollFrame, "rlGearSummary")
    if not fs then return end
    fs:SetText(GearSummaryText(unit) or "")
    fs:Show()
end

local upgradedSlots = {}

local function Refresh()
    if not addon.initialized or not addon.db then return end

    if addon.db.charSlotArrows then
        wipe(upgradedSlots)
        addon:ForEachBagItemLink(function(link)
            local slot = addon:GetBestUpgradeSlot(link)
            if slot then upgradedSlots[slot] = true end
        end, true) -- bank counts too while open
    end

    for slotId, short in ipairs(SLOT_SHORT) do
        local button = _G["Character" .. short .. "Slot"]
        if button then
            addon:SetUpgradeIcon(button, addon.db.charSlotArrows and upgradedSlots[slotId])
        end
    end
    DecorateSlots("Character", "player", addon.db.charSlotScores, addon.db.charSlotILvl)
    UpdateCharSummary()
end
addon.RefreshCharSlots = Refresh

-- low-durability alert: warns on ready check and when joining a group
local inGroup = false
local function DurabilityAlert()
    if not (addon.db and addon.db.durabilityAlert) then return end
    if not GetInventoryItemDurability then return end
    local worst = 100
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            worst = math.min(worst, cur / max * 100)
        end
    end
    if worst < 25 then
        addon:Print("|cffff4040" ..
            string.format(addon:L("MSG_DUR_LOW"), string.format("%.0f", worst))
            .. "|r")
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("INSPECT_READY")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("READY_CHECK")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "INSPECT_READY" then
        C_Timer.After(0.1, function()
            local unit = (InspectFrame and InspectFrame.unit) or "target"
            if addon.db and (addon.db.inspectScores or addon.db.charSlotILvl) then
                DecorateSlots("Inspect", unit,
                    addon.db.inspectScores, addon.db.charSlotILvl)
            end
            UpdateInspectSummary(unit)
        end)
    elseif event == "READY_CHECK" then
        DurabilityAlert()
    elseif event == "GROUP_ROSTER_UPDATE" then
        local now = IsInGroup and (IsInGroup() or IsInRaid()) or false
        if now and not inGroup then
            DurabilityAlert() -- just joined a group
        end
        inGroup = now and true or false
        Refresh()
    elseif event == "ADDON_LOADED" then
        -- Inspect UI may be load-on-demand
        if (arg == "Blizzard_InspectUI" or InspectPaperDollFrame) and InspectPaperDollFrame then
            InspectPaperDollFrame:HookScript("OnShow", function()
                local unit = (InspectFrame and InspectFrame.unit) or "target"
                C_Timer.After(0.2, function()
                    if addon.db and (addon.db.inspectScores or addon.db.charSlotILvl) then
                        DecorateSlots("Inspect", unit,
                            addon.db.inspectScores, addon.db.charSlotILvl)
                    end
                    UpdateInspectSummary(unit)
                end)
            end)
        end
    else
        Refresh()
    end
end)

-- refresh when the character panel opens
if PaperDollFrame then PaperDollFrame:HookScript("OnShow", Refresh) end
if CharacterFrame then CharacterFrame:HookScript("OnShow", Refresh) end
if InspectPaperDollFrame then
    InspectPaperDollFrame:HookScript("OnShow", function()
        local unit = (InspectFrame and InspectFrame.unit) or "target"
        C_Timer.After(0.2, function()
            if addon.db and (addon.db.inspectScores or addon.db.charSlotILvl) then
                DecorateSlots("Inspect", unit,
                    addon.db.inspectScores, addon.db.charSlotILvl)
            end
            UpdateInspectSummary(unit)
        end)
    end)
end
