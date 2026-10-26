-- Blessing manager for paladins: class blessing assignments, aura/seal
-- picks, missing-buff tracking with click-to-cast buttons and raid-wide
-- sync. Speaks the common "PLPWR" addon protocol so assignments stay in
-- sync with other blessing managers in the group.
local _, ns = ...
local S = ns.S
local L = S.L
local PB = S:NewModule("Blessings", "blessings")

local _G = _G
local ipairs, pairs, wipe, tinsert, sort = ipairs, pairs, wipe, table.insert, table.sort
local format, strfind, strsub, strsplit, strmatch, gmatch = string.format, string.find, string.sub, strsplit, string.match, string.gmatch
local tonumber, tostring, min, max, floor, select = tonumber, tostring, math.min, math.max, math.floor, select
local GetUnitName = GetUnitName
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local IsInGroup, IsInRaid, IsInInstance, IsInGuild = IsInGroup, IsInRaid, IsInInstance, IsInGuild
local GetNumGroupMembers, GetNumSubgroupMembers = GetNumGroupMembers, GetNumSubgroupMembers
local UnitName, UnitClass, UnitExists, UnitIsConnected, UnitIsDeadOrGhost = UnitName, UnitClass, UnitExists, UnitIsConnected, UnitIsDeadOrGhost
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local UnitLevel, GetItemCount, Ambiguate = UnitLevel, GetItemCount, Ambiguate
local GetRaidRosterInfo, GetTalentInfo, GetNumTalentTabs, GetNumTalents = GetRaidRosterInfo, GetTalentInfo, GetNumTalentTabs, GetNumTalents
local CreateFrame = CreateFrame

local PREFIX = "PLPWR"
local IS_WRATH = S.isWrath
local MAX_CLASSES = IS_WRATH and 10 or 9
local MAX_AURAS = IS_WRATH and 7 or 8
local MAX_BLESS = IS_WRATH and 4 or 6      -- blessing slots carried by the SELF message
local SYMBOLS_ITEM = 21177                 -- Symbol of Kings
local RF_SPELL = 25780                     -- Righteous Fury
local LOH_SPELLS = { 633, 2800, 10310, 27154, 48788 }
local DI_SPELLS = { 19752 }

-- spell id tables per blessing index (client flavor dependent)
local SPELL_IDS = IS_WRATH and { 19742, 19740, 20217, 20911 } or { 19742, 19740, 20217, 1038, 19977, 20911, 6940, 425600 }
local GSPELL_IDS = IS_WRATH and { 25894, 25782, 25898, 25899 } or { 25894, 25782, 25898, 25895, 25890, 25899 }
local NORMAL_RANKS = IS_WRATH and {
	{ { 67, 48936 }, { 61, 48935 }, { 55, 27142 }, { 50, 25290 }, { 44, 19854 }, { 34, 19853 }, { 24, 19852 }, { 14, 19850 }, { 4, 19742 } },
	{ { 69, 48932 }, { 63, 48931 }, { 60, 27140 }, { 50, 25291 }, { 42, 19838 }, { 32, 19837 }, { 22, 19836 }, { 12, 19835 }, { 4, 19834 }, { 0, 19740 } },
	{ { 10, 20217 } },
	{ { 20, 20911 } },
} or {
	{ { 55, 27142 }, { 50, 25290 }, { 44, 19854 }, { 34, 19853 }, { 24, 19852 }, { 14, 19850 }, { 4, 19742 } },
	{ { 60, 27140 }, { 50, 25291 }, { 42, 19838 }, { 32, 19837 }, { 22, 19836 }, { 12, 19835 }, { 4, 19834 }, { 0, 19740 } },
	{ { 10, 20217 } },
	{ { 16, 1038 } },
	{ { 59, 27144 }, { 50, 19979 }, { 40, 19978 }, { 30, 19977 } },
	{ { 60, 27168 }, { 50, 20914 }, { 40, 20913 }, { 30, 20912 }, { 20, 20911 } },
	{ { 60, 27148 }, { 52, 27147 }, { 44, 20729 }, { 36, 6940 } },
	{ { 0, 425600 } },
}
local GREATER_RANKS = IS_WRATH and {
	{ { 67, 48938 }, { 61, 48937 }, { 55, 27143 }, { 50, 25918 }, { 44, 25894 } },
	{ { 69, 48934 }, { 63, 48933 }, { 60, 27141 }, { 50, 25916 }, { 42, 25782 } },
	{ { 50, 25898 } },
	{ { 50, 25899 } },
} or {
	{ { 55, 27143 }, { 50, 25918 }, { 44, 25894 } },
	{ { 60, 27141 }, { 50, 25916 }, { 42, 25782 } },
	{ { 50, 25898 } },
	{ { 50, 25895 } },
	{ { 59, 27145 }, { 50, 25890 } },
	{ { 60, 27169 }, { 50, 25899 } },
}
local AURA_IDS = IS_WRATH and { 465, 7294, 19746, 19876, 19888, 19891, 32223 } or { 465, 7294, 19746, 19876, 19888, 19891, 20218, 32223 }
local SEAL_IDS = IS_WRATH and { 20164, 20165, 20166, 21084, 20375, 31801, 31892, 348700, 348704 }
	or { 20164, 20165, 20166, 21084, 21082, 20375, 31801, 31892, 348700, 348704 }
