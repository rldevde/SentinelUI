-- Nameplates: own health bar, name, level, castbar, debuffs and threat colouring on top of Blizzard plates.
local _, ns = ...
local S = ns.S
local L = S.L
local NP = S:NewModule("Nameplates")
local UF = S:GetModule("UnitFrames")

local pairs, max, min = pairs, math.max, math.min
local UnitExists, UnitIsUnit, UnitIsPlayer, UnitReaction = UnitExists, UnitIsUnit, UnitIsPlayer, UnitReaction
local UnitCanAttack = UnitCanAttack
local IsSecret = S.IsSecret
local BLANK = [[Interface\Buttons\WHITE8X8]]

NP.plates = {}

-- selectable plate layouts: enemies and friendlies can use different styles.
-- STYLE_SIZE scales the bar per style so e.g. PLATE gets the chunky look.
local STYLE_SIZE = { SLIM = { 0.85, 0.65 }, PLATE = { 1.05, 1.55 }, BAR = { 1.0, 1.25 } }
local function StyleFor(unit, db)
	local friendly = unit and not UnitCanAttack("player", unit)
	return friendly and (db.friendlyStyle or "INLINE") or (db.enemyStyle or "STANDARD")
end

local function IsTank()
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
	if role == "TANK" then return true end
	if GetSpecialization and GetSpecializationRole then
		local spec = GetSpecialization()
		if spec and GetSpecializationRole(spec) == "TANK" then return true end
	end
	local class = S.myClass
	local form = GetShapeshiftFormID and GetShapeshiftFormID()
	if class == "WARRIOR" and GetShapeshiftForm() == 2 then return true end
	if class == "DRUID" and (form == 5 or form == 8) then return true end
	if class == "PALADIN" and not S.isRetail then
		for i = 1, 40 do
			local aura = S.GetAura("player", i, "HELPFUL")
			if not aura then break end
			if aura.spellId == 25780 then return true end
		end
	end
	return false
end

function NP:CreatePlate(plate)
	local db = self.db
	local f = CreateFrame("Frame", nil, plate)
	f:SetAllPoints()
	f:SetFrameLevel(plate:GetFrameLevel() + 1)
	f.isNameplate = true
	f.db = { castbar = { enable = true, latency = false, timeText = true, icon = true }, debuffs = { enable = true }, buffs = { enable = false }, health = {}, name = {} }

	local health = S:CreateStatusBar(f, nil, "Default")
	health:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.Health = health

	f.Name = S:FontString(health, db.fontSize, "OUTLINE", S.media.font)
	f.Name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 3)
	f.Name:SetJustifyH("LEFT")
	f.Level = S:FontString(health, db.fontSize, "OUTLINE", S.media.numberFont)
	f.Level:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 3)
	f.Name:SetPoint("RIGHT", f.Level, "LEFT", -2, 0)
	f.HealthText = S:FontString(health, db.fontSize - 1, "OUTLINE", S.media.numberFont)
	f.HealthText:SetPoint("CENTER", health, "CENTER", 0, 0)

	-- who the mob is on: small class-colored name under the left bar edge
	f.TargetOf = S:FontString(health, db.fontSize - 1, "OUTLINE", S.media.font)
	f.TargetOf:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
	f.TargetOf:SetJustifyH("LEFT")

	-- quest kill progress ("3/8") under the right bar edge
	f.Quest = S:FontString(health, db.fontSize - 1, "OUTLINE", S.media.numberFont)
	f.Quest:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -2)
	f.Quest:SetJustifyH("RIGHT")
	f.Quest:SetTextColor(1, 0.72, 0.25)
	f.Quest:Hide()

	f.RaidIcon = health:CreateTexture(nil, "OVERLAY")
	f.RaidIcon:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
	f.RaidIcon:SetSize(20, 20)
	f.RaidIcon:SetPoint("RIGHT", health, "LEFT", -6, 0)
	f.RaidIcon:Hide()

	f.Elite = health:CreateTexture(nil, "OVERLAY")
	f.Elite:SetTexture([[Interface\Tooltips\EliteNameplateIcon]])
	f.Elite:SetSize(24, 12)
	f.Elite:SetPoint("LEFT", health, "RIGHT", 2, 0)
	f.Elite:Hide()

	local glow = CreateFrame("Frame", nil, health, S.BackdropTemplate)
	S:SetOutside(glow, health, 2, 2)
	glow:SetBackdrop({ edgeFile = BLANK, edgeSize = 2 })
	glow:SetFrameLevel(health:GetFrameLevel() + 3)
	glow:Hide()
	f.TargetGlow = glow

	UF:CreateCastbar(f)
	f.Castbar:SetParent(f)
	f.Castbar:ClearAllPoints()
	f.Castbar:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -4)
	f.Castbar.IconHolder:ClearAllPoints()
	f.Castbar.IconHolder:SetPoint("BOTTOMRIGHT", f.Castbar, "BOTTOMLEFT", -3, 0)

	-- who the mob is casting on, right edge inside the castbar ("-> Name")
	f.CastTarget = S:FontString(f.Castbar, db.fontSize - 1, "OUTLINE", S.media.numberFont)
	f.CastTarget:SetPoint("RIGHT", f.Castbar, "RIGHT", -2, 0)
	f.CastTarget:SetJustifyH("RIGHT")
	f.CastTarget:Hide()

	f.Debuffs = UF:CreateAuras(f, "debuffs")
	f.customTextPool = {}
	plate.suiPlate = f
	return f
