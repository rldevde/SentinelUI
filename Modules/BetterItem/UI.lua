local addon = RLBetterItem

function addon:CreateMainFrame()
    if self.mainFrame then
        self.mainFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "RLBetterItemMainFrame", UIParent)
    self.mainFrame = f
    -- minimum size so the localized labels always fit
    f:SetSize(math.max(self.db.ui.width or 0, 700),
        math.max(self.db.ui.height or 0, 620))
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.12, 0.95)

    -- Header
    local headerBg = f:CreateTexture(nil, "ARTWORK")
    headerBg:SetPoint("TOPLEFT")
    headerBg:SetPoint("TOPRIGHT")
    headerBg:SetHeight(40)
    headerBg:SetColorTexture(0.2, 0.2, 0.25, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -10)
    title:SetText(addon:L("ADDON_NAME"))

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Tabs
    f.tabs = {}
    f.tabButtons = {}

    local tabNames = {addon:L("TAB_SETTINGS"), addon:L("TAB_WEIGHTS"),
        addon:L("TAB_OUTFITS"), addon:L("TAB_TOOLS"),
        addon:L("TAB_PLAYERS"), addon:L("TAB_ABOUT")}

    for i, name in ipairs(tabNames) do
        local tabBtn = CreateFrame("Button", nil, f)
        tabBtn:SetSize(110, 28)
        tabBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 10 + (i - 1) * 115, -45)

        local tbg = tabBtn:CreateTexture(nil, "BACKGROUND")
        tbg:SetAllPoints()
        tbg:SetColorTexture(0.15, 0.15, 0.18, 1)
        tabBtn.bg = tbg

        local text = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(name)
        tabBtn.text = text

        tabBtn:SetScript("OnClick", function()
            addon:ShowTab(i)
        end)

        f.tabButtons[i] = tabBtn
    end

    for i = 1, #tabNames do
        local tab = CreateFrame("Frame", nil, f)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -78)
        tab:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
        tab:Hide()
        f.tabs[i] = tab
    end

    self:CreateSettingsTab(f.tabs[1])
    self:CreateWeightsTab(f.tabs[2])
    self:CreateOutfitsTab(f.tabs[3])
    self:CreateToolsTab(f.tabs[4])
    self:CreatePlayersTab(f.tabs[5])
    self:CreateAboutTab(f.tabs[6])

    self:ShowTab(1)
end

function addon:ShowTab(index)
    if not self.mainFrame then return end

    for i, tab in ipairs(self.mainFrame.tabs) do
        if i == index then
            tab:Show()
            self.mainFrame.tabButtons[i].bg:SetColorTexture(0.25, 0.25, 0.3, 1)
        else
            tab:Hide()
            self.mainFrame.tabButtons[i].bg:SetColorTexture(0.15, 0.15, 0.18, 1)
        end
    end

    self.currentTab = index
    if index == 2 then
        self:RefreshWeightsList()
    elseif index == 3 then
        self:RefreshOutfitList()
    elseif index == 4 then
        self:RefreshTools()
    elseif index == 5 then
        self:RefreshRadarList()
        if self.RefreshRadar then self:RefreshRadar() end
    elseif index == 1 then
        self:RefreshSettings()
    end
end

-- wraps a tab's content in a scroll frame (scrollbar + mousewheel) so
-- long option lists never spill past the window edge
local function MakeScrollable(parent, contentHeight)
    local scroll = CreateFrame("ScrollFrame", nil, parent,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(math.max((parent.GetWidth and parent:GetWidth() or 660) - 30, 600),
        contentHeight)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local sb = self.ScrollBar
        if not sb then return end
        local mn, mx = sb:GetMinMaxValues()
        sb:SetValue(math.min(mx, math.max(mn, sb:GetValue() - delta * 40)))
    end)
    return content
end

