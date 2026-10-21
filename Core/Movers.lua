-- Movers: every SentinelUI element can be unlocked (/sui move) and dragged around.
-- Left drag = move (snaps to other elements / screen edges), left click = select + nudge window,
-- right click = open settings of that element, shift + right click = hide mover, ctrl + right click = reset.
local _, ns = ...
local S = ns.S
local L = S.L

S.movers = {}
S.moverOrder = {}
local gridFrame, moverPanel, nudge, selected
local SNAP = 10
local filter = "ALL"
-- movers registered without a default position get auto-spread slots so they
-- never stack on top of each other at screen center
local fallbackIdx = 0
local function FallbackDefault()
	fallbackIdx = fallbackIdx + 1
	local i = fallbackIdx - 1
	return { "CENTER", "UIParent", "CENTER", -240 + (i % 5) * 120, 140 - floor(i / 5) * 60 }
end

local categories = {
	ALL = L["All"], actionbars = L["Action Bars"], unitframes = L["Unit Frames"], auras = L["Auras"], chat = L["Chat"],
	general = L["General"], minimap = L["Minimap"], bags = L["Bags"], tooltip = L["Tooltip"], databars = L["Data Bars"], datatexts = L["Data Texts"],
}
local categoryOrder = { "ALL", "actionbars", "unitframes", "auras", "chat", "minimap", "bags", "tooltip", "databars", "datatexts", "general" }

local function PointToString(point, rel, relPoint, x, y)
	return format("%s,%s,%s,%d,%d", point, rel or "UIParent", relPoint or point, floor((x or 0) + 0.5), floor((y or 0) + 0.5))
end

local function ParsePoint(str)
	local point, rel, relPoint, x, y = strsplit(",", str)
	return point, rel, relPoint, tonumber(x) or 0, tonumber(y) or 0
end

local function IndexOf(t, v)
	for i, x in ipairs(t) do if x == v then return i end end
end

-- Turns "unitframes" + "player" into the options path { "unitframes", "units", "player" } etc.
local function ResolveConfig(configKey, name)
	if type(configKey) ~= "string" then return configKey end
	local defaults = S.defaults.profile[configKey]
	if not defaults then return configKey end
	local base = name:gsub("Castbar$", ""):gsub("Bar$", "")
	if configKey == "unitframes" and defaults.units[base] then return { "unitframes", "units", base } end
	if type(defaults[name]) == "table" then return { configKey, name } end
	if type(defaults[base]) == "table" then return { configKey, base } end
	return configKey
end

local function Category(mover)
	local c = mover.configKey
	if type(c) == "table" then c = c[1] end
	return c or "general"
end

function S:PositionMover(mover)
	-- protected status propagates to children of secure frames (e.g. action
	-- bar movers) - touching their anchors in combat throws
	-- ADDON_ACTION_BLOCKED, so defer to the next out-of-combat tick
	if InCombatLockdown() and mover.IsProtected and mover:IsProtected() then
		return S:RunOutOfCombat(self.PositionMover, self, mover)
	end
	local saved = self.db.profile.movers[mover.name]
	local point, rel, relPoint, x, y
	if saved then
		point, rel, relPoint, x, y = ParsePoint(saved)
	else
		point, rel, relPoint, x, y = unpack(mover.default)
	end
	local relFrame = type(rel) == "table" and rel or _G[rel or "UIParent"] or UIParent
	if relFrame == mover then relFrame = UIParent end
	x, y = S:Scale(x), S:Scale(y)
	mover:ClearAllPoints()
	if not pcall(mover.SetPoint, mover, point, relFrame, relPoint, x, y) then
		mover:ClearAllPoints()
		mover:SetPoint(point, UIParent, relPoint, x, y)
	end
end