end

function NP:LayoutPlate(f)
	local db = self.db
	local style = StyleFor(f.unit, db)
	local ms = STYLE_SIZE[style]
	f.Health:SetSize(db.width * (ms and ms[1] or 1), max(4, db.height * (ms and ms[2] or 1)))
	f.Health:SetStatusBarTexture(S:Fetch("statusbar", db.statusbar, "Sentinel"))
	f.Health.bg:SetTexture(S:Fetch("statusbar", db.statusbar, "Sentinel"))
	S:SetFont(f.Name, db.font and S:Fetch("font", db.font) or S.media.font, db.fontSize, "OUTLINE")
	S:SetFont(f.Level, S.media.numberFont, db.fontSize, "OUTLINE")
	S:SetFont(f.HealthText, S.media.numberFont, max(8, db.fontSize - 1), "OUTLINE")
	S:SetFont(f.TargetOf, S.media.font, max(8, db.fontSize - 1), "OUTLINE")
	S:SetFont(f.Quest, S.media.numberFont, max(8, db.fontSize - 1), "OUTLINE")
	f.Castbar:SetSize(db.width - (db.castIcon and (db.castbarHeight + db.height + 6) or 0), db.castbarHeight)
	f.Castbar.IconHolder:SetSize(db.castbarHeight + db.height + 4, db.castbarHeight + db.height + 4)
	f.Castbar.IconHolder:ClearAllPoints()
	f.Castbar.IconHolder:SetPoint("BOTTOMRIGHT", f.Castbar, "BOTTOMLEFT", -3, 0)
	f.Castbar.IconHolder:SetShown(db.castIcon)
	S:SetFont(f.Castbar.Text, db.font and S:Fetch("font", db.font) or S.media.font, max(8, db.fontSize - 1), "OUTLINE")
	S:SetFont(f.Castbar.Time, S.media.numberFont, max(8, db.fontSize - 1), "OUTLINE")
	S:SetFont(f.CastTarget, S.media.numberFont, max(8, db.fontSize - 1), "OUTLINE")
	f.Castbar.Spark:SetHeight(db.castbarHeight)
	f.auraDB = { size = db.debuffSize, perRow = db.maxDebuffs, maxRows = 1, spacing = 2, anchor = "TOPLEFT", growthY = "UP", onlyPlayer = db.onlyPlayerDebuffs, useBlacklist = true, customFilter = "NONE", noDuration = true }
	UF:LayoutAuras(f, f.Debuffs, f.auraDB)
	f.Debuffs:ClearAllPoints()
	f.Debuffs:SetPoint("BOTTOMLEFT", f.Health, "TOPLEFT", 0, db.fontSize + 6)
	-- free tag texts: same editor as unit frames, anchored to health or frame
	local activeCT = {}
	for name, ct in pairs(db.customTexts or {}) do
		local fs = f.customTextPool[name]
		if not fs then
			fs = S:FontString(f, max(8, db.fontSize), "OUTLINE", S.media.unitFont)
			f.customTextPool[name] = fs
		end
		S:SetFont(fs, db.font and S:Fetch("font", db.font) or S.media.font, ct.fontSize or max(8, db.fontSize), "OUTLINE")
		fs:ClearAllPoints()
		local anchor = ct.attachTo == "FRAME" and f or f.Health
		local pos = ct.position or "CENTER"
		fs:SetPoint(pos, anchor, pos, ct.xOffset or 0, ct.yOffset or 0)
		fs:SetJustifyH(pos:find("RIGHT") and "RIGHT" or pos:find("LEFT") and "LEFT" or "CENTER")
		fs:SetShown(ct.text ~= nil and ct.text ~= "")
		activeCT[name] = true
	end
	for name, fs in pairs(f.customTextPool) do
		if not activeCT[name] then fs:Hide() end
	end
	self:ApplyStyle(f, style)
