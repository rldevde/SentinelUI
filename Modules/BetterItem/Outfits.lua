local addon = RLBetterItem

-- ==================== OUTFIT MANAGER ====================
-- Gear-set saving / switching, RLOutfitter-style. Outfits live in
-- db.outfits[name] = { icon = tex?, items = { [slotId] = itemID } }

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local function LinkToItemID(link)
    if not link then return nil end
    if GetItemInfoInstant then
        local id = GetItemInfoInstant(link)
        if id then return id end
    end
    local id = string.match(link, "item:(%d+)")
    return id and tonumber(id) or nil
end

function addon:GetOutfitsForItemID(itemID)
    local result = {}
    if not self.db or not itemID then return result end
    for name, outfit in pairs(self.db.outfits or {}) do
        for _, id in pairs(outfit.items or {}) do
            if id == itemID then
                table.insert(result, name)
                break
            end
        end
    end
    table.sort(result)
    return result
end

function addon:GetOutfitNames()
    local names = {}
    for name in pairs(self.db and self.db.outfits or {}) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function addon:SaveOutfit(name, overwrite)
    if not name or name == "" then return nil, "noname" end
    if self.db.outfits[name] and not overwrite then return nil, "exists" end
    local items = {}
    for _, slot in ipairs(EQUIP_SLOTS) do
        local id = GetInventoryItemID("player", slot)
        if id then items[slot] = id end
    end
    local keep = self.db.outfits[name]
    self.db.outfits[name] = {
        icon = keep and keep.icon or nil,
        items = items,
        -- remember which scale this gear belongs to; equipping the
        -- outfit later restores the matching weights
        scaleKey = self:GetActiveScaleKey()
            or (keep and keep.scaleKey) or nil,
    }
    self:RefreshOutfitBar()
    if self.RefreshOutfitPanel then self.RefreshOutfitPanel() end
    return true
end

function addon:DeleteOutfit(name)
    if self.db.outfits then self.db.outfits[name] = nil end
    if self.db.activeOutfit == name then self.db.activeOutfit = nil end
    self:RefreshOutfitBar()
    if self.RefreshOutfitPanel then self.RefreshOutfitPanel() end
end

local function OutfitIcon(outfit)
    if outfit and outfit.icon then return outfit.icon end
    if outfit and outfit.items then
        for _, id in pairs(outfit.items) do
            local tex = GetItemIcon and GetItemIcon(id)
            if tex then return tex end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end
addon.OutfitIcon = OutfitIcon

