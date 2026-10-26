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
local ROLE_ORDER = { "T", "H", "D", "N" }
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
	local hit = CreateFrame("Button", nil, parent)
	hit:SetPoint("TOPLEFT", cb) hit:SetPoint("BOTTOMLEFT", cb)
	hit:SetWidth(16 + (cb.fs:GetStringWidth() or 0) + 6)
	hit:SetScript("OnClick", function() if not cb.IsEnabled or cb:IsEnabled() then cb:Click() end end)
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
		for _, ch in ipairs({ r:GetChildren() }) do ch:Hide() end
		r:SetScript("OnClick", nil)
		r:SetScript("OnEnter", nil)
		r:SetScript("OnLeave", nil)
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
local function Whisper(name)
	if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. name .. " ")
	elseif SendChatMessage then SendChatMessage("", "WHISPER", nil, name) end
end
local function Invite(name) if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end end

local function MemberMenu(name)
	if not EasyMenu then return end
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
	GH.menuFrame = GH.menuFrame or CreateFrame("Frame", "SUGHMenu", UIParent, "UIDropDownMenuTemplate")
	EasyMenu(menu, GH.menuFrame, "cursor", 0, 0, "MENU")
end

-- extra appliers installed here (leader-set role for others)
GH._appliers.SR = function(rest, sender)
	local name, role = rest:match("^(.-)|([THDN])$")
	if not (name and role and IsMember(name)) then return end
	-- allowed: roles/leader right, or the sender setting a role on one of their
	-- own linked characters (alt of sender / main is sender)
	local mine = MainOf(name) == sender or name == sender
	if not (mine or HasRight(sender, "roles") or HasRight(sender, "leader")) then return end
	Shared().roles[name] = role Bump() GH:MaybeRefresh("roster")
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
	if #chars == 0 then chars[1] = { name = MN(), c = {} } end
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
		-- role per own character: T/H/D
		local rx = -100
		for _, rr in ipairs({ "T", "H", "D" }) do
			local role = rr
			local rb = Btn(r, 26, 16, role)
			rb:SetPoint("RIGHT", rx, 0)
			if Shared().roles[ch.name] == role then rb.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
			rb:SetScript("OnClick", function()
				Shared().roles[ch.name] = role Bump()
				Send("SR|" .. ch.name .. "|" .. role)
				GH:RenderTab("chars")
			end)
			rx = rx - 28
		end
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
	local realm = GetRealmName() or ""
	local cd = SentinelUIInstanceDB and SentinelUIInstanceDB[realm] and SentinelUIInstanceDB[realm].chars
	local ATT_LABELS = {
		mcAttune = "Molten Core", onyAttune = "Onyxia", bwlAttune = "Blackwing Lair",
		naxxAttune = "Naxxramas", karaAttune = "Karazhan",
		shatteredHallsAttune = "Shattered Halls", serpentshrineAttune = "Serpentshrine",
		blackMorassAttune = "Black Morass", hyjalAttune = "Hyjal", blackTempleAttune = "Black Temple",
		hellfireCitadelAttune = "HC (heroisch)", coilfangAttune = "Coilfang (heroisch)",
		auchindounAttune = "Auchindoun (heroisch)", shadowLabAttune = "Schattens labyrinth",
		tempestKeepAttune = "Festung der Stürme (heroisch)", cavernsAttune = "HdZ (heroisch)",
		arcatrazAttune = "Arkatraz",
	}
	local attKeys = {}
	for _, a in ipairs((D and D.attunements) or {}) do attKeys[#attKeys + 1] = a.key end
	local seen2 = {}
	for _, akey in ipairs(attKeys) do seen2[akey] = true end
	for _, k in pairs((D and D.keyAttunements) or {}) do if not seen2[k] then attKeys[#attKeys + 1] = k end end
	local h2 = Shared()
	local any = false
	for _, akey in ipairs(attKeys) do
		local vals, seen = {}, {}
		for name in pairs(p.myChars or {}) do
			seen[name] = true
			local c = cd and cd[name]
			if c and c[akey] then vals[#vals + 1] = ClassColor(name) end
		end
		for name, keys in pairs((h2 and h2.attun) or {}) do
			if not seen[name] and keys[akey] then vals[#vals + 1] = "|cff44aa44" .. name .. "|r" end
		end
		if #vals > 0 then
			any = true
			local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", 10, y)
			fs:SetText((ATT_LABELS[akey] or akey) .. ":  " .. table.concat(vals, "  "))
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
	local st = GH.profState or { search = "", onlineOnly = false, view = "members" }
	GH.profState = st
	local views = { members = L["Members"], recipes = L["Recipes"], requests = L["Requests"] }
	local x = 4
	for _, key in ipairs({ "members", "recipes", "requests" }) do
		local k = key
		local tb = Btn(page, 90, 18, views[k])
		tb:SetPoint("TOPLEFT", x, -2)
		if st.view == k then tb.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
		tb:SetScript("OnClick", function() st.view = k GH:RenderTab("profs") end)
		x = x + 94
	end

	if st.view == "members" then
		-- who has which profession (member-centric directory)
		local srch = Edit(page, 140, 16, L["Name or profession"])
		srch:SetPoint("TOPLEFT", 4, -26)
		srch:SetText(st.search or "")
		srch:SetScript("OnTextChanged", function(e) st.search = e:GetText() GH:RenderTab("profs") end)
		local cb = Checkbox(page, L["Online only"], st.onlineOnly, function(v) st.onlineOnly = v GH:RenderTab("profs") end)
		cb:SetPoint("TOPLEFT", 152, -26)
		local hdr = S:FontString(page, 11, "OUTLINE", S.media.font, nil, "LEFT")
		hdr:SetPoint("TOPLEFT", 8, -48)
		hdr:SetText("|cff" .. ACC .. L["MEMBER"] .. "|r")
		local hdr2 = S:FontString(page, 11, "OUTLINE", S.media.font, nil, "LEFT")
		hdr2:SetPoint("TOPLEFT", 250, -48)
		hdr2:SetText("|cff" .. ACC .. L["PROFESSIONS"] .. "|r")
		local roster = Roster()
		local q = lower(st.search or "")
		local rows = {}
		for name, e in pairs(roster) do
			local pset = h.profs[name] or {}
			local plist = {}
			for prof, p in pairs(pset) do
				local sk = p.skill and format(" (%d/%s)", p.skill, tostring(p.max or "?")) or ""
				plist[#plist + 1] = prof .. sk
			end
			sort(plist)
			local line = table.concat(plist, "  ·  ")
			if (#plist > 0) and (q == "" or lower(name):find(q, 1, true) or lower(line):find(q, 1, true))
				and (not st.onlineOnly or e.online) then
				rows[#rows + 1] = { n = name, e = e, line = line }
			end
		end
		sort(rows, function(a, b) return a.n < b.n end)
		ListRows(page, -66, 20, min(#rows, 26), function(r, i)
			local m = rows[i]
			if not m then return end
			RowFS(r, "name", 6):SetText(ClassColor(m.n) .. (m.e.online and "" or " |cff555555(off)|r"))
			RowFS(r, "prof", 250):SetText(m.line)
			r:SetScript("OnClick", function(_, b)
				if b == "RightButton" then Invite(m.n) else Whisper(m.n) end
			end)
		end)
		local hint = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
		hint:SetPoint("BOTTOMLEFT", 4, 4)
		hint:SetText("|cff777777" .. L["Click: whisper · Right-click: invite. Professions share via the addon channel."] .. "|r")
		return
	end

	if st.view == "recipes" then
		local srch = Edit(page, 140, 16, L["Recipe or item"])
		srch:SetPoint("TOPLEFT", 4, -26)
		srch:SetText(st.search or "")
		srch:SetScript("OnTextChanged", function(e) st.search = e:GetText() GH:RenderTab("profs") end)
		local cb = Checkbox(page, L["Online only"], st.onlineOnly, function(v) st.onlineOnly = v GH:RenderTab("profs") end)
		cb:SetPoint("TOPLEFT", 152, -26)
		local roster = Roster()
		local q = lower(st.search or "")
		local grouped, order = {}, {}
		for name, e in pairs(roster) do
			if not st.onlineOnly or e.online then
				for prof, p in pairs(h.profs[name] or {}) do
					local rcp = p.recipes or p.rcp
					if type(rcp) == "table" then
						for rname in pairs(rcp) do
							if q == "" or lower(rname):find(q, 1, true) then
								local g = grouped[rname]
								if not g then g = { r = rname, prof = prof, crafters = {} } grouped[rname] = g order[#order + 1] = g end
								g.crafters[#g.crafters + 1] = { who = name, skill = p.skill, online = e.online }
							end
						end
					end
				end
			end
		end
		sort(order, function(a, b) return a.r < b.r end)
		ListRows(page, -50, 20, min(#order, 24), function(row, i)
			local g = order[i]
			if not g then return end
			local on = 0
			for _, c in ipairs(g.crafters) do if c.online then on = on + 1 end end
			RowFS(row, "r", 6):SetText(g.r)
			RowFS(row, "p", 320):SetText(g.prof)
			RowFS(row, "c", 440):SetText(format("%d/%d", on, #g.crafters))
			row:SetScript("OnClick", function() GH.profSel = g GH:RenderTab("profs") end)
			if GH.profSel and GH.profSel.r == g.r then row.bg:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.12) end
		end)
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
			local wh = Header(dp, L["Who can craft it"])
			wh:SetPoint("TOPLEFT", 8, -28)
			local yy = -46
			for _, c in ipairs(g.crafters) do
				local fs = S:FontString(dp, 11, nil, S.media.font, nil, "LEFT")
				fs:SetPoint("TOPLEFT", 10, yy)
				fs:SetText(ClassColor(c.who) .. (c.skill and ("  |cff888888" .. c.skill .. "|r") or ""))
				local stt = S:FontString(dp, 11, nil, S.media.font, nil, "RIGHT")
				stt:SetPoint("TOPRIGHT", -10, yy)
				stt:SetText(c.online and "|cff55ff55" .. L["online"] .. "|r" or "|cff666666" .. L["offline"] .. "|r")
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
		return
	end

	-- requests view
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
		RowFS(row, "cl", 560):SetText(c.claimer and (L["claimed by"] .. " " .. c.claimer) or "")
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
		local entry, num = wb.LayerContext and wb:LayerContext()
		myLayer = num
		if not myLayer and wb.CurrentLayerID then
			local id = wb:CurrentLayerID()
			if id then myLayer = wb:LayerNum(id) end
		end
	end
	myZone = GetRealZoneText and GetRealZoneText() or GetZoneText and GetZoneText() or "?"
	local hd = Header(page, L["Your layer"])
	hd:SetPoint("TOPLEFT", 4, -4)
	local fs = S:FontString(page, 12, nil, S.media.font, nil, "LEFT")
	fs:SetPoint("TOPLEFT", 8, -24)
	local layerTxt = myLayer and format("%s %s", L["Layer"], tostring(myLayer)) or "|cff888888" .. L["not detected yet"] .. "|r"
	fs:SetText(format("%s · %s", myZone or "?", layerTxt))
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
	if not wb then return end
	local entry, l = wb.LayerContext and wb:LayerContext()
	if not l and wb.CurrentLayerID then
		local id = wb:CurrentLayerID()
		if id then l = wb:LayerNum(id) end
	end
	local z = GetRealZoneText and GetRealZoneText() or ""
	if not l then return end
	local h = Shared()
	local cur = h.layers[MN()]
	if not cur or cur.l ~= l or cur.z ~= z or (time() - (cur.t or 0)) > 300 then
		h.layers[MN()] = { z = z, l = l, t = time() }
		Send("Y|" .. z .. "|" .. l)
	end
end

