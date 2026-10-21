local _, ns = ...
local S = ns.S
local L = S.L

local frame
local page = 1

local function SetupCVars()
	local cvars = {
		lockActionBars = 1, ActionButtonUseKeyDown = 1, alwaysShowActionBars = 1, autoLootDefault = 1,
		chatStyle = "classic", whisperMode = "inline", chatMouseScroll = 1, showTutorials = 0,
		UberTooltips = 1, cameraDistanceMaxZoomFactor = S.isRetail and 2.6 or 4, screenshotQuality = 10,
		nameplateShowEnemies = 1, nameplateMotion = 1, threatWarning = 3, statusTextDisplay = "BOTH",
		countdownForCooldowns = 0, UnitNameOwn = 0,
	}
	for k, v in pairs(cvars) do pcall(SetCVar, k, v) end
	if InterfaceOptionsActionBarsPanelPickupActionKeyDropDown then pcall(SetModifiedClick, "PICKUPACTION", "SHIFT") end
	S:Print(L["CVars applied."])
end

local function SetupChat()
	if InCombatLockdown() then S:Print(ERR_NOT_IN_COMBAT) return end
	FCF_ResetChatWindows()
	if ChatConfigFrame_ReloadChatSettings then pcall(ChatConfigFrame_ReloadChatSettings) end
	FCF_OpenNewWindow(LOOT)
	FCF_SetLocked(ChatFrame1, true)
	local loot
	for i = 1, NUM_CHAT_WINDOWS do
		local name = GetChatWindowInfo(i)
		if name == LOOT then loot = _G["ChatFrame" .. i] end
	end
	if loot then
		FCF_UnDockFrame(loot)
		FCF_SetLocked(loot, true)
		ChatFrame_RemoveAllMessageGroups(loot)
		for _, g in ipairs({ "LOOT", "MONEY", "SKILL", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "CURRENCY", "TRADESKILLS", "OPENING" }) do
			pcall(ChatFrame_AddMessageGroup, loot, g)
		end
		for _, g in ipairs({ "LOOT", "MONEY", "SKILL", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "CURRENCY", "TRADESKILLS", "OPENING" }) do
			pcall(ChatFrame_RemoveMessageGroup, ChatFrame1, g)
		end
		loot:Show()
	end
	for i = 1, NUM_CHAT_WINDOWS do
		local f = _G["ChatFrame" .. i]
		if f then FCF_SetChatWindowFontSize(nil, f, 12) end
	end
	local ch = S:GetModule("Chat")
	if ch and ch.initialized then ch:PositionChat() end
	S:Print(L["Chat set up."])
end

local function LayoutHealer()
	local m = S.db.profile.movers
	m.raid = "BOTTOM,UIParent,BOTTOM,0,260"
	m.raid40 = "BOTTOM,UIParent,BOTTOM,0,260"
	m.party = "BOTTOM,UIParent,BOTTOM,0,330"
	m.player = "BOTTOMRIGHT,UIParent,BOTTOM,-280,250"
	m.target = "BOTTOMLEFT,UIParent,BOTTOM,280,250"
	S.db.profile.unitframes.units.party.growth = "RIGHT"
	S.db.profile.unitframes.units.party.width = 110
	S.db.profile.unitframes.units.party.spacing = 4
	S:Print(L["Healer layout applied. Reload to finish."])
end

local function LayoutDPS()
	local m = S.db.profile.movers
	for _, k in ipairs({ "raid", "raid40", "party", "player", "target" }) do m[k] = nil end
	local d = S.defaults.profile.unitframes.units.party
	S.db.profile.unitframes.units.party.growth = d.growth
	S.db.profile.unitframes.units.party.width = d.width
	S.db.profile.unitframes.units.party.spacing = d.spacing
	S:Print(L["DPS/Tank layout applied. Reload to finish."])
end