end

-- re-anchor name/level/health text + castbar/debuff offsets per style variant
function NP:ApplyStyle(f, style)
	local db = self.db
	local name, level, ht = f.Name, f.Level, f.HealthText
	f.style = style
	name:ClearAllPoints()
	level:ClearAllPoints()
	ht:ClearAllPoints()
	if style == "INLINE" then
		-- compact single-line look: name inside the bar, values to the right
		name:SetPoint("LEFT", f.Health, "LEFT", 4, 0)
		name:SetJustifyH("LEFT")
		ht:SetPoint("RIGHT", f.Health, "RIGHT", -4, 0)
		level:SetPoint("RIGHT", ht, "LEFT", -3, 0)
		name:SetPoint("RIGHT", level, "LEFT", -4, 0)
	elseif style == "CENTER" then
		-- centered name inside the bar, level left, health right
		level:SetPoint("LEFT", f.Health, "LEFT", 4, 0)
		ht:SetPoint("RIGHT", f.Health, "RIGHT", -4, 0)
		name:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
		name:SetPoint("LEFT", level, "RIGHT", 4, 0)
		name:SetPoint("RIGHT", ht, "LEFT", -4, 0)
		name:SetJustifyH("CENTER")
	elseif style == "PLATE" then
		-- chunky bar-centric look: name left, health value then level right,
		-- everything inside the bigger bar
		name:SetPoint("LEFT", f.Health, "LEFT", 5, 0)
		name:SetJustifyH("LEFT")
		level:SetPoint("RIGHT", f.Health, "RIGHT", -5, 0)
		ht:SetPoint("RIGHT", level, "LEFT", -4, 0)
		name:SetPoint("RIGHT", ht, "LEFT", -5, 0)
	elseif style == "BAR" then
		-- pure bar look: no name/level text, only the health value inside
		ht:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
		level:SetPoint("RIGHT", f.Health, "RIGHT", -4, 0)
		name:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
	elseif style == "SLIM" then
		-- minimal thin bar with a small name floating above
		name:SetPoint("BOTTOMLEFT", f.Health, "TOPLEFT", 0, 1)
		name:SetJustifyH("LEFT")
		level:SetPoint("BOTTOMRIGHT", f.Health, "TOPRIGHT", 0, 1)
		name:SetPoint("RIGHT", level, "LEFT", -2, 0)
		ht:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
	elseif style == "UNDER" then
		-- name and level below the bar, health text stays inside
		name:SetPoint("TOPLEFT", f.Health, "BOTTOMLEFT", 0, -3)
		name:SetJustifyH("LEFT")
		level:SetPoint("TOPRIGHT", f.Health, "BOTTOMRIGHT", 0, -3)
		name:SetPoint("RIGHT", level, "LEFT", -2, 0)
		ht:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
	else -- STANDARD: name above the bar
		name:SetPoint("BOTTOMLEFT", f.Health, "TOPLEFT", 0, 3)
		name:SetJustifyH("LEFT")
		level:SetPoint("BOTTOMRIGHT", f.Health, "TOPRIGHT", 0, 3)
		name:SetPoint("RIGHT", level, "LEFT", -2, 0)
		ht:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
	end
	-- castbar sits below; UNDER needs extra room because the name is down there
	f.Castbar:ClearAllPoints()
	f.Castbar:SetPoint("TOPRIGHT", f.Health, "BOTTOMRIGHT", 0, style == "UNDER" and -(db.fontSize + 8) or -4)
	-- debuffs float above; styles with a floating name need the extra room
	f.Debuffs:ClearAllPoints()
	f.Debuffs:SetPoint("BOTTOMLEFT", f.Health, "TOPLEFT", 0, (style == "STANDARD" or style == "SLIM") and (db.fontSize + 6) or 4)
