-- GuildChronicle UI: Roster / Log / Former / Inactive / Alts tabs with
-- sortable columns, search, right-click member actions and export dialog.
local _, ns = ...
local S = ns.S
local L = S.L
local GC = ns.GuildChronicle

local _G = _G
local ipairs, pairs, sort, tinsert = ipairs, pairs, sort, table.insert
local format, floor, min, max = string.format, math.floor, math.min, math.max
local unpack = unpack or table.unpack
local CreateFrame = CreateFrame
local GetServerTime = GetServerTime or time
local strlower, strfind = string.lower, string.find

local WIN_W, WIN_H, ROW_H = 720, 460, 20
local LIST_TOP, LIST_BOTTOM = 86, 34

-- column layouts per tab: { key, label, width, align }
local COLS = {
	roster = {
		{ "name", L["Name"], 150, "LEFT" }, { "level", L["Lvl"], 36, "RIGHT" }, { "rankName", L["Rank"], 110, "LEFT" },
		{ "joined", L["Joined"], 90, "LEFT" }, { "lastOnline", L["Last online"], 90, "LEFT" }, { "main", L["Main"], 110, "LEFT" }, { "note", L["Note"], 0, "LEFT" },
	},
	former = {
		{ "name", L["Name"], 150, "LEFT" }, { "level", L["Lvl"], 36, "RIGHT" }, { "rankName", L["Rank"], 110, "LEFT" },
		{ "joined", L["Joined"], 90, "LEFT" }, { "left", L["Left"], 90, "LEFT" }, { "timesJoined", L["Joins"], 46, "RIGHT" }, { "note", L["Note"], 0, "LEFT" },
	},
	inactive = {
		{ "name", L["Name"], 150, "LEFT" }, { "level", L["Lvl"], 36, "RIGHT" }, { "rankName", L["Rank"], 110, "LEFT" },
		{ "lastOnline", L["Last online"], 90, "LEFT" }, { "idle", L["Inactive"], 90, "LEFT" }, { "main", L["Main"], 110, "LEFT" }, { "note", L["Note"], 0, "LEFT" },
	},
	alts = {
		{ "name", L["Main"], 150, "LEFT" }, { "level", L["Lvl"], 36, "RIGHT" }, { "rankName", L["Rank"], 110, "LEFT" },
		{ "altCount", L["Alts"], 46, "RIGHT" }, { "altList", "", 0, "LEFT" },
	},
	log = {
		{ "t", L["Date"], 110, "LEFT" }, { "k", L["Type"], 90, "LEFT" }, { "n", L["Name"], 130, "LEFT" }, { "x", L["Change"], 0, "LEFT" },
	},
	profs = {
		{ "name", L["Name"], 170, "LEFT" }, { "level", L["Lvl"], 36, "RIGHT" }, { "skill", L["Skill"], 80, "LEFT" },
		{ "src", L["Source"], 90, "LEFT" }, { "online", L["Last online"], 90, "LEFT" }, { "hint", "", 0, "LEFT" },
	},
}

local SRC_LABEL = { self = L["you"], sync = L["SentinelUI sync"], link = L["chat link"], note = L["note"] }

local LOG_FILTERS = { "all", "join", "rejoin", "leave", "kick", "promote", "demote", "level", "note", "onote", "rank", "alt" }

-- ---------------------------------------------------------------------------
-- rows
-- ---------------------------------------------------------------------------
local function MakeRow(list, i)
	local r = list.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, list)
	r:SetHeight(ROW_H)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	S:CreateBackdrop(r, "Default")
	r.cells = {}
	for c = 1, 8 do
		local fs = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
		fs:SetWordWrap(false)
		r.cells[c] = fs
	end
	r:SetScript("OnEnter", function(s)
		local bd = s.suiBackdrop or s
		if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b, 1) end
		if s.tipFunc then
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			s.tipFunc(s)
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(s)
		local bd = s.suiBackdrop or s
		if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(unpack(S.media.borderColor)) end
		GameTooltip:Hide()
	end)
	r:SetScript("OnClick", function(s, btn)
		if btn == "RightButton" and s.member then GC:MemberMenu(s, s.member)
		elseif btn == "LeftButton" and s.tradeLink then
			-- open the posted recipe list exactly like clicking the chat link
			local data = s.tradeLink:match("|H(.-)|h")
			if data and SetItemRef then pcall(SetItemRef, data, s.tradeLink, "LeftButton", DEFAULT_CHAT_FRAME) end
		end
	end)
	list.rows[i] = r
	return r
end

