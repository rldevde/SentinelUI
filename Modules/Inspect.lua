-- Inspect: the TBC client has no InspectTalentFrame, so inspected players'
-- talent trees can't be shown at all. This adds our own "Talents" tab to the
-- Inspect window and renders the target's spec from GetTalentInfo(isInspect).
local _, ns = ...
local S = ns.S
local L = S.L
local IN = S:NewModule("Inspect")
local ipairs, pairs = ipairs, pairs
local format, pcall, select = format, pcall, select
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local _G = _G

local CELL, TCOLS = 30, 4

local function Panel(parent, name)
	local f = _G[name]
	if f then return f end
	f = CreateFrame("Frame", name, parent)
	f:Hide()
	S:CreateBackdrop(f, "Transparent")
	-- one tree at a time: text tabs across the top (name + points spent)
	f.tabs = {}
	for c = 1, 3 do
		local t = CreateFrame("Button", nil, f)
		t:SetSize(100, 18)
		t:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (c - 1) * 104, -6)
		S:CreateBackdrop(t, "Transparent")
		t.label = S:FontString(t, 10, "OUTLINE")
		t.label:SetPoint("CENTER", 0, 0)
		t.line = t:CreateTexture(nil, "OVERLAY")
		t.line:SetPoint("BOTTOMLEFT", 3, 1)
		t.line:SetPoint("BOTTOMRIGHT", -3, 1)
		t.line:SetHeight(1.5)
		t.line:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.9)
		t.line:Hide()
		t:SetID(c)
		t:SetScript("OnClick", function(self)
			f.selected = self:GetID()
			IN:Populate()
		end)
		f.tabs[c] = t
	end
	-- scrollable tier x column icon grid for the selected tree
	f.scroll = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
	f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 6)
	if S.SkinScrollBar and f.scroll.ScrollBar then S:SkinScrollBar(f.scroll.ScrollBar) end
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.scroll:SetScrollChild(f.content)
	f.tree = CreateFrame("Frame", nil, f.content)
	f.tree:SetSize(TCOLS * CELL, 1)
	f.tree:SetPoint("TOP", f.content, "TOP", 0, 0)
	f.cells = {}
	f:SetScript("OnHide", function() IN.open = nil end)
	_G[name] = f
	return f
end