-- Stores the mover position relative to the nearest screen corner/edge (stable across resolutions)
local function SaveCenter(mover, x, y)
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local horiz = x < w / 3 and "LEFT" or x > w * 2 / 3 and "RIGHT" or ""
	local vert = y < h / 3 and "BOTTOM" or y > h * 2 / 3 and "TOP" or ""
	local point = (vert .. horiz ~= "") and (vert .. horiz) or "CENTER"
	local mw, mh = mover:GetWidth(), mover:GetHeight()
	local ox, oy
	if horiz == "LEFT" then ox = x - mw / 2 elseif horiz == "RIGHT" then ox = x + mw / 2 - w else ox = x - w / 2 end
	if vert == "BOTTOM" then oy = y - mh / 2 elseif vert == "TOP" then oy = y + mh / 2 - h else oy = y - h / 2 end
	S.db.profile.movers[mover.name] = PointToString(point, "UIParent", point, ox, oy)
	S:PositionMover(mover)
end

local function GetRect(f)
	local l, b, w, h = f:GetRect()
	if not l then return end
	local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * s, b * s, w * s, h * s
end

local function SavePosition(mover, snap)
	local l, b, w, h = GetRect(mover)
	if not l then return end
	if snap and not IsAltKeyDown() then
		local r, t = l + w, b + h
		local best = { x = SNAP + 1, y = SNAP + 1 }
		local function TryX(edge, target)
			local d = target - edge
			if math.abs(d) < math.abs(best.x) then best.x = d end
		end
		local function TryY(edge, target)
			local d = target - edge
			if math.abs(d) < math.abs(best.y) then best.y = d end
		end
		local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
		TryX(l, 0) TryX(r, sw) TryX(l + w / 2, sw / 2)
		TryY(b, 0) TryY(t, sh) TryY(b + h / 2, sh / 2)
		for _, other in ipairs(S.moverOrder) do
			if other ~= mover and other:IsShown() then
				local ol, ob, ow, oh = GetRect(other)
				if ol then
					local or_, ot = ol + ow, ob + oh
					TryX(l, or_ + 2) TryX(r, ol - 2) TryX(l, ol) TryX(r, or_)
					TryY(b, ot + 2) TryY(t, ob - 2) TryY(b, ob) TryY(t, ot)
				end
			end
		end
		if math.abs(best.x) <= SNAP then l = l + best.x end
		if math.abs(best.y) <= SNAP then b = b + best.y end
	end
	SaveCenter(mover, l + w / 2, b + h / 2)
	if nudge and nudge:IsShown() and selected == mover then nudge:Refresh() end
end

