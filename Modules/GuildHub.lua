-- GuildHub: guild suite with a grouped-sidebar window (Guild / Raids / PvP /
-- Rules / Admin / Settings). Shared data travels over the guild addon channel
-- and is validated against the guild roster. Nothing is written to officer
-- notes; each client keeps a full copy under SentinelUIGuildDB[realm][guild].hub
local _, ns = ...
local S = ns.S
local L = S.L
local GH = S:NewModule("GuildHub", "guildhub")

local _G = _G
local ipairs, pairs, wipe, tinsert, tremove, sort, tonumber, tostring, type = ipairs, pairs, wipe, table.insert, table.remove, table.sort, tonumber, tostring, type
local format, lower, upper, strtrim, gmatch, find = string.format, string.lower, string.upper, strtrim, string.gmatch, string.find
local min, max, floor, time, date = math.min, math.max, math.floor, time, date
local CreateFrame, GetTime, InCombatLockdown, IsInGuild = CreateFrame, GetTime, InCombatLockdown, IsInGuild
local UnitName, UnitLevel, GetRealmName, IsInGroup, IsInRaid = UnitName, UnitLevel, GetRealmName, IsInGroup, IsInRaid
local Ambiguate, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo = Ambiguate, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo
local GameTooltip = GameTooltip
local IsSecret = S.IsSecret

local PREFIX = "SUIGHB"
local VERSION = 1

local myName, myRealm

local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = { T = { 0, 19, 22, 41 }, H = { 20, 39, 1, 20 }, D = { 20, 39, 22, 41 } }
local ROLE_NAME = { T = L["Tank"], H = L["Healer"], D = L["DPS"], N = L["No role"] }
local ROLE_ORDER = { "T", "H", "D", "N" }
local function RoleIcon(role, size)
	local c = ROLE_COORDS[role]
	if not c then return "" end
	size = size or 14
	return format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", ROLE_TEX, size, size, c[1], c[2], c[3], c[4])
end

-------------------------------------------------------------------------------
-- shared document
-------------------------------------------------------------------------------

local function Shared()
	local guild = GetGuildInfo and GetGuildInfo("player")
	if not guild then return nil end
	local realm = GetRealmName() or "?"
	SentinelUIGuildDB = SentinelUIGuildDB or {}
	SentinelUIGuildDB[realm] = SentinelUIGuildDB[realm] or {}
	local g = SentinelUIGuildDB[realm]
	g[guild] = g[guild] or {}
	local d = g[guild]
	d.hub = d.hub or {}
	local h = d.hub
	h.roles = h.roles or {}
	h.altDecl = h.altDecl or {}       -- alt -> main (declared by the alt)
	h.mainDecl = h.mainDecl or {}     -- main -> { [alt]=true } (confirmed by the main)
	h.perms = h.perms or { ranks = {}, grants = {}, membersCanRole = true, bountyChan = "#bounties" }
	h.raids = h.raids or {}
	h.signups = h.signups or {}
	h.att = h.att or {}
	h.teams = h.teams or {}
	h.bounties = h.bounties or {}
	h.excom = h.excom or {}
	h.gbank = h.gbank or {}
	h.crafts = h.crafts or {}
	h.loot = h.loot or {}
	h.layers = h.layers or {}
	h.attun = h.attun or {}
	h.profs = h.profs or {}
	h.rosterSnap = h.rosterSnap or {}
	h.ver = h.ver or 0
	return h
end

local function Priv()
	local h = Shared()
	if not h then return nil end
	h.local_ = h.local_ or {}
	local p = h.local_
	p.blacklist = p.blacklist or {}
	p.myChars = p.myChars or {}
	p.settings = p.settings or {}
	return p
end

-------------------------------------------------------------------------------
-- serializer
-------------------------------------------------------------------------------