-- ==================== SETTINGS TAB ====================
function addon:CreateSettingsTab(parent)
    parent = MakeScrollable(parent, 760)
    local function CreateCheckbox(dbKey, labelKey, relativeTo, yOffset)
        local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
        if relativeTo then
            cb:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset)
        else
            cb:SetPoint("TOPLEFT", 16, -10)
        end
        cb.Text:SetText(addon:L(labelKey))
        -- keep long localized labels inside the window
        cb.Text:SetFontObject("GameFontHighlightSmall")
        cb.Text:SetWidth(265)
        cb.Text:SetJustifyH("LEFT")
        cb:SetChecked(self.db[dbKey])
        cb:SetScript("OnClick", function(btn)
            addon.db[dbKey] = btn:GetChecked() and true or false
            if addon.ClearUpgradeCache then addon:ClearUpgradeCache() end
            addon:RefreshSettings()
        end)
        return cb
    end

    local cb1 = CreateCheckbox("showScore", "OPT_SHOW_SCORE", nil, 0)
    local cb2 = CreateCheckbox("showUpgrade", "OPT_SHOW_UPGRADE", cb1, -8)
    local cbDiff = CreateCheckbox("showStatDiff", "OPT_SHOW_STATDIFF", cb2, -8)
    local cb3 = CreateCheckbox("socketValue", "OPT_SOCKET_VALUE", cbDiff, -8)
    local cbCaps = CreateCheckbox("checkCaps", "OPT_CHECK_CAPS", cb3, -8)
    local cbBags = CreateCheckbox("showBagIcons", "OPT_BAG_ICONS", cbCaps, -8)
    local cbSell = CreateCheckbox("sellButtonShow", "OPT_SELL_BUTTON", cbBags, -8)
    local cbSound = CreateCheckbox("upgradeAlertSound", "OPT_ALERT_SOUND", cbSell, -8)

    -- minimap button (nested db key -> custom handler)
    local cbMM = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
    cbMM:SetPoint("TOPLEFT", cbSound, "BOTTOMLEFT", 0, -8)
    cbMM.Text:SetText(addon:L("OPT_MINIMAP"))
    cbMM.Text:SetFontObject("GameFontHighlightSmall")
    cbMM:SetScript("OnClick", function(btn)
        addon.db.minimap.hide = not btn:GetChecked()
        addon:CreateMinimapButton()
    end)
    self.cbMinimap = cbMM

    -- vendor sell quality: which max quality the sell button may sell
    local sellLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sellLabel:SetPoint("TOPLEFT", cbMM, "BOTTOMLEFT", 0, -14)
    sellLabel:SetText(addon:L("SELL_QUALITY"))

    local QUAL_KEYS = { "QUALITY_GRAY", "QUALITY_WHITE",
        "QUALITY_GREEN", "QUALITY_BLUE" }
    self.sellQualityButtons = {}
    for i = 0, 3 do
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(58, 20)
        if i == 0 then
            b:SetPoint("TOPLEFT", sellLabel, "BOTTOMLEFT", 0, -6)
        else
            b:SetPoint("LEFT", self.sellQualityButtons[i], "RIGHT", 4, 0)
        end
        -- strip embedded color codes so the active-button highlight works
        b:SetText((addon:L(QUAL_KEYS[i + 1])
            :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        b.label = b.Text
        b.quality = i
        b:SetScript("OnClick", function()
            addon.db.sellQuality = b.quality
            addon:RefreshSettings()
        end)
        self.sellQualityButtons[i + 1] = b
    end

    -- second column (settings got too tall for a single column)
    local cbMulti = CreateCheckbox("showMultiSpec", "OPT_MULTI_SPEC", nil, 0)
    cbMulti:SetPoint("TOPLEFT", parent, "TOPLEFT", 300, -10)
    local cbChar = CreateCheckbox("charSlotArrows", "OPT_CHAR_ARROWS", cbMulti, -8)
    local cbQuest = CreateCheckbox("questMarkers", "OPT_QUEST_MARKERS", cbChar, -8)
    local cbLoot = CreateCheckbox("upgradeAlert", "OPT_UPGRADE_ALERT", cbQuest, -8)
    local cbCScore = CreateCheckbox("charSlotScores", "OPT_CHAR_SCORES", cbLoot, -8)
    local cbRoll = CreateCheckbox("lootRollHints", "OPT_LOOT_ROLL", cbCScore, -8)
    local cbInsp = CreateCheckbox("inspectScores", "OPT_INSPECT", cbRoll, -8)
    local cbPanel = CreateCheckbox("showStatPanel", "OPT_STAT_PANEL", cbInsp, -8)
    cbPanel:SetScript("OnClick", function(btn)
        addon.db.showStatPanel = btn:GetChecked() and true or false
        addon:UpdateStatsPanelVisibility()
        addon:RefreshSettings()
    end)
    local cbOutTT = CreateCheckbox("outfitTooltip", "OPT_OUTFIT_TT", cbPanel, -8)
    local cbOutBag = CreateCheckbox("outfitBagMarks", "OPT_OUTFIT_BAG", cbOutTT, -8)
    local cbOutProt = CreateCheckbox("protectOutfitItems", "OPT_OUTFIT_PROTECT", cbOutBag, -8)
    local cbOutPanel = CreateCheckbox("charOutfitPanel", "OPT_OUTFIT_PANEL", cbOutProt, -8)
    cbOutPanel:SetScript("OnClick", function(btn)
        addon.db.charOutfitPanel = btn:GetChecked() and true or false
        addon:UpdateOutfitPanelVisibility()
        addon:RefreshSettings()
    end)
    local cb4 = CreateCheckbox("autoDetect", "OPT_AUTO_DETECT", cbOutPanel, -8)
    self.cbAutoDetect = cb4

    -- player-tooltip section (extra info on hovered players)
    local ttHead = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ttHead:SetPoint("TOPLEFT", cb4, "BOTTOMLEFT", 0, -14)
    ttHead:SetText("|cffffd700" .. addon:L("OPT_TT_SECTION") .. "|r")

    local cbTT = CreateCheckbox("unitTooltips", "OPT_TT_ENABLE", ttHead, -4)
    local cbTC = CreateCheckbox("ttClassColor", "OPT_TT_CLASSCOLOR", cbTT, -6)
    local cbTG = CreateCheckbox("ttGuild", "OPT_TT_GUILD", cbTC, -6)
    local cbTTar = CreateCheckbox("ttTarget", "OPT_TT_TARGET", cbTG, -6)
    local cbTS = CreateCheckbox("ttSpec", "OPT_TT_SPEC", cbTTar, -6)
    local cbTGS = CreateCheckbox("ttGearScore", "OPT_TT_GEAR", cbTS, -6)
    local cbTP = CreateCheckbox("ttPowerBar", "OPT_TT_POWER", cbTGS, -6)
    local cbTPvP = CreateCheckbox("ttPvPIcon", "OPT_TT_PVP", cbTP, -6)
    local cbTHT = CreateCheckbox("ttHideTitles", "OPT_TT_HIDETITLES", cbTPvP, -6)
    CreateCheckbox("ttHideInCombat", "OPT_TT_HIDECOMBAT", cbTHT, -6)

    -- charframe-related options continue at the bottom of column 1
    -- (there is free space below the sell-quality buttons)
    local cbILvl = CreateCheckbox("charSlotILvl", "OPT_TT_ILVL",
        self.sellQualityButtons[1], -34)
    local cbCGT = CreateCheckbox("charGearText", "OPT_TT_CHARGETEXT", cbILvl, -6)
    local cbGM = CreateCheckbox("gearTextUnlock", "OPT_TT_MOVER", cbCGT, -6)
    local cbEW = CreateCheckbox("enchantWarn", "OPT_ENCHANT_WARN", cbGM, -6)
    local cbIX = CreateCheckbox("itemTipExtra", "OPT_ITEM_EXTRA", cbEW, -6)
    local cbMA = CreateCheckbox("ttMouseAnchor", "OPT_TT_MOUSEANCHOR", cbIX, -6)
    local cbIF = CreateCheckbox("ttInstantFade", "OPT_TT_INSTANTFADE", cbMA, -6)
    local cbDE = CreateCheckbox("deValue", "OPT_DE_VALUE", cbIF, -6)
    local cbRC = CreateCheckbox("rollButtonColors", "OPT_ROLL_COLORS", cbDE, -6)
    local cbGA = CreateCheckbox("gemAdvisor", "OPT_GEM_ADVISOR", cbRC, -6)
    local cbDW = CreateCheckbox("durabilityWarn", "OPT_DURABILITY", cbGA, -6)
    local cbAC = CreateCheckbox("ammoCounter", "OPT_AMMO_COUNTER", cbDW, -6)
    local cbIC = CreateCheckbox("inspectCompare", "OPT_INSPECT_COMPARE", cbAC, -6)
    local cbSB = CreateCheckbox("charScaleBtn", "OPT_CHAR_SCALE_BTN", cbIC, -6)
    local cbUH = CreateCheckbox("upgradeHistory", "OPT_UPGRADE_HISTORY", cbSB, -6)
    local cbSL = CreateCheckbox("shoppingList", "OPT_SHOPPING_LIST", cbUH, -6)
    local cbLG = CreateCheckbox("sellLog", "OPT_SELL_LOG", cbSL, -6)
    local cbSW = CreateCheckbox("setBonusWarn", "OPT_SETWARN", cbLG, -6)
    local cbCP = CreateCheckbox("charProfile", "OPT_CHAR_PROFILE", cbSW, -6)
    local cbDA = CreateCheckbox("durabilityAlert", "OPT_DURALERT", cbCP, -6)
    local cbOW = CreateCheckbox("offspecWarn", "OPT_OFFSPEC", cbDA, -6)
    local cbOB = CreateCheckbox("outfitMatchBorders", "OPT_OUTFIT_BORDERS",
        cbOW, -6)

    -- trinket proc flat bonus (number input)
    local tpLabel = parent:CreateFontString(nil, "OVERLAY",
        "GameFontHighlightSmall")
    tpLabel:SetPoint("TOPLEFT", cbOB, "BOTTOMLEFT", 24, -8)
    tpLabel:SetText(addon:L("OPT_TRINKET_PROC"))
    local tpBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    tpBox:SetSize(46, 20)
    tpBox:SetPoint("LEFT", tpLabel, "RIGHT", 8, 0)
    tpBox:SetAutoFocus(false)
    tpBox:SetNumeric(true)
    tpBox:SetFontObject("ChatFontNormal")
    tpBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 4, right = 4, top = 2, bottom = 2 }
    })
    tpBox:SetBackdropColor(0, 0, 0, 0.8)
    tpBox:SetTextInsets(4, 4, 0, 0)
    tpBox:SetText(tostring(self.db.trinketProcValue or 0))
    tpBox:SetScript("OnEnterPressed", function(eb)
        self.db.trinketProcValue = tonumber(eb:GetText()) or 0
        if self.ClearUpgradeCache then self:ClearUpgradeCache() end
        eb:ClearFocus()
    end)
    tpBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    self.trinketProcBox = tpBox

    self:RefreshSettings()
end

function addon:RefreshSettings()
    if not self.scaleDropdown then return end

    local scaleKey = self:GetActiveScaleKey()
    local scale = self:GetScale(scaleKey)
    local label = (self.db.scale == "auto") and (self:L("OPT_SCALE_AUTO") .. "  →  " .. self:GetScaleName(scale))
        or self:GetScaleName(scale)
    self.scaleDropdown.displayText:SetText(label)

    if self.cbMinimap then
        self.cbMinimap:SetChecked(not (self.db.minimap and self.db.minimap.hide))
    end

    -- highlight the chosen sell-quality button
    if self.sellQualityButtons then
        local q = self.db.sellQuality or 0
        for i, b in ipairs(self.sellQualityButtons) do
            if b.quality == q then
                b.label:SetTextColor(1, 0.82, 0)
            else
                b.label:SetTextColor(1, 1, 1)
            end
        end
    end

    if self.specInfo then
        local detected = self:GetScale(self.detectedScale or scaleKey)
        local pts = self.detectedPts
        local dist = pts and ("  |cff888888(" ..
            tostring(pts[1] or 0) .. "/" .. tostring(pts[2] or 0) ..
            "/" .. tostring(pts[3] or 0) .. ")|r") or ""
        self.specInfo:SetText(self:L("DETECTED_SPEC") .. " " ..
            self:GetScaleName(detected) .. dist)
    end

    -- highlight the active role button: "auto" wins when scale=auto,
    -- otherwise the role of the currently selected scale lights up
    if self.roleButtons then
        local activeRole = (self.db.scale == "auto") and "auto"
            or self:GetScaleRole(self.db.scale)
        for _, b in ipairs(self.roleButtons) do
            if b.role == activeRole then
                b.label:SetTextColor(1, 0.82, 0)
            else
                b.label:SetTextColor(1, 1, 1)
            end
        end
    end
