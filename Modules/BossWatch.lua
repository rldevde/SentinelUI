-- BossWatch: encounter timers & warnings (own implementation, SentinelUI name).
-- Timer bars on a movable stack, center-screen warnings, pull/break timers.
-- The combat-log engine is rule-driven: Modules/BossWatch/Data.lua maps spell
-- ids to recast timers / warnings, so the dataset is easy to extend. Pull
-- timers interop with DBM (D4 prefix): ours are broadcast, theirs accepted.
local _, ns = ...
local S = ns.S
local L = S.L
local BW = S:NewModule("BossWatch", "bosswatch")

local _G = _G
local ipairs, pairs, wipe, tinsert, tremove = ipairs, pairs, wipe, table.insert, table.remove
local sort, concat, atan2 = sort, table.concat, atan2
local format, floor = string.format, math.floor
local CreateFrame = CreateFrame
local GetTime, C_Timer = GetTime, C_Timer
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local GameTooltip = GameTooltip
local strsplit = strsplit
local UnitExists, UnitName, UnitGUID = UnitExists, UnitName, UnitGUID
local UnitClassification, UnitLevel = UnitClassification, UnitLevel
local UnitHealth, UnitHealthMax, UnitIsDeadOrGhost = UnitHealth, UnitHealthMax, UnitIsDeadOrGhost
local CheckInteractDistance, UnitInRange = CheckInteractDistance, UnitInRange
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local UnitIsPlayer, IsSecret = UnitIsPlayer, S.IsSecret
local min = math.min
local bit_band = _G.bit and _G.bit.band
if not bit_band then
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

local RULES = {} -- spellId -> rule (filled from ns.BossWatchData)
local BOSS_UNITS = { "target", "focus", "mouseover", "boss1", "boss2", "boss3", "boss4", "boss5" }

local KIND_COLOR = {
	cd = { 0.86, 0.55, 0.15 },    -- ability recast
	cast = { 0.9, 0.3, 0.3 },     -- thing happening NOW
	warn = { 0.85, 0.25, 0.35 },
	pull = { 0.25, 0.75, 0.35 },
	break_ = { 0.3, 0.55, 0.9 },
	phase = { 0.7, 0.4, 0.9 },
	custom = { 0.6, 0.6, 0.6 },
}