local function Ser(v)
	local t = type(v)
	if t == "number" then return "n" .. v
	elseif t == "boolean" then return v and "b1" or "b0"
	elseif t == "string" then return "s" .. #v .. ":" .. v
	elseif t == "table" then
		local p = {}
		for k, vv in pairs(v) do
			local ks, vs = Ser(k), Ser(vv)
			if ks and vs then p[#p + 1] = ks .. vs end
		end
		return "{" .. table.concat(p) .. "}"
	end
end

local function Unser(s, i)
	i = i or 1
	local c = s:sub(i, i)
	if c == "n" then
		local j = i + 1
		while j <= #s and s:sub(j, j):match("[0-9.eE%+%-]") do j = j + 1 end
		return tonumber(s:sub(i + 1, j - 1)), j
	elseif c == "b" then
		return s:sub(i + 1, i + 1) == "1", i + 2
	elseif c == "s" then
		local e = find(s, ":", i + 1, true)
		local len = tonumber(s:sub(i + 1, e - 1)) or 0
		return s:sub(e + 1, e + len), e + len + 1
	elseif c == "{" then
		local t = {}
		i = i + 1
		while i <= #s and s:sub(i, i) ~= "}" do
			local k, v
			k, i = Unser(s, i)
			v, i = Unser(s, i)
			t[k] = v
		end
		return t, i + 1
	end
	return nil, i + 1
end

-------------------------------------------------------------------------------
-- roster access
-------------------------------------------------------------------------------

-- roster: live API merged over a persisted snapshot (offline members keep
-- their data once seen); professions ride in h.profs via addon sync
local rosterCache, rosterAt
local function Roster(force)
	local h = Shared()
	if h then
		h.rosterSnap = h.rosterSnap or {}
		h.profs = h.profs or {}
	end
	if rosterCache and not force and GetTime() - rosterAt < 10 then return rosterCache end
	local r = {}
	if h then
		for name, m in pairs(h.rosterSnap) do
			r[name] = { rank = m.rank, rankName = m.rankName, level = m.level, class = m.class,
				lastOnline = m.lastOnline, online = false, profs = h.profs[name] }
		end
	end
	if GetNumGuildMembers and GetGuildRosterInfo then
		local now = time()
		for i = 1, GetNumGuildMembers() do
			local name, rankName, rankIdx, level, classLoc, zone, note, onote, online, _, classFile = GetGuildRosterInfo(i)
			if name then
				local short = Ambiguate(name, "short")
				if IsSecret(short) then short = name end
				local e = r[short] or {}
				r[short] = e
				e.rank, e.rankName, e.level = rankIdx, rankName, level
				e.online = online and true or false
				e.zone = (not IsSecret(zone)) and zone or nil
				e.class = classFile or e.class
				e.note = (not IsSecret(note)) and note or nil
				e.onote = (not IsSecret(onote)) and onote or nil
				e.lastOnline = online and now or e.lastOnline
				if h then
					h.rosterSnap[short] = { rank = rankIdx, rankName = rankName, level = level,
						class = e.class, lastOnline = e.lastOnline }
				end
			end
		end
	end
	if h then for name in pairs(h.profs or {}) do local e = r[name] if e then e.profs = h.profs[name] end end end
	rosterCache, rosterAt = r, GetTime()
	return r
end

local function IsMember(name) return name and (Roster()[name] ~= nil or name == myName) end
local function OnlineOf(name) local e = name and Roster()[name] return e and e.online or name == myName end
local function IsGM(name) local e = name and Roster()[name] return e and e.rank == 0 end

local function HasRight(name, right) -- roles,teams,bounty,mbounty,excom,leader
	local h = Shared()
	if not h or not name then return false end
	if IsGM(name) then return true end
	local bits = h.perms.grants[name] or ""
	local e = Roster()[name]
	if e and h.perms.ranks[e.rank] then bits = bits .. h.perms.ranks[e.rank] end
	return bits:find(";" .. right .. ";", 1, true) ~= nil
end
local function CanI(right) return HasRight(myName, right) end

local function AltStatus(char) -- "linked"|"alt"(pending), main
	local h = Shared()
	if not h then return nil end
	if h.altDecl[char] then
		local m = h.altDecl[char]
		if h.mainDecl[m] and h.mainDecl[m][char] then return "linked", m end
		return "alt", m
	end
	return nil
end

local function MainOf(char)
	local st, m = AltStatus(char)
	return m or char
end

local function AltsOf(main)
	local h = Shared()
	local out = {}
	for alt, m in pairs(h.altDecl or {}) do
		if m == main then out[#out + 1] = alt end
	end
	sort(out)
	return out
end

-------------------------------------------------------------------------------
-- comm layer
-------------------------------------------------------------------------------

local function Send(msg, chan, target)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	if #msg <= 250 then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, chan or "GUILD", target)
	else
		local n = math.ceil(#msg / 240)
		for i = 1, n do
			pcall(C_ChatInfo.SendAddonMessage, PREFIX, "C|" .. i .. "/" .. n .. "|" .. msg:sub((i - 1) * 240 + 1, i * 240), chan or "GUILD", target)
		end
	end
end

local function Bump() local h = Shared() if h then h.ver = (h.ver or 0) + 1 end end
local function Notify(text) GH:Print("|cff" .. (S.accentHex or "ffcc00") .. "[Guild]|r " .. text) end
-- broadcast-driven notices (other people's raids/bounties/requests) honour the "Chat notices" setting
local function Notice(text)
	local p = Priv()
	if p and p.settings.chatNotices == false then return end
	Notify(text)
end

local appliers = {}
local inbox = {}

local function OnComm(_, _, prefix, msg, dist, sender)
	if prefix ~= PREFIX or type(msg) ~= "string" then return end
	if IsSecret and IsSecret(msg) then return end
	sender = Ambiguate(sender or "", "short")
	if sender == myName or not IsMember(sender) then return end
	local kind, rest = msg:match("^(%a+)|(.*)$")
	if not kind then return end
	if kind == "C" then
		local id, tot, chunk = rest:match("^(%d+)/(%d+)|(.*)$")
		id, tot = tonumber(id), tonumber(tot)
		if id and tot and chunk then
			local box = inbox[sender] or {}
			inbox[sender] = box
			box[id] = chunk
			local n = 0 for _ in pairs(box) do n = n + 1 end
			if n >= tot then
				local full = ""
				for i = 1, tot do full = full .. (box[i] or "") end
				inbox[sender] = nil
				local k2, r2 = full:match("^(%a+)|(.*)$")
				if k2 and appliers[k2] then appliers[k2](r2, sender) end
			end
		end
		return
	end
	if appliers[kind] then appliers[kind](rest, sender) end
end

-------------------------------------------------------------------------------
-- record appliers (validated by right / ownership)
-------------------------------------------------------------------------------

appliers.R = function(rest, sender)          -- role: "R|<role>"
	local role = rest:match("^([THDN])")
	if not role then return end
	local h = Shared()
	if h.roles[sender] ~= role then
		h.roles[sender] = role Bump()
		GH:MaybeRefresh("roster")
	end
end

appliers.M = function(rest, sender)          -- alt declares: "M|<main>"
	local main = strtrim(rest or "")
	if main == "" or main == sender or not IsMember(main) then return end
	local h = Shared()
	if h.altDecl[sender] ~= main then h.altDecl[sender] = main Bump() end
end

appliers.MC = function(rest, sender)         -- main confirms: "MC|<alt>"
	local alt = strtrim(rest or "")
	if alt == "" or alt == sender then return end
	local h = Shared()
	h.mainDecl[sender] = h.mainDecl[sender] or {}
	if not h.mainDecl[sender][alt] then h.mainDecl[sender][alt] = true Bump() end
end

appliers.P = function(rest, sender)          -- perms doc (GM): "P|<ser>"
	if not IsGM(sender) then return end
	local t = Unser(rest)
	if type(t) == "table" and t.ranks then
		Shared().perms = t Bump()
		GH:MaybeRefresh("manager")
	end
end

appliers.F = function(rest, sender)          -- full doc: "F|<ser>"
	local t = Unser(rest)
	if type(t) ~= "table" or type(t.ver) ~= "number" then return end
	local h = Shared()
	if (t.ver or 0) > (h.ver or 0) then
		for k, v in pairs(t) do if k ~= "local_" then h[k] = v end end
		if GH.frame and GH.frame:IsShown() then GH:RenderTab(GH.tab) end
	end
end

appliers.Q = function(_, sender)             -- full doc request
	GH:Delay(1 + math.random() * 4, function()
		local h = Shared()
		if h and (h.ver or 0) > 0 then Send("F|" .. Ser(h)) end
	end)
end

appliers.V = function(rest, sender)          -- hello: "V|<ver>|<docver>"
	local v, dv = rest:match("^(%d+)|(%d+)")
	v, dv = tonumber(v), tonumber(dv)
	local h = Shared()
	if h and dv and dv > (h.ver or 0) then Send("Q|") end
	if v and v > VERSION and not GH._verNotified then
		GH._verNotified = true
		Notify(format(L["%s runs a newer GuildHub version — consider updating."], sender))
	end
end

appliers.PF = function(rest, sender)
	local t = Unser(rest)
	if type(t) == "table" then
		Shared().profs[sender] = t Bump()
		GH:MaybeRefresh("profs")
	end
end

appliers.ATN = function(rest, sender)       -- attunements: "ATN|<ser {char->{key=1}}>"
	local t = Unser(rest)
	if type(t) == "table" then
		local h = Shared()
		for char, keys in pairs(t) do h.attun[char] = keys end
		GH:MaybeRefresh("chars")
	end
end

appliers.Y = function(rest, sender)          -- layer: "Y|<zone>|<layer>"
	local z, l = rest:match("^(.-)|(%d+)$")
	if not z then return end
	Shared().layers[sender] = { z = z, l = tonumber(l), t = time() }
	GH:MaybeRefresh("layers")
end

GH.gf = {}                                   -- sender -> group finder state
appliers.F1 = function(rest, sender)         -- "F1|<roleflags>|<lvl>|<d1,d2>"
	local rf, lvl, list = rest:match("^(%u*)|(%d+)|(.*)$")
	if not rf then return end
	local dgn = {}
	for d in gmatch(list, "[^,]+") do dgn[d] = true end
	GH.gf[sender] = { roles = { T = rf:find("T") ~= nil, H = rf:find("H") ~= nil, D = rf:find("D") ~= nil },
		lvl = tonumber(lvl), dgns = dgn, t = GetTime() }
	GH:MaybeRefresh("finder")
end

GH.bgf = {}                                  -- sender -> bg finder state
appliers.F2 = function(rest, sender)         -- "F2|<heal?>|<bg1,bg2>"
	local heal, list = rest:match("^(%d)|(.*)$")
	local bgs = {}
	for b in gmatch(list or "", "[^,]+") do bgs[b] = true end
	GH.bgf[sender] = { heal = heal == "1", bgs = bgs, t = GetTime() }
	GH:MaybeRefresh("bgf")
end

appliers.E = function(rest, sender)          -- raid event: "E|<ser>" (leader)
	if not HasRight(sender, "leader") then return end
	local r = Unser(rest)
	if type(r) == "table" and r.id then
		Shared().raids[r.id] = r Bump()
		Notice(format(L["Raid updated: %s"], r.title or r.id))
		GH:MaybeRefresh("signups")
	end
end

appliers.ED = function(rest, sender)         -- delete raid
	if not HasRight(sender, "leader") then return end
	local h = Shared()
	local id = strtrim(rest)
	if h.raids[id] then
		h.raids[id], h.signups[id] = nil, nil Bump()
		Notice(format(L["Raid deleted: %s"], id))
		GH:MaybeRefresh("signups")
	end
end

appliers.U = function(rest, sender)          -- signup (own char): "U|<rid>|<st>|<role>|<char>|<note>"
	local rid, st, role, char, note = rest:match("^(.-)|(.-)|(.-)|(.-)|(.*)$")
	if not rid then return end
	local h = Shared()
	if not h.raids[rid] then return end
	h.signups[rid] = h.signups[rid] or {}
	local player = MainOf(sender)
	h.signups[rid][player] = { status = st, role = role, char = char ~= "" and char or sender,
		note = note ~= "" and note or nil, t = time() }
	Bump()
	GH:MaybeRefresh("signups")
end

appliers.LU = function(rest, sender)         -- lineup (leader): "LU|<rid>|<player>|<slot|clear>"
	if not HasRight(sender, "leader") then return end
	local rid, player, slot = rest:match("^(.-)|(.-)|(.-)$")
	local h = Shared()
	local r = rid and h.raids[rid]
	if not r or not player then return end
	r.lineup = r.lineup or {}
	if slot == "clear" then r.lineup[player] = nil else r.lineup[player] = slot end
	Bump()
	GH:MaybeRefresh("signups")
end

appliers.AT = function(rest, sender)         -- attendance: "AT|<rid>|<ser>" (leader)
	if not HasRight(sender, "leader") then return end
	local rid, ser = rest:match("^(.-)|(.*)$")
	local t = ser and Unser(ser)
	if rid and type(t) == "table" then
		local h = Shared()
		h.att[rid] = h.att[rid] or {}
		for p, m in pairs(t) do h.att[rid][p] = m end
		Bump()
		GH:MaybeRefresh("att")
	end
end

appliers.T = function(rest, sender)          -- teams doc (builders): "T|<ser>"
	if not (HasRight(sender, "teams") or HasRight(sender, "leader")) then return end
	local t = Unser(rest)
	if type(t) == "table" then
		local h = Shared()
		for k, v in pairs(t) do h.teams[k] = v end
		Bump()
		GH:MaybeRefresh("teams")
	end
end

appliers.B = function(rest, sender)          -- bounty: "B|<ser>" (posters)
	if not HasRight(sender, "bounty") then return end
	local b = Unser(rest)
	if type(b) == "table" and b.id then
		Shared().bounties[b.id] = b Bump()
		Notice(format(L["New bounty on %s (%sg)"], b.target or "?", b.gold or 0))
		GH:MaybeRefresh("bounties")
	end
end

appliers.BC = function(rest, sender)         -- claim: "BC|<id>"
	local id = strtrim(rest)
	local h = Shared()
	local b = h.bounties[id]
	if b and not b.claimer and sender ~= b.poster then
		b.claimer, b.claimT = sender, time() Bump()
		Notice(format(L["%s claimed the bounty on %s"], sender, b.target or "?"))
		GH:MaybeRefresh("bounties")
	end
end

appliers.BV = function(rest, sender)         -- verdict: "BV|<id>|<v>" (managers; never own claim)
	if not HasRight(sender, "mbounty") then return end
	local id, verdict = rest:match("^(.-)|(.-)$")
	local h = Shared()
	local b = h.bounties and h.bounties[id]
	if b and b.claimer and (IsGM(sender) or b.claimer ~= sender) then
		b.verdict = verdict Bump()
		GH:MaybeRefresh("bounties")
	end
end

appliers.BD = function(rest, sender)         -- delete bounty
	if not HasRight(sender, "mbounty") then return end
	Shared().bounties[strtrim(rest)] = nil Bump()
	GH:MaybeRefresh("bounties")
end

appliers.X = function(rest, sender)          -- excom: "X|<name>|<reason>"
	if not HasRight(sender, "excom") then return end
	local name, reason = rest:match("^(.-)|(.*)$")
	name = strtrim(name or "")
	if name == "" then return end
	Shared().excom[name] = { reason = strtrim(reason or ""), by = sender, t = time() } Bump()
	Notice(format(L["%s was excommunicated."], name))
	GH:MaybeRefresh("excom")
end

appliers.XD = function(rest, sender)
	if not HasRight(sender, "excom") then return end
	Shared().excom[strtrim(rest)] = nil Bump()
	GH:MaybeRefresh("excom")
end

appliers.GB = function(rest, sender)         -- gbank tab: "GB|<tab>|<gold>|<ser>"
	local tab, gold, ser = rest:match("^(%d+)|(%d+)|(.*)$")
	tab = tonumber(tab)
	if not tab then return end
	local items = ser and Unser(ser)
	if type(items) ~= "table" then return end
	local h = Shared()
	h.gbank[tab] = { items = items, by = sender, t = time() }
	h.gbankGold = tonumber(gold) or h.gbankGold
	Bump()
	GH:MaybeRefresh("gbank")
end

appliers.CR = function(rest, sender)         -- craft request: "CR|<ser>"
	local c = Unser(rest)
	if type(c) ~= "table" or not c.id then return end
	local h = Shared()
	local mine = 0
	for _, e in pairs(h.crafts) do if e.char == sender and not e.done then mine = mine + 1 end end
	if mine >= 5 then return end
	c.char = sender
	h.crafts[c.id] = c Bump()
	Notice(format(L["Craft request: %s x%d from %s"], c.item or "?", c.qty or 1, sender))
	GH:MaybeRefresh("profs")
end

appliers.CCD = function(rest, sender)        -- "CCD|<id>|<d?>"
	local id, flag = rest:match("^(.-)|(%a?)$")
	local h = Shared()
	local c = h.crafts and h.crafts[id]
	if c and (c.char == sender or IsGM(sender)) then
		if flag == "d" then c.done = true else h.crafts[id] = nil end
		Bump()
		GH:MaybeRefresh("profs")
	end
end

appliers.CCC = function(rest, sender)        -- crafter claims: "CCC|<id>"
	local id = strtrim(rest)
	local h = Shared()
	local c = h.crafts and h.crafts[id]
	if c and not c.claimer and sender ~= c.char then
		c.claimer = sender Bump()
		Notice(format(L["%s will craft %s for %s"], sender, c.item or "?", c.char or "?"))
		GH:MaybeRefresh("profs")
	end
end

appliers.CTA = function(rest, sender)        -- call to arms
	local zone, x, y, note = rest:match("^(.-)|(.-)|(.-)|(.*)$")
	if not zone then return end
	local p = Priv()
	if p and p.settings.ctaAlerts == false then return end
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame,
			format("%s: %s — %s %s", L["Call to Arms"], sender, zone, (note and note ~= "") and ("(" .. note .. ")") or ""),
			{ r = 1, g = 0.2, b = 0.2 })
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
	Notify(format(L["Call to Arms from %s: %s %s"], sender, zone, (note and note ~= "") and note or ""))
	local inInst = IsInInstance and select(1, IsInInstance())
	if not inInst and p and p.settings.ctaPin ~= false then
		local nx, ny = tonumber(x), tonumber(y)
		if nx and ny and nx > 0 then
			local nav = S.GetModule and S:GetModule("Navigation")
			if nav and nav.SetUserWaypoint then pcall(nav.SetUserWaypoint, nav, zone, nx, ny, "CTA: " .. sender) end
		end
	end
end

appliers.LA = function(rest, sender)         -- loot edit + audit (leader)
	if not HasRight(sender, "leader") then return end
	local t = Unser(rest)
	if type(t) ~= "table" then return end
	local h = Shared()
	if t.audit then
		h.lootAudit = h.lootAudit or {}
		tinsert(h.lootAudit, t.audit)
		if #h.lootAudit > 300 then tremove(h.lootAudit, 1) end
	end
	if t.i then
		for _, e in ipairs(h.loot) do
			if e.item == t.i and e.char == t.who and e.t == t.t2 then e.disp = t.disp end
		end
	end
	Bump()
	GH:MaybeRefresh("loot")
end

appliers.LI = function(rest, sender)         -- loot record (leader): "LI|<ser>"
	if not HasRight(sender, "leader") then return end
	local r = Unser(rest)
	if type(r) == "table" and r.item then
		local h = Shared()
		h.loot[#h.loot + 1] = r
		if #h.loot > 600 then tremove(h.loot, 1) end
		Bump()
		GH:MaybeRefresh("loot")
	end
end

-------------------------------------------------------------------------------
-- window shell
-------------------------------------------------------------------------------

local NAV = {
	{ group = L["Guild"], items = {
		{ "finder", L["Group Finder"] }, { "gbank", L["Guild Bank"] }, { "roster", L["Guild Roster"] },
		{ "layers", L["Layers"] }, { "chars", L["My Characters"] }, { "profs", L["Professions"] },
		{ "builder", L["Raid Builder"] }, { "teams", L["Raid Groups"] },
	} },
	{ group = L["Raids"], items = {
		{ "att", L["Attendance"] }, { "loot", L["Loot History"] }, { "signups", L["Raid Signups"] },
	} },
	{ group = L["PvP"], items = {
		{ "bgf", L["BG Finder"] }, { "bounties", L["Bounties"] }, { "mbounties", L["Manage Bounties"] },
	} },
	{ group = L["Rules"], items = {
		{ "excom", L["Excommunication"] },
	} },
	{ group = L["Admin"], items = {
		{ "manager", L["Guild Manager"] },
	} },
	{ group = "", items = {
		{ "settings", L["Settings"] },
	} },
}

local WIN_W, WIN_H, WIN_MIN_W, WIN_MIN_H = 900, 620, 780, 500
local SIDEBAR_W = 148

local function BuildWindow()
	if GH.frame then return GH.frame end
	local f = CreateFrame("Frame", "SentinelUIGuildHub", UIParent, S.BackdropTemplate)
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
	if f.SetResizeBounds then f:SetResizeBounds(WIN_MIN_W, WIN_MIN_H, 1600, 1200) end
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SkinFrame(f, "Default")
	tinsert(UISpecialFrames, "SentinelUIGuildHub")

	-- header band: title + guild, gold rule underneath
	f.head = CreateFrame("Frame", nil, f)
	f.head:SetPoint("TOPLEFT", 0, 0)
	f.head:SetPoint("TOPRIGHT", 0, 0)
	f.head:SetHeight(44)
	f.head.bg = f.head:CreateTexture(nil, "BACKGROUND")
	f.head.bg:SetAllPoints()
	f.head.bg:SetColorTexture(0.05, 0.05, 0.07, 0.9)
	f.rule = f.head:CreateTexture(nil, "ARTWORK")
	f.rule:SetPoint("BOTTOMLEFT")
	f.rule:SetPoint("BOTTOMRIGHT")
	f.rule:SetHeight(1)
	f.rule:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.9)

	f.title = S:FontString(f.head, 14, "OUTLINE", S.media.font, nil, "LEFT")
	f.title:SetPoint("LEFT", 14, 0)
	f.title:SetText("|cff" .. (S.accentHex or "ffcc00") .. "SENTINEL|r GUILD")
	f.sub = S:FontString(f.head, 11, nil, S.media.font, nil, "LEFT")
	f.sub:SetPoint("LEFT", f.title, "RIGHT", 10, -1)
	f.sub:SetTextColor(0.55, 0.55, 0.6)
	f.sub:SetText(GetGuildInfo and GetGuildInfo("player") or "")

	local close = CreateFrame("Button", nil, f.head)
	close:SetSize(30, 30)
	close:SetPoint("RIGHT", -8, 0)
	close.fs = S:FontString(close, 13, "OUTLINE", S.media.font, nil, "CENTER")
	close.fs:SetPoint("CENTER")
	close.fs:SetText("x")
	close.fs:SetTextColor(0.6, 0.6, 0.6)
	close:SetScript("OnClick", function() f:Hide() end)
	close:SetScript("OnEnter", function() close.fs:SetTextColor(1, 0.4, 0.4) end)
	close:SetScript("OnLeave", function() close.fs:SetTextColor(0.6, 0.6, 0.6) end)

	-- resize grip
	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(16, 16)
	f.grip:SetPoint("BOTTOMRIGHT", -3, 3)
	f.grip.tex = f.grip:CreateTexture(nil, "OVERLAY")
	f.grip.tex:SetAllPoints()
	f.grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	f.grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() GH:SaveSize() end)

	-- sidebar: own dark panel
	f.side = CreateFrame("Frame", nil, f, S.BackdropTemplate)
	f.side:SetPoint("TOPLEFT", 8, -52)
	f.side:SetPoint("BOTTOMLEFT", 8, 8)
	f.side:SetWidth(SIDEBAR_W + 12)
	S:SetTemplate(f.side, "Default")
	f.sideRows = {}
	local y = 10
	for _, grp in ipairs(NAV) do
		if grp.group ~= "" then
			local gh = S:FontString(f.side, 9, "OUTLINE", S.media.font, nil, "LEFT")
			gh:SetPoint("TOPLEFT", 12, -y)
			gh:SetText(upper(grp.group))
			gh:SetTextColor(0.5, 0.45, 0.25)
			y = y + 17
		end
		for _, item in ipairs(grp.items) do
			local key, label = item[1], item[2]
			local b = CreateFrame("Button", nil, f.side)
			b:SetPoint("TOPLEFT", 8, -y)
			b:SetSize(SIDEBAR_W - 4, 19)
			b.bg = b:CreateTexture(nil, "BACKGROUND")
			b.bg:SetAllPoints()
			b.bg:SetColorTexture(1, 1, 1, 0)
			b.bar = b:CreateTexture(nil, "OVERLAY")
			b.bar:SetPoint("TOPLEFT", -4, 0)
			b.bar:SetSize(2, 19)
			b.bar:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0)
			b.fs = S:FontString(b, 11, nil, S.media.font, nil, "LEFT")
			b.fs:SetPoint("LEFT", 8, 0)
			b.fs:SetText(label)
			b.fs:SetTextColor(0.72, 0.72, 0.75)
			b.key = key
			b:SetScript("OnClick", function() GH:SelectTab(key) end)
			b:SetScript("OnEnter", function()
				if GH.tab ~= key then b.bg:SetColorTexture(1, 1, 1, 0.06) end
			end)
			b:SetScript("OnLeave", function()
				b.bg:SetColorTexture(1, 1, 1, GH.tab == key and 0.07 or 0)
			end)
			f.sideRows[key] = b
			y = y + 20
		end
		y = y + 8
	end

	-- version tag bottom of sidebar
	f.ver = S:FontString(f.side, 9, nil, S.media.font, nil, "LEFT")
	f.ver:SetPoint("BOTTOMLEFT", 12, 8)
	f.ver:SetText("|cff555544v" .. VERSION .. "|r")

	-- content: inset panel
	f.content = CreateFrame("Frame", nil, f, S.BackdropTemplate)
	f.content:SetPoint("TOPLEFT", f.side, "TOPRIGHT", 6, 0)
	f.content:SetPoint("BOTTOMRIGHT", -8, 8)
	S:SetTemplate(f.content, "Default")
	f.content.inner = CreateFrame("Frame", nil, f.content)
	f.content.inner:SetPoint("TOPLEFT", 10, -8)
	f.content.inner:SetPoint("BOTTOMRIGHT", -10, 8)

	f:Hide()
	GH.frame = f
	GH.tab = "roster"
	return f
end

function GH:SaveSize()
	local p = Priv()
	if p and self.frame then
		local w, h = self.frame:GetSize()
		p.settings.winW, p.settings.winH = floor(w + 0.5), floor(h + 0.5)
	end
end

function GH:IsShown(key)
	return self.frame and self.frame:IsShown() and self.tab == key
end

function GH:MaybeRefresh(key)
	if self:IsShown(key) then self:RenderTab(key) end
end

function GH:SelectTab(key)
	BuildWindow()
	if self.W then self.W.refocus = nil end
	self.tab = key
	for k, b in pairs(self.frame.sideRows) do
		local active = k == key
		b.bar:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, active and 1 or 0)
		b.bg:SetColorTexture(1, 1, 1, active and 0.07 or 0)
		b.fs:SetTextColor(active and 1 or 0.72, active and 1 or 0.72, active and 0.95 or 0.75)
	end
	self:RenderTab(key)
