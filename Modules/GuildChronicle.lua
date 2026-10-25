-- GuildChronicle: guild roster history. Snapshots the roster on every update
-- and diffs it against the stored state: joins, leaves, promotions, demotions,
-- level ups, note / officer note changes, rank renames and returning members.
-- Tracks join dates, main/alt groups, former members, inactivity and feeds a
-- login summary, chat announcements, unit tooltips and an export.
local _, ns = ...
local S = ns.S
local L = S.L
local GC = S:NewModule("GuildChronicle", "guildchronicle")
ns.GuildChronicle = GC

local _G = _G
local ipairs, pairs, sort, wipe, tinsert, tremove = ipairs, pairs, sort, wipe, table.insert, table.remove
local format, floor, min, max = string.format, math.floor, math.min, math.max
local time, date = time, date
local strlower, strmatch, strfind, gsub, tostring, tonumber = string.lower, string.match, string.find, string.gsub, tostring, tonumber
local pcall, type = pcall, type
local IsSecret = S.IsSecret

GC.maxLog = 2000
GC.maxFormer = 500

-- log entry types -> colour (chat/UI)
GC.TYPES = {
	join = { 0.3, 0.9, 0.4 }, rejoin = { 0.3, 0.9, 0.8 }, leave = { 0.95, 0.35, 0.35 }, kick = { 1, 0.2, 0.2 },
	promote = { 1, 0.85, 0.2 }, demote = { 1, 0.55, 0.2 }, level = { 0.6, 0.8, 1 }, note = { 0.8, 0.8, 0.85 },
	onote = { 0.7, 0.7, 0.95 }, rank = { 0.9, 0.7, 1 }, alt = { 0.75, 0.9, 0.75 }, name = { 1, 0.6, 0.9 },
}

-- ---------------------------------------------------------------------------
-- storage: SentinelUIGuildDB[realm][guild] = { members, former, log, ranks, lastScan, lastLogin }
-- ---------------------------------------------------------------------------
local function Realm()
	local r = GetRealmName and GetRealmName() or "?"
	return (r:gsub("%s+", ""))
end

function GC:GuildName()
	local name = GetGuildInfo("player")
	if IsSecret(name) then return nil end
	return name
end

function GC:Data()
	if type(SentinelUIGuildDB) ~= "table" then SentinelUIGuildDB = {} end
	local guild = self:GuildName()
	if not guild then return nil end
	local realm = Realm()
	local db = SentinelUIGuildDB
	db[realm] = db[realm] or {}
	db[realm][guild] = db[realm][guild] or {}
	local d = db[realm][guild]
	d.members = d.members or {}
	d.former = d.former or {}
	d.log = d.log or {}
	d.ranks = d.ranks or {}
	d.notes = d.notes or {} -- own, local notes per player
	return d
end

local function ShortName(name)
	if not name or IsSecret(name) then return nil end
	return (strmatch(name, "^([^%-]+)")) or name
end
GC.ShortName = ShortName

