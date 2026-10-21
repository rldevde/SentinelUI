-- Damage/healing meter: combat log parsing,
-- fight segments, pet merging, class-colored bars, spell breakdown tooltips,
-- report & reset, up to 5 windows with per-window mode/segment, right-click
-- context menu, docking and a resize grip.
local _, ns = ...
local S = ns.S
local L = S.L
local DM = S:NewModule("DamageMeter")

local _G = _G
local pairs, ipairs, type, format, floor, min, max, sort, wipe, select, tostring = pairs, ipairs, type, format, floor, min, max, sort, wipe, select, tostring
local abs = math.abs
local unpack, tremove, tinsert = unpack or table.unpack, table.remove, table.insert
local date = date
local GetTime, UnitGUID = GetTime, UnitGUID
local IsSecret = S.IsSecret
local bit_band = _G.bit and _G.bit.band
local bit_bor = _G.bit and _G.bit.bor
if not bit_band then
	-- pure-Lua fallback for clients without the bit library (values < 2^31)
	bit_band = function(a, b)
		local res, bitv = 0, 1
		while a > 0 and b > 0 do
			local ab, bb = a % 2, b % 2
			if ab == 1 and bb == 1 then res = res + bitv end
			a, b = (a - ab) / 2, (b - bb) / 2
			bitv = bitv * 2
		end
		return res
	end
end

-- drops the last UTF-8 character without splitting a multi-byte sequence
local function Utf8Chop(s)
	local i = #s
	while i > 1 and (s:byte(i) or 0) >= 0x80 and (s:byte(i) or 0) < 0xC0 do
		i = i - 1
	end
	return s:sub(1, i - 1)
end

local MAX_WINDOWS = 5

-- combat log ------------------------------------------------------------------
local DMG_EVENTS = {
	SWING_DAMAGE = true, SPELL_DAMAGE = true, RANGE_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true,
	SPELL_BUILDING_DAMAGE = true, ENVIRONMENTAL_DAMAGE = true,
}
local HEAL_EVENTS = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
local AFF_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x01
local AFF_PARTY = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x02
local AFF_RAID = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x04
-- non-overlapping bits, so addition equals bitwise-or
local AFF_FRIENDLY = AFF_MINE + AFF_PARTY + AFF_RAID
local TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x1000
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400

local function IsFriendly(flags)
	if not flags or IsSecret(flags) or not bit_band then return false end
	return bit_band(flags, AFF_FRIENDLY) > 0
end
local function IsPet(flags)
	return bit_band and flags and not IsSecret(flags) and bit_band(flags, TYPE_PET) > 0
end

local function NewSegment() return { players = {}, startT = GetTime(), fightTime = 0 } end
DM.segments = { current = NewSegment(), overall = NewSegment(), history = {} }
DM.segments.overall.startT = nil
DM.pets = {}       -- petGUID -> ownerGUID
DM.classCache = {} -- guid -> class
DM.deathFeed = {}  -- guid -> ring of recent dmg/heal events before death
DM.windows = {}

local function PlayerIn(seg, guid, name, class)
	local p = seg.players[guid]
	if not p then
		p = { name = name or "?", class = class, dmg = 0, heal = 0, taken = 0, spells = {} }
		seg.players[guid] = p
	end
	-- new spell categories are added lazily so older saved players keep working
	local sp = p.spells
	if not sp.dmg then sp.dmg = {} end
	if not sp.heal then sp.heal = {} end
	if not sp.taken then sp.taken = {} end
	if not sp.healTaken then sp.healTaken = {} end
	if not sp.aura then sp.aura = {} end
	return p
end

local function AddSpell(tbl, id, name, amount)
	local k = id or name or "?"
	local s = tbl[k]
	if not s then s = { name = name or "?", n = 0, amt = 0 } tbl[k] = s end
	s.n, s.amt = s.n + 1, s.amt + amount
end

function DM:ClassOf(guid)
	if not guid then return end
	local c = self.classCache[guid]
	if c then return c end
	if GetPlayerInfoByGUID then
		-- returns localizedClass, englishClass, ..., name, realm
		local ok, _, cls = pcall(GetPlayerInfoByGUID, guid)
		if ok and cls then self.classCache[guid] = cls return cls end
	end
end

function DM:RefreshPets()
	wipe(self.pets)
	local function AddUnitPet(unit)
		if not UnitExists(unit .. "pet") then return end
		local pg, og = UnitGUID(unit .. "pet"), UnitGUID(unit)
		if pg and og then self.pets[pg] = og end
	end
	AddUnitPet("player")
	local prefix = IsInRaid() and "raid" or "party"
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	for i = 1, min(n, 40) do AddUnitPet(prefix .. i) end
end

