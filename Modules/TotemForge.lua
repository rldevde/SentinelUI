-- TotemForge: complete shaman totem suite (own implementation, SentinelUI name).
-- Four element slots (Earth/Fire/Water/Air) on a movable bar. Each slot casts
-- its selected totem and displays the active totem's icon + remaining duration.
-- Hovering a slot opens a flyout with every known totem of that element:
-- left-click = cast & select, right-click = move up in the order. A recall
-- button casts Totemic Call. Named totem sets store per-element selections.
local _, ns = ...
local S = ns.S
local L = S.L
local TF = S:NewModule("TotemForge", "totemforge")

local _G = _G
local ipairs, pairs, wipe, tinsert, tremove = ipairs, pairs, wipe, table.insert, table.remove
local format = string.format
local strtrim = strtrim
local CreateFrame = CreateFrame
local GetTotemInfo, InCombatLockdown, C_Timer, GetTime = GetTotemInfo, InCombatLockdown, C_Timer, GetTime
local GameTooltip = GameTooltip

local ELEMENTS = { "Earth", "Fire", "Water", "Air" }
local TOTEM_SLOT = { Earth = 2, Fire = 1, Water = 3, Air = 4 } -- classic slot ids (fire=1, earth=2)
local ELEM_COLOR = {
	Earth = { 0.72, 0.45, 0.20 }, Fire = { 0.90, 0.28, 0.16 },
	Water = { 0.20, 0.55, 0.95 }, Air = { 0.55, 0.82, 0.45 },
}
local ELEM_LABEL = { Earth = L["Earth"], Fire = L["Fire"], Water = L["Water"], Air = L["Air"] }

-- totem spell ids per element; names/icons resolve through S.GetSpellInfo so
-- every client/locale uses live data, unlearned entries are skipped
local TOTEMS = {
	Earth = { 2484, 5730, 8071, 8075, 8143, 2062 },
	-- Earthbind, Stoneclaw, Stoneskin, Strength of Earth, Tremor, Earth Elemental
	Fire = { 3599, 1535, 8190, 8181, 8227, 2894, 30706 },
	-- Searing, Fire Nova, Magma, Frost Resistance, Flametongue, Fire Elemental, Totem of Wrath
	Water = { 5394, 5675, 16190, 8166, 8170, 8184 },
	-- Healing Stream, Mana Spring, Mana Tide, Poison Cleansing, Disease Cleansing, Fire Resistance
	Air = { 8177, 10595, 8512, 6495, 8835, 15107, 25908, 3738 },
	-- Grounding, Nature Resistance, Windfury, Sentry, Grace of Air, Windwall, Tranquil Air, Wrath of Air
}
local RECALL = 36936 -- Totemic Call