end

function NP:UpdateColor(f)
	local unit, db = f.unit, self.db
	local r, g, b
	if UnitIsPlayer(unit) then
		local enemy = UnitIsEnemy("player", unit)
		if (enemy and db.classColorEnemy) or (not enemy and db.classColorFriendly) then
			local c = S.ClassColor(select(2, UnitClass(unit)))
			r, g, b = c.r, c.g, c.b
		end
	end
	if not r and UnitIsTapDenied and UnitIsTapDenied(unit) then r, g, b = 0.55, 0.55, 0.55 end
	if not r and db.threat and UnitAffectingCombat(unit) and UnitCanAttack("player", unit) then
		local status = UnitThreatSituation and UnitThreatSituation("player", unit)
		if status and not IsSecret(status) then
			local tank = IsTank()
			local tc = db.threatColors
			local c
			if status == 3 then c = tank and tc.good or tc.bad
			elseif status == 2 or status == 1 then c = tc.transition
			else c = tank and tc.bad or tc.good end
			r, g, b = c.r, c.g, c.b
		end
	end
	if not r then
		local c = S.UnitColor(unit)
		r, g, b = c.r, c.g, c.b
	end
	f.Health:SetStatusBarColor(r, g, b)
	f.Health.bg:SetVertexColor(r * 0.2, g * 0.2, b * 0.2, 0.9)
end

-- shows the plate's current target name (who holds aggro), class-colored
function NP:UpdateTargetOf(f)
	local t = f.TargetOf
	if not t then return end
	if not self.db.targetName then t:Hide() return end
	local unit = f.unit
	if not unit or not UnitExists(unit .. "target") then t:Hide() return end
	local tn = UnitName(unit .. "target")
	if not tn or IsSecret(tn) or tn == "" then t:Hide() return end
	local r, g, b = 0.9, 0.9, 0.9
	if UnitIsPlayer(unit .. "target") then
		local cls = select(2, UnitClass(unit .. "target"))
		if cls and not IsSecret(cls) then
			local c = S.ClassColor(cls)
			r, g, b = c.r, c.g, c.b
		end
	end
	t:SetText(tn)
	t:SetTextColor(r, g, b)
	t:Show()
end

function NP:UpdateHealth(f)
	local unit = f.unit
	local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
	f.Health:SetMinMaxValues(0, IsSecret(mx) and mx or max(1, mx))
	f.Health:SetValue(cur)
	local mode = self.db.healthText
	if mode == "PERCENT" then
		f.HealthText:SetText(UF:FormatTags("[percent]", unit))
	elseif mode == "CURRENT" then
		f.HealthText:SetText(UF:FormatTags("[current]", unit))
	elseif mode == "BOTH" then
		f.HealthText:SetText(UF:FormatTags("[current] - [percent]", unit))
	else
		f.HealthText:SetText("")
	end
end

-- quest kill progress on mob plates: the quest log is scanned for kill
-- objectives and the plate shows "n/m" while the unit name appears inside
-- an unfinished objective's text. Works on every client flavor - modern
-- C_QuestLog first, the old log globals as fallback.
local questMobs = {}

local function NormName(s)
	return s and (s:lower():gsub("%s+", ""):gsub("[%p]", "")) or nil
end

