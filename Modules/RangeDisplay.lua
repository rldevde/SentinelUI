-- RangeDisplay: estimated distance to the current target/focus shown on the
-- unit frame. Friendly units use CheckInteractDistance/UnitInRange bands;
-- hostile units fall back to a class baseline spell range.
local _, ns = ...
local S = ns.S
local L = S.L
local RD = S:NewModule("RangeDisplay", "rangedisplay")

local CreateFrame = CreateFrame
local CheckInteractDistance, UnitInRange = CheckInteractDistance, UnitInRange
local IsSpellInRange = IsSpellInRange

-- per-class baseline spells for hostile range checks (longest common reach)
local HOSTILE_SPELL = {
	MAGE = 133, PRIEST = 585, WARLOCK = 686, DRUID = 5176, SHAMAN = 403,
	PALADIN = 20271, HUNTER = 1978, WARRIOR = 100, ROGUE = 2764, DEATHKNIGHT = 49576,
}
local HOSTILE_RANGE = {
	MAGE = 35, PRIEST = 30, WARLOCK = 30, DRUID = 30, SHAMAN = 30,
	PALADIN = 10, HUNTER = 35, WARRIOR = 25, ROGUE = 30, DEATHKNIGHT = 30,
}

function RD:Estimate(unit)
	if not UnitExists(unit) then return end
	if UnitIsUnit(unit, "player") then return "0" end
	if not UnitCanAttack("player", unit) then
		-- friendly bands: duel 10y, inspect 28y, UnitInRange ~40y.
		-- CheckInteractDistance is a protected call in combat on some
		-- clients — fall back to the coarser UnitInRange band there
		if not InCombatLockdown() and CheckInteractDistance then
			if CheckInteractDistance(unit, 3) then return "0-10" end
			if CheckInteractDistance(unit, 1) then return "10-28" end
		end
		if UnitInRange and UnitInRange(unit) then return InCombatLockdown() and "<=40" or "28-40" end
		return "40+"
	end
	local spell, reach = HOSTILE_SPELL[S.myClass], HOSTILE_RANGE[S.myClass]
	-- IsSpellInRange wants the localized name on classic clients, the id works
	-- on modern ones — try the id first, then the resolved name
	if spell and IsSpellInRange then
		local inRange = IsSpellInRange(spell, unit)
		if inRange ~= 1 and S.GetSpellInfo then
			local name = S.GetSpellInfo(spell)
			if name then inRange = IsSpellInRange(name, unit) end
		end
		if inRange == 1 then return "<=" .. reach end
	end
	return (reach or 30) .. "+"
end

function RD:EnsureText(unit)
	local UF = S:GetModule("UnitFrames")
	local f = UF and UF.units and UF.units[unit]
	if not f then return end
	local parent = f.textHolder or f
	if self.texts and self.texts[unit] then
		if self.texts[unit]:GetParent() == parent then return self.texts[unit] end
		-- stale text on a replaced frame: clear it instead of stacking a second
		-- one on top (that overlap produced garbled glyphs)
		self.texts[unit]:Hide()
		self.texts[unit]:SetText("")
	end
	self.texts = self.texts or {}
	local t = S:FontString(parent, 10, "OUTLINE", S.media.numberFont)
	t:SetPoint("TOP", f, "BOTTOM", 0, -2)
	self.texts[unit] = t
	return t
end

function RD:UpdateUnit(unit)
	local t = self:EnsureText(unit)
	if not t then return end
	local d = self.db.enable ~= false and self:Estimate(unit)
	if d and self.db[unit .. "Show"] ~= false then
		t:Show()
		t:SetText(d .. " yd")
	else
		t:SetText("")
	end
end

local function Tick(_, el)
	RD.elapsed = (RD.elapsed or 0) + el
	if RD.elapsed < 0.25 then return end
	RD.elapsed = 0
	RD:UpdateUnit("target")
	RD:UpdateUnit("focus")
end

function RD:Initialize()
	self.db = S.db.profile.rangedisplay
	self.frame = self.frame or CreateFrame("Frame")
	self:Update()
end

function RD:Update()
	self.db = S.db.profile.rangedisplay
	if not self.frame then return end
	if self.db.enable ~= false then
		self.frame:SetScript("OnUpdate", Tick)
	else
		self.frame:SetScript("OnUpdate", nil)
		for unit, t in pairs(self.texts or {}) do t:SetText("") t:Hide() end
	end
end
