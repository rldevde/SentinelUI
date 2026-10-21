-- Reputation window (replaces standalone RLRep): lists every faction with
-- standing, progress bar and watch toggle. Grouped by expansion headers.
local _, ns = ...
local S = ns.S
local L = S.L
local REP = S:NewModule("Reputation", "rep")
local wipe, ipairs, sort, tinsert = wipe, ipairs, sort, tinsert
local floor, min = floor, math.min
local format = format
local CreateFrame = CreateFrame
local GetNumFactions, GetFactionInfo = GetNumFactions, GetFactionInfo
local SetWatchedFactionIndex, GetWatchedFactionInfo = SetWatchedFactionIndex, GetWatchedFactionInfo

local WIN_W, WIN_H, ROW_H, MAX_ROWS = 480, 520, 26, 15
local ICON = "Interface\\Icons\\Spell_Holy_InnerFire"

local STANDING_COLORS = {
	[1] = { 0.80, 0.13, 0.13 }, -- hated
	[2] = { 1.00, 0.00, 0.00 }, -- hostile
	[3] = { 0.93, 0.45, 0.13 }, -- unfriendly
	[4] = { 0.93, 0.85, 0.13 }, -- neutral
	[5] = { 0.00, 0.60, 0.10 }, -- friendly
	[6] = { 0.00, 0.60, 0.40 }, -- honored
	[7] = { 0.00, 0.60, 0.70 }, -- revered
	[8] = { 0.00, 0.80, 0.90 }, -- exalted
}

local function StandingName(id)
	return _G["FACTION_STANDING_LABEL" .. id] or tostring(id or "?")
end

local function ShortNum(n)
	n = n or 0
	if n >= 1000 then return format("%.1fK", n / 1000) end
	return tostring(n)
end