end

function addon:ToggleScaleMenu(dropdown)
    if self.scaleMenu then
        self.scaleMenu:Hide()
        self.scaleMenu = nil
        return
    end

    local _, class = UnitClass("player")
    local scales = self:GetScalesForClass(class)

    local entries = 1 + #scales -- +1 for "auto" entry
    local menu = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    menu:SetSize(dropdown:GetWidth(), entries * 22 + 4)
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    menu:SetBackdropColor(0.1, 0.1, 0.1, 1)
    menu:SetFrameStrata("DIALOG")

    local function AddEntry(i, text, value)
        local btn = CreateFrame("Button", nil, menu)
        btn:SetSize(menu:GetWidth() - 4, 20)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * 22)

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("LEFT", 5, 0)
        t:SetText(text)
        btn.text = t

        btn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 0) end)
        btn:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnClick", function()
            addon.db.scale = value
            if value ~= "auto" and addon.NoteScalePicked then
                addon:NoteScalePicked(value)
            end
            if addon.ClearUpgradeCache then addon:ClearUpgradeCache() end
            addon:RefreshSettings()
            if addon.UpdateStatsPanel then addon:UpdateStatsPanel() end
            addon:Print(addon:L("MSG_SCALE_CHANGED") .. text)
            menu:Hide()
            addon.scaleMenu = nil
        end)
    end

    AddEntry(1, addon:L("OPT_SCALE_AUTO"), "auto")
    for i, scale in ipairs(scales) do
        AddEntry(i + 1, addon:GetScaleName(scale), scale.key)
    end

    self.scaleMenu = menu
end

-- ==================== WEIGHTS TAB ====================
function addon:CreateWeightsTab(parent)
    parent = MakeScrollable(parent, 900)
    self.weightsParent = parent

    -- scale picker: dropdown + detected spec + role quick-switch
    local scaleLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    scaleLabel:SetText(addon:L("OPT_SCALE"))

    local dropdown = CreateFrame("Frame", "RLBI_ScaleDropdown", parent, "BackdropTemplate")
    dropdown:SetSize(220, 24)
    dropdown:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -5)
    dropdown.displayText = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dropdown.displayText:SetPoint("LEFT", 5, 0)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    dropdown:SetBackdropColor(0, 0, 0, 0.8)
    dropdown:SetScript("OnMouseDown", function(btn)
        addon:ToggleScaleMenu(btn)
    end)
    self.scaleDropdown = dropdown

    local specInfo = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specInfo:SetPoint("LEFT", dropdown, "RIGHT", 10, 0)
    specInfo:SetTextColor(0.6, 0.6, 0.6)
    self.specInfo = specInfo

    -- role quick-switch: Auto | Tank | Heiler | DD (only roles the
    -- class actually has - warrior: tank+dd, priest: heal+dd, ...)
    local roleLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    roleLabel:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -14)
    roleLabel:SetText(addon:L("OPT_ROLE"))

    local _, class = UnitClass("player")
    self.roleButtons = {}
    local prevBtn = roleLabel
    local roleList = { "auto" }
    for _, r in ipairs(class and addon:GetRolesForClass(class) or {}) do
        table.insert(roleList, r)
    end
    for i, role in ipairs(roleList) do
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(64, 20)
        if i == 1 then
            b:SetPoint("LEFT", roleLabel, "RIGHT", 8, 0)
        else
            b:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
        end
        b:SetText(addon:L("ROLE_" .. string.upper(role)))
        b.role = role
        b.label = b.Text
        b:SetScript("OnClick", function()
            addon:SetRole(role)
        end)
        self.roleButtons[i] = b
        prevBtn = b
    end

    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", roleLabel, "BOTTOMLEFT", 0, -22)
    header:SetText(addon:L("WEIGHTS_HEADER"))
    self.weightsHeader = header

    local scaleName = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleName:SetPoint("LEFT", header, "RIGHT", 8, 0)
    self.weightsScaleName = scaleName

    -- container for rows
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 40)
    self.weightsContainer = container
    self.weightRows = {}

    local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 22)
    resetBtn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 10)
    resetBtn:SetText(addon:L("BTN_RESET_WEIGHTS"))
    resetBtn:SetScript("OnClick", function()
        local scaleKey = addon:GetActiveScaleKey()
        addon:ResetCustomWeights(scaleKey)
        addon:RefreshWeightsList()
        addon:Print(addon:L("MSG_WEIGHTS_RESET"))
    end)

    local importBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    importBtn:SetSize(90, 22)
    importBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
    importBtn:SetText(addon:L("BTN_IMPORT"))
    importBtn:SetScript("OnClick", function()
        addon:ShowImportExportPopup("import")
    end)

    local exportBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    exportBtn:SetSize(90, 22)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
    exportBtn:SetText(addon:L("BTN_EXPORT"))
    exportBtn:SetScript("OnClick", function()
        addon:ShowImportExportPopup("export")
    end)
end

function addon:RefreshWeightsList()
    if not self.weightsContainer then return end

    -- clear old rows
    for _, row in ipairs(self.weightRows) do
        row:Hide()
        row:SetParent(nil)
    end
    self.weightRows = {}

    local scaleKey = self:GetActiveScaleKey()
    local scale = self:GetScale(scaleKey)
    if not scale then return end

    self.weightsScaleName:SetText("|cffffd700" .. self:GetScaleName(scale) .. "|r")

    -- collect entries: stats that have a weight, plus caps
    local entries = {}
    for _, stat in ipairs(self.StatOrder) do
        local hasDefault = scale.weights[stat] ~= nil
        local hasCustom = self.db.customWeights[scaleKey] and self.db.customWeights[scaleKey][stat] ~= nil
        if hasDefault or hasCustom then
            table.insert(entries, { stat = stat, isCap = false })
        end
    end
    for _, stat in ipairs({ "Hit", "SpellHit", "Expertise", "Defense" }) do
        if self:GetCap(scaleKey, stat) ~= nil then
            table.insert(entries, { stat = stat, isCap = true })
        end
    end

    local rowHeight = 24
    local colWidth = 275

    for i, entry in ipairs(entries) do
        local stat = entry.stat
        local isCap = entry.isCap
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)

        local rowFrame = CreateFrame("Frame", nil, self.weightsContainer)
        rowFrame:SetSize(colWidth, rowHeight)
        rowFrame:SetPoint("TOPLEFT", self.weightsContainer, "TOPLEFT",
            col * (colWidth + 10), -row * (rowHeight + 4))

        local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetWidth(150)
        label:SetJustifyH("LEFT")
        if isCap then
            label:SetText("|cffaaaaaa" .. (self:L("CAP_" .. stat) or (stat .. "-Cap")) .. "|r")
        else
            label:SetText(self:L("STAT_" .. stat) or stat)
        end

        local eb = CreateFrame("EditBox", nil, rowFrame, "BackdropTemplate")
        eb:SetSize(60, 20)
        eb:SetPoint("LEFT", label, "RIGHT", 5, 0)
        eb:SetAutoFocus(false)
        eb:SetFontObject("ChatFontNormal")
        eb:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        eb:SetBackdropColor(0, 0, 0, 0.8)
        eb:SetTextInsets(5, 5, 0, 0)

        local current, default, isCustom
        if isCap then
            current = self:GetCap(scaleKey, stat)
            default = scale.caps and scale.caps[stat] or 0
            isCustom = self.db.customCaps[scaleKey] and self.db.customCaps[scaleKey][stat] ~= nil
        else
            current = self:GetWeight(scaleKey, stat)
            default = scale.weights[stat] or 0
            isCustom = self.db.customWeights[scaleKey] and self.db.customWeights[scaleKey][stat] ~= nil
        end
        eb:SetText(tostring(current))

        local defText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        defText:SetPoint("LEFT", eb, "RIGHT", 6, 0)
        defText:SetTextColor(0.5, 0.5, 0.5)
        defText:SetText("(" .. self:L("WEIGHTS_DEFAULT") .. ": " .. default .. ")")

        eb:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        eb:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(current))
            self:ClearFocus()
        end)
        eb:SetScript("OnEditFocusLost", function(self)
            local n = tonumber(self:GetText())
            if n then
                if isCap then
                    addon:SetCustomCap(scaleKey, stat, n)
                else
                    addon:SetCustomWeight(scaleKey, stat, n)
                end
                addon:Debug(addon:L("MSG_WEIGHT_SET") .. " " .. stat .. " = " .. n)
            else
                self:SetText(tostring(current))
            end
        end)

        -- highlight custom values
        if isCustom then
            eb:SetTextColor(1, 0.82, 0)
        else
            eb:SetTextColor(1, 1, 1)
        end

        table.insert(self.weightRows, rowFrame)
    end