local function LayoutCells(r, cols)
	local x = 6
	local total = r:GetWidth() - 12
	local fixed = 0
	for _, c in ipairs(cols) do fixed = fixed + (c[3] > 0 and c[3] + 6 or 0) end
	for i, c in ipairs(cols) do
		local fs = r.cells[i]
		local w = c[3] > 0 and c[3] or max(40, total - fixed)
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", r, "LEFT", x, 0)
		fs:SetWidth(w)
		fs:SetJustifyH(c[4])
		fs:Show()
		x = x + w + 6
	end
	for i = #cols + 1, #r.cells do r.cells[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- data per tab
-- ---------------------------------------------------------------------------
local function MemberRows(d, which)
	local rows = {}
	local src = which == "former" and d.former or d.members
	for n, m in pairs(src) do rows[#rows + 1] = { name = n, m = m } end
	return rows
end

local function SortValue(row, key, now)
	local m = row.m
	if key == "name" then return strlower(row.name) end
	if key == "idle" then return row.idle or 0 end
	if key == "altCount" then return row.altCount or 0 end
	if key == "lastOnline" then return m.online and now + 1 or (m.lastOnline or 0) end
	if key == "rankName" then return m.rank or 99 end
	local v = m[key]
	if type(v) == "string" then return strlower(v) end
	return v or 0
end

function GC:Rows()
	local d = self:Data()
	if not d then return {} end
	local now = GetServerTime()
	local tab = self.tab or "roster"
	local rows
	if tab == "log" then
		rows = {}
		local f = self.logFilter or "all"
		for i = #d.log, 1, -1 do
			local e = d.log[i]
			if f == "all" or e.k == f then rows[#rows + 1] = { e = e } end
		end
	elseif tab == "inactive" then
		rows = self:Inactive()
	elseif tab == "profs" then
		rows = {}
		for _, g in ipairs(self:ProfessionGroups()) do
			rows[#rows + 1] = { header = g.prof, count = #g.members }
			for _, e in ipairs(g.members) do
				rows[#rows + 1] = { name = e.name, m = e.m, p = e.p, prof = g.prof }
			end
		end
	elseif tab == "alts" then
		rows = {}
		for n, m in pairs(d.members) do
			if not m.main then
				local _, alts = self:AltGroup(n)
				if #alts > 0 or self.showAllMains then rows[#rows + 1] = { name = n, m = m, alts = alts, altCount = #alts } end
			end
		end
	else
		rows = MemberRows(d, tab)
	end
	-- search
	local q = self.search and strlower(self.search) or ""
	if q ~= "" then
		local out = {}
		for _, r in ipairs(rows) do
			local hay = r.header and strlower(r.header)
				or r.e and (strlower((r.e.n or "") .. " " .. (r.e.x or "") .. " " .. (L["gc_" .. r.e.k] or r.e.k)))
				or strlower(r.name .. " " .. (r.prof or "") .. " " .. (r.m.rankName or "") .. " " .. (r.m.note or "") .. " " .. (r.m.onote or "") .. " " .. (r.m.main or ""))
			if strfind(hay, q, 1, true) then out[#out + 1] = r end
		end
		rows = out
		-- profession headers only stay when at least one member row follows
		if tab == "profs" then
			local kept = {}
			for i, r in ipairs(rows) do
				if not r.header or (rows[i + 1] and not rows[i + 1].header) then kept[#kept + 1] = r end
			end
			rows = kept
		end
	end
	if tab ~= "log" and tab ~= "profs" then
		local key, desc = self.sortKey or (tab == "inactive" and "idle" or "name"), self.sortDesc
		if tab == "inactive" and not self.sortKey then desc = true end
		sort(rows, function(a, b)
			local va, vb = SortValue(a, key, now), SortValue(b, key, now)
			if va == vb then return strlower(a.name) < strlower(b.name) end
			if desc then return va > vb end
			return va < vb
		end)
	end
	return rows
end

-- ---------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------
local function HeaderButton(f, i)
	local h = f.headers[i]
	if h then return h end
	h = CreateFrame("Button", nil, f)
	h:SetHeight(16)
	h.fs = S:FontString(h, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	h.fs:SetPoint("LEFT", 0, 0)
	h.fs:SetPoint("RIGHT", 0, 0)
	h.fs:SetTextColor(0.5, 0.5, 0.55)
	h:SetScript("OnClick", function(s)
		if GC.tab == "log" or not s.key then return end
		if GC.sortKey == s.key then GC.sortDesc = not GC.sortDesc else GC.sortKey, GC.sortDesc = s.key, false end
		GC:RefreshFrame()
	end)
	h:SetScript("OnEnter", function(s) s.fs:SetTextColor(1, 1, 1) end)
	h:SetScript("OnLeave", function(s) s.fs:SetTextColor(0.5, 0.5, 0.55) end)
	f.headers[i] = h
	return h
end

local function MakeButton(parent, text, w)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 70, 18)
	S:SkinButton(b)
	b.label = S:FontString(b, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	return b
end

local function BuildFrame()
	if GC.frame then return GC.frame end
	local f = CreateFrame("Frame", "SentinelUIGuildChronicle", UIParent)
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
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
	f.logo:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
	f.logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 6, 0)
	f.title:SetText(L["Guild Chronicle"])
	S:RegisterAccent(f.title, "text")

	f.guild = S:FontString(f, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.guild:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
	f.guild:SetTextColor(0.65, 0.65, 0.7)

	f.close = CreateFrame("Button", nil, f)
	f.close:SetSize(16, 16)
	f.close:SetPoint("TOPRIGHT", -7, -6)
	S:CreateBackdrop(f.close, "Default")
	f.close.fs = S:FontString(f.close, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.close.fs:SetPoint("CENTER")
	f.close.fs:SetText("x")
	f.close:SetScript("OnClick", function() f:Hide() end)

	-- tabs
	f.tabs = {}
	local tabDefs = {
		{ key = "roster", label = L["Roster"] }, { key = "log", label = L["Log"] }, { key = "former", label = L["Former"] },
		{ key = "inactive", label = L["Inactive"] }, { key = "alts", label = L["Alts"] }, { key = "profs", label = L["Professions"] },
	}
	for i, def in ipairs(tabDefs) do
		local t = CreateFrame("Button", nil, f)
		t:SetSize(84, 20)
		t:SetPoint("TOPLEFT", 8 + (i - 1) * 88, -28)
		t.key = def.key
		S:CreateBackdrop(t, "Default")
		t.fs = S:FontString(t, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
		t.fs:SetPoint("CENTER")
		t.fs:SetText(def.label)
		t:SetScript("OnClick", function() GC:SetTab(def.key) end)
		f.tabs[i] = t
	end

	-- strip under the tabs hosting the tab-specific controls (filter, inactive
	-- days, mains toggle, profession request) so they sit inside a real area
	-- instead of floating between tabs and column headers; the search box
	-- lives on its right edge, the strip itself always stays visible
	f.controls = CreateFrame("Frame", nil, f)
	f.controls:SetPoint("TOPLEFT", 6, -50)
	f.controls:SetPoint("TOPRIGHT", -6, -50)
	f.controls:SetHeight(20)
	S:SetTemplate(f.controls, "Default")

	-- search box (right side of the controls strip)
	f.search = CreateFrame("EditBox", nil, f.controls)
	f.search:SetSize(150, 16)
	f.search:SetPoint("RIGHT", f.controls, "RIGHT", -6, 0)
	f.search:SetAutoFocus(false)
	S:SkinEditBox(f.search)
	f.search:SetScript("OnEscapePressed", function(eb) eb:SetText("") eb:ClearFocus() end)
	f.search:SetScript("OnTextChanged", function(eb, user)
		if user then GC.search = eb:GetText() GC.scroll = 0 GC:RefreshFrame() end
	end)
	f.searchHint = S:FontString(f.controls, 9, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	f.searchHint:SetPoint("RIGHT", f.search, "LEFT", -6, 0)
	f.searchHint:SetText(L["Search"])
	f.searchHint:SetTextColor(0.5, 0.5, 0.55)

	f.filterBtn = MakeButton(f.controls, L["All"], 110)
	f.filterBtn:SetPoint("LEFT", f.controls, "LEFT", 2, 0)
	f.filterBtn:SetScript("OnClick", function()
		local idx = 1
		for i, k in ipairs(LOG_FILTERS) do if k == (GC.logFilter or "all") then idx = i end end
		GC.logFilter = LOG_FILTERS[idx % #LOG_FILTERS + 1]
		GC.scroll = 0
		GC:RefreshFrame()
	end)
	f.daysBtn = MakeButton(f.controls, "", 150)
	f.daysBtn:SetPoint("LEFT", f.controls, "LEFT", 2, 0)
	f.daysBtn:SetScript("OnClick", function(_, btn)
		local steps = { 7, 14, 30, 60, 90, 180, 365 }
		local cur = GC.db.inactiveDays or 30
		local idx = 3
		for i, v in ipairs(steps) do if v == cur then idx = i end end
		idx = btn == "RightButton" and (idx - 2) % #steps + 1 or idx % #steps + 1
		GC.db.inactiveDays = steps[idx]
		GC:RefreshFrame()
	end)
	f.daysBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f.allMainsBtn = MakeButton(f.controls, L["Show all mains"], 130)
	f.allMainsBtn:SetPoint("LEFT", f.controls, "LEFT", 2, 0)
	f.allMainsBtn:SetScript("OnClick", function() GC.showAllMains = not GC.showAllMains GC:RefreshFrame() end)
	f.profReqBtn = MakeButton(f.controls, L["Request professions"], 150)
	f.profReqBtn:SetPoint("LEFT", f.controls, "LEFT", 2, 0)
	f.profReqBtn:SetScript("OnClick", function() GC:BroadcastProfessions() GC:RequestProfessions() GC:ProfsFromNotes() GC:Print(L["Profession data requested from guild members using SentinelUI."]) end)
	f.profHint = S:FontString(f.controls, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.profHint:SetPoint("LEFT", f.profReqBtn, "RIGHT", 10, 0)
	f.profHint:SetPoint("RIGHT", f.searchHint, "LEFT", -8, 0)
	f.profHint:SetTextColor(0.5, 0.5, 0.55)
	f.profHint:SetText(L["Sources: SentinelUI users, trade links in guild chat (click a row to open the recipe list), notes."])
	for _, b in ipairs({ f.filterBtn, f.daysBtn, f.allMainsBtn, f.profReqBtn }) do b:Hide() end

	-- column headers
	f.headers = {}
	f.headerRow = CreateFrame("Frame", nil, f)
	f.headerRow:SetPoint("TOPLEFT", 8, -(LIST_TOP - 16))
	f.headerRow:SetPoint("RIGHT", -8, 0)
	f.headerRow:SetHeight(16)

	-- list
	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", 8, -LIST_TOP)
	f.list:SetPoint("BOTTOMRIGHT", -8, LIST_BOTTOM)
	f.list:EnableMouse(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta)
		GC.scroll = max(0, (GC.scroll or 0) - delta * 3)
		GC:RefreshFrame()
	end)
	f.list.rows = {}

	-- footer
	f.summary = S:FontString(f, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.summary:SetPoint("BOTTOMLEFT", 10, 10)
	f.summary:SetPoint("RIGHT", -260, 0)
	f.summary:SetTextColor(0.65, 0.65, 0.7)

	f.exportBtn = MakeButton(f, L["Export"], 70)
	f.exportBtn:SetPoint("BOTTOMRIGHT", -8, 8)
	f.exportBtn:SetScript("OnClick", function() GC:ExportDialog(GC.tab == "log" and "log" or "roster") end)
	f.scanBtn = MakeButton(f, L["Rescan"], 70)
	f.scanBtn:SetPoint("RIGHT", f.exportBtn, "LEFT", -6, 0)
	f.scanBtn:SetScript("OnClick", function() GC:RequestScan() end)
	f.cfgBtn = MakeButton(f, L["Settings"], 80)
	f.cfgBtn:SetPoint("RIGHT", f.scanBtn, "LEFT", -6, 0)
	f.cfgBtn:SetScript("OnClick", function() S:ToggleConfig("guildchronicle") end)

	tinsert(UISpecialFrames, "SentinelUIGuildChronicle")
	f:SetScript("OnShow", function() GC:RequestScan() GC:RefreshFrame() end)
	GC.frame = f
	return f
end

function GC:SetTab(key)
	local f = BuildFrame()
	self.tab = key
	self.scroll = 0
	self.sortKey = nil
	for _, t in ipairs(f.tabs) do
		local bd = t.suiBackdrop or t
		if t.key == key then
			if bd.SetBackdropColor then bd:SetBackdropColor(S.accent.r * 0.3, S.accent.g * 0.3, S.accent.b * 0.3, 0.8) end
			t.fs:SetTextColor(1, 1, 1)
		else
			if bd.SetBackdropColor then bd:SetBackdropColor(0.08, 0.08, 0.1, 0.8) end
			t.fs:SetTextColor(0.7, 0.7, 0.75)
		end
	end
	self:RefreshFrame()
end

function GC:Toggle(tab)
	local f = BuildFrame()
	if f:IsShown() and (not tab or tab == self.tab) then f:Hide() return end
	f:Show()
	self:SetTab(tab or self.tab or "roster")
end

-- ---------------------------------------------------------------------------
-- fill
-- ---------------------------------------------------------------------------
local function CellText(row, col, now)
	local key = col[1]
	local m = row.m
	if key == "name" then return GC:ColoredName(row.name, m.class) .. (m.online and " |cff33ff33*|r" or "") end
	if key == "level" then return tostring(m.level or "") end
	if key == "rankName" then return m.rankName or "" end
	if key == "joined" then return (m.joinedApprox and "~" or "") .. GC:DateText(m.joined) end
	if key == "left" then return GC:DateText(m.left) end
	if key == "lastOnline" then return m.online and "|cff33ff33" .. L["online"] .. "|r" or GC:DaysAgoText(now - (m.lastOnline or 0)) end
	if key == "idle" then return GC:DaysAgoText(row.idle) end
	if key == "timesJoined" then return tostring(m.timesJoined or 1) end
	if key == "main" then
		if not m.main then return "" end
		local mm = GC:Data().members[m.main]
		return GC:ColoredName(m.main, mm and mm.class) .. (m.autoMain and " |cff888888?|r" or "")
	end
	if key == "altCount" then return tostring(row.altCount or 0) end
	if key == "altList" then
		local parts = {}
		local d = GC:Data()
		for _, a in ipairs(row.alts or {}) do parts[#parts + 1] = GC:ColoredName(a, d.members[a] and d.members[a].class) end
		return table.concat(parts, "  ")
	end
	if key == "note" then
		local own = GC:Data().notes[row.name]
		return (m.note or "") .. (own and own ~= "" and format(" |cff%s[%s]|r", S.accentHex, own) or "")
	end
	return ""
end

function GC:RefreshFrame()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local d = self:Data()
	local tab = self.tab or "roster"
	local cols = COLS[tab]
	local now = GetServerTime()

	f.guild:SetText(d and format("<%s>", self:GuildName() or "") or L["Not in a guild"])
	f.controls:Show()
	f.filterBtn:SetShown(tab == "log")
	f.daysBtn:SetShown(tab == "inactive")
	f.allMainsBtn:SetShown(tab == "alts")
	f.profReqBtn:SetShown(tab == "profs")
	f.profHint:SetShown(tab == "profs")
	if tab == "log" then
		local key = self.logFilter or "all"
		f.filterBtn.label:SetText(L["Filter"] .. ": " .. (key == "all" and L["All"] or (L["gc_" .. key] or key)))
	end
	if tab == "inactive" then f.daysBtn.label:SetText(format(L["Inactive > %d days"], self.db.inactiveDays or 30)) end
	if tab == "alts" then f.allMainsBtn.label:SetText(self.showAllMains and L["Only mains with alts"] or L["Show all mains"]) end

	-- headers
	local x = 6
	local total = f.headerRow:GetWidth() - 12
	local fixed = 0
	for _, c in ipairs(cols) do fixed = fixed + (c[3] > 0 and c[3] + 6 or 0) end
	for i, c in ipairs(cols) do
		local h = HeaderButton(f, i)
		local w = c[3] > 0 and c[3] or max(40, total - fixed)
		h:ClearAllPoints()
		h:SetPoint("LEFT", f.headerRow, "LEFT", x, 0)
		h:SetWidth(w)
		h.key = c[1]
		local arrow = ""
		if tab ~= "log" and tab ~= "profs" and (self.sortKey or (tab == "inactive" and "idle" or "name")) == c[1] then
			arrow = (self.sortDesc or (tab == "inactive" and not self.sortKey)) and " v" or " ^"
		end
		h.fs:SetText(c[2] .. arrow)
		h.fs:SetJustifyH(c[4])
		h:Show()
		x = x + w + 6
	end
	for i = #cols + 1, #f.headers do f.headers[i]:Hide() end

	local rows = d and self:Rows() or {}
	local visible = floor((f.list:GetHeight() + 2) / (ROW_H + 2))
	local maxScroll = max(0, #rows - visible)
	self.scroll = min(self.scroll or 0, maxScroll)

	for i = 1, visible do
		local row = rows[i + self.scroll]
		local r = MakeRow(f.list, i)
		if row then
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -((i - 1) * (ROW_H + 2)))
			r:SetPoint("RIGHT", f.list, "RIGHT", 0, 0)
			r:Show()
			LayoutCells(r, cols)
			r.member = nil
			r.tipFunc = nil
			r.tradeLink = nil
			local bd = r.suiBackdrop
			if row.header then
				-- profession group header
				for c = 1, #cols do r.cells[c]:SetText("") end
				r.cells[1]:SetText(format("|cff%s%s|r  |cff888888(%d)|r", S.accentHex, row.header, row.count or 0))
				if bd then bd:SetBackdropColor(S.accent.r * 0.25, S.accent.g * 0.25, S.accent.b * 0.25, 0.8) end
			elseif tab == "profs" then
				local p = row.p
				r.cells[1]:SetText("    " .. self:ColoredName(row.name, row.m.class) .. (row.m.online and " |cff33ff33*|r" or ""))
				r.cells[2]:SetText(tostring(row.m.level or ""))
				r.cells[3]:SetText(p.skill and (p.max and format("%d/%d", p.skill, p.max) or tostring(p.skill)) or "|cff888888?|r")
				r.cells[4]:SetText(SRC_LABEL[p.src] or p.src or "")
				r.cells[5]:SetText(row.m.online and "|cff33ff33" .. L["online"] .. "|r" or self:DaysAgoText(now - (row.m.lastOnline or 0)))
				r.cells[6]:SetText(p.link and ("|cff71d5ff" .. L["click: recipe list"] .. "|r") or "")
				r.member = row.name
				r.tradeLink = p.link
				r.tipFunc = function() GC:MemberTooltip(row.name, row.m, false) end
				if bd then bd:SetBackdropColor(0.08, 0.08, 0.1, 0.6) end
			elseif tab == "log" then
				local e = row.e
				r.cells[1]:SetText(date("%d.%m.%y %H:%M", e.t or 0))
				r.cells[2]:SetText(self:TypeColor(e.k) .. (L["gc_" .. e.k] or e.k) .. "|r")
				local m = d.members[e.n] or d.former[e.n]
				r.cells[3]:SetText(self:ColoredName(e.n, m and m.class))
				r.cells[4]:SetText(e.x or "")
				if d.members[e.n] then r.member = e.n end
				if bd then bd:SetBackdropColor(0.08, 0.08, 0.1, 0.6) end
			else
				for c, col in ipairs(cols) do r.cells[c]:SetText(CellText(row, col, now)) end
				if tab ~= "former" then r.member = row.name end
				r.tipFunc = function() GC:MemberTooltip(row.name, row.m, tab == "former") end
				if bd then
					if tab == "inactive" and row.idle and row.idle > (self.db.inactiveDays or 30) * 86400 * 3 then
						bd:SetBackdropColor(0.3, 0.08, 0.08, 0.6)
					else
						bd:SetBackdropColor(0.08, 0.08, 0.1, 0.6)
					end
				end
			end
		else
			r:Hide()
		end
	end
	for i = visible + 1, #f.list.rows do f.list.rows[i]:Hide() end

	-- footer summary
	if d then
		local n, on = 0, 0
		for _, m in pairs(d.members) do n = n + 1 if m.online then on = on + 1 end end
		local shown = #rows
		local extra = ""
		if tab == "log" then extra = format("  |cff888888%d %s|r", shown, L["entries"])
		elseif tab == "former" then extra = format("  |cff888888%d %s|r", shown, L["former members"])
		elseif tab == "inactive" then extra = format("  |cffff6666%d %s|r", shown, L["inactive"])
		end
		f.summary:SetText(format("%d %s, %d %s%s  |cff666666%s %s|r", n, L["members"], on, L["online"], extra,
			L["Last scan"], d.lastScan and date("%H:%M", d.lastScan) or "-"))
	else
		f.summary:SetText(L["Not in a guild"])
	end
end

-- ---------------------------------------------------------------------------
-- member tooltip + context menu
-- ---------------------------------------------------------------------------
function GC:MemberTooltip(name, m, former)
	local d = self:Data()
	local tip = GameTooltip
	tip:AddLine(self:ColoredName(name, m.class), 1, 1, 1)
	tip:AddDoubleLine(L["Rank"], m.rankName or "?", 0.6, 0.8, 1, 1, 1, 1)
	tip:AddDoubleLine(L["Level"], tostring(m.level or "?"), 0.6, 0.8, 1, 1, 1, 1)
	tip:AddDoubleLine(L["Joined"], (m.joinedApprox and "~" or "") .. self:DateText(m.joined), 0.6, 0.8, 1, 1, 1, 1)
	if m.prevJoined then tip:AddDoubleLine(L["First joined"], self:DateText(m.prevJoined), 0.6, 0.8, 1, 1, 1, 1) end
	if former then tip:AddDoubleLine(L["Left"], self:DateText(m.left), 0.6, 0.8, 1, 1, 1, 1) end
	if m.rankChanged then tip:AddDoubleLine(L["Rank since"], self:DateText(m.rankChanged), 0.6, 0.8, 1, 1, 1, 1) end
	if m.online then
		tip:AddDoubleLine(L["Zone"], m.zone or "?", 0.6, 0.8, 1, 1, 1, 1)
	elseif m.lastOnline then
		tip:AddDoubleLine(L["Last online"], self:DateText(m.lastOnline), 0.6, 0.8, 1, 1, 1, 1)
	end
	if not former and d then
		local main, alts = self:AltGroup(name)
		if main ~= name then tip:AddDoubleLine(L["Main"], self:ColoredName(main, d.members[main] and d.members[main].class), 0.6, 0.8, 1, 1, 1, 1) end
		if #alts > 0 then
			local parts = {}
			for _, a in ipairs(alts) do parts[#parts + 1] = self:ColoredName(a, d.members[a].class) end
			tip:AddLine(L["Alts"] .. ": " .. table.concat(parts, ", "), 0.6, 0.8, 1, true)
		end
	end
	local profs = self:ProfText(m)
	if profs then tip:AddLine(L["Professions"] .. ": " .. profs, 0.6, 0.8, 1, true) end
	if m.note and m.note ~= "" then tip:AddLine(L["Note"] .. ": " .. m.note, 0.8, 0.8, 0.8, true) end
	if m.onote and m.onote ~= "" then tip:AddLine(L["Officer note"] .. ": " .. m.onote, 0.7, 0.7, 0.95, true) end
	local own = d and d.notes[name]
	if own and own ~= "" then tip:AddLine(format("|cff%s%s:|r %s", S.accentHex, L["Chronicle note"], own), 1, 1, 1, true) end
	-- recent history
	if d then
		local shown = 0
		for i = #d.log, 1, -1 do
			local e = d.log[i]
			if e.n == name then
				if shown == 0 then tip:AddLine(" ") tip:AddLine(L["History"], 0.6, 0.8, 1) end
				tip:AddLine(format("|cff888888%s|r %s%s|r %s", date("%d.%m.%y", e.t or 0), self:TypeColor(e.k), L["gc_" .. e.k] or e.k, e.x or ""), 0.9, 0.9, 0.9, true)
				shown = shown + 1
				if shown >= 6 then break end
			end
		end
	end
	if not former then tip:AddLine(" ") tip:AddLine(L["Right-click for actions"], 0.5, 0.5, 0.55) end
end

local menu
local function MenuItem(parent, i)
	local b = parent.items[i]
	if b then return b end
	b = CreateFrame("Button", nil, parent)
	b:SetHeight(18)
	b:SetPoint("LEFT", 4, 0)
	b:SetPoint("RIGHT", -4, 0)
	b.fs = S:FontString(b, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	b.fs:SetPoint("LEFT", 6, 0)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.25)
	parent.items[i] = b
	return b
end

function GC:MemberMenu(anchor, name)
	local d = self:Data()
	if not d or not d.members[name] then return end
	if not menu then
		menu = CreateFrame("Frame", "SentinelUIGuildChronicleMenu", UIParent)
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:SetWidth(200)
		S:SetTemplate(menu, "Transparent")
		menu.items = {}
		menu:SetScript("OnLeave", function(m) C_Timer.After(0.4, function() if not m:IsMouseOver() then m:Hide() end end) end)
		menu:EnableMouse(true)
		tinsert(UISpecialFrames, "SentinelUIGuildChronicleMenu")
	end
	local m = d.members[name]
	local items = {
		{ text = self:ColoredName(name, m.class), header = true },
		{ text = L["Whisper"], func = function() ChatFrame_OpenChat("/w " .. name .. " ", DEFAULT_CHAT_FRAME) end },
		{ text = L["Invite to group"], func = function() if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end end },
		{ text = L["Set main..."], func = function() self:PromptMain(name) end },
	}
	if m.main then items[#items + 1] = { text = format(L["Remove alt link (%s)"], m.main), func = function() self:SetMain(name, nil) end } end
	items[#items + 1] = { text = L["Chronicle note..."], func = function() self:PromptNote(name) end }
	if CanEditPublicNote and CanEditPublicNote() then
		items[#items + 1] = { text = L["Edit public note..."], func = function() self:PromptGuildNote(name, false) end }
	end
	if CanEditOfficerNote and CanEditOfficerNote() then
		items[#items + 1] = { text = L["Edit officer note..."], func = function() self:PromptGuildNote(name, true) end }
	end
	if CanGuildPromote and CanGuildPromote() and m.rank > 1 then
		items[#items + 1] = { text = L["Promote"], func = function() GuildPromote(name) self:Delay(1, self.RequestScan, self) end }
	end
	if CanGuildDemote and CanGuildDemote() and m.rank < (#d.ranks) then
		items[#items + 1] = { text = L["Demote"], func = function() GuildDemote(name) self:Delay(1, self.RequestScan, self) end }
	end
	if CanGuildRemove and CanGuildRemove() then
		items[#items + 1] = { text = "|cffff5555" .. L["Remove from guild"] .. "|r", func = function()
			StaticPopupDialogs["SENTINELUI_GC_KICK"] = StaticPopupDialogs["SENTINELUI_GC_KICK"] or {
				text = L["Remove %s from the guild?"], button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
				OnAccept = function(_, who) GuildUninvite(who) GC:Delay(1, GC.RequestScan, GC) end,
			}
			StaticPopup_Show("SENTINELUI_GC_KICK", name, nil, name)
		end }
	end
	for i, it in ipairs(items) do
		local b = MenuItem(menu, i)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 4, -(4 + (i - 1) * 19))
		b:SetPoint("RIGHT", -4, 0)
		b.fs:SetText(it.text)
		b.fs:SetTextColor(1, 1, 1)
		if it.header then b.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
		b:EnableMouse(not it.header)
		b:SetScript("OnClick", function() menu:Hide() if it.func then S:SafeCall("GuildChronicle:Menu", it.func) end end)
		b:Show()
	end
	for i = #items + 1, #menu.items do menu.items[i]:Hide() end
	menu:SetHeight(8 + #items * 19)
	menu:ClearAllPoints()
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 4, y / s + 4)
	menu:Show()
end

-- ---------------------------------------------------------------------------
-- input dialogs
-- ---------------------------------------------------------------------------
local function InputPopup(key, text, onAccept, maxLetters, initial)
	StaticPopupDialogs[key] = StaticPopupDialogs[key] or {
		text = "%s", button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, editBoxWidth = 260, maxLetters = maxLetters or 31,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
		OnShow = function(self, data)
			local eb = self.editBox or self.EditBox
			if eb then eb:SetText(data and data.initial or "") eb:SetFocus() eb:HighlightText() end
		end,
		OnAccept = function(self, data)
			local eb = self.editBox or self.EditBox
			if data and data.func then data.func(eb and eb:GetText() or "") end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			if p.data and p.data.func then p.data.func(self:GetText()) end
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	}
	StaticPopup_Show(key, text, nil, { func = onAccept, initial = initial })
end

function GC:PromptMain(alt)
	local d = self:Data()
	InputPopup("SENTINELUI_GC_MAIN", format(L["Main character of %s:"], alt), function(txt)
		txt = (txt or ""):match("^%s*(.-)%s*$")
		if txt == "" then return end
		local main = txt:sub(1, 1):upper() .. txt:sub(2):lower()
		if not d.members[main] then
			-- case-insensitive lookup
			for n in pairs(d.members) do if strlower(n) == strlower(txt) then main = n break end end
		end
		self:SetMain(alt, main)
	end, 12, d.members[alt] and d.members[alt].main or "")
end

function GC:PromptNote(name)
	local d = self:Data()
	InputPopup("SENTINELUI_GC_NOTE", format(L["Chronicle note for %s (only you see this):"], name), function(txt)
		d.notes[name] = (txt and txt ~= "") and txt or nil
		self:RefreshFrame()
	end, 120, d.notes[name] or "")
end

function GC:PromptGuildNote(name, officer)
	local d = self:Data()
	local m = d.members[name]
	InputPopup(officer and "SENTINELUI_GC_ONOTE" or "SENTINELUI_GC_PNOTE",
		format(officer and L["Officer note for %s:"] or L["Public note for %s:"], name), function(txt)
		for i = 1, GetNumGuildMembers() do
			local full = GetGuildRosterInfo(i)
			if GC.ShortName(full) == name then
				if officer then GuildRosterSetOfficerNote(i, txt or "") else GuildRosterSetPublicNote(i, txt or "") end
				break
			end
		end
		self:Delay(1, self.RequestScan, self)
	end, 31, m and (officer and m.onote or m.note) or "")
end

-- ---------------------------------------------------------------------------
-- export dialog
-- ---------------------------------------------------------------------------
function GC:ExportDialog(what)
	local name = "SentinelUIGuildChronicleExport"
	local f = _G[name]
	if not f then
		f = CreateFrame("Frame", name, UIParent)
		f:SetSize(560, 360)
		f:SetPoint("CENTER")
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		S:SetTemplate(f, "Transparent", "TOP")
		f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont, nil, "LEFT")
		f.title:SetPoint("TOPLEFT", 10, -8)
		S:RegisterAccent(f.title, "text")
		f.close = CreateFrame("Button", nil, f)
		f.close:SetSize(16, 16)
		f.close:SetPoint("TOPRIGHT", -7, -6)
		S:CreateBackdrop(f.close, "Default")
		f.close.fs = S:FontString(f.close, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
		f.close.fs:SetPoint("CENTER")
		f.close.fs:SetText("x")
		f.close:SetScript("OnClick", function() f:Hide() end)
		local sf = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 10, -30)
		sf:SetPoint("BOTTOMRIGHT", -30, 28)
		if sf.ScrollBar then S:SkinScrollBar(sf.ScrollBar) end
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetMaxLetters(0)
		eb:SetFontObject(ChatFontNormal or GameFontNormal)
		eb:SetWidth(500)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		sf:SetScrollChild(eb)
		f.box = eb
		local hint = S:FontString(f, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
		hint:SetPoint("BOTTOM", 0, 8)
		hint:SetText("|cff888888" .. L["Ctrl+A to select all, Ctrl+C to copy."] .. "|r")
		tinsert(UISpecialFrames, name)
	end
	f.title:SetText(L["Guild Chronicle"] .. " - " .. (what == "log" and L["Log"] or L["Roster"]) .. " CSV")
	f.box:SetText(what == "log" and self:ExportLog(self.logFilter) or self:ExportRoster())
	f:Show()
	f.box:HighlightText()
	f.box:SetFocus()
end
