local _, ns = ...
local S = ns.S
local L = S.L
local MM = S:NewModule("Minimap")

local _G = _G
local pairs, ipairs, floor, ceil, max = pairs, ipairs, math.floor, math.ceil, math.max
local sort = table.sort
local BLANK = [[Interface\Buttons\WHITE8X8]]

function GetMinimapShape()
	local mm = S.db and S.db.profile.minimap
	return (mm and mm.shape == "SQUARE") and "SQUARE" or "ROUND"
end

local hideList = {
	"MinimapBorder", "MinimapBorderTop", "MinimapZoomIn", "MinimapZoomOut", "MinimapToggleButton", "MiniMapWorldMapButton",
	"MinimapNorthTag", "MinimapCompassTexture", "MinimapBackdrop", "MinimapZoneTextButton", "MiniMapMailBorder",
	"MiniMapTrackingBorder", "MiniMapTrackingBackground", "MiniMapVoiceChatFrame", "MinimapCluster.BorderTop",
}

local function Resolve(path)
	local obj = _G
	for part in path:gmatch("[^%.]+") do
		obj = obj and obj[part]
	end
	return obj
end

function MM:HideBlizzard()
	local db = self.db
	for _, n in ipairs(hideList) do
		local f = Resolve(n)
		if f then
			if f.SetAlpha then f:SetAlpha(0) end
			if f.EnableMouse then f:EnableMouse(false) end
			if f.Hide then f:Hide() end
			if f.UnregisterAllEvents and n ~= "MinimapBackdrop" then pcall(f.UnregisterAllEvents, f) end
		end
	end
	if Minimap.ZoomIn then Minimap.ZoomIn:Hide() Minimap.ZoomIn:SetAlpha(0) end
	if Minimap.ZoomOut then Minimap.ZoomOut:Hide() Minimap.ZoomOut:SetAlpha(0) end
	if Minimap.ZoomHitArea then Minimap.ZoomHitArea:Hide() end
	if MinimapCluster then
		if MinimapCluster.ZoneTextButton then MinimapCluster.ZoneTextButton:SetAlpha(0) MinimapCluster.ZoneTextButton:EnableMouse(false) end
		if MinimapCluster.BorderTop then MinimapCluster.BorderTop:SetAlpha(0) end
		MinimapCluster:EnableMouse(false)
	end
	if db.hideCalendar and GameTimeFrame then GameTimeFrame:SetAlpha(0) GameTimeFrame:EnableMouse(false) end
	if db.hideClock and TimeManagerClockButton then TimeManagerClockButton:SetAlpha(0) TimeManagerClockButton:EnableMouse(false) end
	if db.hideTracking then
		local tracking = MiniMapTracking or MiniMapTrackingFrame or (MinimapCluster and MinimapCluster.Tracking)
		if tracking then tracking:SetAlpha(0) tracking:EnableMouse(false) end
	end
	if MinimapCluster and MinimapCluster.Tracking and not db.hideTracking then
		local t = MinimapCluster.Tracking
		if t.Background then t.Background:SetAlpha(0) end
		t:SetParent(Minimap)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
		t:SetScale(0.8)
	elseif MiniMapTracking and not db.hideTracking then
		MiniMapTracking:ClearAllPoints()
		MiniMapTracking:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, 2)
		MiniMapTracking:SetScale(0.8)
	end
end