-- Nudge window ---------------------------------------------------------------
local function CreateNudge()
	nudge = CreateFrame("Frame", "SentinelUIMoverNudge", UIParent)
	nudge:SetSize(220, 112)
	nudge:SetFrameStrata("FULLSCREEN_DIALOG")
	nudge:EnableMouse(true)
	nudge:SetMovable(true)
	nudge:SetClampedToScreen(true)
	nudge:RegisterForDrag("LeftButton")
	nudge:SetScript("OnDragStart", nudge.StartMoving)
	nudge:SetScript("OnDragStop", nudge.StopMovingOrSizing)
	S:SetTemplate(nudge, "Transparent", "TOP")
	nudge.title = S:FontString(nudge, 12, "OUTLINE")
	nudge.title:SetPoint("TOP", 0, -6)
	S:RegisterAccent(nudge.title, "text")

	local function Edit(label, x)
		local fs = S:FontString(nudge, 11)
		fs:SetPoint("TOPLEFT", x, -28)
		fs:SetText(label)
		local eb = CreateFrame("EditBox", nil, nudge)
		eb:SetSize(60, 18)
		eb:SetPoint("LEFT", fs, "RIGHT", 6, 0)
		eb:SetAutoFocus(false)
		eb:SetFontObject(ChatFontNormal)
		eb:SetJustifyH("CENTER")
		S:SkinEditBox(eb)
		eb:SetScript("OnEscapePressed", function(e) e:ClearFocus() nudge:Refresh() end)
		eb:SetScript("OnEnterPressed", function(e)
			e:ClearFocus()
			if not selected then return end
			local saved = S.db.profile.movers[selected.name] or PointToString(unpack(selected.default))
			local point, rel, relPoint, px, py = ParsePoint(saved)
			local v = tonumber(e:GetText())
			if v then
				if label == "X" then px = v else py = v end
				S.db.profile.movers[selected.name] = PointToString(point, rel, relPoint, px, py)
				S:PositionMover(selected)
			end
			nudge:Refresh()
		end)
		return eb
	end
	nudge.x = Edit("X", 16)
	nudge.y = Edit("Y", 114)

	local function Arrow(text, dx, dy, x, y)
		local b = CreateFrame("Button", nil, nudge)
		b:SetSize(22, 20)
		b:SetPoint("TOP", nudge, "TOP", x, y)
		S:CreateBackdrop(b, "Default", nil, 0)
		S:AddHover(b)
		local t = S:FontString(b, 12, "OUTLINE")
		t:SetPoint("CENTER")
		t:SetText(text)
		b:SetScript("OnClick", function()
			if not selected or InCombatLockdown() then return end
			local step = IsShiftKeyDown() and 10 or 1
			local l, bt, w, h = GetRect(selected)
			SaveCenter(selected, l + w / 2 + dx * step, bt + h / 2 + dy * step)
			nudge:Refresh()
		end)
	end
	Arrow("^", 0, 1, 0, -52)
	Arrow("v", 0, -1, 0, -76)
	Arrow("<", -1, 0, -26, -64)
	Arrow(">", 1, 0, 26, -64)

	local function Btn(text, point, x, func)
		local b = CreateFrame("Button", nil, nudge, "UIPanelButtonTemplate")
		b:SetSize(58, 20)
		b:SetPoint(point, x, 8)
		b:SetText(text)
		b:SetScript("OnClick", func)
		S:SkinButton(b)
	end
	Btn(L["Reset"], "BOTTOMLEFT", 6, function() if selected then S.db.profile.movers[selected.name] = nil S:PositionMover(selected) nudge:Refresh() end end)
	Btn(L["Config"], "BOTTOMRIGHT", -6, function() if selected and selected.configKey then S:ToggleConfig(selected.configKey) end end)

	function nudge:Refresh()
		if not selected then self:Hide() return end
		self.title:SetText(selected.title)
		local saved = S.db.profile.movers[selected.name]
		local _, _, _, x, y
		if saved then _, _, _, x, y = ParsePoint(saved) else x, y = selected.default[4], selected.default[5] end
		self.x:SetText(floor(x + 0.5))
		self.y:SetText(floor(y + 0.5))
	end
	nudge:Hide()
end

local function Select(mover)
	if selected and selected ~= mover then selected:SetBackdropBorderColor(0, 0, 0) end
	selected = mover
	if not nudge then CreateNudge() end
	mover:SetBackdropBorderColor(1, 0.82, 0)
	nudge:ClearAllPoints()
	local _, y = mover:GetCenter()
	if y and y > UIParent:GetHeight() / 2 then
		nudge:SetPoint("TOP", mover, "BOTTOM", 0, -6)
	else
		nudge:SetPoint("BOTTOM", mover, "TOP", 0, 6)
	end
	nudge:Show()
	nudge:Refresh()
end

local function MoverOnEnter(self)
	if self ~= selected then self:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b) end
	self.text:SetTextColor(1, 1, 1)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(self.title, S.accent.r, S.accent.g, S.accent.b)
	GameTooltip:AddLine(L["Left drag: move (Alt = no snapping)"], 1, 1, 1)
	GameTooltip:AddLine(L["Left click: select / fine tune"], 1, 1, 1)
	GameTooltip:AddLine(L["Right click: open settings"], 1, 1, 1)
	GameTooltip:AddLine(L["Shift + right click: hide mover"], 1, 1, 1)
	GameTooltip:AddLine(L["Ctrl + right click: reset position"], 1, 1, 1)
	GameTooltip:AddLine(L["Mouse wheel: nudge (Shift = horizontal)"], 1, 1, 1)
	GameTooltip:Show()
end

local function MoverOnLeave(self)
	if self ~= selected then self:SetBackdropBorderColor(0, 0, 0) end
	self.text:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
	GameTooltip:Hide()
end