-- flat display list: header rows (isHead) + faction rows
local function FactionRows()
	local rows = {}
	local num = GetNumFactions and GetNumFactions() or 0
	local watched = GetWatchedFactionInfo and GetWatchedFactionInfo()
	for i = 1, num do
		local name, desc, standingId, barMin, barMax, barValue, atWar, canWar, isHeader, isCollapsed, hasRep, isWatched, isChild = GetFactionInfo(i)
		if isHeader then
			rows[#rows + 1] = { isHead = true, name = name, collapsed = isCollapsed }
		elseif name and name ~= "" then
			local cur = (barValue or 0) - (barMin or 0)
			local max = (barMax or 0) - (barMin or 0)
			local paragon = false
			if C_Reputation and C_Reputation.GetFactionParagonInfo then
				local p = C_Reputation.GetFactionParagonInfo(i)
				if p then
					paragon = true
					cur, max = p.currentValue or 0, p.threshold or 1
				end
			end
			rows[#rows + 1] = {
				name = name, desc = desc, standingId = standingId or 4,
				cur = cur, max = max, pct = max > 0 and (cur / max) or 0,
				atWar = atWar, watched = (i == watched) or isWatched,
				paragon = paragon, index = i, isChild = isChild,
			}
		end
	end
	return rows
end

-- rows ----------------------------------------------------------------------
local function MakeRow(list, i)
	local r = list.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, list)
	r:SetHeight(ROW_H)
	S:CreateBackdrop(r, "Default")
	r.name = S:FontString(r, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
	r.name:SetPoint("LEFT", 8, 4)
	r.name:SetWidth(180)
	r.name:SetWordWrap(false)
	r.standing = S:FontString(r, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	r.standing:SetPoint("LEFT", 196, 4)
	r.standing:SetWidth(90)
	r.right = S:FontString(r, 9, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	r.right:SetPoint("RIGHT", -8, 4)
	-- thin progress bar along the row bottom
	r.bar = CreateFrame("StatusBar", nil, r)
	r.bar:SetPoint("BOTTOMLEFT", 8, 3)
	r.bar:SetPoint("BOTTOMRIGHT", -8, 3)
	r.bar:SetHeight(6)
	r.bar:SetStatusBarTexture(S:Fetch("statusbar", S.db.profile.general.statusbar, "Sentinel"))
	r.bar:SetMinMaxValues(0, 1)
	r.bar.bg = r.bar:CreateTexture(nil, "BACKGROUND")
	r.bar.bg:SetAllPoints()
	r.bar.bg:SetTexture(S:Fetch("statusbar", S.db.profile.general.statusbar, "Sentinel"))
	r.bar.bg:SetVertexColor(0, 0, 0, 0.45)
	r:SetScript("OnEnter", function(s)
		local bd = s.suiBackdrop or s
		if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b, 1) end
		if s.fac and GameTooltip then
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			GameTooltip:AddLine(s.fac.name, 1, 1, 1)
			if s.fac.desc and s.fac.desc ~= "" then GameTooltip:AddLine(s.fac.desc, 0.8, 0.8, 0.8, true) end
			GameTooltip:AddLine(format("%s: %s  (%s / %s)", StandingName(s.fac.standingId), format("%d%%", floor(s.fac.pct * 100 + 0.5)), ShortNum(s.fac.cur), ShortNum(s.fac.max)), 1, 1, 1, true)
			GameTooltip:AddLine(L["Click: watch / unwatch"], 0.5, 0.5, 0.55)
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(s)
		local bd = s.suiBackdrop or s
		if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(unpack(S.media.borderColor)) end
		if GameTooltip then GameTooltip:Hide() end
	end)
	list.rows[i] = r
	return r
end

-- frame ---------------------------------------------------------------------
function REP:BuildFrame()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "SentinelUIReputation", UIParent)
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER", UIParent, "CENTER", 120, 20)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SetTemplate(f, "Transparent", "TOP")
	f:Hide()

	f.logo = f:CreateTexture(nil, "OVERLAY")
	f.logo:SetSize(16, 16)
	f.logo:SetPoint("TOPLEFT", 8, -6)
	f.logo:SetTexture(ICON)
	f.logo:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)

	f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 6, 0)
	f.title:SetText(L["Reputation"])
	S:RegisterAccent(f.title, "text")

	f.close = CreateFrame("Button", nil, f)
	f.close:SetSize(16, 16)
	f.close:SetPoint("TOPRIGHT", -7, -6)
	S:CreateBackdrop(f.close, "Default")
	f.close.fs = S:FontString(f.close, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.close.fs:SetPoint("CENTER")
	f.close.fs:SetText("x")
	f.close:SetScript("OnClick", function() f:Hide() end)

	-- column header
	f.colName = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.colName:SetPoint("TOPLEFT", 16, -32)
	f.colName:SetText(L["Factions"])
	f.colName:SetTextColor(0.5, 0.5, 0.55)
	f.colMid = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.colMid:SetPoint("TOPLEFT", 204, -32)
	f.colMid:SetText(L["Standing"])
	f.colMid:SetTextColor(0.5, 0.5, 0.55)
	f.colRight = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	f.colRight:SetPoint("TOPRIGHT", -16, -32)
	f.colRight:SetText(L["Progress"])
	f.colRight:SetTextColor(0.5, 0.5, 0.55)

	-- list area
	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", 8, -42)
	f.list:SetPoint("BOTTOMRIGHT", -8, 30)
	f.list:EnableMouse(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta)
		REP.scroll = REP.scroll - delta * 4
		if REP.scroll < 0 then REP.scroll = 0 end
		REP:Refresh()
	end)
	f.list.rows = {}

	-- footer
	f.summary = S:FontString(f, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.summary:SetPoint("BOTTOMLEFT", 10, 10)
	f.summary:SetPoint("RIGHT", -90, 0)
	f.summary:SetTextColor(0.65, 0.65, 0.7)

	f.refresh = CreateFrame("Button", nil, f)
	f.refresh:SetSize(76, 18)
	f.refresh:SetPoint("BOTTOMRIGHT", -8, 8)
	S:SkinButton(f.refresh)
	f.refresh.label = S:FontString(f.refresh, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.refresh.label:SetPoint("CENTER")
	f.refresh.label:SetText(L["Refresh"])
	f.refresh:SetScript("OnClick", function() REP:Refresh() end)

	tinsert(UISpecialFrames, "SentinelUIReputation")
	self.frame = f
	return f
end

function REP:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local rows = FactionRows()
	self.scroll = self.scroll or 0
	local nVis = #rows
	if self.scroll > nVis - MAX_ROWS then self.scroll = math.max(0, nVis - MAX_ROWS) end
	local list = f.list
	local shown, exalted, nFactions = 0, 0, 0
	for i = 1, MAX_ROWS do
		local idx = self.scroll + i
		local data = rows[idx]
		local r = MakeRow(list, i)
		if not data then
			r.fac = nil
			r:Hide()
		elseif data.isHead then
			shown = shown + 1
			r.fac = nil
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((shown - 1) * (ROW_H + 2)))
			r:SetPoint("RIGHT", list, "RIGHT", 0, 0)
			r.name:SetText("|cff" .. S.accentHex .. data.name .. "|r")
			r.standing:SetText("")
			r.right:SetText(data.collapsed and "+" or "-")
			r.bar:Hide()
			local bd = r.suiBackdrop or r
			if bd.SetBackdropColor then bd:SetBackdropColor(0.08, 0.08, 0.1, 0.6) end
			r:SetScript("OnClick", nil)
			r:Show()
		else
			shown = shown + 1
			nFactions = nFactions + 1
			if data.standingId == 8 then exalted = exalted + 1 end
			r.fac = data
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((shown - 1) * (ROW_H + 2)))
			r:SetPoint("RIGHT", list, "RIGHT", 0, 0)
			local c = STANDING_COLORS[data.standingId] or STANDING_COLORS[4]
			local prefix = data.watched and "* " or (data.isChild and "  " or "")
			r.name:SetText(prefix .. data.name)
			r.name:SetTextColor(c[1], c[2], c[3])
			r.standing:SetText(StandingName(data.standingId))
			r.standing:SetTextColor(c[1], c[2], c[3])
			r.right:SetText(format("%s / %s  %d%%", ShortNum(data.cur), ShortNum(data.max), floor(data.pct * 100 + 0.5)) .. (data.paragon and " P" or ""))
			r.bar:SetMinMaxValues(0, 1)
			r.bar:SetValue(data.pct)
			r.bar:SetStatusBarColor(c[1], c[2], c[3])
			r.bar:Show()
			local bd = r.suiBackdrop or r
			if bd.SetBackdropColor then bd:SetBackdropColor(0.06, 0.06, 0.08, 0.9) end
			local idx2 = data.index
			local watched = data.watched
			r:SetScript("OnClick", function()
				if SetWatchedFactionIndex then
					SetWatchedFactionIndex(watched and 0 or idx2)
					REP:Refresh()
				end
			end)
			r:Show()
		end
	end
	for i = shown + 1, #list.rows do
		list.rows[i].fac = nil
		list.rows[i]:Hide()
	end
	f.summary:SetText(format(L["%d factions · %d exalted"], nFactions, exalted))