function MM:PositionIndicators()
	local mail = MiniMapMailFrame or (MinimapCluster and MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.MailFrame)
	if mail then
		-- always anchor the mail button itself, not the IndicatorFrame;
		-- sits in the top-right corner next to the hamburger menu button
		mail:SetParent(self.holder or Minimap)
		mail:ClearAllPoints()
		mail:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -21, -3)
		mail:SetScale(0.85)
		if mail.SetClampedToScreen then mail:SetClampedToScreen(true) end
		if MiniMapMailIcon then MiniMapMailIcon:SetTexture([[Interface\Minimap\Tracking\Mailbox]]) end
		local mailBorder = _G.MiniMapMailBorder
		if mailBorder then mailBorder:SetAlpha(0) end
		mail:SetShown(self.db.mail and HasNewMail() or false)
	end
	local diff = MiniMapInstanceDifficulty or (MinimapCluster and MinimapCluster.InstanceDifficulty)
	if diff then
		diff:SetParent(Minimap)
		diff:ClearAllPoints()
		diff:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)
		diff:SetAlpha(self.db.difficulty and 1 or 0)
	end
	for _, n in ipairs({ "MiniMapLFGFrame", "MiniMapBattlefieldFrame", "LFGMinimapFrame", "QueueStatusMinimapButton" }) do
		local f = _G[n]
		if f then
			f:SetParent(Minimap)
			f:ClearAllPoints()
			f:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 2)
			local border = _G[n .. "Border"]
			if border then border:SetAlpha(0) end
		end
	end
	local landing = ExpansionLandingPageMinimapButton or GarrisonLandingPageMinimapButton
	if landing then
		landing:SetParent(Minimap)
		landing:ClearAllPoints()
		landing:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -6, -6)
		landing:SetScale(0.6)
		if not landing.suiHooked then
			landing.suiHooked = true
			hooksecurefunc(landing, "SetPoint", function(b, _, rel)
				if rel ~= Minimap then b:ClearAllPoints() b:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -6, -6) end
			end)
		end
	end
end