end

-- ==================== IMPORT / EXPORT POPUP ====================
function addon:ShowImportExportPopup(mode, kind)
    kind = kind or "weights" -- "weights" = active scale, "settings" = whole config
    if not self.iePopup then
        local p = CreateFrame("Frame", "RLBetterItemImportExport", UIParent)
        p:SetSize(520, 150)
        p:SetPoint("CENTER")
        p:SetFrameStrata("DIALOG")
        p:SetMovable(true)
        p:EnableMouse(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", function(self) self:StartMoving() end)
        p:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.12, 0.98)

        local border = p:CreateTexture(nil, "ARTWORK")
        border:SetPoint("TOPLEFT", p, "TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 2, -2)
        border:SetColorTexture(0.3, 0.3, 0.35, 1)
        border:SetDrawLayer("ARTWORK", -1)

        p.title = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        p.title:SetPoint("TOPLEFT", 15, -12)

        p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        p.hint:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -8)
        p.hint:SetTextColor(0.6, 0.6, 0.6)

        local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
        eb:SetSize(490, 24)
        eb:SetPoint("TOPLEFT", p.hint, "BOTTOMLEFT", 0, -8)
        eb:SetAutoFocus(false)
        eb:SetFontObject("ChatFontNormal")
        eb:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        eb:SetBackdropColor(0, 0, 0, 0.8)
        eb:SetTextInsets(5, 5, 0, 0)
        eb:SetScript("OnEscapePressed", function() p:Hide() end)
        p.editBox = eb

        p.applyBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        p.applyBtn:SetSize(100, 22)
        p.applyBtn:SetPoint("BOTTOMLEFT", 15, 12)
        p.applyBtn:SetText(addon:L("BTN_APPLY"))

        p.closeBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        p.closeBtn:SetSize(100, 22)
        p.closeBtn:SetPoint("LEFT", p.applyBtn, "RIGHT", 10, 0)
        p.closeBtn:SetText(addon:L("BTN_CLOSE"))
        p.closeBtn:SetScript("OnClick", function() p:Hide() end)

        self.iePopup = p
    end

    local p = self.iePopup
    if mode == "export" then
        p.title:SetText(addon:L("EXPORT_TITLE"))
        p.hint:SetText("")
        p.editBox:SetText(kind == "settings" and self:ExportSettings()
            or self:ExportWeights())
        p.editBox:HighlightText()
        p.applyBtn:Hide()
        p.editBox:SetFocus()
    else
        p.title:SetText(addon:L("IMPORT_TITLE"))
        p.hint:SetText(addon:L("IMPORT_HINT"))
        p.editBox:SetText("")
        p.applyBtn:Show()
        p.applyBtn:SetScript("OnClick", function()
            local count = (kind == "settings")
                and addon:ImportSettings(p.editBox:GetText())
                or addon:ImportWeights(p.editBox:GetText())
            if count and count > 0 then
                addon:Print(count .. addon:L("MSG_IMPORTED"))
                addon:RefreshWeightsList()
                if addon.RefreshTools then addon:RefreshTools() end
                p:Hide()
            else
                addon:Print(addon:L("MSG_IMPORT_FAIL"))
            end
        end)
    end
    p:Show()
end