-- "x years, y months, z days, h hours" ago -> approximate seconds
local function LastOnlineSeconds(years, months, days, hours)
	if IsSecret(years) or IsSecret(months) or IsSecret(days) or IsSecret(hours) then return 0 end
	return ((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 86400 + (hours or 0) * 3600
end

function GC:ColoredName(name, classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name or "?") end
	return name or "?"
end

function GC:TypeColor(kind)
	local c = self.TYPES[kind] or { 0.8, 0.8, 0.8 }
	return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

function GC:DateText(ts)
	if not ts or ts == 0 then return L["unknown"] end
	return date(self.db.dateFormat == "us" and "%m/%d/%Y" or self.db.dateFormat == "iso" and "%Y-%m-%d" or "%d.%m.%Y", ts)
end

function GC:DaysAgoText(sec)
	if not sec then return "?" end
	local d = floor(sec / 86400)
	if d < 1 then return L["today"] end
	if d == 1 then return L["yesterday"] end
	if d < 60 then return format(L["%d days"], d) end
	if d < 365 then return format(L["%d months"], floor(d / 30)) end
	return format(L["%.1f years"], d / 365)
end

-- ---------------------------------------------------------------------------
-- log
-- ---------------------------------------------------------------------------
function GC:AddLog(kind, name, text, extra)
	local d = self:Data()
	if not d then return end
	local e = { t = GetServerTime and GetServerTime() or time(), k = kind, n = name, x = text }
	if extra then for k, v in pairs(extra) do e[k] = v end end
	tinsert(d.log, e)
	while #d.log > self.maxLog do tremove(d.log, 1) end
	self.sessionChanges = self.sessionChanges or {}
	self.sessionChanges[kind] = (self.sessionChanges[kind] or 0) + 1
	if self.announcing and self.db.announce[kind] ~= false then
		self:Print(self:FormatLog(e))
	end
	if self.frame and self.frame:IsShown() then self:RefreshFrame() end
end

function GC:FormatLog(e, plain)
	local m = self:Data() and (self:Data().members[e.n] or self:Data().former[e.n])
	local name = plain and (e.n or "?") or self:ColoredName(e.n, m and m.class)
	local label = L["gc_" .. e.k] or e.k
	local text = e.x or ""
	if plain then return format("[%s] %s: %s %s", date("%Y-%m-%d %H:%M", e.t or 0), label, name, text) end
	return format("%s%s|r %s %s", self:TypeColor(e.k), label, name, text)
end

-- ---------------------------------------------------------------------------
-- roster scan
-- ---------------------------------------------------------------------------
local NOTE_ALT_PATTERNS = {
	"^alt of (%a+)", "^alt:%s*(%a+)", "^alt%s+(%a+)", "^twink von (%a+)", "^twink:%s*(%a+)", "^main:%s*(%a+)",
	"^main (%a+)", "^(%a+)'s alt", "^(%a+)s twink", "^%((%a+)%)$", "^%[(%a+)%]$", "^(%a+)$",
}

-- "Main: Bob" / "alt of Bob" / "(Bob)" -> "Bob" when Bob is a member
local function MainFromNote(note, members)
	if not note or note == "" or IsSecret(note) then return nil end
	local lower = strlower(note)
	for _, p in ipairs(NOTE_ALT_PATTERNS) do
		local cand = strmatch(lower, p)
		if cand then
			cand = cand:sub(1, 1):upper() .. cand:sub(2)
			if members[cand] then return cand end
		end
	end
end

function GC:ScanRoster(reason)
	local d = self:Data()
	if not d or not IsInGuild() then return end
	local num = GetNumGuildMembers()
	if IsSecret(num) or not num or num == 0 then return end
	-- only trust a full roster (offline members included); a filtered view
	-- would look like everyone offline just left the guild
	if GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then return end

	local now = GetServerTime and GetServerTime() or time()
	local seen = {}
	local first = next(d.members) == nil
	local ranks = {}
	for i = 1, (GuildControlGetNumRanks and GuildControlGetNumRanks() or 10) do
		local ok, rn = pcall(GuildControlGetRankName, i)
		if ok and rn and rn ~= "" and not IsSecret(rn) then ranks[i - 1] = rn end
	end
	-- rank renames
	if next(d.ranks) then
		for idx, rn in pairs(ranks) do
			if d.ranks[idx] and d.ranks[idx] ~= rn and not first then
				self:AddLog("rank", rn, format(L["rank %d renamed from '%s'"], idx + 1, d.ranks[idx]))
			end
		end
	end
	d.ranks = ranks

	for i = 1, num do
		local fullName, rankName, rankIndex, level, _, zone, note, onote, online, _, classFile = GetGuildRosterInfo(i)
		local name = ShortName(fullName)
		if name and not IsSecret(rankIndex) and not IsSecret(level) then
			seen[name] = true
			local y, mo, da, h = GetGuildRosterLastOnline(i)
			local offlineFor = online and 0 or LastOnlineSeconds(y, mo, da, h)
			local lastOnline = online and now or (now - offlineFor)
			if IsSecret(note) then note = nil end
			if IsSecret(onote) then onote = nil end
			if IsSecret(rankName) then rankName = ranks[rankIndex] end
			local m = d.members[name]
			if not m then
				local f = d.former[name]
				m = { joined = now, firstSeen = now, rank = rankIndex, rankName = rankName, level = level, class = classFile,
					note = note, onote = onote, lastOnline = lastOnline, main = f and f.main or nil, alts = f and f.alts or nil }
				if f then
					m.joined = now
					m.prevJoined = f.joined
					m.timesJoined = (f.timesJoined or 1) + 1
					d.former[name] = nil
				end
				d.members[name] = m
				if not first then
					if f then
						self:AddLog("rejoin", name, format(L["rejoined (left %s)"], self:DateText(f.left)))
					else
						self:AddLog("join", name, format(L["joined as %s (lvl %d)"], rankName or "?", level or 0))
					end
				elseif first then
					-- very first scan: join date unknown, keep a flag so the UI shows "~"
					m.joinedApprox = true
				end
			else
				if m.rank ~= rankIndex then
					if rankIndex < m.rank then
						self:AddLog("promote", name, format(L["promoted %s -> %s"], m.rankName or "?", rankName or "?"), { from = m.rankName, to = rankName })
					else
						self:AddLog("demote", name, format(L["demoted %s -> %s"], m.rankName or "?", rankName or "?"), { from = m.rankName, to = rankName })
					end
					m.rankChanged = now
					m.rank, m.rankName = rankIndex, rankName
				elseif m.rankName ~= rankName then
					m.rankName = rankName
				end
				if level and m.level and level > m.level then
					if self.db.trackLevels and (level == 60 or level == 70 or level == 80 or level % 10 == 0 or self.db.everyLevel) then
						self:AddLog("level", name, format(L["reached level %d"], level))
					end
					m.level = level
				elseif level then
					m.level = level
				end
				if note ~= m.note and (note or m.note) then
					if self.db.trackNotes then self:AddLog("note", name, format(L["note: '%s' -> '%s'"], m.note or "", note or "")) end
					m.note = note
				end
				if onote ~= m.onote and (onote or m.onote) and (CanViewOfficerNote == nil or CanViewOfficerNote()) then
					if self.db.trackNotes then self:AddLog("onote", name, format(L["officer note: '%s' -> '%s'"], m.onote or "", onote or "")) end
					m.onote = onote
				end
				m.class = classFile or m.class
				if lastOnline > (m.lastOnline or 0) then m.lastOnline = lastOnline end
			end
			m.online = online and true or nil
			m.zone = online and not IsSecret(zone) and zone or nil
			-- alt detection from notes
			if self.db.altsFromNotes and not m.main and not m.mainLocked then
				local cand = MainFromNote(note, d.members) or MainFromNote(onote, d.members)
				if cand and cand ~= name then m.main = cand m.autoMain = true end
			end
		end
	end

	-- leavers
	for name, m in pairs(d.members) do
		if not seen[name] then
			m.left = now
			m.online = nil
			d.former[name] = m
			d.members[name] = nil
			-- kicked vs left: resolved by the system message handler within a few seconds
			local kind = self.pendingKicks and self.pendingKicks[name] and "kick" or "leave"
			if self.pendingKicks then self.pendingKicks[name] = nil end
			self:AddLog(kind, name, format(L["%s (was %s, lvl %d, joined %s)"], kind == "kick" and L["removed"] or L["has left"], m.rankName or "?", m.level or 0, self:DateText(m.joined)))
			-- detach alts
			for _, o in pairs(d.members) do if o.main == name then o.main = nil end end
		end
	end
	local n = 0
	for _ in pairs(d.former) do n = n + 1 end
	if n > self.maxFormer then
		local list = {}
		for nm, f in pairs(d.former) do list[#list + 1] = { nm, f.left or 0 } end
		sort(list, function(a, b) return a[2] < b[2] end)
		for i = 1, n - self.maxFormer do d.former[list[i][1]] = nil end
	end

	d.lastScan = now
	self:ProfsFromNotes()
	if first then
		self:Print(format(L["Guild roster recorded: %d members. Changes are tracked from now on."], num))
	end
	self.scanned = true
	if self.frame and self.frame:IsShown() then self:RefreshFrame() end
end

-- ---------------------------------------------------------------------------
-- system messages: who got removed (vs. left on their own), name changes
-- ---------------------------------------------------------------------------
-- converts a Blizzard format string into a capture pattern; returns the
-- pattern plus the argument index of each capture in order of appearance
-- (handles %s / %d as well as ordered captures like %1$s / %2$d)
local function Pattern(fmt)
	if not fmt then return nil end
	local order = {}
	fmt = gsub(fmt, "%%(%d*)%$?([sd])", function(num)
		order[#order + 1] = tonumber(num) or (#order + 1)
		return "\2"
	end)
	fmt = gsub(fmt, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	fmt = gsub(fmt, "\2", "(.-)")
	return "^" .. fmt .. "$", order
end

function GC:OnSystemMessage(msg)
	if not msg or IsSecret(msg) then return end
	local removedPat, removedOrder = Pattern(_G.ERR_GUILD_REMOVE_SS)
	if removedPat then
		local caps = { strmatch(msg, removedPat) }
		if caps[1] then
			-- the removed member is the 2nd format arg (1st is the kicker)
			local who
			for i, idx in ipairs(removedOrder) do if idx == 2 then who = caps[i] break end end
			self.pendingKicks = self.pendingKicks or {}
			self.pendingKicks[ShortName(who or caps[1])] = true
			S.GuildRoster()
			return
		end
	end
	for _, key in ipairs({ "ERR_GUILD_REMOVE_SELF", "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS" }) do
		local p = Pattern(_G[key])
		if p and strmatch(msg, p) then S.GuildRoster() return end
	end
end

-- ---------------------------------------------------------------------------
-- alt management
-- ---------------------------------------------------------------------------
function GC:SetMain(alt, main)
	local d = self:Data()
	if not d or not d.members[alt] then return end
	if main and main ~= alt and not d.members[main] then self:Print(format(L["%s is not a guild member."], main)) return end
	local m = d.members[alt]
	if main then
		-- flatten: main of a main is the main
		local mm = d.members[main]
		if mm and mm.main then main = mm.main end
		m.main, m.autoMain, m.mainLocked = main, nil, true
		-- anyone who had `alt` as main moves to the new main
		for n, o in pairs(d.members) do if o.main == alt and n ~= main then o.main = main end end
		self:AddLog("alt", alt, format(L["linked as alt of %s"], main))
	else
		m.main, m.autoMain, m.mainLocked = nil, nil, true
		self:AddLog("alt", alt, L["alt link removed"])
	end
	self:RefreshFrame()
end

-- main name + sorted list of alts of a member (whichever is passed)
function GC:AltGroup(name)
	local d = self:Data()
	if not d then return name, {} end
	local m = d.members[name]
	local main = m and m.main or name
	local alts = {}
	for n, o in pairs(d.members) do
		if o.main == main and n ~= main then alts[#alts + 1] = n end
	end
	sort(alts)
	return main, alts
end

-- ---------------------------------------------------------------------------
-- queries
-- ---------------------------------------------------------------------------
function GC:Inactive(days)
	local d = self:Data()
	if not d then return {} end
	local now = GetServerTime and GetServerTime() or time()
	local limit = (days or self.db.inactiveDays or 30) * 86400
	local list = {}
	for n, m in pairs(d.members) do
		if not m.online and m.lastOnline and now - m.lastOnline >= limit then
			-- an alt whose main is active does not count (option)
			local main = m.main and d.members[m.main]
			if not (self.db.inactiveIgnoreAltsOfActive and main and (main.online or (now - (main.lastOnline or 0)) < limit)) then
				list[#list + 1] = { name = n, m = m, idle = now - m.lastOnline }
			end
		end
	end
	sort(list, function(a, b) return a.idle > b.idle end)
	return list
end

function GC:LoginSummary()
	local d = self:Data()
	if not d or not d.lastLogin then return end
	local since = d.lastLogin
	local counts, n = {}, 0
	for _, e in ipairs(d.log) do
		if e.t and e.t > since then counts[e.k] = (counts[e.k] or 0) + 1 n = n + 1 end
	end
	if n == 0 then return end
	local parts = {}
	for _, k in ipairs({ "join", "rejoin", "leave", "kick", "promote", "demote", "level", "note", "onote", "rank" }) do
		if counts[k] then parts[#parts + 1] = format("%s%d %s|r", self:TypeColor(k), counts[k], L["gc_" .. k] or k) end
	end
	self:Print(format(L["Since your last login (%s): %s"], self:DateText(since), table.concat(parts, ", ")) .. " |cff888888/gc|r")
end

-- ---------------------------------------------------------------------------
-- professions: the classic client has no API for other players' trades, so
-- three sources are merged: (1) SentinelUI users broadcast their own skills
-- via addon message, (2) trade links posted in guild/officer chat (clickable
-- -> opens the recipe list), (3) profession names found in notes.
-- members[name].profs[profName] = { skill, max, link, t, src }
-- ---------------------------------------------------------------------------
local PREFIX = "SUIGChron"
-- profession spell ids -> localized names via the spell book
local PROF_SPELLS = { 2259, 2018, 7411, 4036, 2366, 25229, 2108, 2575, 8613, 3908, 2550, 3273, 7620, 45357 }
local profNames -- { [lowerName] = displayName }

local function ProfNames()
	if profNames then return profNames end
	profNames = {}
	for _, id in ipairs(PROF_SPELLS) do
		local n = S.GetSpellInfo(id)
		if n and not IsSecret(n) then profNames[strlower(n)] = n end
	end
	-- "Herb Gathering" is listed as "Herbalism" in the skill frame on most clients
	if HERBALISM then profNames[strlower(HERBALISM)] = HERBALISM end
	return profNames
end

local function IsProfName(name)
	return name and ProfNames()[strlower(name)] ~= nil
end

function GC:SetProf(member, prof, skill, max, link, src)
	local d = self:Data()
	local m = d and d.members[member]
	if not m or not prof then return end
	m.profs = m.profs or {}
	local cur = m.profs[prof]
	-- chat links beat note guesses; a newer skill value wins
	if cur and cur.src == "link" and src == "note" then return end
	m.profs[prof] = { skill = skill or (cur and cur.skill), max = max or (cur and cur.max), link = link or (cur and cur.link),
		t = GetServerTime and GetServerTime() or time(), src = src }
	if self.frame and self.frame:IsShown() and self.tab == "profs" then self:RefreshFrame() end
end

-- own skills from the skill frame (classic) or GetProfessions (wrath+)
function GC:OwnProfessions()
	local out = {}
	if GetProfessions and GetProfessionInfo then
		for _, idx in ipairs({ GetProfessions() }) do
			if idx then
				local name, _, rank, maxRank = GetProfessionInfo(idx)
				if name and not IsSecret(name) then out[#out + 1] = { name = name, skill = rank, max = maxRank } end
			end
		end
	elseif GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
			if name and not isHeader and not IsSecret(name) and IsProfName(name) then
				out[#out + 1] = { name = ProfNames()[strlower(name)] or name, skill = rank, max = maxRank }
			end
		end
	end
	return out
end

function GC:BroadcastProfessions()
	if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	local me = ShortName(UnitName("player"))
	local parts = {}
	for _, p in ipairs(self:OwnProfessions()) do
		local link = self.ownLinks and self.ownLinks[p.name] or ""
		parts[#parts + 1] = format("%s:%d:%d:%s", p.name, p.skill or 0, p.max or 0, link)
		self:SetProf(me, p.name, p.skill, p.max, link ~= "" and link or nil, "self")
	end
	if #parts == 0 then return end
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, "P\t" .. table.concat(parts, "\t"), "GUILD")
end

function GC:OnAddonMessage(prefix, msg, _, sender)
	if prefix ~= PREFIX or not msg or IsSecret(msg) then return end
	local name = ShortName(sender)
	if not name or name == ShortName(UnitName("player")) then return end
	local kind, rest = strmatch(msg, "^(%u)\t(.*)$")
	if kind == "P" then
		for entry in (rest .. "\t"):gmatch("(.-)\t") do
			local pname, skill, max, link = strmatch(entry, "^([^:]+):(%d+):(%d+):(.*)$")
			if pname then self:SetProf(name, pname, tonumber(skill), tonumber(max), link ~= "" and link or nil, "sync") end
		end
	elseif kind == "R" then
		-- someone asks for professions -> answer after a small random delay
		self:Delay(1 + math.random() * 4, self.BroadcastProfessions, self)
	end
end

-- trade links in guild chat: |Htrade:...|h[Alchemy]|h  (classic carries
-- skill/max inside the link data, retail does not)
function GC:OnGuildChat(msg, sender)
	if not msg or IsSecret(msg) or not strfind(msg, "|Htrade:", 1, true) then return end
	local name = ShortName(sender)
	if not name then return end
	for link, text in msg:gmatch("(|Htrade:[^|]+|h%[([^%]]+)%]|h)") do
		local prof = ProfNames()[strlower(text)] or text
		local skill, max = strmatch(link, "^|Htrade:%d+:(%d+):(%d+):")
		self:SetProf(name, prof, tonumber(skill), tonumber(max), link, "link")
	end
end

-- own trade window open -> remember a clickable link for broadcasting
function GC:OnOwnTradeSkill()
	local link = GetTradeSkillListLink and GetTradeSkillListLink()
	if not link or IsSecret(link) then return end
	local text = strmatch(link, "%[([^%]]+)%]")
	local prof = text and (ProfNames()[strlower(text)] or text)
	if not prof then return end
	self.ownLinks = self.ownLinks or {}
	if self.ownLinks[prof] ~= link then
		self.ownLinks[prof] = link
		self:Delay(3, self.BroadcastProfessions, self)
	end
end

-- profession names mentioned in public / officer notes
function GC:ProfsFromNotes()
	local d = self:Data()
	if not d or not self.db.profsFromNotes then return end
	local names = ProfNames()
	for member, m in pairs(d.members) do
		local text = strlower((m.note or "") .. " " .. (m.onote or ""))
		if text ~= " " then
			for lower, display in pairs(names) do
				if strfind(text, lower, 1, true) and not (m.profs and m.profs[display]) then
					self:SetProf(member, display, nil, nil, nil, "note")
				end
			end
		end
	end
end

-- { { prof = name, members = { {name, m, p}, ... } }, ... } sorted
function GC:ProfessionGroups()
	local d = self:Data()
	if not d then return {} end
	local groups = {}
	for member, m in pairs(d.members) do
		for prof, p in pairs(m.profs or {}) do
			groups[prof] = groups[prof] or {}
			tinsert(groups[prof], { name = member, m = m, p = p })
		end
	end
	local list = {}
	for prof, members in pairs(groups) do
		sort(members, function(a, b)
			if (a.p.skill or 0) ~= (b.p.skill or 0) then return (a.p.skill or 0) > (b.p.skill or 0) end
			return strlower(a.name) < strlower(b.name)
		end)
		list[#list + 1] = { prof = prof, members = members }
	end
	sort(list, function(a, b) return strlower(a.prof) < strlower(b.prof) end)
	return list
end

-- "Alchemy 375, Tailoring 300" (sorted, skill when known)
function GC:ProfText(m, withLinks)
	if not m or not m.profs or not next(m.profs) then return nil end
	local parts = {}
	for prof, p in pairs(m.profs) do
		local label = (withLinks and p.link) and p.link or prof
		parts[#parts + 1] = p.skill and format("%s %d", label, p.skill) or label
	end
	sort(parts)
	return table.concat(parts, ", ")
end

function GC:RequestProfessions()
	if C_ChatInfo and C_ChatInfo.SendAddonMessage and IsInGuild() then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, "R\t", "GUILD")
	end
end

-- ---------------------------------------------------------------------------
-- export
-- ---------------------------------------------------------------------------
function GC:ExportRoster()
	local d = self:Data()
	if not d then return "" end
	local lines = { "name;rank;rankIndex;level;class;joined;lastOnline;main;professions;note;officerNote" }
	local names = {}
	for n in pairs(d.members) do names[#names + 1] = n end
	sort(names)
	for _, n in ipairs(names) do
		local m = d.members[n]
		lines[#lines + 1] = table.concat({ n, m.rankName or "", tostring(m.rank or ""), tostring(m.level or ""), m.class or "",
			m.joined and date("%Y-%m-%d", m.joined) or "", m.lastOnline and date("%Y-%m-%d", m.lastOnline) or "",
			m.main or "", (self:ProfText(m) or ""):gsub(";", ","), (m.note or ""):gsub(";", ","), (m.onote or ""):gsub(";", ",") }, ";")
	end
	return table.concat(lines, "\n")
end

function GC:ExportLog(filter)
	local d = self:Data()
	if not d then return "" end
	local lines = {}
	for _, e in ipairs(d.log) do
		if not filter or filter == "all" or e.k == filter then lines[#lines + 1] = self:FormatLog(e, true) end
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- unit tooltip: join date, main/alts, last change
-- ---------------------------------------------------------------------------
function GC:TooltipUnit(tip, unit)
	if not self.db.tooltip or not unit or not UnitIsPlayer(unit) then return end
	local d = self:Data()
	if not d then return end
	local guild = GetGuildInfo(unit)
	if IsSecret(guild) or guild ~= self:GuildName() then return end
	local name = ShortName(UnitName(unit))
	local m = name and d.members[name]
	if not m then return end
	tip:AddLine(" ")
	tip:AddDoubleLine(L["Joined"], (m.joinedApprox and "~" or "") .. self:DateText(m.joined), 0.6, 0.8, 1, 1, 1, 1)
	local main, alts = self:AltGroup(name)
	if main ~= name then
		tip:AddDoubleLine(L["Main"], self:ColoredName(main, d.members[main] and d.members[main].class), 0.6, 0.8, 1, 1, 1, 1)
	elseif #alts > 0 then
		local parts = {}
		for i = 1, min(#alts, 6) do parts[#parts + 1] = self:ColoredName(alts[i], d.members[alts[i]].class) end
		if #alts > 6 then parts[#parts + 1] = "+" .. (#alts - 6) end
		tip:AddDoubleLine(L["Alts"], table.concat(parts, " "), 0.6, 0.8, 1, 1, 1, 1)
	end
	if m.rankChanged then tip:AddDoubleLine(L["Rank since"], self:DateText(m.rankChanged), 0.6, 0.8, 1, 1, 1, 1) end
	local profs = self:ProfText(m)
	if profs then tip:AddDoubleLine(L["Professions"], profs, 0.6, 0.8, 1, 1, 1, 1) end
	local own = d.notes[name]
	if own and own ~= "" then tip:AddLine(format("|cff%s%s:|r %s", S.accentHex, L["Chronicle note"], own), 1, 1, 1, true) end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------
function GC:RequestScan()
	if not IsInGuild() then return end
	-- full roster needed (offline included); restore the user's view
	-- afterwards. Skip the toggle while the Blizzard guild frame is open -
	-- flipping the filter while the user looks at the list blanks it out
	-- until the next roster update arrives
	if GetGuildRosterShowOffline and not GetGuildRosterShowOffline()
		and not (GuildFrame and GuildFrame:IsShown()) then
		self.restoreOffline = true
		SetGuildRosterShowOffline(true)
	end
	S.GuildRoster(true) -- forced: the view/flag may have just changed
end

function GC:GUILD_ROSTER_UPDATE()
	if not IsInGuild() then return end
	self:ScanRoster("update")
	if self.restoreOffline and self.scanned then
		self.restoreOffline = nil
		-- give Blizzard's own frame a moment, then put the toggle back
		self:Delay(2, function()
			if GetGuildRosterShowOffline and GetGuildRosterShowOffline() and not (GuildFrame and GuildFrame:IsShown()) then
				SetGuildRosterShowOffline(false)
			end
		end)
	end
	if not self.announcing then
		-- first update of the session has been consumed -> announce from now on
		self.announcing = true
		self:LoginSummary()
		local d = self:Data()
		if d then d.lastLogin = GetServerTime and GetServerTime() or time() end
	end
end

function GC:Initialize()
	self.db = S.db.profile.guildchronicle
	self.db.announce = self.db.announce or {}
	if not IsInGuild() then
		self:RegisterEvent("PLAYER_GUILD_UPDATE", function() if IsInGuild() then GC:Initialize() end end)
		return
	end
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function()
		-- new members broadcast on their own; poke everyone else too so late
		-- joiners get picked up without waiting for the 15s login ping
		if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
			GC._lastProfReq = GC._lastProfReq or 0
			if GetTime() - GC._lastProfReq > 20 then
				GC._lastProfReq = GetTime()
				pcall(C_ChatInfo.SendAddonMessage, PREFIX, "R	", "GUILD")
			end
		end
	end)
	self:RegisterEvent("PLAYER_GUILD_UPDATE", function() GC:Delay(1, GC.RequestScan, GC) end)
	-- the Blizzard guild frame loads on demand; if it opens while the roster
	-- cache is empty (throttled earlier request got eaten), force a refresh
	local function HookGuildFrame()
		if not (GuildFrame and not self.guildFrameHooked) then return end
		self.guildFrameHooked = true
		GuildFrame:HookScript("OnShow", function()
			if (GetNumGuildMembers and GetNumGuildMembers() or 0) == 0 then
				S.GuildRoster(true)
			end
		end)
	end
	if IsAddOnLoaded and IsAddOnLoaded("Blizzard_GuildUI") then
		HookGuildFrame()
	else
		self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_GuildUI" then HookGuildFrame() end
		end)
	end
	self:RegisterEvent("CHAT_MSG_SYSTEM", function(_, _, msg) GC:OnSystemMessage(msg) end)
	-- professions
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
	self:RegisterEvent("CHAT_MSG_ADDON", function(_, _, prefix, msg, dist, sender) GC:OnAddonMessage(prefix, msg, dist, sender) end)
	self:RegisterEvent("CHAT_MSG_GUILD", function(_, _, msg, sender) GC:OnGuildChat(msg, sender) end)
	self:RegisterEvent("CHAT_MSG_OFFICER", function(_, _, msg, sender) GC:OnGuildChat(msg, sender) end)
	pcall(self.RegisterEvent, self, "TRADE_SKILL_SHOW", function() GC:OnOwnTradeSkill() end)
	pcall(self.RegisterEvent, self, "CRAFT_SHOW", function() GC:OnOwnTradeSkill() end)
	self:RegisterEvent("SKILL_LINES_CHANGED", function()
		if GC.skillTimer then return end
		GC.skillTimer = true
		GC:Delay(10, function() GC.skillTimer = nil GC:BroadcastProfessions() end)
	end)
	self:Delay(15, function() GC:BroadcastProfessions() GC:RequestProfessions() GC:ProfsFromNotes() end)
	if GameTooltip and GameTooltip.HookScript and TooltipDataProcessor == nil then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tip)
			local _, unit = tip:GetUnit()
			S:SafeCall("GuildChronicle:Tooltip", GC.TooltipUnit, GC, tip, unit)
		end)
	elseif TooltipDataProcessor and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
			if tip ~= GameTooltip then return end
			local _, unit = tip:GetUnit()
			S:SafeCall("GuildChronicle:Tooltip", GC.TooltipUnit, GC, tip, unit)
		end)
	end
	-- periodic rescan keeps last-online and level data fresh
	self:Delay(8, self.RequestScan, self)
	self.ticker = C_Timer.NewTicker(300, function() GC:RequestScan() end)
	if self.db.minimapButton then self:CreateMinimapBtn() end
	S:RegisterChatCommand("gc", function(msg) GC:Slash(msg) end)
	S:RegisterChatCommand("chronicle", function(msg) GC:Slash(msg) end)
end

function GC:Update()
	self.db = S.db.profile.guildchronicle
	if self.db.minimapButton then self:CreateMinimapBtn() elseif self.minimapBtn then self.minimapBtn:Hide() end
	if self.minimapBtn and self.db.minimapButton then self.minimapBtn:Show() end
	self:RefreshFrame()
end

function GC:Slash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "scan" then self:RequestScan() self:Print(L["Roster scan requested."])
	elseif msg == "inactive" then self:Toggle("inactive")
	elseif msg == "log" then self:Toggle("log")
	elseif msg == "former" then self:Toggle("former")
	elseif msg == "alts" then self:Toggle("alts")
	elseif msg == "profs" or msg == "professions" then self:Toggle("profs")
	elseif msg == "export" then self:ExportDialog("roster")
	elseif msg == "config" then S:ToggleConfig("guildchronicle")
	elseif msg == "help" or msg == "?" then
		self:Print("/gc  |cffaaaaaa" .. L["toggle window"] .. "|r  -  /gc scan|log|former|inactive|alts|export|config")
	else self:Toggle("roster") end
end

function GC:CreateMinimapBtn()
	if self.minimapBtn then return end
	S.db.global.guildChronicle = S.db.global.guildChronicle or {}
	S.db.global.guildChronicle.minimap = S.db.global.guildChronicle.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "GuildChronicle",
		glyph = "GC",
		angle = 160,
		store = S.db.global.guildChronicle.minimap,
		onLeft = function() GC:Toggle() end,
		onRight = function() S:ToggleConfig("guildchronicle") end,
		tooltip = function()
			local tip = GameTooltip
			tip:AddLine("|cff" .. S.accentHex .. "SentinelUI|r " .. L["Guild Chronicle"])
			local d = GC:Data()
			if d then
				local n, on = 0, 0
				for _, m in pairs(d.members) do n = n + 1 if m.online then on = on + 1 end end
				tip:AddDoubleLine(L["Members"], format("%d (%d %s)", n, on, L["online"]), 0.7, 0.7, 0.7, 1, 1, 1)
				local inactive = GC:Inactive()
				tip:AddDoubleLine(format(L["Inactive > %d days"], GC.db.inactiveDays or 30), tostring(#inactive), 0.7, 0.7, 0.7, 1, 1, 1)
			end
			tip:AddLine(" ")
			tip:AddLine(L["Left-click: toggle window"], 0.6, 0.8, 1)
			tip:AddLine(L["Right-click: settings"], 0.6, 0.8, 1)
		end,
	})
end
