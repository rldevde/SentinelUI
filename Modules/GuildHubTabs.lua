-- GuildHubTabs: remaining tabs (finders, raids, pvp, rules, admin) + Initialize
local _, ns = ...
local S = ns.S
local L = S.L
local GH = S:GetModule("GuildHub")

local _G = _G
local ipairs, pairs, wipe, tinsert, tremove, sort, tonumber, tostring, type, next = ipairs, pairs, wipe, table.insert, table.remove, table.sort, tonumber, tostring, type, next
local format, lower, upper, strtrim, gmatch, gsub = string.format, string.lower, string.upper, strtrim, string.gmatch, string.gsub
local min, max, floor, time, date = math.min, math.max, math.floor, time, date
local CreateFrame, GetTime, InCombatLockdown, IsInGuild = CreateFrame, GetTime, InCombatLockdown, IsInGuild
local UnitName, UnitClass, UnitLevel, GetRealmName, IsInGroup, IsInRaid, GetNumGroupMembers = UnitName, UnitClass, UnitLevel, GetRealmName, IsInGroup, IsInRaid, GetNumGroupMembers
local Ambiguate, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo = Ambiguate, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo
local GameTooltip = GameTooltip
local IsSecret = S.IsSecret

local Shared, Priv, Roster, Send, Bump, Notify = GH._Shared, GH._Priv, GH._Roster, GH._Send, GH._Bump, GH._Notify
local IsMember, OnlineOf, IsGM, HasRight, CanI = GH._IsMember, GH._OnlineOf, GH._IsGM, GH._HasRight, GH._CanI
local AltStatus, MainOf, AltsOf, RoleIcon, RoleName = GH._AltStatus, GH._MainOf, GH._AltsOf, GH._RoleIcon, GH._RoleName
local Ser, Unser = GH._Ser, GH._Unser
local myName

local ACC = S.accentHex or "ffcc00"
local tabs = GH.tabs

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

local function SendWhisper(text, who)
	if SendChatMessage then SendChatMessage(text, "WHISPER", nil, who) end
end
local function Whisper(name)
	if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. name .. " ") end