-- Own minimap button (left = options, right = movers, drag along the rim)
function MM:CreateAddonButton()
	local btn = CreateFrame("Button", "SentinelUIMinimapButton", Minimap)
	btn:SetSize(26, 26)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(9)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(S.media.logo or [[Interface\Buttons\UI-Panel-MinimizeButton-Up]])
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	S:CreateBackdrop(btn, "Default")
	S:AddHover(btn)
	local tick = btn:CreateTexture(nil, "OVERLAY")
	tick:SetTexture(BLANK)
	tick:SetSize(10, 2)
	tick:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
	S:RegisterAccent(tick, "texture")

	function btn:UpdatePosition()
		local angle = math.rad(S.db.global.minimapButtonAngle or 220)
		local r = Minimap:GetWidth() / 2
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * (r + 3), math.sin(angle) * (r + 3))
	end
	btn:UpdatePosition()

	btn:RegisterForClicks("AnyUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnDragStart", function(b)
		b:SetScript("OnUpdate", function()
			b.dragged = true
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			cx, cy = cx / scale - mx, cy / scale - my
			S.db.global.minimapButtonAngle = math.deg(math.atan2(cy, cx))
			b:UpdatePosition()
		end)
	end)
	btn:SetScript("OnDragStop", function(b)
		b:SetScript("OnUpdate", nil)
		C_Timer.After(0, function() b.dragged = nil end)
	end)
	btn:SetScript("OnClick", function(b, button)
		if b.dragged then return end
		if button == "RightButton" then S:ToggleMovers() else S:ToggleConfig() end
	end)
	btn:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_LEFT")
		GameTooltip:AddLine(S.title, S.accent.r, S.accent.g, S.accent.b)
		GameTooltip:AddLine(L["Left click: options"], 1, 1, 1)
		GameTooltip:AddLine(L["Right click: move elements"], 1, 1, 1)
		GameTooltip:AddLine(L["Drag: reposition button"], 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.addonButton = btn
end

-- Shared minimap-button factory for SentinelUI modules: SentinelUI look
-- (backdrop + centered icon + hover), draggable along the rim, angle stored
-- in the caller's persistent `store` table. All module buttons register in
-- S.minimapButtons; LayoutMinimapButtons auto-assigns free rim positions so
-- fresh installs never stack several buttons on the same spot.
S.minimapButtons = S.minimapButtons or {}

function S:LayoutMinimapButtons()
	local db = self.db and self.db.global
	local mainAngle = (db and db.minimapButtonAngle) or 220
	local used = { [floor(mainAngle % 360)] = true }
	local pending = {}
	for _, b in pairs(self.minimapButtons) do
		-- buttons collected into a ButtonBars bar are no longer rim children:
		-- skip them so they neither consume an angle slot nor get re-anchored
		if b:GetParent() == Minimap then
			local a = b._mmStore and b._mmStore.angle
			if a then used[floor(a % 360)] = true else pending[#pending + 1] = b end
		end
	end
	sort(pending, function(x, y) return tostring(x:GetName()) < tostring(y:GetName()) end)
	for _, b in ipairs(pending) do
		local a = b._mmPrefAngle
		if not a or used[floor(a % 360)] then
			a = (mainAngle + 26) % 360
			while used[floor(a)] do a = (a + 24) % 360 end
		end
		used[floor(a)] = true
		b.autoAngle = a
		b:UpdatePosition()
	end
end

function S:CreateMinimapButton(opts)
	-- modules may call this more than once (re-init, option toggles): reuse the
	-- existing frame, refresh its handlers and never stack a second icon
	local existing = self.minimapButtons[opts.name] or _G["SentinelUIMinimapButton_" .. opts.name]
	if existing then
		existing._mmOpts = opts
		existing._mmStore = opts.store or existing._mmStore
		existing._mmPrefAngle = opts.angle or existing._mmPrefAngle
		if existing.icon then
			if opts.glyph and existing.icon.SetText then existing.icon:SetText(opts.glyph)
			elseif opts.icon and existing.icon.SetTexture then existing.icon:SetTexture(opts.icon) end
		end
		self.minimapButtons[opts.name] = existing
		self:LayoutMinimapButtons()
		return existing
	end
	local btn = CreateFrame("Button", "SentinelUIMinimapButton_" .. opts.name, Minimap)
	btn:SetSize(26, 26)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(9)
	-- module buttons carry a short accent-colored monogram instead of a WoW
	-- icon: uniform look that marks them as SentinelUI at a glance
	local icon
	if opts.glyph then
		icon = S:FontString(btn, 12, "OUTLINE")
		icon:SetPoint("CENTER", 0, 0)
		icon:SetText(opts.glyph)
		S:RegisterAccent(icon, "text")
	else
		icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetTexture(opts.icon)
		icon:SetSize(18, 18)
		icon:SetPoint("CENTER")
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
	btn.icon = icon
	S:CreateBackdrop(btn, "Default")
	S:AddHover(btn)
	-- accent tick marks the button as part of the SentinelUI button family
	local tick = btn:CreateTexture(nil, "OVERLAY")
	tick:SetTexture(BLANK)
	tick:SetSize(10, 2)
	tick:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
	S:RegisterAccent(tick, "texture")

	local store = opts.store or {}
	btn._mmStore, btn._mmPrefAngle = store, opts.angle
	btn._mmOpts = opts
	function btn:UpdatePosition()
		if self:GetParent() ~= Minimap then return end -- collected into a bar
		local st = self._mmStore or {}
		local o = self._mmOpts or {}
		local angle = math.rad(st.angle or self.autoAngle or o.angle or 220)
		local r = Minimap:GetWidth() / 2
		self:ClearAllPoints()
		self:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * (r + 3), math.sin(angle) * (r + 3))
	end
	S.minimapButtons[opts.name] = btn
	S:LayoutMinimapButtons()

	btn:RegisterForClicks("AnyUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnDragStart", function(b)
		b:SetScript("OnUpdate", function()
			b.dragged = true
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			cx, cy = cx / scale - mx, cy / scale - my
			if b._mmStore then b._mmStore.angle = math.deg(math.atan2(cy, cx)) end
			b:UpdatePosition()
		end)
	end)
	btn:SetScript("OnDragStop", function(b)
		b:SetScript("OnUpdate", nil)
		C_Timer.After(0, function() b.dragged = nil end)
		S:LayoutMinimapButtons()
	end)
	btn:SetScript("OnClick", function(b, button)
		if b.dragged then return end
		local o = b._mmOpts or {}
		if button == "RightButton" then
			if o.onRight then S:SafeCall("MinimapButton:" .. (o.name or ""), o.onRight) end
		elseif o.onLeft then
			S:SafeCall("MinimapButton:" .. (o.name or ""), o.onLeft)
		end
	end)
	btn:SetScript("OnEnter", function(b)
		local o = b._mmOpts or {}
		if not o.tooltip then return end
		GameTooltip:SetOwner(b, "ANCHOR_LEFT")
		S:SafeCall("MinimapButtonTip:" .. (o.name or ""), o.tooltip, b)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return btn
end

-- Hamburger button (top-right corner): opens the classic main menu as a dropdown.
local menuEntries = {
	{ L["Character"], function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end },
	{ L["Spellbook"], function() if ToggleSpellBook then ToggleSpellBook(BOOKTYPE_SPELL) elseif SpellBookFrame then ToggleFrame(SpellBookFrame) end end },
	{ L["Talents"], function() if ToggleTalentFrame then ToggleTalentFrame() elseif PlayerTalentFrame then ToggleFrame(PlayerTalentFrame) end end },
	{ L["Quest Log"], function() if ToggleQuestLog then ToggleQuestLog() elseif QuestLogFrame then ToggleFrame(QuestLogFrame) end end },
	{ L["Social"], function() if ToggleFriendsFrame then ToggleFriendsFrame() elseif FriendsFrame then ToggleFrame(FriendsFrame) end end },
	{ L["Guild"], function() if ToggleGuildFrame then ToggleGuildFrame() elseif GuildFrame then ToggleFrame(GuildFrame) end end },
	{ L["Group Finder"], function() if ToggleLFGParentFrame then ToggleLFGParentFrame() elseif LFGParentFrame then ToggleFrame(LFGParentFrame) elseif PVEFrame then ToggleFrame(PVEFrame) end end },
	{ L["Achievements"], function() if ToggleAchievementFrame then ToggleAchievementFrame() end end },
	{ L["Collections"], function() if ToggleCollectionsJournal then ToggleCollectionsJournal() end end },
	{ L["World Map"], function() if ToggleWorldMap then ToggleWorldMap() elseif WorldMapFrame then ToggleFrame(WorldMapFrame) end end },
	{ L["Macros"], function() if ShowMacroFrame then ShowMacroFrame() elseif ToggleMacroFrame then ToggleMacroFrame() end end },
	{ L["Keybindings"], function() if ToggleKeyBindingFrame then ToggleKeyBindingFrame() end end },
	{ L["Options"], function() if SettingsPanel then ToggleFrame(SettingsPanel) elseif InterfaceOptionsFrame then ToggleFrame(InterfaceOptionsFrame) end end },
	{ L["Main Menu"], function() if GameMenuFrame then ToggleFrame(GameMenuFrame) end end },
}

function MM:CreateMenuButton()
	local btn = CreateFrame("Button", "SentinelUIMinimapMenuButton", Minimap)
	btn:SetSize(16, 16)
	btn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2, -2)
	btn:SetFrameLevel(Minimap:GetFrameLevel() + 10)
	S:CreateBackdrop(btn, "Default", nil, 0)
	for i = 1, 3 do
		local line = btn:CreateTexture(nil, "ARTWORK")
		line:SetTexture(BLANK)
		line:SetSize(8, 1)
		line:SetPoint("CENTER", btn, "CENTER", 0, 4 - i * 3 + 3)
		line:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
	end
	S:AddHover(btn)

	local menu = CreateFrame("Frame", "SentinelUIMinimapMenu", UIParent, S.BackdropTemplate)
	-- TOOLTIP strata: collected-button bars go up to FULLSCREEN_DIALOG and
	-- would otherwise paint over the dropdown and make it look dead
	menu:SetFrameStrata("TOOLTIP")
	menu:SetToplevel(true)
	S:SetTemplate(menu, "Default", "DIALOG")
	menu.buttons = {}
	local rows = 0
	local function AddRow(label, onClick)
		rows = rows + 1
		local b = CreateFrame("Button", nil, menu)
		b:SetHeight(18)
		b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (rows - 1) * 18))
		b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -(4 + (rows - 1) * 18))
		local t = S:FontString(b, 11)
		t:SetPoint("LEFT", 6, 0)
		t:SetText(label)
		b.text = t
		S:AddHover(b)
		if onClick then b:SetScript("OnClick", onClick) end
		menu.buttons[rows] = b
		return b
	end

	-- SentinelUI flyout: our own functions sit in a dedicated submenu that
	-- opens to the left of the main dropdown. Entries resolve the module on
	-- open, so disabled modules simply drop out of the list.
	local suiMenu = CreateFrame("Frame", "SentinelUIMinimapMenuSUI", menu, S.BackdropTemplate)
	suiMenu:SetFrameStrata("TOOLTIP")
	suiMenu:SetToplevel(true)
	S:SetTemplate(suiMenu, "Default", "DIALOG")
	suiMenu.rows = {}
	suiMenu:Hide()
	local suiEntries = {
		{ L["Options"], nil, nil, function() S:ToggleConfig() end },
		{ L["Toggle Movers"], nil, nil, function() S:ToggleMovers() end },
		{ L["Guild Hub"], "GuildHub", "Toggle" },
		{ L["Instance Tracker"], "InstanceTracker", "Toggle" },
		{ L["Instance Resets"], "RaidReset", "Toggle" },
		{ L["Reputation"], "Reputation", "Toggle" },
		{ "SeeLast", "SeeLast", "Toggle" },
		{ "BugFolder", "BugFolder", "OpenSack" },
		{ "ItemSync", "ItemSync", "OpenSearch" },
		{ "Messenger", "Messenger", "Open" },
		{ L["Damage Meter"], "DamageMeter", nil, function(m)
			local w = m.windows and m.windows[1]
			if w then w.hidden = not w.hidden w.frame:SetShown(not w.hidden) end
		end },
		{ L["Announcer"], "Announcer", "ToggleWindow" },
		{ L["Blessings"], "Blessings", "ToggleGrid" },
		{ L["Raid Check"], "RaidCheck", "Toggle" },
		{ L["Heal Grid"], "RaidGrid", "Toggle" },
		{ L["Totem Forge"], "TotemForge", "Toggle" },
		{ L["Quest Scope"], "QuestScope", nil, function() S:ToggleConfig("questscope") end },
		{ L["Boss Watch"], "BossWatch", "ToggleSettings" },
		{ L["Interrupt Alert"], "InterruptAlert", nil, function() S:ToggleConfig("interruptalert") end },
		{ L["Healer Protection"], "HealerProtection", nil, function() S:ToggleConfig("healerprot") end },
		{ L["Decurse"], "Decurse", nil, function(m)
			local f = m.frame or (m.BuildFrame and m:BuildFrame())
			if f then f:SetShown(not f:IsShown()) end
		end },
	}
	local function RefreshSuiMenu()
		local n = 0
		for _, e in ipairs(suiEntries) do
			local m = e[2] and S:GetModule(e[2])
			if not e[2] or (m and m:IsEnabled()) then
				n = n + 1
				local b = suiMenu.rows[n]
				if not b then
					b = CreateFrame("Button", nil, suiMenu)
					b:SetHeight(18)
					local t = S:FontString(b, 11)
					t:SetPoint("LEFT", 6, 0)
					b.text = t
					S:AddHover(b)
					b:SetScript("OnClick", function(btn)
						local en = btn.entry
						local mod = en[2] and S:GetModule(en[2])
						suiMenu:Hide() menu:Hide()
						if en[4] then
							S:SafeCall("SuiMenu:" .. en[1], en[4], mod)
						elseif mod and mod[en[3]] then
							S:SafeCall("SuiMenu:" .. en[1], mod[en[3]], mod)
						end
					end)
					suiMenu.rows[n] = b
				end
				b.entry = e
				b.text:SetText(e[1])
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", suiMenu, "TOPLEFT", 4, -(4 + (n - 1) * 18))
				b:SetPoint("TOPRIGHT", suiMenu, "TOPRIGHT", -4, -(4 + (n - 1) * 18))
				b:Show()
			end
		end
		for i = n + 1, #suiMenu.rows do suiMenu.rows[i]:Hide() end
		local w = 110
		for i = 1, n do
			suiMenu.rows[i].text:SetWidth(0)
			w = math.max(w, suiMenu.rows[i].text:GetStringWidth() + 16)
		end
		suiMenu:SetSize(w, 8 + n * 18)
	end
	local suiRow = AddRow("|cff" .. S.accentHex .. "SentinelUI|r  »")
	suiRow:SetScript("OnEnter", function()
		RefreshSuiMenu()
		suiMenu:ClearAllPoints()
		suiMenu:SetPoint("TOPRIGHT", menu, "TOPLEFT", -2, 0)
		suiMenu:Show()
	end)
	suiRow:SetScript("OnClick", function()
		if suiMenu:IsShown() then suiMenu:Hide() else
			RefreshSuiMenu()
			suiMenu:ClearAllPoints()
			suiMenu:SetPoint("TOPRIGHT", menu, "TOPLEFT", -2, 0)
			suiMenu:Show()
		end
	end)
	for i, entry in ipairs(menuEntries) do
		local b = AddRow(entry[1], function()
			menu:Hide()
			S:SafeCall("MinimapMenu:" .. i, entry[2])
		end)
		b:HookScript("OnEnter", function() suiMenu:Hide() end)
	end
	menu:SetSize(120, 8 + rows * 18)
	menu:Hide()
	menu:HookScript("OnHide", function() suiMenu:Hide() end)
	menu:EnableMouse(true)
	self.menuFrame = menu
	self.menuButton = btn

	btn:RegisterForClicks("AnyUp")
	btn:SetScript("OnClick", function()
		if menu:IsShown() then menu:Hide() return end
		-- widest label sets the width
		local w = 90
		for _, b in ipairs(menu.buttons) do
			b.text:SetWidth(0)
			w = math.max(w, b.text:GetStringWidth() + 16)
		end
		menu:SetWidth(w)
		menu:ClearAllPoints()
		menu:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -2)
		menu:Show()
		btn:SetAlpha(1)
	end)
	btn:SetScript("OnEnter", function(b)
		S.HoverEnter(b)
		GameTooltip:SetOwner(b, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Main Menu"])
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function(b) S.HoverLeave(b) GameTooltip:Hide() end)
	-- close when clicking elsewhere or pressing ESC
	menu:SetScript("OnShow", function()
		tinsert(UISpecialFrames, "SentinelUIMinimapMenu")
	end)
	local watcher = CreateFrame("Frame")
	watcher:Hide()
	watcher:SetScript("OnUpdate", function(f)
		-- the flyout anchors left of the menu, outside its rect: count it too
		-- or every click on a SentinelUI entry would close the menu first
		if not menu:IsMouseOver() and not suiMenu:IsMouseOver() and not btn:IsMouseOver() and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
			menu:Hide()
			f:Hide()
		end
	end)
	menu:HookScript("OnShow", function() watcher:Show() end)
	menu:HookScript("OnHide", function() watcher:Hide() end)
	-- always visible, dimmed at rest and bright on hover
	btn:SetAlpha(0.65)
	btn:HookScript("OnEnter", function() btn:SetAlpha(1) end)
	btn:HookScript("OnLeave", function() btn:SetAlpha(0.65) end)
end

-- Main ----------------------------------------------------------------------
function MM:UpdateZoneText()
	local text = GetMinimapZoneText()
	local pvp = GetZonePVPInfo and GetZonePVPInfo()
	local c = (pvp == "sanctuary" and { 0.41, 0.8, 0.94 }) or (pvp == "arena" and { 1, 0.1, 0.1 }) or (pvp == "friendly" and { 0.1, 1, 0.1 }) or (pvp == "hostile" and { 1, 0.1, 0.1 }) or (pvp == "contested" and { 1, 0.7, 0 }) or (pvp == "combat" and { 1, 0.1, 0.1 }) or { 1, 0.9, 0.7 }
	self.zoneText:SetText(text)
	self.zoneText:SetTextColor(c[1], c[2], c[3])
end

function MM:ApplyShape()
	local round = self.db.shape ~= "SQUARE"
	Minimap:SetMaskTexture(round and S.media.circleMask or BLANK)
	if HybridMinimap and HybridMinimap.CircleMask then HybridMinimap.CircleMask:SetTexture(round and S.media.circleMask or BLANK) end
	if Minimap.suiBackdrop then
		Minimap.suiBackdrop:SetShown(not round)
		if not round then S:SetOutside(Minimap.suiBackdrop, Minimap, 2, 2) end
	end
	if self.ring then self.ring:SetShown(round) self.halo:SetShown(round) end
	for _, t in ipairs(self.corners or {}) do t:SetShown(not round) end
end

function MM:Update()
	local db = self.db
	self:ApplyShape()
	if InCombatLockdown() then return S:RunOutOfCombat(self.Update, self) end
	self.holder:SetSize(db.size, db.size)
	Minimap:SetSize(db.size, db.size)
	if Minimap.SetZoom then
		local z = Minimap:GetZoom()
		Minimap:SetZoom(z > 0 and z - 1 or z + 1)
		Minimap:SetZoom(z)
	end
	S:SetFont(self.zoneText, S.media.font, db.locationFontSize, "OUTLINE")
	if GetCVar("rotateMinimap") ~= (db.rotate and "1" or "0") then pcall(SetCVar, "rotateMinimap", db.rotate and "1" or "0") end
	self.zoneText:SetShown(db.locationText == "SHOW")
	if self.addonButton then
		self.addonButton:SetShown(db.minimapButton ~= false)
		self.addonButton:UpdatePosition()
	end
	S:LayoutMinimapButtons()
	self:PositionIndicators()
end

-- farm mode: world map as a large centered overview
function MM:ToggleFarmMode()
	self.farmMode = not self.farmMode
	local wmf = _G.WorldMapFrame
	if not wmf then return end
	if self.farmMode then
		if C_Map and C_Map.GetBestMapForUnit then
			local mapID = C_Map.GetBestMapForUnit("player")
			if mapID and wmf.SetMapID then wmf:SetMapID(mapID) end
		end
		ShowUIPanel(wmf)
		wmf:ClearAllPoints()
		wmf:SetPoint("CENTER", UIParent, "CENTER")
		wmf:SetSize(UIParent:GetWidth() * 0.94, UIParent:GetHeight() * 0.88)
		if not wmf.suiFarmHook then
			wmf.suiFarmHook = true
			wmf:HookScript("OnShow", function()
				if MM.farmMode then
					wmf:ClearAllPoints()
					wmf:SetPoint("CENTER", UIParent, "CENTER")
					wmf:SetSize(UIParent:GetWidth() * 0.94, UIParent:GetHeight() * 0.88)
				end
			end)
			wmf:HookScript("OnHide", function() MM.farmMode = false end)
		end
	else
		HideUIPanel(wmf)
	end
end

function MM:Initialize()
	local db = self.db
	local holder = CreateFrame("Frame", "SentinelUIMinimapHolder", UIParent)
	holder:SetSize(db.size, db.size)
	S:CreateMover(holder, "minimap", L["Minimap"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -6, -6 }, "minimap")
	self.holder = holder

	Minimap:SetParent(holder)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", holder, "CENTER")
	Minimap:SetSize(db.size, db.size)
	Minimap:SetFrameStrata("LOW")
	Minimap:SetFrameLevel(2)
	if Minimap.SetArchBlobRingScalar then Minimap:SetArchBlobRingScalar(0) Minimap:SetQuestBlobRingScalar(0) end
	S:CreateBackdrop(Minimap, "Default")
	Minimap.suiBackdrop:SetFrameLevel(1)
	-- radar look: amber ring with compass ticks + dark halo behind the circle
	local deco = CreateFrame("Frame", nil, Minimap)
	deco:SetAllPoints()
	deco:SetFrameLevel(Minimap:GetFrameLevel() + 3)
	local halo = holder:CreateTexture(nil, "BACKGROUND")
	halo:SetTexture(S.media.circleMask)
	halo:SetVertexColor(0, 0, 0, 0.75)
	halo:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -5, 5)
	halo:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 5, -5)
	local ring = deco:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(S.media.ring)
	ring:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -3, 3)
	ring:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 3, -3)
	S:RegisterAccent(ring, "texture")
	self.ring, self.halo = ring, halo
	-- square look: amber corner brackets on all four corners (Sentinel signature)
	self.corners = {}
	for _, p in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
		for _, horiz in ipairs({ true, false }) do
			local t = deco:CreateTexture(nil, "OVERLAY", nil, 7)
			t:SetTexture(BLANK)
			t:SetPoint(p, Minimap, p, (p:find("LEFT") and -2 or 2), (p:find("TOP") and 2 or -2))
			if horiz then t:SetSize(14, 2) else t:SetSize(2, 14) end
			S:RegisterAccent(t, "texture")
			self.corners[#self.corners + 1] = t
		end
	end
	self:ApplyShape()
	hooksecurefunc(Minimap, "SetPoint", function(m, _, rel)
		if rel ~= holder and not InCombatLockdown() then m:ClearAllPoints() m:SetPoint("CENTER", holder, "CENTER") end
	end)
	if MinimapCluster and MinimapCluster.SetHeaderUnderneath then
		hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", function() S:SafeCall("Minimap:Header", MM.HideBlizzard, MM) end)
	end

	self:HideBlizzard()

	self.zoneText = S:FontString(Minimap, db.locationFontSize, "OUTLINE", S.media.font)
	self.zoneText:SetPoint("TOP", Minimap, "TOP", 0, -4)
	self.zoneText:SetWidth(db.size - 30)
	self.zoneText:SetDrawLayer("OVERLAY", 7)
	Minimap:HookScript("OnEnter", function() if MM.db.locationText == "MOUSEOVER" then MM.zoneText:Show() end end)
	Minimap:HookScript("OnLeave", function() if MM.db.locationText == "MOUSEOVER" then MM.zoneText:Hide() end end)

	Minimap:EnableMouseWheel(true)
	Minimap:SetScript("OnMouseWheel", function(m, delta)
		if not MM.db.scrollZoom then return end
		if delta > 0 then m:SetZoom(math.min(m:GetZoomLevels() - 1, m:GetZoom() + 1)) else m:SetZoom(math.max(0, m:GetZoom() - 1)) end
		-- zoom reset: jump back to fully zoomed out a few seconds after the last scroll
		if MM.db.zoomReset then
			MM.zoomToken = (MM.zoomToken or 0) + 1
			local token = MM.zoomToken
			C_Timer.After(6, function() if MM.zoomToken == token and m:GetZoom() > 0 then m:SetZoom(0) end end)
		end
	end)
	Minimap:HookScript("OnMouseUp", function(m, button)
		if button == "RightButton" then
			if MiniMapTrackingDropDown and ToggleDropDownMenu then
				ToggleDropDownMenu(1, nil, MiniMapTrackingDropDown, "cursor")
			elseif MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button then
				local b = MinimapCluster.Tracking.Button
				if b.OpenMenu then b:OpenMenu() else b:Click() end
			elseif MiniMapTrackingButton then
				MiniMapTrackingButton:Click()
			end
		elseif button == "MiddleButton" then
			if ToggleCalendar then ToggleCalendar() end
		end
	end)

	self:CreateAddonButton()
	self:CreateMenuButton()
	self:Update()
	self:UpdateZoneText()

	self:RegisterEvent("ZONE_CHANGED", "UpdateZoneText")
	self:RegisterEvent("ZONE_CHANGED_INDOORS", "UpdateZoneText")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "UpdateZoneText")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		MM:UpdateZoneText()
		MM:PositionIndicators()
	end)
	self:RegisterEvent("UPDATE_PENDING_MAIL", "PositionIndicators")
end