-- bars -----------------------------------------------------------------------
function BW:GetBar()
	for _, b in ipairs(self.bars) do
		if not b.active then return b end
	end
	if #self.bars >= (self.db.maxBars or 10) + 8 then return end
	local b = CreateFrame("StatusBar", nil, self.anchor)
	S:SetTemplate(b, "Default")
	b:SetStatusBarTexture(S.media.statusbar)
	b:SetMinMaxValues(0, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("RIGHT", b, "LEFT", -2, 0)
	b.name = S:FontString(b, 10, "OUTLINE")
	b.name:SetPoint("LEFT", 4, 0)
	b.name:SetJustifyH("LEFT")
	b.time = S:FontString(b, 10, "OUTLINE")
	b.time:SetPoint("RIGHT", -4, 0)
	b.time:SetJustifyH("RIGHT")
	-- shift-click a bar: announce remaining time to the group
	b:EnableMouse(true)
	b:SetScript("OnMouseUp", function(bar)
		if IsShiftKeyDown() and bar.ends then
			local ch = IsInRaid() and "RAID_WARNING" or (IsInGroup() and "PARTY")
			if ch then
				pcall(SendChatMessage, format("%s: %.0fs", bar.name:GetText() or "?", bar.ends - GetTime()), ch)
			end
		end
	end)
	self.bars[#self.bars + 1] = b
	return b
end

function BW:Layout()
	local w, h = self.db.width or 200, self.db.height or 18
	for i, b in ipairs(self.bars) do
		b:SetSize(w, h)
		b.icon:SetSize(h - 2, h - 2)
		b.icon:SetShown(self.db.showIcon ~= false)
	end
	if S.movers.bossWatch then S.movers.bossWatch:SetSize(w, h * 3 + 8) end
end

function BW:Restack()
	local y, h, up = 0, self.db.height or 18, self.db.growUp
	for i = #self.active + 1, #self.bars do self.bars[i]:Hide() self.bars[i].active = nil end
	for i, b in ipairs(self.active) do
		b:ClearAllPoints()
		if up then b:SetPoint("BOTTOMLEFT", self.anchor, "BOTTOMLEFT", 0, y)
		else b:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", 0, -y) end
		y = y + h + 2
	end
end

function BW:StartTimer(id, text, duration, kind, icon, soonText, phaseTimer)
	if not self.anchor or not duration or duration <= 0 then return end
	for _, b in ipairs(self.active) do
		if b.tid == id then
			b.ends = GetTime() + duration
			b.duration = duration
			b.soonFired = nil
			b.soonText = soonText
			return
		end
	end
	local b = self:GetBar()
	if not b then return end
	b.tid = id
	b.ends = GetTime() + duration
	b.duration = duration
	b.soonFired = nil
	b.soonText = soonText
	b.lastSec = nil
	b.countdown = (kind == "pull" or kind == "break_")
	b.phaseTimer = phaseTimer or nil
	b.name:SetText(text or "")
	local c = KIND_COLOR[kind or "cd"] or KIND_COLOR.custom
	b:SetStatusBarColor(c[1], c[2], c[3])
	if icon then b.icon:SetTexture(icon) else b.icon:SetTexture(nil) end
	b:Show()
	b.active = true
	self.active[#self.active + 1] = b
	self:Restack()
end

function BW:StopTimer(id)
	for i, b in ipairs(self.active) do
		if b.tid == id then b.active = nil b:Hide() tremove(self.active, i) break end
	end
	self:Restack()
end

function BW:Tick()
	local now = GetTime()
	local dirty
	for i = #self.active, 1, -1 do
		local b = self.active[i]
		local left = b.ends - now
		if left <= 0 then
			b.active = nil
			b:Hide()
			tremove(self.active, i)
			dirty = true
		else
			b:SetValue(left / b.duration)
			b.time:SetText(format("%.1f", left))
			if b.soonText and not b.soonFired and left <= 5 then
				b.soonFired = true
				self:Warn(format("%s %s", b.soonText, L["soon"]))
			end
			-- countdown beeps on the last 5 seconds (pull/break timers)
			if b.countdown and self.db.countdownSounds ~= false then
				local sec = math.ceil(left)
				if sec <= 5 and sec >= 1 and b.lastSec ~= sec then
					b.lastSec = sec
					pcall(PlaySound, 856)
				end
			end
		end
	end
	-- nameplate icons + arrow refresh for tracked debuff carriers
	if GetTime() - (self.npCheck or 0) > 0.5 then
		self.npCheck = GetTime()
		self:UpdateNameplates()
		self:UpdateArrow()
	end
	if dirty then self:Restack() end
end

-- warnings -------------------------------------------------------------------
function BW:Warn(text, big)
	if not text or text == "" then return end
	local f = self.warnFrame
	if not f then return end
	f.text:SetText(text)
	f.text:SetFont(S.media.font, big and 34 or 24, "OUTLINE")
	f.alpha = 2.4
	f:SetAlpha(1)
	f:Show()
	if self.db.sounds ~= false then
		pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
	end
	if big and self.db.flash ~= false and self.flashFrame then
		self.flashFrame.alpha = 0.8
		self.flashFrame:SetAlpha(0.8)
		self.flashFrame:Show()
	end
end

-- boss fight tracking ---------------------------------------------------------
local function FightTime()
	local d = GetTime() - (BW.bossStart or GetTime())
	return format("%d:%02d", floor(d / 60), floor(d % 60))
end

function BW:BossEngage(name, guid, unit)
	if self.bossStart then return end
	if not name or name == "" then return end
	self.bossName, self.bossGUID, self.bossUnit = name, guid, unit
	self.bossStart = GetTime()
	self.phase = nil
	if self.db.fightAnnounce ~= false then
		self:Warn(format(L["%s engaged"], name))
	end
end

function BW:BossDown(killed)
	if not self.bossStart then return end
	local t, name = FightTime(), self.bossName or "Boss"
	self.db.stats = self.db.stats or {}
	local st = self.db.stats[name] or { kills = 0 }
	if killed then
		st.kills = st.kills + 1
		local secs = floor(GetTime() - self.bossStart)
		if not st.best or secs < st.best then st.best = secs end
		st.last = secs
		self.db.stats[name] = st
		self:Warn(format(L["%s down after %s"], name, t) .. (st.best == secs and format(" (%s)", L["new best"]) or ""))
	else
		st.last = nil
		self.db.stats[name] = st
		local hp
		if self.bossUnit and UnitExists(self.bossUnit) then
			local h, m = UnitHealth(self.bossUnit), UnitHealthMax(self.bossUnit)
			if not IsSecret(h) and not IsSecret(m) and m > 0 then hp = floor(h / m * 100) end
		end
		self:Warn(format(L["Wipe on %s after %s"], name, t) .. (hp and format(" (%s%%)", hp) or ""))
	end
	wipe(self.castCounts)
	self.bossName, self.bossGUID, self.bossUnit, self.bossStart, self.phase = nil, nil, nil, nil, nil
end

-- phase transitions: rules can carry setPhase/phase ("P2" or "P1,P4") fields.
-- On a change we wipe rule timers + cast counts and start pfirst timers.
function BW:SetPhase(ph)
	if not ph or ph == self.phase then return end
	self.phase = ph
	for i = #self.active, 1, -1 do
		local b = self.active[i]
		if b.phaseTimer then
			b.active = nil
			b:Hide()
			tremove(self.active, i)
		end
	end
	wipe(self.castCounts)
	self:Warn(format(L["Phase %s"], (ph:gsub("^P", ""))), true)
	for id, r in pairs(RULES) do
		if r.phase == ph and r.t and r.pfirst then
			local name, _, icon = S.GetSpellInfo(id)
			self:StartTimer("pfirst:" .. id, name, r.pfirst, "phase", icon)
		end
	end
	self:Restack()
end

-- rule.phase may be "P2" or a list "P1,P4"; nil phase state = allow everything
local function PhaseOK(rule)
	if not rule.phase then return true end
	local cur = BW.phase or "P1"
	return ("," .. rule.phase .. ","):find("," .. cur .. ",", 1, true) ~= nil
end

local function IsBossUnit(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) then return end
	return UnitClassification(unit) == "worldboss" or UnitLevel(unit) == -1
end

function BW:ScanForBoss()
	for _, u in ipairs(BOSS_UNITS) do
		if IsBossUnit(u) then self:BossEngage(UnitName(u), UnitGUID(u), u) return end
	end
	-- raid member targets
	local n = GetNumGroupMembers()
	if n and n > 0 then
		local prefix = IsInRaid() and "raid" or "party"
		for i = 1, min(n, prefix == "raid" and 40 or 4) do
			local u = prefix .. i .. "target"
			if IsBossUnit(u) then self:BossEngage(UnitName(u), UnitGUID(u), u) return end
		end
	end
end

-- debuff target tracking (info list) ------------------------------------------
function BW:TrackAdd(spellId, name)
	if not name then return end
	local e = self.tracked[spellId] or { names = {}, text = (S.GetSpellInfo(spellId)) }
	self.tracked[spellId] = e
	e.names[name] = GetTime()
	e.expires = GetTime() + 15
	self:TrackRefresh()
end

function BW:TrackRemove(spellId, name)
	local e = self.tracked[spellId]
	if e then e.names[name] = nil end
	self:TrackRefresh()
end

function BW:TrackRefresh()
	if not self.trackFrame then return end
	local out = {}
	for _, e in pairs(self.tracked) do
		local names = {}
		for n in pairs(e.names) do names[#names + 1] = n end
		if #names > 0 then out[#out + 1] = e.text .. ": " .. table.concat(names, ", ") end
	end
	if #out == 0 then
		self.trackFrame:Hide()
	else
		self.trackFrame.text:SetText(table.concat(out, "\n"))
		self.trackFrame:Show()
	end
end

-- nameplate icons + direction arrow for tracked debuff carriers --------------
local function GroupUnitFor(name)
	if not name then return end
	if UnitName("player") == name then return "player" end
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, min(GetNumGroupMembers() or 0, prefix == "raid" and 40 or 4) do
		local u = prefix .. i
		if UnitName(u) == name then return u end
	end
end

function BW:UpdateNameplates()
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
	wipe(self.npUnits)
	for spellId, e in pairs(self.tracked) do
		local _, _, icon = S.GetSpellInfo(spellId)
		for name in pairs(e.names) do
			local u = GroupUnitFor(name)
			if u then self.npUnits[u] = icon end
		end
	end
	if self.db.nameplateIcons == false then wipe(self.npUnits) end
	for u, tex in pairs(self.npIcons) do
		if not self.npUnits[u] then tex:Hide() self.npIcons[u] = nil end
	end
	for u, icon in pairs(self.npUnits) do
		local np = C_NamePlate.GetNamePlateForUnit(u)
		if np then
			local tex = self.npIcons[u]
			if not tex then
				tex = np:CreateTexture(nil, "OVERLAY")
				tex:SetSize(20, 20)
				self.npIcons[u] = tex
			end
			if tex:GetParent() ~= np then tex:SetParent(np) end
			tex:ClearAllPoints()
			tex:SetPoint("BOTTOM", np, "TOP", 0, 2)
			tex:SetTexture(icon)
			tex:Show()
		end
	end
end

function BW:UpdateArrow()
	local f = self.arrowFrame
	if not f then return end
	if self.db.arrow == false or not UnitPosition then f:Hide() return end
	local px, py = UnitPosition("player")
	if not px then f:Hide() return end
	local bx, by
	for u in pairs(self.npUnits) do
		if u ~= "player" then
			local x, y = UnitPosition(u)
			if x and (not bx or (x - px) ^ 2 + (y - py) ^ 2 < (bx - px) ^ 2 + (by - py) ^ 2) then bx, by = x, y end
		end
	end
	if not bx then f:Hide() return end
	local facing = GetPlayerFacing and GetPlayerFacing() or 0
	f.tex:SetRotation(-(atan2(by - py, bx - px) - facing))
	f:Show()
end

-- combat-log engine -----------------------------------------------------------
function BW:OnCombatLog()
	local _, ev, _, sGUID, sName, sFlags, _, dGUID, dName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
	if ev == "UNIT_DIED" then
		if self.bossGUID and dGUID == self.bossGUID then self:BossDown(true) end
		return
	end
	-- "GTFO": environmental fire/lava damage on the player (throttled 3s)
	if ev == "ENVIRONMENTAL_DAMAGE" then
		if self.db.gtfo ~= false and dGUID == UnitGUID("player")
			and (spellId == "Fire" or spellId == "Lava") then
			if GetTime() - (self.envWarn or 0) > 3 then
				self.envWarn = GetTime()
				self:Warn(L["Move!"], true)
			end
		end
		return
	end
	local rule = spellId and RULES[spellId]
	if not rule then return end
	if self.db.disabledRules and self.db.disabledRules[spellId] then return end
	-- phase engine: setPhase rules always fire; phase-gated rules only in their phase
	if rule.setPhase then self:SetPhase(rule.setPhase) end
	if not PhaseOK(rule) then return end
	-- a known boss spell firing marks the fight as running
	if not self.bossStart and sName and bit_band(sFlags or 0, COMBATLOG_OBJECT_REACTION_HOSTILE or 16) ~= 0 then
		self:BossEngage(sName, sGUID, nil)
	end
	if ev == "SPELL_CAST_START" or ev == "SPELL_CAST_SUCCESS" or ev == "SPELL_AURA_APPLIED" then
		local key = spellId .. ":" .. (sGUID or "?")
		local count = (self.castCounts[key] or 0) + 1
		self.castCounts[key] = count
		if rule.t then
			local label = spellName or L["Ability"]
			if count > 1 then label = format("%s (%d)", label, count) end
			local _, _, icon = S.GetSpellInfo(spellId)
			-- t may be a {min, max} window: roll inside it so bars stay honest
			local dur = rule.t
			if type(dur) == "table" then
				dur = dur[1] + (math.random() * ((dur[2] or dur[1]) - dur[1]))
			end
			self:StartTimer(key, label, dur, rule.kind or "cd", icon, rule.soon and label or nil, true)
		end
		if rule.warn then
			-- throttle: same spell warns at most once every 3s (multi-target auras)
			local now = GetTime()
			if now - (self.warnTimes[spellId] or 0) >= 3 then
				self.warnTimes[spellId] = now
				local txt = (type(rule.warn) == "string" and rule.warn) or format("%s!", spellName or "")
				if rule.sourceName ~= false and sName then txt = format("%s: %s", sName, txt) end
				self:Warn(txt, rule.big)
			end
		end
		if rule.rw then
			local ch = IsInRaid() and "RAID_WARNING" or (IsInGroup() and "PARTY")
			if ch then pcall(SendChatMessage, format("%s: %s!", sName or "?", spellName or ""), ch) end
		end
		if rule.sayMe and ev == "SPELL_AURA_APPLIED" and dGUID == UnitGUID("player") then
			pcall(SendChatMessage, format("%s on me!", spellName or ""), "SAY")
		end
		if rule.track and ev == "SPELL_AURA_APPLIED" then
			self:TrackAdd(spellId, dName)
		end
		if rule.mark and ev == "SPELL_AURA_APPLIED" then
			local u = GroupUnitFor(dName)
			if u and self.db.marks ~= false then SetRaidTarget(u, rule.mark) end
		end
	elseif ev == "SPELL_AURA_REMOVED" then
		if rule.track then self:TrackRemove(spellId, dName) end
		if rule.mark then
			local u = GroupUnitFor(dName)
			if u and GetRaidTargetIndex(u) == rule.mark then SetRaidTarget(u, 0) end
		end
	elseif ev == "SPELL_CAST_INTERRUPT" or ev == "SPELL_INTERRUPT" then
		if rule.t then self:StopTimer(spellId .. ":" .. (sGUID or "?")) end
	end
end

-- per-rule options window (/bw rules) ------------------------------------------
function BW:ToggleRules()
	if self.rulesFrame then
		self.rulesFrame:SetShown(not self.rulesFrame:IsShown())
		return
	end
	local f = CreateFrame("Frame", "SentinelUIBossWatchRules", UIParent, S.BackdropTemplate)
	f:SetSize(400, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SkinFrame(f, "Default")
	f.title = S:FontString(f, 13, "OUTLINE")
	f.title:SetPoint("TOP", 0, -8)
	f.title:SetText(L["Boss Watch"] .. " — " .. L["Rules"])
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local scroll = CreateFrame("ScrollFrame", "SentinelUIBWRulesScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -30)
	scroll:SetPoint("BOTTOMRIGHT", -28, 10)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(360, 1)
	scroll:SetScrollChild(child)

	-- group rules by zone, sorted
	local zones, byZone = {}, {}
	for id, r in pairs(RULES) do
		local z = r.z or L["Other"]
		if not byZone[z] then byZone[z] = {} zones[#zones + 1] = z end
		byZone[z][#byZone[z] + 1] = id
	end
	sort(zones)
	local y = 0
	for _, z in ipairs(zones) do
		sort(byZone[z])
		local h = S:FontString(child, 12, "OUTLINE")
		h:SetPoint("TOPLEFT", 4, y)
		h:SetText("|cff" .. S.accentHex .. z .. "|r")
		y = y - 20
		for _, id in ipairs(byZone[z]) do
			local name, _, icon = S.GetSpellInfo(id)
			local cb = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
			cb:SetPoint("TOPLEFT", 10, y)
			cb:SetSize(18, 18)
			S:SkinCheckBox(cb)
			cb:SetChecked(not (self.db.disabledRules and self.db.disabledRules[id]))
			cb:SetScript("OnClick", function(c)
				self.db.disabledRules = self.db.disabledRules or {}
				self.db.disabledRules[id] = not c:GetChecked() or nil
			end)
			local t = S:FontString(cb, 10)
			t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
			t:SetFormattedText("|T%s:12|t %s |cff888888(%d)|r", icon or 134400, name or "?", id)
			y = y - 20
		end
		y = y - 6
	end
	child:SetHeight(-y + 10)
	self.rulesFrame = f
end

-- dedicated settings window ---------------------------------------------------
local BW_OPTS = {
	{ "sounds", L["Sounds"] }, { "flash", L["Screen Flash"] }, { "gtfo", L["GTFO Warning"] },
	{ "autoReply", L["Whisper Auto-Reply"] }, { "countdownSounds", L["Countdown Beeps"] },
	{ "nameplateIcons", L["Nameplate Icons"] }, { "arrow", L["Direction Arrow"] },
	{ "marks", L["Auto Raid Marks"] }, { "fightAnnounce", L["Fight Announce"] },
	{ "announcePull", L["Announce Pull"] }, { "showIcon", L["Bar Icons"] }, { "growUp", L["Grow Upwards"] },
}
local BW_SLIDERS = {
	{ "width", L["Bar Width"], 80, 400, 1 },
	{ "height", L["Bar Height"], 8, 40, 1 },
	{ "maxBars", L["Max Bars"], 1, 20, 1 },
}

function BW:ToggleSettings()
	if self.cfgFrame then
		self.cfgFrame:SetShown(not self.cfgFrame:IsShown())
		return
	end
	local f = CreateFrame("Frame", "SentinelUIBossWatchConfig", UIParent, S.BackdropTemplate)
	f:SetSize(320, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SkinFrame(f, "Default")
	f.title = S:FontString(f, 13, "OUTLINE")
	f.title:SetPoint("TOP", 0, -8)
	f.title:SetText(L["Boss Watch"] .. " — " .. L["Settings"])
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local y = -34
	for _, info in ipairs(BW_OPTS) do
		local key, label = info[1], info[2]
		local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 12, y)
		cb:SetSize(20, 20)
		S:SkinCheckBox(cb)
		cb:SetChecked(self.db[key] ~= false)
		cb:SetScript("OnClick", function(c)
			BW.db[key] = c:GetChecked() and true or false
			BW:Update()
		end)
		local t = S:FontString(cb, 10)
		t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		t:SetText(label)
		y = y - 22
	end
	y = y - 6
	for _, info in ipairs(BW_SLIDERS) do
		local key, label, mn, mx = info[1], info[2], info[3], info[4]
		local name = "SentinelUIBWSlider" .. key
		local sl = CreateFrame("Slider", name, f, "OptionsSliderTemplate")
		sl:SetPoint("TOPLEFT", 16, y)
		sl:SetSize(200, 14)
		sl:SetMinMaxValues(mn, mx)
		sl:SetValueStep(1)
		sl:SetObeyStepOnDrag(true)
		sl:SetValue(self.db[key] or mn)
		S:SkinSlider(sl)
		_G[name .. "Text"]:SetText(label .. ": " .. (self.db[key] or mn))
		_G[name .. "Low"]:SetText(tostring(mn))
		_G[name .. "High"]:SetText(tostring(mx))
		sl:SetScript("OnValueChanged", function(_, v)
			v = floor(v + 0.5)
			if BW.db[key] ~= v then
				BW.db[key] = v
				_G[name .. "Text"]:SetText(label .. ": " .. v)
				BW:Update()
			end
		end)
		y = y - 34
	end

	local rules = CreateFrame("Button", nil, f)
	rules:SetPoint("BOTTOMLEFT", 12, 12)
	rules:SetSize(140, 24)
	S:SkinButton(rules)
	local rt = S:FontString(rules, 10, "OUTLINE")
	rt:SetPoint("CENTER")
	rt:SetText(L["Boss Rules"])
	rules:SetScript("OnClick", function() BW:ToggleRules() end)

	local test = CreateFrame("Button", nil, f)
	test:SetPoint("BOTTOMRIGHT", -12, 12)
	test:SetSize(140, 24)
	S:SkinButton(test)
	local tt = S:FontString(test, 10, "OUTLINE")
	tt:SetPoint("CENTER")
	tt:SetText(L["Test"])
	test:SetScript("OnClick", function() SlashCmdList.SUIBOSSWATCH("test") end)

	self.cfgFrame = f
end

-- pull / break ----------------------------------------------------------------
function BW:Pull(seconds, fromComm)
	seconds = floor(tonumber(seconds) or 0)
	if seconds <= 0 or seconds > 60 then return end
	self:StartTimer("pull", L["Pull"], seconds, "pull")
	if not fromComm and self.db.announcePull ~= false then
		local ch = IsInRaid() and "RAID_WARNING" or (IsInGroup() and "PARTY")
		if ch then pcall(SendChatMessage, format("%s %ds", L["Pull"], seconds), ch) end
		if C_ChatInfo and C_ChatInfo.SendAddonMessage then
			local ch2 = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
			if ch2 then
				pcall(C_ChatInfo.SendAddonMessage, "D4", "PT\t" .. seconds .. "\t" .. floor(GetTime()), ch2)
				pcall(C_ChatInfo.SendAddonMessage, "BigWigs", "P^Pull^" .. seconds, ch2)
			end
		end
		S.SendAddonMessage("SUIBW", "P\t" .. seconds, S.GroupChannel())
	end
end

-- SUI<->SUI timer sync: share custom timers with other SentinelUI users
function BW:ShareTimer(seconds, name)
	if not IsInGroup() then return end
	S.SendAddonMessage("SUIBW", "T\t" .. seconds .. "\t" .. (name or ""), S.GroupChannel())
end

function BW:Break(seconds, fromComm)
	seconds = floor(tonumber(seconds) or 0)
	if seconds <= 0 or seconds > 3600 then return end
	self:StartTimer("break", L["Break"], seconds, "break_")
	if not fromComm and IsInGroup() then
		S.SendAddonMessage("D4", "BT\t" .. seconds, S.GroupChannel())
		S.SendAddonMessage("SUIBW", "B\t" .. seconds, S.GroupChannel())
	end
end

-- range radar (/bw range N) ----------------------------------------------------
local function InRange(unit, yards)
	if CheckInteractDistance then
		if yards <= 11 then return CheckInteractDistance(unit, 3)      -- ~9.9y duel
		elseif yards <= 28 then return CheckInteractDistance(unit, 1)  -- ~28y inspect
		end
	end
	return UnitInRange and UnitInRange(unit)                      -- ~40y heal
end

function BW:RangeTick()
	local rf, yards = self.rangeFrame, self.rangeYards
	if not rf or not yards then return end
	local out = {}
	local prefix = IsInRaid() and "raid" or "party"
	local n = GetNumGroupMembers()
	for i = 1, min(n or 0, prefix == "raid" and 40 or 4) do
		local u = prefix .. i
		if UnitExists(u) and not UnitIsDeadOrGhost(u) and InRange(u, yards) then
			out[#out + 1] = UnitName(u) or u
		end
	end
	rf.title:SetText(format("%s %dy", L["Range"], yards))
	rf.text:SetText(#out > 0 and table.concat(out, "\n") or "—")
	rf:Show()
end

function BW:RangeToggle(yards)
	if not self.rangeFrame then return end
	if self.rangeYards and not yards then
		-- /bw range  without args toggles off
		self.rangeYards = nil
		self.rangeFrame:Hide()
		return
	end
	if not yards then self.rangeYards = nil self.rangeFrame:Hide() return end
	yards = floor(tonumber(yards) or 0)
	if yards <= 0 then self.rangeYards = nil self.rangeFrame:Hide() return end
	self.rangeYards = yards
	if not self.rangeTicker then
		self.rangeTicker = C_Timer.NewTicker(0.5, function() S:SafeCall("BossWatch:Range", BW.RangeTick, BW) end)
	end
	self:RangeTick()
end

-- build -----------------------------------------------------------------------
function BW:Create()
	self.anchor = CreateFrame("Frame", "SentinelUIBossWatch", UIParent)
	S:CreateMover(self.anchor, "bossWatch", L["Boss Watch"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -420, -260 }, "general")
	self.bars, self.active, self.castCounts = {}, {}, {}
	self.tracked = {}
	self.warnTimes = {}

	-- debuff-holder info list (rules with `track`)
	local tf = CreateFrame("Frame", "SentinelUIBossWatchInfo", self.anchor)
	S:SetTemplate(tf, "Default")
	tf:SetSize(220, 60)
	tf:SetPoint("TOPRIGHT", self.anchor, "BOTTOMRIGHT", 0, -6)
	tf:SetFrameStrata("MEDIUM")
	tf.text = S:FontString(tf, 11, "OUTLINE")
	tf.text:SetPoint("TOPLEFT", 6, -6)
	tf.text:SetPoint("BOTTOMRIGHT", -6, 6)
	tf.text:SetJustifyH("LEFT")
	tf.text:SetJustifyV("TOP")
	tf:Hide()
	self.trackFrame = tf

	-- range radar frame (/bw range N)
	local rf = CreateFrame("Frame", "SentinelUIBossWatchRange", self.anchor)
	S:SetTemplate(rf, "Default")
	rf:SetSize(160, 140)
	rf:SetPoint("TOPLEFT", self.anchor, "BOTTOMLEFT", 0, -6)
	rf:SetFrameStrata("MEDIUM")
	rf.title = S:FontString(rf, 11, "OUTLINE")
	rf.title:SetPoint("TOP", 0, -5)
	rf.title:SetText(L["Range"])
	rf.text = S:FontString(rf, 10, "OUTLINE")
	rf.text:SetPoint("TOPLEFT", 6, -20)
	rf.text:SetPoint("BOTTOMRIGHT", -6, 6)
	rf.text:SetJustifyH("LEFT")
	rf.text:SetJustifyV("TOP")
	rf:Hide()
	self.rangeFrame = rf

	-- screen flash overlay for big warnings
	local fl = CreateFrame("Frame", "SentinelUIBossWatchFlash", UIParent)
	fl:SetAllPoints(UIParent)
	fl:SetFrameStrata("FULLSCREEN")
	fl.tex = fl:CreateTexture(nil, "BACKGROUND")
	fl.tex:SetAllPoints()
	fl.tex:SetColorTexture(1, 0.15, 0.15, 0.28)
	fl.alpha = 0
	fl:SetScript("OnUpdate", function(f, dt)
		if not f:IsShown() then return end
		f.alpha = f.alpha - dt * 1.6
		f:SetAlpha(f.alpha < 0 and 0 or f.alpha)
		if f.alpha <= 0 then f:Hide() end
	end)
	fl:Hide()
	self.flashFrame = fl

	-- tracked-carrier nameplate icons + direction arrow
	self.npUnits, self.npIcons = {}, {}
	local af = CreateFrame("Frame", "SentinelUIBossWatchArrow", UIParent)
	af:SetSize(40, 40)
	af:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	af:SetFrameStrata("HIGH")
	af.tex = af:CreateTexture(nil, "OVERLAY")
	af.tex:SetAllPoints()
	af.tex:SetTexture("Interface\\MiniMap\\MiniMap-DeadArrow")
	af:Hide()
	self.arrowFrame = af

	self.warnFrame = CreateFrame("Frame", "SentinelUIBossWatchWarn", UIParent)
	self.warnFrame:SetSize(800, 60)
	self.warnFrame:SetPoint("TOP", UIParent, "TOP", 0, -320)
	self.warnFrame:SetFrameStrata("FULLSCREEN_DIALOG")
	self.warnFrame.text = S:FontString(self.warnFrame, 26, "OUTLINE")
	self.warnFrame.text:SetPoint("CENTER")
	self.warnFrame.alpha = 0
	self.warnFrame:SetScript("OnUpdate", function(f, dt)
		if not f:IsShown() then return end
		f.alpha = f.alpha - dt
		if f.alpha <= 1 then f:SetAlpha(f.alpha < 0 and 0 or f.alpha) end
		if f.alpha <= 0 then f:Hide() end
	end)

	self:Layout()
end

function BW:Update()
	self.db = S.db.profile.bosswatch
	if self.anchor then self:Layout() end
end

function BW:Initialize()
	self.db = S.db.profile.bosswatch
	-- load rule dataset
	for id, r in pairs((ns.BossWatchData and ns.BossWatchData.rules) or {}) do RULES[id] = r end
	self:Create()

	-- minimap button (SentinelUI monogram family)
	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "bosswatch", glyph = "BW",
		store = self.private.minimap, angle = 335,
		onLeft = function() BW:ToggleSettings() end,
		onRight = function() BW:ToggleRules() end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. L["Boss Watch"])
			GameTooltip:AddLine(L["Left-click: settings  |  Right-click: boss rules  |  /pull <s>"], 1, 1, 1)
		end,
	})

	-- announce ourselves as a boss mod so DBM/BigWigs list us in version checks
	function BW:AnnounceSelf()
		if not IsInGroup() then return end
		local v = S.version or "?"
		-- D4 "H" hello (best-effort field layout) + BigWigs presence ping
		S.SendAddonMessage("D4", "H\t1\t" .. v .. "\tSentinelUI " .. v .. "\t" .. (GetLocale() or "enUS"), S.GroupChannel())
		S.SendAddonMessage("BigWigs", "V^" .. v, S.GroupChannel())
	end
	self.wasInGroup = IsInGroup()
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		local inGroup = IsInGroup()
		if inGroup and not BW.wasInGroup then
			C_Timer.After(2, function() S:SafeCall("BossWatch:Hello", BW.AnnounceSelf, BW) end)
		end
		BW.wasInGroup = inGroup
	end)
	C_Timer.After(5, function() S:SafeCall("BossWatch:Hello", BW.AnnounceSelf, BW) end)

	self.ticker = C_Timer.NewTicker(0.05, function() BW:Tick() end)
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function() S:SafeCall("BossWatch:CLEU", BW.OnCombatLog, BW) end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() S:SafeCall("BossWatch:Engage", BW.ScanForBoss, BW) end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if BW.bossStart then S:SafeCall("BossWatch:Wipe", BW.BossDown, BW, false) end end)
	-- whisper auto-reply while fighting a boss
	self:RegisterEvent("CHAT_MSG_WHISPER", function(_, _, msg, sender)
		if BW.bossStart and BW.db.autoReply ~= false and sender and sender ~= S.myName then
			pcall(SendChatMessage, format("[SentinelUI] %s", format(L["Busy fighting %s"], BW.bossName or "boss")), "WHISPER", nil, sender)
		end
	end)
	-- retail encounter events (pcall: they don't exist on classic-era clients)
	pcall(function()
		self:RegisterEvent("ENCOUNTER_START", function(_, _, name) S:SafeCall("BossWatch:Engage", BW.BossEngage, BW, name, nil, nil) end)
		self:RegisterEvent("ENCOUNTER_END", function(_, _, _, _, _, success)
			if BW.bossStart then S:SafeCall("BossWatch:End", BW.BossDown, BW, success == 1) end
		end)
	end)

	-- DBM pull-timer interop (D4 prefix): we accept their pulls, they see ours
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, "D4")
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, "BigWigs")
		if S.RegisterAddonPrefix then pcall(S.RegisterAddonPrefix, "SUIBW") end
		self:RegisterEvent("CHAT_MSG_ADDON", function(_, _, prefix, msg, _, sender)
			if type(msg) ~= "string" then return end
			-- answer boss-mod version checks so DBM/BigWigs recognize us
			if prefix == "D4" and (msg == "V" or msg:sub(1, 2) == "V\t") then
				S.SendAddonMessage("D4", "VE\t1\t" .. (S.version or "?") .. "\tSentinelUI " .. (S.version or "?") .. "\t" .. (GetLocale() or "enUS") .. "\t1", "WHISPER", sender)
				return
			end
			if prefix == "BigWigs" and msg == "V" then
				S.SendAddonMessage("BigWigs", "V^" .. (S.version or "?"), "WHISPER", sender)
				return
			end
			if prefix == "SUIBW" then
				-- SUI<->SUI sync: P = pull, T = shared timer, V = version check
				if msg == "V" then
					S.SendAddonMessage("SUIBW", "V\t" .. (S.version or "?"), "WHISPER", sender)
					return
				end
				local ver = msg:match("^V\t(.*)$")
				if ver then
					if BW.verReplies then BW.verReplies[sender] = ver end
					return
				end
				local secs = msg:match("^P\t(%d+)")
				if secs then BW:Pull(secs, true) return end
				local tsecs, tname = msg:match("^T\t(%d+)\t(.*)$")
				if tsecs then
					BW:StartTimer("sync:" .. (sender or "?") .. tname, format("%s (%s)", tname ~= "" and tname or L["Timer"], sender or "?"), tonumber(tsecs), "custom")
					return
				end
				local brk = msg:match("^B\t(%d+)")
				if brk then BW:Break(brk, true) return end
				return
			end
			local secs
			if prefix == "D4" then
				secs = msg:match("^PT\t(%d+)")
				local brk = msg:match("^BT\t(%d+)")
				if brk then BW:Break(brk, true) return end
			elseif prefix == "BigWigs" then
				secs = msg:match("P%^Pull%^(%d+)")
				local brk = msg:match("B%^Break%^(%d+)")
				if brk then BW:Break(brk, true) return end
			end
			if secs then BW:Pull(secs, true) end
		end)
	end
end

-- /bw pull 10 | /bw break 300 | /bw timer 60 <name> | /bw test | /bw stop
SLASH_SUIBOSSWATCH1 = "/bw"
SLASH_SUIBOSSWATCH2 = "/bosswatch"
SLASH_SUIBOSSPULL1 = "/pull"
SlashCmdList.SUIBOSSPULL = function(msg) BW:Pull(tonumber(msg) or 10) end
SlashCmdList.SUIBOSSWATCH = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	if not cmd then BW:ToggleSettings() return end
	cmd = cmd:lower()
	if cmd == "options" or cmd == "config" or cmd == "opt" then BW:ToggleSettings() return end
	if cmd == "pull" then
		BW:Pull(tonumber(rest) or 10)
	elseif cmd == "break" then
		BW:Break(tonumber(rest) or 300)
	elseif cmd == "timer" then
		local secs, name = rest:match("^(%d+)%s*(.*)$")
		if secs then
			BW:StartTimer("custom:" .. GetTime(), (name ~= "" and name or L["Timer"]), tonumber(secs), "custom")
			BW:ShareTimer(tonumber(secs), name)
		end
	elseif cmd == "range" then
		BW:RangeToggle(tonumber(rest))
	elseif cmd == "ver" then
		BW.verReplies = { [S.myName] = S.version }
		S.SendAddonMessage("SUIBW", "V", S.GroupChannel())
		C_Timer.After(3, function()
			S:Print(L["SentinelUI users in group:"])
			for name, v in pairs(BW.verReplies or {}) do
				S:Print(format("  %s — v%s", name, v))
			end
		end)
	elseif cmd == "stats" then
		for name, st in pairs((BW.db and BW.db.stats) or {}) do
			S:Print(format("%s — %s: %d, %s: %s", name, L["kills"], st.kills or 0, L["best"],
				st.best and format("%d:%02d", floor(st.best / 60), st.best % 60) or "—"))
		end
	elseif cmd == "rules" then
		BW:ToggleRules()
	elseif cmd == "test" then
		BW:StartTimer("test1", "Test Timer", 20, "cd")
		BW:Warn("Test Warning", true)
	elseif cmd == "stop" then
		for i = #BW.active, 1, -1 do BW.active[i].active = nil BW.active[i]:Hide() tremove(BW.active, i) end
		BW:Restack()
	end
end