function S:CreateMover(frame, name, title, default, configKey)
	if self.movers[name] then
		-- a second frame registering the same mover still needs an anchor,
		-- otherwise it floats at the screen center forever
		local mover = self.movers[name]
		if frame and frame ~= mover.parent then
			mover.parent = frame
			frame.suiMover = mover
			local function Anchor() frame:ClearAllPoints() frame:SetPoint("CENTER", mover, "CENTER") end
			if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then
				S:RunOutOfCombat(Anchor)
			else
				Anchor()
			end
		end
		return mover
	end
	local mover = CreateFrame("Button", "SentinelUIMover_" .. name, UIParent, self.BackdropTemplate)
	mover.name, mover.title, mover.parent = name, title, frame
	mover.configKey = ResolveConfig(configKey, name)
	mover.default = default or FallbackDefault()
	mover:SetFrameStrata("DIALOG")
	mover:SetFrameLevel(100)
	mover:SetClampedToScreen(true)
	mover:SetMovable(true)
	mover:EnableMouse(true)
	mover:EnableMouseWheel(true)
	mover:RegisterForDrag("LeftButton")
	mover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local w, h = frame:GetSize()
	mover:SetSize(math.max(w or 20, 10), math.max(h or 20, 10))
	self:SetTemplate(mover, "Transparent")
	mover:SetBackdropColor(S.accent.r * 0.25, S.accent.g * 0.25, S.accent.b * 0.25, 0.75)
	mover.text = self:FontString(mover, 11, "OUTLINE")
	mover.text:SetPoint("CENTER")
	mover.text:SetText(title)
	mover.text:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
	mover:Hide()

	mover:SetScript("OnDragStart", function(m)
		if InCombatLockdown() then return end
		m.dragging = true
		m:StartMoving()
	end)
	mover:SetScript("OnDragStop", function(m)
		m:StopMovingOrSizing()
		S:SafeCall("Mover:Save", SavePosition, m, true)
		C_Timer.After(0, function() m.dragging = nil end)
	end)
	mover:SetScript("OnEnter", MoverOnEnter)
	mover:SetScript("OnLeave", MoverOnLeave)
	mover:SetScript("OnMouseWheel", function(m, delta)
		if InCombatLockdown() then return end
		local l, b, mw, mh = GetRect(m)
		if not l then return end
		if IsShiftKeyDown() then l = l + delta else b = b + delta end
		SaveCenter(m, l + mw / 2, b + mh / 2)
		if selected == m and nudge then nudge:Refresh() end
	end)
	mover:SetScript("OnClick", function(m, button)
		if m.dragging then return end
		if button == "LeftButton" then
			Select(m)
		elseif IsShiftKeyDown() then
			if not (m.IsProtected and m:IsProtected() and InCombatLockdown()) then m:Hide() end
		elseif IsControlKeyDown() then
			S.db.profile.movers[m.name] = nil
			S:PositionMover(m)
			if selected == m and nudge then nudge:Refresh() end
		elseif m.configKey then
			S:ToggleConfig(m.configKey)
		end
	end)

	frame:HookScript("OnSizeChanged", function(_, fw, fh)
		if not (fw and fh and fw > 0 and fh > 0) then return end
		-- the mover anchors a (possibly protected) frame: resizing it in combat is blocked
		if InCombatLockdown() then S:RunOutOfCombat(mover.SetSize, mover, fw, fh) else mover:SetSize(fw, fh) end
	end)

	self.movers[name] = mover
	self.moverOrder[#self.moverOrder + 1] = mover
	self:PositionMover(mover)
	local function AnchorToMover()
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", mover, "CENTER")
	end
	if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then
		-- unanchored frames render at screen center; queue the anchor instead of skipping
		S:RunOutOfCombat(AnchorToMover)
	else
		AnchorToMover()
	end
	frame.suiMover = mover
	return mover
end

-- Lets a handle (e.g. a window title area) drag a mover directly, outside move mode.
-- The anchored frame follows automatically; the new position is persisted.
function S:AttachMoverDrag(handle, moverName)
	local mover = self.movers[moverName]
	if not mover or not handle then return end
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function()
		if InCombatLockdown() then
			local prot = (handle.IsProtected and handle:IsProtected())
				or (mover.IsProtected and mover:IsProtected())
			if prot then return end
		end
		mover:StartMoving()
	end)
	handle:SetScript("OnDragStop", function()
		if mover.IsProtected and mover:IsProtected() and InCombatLockdown() then return end
		mover:StopMovingOrSizing()
		S:SafeCall("Mover:Save", SavePosition, mover, false)
	end)
end

