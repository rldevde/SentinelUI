-- Unit frame framework: elements, tags, castbars, auras. Unit layouts live in UnitFrameUnits.lua
local _, ns = ...
local S = ns.S
local L = S.L
local UF = S:NewModule("UnitFrames")

local _G = _G
local pairs, ipairs, type, format, floor, min, max, tostring = pairs, ipairs, type, format, floor, min, max, tostring
local UnitExists, UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax, UnitPowerType = UnitExists, UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax, UnitPowerType
local UnitIsDead, UnitIsGhost, UnitIsConnected, UnitName, UnitLevel, UnitClassification = UnitIsDead, UnitIsGhost, UnitIsConnected, UnitName, UnitLevel, UnitClassification
local IsSecret = S.IsSecret
local BLANK = [[Interface\Buttons\WHITE8X8]]

UF.frames = {}
UF.units = {}
UF.headers = {}

local DEBUFF_COLORS = {
	Magic = { r = 0.2, g = 0.6, b = 1 }, Curse = { r = 0.6, g = 0, b = 1 }, Disease = { r = 0.6, g = 0.4, b = 0 },
	Poison = { r = 0, g = 0.6, b = 0 }, none = { r = 0.8, g = 0, b = 0 },
}
UF.DEBUFF_COLORS = DEBUFF_COLORS
-- small-circle role coords of UI-LFG-ICON-PORTRAITROLES (fallback for clients without GetTexCoordsForRoleSmallCircle)
local ROLE_COORDS = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 }, DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }

-- Tags ----------------------------------------------------------------------
local function HealthPercent(unit)
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok, p = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
		if ok and p then
			local ok2, txt = pcall(format, "%.0f%%", p)
			return ok2 and txt or ""
		end
	end
	local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
	if IsSecret(cur) or IsSecret(mx) then return "" end
	if not mx or mx == 0 then return "0%" end
	return format("%d%%", floor(cur / mx * 100 + 0.5))
end

local function Status(unit)
	if not UnitIsConnected(unit) then return L["Offline"] end
	if UnitIsGhost(unit) then return L["Ghost"] end
	if UnitIsDead(unit) then return L["Dead"] end
end

local function Utf8Sub(s, n)
	local bytes, chars = 1, 0
	while bytes <= #s and chars < n do
		local c = s:byte(bytes)
		bytes = bytes + (c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1)
		chars = chars + 1
	end
	return s:sub(1, bytes - 1)
end
UF.Utf8Sub = Utf8Sub

UF.tags = {
	name = function(unit, db)
		local n = UnitName(unit) or ""
		local len = db and db.maxLength
		if len and len > 0 and not IsSecret(n) then n = Utf8Sub(n, len) end
		return n
	end,
	level = function(unit)
		local lvl = UnitLevel(unit)
		if IsSecret(lvl) then return lvl end
		local c = UnitClassification(unit)
		local plus = (c == "elite" or c == "rareelite") and "+" or (c == "worldboss" and "B" or "") .. (c == "rare" and "R" or "")
		if lvl == -1 then return "|cffff3333??|r" end
		local color = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl) or { r = 1, g = 1, b = 1 }
		return S:Hex(color) .. lvl .. plus .. "|r"
	end,
	current = function(unit) return Status(unit) or S:Abbrev(UnitHealth(unit)) end,
	max = function(unit) return S:Abbrev(UnitHealthMax(unit)) end,
	percent = function(unit) return Status(unit) or HealthPercent(unit) end,
	deficit = function(unit)
		local st = Status(unit)
		if st then return st end
		local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
		if IsSecret(cur) or IsSecret(mx) then return "" end
		local d = mx - cur
		return d > 0 and ("-" .. S:Abbrev(d)) or ""
	end,
	curmax = function(unit) return Status(unit) or (S:Abbrev(UnitHealth(unit)) .. " / " .. S:Abbrev(UnitHealthMax(unit))) end,
	curpp = function(unit) return S:Abbrev(UnitPower(unit)) end,
	maxpp = function(unit) return S:Abbrev(UnitPowerMax(unit)) end,
	perpp = function(unit)
		local cur, mx = UnitPower(unit), UnitPowerMax(unit)
		if IsSecret(cur) or IsSecret(mx) then return "" end
		if not mx or mx == 0 then return "" end
		return format("%d%%", floor(cur / mx * 100 + 0.5))
	end,
	status = function(unit) return Status(unit) or "" end,
	classification = function(unit)
		local c = UnitClassification(unit)
		return c == "rare" and L["Rare"] or c == "rareelite" and L["Rare Elite"] or c == "elite" and L["Elite"] or c == "worldboss" and L["Boss"] or ""
	end,
	group = function(unit)
		if not IsInRaid() then return "" end
		for i = 1, GetNumGroupMembers() do
			if UnitIsUnit("raid" .. i, unit) then return select(3, GetRaidRosterInfo(i)) end
		end
		return ""
	end,
	afk = function(unit) return UnitIsAFK(unit) and "|cffff9900AFK|r" or UnitIsDND(unit) and "|cffff3333DND|r" or "" end,
}

local T = UF.tags
local function NameLen(n) return function(unit) local s = UnitName(unit) or "" if IsSecret(s) then return s end return Utf8Sub(s, n) end end
T["name:veryshort"] = NameLen(5)
T["name:short"] = NameLen(10)
T["name:medium"] = NameLen(15)
T["name:long"] = NameLen(20)
T["name:full"] = function(unit) local n, r = UnitName(unit) if IsSecret(n) then return n end return (n or "") .. (r and r ~= "" and ("-" .. r) or "") end
T.classcolor = function(unit) return S:Hex(S.UnitColor(unit)) end
T.reactioncolor = function(unit) local r = UnitReaction(unit, "player") local c = r and FACTION_BAR_COLORS[r] or { r = 1, g = 1, b = 1 } return S:Hex(c) end
T.powercolor = function(unit) local r, g, b = UF.PowerColor(unit) return S:Hex(r, g, b) end
T.healthcolor = function(unit)
	local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
	if IsSecret(cur) or IsSecret(mx) or not mx or mx == 0 then return "|cffffffff" end
	local p = cur / mx
	return S:Hex(p < 0.5 and 1 or 2 * (1 - p), p > 0.5 and 1 or 2 * p, 0)
end
T.difficultycolor = function(unit)
	local lvl = UnitLevel(unit)
	if IsSecret(lvl) then return "|cffffffff" end
	local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl > 0 and lvl or 999) or { r = 1, g = 1, b = 1 }
	return S:Hex(c)
end
T.close = function() return "|r" end
T.class = function(unit) return (UnitClass(unit)) or "" end
T.race = function(unit) return (UnitRace(unit)) or "" end
T.smartclass = function(unit) if UnitIsPlayer(unit) then return (UnitClass(unit)) or "" end return UnitCreatureFamily(unit) or UnitCreatureType(unit) or "" end
T.creature = function(unit) return UnitCreatureFamily(unit) or UnitCreatureType(unit) or "" end
T.smartlevel = function(unit)
	local lvl = UnitLevel(unit)
	if IsSecret(lvl) then return lvl end
	if UnitIsPlayer(unit) and lvl == UnitLevel("player") then return "" end
	return T.level(unit)
end
T.pvp = function(unit) return UnitIsPVP(unit) and "|cffff3333PvP|r" or "" end
T.leader = function(unit) return UnitIsGroupLeader(unit) and "|cffffd100L|r" or "" end
T.dead = function(unit) return UnitIsDeadOrGhost(unit) and L["Dead"] or "" end
T.offline = function(unit) return not UnitIsConnected(unit) and L["Offline"] or "" end
T.curhp = T.current
T.maxhp = T.max
T.perhp = function(unit) return HealthPercent(unit) end
T.missinghp = T.deficit
T["health:current-percent"] = function(unit)
	local st = Status(unit)
	if st then return st end
	local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
	if IsSecret(cur) or IsSecret(mx) then return S:Abbrev(cur) end
	if cur == mx then return S:Abbrev(cur) end
	return S:Abbrev(cur) .. " - " .. HealthPercent(unit)
end
T["health:current-max"] = T.curmax
T["health:deficit-percent"] = function(unit)
	local st = Status(unit)
	if st then return st end
	local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
	if IsSecret(cur) or IsSecret(mx) or cur == mx then return "" end
	return HealthPercent(unit)
end
T.missingpp = function(unit)
	local cur, mx = UnitPower(unit), UnitPowerMax(unit)
	if IsSecret(cur) or IsSecret(mx) then return "" end
	local d = mx - cur
	return d > 0 and ("-" .. S:Abbrev(d)) or ""
end
T["power:current-percent"] = function(unit)
	local cur, mx = UnitPower(unit), UnitPowerMax(unit)
	if IsSecret(cur) or IsSecret(mx) then return S:Abbrev(cur) end
	if mx == 0 then return "" end
	return S:Abbrev(cur) .. " - " .. floor(cur / mx * 100 + 0.5) .. "%"
end
T.threat = function(unit)
	local _, _, pct = UnitDetailedThreatSituation("player", unit)
	if not pct or IsSecret(pct) or pct == 0 then return "" end
	return format("%.0f%%", pct)
end
T.combo = function()
	local n = GetComboPoints and GetComboPoints("player", "target") or 0
	return (n and n > 0) and n or ""
end

local tagHelp = {
	{ "name, name:veryshort/short/medium/long/full", "Name (length 5/10/15/20/with realm)" },
	{ "level, smartlevel, difficultycolor", "Level (colored), only when different from yours" },
	{ "current, max, percent, deficit, curmax", "Health" },
	{ "health:current-percent, health:current-max, health:deficit-percent", "Health combined" },
	{ "curpp, maxpp, perpp, missingpp, power:current-percent", "Power (Mana/Rage/Energy)" },
	{ "classcolor, reactioncolor, powercolor, healthcolor ... close", "Start/end color, e.g. [classcolor][name][close]" },
	{ "class, smartclass, race, creature, classification", "Class / race / creature type / elite" },
	{ "status, dead, offline, afk, pvp, leader, group", "Status info" },
	{ "threat, combo", "Threat %, combo points" },
}