local function AddObjective(text, num, req)
	if not (text and num and req) then return end
	if not num and text then num, req = text:match("(%d+)%s*/%s*(%d+)") end
	num, req = tonumber(num), tonumber(req)
	if not num or not req or num >= req then return end
	local name = NormName(text)
	if not name or #name < 4 then return end
	questMobs[#questMobs + 1] = { name = name, num = num, req = req }
end

local function ScanQuestLog()
	wipe(questMobs)
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives then
		for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader then
				for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
					if not o.finished and (o.type == "monster" or o.type == "object" or o.type == "item") then
						AddObjective(o.text, o.numFulfilled, o.numRequired)
					end
				end
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle and GetQuestLogLeaderBoard then
		for i = 1, (GetNumQuestLogEntries() or 0) do
			local title, _, _, isHeader = GetQuestLogTitle(i)
			if title and not isHeader then
				for j = 1, 40 do
					local text, _, finished = GetQuestLogLeaderBoard(j, i)
					if not text then break end
					if not finished then AddObjective(text) end
				end
			end
		end
	end
end

local function QuestProgressFor(unit)
	local un = NormName(UnitName(unit))
	if not un or #un < 3 then return nil end
	for _, o in ipairs(questMobs) do
		if o.name:find(un, 1, true) then return o end
	end
end

function NP:UpdateQuest(f)
	if not self.db.quest then f.Quest:Hide() return end
	local o = f.unit and QuestProgressFor(f.unit)
	if o then
		f.Quest:SetFormattedText("%d/%d", o.num, o.req)
		f.Quest:Show()
	else
		f.Quest:Hide()
	end
end

function NP:RefreshQuests()
	ScanQuestLog()
	for _, f in pairs(self.plates) do self:UpdateQuest(f) end
end

function NP:UpdateName(f)
	local unit = f.unit
	local barOnly = f.style == "BAR"
	f.Name:SetText((self.db.showName and not barOnly) and UnitName(unit) or "")
	f.Level:SetText((self.db.showLevel and not barOnly) and UF.tags.level(unit) or "")
	local c = UnitClassification(unit)
	f.Elite:SetShown(self.db.eliteIcon and (c == "elite" or c == "rareelite" or c == "worldboss") or false)
	if UnitIsPlayer(unit) then
		local cc = S.ClassColor(select(2, UnitClass(unit)))
		f.Name:SetTextColor(cc.r, cc.g, cc.b)
	else
		f.Name:SetTextColor(1, 1, 1)
	end
	self:UpdateQuest(f)
end

function NP:UpdateTarget(f)
	local isTarget = UnitIsUnit(f.unit, "target")
	local db = self.db
	if isTarget and db.targetGlow then
		f.TargetGlow:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b, 1)
		f.TargetGlow:Show()
	else
		f.TargetGlow:Hide()
	end
	if IsSecret(isTarget) then f:SetAlpha(1) return end
	local hasTarget = UnitExists("target")
	f:SetAlpha((not hasTarget or isTarget) and 1 or db.nonTargetAlpha)
	f.Health:SetScale(isTarget and db.targetScale or 1)
end

function NP:UpdateRaidIcon(f)
	local index = GetRaidTargetIndex(f.unit)
	if index and not IsSecret(index) then
		SetRaidTargetIconTexture(f.RaidIcon, index)
		f.RaidIcon:Show()
	else
		f.RaidIcon:Hide()
	end
end

function NP:UpdateAuras(f)
	if not self.db.debuffs then f.Debuffs:Hide() return end
	UF:UpdateAuras(f, f.Debuffs, f.auraDB)
end

function NP:UpdateCastTarget(f)
	local cast = f.Castbar.casting or f.Castbar.channeling
	if not self.db.castTarget or not cast or not f.unit then f.CastTarget:Hide() return end
	local name = UnitName(f.unit .. "target")
	if name and name ~= "" then
		local c = UnitIsPlayer(f.unit .. "target") and S.ClassColor(select(2, UnitClass(f.unit .. "target"))) or { r = 1, g = 1, b = 1 }
		f.CastTarget:SetFormattedText("-> |cff%02x%02x%02x%s|r", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255, name)
		f.CastTarget:Show()
	else
		f.CastTarget:Hide()
	end
end