function S:RemoveMover(name)
	local mover = self.movers[name]
	if not mover then return end
	self.db.profile.movers[name] = nil
	self.movers[name] = nil
	for i, m in ipairs(self.moverOrder) do
		if m == mover then table.remove(self.moverOrder, i) break end
	end
	if selected == mover then selected = nil end
	mover:Hide()
end

function S:ResetMovers(name)
	if name then
		self.db.profile.movers[name] = nil
	else
		wipe(self.db.profile.movers)
	end
	for _, mover in ipairs(self.moverOrder) do self:PositionMover(mover) end
end

function S:RefreshMovers()
	for _, mover in ipairs(self.moverOrder) do self:PositionMover(mover) end
end

local function DrawGrid(size)
	if not gridFrame then
		gridFrame = CreateFrame("Frame", "SentinelUIGrid", UIParent)
		gridFrame:SetAllPoints(UIParent)
		gridFrame:SetFrameStrata("BACKGROUND")
		gridFrame.lines = {}
	end
	for _, l in ipairs(gridFrame.lines) do l:Hide() end
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local i = 0
	local function Line(horizontal, offset, center)
		i = i + 1
		local t = gridFrame.lines[i] or gridFrame:CreateTexture(nil, "BACKGROUND")
		gridFrame.lines[i] = t
		t:SetTexture(S.media.blank)
		if center then t:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.8) else t:SetVertexColor(0, 0, 0, 0.5) end
		t:ClearAllPoints()
		if horizontal then
			t:SetPoint("TOPLEFT", gridFrame, "BOTTOMLEFT", 0, offset)
			t:SetPoint("TOPRIGHT", gridFrame, "BOTTOMRIGHT", 0, offset)
			t:SetHeight(S.mult * 2)
		else
			t:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", offset, 0)
			t:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", offset, 0)
			t:SetWidth(S.mult * 2)
		end
		t:Show()
	end
	local cx, cy = w / 2, h / 2
	for x = cx % size, w, size do Line(false, x, math.abs(x - cx) < 1) end
	for y = cy % size, h, size do Line(true, y, math.abs(y - cy) < 1) end
	gridFrame:Show()
end

local function ApplyFilter()
	for _, mover in ipairs(S.moverOrder) do
		local show = S.moversUnlocked and not mover.disabled and (filter == "ALL" or Category(mover) == filter)
		mover:SetShown(show and true or false)
	end
	if moverPanel then moverPanel.filterText:SetText(categories[filter] or filter) end
end

