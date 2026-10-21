-- Sentinel Scrolling Combat Text: own SCT with three movable scroll areas
--   Incoming      (left of the character)  damage taken, heals received, avoids
--   Outgoing      (right of the character) your + pet damage and heals, with spell icons
--   Notifications (above the character)    entering/leaving combat, killing blows, low health
-- Numbers travel on a slight arc, crits "pop" in larger. Blizzard's own floating
-- numbers can be switched off so only Sentinel text is shown.
local _, ns = ...
local S = ns.S
local L = S.L
local CT = S:NewModule("CombatText")

local _G = _G
local ipairs, type, select, tremove, wipe = ipairs, type, select, tremove, wipe
local floor, max, min, random, sin = math.floor, math.max, math.min, math.random, math.sin
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitGUID = UnitGUID
local IsSecret = S.IsSecret

local SCHOOL_COLORS = {
	[1] = { 1, 1, 0.85 }, [2] = { 1, 0.9, 0.5 }, [4] = { 1, 0.5, 0 }, [8] = { 0.3, 1, 0.3 },
	[16] = { 0.5, 1, 1 }, [32] = { 0.6, 0.5, 1 }, [64] = { 1, 0.35, 1 },
}
local function SchoolColor(school)
	local c = SCHOOL_COLORS[school]
	if c then return c[1], c[2], c[3] end
	if type(school) == "number" then
		for _, b in ipairs({ 64, 32, 16, 8, 4, 2 }) do
			if school % (b * 2) >= b then local cc = SCHOOL_COLORS[b] return cc[1], cc[2], cc[3] end
		end
	end
	return 1, 1, 1
end