local pages = {
	{
		title = L["Welcome"],
		text = L["This short installation sets up chat, recommended game settings and the layout. You can run it again any time with /sui install."],
	},
	{
		title = L["Settings"],
		text = L["Applies recommended settings: locked action bars, cast on key down, auto loot, classic chat style and more."],
		button = { L["Apply CVars"], SetupCVars },
	},
	{
		title = L["Chat"],
		text = L["Resets the chat windows: General on the left panel and a separate Loot window on the right panel."],
		button = { L["Set up Chat"], SetupChat },
	},
	{
		title = L["UI Scale"],
		text = L["SentinelUI calculates a pixel perfect scale for your resolution automatically. Drag the slider for a custom scale - it applies live. You can change it later under General."],
		button = { L["Auto Scale"], function()
			S.db.profile.general.autoScale = true
			S:SetUIScale()
			S:UpdateTemplates()
			if frame and frame.scaleSlider then
				frame.scaleSlider.updating = true
				frame.scaleSlider:SetValue(S.db.profile.general.uiScale or 0.71)
				frame.scaleSlider.updating = nil
			end
		end },
		scaleUI = true,
	},
	{
		title = L["Layout"],
		text = L["Choose where your group and raid frames should be placed."],
		button = { L["DPS / Tank"], LayoutDPS },
		button2 = { L["Healer"], LayoutHealer },
	},
	{
		title = L["Health Bars"],
		text = L["How should unit health bars look? Dark (Sentinel) shows a dark bar with a subtle class tint - the class color sits on the edge strip and the name. Class Colors fills the whole bar with the class color."],
		button = { L["Dark (Sentinel)"], function()
			local c = S.db.profile.unitframes.colors
			c.healthMode, c.healthClass = "DARK", true
			S:SafeCall("Install:HealthDark", S.RefreshAll, S)
			S:Print(L["Health bars: dark"])
		end },
		button2 = { L["Class Colors"], function()
			local c = S.db.profile.unitframes.colors
			c.healthMode, c.healthClass = "CLASS", true
			S:SafeCall("Install:HealthClass", S.RefreshAll, S)
			S:Print(L["Health bars: class colors"])
		end },
	},
	{
		title = L["Done"],
		text = L["Installation complete. Use /sui for options, /sui move to move elements and /sui kb for keybinds. Errors are written to the SentinelUI log (/sui log)."] .. "\n\n" .. L["Bugtracker"] .. ": |cffebad33" .. S.bugtracker .. "|r",
		button = { L["Finish & Reload"], function() S.private.install_complete = true ReloadUI() end },
		button2 = { L["Report a Bug"], function() S:ShowBugtracker() end },
	},
}