-- itemIDs of the outfit that are neither equipped nor in bags
-- (the bank counts too, but only while it is open)
function addon:OutfitMissing(name)
    local missing = {}
    local outfit = self.db and self.db.outfits and self.db.outfits[name]
    if not outfit then return missing end
    local owned = {}
    for slot = 1, 19 do
        local l = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        local id = l and tonumber(l:match("item:(%d+)"))
        if id then owned[id] = true end
    end
    self:ForEachBagItemLink(function(l)
        local id = tonumber(l:match("item:(%d+)") or "")
        if id then owned[id] = true end
    end, true)
    for _, id in pairs(outfit.items or {}) do
        id = tonumber(id)
        if id and not owned[id] then
            missing[#missing + 1] = id
        end
    end
    return missing
end

-- equip an outfit; also switches to the scale linked to it (unless
-- called from the auto-equip path, which must keep db.scale = "auto")
function addon:EquipOutfit(name, noScaleSwitch)
    local outfit = self.db and self.db.outfits and self.db.outfits[name]
    if not outfit then return end
    if InCombatLockdown and InCombatLockdown() then
        self:Print(self:L("MSG_OUTFIT_COMBAT"))
        return
    end
    for slot, id in pairs(outfit.items or {}) do
        if id then EquipItemByName(id, slot) end
    end
    self.db.activeOutfit = name
    self:RefreshOutfitBar()

    if not noScaleSwitch and outfit.scaleKey
        and self.db.scale ~= outfit.scaleKey then
        self.db.scale = outfit.scaleKey
        if self.NoteScalePicked then self:NoteScalePicked(outfit.scaleKey) end
        if self.ClearUpgradeCache then self:ClearUpgradeCache() end
        if self.RefreshSettings then self:RefreshSettings() end
        if self.UpdateStatsPanel then self:UpdateStatsPanel() end
        local scale = self:GetScale(outfit.scaleKey)
        if scale then
            self:Print(self:L("MSG_SCALE_CHANGED") .. self:GetScaleName(scale))
        end
    end
end

-- macro-friendly global: /run RLBetterItem_EquipOutfit("name")
_G.RLBetterItem_EquipOutfit = function(name)
    addon:EquipOutfit(name)
end

-- auto-equip the outfit assigned to the current scale (spec)
function addon:AutoEquipForScale()
    if not self.db or not self.db.autoOutfit then return end
    local key = self:GetActiveScaleKey()
    local name = key and self.db.autoOutfits and self.db.autoOutfits[key]
    if name and name ~= self.db.activeOutfit and self.db.outfits[name] then
        -- learn the reverse link while we are here
        if not self.db.outfits[name].scaleKey then
            self.db.outfits[name].scaleKey = key
        end
        self:EquipOutfit(name, true)
    end
end

-- ==================== OUTFIT BAR ====================
local bar, barButtons = nil, {}

function addon:RefreshOutfitBar()
    if not self.db or not self.db.outfitBarShow then
        if bar then bar:Hide() end
        return
    end
    if not bar then
        bar = CreateFrame("Frame", "RLBetterItemOutfitBar", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        bar:SetSize(40, 36)
        bar:SetMovable(true)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        bar:SetBackdropColor(0, 0, 0, 0.8)
        bar:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
        bar:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local p, rel, rp, x, y = self:GetPoint()
            addon.db.outfitBarPoint = { p, rel and rel:GetName() or "UIParent", rp, x, y }
        end)
    end

    -- docked mode: the outfit icons live inside the SentinelUI bottom dock,
    -- right after the left data panel; free-floating mode is the fallback
    -- when the dock does not exist (datatexts disabled)
    local dock = _G.SentinelUIDock
    local size, pad = 30, 4
    if dock then
        size = math.max(14, math.floor((dock:GetHeight() or 22) - 8))
        bar:SetParent(dock)
        bar:SetMovable(false)
        bar:SetFrameLevel((dock:GetFrameLevel() or 0) + 5)
        bar:ClearAllPoints()
        local leftPanel = _G.SentinelUILeftChatDataPanel
        if leftPanel and leftPanel:IsShown() then
            bar:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 8, 0)
        else
            bar:SetPoint("BOTTOM", dock, "BOTTOM", 90, 0)
        end
    else
        bar:SetParent(UIParent)
        bar:SetMovable(true)
        local p = self.db.outfitBarPoint
        if not bar:GetPoint() then
            if p and _G[p[2] or ""] then
                bar:SetPoint(p[1], _G[p[2]], p[3], p[4], p[5])
            else
                bar:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
            end
        end
    end
    bar:Show()

    for _, btn in ipairs(barButtons) do btn:Hide() end
    -- per-outfit selection: outfits unchecked in the outfit panel
    -- (db.outfitBarSel[name] == false) are skipped from the bar
    local sel = self.db.outfitBarSel
    local names = {}
    for _, name in ipairs(self:GetOutfitNames()) do
        if not sel or sel[name] ~= false then names[#names + 1] = name end
    end
    local prev, n = nil, 0
    for _, name in ipairs(names) do
        n = n + 1
        local btn = barButtons[n]
        if not btn then
            btn = CreateFrame("Button", nil, bar)
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetAllPoints()
            btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
            btn.hl:SetAllPoints()
            btn.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            btn.hl:SetBlendMode("ADD")
            btn:SetScript("OnClick", function(self)
                addon:EquipOutfit(self.outfitName)
            end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.outfitName)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            barButtons[n] = btn
        end
        btn.outfitName = name
        btn:SetSize(size, size)
        btn.icon:SetTexture(OutfitIcon(self.db.outfits[name]))
        btn.icon:SetDesaturated(self.db.activeOutfit ~= name)
        btn:ClearAllPoints()
        if prev then btn:SetPoint("LEFT", prev, "RIGHT", pad, 0)
        else btn:SetPoint("LEFT", bar, "LEFT", 4, 0) end
        btn:Show()
        prev = btn
    end
    if n == 0 then
        bar:Hide()
        return
    end
    bar:SetSize(math.max(40, n * (size + pad) + 4), size + 8)
end

-- ==================== CHARACTER-FRAME OUTFIT PANEL ====================
-- outfit list pinned next to the character window (RLPalaTankHelper spot):
-- left of the char frame, click an outfit to equip it.
local outPanel, outRows = nil, {}

-- name prompt for the "+" button (save current gear as new outfit)
StaticPopupDialogs["RLBI_OUTFIT_NEW"] = {
    text = "%s",
    button1 = SAVE or "Save",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1,
    timeout = 0,
    hideOnEscape = true,
    whileDead = true,
    OnShow = function(self)
        local box = self.EditBox or self.editBox
        if box then box:SetText("") box:SetFocus() end
    end,
    OnAccept = function(self)
        local box = self.EditBox or self.editBox
        local name = box and strtrim(box:GetText() or "") or ""
        local ok, err = addon:SaveOutfit(name)
        addon:Print(ok and (addon:L("MSG_OUTFIT_SAVED") .. " " .. name)
            or addon:L(err == "exists" and "MSG_OUTFIT_EXISTS" or "MSG_OUTFIT_NONAME"))
        if addon.RefreshOutfitPanel then addon.RefreshOutfitPanel() end
    end,
}

-- tiny right-click context menu for outfit rows
local ctxMenu
local function ShowOutfitMenu(anchor, name)
    if not ctxMenu then
        ctxMenu = CreateFrame("Frame", "RLBetterItemOutfitMenu", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        ctxMenu:SetFrameStrata("TOOLTIP")
        ctxMenu:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        ctxMenu:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        ctxMenu:SetClampedToScreen(true)
        ctxMenu.buttons = {}
        ctxMenu:SetScript("OnUpdate", function(self, dt)
            self.leaveT = self:IsMouseOver() and 0 or (self.leaveT or 0) + dt
            if self.leaveT > 1.2 then self:Hide() end
        end)
    end
    local actions = {
        { key = "OUTFIT_EQUIP",     fn = function() addon:EquipOutfit(name) end },
        { key = "OUTFIT_OVERWRITE", fn = function() addon:SaveOutfit(name, true) addon:Print(addon:L("MSG_OUTFIT_SAVED") .. " " .. name) end },
        { key = "OUTFIT_PREVIEW",   fn = function() addon:PreviewOutfit(name) end },
        { key = "OUTFIT_MACRO",     fn = function() addon:CreateOutfitMacro(name) end },
        { key = "OUTFIT_ICON",      fn = function() addon:ShowIconPicker(name) end },
        { key = "OUTFIT_SETSCALE",  fn = function()
            local key = addon:GetActiveScaleKey()
            addon.db.outfits[name].scaleKey = key
            local scale = addon:GetScale(key)
            addon:Print(string.format(addon:L("MSG_OUTFIT_SCALE_SET"),
                name, addon:GetScaleName(scale)))
        end },
        { key = "OUTFIT_DELETE",    fn = function() addon:DeleteOutfit(name) end },
    }
    for i, a in ipairs(actions) do
        local b = ctxMenu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, ctxMenu)
            b:SetSize(118, 18)
            b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 19)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(0.35, 0.35, 0.45, 0.6)
            b:SetScript("OnClick", function(self)
                self.action()
                ctxMenu:Hide()
            end)
            ctxMenu.buttons[i] = b
        end
        b.text:SetText(addon:L(a.key))
        b.action = a.fn
        b:Show()
    end
    for i = #actions + 1, #ctxMenu.buttons do ctxMenu.buttons[i]:Hide() end
    ctxMenu:SetSize(130, 12 + #actions * 19)
    ctxMenu:ClearAllPoints()
    ctxMenu:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 0)
    ctxMenu:Show()