-- known-totem resolution: persisted order first, then newly learned ones
function TF:Known(e)
	local list, seen = {}, {}
	local ord = self.db.order and self.db.order[e]
	if ord then
		for _, id in ipairs(ord) do
			if S.IsSpellKnown and S.IsSpellKnown(id) then
				local name, _, icon = S.GetSpellInfo(id)
				if name then list[#list + 1] = { id = id, name = name, icon = icon } seen[id] = true end
			end
		end
	end
	for _, id in ipairs(TOTEMS[e]) do
		if not seen[id] and S.IsSpellKnown and S.IsSpellKnown(id) then
			local name, _, icon = S.GetSpellInfo(id)
			if name then list[#list + 1] = { id = id, name = name, icon = icon } end
		end
	end
	return list
end

function TF:RefreshKnown()
	self.known = {}
	for _, e in ipairs(ELEMENTS) do self.known[e] = self:Known(e) end
end

-- secure button factory -------------------------------------------------------
local function SpellButton(parent, name)
	local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "spell")
	b:SetAttribute("type2", "macro") -- right-click is a no-op securely; OnClick handles it
	b:SetAttribute("macrotext2", "")
	S:SetTemplate(b, "Default")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	S:SetInside(b.icon, b, 2, 2)
	return b
end

-- slot (one per element) ------------------------------------------------------
function TF:ApplySlot(e)
	local slot = self.slots[e]
	if not slot then return end
	local list = self.known[e] or {}
	local pick
	local sel = self.db.selected and self.db.selected[e]
	for _, t in ipairs(list) do if t.id == sel then pick = t break end end
	pick = pick or list[1]
	slot.pick = pick
	if pick then
		slot:SetAttribute("spell", pick.name)
		slot.icon:SetTexture(pick.icon)
		slot.icon:SetDesaturated(false)
	else
		slot:SetAttribute("spell", nil)
		slot.icon:SetTexture(nil)
	end
end

function TF:Select(e, id)
	if not self.db.selected then self.db.selected = {} end
	self.db.selected[e] = id
	if InCombatLockdown() then S:RunOutOfCombat(self.ApplySlot, self, e)
	else self:ApplySlot(e) end
end

-- right-click on a flyout item: move it one slot earlier in the order
function TF:MoveUp(e, id)
	local list = self.known[e]
	if not list or #list < 2 then return end
	local pos
	for i, t in ipairs(list) do if t.id == id then pos = i break end end
	if not pos or pos == 1 then return end
	if not self.db.order then self.db.order = {} end
	local ord = {}
	for _, t in ipairs(list) do ord[#ord + 1] = t.id end
	tremove(ord, pos)
	tinsert(ord, pos - 1, id)
	self.db.order[e] = ord
	self.known[e] = self:Known(e)
	self:OpenFlyout(e) -- re-lay out the open flyout
end

-- flyouts ---------------------------------------------------------------------
function TF:OpenFlyout(e)
	local fl = self.flyouts[e]
	local list = self.known[e] or {}
	if not fl or #list == 0 then return end
	local size, spacing = self.db.size or 28, self.db.spacing or 4
	for i, btn in ipairs(fl.btns) do
		local t = list[i]
		if t then
			btn:SetAttribute("spell", t.name)
			btn.icon:SetTexture(t.icon)
			btn.icon:SetDesaturated(false)
			btn.tid, btn.tname = t.id, t.name
			btn:ClearAllPoints()
			btn:SetPoint("LEFT", fl, "LEFT", spacing + (i - 1) * (size + spacing), 0)
			btn:SetSize(size, size)
			btn:Show()
		else
			btn:Hide()
		end
	end
	-- flyout row can grow in any direction; AUTO = up when the bar sits in the
	-- lower half of the screen, down otherwise
	local dir = self.db.flyoutDirection or "UP"
	if dir == "AUTO" then
		local _, cy = self.bar:GetCenter()
		dir = (cy or 0) < (S.screenHeight or 0) * 0.5 and "UP" or "DOWN"
	end
	local n = #list
	if dir == "LEFT" or dir == "RIGHT" then
		fl:SetSize(size + spacing * 2, n * (size + spacing) + spacing)
		for i, btn in ipairs(fl.btns) do
			if list[i] then btn:ClearAllPoints() btn:SetPoint("TOP", fl, "TOP", 0, -(spacing + (i - 1) * (size + spacing))) end
		end
		fl:ClearAllPoints()
		if dir == "LEFT" then fl:SetPoint("RIGHT", self.slots[e], "LEFT", -4, 0)
		else fl:SetPoint("LEFT", self.slots[e], "RIGHT", 4, 0) end
	else
		fl:SetSize(n * (size + spacing) + spacing, size + spacing * 2)
		for i, btn in ipairs(fl.btns) do
			if list[i] then btn:ClearAllPoints() btn:SetPoint("LEFT", fl, "LEFT", spacing + (i - 1) * (size + spacing), 0) end
		end
		fl:ClearAllPoints()
		if dir == "DOWN" then fl:SetPoint("TOP", self.slots[e], "BOTTOM", 0, -4)
		else fl:SetPoint("BOTTOM", self.slots[e], "TOP", 0, 4) end
	end
	fl:Show()
	self.flyoutOpen = e
	C_Timer.After(0.25, function() TF:PollClose() end)
end

function TF:PollClose()
	local e = self.flyoutOpen
	if not e then return end
	local over = self.slots[e]:IsMouseOver() or self.flyouts[e]:IsMouseOver()
	if not over then
		self.flyouts[e]:Hide()
		self.flyoutOpen = nil
	else
		C_Timer.After(0.25, function() TF:PollClose() end)
	end
end

function TF:CloseFlyouts()
	for _, e in ipairs(ELEMENTS) do if self.flyouts and self.flyouts[e] then self.flyouts[e]:Hide() end end
	self.flyoutOpen = nil
end

-- active totem timers ---------------------------------------------------------
function TF:UpdateTimers()
	if not self.slots then return end
	for _, e in ipairs(ELEMENTS) do
		local slot = self.slots[e]
		local have, _, start, dur, icon = GetTotemInfo(TOTEM_SLOT[e])
		if have and icon then
			slot.icon:SetTexture(icon)
			slot.icon:SetDesaturated(false)
			if self.db.showTimers ~= false then
				slot.cd:SetCooldown(start or 0, dur or 0)
				local left = dur and start and (dur - (GetTime() - start)) or 0
				slot.time:SetText(left > 0 and format("%d", left + 0.5) or "")
			end
		else
			slot.cd:Clear()
			slot.time:SetText("")
			if slot.pick then slot.icon:SetTexture(slot.pick.icon) else slot.icon:SetTexture(nil) end
		end
	end
end

-- totem sets ------------------------------------------------------------------
function TF:SaveSet(name)
	name = strtrim(name or "")
	if name == "" then return end
	if not self.db.sets then self.db.sets = {} end
	local set = {}
	for _, e in ipairs(ELEMENTS) do
		local slot = self.slots[e]
		set[e] = slot and slot.pick and slot.pick.id or nil
	end
	self.db.sets[name] = set
	S:Print(format("%s: %s", L["Totem set saved"], name))
end

function TF:ApplySet(name)
	local set = self.db.sets and self.db.sets[name]
	if not set then return end
	if not self.db.selected then self.db.selected = {} end
	for _, e in ipairs(ELEMENTS) do
		if set[e] then self.db.selected[e] = set[e] end
	end
	if InCombatLockdown() then
		S:RunOutOfCombat(function() for _, e in ipairs(ELEMENTS) do TF:ApplySlot(e) end end)
	else
		for _, e in ipairs(ELEMENTS) do self:ApplySlot(e) end
	end
end

function TF:DeleteSet(name)
	if self.db.sets then self.db.sets[name] = nil end
end

-- small dropdown next to the bar: set manager
function TF:ToggleSetMenu(anchor)
	local menu = self.setMenu
	if menu and menu:IsShown() then menu:Hide() return end
	if not menu then
		menu = CreateFrame("Frame", "SentinelUITotemForgeSets", UIParent, S.BackdropTemplate)
		menu:SetFrameStrata("TOOLTIP")
		S:SetTemplate(menu, "Default", "DIALOG")
		menu.rows = {}
		self.setMenu = menu
	end
	for _, r in ipairs(menu.rows) do r:Hide() end
	local n = 0
	local function Row(text, click, rightClick)
		n = n + 1
		local r = menu.rows[n]
		if not r then
			r = CreateFrame("Button", nil, menu)
			r:SetHeight(18)
			r.text = S:FontString(r, 11)
			r.text:SetPoint("LEFT", 6, 0)
			S:AddHover(r)
			menu.rows[n] = r
		end
		r.text:SetText(text)
		r:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (n - 1) * 18))
		r:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -(4 + (n - 1) * 18))
		r:SetScript("OnClick", function(_, btn)
			if btn == "RightButton" and rightClick then rightClick() else if click then click() end end
			menu:Hide()
		end)
		r:Show()
	end
	Row("|cff" .. S.accentHex .. (L["Save current set"]) .. "|r", function()
		StaticPopup_Show("SUI_TOTEMFORGE_SET")
	end)
	local names = {}
	for k in pairs(self.db.sets or {}) do names[#names + 1] = k end
	table.sort(names)
	for _, nm in ipairs(names) do
		Row(nm .. "  |cff888888(" .. (L["right-click: delete"]) .. ")|r", function() TF:ApplySet(nm) end, function() TF:DeleteSet(nm) end)
	end
	menu:SetSize(200, n * 18 + 8)
	menu:ClearAllPoints()
	menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
	menu:Show()
end

StaticPopupDialogs["SUI_TOTEMFORGE_SET"] = {
	text = L["Name of the totem set:"],
	button1 = SAVE, button2 = CANCEL,
	hasEditBox = true,
	OnAccept = function(self)
		local eb = self.GetEditBox and self:GetEditBox() or self.editBox
		TF:SaveSet(eb and eb:GetText() or "")
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

-- layout ----------------------------------------------------------------------
function TF:Layout()
	if not self.bar then return end
	local size, spacing = self.db.size or 28, self.db.spacing or 4
	local x = spacing
	for _, e in ipairs(ELEMENTS) do
		local slot = self.slots[e]
		slot:SetSize(size, size)
		slot:ClearAllPoints()
		slot:SetPoint("LEFT", self.bar, "LEFT", x, 0)
		x = x + size + spacing
	end
	if self.recallBtn and self.db.showRecall ~= false and self.recallKnown then
		self.recallBtn:SetSize(size, size)
		self.recallBtn:ClearAllPoints()
		self.recallBtn:SetPoint("LEFT", self.bar, "LEFT", x, 0)
		x = x + size + spacing
		self.recallBtn:Show()
	elseif self.recallBtn then
		self.recallBtn:Hide()
	end
	if self.setBtn then
		self.setBtn:SetSize(14, size)
		self.setBtn:ClearAllPoints()
		self.setBtn:SetPoint("LEFT", self.bar, "LEFT", x, 0)
		x = x + 14 + spacing
	end
	self.bar:SetSize(x, size + spacing * 2)
	if S.movers.totemForge then S.movers.totemForge:SetSize(self.bar:GetSize()) end
end

function TF:Update()
	self.db = S.db.profile.totemforge
	if not self.bar then return end
	self:Layout()
end

function TF:Toggle()
	if self.bar then
		self.bar:SetShown(not self.bar:IsShown())
		if not self.bar:IsShown() then self:CloseFlyouts() end
	end
end

-- build -----------------------------------------------------------------------
function TF:Create()
	local bar = CreateFrame("Frame", "SentinelUITotemForge", UIParent)
	S:SetTemplate(bar, "Default")
	self.bar = bar
	self.slots, self.flyouts = {}, {}

	self:RefreshKnown()

	for _, e in ipairs(ELEMENTS) do
		local slot = SpellButton(bar, "SentinelUITotemForge_" .. e)
		slot.suiBorderColor = ELEM_COLOR[e]
		S:SetTemplate(slot, "Default")
		slot.cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
		slot.cd:SetAllPoints(slot.icon)
		slot.time = S:FontString(slot, 11, "OUTLINE")
		slot.time:SetPoint("BOTTOM", slot, "BOTTOM", 0, 2)
		slot.e = e
		slot:SetScript("OnEnter", function(b)
			TF:OpenFlyout(b.e)
			GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
			GameTooltip:SetText(ELEM_LABEL[b.e] or b.e)
			if b.pick then GameTooltip:AddLine(b.pick.name, 0.8, 0.8, 0.8) end
			GameTooltip:AddLine(L["Hover: flyout  |  Click: cast  |  Right-click in flyout: reorder"], 0.5, 0.5, 0.5)
			GameTooltip:Show()
		end)
		slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
		slot:SetScript("OnClick", function(_, btn) if btn == "RightButton" then TF:OpenFlyout(e) end end)
		self.slots[e] = slot
		self:ApplySlot(e)

		local fl = CreateFrame("Frame", "SentinelUITotemForgeFlyout_" .. e, bar, S.BackdropTemplate)
		fl:SetFrameStrata("TOOLTIP")
		S:SetTemplate(fl, "Default", "DIALOG")
		fl.btns = {}
		for i = 1, #TOTEMS[e] do
			local fb = SpellButton(fl, "SentinelUITotemForgeFly_" .. e .. i)
			fb:SetScript("OnClick", function(b, btn)
				if btn == "RightButton" then
					TF:MoveUp(e, b.tid)
				else
					TF:Select(e, b.tid)
				end
			end)
			fb:SetScript("OnEnter", function(b)
				GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
				GameTooltip:SetText(b.tname or "")
				GameTooltip:Show()
			end)
			fb:SetScript("OnLeave", function() GameTooltip:Hide() end)
			fl.btns[i] = fb
		end
		fl:Hide()
		self.flyouts[e] = fl
	end

	-- recall (Totemic Call) when the spell is known
	local rn = S.GetSpellInfo(RECALL)
	self.recallKnown = rn and S.IsSpellKnown and S.IsSpellKnown(RECALL)
	local rb = SpellButton(bar, "SentinelUITotemForge_Recall")
	rb.suiBorderColor = { 0.9, 0.7, 0.2 }
	S:SetTemplate(rb, "Default")
	if rn then
		local _, _, ricon = S.GetSpellInfo(RECALL)
		rb.icon:SetTexture(ricon)
		rb:SetAttribute("spell", rn)
	end
	rb:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
		GameTooltip:SetText(rn or L["Totemic Call"])
		GameTooltip:Show()
	end)
	rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.recallBtn = rb

	-- set-manager cap
	local sb = CreateFrame("Button", "SentinelUITotemForge_Sets", bar)
	sb.text = S:FontString(sb, 12, "OUTLINE")
	sb.text:SetPoint("CENTER", 0, 0)
	sb.text:SetText("|cff" .. S.accentHex .. "+|r")
	S:CreateBackdrop(sb, "Default")
	S:AddHover(sb)
	sb:SetScript("OnClick", function(b) TF:ToggleSetMenu(b) end)
	sb:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Totem Sets"])
		GameTooltip:Show()
	end)
	sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.setBtn = sb

	S:CreateMover(bar, "totemForge", L["Totem Forge"], { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 490, 70 }, "general")
	self:Layout()
	self:UpdateTimers()