end

function GH:RenderTab(key)
	local f = self.frame
	if not f then return end
	if f.page then f.page:Hide() f.page = nil end
	if self.W then self.W.ReleaseAll() end
	local page = CreateFrame("Frame", nil, f.content.inner)
	page:SetAllPoints()
	f.page = page
	local fn = self.tabs and self.tabs[key]
	if fn then
		if not Shared() then
			local fs = S:FontString(page, 12, nil, S.media.font, nil, "LEFT")
			fs:SetPoint("TOPLEFT", 8, -8)
			fs:SetText("|cff888888" .. L["You are not in a guild."] .. "|r")
		else
			S:SafeCall("GuildHub:" .. key, fn, self, page)
		end
	end
	if self.W then self.W.refocus = nil end
end

function GH:Toggle()
	local f = BuildWindow()
	if f:IsShown() then f:Hide() return end
	local p = Priv()
	if p then
		local w, h2 = tonumber(p.settings.winW), tonumber(p.settings.winH)
		if w and h2 then f:SetSize(max(WIN_MIN_W, w), max(WIN_MIN_H, h2)) end
	end
	f:Show()
	self:SelectTab(self.tab or "roster")
end


-- expose internals to GuildHubUI.lua
GH._Shared, GH._Priv, GH._Roster = Shared, Priv, Roster
GH._Send, GH._Bump, GH._Notify = Send, Bump, Notify
GH._IsMember, GH._OnlineOf, GH._IsGM = IsMember, OnlineOf, IsGM
GH._HasRight, GH._CanI = HasRight, CanI
GH._AltStatus, GH._MainOf, GH._AltsOf = AltStatus, MainOf, AltsOf
GH._RoleIcon, GH._RoleName = RoleIcon, function(r) return ROLE_NAME[r] end
GH._Ser, GH._Unser = Ser, Unser
GH._appliers = appliers
function GH._GetMyName() return myName end
function GH._SetMyName(n) myName = n end


GH._VERSION = VERSION
function GH:OnCommRaw(prefix, msg, dist, sender)
	OnComm(nil, nil, prefix, msg, dist, sender)
end