end

local function CreateOutfitPanel()
    outPanel = CreateFrame("Frame", "RLBetterItemOutfitPanel", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    outPanel:SetSize(200, 120)
    outPanel:SetFrameStrata("HIGH")
    outPanel:SetMovable(true)
    outPanel:EnableMouse(true)
    outPanel:RegisterForDrag("LeftButton")
    outPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    outPanel:SetBackdropColor(0, 0, 0, 0.85)
    outPanel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    outPanel:Hide()

    outPanel.title = outPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outPanel.title:SetPoint("TOPLEFT", 12, -12)
    outPanel.title:SetText("|cffffd700" .. addon:L("TAB_OUTFITS") .. "|r")

    -- "+" button: save current gear as a new outfit
    local addBtn = CreateFrame("Button", nil, outPanel)
    addBtn:SetSize(18, 18)
    addBtn:SetPoint("TOPRIGHT", -8, -7)
    addBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    addBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    addBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
    addBtn:SetScript("OnClick", function()
        StaticPopup_Show("RLBI_OUTFIT_NEW")
    end)
    addBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(addon:L("OUTFIT_SAVE"))
        GameTooltip:Show()
    end)
    addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    outPanel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    outPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, rel, rp, x, y = self:GetPoint()
        addon.db.outfitPanelPoint = { p, rel and rel:GetName() or "UIParent", rp, x, y }
    end)