local function ShowPage(n)
	page = math.max(1, math.min(#pages, n))
	local p = pages[page]
	frame.title:SetText(p.title)
	frame.text:SetText(p.text)
	frame.pageText:SetFormattedText("STEP %d / %d", page, #pages)
	-- sidebar step list: accent marker + highlight on the active step
	for i, row in ipairs(frame.steps) do
		local active = i == page
		row.dot:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, active and 1 or 0.25)
		row.num:SetTextColor(S.accent.r, S.accent.g, S.accent.b, active and 1 or 0.35)
		row.label:SetTextColor(active and 1 or 0.5, active and 1 or 0.5, active and 1 or 0.55)
		row.hl:SetShown(active)
	end
	for i, key in ipairs({ "button", "button2" }) do
		local b = frame["option" .. i]
		if p[key] then
			b:SetText(p[key][1])
			b:SetScript("OnClick", function() S:SafeCall("Install:" .. page, p[key][2]) end)
			b:Show()
		else
			b:Hide()
		end
	end
	if p.button2 then
		frame.option1:ClearAllPoints()
		frame.option1:SetPoint("BOTTOMRIGHT", frame.content, "BOTTOM", -4, 64)
	else
		frame.option1:ClearAllPoints()
		frame.option1:SetPoint("BOTTOM", frame.content, "BOTTOM", 0, 64)
	end
	if frame.scaleUI then
		frame.scaleUI:SetShown(p.scaleUI == true)
		if p.scaleUI then
			frame.scaleSlider.updating = true
			frame.scaleSlider:SetValue(S.db.profile.general.uiScale or 0.71)
			frame.scaleSlider.updating = nil
		end
	end
	frame.prev:SetEnabled(page > 1)
	frame.next:SetEnabled(page < #pages)
end

-- Own installer design: left sidebar with numbered step list + brand mark,
-- content on the right, HUD corner accents on the window edge.
function S:ShowInstall()
	if not frame then
		frame = CreateFrame("Frame", "SentinelUIInstall", UIParent)
		frame:SetSize(600, 400)
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("DIALOG")
		frame:EnableMouse(true)
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
		S:SetTemplate(frame, "Transparent", "TOP")

		-- left sidebar
		local side = CreateFrame("Frame", nil, frame, S.BackdropTemplate)
		side:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
		side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
		side:SetWidth(172)
		S:SetTemplate(side, "Default")

		local brand = S:FontString(side, 17, "OUTLINE")
		brand:SetPoint("TOP", side, "TOP", 0, -20)
		brand:SetText("SENTINEL")
		S:RegisterAccent(brand, "text")
		local sub = S:FontString(side, 10, "NONE")
		sub:SetPoint("TOP", brand, "BOTTOM", 0, -3)
		sub:SetText("UI SETUP")
		sub:SetTextColor(0.5, 0.5, 0.55)

		frame.steps = {}
		for i, p in ipairs(pages) do
			local row = CreateFrame("Frame", nil, side)
			row:SetSize(150, 24)
			row:SetPoint("TOP", side, "TOP", 0, -(64 + (i - 1) * 28))
			local hl = row:CreateTexture(nil, "BACKGROUND")
			hl:SetAllPoints()
			hl:SetTexture(S.media.blank)
			hl:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.10)
			hl:Hide()
			row.hl = hl
			local dot = row:CreateTexture(nil, "ARTWORK")
			dot:SetTexture(S.media.blank)
			dot:SetSize(3, 15)
			dot:SetPoint("LEFT", 8, 0)
			row.dot = dot
			local num = S:FontString(row, 11, "OUTLINE")
			num:SetPoint("LEFT", dot, "RIGHT", 5, 0)
			num:SetFormattedText("%02d", i)
			row.num = num
			local label = S:FontString(row, 11, "NONE")
			label:SetPoint("LEFT", num, "RIGHT", 7, 0)
			label:SetWidth(105)
			label:SetJustifyH("LEFT")
			label:SetText(p.title)
			row.label = label
			frame.steps[i] = row
		end

		-- right content area
		local content = CreateFrame("Frame", nil, frame)
		content:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
		content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		frame.content = content

		frame.title = S:FontString(content, 19, "OUTLINE")
		frame.title:SetPoint("TOPLEFT", content, "TOPLEFT", 26, -30)
		frame.title:SetJustifyH("LEFT")
		S:RegisterAccent(frame.title, "text")
		frame.pageText = S:FontString(content, 10, "OUTLINE")
		frame.pageText:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -34)
		frame.pageText:SetTextColor(0.5, 0.5, 0.55)

		local rule = content:CreateTexture(nil, "ARTWORK")
		rule:SetTexture(S.media.blank)
		rule:SetHeight(1)
		rule:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
		rule:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, 0)
		rule:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.35)

		frame.text = S:FontString(content, 13, "NONE")
		frame.text:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -16)
		frame.text:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", -6, -16)
		frame.text:SetWordWrap(true)
		frame.text:SetJustifyV("TOP")
		frame.text:SetJustifyH("LEFT")
		frame.text:SetTextColor(0.82, 0.82, 0.85)

		local function Btn(text, w)
			local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
			b:SetSize(w or 150, 24)
			b:SetText(text)
			S:SkinButton(b)
			return b
		end
		frame.option1 = Btn("", 170)
		frame.option2 = Btn("", 170)
		frame.option2:SetPoint("BOTTOMLEFT", content, "BOTTOM", 4, 64)

		-- live UI-scale slider, only visible on the "UI Scale" page
		local scaleUI = CreateFrame("Frame", nil, content)
		scaleUI:SetPoint("TOP", frame.text, "BOTTOM", 0, -14)
		scaleUI:SetSize(320, 70)
		scaleUI:Hide()
		frame.scaleUI = scaleUI
		local sLabel = S:FontString(scaleUI, 12, "OUTLINE")
		sLabel:SetPoint("TOP", scaleUI, "TOP", 0, 0)
		local slider = CreateFrame("Slider", "SentinelUIInstallScale", scaleUI)
		slider:SetPoint("TOP", sLabel, "BOTTOM", 0, -12)
		slider:SetSize(280, 16)
		slider:SetOrientation("HORIZONTAL")
		slider:SetMinMaxValues(0.4, 1.15)
		slider:SetValueStep(0.01)
		slider:SetObeyStepOnDrag(true)
		local thumb = slider:CreateTexture(nil, "OVERLAY")
		thumb:SetTexture(S.media.blank)
		thumb:SetSize(8, 14)
		slider:SetThumbTexture(thumb)
		S:SkinSlider(slider)
		frame.scaleSlider = slider
		slider:SetScript("OnValueChanged", function(self, v)
			v = floor(v * 100 + 0.5) / 100
			sLabel:SetFormattedText(L["UI Scale"] .. ": %.0f%%", v * 100)
			if self.updating then return end
			local g = S.db.profile.general
			if math.abs((g.uiScale or 0) - v) > 0.0001 or g.autoScale then
				g.autoScale = false
				g.uiScale = v
				S:SetUIScale()
				S:UpdateTemplates()
			end
		end)
		sLabel:SetFormattedText(L["UI Scale"] .. ": %.0f%%", (S.db.profile.general.uiScale or 0.71) * 100)
		frame.prev = Btn(L["Back"], 100)
		frame.prev:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 18, 20)
		frame.prev:SetScript("OnClick", function() ShowPage(page - 1) end)
		frame.next = Btn(L["Next"], 100)
		frame.next:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -18, 20)
		frame.next:SetScript("OnClick", function() ShowPage(page + 1) end)

		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		S:SkinCloseButton(close)
		close:SetPoint("TOPRIGHT", -6, -6)
		close:SetScript("OnClick", function()
			S.private.install_complete = true
			frame:Hide()
		end)
	end
	frame:Show()
	ShowPage(1)
end