-- ==================== PLAYERS TAB (addon radar) ====================
function addon:CreatePlayersTab(parent)
    parent = MakeScrollable(parent, 560)

    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    header:SetText("|cffffd700" .. addon:L("RADAR_HEADER") .. "|r")
    self.radarCount = header

    local ownLine = parent:CreateFontString(nil, "OVERLAY",
        "GameFontHighlightSmall")
    ownLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    ownLine:SetText(string.format(addon:L("RADAR_OWN"),
        tostring(addon.version)))

    -- update banner: only visible once a newer version was spotted
    local updLine = parent:CreateFontString(nil, "OVERLAY",
        "GameFontHighlight")
    updLine:SetPoint("TOPLEFT", ownLine, "BOTTOMLEFT", 0, -4)
    updLine:Hide()
    self.radarUpdate = updLine

    -- refresh button
    local refreshBtn = CreateFrame("Button", nil, parent,
        "UIPanelButtonTemplate")
    refreshBtn:SetSize(140, 22)
    refreshBtn:SetPoint("TOPLEFT", updLine, "BOTTOMLEFT", 0, -8)
    refreshBtn:SetText(addon:L("RADAR_REFRESH"))
    refreshBtn:SetScript("OnClick", function()
        if addon.RefreshRadar then addon:RefreshRadar() end
        addon:RefreshRadarList()
    end)

    -- announce toggle + update-notify toggle
    local function MakeRadarCb(key, lkey, anchor)
        local cb = CreateFrame("CheckButton", nil, parent,
            "ChatConfigCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -2, -6)
        local lbl = cb:CreateFontString(nil, "OVERLAY",
            "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(addon:L(lkey))
        cb:SetChecked(addon.db[key] ~= false)
        cb:SetScript("OnClick", function(c)
            addon.db[key] = c:GetChecked() and true or false
        end)
        return cb
    end
    local cbRadar = MakeRadarCb("radar", "OPT_RADAR", refreshBtn)
    local cbNotify = MakeRadarCb("versionNotify", "OPT_VERSION_NOTIFY",
        cbRadar)

    -- result rows
    self.radarRows = {}
    local last = cbNotify
    for i = 1, 20 do
        local row = parent:CreateFontString(nil, "OVERLAY",
            "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 10, i == 1 and -12 or -2)
        row:SetJustifyH("LEFT")
        self.radarRows[i] = row
        last = row
    end
end

function addon:RefreshRadarList()
    if not self.radarRows then return end
    local users = (self.GetRadarUsers and self:GetRadarUsers()) or {}
    if self.radarCount then
        self.radarCount:SetText("|cffffd700" ..
            string.format(self:L("RADAR_HEADER"), #users) .. "|r")
    end
    if self.radarUpdate then
        local nv = self.GetNewestSeenVersion
            and self:GetNewestSeenVersion()
        if nv then
            self.radarUpdate:SetText("|cffff4040" ..
                string.format(self:L("RADAR_UPDATE"), nv) .. "|r")
            self.radarUpdate:Show()
        else
            self.radarUpdate:SetText(self:L("RADAR_UPTODATE"))
            self.radarUpdate:Show()
        end
    end
    for i, row in ipairs(self.radarRows) do
        local u = users[i]
        if u then
            -- version color: green = newer than us, gray = same,
            -- red = older
            local vc = u.rel > 0 and "|cff00ff00"
                or (u.rel < 0 and "|cffff5050" or "|cffaaaaaa")
            local tag = u.rel > 0
                and ("  |cff00ff00(" .. self:L("RADAR_NEWER") .. ")|r")
                or ""
            local agoTxt
            if u.ago < 60 then
                agoTxt = u.ago .. "s"
            else
                agoTxt = string.format("%dm", math.floor(u.ago / 60))
            end
            row:SetText("|cffffffff" .. u.name .. "|r  " .. vc .. "v" ..
                u.ver .. "|r  |cff888888" .. u.channel .. "  " ..
                agoTxt .. "|r" .. tag)
        elseif i == 1 then
            row:SetText("|cff888888" .. self:L("RADAR_EMPTY") .. "|r")
        else
            row:SetText("")
        end
    end
end

-- ==================== ABOUT TAB ====================
function addon:CreateAboutTab(parent)
    parent = MakeScrollable(parent, 640)
    local logo = parent:CreateTexture(nil, "ARTWORK")
    logo:SetSize(96, 96)
    logo:SetPoint("TOP", parent, "TOP", 0, -30)
    logo:SetTexture("Interface\\AddOns\\SentinelUI\\Modules\\BetterItem\\img\\logo.tga")

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", logo, "BOTTOM", 0, -10)
    title:SetText("|cffebad33Sentinel|r|cffffffffUI|r |cffffd700BetterItem|r")

    local version = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    version:SetPoint("TOP", title, "BOTTOM", 0, -5)
    version:SetText(addon:L("VERSION") .. ": " .. self.version)

    local author = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    author:SetPoint("TOP", version, "BOTTOM", 0, -5)
    author:SetText(addon:L("AUTHOR") .. ": |cff00ffffxRL-Dev.de|r")

    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOP", author, "BOTTOM", 0, -20)
    desc:SetWidth(500)
    desc:SetJustifyH("CENTER")
    desc:SetText(addon:L("ABOUT_DESC"))

    local usage = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    usage:SetPoint("TOP", desc, "BOTTOM", 0, -30)
    usage:SetWidth(480)
    usage:SetJustifyH("LEFT")
    usage:SetText(
        addon:L("ABOUT_USAGE_TITLE") .. "\n" ..
        addon:L("ABOUT_USAGE_1") .. "\n" ..
        addon:L("ABOUT_USAGE_2") .. "\n" ..
        addon:L("ABOUT_USAGE_3") .. "\n" ..
        addon:L("ABOUT_USAGE_4") .. "\n" ..
        addon:L("ABOUT_USAGE_5") .. "\n\n" ..
        addon:L("ABOUT_CMD")
    )

    -- bugtracker: WoW can't open URLs, so the link sits in a readonly
    -- edit box that highlights itself for easy copying
    local btLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btLabel:SetPoint("TOP", usage, "BOTTOM", 0, -20)
    btLabel:SetText("|cffffd700" .. addon:L("ABOUT_BUGTRACKER") .. ":|r")

    local btBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    btBox:SetSize(260, 20)
    btBox:SetPoint("TOP", btLabel, "BOTTOM", 0, -4)
    btBox:SetAutoFocus(false)
    btBox:SetFontObject("ChatFontNormal")
    btBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 4, right = 4, top = 2, bottom = 2 }
    })
    btBox:SetBackdropColor(0, 0, 0, 0.8)
    btBox:SetTextInsets(6, 6, 0, 0)
    btBox:SetText("https://xrl-dev.de/bugtracker")
    btBox:SetScript("OnEditFocusGained", function(eb) eb:HighlightText() end)
    btBox:SetScript("OnTextChanged", function(eb)
        eb:SetText("https://xrl-dev.de/bugtracker")
        eb:HighlightText()
    end)
    btBox:SetScript("OnEnterPressed", function(eb)
        eb:HighlightText()
        eb:ClearFocus()
    end)
    btBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)

    -- error log button next to the link: captured errors + copy view
    local logBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    logBtn:SetSize(130, 20)
    logBtn:SetPoint("LEFT", btBox, "RIGHT", 8, 0)
    logBtn:SetText(addon:L("LOG_BTN"))
    logBtn:SetScript("OnClick", function()
        if addon.ShowErrorLog then addon:ShowErrorLog() end
    end)
end

-- ==================== OUTFITS TAB ====================
function addon:CreateOutfitsTab(parent)
    parent = MakeScrollable(parent, 700)
    self.outfitsParent = parent
    self.selectedOutfit = nil

    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    header:SetText(addon:L("OUTFITS_HEADER"))

    -- outfit list (left column)
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    list:SetSize(240, 320)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    list:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    list:SetBackdropColor(0, 0, 0, 0.5)
    self.outfitList = list
    self.outfitRows = {}

    -- name editbox (right column)
    local nameLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", list, "TOPRIGHT", 16, 0)
    nameLabel:SetText(addon:L("OUTFIT_NAME"))

    local nameBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    nameBox:SetSize(200, 24)
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject("ChatFontNormal")
    nameBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 4, right = 4, top = 2, bottom = 2 }
    })
    nameBox:SetBackdropColor(0, 0, 0, 0.8)
    nameBox:SetTextInsets(5, 5, 0, 0)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    self.outfitNameBox = nameBox

    local function Btn(text, x, y, onClick)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(100, 22)
        b:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", x, y)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end

    local function Sel() return self.selectedOutfit end

    Btn(addon:L("OUTFIT_SAVE"), 0, -12, function()
        local ok, err = addon:SaveOutfit(nameBox:GetText(), false)
        addon:Print(err == "exists" and addon:L("MSG_OUTFIT_EXISTS")
            or (ok and addon:L("MSG_OUTFIT_SAVED") or addon:L("MSG_OUTFIT_NONAME")))
        addon:RefreshOutfitList()
    end)
    Btn(addon:L("OUTFIT_OVERWRITE"), 106, -12, function()
        local n = Sel() or nameBox:GetText()
        if addon:SaveOutfit(n, true) then
            addon:Print(addon:L("MSG_OUTFIT_SAVED") .. " " .. tostring(n))
            addon:RefreshOutfitList()
        end
    end)
    Btn(addon:L("OUTFIT_EQUIP"), 0, -40, function()
        if Sel() then addon:EquipOutfit(Sel()) end
        addon:RefreshOutfitList()
    end)
    Btn(addon:L("OUTFIT_DELETE"), 106, -40, function()
        if Sel() then
            addon:DeleteOutfit(Sel())
            self.selectedOutfit = nil
            nameBox:SetText("")
            addon:RefreshOutfitList()
        end
    end)
    Btn(addon:L("OUTFIT_PREVIEW"), 0, -68, function()
        if Sel() then addon:PreviewOutfit(Sel()) end
    end)
    Btn(addon:L("OUTFIT_MACRO"), 106, -68, function()
        if Sel() then addon:CreateOutfitMacro(Sel()) end
    end)
    Btn(addon:L("OUTFIT_ICON"), 106, -96, function()
        if Sel() then addon:ShowIconPicker(Sel()) end
    end)
    Btn(addon:L("OUTFIT_ASSIGN"), 0, -96, function()
        local n = Sel()
        if not n then return end
        local key = addon:GetActiveScaleKey()
        addon.db.autoOutfits = addon.db.autoOutfits or {}
        addon.db.autoOutfits[key] = n
        -- link both ways: this outfit belongs to this scale
        if addon.db.outfits[n] then
            addon.db.outfits[n].scaleKey = key
        end
        addon:Print(string.format(addon:L("MSG_OUTFIT_ASSIGNED"),
            n, addon:GetScaleName(addon:GetScale(key))))
    end)

    -- auto-equip toggle
    local cbAuto = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
    cbAuto:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -126)
    cbAuto.Text:SetText(addon:L("OPT_AUTO_OUTFIT"))
    cbAuto:SetChecked(self.db.autoOutfit)
    cbAuto:SetScript("OnClick", function(btn)
        addon.db.autoOutfit = btn:GetChecked() and true or false
    end)

    -- bar toggle
    local cbBar = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
    cbBar:SetPoint("TOPLEFT", cbAuto, "BOTTOMLEFT", 6, -6)
    cbBar.Text:SetText(addon:L("OPT_OUTFIT_BAR"))
    cbBar:SetChecked(self.db.outfitBarShow)
    cbBar:SetScript("OnClick", function(btn)
        addon.db.outfitBarShow = btn:GetChecked() and true or false
        addon:RefreshOutfitBar()
    end)
    self.cbOutfitBar = cbBar

    -- scale link: which scale this outfit restores when equipped
    local scLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scLabel:SetPoint("TOPLEFT", cbBar, "BOTTOMLEFT", 6, -14)
    scLabel:SetText(addon:L("OUTFIT_SCALE"))

    local scDrop = CreateFrame("Frame", "RLBI_OutfitScaleDropdown", parent,
        "BackdropTemplate")
    scDrop:SetSize(200, 22)
    scDrop:SetPoint("TOPLEFT", scLabel, "BOTTOMLEFT", 0, -5)
    scDrop.displayText = scDrop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scDrop.displayText:SetPoint("LEFT", 5, 0)
    scDrop:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    scDrop:SetBackdropColor(0, 0, 0, 0.8)
    scDrop:SetScript("OnMouseDown", function(btn)
        addon:ToggleOutfitScaleMenu(btn)
    end)
    self.outfitScaleDropdown = scDrop