end
local function Invite(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end
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
		for _, ch in ipairs({ r:GetChildren() }) do if ch ~= r.bg then ch:Hide() end end
		fill(r, i)
		r:Show()
	end
	return rows
end

local function RowFS(r, key, x, justify)
	local fs = r.fss[key]
	if not fs then
		fs = S:FontString(r, 11, nil, S.media.font, nil, justify or "LEFT")
		r.fss[key] = fs
	end
	fs:ClearAllPoints()
	if justify == "RIGHT" then fs:SetPoint("RIGHT", r, "RIGHT", x, 0)
	else fs:SetPoint("LEFT", x, 0) end
	fs:SetJustifyH(justify or "LEFT")
	fs:Show()
	return fs
end

-------------------------------------------------------------------------------
-- static lists
-------------------------------------------------------------------------------

local DUNGEONS = {
	{ "Ragefire Chasm", "13-18" }, { "Deadmines", "17-24" }, { "Wailing Caverns", "18-23" },
	{ "Shadowfang Keep", "20-27" }, { "Blackfathom Deeps", "22-29" }, { "The Stockade", "23-29" },
	{ "Gnomeregan", "25-32" }, { "Razorfen Kraul", "27-32" }, { "SM: Graveyard", "29-34" },
	{ "SM: Library", "31-37" }, { "SM: Armory", "34-39" }, { "SM: Cathedral", "37-42" },
	{ "Razorfen Downs", "35-40" }, { "Uldaman", "38-44" }, { "Zul'Farrak", "42-48" },
	{ "Maraudon", "43-51" }, { "Sunken Temple", "47-54" }, { "Blackrock Depths", "50-58" },
	{ "Lower Blackrock Spire", "53-58" }, { "DM: Warpwood (East)", "54-59" },
	{ "DM: Capital Gardens (West)", "56-60" }, { "DM: Gordok Commons (North)", "57-60" },
	{ "Scholomance", "57-60" }, { "Stratholme: Live", "58-60" }, { "Stratholme: Undead", "58-60" },
	{ "Upper Blackrock Spire", "58-60" },
	{ "Hellfire Ramparts", "59-63" }, { "Blood Furnace", "60-64" }, { "Slave Pens", "61-65" },
	{ "Underbog", "62-66" }, { "Mana-Tombs", "63-67" }, { "Auchenai Crypts", "64-68" },
	{ "Old Hillsbrad", "66-68" }, { "Sethekk Halls", "66-69" }, { "Shadow Labyrinth", "67-70" },
	{ "Steamvault", "68-70" }, { "Shattered Halls", "68-70" }, { "Black Morass", "69-70" },
	{ "Mechanar", "69-70" }, { "Botanica", "69-70" }, { "Arcatraz", "69-70" }, { "Magisters' Terrace", "70" },
}
local BGS = {
	{ "Warsong Gulch", 10 }, { "Arathi Basin", 15 }, { "Alterac Valley", 40 }, { "Eye of the Storm", 15 },
}

local function MyLevel() return UnitLevel and UnitLevel("player") or 60 end

local function LevelInRange(lvl, range)
	local lo, hi = range:match("^(%d+)%-(%d+)")
	if not lo then return (tonumber(range) or 0) <= lvl + 5 and lvl <= (tonumber(range) or 0) + 5 end
	lvl = tonumber(lvl) or 0
	return lvl >= tonumber(lo) - 2 and lvl <= tonumber(hi) + 2
end

-------------------------------------------------------------------------------
-- TAB: Group Finder
-------------------------------------------------------------------------------

GH.gfMine = GH.gfMine or { roles = { T = false, H = false, D = true }, dgns = {}, all = false }
tabs.finder = function(self, page)
	local st = GH.gfMine
	local hd = Header(page, L["Group Finder: your role"])
	hd:SetPoint("TOPLEFT", 4, -2)
	local x = 4
	for _, r in ipairs({ "T", "H", "D" }) do
		local role = r
		local cb = Checkbox(page, RoleName(role), st.roles[role], function(v)
			st.roles[role] = v GH:BroadcastFinder() GH:RenderTab("finder")
		end)
		cb:SetPoint("TOPLEFT", x, -24)
		x = x + 80
	end
	local cbA = Checkbox(page, L["Show all levels"], st.all, function(v) st.all = v GH:RenderTab("finder") end)
	cbA:SetPoint("TOPLEFT", x + 10, -24)
	local leave = Btn(page, 70, 16, L["Leave all"])
	leave:SetPoint("TOPRIGHT", -4, -22)
	leave:SetScript("OnClick", function()
		wipe(st.dgns) GH:BroadcastFinder() GH:RenderTab("finder")
	end)

	local hdr = S:FontString(page, 11, "OUTLINE", S.media.font, nil, "LEFT")
	hdr:SetPoint("TOPLEFT", 30, -50)
	hdr:SetText("|cff" .. ACC .. L["DUNGEON"] .. "|r")
	local hdr2 = S:FontString(page, 11, "OUTLINE", S.media.font, nil, "LEFT")
	hdr2:SetPoint("TOPLEFT", 370, -50)
	hdr2:SetText("|cff" .. ACC .. L["LEVELS"] .. "   " .. L["OTHERS"] .. "|r")

	local lvl = MyLevel()
	local function OthersLooking(dgn)
		local out = {}
		for name, g in pairs(GH.gf or {}) do
			if g.dgns and g.dgns[dgn] and (GetTime() - (g.t or 0)) < 600 then
				out[#out + 1] = { n = name, g = g }
			end
		end
		return out
	end

	ListRows(page, -68, 20, min(#DUNGEONS, 26), function(r, i)
		local d = DUNGEONS[i]
		if not d then return end
		local name, range = d[1], d[2]
		local oth = OthersLooking(name)
		local mine = st.dgns[name] and true or false
		local dim = not st.all and not LevelInRange(lvl, range)
		RowFS(r, "tick", 4):SetText(mine and "|cff" .. ACC .. "x|r" or "")
		local nfs = RowFS(r, "name", 24)
		nfs:SetText((dim and "|cff666666" or "") .. name .. "|r")
		RowFS(r, "lv", 370):SetText(range)
		RowFS(r, "o", 440):SetText(#oth > 0 and ("|cff" .. ACC .. #oth .. "|r") or "–")
		r:SetScript("OnClick", function()
			if mine then st.dgns[name] = nil else st.dgns[name] = true end
			GH:BroadcastFinder() GH:RenderTab("finder")
		end)
	end)

	-- detail panel for a picked dungeon (first ticked or with others)
	local sel
	for _, d in ipairs(DUNGEONS) do if st.dgns[d[1]] then sel = sel or d[1] end end
	for _, d in ipairs(DUNGEONS) do if #OthersLooking(d[1]) > 0 then sel = sel or d[1] end end
	local dp = CreateFrame("Frame", nil, page, S.BackdropTemplate)
	dp:SetPoint("TOPRIGHT", -4, -50)
	dp:SetWidth(280) dp:SetHeight(300)
	S:SetTemplate(dp, "Default")
	if sel then
		local oth = OthersLooking(sel)
		local tt = Header(dp, sel)
		tt:SetPoint("TOPLEFT", 8, -8)
		local cnt = { T = 0, H = 0, D = 0 }
		for _, o in ipairs(oth) do
			for _, r in ipairs({ "T", "H", "D" }) do if o.g.roles[r] then cnt[r] = cnt[r] + 1 end end
		end
		local sub = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
		sub:SetPoint("TOPLEFT", 10, -28)
		sub:SetText(format("%d %s, %d %s, %d DPS", cnt.T, L["tank"], cnt.H, L["healer"], L["and"]))
		local yy = -48
		for _, o in ipairs(oth) do
			local e = Roster()[o.n]
			local fs = S:FontString(dp, 11, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", 10, yy)
			local roles = {}
			for _, r in ipairs({ "T", "H", "D" }) do if o.g.roles[r] then roles[#roles + 1] = RoleIcon(r, 12) end end
			fs:SetText(table.concat(roles, " ") .. " " .. ClassColor(o.n))
			local lv = S:FontString(dp, 11, nil, S.media.font, nil, "RIGHT")
			lv:SetPoint("TOPRIGHT", -10, yy)
			lv:SetText(tostring(o.g.lvl or "?"))
			local hb = CreateFrame("Button", nil, dp)
			hb:SetPoint("TOPLEFT", 4, yy - 2) hb:SetPoint("TOPRIGHT", -4, yy - 2) hb:SetHeight(16)
			hb:SetScript("OnClick", function(_, b) if b == "RightButton" then Invite(o.n) else Whisper(o.n) end end)
			yy = yy - 18
		end
		if #oth == 0 then
			local em = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
			em:SetPoint("TOPLEFT", 10, -48)
			em:SetText("|cff777777" .. L["Nobody else is looking yet."] .. "|r")
		end
	end
	local hint = S:FontString(page, 10, nil, S.media.font, nil, "RIGHT")
	hint:SetPoint("BOTTOMRIGHT", -4, 4)
	hint:SetText("|cff777777" .. L["Click a name to whisper, right-click to invite."] .. "|r")
end

function GH:BroadcastFinder()
	local st = self.gfMine
	local rf = (st.roles.T and "T" or "") .. (st.roles.H and "H" or "") .. (st.roles.D and "D" or "")
	local list = {}
	for d in pairs(st.dgns) do list[#list + 1] = d end
	Send("F1|" .. rf .. "|" .. MyLevel() .. "|" .. table.concat(list, ","))
end

-------------------------------------------------------------------------------
-- TAB: BG Finder
-------------------------------------------------------------------------------

GH.bgMine = GH.bgMine or { bgs = {}, heal = false }
tabs.bgf = function(self, page)
	local st = GH.bgMine
	local hd = Header(page, L["Battleground Finder"])
	hd:SetPoint("TOPLEFT", 4, -2)
	local cb = Checkbox(page, L["I'm healing"], st.heal, function(v) st.heal = v GH:BroadcastBG() end)
	cb:SetPoint("TOPLEFT", 4, -24)
	local y = -50
	local function CountFor(bg)
		local n, heals, names = 0, 0, {}
		for name, g in pairs(GH.bgf or {}) do
			if g.bgs and g.bgs[bg] and (GetTime() - (g.t or 0)) < 600 then
				n = n + 1 if g.heal then heals = heals + 1 end
				names[#names + 1] = name
			end
		end
		return n, heals, names
	end
	for _, bg in ipairs(BGS) do
		local name, team = bg[1], bg[2]
		local n, heals, names = CountFor(name)
		local row = CreateFrame("Button", nil, page)
		row:SetPoint("TOPLEFT", 4, y) row:SetSize(560, 22)
		row.bg = row:CreateTexture(nil, "BACKGROUND") row.bg:SetAllPoints()
		row.bg:SetColorTexture(1, 1, 1, 0.03)
		local tick = S:FontString(row, 12, nil, S.media.font, nil, "LEFT")
		tick:SetPoint("LEFT", 6, 0)
		tick:SetText(st.bgs[name] and ("|cff" .. ACC .. "x|r") or "")
		local nf = S:FontString(row, 12, nil, S.media.font, nil, "LEFT")
		nf:SetPoint("LEFT", 30, 0)
		nf:SetText(name)
		local cf = S:FontString(row, 11, nil, S.media.font, nil, "RIGHT")
		cf:SetPoint("RIGHT", -120, 0)
		cf:SetText(format("%d / %d%s", n + (st.bgs[name] and 1 or 0), team, heals > 0 and format(" (%d %s)", heals, L["healers"]) or ""))
		if n + (st.bgs[name] and 1 or 0) >= team and GH._bgAnnounced ~= name then
			GH._bgAnnounced = name
			Notify(format(L["%s has %d — form up!"], name, team))
		elseif n + (st.bgs[name] and 1 or 0) < team then
			GH._bgAnnounced = nil
		end
		local fb = Btn(row, 110, 18, L["Form premade"])
		fb:SetPoint("RIGHT", -4, 0)
		fb:SetScript("OnClick", function()
			-- healers first, then everyone; convert to raid >5
			table.sort(names, function(a, b)
				local ga, gb = GH.bgf[a], GH.bgf[b]
				return tostring((ga and ga.heal) or false) > tostring((gb and gb.heal) or false)
			end)
			for _, nm in ipairs(names) do if OnlineOf(nm) and nm ~= myName then Invite(nm) end end
			if not IsInGroup() then Notify(L["Premade invites sent (invite yourself into a group first)."]) end
		end)
		row:SetScript("OnClick", function()
			if st.bgs[name] then st.bgs[name] = nil else st.bgs[name] = true end
			GH:BroadcastBG() GH:RenderTab("bgf")
		end)
		y = y - 24
	end
	local hint = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	hint:SetPoint("BOTTOMLEFT", 4, 4)
	hint:SetText("|cff777777" .. L["Ticks are live for ~10 min while the addon is online — nothing is stored."] .. "|r")
end

function GH:BroadcastBG()
	local st = self.bgMine
	local list = {}
	for b in pairs(st.bgs) do list[#list + 1] = b end
	Send("F2|" .. (st.heal and "1" or "0") .. "|" .. table.concat(list, ","))
end

-------------------------------------------------------------------------------
-- TAB: Raid Signups
-------------------------------------------------------------------------------

local SIGNUP_ST = {
	coming = { L["Coming"], "|cff55ff55" }, tentative = { L["Tentative"], "|cffffff55" },
	late = { L["Late"], "|cffff8855" }, cant = { L["Can't"], "|cffff5555" },
}
local LINEUP_ST = { confirmed = { L["Confirmed"], "|cff55ff55" }, bench = { L["Bench"], "|cffaaaaaa" } }

tabs.signups = function(self, page)
	local h = Shared()
	local st = GH.suState or { sel = nil, past = false }
	GH.suState = st
	local now = time()
	local raids = {}
	for id, r in pairs(h.raids) do
		local past = r.epoch and r.epoch + (r.dur or 3) * 3600 < now
		if r.status ~= "cancelled" and (past == (st.past and true or false)) then raids[#raids + 1] = r end
	end
	sort(raids, function(a, b) return (a.epoch or 0) < (b.epoch or 0) end)
	local t1 = Btn(page, 90, 18, L["Upcoming"])
	t1:SetPoint("TOPLEFT", 4, -2)
	t1:SetScript("OnClick", function() st.past = false GH:RenderTab("signups") end)
	local t2 = Btn(page, 90, 18, L["Past raids"])
	t2:SetPoint("TOPLEFT", 98, -2)
	t2:SetScript("OnClick", function() st.past = true GH:RenderTab("signups") end)
	;(st.past and t2 or t1).fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
	if CanI("leader") then
		local nb = Btn(page, 100, 18, L["New raid…"])
		nb:SetPoint("TOPRIGHT", -4, -2)
		nb:SetScript("OnClick", function() GH:RaidEditDialog(nil) end)
	end
	-- raid list left
	local lx = 0
	ListRows(page, -26, 22, min(#raids, 20), function(r, i)
		local raid = raids[i]
		if not raid then return end
		local when = raid.epoch and date("%d.%m. %H:%M", raid.epoch) or "?"
		RowFS(r, "d", 6):SetText("|cff" .. ACC .. when .. "|r")
		RowFS(r, "t", 110):SetText(raid.title or "?")
		RowFS(r, "s", 300):SetText(tostring(raid.size or 40))
		local mine = h.signups[raid.id] and h.signups[raid.id][MainOf(myName)]
		RowFS(r, "me", 340):SetText(mine and (SIGNUP_ST[mine.status] and (SIGNUP_ST[mine.status][2] .. SIGNUP_ST[mine.status][1] .. "|r") or mine.status) or "|cff555555—|r")
		r:SetScript("OnClick", function() st.sel = raid.id GH:RenderTab("signups") end)
		if st.sel == raid.id then r.bg:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.12) end
	end)
	if #raids == 0 then
		local em = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		em:SetPoint("TOPLEFT", 8, -40)
		em:SetText("|cff777777" .. (st.past and L["No past raids."] or L["No raids scheduled — a raid leader can create one."]) .. "|r")
	end
	-- detail right
	local raid = st.sel and h.raids[st.sel]
	local dp = CreateFrame("Frame", nil, page, S.BackdropTemplate)
	dp:SetPoint("TOPLEFT", 0, -26)
	dp:SetPoint("BOTTOMRIGHT", 0, 4)
	dp:Hide()
	if raid then
		dp:Show()
		dp:ClearAllPoints()
		dp:SetPoint("TOPLEFT", 360, -26)
		dp:SetPoint("BOTTOMRIGHT", 0, 4)
		local t = Header(dp, raid.title or "?")
		t:SetPoint("TOPLEFT", 10, -8)
		local sub = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
		sub:SetPoint("TOPLEFT", 10, -28)
		sub:SetText(format("%s · %s %d · %s", raid.epoch and date("%A %d.%m. %H:%M", raid.epoch) or "?",
			L["Size"], raid.size or 40, raid.note or ""))
		-- signup buttons
		local bx = 10
		for key, s in pairs(SIGNUP_ST) do
			local k = key
			local b = Btn(dp, 78, 18, s[1])
			b:SetPoint("TOPLEFT", bx, -48)
			b:SetScript("OnClick", function()
				GH:SignupDialog(raid, k)
			end)
			bx = bx + 82
		end
		-- counts + lineup
		local sg = h.signups[raid.id] or {}
		local counts = {}
		for p, su in pairs(sg) do counts[su.status] = (counts[su.status] or 0) + 1 end
		local cy = -74
		for key, s in pairs(SIGNUP_ST) do
			if counts[key] then
				local fs = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
				fs:SetPoint("TOPLEFT", 10, cy)
				fs:SetText(s[2] .. s[1] .. ": " .. counts[key] .. "|r")
				cy = cy - 14
			end
		end
		local lh = Header(dp, L["Lineup"])
		lh:SetPoint("TOPLEFT", 10, cy - 6)
		cy = cy - 24
		raid.lineup = raid.lineup or {}
		local done = {}
		for _, slot in ipairs({ "confirmed", "bench" }) do
			for p, su in pairs(sg) do
				if raid.lineup[p] == slot and not done[p] then
					done[p] = true
					local fs = S:FontString(dp, 11, nil, S.media.font, nil, "LEFT")
					fs:SetPoint("TOPLEFT", 12, cy)
					fs:SetText((LINEUP_ST[slot][2] .. "[" .. LINEUP_ST[slot][1] .. "]|r  ") .. RoleIcon(su.role, 12) .. " " .. ClassColor(su.char or p) .. (su.role and ("  |cff888888" .. (RoleName(su.role) or "") .. "|r") or ""))
					cy = cy - 16
				end
			end
		end
		local na = Header(dp, L["No answer"])
		na:SetPoint("TOPLEFT", 10, cy - 4)
		cy = cy - 20
		local nShown = 0
		for p in pairs(sg) do
			if not raid.lineup[p] and nShown < 14 then
				nShown = nShown + 1
				local su = sg[p]
				local fs = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
				fs:SetPoint("TOPLEFT", 12, cy)
				fs:SetText("|cff888888" .. (su.char or p) .. " — " .. (SIGNUP_ST[su.status] and SIGNUP_ST[su.status][1] or su.status or "?") .. "|r")
				cy = cy - 14
			end
		end
		if CanI("leader") then
			local del = Btn(dp, 110, 18, L["Delete raid"])
			del:SetPoint("BOTTOMRIGHT", -8, 8)
			del:SetScript("OnClick", function()
				Send("ED|" .. raid.id)
				Shared().raids[raid.id] = nil Shared().signups[raid.id] = nil Bump()
				GH:RenderTab("signups")
			end)
			local edit = Btn(dp, 90, 18, L["Edit…"])
			edit:SetPoint("RIGHT", del, "LEFT", -6, 0)
			edit:SetScript("OnClick", function() GH:RaidEditDialog(raid) end)
			local inv = Btn(dp, 110, 18, L["Invite online"])
			inv:SetPoint("RIGHT", edit, "LEFT", -6, 0)
			inv:SetScript("OnClick", function()
				local sg2 = h.signups[raid.id] or {}
				for p, su in pairs(sg2) do
					local char = su.char or p
					if raid.lineup[p] == "confirmed" and OnlineOf(char) and char ~= myName then Invite(char) end
				end
			end)
		end
	end
end

function GH:SignupDialog(raid, status)
	local h = Shared()
	local p = Priv()
	StaticPopupDialogs = StaticPopupDialogs or {}
	StaticPopupDialogs["SUGH_SIGNUP"] = {
		text = format(L["Sign up for %s — character (optional, default %s), note:"], raid.title or "?", myName),
		button1 = L["Sign up"], button2 = L["Cancel"], hasEditBox = true, maxLetters = 60,
		OnAccept = function(self2)
			local txt = self2.editBox and self2.editBox:GetText() or ""
			local char, note = txt:match("^(%S*)%s*(.-)%s*$")
			local pv = Priv()
			char = (char ~= "" and pv and pv.myChars[char]) and char or myName
			h.signups[raid.id] = h.signups[raid.id] or {}
			h.signups[raid.id][MainOf(myName)] = { status = status, role = h.roles[myName] or "D",
				char = char, note = note ~= "" and note or nil, t = time() }
			Bump()
			Send("U|" .. raid.id .. "|" .. status .. "|" .. (h.roles[myName] or "D") .. "|" .. char .. "|" .. (note or ""))
			GH:RenderTab("signups")
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopup_Show("SUGH_SIGNUP")
end

function GH:RaidEditDialog(raid)
	StaticPopupDialogs = StaticPopupDialogs or {}
	local def = raid or {}
	StaticPopupDialogs["SUGH_RAID"] = {
		text = L["Raid: title, YYYY-MM-DD HH:MM, size (comma separated)"],
		button1 = raid and L["Save"] or L["Create"], button2 = L["Cancel"], hasEditBox = true, maxLetters = 120,
		OnShow = function(self2)
			local s = (def.title or "Raid") .. ", " .. (def.epoch and date("%Y-%m-%d %H:%M", def.epoch) or date("%Y-%m-%d 20:00", time() + 86400)) .. ", " .. (def.size or 40)
			self2.editBox:SetText(s)
		end,
		OnAccept = function(self2)
			local txt = self2.editBox:GetText() or ""
			local title, dt, size = txt:match("^%s*(.-)%s*,%s*(.-)%s*,?%s*(.-)%s*$")
			local yy, mo, dd, hh, mm = (dt or ""):match("(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+)")
			if not (title and yy) then GH:Print(L["Bad format — need: title, YYYY-MM-DD HH:MM, size"]) return end
			local r = def.id and Shared().raids[def.id] or {}
			r.id = r.id or ("r" .. time() .. "-" .. myName)
			r.title, r.size = title, tonumber(size) or 40
			r.epoch = time({ year = tonumber(yy), month = tonumber(mo), day = tonumber(dd), hour = tonumber(hh), min = tonumber(mm) })
			r.creator, r.status, r.dur = myName, "open", r.dur or 3
			Shared().raids[r.id] = r Bump()
			Send("E|" .. Ser(r))
			GH:RenderTab("signups")
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopup_Show("SUGH_RAID")
end

-------------------------------------------------------------------------------
-- TAB: Attendance
-------------------------------------------------------------------------------

local ATT_MARKS = {
	present = { L["Present"], "|cff55ff55" }, late = { L["Late"], "|cffffff55" },
	left = { L["Left early"], "|cffff8855" }, absent = { L["Absent"], "|cffff5555" },
	noanswer = { L["No answer"], "|cff888888" }, excused = { L["Excused"], "|cff66aaff" },
}

tabs.att = function(self, page)
	local h = Shared()
	local st = GH.attState or { raid = nil, days = 30 }
	GH.attState = st
	local now = time()
	local raids = {}
	for id, r in pairs(h.raids) do raids[#raids + 1] = r end
	sort(raids, function(a, b) return (a.epoch or 0) > (b.epoch or 0) end)
	-- raid picker
	local rl = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
	rl:SetPoint("TOPLEFT", 4, -4)
	rl:SetText(L["Raid:"])
	local x = 46
	for i = 1, min(6, #raids) do
		local r = raids[i]
		local b = Btn(page, 84, 16, (r.title or "?"):sub(1, 12))
		b:SetPoint("TOPLEFT", x, -4)
		b:SetScript("OnClick", function() st.raid = r.id GH:RenderTab("att") end)
		if st.raid == r.id then b.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
		x = x + 88
	end
	local raid = st.raid and h.raids[st.raid]
	local rows = {}
	if raid then
		local sg = h.signups[raid.id] or {}
		local marks = h.att[raid.id] or {}
		for p, su in pairs(sg) do
			rows[#rows + 1] = { p = p, char = su.char or p, su = su, mark = marks[p] }
		end
		sort(rows, function(a, b) return a.char < b.char end)
	else
		-- aggregate view: attendance % per player over st.days
		local agg = {}
		for rid, marks in pairs(h.att) do
			local r = h.raids[rid]
			if r and (now - (r.epoch or 0)) < st.days * 86400 then
				for p, m in pairs(marks) do
					agg[p] = agg[p] or { n = 0, p = 0 }
					agg[p].n = agg[p].n + 1
					if m == "present" or m == "late" then agg[p].p = agg[p].p + 1 end
				end
			end
		end
		for p, a in pairs(agg) do rows[#rows + 1] = { p = p, char = p, agg = a } end
		sort(rows, function(a, b) return (a.agg.p / a.agg.n) > (b.agg.p / b.agg.n) end)
	end
	if raid and CanI("leader") then
		local rec = Btn(page, 130, 18, L["Record now"])
		rec:SetPoint("TOPRIGHT", -4, -4)
		rec:SetScript("OnClick", function() GH:RecordAttendance(raid) end)
	end
	ListRows(page, -30, 20, min(#rows, 24), function(r, i)
		local row = rows[i]
		if not row then return end
		RowFS(r, "name", 6):SetText(ClassColor(row.char))
		if row.agg then
			RowFS(r, "a", 320):SetText(format("%d%% (%d %s)", floor(row.agg.p / row.agg.n * 100 + 0.5), row.agg.n, L["raids"]))
		else
			local m = row.mark
			RowFS(r, "a", 320):SetText(m and ATT_MARKS[m] and (ATT_MARKS[m][2] .. ATT_MARKS[m][1] .. "|r") or "|cff555555—|r")
			if CanI("leader") then
				r:SetScript("OnClick", function(_, btn)
					if btn ~= "RightButton" then return end
					local order = { "present", "late", "left", "absent", "noanswer", "excused" }
					local cur = row.mark and (({present=1,late=2,left=3,absent=4,noanswer=5,excused=6})[row.mark] or 0)
					local nm = order[(cur % #order) + 1]
					local h2 = Shared()
					h2.att[raid.id] = h2.att[raid.id] or {}
					h2.att[raid.id][row.p] = nm
					row.mark = nm Bump()
					Send("AT|" .. raid.id .. "|" .. Ser({ [row.p] = nm }))
					GH:RenderTab("att")
				end)
			end
		end
	end)
	local hint = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	hint:SetPoint("BOTTOMLEFT", 4, 4)
	hint:SetText("|cff777777" .. (raid and L["Raid leaders: right-click a row to cycle the mark."] or L["Pick a raid for its marks; totals shown otherwise."]) .. "|r")
end

function GH:RecordAttendance(raid)
	local h = Shared()
	h.att[raid.id] = h.att[raid.id] or {}
	local inRaid = {}
	for i = 1, GetNumGroupMembers() do
		local u = IsInRaid() and ("raid" .. i) or ("party" .. i)
		local n = UnitName(u)
		if n then inRaid[Ambiguate(n, "short")] = true end
	end
	inRaid[myName] = true
	local sg = h.signups[raid.id] or {}
	local marks = {}
	for p, su in pairs(sg) do
		local char = su.char or p
		local present = inRaid[char] or inRaid[p]
		local mark
		if raid.lineup and raid.lineup[p] == "bench" then mark = "excused"
		elseif present then mark = "present"
		elseif su.status == "cant" then mark = "absent"
		else mark = "noanswer" end
		if h.att[raid.id][p] == "present" and not present then mark = "left" end
		h.att[raid.id][p] = mark
		marks[p] = mark
	end
	-- people physically in raid who never signed
	for n in pairs(inRaid) do
		local p = MainOf(n)
		if sg[p] == nil then
			h.att[raid.id][p] = h.att[raid.id][p] or "present"
			marks[p] = h.att[raid.id][p]
		end
	end
	Bump()
	Send("AT|" .. raid.id .. "|" .. Ser(marks))
	Notify(L["Attendance recorded."])
	GH:RenderTab("att")
end

-------------------------------------------------------------------------------
-- TAB: Loot History
-------------------------------------------------------------------------------

tabs.loot = function(self, page)
	local h = Shared()
	local st = GH.lootState or { search = "", view = "log" }
	GH.lootState = st
	local srch = Edit(page, 160, 16, L["Search items"])
	srch:SetPoint("TOPLEFT", 4, -2)
	srch:SetText(st.search or "")
	srch:SetScript("OnTextChanged", function(e) st.search = e:GetText() GH:RenderTab("loot") end)
	local q = lower(st.search or "")
	local rows = {}
	for i = #h.loot, 1, -1 do
		local e = h.loot[i]
		if e and e.item and (time() - (e.t or 0)) < 180 * 86400 then
			local nm = e.iname or ("item:" .. tostring(e.item))
			if q == "" or lower(nm):find(q, 1, true) or lower(e.char or ""):find(q, 1, true) then
				rows[#rows + 1] = e
			end
		end
		if #rows >= 40 then break end
	end
	ListRows(page, -26, 20, min(#rows, 24), function(r, i)
		local e = rows[i]
		if not e then return end
		RowFS(r, "item", 6):SetText(e.iname or ("item:" .. tostring(e.item)))
		RowFS(r, "who", 300):SetText(ClassColor(e.char or "?"))
		RowFS(r, "boss", 440):SetText(e.boss or "")
		RowFS(r, "how", 560):SetText((e.disp and ("|cffffaa55" .. e.disp .. "|r")) or e.how or "")
		if CanI("leader") then
			r:SetScript("OnClick", function(_, btn)
				if btn ~= "RightButton" then return end
				local order = { "Disenchanted", "Banked", "Rotted" }
				local cur = 0
				for j, d in ipairs(order) do if e.disp == d then cur = j end end
				e.disp = order[cur % 3 + 1]
				local audit = { t = time(), by = myName, act = "disp", item = e.iname, to = e.disp }
				Shared().lootAudit = Shared().lootAudit or {}
				tinsert(Shared().lootAudit, audit)
				if #Shared().lootAudit > 300 then tremove(Shared().lootAudit, 1) end
				Bump()
				Send("LA|" .. Ser({ i = e.item, who = e.char, t2 = e.t, disp = e.disp, audit = audit }))
				GH:RenderTab("loot")
			end)
		end
		RowFS(r, "t", 660):SetText(Ago(e.t))
		r:SetScript("OnEnter", function()
			GameTooltip:SetOwner(r, "ANCHOR_CURSOR")
			GameTooltip:SetHyperlink("item:" .. tostring(e.item))
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end)
	if #rows == 0 then
		local em = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		em:SetPoint("TOPLEFT", 8, -30)
		em:SetText("|cff777777" .. L["No drops recorded — the master looter's addon records them during raids."] .. "|r")
	end
end

-- record drops while we're the master looter in a raid (leader right required)
local LOOT_THRESHOLD = 3 -- rare
function GH:OnLootMsg(msg)
	if not IsInRaid() or not CanI("leader") then return end
	if GetLootMethod and GetLootMethod() ~= "master" then return end
	local who, link = msg:match("^(%S+) .-(|c%x+|Hitem:.-|h%[.-%]|h|r?)")
	if not who or not link then return end
	local id = tonumber(link:match("item:(%d+)"))
	if not id then return end
	local name, _, qual = GetItemInfo and GetItemInfo(id) or nil
	if not name or (qual or 0) < LOOT_THRESHOLD then return end
	local short = Ambiguate(who, "short")
	if not IsMember(short) then return end
	local h = Shared()
	h.loot[#h.loot + 1] = { t = time(), item = id, iname = name, char = short, how = "loot", by = myName }
	if #h.loot > 600 then tremove(h.loot, 1) end
	Bump()
	Send("LI|" .. Ser(h.loot[#h.loot]))
end

-------------------------------------------------------------------------------
-- TAB: Raid Groups (teams) + Raid Builder
-------------------------------------------------------------------------------

tabs.teams = function(self, page)
	local h = Shared()
	local any = false
	local x, y = 4, -4
	for i = 1, 9 do
		local t = h.teams[i]
		if t and t.name and not t.hidden then
			any = true
			local card = CreateFrame("Frame", nil, page, S.BackdropTemplate)
			card:SetPoint("TOPLEFT", x, y)
			card:SetSize(230, 120)
			S:SetTemplate(card, "Default")
			local tt = Header(card, t.name)
			tt:SetPoint("TOPLEFT", 8, -6)
			local n = 0 for _ in pairs(t.members or {}) do n = n + 1 end
			local cnt = S:FontString(card, 10, nil, S.media.font, nil, "RIGHT")
			cnt:SetPoint("TOPRIGHT", -8, -8)
			cnt:SetText(format("%d/%d", n, t.size or 40))
			local yy = -26
			for role, label in pairs({ T = "Tanks", H = "Healers", D = "DPS" }) do
				local line = ""
				for nm, mr in pairs(t.members or {}) do
					if mr == role then line = line .. ClassColor(nm) .. " " end
				end
				if line ~= "" then
					local fs = S:FontString(card, 10, nil, S.media.font, nil, "LEFT")
					fs:SetPoint("TOPLEFT", 8, yy)
					fs:SetText(RoleIcon(role, 12) .. " " .. line)
					yy = yy - 30
				end
			end
			x = x + 236
			if x > 480 then x = 4 y = y - 126 end
		end
	end
	if not any then
		local em = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		em:SetPoint("TOPLEFT", 8, -8)
		em:SetText("|cff777777" .. L["No raid teams yet — a raid builder can create them in Raid Builder."] .. "|r")
	end
end

tabs.builder = function(self, page)
	local h = Shared()
	if not (CanI("teams") or CanI("leader")) then
		local em = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		em:SetPoint("TOPLEFT", 8, -8)
		em:SetText("|cff777777" .. L["Raid Builder is for members with the 'build teams' right."] .. "|r")
		return
	end
	local st = GH.bldState or { sel = 1 }
	GH.bldState = st
	-- team cards top
	local x = 4
	for i = 1, 9 do
		local t = h.teams[i]
		local label = t and t.name or ("+" .. i)
		local b = Btn(page, 76, 18, (label or ""):sub(1, 10))
		b:SetPoint("TOPLEFT", x, -2)
		b:SetScript("OnClick", function(_, btn)
			if GH.pickup then
				local t2 = h.teams[i] or { name = "Team " .. i, size = 40, members = {} }
				h.teams[i] = t2
				t2.members = t2.members or {}
				if not t2.members[GH.pickup] then
					t2.members[GH.pickup] = h.roles[GH.pickup] or "D"
					Bump() Send("T|" .. Ser(h.teams))
				end
				GH.pickup = nil
				if GH.chip then GH.chip:Hide() end
			end
			if btn ~= "RightButton" then st.sel = i end
			GH:RenderTab("builder")
		end)
		b:SetScript("OnDoubleClick", function()
			local t2 = h.teams[i] or { name = "Team " .. i, size = 40, members = {} }
			StaticPopupDialogs["SUGH_TEAMNAME"] = {
				text = L["Team name, size"], button1 = L["Save"], button2 = L["Cancel"], hasEditBox = true,
				OnShow = function(s2) s2.editBox:SetText((t2.name or "") .. ", " .. (t2.size or 40)) end,
				OnAccept = function(s2)
					local nm, sz = (s2.editBox:GetText() or ""):match("^%s*(.-)%s*,%s*(%d*)")
					t2.name = (nm and nm ~= "") and nm or t2.name
					t2.size = tonumber(sz) or t2.size
					h.teams[i] = t2 Bump()
					Send("T|" .. Ser(h.teams))
					GH:RenderTab("builder")
				end, timeout = 0, whileDead = true, hideOnEscape = true }
			StaticPopup_Show("SUGH_TEAMNAME")
		end)
		if st.sel == i then b.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
		x = x + 80
	end
	local hint = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	hint:SetPoint("TOPLEFT", 4, -24)
	hint:SetText("|cff777777" .. L["Click a member to pick them up, then click a team card to drop. Right-click a member removes them. Double-click a card renames."] .. "|r")
	local t = h.teams[st.sel]
	if t then
		local del = Btn(page, 90, 16, L["Hide team"])
		del:SetPoint("TOPRIGHT", -4, -24)
		del:SetScript("OnClick", function()
			t.hidden = not t.hidden Bump() Send("T|" .. Ser(h.teams)) GH:RenderTab("builder")
		end)
	end
	-- member list: click assigns into selected team
	local roster = Roster()
	local list = {}
	for name, e in pairs(roster) do list[#list + 1] = { n = name, e = e } end
	sort(list, function(a, b) return a.n < b.n end)
	ListRows(page, -44, 18, min(#list, 26), function(r, i)
		local m = list[i]
		if not m then return end
		local inteam = t and t.members and t.members[m.n]
		RowFS(r, "name", 6):SetText((inteam and ("|cff" .. ACC .. "» |r") or "") .. ClassColor(m.n))
		RowFS(r, "role", 280):SetText(RoleIcon(h.roles[m.n] or "N", 12) .. " " .. (RoleName(h.roles[m.n] or "N") or ""))
		r:SetScript("OnClick", function(_, btn)
			if not t then return end
			t.members = t.members or {}
			if btn == "RightButton" then
				if t.members[m.n] then t.members[m.n] = nil Bump() Send("T|" .. Ser(h.teams)) GH:RenderTab("builder") end
			elseif not t.members[m.n] then
				-- pick up the member; next card click drops them there
				GH.pickup = m.n
				if not GH.chip then
					local c = CreateFrame("Frame", nil, UIParent)
					c:SetSize(120, 18) c:SetFrameStrata("TOOLTIP")
					c.fs = S:FontString(c, 11, "OUTLINE", S.media.font, nil, "LEFT")
					c.fs:SetPoint("CENTER")
					c:SetScript("OnUpdate", function()
						local x, y = GetCursorPosition()
						c:ClearAllPoints() c:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / UIParent:GetEffectiveScale(), y / UIParent:GetEffectiveScale())
					end)
					GH.chip = c
				end
				GH.chip.fs:SetText("|cff" .. ACC .. "» " .. m.n .. "|r")
				GH.chip:Show()
			end
		end)
	end)
end

-------------------------------------------------------------------------------
-- TAB: Bounties
-------------------------------------------------------------------------------

tabs.bounties = function(self, page)
	local h = Shared()
	local rows = {}
	for id, b in pairs(h.bounties) do
		if not b.done then rows[#rows + 1] = b end
	end
	sort(rows, function(a, b) return (a.t or 0) > (b.t or 0) end)
	if CanI("bounty") then
		local nb = Btn(page, 110, 18, L["Post bounty…"])
		nb:SetPoint("TOPRIGHT", -4, -2)
		nb:SetScript("OnClick", function()
			StaticPopupDialogs["SUGH_BOUNTY"] = {
				text = L["Target, gold, note (comma separated) — 'Use target' fills your current target"],
				button1 = L["Post"], button2 = L["Cancel"], hasEditBox = true, maxLetters = 80,
				OnShow = function(s2)
					local tn = UnitName("target")
					if tn then s2.editBox:SetText(tn .. ", 50, ") end
				end,
				OnAccept = function(s2)
					local t, g, n = (s2.editBox:GetText() or ""):match("^%s*(.-)%s*,%s*(%d*)%s*,?%s*(.-)%s*$")
					if not t or t == "" then return end
					local b = { id = "b" .. time() .. "-" .. myName, target = t, gold = tonumber(g) or 0,
						note = n, poster = myName, t = time() }
					Shared().bounties[b.id] = b Bump()
					Send("B|" .. Ser(b))
					GH:RenderTab("bounties")
				end, timeout = 0, whileDead = true, hideOnEscape = true }
			StaticPopup_Show("SUGH_BOUNTY")
		end)
	end
	ListRows(page, -26, 22, min(#rows, 22), function(r, i)
		local b = rows[i]
		if not b then return end
		RowFS(r, "t", 6):SetText(b.target or "?")
		RowFS(r, "g", 240):SetText(format("|cff" .. ACC .. "%dg|r", b.gold or 0))
		RowFS(r, "p", 300):SetText(format("|cff888888%s|r", b.poster or "?"))
		RowFS(r, "n", 400):SetText(b.note or "")
		RowFS(r, "c", 580):SetText(b.claimer and format(L["claimed by %s"], b.claimer) or "")
		r:SetScript("OnClick", function(_, btn)
			if btn == "RightButton" and not b.claimer and b.poster ~= myName then
				b.claimer, b.claimT = myName, time() Bump()
				Send("BC|" .. b.id)
				Notify(format(L["Bounty claimed — post the kill screenshot in %s."], Shared().perms.bountyChan or "#bounties"))
				GH:RenderTab("bounties")
			end
		end)
	end)
	local hint = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	hint:SetPoint("BOTTOMLEFT", 4, 4)
	hint:SetText("|cff777777" .. L["Right-click a bounty to claim it, then post the kill screenshot in the Discord channel."] .. "|r")
end

tabs.mbounties = function(self, page)
	local h = Shared()
	if not (CanI("mbounty") or IsGM(myName)) then
		local em = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		em:SetPoint("TOPLEFT", 8, -8)
		em:SetText("|cff777777" .. L["Only bounty managers can approve or reject claims."] .. "|r")
		return
	end
	local rows = {}
	for id, b in pairs(h.bounties) do rows[#rows + 1] = b end
	sort(rows, function(a, b) return (a.t or 0) > (b.t or 0) end)
	ListRows(page, -6, 22, min(#rows, 22), function(r, i)
		local b = rows[i]
		if not b then return end
		RowFS(r, "t", 6):SetText(b.target or "?")
		RowFS(r, "g", 200):SetText(format("%dg", b.gold or 0))
		RowFS(r, "c", 260):SetText(b.claimer and (L["claimed:"] .. " " .. b.claimer) or "|cff555555—|r")
		RowFS(r, "v", 380):SetText(b.verdict or "")
		if b.claimer and not b.verdict then
			local ok = Btn(r, 60, 16, L["Approve"])
			ok:SetPoint("RIGHT", -70, 0)
			ok:SetScript("OnClick", function()
				b.verdict = "approved" Bump() Send("BV|" .. b.id .. "|approved") GH:RenderTab("mbounties")
			end)
			local no = Btn(r, 60, 16, L["Reject"])
			no:SetPoint("RIGHT", -4, 0)
			no:SetScript("OnClick", function()
				b.verdict = "rejected" Bump() Send("BV|" .. b.id .. "|rejected") GH:RenderTab("mbounties")
			end)
		elseif not b.claimer then
			local d = Btn(r, 60, 16, L["Remove"])
			d:SetPoint("RIGHT", -4, 0)
			d:SetScript("OnClick", function()
				Shared().bounties[b.id] = nil Bump() Send("BD|" .. b.id) GH:RenderTab("mbounties")
			end)
		end
	end)
end

-------------------------------------------------------------------------------
-- TAB: Excommunication (guild list + private blacklist)
-------------------------------------------------------------------------------

tabs.excom = function(self, page)
	local h = Shared()
	local p = Priv()
	local hd = Header(page, L["Excommunication (the guild's)"])
	hd:SetPoint("TOPLEFT", 4, -4)
	if CanI("excom") then
		local nb = Btn(page, 110, 16, L["Add player…"])
		nb:SetPoint("TOPRIGHT", -4, -4)
		nb:SetScript("OnClick", function()
			StaticPopupDialogs["SUGH_EXCOM"] = {
				text = L["Name, reason"], button1 = L["Add"], button2 = L["Cancel"], hasEditBox = true, maxLetters = 80,
				OnAccept = function(s2)
					local n, r = (s2.editBox:GetText() or ""):match("^%s*(.-)%s*,%s*(.-)%s*$")
					if not n or n == "" then return end
					h.excom[n] = { reason = r or "", by = myName, t = time() } Bump()
					Send("X|" .. n .. "|" .. (r or ""))
					GH:RenderTab("excom")
				end, timeout = 0, whileDead = true, hideOnEscape = true }
			StaticPopup_Show("SUGH_EXCOM")
		end)
	end
	local rows = {}
	for n, e in pairs(h.excom) do rows[#rows + 1] = { n = n, e = e } end
	sort(rows, function(a, b) return a.n < b.n end)
	ListRows(page, -26, 20, min(#rows, 10), function(r, i)
		local e = rows[i]
		if not e then return end
		RowFS(r, "n", 6):SetText(e.n)
		RowFS(r, "r", 220):SetText(e.e.reason or "")
		RowFS(r, "b", 440):SetText("|cff888888" .. (e.e.by or "?") .. "|r")
		if CanI("excom") then
			local d = Btn(r, 60, 16, L["Remove"])
			d:SetPoint("RIGHT", -4, 0)
			d:SetScript("OnClick", function()
				Shared().excom[e.n] = nil Bump() Send("XD|" .. e.n) GH:RenderTab("excom")
			end)
		end
	end)
	-- personal blacklist
	local y = -30 - 10 * 20 - 14
	local hd2 = Header(page, L["Your blacklist (never shared)"])
	hd2:SetPoint("TOPLEFT", 4, y)
	local addB = Btn(page, 110, 16, L["Add player…"])
	addB:SetPoint("TOPRIGHT", -4, y - 2)
	addB:SetScript("OnClick", function()
		StaticPopupDialogs["SUGH_BLACK"] = {
			text = L["Name, days (0 = forever), reason"], button1 = L["Add"], button2 = L["Cancel"], hasEditBox = true, maxLetters = 80,
			OnAccept = function(s2)
				local n, d, r = (s2.editBox:GetText() or ""):match("^%s*(.-)%s*,%s*(%d*)%s*,?%s*(.-)%s*$")
				if not n or n == "" then return end
				local days = tonumber(d) or 0
				Priv().blacklist[n] = { reason = r or "", until_ = days > 0 and (time() + days * 86400) or nil }
				GH:RenderTab("excom")
			end, timeout = 0, whileDead = true, hideOnEscape = true }
		StaticPopup_Show("SUGH_BLACK")
	end)
	local brow = {}
	for n, e in pairs(p.blacklist) do
		if not e.until_ or e.until_ > time() then brow[#brow + 1] = { n = n, e = e } end
	end
	sort(brow, function(a, b) return a.n < b.n end)
	ListRows(page, y - 22, 20, min(#brow, 8), function(r, i)
		local e = brow[i]
		if not e then return end
		RowFS(r, "n", 6):SetText(e.n)
		RowFS(r, "r", 220):SetText(e.e.reason or "")
		RowFS(r, "u", 440):SetText(e.e.until_ and (L["until"] .. " " .. date("%d.%m.", e.e.until_)) or L["forever"])
		local d = Btn(r, 60, 16, L["Remove"])
		d:SetPoint("RIGHT", -4, 0)
		d:SetScript("OnClick", function() Priv().blacklist[e.n] = nil GH:RenderTab("excom") end)
	end)
end

-------------------------------------------------------------------------------
-- TAB: Guild Manager (rank permissions, GM writes)
-------------------------------------------------------------------------------

local RIGHTS = {
	{ "roles", L["Edit others' roles"] }, { "teams", L["Build raid groups"] },
	{ "bounty", L["Post bounties"] }, { "mbounty", L["Manage bounties"] },
	{ "excom", L["Excommunicate"] }, { "leader", L["Raid leader"] },
}

tabs.manager = function(self, page)
	local h = Shared()
	local gm = IsGM(myName)
	if not gm then
		local em = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		em:SetPoint("TOPLEFT", 8, -8)
		em:SetText("|cff777777" .. L["Only the Guild Master changes these — everyone can read them."] .. "|r")
	end
	-- rank matrix
	local ranks = {}
	for name, e in pairs(Roster()) do ranks[e.rank or 99] = e.rankName or ("Rank " .. (e.rank or 99)) end
	local cols = {}
	for i = 0, 10 do if ranks[i] then cols[#cols + 1] = i end end
	local x0, y0 = 200, -10
	local hd = S:FontString(page, 11, "OUTLINE", S.media.font, nil, "LEFT")
	hd:SetPoint("TOPLEFT", 8, 8)
	hd:SetText("|cff" .. ACC .. L["Right"] .. "|r")
	for ci, rank in ipairs(cols) do
		local fs = S:FontString(page, 9, nil, S.media.font, nil, "CENTER")
		fs:SetPoint("TOPLEFT", x0 + (ci - 1) * 60, 8)
		fs:SetWidth(58)
		fs:SetText(rank == 0 and "|cff" .. ACC .. (ranks[rank] or "GM") .. "|r" or (ranks[rank] or "?"))
	end
	local y = y0 - 8
	for _, rt in ipairs(RIGHTS) do
		local key, label = rt[1], rt[2]
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 8, y)
		fs:SetText(label)
		for ci, rank in ipairs(cols) do
			local rk = rank
			local cb = Checkbox(page, "", (function()
				for tok in gmatch(h.perms.ranks[rk] or "", "([^;]+)") do if tok == key then return true end end
				return false
			end)(), function(v)
				if not gm then return end
				local toks = {}
				for tok in gmatch(h.perms.ranks[rk] or "", "([^;]+)") do if tok ~= "" and tok ~= key then toks[#toks + 1] = tok end end
				if v then toks[#toks + 1] = key end
				h.perms.ranks[rk] = ";" .. table.concat(toks, ";") .. ";"
				Bump() Send("P|" .. Ser(h.perms))
			end)
			cb:SetPoint("TOPLEFT", x0 + (ci - 1) * 60 + 18, y)
			if not gm then cb:Disable() end
		end
		y = y - 22
	end
	local cb = Checkbox(page, L["Members may set their own role"], h.perms.membersCanRole ~= false, function(v)
		if not gm then return end
		h.perms.membersCanRole = v Bump() Send("P|" .. Ser(h.perms))
	end)
	cb:SetPoint("TOPLEFT", 8, y - 10)
	if not gm then cb:Disable() end
	y = y - 40
	-- grants
	local gh2 = Header(page, L["Personal grants"])
	gh2:SetPoint("TOPLEFT", 8, y)
	y = y - 20
	local ge = Edit(page, 140, 18, L["Character name"])
	ge:SetPoint("TOPLEFT", 8, y)
	local gb = Edit(page, 140, 18, L["rights (roles,teams,leader…)"])
	gb:SetPoint("TOPLEFT", 156, y)
	local ga = Btn(page, 70, 18, L["Grant"])
	ga:SetPoint("TOPLEFT", 304, y)
	ga:SetScript("OnClick", function()
		if not gm then return end
		local n, r = strtrim(ge:GetText() or ""), strtrim(gb:GetText() or "")
		if n == "" then return end
		if r ~= "" and r:sub(1,1) ~= ";" then r = ";" .. r:gsub(",", ";") .. ";" end
		h.perms.grants[n] = r
		Bump() Send("P|" .. Ser(h.perms)) GH:RenderTab("manager")
	end)
	y = y - 26
	local n = 0
	for nm, r in pairs(h.perms.grants) do
		if n < 6 then
			n = n + 1
			local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", 10, y)
			fs:SetText(format("%s — %s", nm, r))
			y = y - 14
		end
	end
	-- nuke
	y = y - 14
	local wipe2 = Btn(page, 180, 18, L["Remove all addon data"])
	wipe2:SetPoint("TOPLEFT", 8, y)
	if not gm then wipe2:Disable() end
	wipe2:SetScript("OnClick", function()
		StaticPopupDialogs["SUGH_WIPE"] = {
			text = L["Really clear ALL shared GuildHub data for this guild? (permissions, raids, bounties, roles)"],
			button1 = L["Yes, clear"], button2 = L["Cancel"],
			OnAccept = function()
				local h2 = Shared()
				for k in pairs(h2) do if k ~= "local_" and k ~= "ver" then h2[k] = nil end end
				Shared() -- rebuild defaults
				Bump() Send("F|" .. Ser(Shared()))
				GH:RenderTab("manager")
			end, timeout = 0, whileDead = true, hideOnEscape = true }
		StaticPopup_Show("SUGH_WIPE")
	end)
end

-------------------------------------------------------------------------------
-- TAB: Settings
-------------------------------------------------------------------------------

tabs.settings = function(self, page)
	local p = Priv()
	if not p then return end
	local s = p.settings
	local y = -6
	local function Tog(key, label, invert)
		local v = s[key]
		if invert then v = (v == false) and false or true else v = v and true or false end
		local cb = Checkbox(page, label, v, function(nv)
			s[key] = invert and (not nv) or nv
			if key == "ctaButton" then GH:UpdateCTA() end
			if key == "minimap" then GH:UpdateMinimap() end
		end)
		cb:SetPoint("TOPLEFT", 8, y)
		y = y - 24
	end
	local hd = Header(page, L["Alerts"])
	hd:SetPoint("TOPLEFT", 4, y) y = y - 22
	Tog("raidAlerts", L["Raid alerts (15 min before + at start)"])
	Tog("ctaAlerts", L["Call to Arms popups"])
	Tog("ctaPin", L["Call to Arms drops a map pin"])
	Tog("chatNotices", L["Chat notices (craft requests, bounties, raids)"])
	local hd2 = Header(page, L["Sharing"])
	hd2:SetPoint("TOPLEFT", 4, y) y = y - 22
	Tog("shareBank", L["Share the guild bank when I open it"])
	local hd3 = Header(page, L["Window"])
	hd3:SetPoint("TOPLEFT", 4, y) y = y - 22
	Tog("ctaButton", L["Show the Call to Arms button"])
	Tog("minimap", L["Minimap button"])
	local hd4 = Header(page, L["Excommunication"])
	hd4:SetPoint("TOPLEFT", 4, y) y = y - 22
	Tog("hideExcom", L["Hide chat and invites of excommunicated players"])
	Tog("hideBlack", L["Hide chat and invites of my blacklist"])
end

-------------------------------------------------------------------------------
-- Call to Arms button + broadcasting
-------------------------------------------------------------------------------

function GH:UpdateCTA()
	local p = Priv()
	if p and p.settings.ctaButton == false then
		if self.cta then self.cta:Hide() end
		return
	end
	if not self.cta then
		local b = CreateFrame("Button", "SentinelUICTA", UIParent, S.BackdropTemplate)
		b:SetSize(46, 46)
		b:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
		b:SetMovable(true) b:EnableMouse(true) b:RegisterForDrag("LeftButton")
		b:SetClampedToScreen(true)
		S:SetTemplate(b, "Default")
		b:SetScript("OnDragStart", b.StartMoving)
		b:SetScript("OnDragStop", b.StopMovingOrSizing)
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		t:SetTexture("Interface\\Icons\\INV_Misc_Horn_04")
		t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b:SetScript("OnEnter", function()
			GameTooltip:SetOwner(b, "ANCHOR_TOP")
			GameTooltip:SetText(L["Call to Arms"])
			GameTooltip:AddLine(L["Click: call the guild to your position · Drag: move"], 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function() GH:CallToArms() end)
		self.cta = b
	end
	self.cta:Show()
end

function GH:CallToArms(note)
	local now = GetTime()
	if self._ctaT and now - self._ctaT < 900 then
		Notify(format(L["Call to Arms is on cooldown (%d min left)."], floor((900 - (now - self._ctaT)) / 60)))
		return
	end
	self._ctaT = now
	local zone = GetRealZoneText and GetRealZoneText() or GetZoneText and GetZoneText() or "?"
	local x, y = 0, 0
	if GetPlayerMapPosition then
		x, y = GetPlayerMapPosition("player") or 0, 0
	elseif C_Map and C_Map.GetPlayerMapPosition then
		local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
		if pos then x, y = pos.x or 0, pos.y or 0 end
	end
	x, y = tonumber(x) or 0, tonumber(y) or 0
	Send("CTA|" .. zone .. "|" .. format("%.3f", x) .. "|" .. format("%.3f", y) .. "|" .. (note or ""))
	if SendChatMessage then
		SendChatMessage(format("%s — %s %s", L["Call to Arms"], zone, (note and note ~= "") and ("(" .. note .. ")") or ""), "GUILD")
	end
	Notify(L["Call to Arms sent."])
end

-------------------------------------------------------------------------------
-- excom / blacklist enforcement: chat filter + invite decline
-------------------------------------------------------------------------------

local function Blocked(name)
	if not name then return false end
	name = Ambiguate(name, "short")
	local h = Shared()
	local p = Priv()
	if not p then return false end
	if p.settings.hideExcom and h.excom[name] then return true end
	if p.settings.hideBlack then
		local b = p.blacklist[name]
		if b and (not b.until_ or b.until_ > time()) then return true end
	end
	return false
end

local function ChatFilter(_, _, msg, sender, ...)
	if Blocked(sender) then return true end
	return false
end

local CHAT_EVENTS = {
	"CHAT_MSG_GUILD", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
}

-------------------------------------------------------------------------------
-- raid alerts
-------------------------------------------------------------------------------

local function CheckRaidAlerts()
	local h = Shared()
	local p = Priv()
	if not (h and p) or p.settings.raidAlerts == false then return end
	p.alertsGiven = p.alertsGiven or {}
	local now = time()
	for id, r in pairs(h.raids) do
		if r.status == "open" and r.epoch then
			local su = h.signups[id] and h.signups[id][MainOf(myName)]
			local going = su and (su.status == "coming" or su.status == "tentative" or su.status == "late")
			local lineupOk = (not r.lineup) or r.lineup[MainOf(myName)] == "confirmed" or r.lineup[MainOf(myName)] == nil
			if su and going and lineupOk then
				for _, when in ipairs({ { "pre", r.epoch - 900, L["starts in 15 minutes"] }, { "go", r.epoch, L["starts now"] } }) do
					local key = id .. when[1]
					if now >= when[2] and now < when[2] + 120 and not p.alertsGiven[key] then
						p.alertsGiven[key] = true
						local slot = r.lineup and r.lineup[MainOf(myName)]
						Notify(format("|cffff5050%s:|r %s — %s (%s%s)", L["Raid"], r.title or "?", when[3],
							su.status, slot and (", " .. LINEUP_ST[slot][1]) or ""))
						if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Initialize
-------------------------------------------------------------------------------

function GH:UpdateMinimap()
	local p = Priv()
	if p and p.settings.minimap == false then
		if self.minimapBtn then self.minimapBtn:Hide() end
		return
	end
	if not self.minimapBtn then
		self.private = self.private or {}
		self.private.ghMinimap = self.private.ghMinimap or {}
		self.minimapBtn = S:CreateMinimapButton({
			name = "guildhub", glyph = "GH",
			store = self.private.ghMinimap, angle = 250,
			onLeft = function() GH:Toggle() end,
			onRight = function() GH:Toggle() GH:SelectTab("manager") end,
			tooltip = function()
				GameTooltip:AddLine("SentinelGuild")
				local h = Shared()
				if h then
					local next_ = nil
					for _, r in pairs(h.raids) do
						if r.status == "open" and r.epoch and r.epoch > time() and (not next_ or r.epoch < next_.epoch) then next_ = r end
					end
					if next_ then GameTooltip:AddLine(format("%s: %s %s", L["Next raid"], next_.title or "?", date("%d.%m. %H:%M", next_.epoch)), 1, 1, 1) end
					GameTooltip:AddLine(format(L["Role: %s"], RoleName(h.roles[GH._GetMyName() or "?"] or "N")), 0.8, 0.8, 0.8)
					local nb = 0 for _, b in pairs(h.bounties) do if not b.claimer and not b.done then nb = nb + 1 end end
					if nb > 0 then GameTooltip:AddLine(format(L["Open bounties: %d"], nb), 1, 0.8, 0.4) end
				end
				GameTooltip:AddLine(L["Left-click: window · Right-click: Guild Manager"], 0.7, 0.7, 0.7)
			end,
		})
	end
	self.minimapBtn:Show()
end

function GH:Initialize()
	myName = Ambiguate(UnitName("player"), "short")
	self:SetupShell()
	if not IsInGuild() then
		if not self._guildWait then
			self._guildWait = true
			self:RegisterEvent("PLAYER_GUILD_UPDATE", function()
				if IsInGuild() then GH._guildWait = nil GH:Initialize() end
			end)
		end
		return
	end
	GH._SetMyName(myName)
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	-- record this character as one of the account's guild characters
	local p = Priv()
	if p then
		local d = p.settings
		for _, k in ipairs({ "raidAlerts", "ctaAlerts", "ctaPin", "chatNotices", "shareBank", "ctaButton", "minimap" }) do
			if d[k] == nil then d[k] = true end
		end
		p.myChars[myName] = p.myChars[myName] or {}
		local e = Roster(true)[myName]
		p.myChars[myName].level = (e and e.level) or UnitLevel("player")
		p.myChars[myName].class = select(2, UnitClass("player"))
		p.myChars[myName].rank = e and e.rankName
		p.myChars[myName].t = time()
		-- declare main link if we have one stored locally
		if p.myChars[myName].main then Send("M|" .. p.myChars[myName].main) end
	end
	-- events
	self:RegisterEvent("CHAT_MSG_ADDON", OnComm2)
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function() Roster(true) if GH:IsShown("roster") then GH:RenderTab("roster") end end)
	self:RegisterEvent("GUILDBANKFRAME_OPENED", function() C_Timer.After(0.5, function() GH:ShareGuildBank() end) end)
	self:RegisterEvent("CHAT_MSG_LOOT", function(_, _, msg) S:SafeCall("GuildHub:Loot", GH.OnLootMsg, GH, msg) end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() GH:ReportLayer() end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
		-- remind about bounties on your target
		local tn = UnitName("target")
		local h = Shared()
		if tn and h then
			for id, b in pairs(h.bounties) do
				if b.target == tn and not b.claimer and not b.done then
					Notify(format(L["Your target has a bounty: %sg — screenshot the kill!"], b.gold or 0))
					break
				end
			end
		end
	end)
	for _, ev in ipairs(CHAT_EVENTS) do
		if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter(ev, ChatFilter) end
	end
	-- invite decline for blocked players
	hooksecurefunc("StaticPopup_Show", function(which, a1)
		if which == "PARTY_INVITE" and Blocked(a1) then
			C_Timer.After(0, function()
				if DeclineGroup then DeclineGroup() end
				if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
			end)
		end
	end)
	-- sync hello + periodic re-request
	Hello2()
	C_Timer.NewTicker(900, function() Send("Q|") end)
	self:RegisterEvent("TRADE_SKILL_SHOW", function() GH:Delay(0.7, GH.ScanTradeRecipes, GH) end)
	GH:Delay(8, GH.ScanAndShareProfs, GH)
	GH:Delay(10, GH.ShareAttunements, GH)
	-- broadcast own state
	self:Delay(5, function()
		local h = Shared()
		local role = h.roles[myName]
		if role then Send("R|" .. role) end
		if h.altDecl[myName] then Send("M|" .. h.altDecl[myName]) end
		if h.mainDecl[myName] then for alt in pairs(h.mainDecl[myName]) do Send("MC|" .. alt) end end
		GH:BroadcastFinder() GH:BroadcastBG() GH:ReportLayer()
	end)
	-- auto attendance: a leader inside the raid window records every 5 min
	C_Timer.NewTicker(60, function()
		S:SafeCall("GuildHub:AutoAtt", function()
			if not (CanI("leader") and IsInRaid()) then return end
			local now = time()
			for id, r in pairs(Shared().raids) do
				if r.status == "open" and r.epoch and now >= r.epoch - 900 and now <= r.epoch + (r.dur or 3) * 3600 then
					if not GH._attT or now - GH._attT >= 300 then
						GH._attT = now
						GH:RecordAttendance(r)
					end
				end
			end
		end)
	end)
	-- alert tickers
	C_Timer.NewTicker(30, function() S:SafeCall("GuildHub:Alerts", CheckRaidAlerts) end)
	C_Timer.NewTicker(120, function() S:SafeCall("GuildHub:LayerTick", GH.ReportLayer, GH) end)
	-- prune stale finder entries
	C_Timer.NewTicker(60, function()
		local now = GetTime()
		for n, g in pairs(GH.gf) do if now - (g.t or 0) > 660 then GH.gf[n] = nil end end
		for n, g in pairs(GH.bgf) do if now - (g.t or 0) > 660 then GH.bgf[n] = nil end end
	end)
	self:UpdateMinimap()
	self:UpdateCTA()
end

function GH:SetupShell()
	if self._shellDone then return end
	self._shellDone = true
	-- commands
	SLASH_SENTINELGUILD1 = "/sgh"
	SLASH_SENTINELGUILD2 = "/sguild"
	SlashCmdList.SENTINELGUILD = function(arg)
		arg = strtrim(arg or ""):lower()
		local first, rest = arg:match("^(%S*)%s*(.*)$")
		if first == "cta" then GH:CallToArms(rest ~= "" and rest or nil)
		elseif first == "roster" or first == "bank" or first == "layers" or first == "chars" or first == "prof"
			or first == "finder" or first == "lfg" or first == "bg" or first == "teams" or first == "builder"
			or first == "raids" or first == "signups" or first == "att" or first == "loot" or first == "bounties"
			or first == "excom" or first == "manager" or first == "settings" then
			local map = { roster = "roster", bank = "gbank", lfg = "finder", bg = "bgf", teams = "teams",
				raids = "signups", chars = "chars", prof = "profs" }
			local key = map[first] or first
			GH:Toggle()
			if GH.frame and GH.frame:IsShown() then GH:SelectTab(key) end
		elseif first == "refresh" then
			Roster(true) Send("Q|") Notify(L["Requested fresh guild data."])
		elseif first == "minimap" then
			local p2 = Priv()
			if p2 then p2.settings.minimap = not (p2.settings.minimap == false) GH:UpdateMinimap() end
		elseif first == "hop" and rest ~= "" then
			local h2 = Shared()
			for n, e in pairs(h2.layers) do
				if n == rest or tostring(e.l) == rest then
					if OnlineOf(n) then SendWhisper("layer hop invite?", n) Notify(format(L["Hop request sent to %s"], n)) return end
				end
			end
			Notify(L["No guildmate on that layer."])
		elseif first == "export" then
			GH:ExportTeams()
		else
			GH:Toggle()
		end
	end
end

-- comm entry point defined in GuildHub.lua
function OnComm2(_, _, prefix, msg, dist, sender)
	GH:OnCommRaw(prefix, msg, dist, sender)
end

function Hello2()
	Send("V|" .. (GH._VERSION or 1) .. "|" .. (Shared() and Shared().ver or 0))
	GH:Delay(3, function() Send("Q|") end)
end


-------------------------------------------------------------------------------
-- profession recipe + cooldown sharing (GetTradeSkill* family)
-------------------------------------------------------------------------------

function GH:ScanAndShareProfs()
	local h = Shared()
	if not (h and GetProfessions and GetProfessionInfo) then return end
	h.profs = h.profs or {}
	h.profs[myName] = h.profs[myName] or {}
	local changed = false
	for _, idx in ipairs({ GetProfessions() }) do
		local name, _, skill, maxSkill = GetProfessionInfo(idx)
		if name then
			local e = h.profs[myName][name] or {}
			e.skill, e.max = skill, maxSkill
			h.profs[myName][name] = e
			changed = true
		end
	end
	if changed then Send("PF|" .. Ser(h.profs[myName])) end
end

function GH:ScanTradeRecipes()
	local h = Shared()
	if not (h and GetNumTradeSkills and GetTradeSkillInfo) then return end
	local n = GetNumTradeSkills() or 0
	if n == 0 then return end
	local prof = GetTradeSkillLine and GetTradeSkillLine() or "?"
	local rcp, cds = {}, {}
	for i = 1, n do
		local name, stype = GetTradeSkillInfo(i)
		if name and stype ~= "header" then
			rcp[name] = true
			local cd = GetTradeSkillCooldown and GetTradeSkillCooldown(i)
			if cd and cd > 0 then cds[name] = time() + cd end
		end
	end
	if next(rcp) then
		h.profs[myName] = h.profs[myName] or {}
		local e = h.profs[myName][prof] or {}
		e.rcp, e.cds = rcp, cds
		h.profs[myName][prof] = e
		Send("PF|" .. Ser({ [prof] = e }))
	end
end

-------------------------------------------------------------------------------
-- teams export (/sgh export)
-------------------------------------------------------------------------------

function GH:ExportTeams()
	local h = Shared()
	local lines = { "SentinelGuild raid teams — " .. date("%Y-%m-%d %H:%M") }
	for i = 1, 9 do
		local t = h.teams[i]
		if t and t.name and not t.hidden then
			lines[#lines + 1] = ""
			lines[#lines + 1] = t.name .. " (" .. (t.size or 40) .. ")"
			for nm, mr in pairs(t.members or {}) do
				lines[#lines + 1] = "  " .. nm .. " (" .. (RoleName(mr) or mr) .. ")"
			end
		end
	end
	local txt = table.concat(lines, "\n")
	local f = GH.exportFrame
	if not f then
		f = CreateFrame("Frame", "SentinelUIGuildExport", UIParent, S.BackdropTemplate)
		f:SetSize(420, 320)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		S:SetTemplate(f, "Default")
		local eb = CreateFrame("EditBox", nil, f)
		eb:SetMultiLine(true) eb:SetAutoFocus(false) eb:SetFontObject("GameFontHighlight")
		eb:SetPoint("TOPLEFT", 10, -10) eb:SetPoint("BOTTOMRIGHT", -10, 10)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		f.eb = eb
		GH.exportFrame = f
	end
	f.eb:SetText(txt)
	f:Show()
	f.eb:HighlightText()
	f.eb:SetFocus()
end

function GH:ShareAttunements()
	local h = Shared()
	local D = ns.InstanceTrackerData
	if not (h and D and D.attunements) then return end
	local cd = SentinelUIInstanceDB and SentinelUIInstanceDB[GetRealmName() or ""]
	cd = cd and cd.chars
	if not cd then return end
	local p = Priv()
	local out = {}
	for name in pairs(p.myChars or {}) do
		local c = cd[name]
		if c then
			local keys = {}
			for _, a in ipairs(D.attunements) do if c[a.key] then keys[a.key] = true end end
			out[name] = keys
		end
	end
	if next(out) then
		for char, keys in pairs(out) do h.attun[char] = keys end
		Send("ATN|" .. Ser(out))
	end
end