local MISS_TEXT = { MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", EVADE = "Evade", IMMUNE = "Immune", DEFLECT = "Deflect", REFLECT = "Reflect", ABSORB = "Absorb", RESIST = "Resist" }
local DAMAGE_EVENTS = { SWING_DAMAGE = true, SPELL_DAMAGE = true, RANGE_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true }
local HEAL_EVENTS = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
local MISS_EVENTS = { SWING_MISSED = true, SPELL_MISSED = true, RANGE_MISSED = true, SPELL_PERIODIC_MISSED = true }

-- every CVar that makes Blizzard draw floating numbers (world text over targets,
-- pet damage, periodic ticks, and the self text from Blizzard_CombatText)
local BLIZZ_CVARS = {
	"floatingCombatTextCombatDamage", "floatingCombatTextCombatHealing", "floatingCombatTextCombatLogPeriodicSpells",
	"floatingCombatTextPetMeleeDamage", "floatingCombatTextPetSpellDamage", "floatingCombatTextCombatDamageAllAutos",
	"floatingCombatTextCombatHealingAbsorbTarget", "floatingCombatTextCombatHealingAbsorbSelf", "enableFloatingCombatText",
}

CT.areas = {}
CT.active = {}

-- Scroll areas ----------------------------------------------------------------
-- dir: vertical direction, arc: horizontal drift over the path (sign = side)
local AREA_DEFS = {
	incoming = { title = "Combat Text: Incoming", point = { "CENTER", "UIParent", "CENTER", -260, 40 }, dir = -1, arc = -40, justify = "RIGHT" },
	outgoing = { title = "Combat Text: Outgoing", point = { "CENTER", "UIParent", "CENTER", 260, 40 }, dir = 1, arc = 40, justify = "LEFT" },
	notify = { title = "Combat Text: Notifications", point = { "CENTER", "UIParent", "CENTER", 0, 210 }, dir = 1, arc = 0, justify = "CENTER" },
}

function CT:CreateAreas()
	for key, def in pairs(AREA_DEFS) do
		local f = CreateFrame("Frame", "SentinelUISCT_" .. key, UIParent)
		f:SetSize(160, 40)
		f:SetFrameStrata("HIGH")
		f.def, f.key, f.pool = def, key, {}
		S:CreateMover(f, "sct" .. key, L[def.title], def.point, "general")
		self.areas[key] = f
	end
end

local function Acquire(area)
	for _, fs in ipairs(area.pool) do
		if not fs.suiActive then return fs end
	end
	local fs = area:CreateFontString(nil, "OVERLAY")
	fs:SetDrawLayer("OVERLAY", 7)
	area.pool[#area.pool + 1] = fs
	return fs
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
	local active = CT.active
	for i = #active, 1, -1 do
		local t = active[i]
		t.elapsed = t.elapsed + elapsed
		local p = t.elapsed / t.dur
		if p >= 1 then
			t.fs:SetAlpha(0)
			t.fs.suiActive = false
			tremove(active, i)
		else
			local def = t.area.def
			-- crit pop: start 160% and settle to 100% in the first 15%
			if t.crit then
				local s = p < 0.15 and (1.6 - 0.6 * (p / 0.15)) or 1
				t.fs:SetTextHeight(max(1, t.size * s))
			end
			local y = t.y0 + def.dir * t.distance * p
			local x = t.x0 + def.arc * sin(p * 1.5708)
			t.fs:ClearAllPoints()
			t.fs:SetPoint("CENTER", t.area, "CENTER", x, y)
			t.fs:SetAlpha(p < 0.75 and 1 or (1 - p) / 0.25)
		end
	end
	if #active == 0 then driver:Hide() end
end)

function CT:Spawn(areaKey, text, r, g, b, crit)
	local area = self.areas[areaKey]
	if not area or not text then return end
	local db = self.db
	local fs = Acquire(area)
	local size = crit and db.critSize or db.fontSize
	S:SetFont(fs, db.font and S:Fetch("font", db.font) or S.media.numberFont, size, "OUTLINE")
	fs:SetText(text)
	fs:SetTextColor(r, g, b)
	fs.suiActive = true
	-- stagger: new lines start slightly offset so bursts don't overlap
	local count = 0
	for _, t in ipairs(self.active) do if t.area == area and t.elapsed < 0.25 then count = count + 1 end end
	local entry = {
		fs = fs, area = area, size = size, crit = crit, elapsed = 0,
		x0 = (areaKey == "notify") and 0 or (random(0, 24) - 12),
		y0 = -area.def.dir * count * (size + 2),
		distance = areaKey == "notify" and db.distance * 0.35 or db.distance,
		dur = crit and db.duration * 1.25 or db.duration,
	}
	fs:ClearAllPoints()
	fs:SetPoint("CENTER", area, "CENTER", entry.x0, entry.y0)
	fs:SetAlpha(1)
	self.active[#self.active + 1] = entry
	driver:Show()
end

local function Icon(spellId)
	if not CT.db.showIcons or not spellId or IsSecret(spellId) then return "" end
	local icon
	if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(spellId)
	elseif GetSpellTexture then icon = GetSpellTexture(spellId) end
	return icon and ("|T" .. icon .. ":0:0:0:0:64:64:5:59:5:59|t ") or ""
end

-- CLEU ----------------------------------------------------------------------
function CT:OnCLEU()
	local db = self.db
	local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, a12, _, a14, a15, _, _, a18, _, _, a21 = CombatLogGetCurrentEventInfo()
	if IsSecret(sourceGUID) or IsSecret(destGUID) then return end
	local me, pet = self.playerGUID, UnitGUID("pet")
	local fromMe = sourceGUID == me or (pet and sourceGUID == pet)
	local toMe = destGUID == me

	if subevent == "PARTY_KILL" and fromMe and db.notifications then
		self:Spawn("notify", L["Killing Blow"] .. "!", 1, 0.82, 0.2, true)
		return
	end

	if DAMAGE_EVENTS[subevent] then
		if not db.showDamage then return end
		local amount, crit, spellId, school
		if subevent == "SWING_DAMAGE" then amount, crit = a12, a18
		else spellId, school, amount, crit = a12, a14, a15, a21 end
		if not amount or IsSecret(amount) or amount < (db.minAmount or 0) then return end
		crit = crit and db.showCrits
		if toMe and db.incoming then
			self:Spawn("incoming", "-" .. S:Abbrev(amount), 1, 0.25, 0.25, crit)
		elseif fromMe and db.outgoing then
			local r, g, b = SchoolColor(school or 1)
			self:Spawn("outgoing", Icon(spellId) .. S:Abbrev(amount) .. (crit and "!" or ""), r, g, b, crit)
		end
	elseif HEAL_EVENTS[subevent] then
		if not db.showHealing then return end
		local spellId, amount, overheal, crit = a12, a15, select(16, CombatLogGetCurrentEventInfo()), a18
		if not amount or IsSecret(amount) then return end
		local effective = amount - ((not IsSecret(overheal) and overheal) or 0)
		if effective <= 0 or effective < (db.minAmount or 0) then return end
		crit = crit and db.showCrits
		if toMe and db.incoming then
			self:Spawn("incoming", "+" .. S:Abbrev(effective), 0.3, 1, 0.4, crit)
		elseif fromMe and db.outgoing then
			self:Spawn("outgoing", Icon(spellId) .. "+" .. S:Abbrev(effective), 0.3, 1, 0.4, crit)
		end
	elseif MISS_EVENTS[subevent] then
		if not db.showMisses then return end
		local missType = subevent == "SWING_MISSED" and a12 or a15
		local label = MISS_TEXT[missType]
		if not label then return end
		if toMe and db.incoming then
			self:Spawn("incoming", L[label], 0.6, 0.65, 0.75)
		elseif fromMe and db.outgoing then
			self:Spawn("outgoing", L[label], 0.6, 0.65, 0.75)
		end
	end
end

-- Notifications -------------------------------------------------------------
function CT:OnCombat(event)
	if not self.db.notifications then return end
	if event == "PLAYER_REGEN_DISABLED" then
		self:Spawn("notify", "+ " .. L["Combat"], 1, 0.3, 0.3)
	else
		self:Spawn("notify", "- " .. L["Combat"], 0.4, 1, 0.5)
	end
end

function CT:OnHealth(_, unit)
	if unit ~= "player" or not self.db.notifications then return end
	local hp, mx = UnitHealth("player"), UnitHealthMax("player")
	if IsSecret(hp) or IsSecret(mx) or not mx or mx == 0 then return end
	local low = hp / mx < 0.3 and not UnitIsDeadOrGhost("player")
	if low and not self.lowWarned then
		self.lowWarned = true
		self:Spawn("notify", L["Low Health!"], 1, 0.15, 0.15, true)
	elseif not low and hp / mx > 0.45 then
		self.lowWarned = nil
	end
end

-- Blizzard floating text ------------------------------------------------------
-- some classic builds render the numbers through the Blizzard_CombatText
-- FrameXML addon instead of honouring the CVars, so we also neuter that frame.
local function NeuterBlizzardText()
	local loadResult, loadReason
	if IsAddOnLoaded and not IsAddOnLoaded("Blizzard_CombatText") then
		-- a previous session may have left it disabled in the addon list;
		-- re-enable first or LoadAddOn always fails
		if EnableAddOn then pcall(EnableAddOn, "Blizzard_CombatText") end
		local loader = LoadAddOn or UIParentLoadAddOn
		if loader then loadResult, loadReason = loader("Blizzard_CombatText") end
	end
	if not CT.blizzOrig and (_G.CombatText_UpdateDisplayedMessages or _G.CombatText) then
		CT.blizzOrig = {
			update = _G.CombatText_UpdateDisplayedMessages,
			register = _G.CombatText_RegisterForDisplayedEvents,
			onEvent = _G.CombatText and _G.CombatText:GetScript("OnEvent"),
		}
	end
	local f = _G.CombatText
	if f and f.UnregisterAllEvents then
		f:UnregisterAllEvents()
		f:SetScript("OnEvent", nil)
		f:Hide()
	end
	-- its cvar sync re-registers all events on every CVAR_UPDATE: block both
	if _G.CombatText_UpdateDisplayedMessages then _G.CombatText_UpdateDisplayedMessages = function() end end
	if _G.CombatText_RegisterForDisplayedEvents then _G.CombatText_RegisterForDisplayedEvents = function() end end
	-- keep it from loading again next session (re-enabled in RestoreBlizzardText)
	pcall(DisableAddOn or function() end, "Blizzard_CombatText")
	-- diagnostic: record what was actually found on this client
	if S.LogInfo then
		local found = {}
		for _, cv in ipairs(BLIZZ_CVARS) do if GetCVar(cv) ~= nil then found[#found + 1] = cv end end
		S:LogInfo("combattext", string.format("blizzard fct neutered: loaded=%s/%s frame=%s updateFn=%s cvars=%s",
			tostring(IsAddOnLoaded and IsAddOnLoaded("Blizzard_CombatText") or nil), tostring(loadReason or loadResult),
			tostring(f ~= nil), tostring(CT.blizzOrig and CT.blizzOrig.update ~= nil), #found > 0 and table.concat(found, ",") or "none"))
	end
end

local function RestoreBlizzardText()
	if not CT.blizzOrig then return end
	if CT.blizzOrig.update then _G.CombatText_UpdateDisplayedMessages = CT.blizzOrig.update end
	if CT.blizzOrig.register then _G.CombatText_RegisterForDisplayedEvents = CT.blizzOrig.register end
	local f = _G.CombatText
	if f and f.SetScript then
		f:SetScript("OnEvent", CT.blizzOrig.onEvent or _G.CombatText_OnEvent)
		if CT.blizzOrig.update then pcall(CT.blizzOrig.update) end
		f:Show()
	end
	pcall(EnableAddOn or function() end, "Blizzard_CombatText")
	CT.blizzOrig = nil
end

local function BlizzardCVars()
	local list, seen = {}, {}
	if C_Console and C_Console.GetAllCommands then
		local ok, cmds = pcall(C_Console.GetAllCommands)
		if ok and type(cmds) == "table" then
			for _, info in ipairs(cmds) do
				local name = type(info) == "table" and (info.command or info.name) or info
				if type(name) == "string" then
					local low = name:lower()
					if (low:find("floating") or low:find("combattext") or low:find("worldtext")) and not seen[name] then
						seen[name] = true
						list[#list + 1] = name
					end
				end
			end
		end
	end
	for _, cv in ipairs(BLIZZ_CVARS) do
		if not seen[cv] then seen[cv] = true list[#list + 1] = cv end
	end
	return list
end

-- force a cvar to "0" without going through our own SetCVar hook logic
local cvarReapply -- forward decl: set below to re-run ApplyBlizzard deferred
local function ForceZero(cv)
	local cur = GetCVar(cv)
	if cur ~= nil and cur ~= "0" then pcall(SetCVar, cv, "0") end
	-- write even when GetCVar reports nil: on some builds the CVars only get
	-- registered once the Blizzard addon/settings panel ran, and they still
	-- drive the engine world text
	if cur == nil then pcall(SetCVar, cv, "0") end
end

-- Blizzard re-syncs combat-text CVars after login (account cvar pull) and the
-- Interface options panel re-writes them when opened -> keep re-applying 0.
local cvarHookInstalled
local function InstallCVarWatch()
	if cvarHookInstalled then return end
	cvarHookInstalled = true
	-- any Lua-side re-enable goes through SetCVar / C_CVar.SetCVar -> clamp it
	local function Watch(name, value)
		if type(name) == "string" and (name == "enableFloatingCombatText" or name:find("floatingCombatText") or name:find("FloatingCombatText")) and value and value ~= "0" then
			C_Timer.After(0, function() S:SafeCall("CombatText:Blizzard", CT.ApplyBlizzard, CT) end)
		end
	end
	if SetCVar then hooksecurefunc("SetCVar", Watch) end
	if C_CVar and C_CVar.SetCVar then hooksecurefunc(C_CVar, "SetCVar", Watch) end
	-- the Interface > Combat options panel syncs its checkboxes on open:
	-- re-run after it had a chance to flip the cvar back on
	for _, pn in ipairs({ "InterfaceOptionsCombatPanel", "InterfaceOptionsCombatTextPanel" }) do
		local panel = _G[pn]
		if panel and panel.HookScript then
			panel:HookScript("OnShow", function()
				C_Timer.After(0.1, function() S:SafeCall("CombatText:Blizzard", CT.ApplyBlizzard, CT) end)
			end)
		end
	end
end

function CT:ApplyBlizzard()
	local hide = self.db.enable and self.db.hideBlizzard
	S.private.sctSavedCVars = S.private.sctSavedCVars or {}
	local saved = S.private.sctSavedCVars
	for _, cv in ipairs(BlizzardCVars()) do
		local cur = GetCVar(cv)
		if hide then
			if cur ~= nil and saved[cv] == nil and cur ~= "0" then saved[cv] = cur end
			ForceZero(cv)
		elseif saved[cv] ~= nil then
			pcall(SetCVar, cv, saved[cv])
			saved[cv] = nil
		end
	end
	if hide then
		InstallCVarWatch()
		NeuterBlizzardText()
		-- log the resulting state so the persistent log proves the cvar stuck
		if S.LogInfo and not CT._cvarLogged then
			CT._cvarLogged = true
			S:LogInfo("combattext", "enableFloatingCombatText -> " .. tostring(GetCVar("enableFloatingCombatText")))
		end
	else
		RestoreBlizzardText()
	end
	-- Sentinel font for whatever Blizzard still shows
	local font = S.media.numberFont or S.media.font
	if font then
		_G.DAMAGE_TEXT_FONT = font
		if _G.CombatTextFont and _G.CombatTextFont.SetFont then S:SetFont(_G.CombatTextFont, font, 120, "OUTLINE") end
	end
end

function CT:Update()
	self.db = S.db.profile.general.combatText
	if self.db.enable then
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCLEU")
	else
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		for _, t in ipairs(self.active) do t.fs:SetAlpha(0) t.fs.suiActive = false end
		wipe(self.active)
		driver:Hide()
	end
	self:ApplyBlizzard()
end

function CT:Initialize()
	self.db = S.db.profile.general.combatText
	self.playerGUID = UnitGUID("player")
	self:CreateAreas()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombat")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombat")
	self:RegisterEvent("UNIT_HEALTH", "OnHealth")
	-- the client may sync account CVars after login and turn Blizzard's numbers back on
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		-- account cvar sync can land seconds after login; re-apply twice
		for _, delay in ipairs({ 2, 8 }) do
			C_Timer.After(delay, function() S:SafeCall("CombatText:Blizzard", CT.ApplyBlizzard, CT) end)
		end
	end)
	self:RegisterEvent("ADDON_LOADED", function(_, _, name)
		if name == "Blizzard_CombatText" then CT:ApplyBlizzard() end
	end)
	self:RegisterEvent("CVAR_UPDATE", function(_, _, name)
		if CT.db.enable and CT.db.hideBlizzard and type(name) == "string" and (name:find("floatingCombatText") or name == "enableFloatingCombatText" or name:find("FLOATING")) then
			C_Timer.After(0, function() S:SafeCall("CombatText:Blizzard", CT.ApplyBlizzard, CT) end)
		end
	end)
	self:Update()
end

-- /sui sct test: spawns sample numbers in every area
function CT:Test()
	for i = 1, 4 do
		C_Timer.After(i * 0.25, function()
			CT:Spawn("outgoing", Icon(133) .. S:Abbrev(random(800, 4000)), 1, 0.5, 0, i == 3)
			CT:Spawn("incoming", "-" .. S:Abbrev(random(200, 1500)), 1, 0.25, 0.25, i == 2)
		end)
	end
	self:Spawn("notify", "+ " .. L["Combat"], 1, 0.3, 0.3)
end