function UF:TagHelp()
	local lines = { L["Use tags in the text fields of each unit (Health / Power / Name). Example: [classcolor][name:medium][close] [level]"], " " }
	for _, t in ipairs(tagHelp) do lines[#lines + 1] = "|cff" .. S.accentHex .. "[" .. t[1]:gsub(", ", "] [") .. "]|r\n    " .. L[t[2]] end
	return table.concat(lines, "\n")
end

local tagCache = {}
local function CompileTags(str)
	if tagCache[str] then return tagCache[str] end
	local parts = {}
	local pos = 1
	while true do
		local s, e, tag = str:find("%[([%w:%-]+)%]", pos)
		if not s then parts[#parts + 1] = str:sub(pos) break end
		if s > pos then parts[#parts + 1] = str:sub(pos, s - 1) end
		parts[#parts + 1] = UF.tags[tag] or ("[" .. tag .. "]")
		pos = e + 1
	end
	tagCache[str] = parts
	return parts
end

function UF:FormatTags(str, unit, db)
	if not str or str == "" then return "" end
	local parts = CompileTags(str)
	local out = {}
	for i, p in ipairs(parts) do
		if type(p) == "function" then
			local ok, v = pcall(p, unit, db)
			out[i] = ok and v or ""
		else
			out[i] = p
		end
	end
	local ok, res = pcall(table.concat, out)
	if ok then return res end
	-- secret values can't be concatenated; show the first meaningful piece
	for _, v in ipairs(out) do if IsSecret(v) then return v end end
	return ""
end

function UF:SetTagText(fs, str, unit, db)
	local text = self:FormatTags(str, unit, db)
	if IsSecret(text) then fs:SetText(text) return end
	fs:SetText(text)
end

-- Smooth bars ---------------------------------------------------------------
local smoothing = {}
local smoothFrame = CreateFrame("Frame")
smoothFrame:SetScript("OnUpdate", function(_, elapsed)
	local rate = min(1, elapsed * 12)
	for bar, target in pairs(smoothing) do
		local cur = bar:GetValue()
		local new = cur + (target - cur) * rate
		if math.abs(new - target) < 0.5 or math.abs(new - target) / max(1, select(2, bar:GetMinMaxValues())) < 0.002 then
			new = target
			smoothing[bar] = nil
		end
		bar:SetValue(new)
	end
end)

function UF:SetBarValue(bar, value)
	if IsSecret(value) or not self.db.smoothBars then
		smoothing[bar] = nil
		bar:SetValue(value)
	else
		smoothing[bar] = value
	end
end

-- Cutaway ------------------------------------------------------------------
-- recently-lost health lingers as a fading red slice behind the fill so big
-- hits read at a glance. Fades over CUT_DUR seconds then hides.
local CUT_DUR = 0.6
local cutaways = {}
local cutFrame = CreateFrame("Frame")
cutFrame:SetScript("OnUpdate", function(_, elapsed)
	for tex, t in pairs(cutaways) do
		t = t - elapsed
		if t <= 0 or not tex:IsShown() then
			cutaways[tex] = nil
			tex:Hide()
		else
			cutaways[tex] = t
			tex:SetAlpha(min(1, t / CUT_DUR))
		end
	end
end)

local function ShowCutaway(health, prev, cur, mx)
	if mx <= 0 or cur >= prev then return end
	local tex = health.cutaway
	if not tex then
		tex = health:CreateTexture(nil, "ARTWORK", nil, 2)
		tex:SetColorTexture(0.85, 0.25, 0.2)
		health.cutaway = tex
	end
	local w = health:GetWidth()
	if w <= 0 then return end
	local lost = min(prev - cur, mx - cur)
	local cw = lost / mx * w
	if cw < 2 then return end
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", health, "TOPLEFT", cur / mx * w, 0)
	tex:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
	tex:SetWidth(cw)
	tex:SetAlpha(1)
	tex:Show()
	cutaways[tex] = CUT_DUR
end

-- Elements ------------------------------------------------------------------
local powerColors = {}
-- softer Sentinel tones for the most common resources (Blizzard mana is pure blue)
local POWER_OVERRIDE = { MANA = { 0.30, 0.50, 0.95 }, RAGE = { 0.85, 0.22, 0.22 }, ENERGY = { 0.95, 0.82, 0.25 }, FOCUS = { 0.95, 0.55, 0.25 } }
local function PowerColor(unit)
	local ptype, ptoken, altR, altG, altB = UnitPowerType(unit)
	local o = ptoken and POWER_OVERRIDE[ptoken]
	if o then return o[1], o[2], o[3] end
	local c = PowerBarColor and (PowerBarColor[ptoken] or PowerBarColor[ptype])
	if c then return c.r, c.g, c.b end
	if altR then return altR, altG, altB end
	return 0.3, 0.5, 0.9
end
UF.PowerColor = PowerColor

function UF:UpdateHealthColor(f)
	local unit, health = f.unit, f.Health
	local db, colors = f.db, self.db.colors
	local c
	if not UnitIsConnected(unit) then
		c = colors.disconnected
	elseif UnitIsTapDenied and UnitIsTapDenied(unit) and not UnitPlayerControlled(unit) then
		c = colors.tapped
	elseif colors.healthClass and (db.health.colorClass or db.health.colorReaction) then
		c = S.UnitColor(unit)
	else
		c = colors.health
	end
	local r, g, b = c.r, c.g, c.b
	-- Sentinel dark mode: slate bar with a faint class tint, class color lives on the
	-- edge strip and the name; missing health shows as dark red behind the bar
	if colors.healthMode ~= "CLASS" and c ~= colors.disconnected and c ~= colors.tapped then
		local d = colors.darkHealth or { r = 0.14, g = 0.15, b = 0.19 }
		local tint = colors.darkTint or 0.3
		local cc = S.UnitColor(unit)
		health:SetStatusBarColor(d.r + (cc.r - d.r) * tint, d.g + (cc.g - d.g) * tint, d.b + (cc.b - d.b) * tint)
		local m = colors.darkMissing or { r = 0.42, g = 0.07, b = 0.07 }
		health.bg:SetVertexColor(m.r, m.g, m.b, 1)
		if f.Edge then f.Edge:SetVertexColor(cc.r, cc.g, cc.b, 1) end
		return
	end
	health:SetStatusBarColor(r, g, b)
	if f.Edge then
		local ec = (UnitIsPlayer(unit) or UnitPlayerControlled(unit)) and S.UnitColor(unit) or c
		f.Edge:SetVertexColor(ec.r * 0.5 + 0.5, ec.g * 0.5 + 0.5, ec.b * 0.5 + 0.5, 1)
	end
	local bg = colors.healthBackdrop
	local br, bgc, bb
	if colors.healthClass then
		br, bgc, bb = r * 0.25, g * 0.25, b * 0.25
	else
		br, bgc, bb = bg.r, bg.g, bg.b
	end
	-- backdrop by value: the missing-health area shifts towards the backdrop color as health drops
	if colors.healthBackdropByValue and colors.healthClass then
		local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
		if not IsSecret(cur) and not IsSecret(mx) and mx and mx > 0 then
			local missing = 1 - cur / mx
			br = br + (bg.r - br) * missing
			bgc = bgc + (bg.g - bgc) * missing
			bb = bb + (bg.b - bb) * missing
		end
	end
	health.bg:SetVertexColor(br, bgc, bb, 1)
end

function UF:UpdateHealth(f)
	local unit = f.unit
	if not unit or not UnitExists(unit) then return end
	local health = f.Health
	local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
	health:SetMinMaxValues(0, IsSecret(mx) and mx or max(mx or 1, 1))
	if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
		smoothing[health] = nil
		health:SetValue(0)
		if health.cutaway then health.cutaway:Hide() cutaways[health.cutaway] = nil end
	else
		if self.db.cutaway and f._prevHealth and not IsSecret(cur) and not IsSecret(mx) then
			ShowCutaway(health, f._prevHealth, cur, mx)
		end
		self:SetBarValue(health, cur)
	end
	f._prevHealth = cur
	if f.HealthText then self:SetTagText(f.HealthText, f.db.health.text, unit) end
	self:UpdateHealthColor(f)
	if f.HealPrediction then self:UpdateHealPrediction(f) end
	self:UpdateCustomTexts(f)
end

function UF:UpdatePower(f)
	local unit, power = f.unit, f.Power
	if not power or not unit or not UnitExists(unit) then return end
	local cur, mx = UnitPower(unit), UnitPowerMax(unit)
	power:SetMinMaxValues(0, IsSecret(mx) and mx or max(mx or 1, 1))
	self:SetBarValue(power, cur)
	local r, g, b
	if self.db.colors.powerClassColor and UnitIsPlayer(unit) then
		local c = S.UnitColor(unit) r, g, b = c.r, c.g, c.b
	else
		r, g, b = PowerColor(unit)
	end
	power:SetStatusBarColor(r, g, b)
	power.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 1)
	if f.PowerText then self:SetTagText(f.PowerText, f.db.power.text, unit) end
	if f.db.power.hideWhenEmpty and not IsSecret(mx) then
		power:SetAlpha(mx == 0 and 0 or 1)
	end
	-- power prediction: overlay the cost of the spell currently being cast
	if unit == "player" then
		if not power.pred then
			local t = power:CreateTexture(nil, "ARTWORK", nil, 2)
			t:SetTexture(S.media.statusbar or "Interface/Buttons/WHITE8x8")
			t:SetVertexColor(0.9, 0.7, 0.2, 0.45)
			power.pred = t
		end
		local cost
		local name, _, _, _, _, _, _, spellId = UnitCastingInfo(unit)
		if not name then name, _, _, _, _, _, _, spellId = UnitChannelInfo(unit) end
		if name then
			local cts
			if C_Spell and C_Spell.GetSpellPowerCost then cts = C_Spell.GetSpellPowerCost(spellId or name) end
			if not cts and GetSpellPowerCost then cts = GetSpellPowerCost(spellId or name) end
			if type(cts) == "table" then
				for _, c in ipairs(cts) do
					if c.cost and c.cost > 0 then cost = c.cost break end
				end
			elseif type(cts) == "number" and cts > 0 then
				cost = cts
			end
		end
		if cost and mx and mx > 0 then
			local w = power:GetWidth() * math.min(1, cost / mx)
			power.pred:ClearAllPoints()
			power.pred:SetPoint("TOP", power:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
			power.pred:SetPoint("BOTTOM", power:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
			power.pred:SetWidth(math.max(1, w))
			power.pred:Show()
		else
			power.pred:Hide()
		end
	end
	self:UpdateCustomTexts(f)
end

function UF:UpdateName(f)
	local unit = f.unit
	if not unit or not f.NameText then return end
	self:SetTagText(f.NameText, f.db.name.text .. ((f.db.level.enable and f.showLevelInName) and " [level]" or ""), unit, f.db.name)
	if f.db.name.classColor then
		local c = S.UnitColor(unit)
		f.NameText:SetTextColor(c.r, c.g, c.b)
	else
		f.NameText:SetTextColor(1, 1, 1)
	end
	if f.LevelText then self:SetTagText(f.LevelText, "[level]", unit) end
	self:UpdateCustomTexts(f)
end

-- free tag-based texts at arbitrary positions (customTexts table per unit)
function UF:UpdateCustomTexts(f)
	local pool = f.customTextPool
	if not pool then return end
	local unit = f.unit
	if not unit then return end
	for name, fs in pairs(pool) do
		local ct = f.db.customTexts and f.db.customTexts[name]
		if ct and ct.text and ct.text ~= "" and fs:IsShown() then
			S:SafeCall("UnitFrames:CustomText", function()
				UF:SetTagText(fs, ct.text, unit, ct)
				if ct.colorClass then
					local c = S.UnitColor(unit)
					fs:SetTextColor(c.r, c.g, c.b)
				else
					local col = ct.color
					if col and col.r then fs:SetTextColor(col.r, col.g, col.b) else fs:SetTextColor(1, 1, 1) end
				end
			end)
		end
	end
end

function UF:UpdateHealPrediction(f)
	local hp = f.HealPrediction
	local unit = f.unit
	local health = f.Health
	local incoming = UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or 0
	local absorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
	local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
	if IsSecret(incoming) or IsSecret(cur) or IsSecret(mx) or IsSecret(absorb) or not mx or mx == 0 then
		hp.heal:Hide() hp.absorb:Hide()
		return
	end
	local width = health:GetWidth()
	local function Place(tex, startValue, amount)
		if not amount or amount <= 0 or startValue >= mx then tex:Hide() return end
		local w = min(amount, mx - startValue) / mx * width
		if w < 1 then tex:Hide() return end
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", health, "TOPLEFT", startValue / mx * width, 0)
		tex:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", startValue / mx * width, 0)
		tex:SetWidth(w)
		tex:Show()
	end
	Place(hp.heal, cur, incoming)
	Place(hp.absorb, min(mx, cur + (incoming or 0)), absorb)
end

function UF:UpdateRaidIcon(f)
	local icon = f.RaidIcon
	if not icon then return end
	local index = f.unit and GetRaidTargetIndex(f.unit)
	if index and not IsSecret(index) then
		SetRaidTargetIconTexture(icon, index)
		icon:Show()
	else
		icon:Hide()
	end
end

function UF:UpdateIndicators(f)
	local unit = f.unit
	if f.LeaderIcon then
		f.LeaderIcon:SetShown(f.db.leaderIcon and (UnitIsGroupLeader(unit)) or false)
	end
	if f.RoleIcon then
		local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
		if f.db.roleIcon and role and not IsSecret(role) and ROLE_COORDS[role] and IsInGroup() then
			f.RoleIcon:SetTexture([[Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES]])
			if GetTexCoordsForRoleSmallCircle then
				f.RoleIcon:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
			else
				f.RoleIcon:SetTexCoord(unpack(ROLE_COORDS[role]))
			end
			f.RoleIcon:Show()
		else
			f.RoleIcon:Hide()
		end
	end
	if f.ClassIcon then
		local _, class = UnitClass(unit)
		local coords = class and not IsSecret(class) and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		if f.db.classIcon and UnitIsPlayer(unit) and coords then
			local l, r, t, b = unpack(coords)
			local inset = (r - l) * 0.08
			f.ClassIcon.icon:SetTexCoord(l + inset, r - inset, t + inset, b - inset)
			local c = S.UnitColor(unit)
			f.ClassIcon:SetBackdropBorderColor(c.r, c.g, c.b)
			f.ClassIcon:Show()
		else
			f.ClassIcon:Hide()
		end
	end
	if UnitIsPVP then
		if not f.PVPIcon and f.Health then
			f.PVPIcon = f:CreateTexture(nil, "OVERLAY")
			f.PVPIcon:SetSize(14, 14)
			f.PVPIcon:SetPoint("TOPRIGHT", f.Health, "TOPRIGHT", -2, -2)
			f.PVPIcon:SetTexture([[Interface/TargetingFrame/UI-PVP-Alliance]])
			local _, fac = UnitFactionGroup("player")
			if fac == "Horde" then f.PVPIcon:SetTexture([[Interface/TargetingFrame/UI-PVP-Horde]]) end
		end
		if f.PVPIcon then f.PVPIcon:SetShown(UnitIsPVP(unit) or false) end
	end
	if unit and unit:match("^party%d$") then
		if not f.PartyIdx then
			f.PartyIdx = S:FontString(f.Health or f, 10, "OUTLINE", S.media.numberFont)
			f.PartyIdx:SetPoint("BOTTOMLEFT", f.Health or f, "BOTTOMLEFT", 2, 1)
			f.PartyIdx:SetTextColor(0.9, 0.8, 0.4)
		end
		f.PartyIdx:SetText(unit:match("%d"))
		f.PartyIdx:Show()
	elseif f.PartyIdx then
		f.PartyIdx:Hide()
	end
	if f.RestingIcon then f.RestingIcon:SetShown(f.db.restingIcon and IsResting() or false) end
	if f.CombatIcon then f.CombatIcon:SetShown(f.db.combatIcon and UnitAffectingCombat("player") or false) end
	-- incoming resurrection icon (center) where the client exposes the API
	if UnitHasIncomingResurrection then
		if not f.ResIcon and f.Health then
			f.ResIcon = f:CreateTexture(nil, "OVERLAY")
			f.ResIcon:SetSize(20, 20)
			f.ResIcon:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
			f.ResIcon:SetTexture([[Interface\RaidFrame\Raid-Icon-Rez]])
		end
		if f.ResIcon then f.ResIcon:SetShown(UnitHasIncomingResurrection(unit) or false) end
	end
	-- incoming summon icon where the client exposes the API
	if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
		if not f.SummonIcon and f.Health then
			f.SummonIcon = f:CreateTexture(nil, "OVERLAY")
			f.SummonIcon:SetSize(16, 16)
			f.SummonIcon:SetPoint("CENTER", f.Health, "TOP", 0, -2)
			f.SummonIcon:SetTexture([[Interface\RaidFrame\Raid-Icon-SummonPending]])
		end
		if f.SummonIcon then
			local st = C_IncomingSummon.IncomingSummonStatus(unit)
			f.SummonIcon:SetShown(st and st ~= 0 or false)
		end
	end
end

function UF:UpdateThreat(f)
	if not f.Threat then return end
	local status = UnitThreatSituation and UnitThreatSituation(f.unit)
	if f.db.threatGlow and status and not IsSecret(status) and status > 1 then
		local r, g, b = GetThreatStatusColor(status)
		f.Threat:SetBackdropBorderColor(r, g, b, 1)
		f.Threat:Show()
	else
		f.Threat:Hide()
	end
end

function UF:UpdatePortrait(f)
	local p = f.Portrait
	if not p then return end
	if p.is3D then
		if not UnitIsVisible(f.unit) or not UnitIsConnected(f.unit) then
			if not p.showingUnknown then
				p.showingUnknown = true
				p.guid, p.pending = nil, nil
				p:ClearModel()
				p:SetModel([[Interface\Buttons\TalkToMeQuestionMark.m2]])
			end
			return
		end
		-- 3D models flicker when SetUnit/zoom is re-applied on every update.
		-- Only re-set when the unit changed, with a short retry window while
		-- the model data is still loading (client refires UNIT_PORTRAIT_UPDATE).
		local guid = UnitGUID(f.unit)
		local now = GetTime()
		if p.guid ~= guid or (p.pending and now - p.pending < 3) then
			if p.guid ~= guid then p.pending = now end
			p.showingUnknown = nil
			p:SetUnit(f.unit)
			p:SetCamDistanceScale(1)
			p:SetPortraitZoom(1)
		end
	else
		local tex = p.tex or p
		if UnitIsConnected(f.unit) and UnitIsVisible(f.unit) then
			SetPortraitTexture(tex, f.unit)
		else
			tex:SetTexture([[Interface\CharacterFrame\TempPortrait]])
		end
	end
end

function UF:UpdateRange(f)
	if not f.db.rangeFade or f.unit == "player" then f:SetAlpha(1) return end
	local unit = f.unit
	if not UnitExists(unit) then return end
	if f.SetAlphaFromBoolean and UnitInRange then
		local inRange, checked = UnitInRange(unit)
		if IsSecret(inRange) then
			f:SetAlphaFromBoolean(inRange, 1, f.db.rangeAlpha)
			return
		end
	end
	f:SetAlpha(S.UnitInRange(unit) and 1 or f.db.rangeAlpha)
end

function UF:UpdateDispelHighlight(f)
	if not f.Dispel then return end
	if not f.db.dispelHighlight then f.Dispel:Hide() return end
	for i = 1, 40 do
		local aura = S.GetAura(f.unit, i, "HARMFUL")
		if not aura then break end
		local dtype = aura.dispelName
		if not IsSecret(dtype) and dtype and DEBUFF_COLORS[dtype] then
			local c = DEBUFF_COLORS[dtype]
			f.Dispel:SetBackdropColor(c.r, c.g, c.b, 0.35)
			f.Dispel:SetBackdropBorderColor(c.r, c.g, c.b, 1)
			f.Dispel:Show()
			return
		end
	end
	f.Dispel:Hide()
end

-- Auras ---------------------------------------------------------------------
local function AuraOnEnter(btn)
	if not btn:IsVisible() then return end
	GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMRIGHT")
	if btn.auraInstanceID and GameTooltip.SetUnitAuraByAuraInstanceID then
		GameTooltip:SetUnitAuraByAuraInstanceID(btn.unit, btn.auraInstanceID)
	else
		GameTooltip:SetUnitAura(btn.unit, btn.index, btn.filter)
	end
	GameTooltip:Show()
end

local function CreateAuraButton(holder, i)
	local b = CreateFrame("Button", nil, holder)
	b:SetSize(holder.size, holder.size)
	S:CreateBackdrop(b, "Default")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	b.cd:SetReverse(true)
	S:RegisterCooldown(b.cd)
	b.count = S:FontString(b, 11, "OUTLINE", S.media.numberFont)
	b.count:SetPoint("BOTTOMRIGHT", 1, 1)
	b.count:SetDrawLayer("OVERLAY", 7)
	b:SetScript("OnEnter", AuraOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:RegisterForClicks("RightButtonUp")
	holder[i] = b
	return b
end

function UF:CreateAuras(f, kind)
	local holder = CreateFrame("Frame", nil, f)
	holder.kind = kind
	holder.filter = kind == "buffs" and "HELPFUL" or "HARMFUL"
	holder.size = 22
	holder:SetSize(10, 10)
	return holder
end

function UF:LayoutAuras(f, holder, db)
	holder.size, holder.perRow, holder.maxRows, holder.spacing = db.size, db.perRow, db.maxRows, db.spacing or 2
	local anchor, growthY = db.anchor, db.growthY
	holder:ClearAllPoints()
	local w = db.perRow * (db.size + holder.spacing) - holder.spacing
	holder:SetSize(w, db.size)
	local top = f.ClassPower and 15 or 4
	if anchor == "TOPLEFT" then holder:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, top)
	elseif anchor == "TOPRIGHT" then holder:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, top)
	elseif anchor == "BOTTOMLEFT" then holder:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4 - (f.castbarBelow or 0))
	elseif anchor == "BOTTOMRIGHT" then holder:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4 - (f.castbarBelow or 0))
	elseif anchor == "RIGHT" then holder:SetPoint("LEFT", f, "RIGHT", 4, 0)
	elseif anchor == "LEFT" then holder:SetPoint("RIGHT", f, "LEFT", -4, 0)
	else holder:SetPoint("CENTER", f.Health or f, "CENTER", 0, 0) end
	holder.growRight = not (anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" or anchor == "LEFT")
	holder.growUp = growthY == "UP"
	holder.centered = anchor == "CENTER"
	for _, b in ipairs(holder) do b:SetSize(db.size, db.size) end
end

local function SetAuraTimer(b, unit, aura)
	local duration, expiration = aura.duration, aura.expirationTime
	if IsSecret(duration) or IsSecret(expiration) then
		if C_UnitAuras.GetAuraDuration and b.cd.SetCooldownFromDurationObject and aura.auraInstanceID then
			local obj = C_UnitAuras.GetAuraDuration(unit, aura.auraInstanceID)
			if obj then b.cd:SetCooldownFromDurationObject(obj) b.cd:Show() return end
		end
		b.cd:Hide()
		return
	end
	if duration and duration > 0 and expiration then
		b.cd:SetCooldown(expiration - duration, duration)
		b.cd:Show()
	else
		b.cd:Hide()
	end
end

local function SetAuraCount(b, unit, aura)
	local count = aura.applications
	if IsSecret(count) then
		if C_UnitAuras.GetAuraApplicationDisplayCount and aura.auraInstanceID then
			b.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, aura.auraInstanceID, 2, 999))
		else
			b.count:SetText("")
		end
		return
	end
	b.count:SetText(count and count > 1 and count or "")
end

-- Filter lists (Blacklist / Whitelist / custom). Values: true = listed, false = removed default.
function UF:InFilter(name, aura)
	local list = self.db.filters and self.db.filters[name]
	if not list or not list.spells then return false end
	local id, spellName = aura.spellId, aura.name
	if id and not IsSecret(id) and list.spells[id] == true then return true end
	if spellName and not IsSecret(spellName) and list.spells[spellName:lower()] == true then return true end
	return false
end

function UF:PassesFilter(aura, db, isEnemy)
	if IsSecret(aura.spellId) or IsSecret(aura.duration) then return true end
	local custom = db.customFilter
	if custom and custom ~= "NONE" and self.db.filters[custom] then
		local inList = self:InFilter(custom, aura)
		if self.db.filters[custom].type == "Whitelist" then
			if inList then return true end
			if not db.useWhitelist then return false end
		elseif inList then
			return false
		end
	end
	if db.useBlacklist and self:InFilter("Blacklist", aura) then return false end
	if db.useWhitelist and not self:InFilter("Whitelist", aura) then return false end
	local duration = aura.duration or 0
	if duration == 0 and db.noDuration == false then return false end
	if duration > 0 then
		if db.maxDuration and db.maxDuration > 0 and duration > db.maxDuration then return false end
		if db.minDuration and db.minDuration > 0 and duration < db.minDuration then return false end
	end
	-- debuffs: only magic/curse/poison/disease; buffs: only stealable/purgeable ones on enemies
	if db.onlyDispellable and not IsSecret(aura.dispelName) and not IsSecret(aura.isStealable) then
		if aura.isHelpful then
			if not (isEnemy and aura.isStealable) then return false end
		elseif not aura.dispelName then
			return false
		end
	end
	return true
end

function UF:UpdateAuras(f, holder, db)
	local unit = f.unit
	if not unit or not UnitExists(unit) then holder:Hide() return end
	holder:Show()
	local filter = holder.filter .. (db.onlyPlayer and "|PLAYER" or "")
	if f.isGroup and holder.kind == "debuffs" and f.db.debuffs.anchor == "CENTER" then filter = "HARMFUL|RAID" end
	local maxIcons = db.perRow * db.maxRows
	local shown = 0
	local isEnemy = UnitCanAttack("player", unit)
	local iterated, firstName = 0
	for i = 1, 40 do
		if shown >= maxIcons then break end
		local aura = S.GetAura(unit, i, filter)
		if not aura then break end
		iterated = i
		if not firstName and not IsSecret(aura.spellId) then firstName = tostring(aura.name) .. "/" .. tostring(aura.spellId) end
		if self:PassesFilter(aura, db, isEnemy) then
		shown = shown + 1
		local b = holder[shown] or CreateAuraButton(holder, shown)
		b.unit, b.index, b.filter, b.auraInstanceID = unit, i, filter, aura.auraInstanceID
		-- nil icon would leave an invisible bordered square; keep it visible
		b.icon:SetTexture(aura.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		SetAuraTimer(b, unit, aura)
		SetAuraCount(b, unit, aura)
		local bd = b.suiBackdrop
		if holder.kind == "debuffs" then
			local dtype = aura.dispelName
			local c = (not IsSecret(dtype) and dtype and DEBUFF_COLORS[dtype]) or DEBUFF_COLORS.none
			bd:SetBackdropBorderColor(c.r, c.g, c.b)
			local mine = aura.sourceUnit
			if isEnemy and not db.onlyPlayer and not IsSecret(mine) then
				b.icon:SetDesaturated(not (mine == "player" or mine == "pet" or mine == "vehicle"))
			else
				b.icon:SetDesaturated(false)
			end
		else
			local steal = aura.isStealable
			if isEnemy and not IsSecret(steal) and steal then bd:SetBackdropBorderColor(1, 0.9, 0.3) else bd:SetBackdropBorderColor(unpack(S.media.borderColor)) end
		end
		local idx = shown - 1
		local col, row = idx % db.perRow, floor(idx / db.perRow)
		b:ClearAllPoints()
		local step = db.size + (holder.spacing or db.spacing or 0)
		if holder.centered then
			b:SetPoint("CENTER", holder, "CENTER", (col - (min(maxIcons, db.perRow) - 1) / 2) * step, 0)
		else
			local x = holder.growRight and col * step or -col * step
			local y = holder.growUp and row * step or -row * step
			local point = (holder.growUp and "BOTTOM" or "TOP") .. (holder.growRight and "LEFT" or "RIGHT")
			b:SetPoint(point, holder, point, x, y)
		end
		b:Show()
		end
	end
	for i = shown + 1, #holder do holder[i]:Hide() end
	if holder.centered and shown > 0 then
		for i = 1, shown do
			local b = holder[i]
			b:ClearAllPoints()
			b:SetPoint("CENTER", holder, "CENTER", (i - 1 - (shown - 1) / 2) * (db.size + holder.spacing), 0)
		end
	end
end

local function CreateIndicator(holder, i)
	local b = CreateFrame("Frame", nil, holder)
	b:SetSize(9, 9)
	S:CreateBackdrop(b, "Default")
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetPoint("TOPLEFT", 1, -1)
	b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return b
end

-- buff indicators (aura watch): icons from the BuffIndicator filter along the
-- top edge of the frame - HoTs, shields, earth shield, etc. for healers
function UF:UpdateBuffIndicators(f)
	local holder = f.Indicators
	if not holder then return end
	local db = f.db and f.db.buffIndicators
	local filters = self.db.filters
	local list = filters and filters.BuffIndicator and filters.BuffIndicator.spells
	local unit = f.unit
	local shown = 0
	if db and db.enable and list and unit and UnitExists(unit) then
		local size = db.size or 9
		local maxShow = db.max or 5
		for i = 1, 40 do
			if shown >= maxShow then break end
			local aura = S.GetAura(unit, i, "HELPFUL")
			if not aura then break end
			local id, name = aura.spellId, aura.name
			if (id and not IsSecret(id) and list[id]) or (name and not IsSecret(name) and list[name:lower()]) then
				shown = shown + 1
				local b = holder[shown]
				if not b then b = CreateIndicator(holder, shown) holder[shown] = b end
				b:SetSize(size, size)
				b:ClearAllPoints()
				b:SetPoint("LEFT", holder, "LEFT", (shown - 1) * (size + 2), 0)
				b.tex:SetTexture(aura.icon)
				b:Show()
			end
		end
	end
	for i = shown + 1, #holder do holder[i]:Hide() end
end

-- Aura bars: buffs/debuffs as sorted timer bars (alternative to icon grids)
local auraBarTmp = {}
local function CreateAuraBar(parent)
	local bar = S:CreateStatusBar(parent, nil, "Default")
	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	bar.nameText = S:FontString(bar, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	bar.timeText = S:FontString(bar, 11, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	return bar
end

local function AuraBarsOnUpdate(holder, elapsed)
	holder.t = (holder.t or 0) + elapsed
	if holder.t < 0.1 then return end
	holder.t = 0
	local now = GetTime()
	for i = 1, #holder do
		local bar = holder[i]
		if not bar:IsShown() then break end
		if bar.expTime and bar.duration and bar.duration > 0 then
			local remain = bar.expTime - now
			if remain < 0 then remain = 0 end
			bar:SetValue(remain)
			if bar.timeText then bar.timeText:SetText(S:FormatTime(remain)) end
		elseif bar.timeText then
			bar.timeText:SetText("")
		end
	end
end

function UF:UpdateAuraBars(f)
	local holder = f.AuraBars
	local db = f.db.aurabars
	if not holder then return end
	if not db or not db.enable then holder:Hide() return end
	local unit = f.unit
	if not unit or not UnitExists(unit) then holder:Hide() return end
	holder:Show()

	local extraFilter = db.onlyPlayer and "|PLAYER" or ""
	wipe(auraBarTmp)
	for i = 1, 40 do
		local aura = S.GetAura(unit, i, "HELPFUL" .. extraFilter)
		if not aura then break end
		auraBarTmp[#auraBarTmp + 1] = aura
	end
	for i = 1, 40 do
		local aura = S.GetAura(unit, i, "HARMFUL" .. extraFilter)
		if not aura then break end
		auraBarTmp[#auraBarTmp + 1] = aura
	end
	if db.sort == "NAME" then
		sort(auraBarTmp, function(a, b) return tostring(a.name) < tostring(b.name) end)
	else
		sort(auraBarTmp, function(a, b)
			local ae, be = a.expirationTime or 0, b.expirationTime or 0
			if IsSecret(ae) then ae = 0 end
			if IsSecret(be) then be = 0 end
			if ae == 0 then ae = math.huge end
			if be == 0 then be = math.huge end
			return ae < be
		end)
	end

	local isEnemy = UnitCanAttack("player", unit)
	local bh, sp = db.barHeight or 14, db.spacing or 2
	local growDown = db.growth ~= "UP"
	local now = GetTime()
	local shown = 0
	for i = 1, min(#auraBarTmp, db.maxBars or 8) do
		local aura = auraBarTmp[i]
		shown = shown + 1
		local bar = holder[shown]
		if not bar then bar = CreateAuraBar(holder) holder[shown] = bar end
		bar:ClearAllPoints()
		local y = (shown - 1) * (bh + sp)
		bar:SetPoint("TOPLEFT", holder, growDown and "TOPLEFT" or "BOTTOMLEFT", bh, growDown and -y or y)
		bar:SetPoint("TOPRIGHT", holder, growDown and "TOPRIGHT" or "BOTTOMRIGHT", 0, growDown and -y or y)
		bar:SetHeight(bh)
		bar:SetStatusBarTexture(S:Fetch("statusbar", self.db.statusbar, "Sentinel"))
		bar.icon:ClearAllPoints()
		bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
		bar.icon:SetSize(bh, bh)
		bar.icon:SetTexture(aura.icon)
		bar.nameText:ClearAllPoints()
		bar.nameText:SetPoint("LEFT", 3, 0)
		bar.nameText:SetPoint("RIGHT", bar.timeText, "LEFT", -4, 0)
		bar.nameText:SetText(db.showName and aura.name or "")
		bar.timeText:ClearAllPoints()
		bar.timeText:SetPoint("RIGHT", -3, 0)
		bar.timeText:SetShown(db.showTime ~= false)
		local exp, dur = aura.expirationTime, aura.duration
		if not IsSecret(exp) and exp and dur and dur > 0 then
			bar.expTime, bar.duration = exp, dur
			bar:SetMinMaxValues(0, dur)
			bar:SetValue(max(0, exp - now))
		else
			bar.expTime, bar.duration = nil, nil
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(1)
		end
		local r, g, b
		if aura.isHarmful then
			local dtype = aura.dispelName
			local c = (not IsSecret(dtype) and dtype and DEBUFF_COLORS[dtype]) or DEBUFF_COLORS.none
			r, g, b = c.r, c.g, c.b
		elseif isEnemy then
			r, g, b = 0.35, 0.75, 0.35
		else
			local c = S.UnitColor(unit)
			if self.db.colors.healthClassColor and UnitIsPlayer(unit) then r, g, b = c.r, c.g, c.b
			else r, g, b = S.accent.r, S.accent.g, S.accent.b end
		end
		bar:SetStatusBarColor(r, g, b)
		bar:Show()
	end
	for i = shown + 1, #holder do holder[i]:Hide() end
	holder:SetScript("OnUpdate", shown > 0 and AuraBarsOnUpdate or nil)
end

-- priority debuff icon: center icon on the frame for debuffs the player can
-- dispel (by class) or boss-flagged auras - the "this matters NOW" marker
local DISPEL = {
	DRUID = { Curse = true, Poison = true },
	PRIEST = { Magic = true, Disease = true },
	PALADIN = { Magic = true, Disease = true, Poison = true },
	SHAMAN = { Disease = true, Poison = true },
	MAGE = { Curse = true },
	WARLOCK = { Magic = true },
}
function UF:UpdatePrioDebuff(f)
	if not f.Health then return end
	if not f.PrioDebuff then
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetSize(20, 20)
		t:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
		t:SetTexCoord(0.06, 0.94, 0.06, 0.94)
		f.PrioDebuff = t
	end
	local unit = f.unit
	if not unit or not S.UnitAura then f.PrioDebuff:Hide() return end
	local _, myClass = UnitClass("player")
	local can = DISPEL[myClass] or {}
	local icon
	for i = 1, 8 do
		local a = { S.UnitAura(unit, i, "HARMFUL") }
		if not a[1] then break end
		local dType, isBoss = a[4], a[12]
		if isBoss or (dType and can[dType]) then icon = a[2] break end
	end
	if icon then f.PrioDebuff:SetTexture(icon) f.PrioDebuff:Show() else f.PrioDebuff:Hide() end
end

function UF:UpdateAllAuras(f)
	if f.Buffs and f.db.buffs.enable then self:UpdateAuras(f, f.Buffs, f.db.buffs) end
	if f.Debuffs and f.db.debuffs.enable then self:UpdateAuras(f, f.Debuffs, f.db.debuffs) end
	if f.Dispel then self:UpdateDispelHighlight(f) end
	if f.Indicators then self:UpdateBuffIndicators(f) end
	if f.AuraBars then self:UpdateAuraBars(f) end
end

-- Castbar -------------------------------------------------------------------
local function CastInfo(unit, channel)
	local name, text, texture, startMS, endMS, isTrade, castID, notInterruptible, spellID
	if channel then
		local r = { UnitChannelInfo(unit) }
		name, text, texture, startMS, endMS, isTrade = r[1], r[2], r[3], r[4], r[5], r[6]
		if type(r[7]) == "boolean" then notInterruptible, spellID = r[7], r[8] else spellID = r[7] end
		if type(r[8]) == "boolean" then notInterruptible = r[8] spellID = r[9] end
	else
		local r = { UnitCastingInfo(unit) }
		name, text, texture, startMS, endMS, isTrade, castID = r[1], r[2], r[3], r[4], r[5], r[6], r[7]
		if type(r[8]) == "boolean" then notInterruptible, spellID = r[8], r[9] else spellID = r[8] end
	end
	return name, text, texture, startMS, endMS, notInterruptible, spellID
end

local function CastbarOnUpdate(cb, elapsed)
	if cb.timerObject then return end
	if cb.casting or cb.channeling then
		local now = GetTime()
		if cb.pushMarkFade then
			cb.pushMarkFade = cb.pushMarkFade - elapsed
			if cb.pushMarkFade <= 0 then cb.pushMarkFade = nil cb.PushMark:Hide()
			else cb.PushMark:SetAlpha(0.9 * cb.pushMarkFade / 0.6) end
		end
		local value = cb.casting and (now - cb.startTime) or (cb.endTime - now)
		if (cb.casting and value >= cb.duration) or (cb.channeling and value <= 0) then
			cb.casting, cb.channeling = nil, nil
			cb.fade = 0.3
			return
		end
		cb:SetValue(value)
		if cb.Time then
			local remain = cb.casting and (cb.duration - value) or value
			if cb.delay and cb.delay ~= 0 then
				cb.Time:SetFormattedText("%.1f |cffff4444%+.1f|r", remain, cb.delay)
			else
				cb.Time:SetFormattedText("%.1f", remain)
			end
		end
		if cb.Spark then
			local pct = value / cb.duration
			cb.Spark:SetPoint("CENTER", cb, "LEFT", pct * cb:GetWidth(), 0)
		end
	elseif cb.fade then
		cb.fade = cb.fade - elapsed
		cb:SetAlpha(max(0, cb.fade / 0.3))
		if cb.fade <= 0 then cb.fade = nil cb:Hide() cb:SetAlpha(1) end
	else
		cb:Hide()
	end
end

function UF:CreateCastbar(f)
	local cb = S:CreateStatusBar(f, nil, "Default")
	cb:Hide()
	cb.unit = f.unit
	cb.Text = S:FontString(cb, 12, "OUTLINE", S.media.unitFont, nil, "LEFT")
	cb.Text:SetPoint("LEFT", 4, 0)
	cb.Time = S:FontString(cb, 12, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	cb.Time:SetPoint("RIGHT", -4, 0)
	cb.Text:SetPoint("RIGHT", cb.Time, "LEFT", -4, 0)
	cb.Spark = cb:CreateTexture(nil, "OVERLAY")
	cb.Spark:SetTexture(BLANK)
	cb.Spark:SetVertexColor(1, 1, 1, 0.6)
	cb.Spark:SetSize(2, 10)
	cb.Spark:SetBlendMode("ADD")
	-- pushback marker: red tick where the fill jumped back to after a delay
	cb.PushMark = cb:CreateTexture(nil, "OVERLAY", nil, 5)
	cb.PushMark:SetTexture(BLANK)
	cb.PushMark:SetVertexColor(1, 0.25, 0.25)
	cb.PushMark:SetWidth(2)
	cb.PushMark:Hide()
	local iconHolder = CreateFrame("Frame", nil, cb)
	S:CreateBackdrop(iconHolder, "Default")
	cb.Icon = iconHolder:CreateTexture(nil, "ARTWORK")
	cb.Icon:SetAllPoints()
	cb.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cb.IconHolder = iconHolder
	cb.SafeZone = cb:CreateTexture(nil, "ARTWORK")
	cb.SafeZone:SetTexture(BLANK)
	cb.SafeZone:SetVertexColor(0.85, 0.2, 0.2, 0.45)
	cb.Shield = iconHolder:CreateTexture(nil, "OVERLAY")
	cb.Shield:SetTexture(BLANK)
	cb.Shield:SetVertexColor(0.8, 0.2, 0.2, 0.4)
	cb.Shield:SetAllPoints()
	cb.Shield:Hide()
	cb:SetScript("OnUpdate", CastbarOnUpdate)
	f.Castbar = cb
	return cb
end

function UF:CastStart(f, channel)
	local cb = f.Castbar
	local unit = f.unit
	local name, text, texture, startMS, endMS, notInterruptible = CastInfo(unit, channel)
	if not name then cb.casting, cb.channeling = nil, nil return end
	local colors = self.db.colors
	cb.Icon:SetTexture(texture)
	-- "Opening - No Text" is the client's internal label for item-opening casts
	local label = text and text ~= "" and not channel and text or name
	cb.Text:SetText(type(label) == "string" and label:gsub("%s*%-?%s*No Text$", "") or label)
	cb.delay = 0
	cb.fade = nil
	cb.pushMarkFade = nil
	if cb.PushMark then cb.PushMark:Hide() end
	cb:SetAlpha(1)
	local secretInterrupt = IsSecret(notInterruptible)
	local c = (not secretInterrupt and notInterruptible) and colors.castNoInterrupt or colors.castbar
	cb:SetStatusBarColor(c.r, c.g, c.b)
	cb.Shield:SetShown(not secretInterrupt and notInterruptible or false)

	if IsSecret(startMS) or IsSecret(endMS) then
		local durationFunc = channel and UnitChannelDuration or UnitCastingDuration
		if durationFunc and cb.SetTimerDuration then
			cb.timerObject = durationFunc(unit)
			cb:SetTimerDuration(cb.timerObject)
			cb.Time:SetText("")
			cb.casting, cb.channeling = not channel, channel
			cb.Spark:Hide()
			cb:Show()
		end
		return
	end
	cb.timerObject = nil
	cb.Spark:SetShown(f.db.castbar.spark ~= false)
	self:UpdateTicks(f, channel and name or nil)
	cb.startTime = startMS / 1000
	cb.endTime = endMS / 1000
	cb.duration = cb.endTime - cb.startTime
	cb:SetMinMaxValues(0, cb.duration)
	cb.casting, cb.channeling = not channel, channel
	cb:SetValue(channel and cb.duration or (GetTime() - cb.startTime))
	if f.unit == "player" and f.db.castbar.latency then
		local _, _, home, world = GetNetStats()
		local lag = (max(home or 0, world or 0)) / 1000
		local w = min(1, lag / max(cb.duration, 0.01)) * cb:GetWidth()
		cb.SafeZone:ClearAllPoints()
		if channel then cb.SafeZone:SetPoint("TOPLEFT") cb.SafeZone:SetPoint("BOTTOMLEFT") else cb.SafeZone:SetPoint("TOPRIGHT") cb.SafeZone:SetPoint("BOTTOMRIGHT") end
		cb.SafeZone:SetWidth(max(1, w))
		cb.SafeZone:Show()
	else
		cb.SafeZone:Hide()
	end
	cb:Show()
end

-- channel ticks (player): evenly spaced markers for known channeled spells
local tickSpells = { [5143] = 5, [689] = 5, [1120] = 5, [15407] = 3, [10] = 8, [16914] = 10, [5740] = 4, [740] = 5, [1510] = 6, [755] = 10, [5138] = 5, [12051] = 4, [746] = 8 }
local tickNames
function UF:UpdateTicks(f, channelName)
	local cb = f.Castbar
	cb.ticks = cb.ticks or {}
	for _, t in ipairs(cb.ticks) do t:Hide() end
	if not channelName or f.unit ~= "player" or not f.db.castbar.ticks or IsSecret(channelName) then return end
	if not tickNames then
		tickNames = {}
		for id, n in pairs(tickSpells) do
			local name = S.GetSpellInfo(id)
			if type(name) == "table" then name = name.name end
			if name then tickNames[name] = n end
		end
	end
	local n = tickNames[channelName]
	if not n then return end
	local w = cb:GetWidth()
	for i = 1, n - 1 do
		local t = cb.ticks[i]
		if not t then
			t = cb:CreateTexture(nil, "OVERLAY")
			t:SetTexture(BLANK)
			t:SetVertexColor(0, 0, 0, 0.75)
			cb.ticks[i] = t
		end
		t:ClearAllPoints()
		t:SetSize(S.mult * 2, cb:GetHeight())
		t:SetPoint("CENTER", cb, "LEFT", w * i / n, 0)
		t:Show()
	end
end

function UF:CastUpdate(f, channel)
	local cb = f.Castbar
	local _, _, _, startMS, endMS = CastInfo(f.unit, channel)
	if not startMS or IsSecret(startMS) or cb.timerObject then return end
	local newStart = startMS / 1000
	if channel then
		cb.delay = (cb.delay or 0) + (cb.endTime - endMS / 1000)
		cb.startTime, cb.endTime = newStart, endMS / 1000
		cb.duration = cb.endTime - cb.startTime
		cb:SetMinMaxValues(0, cb.duration)
	else
		cb.delay = (cb.delay or 0) + (newStart - cb.startTime)
		cb.startTime = newStart
		cb.endTime = endMS / 1000
		cb.duration = cb.endTime - cb.startTime
		cb:SetMinMaxValues(0, cb.duration)
		if cb.PushMark then
			local backPct = (GetTime() - newStart) / cb.duration
			if backPct > 0 and backPct < 1 then
				local x = cb:GetWidth() * backPct
				cb.PushMark:ClearAllPoints()
				cb.PushMark:SetPoint("TOP", cb, "TOPLEFT", x, 0)
				cb.PushMark:SetPoint("BOTTOM", cb, "BOTTOMLEFT", x, 0)
				cb.PushMark:SetAlpha(0.9)
				cb.PushMark:Show()
				cb.pushMarkFade = 0.6
			end
		end
	end
end

function UF:CastStop(f, event)
	local cb = f.Castbar
	if not cb:IsShown() then return end
	local colors = self.db.colors
	if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		local c = event == "UNIT_SPELLCAST_INTERRUPTED" and colors.castNoInterrupt or colors.castFailed
		cb:SetStatusBarColor(c.r, c.g, c.b)
		cb.Text:SetText(event == "UNIT_SPELLCAST_INTERRUPTED" and INTERRUPTED or FAILED)
		if not cb.timerObject then cb:SetValue(select(2, cb:GetMinMaxValues())) end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if not cb.casting then return end
		local c = colors.castSuccess
		cb:SetStatusBarColor(c.r, c.g, c.b)
	end
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" or cb.casting then
		if cb.ticks then for _, t in ipairs(cb.ticks) do t:Hide() end end
		cb.casting, cb.channeling, cb.timerObject = nil, nil, nil
		cb.fade = 0.5
	end
end

function UF:LayoutCastbar(f)
	local cb, db = f.Castbar, f.db.castbar
	if not cb then return end
	if not db.enable then cb:Hide() cb.disabled = true S:DisableMover(f.key .. "Castbar", true) return end
	cb.disabled = nil
	local width = (db.width and db.width > 0) and db.width or f.db.width
	local height = db.height
	local iconSize = db.icon and height or 0
	cb:SetSize(width - (db.icon and (iconSize + 3) or 0), height)
	cb.Spark:SetHeight(height)
	S:SetFont(cb.Text, S.media.unitFont, max(9, min(13, height - 6)), "OUTLINE")
	S:SetFont(cb.Time, S.media.numberFont, max(9, min(13, height - 6)), "OUTLINE")
	cb.IconHolder:SetSize(iconSize, iconSize)
	cb.IconHolder:SetShown(db.icon)
	cb.IconHolder:ClearAllPoints()
	cb.IconHolder:SetPoint("RIGHT", cb, "LEFT", -3, 0)
	cb.Time:SetShown(db.timeText ~= false)
	if not cb.holder then
		local holder = CreateFrame("Frame", nil, UIParent)
		cb.holder = holder
		if db.detached and f.unit and not f.isGroup and (f.unit == "player" or f.unit == "target" or f.unit == "focus") then
			local defaults = {
				player = { "BOTTOM", "SentinelUIMover_bar3", "TOP", 0, 80 },
				target = { "TOP", "SentinelUIMover_target", "BOTTOM", 0, -40 },
				focus = { "TOP", "SentinelUIMover_focus", "BOTTOM", 0, -24 },
			}
			holder:SetParent(UIParent)
			S:CreateMover(holder, f.key .. "Castbar", format(L["%s Castbar"], f.title or f.key), defaults[f.unit], "unitframes")
			holder.detached = true
		end
	end
	local holder = cb.holder
	holder:SetSize(width, height)
	cb:ClearAllPoints()
	if holder.detached then
		cb:SetParent(holder)
		cb:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
		f.castbarBelow = 0
	else
		cb:SetParent(f)
		cb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
		f.castbarBelow = height + 4
	end
	cb:SetFrameLevel(f:GetFrameLevel() + 5)
end

-- Class power (combo points / holy power / shards / chi / essence / arcane / runes)
local classPowerTypes = {
	ROGUE = "COMBO_POINTS", DRUID = "COMBO_POINTS", PALADIN = "HOLY_POWER", WARLOCK = "SOUL_SHARDS",
	MONK = "CHI", MAGE = "ARCANE_CHARGES", EVOKER = "ESSENCE",
}

function UF:CreateClassPower(f)
	local holder = CreateFrame("Frame", nil, f)
	holder:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
	holder:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 4)
	holder:SetHeight(7)
	holder.bars = {}
	for i = 1, 10 do
		local b = S:CreateStatusBar(holder, nil, "Default")
		b:SetMinMaxValues(0, 1)
		b:Hide()
		holder.bars[i] = b
	end
	f.ClassPower = holder
	return holder
end

function UF:UpdateClassPower(f)
	local cp = f.ClassPower
	if not cp then return end
	local class = S.myClass
	local num, maxNum, r, g, b = 0, 0, 1, 0.85, 0.2
	if class == "DEATHKNIGHT" and GetRuneCooldown then
		maxNum = 6
		local now = GetTime()
		for i = 1, 6 do
			local start, duration, ready = GetRuneCooldown(i)
			local bar = cp.bars[i]
			if not IsSecret(ready) then
				bar:SetMinMaxValues(0, 1)
				if ready or not start then bar:SetValue(1) else bar:SetValue(min(1, (now - start) / max(duration, 0.01))) end
			end
			bar:SetStatusBarColor(0.0, 0.75, 0.95)
		end
		num = 6
		cp.runes = true
	else
		local token = classPowerTypes[class]
		if not token then cp:Hide() return end
		local powerType = Enum and Enum.PowerType and Enum.PowerType[token == "COMBO_POINTS" and "ComboPoints" or token == "HOLY_POWER" and "HolyPower" or token == "SOUL_SHARDS" and "SoulShards" or token == "CHI" and "Chi" or token == "ARCANE_CHARGES" and "ArcaneCharges" or "Essence"]
		if token == "COMBO_POINTS" then
			if class == "DRUID" and UnitPowerType("player") ~= 3 then cp:Hide() return end
			if S.isRetail or S.isMists or S.isCata then
				num, maxNum = UnitPower("player", powerType or 4), UnitPowerMax("player", powerType or 4)
			else
				num, maxNum = GetComboPoints("player", "target"), 5
			end
			r, g, b = 1, 0.3, 0.25
		elseif powerType and (S.isRetail or S.isMists or S.isCata) then
			if class == "MAGE" and GetSpecialization and GetSpecialization() ~= 1 then cp:Hide() return end
			num, maxNum = UnitPower("player", powerType), UnitPowerMax("player", powerType)
			local pc = PowerBarColor and PowerBarColor[token]
			if pc then r, g, b = pc.r, pc.g, pc.b end
		else
			cp:Hide() return
		end
		if IsSecret(num) or IsSecret(maxNum) or not maxNum or maxNum == 0 then cp:Hide() return end
		for i = 1, maxNum do
			local bar = cp.bars[i]
			bar:SetValue(i <= num and 1 or 0)
			bar:SetStatusBarColor(r, g, b)
		end
	end
	if maxNum == 0 then cp:Hide() return end
	local width = (f:GetWidth() - (maxNum - 1) * 3) / maxNum
	for i, bar in ipairs(cp.bars) do
		if i <= maxNum then
			bar:ClearAllPoints()
			bar:SetSize(width, cp:GetHeight())
			bar:SetPoint("LEFT", cp, "LEFT", (i - 1) * (width + 3), 0)
			bar:Show()
		else
			bar:Hide()
		end
	end
	cp:Show()
end

-- druid only: mana stays relevant in bear/cat form (powershifting, healing)
function UF:UpdateDruidMana(f)
	local dm = f.DruidMana
	if not dm then return end
	local pt = S.myClass == "DRUID" and UnitPowerType("player") or 0
	if pt == 0 or not (f.db.power and f.db.power.enable) then dm:Hide() return end
	local mx = UnitPowerMax("player", 0)
	if IsSecret(mx) or not mx or mx <= 0 then dm:Hide() return end
	local cur = UnitPower("player", 0)
	dm:SetMinMaxValues(0, mx)
	self:SetBarValue(dm, IsSecret(cur) and 0 or cur)
	dm:SetStatusBarColor(0.1, 0.4, 0.95)
	if dm.bg then dm.bg:SetVertexColor(0.03, 0.12, 0.3, 1) end
	if dm.text then
		if IsSecret(cur) then dm.text:SetText("")
		else dm.text:SetFormattedText("%d%%", floor(cur / mx * 100 + 0.5)) end
	end
	dm:Show()
end

-- Frame construction --------------------------------------------------------
local function OnEnter(f)
	if UnitFrame_OnEnter then UnitFrame_OnEnter(f) end
	if f.Highlight then f.Highlight:Show() end
end

local function OnLeave(f)
	if UnitFrame_OnLeave then UnitFrame_OnLeave(f) end
	if f.Highlight then f.Highlight:Hide() end
end

function UF:BuildFrame(f, key)
	f.key = key
	f.db = self.db.units[key]
	f:RegisterForClicks("AnyUp")
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:HookScript("OnEnter", OnEnter)
	f:HookScript("OnLeave", OnLeave)

	local bd = S:CreateBackdrop(f, "Default")
	f.bd = bd
	local health = S:CreateStatusBar(f, nil, false)
	health:SetFrameLevel(f:GetFrameLevel() + 1)
	f.Health = health

	local power = S:CreateStatusBar(f, nil, false)
	power:SetFrameLevel(f:GetFrameLevel() + 1)
	f.Power = power
	f.powerSep = power:CreateTexture(nil, "OVERLAY")
	f.powerSep:SetTexture(BLANK)
	f.powerSep:SetVertexColor(0, 0, 0)
	f.powerSep:SetPoint("BOTTOMLEFT", power, "TOPLEFT")
	f.powerSep:SetPoint("BOTTOMRIGHT", power, "TOPRIGHT")
	f.powerSep:SetHeight(S.mult)

	-- glass gloss on the upper half of the health bar + soft shade at the bottom
	f.Gloss = health:CreateTexture(nil, "OVERLAY", nil, 1)
	f.Gloss:SetPoint("TOPLEFT") f.Gloss:SetPoint("TOPRIGHT")
	f.Gloss:SetPoint("BOTTOM", health, "CENTER")
	S:Gradient(f.Gloss, "VERTICAL", 1, 1, 1, 0, 0.16)
	f.Shade = health:CreateTexture(nil, "OVERLAY", nil, 1)
	f.Shade:SetPoint("BOTTOMLEFT") f.Shade:SetPoint("BOTTOMRIGHT")
	f.Shade:SetHeight(6)
	S:Gradient(f.Shade, "VERTICAL", 0, 0, 0, 0.35, 0)

	-- optional class icon next to the frame
	local ci = CreateFrame("Frame", nil, f, S.BackdropTemplate)
	S:SetTemplate(ci, "Default")
	ci.icon = ci:CreateTexture(nil, "ARTWORK")
	S:SetInside(ci.icon, ci, 1, 1)
	ci.icon:SetTexture([[Interface\WorldStateFrame\Icons-Classes]])
	ci:Hide()
	f.ClassIcon = ci

	-- Sentinel edge: thin class/reaction colored strip on the inner left of the health bar
	f.Edge = health:CreateTexture(nil, "OVERLAY", nil, 6)
	f.Edge:SetTexture(BLANK)
	f.Edge:SetPoint("TOPLEFT", health, "TOPLEFT")
	f.Edge:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT")
	f.Edge:SetWidth(4)

	local textHolder = CreateFrame("Frame", nil, f)
	textHolder:SetAllPoints()
	textHolder:SetFrameLevel(f:GetFrameLevel() + 6)
	f.textHolder = textHolder
	f.HealthText = S:FontString(textHolder, 12, self.db.fontOutline, S.media.unitFont)
	f.PowerText = S:FontString(textHolder, 11, self.db.fontOutline, S.media.unitFont)
	f.NameText = S:FontString(textHolder, 12, self.db.fontOutline, S.media.unitFont)
	f.customTextPool = {}
	-- level after the name for every single unit and party (raid frames stay compact)
	f.showLevelInName = not (key == "raid" or key == "raid40" or key == "maintank")

	local hp = {}
	hp.heal = health:CreateTexture(nil, "ARTWORK", nil, 1)
	hp.heal:SetTexture(BLANK)
	hp.absorb = health:CreateTexture(nil, "ARTWORK", nil, 2)
	hp.absorb:SetTexture(BLANK)
	hp.heal:Hide() hp.absorb:Hide()
	f.HealPrediction = hp

	f.RaidIcon = textHolder:CreateTexture(nil, "OVERLAY")
	f.RaidIcon:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
	f.RaidIcon:Hide()
	f.LeaderIcon = textHolder:CreateTexture(nil, "OVERLAY")
	f.LeaderIcon:SetTexture([[Interface\GroupFrame\UI-Group-LeaderIcon]])
	f.LeaderIcon:SetSize(14, 14)
	f.LeaderIcon:SetPoint("CENTER", f, "TOPLEFT", 8, 0)
	f.LeaderIcon:Hide()
	f.RoleIcon = textHolder:CreateTexture(nil, "OVERLAY", nil, 7)
	f.RoleIcon:SetSize(16, 16)
	f.RoleIcon:SetPoint("CENTER", f, "TOPRIGHT", -10, 0)
	f.RoleIcon:Hide()
	if key == "player" then
		f.RestingIcon = textHolder:CreateTexture(nil, "OVERLAY")
		f.RestingIcon:SetTexture([[Interface\CharacterFrame\UI-StateIcon]])
		f.RestingIcon:SetTexCoord(0, 0.5, 0, 0.421875)
		f.RestingIcon:SetSize(22, 22)
		f.RestingIcon:SetPoint("CENTER", f, "TOPLEFT", 0, 4)
		f.CombatIcon = textHolder:CreateTexture(nil, "OVERLAY")
		f.CombatIcon:SetTexture([[Interface\CharacterFrame\UI-StateIcon]])
		f.CombatIcon:SetTexCoord(0.5, 1, 0, 0.49)
		f.CombatIcon:SetSize(22, 22)
		f.CombatIcon:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
		f.CombatIcon:Hide()
		self:CreateClassPower(f)
		-- druid mana strip under the power bar: the bar shows rage/energy in
		-- forms, but mana still matters for powershifting and healing
		local dm = S:CreateStatusBar(f, nil, "Default")
		dm:SetHeight(4)
		dm:SetPoint("TOPLEFT", power, "BOTTOMLEFT", 0, -1)
		dm:SetPoint("TOPRIGHT", power, "BOTTOMRIGHT", 0, -1)
		dm:Hide()
		dm.text = S:FontString(dm, 10, self.db.fontOutline, S.media.unitFont)
		dm.text:SetPoint("CENTER", dm, "CENTER", 0, 0)
		f.DruidMana = dm
	end
	if f.db.readyCheck ~= nil and (key == "party" or key == "raid" or key == "raid40") then
		f.ReadyCheck = textHolder:CreateTexture(nil, "OVERLAY")
		f.ReadyCheck:SetSize(18, 18)
		f.ReadyCheck:SetPoint("CENTER", f.Health, "CENTER")
		f.ReadyCheck:Hide()
	end

	local threat = CreateFrame("Frame", nil, f, S.BackdropTemplate)
	S:SetOutside(threat, f, 3, 3)
	threat:SetBackdrop({ edgeFile = BLANK, edgeSize = 2 })
	threat:SetFrameLevel(max(0, f:GetFrameLevel() - 1))
	threat:Hide()
	f.Threat = threat

	if key == "raid" or key == "raid40" or key == "party" or key == "player" then
		local dispel = CreateFrame("Frame", nil, f, S.BackdropTemplate)
		S:SetOutside(dispel, f, 1, 1)
		dispel:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 2 })
		dispel:SetBackdropColor(0, 0, 0, 0)
		dispel:SetFrameLevel(f:GetFrameLevel() + 7)
		dispel:Hide()
		f.Dispel = dispel
	end

	local hl = textHolder:CreateTexture(nil, "OVERLAY")
	hl:SetAllPoints(f.Health)
	hl:SetTexture(BLANK)
	hl:SetVertexColor(1, 1, 1, 0.08)
	hl:Hide()
	f.Highlight = hl

	f.Buffs = self:CreateAuras(f, "buffs")
	f.Debuffs = self:CreateAuras(f, "debuffs")
	-- buff indicators: small tracked-aura squares along the top edge (aura watch)
	f.Indicators = CreateFrame("Frame", nil, f)
	f.Indicators:SetFrameLevel(f:GetFrameLevel() + 6)
	f.Indicators:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
	f.Indicators:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.Indicators:SetHeight(1)
	-- aura bars: timer-bar strip anchored outside the frame
	f.AuraBars = CreateFrame("Frame", nil, f)
	f.AuraBars:SetFrameLevel(f:GetFrameLevel() + 3)
	f.AuraBars:Hide()
	if f.db.castbar then self:CreateCastbar(f) end

	self.frames[#self.frames + 1] = f
	return f
end

local function PlaceText(fs, parent, db)
	fs:ClearAllPoints()
	local pos = db.position or "CENTER"
	fs:SetPoint(pos, parent, pos, db.xOffset or 0, db.yOffset or 0)
	fs:SetJustifyH(pos:find("LEFT") and "LEFT" or pos:find("RIGHT") and "RIGHT" or "CENTER")
end

function UF:ConfigureFrame(f)
	local db = f.db
	local colors = self.db.colors
	local width, height = db.width, db.height
	if not f.isGroup then
		if InCombatLockdown() then return S:RunOutOfCombat(self.ConfigureFrame, self, f) end
		f:SetSize(width, height)
	end
	local powerH = (db.power.enable and db.power.height) or 0
	local portraitW = 0
	local health, power = f.Health, f.Power
	local m = S.mult

	local portraitRight = db.portrait.side == "RIGHT"
	if db.portrait.enable then
		-- 2D (static class/character picture) by default; 3D models animate
		local want3D = db.portrait.style == "3D"
		if f.Portrait and (f.Portrait.is3D or false) ~= want3D then
			f.Portrait:Hide()
			f.Portrait = nil
		end
		if not f.Portrait then
			local p
			if want3D then
				p = CreateFrame("PlayerModel", nil, f)
				p.is3D = true
				S:CreateBackdrop(p, "Default")
			else
				p = CreateFrame("Frame", nil, f)
				S:CreateBackdrop(p, "Default")
				p.tex = p:CreateTexture(nil, "ARTWORK")
				p.tex:SetAllPoints()
				p.tex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
			end
			f.Portrait = p
		end
		portraitW = (db.portrait.width and db.portrait.width > 0) and db.portrait.width or height
		f.Portrait:ClearAllPoints()
		f.Portrait:SetPoint(portraitRight and "TOPRIGHT" or "TOPLEFT", f, portraitRight and "TOPRIGHT" or "TOPLEFT", portraitRight and -m or m, -m)
		f.Portrait:SetSize(portraitW - m, height - 2 * m)
		f.Portrait:Show()
		portraitW = portraitW + 1
	elseif f.Portrait then
		f.Portrait:Hide()
	end
	local padL = portraitRight and 0 or portraitW
	local padR = portraitRight and portraitW or 0

	-- per-unit frame style: SENTINEL = edge strip + floating power rail,
	-- EDGE = edge strip only, CLASSIC = plain stacked bars
	local style = db.style or "SENTINEL"
	local rail = style == "SENTINEL" and not f.isGroup and powerH > 0 and not db.power.detached
	f.isRail = rail
	health:ClearAllPoints()
	health:SetPoint("TOPLEFT", f, "TOPLEFT", m + padL, -m)
	if rail then
		health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -m - padR, m)
	else
		health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -m - padR, m + (powerH > 0 and powerH + m or 0))
	end
	f.Edge:SetShown(style ~= "CLASSIC")
	health:SetStatusBarTexture(S:Fetch("statusbar", self.db.statusbar, "Sentinel"))
	health.bg:SetTexture(S:Fetch("statusbar", self.db.statusbar, "Sentinel"))

	if powerH > 0 then
		power:ClearAllPoints()
		if rail then
			local inset = max(8, floor(width * 0.06))
			power:SetPoint("TOPLEFT", f, "BOTTOMLEFT", m + padL + inset, floor(powerH / 2))
			power:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -(inset + padR), floor(powerH / 2))
			power:SetFrameLevel(f:GetFrameLevel() + 4)
			if not power.suiRailBD then power.suiRailBD = S:CreateBackdrop(power, "Default") end
			power.suiRailBD:Show()
		else
			power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", m + padL, m)
			power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -m - padR, m)
			power:SetFrameLevel(f:GetFrameLevel() + 1)
			if power.suiRailBD then power.suiRailBD:Hide() end
		end
		power:SetHeight(powerH)
		power:SetStatusBarTexture(S:Fetch("statusbar", self.db.statusbar, "Sentinel"))
		power.bg:SetTexture(S:Fetch("statusbar", self.db.statusbar, "Sentinel"))
		power:Show()
		f.powerSep:SetShown(not rail)
	else
		power:Hide()
		f.powerSep:Hide()
	end

	local font = S:Fetch("font", self.db.font)
	local size = db.fontSize or 12
	S:SetFont(f.HealthText, font, size, self.db.fontOutline)
	S:SetFont(f.PowerText, font, size - 1, self.db.fontOutline)
	S:SetFont(f.NameText, font, size, self.db.fontOutline)
	if f.DruidMana and f.DruidMana.text then S:SetFont(f.DruidMana.text, font, max(8, size - 3), self.db.fontOutline) end
	PlaceText(f.HealthText, health, db.health)
	PlaceText(f.PowerText, powerH > 0 and power or health, db.power)
	PlaceText(f.NameText, health, db.name)
	f.HealthText:SetShown(db.health.text ~= "")
	f.PowerText:SetShown(db.power.text ~= "" and powerH > 0)
	f.NameText:SetShown(db.name.enable)
	f.NameText:SetWidth(max(10, width * (db.name.position == "CENTER" and 0.95 or 0.6)))

	-- custom tag texts: one FontString per entry, positioned on health/power or the frame
	local activeCT = {}
	for name, ct in pairs(db.customTexts or {}) do
		local fs = f.customTextPool[name]
		if not fs then
			fs = S:FontString(textHolder, 12, self.db.fontOutline, S.media.unitFont)
			f.customTextPool[name] = fs
		end
		S:SetFont(fs, font, ct.fontSize or size, self.db.fontOutline)
		fs:ClearAllPoints()
		local anchor = (ct.attachTo == "POWER" and powerH > 0) and power
			or (ct.attachTo == "FRAME") and f or health
		local pos = ct.position or "CENTER"
		fs:SetPoint(pos, anchor, pos, ct.xOffset or 0, ct.yOffset or 0)
		fs:SetJustifyH(pos:find("RIGHT") and "RIGHT" or pos:find("LEFT") and "LEFT" or "CENTER")
		fs:SetShown(ct.text ~= nil and ct.text ~= "")
		activeCT[name] = true
	end
	for name, fs in pairs(f.customTextPool) do
		if not activeCT[name] then fs:Hide() end
	end

	local hc, ac = colors.healPrediction, colors.absorb
	f.HealPrediction.heal:SetVertexColor(hc.r, hc.g, hc.b, hc.a)
	f.HealPrediction.absorb:SetVertexColor(ac.r, ac.g, ac.b, ac.a)
	f.HealPrediction.heal:SetAlpha(db.healPrediction and 1 or 0)
	f.HealPrediction.absorb:SetAlpha((db.healPrediction and db.absorbs ~= false) and 1 or 0)

	local ci = f.ClassIcon
	if db.classIcon then
		ci:ClearAllPoints()
		ci:SetSize(height, height)
		if db.classIconSide == "RIGHT" then ci:SetPoint("LEFT", f, "RIGHT", 3, 0) else ci:SetPoint("RIGHT", f, "LEFT", -3, 0) end
	else
		ci:Hide()
	end
	f.RoleIcon:SetSize(db.roleIconSize or 16, db.roleIconSize or 16)

	f.RaidIcon:ClearAllPoints()
	f.RaidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
	f.RaidIcon:SetSize(db.raidIcon.size, db.raidIcon.size)
	f.RaidIcon:SetAlpha(db.raidIcon.enable and 1 or 0)

	if f.Castbar then self:LayoutCastbar(f) end
	self:LayoutAuras(f, f.Buffs, db.buffs)
	self:LayoutAuras(f, f.Debuffs, db.debuffs)
	f.Buffs:SetShown(db.buffs.enable)
	f.Debuffs:SetShown(db.debuffs.enable)

	if f.AuraBars then
		local ab = db.aurabars
		f.AuraBars:ClearAllPoints()
		f.AuraBars:SetSize(ab.width or width, (ab.barHeight + ab.spacing) * ab.maxBars)
		local anchor = ab.anchor or "TOP"
		if anchor:find("BOTTOM") then
			f.AuraBars:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
		elseif anchor:find("LEFT") then
			f.AuraBars:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
		elseif anchor:find("RIGHT") then
			f.AuraBars:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
		else
			f.AuraBars:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
		end
	end

	if f.unit then self:UpdateFrame(f) end
end

-- every element updates on its own: one failing element (e.g. a secret value on
-- newer clients) must not leave name/health/auras of the frame stale
local elementUpdates = { "UpdateHealth", "UpdatePower", "UpdateName", "UpdateRaidIcon", "UpdateIndicators", "UpdateThreat", "UpdatePortrait", "UpdateAllAuras", "UpdateRange" }
function UF:UpdateFrame(f)
	local unit = f.unit
	if not unit or not UnitExists(unit) then return end
	for _, method in ipairs(elementUpdates) do
		S:SafeCall("UnitFrames:" .. (f.key or "?") .. ":" .. method, self[method], self, f)
	end
	if f.ClassPower then S:SafeCall("UnitFrames:ClassPower", self.UpdateClassPower, self, f) end
	if f.DruidMana then S:SafeCall("UnitFrames:DruidMana", self.UpdateDruidMana, self, f) end
	if f.Castbar and f.db.castbar.enable then
		if UnitCastingInfo(unit) then self:CastStart(f, false)
		elseif UnitChannelInfo(unit) then self:CastStart(f, true)
		else f.Castbar.casting, f.Castbar.channeling = nil, nil f.Castbar:Hide() end
	end
end

-- Event routing -------------------------------------------------------------
local unitEvents = {
	UNIT_HEALTH = "Health", UNIT_HEALTH_FREQUENT = "Health", UNIT_MAXHEALTH = "Health", UNIT_CONNECTION = "Full",
	UNIT_POWER_UPDATE = "Power", UNIT_POWER_FREQUENT = "Power", UNIT_MAXPOWER = "Power", UNIT_DISPLAYPOWER = "Power",
	UNIT_NAME_UPDATE = "Name", UNIT_LEVEL = "Name", UNIT_FACTION = "Health", UNIT_CLASSIFICATION_CHANGED = "Name",
	UNIT_AURA = "Auras", UNIT_THREAT_SITUATION_UPDATE = "Threat", UNIT_HEAL_PREDICTION = "Heal", UNIT_ABSORB_AMOUNT_CHANGED = "Heal",
	UNIT_PORTRAIT_UPDATE = "Portrait", UNIT_MODEL_CHANGED = "Portrait", UNIT_FLAGS = "Name",
	UNIT_SPELLCAST_START = "Cast", UNIT_SPELLCAST_CHANNEL_START = "Channel", UNIT_SPELLCAST_STOP = "Stop",
	UNIT_SPELLCAST_CHANNEL_STOP = "Stop", UNIT_SPELLCAST_FAILED = "Stop", UNIT_SPELLCAST_INTERRUPTED = "Stop",
	UNIT_SPELLCAST_SUCCEEDED = "Stop", UNIT_SPELLCAST_DELAYED = "Delay", UNIT_SPELLCAST_CHANNEL_UPDATE = "ChannelDelay",
	UNIT_SPELLCAST_INTERRUPTIBLE = "Interruptible", UNIT_SPELLCAST_NOT_INTERRUPTIBLE = "Interruptible",
	UNIT_SPELLCAST_EMPOWER_START = "Channel", UNIT_SPELLCAST_EMPOWER_STOP = "Stop",
}

local function HandleUnitEvent(f, event, unit, ...)
	local kind = unitEvents[event]
	if kind == "Health" then UF:UpdateHealth(f)
	elseif kind == "Power" then UF:UpdatePower(f) if f.ClassPower then UF:UpdateClassPower(f) end if f.DruidMana then UF:UpdateDruidMana(f) end
	elseif kind == "Name" then UF:UpdateName(f) UF:UpdateIndicators(f)
	elseif kind == "Auras" then UF:UpdateAllAuras(f) UF:UpdatePrioDebuff(f)
	elseif kind == "Threat" then UF:UpdateThreat(f)
	elseif kind == "Heal" then UF:UpdateHealPrediction(f)
	elseif kind == "Portrait" then UF:UpdatePortrait(f)
	elseif kind == "Full" then UF:UpdateFrame(f)
	elseif f.Castbar and f.db.castbar.enable then
		if f.unit == "player" then UF:UpdatePower(f) end
		if kind == "Cast" then UF:CastStart(f, false)
		elseif kind == "Channel" then UF:CastStart(f, true)
		elseif kind == "Stop" then UF:CastStop(f, event)
		elseif kind == "Delay" then UF:CastUpdate(f, false)
		elseif kind == "ChannelDelay" then UF:CastUpdate(f, true)
		elseif kind == "Interruptible" then
			local c = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" and UF.db.colors.castNoInterrupt or UF.db.colors.castbar
			f.Castbar:SetStatusBarColor(c.r, c.g, c.b)
			f.Castbar.Shield:SetShown(event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
		end
	end
end

function UF:RegisterFrameEvents(f)
	if not f.eventFrame then
		f.eventFrame = CreateFrame("Frame", nil, f)
		f.eventFrame:SetScript("OnEvent", function(_, event, ...)
			S:SafeCall("UnitFrames:" .. (f.key or "?") .. ":" .. event, HandleUnitEvent, f, event, ...)
		end)
	end
	local ef = f.eventFrame
	ef:UnregisterAllEvents()
	local unit = f.unit
	if not unit then return end
	local realUnit = unit
	local pairedUnit = unit == "player" and UnitHasVehicleUI and "vehicle" or nil
	for event in pairs(unitEvents) do
		if pairedUnit then
			pcall(ef.RegisterUnitEvent, ef, event, realUnit, pairedUnit)
		else
			pcall(ef.RegisterUnitEvent, ef, event, realUnit)
		end
	end
end

function UF:SetFrameUnit(f, unit)
	if f.unit == unit and f.eventFrame then return end
	f.unit = unit
	if f.Castbar then f.Castbar.unit = unit end
	self:RegisterFrameEvents(f)
	if unit then self:UpdateFrame(f) end
end

-- Units without events (targettarget etc.) are polled.
local polled = {}
local pollElapsed = 0
local pollFrame = CreateFrame("Frame")
pollFrame:SetScript("OnUpdate", function(_, elapsed)
	pollElapsed = pollElapsed + elapsed
	if pollElapsed < 0.25 then return end
	pollElapsed = 0
	for f in pairs(polled) do
		if f:IsVisible() and f.unit and UnitExists(f.unit) then S:SafeCall("UnitFrames:Poll", UF.UpdateFrame, UF, f) end
	end
	for _, f in ipairs(UF.frames) do
		if f.isGroup and f:IsVisible() and f.unit and f.db.rangeFade then UF:UpdateRange(f) end
	end
end)

function UF:AddPolling(f) polled[f] = true end

-- Hide Blizzard -------------------------------------------------------------
local function HideFrame(f)
	if not f then return end
	f:UnregisterAllEvents()
	f:Hide()
	f:SetParent(S.hiddenFrame)
	local health = f.healthbar or f.healthBar or (f.HealthBarsContainer and f.HealthBarsContainer.healthBar)
	if health and health.UnregisterAllEvents then health:UnregisterAllEvents() end
	local power = f.manabar or f.manaBar
	if power and power.UnregisterAllEvents then power:UnregisterAllEvents() end
	local spell = f.castBar or f.spellbar
	if spell and spell.UnregisterAllEvents then spell:UnregisterAllEvents() end
end
UF.HideBlizzardFrame = HideFrame

function UF:DisableBlizzard()
	local p = self.private
	if p.disableBlizzardPlayer then
		HideFrame(PlayerFrame)
		if PlayerCastingBarFrame then PlayerCastingBarFrame:UnregisterAllEvents() PlayerCastingBarFrame:SetParent(S.hiddenFrame) end
		if CastingBarFrame then CastingBarFrame:UnregisterAllEvents() CastingBarFrame:SetParent(S.hiddenFrame) end
		if PetCastingBarFrame then PetCastingBarFrame:UnregisterAllEvents() PetCastingBarFrame:SetParent(S.hiddenFrame) end
		if RuneFrame then RuneFrame:UnregisterAllEvents() RuneFrame:SetParent(S.hiddenFrame) end
		HideFrame(PetFrame)
		if ComboFrame then ComboFrame:UnregisterAllEvents() ComboFrame:SetParent(S.hiddenFrame) end
	end
	if p.disableBlizzardTarget then
		HideFrame(TargetFrame)
		HideFrame(TargetFrameToT)
		if ComboPointPlayerFrame then ComboPointPlayerFrame:UnregisterAllEvents() ComboPointPlayerFrame:SetParent(S.hiddenFrame) end
	end
	if p.disableBlizzardFocus then
		HideFrame(FocusFrame)
		HideFrame(FocusFrameToT)
	end
	if p.disableBlizzardParty then
		if PartyFrame then
			HideFrame(PartyFrame)
			if PartyFrame.PartyMemberFramePool then
				for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do HideFrame(frame) end
			end
		end
		for i = 1, 4 do
			HideFrame(_G["PartyMemberFrame" .. i])
		end
		if CompactPartyFrame then HideFrame(CompactPartyFrame) end
		if PartyMemberBackground then PartyMemberBackground:SetParent(S.hiddenFrame) end
	end
	if p.disableBlizzardRaid and self.db.units.raid.enable then
		if CompactRaidFrameManager_SetSetting then
			pcall(CompactRaidFrameManager_SetSetting, "IsShown", "0")
		end
		if CompactRaidFrameManager then
			CompactRaidFrameManager:UnregisterAllEvents()
			CompactRaidFrameManager:SetParent(S.hiddenFrame)
		end
		if CompactRaidFrameContainer then
			CompactRaidFrameContainer:UnregisterAllEvents()
			CompactRaidFrameContainer:SetParent(S.hiddenFrame)
		end
	end
	if p.disableBlizzardBoss then
		for i = 1, 8 do HideFrame(_G["Boss" .. i .. "TargetFrame"]) end
		if BossTargetFrameContainer then BossTargetFrameContainer:SetParent(S.hiddenFrame) end
	end
	if p.disableBlizzardArena and not S.isClassic then
		if ArenaEnemyFramesContainer then ArenaEnemyFramesContainer:SetParent(S.hiddenFrame) end
		self.hideArena = true
	end
end

-- click-cast bindings (Clique-style): secure attributes on unit frames,
-- applied out of combat. mod-prefixed attrs ("shift-type2") take precedence
-- over the default *type attrs only for that modifier combination.
local CC_VALUE_ATTR = { spell = "spell", macro = "macrotext", item = "item" }
function UF:ApplyClickCastTo(f)
	if not f.ccKeys then f.ccKeys = {} end
	if InCombatLockdown() then return S:RunOutOfCombat(self.ApplyClickCastTo, self, f) end
	for _, k in ipairs(f.ccKeys) do f:SetAttribute(k, nil) end
	wipe(f.ccKeys)
	local cc = self.db.clickCast
	if not cc or not cc.enable or not cc.bindings then return end
	for _, b in ipairs(cc.bindings) do
		local btn = tonumber(b.button) or 1
		local mod = (b.mod and b.mod ~= "none" and b.mod ~= "") and (b.mod:lower() .. "-") or ""
		local tattr = mod .. "type" .. btn
		f:SetAttribute(tattr, b.type or "spell")
		f.ccKeys[#f.ccKeys + 1] = tattr
		local vname = CC_VALUE_ATTR[b.type or ""]
		if vname and b.value and b.value ~= "" then
			local vattr = mod .. vname .. btn
			f:SetAttribute(vattr, b.value)
			f.ccKeys[#f.ccKeys + 1] = vattr
		end
	end
end

function UF:ApplyClickCast()
	for _, f in ipairs(self.frames) do self:ApplyClickCastTo(f) end
end

function UF:Update()
	for _, f in ipairs(self.frames) do
		f.db = self.db.units[f.key]
		self:ConfigureFrame(f)
		-- ConfigureFrame only rebuilds the layout; repaint colors/text/auras too so
		-- option changes (health mode, class colors, ...) show without a reload
		self:UpdateFrame(f)
	end
	if self.UpdateHeaders then self:UpdateHeaders() end
	self:ApplyClickCast()
end

function UF:Initialize()
	self:DisableBlizzard()
	self:CreateUnits()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
		if UF.units.target then UF:UpdateFrame(UF.units.target) end
		if UF.units.targettarget then UF:UpdateFrame(UF.units.targettarget) end
		if UF.units.player and UF.units.player.ClassPower then UF:UpdateClassPower(UF.units.player) end
	end)
	if not S.isClassic then
		self:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
			if UF.units.focus then UF:UpdateFrame(UF.units.focus) end
			if UF.units.focustarget then UF:UpdateFrame(UF.units.focustarget) end
		end)
	end
	self:RegisterUnitEvent("UNIT_PET", function() if UF.units.pet then UF:UpdateFrame(UF.units.pet) end end, "player")
	-- target of target / focus target / pet target: refresh instantly when the
	-- parent unit switches its target (polling only catches health changes)
	self:RegisterEvent("UNIT_TARGET", function(_, _, unit)
		local child = unit == "target" and UF.units.targettarget or unit == "focus" and UF.units.focustarget or unit == "pet" and UF.units.pettarget
		if child then UF:UpdateFrame(child) end
	end)
	self:RegisterEvent("RAID_TARGET_UPDATE", function() for _, f in ipairs(UF.frames) do UF:UpdateRaidIcon(f) end end)
	local function RefreshSecureHeaders()
		-- force the secure headers to reassign units to their children; members
		-- who joined while the header was hidden or mid-combat otherwise keep a
		-- stale roster until the next visibility change
		for _, header in pairs(UF.headers) do
			if header.InitChild and SecureGroupHeader_Update then
				if InCombatLockdown() then
					S:RunOutOfCombat(SecureGroupHeader_Update, header)
				else
					SecureGroupHeader_Update(header)
				end
			end
		end
	end
	UF.RefreshSecureHeaders = RefreshSecureHeaders
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		for _, f in ipairs(UF.frames) do if f.unit then UF:UpdateIndicators(f) end end
		RefreshSecureHeaders()
	end)
	self:RegisterEvent("UNIT_PET", function(_, _, unit)
		if unit == "player" then RefreshSecureHeaders() end
	end)
	self:RegisterEvent("PARTY_LEADER_CHANGED", function() for _, f in ipairs(UF.frames) do if f.unit then UF:UpdateIndicators(f) end end end)
	pcall(self.RegisterEvent, self, "PLAYER_ROLES_ASSIGNED", function() for _, f in ipairs(UF.frames) do if f.unit then UF:UpdateIndicators(f) end end end)
	self:RegisterEvent("PLAYER_UPDATE_RESTING", function() if UF.units.player then UF:UpdateIndicators(UF.units.player) end end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() if UF.units.player then UF:UpdateIndicators(UF.units.player) end end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if UF.units.player then UF:UpdateIndicators(UF.units.player) end end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() for _, f in ipairs(UF.frames) do if f.unit then UF:UpdateFrame(f) end end end)
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
		local f = UF.units.player
		if f then
			if f.ClassPower then UF:UpdateClassPower(f) end
			if f.DruidMana then UF:UpdateDruidMana(f) end
		end
	end)
	if S.myClass == "DEATHKNIGHT" then
		self:RegisterEvent("RUNE_POWER_UPDATE", function() if UF.units.player then UF:UpdateClassPower(UF.units.player) end end)
	end
	if not (S.isRetail or S.isMists or S.isCata) then
		self:RegisterEvent("UNIT_POWER_UPDATE", function(_, _, unit) if unit == "player" and UF.units.player then UF:UpdateClassPower(UF.units.player) end end)
		pcall(function() self:RegisterEvent("PLAYER_COMBO_POINTS", function() if UF.units.player then UF:UpdateClassPower(UF.units.player) end end) end)
	end
	self:RegisterEvent("READY_CHECK", "ReadyCheck")
	self:RegisterEvent("READY_CHECK_CONFIRM", "ReadyCheck")
	self:RegisterEvent("READY_CHECK_FINISHED", "ReadyCheckFinished")
end

function UF:ReadyCheck()
	for _, f in ipairs(self.frames) do
		if f.ReadyCheck and f.unit and UnitExists(f.unit) then
			local status = GetReadyCheckStatus(f.unit)
			if status == "ready" then f.ReadyCheck:SetTexture(READY_CHECK_READY_TEXTURE)
			elseif status == "notready" then f.ReadyCheck:SetTexture(READY_CHECK_NOT_READY_TEXTURE)
			elseif status == "waiting" then f.ReadyCheck:SetTexture(READY_CHECK_WAITING_TEXTURE) end
			f.ReadyCheck:SetShown(status ~= nil)
		end
	end
end

function UF:ReadyCheckFinished()
	C_Timer.After(6, function()
		for _, f in ipairs(UF.frames) do if f.ReadyCheck then f.ReadyCheck:Hide() end end
	end)
end
