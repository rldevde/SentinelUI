-- GuildHubUI: tab renderers + module init for GuildHub (loads after GuildHub.lua)
local _, ns = ...
local S = ns.S
local L = S.L
local GH = S:GetModule("GuildHub")

local _G = _G
local ipairs, pairs, wipe, tinsert, tremove, sort, tonumber, tostring, type, next = ipairs, pairs, wipe, table.insert, table.remove, table.sort, tonumber, tostring, type, next
local format, lower, upper, strtrim, gmatch, find, gsub = string.format, string.lower, string.upper, strtrim, string.gmatch, string.find, string.gsub
local min, max, floor, time, date = math.min, math.max, math.floor, time, date
local CreateFrame, GetTime, InCombatLockdown, IsInGuild = CreateFrame, GetTime, InCombatLockdown, IsInGuild
local UnitName, UnitClass, UnitLevel, GetRealmName, IsInGroup, IsInRaid, GetNumGroupMembers = UnitName, UnitClass, UnitLevel, GetRealmName, IsInGroup, IsInRaid, GetNumGroupMembers
local Ambiguate, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo = Ambiguate, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo
local GameTooltip, UIDropDownMenu_Initialize, EasyMenu = GameTooltip, UIDropDownMenu_Initialize, EasyMenu
local IsSecret = S.IsSecret

-- pull in upvalues defined by GuildHub.lua via debug-safe module locals
local Shared, Priv, Roster, Send, Bump, Notify = GH._Shared, GH._Priv, GH._Roster, GH._Send, GH._Bump, GH._Notify
local IsMember, OnlineOf, IsGM, HasRight, CanI = GH._IsMember, GH._OnlineOf, GH._IsGM, GH._HasRight, GH._CanI
local AltStatus, MainOf, AltsOf, RoleIcon, RoleName = GH._AltStatus, GH._MainOf, GH._AltsOf, GH._RoleIcon, GH._RoleName
local myName
local function MN()
	if not myName then myName = GH._GetMyName() or UnitName("player") or "?" end
	return myName
end

GH.tabs = {}
local tabs = GH.tabs

local ACC = S.accentHex or "ffcc00"
local ROW_H = 20

local function Btn(parent, w, h, label)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	S:CreateBackdrop(b, "Default")
	b.fs = S:FontString(b, 11, nil, S.media.font, nil, "CENTER")
	b.fs:SetPoint("CENTER")
	b.fs:SetText(label)
	S:AddHover(b)
	return b
end

local function Checkbox(parent, label, checked, onClick)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(16, 16)
	S:SkinCheckBox(cb)
	cb:SetChecked(checked and true or false)
	cb.fs = S:FontString(cb, 11, nil, S.media.font, nil, "LEFT")
	cb.fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	cb.fs:SetText(label)
	cb:SetScript("OnClick", function(c) onClick(c:GetChecked() and true or false) end)
	cb:SetHitRectInsets(0, -max(60, cb.fs:GetStringWidth() + 8), 0, 0)
	return cb
end

local function Edit(parent, w, h, placeholder)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(w, h)
	e:SetAutoFocus(false)
	e:SetFontObject("GameFontHighlight")
	S:SkinEditBox(e, h)
	if placeholder then
		e.ph = S:FontString(e, 11, nil, S.media.font, nil, "LEFT")
		e.ph:SetPoint("LEFT", 6, 0)
		e.ph:SetText("|cff777777" .. placeholder .. "|r")
		e:SetScript("OnTextChanged", function(s) s.ph:SetShown(s:GetText() == "") end)
	end
	e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	return e
end

local function Header(parent, text)
	local fs = S:FontString(parent, 12, "OUTLINE", S.media.font, nil, "LEFT")
	fs:SetText("|cff" .. ACC .. upper(text) .. "|r")
	return fs
end

local function ClassColor(name)
	local e = Roster()[name]
	local c = e and e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
	if c then return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
	return name
end

local function Ago(t)
	if not t then return "?" end
	local d = time() - t
	if d < 60 then return L["just now"] end
	if d < 3600 then return format(L["%d min ago"], floor(d / 60)) end
	if d < 86400 then return format(L["%d h ago"], floor(d / 3600)) end
	return format(L["%d d ago"], floor(d / 86400))
