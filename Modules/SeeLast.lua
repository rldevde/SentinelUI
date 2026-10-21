-- SeeLast: overview window for the last fights recorded by the DamageMeter.
-- Lists the recent combat segments (current fight, archived fights, overall)
-- with per-fight summary lines and a sortable per-player breakdown.
local _, ns = ...
local S = ns.S
local L = S.L
local SL = S:NewModule("SeeLast", "seelast")

local pairs, ipairs, sort, wipe = pairs, ipairs, table.sort, wipe
local format, floor, max = format, math.floor, math.max
local tostring, tonumber = tostring, tonumber
local date, time, GetTime = date, time, GetTime
local CreateFrame = CreateFrame
local UnitGUID = UnitGUID
local GameTooltip = GameTooltip
local PlaySound = PlaySound

local WIN_W, WIN_H = 470, 430
local MAX_FIGHT_ROWS = 7   -- current + history cap + overall
local MAX_PLAYER_ROWS = 9
local win

local SORTS = {
	{ key = "dmg", label = "Damage" },
	{ key = "dps", label = "DPS" },
	{ key = "heal", label = "Healing" },
	{ key = "hps", label = "HPS" },
	{ key = "taken", label = "Damage Taken" },
	{ key = "deaths", label = "Deaths" },
}

local function Fmt(n)
	n = tonumber(n) or 0
	if n >= 1e6 then return format("%.2fM", n / 1e6) end
	if n >= 1e3 then return format("%.1fk", n / 1e3) end
	return format("%.0f", n)
end

local function ValOf(p, key, ft)
	if key == "dmg" then return p.dmg or 0
	elseif key == "dps" then return (p.dmg or 0) / ft
	elseif key == "heal" then return p.heal or 0
	elseif key == "hps" then return (p.heal or 0) / ft
	elseif key == "taken" then return p.taken or 0
	elseif key == "deaths" then return p.deaths or 0 end
	return 0
end