end

function TF:Initialize()
	self.db = S.db.profile.totemforge
	if S.myClass ~= "SHAMAN" then return end
	self:Create()
	self:RegisterEvent("PLAYER_TOTEM_UPDATE", function() TF:UpdateTimers() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		TF:RefreshKnown()
		for _, e in ipairs(ELEMENTS) do TF:ApplySlot(e) end
		TF:UpdateTimers()
	end)
	self:RegisterEvent("SPELLS_CHANGED", function()
		S:RunOutOfCombat(function()
			TF:RefreshKnown()
			for _, e in ipairs(ELEMENTS) do TF:ApplySlot(e) end
		end)
	end)
	-- time text on active totems
	self.ticker = C_Timer.NewTicker(1, function()
		if TF.bar and TF.bar:IsShown() then TF:UpdateTimers() end
	end)
end

-- /suitf - toggle the bar | /suitf save <name> | /suitf delete <name>
SLASH_SUITOTEMFORGE1 = "/suitf"
SLASH_SUITOTEMFORGE2 = "/suitotem"
SlashCmdList.SUITOTEMFORGE = function(msg)
	msg = strtrim(msg or "")
	local cmd, arg = msg:match("^(%S+)%s*(.*)$")
	if not cmd then
		TF:Toggle()
		return
	end
	cmd = cmd:lower()
	if cmd == "save" then
		TF:SaveSet(arg)
	elseif cmd == "delete" or cmd == "del" then
		TF:DeleteSet(arg)
	elseif cmd == "apply" or cmd == "load" then
		TF:ApplySet(arg)
	elseif cmd == "options" or cmd == "config" then
		S:ToggleConfig("totemforge")
	end
end