function NP:UpdateCustomTexts(f)
	local pool = f.customTextPool
	if not pool or not f.unit then return end
	for name, fs in pairs(pool) do
		local ct = self.db.customTexts and self.db.customTexts[name]
		if ct and ct.text and ct.text ~= "" and fs:IsShown() then
			S:SafeCall("Nameplates:CustomText", function()
				UF:SetTagText(fs, ct.text, f.unit, ct)
				if ct.colorClass then
					local c = S.UnitColor(f.unit)
					fs:SetTextColor(c.r, c.g, c.b)
				elseif ct.color and ct.color.r then
					fs:SetTextColor(ct.color.r, ct.color.g, ct.color.b)
				else
					fs:SetTextColor(1, 1, 1)
				end
			end)
		end
	end
end

function NP:UpdateCast(f)
	if not self.db.castbar then f.Castbar:Hide() f.CastTarget:Hide() return end
	if UnitCastingInfo(f.unit) then UF:CastStart(f, false)
	elseif UnitChannelInfo(f.unit) then UF:CastStart(f, true)
	else f.Castbar.casting, f.Castbar.channeling = nil, nil f.Castbar:Hide() end
	self:UpdateCastTarget(f)
end

function NP:FullUpdate(f)
	self:UpdateHealth(f)
	self:UpdateColor(f)
	self:UpdateName(f)
	self:UpdateTarget(f)
	self:UpdateTargetOf(f)
	self:UpdateRaidIcon(f)
	self:UpdateAuras(f)
	self:UpdateCast(f)
	self:UpdateQuest(f)
	self:UpdateCustomTexts(f)
end

local function HideBlizzardPlate(plate)
	local uf = plate.UnitFrame
	if not uf then return end
	uf:SetAlpha(0)
	if not uf.suiHooked then
		uf.suiHooked = true
		hooksecurefunc(uf, "SetAlpha", function(self, a)
			if a ~= 0 and self:GetParent() and self:GetParent().suiActive then self:SetAlpha(0) end
		end)
	end
end

function NP:NAME_PLATE_UNIT_ADDED(_, unit)
	if self.disabled or UnitIsUnit(unit, "player") then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit, issecure and issecure() or false)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	local f = plate.suiPlate or self:CreatePlate(plate)
	f.unit = unit
	f.Castbar.unit = unit
	if not f.layoutVersion or f.layoutVersion ~= self.layoutVersion or f.style ~= StyleFor(unit, self.db) then
		self:LayoutPlate(f)
		f.layoutVersion = self.layoutVersion
	end
	plate.suiActive = true
	HideBlizzardPlate(plate)
	self.plates[unit] = f
	f:Show()
	self:FullUpdate(f)
end

function NP:NAME_PLATE_UNIT_REMOVED(_, unit)
	local f = self.plates[unit]
	if f then
		f:Hide()
		f.Castbar:Hide()
		f.Castbar.casting, f.Castbar.channeling = nil, nil
		f:GetParent().suiActive = nil
		local uf = f:GetParent().UnitFrame
		if uf then uf:SetAlpha(1) end
		self.plates[unit] = nil
		f.unit = nil
	end
end

local plateEvents = {
	UNIT_HEALTH = "UpdateHealth", UNIT_MAXHEALTH = "UpdateHealth", UNIT_HEALTH_FREQUENT = "UpdateHealth",
	UNIT_NAME_UPDATE = "UpdateName", UNIT_LEVEL = "UpdateName", UNIT_FACTION = "UpdateColor",
	UNIT_THREAT_LIST_UPDATE = "UpdateColor", UNIT_THREAT_SITUATION_UPDATE = "UpdateColor", UNIT_FLAGS = "UpdateColor",
	UNIT_TARGET = "UpdateTargetOf", -- also refreshes the cast-target text
	UNIT_AURA = "UpdateAuras",
}
local castEvents = {
	UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true,
	UNIT_SPELLCAST_INTERRUPTIBLE = true, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true, UNIT_SPELLCAST_SUCCEEDED = true,
}