end

local function ListRows(page, topY, rowH, n, fill)
	local rows = page._lrows or {}
	page._lrows = rows
	for _, r in ipairs(rows) do r:Hide() end
	for i = 1, n do
		local r = rows[i]
		if not r then
			r = CreateFrame("Button", nil, page)
			r:SetHeight(rowH)
			r.bg = r:CreateTexture(nil, "BACKGROUND")
			r.bg:SetAllPoints()
			r.fss = {}
			rows[i] = r
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, topY - (i - 1) * rowH)
		r:SetPoint("TOPRIGHT", 0, topY - (i - 1) * rowH)
		r.bg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.03 or 0)
		for _, fs in pairs(r.fss) do fs:Hide() end
		fill(r, i)
		r:Show()
	end
	return rows
end

local function RowFS(r, key, x, size, justify)
	local fs = r.fss[key]
	if not fs then
		fs = S:FontString(r, size or 11, nil, S.media.font, nil, justify or "LEFT")
		r.fss[key] = fs
	end
	fs:ClearAllPoints()
	fs:SetPoint(justify == "RIGHT" and "RIGHT" or "LEFT", x, 0)
	if justify == "RIGHT" then fs:SetPoint("RIGHT", x, 0) end
	fs:SetJustifyH(justify or "LEFT")
	fs:Show()
	return fs
end

local function SortHeader(page, text, x, y, key, state)
	local b = CreateFrame("Button", nil, page)
	b:SetPoint("TOPLEFT", x, y)
	b:SetSize(160, 16)
	b.fs = S:FontString(b, 11, "OUTLINE", S.media.font, nil, "LEFT")
	b.fs:SetPoint("LEFT")
	b.fs:SetText("|cff" .. ACC .. text .. (state.sort == key and (state.desc and " v" or " ^") or "") .. "|r")
	b:SetScript("OnClick", function()
		if state.sort == key then state.desc = not state.desc else state.sort, state.desc = key, false end
		GH:RenderTab(GH.tab)
	end)
	return b
end

local function SendWhisper(text, who)
	if SendChatMessage then SendChatMessage(text, "WHISPER", nil, who) end
end
local function Whisper(name) SetItemRef("player:" .. name, "|Hplayer:" .. name .. "|h[" .. name .. "]|h", "LeftButton") end
local function Invite(name) if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end end

local function MemberMenu(name)
	if not (EasyMenu and DropDownList1) then return end
	local menu = {
		{ text = name, isTitle = true, notCheckable = true },
		{ text = L["Whisper"], notCheckable = true, func = function() Whisper(name) end },
		{ text = L["Invite"], notCheckable = true, func = function() Invite(name) end },
	}
	if CanI("roles") or CanI("leader") then
		for _, r in ipairs({ "T", "H", "D", "N" }) do
			menu[#menu + 1] = { text = format(L["Set role: %s"], RoleName(r)), notCheckable = true,
				func = function()
					Shared().roles[name] = r
					Send("SR|" .. name .. "|" .. r)
					GH:RenderTab("roster")
				end }
		end
	end
	EasyMenu(menu, GH.menuFrame or CreateFrame("Frame", "SUGHMenu", UIParent, "UIDropDownMenuTemplate"), "cursor", 0, 0, "MENU")
end

-- extra appliers installed here (leader-set role for others)
GH._appliers.SR = function(rest, sender)
	if not (HasRight(sender, "roles") or HasRight(sender, "leader")) then return end
	local name, role = rest:match("^(.-)|([THDN])$")
	if name and role and IsMember(name) then Shared().roles[name] = role Bump() GH:MaybeRefresh("roster") end
end

-------------------------------------------------------------------------------
-- TAB: Guild Roster
-------------------------------------------------------------------------------