local CLASS_IDS = IS_WRATH and
	{ "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN", "DEATHKNIGHT" } or
	(S.isTBC or S.isCata or S.isMists) and { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" } or
	{ "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "PET" }
local CLASS_TO_ID = {}
for i, c in ipairs(CLASS_IDS) do CLASS_TO_ID[c] = i end

-- resolved at runtime (localized names/icons)
local SpellName, SpellIcon, AuraName, AuraIcon, SealName, SealIcon = {}, {}, {}, {}, {}, {}
local function SpellInfo(id)
	local n, _, ic = S.GetSpellInfo(id)
	return n, ic
end
local function ResolveSpells()
	for i = 1, #SPELL_IDS do SpellName[i], SpellIcon[i] = SpellInfo(SPELL_IDS[i]) end
	for i = 1, #GSPELL_IDS do
		local n, ic = SpellInfo(GSPELL_IDS[i])
		PB.greaterName, PB.greaterIcon = PB.greaterName or {}, PB.greaterIcon or {}
		PB.greaterName[i], PB.greaterIcon[i] = n, ic
	end
	for i = 1, #AURA_IDS do AuraName[i], AuraIcon[i] = SpellInfo(AURA_IDS[i]) end
	for i = 1, #SEAL_IDS do SealName[i], SealIcon[i] = SpellInfo(SEAL_IDS[i]) end
end

-- module state -------------------------------------------------------------
local isPally = S.myClass == "PALADIN"
local pallys = {}          -- name -> { [bless]={rank,talent}, AuraInfo, symbols, freeassign, subgroup, cooldowns }
local assignments = {}     -- name -> { [classId] = blessId }
local normalAssign = {}    -- name -> { [classId] = { [tname] = blessId } }
local auraAssign = {}      -- name -> auraId
local leaders = {}         -- name -> true (raid leader/assist using sync)
local rosterClasses = {}   -- classId -> { unitids }
local talentByIcon = {}    -- icon texture -> {tab, index}
local playerName

local function ShortName(n) return n and Ambiguate(n, "short") or n end

local function Store()
	local g = S.db and S.db.global
	if not g then return nil end
	g.blessings = g.blessings or { assignments = {}, normal = {}, aura = {} }
	return g.blessings
end

local function MyAssignments()
	local st = Store()
	if not st then return {} end
	if not st.assignments[playerName] then
		st.assignments[playerName] = {}
		for i = 1, MAX_CLASSES do st.assignments[playerName][i] = 0 end
	end
	return st.assignments[playerName]
end

-- persisted tables are shared; live tables point at them
local function LoadState()
	local st = Store()
	if not st then return end
	assignments = st.assignments
	normalAssign = st.normal
	auraAssign = st.aura
end

-- helpers ------------------------------------------------------------------
local function SendMsg(msg, target)
	if not IsInGroup() then return end
	if PB.lastMsg == msg and not target then return end
	PB.lastMsg = msg
	local ch = target and "WHISPER" or S.GroupChannel()
	if ch then S.SendAddonMessage(PREFIX, msg, ch, target) end
end

local function IsLeader(name) return leaders[name] == true end

function PB:CanControl(name)
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
		return name == playerName or (pallys[name] and pallys[name].freeassign == true)
	end
	if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then return true end
	return name == playerName or (pallys[name] and pallys[name].freeassign == true)
end

-- own spell knowledge ------------------------------------------------------
local function KnownRank(idList)
	for i = 1, #idList do
		if S.IsSpellKnown and S.IsSpellKnown(idList[i][2]) then return #idList - i + 1 end
	end
end

local function ScanTalents()
	if not GetNumTalentTabs then return end
	wipe(talentByIcon)
	for t = 1, GetNumTalentTabs() do
		for i = 1, GetNumTalents(t) do
			local _, icon = GetTalentInfo(t, i)
			if icon then talentByIcon[icon] = { t, i } end
		end
	end
end

local function TalentRank(icon)
	local t = icon and talentByIcon[icon]
	if not t then return 0 end
	return select(5, GetTalentInfo(t[1], t[2])) or 0
end

function PB:ScanSpells()
	if not isPally then return end
	local info = {}
	for i = 1, MAX_BLESS do
		local ranks = NORMAL_RANKS[i]
		if ranks then
			local rank = KnownRank(ranks)
			if rank then
				-- talent check only for improved blessings (wisdom/might/sanctuary)
				local talent = 0
				if i == 1 or i == 2 or i == 6 then talent = TalentRank(SpellIcon[i]) end
				info[i] = { rank = rank, talent = talent }
			end
		end
	end
	info.AuraInfo = {}
	for i = 1, MAX_AURAS do
		if AuraName[i] and S.IsSpellKnown and S.IsSpellKnown(AURA_IDS[i]) then
			local talent = (i <= 3 or i == 7) and TalentRank(AuraIcon[i]) or 0
			info.AuraInfo[i] = { rank = 1, talent = talent }
		end
	end
	info.CooldownInfo = info.CooldownInfo or {}
	for cd, list in ipairs({ LOH_SPELLS, DI_SPELLS }) do
		for _, id in ipairs(list) do
			if S.IsSpellKnown and S.IsSpellKnown(id) then info.CooldownInfo[cd] = info.CooldownInfo[cd] or {} break end
		end
	end
	pallys[playerName] = info
	if not info.subgroup then info.subgroup = 1 end
	self:ScanInventory()
end

function PB:ScanInventory()
	if pallys[playerName] then pallys[playerName].symbols = GetItemCount(SYMBOLS_ITEM) or 0 end
end

function PB:ScanCooldowns()
	if not isPally then return end
	local info = pallys[playerName]
	if not info or not info.CooldownInfo then return end
	for cd, list in ipairs({ LOH_SPELLS, DI_SPELLS }) do
		if info.CooldownInfo[cd] then
			for _, id in ipairs(list) do
				local start, dur = S.GetSpellCooldown(id)
				if start then
					info.CooldownInfo[cd].start = start
					info.CooldownInfo[cd].duration = dur
					info.CooldownInfo[cd].remaining = max(start + dur - GetTime(), 0)
					break
				end
			end
		end
	end
end

-- protocol -----------------------------------------------------------------
function PB:SendSelf(sender)
	if GetNumGroupMembers() == 0 then return end
	if IsLeader(playerName) then SendMsg("PPLEADER " .. playerName) end
	if not isPally then return end
	local whisper = sender and not IsLeader(sender) and sender or nil
	local info = pallys[playerName]
	if not info then return end
	local s = ""
	for i = 1, MAX_BLESS do
		s = s .. (info[i] and format("%x%x", info[i].rank, info[i].talent) or "nn")
	end
	s = s .. "@"
	local mine = MyAssignments()
	for i = 1, MAX_CLASSES do
		local v = mine[i]
		s = s .. (v and v > 0 and v or "n")
	end
	SendMsg("SELF " .. s, whisper)
	s = ""
	for i = 1, MAX_AURAS do
		local a = info.AuraInfo[i]
		s = s .. (a and format("%x%x", a.rank, a.talent) or "nn")
	end
	SendMsg("ASELF " .. s .. "@" .. (auraAssign[playerName] or 0), whisper)
	local list = {}
	local myNormal = normalAssign[playerName]
	if myNormal then
		for class, targets in pairs(myNormal) do
			for tname, bless in pairs(targets) do
				tinsert(list, format("%s %s %s %s", playerName, class, tname, bless))
			end
		end
	end
	for off = 1, #list, 5 do
		SendMsg("NASSIGN " .. table.concat(list, "@", off, min(off + 4, #list)), whisper)
	end
	self:ScanCooldowns()
	local cds = ":n:n:n:n"
	local ci = info.CooldownInfo
	if ci and (ci[1] or ci[2]) then
		local t = ""
		for i = 1, 2 do
			local c = ci[i]
			t = t .. ":" .. (c and c.duration or "n") .. ":" .. (c and c.remaining and floor(c.remaining) or "n")
		end
		cds = t
	end
	local fa = self.db.freeassign and "YES" or "NO"
	SendMsg("FREEASSIGN " .. fa .. " | SYMCOUNT " .. (info.symbols or 0) .. " | COOLDOWNS" .. cds, whisper)
end

local function ClearAssignments(fromLeader, skipAuras)
	for name in pairs(assignments) do
		if fromLeader or name == playerName then
			for i = 1, MAX_CLASSES do assignments[name][i] = 0 end
		end
	end
	for pname, classes in pairs(normalAssign) do
		if fromLeader or pname == playerName then
			for _, t in pairs(classes) do wipe(t) end
		end
	end
	if skipAuras then return end
	for name in pairs(auraAssign) do
		if fromLeader or name == playerName then auraAssign[name] = 0 end
	end
end

function PB:ParseMessage(sender, msg)
	sender = ShortName(sender)
	if strfind(msg, "^PPLEADER") then
		local name = ShortName(strmatch(msg, "^PPLEADER (.*)"))
		if name and IsLeader(name) then self.remoteLeader = true end
	end
	if sender == playerName or not self.initialized then return end
	local fromLeader = IsLeader(sender)

	if msg == "REQ" then self:SendSelf(sender) end

	local numbers, assign = strmatch(msg, "^SELF ([0-9a-fn]*)@([0-9n]*)")
	if numbers then
		assignments[sender] = assignments[sender] or {}
		pallys[sender] = {}
		normalAssign[sender] = normalAssign[sender] or {}
		for i = 1, MAX_BLESS do
			local rank = strsub(numbers, i * 2 - 1, i * 2 - 1)
			local talent = strsub(numbers, i * 2, i * 2)
			if rank ~= "n" and rank ~= "" then
				pallys[sender][i] = { rank = tonumber(rank, 16), talent = tonumber(talent) }
			end
		end
		for i = 1, MAX_CLASSES do
			local d = strsub(assign, i, i)
			assignments[sender][i] = (d == "n" or d == "") and 0 or tonumber(d)
		end
	end

	local aname, aclass, askill = strmatch(msg, "^ASSIGN (.*) (.*) (.*)")
	if aname then
		aname = ShortName(aname)
		if aname ~= sender and not (fromLeader or self.db.freeassign) then return end
		assignments[aname] = assignments[aname] or {}
		assignments[aname][tonumber(aclass)] = tonumber(askill)
	end

	aname, assign = strmatch(msg, "^PASSIGN (.*)@([0-9n]*)")
	if aname then
		aname = ShortName(aname)
		if aname ~= sender and not (fromLeader or self.db.freeassign) then return end
		assignments[aname] = assignments[aname] or {}
		for i = 1, MAX_CLASSES do
			local d = strsub(assign, i, i)
			assignments[aname][i] = (d == "n" or d == "") and 0 or tonumber(d)
		end
	end

	if strfind(msg, "^NASSIGN") then
		for pname, class, tname, skill in gmatch(strsub(msg, 9), "([^@]*) ([^@]*) ([^@]*) ([^@]*)") do
			local name = ShortName(pname)
			if name ~= sender and not (fromLeader or self.db.freeassign) then return end
			normalAssign[name] = normalAssign[name] or {}
			class = tonumber(class)
			normalAssign[name][class] = normalAssign[name][class] or {}
			skill = tonumber(skill)
			normalAssign[name][class][tname] = skill ~= 0 and skill or nil
		end
	end

	aname, askill = strmatch(msg, "^MASSIGN (.*) (.*)")
	if aname then
		aname = ShortName(aname)
		if aname ~= sender and not (fromLeader or self.db.freeassign) then return end
		assignments[aname] = assignments[aname] or {}
		for i = 1, MAX_CLASSES do assignments[aname][i] = tonumber(askill) end
	end

	aname, askill = strmatch(msg, "^AASSIGN (.*) (.*)")
	if aname then
		aname = ShortName(aname)
		if aname ~= sender and not (fromLeader or self.db.freeassign) then return end
		auraAssign[aname] = tonumber(askill) or 0
	end

	local syms = strmatch(msg, "SYMCOUNT ([0-9]*)")
	if syms and pallys[sender] then pallys[sender].symbols = tonumber(syms) or 0 end

	if strfind(msg, "COOLDOWNS") and pallys[sender] then
		local _, d1, r1, d2, r2 = strsplit(":", msg)
		local ci = pallys[sender].CooldownInfo or {}
		pallys[sender].CooldownInfo = ci
		if not ci[1] and r1 ~= "n" then
			ci[1] = { duration = tonumber(d1), start = GetTime() - ((tonumber(d1) or 0) - (tonumber(r1) or 0)) }
		end
		if not ci[2] and r2 ~= "n" then
			ci[2] = { duration = tonumber(d2), start = GetTime() - ((tonumber(d2) or 0) - (tonumber(r2) or 0)) }
		end
	end

	if strfind(msg, "^CLEAR") then
		if fromLeader then ClearAssignments(true, strfind(msg, "SKIP"))
		elseif self.db.freeassign then ClearAssignments(false, strfind(msg, "SKIP")) end
	end

	if strfind(msg, "FREEASSIGN YES") and pallys[sender] then pallys[sender].freeassign = true end
	if strfind(msg, "FREEASSIGN NO") and pallys[sender] then pallys[sender].freeassign = false end

	numbers, assign = strmatch(msg, "^ASELF ([0-9a-fn]*)@([0-9n]*)")
	if numbers and pallys[sender] then
		local ai = pallys[sender].AuraInfo or {}
		pallys[sender].AuraInfo = ai
		for i = 1, MAX_AURAS do
			local rank = strsub(numbers, i * 2 - 1, i * 2 - 1)
			local talent = strsub(numbers, i * 2, i * 2)
			if rank ~= "n" and rank ~= "" then ai[i] = { rank = tonumber(rank, 16), talent = tonumber(talent) } end
		end
		auraAssign[sender] = (assign == "n" or assign == "") and 0 or tonumber(assign)
	end

	self:RefreshFrames()
	if self.grid and self.grid:IsShown() then self:RefreshGrid() end
end

-- roster -------------------------------------------------------------------
local function UnitIterator()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	else
		units[1] = "player"
		for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
	end
	return units
end

function PB:UpdateRoster()
	wipe(leaders)
	for i = 1, MAX_CLASSES do rosterClasses[i] = rosterClasses[i] or {} wipe(rosterClasses[i]) end
	for _, unit in ipairs(UnitIterator()) do
		if UnitExists(unit) then
			local name = ShortName(GetUnitName(unit, true) or UnitName(unit))
			local class = select(2, UnitClass(unit))
			if IsInRaid() then
				local n = tonumber(strmatch(unit, "(%d+)"))
				local rname, rank, subgroup = GetRaidRosterInfo(n)
				name = ShortName(rname) or name
				if rank and rank > 0 then leaders[name] = true end
				if pallys[name] then pallys[name].subgroup = subgroup end
			elseif UnitIsGroupLeader(unit) then
				leaders[name] = true
			end
			local cid = CLASS_TO_ID[class]
			if cid and rosterClasses[cid] then
				tinsert(rosterClasses[cid], { unit = unit, name = name })
			end
		end
	end
	self.buffsDirty = true
	self:RefreshFrames()
	if self.grid and self.grid:IsShown() then self:RefreshGrid() end
end

-- blessing resolution ------------------------------------------------------
local function BlessingFor(name, classId, unitName)
	local na = normalAssign[name]
	if na and na[classId] and unitName and na[classId][unitName] then
		return na[classId][unitName]
	end
	local a = assignments[name]
	return a and a[classId] or 0
end

local function BestBlessingFor(classId, unitName)
	-- pick the assignment of the highest-ranked pally that knows the blessing
	local best, bestName
	for pname in pairs(pallys) do
		local b = BlessingFor(pname, classId, unitName)
		if b > 0 then
			local info = pallys[pname] and pallys[pname][b]
			local rank = info and info.rank or -1
			if not best or rank > best then best, bestName = rank, pname end
		end
	end
	if not bestName then return 0 end
	return BlessingFor(bestName, classId, unitName)
end

-- aura scan: does unit carry blessing b (normal or greater, any pally)?
local function HasBlessing(unit, blessId)
	if blessId <= 0 then return false end
	local want = SpellName[blessId]
	local wantG = PB.greaterName and PB.greaterName[blessId]
	if not want and not wantG then return false end
	for i = 1, 40 do
		local a = S.GetAura(unit, i, "HELPFUL")
		if not a then break end
		if a.name == want or a.name == wantG then return true, a.expirationTime end
	end
	return false
end

local function SpellForLevel(ranks, level)
	for _, r in ipairs(ranks) do
		if level >= r[1] and S.IsSpellKnown and S.IsSpellKnown(r[2]) then return r[2] end
	end
end

-- buff tracking ------------------------------------------------------------
function PB:ScanBuffs()
	wipe(self.missing or {})
	self.missing = self.missing or {}
	for cid = 1, MAX_CLASSES do
		local missing, total = 0, 0
		local expiry
		local bless = isPally and BlessingFor(playerName, cid) or BestBlessingFor(cid)
		for _, m in ipairs(rosterClasses[cid] or {}) do
			if UnitExists(m.unit) and UnitIsConnected(m.unit) and not UnitIsDeadOrGhost(m.unit) then
				total = total + 1
				local myBless = isPally and BlessingFor(playerName, cid, m.name) or BestBlessingFor(cid, m.name)
				local has, exp = HasBlessing(m.unit, myBless)
				m.miss = not has
				if not has then missing = missing + 1
				elseif exp and exp > 0 then expiry = (not expiry or exp < expiry) and exp or expiry end
			end
		end
		self.missing[cid] = { missing = missing, total = total, bless = bless, expiry = expiry }
	end
end

local function FormatTime(t)
	if not t or t <= 0 then return "" end
	return format("%d:%02d", floor(t / 60), t % 60)
end

-- buff frame ---------------------------------------------------------------
local ROW_H, ROW_W = 18, 150

local function MakeBuffRow(parent, classId)
	local b = CreateFrame("Button", "SentinelUIBlessingRow" .. classId, parent, "SecureActionButtonTemplate")
	b:SetSize(ROW_W, ROW_H)
	b:EnableMouse(true)
	b:RegisterForClicks("AnyUp", "AnyDown")
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", 2, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon = icon
	local classT = b:CreateTexture(nil, "OVERLAY")
	classT:SetSize(11, 11)
	classT:SetPoint("LEFT", icon, "RIGHT", 2, 0)
	classT:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
	local cc = CLASS_IDS[classId]
	local coords = cc and CLASS_ICON_TCOORDS[cc]
	if coords then classT:SetTexCoord(unpack(coords)) end
	b.classIcon = classT
	local t = S:FontString(b, 10)
	t:SetPoint("LEFT", classT, "RIGHT", 4, 0)
	b.text = t
	local cnt = S:FontString(b, 9, "OUTLINE")
	cnt:SetPoint("RIGHT", -3, 0)
	b.count = cnt
	b.classId = classId
	return b
end

local function MakeSmall(parent, name)
	local b = CreateFrame("Button", "SentinelUIBlessing" .. name, parent, "SecureActionButtonTemplate")
	b:SetSize(16, 16)
	b:RegisterForClicks("AnyUp", "AnyDown")
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon = icon
	b:EnableMouse(true)
	return b
end

local function SaveBarPos(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	PB.db.barPos = { point = point, rel = relPoint, x = x, y = y }
end

local function RestoreBarPos(f)
	local p = PB.db.barPos
	f:ClearAllPoints()
	if p and p.point then
		f:SetPoint(p.point, UIParent, p.rel or "CENTER", p.x or 0, p.y or 0)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
	end
end

function PB:BuildBuffFrame()
	if self.buffFrame then return end
	local f = CreateFrame("Frame", "SentinelUIBlessings", UIParent, S.BackdropTemplate)
	f:SetSize(ROW_W + 8, 30)
	RestoreBarPos(f)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetFrameStrata("MEDIUM")
	S:SetTemplate(f, "Default", "MEDIUM")
	f:Hide()
	f:SetScript("OnDragStart", function(fr) if not PB.db.lockFrame then fr:StartMoving() end end)
	f:SetScript("OnDragStop", function(fr) fr:StopMovingOrSizing() SaveBarPos(fr) end)

	f.title = S:FontString(f, 9, "OUTLINE")
	f.title:SetPoint("TOPLEFT", 5, -4)
	f.title:SetText("|cff" .. S.accentHex .. "Blessings|r")

	-- personal row: RF, aura, seal
	-- drag handle: the secure class buttons swallow clicks, so the frame needs
	-- a dedicated strip to grab
	f.grip = CreateFrame("Button", nil, f)
	f.grip:EnableMouse(true)
	f.grip:SetPoint("TOPLEFT", 0, 0)
	f.grip:SetPoint("TOPRIGHT", 0, 0)
	f.grip:SetHeight(14)
	f.grip:SetScript("OnMouseDown", function(_, btn)
		if btn == "LeftButton" and not PB.db.lockFrame then f:StartMoving() end
	end)
	f.grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() SaveBarPos(f) end)

	f.rf = MakeSmall(f, "RF")
	f.rf:SetPoint("TOPLEFT", 5, -17)
	f.auraBtn = MakeSmall(f, "Aura")
	f.auraBtn:SetPoint("LEFT", f.rf, "RIGHT", 3, 0)
	f.seal = MakeSmall(f, "Seal")
	f.seal:SetPoint("LEFT", f.auraBtn, "RIGHT", 3, 0)

	f.rows = {}
	for cid = 1, MAX_CLASSES do
		local r = MakeBuffRow(f, cid)
		r:SetPoint("TOPLEFT", 3, -(38 + (cid - 1) * ROW_H))
		f.rows[cid] = r
		r:Hide()
	end

	-- tooltips + click behavior for personal buttons
	local function Tip(btn, text)
		btn:SetScript("OnEnter", function(b)
			GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
			GameTooltip:AddLine(text)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	Tip(f.rf, L["Righteous Fury"])
	Tip(f.auraBtn, L["Aura (left: cast, right: next aura)"])
	Tip(f.seal, L["Seal (left: cast, right: next seal)"])
	f.rf:SetScript("PostClick", function(_, btn) if btn == "RightButton" then PB:CycleRF() end end)
	f.auraBtn:SetScript("PostClick", function(_, btn) if btn == "RightButton" then PB:CycleAura() end end)
	f.seal:SetScript("PostClick", function(_, btn) if btn == "RightButton" then PB:CycleSeal() end end)
	for _, r in ipairs(f.rows) do
		r:SetScript("OnEnter", function(b)
			GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
			local st = PB.missing and PB.missing[b.classId]
			local cn = CLASS_IDS[b.classId] and (LOCALIZED_CLASS_NAMES_MALE[CLASS_IDS[b.classId]] or CLASS_IDS[b.classId])
			GameTooltip:AddLine(cn or "?")
			if st then
				local bn = st.bless > 0 and (PB.greaterName and PB.greaterName[st.bless] or SpellName[st.bless]) or L["none"]
				GameTooltip:AddLine(format(L["Assigned: %s"], bn), 1, 1, 1)
				GameTooltip:AddLine(format(L["Missing: %d/%d"], st.missing, st.total), 1, 1, 1)
			end
			GameTooltip:AddLine(L["Left: greater blessing  |  Right: single blessing"], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	self.buffFrame = f
end

function PB:CycleAura()
	local cur = auraAssign[playerName] or 0
	cur = (cur % MAX_AURAS) + 1
	auraAssign[playerName] = cur
	if IsInGroup() then SendMsg("AASSIGN " .. playerName .. " " .. cur) end
	self:ApplySecure()
end

function PB:CycleSeal()
	self.db.seal = ((self.db.seal or 0) % #SEAL_IDS) + 1
	self:ApplySecure()
end

function PB:CycleRF() end -- RF button casts; nothing to cycle

-- apply secure attributes (out of combat only) ------------------------------
local function SetCast(btn, mouse, spellId, unit)
	btn:SetAttribute("type" .. mouse, "spell")
	btn:SetAttribute("spell" .. mouse, spellId and SpellInfo(spellId) or nil)
	if unit then btn:SetAttribute("unit" .. mouse, unit) end
end

function PB:ApplySecure()
	if InCombatLockdown() then self.securePending = true return end
	self.securePending = nil
	local f = self.buffFrame
	if not f then return end
	ResolveSpells()
	MyAssignments() -- ensure the persisted row for the player exists
	local myAura = auraAssign[playerName] or self.db.aura or 0
	if myAura > MAX_AURAS then myAura = 0 end
	if myAura > 0 and AuraName[myAura] then
		f.auraBtn:SetAttribute("type1", "spell")
		f.auraBtn:SetAttribute("spell1", AuraName[myAura])
		f.auraBtn:SetAttribute("unit1", "player")
		f.auraBtn.icon:SetTexture(AuraIcon[myAura])
	else
		f.auraBtn:SetAttribute("type1", nil)
		f.auraBtn.icon:SetTexture(AuraIcon[1])
		f.auraBtn.icon:SetDesaturated(true)
	end
	if myAura > 0 then f.auraBtn.icon:SetDesaturated(false) end
	local sealId = SEAL_IDS[self.db.seal or 0]
	if sealId and SealName[self.db.seal] then
		f.seal:SetAttribute("type1", "spell")
		f.seal:SetAttribute("spell1", SealName[self.db.seal])
		f.seal:SetAttribute("unit1", "player")
		f.seal.icon:SetTexture(SealIcon[self.db.seal])
	else
		f.seal:SetAttribute("type1", nil)
		f.seal.icon:SetTexture(SealIcon[1])
		f.seal.icon:SetDesaturated(true)
	end
	if S.IsSpellKnown and S.IsSpellKnown(RF_SPELL) then
		local n, ic = SpellInfo(RF_SPELL)
		f.rf:SetAttribute("type1", "spell")
		f.rf:SetAttribute("spell1", n)
		f.rf:SetAttribute("unit1", "player")
		f.rf.icon:SetTexture(ic)
		f.rf:Show()
	else
		f.rf:Hide()
	end
	-- class rows: left = greater, right = single-target rank for lowest level member
	local mine = assignments[playerName] or {}
	for cid = 1, MAX_CLASSES do
		local row = f.rows[cid]
		local bless = mine[cid] or 0
		local members = rosterClasses[cid]
		if bless > 0 and members and #members > 0 then
			local target = members[1]
			local lowest = target
			for _, m in ipairs(members) do
				if UnitLevel(m.unit) < UnitLevel(lowest.unit) then lowest = m end
			end
			-- normal blessing: target the first member still missing it so that
			-- repeated right clicks work through the class automatically
			local normTarget = lowest
			for _, m in ipairs(members) do
				if m.miss then normTarget = m break end
			end
			local gid = GREATER_RANKS[bless] and SpellForLevel(GREATER_RANKS[bless], 80)
			local nid = NORMAL_RANKS[bless] and SpellForLevel(NORMAL_RANKS[bless], UnitLevel(normTarget.unit))
			SetCast(row, 1, gid, target.unit)
			SetCast(row, 2, nid, normTarget.unit)
		else
			row:SetAttribute("type1", nil)
			row:SetAttribute("type2", nil)
		end
	end
end

-- frame refresh -------------------------------------------------------------
function PB:RefreshFrames()
	if not self.buffFrame then return end
	if InCombatLockdown() then self.refreshPending = true return end
	self.refreshPending = nil
	self:ScanBuffs()
	self:ApplySecure()
	local f = self.buffFrame
	local shown = 0
	local mine = assignments[playerName] or {}
	for cid = 1, MAX_CLASSES do
		local members = rosterClasses[cid]
		local row = f.rows[cid]
		if members and #members > 0 then
			local st = self.missing[cid] or {}
			local bless = isPally and (mine[cid] or 0) or (st.bless or 0)
			row:Show()
			shown = shown + 1
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 3, -(38 + (shown - 1) * ROW_H))
			if bless > 0 then
				row.icon:SetTexture(PB.greaterIcon and PB.greaterIcon[bless] or SpellIcon[bless])
				row.icon:SetDesaturated(false)
			else
				row.icon:SetTexture(SpellIcon[1])
				row.icon:SetDesaturated(true)
				row.icon:SetAlpha(0.4)
			end
			if bless > 0 then row.icon:SetAlpha(1) end
			local cn = LOCALIZED_CLASS_NAMES_MALE[CLASS_IDS[cid]] or CLASS_IDS[cid]
			local st2 = self.missing[cid]
			local remain = st2 and st2.expiry and st2.expiry - GetTime() or nil
			row.text:SetText(cn .. (remain and ("  |cffaaaaaa" .. FormatTime(remain) .. "|r") or ""))
			if st2 and st2.missing > 0 then
				row.count:SetText("|cffff5544" .. st2.missing .. "/" .. st2.total .. "|r")
			elseif st2 then
				row.count:SetText("|cff55ff55" .. st2.total .. "/" .. st2.total .. "|r")
			else
				row.count:SetText("")
			end
		else
			row:Hide()
		end
	end
	f:SetSize(ROW_W + 6, 40 + max(shown, 0) * ROW_H)
	f:SetShown(self.db.showBar and isPally and (self.db.showWhenSolo or IsInGroup()) and shown > 0)
end

-- assignment grid ------------------------------------------------------------
local CELL = 24
function PB:BuildGrid()
	if self.grid then return end
	local f = CreateFrame("Frame", "SentinelUIBlessingGrid", UIParent, S.BackdropTemplate)
	f:SetSize(150 + (MAX_CLASSES + 1) * (CELL + 4) + 8, 300)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetFrameStrata("DIALOG")
	S:SetTemplate(f, "Default", "DIALOG")
	f:Hide()
	tinsert(UISpecialFrames, "SentinelUIBlessingGrid")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	f.title = S:FontString(f, 13, "OUTLINE")
	f.title:SetPoint("TOPLEFT", 12, -10)
	f.title:SetText("SentinelUI " .. L["Blessings"])
	local close = CreateFrame("Button", nil, f)
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", -8, -8)
	close:EnableMouse(true)
	close:SetScript("OnClick", function() f:Hide() end)
	S:SkinCloseButton(close)

	-- column headers = class icons
	for cid = 1, MAX_CLASSES do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetSize(18, 18)
		t:SetPoint("TOPLEFT", 150 + (cid - 1) * (CELL + 4), -30)
		t:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		local cc = CLASS_IDS[cid]
		if cc and CLASS_ICON_TCOORDS[cc] then t:SetTexCoord(unpack(CLASS_ICON_TCOORDS[cc])) end
	end
	local ah = S:FontString(f, 10)
	ah:SetPoint("TOPLEFT", 150 + MAX_CLASSES * (CELL + 4), -34)
	ah:SetText(L["Aura"])

	f.cells = {}
	f.names = {}
	f.auras = {}

	-- footer buttons
	local function FooterBtn(label, w, fn)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(w, 20)
		S:SkinButton(b)
		local t = S:FontString(b, 11)
		t:SetPoint("CENTER")
		t:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	f.refresh = FooterBtn(L["Refresh"], 70, function() SendMsg("REQ") PB:UpdateRoster() PB:SendSelf() end)
	f.refresh:SetPoint("BOTTOMLEFT", 10, 10)
	f.clear = FooterBtn(L["Clear"], 70, function()
		if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then SendMsg("CLEAR") end
		ClearAssignments(UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
		PB:RefreshFrames() PB:RefreshGrid()
	end)
	f.clear:SetPoint("LEFT", f.refresh, "RIGHT", 6, 0)
	f.free = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.free:SetPoint("LEFT", f.clear, "RIGHT", 10, 0)
	f.free:SetSize(22, 22)
	f.free.text = S:FontString(f.free, 11)
	f.free.text:SetPoint("LEFT", f.free, "RIGHT", 2, 0)
	f.free.text:SetText(L["Free assign"])
	f.free:SetScript("OnClick", function(b)
		PB.db.freeassign = b:GetChecked()
		if pallys[playerName] then pallys[playerName].freeassign = PB.db.freeassign end
		PB:SendSelf()
	end)
	self.grid = f
end

local function GridCell(parent, row, col)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(CELL, CELL)
	b:SetPoint("TOPLEFT", 150 + (col - 1) * (CELL + 4), -52 - (row - 1) * (CELL + 4))
	S:SetTemplate(b, "Default")
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon = t
	return b
end

local function PallyList()
	local list = {}
	for name in pairs(pallys) do tinsert(list, name) end
	if isPally and not pallys[playerName] then tinsert(list, playerName) end
	sort(list)
	return list
end

function PB:SetAssignment(pname, cid, bless)
	local st = Store()
	if st then assignments = st.assignments end -- rebind in case the db was (re)created after LoadState
	assignments[pname] = assignments[pname] or {}
	assignments[pname][cid] = bless
	SendMsg("ASSIGN " .. pname .. " " .. cid .. " " .. bless)
	self:RefreshFrames()
end

local function CycleBlessing(pname, cid, back)
	local a = assignments[pname] or {}
	local cur = a[cid] or 0
	local info = pallys[pname]
	local nxt = cur
	for _ = 0, MAX_BLESS do
		nxt = back and (nxt - 1) or (nxt + 1)
		if nxt < 0 then nxt = MAX_BLESS elseif nxt > MAX_BLESS then nxt = 0 end
		if nxt == 0 or not info or (info[nxt] and (info[nxt].rank or 0) > 0) then break end
		if nxt == cur then break end
	end
	PB:SetAssignment(pname, cid, nxt)
end

function PB:RefreshGrid()
	if not self.grid then return end
	local f = self.grid
	local list = PallyList()
	for r, name in ipairs(list) do
		local nameFs = f.names[r]
		if not nameFs then
			nameFs = S:FontString(f, 11)
			nameFs:SetPoint("TOPLEFT", 12, -56 - (r - 1) * (CELL + 4))
			nameFs:SetWidth(134)
			nameFs:SetJustifyH("LEFT")
			f.names[r] = nameFs
		end
		nameFs:SetText(name == playerName and ("|cff" .. S.accentHex .. name .. "|r") or name)
		nameFs:Show()
		for cid = 1, MAX_CLASSES do
			local cell = f.cells[r * 100 + cid]
			if not cell then cell = GridCell(f, r, cid) f.cells[r * 100 + cid] = cell end
			local bless = assignments[name] and assignments[name][cid] or 0
			if bless > 0 and SpellIcon[bless] then
				cell.icon:SetTexture(SpellIcon[bless])
				cell.icon:SetDesaturated(false)
				cell.icon:SetAlpha(1)
			else
				cell.icon:SetTexture(SpellIcon[1] or 0)
				cell.icon:SetDesaturated(true)
				cell.icon:SetAlpha(0.15)
			end
			cell:SetScript("OnClick", function(_, btn)
				if not PB:CanControl(name) then return end
				CycleBlessing(name, cid, btn == "RightButton")
				PB:RefreshGrid()
			end)
			cell:RegisterForClicks("AnyUp")
			cell:Show()
		end
		local ab = f.auras[r]
		if not ab then
			ab = GridCell(f, r, MAX_CLASSES + 1)
			f.auras[r] = ab
		end
		local aura = auraAssign[name] or 0
		if aura > 0 and AuraIcon[aura] then
			ab.icon:SetTexture(AuraIcon[aura])
			ab.icon:SetDesaturated(false)
			ab.icon:SetAlpha(1)
		else
			ab.icon:SetTexture(AuraIcon[1] or 0)
			ab.icon:SetDesaturated(true)
			ab.icon:SetAlpha(0.15)
		end
		ab:SetScript("OnClick", function(_, btn)
			if not PB:CanControl(name) then return end
			local cur = auraAssign[name] or 0
			cur = btn == "RightButton" and (cur - 1) or (cur + 1)
			if cur < 0 then cur = MAX_AURAS elseif cur > MAX_AURAS then cur = 0 end
			auraAssign[name] = cur
			SendMsg("AASSIGN " .. name .. " " .. cur)
			PB:RefreshGrid()
			PB:ApplySecure()
		end)
		ab:RegisterForClicks("AnyUp")
		ab:Show()
	end
	for r = #list + 1, #f.names do
		f.names[r]:Hide()
		for cid = 1, MAX_CLASSES do
			local c = f.cells[r * 100 + cid]
			if c then c:Hide() end
		end
		if f.auras[r] then f.auras[r]:Hide() end
	end
	f:SetHeight(96 + max(#list, 1) * (CELL + 4))
	f.free:SetChecked(self.db.freeassign)
end

function PB:ToggleGrid()
	self:BuildGrid()
	ResolveSpells()
	if self.grid:IsShown() then
		self.grid:Hide()
	else
		self:UpdateRoster()
		self.grid:Show()
		self:RefreshGrid()
	end
end

-- events --------------------------------------------------------------------
function PB:CHAT_MSG_ADDON(event, prefix, msg, channel, sender)
	if prefix ~= PREFIX then return end
	if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" and channel ~= "WHISPER" then return end
	self:ParseMessage(sender, msg)
end

local joinedBefore = false
function PB:GROUP_ROSTER_UPDATE()
	self:UpdateRoster()
	local inGroup = IsInGroup()
	if inGroup and not joinedBefore then
		C_Timer.After(2, function()
			PB:ScanSpells()
			PB:SendSelf()
			SendMsg("REQ")
		end)
	elseif not inGroup then
		wipe(pallys)
		self:ScanSpells()
	end
	joinedBefore = inGroup and true or false
end

function PB:SPELLS_CHANGED()
	self:ScanSpells()
	self:SendSelf()
	self:RefreshFrames()
end

function PB:PLAYER_REGEN_ENABLED()
	if self.securePending or self.refreshPending then
		self:ApplySecure()
		self:RefreshFrames()
	end
end

local auraPending = false
function PB:UNIT_AURA()
	if auraPending then return end
	auraPending = true
	C_Timer.After(0.5, function()
		auraPending = false
		if PB.buffsDirty or PB.buffFrame and PB.buffFrame:IsShown() then
			PB.buffsDirty = nil
			PB:RefreshFrames()
		end
	end)
end

function PB:UNIT_SPELLCAST_SUCCEEDED(event, unit, _, spellID)
	if select(2, UnitClass(unit)) ~= "PALADIN" then return end
	for _, list in ipairs({ LOH_SPELLS, DI_SPELLS }) do
		for _, id in ipairs(list) do
			if id == spellID then
				C_Timer.After(2, function() PB:ScanCooldowns() if IsInGroup() then PB:SendSelf() end end)
				return
			end
		end
	end
end

function PB:Update()
	LoadState()
	local f = self.buffFrame
	if f then self:ApplySecure() self:RefreshFrames() end
end

function PB:Initialize()
	self.db = S.db.profile.blessings
	if self.db.enable == false then return end
	playerName = ShortName(GetUnitName("player", true) or UnitName("player"))
	ResolveSpells()
	LoadState()
	if S.RegisterAddonPrefix then pcall(S.RegisterAddonPrefix, PREFIX) end
	ScanTalents()
	self:ScanSpells()

	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "blessings", glyph = "SG",
		store = self.private.minimap, angle = 270,
		onLeft = function() PB.db.showBar = not PB.db.showBar PB:RefreshFrames() end,
		onRight = function() PB:ToggleGrid() end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. L["Blessings"])
			GameTooltip:AddLine(L["Left-click: buff bar  |  Right-click: assignments  |  Drag: move"], 1, 1, 1)
		end,
	})
	-- the buff bar doubles as its own movable frame; a mover handle would fight
	-- secure attributes, so keep the frame draggable via its title area
	self:BuildBuffFrame()
	self:BuildGrid()
	self:UpdateRoster()
	self:ApplySecure()
	self:RegisterEvent("CHAT_MSG_ADDON")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("SPELLS_CHANGED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("UNIT_AURA")
	C_Timer.After(3, function() if IsInGroup() then PB:SendSelf() SendMsg("REQ") end end)
	SlashCmdList.SENTINELUIBLESS = function(msg)
		msg = (msg or ""):lower()
		if msg == "grid" or msg == "assign" then PB:ToggleGrid()
		elseif msg == "bar" then PB.db.showBar = not PB.db.showBar PB:RefreshFrames()
		else PB:ToggleGrid() end
	end
	SLASH_SENTINELUIBLESS1 = "/suibless"
	SLASH_SENTINELUIBLESS2 = "/sbless"
end