local function TalentCell(f, tier, tc)
	local key = tier * 10 + tc
	local cell = f.cells[key]
	if not cell then
		cell = CreateFrame("Button", nil, f.tree)
		cell:SetSize(CELL - 3, CELL - 3)
		S:CreateBackdrop(cell, "Default")
		cell.tex = cell:CreateTexture(nil, "ARTWORK")
		cell.tex:SetPoint("TOPLEFT", 1.5, -1.5)
		cell.tex:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
		cell.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		-- rank pip inside the icon, gold like Blizzard's pips
		cell.rank = S:FontString(cell, 9, "OUTLINE")
		cell.rank:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
		cell.rank:SetTextColor(1, 0.82, 0)
		cell:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tname or "")
			GameTooltip:AddLine(format("%d / %d", self.r or 0, self.mr or 0), 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.cells[key] = cell
	end
	return cell
end

function IN:Populate()
	local f = self.panel
	if not f or not f:IsShown() then return end
	local group = (GetActiveTalentGroup and GetActiveTalentGroup(true)) or 1
	local nTabs = 3
	if GetNumTalentTabs then
		local ok, n = pcall(GetNumTalentTabs, true)
		if ok and n and n > 0 then nTabs = n end
	end
	-- tab labels; default selection = tree with the most points spent
	local best, bestPts = 1, -1
	for c = 1, 3 do
		local t = f.tabs[c]
		local name, spent
		if c <= nTabs and GetTalentTabInfo then
			local ok, a, b, cc, d, e = pcall(GetTalentTabInfo, c, true)
			if ok then
				-- TBC: name, icon, points | newer: id, name, desc, icon, points
				if type(a) == "number" then name, spent = b, e else name, spent = a, cc end
			end
		end
		if name then
			t.label:SetText(format("%s |cff888888(%d)|r", name, spent or 0))
			t:Show()
			if (spent or 0) > bestPts then best, bestPts = c, spent or 0 end
		else
			t:Hide()
		end
	end
	if not f.selected or f.selected > nTabs then f.selected = best end
	for c = 1, 3 do f.tabs[c].line:SetShown(c == f.selected) end
	-- grid for the selected tree only
	for _, cell in pairs(f.cells) do cell:Hide() end
	local maxTier = 0
	if f.selected <= nTabs and GetNumTalents and GetTalentInfo then
		local ok, n = pcall(GetNumTalents, f.selected, true)
		if ok and n then
			for i = 1, n do
				local ok2, tname, tex, tier, tc, r, mr = pcall(GetTalentInfo, f.selected, i, true, nil, group)
				if ok2 and tname and tier and tc then
					local cell = TalentCell(f, tier, tc)
					cell:ClearAllPoints()
					cell:SetPoint("TOPLEFT", f.tree, "TOPLEFT", (tc - 1) * CELL, -(tier - 1) * CELL)
					cell.tex:SetTexture(tex)
					cell.tex:SetDesaturated(r == 0)
					cell.tex:SetVertexColor(1, 1, 1, r == 0 and 0.55 or 1)
					cell.tname, cell.r, cell.mr = tname, r, mr
					cell.rank:SetText(mr > 1 and (r .. "/" .. mr) or "")
					cell:Show()
					if tier > maxTier then maxTier = tier end
				end
			end
		end
	end
	f.content:SetSize(f.scroll:GetWidth() > 0 and f.scroll:GetWidth() or 200, math.max(1, maxTier * CELL))
	f.scroll:UpdateScrollChildRect()
end

function IN:SelectTab(id)
	-- hide every registered subframe, select the tab visually, then show ours
	for _, n in ipairs(_G.INSPECTFRAME_SUBFRAMES or {}) do
		local f = _G[n]
		if f then f:Hide() end
	end
	if PanelTemplates_SelectTab then
		for i = 1, (InspectFrame.numTabs or self.tabId) do
			local t = _G["InspectFrameTab" .. i]
			if t then
				if i == id then PanelTemplates_SelectTab(t) else PanelTemplates_DeselectTab(t) end
			end
		end
	end
	if id == self.tabId and self.panel then
		self.open = true
		self.panel:Show()
		self:Populate()
	end
end

function IN:Setup()
	if self.done or not InspectFrame then return end
	if _G.InspectTalentFrame then return end -- native frame exists (other clients): leave it alone
	if not GetTalentInfo or not GetTalentTabInfo then return end
	self.done = true

	-- anchor inside the paperdoll content area
	local panel = Panel(InspectFrame, "SentinelUIInspectTalents")
	panel:ClearAllPoints()
	if _G.InspectPaperDollFrame then panel:SetAllPoints(_G.InspectPaperDollFrame)
	else panel:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 10, -70) panel:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT", -10, 40) end
	panel:SetFrameLevel((InspectFrame:GetFrameLevel() or 1) + 5)
	self.panel = panel

	-- extend Blizzard's subframe list so their tab switcher knows about us
	local subs = _G.INSPECTFRAME_SUBFRAMES or {}
	subs[#subs + 1] = "SentinelUIInspectTalents"
	_G.INSPECTFRAME_SUBFRAMES = subs
	self.tabId = #subs

	-- create our tab button with whatever tab template the client ships
	local lastTab
	for i = 1, 6 do
		local t = _G["InspectFrameTab" .. i]
		if not t then break end
		lastTab = t
	end
	local tab
	for _, tmpl in ipairs({ "CharacterFrameTabButtonTemplate", "PanelTopTabButtonTemplate", "TabButtonTemplate" }) do
		local ok, btn = pcall(CreateFrame, "Button", "InspectFrameTab" .. self.tabId, InspectFrame, tmpl)
		if ok and btn then tab = btn break end
	end
	if not tab then return end -- no usable template: panel still reachable? skip feature
	tab:SetID(self.tabId)
	tab:SetText(L["Talents"] or "Talents")
	if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
	tab:ClearAllPoints()
	if lastTab then tab:SetPoint("LEFT", lastTab, "RIGHT", -15, 0)
	else tab:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMLEFT", 10, -28) end
	tab:SetFrameLevel((InspectFrame:GetFrameLevel() or 1) + 6)
	if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, InspectFrame, self.tabId) end
	self.tab = tab
	tab:SetScript("OnClick", function()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		IN:SelectTab(IN.tabId)
	end)

	-- when Blizzard switches to another tab, hide our panel
	if type(_G.InspectSwitchTabs) == "function" then
		hooksecurefunc("InspectSwitchTabs", function(i)
			if i ~= IN.tabId and IN.panel then IN.panel:Hide() end
		end)
	else
		for i = 1, self.tabId - 1 do
			local t = _G["InspectFrameTab" .. i]
			if t and t ~= tab then t:HookScript("OnClick", function() if IN.panel then IN.panel:Hide() end end) end
		end
	end

	InspectFrame:HookScript("OnHide", function() if panel then panel:Hide() end end)
	InspectFrame:HookScript("OnShow", function()
		-- re-anchoring after first layout pass keeps us inside the content area
		if _G.InspectPaperDollFrame then panel:SetAllPoints(_G.InspectPaperDollFrame) end
	end)

	self:RegisterEvent("INSPECT_READY", function()
		if IN.open and InspectFrame:IsShown() then IN:Populate() end
		IN:UpdateGearInfo()
	end)
	InspectFrame:HookScript("OnShow", function() IN:UpdateGearInfo() end)
	InspectFrame:HookScript("OnHide", function() IN:ClearGearInfo() end)