end

-- dropdown menu that writes the picked scale into the selected outfit
function addon:ToggleOutfitScaleMenu(dropdown)
    if self.outfitScaleMenu then
        self.outfitScaleMenu:Hide()
        self.outfitScaleMenu = nil
        return
    end
    local outfitName = self.selectedOutfit
    if not outfitName or not self.db.outfits[outfitName] then return end

    local _, class = UnitClass("player")
    local scales = self:GetScalesForClass(class)

    local menu = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    menu:SetSize(dropdown:GetWidth(), (#scales + 1) * 22 + 4)
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    menu:SetBackdropColor(0.1, 0.1, 0.1, 1)
    menu:SetFrameStrata("DIALOG")

    local function AddEntry(i, text, value)
        local btn = CreateFrame("Button", nil, menu)
        btn:SetSize(menu:GetWidth() - 4, 20)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * 22)
        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("LEFT", 5, 0)
        t:SetText(text)
        btn.text = t
        btn:SetScript("OnEnter", function() t:SetTextColor(1, 1, 0) end)
        btn:SetScript("OnLeave", function() t:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnClick", function()
            addon.db.outfits[outfitName].scaleKey = value
            if value and addon.NoteScalePicked then
                addon:NoteScalePicked(value)
            end
            if value then
                addon:Print(string.format(addon:L("MSG_OUTFIT_SCALE_SET"),
                    outfitName, addon:GetScaleName(addon:GetScale(value))))
            end
            addon:RefreshOutfitList()
            menu:Hide()
            addon.outfitScaleMenu = nil
        end)
    end

    AddEntry(1, "|cff888888" .. self:L("OUTFIT_SCALE_NONE") .. "|r", nil)
    for i, scale in ipairs(scales) do
        AddEntry(i + 1, self:GetScaleName(scale), scale.key)
    end

    self.outfitScaleMenu = menu
end

function addon:RefreshOutfitList()
    if not self.outfitList then return end
    for _, row in ipairs(self.outfitRows) do row:Hide() end

    local names = self:GetOutfitNames()
    for i, name in ipairs(names) do
        local row = self.outfitRows[i]
        if not row then
            row = CreateFrame("Button", nil, self.outfitList)
            row:SetSize(228, 24)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", 4, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(0.3, 0.3, 0.4, 0.5)
            row:SetScript("OnClick", function(self)
                addon.selectedOutfit = self.outfitName
                addon.outfitNameBox:SetText(self.outfitName)
                addon:RefreshOutfitList()
            end)
            self.outfitRows[i] = row
        end
        row.outfitName = name
        row.icon:SetTexture(self.OutfitIcon(self.db.outfits[name]))
        local active = (self.db.activeOutfit == name) and "  |cff00ff00[A]|r" or ""
        local sel = (self.selectedOutfit == name) and "|cffffd700" or ""
        -- linked scale shown gray behind the name
        local o = self.db.outfits[name]
        local sc = o and o.scaleKey and self:GetScale(o.scaleKey)
        local scText = ""
        if sc then
            local sn = self:GetScaleName(sc)
            scText = "  |cff8899aa(" ..
                (string.match(sn, ":%s*(.+)$") or sn) .. ")|r"
        end
        row.text:SetText(sel .. name .. "|r" .. active .. scText)
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
        row:Show()
    end

    -- reflect the selected outfit's linked scale in the dropdown
    if self.outfitScaleDropdown then
        local txt
        if self.selectedOutfit then
            local o = self.db.outfits[self.selectedOutfit]
            local sc = o and o.scaleKey and self:GetScale(o.scaleKey)
            txt = sc and self:GetScaleName(sc)
                or ("|cff888888" .. self:L("OUTFIT_SCALE_NONE") .. "|r")
        else
            txt = "|cff666666-|r"
        end
        self.outfitScaleDropdown.displayText:SetText(txt)
    end
end

-- ==================== TOOLS TAB ====================
local function MakeSectionHeader(parent, anchor, text, yOff)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if anchor then
        h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff or -16)
    else
        h:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    end
    h:SetText("|cffffd700" .. text .. "|r")
    return h
end

local function MakeRowText(parent, anchor, yOff)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetJustifyH("LEFT")
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 8, yOff or -4)
    return t
end

-- progress-bar row for cap tracking
local function MakeCapBar(parent, anchor)
    local fr = CreateFrame("StatusBar", nil, parent)
    fr:SetSize(260, 14)
    fr:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 8, -4)
    fr:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    fr:SetMinMaxValues(0, 100)
    fr:SetValue(0)
    local bg = fr:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    fr.text = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fr.text:SetPoint("LEFT", 4, 0)
    fr.text:SetJustifyH("LEFT")
    fr:Hide()
    return fr
end