-- recent hits/heals on a friendly player; snapshot on death = death log
local function FeedDeath(guid, entry)
	local f = DM.deathFeed[guid]
	if not f then f = {} DM.deathFeed[guid] = f end
	f[#f + 1] = entry
	if #f > 15 then tremove(f, 1) end
end

function DM:OnCombatLog()
	local r = { CombatLogGetCurrentEventInfo() }
	local sub, srcGUID, srcName, srcFlags = r[2], r[4], r[5], r[6]
	local dstGUID, dstName, dstFlags = r[8], r[9], r[10]
	self.cleuN = (self.cleuN or 0) + 1
	if IsSecret(srcGUID) or IsSecret(sub) then return end

	-- pull detection: first hostile event after combat start tells who engaged
	-- first and with what (spell/cast vs. melee/body pull by an enemy)
	if self.pullPending then
		local isHostileAction = DMG_EVENTS[sub] or HEAL_EVENTS[sub]
			or sub == "SPELL_INTERRUPT" or sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN"
			or sub == "SPELL_CAST_START" or sub == "SPELL_CAST_SUCCESS"
			or sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH"
		if isHostileAction then
			self.pullPending = nil
			local ours = IsFriendly(srcFlags)
			local spell = (sub == "SWING_DAMAGE" or sub == "ENVIRONMENTAL_DAMAGE" or sub == "RANGE_DAMAGE") and nil or r[13]
			self.segments.current.pull = {
				name = srcName and select(1, strsplit("-", srcName)) or "?",
				target = dstName and select(1, strsplit("-", dstName)) or nil,
				spell = spell,
				ours = ours and true or false,
				t = date("%H:%M:%S"),
			}
		end
	end

	-- merge pet damage into the owner
	local owner = (not self.db or self.db.mergePets ~= false) and self.pets[srcGUID] or nil
	local effGUID, effName = srcGUID, srcName
	if IsPet(srcFlags) and owner then
		effGUID = owner
		effName = nil -- resolved via GetPlayerInfoByGUID below
	end
	local effFriendly = IsFriendly(srcFlags) or (owner ~= nil)
	if effFriendly then
		local class = self:ClassOf(effGUID)
		local pname = effName
		if not pname then
			local _, _, _, _, _, _, gname = GetPlayerInfoByGUID and GetPlayerInfoByGUID(effGUID) or nil
			pname = gname or "?"
		end
		pname = pname and select(1, strsplit("-", pname)) or "?"
		for _, seg in ipairs({ self.segments.current, self.segments.overall }) do
			local p = PlayerIn(seg, effGUID, pname, class)
			if DMG_EVENTS[sub] then
				local amount
				if sub == "SWING_DAMAGE" then amount = r[12]
				elseif sub == "ENVIRONMENTAL_DAMAGE" then amount = r[13]
				else amount = r[15] end
				if amount and not IsSecret(amount) and amount > 0 then
					p.dmg = p.dmg + amount
					local spellID = (sub == "SWING_DAMAGE" or sub == "ENVIRONMENTAL_DAMAGE") and nil or r[12]
					local spellName = sub == "SWING_DAMAGE" and (ACTION_SPELL_DAMAGE or "Melee")
						or sub == "ENVIRONMENTAL_DAMAGE" and (ACTION_ENVIRONMENTAL_DAMAGE or "Umgebung")
						or r[13]
					AddSpell(p.spells.dmg, spellID, spellName, amount)
				end
			elseif HEAL_EVENTS[sub] then
				local amount, overheal = r[15], r[16]
				if amount and not IsSecret(amount) then
					if IsSecret(overheal) or not overheal then overheal = 0 end
					local eff = amount - overheal
					p.heal = p.heal + eff
					p.overheal = (p.overheal or 0) + overheal
					AddSpell(p.spells.heal, r[12], r[13], eff)
				end
			elseif sub == "SPELL_INTERRUPT" then
				p.interrupts = (p.interrupts or 0) + 1
			elseif sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN" then
				p.dispels = (p.dispels or 0) + 1
			elseif sub == "SPELL_AURA_BROKEN" or sub == "SPELL_AURA_BROKEN_SPELL" then
				p.ccBreaks = (p.ccBreaks or 0) + 1
			elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" or sub == "SPELL_AURA_APPLIED_DOSE" then
				-- uptime tracking: running auras keep their original start on refresh/dose
				local id = r[12]
				if id and not IsSecret(id) then
					if not p.auraActive then p.auraActive = {} end
					if not p.auraActive[id] then p.auraActive[id] = GetTime() end
					AddSpell(p.spells.aura, id, r[13], 0)
				end
			elseif sub == "SPELL_AURA_REMOVED" then
				local id = r[12]
				if id and not IsSecret(id) and p.auraActive and p.auraActive[id] then
					local dur = GetTime() - p.auraActive[id]
					p.auraActive[id] = nil
					p.auraUp = (p.auraUp or 0) + dur
					local s = p.spells.aura[id]
					if s then s.amt = s.amt + dur end
				end
			end
		end
	end
	-- deaths of friendly players (snapshot of the recent-hit feed = death log)
	if sub == "UNIT_DIED" and dstGUID and IsFriendly(dstFlags) and bit_band and not IsSecret(dstFlags) and bit_band(dstFlags, TYPE_PLAYER) > 0 then
		local dname = dstName and select(1, strsplit("-", dstName)) or "?"
		local feed = self.deathFeed[dstGUID]
		for _, seg in ipairs({ self.segments.current, self.segments.overall }) do
			local p = PlayerIn(seg, dstGUID, dname, self:ClassOf(dstGUID))
			p.deaths = (p.deaths or 0) + 1
			if feed and #feed > 0 then
				local snap = { n = #feed }
				for i = 1, #feed do snap[i] = feed[i] end
				p.dlog = snap
			end
		end
		if feed then wipe(feed) end
	end
	-- damage taken / healing received / friendly fire on friendly targets
	local dstFriendly = dstGUID and IsFriendly(dstFlags)
	if dstFriendly and (DMG_EVENTS[sub] or HEAL_EVENTS[sub]) then
		local amount, overheal, kind
		if DMG_EVENTS[sub] then
			kind = "dmg"
			if sub == "SWING_DAMAGE" then amount = r[12]
			elseif sub == "ENVIRONMENTAL_DAMAGE" then amount = r[13]
			else amount = r[15] end
		else
			kind = "heal"
			amount, overheal = r[15], r[16]
			if IsSecret(overheal) or not overheal then overheal = 0 end
		end
		if amount and not IsSecret(amount) and amount > 0 then
			local eff = kind == "heal" and max(amount - overheal, 0) or amount
			local dname = dstName and select(1, strsplit("-", dstName)) or "?"
			local isPlayer = bit_band and not IsSecret(dstFlags) and bit_band(dstFlags, TYPE_PLAYER) > 0
			local sn = srcName and select(1, strsplit("-", srcName)) or "?"
			local spellID = (sub == "SWING_DAMAGE" or sub == "ENVIRONMENTAL_DAMAGE") and nil or r[12]
			local spellName = sub == "SWING_DAMAGE" and (ACTION_SPELL_DAMAGE or "Melee")
				or sub == "ENVIRONMENTAL_DAMAGE" and (ACTION_ENVIRONMENTAL_DAMAGE or "Umgebung")
				or r[13]
			for _, seg in ipairs({ self.segments.current, self.segments.overall }) do
				local p = PlayerIn(seg, dstGUID, dname, self:ClassOf(dstGUID))
				if kind == "dmg" then
					p.taken = p.taken + amount
					AddSpell(p.spells.taken, spellID, spellName, amount)
					-- friendly fire: source and target both friendly
					if effFriendly and dstGUID ~= effGUID then p.ffire = (p.ffire or 0) + amount end
				else
					p.healTaken = (p.healTaken or 0) + eff
					AddSpell(p.spells.healTaken, spellID, spellName, eff)
				end
			end
			if isPlayer then
				FeedDeath(dstGUID, { t = GetTime(), src = sn, spell = spellName or "?", amt = eff, kind = kind })
			end
		end
	end
	self.dirty = true
end

-- segments --------------------------------------------------------------------
function DM:OnCombatStart()
	self.inCombat = true
	local cur = self.segments.current
	if cur.ended then
		self.segments.current = NewSegment()
		self.segments.current.startT = GetTime()
	end
	-- the next hostile event is the pull: who engaged first and with what
	self.pullPending = true
	self.dirty = true
end

function DM:OnCombatEnd()
	self.inCombat = false
	local cur = self.segments.current
	local dur = GetTime() - (cur.startT or GetTime())
	cur.fightTime = (cur.fightTime or 0) + dur
	cur.ended = true
	self.segments.overall.fightTime = (self.segments.overall.fightTime or 0) + dur
	-- close auras still running on the finished segment so uptime stays sane
	local now = GetTime()
	for _, p in pairs(cur.players or {}) do
		if p.auraActive then
			for id, st in pairs(p.auraActive) do
				local dur = now - st
				p.auraUp = (p.auraUp or 0) + dur
				local s = p.spells.aura and p.spells.aura[id]
				if s then s.amt = s.amt + dur end
			end
			wipe(p.auraActive)
		end
	end
	-- archive the finished fight: history[1] = most recent
	if cur.fightTime > 0.5 then
		local hasData = cur.players and next(cur.players) ~= nil
		if hasData then
			cur.label = format("%s (%ds)", date("%H:%M"), floor(cur.fightTime))
			local hist = self.segments.history or {}
			self.segments.history = hist
			tinsert(hist, 1, cur)
			local cap = (self.db and self.db.historyCount) or 5
			while #hist > cap do tremove(hist) end
		end
	end
	self.dirty = true
end

function DM:Reset()
	self.segments.current = NewSegment()
	self.segments.overall = NewSegment()
	self.segments.overall.startT = nil
	self.segments.history = {}
	-- keep the saved-variables table pointing at the new (empty) segments
	local g = S.db.global
	if g.meter then g.meter.segments = self.segments end
	self.dirty = true
end

-- resolve a window's segment key: "current" | "overall" | "fight:<n>"
local function SegFor(w)
	local segKey = w.segment
	if type(segKey) == "string" and segKey:sub(1, 6) == "fight:" then
		local n = tonumber(segKey:sub(7)) or 1
		local hist = DM.segments.history
		return hist and hist[n]
	end
	return DM.segments[segKey] or DM.segments.current
end
-- short label for the segment header button
local function SegShort(w)
	local segKey = w.segment
	if type(segKey) == "string" and segKey:sub(1, 6) == "fight:" then
		return "#" .. (segKey:sub(7) or "?")
	end
	return segKey == "overall" and "A" or "C"
end
function DM:SegLabel(w)
	local segKey = w.segment
	if type(segKey) == "string" and segKey:sub(1, 6) == "fight:" then
		local n = tonumber(segKey:sub(7)) or 1
		local seg = self.segments.history and self.segments.history[n]
		return seg and (L["Fight"] .. ": " .. (seg.label or "?")) or (L["Fight"] .. " " .. n)
	end
	return segKey == "overall" and L["Overall"] or L["Current fight"]
end
local SaveWindow -- forward decl: defined with the persistence helpers below
-- ordered list of selectable segments for a window (current, history, overall)
function DM:SegmentChoices()
	local out = { "current" }
	for i = 1, #(self.segments.history or {}) do out[#out + 1] = "fight:" .. i end
	out[#out + 1] = "overall"
	return out
end
function DM:SetWindowSegment(w, segKey)
	w.segment = segKey
	SaveWindow(w)
	if w.frame and w.frame.segBtn then w.frame.segBtn.fs:SetText(SegShort(w)) end
	self.dirty = true
end

-- modes -----------------------------------------------------------------------
local MODES = {
	{ key = "damage", label = "Damage" },
	{ key = "dps", label = "DPS" },
	{ key = "healing", label = "Healing" },
	{ key = "hps", label = "HPS" },
	{ key = "taken", label = "Damage Taken" },
	{ key = "overheal", label = "Overheal" },
	{ key = "interrupts", label = "Interrupts" },
	{ key = "dispels", label = "Dispels" },
	{ key = "deaths", label = "Deaths" },
	{ key = "healtaken", label = "Healing Taken" },
	{ key = "ccbreak", label = "CC Breaks" },
	{ key = "ffire", label = "Friendly Fire" },
	{ key = "aurauptime", label = "Aura Uptime" },
	{ key = "threat", label = "Threat" },
}
local function ModeLabel(k)
	for _, m in ipairs(MODES) do if m.key == k then return L[m.label] or m.label end end
	return k
end
local function ModeValue(p, mode, fightTime)
	if mode == "damage" then return p.dmg
	elseif mode == "dps" then return p.dmg / max(fightTime, 1)
	elseif mode == "healing" then return p.heal
	elseif mode == "hps" then return p.heal / max(fightTime, 1)
	elseif mode == "taken" then return p.taken
	elseif mode == "overheal" then return p.overheal or 0
	elseif mode == "healtaken" then return p.healTaken or 0
	elseif mode == "interrupts" then return p.interrupts or 0
	elseif mode == "dispels" then return p.dispels or 0
	elseif mode == "ccbreak" then return p.ccBreaks or 0
	elseif mode == "ffire" then return p.ffire or 0
	elseif mode == "aurauptime" then
		-- closed durations plus the live share of auras still running
		local v = p.auraUp or 0
		if p.auraActive then
			local now = GetTime()
			for _, st in pairs(p.auraActive) do v = v + (now - st) end
		end
		return v
	elseif mode == "threat" then return p.threat or 0
	elseif mode == "deaths" then return p.deaths or 0 end
	return 0
end

function DM:FightTime()
	local seg = self.segments.current
	local t = seg.fightTime
	if self.inCombat and seg.startT then t = t + (GetTime() - seg.startT) end
	return max(t, 0.1), max(self.segments.overall.fightTime, 0.1)
end
-- fight duration of the segment a window shows (history segments are fixed)
function DM:SegTime(w)
	local seg = SegFor(w)
	if not seg then return 0.1 end
	local t = seg.fightTime or 0
	if seg == self.segments.current and self.inCombat and seg.startT then t = t + (GetTime() - seg.startT) end
	return max(t, 0.1)
end

-- window persistence ----------------------------------------------------------
local function WinDB()
	local g = S.db.global
	g.meterWindows = g.meterWindows or {}
	return g.meterWindows
end
SaveWindow = function(w)
	local e = WinDB()[w.idx]
	if e then
		e.mode, e.segment, e.width, e.height, e.maxBars = w.mode, w.segment, w.width, w.height, w.maxBars
		e.dockSide, e.dockTarget = w.dockSide, w.dockTarget
		e.tabs = w.tabs and { unpack(w.tabs) } or nil
		e.minimized, e.hidden = w.minimized, w.hidden
	end
end -- SaveWindow (forward-declared above)

-- single entry point for mode changes: window, saved layout AND the
-- settings panel field stay in sync (so options changes always apply)
local function SetWindowMode(w, mode)
	w.mode = mode
	SaveWindow(w)
	if DM.db then DM.db["win" .. w.idx .. "Mode"] = mode end
	if w.frame and w.frame.title then
		w.frame.title:SetText(ModeLabel(mode) .. (w.idx > 1 and ("  #" .. w.idx) or ""))
	end
	DM.dirty = true
end

-- context menu (custom, Sentinel-styled) ---------------------------------------
local menuFrame
local function GetMenu()
	if menuFrame then return menuFrame end
	menuFrame = CreateFrame("Frame", "SentinelUIMeterMenu", UIParent)
	menuFrame:SetFrameStrata("TOOLTIP")
	menuFrame:SetClampedToScreen(true)
	S:SetTemplate(menuFrame, "Default")
	menuFrame.rows = {}
	menuFrame:SetScript("OnShow", function(m) m.hideT = 0 end)
	menuFrame:SetScript("OnUpdate", function(m, el)
		-- auto-close shortly after the mouse leaves
		if m:IsMouseOver() then m.hideT = 0 return end
		m.hideT = (m.hideT or 0) + el
		if m.hideT > 0.75 then m:Hide() end
	end)
	return menuFrame
end

local function MenuRow(m, i)
	local r = m.rows[i]
	if not r then
		r = CreateFrame("Button", nil, m)
		r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
		r:SetPoint("RIGHT", -4, 0)
		r:SetHeight(18)
		r.check = S:FontString(r, 11, "OUTLINE", S.media.numberFont, nil, "LEFT")
		r.check:SetPoint("LEFT", 2, 0)
		r.text = S:FontString(r, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
		r.text:SetPoint("LEFT", r.check, "RIGHT", 6, 0)
		r.hl = r:CreateTexture(nil, "BACKGROUND")
		r.hl:SetAllPoints()
		r.hl:SetTexture(S.media.blank)
		r.hl:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.25)
		r.hl:Hide()
		m.rows[i] = r
	end
	return r
end

function DM:OpenMenu(w, anchor)
	local m = GetMenu()
	local items = {}
	for _, mode in ipairs(MODES) do
		items[#items + 1] = {
			text = ModeLabel(mode.key), check = w.mode == mode.key,
			func = function() SetWindowMode(w, mode.key) end,
		}
	end
	items[#items + 1] = { sep = true }
	-- segment picker: current fight, archived fights, overall
	items[#items + 1] = {
		text = L["Current fight"], check = w.segment == "current",
		func = function() self:SetWindowSegment(w, "current") end,
	}
	for i, seg in ipairs(self.segments.history or {}) do
		local n = i
		items[#items + 1] = {
			text = (L["Fight"] .. " " .. n) .. "  " .. (seg.label or ""), check = w.segment == "fight:" .. n,
			func = function() self:SetWindowSegment(w, "fight:" .. n) end,
		}
	end
	items[#items + 1] = {
		text = L["Overall"], check = w.segment == "overall",
		func = function() self:SetWindowSegment(w, "overall") end,
	}
	-- docking: free -> dock on any side of the previous window; docked -> undock
	if w.dockSide then
		items[#items + 1] = {
			text = L["Undock"], check = true,
			func = function() w.dockSide, w.dockTarget = nil, nil SaveWindow(w) self:LayoutWindows() end,
		}
	elseif w.idx > 1 then
		for _, side in ipairs({ "RIGHT", "LEFT", "TOP", "BOTTOM" }) do
			items[#items + 1] = {
				text = L["Dock"] .. ": " .. L[side],
				func = function() w.dockSide = side w.dockTarget = w.idx - 1 SaveWindow(w) self:LayoutWindows() end,
			}
		end
	end
	-- tabs: remember the current mode as a tab on this window
	items[#items + 1] = {
		text = L["Add tab (current mode)"],
		func = function()
			w.tabs = w.tabs or {}
			for _, t in ipairs(w.tabs) do if t == w.mode then return end end
			w.tabs[#w.tabs + 1] = w.mode
			SaveWindow(w) self:RefreshTabs(w)
		end,
	}
	if w.tabs and #w.tabs > 0 then
		items[#items + 1] = {
			text = L["Remove current tab"],
			func = function()
				for i, t in ipairs(w.tabs) do if t == w.mode then tremove(w.tabs, i) break end end
				SaveWindow(w) self:RefreshTabs(w)
			end,
		}
	end
	items[#items + 1] = { sep = true }
	items[#items + 1] = {
		text = L["New window"],
		func = function() self:NewWindow() end,
	}
	if #self.windows > 1 then
		items[#items + 1] = {
			text = L["Close window"],
			func = function() self:CloseWindow(w) end,
		}
	end
	items[#items + 1] = { text = L["Reset data"], func = function() self:Reset() end }
	items[#items + 1] = { text = L["Settings"], func = function() if S.ToggleConfig then S:ToggleConfig("damagemeter") end end }

	local width = 150
	for i, it in ipairs(items) do
		local r = MenuRow(m, i)
		if it.sep then
			r:SetHeight(9)
			r.text:SetText("")
			r.check:SetText("")
			r.hl:Hide()
			r:SetScript("OnClick", nil)
			r:SetScript("OnEnter", nil)
			r:SetScript("OnLeave", nil)
			r:EnableMouse(false)
		else
			r:SetHeight(18)
			r.check:SetText(it.check and "|cff" .. S.accentHex .. "✓|r" or "")
			r.text:SetText(it.text)
			r:SetScript("OnClick", function() m:Hide() S:SafeCall("Meter:Menu", it.func) end)
			r:EnableMouse(true)
			r:SetScript("OnEnter", function(s) s.hl:Show() end)
			r:SetScript("OnLeave", function(s) s.hl:Hide() end)
			local tw = r.text.GetStringWidth and r.text:GetStringWidth() or 0
			width = max(width, tw + 40)
		end
		r:Show()
	end
	for i = #items + 1, #m.rows do m.rows[i]:Hide() end
	m:SetSize(width, 8 + #items * 18)
	m:ClearAllPoints()
	m:SetPoint("BOTTOMLEFT", anchor or UIParent, "TOPRIGHT", 0, 4)
	m:Show()
end

-- windows ---------------------------------------------------------------------
local sortedList = {}
-- live threat list (mode "threat" ignores segment data)
local threatList = {}
function DM:ThreatList()
	wipe(threatList)
	local function add(unit)
		if not UnitExists(unit) then return end
		local isT, status, pct, rawpct, val = UnitDetailedThreatSituation(unit, "target")
		if val and not IsSecret(val) and val > 0 then
			local guid = UnitGUID(unit)
			threatList[#threatList + 1] = {
				name = select(1, strsplit("-", UnitName(unit) or "?")),
				class = self:ClassOf(guid), threat = val, tpct = rawpct or pct, isTank = isT,
			}
		end
	end
	add("player")
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, min(n, 40) do add(prefix .. i) end
	return threatList
end

function DM:RebuildWindow(w)
	local f = w.frame
	if not f or not f:IsShown() or w.minimized then return end
	local db = self.db
	local mode = w.mode
	local seg = SegFor(w)
	if not seg then
		-- saved "fight:N" segment no longer exists (reset / history cap)
		w.segment = "current"
		seg = SegFor(w)
	end
	local fightTime = self:SegTime(w)
	wipe(sortedList)
	local total = 0
	if mode == "threat" then
		for _, p in ipairs(self:ThreatList()) do
			sortedList[#sortedList + 1] = p
			total = total + p.threat
		end
	elseif seg then
		for _, p in pairs(seg.players) do
			local v = ModeValue(p, mode, fightTime)
			if v > 0 then
				sortedList[#sortedList + 1] = p
				total = total + v
			end
		end
	end
	sort(sortedList, function(a, b) return ModeValue(a, mode, fightTime) > ModeValue(b, mode, fightTime) end)

	local bh, sp = db.barHeight or 16, db.spacing or 1
	-- fixed-size viewport: number of visible rows derives from the frame height
	local viewH = max(20, f:GetHeight() - (f.topInset or 26) - 4)
	f.body:SetHeight(viewH)
	local rows = max(1, min(db.maxBars or 25, floor((viewH + sp) / (bh + sp))))
	local totalN = #sortedList
	w.rows, w.total = rows, totalN
	w.scroll = max(0, min(w.scroll or 0, max(0, totalN - rows)))
	local shown = 0
	for i = w.scroll + 1, min(totalN, w.scroll + rows) do
		local p = sortedList[i]
		local v = ModeValue(p, mode, fightTime)
		shown = shown + 1
		local bar = f.bars[shown]
		if not bar then
			bar = S:CreateStatusBar(f.body, nil, "Default")
			bar:EnableMouse(true)
			-- forward right-click menu and window dragging through the bars
			bar:SetScript("OnMouseUp", function(s2, btn)
				if btn == "RightButton" then DM:OpenMenu(w, f)
				elseif btn == "LeftButton" and s2.player then DM:OpenDetail(w, s2.player) end
			end)
			bar:RegisterForDrag("LeftButton")
			bar:SetScript("OnDragStart", function()
				if f.suiDetach then f.suiDetach() end
				local dh = f:GetScript("OnDragStart")
				if dh then dh(f) end
			end)
			bar:SetScript("OnDragStop", function()
				local dh = f:GetScript("OnDragStop")
				if dh then dh(f) end
			end)
			bar.cicon = bar:CreateTexture(nil, "OVERLAY")
			bar.cicon:SetPoint("LEFT", 2, 0)
			bar.cicon:SetTexture([[Interface\GLUES\CHARACTERCREATE\UI-CharacterCreate-Classes]])
			-- FontString lands on suiTextOverlay (above the fill), not the backdrop
			bar.name = S:FontString(bar, db.fontSize or 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
			bar.name:SetPoint("LEFT", 4, 0)
			bar.val = S:FontString(bar, db.fontSize or 11, "OUTLINE", S.media.numberFont, nil, "RIGHT")
			bar.val:SetPoint("RIGHT", -12, 0) -- leave room for the scrollbar
			bar:SetScript("OnEnter", function(self2)
				local pl = self2.player
				if not pl or not pl.spells then return end
				GameTooltip:SetOwner(self2, "ANCHOR_TOP")
				GameTooltip:AddLine(pl.name or "?", 1, 1, 1)
				local spells = (w.mode == "healing" or w.mode == "hps" or w.mode == "overheal") and pl.spells.heal
					or (w.mode == "taken" or w.mode == "ffire") and pl.spells.taken
					or w.mode == "healtaken" and pl.spells.healTaken
					or w.mode == "aurauptime" and pl.spells.aura
					or pl.spells.dmg
				local list = {}
				for _, s in pairs(spells) do list[#list + 1] = s end
				sort(list, function(a, b) return a.amt > b.amt end)
				for j = 1, min(6, #list) do
					local s = list[j]
					local amt = w.mode == "aurauptime" and format("%ds", s.amt) or S:Abbrev(s.amt)
					GameTooltip:AddDoubleLine(s.name, format("%s (%d)", amt, s.n), 1, 1, 1, 0.7, 0.7, 0.7)
				end
				GameTooltip:Show()
			end)
			bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
			f.bars[shown] = bar
		end
		bar.player = p
		-- class icon in front of the name
		local ico = CLASS_ICON_TCOORDS and p.class and CLASS_ICON_TCOORDS[p.class]
		if ico then
			bar.cicon:SetSize(bh - 4, bh - 4)
			bar.cicon:SetTexCoord(ico[1], ico[2], ico[3], ico[4])
			bar.cicon:Show()
			bar.name:ClearAllPoints()
			bar.name:SetPoint("LEFT", 2 + (bh - 2), 0)
		else
			bar.cicon:Hide()
			bar.name:ClearAllPoints()
			bar.name:SetPoint("LEFT", 4, 0)
		end
		-- single LEFT anchor: a right anchor pinned to bar.val collapses the
		-- FontString to zero width on narrow windows and the name vanishes
		S:SetFont(bar.name, S.media.unitFont, db.fontSize or 11, "OUTLINE")
		S:SetFont(bar.val, S.media.numberFont, db.fontSize or 11, "OUTLINE")
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -((shown - 1) * (bh + sp)))
		bar:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -((shown - 1) * (bh + sp)))
		bar:SetHeight(bh)
		bar:SetStatusBarTexture(S:Fetch("statusbar", S.db.profile.general.statusbar, "Sentinel"))
		if db.classColor and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class] then
			local c = RAID_CLASS_COLORS[p.class]
			bar:SetStatusBarColor(c.r, c.g, c.b)
		else
			bar:SetStatusBarColor(S.accent.r, S.accent.g, S.accent.b)
		end
		local topV = sortedList[1] and ModeValue(sortedList[1], mode, fightTime) or 1
		bar:SetMinMaxValues(0, max(topV, 0.01))
		bar:SetValue(v)
		local pct = total > 0 and (v / total * 100) or 0
		local perSec = (mode == "damage" or mode == "healing" or mode == "taken" or mode == "overheal" or mode == "healtaken" or mode == "ffire") and v / max(fightTime, 0.1) or nil
		local txt = S:Abbrev(v)
		if mode == "threat" and p.tpct then
			txt = txt .. format(" | %d%%", p.tpct)
			if p.isTank then txt = L["TANKING"] .. " " .. txt end
		elseif mode == "aurauptime" then
			txt = format("%ds | %d%%", v, min(100, v / max(fightTime, 0.1) * 100))
		else
			if perSec and db.showPerSecond ~= false then txt = txt .. format(" (%.0f/s)", perSec) end
			if db.showPercent ~= false then txt = txt .. format(" | %d%%", pct) end
		end
		bar.val:SetText(txt)
		-- truncate the name against the measured value-text width; on very
		-- narrow windows fall back to the rank only, never an empty string
		local pname = format("%d. %s", i, p.name or "?")
		bar.name:SetText(pname)
		local iconW = (bar.cicon:IsShown() and (bh - 2) or 4) + 12
		local avail = (f.body:GetWidth() or 0) - iconW - (bar.val:GetStringWidth() or 0) - 14
		if avail < 14 then
			bar.name:SetText(format("%d.", i))
		else
			local guard = 0
			while bar.name:GetStringWidth() > avail and #pname > 1 and guard < 60 do
				pname = Utf8Chop(pname)
				bar.name:SetText(pname .. "…")
				guard = guard + 1
			end
		end
		bar:Show()
	end
	for i = shown + 1, #f.bars do f.bars[i]:Hide() end
	-- scrollbar state (thin accent slider on the right edge)
	if f.scrollBar then
		local need = totalN > rows
		f.scrollBar:SetShown(need)
		if need then
			f.scrollBar:SetMinMaxValues(0, totalN - rows)
			f.scrollBar:SetValue(w.scroll)
		end
	end
end

function DM:Rebuild()
	for _, w in ipairs(self.windows) do self:RebuildWindow(w) end
end

local CHANNELS = { SAY = "SAY", PARTY = "PARTY", RAID = "RAID", GUILD = "GUILD" }
function DM:Report(w)
	local seg = SegFor(w)
	if not seg then return end
	local fightTime = self:SegTime(w)
	local list = {}
	for _, p in pairs(seg.players) do
		local v = ModeValue(p, w.mode, fightTime)
		if v > 0 then list[#list + 1] = { p = p, v = v } end
	end
	sort(list, function(a, b) return a.v > b.v end)
	local ch = self.db.reportChannel or "AUTO"
	if ch == "AUTO" then ch = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY") end
	if ch == "PARTY" and not IsInGroup() then ch = "SAY" end
	if ch == "RAID" and not IsInRaid() then ch = IsInGroup() and "PARTY" or "SAY" end
	if ch == "GUILD" and not IsInGuild() then ch = "SAY" end
	SendChatMessage(format("SentinelUI - %s (%s):", ModeLabel(w.mode), self:SegLabel(w)), ch)
	for i = 1, min(5, #list) do
		local e = list[i]
		SendChatMessage(format("%d. %s - %s", i, e.p.name or "?", S:Abbrev(e.v)), ch)
	end
end

function DM:CycleMode(w)
	for i, m in ipairs(MODES) do
		if m.key == w.mode then
			SetWindowMode(w, MODES[(i % #MODES) + 1].key)
			break
		end
	end
	self:RebuildWindow(w)
end

function DM:LayoutWindows()
	-- docked windows anchor to a side of another (earlier) window
	for i, w in ipairs(self.windows) do
		local f = w.frame
		if w.dockSide and self.windows[w.dockTarget or (i - 1)] and (w.dockTarget or (i - 1)) < i then
			local t = self.windows[w.dockTarget or (i - 1)].frame
			f:ClearAllPoints()
			if w.dockSide == "RIGHT" then f:SetPoint("TOPLEFT", t, "TOPRIGHT", 3, 0)
			elseif w.dockSide == "LEFT" then f:SetPoint("TOPRIGHT", t, "TOPLEFT", -3, 0)
			elseif w.dockSide == "TOP" then f:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 0, 3)
			elseif w.dockSide == "BOTTOM" then f:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
			end
			if f.suiMover then f.suiMover:Hide() end
		elseif f.suiMover then
			-- free window: back on its mover
			f:ClearAllPoints()
			f:SetPoint("CENTER", f.suiMover, "CENTER")
		end
	end
end

function DM:NewWindow()
	if #self.windows >= MAX_WINDOWS then S:Print(L["Maximum windows reached."]) return end
	local idx = #self.windows + 1
	WinDB()[idx] = { mode = "damage", segment = "current", dockSide = "RIGHT", dockTarget = idx - 1 }
	self:CreateWindow(idx)
	self:LayoutWindows()
	self.dirty = true
end

function DM:SetMinimized(w, on)
	w.minimized = on and true or nil
	local f = w.frame
	if not f then return end
	f.body:SetShown(not on)
	if f.scrollBar then f.scrollBar:Hide() end
	if f.grip then f.grip:SetShown(not on) end
	f:SetHeight(on and f.topInset or (w.height or 180))
	f:SetResizable(not on)
	if f.minBtn then f.minBtn.fs:SetText(on and "+" or "–") end
	SaveWindow(w)
	self.dirty = true
end

function DM:HideWindow(w)
	if #self.windows > 1 then
		self:CloseWindow(w)
		return
	end
	w.hidden = true
	SaveWindow(w)
	if w.frame then w.frame:Hide() end
end

function DM:CloseWindow(w)
	if #self.windows <= 1 then
		self:HideWindow(w)
		return
	end
	w.frame:Hide()
	local e = WinDB()
	e[w.idx] = nil
	-- compact the window list
	local wins = {}
	for i, ww in ipairs(self.windows) do if ww ~= w then wins[#wins + 1] = ww end end
	self.windows = wins
	for i, ww in ipairs(self.windows) do ww.idx = i end
	local newDB = {}
	for i, ww in ipairs(self.windows) do
		newDB[i] = { mode = ww.mode, segment = ww.segment, dockSide = ww.dockSide, dockTarget = ww.dockTarget, width = ww.width, height = ww.height, maxBars = ww.maxBars, tabs = ww.tabs and { unpack(ww.tabs) } or nil }
		if newDB[i].dockTarget and newDB[i].dockTarget >= i then newDB[i].dockTarget = nil newDB[i].dockSide = nil ww.dockSide = nil ww.dockTarget = nil end
	end
	wipe(e)
	for i, d in pairs(newDB) do e[i] = d end
	self:LayoutWindows()
	self.dirty = true
end

function DM:CreateWindow(idx)
	local db = self.db
	local saved = WinDB()[idx] or {}
	local w = {
		idx = idx,
		mode = saved.mode or "damage",
		segment = saved.segment or "current",
		width = saved.width or db.width or 250,
		height = saved.height or 180,
		maxBars = saved.maxBars or db.maxBars or 8,
		scroll = 0,
		dockSide = saved.dockSide,
		dockTarget = saved.dockTarget,
		tabs = saved.tabs and { unpack(saved.tabs) } or nil,
		minimized = saved.minimized,
		hidden = saved.hidden,
	}
	local f = CreateFrame("Frame", "SentinelUIMeter" .. idx, UIParent)
	f:SetSize(w.width, w.height)
	S:SetTemplate(f, "Transparent", "TOP")
	f:SetFrameStrata("MEDIUM")
	f:EnableMouse(true)
	w.frame = f

	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(22)
	header:EnableMouse(true)
	header:SetScript("OnMouseUp", function(_, btn)
		if btn == "RightButton" then DM:OpenMenu(w, header) end
	end)
	f.header = header
	f:SetScript("OnMouseUp", function(_, btn)
		if btn == "RightButton" then DM:OpenMenu(w, f) end
	end)

	f.logo = f:CreateTexture(nil, "OVERLAY")
	f.logo:SetSize(14, 14)
	f.logo:SetPoint("LEFT", header, "LEFT", 5, 0)
	f.logo:SetTexture(S.media.iconMeter)
	f.logo:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)

	f.title = S:FontString(header, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 4, 0)
	f.title:SetText(idx == 1 and L["Damage Meter"] or (L["Damage Meter"] .. " " .. idx))
	S:RegisterAccent(f.title, "text")

	local function HBtn(label, func, wdt, icon, tip)
		local b = CreateFrame("Button", nil, header)
		b:SetSize(wdt or 16, 16)
		S:CreateBackdrop(b, "Default")
		if icon then
			b.icon = b:CreateTexture(nil, "OVERLAY")
			b.icon:SetPoint("TOPLEFT", 3, -3)
			b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
			b.icon:SetTexture(icon)
			b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
			b.icon:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
		end
		b.fs = S:FontString(b, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
		b.fs:SetPoint("TOPLEFT", 2, 0)
		b.fs:SetPoint("BOTTOMRIGHT", -2, 0)
		b.fs:SetText(label or "")
		b.fs:SetTextColor(1, 1, 1)
		b:SetScript("OnEnter", function(s2)
			s2:SetAlpha(0.8)
			if tip and GameTooltip then
				GameTooltip:SetOwner(s2, "ANCHOR_BOTTOM")
				GameTooltip:AddLine(tip, 1, 1, 1)
				GameTooltip:AddLine(L["Right-click window: options menu"], 0.6, 0.6, 0.6)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function(s2) s2:SetAlpha(1) if GameTooltip then GameTooltip:Hide() end end)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, btn)
			if btn == "RightButton" then DM:OpenMenu(w, b) else S:SafeCall("Meter:Btn", func) end
		end)
		return b
	end

	-- window chrome: close (✕) and minimize/maximize (–/+) at the far right
	f.closeBtn = HBtn("X", function() DM:HideWindow(w) end, 15, nil, L["Close window"])
	f.closeBtn:SetPoint("RIGHT", -4, -1)
	f.minBtn = HBtn(w.minimized and "+" or "–", function() DM:SetMinimized(w, not w.minimized) end, 15, nil, L["Minimize window"])
	f.minBtn:SetPoint("RIGHT", f.closeBtn, "LEFT", -3, 0)
	f.segBtn = HBtn(SegShort(w), function()
		local choices = DM:SegmentChoices()
		for i, k in ipairs(choices) do
			if k == w.segment then
				DM:SetWindowSegment(w, choices[(i % #choices) + 1])
				break
			end
		end
	end, 20, nil, L["Current fight / Fight history / Overall"])
	f.segBtn:SetPoint("RIGHT", f.minBtn, "LEFT", -3, -1)
	f.resetBtn = HBtn("", function() DM:Reset() end, 18, S.media.iconReset, L["Reset data"])
	f.resetBtn:SetPoint("RIGHT", f.segBtn, "LEFT", -3, 0)
	f.reportBtn = HBtn("", function() DM:Report(w) end, 18, S.media.iconReport, L["Report to chat"])
	f.reportBtn:SetPoint("RIGHT", f.resetBtn, "LEFT", -3, 0)

	-- title shows the current mode; left-click on the header
	-- cycles modes when the mouse did not move (i.e. it was a click, not a drag)
	f.title:SetText(ModeLabel(w.mode) .. (idx > 1 and ("  #" .. idx) or ""))
	header:SetScript("OnMouseDown", function(_, btn)
		if btn == "LeftButton" then f._downX = select(1, GetCursorPosition()) end
	end)
	header:HookScript("OnMouseUp", function(_, btn)
		if btn == "LeftButton" and f._downX then
			local moved = abs((select(1, GetCursorPosition()) or 0) - f._downX) > 6
			if not moved then DM:CycleMode(w) end
			f._downX = nil
		end
	end)

	-- clip the title so it never runs underneath the header buttons
	f.title:SetPoint("RIGHT", f.reportBtn, "LEFT", -6, 0)

	f.body = CreateFrame("Frame", nil, f)
	f.body:SetPoint("TOPLEFT", 4, -26)
	f.body:SetPoint("TOPRIGHT", -4, -26)
	if f.body.SetClipsChildren then f.body:SetClipsChildren(true) end
	S:CreateBackdrop(f.body, "Default")
	f.bars = {}

	-- thin scrollbar on the right edge (visible only when rows overflow)
	local sb = CreateFrame("Slider", nil, f)
	sb:SetWidth(6)
	sb:SetOrientation("VERTICAL")
	sb:SetValueStep(1)
	sb:SetMinMaxValues(0, 0)
	sb:SetValue(0)
	S:CreateBackdrop(sb, "Default")
	sb:SetThumbTexture([[Interface\Buttons\WHITE8X8]])
	local th = sb:GetThumbTexture()
	if th then
		th:SetSize(6, 24)
		th:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
		S:RegisterAccent(th, "texture")
	end
	sb:SetScript("OnValueChanged", function(_, v)
		v = floor(v + 0.5)
		if v ~= (w.scroll or 0) then w.scroll = v DM:RebuildWindow(w) end
	end)
	sb:Hide()
	f.scrollBar = sb

	-- mouse wheel scrolls the bar list
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		local mx = max(0, (w.total or 0) - (w.rows or 1))
		local s2 = max(0, min(mx, (w.scroll or 0) - delta))
		if s2 ~= w.scroll then w.scroll = s2 DM:RebuildWindow(w) end
	end)

	-- resize grip (bottom-right): native StartSizing; horizontal = width, vertical = bar count
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(160, 60, 900, 800) else f:SetMinResize(160, 60) f:SetMaxResize(900, 800) end
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -1, 1)
	grip:SetFrameLevel(f:GetFrameLevel() + 10)
	grip.tex = grip:CreateTexture(nil, "OVERLAY")
	grip.tex:SetAllPoints()
	grip.tex:SetTexture([[Interface\CHATFRAME\UI-ChatIM-SizeGrabber-Up]])
	grip:SetScript("OnMouseDown", function(_, btn)
		if btn ~= "LeftButton" then return end
		f.sizing = true
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		f.sizing = nil
		f:StopMovingOrSizing()
		SaveWindow(w)
	end)
	f:SetScript("OnSizeChanged", function(_, newW, newH)
		if not f.sizing then return end
		w.width = floor(newW + 0.5)
		w.height = floor(newH + 0.5)
		DM.dirty = true
	end)
	f.grip = grip

	f:SetScript("OnUpdate", function(_, el)
		if f.sizing then return end -- grip drives updates while resizing
		f.t = (f.t or 0) + el
		if f.t < 0.4 then return end
		f.t = 0
		if DM.dirty or DM.inCombat then
			DM:RebuildWindow(w)
			if w.idx == #DM.windows then DM.dirty = nil end
		end
	end)
	-- tab strip: one small button per saved mode, under the title row
	f.tabBtns = {}
	f.topInset = 26
	self:RefreshTabs(w)

	local mname = "damageMeter" .. idx
	S:CreateMover(f, mname, L["Damage Meter"] .. (idx > 1 and (" " .. idx) or ""), { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -320 - (idx - 1) * 260, 200 }, "general")
	S:AttachMoverDrag(header, mname)
	S:AttachMoverDrag(f, mname) -- whole window drags (bars only take tooltips)
	-- dragging a docked window detaches it first: the hook
	-- runs before AttachMoverDrag's own OnDragStart
	local function DetachForDrag()
		if not w.dockSide or not f.suiMover then return end
		local l, b, ww, hh = f:GetRect()
		local es = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
		w.dockSide, w.dockTarget = nil, nil
		SaveWindow(w)
		f.suiMover:ClearAllPoints()
		f.suiMover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * es, b * es)
		f.suiMover:SetSize(ww * es, hh * es)
		self:LayoutWindows() -- re-anchors f to its mover (same spot, no jump)
	end
	header:HookScript("OnDragStart", DetachForDrag)
	f:HookScript("OnDragStart", DetachForDrag)
	f.suiDetach = DetachForDrag
	self.windows[idx] = w
	if w.minimized then self:SetMinimized(w, true) end
	if w.hidden then f:Hide() end
end

function DM:RefreshTabs(w)
	local f = w.frame
	if not f then return end
	local tabs = w.tabs or {}
	local n = #tabs
	f.topInset = 26 + (n > 0 and 15 or 0)
	f.header:SetHeight(f.topInset - 4)
	f.body:ClearAllPoints()
	f.body:SetPoint("TOPLEFT", 4, -f.topInset)
	f.body:SetPoint("TOPRIGHT", -4, -f.topInset)
	if f.scrollBar then
		f.scrollBar:ClearAllPoints()
		f.scrollBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -f.topInset + 1)
		f.scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 16)
	end
	local x = 4
	for i = 1, n do
		local tb = f.tabBtns[i]
		if not tb then
			tb = CreateFrame("Button", nil, f.header)
			tb:SetHeight(13)
			S:CreateBackdrop(tb, "Default")
			tb.fs = S:FontString(tb, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
			tb.fs:SetPoint("TOPLEFT", 2, 0)
			tb.fs:SetPoint("BOTTOMRIGHT", -2, 0)
			tb:SetScript("OnClick", function()
				SetWindowMode(w, tabs[i])
				self:RefreshTabs(w)
			end)
			f.tabBtns[i] = tb
		end
		local mode = tabs[i]
		tb.fs:SetText(ModeLabel(mode))
		local tw = tb.fs.GetStringWidth and tb.fs:GetStringWidth() or 30
		tb:SetWidth(tw + 10)
		tb:ClearAllPoints()
		tb:SetPoint("BOTTOMLEFT", f.header, "BOTTOMLEFT", x, 1)
		x = x + tw + 12
		if mode == w.mode then
			tb.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
		else
			tb.fs:SetTextColor(0.6, 0.6, 0.6)
		end
		tb:Show()
	end
	for i = n + 1, #f.tabBtns do f.tabBtns[i]:Hide() end
	self.dirty = true
end

-- detail window: per-player spell breakdown (or death feed for "deaths")
function DM:CreateDetailFrame()
	local d = CreateFrame("Frame", "SentinelUIMeterDetail", UIParent)
	d:SetSize(230, 250)
	d:SetFrameStrata("HIGH")
	S:SetTemplate(d, "Default")
	d:EnableMouse(true)
	d:SetMovable(true)
	d:RegisterForDrag("LeftButton")
	d:SetScript("OnDragStart", d.StartMoving)
	d:SetScript("OnDragStop", d.StopMovingOrSizing)
	d:SetClampedToScreen(true)

	d.title = S:FontString(d, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	d.title:SetPoint("TOPLEFT", 6, -5)
	d.title:SetPoint("TOPRIGHT", -24, -5)
	S:RegisterAccent(d.title, "text")

	local cb = CreateFrame("Button", nil, d)
	cb:SetSize(14, 14)
	cb:SetPoint("TOPRIGHT", -5, -4)
	S:CreateBackdrop(cb, "Default")
	cb.fs = S:FontString(cb, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
	cb.fs:SetPoint("TOPLEFT", 2, 0)
	cb.fs:SetPoint("BOTTOMRIGHT", -2, 0)
	cb.fs:SetText("x")
	cb:SetScript("OnClick", function() d:Hide() end)

	d.body = CreateFrame("Frame", nil, d)
	d.body:SetPoint("TOPLEFT", 5, -22)
	d.body:SetPoint("BOTTOMRIGHT", -5, 5)
	if d.body.SetClipsChildren then d.body:SetClipsChildren(true) end
	d.rows = {}
	self.detailFrame = d
	d:Hide()
	return d
end

local detailTmp = {}
function DM:RefreshDetail()
	local d = self.detailFrame
	if not d or not d:IsShown() then return end
	local p, mode = d.player, d.mode
	if not p then d:Hide() return end
	d.title:SetText(format("%s — %s", p.name or "?", ModeLabel(mode)))
	local bh = 16
	local shown = 0
	wipe(detailTmp)
	if mode == "deaths" and p.dlog then
		-- death log: recent feed entries, latest first
		for i = #p.dlog, 1, -1 do
			local e = p.dlog[i]
			detailTmp[#detailTmp + 1] = {
				name = format("%s — %s", e.spell or "?", e.src or "?"),
				amt = e.amt or 0, n = 0, heal = e.kind == "heal",
			}
		end
	else
		local spells = (mode == "healing" or mode == "hps" or mode == "overheal") and p.spells.heal
			or (mode == "taken" or mode == "ffire") and p.spells.taken
			or mode == "healtaken" and p.spells.healTaken
			or mode == "aurauptime" and p.spells.aura
			or p.spells.dmg
		for _, s in pairs(spells) do detailTmp[#detailTmp + 1] = s end
		sort(detailTmp, function(a, b) return a.amt > b.amt end)
	end
	local total = 0
	for _, s in ipairs(detailTmp) do total = total + (s.amt or 0) end
	local maxAmt = detailTmp[1] and detailTmp[1].amt or 1
	for i, s in ipairs(detailTmp) do
		if shown >= 12 then break end
		shown = shown + 1
		local row = d.rows[shown]
		if not row then
			row = S:CreateStatusBar(d.body, nil, "Default")
			row.name = S:FontString(row, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
			row.name:SetPoint("LEFT", 4, 0)
			row.val = S:FontString(row, 10, "OUTLINE", S.media.numberFont, nil, "RIGHT")
			row.val:SetPoint("RIGHT", -4, 0)
			row.name:SetPoint("RIGHT", row.val, "LEFT", -4, 0)
			d.rows[shown] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", d.body, "TOPLEFT", 0, -((shown - 1) * (bh + 1)))
		row:SetPoint("TOPRIGHT", d.body, "TOPRIGHT", 0, -((shown - 1) * (bh + 1)))
		row:SetHeight(bh)
		row:SetMinMaxValues(0, max(maxAmt, 1))
		row:SetValue(s.amt or 0)
		if s.heal then row:SetStatusBarColor(0.35, 0.75, 0.35)
		elseif mode == "deaths" then row:SetStatusBarColor(0.75, 0.3, 0.3)
		else row:SetStatusBarColor(S.accent.r, S.accent.g, S.accent.b) end
		row.name:SetText(format("%d. %s", shown, s.name or "?"))
		local pct = total > 0 and floor((s.amt or 0) / total * 100 + 0.5) or 0
		local amtTxt = mode == "aurauptime" and format("%ds", s.amt or 0) or S:Abbrev(s.amt)
		row.val:SetText(s.n and s.n > 0 and format("%s (%d, %d%%)", amtTxt, s.n, pct) or format("%s (%d%%)", amtTxt, pct))
		row:Show()
	end
	for i = shown + 1, #d.rows do d.rows[i]:Hide() end
	d:SetHeight(27 + max(1, shown) * (bh + 1))
end

function DM:OpenDetail(w, p)
	if not p or w.mode == "threat" then return end
	local d = self.detailFrame or self:CreateDetailFrame()
	d.player, d.mode = p, w.mode
	d:ClearAllPoints()
	d:SetPoint("TOPLEFT", w.frame, "TOPRIGHT", 6, 0)
	d:Show()
	self:RefreshDetail()
end

function DM:Update()
	self.db = S.db.profile.damagemeter
	local db = self.db
	local saved = WinDB()
	if #saved == 0 and #self.windows == 0 then
		saved[1] = { mode = "damage", segment = "current", docked = false }
	end
	for i = 1, MAX_WINDOWS do
		local s = saved[i]
		local w = self.windows[i]
		if s then
			if not w then self:CreateWindow(i) w = self.windows[i] end
			w.mode = s.mode or w.mode or "damage"
			local sm = db["win" .. i .. "Mode"] -- settings panel overrides the saved mode
			if sm and sm ~= w.mode then SetWindowMode(w, sm) end
			w.segment = s.segment or "current"
			if s.width then w.width = s.width w.frame:SetWidth(s.width) end
			if s.height then w.height = s.height w.frame:SetHeight(s.height) end
			if s.maxBars then w.maxBars = s.maxBars end
			if w.frame.title then w.frame.title:SetText(ModeLabel(w.mode) .. (w.idx > 1 and ("  #" .. w.idx) or "")) end
			w.hidden = s.hidden
			if w.minimized ~= s.minimized then w.minimized = s.minimized self:SetMinimized(w, w.minimized) end
			w.frame:SetShown(self.db.enable ~= false and not w.hidden)
		elseif w then
			w.frame:Hide()
		end
	end
	self:LayoutWindows()
	self.dirty = true
	self:Rebuild()
end

function DM:Initialize()
	self.db = S.db.profile.damagemeter
	-- segment data lives in the global (saved) db: it survives /reload.
	-- GetTime() only restarts with the client process, so a small value at
	-- PLAYER_LOGIN means a real WoW restart -> wipe the stored data then.
	local g = S.db.global
	g.meter = g.meter or {}
	if g.meter.segments and (GetTime() or 0) > 120 then
		self.segments = g.meter.segments
		self.classCache = g.meter.classCache or self.classCache
		-- older saves may lack the tables added later
		self.segments.current = self.segments.current or NewSegment()
		self.segments.overall = self.segments.overall or NewSegment()
		self.segments.history = self.segments.history or {}
		-- aura start times are GetTime() stamps and stale after a reload
		local function ClearActive(seg)
			if not seg then return end
			for _, p in pairs(seg.players or {}) do
				if p.auraActive then wipe(p.auraActive) end
			end
		end
		ClearActive(self.segments.current)
		ClearActive(self.segments.overall)
		for _, seg in ipairs(self.segments.history or {}) do ClearActive(seg) end
	else
		g.meter.segments = self.segments
		g.meter.classCache = self.classCache
	end
	self:RefreshPets()
	self:Update()
	if not CombatLogGetCurrentEventInfo then return end
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLog")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() DM:RefreshPets() end)
	self:RegisterUnitEvent("UNIT_PET", function() DM:RefreshPets() end, "player")
	S:RegisterChatCommand("meter", function()
		for _, w in ipairs(DM.windows) do
			local show = not w.frame:IsShown()
			w.frame:SetShown(show)
			if show and w.hidden then w.hidden = nil SaveWindow(w) end
		end
	end)
	S:LogInfo("meter", format("init: windows=%d cleu=%s bit=%s secretAPI=%s affConst=%s",
		#self.windows, tostring(CombatLogGetCurrentEventInfo ~= nil),
		tostring(_G.bit ~= nil), tostring(issecretvalue ~= nil),
		tostring(COMBATLOG_OBJECT_AFFILIATION_MINE ~= nil)))
end