end

-- ==================== ENCHANT / GEM OVERLAY ====================
-- slot buttons on the inspect paperdoll get a red "!" when an enchantable
-- slot has no enchant, and tiny gem icons for every socketed gem.
local SLOT_ID = {
	Head = 1, Neck = 2, Shoulder = 3, Back = 15, Chest = 5, Shirt = 4,
	Tabard = 19, Wrist = 9, Hands = 10, Waist = 6, Legs = 7, Feet = 8,
	Finger0 = 11, Finger1 = 12, Trinket0 = 13, Trinket1 = 14,
	MainHand = 16, SecondaryHand = 17, Ranged = 18, Ammo = 0,
}
-- TBC-era enchantable slots (rings are enchanter-only perks, belt buckles
-- do not exist yet, shirts/tabards/necks/trinkets take no enchants)
local ENCH_SLOT = { [1] = true, [3] = true, [5] = true, [7] = true, [8] = true,
	[9] = true, [10] = true, [15] = true, [16] = true, [17] = true, [18] = true }
local gearSlots = {}

local function ParseLink(link)
	-- item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:...
	local _, id, ench, g1, g2, g3, g4 = strsplit(":", link or "")
	return tonumber(ench) or 0,
		tonumber(g1) or 0, tonumber(g2) or 0, tonumber(g3) or 0, tonumber(g4) or 0
end

function IN:ClearGearInfo()
	for _, gs in pairs(gearSlots) do
		if gs.warn then gs.warn:Hide() end
		if gs.gems then for _, t in ipairs(gs.gems) do t:Hide() end end
	end
end

function IN:UpdateGearInfo()
	if not InspectFrame or not InspectFrame:IsShown() then return end
	local unit = InspectFrame.unit or "target"
	if not UnitExists(unit) or not GetInventoryItemLink then return end
	for slotName, slotId in pairs(SLOT_ID) do
		local btn = _G["Inspect" .. slotName .. "Slot"]
		if btn then
			local gs = gearSlots[slotName]
			if not gs then
				gs = { gems = {} }
				gs.warn = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				gs.warn:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -2)
				gs.warn:SetText("|cffff4040!|r")
				for i = 1, 4 do
					local t = btn:CreateTexture(nil, "OVERLAY")
					t:SetSize(10, 10)
					t:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2 + (i - 1) * 11, 2)
					gs.gems[i] = t
				end
				gearSlots[slotName] = gs
			end
			local link = GetInventoryItemLink(unit, slotId)
			local ench, g1, g2, g3, g4 = ParseLink(link)
			gs.warn:SetShown(link and ENCH_SLOT[slotId] and ench == 0)
			local n = 0
			for _, gem in ipairs({ g1, g2, g3, g4 }) do
				if gem and gem > 0 then
					n = n + 1
					local tex = GetItemInfoInstant and select(5, GetItemInfoInstant(gem)) or nil
					if not tex and GetItemIcon then tex = GetItemIcon(gem) end
					gs.gems[n]:SetTexture(tex)
					gs.gems[n]:Show()
				end
			end
			for i = n + 1, 4 do gs.gems[i]:Hide() end
		end
	end
end

function IN:Initialize()
	-- InspectUI/TalentUI are load-on-demand; hook them when they arrive
	self:RegisterEvent("ADDON_LOADED", function(_, _, name)
		if name == "Blizzard_InspectUI" then IN:Setup() end
	end)
	if S.IsAddOnLoaded and S.IsAddOnLoaded("Blizzard_InspectUI") then self:Setup() end
end