local function MakeDropSlot(parent, anchor, label)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(230, 36)
    b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    b:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    b:SetBackdropColor(0, 0, 0, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(28, 28)
    b.icon:SetPoint("LEFT", 4, 0)
    b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetWidth(190)
    b.text:SetJustifyH("LEFT")
    b.text:SetText("|cff888888" .. label .. "|r")

    local function Grab(self)
        local t, _, link = GetCursorInfo()
        if t == "item" and link then
            self.link = link
            self.icon:SetTexture(select(5, GetItemInfoInstant(link))
                or "Interface\\Icons\\INV_Misc_QuestionMark")
            self.text:SetText(link)
            ClearCursor()
        end
    end
    b:SetScript("OnReceiveDrag", Grab)
    b:SetScript("OnClick", Grab)
    return b
end

function addon:CreateToolsTab(parent)
    parent = MakeScrollable(parent, 1040)
    self.toolsParent = parent

    -- ===== left column =====
    local capsH = MakeSectionHeader(parent, nil, addon:L("TOOLS_CAPS"))
    self.toolCapRows = {}
    local last = capsH
    for i = 1, 4 do
        self.toolCapRows[i] = MakeCapBar(parent, last)
        last = self.toolCapRows[i]
    end

    local weakH = MakeSectionHeader(parent, last, addon:L("TOOLS_WEAKEST"), -18)
    self.toolWeakRows = {}
    last = weakH
    for i = 1, 3 do
        self.toolWeakRows[i] = MakeRowText(parent, last, -4)
        last = self.toolWeakRows[i]
    end

    -- shopping list: slots still missing an enchant or gems
    local shopH = MakeSectionHeader(parent, last, addon:L("TOOLS_SHOPPING"), -18)
    self.toolShopRows = {}
    last = shopH
    for i = 1, 5 do
        self.toolShopRows[i] = MakeRowText(parent, last, -4)
        last = self.toolShopRows[i]
    end

    -- upgrade history for this session
    local histH = MakeSectionHeader(parent, last, addon:L("TOOLS_HISTORY"), -18)
    self.toolHistRows = {}
    last = histH
    for i = 1, 4 do
        self.toolHistRows[i] = MakeRowText(parent, last, -4)
        last = self.toolHistRows[i]
    end

    -- every upgrade currently sitting in bags/bank
    local bagH = MakeSectionHeader(parent, last, addon:L("TOOLS_BAGUPS"), -18)
    self.toolBagRows = {}
    last = bagH
    for i = 1, 6 do
        self.toolBagRows[i] = MakeRowText(parent, last, -4)
        last = self.toolBagRows[i]
    end

    -- item search across bags/bank: type, Enter, results below
    local searchH = MakeSectionHeader(parent, last, addon:L("TOOLS_SEARCH"), -18)
    local schBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    schBox:SetSize(180, 22)
    schBox:SetPoint("TOPLEFT", searchH, "BOTTOMLEFT", 8, -4)
    schBox:SetAutoFocus(false)
    schBox:SetFontObject("ChatFontNormal")
    schBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 4, right = 4, top = 2, bottom = 2 }
    })
    schBox:SetBackdropColor(0, 0, 0, 0.8)
    schBox:SetTextInsets(4, 4, 0, 0)
    self.toolSearchRows = {}
    local sAnchor = schBox
    for i = 1, 4 do
        self.toolSearchRows[i] = MakeRowText(parent, sAnchor, -4)
        sAnchor = self.toolSearchRows[i]
    end
    schBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    schBox:SetScript("OnEnterPressed", function(eb)
        local q = eb:GetText() or ""
        eb:ClearFocus()
        q = string.lower(q)
        local found = {}
        if #q >= 2 then
            addon:ForEachBagItemLink(function(link, bag, slot)
                local nm = GetItemInfo and (GetItemInfo(link))
                if nm and string.lower(nm):find(q, 1, true) then
                    found[#found + 1] = { link = link, bag = bag, slot = slot }
                end
            end, true)
        end
        for i, row in ipairs(addon.toolSearchRows) do
            local e = found[i]
            if e then
                row:SetText(e.link .. "  |cff888888" ..
                    string.format(addon:L("BAG_SLOT"), e.bag, e.slot) .. "|r")
            elseif i == 1 then
                row:SetText("|cff888888" ..
                    (#q >= 2 and addon:L("TOOLS_SEARCH_EMPTY")
                        or addon:L("TOOLS_SEARCH_HINT")) .. "|r")
            else
                row:SetText("")
            end
        end
    end)

    -- ===== right column =====
    local rx = 320
    local compH = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    compH:SetPoint("TOPLEFT", parent, "TOPLEFT", rx, -10)
    compH:SetText("|cffffd700" .. addon:L("TOOLS_COMPARE") .. "|r")

    self.compareSlot1 = MakeDropSlot(parent, compH, addon:L("TOOLS_DROP1"))
    self.compareSlot2 = MakeDropSlot(parent, self.compareSlot1, addon:L("TOOLS_DROP2"))

    local cmpBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    cmpBtn:SetSize(110, 22)
    cmpBtn:SetPoint("TOPLEFT", self.compareSlot2, "BOTTOMLEFT", 0, -6)
    cmpBtn:SetText(addon:L("TOOLS_COMPARE_BTN"))
    self.compareResult = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.compareResult:SetPoint("LEFT", cmpBtn, "RIGHT", 10, 0)
    self.compareResult:SetJustifyH("LEFT")
    -- "try on": each dropped item vs the gear you currently wear
    local function UpText(l)
        local sc, base = addon:GetUpgradeInfo(l)
        if not sc then return "|cff666666-|r" end
        if base and base > 0 then
            local pct = (sc - base) / base * 100
            return (pct >= 0 and "|cff00ff00+" or "|cffff4040") ..
                string.format("%.0f", pct) .. "%|r"
        end
        return "|cff00ff00" .. addon:L("TT_UPGRADE") .. "|r"
    end
    cmpBtn:SetScript("OnClick", function()
        local l1, l2 = addon.compareSlot1.link, addon.compareSlot2.link
        if not l1 and not l2 then
            addon.compareResult:SetText("|cffff5050-|r")
            return
        end
        local key = addon:GetActiveScaleKey()
        local lines = {}
        if l1 then lines[#lines + 1] = "A: " .. UpText(l1) end
        if l2 then lines[#lines + 1] = "B: " .. UpText(l2) end
        if l1 and l2 then
            local s1 = addon:GetItemScore(l1, key) or 0
            local s2 = addon:GetItemScore(l2, key) or 0
            if s1 > 0 and s2 > 0 then
                local hi, lo = math.max(s1, s2), math.min(s1, s2)
                lines[#lines + 1] = string.format(
                    "%.1f vs %.1f  |cff00ff00+%.1f%%|r",
                    s1, s2, (hi - lo) / lo * 100)
            end
        end
        addon.compareResult:SetText(table.concat(lines, "\n"))
    end)

    -- toggle the item in drop slot 1 on/off the wishlist
    local wishBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    wishBtn:SetSize(110, 22)
    wishBtn:SetPoint("TOPLEFT", cmpBtn, "BOTTOMLEFT", 0, -4)
    wishBtn:SetText(addon:L("BTN_WISHLIST"))
    wishBtn:SetScript("OnClick", function()
        local l = addon.compareSlot1.link
        local id = l and ((GetItemInfoInstant and GetItemInfoInstant(l))
            or tonumber(string.match(l, "item:(%d+)") or ""))
        if not id then
            addon:Print("|cffff5050" .. addon:L("TOOLS_DROP1") .. "|r")
            return
        end
        addon.db.wishlist = addon.db.wishlist or {}
        if addon.db.wishlist[id] then
            addon.db.wishlist[id] = nil
            addon:Print(addon:L("MSG_WISHLIST_REMOVE") .. " " .. l)
        else
            addon.db.wishlist[id] = true
            addon:Print(addon:L("MSG_WISHLIST_ADD") .. " " .. l)
        end
    end)

    local shareH = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    shareH:SetPoint("TOPLEFT", wishBtn, "BOTTOMLEFT", 0, -14)
    shareH:SetText("|cffffd700" .. addon:L("TOOLS_SHARE") .. "|r")
    local channels = { "GUILD", "PARTY", "SAY" }
    local prev
    for i, ch in ipairs(channels) do
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(70, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else b:SetPoint("TOPLEFT", shareH, "BOTTOMLEFT", 0, -4) end
        b:SetText(addon:L("SHARE_" .. ch))
        b:SetScript("OnClick", function()
            if SendChatMessage then
                SendChatMessage(addon:ExportWeights(), ch)
                addon:Print(addon:L("MSG_SHARED") .. " → " .. ch)
            end
        end)
        prev = b
    end

    -- full-settings export / import (weights, caps, outfits, toggles)
    local expBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    expBtn:SetSize(146, 22)
    expBtn:SetPoint("TOPLEFT", shareH, "BOTTOMLEFT", 0, -30)
    expBtn:SetText(addon:L("BTN_EXPORT_SET"))
    expBtn:SetScript("OnClick", function()
        addon:ShowImportExportPopup("export", "settings")
    end)
    local impBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    impBtn:SetSize(146, 22)
    impBtn:SetPoint("LEFT", expBtn, "RIGHT", 6, 0)
    impBtn:SetText(addon:L("BTN_IMPORT_SET"))
    impBtn:SetScript("OnClick", function()
        addon:ShowImportExportPopup("import", "settings")
    end)

    local savedH = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    savedH:SetPoint("TOPLEFT", shareH, "BOTTOMLEFT", 0, -60)
    savedH:SetText("|cffffd700" .. addon:L("TOOLS_SCALES") .. "|r")

    local sBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    sBox:SetSize(130, 22)
    sBox:SetPoint("TOPLEFT", savedH, "BOTTOMLEFT", 0, -4)
    sBox:SetAutoFocus(false)
    sBox:SetFontObject("ChatFontNormal")
    sBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 4, right = 4, top = 2, bottom = 2 }
    })
    sBox:SetBackdropColor(0, 0, 0, 0.8)
    sBox:SetTextInsets(4, 4, 0, 0)
    sBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    self.scaleNameBox = sBox

    local sBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    sBtn:SetSize(90, 22)
    sBtn:SetPoint("LEFT", sBox, "RIGHT", 6, 0)
    sBtn:SetText(addon:L("TOOLS_SAVE_SCALE"))
    sBtn:SetScript("OnClick", function()
        local name = sBox:GetText()
        if addon:SaveScaleLibrary(name) then
            addon:Print(addon:L("MSG_SCALE_SAVED") .. " " .. name)
            sBox:SetText("")
            addon:RefreshTools()
        end
    end)

    self.savedScaleRows = {}
    local anchor = sBox
    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(240, 18)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 0, 0)
        local del = CreateFrame("Button", nil, row)
        del:SetSize(16, 16)
        del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        del:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        del:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        del:SetScript("OnClick", function(self)
            addon:DeleteScaleLibrary(self.key)
            addon:Print(addon:L("MSG_SCALE_DELETED") .. " " .. (self.disp or ""))
            addon:RefreshTools()
        end)
        row.del = del
        self.savedScaleRows[i] = row
        anchor = row
        row:Hide()
    end