end

function REP:Toggle()
	local f = self:BuildFrame()
	if f:IsShown() then f:Hide() return end
	f:Show()
	self.scroll = 0
	self:Refresh()
end

-- minimap button ------------------------------------------------------------
function REP:UpdateMinimap()
	local d = S.private.rep
	if not d or not d.minimapShow or (self.db and self.db.enable == false) then
		if self.minimapBtn then self.minimapBtn:Hide() end
		return
	end
	if not self.minimapBtn then
		self.minimapBtn = S:CreateMinimapButton({
			name = "rep", glyph = "RE", store = d, angle = -95,
			onLeft = function() REP:Toggle() end,
			tooltip = function()
				GameTooltip:AddLine("SentinelUI " .. L["Reputation"])
				GameTooltip:AddLine(L["Left-click: open  |  Drag: move"], 1, 1, 1)
			end,
		})
	end
	self.minimapBtn:Show()
	self.minimapBtn:UpdatePosition()
end

function REP:OnFaction()
	if self.frame and self.frame:IsShown() then self:Refresh() end
	-- auto-watch: switch the watched faction to whichever one just gained rep
	if not (self.db.autoWatch and SetWatchedFactionIndex and GetFactionInfo) then return end
	local snap = self._snap or {}
	self._snap = snap
	local gained
	for i = 1, (GetNumFactions and GetNumFactions() or 0) do
		local name, _, _, barMin, _, barValue, _, _, isHeader, _, hasRep, isWatched = GetFactionInfo(i)
		if name and not isHeader and hasRep then
			local v = (barValue or 0) - (barMin or 0)
			local key = name
			if snap[key] and v > snap[key] and not isWatched then
				gained = i
			end
			snap[key] = v
		end
	end
	if gained then SetWatchedFactionIndex(gained) end
end

function REP:Initialize()
	self.db = S.db.profile.rep
	S.private.rep = S.private.rep or { minimapShow = true }
	if S.private.rep.minimapShow == nil then S.private.rep.minimapShow = true end
	self:RegisterEvent("UPDATE_FACTION", "OnFaction")
	self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "OnFaction")
	self:UpdateMinimap()
	S:RegisterChatCommand("rep", function() REP:Toggle() end)
	SLASH_RLREP1 = "/rlrep"
	SlashCmdList["RLREP"] = function() REP:Toggle() end
end

function REP:Update()
	self.db = S.db.profile.rep
	self:UpdateMinimap()
end