-- fight list: current (while it has data), archived fights, overall
local function CollectFights()
	local DM = S:GetModule("DamageMeter")
	local out = {}
	if not DM or not DM.segments then return out, DM end
	local cur = DM.segments.current
	if (DM.inCombat or (cur.players and next(cur.players))) then
		out[#out + 1] = { seg = cur, key = "current", label = L["Current fight"] or "Current fight", live = DM.inCombat }
	end
	for i, seg in ipairs(DM.segments.history or {}) do
		out[#out + 1] = { seg = seg, key = "fight:" .. i, label = (L["Fight"] or "Fight") .. " " .. i, n = i }
	end
	local ov = DM.segments.overall
	if (ov.fightTime or 0) > 0 or (ov.players and next(ov.players)) then
		out[#out + 1] = { seg = ov, key = "overall", label = L["Overall"] or "Overall" }
	end
	return out, DM
end

local function SegTime(seg, DM)
	local t = seg.fightTime or 0
	if seg == DM.segments.current and DM.inCombat and seg.startT then
		t = t + (GetTime() - seg.startT)
	end
	return max(t, 0.1)
end

-- per-player table of a segment, sorted by the active key
local function PlayerRows(seg, ft, key, asc)
	local rows = {}
	local myGUID = UnitGUID("player")
	for guid, p in pairs(seg.players or {}) do
		rows[#rows + 1] = {
			name = p.name or "?", class = p.class, p = p, mine = guid == myGUID,
			dmg = p.dmg or 0, dps = (p.dmg or 0) / ft, heal = p.heal or 0,
			hps = (p.heal or 0) / ft, taken = p.taken or 0, deaths = p.deaths or 0,
		}
	end
	sort(rows, function(a, b)
		local av, bv = ValOf(a, key, ft), ValOf(b, key, ft)
		if av == bv then return (a.name or "") < (b.name or "") end
		if asc then return av < bv end
		return av > bv
	end)
	return rows
end

-- window ---------------------------------------------------------------------
local function BuildWindow()
	if win then return win end
	local f = CreateFrame("Frame", "SentinelUISeeLast", UIParent)
	f:SetSize(WIN_W, WIN_H)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(ff)
		ff:StopMovingOrSizing()
		SL.private.seelastPos = { x = ff:GetLeft(), y = ff:GetTop() }
	end)
	local pos = SL.private.seelastPos
	if pos and pos.x then
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", -180, 40)
	end
	S:SetTemplate(f, "Default", "TOP")

	f.title = S:FontString(f, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("TOPLEFT", 10, -8)
	f.title:SetText("SeeLast")
	S:RegisterAccent(f.title, "text")

	f.close = CreateFrame("Button", nil, f)
	f.close:SetSize(16, 16)
	f.close:SetPoint("TOPRIGHT", -7, -6)
	S:CreateBackdrop(f.close, "Default")
	f.close.fs = S:FontString(f.close, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.close.fs:SetPoint("CENTER")
	f.close.fs:SetText("x")
	f.close:SetScript("OnClick", function() f:Hide() end)

	f.subtitle = S:FontString(f, 9, nil, S.media.font, nil, "LEFT")
	f.subtitle:SetPoint("TOPLEFT", 10, -20)
	f.subtitle:SetText("|cff666f7a" .. (L["Last fights recorded by the damage meter"] or "Last fights recorded by the damage meter") .. "|r")

	-- fight list -------------------------------------------------------------
	local listTop = -36
	f.fightRows = {}
	for i = 1, MAX_FIGHT_ROWS do
		local r = CreateFrame("Button", nil, f)
		r:SetPoint("TOPLEFT", 8, listTop - (i - 1) * 22)
		r:SetPoint("TOPRIGHT", -8, listTop - (i - 1) * 22)
		r:SetHeight(20)
		S:CreateBackdrop(r, "Transparent")
		r.hl = r:CreateTexture(nil, "BACKGROUND")
		r.hl:SetAllPoints()
		r.hl:SetTexture(S.media.blank)
		r.hl:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.18)
		r.hl:Hide()
		r.label = S:FontString(r, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
		r.label:SetPoint("LEFT", 6, 0)
		r.info = S:FontString(r, 10, nil, S.media.numberFont, nil, "RIGHT")
		r.info:SetPoint("RIGHT", -6, 0)
		r:SetScript("OnClick", function()
			f.selected = r.fightKey
			SL:Refresh()
		end)
		f.fightRows[i] = r
	end
	local listH = MAX_FIGHT_ROWS * 22 + 4

	-- info line under the fight list: who pulled + fight totals
	f.fightInfo = S:FontString(f, 10, nil, S.media.font, nil, "LEFT")
	f.fightInfo:SetPoint("TOPLEFT", 10, listTop - listH - 2)
	f.fightInfo:SetPoint("TOPRIGHT", -10, listTop - listH - 2)
	f.fightInfo:SetText("")

	-- column headers (click = sort) ------------------------------------------
	-- col 1 = name, cols 2..7 = dmg / dps / heal / hps / taken / deaths
	local headTop = listTop - listH - 20
	f.sortKey, f.sortAsc = "dmg", false
	f.headers = {}
	local colX = { 10, 112, 172, 232, 292, 352, 412 }
	local colW = { 100, 58, 58, 58, 58, 58, 44 }
	local nameHead = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	nameHead:SetPoint("TOPLEFT", colX[1] + 2, headTop - 2)
	nameHead:SetText(NAME or "Name")
	for i, s in ipairs(SORTS) do
		local h = CreateFrame("Button", nil, f)
		h:SetPoint("TOPLEFT", colX[i + 1], headTop)
		h:SetSize(colW[i + 1], 16)
		h.fs = S:FontString(h, 9, "OUTLINE", S.media.numberFont, nil, "RIGHT")
		h.fs:SetPoint("RIGHT", -2, 0)
		h.fs:SetText(L[s.label] or s.label)
		h:SetScript("OnClick", function()
			if f.sortKey == s.key then f.sortAsc = not f.sortAsc
			else f.sortKey, f.sortAsc = s.key, false end
			SL:Refresh()
		end)
		f.headers[i] = h
	end

	-- player rows -------------------------------------------------------------
	f.detailOffset = 0
	f.playerRows = {}
	local rowTop = headTop - 20
	for i = 1, MAX_PLAYER_ROWS do
		local r = CreateFrame("Button", nil, f)
		r:SetPoint("TOPLEFT", 8, rowTop - (i - 1) * 17)
		r:SetPoint("TOPRIGHT", -8, rowTop - (i - 1) * 17)
		r:SetHeight(16)
		r.bar = r:CreateTexture(nil, "BACKGROUND")
		r.bar:SetPoint("TOPLEFT", 1, -1)
		r.bar:SetPoint("BOTTOMLEFT", 1, 1)
		r.bar:SetTexture(S.media.blank)
		r.name = S:FontString(r, 10, nil, S.media.font, nil, "LEFT")
		r.name:SetPoint("LEFT", 5, 0)
		r.name:SetWidth(100)
		r.vals = {}
		for ci = 2, 7 do
			local v = S:FontString(r, 10, nil, S.media.numberFont, nil, "RIGHT")
			v:SetPoint("RIGHT", r, "LEFT", colX[ci] + colW[ci] - 4, 0)
			r.vals[ci] = v
		end
		r:SetScript("OnEnter", function(rr)
			if not rr.entry then return end
			GameTooltip:SetOwner(rr, "ANCHOR_RIGHT")
			GameTooltip:SetText(rr.entry.name)
			GameTooltip:AddLine(format("%s: |cffffffff%s|r", L["Damage"] or "Damage", Fmt(rr.entry.dmg)), 0.8, 0.8, 0.8)
			GameTooltip:AddLine(format("DPS: |cffffffff%s|r", Fmt(rr.entry.dps)), 0.8, 0.8, 0.8)
			GameTooltip:AddLine(format("%s: |cffffffff%s|r", L["Healing"] or "Healing", Fmt(rr.entry.heal)), 0.8, 0.8, 0.8)
			GameTooltip:AddLine(format("%s: |cffffffff%s|r", L["Damage Taken"] or "Damage Taken", Fmt(rr.entry.taken)), 0.8, 0.8, 0.8)
			if (rr.entry.p.interrupts or 0) > 0 then
				GameTooltip:AddLine(format("%s: |cffffffff%d|r", L["Interrupts"] or "Interrupts", rr.entry.p.interrupts), 0.8, 0.8, 0.8)
			end
			if (rr.entry.deaths or 0) > 0 then
				GameTooltip:AddLine(format("%s: |cffff4040%d|r", L["Deaths"] or "Deaths", rr.entry.deaths), 0.8, 0.8, 0.8)
			end
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.playerRows[i] = r
	end

	-- footer ------------------------------------------------------------------
	local function FootBtn(text, onClick)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(120, 20)
		b:SetText(text)
		b:SetScript("OnClick", onClick)
		if S.SkinButton then S:SkinButton(b) end
		return b
	end
	f.btnMeter = FootBtn(L["Show in meter"] or "Show in meter", function()
		local DM = S:GetModule("DamageMeter")
		if DM and DM.windows and DM.windows[1] and f.selected then
			DM:SetWindowSegment(DM.windows[1], f.selected)
			if DM.windows[1].frame then DM.windows[1].frame:Show() end
		end
	end)
	f.btnMeter:SetPoint("BOTTOMLEFT", 10, 10)
	f.btnWipe = FootBtn(L["Clear history"] or "Clear history", function()
		local DM = S:GetModule("DamageMeter")
		if DM and DM.segments then
			wipe(DM.segments.history)
			f.selected = nil
			SL:Refresh()
		end
	end)
	f.btnWipe:SetPoint("BOTTOMRIGHT", -10, 10)

	f.empty = S:FontString(f, 11, nil, S.media.font, nil, "CENTER")
	f.empty:SetPoint("CENTER", 0, -20)
	f.empty:SetText("|cff666f7a" .. (L["No fight data yet."] or "No fight data yet.") .. "|r")

	-- mouse wheel scrolls the player list (raids have more rows than fit)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(ff, d)
		ff.detailOffset = max(0, (ff.detailOffset or 0) - d)
		SL:Refresh()
	end)

	-- live refresh while the window is open
	f:SetScript("OnUpdate", function(ff, el)
		ff.tick = (ff.tick or 0) + el
		if ff.tick < 0.75 then return end
		ff.tick = 0
		local DM = S:GetModule("DamageMeter")
		if DM and DM.dirty then SL:Refresh() end
	end)
	f:SetScript("OnShow", function() SL:Refresh() end)

	tinsert(UISpecialFrames, "SentinelUISeeLast")
	f:Hide()
	win = f
	return f
end

function SL:Refresh()
	local f = win
	if not f or not f:IsShown() then return end
	local fights, DM = CollectFights()
	if not DM or not DM.initialized then
		f.empty:SetText("|cff666f7a" .. (L["Requires the Damage Meter module."] or "Requires the Damage Meter module.") .. "|r")
		f.empty:Show()
		for _, r in ipairs(f.fightRows) do r:Hide() end
		for _, r in ipairs(f.playerRows) do r:Hide() end
		return
	end

	-- keep the selection valid
	if not f.selected then
		f.selected = fights[1] and fights[1].key or nil
	end
	local selValid = false
	for _, e in ipairs(fights) do if e.key == f.selected then selValid = true break end end
	if not selValid then f.selected = fights[1] and fights[1].key or nil end

	local myGUID = UnitGUID("player")
	for i, row in ipairs(f.fightRows) do
		local e = fights[i]
		if e then
			local seg = e.seg
			local ft = SegTime(seg, DM)
			local totalDmg = 0
			for _, p in pairs(seg.players or {}) do totalDmg = totalDmg + (p.dmg or 0) end
			-- your rank by damage inside this fight
			local my, rank, nPlayers = nil, 0, 0
			for guid, p in pairs(seg.players or {}) do
				nPlayers = nPlayers + 1
				if guid == myGUID then my = p elseif (p.dmg or 0) > (my and my.dmg or 0) then rank = rank + 1 end
			end
			rank = my and (rank + 1) or 0
			local live = e.live and " |cff33cc66[LIVE]|r" or ""
			row.label:SetText("|cff33bbff" .. e.label .. "|r " ..
				(e.seg.label and ("|cff666f7a" .. e.seg.label .. "|r")
					or ("|cff8899aa" .. format("%.0fs", ft) .. "|r")) .. live)
			row.info:SetText(format("|cff8899aa%s|r |cffffd700%s|r%s",
				L["Total"] or "Total", Fmt(totalDmg),
				my and (" |cff33bbff" .. (L["You"] or "You") .. ":|r " .. Fmt(my.dmg) ..
					(rank > 0 and format(" |cffaaaaaa(#%d/%d)|r", rank, nPlayers) or "")) or ""))
			row.fightKey = e.key
			row.hl:SetShown(f.selected == e.key)
			row:Show()
		else
			row:Hide()
		end
	end

	-- detail breakdown of the selected fight
	local sel
	for _, e in ipairs(fights) do if e.key == f.selected then sel = e break end end
	if not sel then
		f.fightInfo:SetText("")
		f.empty:Show()
		for _, r in ipairs(f.playerRows) do r:Hide() end
		return
	end
	f.empty:Hide()
	local ft = SegTime(sel.seg, DM)

	-- pull line: who engaged first, with what spell - or an enemy body pull
	local pull = sel.seg.pull
	local deaths, ints, disps = 0, 0, 0
	for _, p in pairs(sel.seg.players or {}) do
		deaths = deaths + (p.deaths or 0)
		ints = ints + (p.interrupts or 0)
		disps = disps + (p.dispels or 0)
	end
	local pullTxt
	if pull then
		local spell = pull.spell or (L["Melee/Body"] or "Melee/Body")
		pullTxt = format("|cff8899aa%s:|r |cffffd700%s|r · %s%s",
			L["Pull"] or "Pull", pull.name or "?", spell,
			pull.ours and "" or (" |cffff8040(" .. (L["enemy pull"] or "enemy pull") .. ")|r"))
	else
		pullTxt = "|cff666f7a" .. (L["Pull: unknown"] or "Pull: unknown") .. "|r"
	end
	f.fightInfo:SetText(format("%s   |cff666f7a%s:|r %d  |cff666f7a%s:|r %d  |cff666f7a%s:|r %d",
		pullTxt, L["Deaths"] or "Deaths", deaths, L["Interrupts"] or "Interrupts", ints, L["Dispels"] or "Dispels", disps))

	-- header sort indicators
	for i, s in ipairs(SORTS) do
		local h = f.headers[i]
		local mark = f.sortKey == s.key and (f.sortAsc and " ^" or " v") or ""
		h.fs:SetText((L[s.label] or s.label) .. mark)
	end

	local rows = PlayerRows(sel.seg, ft, f.sortKey, f.sortAsc)
	f.detailOffset = max(0, min(#rows - MAX_PLAYER_ROWS, f.detailOffset or 0))
	local maxVal = rows[1] and ValOf(rows[1], f.sortKey, ft) or 0
	if f.sortAsc and #rows > 0 then maxVal = ValOf(rows[#rows], f.sortKey, ft) end
	local total = 0
	for _, r in ipairs(rows) do total = total + ValOf(r, f.sortKey, ft) end
	for i, row in ipairs(f.playerRows) do
		local e = rows[i + f.detailOffset]
		if e then
			local cc = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
			local cr, cg, cb = cc and cc.r or 0.5, cc and cc.g or 0.5, cc and cc.b or 0.5
			row.bar:SetVertexColor(cr, cg, cb, 0.35)
			row.bar:SetWidth(max(4, (maxVal > 0 and (ValOf(e, f.sortKey, ft) / maxVal) or 0) * (WIN_W - 22)))
			row.name:SetText((e.mine and "|cff33bbff" or format("|cff%02x%02x%02x", cr * 255, cg * 255, cb * 255)) .. e.name .. "|r")
			row.vals[2]:SetText(Fmt(e.dmg))
			row.vals[3]:SetText(Fmt(e.dps))
			row.vals[4]:SetText(Fmt(e.heal))
			row.vals[5]:SetText(Fmt(e.hps))
			row.vals[6]:SetText(Fmt(e.taken))
			row.vals[7]:SetText(e.deaths > 0 and ("|cffff4040" .. e.deaths .. "|r") or "0")
			-- highlight the sorted column
			local sortCol = ({ dmg = 2, dps = 3, heal = 4, hps = 5, taken = 6, deaths = 7 })[f.sortKey]
			for ci = 2, 7 do
				row.vals[ci]:SetTextColor(ci == sortCol and 1 or 0.75, ci == sortCol and 0.9 or 0.75, ci == sortCol and 0.4 or 0.78)
			end
			row.entry = e
			row:Show()
		else
			row:Hide()
		end
	end
end

function SL:Toggle()
	local f = BuildWindow()
	if f:IsShown() then f:Hide() else f:Show() end
end

function SL:UpdateMinimap()
	if self.db and self.db.minimapIcon == false then
		if self.minimapBtn then self.minimapBtn:Hide() end
		return
	end
	if not self.minimapBtn then
		self.private.seelastMinimap = self.private.seelastMinimap or {}
		self.minimapBtn = S:CreateMinimapButton({
			name = "SeeLast",
			glyph = "SL",
			store = self.private.seelastMinimap,
			angle = 285,
			onLeft = function() SL:Toggle() end,
			tooltip = function()
				GameTooltip:SetText("SentinelUI SeeLast")
				GameTooltip:AddLine(L["Left-click: last fights overview"] or "Left-click: last fights overview", 0.8, 0.8, 0.8)
			end,
		})
	end
	self.minimapBtn:Show()
	self.minimapBtn:UpdatePosition()
end

function SL:Initialize()
	self.db = S.db.profile.seelast
	self:UpdateMinimap()
	S:RegisterChatCommand("seelast", function() SL:Toggle() end)
	S:RegisterChatCommand("slast", function() SL:Toggle() end)
end

function SL:Update()
	self.db = S.db.profile.seelast
	self:UpdateMinimap()
	if win and win:IsShown() then self:Refresh() end
end