end

function addon:RefreshTools()
    if not self.toolCapRows then return end

    -- caps as progress bars
    local key = self:GetActiveScaleKey()
    local shown = 0
    for _, stat in ipairs({ "Hit", "SpellHit", "Expertise", "Defense" }) do
        local cap = self:GetCap(key, stat)
        if cap and cap > 0 then
            shown = shown + 1
            local cur = self:GetPlayerRating(key, stat)
            local pct = math.min(100, cur / cap * 100)
            local bar = self.toolCapRows[shown]
            bar:SetValue(pct)
            if cur >= cap then
                bar:SetStatusBarColor(0.1, 0.85, 0.15)
            elseif pct >= 75 then
                bar:SetStatusBarColor(0.95, 0.7, 0.15)
            else
                bar:SetStatusBarColor(0.95, 0.3, 0.15)
            end
            bar.text:SetText(
                tostring(self.StatName and self.StatName(stat) or stat) ..
                ":  " .. cur .. "/" .. cap ..
                "  (" .. string.format("%.0f", pct) .. "%)")
            bar:Show()
        end
    end
    for i = shown + 1, 4 do
        self.toolCapRows[i]:Hide()
    end
    if shown == 0 then
        local bar = self.toolCapRows[1]
        bar:SetValue(0)
        bar:SetStatusBarColor(0.4, 0.4, 0.4)
        bar.text:SetText("|cff888888-|r")
        bar:Show()
    end

    -- weakest items
    local list = {}
    for slot = 1, 18 do
        if slot ~= 4 then
            local link = GetInventoryItemLink("player", slot)
            local score = link and self:GetItemScore(link, key) or 0
            table.insert(list, { link = link, score = score, slot = slot })
        end
    end
    table.sort(list, function(a, b) return a.score < b.score end)
    for i = 1, 3 do
        local e = list[i]
        if e and e.slot then
            -- upgrade finder: best bag/bank item for that slot
            local best, bestScore = self:BestBagItemForSlot(e.slot)
            local hint = ""
            if best and bestScore and bestScore > e.score then
                hint = "  |cff00ff00→ " .. best .. " +" ..
                    string.format("%.0f", (bestScore - e.score) / math.max(e.score, 1) * 100) .. "%|r"
            end
            self.toolWeakRows[i]:SetText(i .. ". " .. (e.link or "|cff666666-|r") ..
                "  |cffffffff" .. string.format("%.1f", e.score) .. "|r" .. hint)
        else
            self.toolWeakRows[i]:SetText("")
        end
    end

    -- shopping list: missing enchants & empty sockets per slot
    local sn = 0
    if self.db.shoppingList then
        for slot = 1, 18 do
            local missE, emptyS, link = self:SlotNeedsAttention("player", slot)
            if sn < #self.toolShopRows and (missE or emptyS > 0) then
                sn = sn + 1
                self.toolShopRows[sn]:SetText((link or "?") .. "  " ..
                    (missE and ("|cffff4040" .. self:L("WANT_ENCHANT") .. "|r  ") or "") ..
                    (emptyS > 0 and ("|cffff8800" .. emptyS .. "× " ..
                        self:L("WANT_GEM") .. "|r") or ""))
            end
        end
    end
    if sn == 0 then
        self.toolShopRows[1]:SetText("|cff00ff00" ..
            self:L("TOOLS_SHOPPING_OK") .. "|r")
        sn = 1
    end
    for i = sn + 1, #self.toolShopRows do
        self.toolShopRows[i]:SetText("")
    end

    -- upgrade history of this session (newest first)
    local hn = 0
    if self.db.upgradeHistory then
        for _, e in ipairs(addon.UpgradeHistory or {}) do
            if hn >= #self.toolHistRows then break end
            hn = hn + 1
            local ago = math.max(0, time() - (e.t or time()))
            local agoStr = ago >= 3600 and string.format("%.0fh", ago / 3600)
                or ago >= 60 and string.format("%.0fm", ago / 60)
                or ago .. "s"
            self.toolHistRows[hn]:SetText(
                (e.pct and ("|cff00ff00+" .. string.format("%.0f", e.pct) ..
                    "%|r ") or "") .. (e.link or "?") ..
                "  |cff666666" .. agoStr .. "|r")
        end
    end
    if hn == 0 then
        self.toolHistRows[1]:SetText("|cff888888" ..
            self:L("TOOLS_HISTORY_EMPTY") .. "|r")
        hn = 1
    end
    for i = hn + 1, #self.toolHistRows do
        self.toolHistRows[i]:SetText("")
    end

    -- all upgrades sitting in bags/bank, sorted by gain
    local ups = {}
    self:ForEachBagItemLink(function(link)
        local sc, base = self:GetUpgradeInfo(link)
        if sc and base and base > 0 and sc > base then
            ups[#ups + 1] = { link = link, pct = (sc - base) / base * 100 }
        elseif sc and (not base or base <= 0) then
            ups[#ups + 1] = { link = link, pct = math.huge } -- empty slot
        end
    end, true)
    table.sort(ups, function(a, b) return a.pct > b.pct end)
    local nBagRows = #self.toolBagRows
    for i = 1, nBagRows do
        local row = self.toolBagRows[i]
        if i == nBagRows and #ups > nBagRows then
            row:SetText("|cff888888… +" .. (#ups - i + 1) ..
                " " .. self:L("AND_MORE") .. "|r")
        elseif ups[i] then
            local p = (ups[i].pct == math.huge) and "▲"
                or ("+" .. string.format("%.0f", ups[i].pct) .. "%")
            row:SetText("|cff00ff00" .. p .. "|r " .. ups[i].link)
        elseif i == 1 then
            row:SetText("|cff888888" .. self:L("TOOLS_BAGUPS_EMPTY") .. "|r")
        else
            row:SetText("")
        end
    end

    -- saved custom scales
    local n = 0
    for key2, sc in pairs(self.db.savedScales or {}) do
        n = n + 1
        local row = self.savedScaleRows[n]
        if row then
            row.del.key = key2
            row.del.disp = sc.name or key2
            row.text:SetText("|cff66ccff" .. row.del.disp .. "|r")
            row:Show()
        end
    end
    for i = n + 1, 6 do self.savedScaleRows[i]:Hide() end
end