end

local function RestoreOutfitPanelPos()
    local p = addon.db.outfitPanelPoint
    outPanel:ClearAllPoints()
    if p and _G[p[2] or ""] then
        outPanel:SetPoint(p[1], _G[p[2]], p[3], p[4], p[5])
    else
        -- default: directly below the stats panel on the right side;
        -- same spot as the stats panel when it is disabled
        local stats = _G["RLBetterItemStatsPanel"]
        if stats and stats:IsShown() then
            outPanel:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -8)
        else
            outPanel:SetPoint("TOPLEFT", CharacterFrame or UIParent,
                "TOPRIGHT", -2, -50)
        end
    end
end

local function RefreshOutfitPanel()
    if not outPanel or not outPanel:IsShown() then return end
    for _, row in ipairs(outRows) do row:Hide() end
    local names = addon:GetOutfitNames()
    for i, name in ipairs(names) do
        local row = outRows[i]
        if not row then
            row = CreateFrame("Button", nil, outPanel)
            row:SetSize(172, 20)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 2, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
            row.text:SetWidth(120)
            row.text:SetJustifyH("LEFT")
            -- per-outfit checkbox: unchecked outfits are hidden from the
            -- outfit bar in the SentinelUI dock (db.outfitBarSel[name]=false)
            row.cb = CreateFrame("CheckButton", nil, row, "ChatConfigCheckButtonTemplate")
            row.cb:SetSize(18, 18)
            row.cb:SetPoint("RIGHT", -2, 0)
            row.cb:SetHitRectInsets(0, 0, 0, 0)
            row.cb:SetScript("OnClick", function(self2)
                addon.db.outfitBarSel = addon.db.outfitBarSel or {}
                addon.db.outfitBarSel[self2:GetParent().outfitName] =
                    self2:GetChecked() and true or false
                addon:RefreshOutfitBar()
            end)
            row.cb:SetScript("OnEnter", function()
                GameTooltip:SetOwner(row.cb, "ANCHOR_RIGHT")
                GameTooltip:SetText(addon:L("OPT_OUTFIT_BAR"))
                GameTooltip:Show()
            end)
            row.cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(0.3, 0.3, 0.4, 0.5)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    ShowOutfitMenu(self, self.outfitName)
                else
                    addon:EquipOutfit(self.outfitName)
                    RefreshOutfitPanel()
                end
            end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.outfitName)
                local outfit = addon.db.outfits[self.outfitName]
                if outfit and outfit.scaleKey then
                    GameTooltip:AddLine(string.format(addon:L("OUTFIT_TT_SCALE"),
                        addon:GetScaleName(addon:GetScale(outfit.scaleKey))),
                        0.55, 0.75, 1)
                end
                local missing = addon:OutfitMissing(self.outfitName)
                if #missing > 0 then
                    GameTooltip:AddLine(string.format(
                        addon:L("OUTFIT_TT_MISSING"), #missing), 1, 0.3, 0.3)
                    for j = 1, math.min(#missing, 5) do
                        local mn = GetItemInfo and GetItemInfo(missing[j])
                        GameTooltip:AddLine("   • " ..
                            (mn or ("#" .. missing[j])), 1, 0.6, 0.6)
                    end
                end
                GameTooltip:AddLine(addon:L("OUTFIT_TT_EQUIP"), 0.7, 0.7, 0.7)
                GameTooltip:AddLine(addon:L("OUTFIT_TT_MENU"), 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            outRows[i] = row
        end
        row.outfitName = name
        row.icon:SetTexture(OutfitIcon(addon.db.outfits[name]))
        local sel = addon.db.outfitBarSel
        row.cb:SetChecked(not sel or sel[name] ~= false)
        local active = (addon.db.activeOutfit == name) and "|cff00ff00" or "|cffffffff"
        local missingN = #addon:OutfitMissing(name)
        row.text:SetText(active .. name .. "|r" ..
            (missingN > 0 and (" |cffff4040-" .. missingN .. "|r") or ""))
        row:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 20)
        row:Show()
    end
    if #names == 0 then
        if not outPanel.empty then
            outPanel.empty = outPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            outPanel.empty:SetPoint("TOPLEFT", 12, -34)
            outPanel.empty:SetText("|cff888888" .. addon:L("OUTFIT_EMPTY") .. "|r")
        end
        outPanel.empty:Show()
    elseif outPanel.empty then
        outPanel.empty:Hide()
    end
    outPanel:SetHeight(math.max(60, 40 + math.max(#names, 1) * 20 + 8))
end
addon.RefreshOutfitPanel = RefreshOutfitPanel

function addon:UpdateOutfitPanelVisibility()
    if not addon.db then return end
    if not outPanel then
        CreateOutfitPanel()
        RestoreOutfitPanelPos()
    end
    if addon.db.charOutfitPanel and CharacterFrame and CharacterFrame:IsShown() then
        if not addon.db.outfitPanelPoint then
            RestoreOutfitPanelPos()
        end
        outPanel:Show()
        RefreshOutfitPanel()
    else
        outPanel:Hide()
    end
end

-- ==================== TOOLTIP LINE ====================
-- called from Tooltip.lua: marks which outfits contain this item
function addon:AddOutfitLine(tooltip, link)
    if not self.db or not self.db.outfitTooltip then return end
    local id = LinkToItemID(link)
    if not id then return end
    local names = self:GetOutfitsForItemID(id)
    if #names > 0 then
        tooltip:AddLine("  |cff66ccff" .. self:L("TT_OUTFIT") ..
            ": " .. table.concat(names, ", ") .. "|r")
    end
end

-- ==================== BAG MARKER ====================
local function UpdateOutfitMark(button, link)
    if not button then return end
    local show = false
    if link and addon.db and addon.db.outfitBagMarks then
        local id = LinkToItemID(link)
        show = id and #addon:GetOutfitsForItemID(id) > 0 or false
    end
    if show then
        if not button.rlOutfitIcon then
            local tex = button:CreateTexture(nil, "OVERLAY")
            tex:SetSize(13, 13)
            tex:SetPoint("BOTTOMLEFT", 2, 2)
            tex:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
            tex:SetVertexColor(0.4, 0.8, 1)
            button.rlOutfitIcon = tex
        end
        button.rlOutfitIcon:Show()
    elseif button.rlOutfitIcon then
        button.rlOutfitIcon:Hide()
    end
end
addon.UpdateOutfitMark = UpdateOutfitMark

-- ==================== VENDOR PROTECTION ====================
-- NEVER replace UseContainerItem/C_Container.UseContainerItem:
-- they are on the secure item-use path and overwriting them taints
-- right-click item use (addons get blocked). Instead we watch sells
-- with hooksecurefunc and BUY BACK any outfit item that was sold.
local vendorHooked = false
local lastGuardHit = 0

local function RecoverSold(soldLink)
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    local soldID = LinkToItemID(soldLink)
    if not soldID then return end
    local n = GetNumBuybackItems and GetNumBuybackItems() or 0
    for i = 1, n do
        local bl = GetBuybackItemLink and GetBuybackItemLink(i)
        local match = bl and LinkToItemID(bl) == soldID
        if not match and GetBuybackItemInfo then
            local nm = GetBuybackItemInfo(i)
            if nm and GetItemInfo
                and nm == (GetItemInfo(soldLink)) then
                match = true
            end
        end
        if match and BuybackItem then
            BuybackItem(i)
            addon:Print("|cffff8800" .. string.format(
                addon:L("MSG_ITEM_PROTECTED"), tostring(soldLink)) ..
                "|r")
            return
        end
    end
end

local function HookVendorProtection()
    if vendorHooked or not hooksecurefunc then return end
    local function Track(bag, slot)
        local ok = pcall(function()
            if not (addon.db and addon.db.protectOutfitItems
                and MerchantFrame and MerchantFrame:IsShown()
                and bag and slot) then return end
            local now = GetTime()
            if now - lastGuardHit < 0.1 then return end -- hooked twice
            lastGuardHit = now
            local link = addon.GetBagItemLink
                and addon.GetBagItemLink(bag, slot)
            local id = LinkToItemID(link)
            if not id or #addon:GetOutfitsForItemID(id) == 0 then
                return
            end
            -- sell lands right after; buy it back a moment later
            if C_Timer and C_Timer.After then
                C_Timer.After(0.15, function()
                    pcall(RecoverSold, link)
                end)
            end
        end)
        if not ok and addon.Debug then
            addon:Debug("vendor guard error")
        end
    end
    -- hooksecurefunc throws on protected functions on some clients;
    -- never let a failed hook break the addon
    local hookedAny = false
    if C_Container and C_Container.UseContainerItem then
        hookedAny = pcall(hooksecurefunc, C_Container,
            "UseContainerItem", Track) or hookedAny
    end
    if UseContainerItem then
        hookedAny = pcall(hooksecurefunc, "UseContainerItem", Track)
            or hookedAny
    end
    if hookedAny then vendorHooked = true end
end

-- ==================== DRESSUP PREVIEW ====================
function addon:PreviewOutfit(name)
    local outfit = self.db and self.db.outfits and self.db.outfits[name]
    if not outfit then return end
    if DressUpFrame_Show then DressUpFrame_Show()
    elseif DressUpFrame then DressUpFrame:Show() end
    local model = DressUpFrame and DressUpFrame.Model
    if model and model.Reset then model:Reset() end
    for _, id in pairs(outfit.items or {}) do
        if DressUpItemLink then
            DressUpItemLink("item:" .. id)
        elseif model and model.TryOn then
            model:TryOn("item:" .. id)
        end
    end
end

-- ==================== MACRO ====================
function addon:CreateOutfitMacro(name)
    if not name or name == "" then return end
    if InCombatLockdown and InCombatLockdown() then
        self:Print(self:L("MSG_OUTFIT_COMBAT"))
        return
    end
    local outfit = self.db.outfits and self.db.outfits[name]
    if not outfit or not GetNumMacros then return end
    local safe = name:gsub("\"", "")
    local macroName = "RLBI " .. safe
    if #macroName > 16 then macroName = macroName:sub(1, 16) end
    local body = string.format('/run RLBetterItem_EquipOutfit("%s")', safe)
    local icon = OutfitIcon(outfit)
    local g, c = GetNumMacros()
    for i = 1, (g or 0) + (c or 0) do
        if GetMacroInfo(i) == macroName then
            EditMacro(i, macroName, icon, body, 1)
            self:Print(string.format(self:L("MSG_MACRO_UPDATED"), macroName, name))
            return
        end
    end
    if CreateMacro(macroName, icon, body, 1) then
        self:Print(string.format(self:L("MSG_MACRO_CREATED"), macroName, name))
    end
end

-- ==================== ICON PICKER ====================
-- grid picker (macro-window style) to assign an icon to an outfit;
-- the icon shows on the outfit bar, the charframe panel and the UI list
local ICON_FALLBACK = {
    "Interface\\Icons\\INV_Sword_27", "Interface\\Icons\\INV_Shield_06",
    "Interface\\Icons\\INV_Staff_13", "Interface\\Icons\\INV_Axe_10",
    "Interface\\Icons\\INV_Mace_05", "Interface\\Icons\\INV_Sword_04",
    "Interface\\Icons\\INV_Weapon_Bow_07", "Interface\\Icons\\INV_Weapon_Crossbow_02",
    "Interface\\Icons\\Spell_Holy_GreaterHeal", "Interface\\Icons\\Spell_Holy_HolyBolt",
    "Interface\\Icons\\Spell_Fire_Fireball02", "Interface\\Icons\\Spell_Fire_FlameBolt",
    "Interface\\Icons\\Spell_Nature_Lightning", "Interface\\Icons\\Spell_Nature_HealingTouch",
    "Interface\\Icons\\Spell_Shadow_ShadowBolt", "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
    "Interface\\Icons\\Ability_Whirlwind", "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    "Interface\\Icons\\Ability_Rogue_Eviscerate", "Interface\\Icons\\Ability_Druid_CatForm",
    "Interface\\Icons\\Ability_Druid_Maul", "Interface\\Icons\\Ability_Hunter_AimedShot",
    "Interface\\Icons\\INV_Chest_Plate04", "Interface\\Icons\\INV_Chest_Cloth_17",
    "Interface\\Icons\\INV_Helmet_25", "Interface\\Icons\\INV_Misc_QuestionMark",
}

local function CollectIconList()
    local t = {}
    if GetMacroIcons then pcall(GetMacroIcons, t) end
    if GetMacroItemIcons then pcall(GetMacroItemIcons, t) end
    if #t == 0 then return ICON_FALLBACK end
    -- normalize: "NAME" -> full path, fileIDs stay numeric
    local out = {}
    for _, v in ipairs(t) do
        if type(v) == "number" then
            out[#out + 1] = v
        elseif type(v) == "string" then
            out[#out + 1] = string.find(v, "\\") and v
                or ("Interface\\Icons\\" .. v)
        end
    end
    return out
end

local iconPicker
local COLS, ROWS = 9, 5
local function RefreshIconPicker()
    local icons = iconPicker.icons
    local start = (iconPicker.page - 1) * (COLS * ROWS)
    for i, btn in ipairs(iconPicker.cells) do
        local icon = icons[start + i]
        if icon then
            btn.icon:SetTexture(icon)
            btn.pick = icon
            btn:Show()
        else
            btn:Hide()
        end
    end
    local pages = math.max(1, math.ceil(#icons / (COLS * ROWS)))
    iconPicker.pageLbl:SetText(iconPicker.page .. "/" .. pages)
    if iconPicker.nameLbl then
        iconPicker.nameLbl:SetText("|cffffd700" .. tostring(iconPicker.outfitName) .. "|r")
    end
end

function addon:ShowIconPicker(outfitName)
    if not outfitName or not (self.db and self.db.outfits and self.db.outfits[outfitName]) then
        return
    end
    if not iconPicker then
        iconPicker = CreateFrame("Frame", "RLBetterItemIconPicker", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        iconPicker:SetSize(320, 230)
        iconPicker:SetPoint("CENTER")
        iconPicker:SetFrameStrata("DIALOG")
        iconPicker:SetMovable(true)
        iconPicker:EnableMouse(true)
        iconPicker:RegisterForDrag("LeftButton")
        iconPicker:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        iconPicker:SetBackdropColor(0, 0, 0, 0.95)
        iconPicker:SetScript("OnDragStart", iconPicker.StartMoving)
        iconPicker:SetScript("OnDragStop", iconPicker.StopMovingOrSizing)
        iconPicker:Hide()

        iconPicker.nameLbl = iconPicker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        iconPicker.nameLbl:SetPoint("TOP", 0, -14)

        local closeBtn = CreateFrame("Button", nil, iconPicker, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)

        iconPicker.cells = {}
        for i = 1, COLS * ROWS do
            local b = CreateFrame("Button", nil, iconPicker)
            b:SetSize(30, 30)
            b:SetPoint("TOPLEFT", 16 + ((i - 1) % COLS) * 33,
                -38 - math.floor((i - 1) / COLS) * 33)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            b.hl:SetBlendMode("ADD")
            b:SetScript("OnClick", function(self)
                local outfit = addon.db.outfits[iconPicker.outfitName]
                if outfit then
                    outfit.icon = self.pick
                    addon:RefreshOutfitBar()
                    if addon.RefreshOutfitPanel then addon.RefreshOutfitPanel() end
                    if addon.RefreshOutfitList then addon:RefreshOutfitList() end
                end
                iconPicker:Hide()
            end)
            iconPicker.cells[i] = b
        end

        iconPicker.pageLbl = iconPicker:CreateFontString(nil, "OVERLAY",
            "GameFontHighlightSmall")
        iconPicker.pageLbl:SetPoint("BOTTOM", 0, 12)

        local prev = CreateFrame("Button", nil, iconPicker, "UIPanelButtonTemplate")
        prev:SetSize(70, 20)
        prev:SetPoint("BOTTOMLEFT", 16, 8)
        prev:SetText("<")
        prev:SetScript("OnClick", function()
            if iconPicker.page > 1 then
                iconPicker.page = iconPicker.page - 1
                RefreshIconPicker()
            end
        end)
        local nxt = CreateFrame("Button", nil, iconPicker, "UIPanelButtonTemplate")
        nxt:SetSize(70, 20)
        nxt:SetPoint("BOTTOMRIGHT", -16, 8)
        nxt:SetText(">")
        nxt:SetScript("OnClick", function()
            local pages = math.max(1, math.ceil(#iconPicker.icons / (COLS * ROWS)))
            if iconPicker.page < pages then
                iconPicker.page = iconPicker.page + 1
                RefreshIconPicker()
            end
        end)
    end
    iconPicker.outfitName = outfitName
    iconPicker.icons = CollectIconList()
    iconPicker.page = 1
    RefreshIconPicker()
    iconPicker:Show()
end

-- ==================== INIT ====================
-- RLBI icon button on the character frame (RLOutfitter-style):
-- opens the addon UI on the Outfits tab.
local function CreateCharButton()
    if not CharacterFrame or _G["RLBetterItemCharButton"] then return end
    local b = CreateFrame("Button", "RLBetterItemCharButton", UIParent)
    b:SetSize(26, 26)
    b:SetFrameStrata("HIGH")
    -- saved user position wins; default: top title area of the char
    -- frame, right of the portrait
    local function ApplyPos()
        b:ClearAllPoints()
        local p = addon.db and addon.db.charBtnPoint
        if p then
            b:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else
            b:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 76, -4)
        end
    end
    ApplyPos()
    b:SetScript("OnShow", ApplyPos)
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)
    b:SetScript("OnDragStart", function(self)
        self.dragged = true
        self:StartMoving()
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        addon.db.charBtnPoint = { point, relPoint, x, y }
    end)
    -- only show while the character frame is open
    CharacterFrame:HookScript("OnShow", function() b:Show() end)
    CharacterFrame:HookScript("OnHide", function() b:Hide() end)
    b:SetShown(CharacterFrame:IsShown())
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture("Interface\\AddOns\\SentinelUI\\Modules\\BetterItem\\img\\logo.tga")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(40, 40)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetVertexColor(1, 0.82, 0)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    b.hl:SetBlendMode("ADD")
    b:SetScript("OnClick", function()
        if b.dragged then
            b.dragged = nil -- mouse released after a drag, not a click
            return
        end
        if not addon.mainFrame then addon:CreateMainFrame() end
        addon.mainFrame:Show()
        addon:ShowTab(3)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffffd700" .. addon:L("MINIMAP_TITLE") .. "|r")
        GameTooltip:AddLine(addon:L("CHAR_TT"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(addon:L("SELL_TT_DRAG"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local outPanelHooked = false
local function HookOutfitPanel()
    if outPanelHooked or not CharacterFrame then return end
    outPanelHooked = true
    CreateCharButton()
    CharacterFrame:HookScript("OnShow", function()
        addon:UpdateOutfitPanelVisibility()
    end)
    CharacterFrame:HookScript("OnHide", function()
        if outPanel then outPanel:Hide() end
        if ctxMenu then ctxMenu:Hide() end
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_CharacterUI" or name == "Blizzard_UIPanels_Game" then
            HookOutfitPanel()
        end
        return
    end
    HookVendorProtection()
    addon:RefreshOutfitBar()
    HookOutfitPanel()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)

-- ==================== OFFSPEC WARNING ==============================
-- equipping an item that belongs to a DIFFERENT outfit than the
-- active one -> chat note (debounced; suppressed while this addon
-- equips a set itself)
local equipBusy
local _EquipOutfit = addon.EquipOutfit
function addon:EquipOutfit(name, noScaleSwitch)
    equipBusy = true
    _EquipOutfit(self, name, noScaleSwitch)
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function() equipBusy = false end)
    else
        equipBusy = false
    end
end

local offspecPending, offspecFlush
local of = CreateFrame("Frame")
of:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
of:SetScript("OnEvent", function(_, _, slot)
    if equipBusy or not (addon.initialized and addon.db
        and addon.db.offspecWarn and addon.db.activeOutfit) then
        return
    end
    local link = slot and GetInventoryItemLink
        and GetInventoryItemLink("player", slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    if not id then return end
    for _, oname in ipairs(addon:GetOutfitsForItemID(id)) do
        if oname ~= addon.db.activeOutfit then
            offspecPending = offspecPending or {}
            offspecPending[oname] = link
            break
        end
    end
    if offspecPending and not offspecFlush and C_Timer and C_Timer.After then
        offspecFlush = true
        C_Timer.After(0.6, function()
            offspecFlush = nil
            if not offspecPending then return end
            for oname, lnk in pairs(offspecPending) do
                addon:Print("|cffff8800" .. string.format(
                    addon:L("MSG_OFFSPEC"), lnk, oname,
                    addon.db.activeOutfit) .. "|r")
            end
            offspecPending = nil
        end)
    end
end)