function NP:OnUnitEvent(event, unit)
	local f = unit and self.plates[unit]
	if not f then return end
	local method = plateEvents[event]
	if method then
		self[method](self, f)
		if method == "UpdateHealth" then self:UpdateColor(f) self:UpdateCustomTexts(f)
		elseif method == "UpdateName" then self:UpdateCustomTexts(f)
		elseif method == "UpdateTargetOf" then self:UpdateCastTarget(f) end
	elseif castEvents[event] and self.db.castbar then
		if event == "UNIT_SPELLCAST_START" then UF:CastStart(f, false)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" then UF:CastStart(f, true)
		elseif event == "UNIT_SPELLCAST_DELAYED" then UF:CastUpdate(f, false)
		elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then UF:CastUpdate(f, true)
		elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
			local c = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" and UF.db.colors.castNoInterrupt or UF.db.colors.castbar
			f.Castbar:SetStatusBarColor(c.r, c.g, c.b)
		else UF:CastStop(f, event) end
		self:UpdateCastTarget(f)
	end
end

function NP:PLAYER_TARGET_CHANGED()
	for _, f in pairs(self.plates) do self:UpdateTarget(f) end
end

function NP:RAID_TARGET_UPDATE()
	for _, f in pairs(self.plates) do self:UpdateRaidIcon(f) end
end

function NP:Update()
	self.layoutVersion = (self.layoutVersion or 0) + 1
	for _, f in pairs(self.plates) do
		self:LayoutPlate(f)
		f.layoutVersion = self.layoutVersion
		self:FullUpdate(f)
	end
end

-- nameplate addon compatibility: if a dedicated plate addon is installed we ask
-- once which one should own the plates (stored in the per-character private db)
local NP_ADDONS = {
	"Plater", "Kui_Nameplates", "Kui_Nameplates_Core", "TidyPlates", "TidyPlates_ThreatPlates",
	"NeatPlates", "BetterBlizzPlates", "SimpleNameplates", "NamePlateKAI", "EkNameplates", "ElvUI",
}

-- stop drawing our plates immediately (module enable itself needs a reload)
function NP:SoftDisable()
	self.disabled = true
	for unit, f in pairs(self.plates) do
		f:Hide()
		local plate = f:GetParent()
		plate.suiActive = nil
		local uf = plate.UnitFrame
		if uf then uf:SetAlpha(1) end
		self.plates[unit] = nil
	end
end

function NP:CheckCompat()
	if not self.private or self.private.npCompatDone then return end
	local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if not IsLoaded then return end
	for _, name in ipairs(NP_ADDONS) do
		if IsLoaded(name) then
			StaticPopupDialogs["SENTINELUI_NPCOMPAT"] = {
				text = format(L["The nameplate addon |cffffd700%s|r is active. Which should draw the nameplates?"] or "The nameplate addon %s is active. Which should draw the nameplates?", name),
				button1 = "SentinelUI",
				button2 = name,
				button3 = L["Decide later"] or "Decide later",
				OnAccept = function() NP.private.npCompatDone = true end,
				OnCancel = function()
					NP.private.npCompatDone = true
					NP.private.enable = false
					NP:SoftDisable()
					S:StaticReload(format(L["SentinelUI nameplates disabled for %s. Reload now?"] or "SentinelUI nameplates disabled for %s. Reload now?", name))
				end,
				OnAlt = function() end, -- ask again next session
				timeout = 0, whileDead = true, hideOnEscape = false,
			}
			StaticPopup_Show("SENTINELUI_NPCOMPAT")
			return
		end
	end
	self.private.npCompatDone = true
end

function NP:Initialize()
	self.layoutVersion = 1
	self:CheckCompat()
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("RAID_TARGET_UPDATE")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() for _, f in pairs(NP.plates) do NP:UpdateColor(f) end end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() for _, f in pairs(NP.plates) do NP:UpdateColor(f) end end)
	self:RegisterEvent("QUEST_LOG_UPDATE", function() NP:RefreshQuests() end)
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED", function(_, unit)
		if unit == "player" then NP:RefreshQuests() end
	end)
	local ef = CreateFrame("Frame")
	for e in pairs(plateEvents) do pcall(ef.RegisterEvent, ef, e) end
	for e in pairs(castEvents) do pcall(ef.RegisterEvent, ef, e) end
	ef:SetScript("OnEvent", function(_, event, unit)
		if unit and unit:find("^nameplate") then S:SafeCall("Nameplates:" .. event, NP.OnUnitEvent, NP, event, unit) end
	end)
end