local function CreateMoverPanel()
	moverPanel = CreateFrame("Frame", "SentinelUIMoverPanel", UIParent)
	moverPanel:SetSize(400, 104)
	moverPanel:SetPoint("TOP", 0, -60)
	moverPanel:SetFrameStrata("FULLSCREEN_DIALOG")
	moverPanel:EnableMouse(true)
	moverPanel:SetMovable(true)
	moverPanel:SetClampedToScreen(true)
	moverPanel:RegisterForDrag("LeftButton")
	moverPanel:SetScript("OnDragStart", moverPanel.StartMoving)
	moverPanel:SetScript("OnDragStop", moverPanel.StopMovingOrSizing)
	S:SetTemplate(moverPanel, "Transparent", "TOP")
	local title = S:FontString(moverPanel, 14, "OUTLINE")
	title:SetPoint("TOP", 0, -8)
	title:SetText(S.title .. " - " .. L["Movers unlocked"])
	local hint = S:FontString(moverPanel, 11)
	hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
	hint:SetText(L["Drag to move, click to fine tune, right click for settings."])
	hint:SetTextColor(0.75, 0.75, 0.75)

	local function Btn(text, w, point, x, y, func)
		local b = CreateFrame("Button", nil, moverPanel, "UIPanelButtonTemplate")
		b:SetSize(w, 22)
		b:SetPoint(point, x, y)
		b:SetText(text)
		b:SetScript("OnClick", func)
		S:SkinButton(b)
		return b
	end
	-- row 1: filter
	local prev = Btn("<", 24, "TOPLEFT", 12, -46, function()
		local idx = IndexOf(categoryOrder, filter) or 1
		filter = categoryOrder[(idx - 2) % #categoryOrder + 1]
		ApplyFilter()
	end)
	moverPanel.filterText = S:FontString(moverPanel, 12, "OUTLINE")
	moverPanel.filterText:SetPoint("LEFT", prev, "RIGHT", 8, 0)
	moverPanel.filterText:SetWidth(120)
	Btn(">", 24, "TOPLEFT", 166, -46, function()
		local idx = IndexOf(categoryOrder, filter) or 1
		filter = categoryOrder[idx % #categoryOrder + 1]
		ApplyFilter()
	end)
	local gridLabel = S:FontString(moverPanel, 11)
	gridLabel:SetPoint("TOPLEFT", 206, -50)
	local function UpdateGridLabel() gridLabel:SetText(L["Grid"] .. ": " .. S.db.global.gridSize) end
	Btn("-", 24, "TOPLEFT", 290, -46, function()
		S.db.global.gridSize = math.max(8, S.db.global.gridSize - 8)
		UpdateGridLabel()
		if gridFrame and gridFrame:IsShown() then DrawGrid(S.db.global.gridSize) end
	end)
	Btn("+", 24, "TOPLEFT", 318, -46, function()
		S.db.global.gridSize = math.min(256, S.db.global.gridSize + 8)
		UpdateGridLabel()
		if gridFrame and gridFrame:IsShown() then DrawGrid(S.db.global.gridSize) end
	end)
	UpdateGridLabel()
	-- row 2
	Btn(L["Lock"], 90, "BOTTOMLEFT", 12, 10, function() S:ToggleMovers(false) end)
	Btn(L["Grid"], 90, "BOTTOMLEFT", 108, 10, function()
		if gridFrame and gridFrame:IsShown() then gridFrame:Hide() else DrawGrid(S.db.global.gridSize or 64) end
	end)
	Btn(L["Options"], 90, "BOTTOMLEFT", 204, 10, function() S:ToggleConfig() end)
	Btn(L["Reset all"], 90, "BOTTOMLEFT", 300, 10, function() StaticPopup_Show("SENTINELUI_RESET_MOVERS") end)
end

StaticPopupDialogs["SENTINELUI_RESET_MOVERS"] = {
	text = L["SentinelUI: Reset all positions?"],
	button1 = YES, button2 = NO,
	OnAccept = function() S:ResetMovers() if nudge and nudge:IsShown() then nudge:Refresh() end end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

function S:ToggleMovers(show)
	if show == nil then show = not self.moversUnlocked end
	if show and InCombatLockdown() then
		self:Print(ERR_NOT_IN_COMBAT)
		return
	end
	self.moversUnlocked = show
	if show then
		if not moverPanel then CreateMoverPanel() end
		moverPanel:Show()
		DrawGrid(self.db.global.gridSize or 64)
	else
		if moverPanel then moverPanel:Hide() end
		if gridFrame then gridFrame:Hide() end
		if nudge then nudge:Hide() end
		if selected then selected:SetBackdropBorderColor(0, 0, 0) selected = nil end
	end
	ApplyFilter()
end

function S:DisableMover(name, disabled)
	local m = self.movers[name]
	if m then
		m.disabled = disabled
		if disabled then m:Hide() elseif self.moversUnlocked then ApplyFilter() end
	end
end

-- Self-heal: any moved frame that lost its anchor (combat-deferred init, stale
-- SetPoint hooks, ...) would render at screen center. Re-anchor it to its mover.
function S:VerifyMoverAnchors()
	for _, mover in ipairs(self.moverOrder) do
		local frame = mover.parent
		if frame and frame.IsShown then
			local anchored = false
			for i = 1, frame:GetNumPoints() do
				local _, rel = frame:GetPoint(i)
				if rel == mover then anchored = true break end
			end
			if not anchored and not (frame.IsProtected and frame:IsProtected() and InCombatLockdown()) then
				S:SafeCall("Mover:ReAnchor", function()
					frame:ClearAllPoints()
					frame:SetPoint("CENTER", mover, "CENTER")
				end)
			end
		end
	end
end

S:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if S.moversUnlocked then S:ToggleMovers(false) end
end)

S:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	S:VerifyMoverAnchors()
end)

S:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	C_Timer.After(2, function() S:SafeCall("Mover:Verify", S.VerifyMoverAnchors, S) end)
end)