tabs.roster = function(self, page)
	local h = Shared()
	local st = GH.rosterState or { sort = "name", desc = false, roleFilter = "all", hideOffline = false, mainsOnly = false, search = "" }
	GH.rosterState = st

	-- own role row
	local lab = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
	lab:SetPoint("TOPLEFT", 4, -2)
	lab:SetText(L["Your role:"])
	local x = 80
	for _, r in ipairs(ROLE_ORDER) do
		local b = Btn(page, 62, 18, RoleName(r))
		b:SetPoint("TOPLEFT", x, -2)
		b:SetScript("OnClick", function()
			if h.perms.membersCanRole == false and not CanI("roles") then return end
			h.roles[MN()] = r Bump()
			Send("R|" .. r)
			GH:RenderTab("roster")
		end)
		if h.roles[MN()] == r then b.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
		x = x + 66
	end

	-- filters
	x = 4
	local function FBtn(label, key, val, w)
		local b = Btn(page, w or 56, 16, label)
		b:SetPoint("TOPLEFT", x, -28)
		b:SetScript("OnClick", function() st.roleFilter = val GH:RenderTab("roster") end)
		if st.roleFilter == val then b.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
		x = x + (w or 56) + 4
	end
	FBtn(L["All"], nil, "all")
	FBtn(L["Tank"], nil, "T")
	FBtn(L["Healer"], nil, "H")
	FBtn(L["DPS"], nil, "D")
	FBtn(L["No role"], nil, "N", 70)
	local c1 = Checkbox(page, L["Show offline"], not st.hideOffline, function(v) st.hideOffline = not v GH:RenderTab("roster") end)
	c1:SetPoint("TOPLEFT", x + 4, -28)
	local c2 = Checkbox(page, L["Mains only"], st.mainsOnly, function(v) st.mainsOnly = v GH:RenderTab("roster") end)
	c2:SetPoint("TOPLEFT", x + 104, -28)
	local srch = Edit(page, 120, 16, L["Search names"])
	srch:SetPoint("TOPRIGHT", -4, -28)
	srch:SetText(st.search or "")
	srch:SetScript("OnTextChanged", function(e) st.search = e:GetText() GH:RenderTab("roster") end)

	-- counts
	local cnt = { T = 0, H = 0, D = 0, N = 0 }
	for name in pairs(Roster()) do cnt[h.roles[name] or "N"] = (cnt[h.roles[name] or "N"] or 0) + 1 end
	local cl = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
	cl:SetPoint("TOPLEFT", 4, -50)
	cl:SetText(format("%s%s %d|r  ·  %s%s %d|r  ·  %s%s %d|r  ·  %s %d",
		RoleIcon("T"), L["Tanks"], cnt.T, RoleIcon("H"), L["Healers"], cnt.H,
		RoleIcon("D"), L["DPS"], cnt.D, L["No role"], cnt.N))
	if CanI("roles") then
		local hint = S:FontString(page, 10, nil, S.media.font, nil, "RIGHT")
		hint:SetPoint("TOPRIGHT", -4, -50)
		hint:SetText("|cff888888" .. L["Click a member to set their role."] .. "|r")
	end

	-- header
	local hy = -70
	SortHeader(page, L["NAME"], 26, hy, "name", st)
	SortHeader(page, L["LEVEL"], 240, hy, "level", st)
	SortHeader(page, L["RANK"], 300, hy, "rank", st)
	SortHeader(page, L["ROLE"], 420, hy, "role", st)
	SortHeader(page, L["ZONE"], 510, hy, "zone", st)

	-- build rows
	local list = {}
	local q = lower(st.search or "")
	for name, e in pairs(Roster()) do
		local role = h.roles[name] or "N"
		local main = MainOf(name)
		local st2, mName = AltStatus(name)
		local isAlt = h.altDecl[name] ~= nil
		if (q == "" or lower(name):find(q, 1, true))
			and (st.roleFilter == "all" or role == st.roleFilter)
			and (not st.hideOffline or e.online)
			and (not st.mainsOnly or not isAlt)
		then
			list[#list + 1] = { name = name, e = e, role = role, isAlt = isAlt, main = main,
				nAlts = #AltsOf(name), linked = st2 == "linked" }
		end
	end
	local roleIdx = { T = 1, H = 2, D = 3, N = 4 }
	sort(list, function(a, b)
		local k = st.sort
		local va, vb
		if k == "level" then va, vb = a.e.level or 0, b.e.level or 0
		elseif k == "rank" then va, vb = a.e.rank or 99, b.e.rank or 99
		elseif k == "role" then va, vb = roleIdx[a.role], roleIdx[b.role]
		elseif k == "zone" then va, vb = a.e.zone or "", b.e.zone or ""
		else va, vb = a.name, b.name end
		if va == vb then return a.name < b.name end
		if st.desc then return va > vb end
		return va < vb
	end)
	if st.mainsOnly then
		local seen, out = {}, {}
		for _, r in ipairs(list) do
			if not seen[r.main] then seen[r.main] = true out[#out + 1] = r end
		end
		list = out
	end

	ListRows(page, hy - 18, ROW_H, min(#list, 28), function(r, i)
		local m = list[i]
		if not m then return end
		local name, e = m.name, m.e
		local role = m.role
		RowFS(r, "icon", 4):SetText(RoleIcon(role, 13))
		local label = ClassColor(name)
		if name == MN() then label = label .. " |cff888888(" .. L["you"] .. ")|r" end
		if m.isAlt then label = "    " .. label .. " |cff777777" .. format(L["alt of %s"], m.main or "?") .. "|r"
		elseif m.nAlts > 0 then label = label .. format(" |cff777777+%d %s|r", m.nAlts, L["alts"]) end
		RowFS(r, "name", 22):SetText(label)
		RowFS(r, "level", 240):SetText(tostring(e.level or ""))
		RowFS(r, "rank", 300):SetText(e.rankName or "")
		local rfs = RowFS(r, "role", 420)
		rfs:SetText(role ~= "N" and (RoleIcon(role, 13) .. " " .. RoleName(role)) or "|cff555555—|r")
		RowFS(r, "zone", 510):SetText(e.online and (e.zone or "") or "|cff666666" .. L["offline"] .. "|r")
		if not e.online then r.bg:SetColorTexture(0, 0, 0, 0) end
		if name == MN() then
			r.bg:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.10)
		end
		r:SetScript("OnClick", function(_, btn)
			if btn == "RightButton" then MemberMenu(name)
			elseif (CanI("roles") or CanI("leader")) and name ~= MN() then MemberMenu(name)
			else MemberMenu(name) end
		end)
	end)
	local foot = S:FontString(page, 10, nil, S.media.font, nil, "RIGHT")
	foot:SetPoint("BOTTOMRIGHT", -4, 4)
	foot:SetText("|cff888888" .. format(L["%d members · roster by GuildChronicle + live data"], #list) .. "|r")
end

-------------------------------------------------------------------------------
-- TAB: My Characters
-------------------------------------------------------------------------------

tabs.chars = function(self, page)
	local p = Priv()
	local h = Shared()
	local y = -4
	local hd = Header(page, L["Your characters"])
	hd:SetPoint("TOPLEFT", 4, y)
	y = y - 20
	local chars = {}
	for name, c in pairs(p.myChars) do chars[#chars + 1] = { name = name, c = c } end
	chars[#chars + 1] = chars[#chars + 1] or { name = MN(), c = {} }
	sort(chars, function(a, b) return (a.c.level or 0) > (b.c.level or 0) end)
	local roster = Roster()
	ListRows(page, y, 24, #chars, function(r, i)
		local ch = chars[i]
		local e = roster[ch.name]
		local st, mName = AltStatus(ch.name)
		local badge = (st == "linked") and "|cff55ff55Linked|r" or st == "alt" and "|cffaaaa55Alt|r" or (ch.name == MN() and "|cff" .. ACC .. "Main|r" or "")
		local txt = ClassColor(ch.name) .. (ch.name == MN() and " |cff888888(" .. L["you"] .. ")|r" or "")
		RowFS(r, "name", 6):SetText(txt)
		RowFS(r, "lvl", 200):SetText(tostring((e and e.level) or ch.c.level or "?"))
		RowFS(r, "rank", 250):SetText((e and e.rankName) or "")
		RowFS(r, "badge", 400):SetText(badge)
		RowFS(r, "seen", 470):SetText(ch.name == MN() and "" or (Ago(ch.c.t)))
		if ch.name == MN() then
			local mk = Btn(r, 90, 18, L["Make main"])
			mk:SetPoint("RIGHT", -4, 0)
			mk:SetScript("OnClick", function()
				local h2 = Shared()
				h2.mainDecl[MN()] = h2.mainDecl[MN()] or {}
				for other in pairs(p.myChars) do
					if other ~= MN() then
						h2.mainDecl[MN()][other] = true
						Send("MC|" .. other)
					end
				end
				h2.altDecl[MN()] = nil
				Bump()
				GH:RenderTab("chars")
			end)
		end
	end)
	y = y - #chars * 24 - 12
	local note = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	note:SetPoint("TOPLEFT", 6, y)
	note:SetText("|cff777777" .. L["A character shows here once you've logged in on it with the addon. Alts declare their main themselves when you log them in."] .. "|r")

	-- attunements (from InstanceTracker char data)
	y = y - 18
	local hd2 = Header(page, L["Attunements"])
	hd2:SetPoint("TOPLEFT", 4, y)
	y = y - 18
	local D = ns.InstanceTrackerData
	local cd = SentinelUIInstanceDB and SentinelUIInstanceDB[GetRealmName() or ""] and SentinelUIInstanceDB[GetRealmName() or ""].chars
	local any = false
	for _, a in ipairs((D and D.attunements) or {}) do
		local line = a.label or a.key
		local vals = {}
		for name in pairs(p.myChars or {}) do
			local c = cd and cd[name]
			vals[#vals + 1] = (c and c[a.key]) and (ClassColor(name)) or ("|cff555555" .. name .. "|r")
		end
		if #vals > 0 then
			any = true
			local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", 10, y)
			fs:SetText(line .. ":  " .. table.concat(vals, "  "))
			y = y - 16
		end
	end
	if not any then
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 10, y)
		fs:SetText("|cff777777" .. L["No attunement data yet — open the Instance Tracker once per character."] .. "|r")
	end
end

-------------------------------------------------------------------------------
-- TAB: Professions (directory + craft requests)
-------------------------------------------------------------------------------

tabs.profs = function(self, page)
	local h = Shared()
	local st = GH.profState or { search = "", onlineOnly = false, showReq = false }
	GH.profState = st
	local tab1 = Btn(page, 80, 18, L["Recipes"])
	tab1:SetPoint("TOPLEFT", 4, -2)
	tab1:SetScript("OnClick", function() st.showReq = false GH:RenderTab("profs") end)
	local tab2 = Btn(page, 80, 18, L["Requests"])
	tab2:SetPoint("TOPLEFT", 88, -2)
	tab2:SetScript("OnClick", function() st.showReq = true GH:RenderTab("profs") end)
	;(st.showReq and tab2 or tab1).fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)

	if not st.showReq then
		local srch = Edit(page, 140, 16, L["Recipe or item"])
		srch:SetPoint("TOPLEFT", 4, -26)
		srch:SetText(st.search or "")
		srch:SetScript("OnTextChanged", function(e) st.search = e:GetText() GH:RenderTab("profs") end)
		local cb = Checkbox(page, L["Online only"], st.onlineOnly, function(v) st.onlineOnly = v GH:RenderTab("profs") end)
		cb:SetPoint("TOPLEFT", 160, -26)
		-- gather recipes from shared prof data (member.profs[prof].link/rcp list)
		local roster = Roster()
		local q = lower(st.search or "")
		local rows = {}
		for name, e in pairs(roster) do
			for prof, p in pairs(e.profs or {}) do
				if (not st.onlineOnly or OnlineOf(name)) then
					local rcp = p.recipes
					if type(rcp) == "table" and next(rcp) then
						for rname in pairs(rcp) do
							if q == "" or lower(rname):find(q, 1, true) or lower(prof):find(q, 1, true) then
								rows[#rows + 1] = { r = rname, prof = prof, who = name, skill = p.skill, online = e.online }
							end
						end
					else
						if q == "" or lower(prof):find(q, 1, true) then
							rows[#rows + 1] = { r = prof, prof = prof, who = name, skill = p.skill, online = e.online, justProf = true }
						end
					end
				end
			end
		end
		sort(rows, function(a, b) if a.r == b.r then return (a.who or "") < (b.who or "") end return a.r < b.r end)
		-- dedupe per recipe: show crafter count
		local grouped, order = {}, {}
		for _, r in ipairs(rows) do
			local g = grouped[r.r]
			if not g then g = { r = r.r, prof = r.prof, crafters = {} } grouped[r.r] = g order[#order + 1] = g end
			g.crafters[#g.crafters + 1] = r
		end
		ListRows(page, -50, 20, min(#order, 24), function(row, i)
			local g = order[i]
			if not g then return end
			local on = 0
			for _, c in ipairs(g.crafters) do if c.online then on = on + 1 end end
			RowFS(row, "r", 6):SetText(g.r)
			RowFS(row, "p", 320):SetText(g.prof)
			RowFS(row, "c", 440):SetText(format("%d/%d", on, #g.crafters))
			row:SetScript("OnClick", function()
				GH.profSel = g
				GH:RenderTab("profs")
			end)
			if GH.profSel and GH.profSel.r == g.r then row.bg:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.12) end
		end)
		-- detail panel
		local g = GH.profSel
		if g then
			local dp = CreateFrame("Frame", nil, page, S.BackdropTemplate)
			dp:SetPoint("TOPRIGHT", -4, -50)
			dp:SetPoint("BOTTOMRIGHT", -4, 8)
			dp:SetWidth(280)
			S:SetTemplate(dp, "Default")
			local t = S:FontString(dp, 12, "OUTLINE", S.media.font, nil, "LEFT")
			t:SetPoint("TOPLEFT", 8, -8)
			t:SetText("|cff" .. ACC .. g.r .. "|r")
			local info = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
			info:SetPoint("TOPLEFT", 8, -26)
			info:SetText(g.prof)
			local wh = Header(dp, L["Who can craft it"])
			wh:SetPoint("TOPLEFT", 8, -46)
			local yy = -64
			for _, c in ipairs(g.crafters) do
				local fs = S:FontString(dp, 11, nil, S.media.font, nil, "LEFT")
				fs:SetPoint("TOPLEFT", 10, yy)
				fs:SetText(ClassColor(c.who) .. (c.skill and ("  |cff888888" .. c.skill .. "|r") or ""))
				local st3 = S:FontString(dp, 11, nil, S.media.font, nil, "RIGHT")
				st3:SetPoint("TOPRIGHT", -10, yy)
				st3:SetText(c.online and "|cff55ff55" .. L["online"] .. "|r" or "|cff666666" .. L["offline"] .. "|r")
				yy = yy - 17
			end
			local req = Btn(dp, 90, 20, L["Request it"])
			req:SetPoint("TOPRIGHT", -8, -8)
			req:SetScript("OnClick", function()
				local id = tostring(time()) .. "-" .. MN()
				local c = { id = id, item = g.r, prof = g.prof, qty = 1, t = time() }
				Shared().crafts[id] = c Bump()
				Send("CR|" .. (GH._Ser and GH._Ser(c) or ""))
				Notify(format(L["Craft request posted: %s"], g.r))
			end)
		end
	else
		-- requests list
		local rows = {}
		for id, c in pairs(h.crafts) do
			if not c.done and (time() - (c.t or 0)) < 7 * 86400 then rows[#rows + 1] = c end
		end
		sort(rows, function(a, b) return (a.t or 0) > (b.t or 0) end)
		ListRows(page, -30, 22, min(#rows, 24), function(row, i)
			local c = rows[i]
			if not c then return end
			RowFS(row, "item", 6):SetText(format("%s x%d", c.item or "?", c.qty or 1))
			RowFS(row, "by", 260):SetText(ClassColor(c.char or "?"))
			RowFS(row, "prof", 400):SetText(c.prof or "")
			RowFS(row, "t", 500):SetText(Ago(c.t))
			local txt = c.claimer and (L["claimed by"] .. " " .. (c.claimer or "?")) or ""
			RowFS(row, "cl", 560):SetText(txt)
			row:SetScript("OnClick", function(_, btn)
				if c.char == MN() then
					if btn == "RightButton" then
						Send("CCD|" .. c.id .. "|")
						Shared().crafts[c.id] = nil Bump() GH:RenderTab("profs")
					else
						Send("CCD|" .. c.id .. "|d")
						Shared().crafts[c.id].done = true Bump() GH:RenderTab("profs")
					end
				elseif btn == "RightButton" then Whisper(c.char)
				elseif not c.claimer then
					Send("CCC|" .. c.id)
					Shared().crafts[c.id].claimer = MN() Bump() GH:RenderTab("profs")
				end
			end)
		end)
		local hint = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
		hint:SetPoint("BOTTOMLEFT", 4, 4)
		hint:SetText("|cff777777" .. L["Click: I'll make it / mark done (own). Right-click: whisper / cancel (own)."] .. "|r")
	end
end

-------------------------------------------------------------------------------
-- TAB: Guild Bank (remote view of last snapshot)
-------------------------------------------------------------------------------

tabs.gbank = function(self, page)
	local h = Shared()
	local st = GH.gbState or { tab = 1, search = "" }
	GH.gbState = st
	local is = S.GetModule and S:GetModule("ItemSync")
	local gdata
	if is and S.db and S.db.global and S.db.global.itemSync and S.db.global.itemSync.guilds then
		gdata = S.db.global.itemSync.guilds[GetGuildInfo("player") or ""]
	end
	-- merge: our own scan + shared snapshots
	local tabsData = {}
	if gdata and gdata.tabs then for t, items in pairs(gdata.tabs) do tabsData[t] = { items = items, by = MN(), t = gdata.updated } end end
	for t, snap in pairs(h.gbank) do
		if not tabsData[t] or (snap.t or 0) > (tabsData[t].t or 0) then tabsData[t] = snap end
	end
	local x = 4
	for t = 1, 6 do
		local b = Btn(page, 54, 18, format(L["Tab %d"], t))
		b:SetPoint("TOPLEFT", x, -2)
		b:SetScript("OnClick", function() st.tab = t GH:RenderTab("gbank") end)
		if st.tab == t then b.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
		x = x + 58
	end
	local gold = S:FontString(page, 11, nil, S.media.font, nil, "RIGHT")
	gold:SetPoint("TOPRIGHT", -4, -4)
	if h.gbankGold then gold:SetText(GetCoinTextureString and GetCoinTextureString(h.gbankGold) or (h.gbankGold .. "c") or "") end
	local srch = Edit(page, 160, 16, L["Search all tabs"])
	srch:SetPoint("TOPLEFT", 4, -26)
	srch:SetText(st.search or "")
	srch:SetScript("OnTextChanged", function(e) st.search = e:GetText() GH:RenderTab("gbank") end)

	local td = tabsData[st.tab]
	local q = lower(st.search or "")
	local rows = {}
	if q ~= "" then
		for t, d in pairs(tabsData) do
			for id, n in pairs(d.items or {}) do
				local name = S.GetItemInfo and select(1, S.GetItemInfo(id)) or nil
				if name and lower(name):find(q, 1, true) then
					rows[#rows + 1] = { id = id, n = n, tab = t, name = name }
				end
			end
		end
		sort(rows, function(a, b) return a.name < b.name end)
	elseif td and td.items then
		for id, n in pairs(td.items) do
			local name = S.GetItemInfo and select(1, S.GetItemInfo(id)) or ("item:" .. id)
			rows[#rows + 1] = { id = id, n = n, name = name }
		end
		sort(rows, function(a, b) return a.name < b.name end)
	end
	ListRows(page, -50, 20, min(#rows, 24), function(r, i)
		local it = rows[i]
		if not it then return end
		RowFS(r, "name", 6):SetText(it.name or "?")
		RowFS(r, "n", 340):SetText("x" .. tostring(it.n or 1))
		if it.tab then RowFS(r, "t", 400):SetText(format(L["Tab %d"], it.tab)) end
		r:SetScript("OnEnter", function()
			GameTooltip:SetOwner(r, "ANCHOR_CURSOR")
			GameTooltip:SetHyperlink("item:" .. it.id)
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end)
	local foot = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	foot:SetPoint("BOTTOMLEFT", 4, 4)
	if td then
		foot:SetText(format("|cff777777%s|r", format(L["Seen by %s · %s"], td.by or "?", Ago(td.t))))
	else
		foot:SetText("|cff777777" .. L["No snapshot yet — someone with the addon must open the guild bank."] .. "|r")
	end
end

-- share our own bank scans when we open the guild bank
function GH:ShareGuildBank()
	local p = Priv()
	if p and p.settings.shareBank == false then return end
	if not (GetNumGuildBankTabs and GetGuildBankItemLink) then return end
	local gold = GetGuildBankMoney and GetGuildBankMoney() or 0
	for t = 1, GetNumGuildBankTabs() do
		local items = {}
		for slot = 1, 98 do
			local link = GetGuildBankItemLink(t, slot)
			if link then
				local id = tonumber(link:match("item:(%d+)"))
				local cnt = select(2, GetGuildBankItemInfo(t, slot)) or 1
				if id then items[id] = (items[id] or 0) + cnt end
			end
		end
		local h = Shared()
		h.gbank[t] = { items = items, by = MN(), t = time() }
		h.gbankGold = gold
		Send("GB|" .. t .. "|" .. gold .. "|" .. Ser(items))
	end
	Bump()
end

-------------------------------------------------------------------------------
-- TAB: Layers
-------------------------------------------------------------------------------

tabs.layers = function(self, page)
	local h = Shared()
	local wb = S.GetModule and S:GetModule("WorldBuffs")
	local myLayer, myZone
	if wb then
		if wb.LayerNum then myLayer = wb:LayerNum() end
	end
	myZone = GetRealZoneText and GetRealZoneText() or GetZoneText and GetZoneText() or "?"
	local hd = Header(page, L["Your layer"])
	hd:SetPoint("TOPLEFT", 4, -4)
	local fs = S:FontString(page, 12, nil, S.media.font, nil, "LEFT")
	fs:SetPoint("TOPLEFT", 8, -24)
	fs:SetText(format("%s · %s %s", myZone or "?", L["Layer"], tostring(myLayer or "?")))
	if wb and wb.LayerNum and myLayer then
		GH:ReportLayer()
	end
	local hd2 = Header(page, L["Guildmates"])
	hd2:SetPoint("TOPLEFT", 4, -48)
	local rows = {}
	for name, e in pairs(h.layers) do
		if name ~= MN() and (time() - (e.t or 0)) < 3600 then rows[#rows + 1] = { n = name, e = e } end
	end
	sort(rows, function(a, b) return (a.e.l or 0) < (b.e.l or 0) end)
	ListRows(page, -70, 20, min(#rows, 22), function(r, i)
		local e = rows[i]
		if not e then return end
		RowFS(r, "name", 6):SetText(ClassColor(e.n))
		RowFS(r, "zone", 220):SetText(e.e.z or "?")
		RowFS(r, "layer", 400):SetText(format("%s %s", L["Layer"], tostring(e.e.l or "?")))
		RowFS(r, "t", 480):SetText(Ago(e.e.t))
		local b = Btn(r, 60, 16, L["Hop"])
		b:SetPoint("RIGHT", -4, 0)
		b:SetScript("OnClick", function()
			if OnlineOf(e.n) then
				SendWhisper(format(L["layer hop invite? I'm on layer %s"], tostring(myLayer or "?")), e.n)
				Notify(format(L["Hop request sent to %s"], e.n))
			end
		end)
	end)
	local foot = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	foot:SetPoint("BOTTOMLEFT", 4, 4)
	foot:SetText("|cff777777" .. L["Layers are reported by WorldBuffs tracking — members show up while their addon is online."] .. "|r")
end

function GH:ReportLayer()
	local wb = S.GetModule and S:GetModule("WorldBuffs")
	if not (wb and wb.LayerNum) then return end
	local l = wb:LayerNum()
	local z = GetRealZoneText and GetRealZoneText() or ""
	if not l then return end
	local h = Shared()
	local cur = h.layers[MN()]
	if not cur or cur.l ~= l or cur.z ~= z or (time() - (cur.t or 0)) > 300 then
		h.layers[MN()] = { z = z, l = l, t = time() }
		Send("Y|" .. z .. "|" .. l)
	end
end

