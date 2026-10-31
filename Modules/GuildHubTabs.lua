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

local W = GH.W
local Btn, SelBtn, Checkbox, Edit, Header, ClassColor, Ago = W.Btn, W.SelBtn, W.Checkbox, W.Edit, W.Header, W.ClassColor, W.Ago
local ListRows, RowFS, SendWhisper, Whisper, Invite = W.ListRows, W.RowFS, W.SendWhisper, W.Whisper, W.Invite
local ACC = S.accentHex or "ffcc00"
local tabs = GH.tabs

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
		sub:SetText(format("%d %s, %d %s, %d DPS", cnt.T, L["tank"], cnt.H, L["healer"], cnt.D))
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
local SIGNUP_ORDER = { "coming", "tentative", "late", "cant" }
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
	SelBtn(st.past and t2 or t1, true)
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
		-- signup buttons (fixed order)
		local bx = 10
		for _, key in ipairs(SIGNUP_ORDER) do
			local k = key
			local b = Btn(dp, 78, 18, SIGNUP_ST[k][1])
			b:SetPoint("TOPLEFT", bx, -48)
			b:SetScript("OnClick", function()
				GH:SignupDialog(raid, k)
			end)
			bx = bx + 82
		end
		-- counts
		local sg = h.signups[raid.id] or {}
		local counts = {}
		for p, su in pairs(sg) do counts[su.status] = (counts[su.status] or 0) + 1 end
		local cy = -74
		local parts = {}
		for _, key in ipairs(SIGNUP_ORDER) do
			if counts[key] then parts[#parts + 1] = SIGNUP_ST[key][2] .. SIGNUP_ST[key][1] .. ": " .. counts[key] .. "|r" end
		end
		if #parts > 0 then
			local fs = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", 10, cy)
			fs:SetText(table.concat(parts, "   "))
			cy = cy - 16
		end
		-- lineup: every signup with its slot; leaders confirm/bench per row
		local lh = Header(dp, L["Lineup"])
		lh:SetPoint("TOPLEFT", 10, cy - 4)
		cy = cy - 24
		raid.lineup = raid.lineup or {}
		local canLead = CanI("leader")
		local order = { confirmed = 1, bench = 2 }
		local plist = {}
		for p in pairs(sg) do plist[#plist + 1] = p end
		sort(plist, function(a, b)
			local ra, rb = order[raid.lineup[a]] or 3, order[raid.lineup[b]] or 3
			if ra ~= rb then return ra < rb end
			return (sg[a].char or a) < (sg[b].char or b)
		end)
		if #plist == 0 then
			local fs = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", 12, cy)
			fs:SetText("|cff777777" .. L["Nobody has signed up yet."] .. "|r")
		end
		for i, p in ipairs(plist) do
			if i > 16 then break end
			local su = sg[p]
			local slot = raid.lineup[p]
			local sst = SIGNUP_ST[su.status]
			local fs = S:FontString(dp, 11, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", 12, cy)
			fs:SetText((slot and LINEUP_ST[slot] and (LINEUP_ST[slot][2] .. "[" .. LINEUP_ST[slot][1] .. "]|r ") or "")
				.. RoleIcon(su.role, 12) .. " " .. ClassColor(su.char or p)
				.. (sst and ("  " .. sst[2] .. sst[1] .. "|r") or ""))
			if canLead then
				local function setSlot(v)
					if raid.lineup[p] == v then
						raid.lineup[p] = nil
						Send("LU|" .. raid.id .. "|" .. p .. "|clear")
					else
						raid.lineup[p] = v
						Send("LU|" .. raid.id .. "|" .. p .. "|" .. v)
					end
					Bump()
					GH:RenderTab("signups")
				end
				local bB = Btn(dp, 56, 15, L["Bench"])
				bB:SetPoint("TOPRIGHT", -8, cy + 2)
				bB:SetScript("OnClick", function() setSlot("bench") end)
				SelBtn(bB, slot == "bench")
				local bC = Btn(dp, 76, 15, L["Confirmed"])
				bC:SetPoint("RIGHT", bB, "LEFT", -4, 0)
				bC:SetScript("OnClick", function() setSlot("confirmed") end)
				SelBtn(bC, slot == "confirmed")
			end
			cy = cy - 18
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
	if #raids == 0 then
		local em = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		em:SetPoint("TOPLEFT", 4, -28)
		em:SetText("|cff777777" .. L["No raids yet — create one under Raid Signups."] .. "|r")
		if CanI("leader") then
			local nb = Btn(page, 100, 18, L["New raid…"])
			nb:SetPoint("TOPLEFT", 4, -50)
			nb:SetScript("OnClick", function() GH:RaidEditDialog(nil) end)
		end
		return
	end
	local x = 46
	for i = 1, min(6, #raids) do
		local r = raids[i]
		local b = Btn(page, 84, 16, (r.title or "?"):sub(1, 12))
		b:SetPoint("TOPLEFT", x, -4)
		b:SetScript("OnClick", function() st.raid = r.id GH:RenderTab("att") end)
		SelBtn(b, st.raid == r.id)
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
	W.OnType(srch, function(e) st.search = e:GetText() GH:RenderTab("loot") end)
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

local TEAM_ROLES = { "T", "H", "D" }
local NEXT_ROLE = { T = "H", H = "D", D = "T" }

local function TeamLive(t) return t and t.name and not t.hidden end

local function SyncTeams()
	Bump()
	Send("T|" .. Ser(Shared().teams))
end

function GH:NewTeam()
	local h = Shared()
	for i = 1, 9 do
		if not TeamLive(h.teams[i]) then
			h.teams[i] = { name = "Team " .. i, size = 40, members = {} }
			SyncTeams()
			return i
		end
	end
	Notify(L["All 9 team slots are in use — delete one first."])
end

function GH:TeamNameDialog(slot)
	local h = Shared()
	local t = h.teams[slot]
	if not TeamLive(t) then return end
	StaticPopupDialogs["SUGH_TEAMNAME"] = {
		text = L["Team name, size"], button1 = L["Save"], button2 = L["Cancel"], hasEditBox = true,
		OnShow = function(s2) s2.editBox:SetText((t.name or "") .. ", " .. (t.size or 40)) end,
		OnAccept = function(s2)
			local nm, sz = (s2.editBox:GetText() or ""):match("^%s*(.-)%s*,%s*(%d*)")
			nm = nm or strtrim(s2.editBox:GetText() or "")
			if nm ~= "" then t.name = nm end
			t.size = tonumber(sz) or t.size
			SyncTeams()
			GH:RenderTab(GH.tab)
		end, timeout = 0, whileDead = true, hideOnEscape = true }
	StaticPopup_Show("SUGH_TEAMNAME")
end

local function ToolbarButtons(page, y, x)
	local ex = Btn(page, 70, 18, L["Export"])
	ex:SetPoint("TOPLEFT", x, y)
	ex:SetScript("OnClick", function() GH:ExportTeams() end)
	local im = Btn(page, 70, 18, L["Import"])
	im:SetPoint("LEFT", ex, "RIGHT", 4, 0)
	im:SetScript("OnClick", function() GH:ImportTeamsDialog() end)
	return im
end

tabs.teams = function(self, page)
	local h = Shared()
	local canBuild = CanI("teams") or CanI("leader")
	local x = 4
	if canBuild then
		local nb = Btn(page, 110, 18, L["+ New team"])
		nb:SetPoint("TOPLEFT", 4, -2)
		nb:SetScript("OnClick", function()
			local slot = GH:NewTeam()
			if slot then
				GH.bldState = GH.bldState or {}
				GH.bldState.sel = slot
				GH:SelectTab("builder")
			end
		end)
		x = 118
	end
	ToolbarButtons(page, -2, x)

	local any = false
	local cx, cy = 4, -28
	for i = 1, 9 do
		local t = h.teams[i]
		if TeamLive(t) then
			any = true
			local card = CreateFrame("Frame", nil, page, S.BackdropTemplate)
			card:SetPoint("TOPLEFT", cx, cy)
			card:SetSize(336, 132)
			S:SetTemplate(card, "Default")
			local tt = Header(card, t.name)
			tt:SetPoint("TOPLEFT", 8, -6)
			local n = 0
			for _ in pairs(t.members or {}) do n = n + 1 end
			local cnt = S:FontString(card, 10, nil, S.media.font, nil, "RIGHT")
			cnt:SetPoint("TOPRIGHT", -8, -8)
			cnt:SetText(format("%d/%d", n, t.size or 40))
			local yy = -26
			for _, role in ipairs(TEAM_ROLES) do
				local names = {}
				for nm, mr in pairs(t.members or {}) do
					if mr == role then names[#names + 1] = nm end
				end
				sort(names)
				if #names > 0 then
					local colored = {}
					for _, nm in ipairs(names) do colored[#colored + 1] = ClassColor(nm) end
					local fs = S:FontString(card, 10, nil, S.media.font, nil, "LEFT")
					fs:SetPoint("TOPLEFT", 8, yy)
					fs:SetWidth(318)
					fs:SetWordWrap(true)
					fs:SetText(RoleIcon(role, 12) .. " " .. table.concat(colored, ", "))
					yy = yy - (10 + 12 * math.ceil(#names / 5))
				end
			end
			if n == 0 then
				local fs = S:FontString(card, 10, nil, S.media.font, nil, "LEFT")
				fs:SetPoint("TOPLEFT", 8, -28)
				fs:SetText("|cff777777" .. L["Empty — open the Raid Builder to fill it."] .. "|r")
			end
			if canBuild then
				local eb = Btn(card, 60, 16, L["Edit"])
				eb:SetPoint("BOTTOMRIGHT", -6, 6)
				eb:SetScript("OnClick", function()
					GH.bldState = GH.bldState or {}
					GH.bldState.sel = i
					GH:SelectTab("builder")
				end)
			end
			if cx == 4 then cx = 344 else cx = 4 cy = cy - 138 end
		end
	end
	if not any then
		local em = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		em:SetPoint("TOPLEFT", 8, -34)
		em:SetText("|cff777777" .. L["No raid teams yet — use '+ New team' or paste a list with Import."] .. "|r")
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
	st.sel = st.sel or 1

	-- row 1: the nine team slots
	local x = 4
	for i = 1, 9 do
		local t = h.teams[i]
		local b = Btn(page, 72, 18, (TeamLive(t) and t.name or ("+" .. i)):sub(1, 10))
		b:SetPoint("TOPLEFT", x, -2)
		b:SetScript("OnClick", function() st.sel = i GH:RenderTab("builder") end)
		SelBtn(b, st.sel == i)
		x = x + 75
	end

	local t = TeamLive(h.teams[st.sel]) and h.teams[st.sel] or nil

	-- row 2: toolbar
	local tx = 4
	local function Tool(label, w, fn, enabled)
		local b = Btn(page, w, 18, label)
		b:SetPoint("TOPLEFT", tx, -26)
		if enabled == false then b:Disable() b.fs:SetTextColor(0.4, 0.4, 0.4) else b:SetScript("OnClick", fn) end
		tx = tx + w + 4
		return b
	end
	Tool(L["Create team"], 90, function()
		h.teams[st.sel] = { name = "Team " .. st.sel, size = 40, members = {} }
		SyncTeams() GH:RenderTab("builder")
	end, not t)
	Tool(L["Rename"], 70, function() GH:TeamNameDialog(st.sel) end, t ~= nil)
	Tool(L["Delete team"], 90, function()
		t.hidden = true SyncTeams() GH:RenderTab("builder")
	end, t ~= nil)
	Tool(L["Export"], 70, function() GH:ExportTeams() end)
	Tool(L["Import"], 70, function() GH:ImportTeamsDialog() end)

	-- externals (not in the guild): name [role]
	local extBtn = Btn(page, 56, 18, L["Add"])
	extBtn:SetPoint("TOPRIGHT", -4, -26)
	local ext = Edit(page, 150, 18, L["Non-guild name…"])
	ext:SetPoint("RIGHT", extBtn, "LEFT", -4, 0)
	local function AddExternal()
		if GH:AddExternalToTeam(st.sel, ext:GetText()) then
			ext:SetText("")
			GH:RenderTab("builder")
		end
	end
	extBtn:SetScript("OnClick", AddExternal)
	ext:SetScript("OnEnterPressed", function() AddExternal() end)

	-- left: everyone who can be added (guild + externals already in the team)
	local left = CreateFrame("Frame", nil, page)
	left:SetPoint("TOPLEFT", 0, -54)
	left:SetPoint("BOTTOMLEFT", 0, 22)
	left:SetWidth(370)
	local list, seen = {}, {}
	local roster = Roster()
	for name in pairs(roster) do list[#list + 1] = { n = name, on = roster[name].online } seen[name] = true end
	if t then
		for name in pairs(t.members or {}) do
			if not seen[name] then list[#list + 1] = { n = name, ext = true } end
		end
	end
	local q = lower(st.search or "")
	if q ~= "" then
		local f = {}
		for _, m in ipairs(list) do if lower(m.n):find(q, 1, true) then f[#f + 1] = m end end
		list = f
	end
	sort(list, function(a, b)
		if (a.ext and 1 or 0) ~= (b.ext and 1 or 0) then return a.ext and true or false end
		if (a.on and 1 or 0) ~= (b.on and 1 or 0) then return a.on and true or false end
		return a.n < b.n
	end)
	local PER = 22
	local pages = max(1, math.ceil(#list / PER))
	st.page = min(max(st.page or 1, 1), pages)
	local srch = Edit(left, 120, 16, L["Search"])
	srch:SetPoint("TOPRIGHT", -88, 0)
	srch:SetText(st.search or "")
	W.OnType(srch, function(e) st.search = e:GetText() st.page = 1 GH:RenderTab("builder") end)
	local nextB = Btn(left, 20, 16, ">")
	nextB:SetPoint("TOPRIGHT", -2, 0)
	nextB:SetScript("OnClick", function() st.page = min(pages, st.page + 1) GH:RenderTab("builder") end)
	local prevB = Btn(left, 20, 16, "<")
	prevB:SetPoint("RIGHT", nextB, "LEFT", -2, 0)
	prevB:SetScript("OnClick", function() st.page = max(1, st.page - 1) GH:RenderTab("builder") end)
	local lh = Header(left, format("%s %d/%d", L["Members"], st.page, pages))
	lh:SetPoint("TOPLEFT", 6, -2)
	local first = (st.page - 1) * PER
	ListRows(left, -22, 18, min(PER, #list - first), function(r, i)
		local m = list[first + i]
		if not m then return end
		local inteam = t and t.members and t.members[m.n]
		local role = h.roles[m.n] or "N"
		RowFS(r, "name", 6):SetText((inteam and ("|cff" .. ACC .. "» |r") or "   ") .. ClassColor(m.n) .. (m.ext and (" |cff888888(" .. L["external"] .. ")|r") or (m.on and "" or " |cff555555(off)|r")))
		RowFS(r, "role", 250):SetText(RoleIcon(role, 12) .. " " .. (RoleName(role) or ""))
		r:SetScript("OnClick", function(_, btn)
			if not t then
				GH:NewTeam()
				return GH:RenderTab("builder")
			end
			t.members = t.members or {}
			if btn == "RightButton" then
				if t.members[m.n] then t.members[m.n] = NEXT_ROLE[t.members[m.n]] or "D" end
			elseif t.members[m.n] then
				t.members[m.n] = nil
			else
				t.members[m.n] = (role == "T" or role == "H" or role == "D") and role or "D"
			end
			SyncTeams()
			GH:RenderTab("builder")
		end)
	end)
	local hint = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	hint:SetPoint("BOTTOMLEFT", 4, 4)
	hint:SetText("|cff777777" .. L["Left-click adds/removes a member in the selected team, right-click changes their role in it."] .. "|r")

	-- right: the selected team
	local dp = CreateFrame("Frame", nil, page, S.BackdropTemplate)
	dp:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
	dp:SetPoint("BOTTOMRIGHT", 0, 22)
	S:SetTemplate(dp, "Default")
	if not t then
		local fs = S:FontString(dp, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 10, -10)
		fs:SetText("|cff777777" .. L["This slot is empty — press 'Create team'."] .. "|r")
		return
	end
	local title = Header(dp, t.name)
	title:SetPoint("TOPLEFT", 10, -8)
	local counts = { T = 0, H = 0, D = 0 }
	local total = 0
	for _, r in pairs(t.members or {}) do counts[r] = (counts[r] or 0) + 1 total = total + 1 end
	local sub = S:FontString(dp, 10, nil, S.media.font, nil, "LEFT")
	sub:SetPoint("TOPLEFT", 10, -26)
	sub:SetText(format("%d/%d   %s %d  %s %d  %s %d", total, t.size or 40,
		RoleIcon("T", 12), counts.T, RoleIcon("H", 12), counts.H, RoleIcon("D", 12), counts.D))
	local members = {}
	for nm, r in pairs(t.members or {}) do members[#members + 1] = { n = nm, r = r } end
	local rank = { T = 1, H = 2, D = 3 }
	sort(members, function(a, b)
		if rank[a.r] ~= rank[b.r] then return (rank[a.r] or 4) < (rank[b.r] or 4) end
		return a.n < b.n
	end)
	ListRows(dp, -44, 18, min(#members, 20), function(r, i)
		local m = members[i]
		if not m then return end
		RowFS(r, "name", 8):SetText(RoleIcon(m.r, 12) .. " " .. ClassColor(m.n))
		RowFS(r, "role", 160):SetText(RoleName(m.r) or m.r)
		local rm = Btn(r, 18, 14, "x")
		rm:SetPoint("RIGHT", -4, 0)
		rm:SetScript("OnClick", function()
			t.members[m.n] = nil SyncTeams() GH:RenderTab("builder")
		end)
		r:SetScript("OnClick", function()
			t.members[m.n] = NEXT_ROLE[m.r] or "D" SyncTeams() GH:RenderTab("builder")
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
		-- registered as a minimap-family button: ButtonBars collects it into the
		-- bottom icon bar automatically, with the horn texture as its icon
		self.cta = S:CreateMinimapButton({
			name = "cta",
			icon = "Interface\\Icons\\INV_Misc_Horn_04",
			angle = 280,
			onLeft = function() GH:CallToArms() end,
			tooltip = function()
				GameTooltip:AddLine(L["Call to Arms"])
				GameTooltip:AddLine(L["Click: call the guild to your position · Drag: move"], 1, 1, 1)
			end,
		})
	end
	-- hand it to ButtonBars explicitly (auto-scan skips SentinelUI-named buttons
	-- unless collectSUI is on)
	local bb = S.GetModule and S:GetModule("ButtonBars")
	if bb and bb.GrabButton and self.cta:GetParent() == Minimap then
		bb:GrabButton(self.cta, "SentinelUIMinimapButton_cta")
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
-- TAB: Member detail (gear, stats, professions, attunements, loot)
-------------------------------------------------------------------------------

local GEAR_COLS = {
	{ 1, 2, 3, 15, 5, 9 },          -- head neck shoulder back chest wrist
	{ 10, 6, 7, 8, 11, 12, 13, 14 },-- hands waist legs feet rings trinkets
}
local GEAR_BOT = { 16, 17, 18 }     -- main, off, ranged
local SLOT_NAME = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest",
	[9] = "Wrist", [10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet",
	[11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket",
	[16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}
local QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
	[4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff" }

local function ItemIcon(id)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
	if S.GetItemInfoInstant then return select(5, S.GetItemInfoInstant(id)) end
end

local function GearSlot(page, x, y, w, slot, d)
	local row = CreateFrame("Button", nil, page)
	row:SetPoint("TOPLEFT", x, y)
	row:SetSize(w, 20)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("LEFT", 2, 0)
	row.icon:SetSize(16, 16)
	row.fs = S:FontString(row, 10, nil, S.media.font, nil, "LEFT")
	row.fs:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
	row.fs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.fs:SetJustifyH("LEFT")
	if d then
		local q = (S.GetItemInfo and select(3, S.GetItemInfo(d.l or ""))) or 1
		local hex = QUALITY_HEX[q] or "ffffff"
		row.icon:SetTexture(ItemIcon(d.id or 0) or "Interface\\Icons\\INV_Misc_QuestionMark")
		local ench = (GH.ENCHANT_SLOTS[slot] and (d.e or 0) == 0) and "  |cffff4444!ench|r" or ""
		row.fs:SetText(format("|cff%s%s|r  |cff888888%d|r%s", hex,
			(S.GetItemInfo and S.GetItemInfo(d.l or "")) or L[SLOT_NAME[slot]] or "?", d.i or 0, ench))
		row:SetScript("OnEnter", function()
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(d.l)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnClick", function() if IsModifiedClick and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(d.l) end end)
	else
		row.icon:SetColorTexture(0.16, 0.16, 0.16, 1)
		row.fs:SetText("|cff555555" .. (L[SLOT_NAME[slot]] or "?") .. "|r")
	end
	return row
end

tabs.member = function(self, page)
	local h = Shared()
	local name = GH.memberOf or myName
	local e = Roster()[name] or {}

	local back = Btn(page, 92, 18, "< " .. L["Guild Roster"])
	back:SetPoint("TOPLEFT", 4, -4)
	back:SetScript("OnClick", function() GH:SelectTab("roster") end)
	local wsp = Btn(page, 70, 18, L["Whisper"])
	wsp:SetPoint("TOPLEFT", 100, -4)
	wsp:SetScript("OnClick", function() Whisper(name) end)

	local title = S:FontString(page, 15, "OUTLINE", S.media.font, nil, "LEFT")
	title:SetPoint("TOPLEFT", 4, -28)
	title:SetText(ClassColor(name) .. (name == myName and (" |cff888888(" .. L["you"] .. ")|r") or ""))
	local st, mName = AltStatus(name)
	local seen = e.online and ("|cff44dd44" .. L["Online"] .. "|r  " .. (e.zone or ""))
		or (e.lastOnline and format("|cff888888%s %s|r", L["last seen"], Ago(time() - e.lastOnline)) or "|cff888888" .. L["offline"] .. "|r")
	local sub = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	sub:SetPoint("TOPLEFT", 4, -44)
	sub:SetText(format("%s  ·  %s %d  ·  %s%s", e.rankName or "?", L["Level"], e.level or 0, seen,
		st == "linked" and ("  ·  |cff777777" .. format(L["alt of %s"], mName)) or ""))

	-- equipment
	local gy = -64
	Header(page, L["Equipment"]):SetPoint("TOPLEFT", 4, gy)
	local eq = h.equip and h.equip[name]
	if eq and eq.slots then
		local ilfs = S:FontString(page, 10, nil, S.media.font, nil, "RIGHT")
		ilfs:SetPoint("TOPRIGHT", -8, gy - 1)
		ilfs:SetText(format(L["Item level |cff%s%d|r  ·  %s"], ACC, eq.ilvl or 0, Ago(time() - (eq.t or time()))))
		gy = gy - 20
		local colW, colX = 205, { 8, 232 }
		for ci, slots in ipairs(GEAR_COLS) do
			local yy = gy
			for _, slot in ipairs(slots) do
				GearSlot(page, colX[ci], yy, colW, slot, eq.slots[slot])
				yy = yy - 20
			end
		end
		local bx = 8
		for _, slot in ipairs(GEAR_BOT) do
			GearSlot(page, bx, gy - 6 * 20 - 4, 140, slot, eq.slots[slot])
			bx = bx + 145
		end
		local missEnch = 0
		for slot in pairs(GH.ENCHANT_SLOTS) do
			local d = eq.slots[slot]
			if d and (d.e or 0) == 0 then missEnch = missEnch + 1 end
		end
		if missEnch > 0 then
			local wf = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
			wf:SetPoint("TOPLEFT", 8, gy - 6 * 20 - 28)
			wf:SetText("|cffff4444" .. format(L["%d slots missing an enchant."], missEnch) .. "|r")
		end
	else
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 10, gy - 18)
		fs:SetText("|cff777777" .. L["No gear data yet — this member has to log in once with the addon."] .. "|r")
	end

	-- right column: stats / professions / attunements / alts / loot
	local rx, ry = 452, -64
	Header(page, L["Stats"]):SetPoint("TOPLEFT", rx, ry)
	ry = ry - 18
	if eq then
		local st2 = { { "HP", eq.hp }, { "Mana", eq.mp }, { "STR", eq.str }, { "AGI", eq.agi },
			{ "STA", eq.sta }, { "INT", eq.int }, { "SPI", eq.spi } }
		for i, kv in ipairs(st2) do
			if kv[2] and kv[2] > 0 then
				local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
				fs:SetPoint("TOPLEFT", rx + 4 + ((i - 1) % 4) * 80, ry - floor((i - 1) / 4) * 15)
				fs:SetText(format("|cff888888%s|r  %d", kv[1], kv[2]))
			end
		end
		ry = ry - 32
	else
		ry = ry - 4
	end

	Header(page, L["Professions"]):SetPoint("TOPLEFT", rx, ry)
	ry = ry - 18
	local pset = h.profs and h.profs[name]
	if pset and next(pset) then
		for prof, pp in pairs(pset) do
			local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", rx + 4, ry)
			fs:SetText(format("%s  |cff888888%d/%s|r", prof, pp.skill or 0, tostring(pp.max or "?")))
			local bar = CreateFrame("StatusBar", nil, page)
			bar:SetPoint("TOPLEFT", rx + 190, ry - 2)
			bar:SetSize(110, 9)
			bar:SetMinMaxValues(0, pp.max or 1)
			bar:SetValue(pp.skill or 0)
			bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
			bar:SetStatusBarColor(S.accent.r, S.accent.g, S.accent.b, 0.8)
			local bg = bar:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints() bg:SetColorTexture(0, 0, 0, 0.5)
			ry = ry - 16
		end
	else
		local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", rx + 4, ry)
		fs:SetText("|cff555555" .. L["no data"] .. "|r")
		ry = ry - 16
	end
	ry = ry - 8

	Header(page, L["Attunements"]):SetPoint("TOPLEFT", rx, ry)
	ry = ry - 18
	local ATTL = {
		mcAttune = "Molten Core", onyAttune = "Onyxia", bwlAttune = "Blackwing Lair",
		naxxAttune = "Naxxramas", karaAttune = "Karazhan", shatteredHallsAttune = "Shattered Halls",
		serpentshrineAttune = "Serpentshrine", blackMorassAttune = "Black Morass",
		hyjalAttune = "Hyjal", blackTempleAttune = "Black Temple",
		hellfireCitadelAttune = "HC heroic", coilfangAttune = "Coilfang heroic",
		auchindounAttune = "Auchindoun heroic", shadowLabAttune = "Shadow Labyrinth",
		tempestKeepAttune = "Tempest Keep heroic", cavernsAttune = "CoT heroic", arcatrazAttune = "Arcatraz",
	}
	-- account-wide: the char's keys merged with main + every linked alt
	local main = MainOf(name)
	local chars = { name }
	if main and main ~= name then chars[#chars + 1] = main end
	for _, alt in ipairs(AltsOf(main or name)) do chars[#chars + 1] = alt end
	local keys = {}
	for _, ch in ipairs(chars) do
		for k in pairs((h.attun and h.attun[ch]) or {}) do keys[k] = true end
	end
	local any = false
	for _, a in ipairs((ns.InstanceTrackerData and ns.InstanceTrackerData.attunements) or {}) do
		if keys[a.key] then
			any = true
			local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", rx + 4, ry)
			fs:SetText("|cff44dd44" .. (ATTL[a.key] or a.key) .. "|r")
			ry = ry - 15
		end
	end
	if not any then
		local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", rx + 4, ry)
		fs:SetText("|cff555555" .. L["no data"] .. "|r")
		ry = ry - 15
	end
	ry = ry - 8

	local alts = AltsOf(name)
	if #alts > 0 or (MainOf(name) ~= name) then
		Header(page, L["Linked characters"]):SetPoint("TOPLEFT", rx, ry)
		ry = ry - 18
		if MainOf(name) ~= name then
			local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", rx + 4, ry)
			fs:SetText(L["Main:"] .. " " .. ClassColor(MainOf(name)))
			ry = ry - 15
		end
		for _, alt in ipairs(alts) do
			local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", rx + 4, ry)
			fs:SetText(ClassColor(alt))
			ry = ry - 15
		end
		ry = ry - 8
	end

	-- wishlist (imported, account-wide)
	local wish = {}
	for _, ch in ipairs(chars) do
		for _, it in ipairs((h.wish and h.wish[ch]) or {}) do wish[#wish + 1] = it end
	end
	if #wish > 0 then
		Header(page, L["Wishlist"]):SetPoint("TOPLEFT", rx, ry)
		ry = ry - 18
		for i, it in ipairs(wish) do
			if i > 6 then break end
			local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", rx + 4, ry)
			fs:SetText(it)
			ry = ry - 15
		end
		ry = ry - 8
	end

	Header(page, L["Recent loot"]):SetPoint("TOPLEFT", rx, ry)
	ry = ry - 18
	local n = 0
	for i = #h.loot, 1, -1 do
		local l2 = h.loot[i]
		if l2.char == name then
			n = n + 1
			local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", rx + 4, ry)
			fs:SetText(format("%s  |cff777777%s|r", l2.item or "?", Ago(time() - (l2.t or time()))))
			ry = ry - 15
			if n >= 6 then break end
		end
	end
	if n == 0 then
		local fs = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", rx + 4, ry)
		fs:SetText("|cff555555" .. L["none recorded"] .. "|r")
	end
end

-------------------------------------------------------------------------------
-- TAB: EPGP (effort points / gear points)
-------------------------------------------------------------------------------

local function EPGPSync()
	local h = Shared()
	local tail = {}
	for i = max(1, #h.epgpLog - 59), #h.epgpLog do tail[#tail + 1] = h.epgpLog[i] end
	Send("EP|" .. Ser({ e = h.epgp, l = tail }))
	Bump()
end

local function EPGPLogEntry(who, kind, amt, reason)
	local h = Shared()
	h.epgpLog[#h.epgpLog + 1] = { t = time(), who = who, kind = kind, amt = amt, reason = reason, by = myName }
	if #h.epgpLog > 200 then tremove(h.epgpLog, 1) end
end

function GH:AwardEPGP(who, kind, amt, reason)
	local h = Shared()
	amt = floor(tonumber(amt) or 0)
	if amt == 0 or not who or who == "" then return end
	local e = h.epgp[who] or { ep = 0, gp = 0 }
	h.epgp[who] = e
	if kind == "ep" then e.ep = max(0, (e.ep or 0) + amt) else e.gp = max(0, (e.gp or 0) + amt) end
	EPGPLogEntry(who, kind, amt, reason)
	EPGPSync()
end

StaticPopupDialogs["SENTGH_EPGP"] = {
	text = "%s",
	button1 = L["OK"], button2 = L["Cancel"], hasEditBox = true, maxLetters = 60,
	OnAccept = function(self, data)
		local v = self.editBox:GetText()
		if data and data.fn then data.fn(v) end
	end,
	whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

tabs.epgp = function(self, page)
	local h = Shared()
	local st = GH.epgpState or { search = "", hideAlts = false }
	GH.epgpState = st
	local isLead = CanI("leader")

	local hdr = S:FontString(page, 11, "OUTLINE", S.media.font, nil, "LEFT")
	hdr:SetPoint("TOPLEFT", 4, -4)
	hdr:SetText("|cff" .. ACC .. L["EPGP — effort points / gear points / priority"] .. "|r")

	-- leader controls
	local x = 4
	if isLead then
		local function AwardDlg(title, kind, mass)
			local d = StaticPopup_Show("SENTGH_EPGP", title)
			if d then d.data = { fn = function(v)
				local amt, reason = v:match("^(%S+)%s*(.*)$")
				amt = tonumber(amt)
				if not amt then return end
				reason = strtrim(reason or "")
				if mass then
					local n = 0
					-- mass award goes to every signup of the newest open raid, else all members
					local targets = {}
					local newest, nt = nil, 0
					for id, r in pairs(h.raids) do if (r.epoch or 0) > nt then newest, nt = r, r.epoch end end
					if newest and h.signups[newest.id] then
						for p2, su in pairs(h.signups[newest.id]) do
							if su.status == "coming" or su.status == "late" or su.status == "tentative" then targets[MainOf(p2)] = true end
						end
					end
					if not next(targets) then for name in pairs(Roster()) do targets[MainOf(name)] = true end end
					for who in pairs(targets) do GH:AwardEPGP(who, kind, amt, reason) n = n + 1 end
					Notify(format(L["Awarded %d %s to %d members."], amt, upper(kind), n))
				else
					local who = GH.epgpPicked
					if not who then return end
					GH:AwardEPGP(who, kind, amt, reason)
					Notify(format(L["Awarded %d %s to %s."], amt, upper(kind), who))
				end
				GH:RenderTab("epgp")
			end } end
		end
		local b1 = Btn(page, 88, 18, L["Award EP…"])
		b1:SetPoint("TOPLEFT", x, -26)
		b1:SetScript("OnClick", function() AwardDlg(L["EP amount (and reason)"], "ep", not GH.epgpPicked) end)
		x = x + 92
		local b2 = Btn(page, 88, 18, L["Award GP…"])
		b2:SetPoint("TOPLEFT", x, -26)
		b2:SetScript("OnClick", function() AwardDlg(L["GP amount (and reason)"], "gp", not GH.epgpPicked) end)
		x = x + 92
		local b3 = Btn(page, 80, 18, L["Decay 10%"])
		b3:SetPoint("TOPLEFT", x, -26)
		b3:SetScript("OnClick", function()
			for _, e in pairs(h.epgp) do e.ep = floor((e.ep or 0) * 0.9) e.gp = floor((e.gp or 0) * 0.9) end
			EPGPLogEntry(nil, "decay", 10, L["Decay"])
			EPGPSync()
			Notify(L["EPGP decayed by 10%."])
			GH:RenderTab("epgp")
		end)
		x = x + 88
		local hint = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
		hint:SetPoint("TOPLEFT", x, -28)
		hint:SetText("|cff777777" .. L["Click a member first — no selection awards the raid (or everyone)."] .. "|r")
	end
	local cbx = Checkbox(page, L["Mains only"], st.hideAlts, function(v) st.hideAlts = v GH:RenderTab("epgp") end)
	cbx:SetPoint("TOPRIGHT", -170, -26)
	local srch = Edit(page, 130, 16, L["Search names"])
	srch:SetPoint("TOPRIGHT", -4, -26)
	srch:SetText(st.search or "")
	W.OnType(srch, function(ed) st.search = ed:GetText() GH:RenderTab("epgp") end)

	-- list
	local list, seen = {}, {}
	for name, e2 in pairs(h.epgp) do
		local m = st.hideAlts and MainOf(name) or name
		if not seen[m] then
			seen[m] = true
			local gp = max(e2.gp or 0, 1)
			list[#list + 1] = { name = m, ep = e2.ep or 0, gp = e2.gp or 0, pr = (e2.ep or 0) / gp }
		end
	end
	sort(list, function(a, b) return a.pr == b.pr and a.name < b.name or a.pr > b.pr end)
	local q = lower(st.search or "")
	local shown = {}
	for _, r2 in ipairs(list) do
		if q == "" or lower(r2.name):find(q, 1, true) then shown[#shown + 1] = r2 end
	end

	local hy = -50
	local cols = { { L["NAME"], 8 }, { "EP", 250 }, { "GP", 330 }, { "PR", 410 } }
	for _, c in ipairs(cols) do
		local fs = S:FontString(page, 10, "OUTLINE", S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", c[2], hy)
		fs:SetText("|cff" .. ACC .. c[1] .. "|r")
	end
	ListRows(page, hy - 16, 18, min(#shown, 22), function(r, i)
		local m = shown[i]
		if not m then return end
		local sel = GH.epgpPicked == m.name
		RowFS(r, "name", 10):SetText(ClassColor(m.name))
		RowFS(r, "ep", 250):SetText(tostring(m.ep))
		RowFS(r, "gp", 330):SetText(tostring(m.gp))
		RowFS(r, "pr", 410):SetText(format("%.2f", m.pr))
		if sel then r.bg:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.12) end
		r:SetScript("OnClick", function()
			GH.epgpPicked = (GH.epgpPicked == m.name) and nil or m.name
			GH:RenderTab("epgp")
		end)
	end)
	if #shown == 0 then
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 8, hy - 30)
		fs:SetText("|cff777777" .. L["No EPGP data yet — a leader can award EP/GP here."] .. "|r")
	end

	-- log
	local ly = hy - 16 - min(#shown, 22) * 18 - 24
	Header(page, L["Log"]):SetPoint("TOPLEFT", 4, ly)
	ly = ly - 16
	local n = 0
	for i = #h.epgpLog, 1, -1 do
		local le = h.epgpLog[i]
		n = n + 1
		local fs = S:FontString(page, 9, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 8, ly)
		fs:SetText(format("|cff777777%s|r  %s%s %s%d  %s%s", Ago(time() - (le.t or time())),
			le.who and ClassColor(le.who) or "", le.who and "  " or "", le.kind == "decay" and "-" or "+",
			le.amt or 0, le.kind == "decay" and "% " .. (le.reason or "") or upper(le.kind or "?") .. " ",
			(le.reason and le.reason ~= "") and ("— " .. le.reason) or ""))
		ly = ly - 14
		if n >= 8 then break end
	end
end

-------------------------------------------------------------------------------
-- TAB: Soft reserves
-------------------------------------------------------------------------------

tabs.sres = function(self, page)
	local h = Shared()
	local st = GH.sresState or {}
	GH.sresState = st

	-- raid picker
	local raids = {}
	for id, r in pairs(h.raids) do raids[#raids + 1] = r end
	sort(raids, function(a, b) return (a.epoch or 0) < (b.epoch or 0) end)
	if #raids == 0 then
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 8, -10)
		fs:SetText("|cff777777" .. L["No raids yet — create one under Raid Signups."] .. "|r")
		return
	end
	if not st.rid or not h.raids[st.rid] then st.rid = raids[1].id end
	local x = 4
	for _, r in ipairs(raids) do
		local b = Btn(page, 150, 18, (r.title or r.id) .. "  |cff888888" .. date("%d.%m", r.epoch or 0) .. "|r")
		b:SetPoint("TOPLEFT", x, -4)
		b:SetScript("OnClick", function() st.rid = r.id GH:RenderTab("sres") end)
		SelBtn(b, st.rid == r.id)
		x = x + 154
		if x > 700 then break end
	end
	local rid = st.rid
	local raid = h.raids[rid]
	h.sres[rid] = h.sres[rid] or {}
	local res = h.sres[rid]

	-- own reserves
	local hdr = S:FontString(page, 11, "OUTLINE", S.media.font, nil, "LEFT")
	hdr:SetPoint("TOPLEFT", 4, -30)
	hdr:SetText("|cff" .. ACC .. format(L["Your reserves for %s (max 2)"], raid.title or rid) .. "|r")
	local mine = res[myName] or {}
	local ey = -50
	for i, it in ipairs(mine) do
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 8, ey)
		fs:SetText(i .. ". " .. it)
		local del = Btn(page, 18, 14, "x")
		del:SetPoint("TOPLEFT", 230, ey - 2)
		del:SetScript("OnClick", function()
			tremove(mine, i)
			res[myName] = #mine > 0 and mine or nil
			Send("SR2|" .. rid .. "|" .. Ser(mine))
			Bump()
			GH:RenderTab("sres")
		end)
		ey = ey - 17
	end
	if #mine < 2 then
		local ed = Edit(page, 220, 16, L["Item name or paste link"])
		ed:SetPoint("TOPLEFT", 8, ey)
		local add = Btn(page, 50, 18, L["Add"])
		add:SetPoint("TOPLEFT", 232, ey - 1)
		add:SetScript("OnClick", function()
			local v = strtrim(ed:GetText() or "")
			local link = v:match("(|Hitem:.-|h%[.-%]|h)") or v:match("(%[.-%])")
			v = link or v
			if v == "" then return end
			mine[#mine + 1] = v
			res[myName] = mine
			Send("SR2|" .. rid .. "|" .. Ser(mine))
			Bump()
			GH:RenderTab("sres")
		end)
		ey = ey - 24
	end
	ey = ey - 8

	-- buff coverage from this raid's signups (classes -> shared raid buffs)
	local COVER = {
		{ "Fort", "PRIEST" }, { "ShadowProt", "PRIEST" }, { "Spirit", "PRIEST" },
		{ "MotW", "DRUID" }, { "AI", "MAGE" }, { "Blessings", "PALADIN" },
		{ "Bloodlust", "SHAMAN" },
	}
	local have = {}
	for who in pairs(h.signups[rid] or {}) do
		local cls = (Roster()[who] or {}).class or (Priv() and Priv().myChars[who] and Priv().myChars[who].class)
		if cls then have[cls] = true end
	end
	local parts = {}
	for _, b in ipairs(COVER) do
		parts[#parts + 1] = have[b[2]] and ("|cff44dd44" .. b[1] .. "|r") or ("|cff884444" .. b[1] .. "|r")
	end
	local cov = S:FontString(page, 10, nil, S.media.font, nil, "LEFT")
	cov:SetPoint("TOPLEFT", 4, ey)
	cov:SetText(L["Buff coverage:"] .. " " .. table.concat(parts, "  "))
	ey = ey - 18
	if CanI("leader") then
		local imp = Btn(page, 130, 18, L["Import wishlist…"])
		imp:SetPoint("TOPLEFT", 4, ey)
		imp:SetScript("OnClick", function() GH:WishlistDialog() end)
		ey = ey - 24
	end
	ey = ey - 4

	-- everybody's reserves
	Header(page, L["All reserves"]):SetPoint("TOPLEFT", 4, ey)
	ey = ey - 18
	local isLead = CanI("leader")
	local rows = {}
	for who, items in pairs(res) do
		local signed = h.signups[rid] and h.signups[rid][who] and h.signups[rid][who].status or nil
		rows[#rows + 1] = { who = who, items = items, signed = signed }
	end
	sort(rows, function(a, b) return a.who < b.who end)
	ListRows(page, ey, 18, min(#rows, 18), function(r, i)
		local m = rows[i]
		if not m then return end
		local sufs = m.signed and ("  |cff777777(" .. m.signed .. ")|r") or "  |cffff8844(" .. L["not signed"] .. ")|r"
		RowFS(r, "who", 8):SetText(ClassColor(m.who) .. sufs)
		RowFS(r, "items", 240):SetText(table.concat(m.items, "  +  "))
		if isLead or m.who == myName then
			local del = Btn(r, 18, 14, "x")
			del:SetPoint("RIGHT", r, "RIGHT", -4, 0)
			del:SetScript("OnClick", function()
				res[m.who] = nil
				if m.who == myName then
					Send("SR2|" .. rid .. "|" .. Ser({}))
				else
					Send("SRX|" .. rid .. "|" .. m.who)
				end
				Bump()
				GH:RenderTab("sres")
			end)
		end
	end)
	if #rows == 0 then
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 8, ey - 20)
		fs:SetText("|cff777777" .. L["Nobody has reserved anything for this raid yet."] .. "|r")
	end
end

-------------------------------------------------------------------------------
-- TAB: Guild chat
-------------------------------------------------------------------------------

GH.chatLog = GH.chatLog or {}

local function ChatLogPush(name, msg, kind)
	local log = GH.chatLog
	log[#log + 1] = { n = name, m = msg, c = kind, t = time() }
	if #log > 120 then tremove(log, 1) end
	GH:MaybeRefresh("gchat")
end
GH._ChatLogPush = ChatLogPush

tabs.gchat = function(self, page)
	local log = GH.chatLog
	local list = {}
	for i = max(1, #log - 26), #log do list[#list + 1] = log[i] end
	local y = -6
	if #list == 0 then
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 8, -10)
		fs:SetText("|cff777777" .. L["Guild chat shows here while the window is open."] .. "|r")
	end
	for i = #list, 1, -1 do
		local m = list[i]
		local fs = S:FontString(page, 11, nil, S.media.font, nil, "LEFT")
		fs:SetPoint("TOPLEFT", 6, y)
		fs:SetWidth(690)
		fs:SetJustifyH("LEFT")
		local tag = m.c == "OFFICER" and "|cffff8844[O]|r " or ""
		fs:SetText(tag .. ClassColor(m.n or "?") .. ": " .. (m.m or ""))
		y = y - 16
	end

	local ed = Edit(page, 620, 20, L["Message"])
	ed:SetPoint("BOTTOMLEFT", 6, 8)
	local snd = Btn(page, 70, 20, L["Send"])
	snd:SetPoint("BOTTOMLEFT", 630, 8)
	local function Go()
		local v = strtrim(ed:GetText() or "")
		if v ~= "" then SendChatMessage(v, "GUILD") ed:SetText("") end
	end
	snd:SetScript("OnClick", Go)
	ed:SetScript("OnEnterPressed", function(e2) Go() e2:ClearFocus() end)
end

-------------------------------------------------------------------------------
-- Discord bridge (DiscordData.lua -> SENTINEL_DISCORD; spec: Tools/api.md)
-------------------------------------------------------------------------------

function GH:ApplyDiscordData(manual)
	local d = SENTINEL_DISCORD
	local h = Shared()
	if not (h and type(d) == "table" and d.ver == 1) then
		if manual then Notify(L["No Discord data found."]) end
		return
	end
	if type(d.stamp) ~= "number" or (h.discordStamp or 0) >= d.stamp then
		if manual then Notify(L["Discord data is already applied."]) end
		return
	end
	h.discordStamp = d.stamp
	local made, signed, lined = 0, 0, 0
	local unknown = {}
	for _, r in ipairs(d.raids or {}) do
		if type(r) == "table" and type(r.id) == "string" and type(r.epoch) == "number" then
			local e = h.raids[r.id]
			if not e then e = {} h.raids[r.id] = e made = made + 1 end
			e.id, e.title = r.id, r.title or e.title or r.id
			e.epoch, e.dur = r.epoch, r.dur or e.dur or 3
			e.status = r.status or e.status or "open"
			e.discord = true
			if type(r.lineup) == "table" then
				e.lineup = e.lineup or {}
				for who, slot in pairs(r.lineup) do
					if slot == "confirmed" or slot == "bench" then
						e.lineup[who] = slot
						lined = lined + 1
					end
				end
			end
		end
	end
	local map = type(d.map) == "table" and d.map or {}
	for rid, list in pairs(d.signups or {}) do
		local raid = h.raids[rid]
		if raid and type(list) == "table" then
			h.signups[rid] = h.signups[rid] or {}
			for _, su in ipairs(list) do
				if type(su) == "table" and type(su.player) == "string" then
					local who = Ambiguate(map[su.player] or su.player, "short")
					local st2 = su.status
					if st2 == "coming" or st2 == "tentative" or st2 == "late" or st2 == "no" then
						local member = IsMember(who)
						if member or su.external then
							local key = member and MainOf(who) or who
							h.signups[rid][key] = {
								status = st2,
								role = (su.role == "T" or su.role == "H") and su.role or "D",
								char = su.char or who,
								note = su.note,
								ext = su.external and true or nil,
								via = "discord",
								t = time(),
							}
							signed = signed + 1
						else
							unknown[who] = true
						end
					end
				end
			end
		end
	end
	Bump()
	Notify(format(L["Discord sync: %d new raid(s), %d signups, %d lineup slots applied."], made, signed, lined))
	if next(unknown) then
		local names = {}
		for w in pairs(unknown) do names[#names + 1] = w end
		sort(names)
		Notify(format(L["Unknown names skipped: %s"], table.concat(names, ", ")))
	end
	GH:MaybeRefresh("signups")
end

-------------------------------------------------------------------------------
-- wishlist import ("Player; Item" per line — TMB-style), leader pushes doc
-------------------------------------------------------------------------------

function GH:WishlistImport(text)
	if not CanI("leader") then
		Notify(L["You need the 'leader' right to import a wishlist."])
		return false
	end
	local h = Shared()
	local n = 0
	for line in (text or ""):gmatch("[^\r\n]+") do
		local who, item = line:match("^%s*(.-)%s*[;,:=\t]%s*(.+)%s*$")
		if who and item and who ~= "" and item ~= "" then
			who = Ambiguate(who, "short")
			h.wish[who] = h.wish[who] or {}
			h.wish[who][#h.wish[who] + 1] = item
			n = n + 1
		end
	end
	if n == 0 then
		Notify(L["No wishlist lines found — one 'Player; Item' per line."])
		return false
	end
	Send("WL|" .. Ser(h.wish))
	Bump()
	Notify(format(L["Imported %d wishlist entries."], n))
	return true
end

function GH:WishlistDialog()
	local f = self.wishIO
	if not f then
		f = CreateFrame("Frame", "SentinelUIGuildWishIO", UIParent, S.BackdropTemplate)
		f:SetSize(480, 340)
		f:SetPoint("CENTER")
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetClampedToScreen(true)
		f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		S:SetTemplate(f, "Default")
		tinsert(UISpecialFrames, "SentinelUIGuildWishIO")
		f.title = S:FontString(f, 13, "OUTLINE", S.media.font, nil, "LEFT")
		f.title:SetPoint("TOPLEFT", 14, -12)
		f.title:SetText("|cff" .. ACC .. L["IMPORT WISHLIST"] .. "|r")
		f.hint = S:FontString(f, 10, nil, S.media.font, nil, "LEFT")
		f.hint:SetPoint("TOPLEFT", 14, -32)
		f.hint:SetWidth(450)
		f.hint:SetText("|cff999999" .. L["One 'Player; Item' per line (works with ; , : = or TAB)."] .. "|r")
		local sf = CreateFrame("ScrollFrame", nil, f)
		sf:SetPoint("TOPLEFT", 14, -56)
		sf:SetPoint("BOTTOMRIGHT", -14, 48)
		sf:EnableMouse(true)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetFontObject("GameFontHighlight")
		eb:SetWidth(440)
		eb:SetHeight(260)
		sf:SetScrollChild(eb)
		eb:SetScript("OnEscapePressed", function(s2) s2:ClearFocus() end)
		sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
		f.eb = eb
		f.imp = W.StaticBtn(f, 140, 20, L["Import"])
		f.imp:SetPoint("BOTTOMLEFT", 14, 14)
		f.imp:SetScript("OnClick", function()
			if GH:WishlistImport(f.eb:GetText()) then f:Hide() GH:RenderTab(GH.tab) end
		end)
		f.close = W.StaticBtn(f, 90, 20, L["Close"])
		f.close:SetPoint("BOTTOMRIGHT", -14, 14)
		f.close:SetScript("OnClick", function() f:Hide() end)
		self.wishIO = f
	end
	f.eb:SetText("")
	f:Show()
	f:Raise()
	f.eb:SetFocus()
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
	local bb = S.GetModule and S:GetModule("ButtonBars")
	if bb and bb.GrabButton and self.minimapBtn:GetParent() == Minimap then
		bb:GrabButton(self.minimapBtn, "SentinelUIMinimapButton_guildhub")
	end
	self.minimapBtn:Show()
end

function GH:Initialize()
	myName = Ambiguate(UnitName("player"), "short")
	GH._SetMyName(myName)
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
	-- equipment/stats snapshot for the member panel + roster iLvl
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() GH:ShareEquip() end)
	self:RegisterEvent("UNIT_MAXHEALTH", function(_, _, u) if u == "player" then GH:ShareEquip() end end)
	GH:Delay(6, GH.ShareEquip, GH)
	GH:Delay(4, GH.ApplyDiscordData, GH)
	GH.users[myName] = GetTime()
	-- guild chat feed for the Guild Chat tab
	self:RegisterEvent("CHAT_MSG_GUILD", function(_, _, msg, sender)
		GH._ChatLogPush(Ambiguate(sender or "", "short"), msg, "GUILD")
	end)
	self:RegisterEvent("CHAT_MSG_OFFICER", function(_, _, msg, sender)
		GH._ChatLogPush(Ambiguate(sender or "", "short"), msg, "OFFICER")
	end)
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
end

function GH:SetupShell()
	if self._shellDone then return end
	self._shellDone = true
	self:UpdateMinimap()
	self:UpdateCTA()
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
		elseif first == "import" then
			GH:ImportTeamsDialog()
		elseif first == "discord" then
			GH:ApplyDiscordData(true)
		elseif first == "focus" then
			-- diagnostic: for 15s print what is under the mouse (frame, type, level, parent chain)
			local last
			local n = 0
			local ticker
			ticker = C_Timer.NewTicker(0.4, function()
				n = n + 1
				local f = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
				local desc = "nil"
				if f and f.GetObjectType then
					local chain, p = {}, f
					while p and #chain < 5 do
						chain[#chain + 1] = (p.GetName and p:GetName()) or p:GetObjectType()
						p = p.GetParent and p:GetParent()
					end
					desc = format("%s lvl %d strata %s  <  %s", f:GetObjectType(), f:GetFrameLevel(), f:GetFrameStrata(), table.concat(chain, " < "))
				end
				if desc ~= last then last = desc Notify("focus: " .. desc) end
				if n >= 38 then ticker:Cancel() end
			end)
			Notify(L["Move the mouse over the control that does not react — the frame under it is printed for 15 seconds."])
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

-------------------------------------------------------------------------------
-- Raid teams: text export / import
--   # comment
--   [Team name | 25]
--   Alice T
--   Bob Healer
--   Randy            (no role: current guild role, else DPS)
-------------------------------------------------------------------------------

local ROLE_WORDS = {
	t = "T", tank = "T", tanks = "T",
	h = "H", heal = "H", healer = "H", heiler = "H",
	d = "D", dd = "D", dps = "D", damage = "D", schaden = "D",
}

local function CleanName(n)
	n = strtrim(n or ""):gsub("%-.*$", "")
	if n:match("^%a+$") then n = n:sub(1, 1):upper() .. n:sub(2):lower() end
	return n
end

function GH:AddExternalToTeam(slot, text)
	local nm, role = (text or ""):match("^%s*([^%s,;:]+)[%s,;:]*(.-)%s*$")
	nm = CleanName(nm)
	if nm == "" then return false end
	local h = Shared()
	if not TeamLive(h.teams[slot]) then
		h.teams[slot] = { name = "Team " .. slot, size = 40, members = {} }
	end
	local t = h.teams[slot]
	t.members = t.members or {}
	local r = ROLE_WORDS[lower(strtrim(role or ""))] or h.roles[nm]
	t.members[nm] = (r == "T" or r == "H" or r == "D") and r or "D"
	SyncTeams()
	return true
end

function GH:BuildTeamsText()
	local h = Shared()
	local lines = { "# SentinelGuild raid teams — " .. date("%Y-%m-%d %H:%M") }
	local rank = { T = 1, H = 2, D = 3 }
	for i = 1, 9 do
		local t = h.teams[i]
		if t and t.name and not t.hidden then
			lines[#lines + 1] = ""
			lines[#lines + 1] = format("[%s | %d]", t.name, t.size or 40)
			local names = {}
			for nm in pairs(t.members or {}) do names[#names + 1] = nm end
			sort(names, function(a, b)
				local ra, rb = rank[t.members[a]] or 4, rank[t.members[b]] or 4
				if ra ~= rb then return ra < rb end
				return a < b
			end)
			for _, nm in ipairs(names) do lines[#lines + 1] = nm .. " " .. (t.members[nm] or "D") end
		end
	end
	return table.concat(lines, "\n")
end

-- returns { {name=, size=, members={}} ... }, ignoredLines
function GH:ParseTeamsText(text)
	local h = Shared()
	local out, cur, ignored = {}, nil, 0
	for line in (text or ""):gmatch("[^\r\n]+") do
		line = strtrim(line)
		if line == "" or line:sub(1, 1) == "#" then
			-- skip
		elseif line:sub(1, 1) == "[" then
			local body = line:match("^%[(.-)%]") or line:sub(2)
			local nm, sz = body:match("^(.-)%s*|%s*(%d+)%s*$")
			cur = { name = strtrim(nm or body), size = tonumber(sz) or 40, members = {} }
			if cur.name == "" then cur.name = "Team " .. (#out + 1) end
			out[#out + 1] = cur
		elseif cur then
			local nm, role = line:match("^([^%s,;:]+)[%s,;:]*(.-)$")
			nm = CleanName(nm)
			if nm ~= "" then
				local r = ROLE_WORDS[lower(strtrim(role or ""))] or h.roles[nm] or "D"
				if r == "N" then r = "D" end
				cur.members[nm] = r
			else
				ignored = ignored + 1
			end
		else
			ignored = ignored + 1
		end
	end
	return out, ignored
end

function GH:ImportTeams(text, replace)
	if not (CanI("teams") or CanI("leader")) then
		Notify(L["You need the 'build teams' right to import."])
		return false
	end
	local list, ignored = self:ParseTeamsText(text)
	if #list == 0 then
		Notify(L["No teams found — start each team with a [Name | size] line."])
		return false
	end
	local h = Shared()
	local slots = {}
	for i = 1, 9 do
		if replace or not h.teams[i] or h.teams[i].hidden or not h.teams[i].name then slots[#slots + 1] = i end
	end
	local used = 0
	for idx, t in ipairs(list) do
		local slot = slots[idx]
		if not slot then break end
		h.teams[slot] = { name = t.name, size = t.size, members = t.members }
		used = used + 1
	end
	if replace then
		-- slots that vanish are blanked (hidden), so the removal reaches everyone
		for k = used + 1, 9 do
			if h.teams[k] then h.teams[k] = { name = "Team " .. k, size = 40, members = {}, hidden = true } end
		end
	end
	Bump()
	Send("T|" .. Ser(h.teams))
	Notify(format(L["Imported %d teams."], used))
	if #list > used then Notify(format(L["%d teams skipped (only 9 slots)."], #list - used)) end
	GH.bldState = GH.bldState or {}
	GH.bldState.sel = 1
	GH:RenderTab(GH.tab)
	return true
end

function GH:TeamsDialog(mode)
	local f = self.teamsIO
	if not f then
		f = CreateFrame("Frame", "SentinelUIGuildTeamsIO", UIParent, S.BackdropTemplate)
		f:SetSize(500, 400)
		f:SetPoint("CENTER")
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetClampedToScreen(true)
		f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		S:SetTemplate(f, "Default")
		tinsert(UISpecialFrames, "SentinelUIGuildTeamsIO")
		f.title = S:FontString(f, 13, "OUTLINE", S.media.font, nil, "LEFT")
		f.title:SetPoint("TOPLEFT", 14, -12)
		f.hint = S:FontString(f, 10, nil, S.media.font, nil, "LEFT")
		f.hint:SetPoint("TOPLEFT", 14, -32)
		f.hint:SetWidth(470)
		f.hint:SetWordWrap(true)
		f.hint:SetTextColor(0.6, 0.6, 0.65)
		local sf = CreateFrame("ScrollFrame", nil, f)
		sf:SetPoint("TOPLEFT", 14, -62)
		sf:SetPoint("BOTTOMRIGHT", -14, 48)
		sf:EnableMouse(true)
		sf:EnableMouseWheel(true)
		local bg = CreateFrame("Frame", nil, f, S.BackdropTemplate)
		bg:SetPoint("TOPLEFT", sf, -4, 4)
		bg:SetPoint("BOTTOMRIGHT", sf, 4, -4)
		bg:SetFrameLevel(f:GetFrameLevel() + 1)
		S:SetTemplate(bg, "Default")
		sf:SetFrameLevel(bg:GetFrameLevel() + 1)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetFontObject("GameFontHighlight")
		eb:SetWidth(460)
		eb:SetHeight(300)
		eb:SetMaxLetters(0)
		sf:SetScrollChild(eb)
		eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
		eb:SetScript("OnTextChanged", function(s)
			local n = select(2, (s:GetText() or ""):gsub("\n", "\n")) + 1
			s:SetHeight(max(300, n * 14 + 10))
		end)
		sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
		sf:SetScript("OnMouseWheel", function(s, d)
			local v = s:GetVerticalScroll() - d * 28
			s:SetVerticalScroll(max(0, min(s:GetVerticalScrollRange(), v)))
		end)
		f.eb = eb
		f.close = W.StaticBtn(f, 90, 20, L["Close"])
		f.close:SetPoint("BOTTOMRIGHT", -14, 14)
		f.close:SetScript("OnClick", function() f:Hide() end)
		f.replace = W.StaticBtn(f, 150, 20, L["Import: replace all"])
		f.replace:SetPoint("BOTTOMLEFT", 14, 14)
		f.replace:SetScript("OnClick", function()
			if GH:ImportTeams(f.eb:GetText(), true) then f:Hide() end
		end)
		f.add = W.StaticBtn(f, 150, 20, L["Import: add as new"])
		f.add:SetPoint("LEFT", f.replace, "RIGHT", 6, 0)
		f.add:SetScript("OnClick", function()
			if GH:ImportTeams(f.eb:GetText(), false) then f:Hide() end
		end)
		f.copy = S:FontString(f, 10, nil, S.media.font, nil, "LEFT")
		f.copy:SetPoint("BOTTOMLEFT", 14, 18)
		f.copy:SetTextColor(0.6, 0.6, 0.65)
		self.teamsIO = f
	end
	local exporting = mode ~= "import"
	f.title:SetText("|cff" .. ACC .. (exporting and L["EXPORT RAID TEAMS"] or L["IMPORT RAID TEAMS"]) .. "|r")
	f.hint:SetText(L["Format: a [Team name | size] line starts a team, then one 'Name Role' per line (Role: T, H or D). Lines starting with # are ignored."])
	f.replace:SetShown(not exporting)
	f.add:SetShown(not exporting)
	f.copy:SetShown(exporting)
	f.copy:SetText(L["Ctrl+C copies the selected text."])
	f.eb:SetText(exporting and self:BuildTeamsText() or "")
	f:Show()
	f:Raise()
	f.eb:SetFocus()
	if exporting then f.eb:HighlightText() end
end

function GH:ExportTeams() self:TeamsDialog("export") end
function GH:ImportTeamsDialog() self:TeamsDialog("import") end

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
