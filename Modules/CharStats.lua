-- CharStats: extended character stats panel docked to the right side of the
-- character frame. Melee / ranged / spell / defense numbers the stock paper
-- doll does not show on this client.
local _, ns = ...
local S = ns.S
local L = S.L
local CS = S:NewModule("CharStats", "charstats")

local CreateFrame = CreateFrame
local format, max = format, math.max

local function RB(cr)
	if not (cr and GetCombatRatingBonus) then return 0 end
	local ok, v = pcall(GetCombatRatingBonus, cr)
	return (ok and tonumber(v)) or 0
end

local function Pct(v) return format("%.1f%%", v or 0) end

local function Rows()
	local rows = {}
	local function cat(t) rows[#rows + 1] = { cat = t } end
	local function it(name, val) rows[#rows + 1] = { name = name, val = val } end

	cat(L["Melee"])
	it(L["Attack Power"], BreakUpLargeNumbers(UnitAttackPower and select(1, UnitAttackPower("player")) or 0))
	it(L["Crit Chance"], Pct(GetCritChance and GetCritChance() or 0))
	local mh = (GetHitModifier and GetHitModifier() or 0) + RB(CR_HIT_MELEE)
	it(L["Hit Rating"], format("%d (+%s)", mh, Pct(RB(CR_HIT_MELEE))))
	local haste = GetHaste and GetHaste()
	if haste and haste > 0 then it(L["Haste"], Pct(haste)) end
	local exp = CR_EXPERTISE and RB(CR_EXPERTISE) or 0
	if exp > 0 then it(L["Expertise"], tostring(exp)) end
	local arp = CR_ARMOR_PENETRATION and RB(CR_ARMOR_PENETRATION) or 0
	if arp > 0 then it(L["Armor Pen"], tostring(arp)) end

	cat(L["Ranged"])
	it(L["Attack Power"], BreakUpLargeNumbers(UnitRangedAttackPower and select(1, UnitRangedAttackPower("player")) or 0))
	it(L["Crit Chance"], Pct(GetRangedCritChance and GetRangedCritChance() or 0))

	cat(L["Spell"])
	local sp = 0
	for i = 1, 7 do
		local v = GetSpellBonusDamage and GetSpellBonusDamage(i) or 0
		if v > sp then sp = v end
	end
	it(L["Spell Power"], tostring(sp))
	it(L["Crit Chance"], Pct(GetSpellCritChance and (max(1, GetSpellCritChance(2) or 0, GetSpellCritChance(3) or 0, GetSpellCritChance(4) or 0, GetSpellCritChance(5) or 0, GetSpellCritChance(6) or 0, GetSpellCritChance(7) or 0)) or 0))
	local sh = (GetSpellHitModifier and GetSpellHitModifier() or 0) + RB(CR_HIT_SPELL)
	it(L["Hit Rating"], tostring(sh))
	if GetManaRegen then
		local _, combat = GetManaRegen()
		if combat and combat > 0 then it(L["MP5 (combat)"], format("%.0f", combat * 5)) end
	end

	cat(L["Defense"])
	it(ARMOR, BreakUpLargeNumbers(UnitArmor and select(1, UnitArmor("player")) or 0))
	it(L["Defense Rating"], tostring(CR_DEFENSE_SKILL and RB(CR_DEFENSE_SKILL) or 0))
	it(DODGE, Pct(GetDodgeChance and GetDodgeChance() or 0))
	it(PARRY, Pct(GetParryChance and GetParryChance() or 0))
	it(BLOCK, Pct(GetBlockChance and GetBlockChance() or 0))
	local res = GetCombatRating and CR_RESILIENCE_CRIT_TAKEN and RB(CR_RESILIENCE_CRIT_TAKEN) or 0
	if res > 0 then it(L["Resilience"], tostring(res)) end
	return rows
end

function CS:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUICharStats", CharacterFrame or UIParent)
	f:SetSize(190, 340)
	if CharacterFrame then
		f:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -30, -30)
	else
		f:SetPoint("CENTER")
	end
	f:SetFrameStrata("HIGH")
	S:SetTemplate(f, "Transparent")
	local title = S:FontString(f, 11, "OUTLINE", S.media.unitFont)
	title:SetPoint("TOP", 0, -6)
	title:SetText(L["Stats"])
	S:RegisterAccent(title, "text")
	f.lines = {}
	for i = 1, 40 do
		local t = S:FontString(f, 10, "OUTLINE", S.media.unitFont)
		t:SetPoint("TOPLEFT", 8, -22 - (i - 1) * 14)
		f.lines[i] = t
	end
	f:Hide()
	self.frame = f
	-- toggle button on the character frame
	if CharacterFrame then
		local btn = CreateFrame("Button", "SentinelUICharStatsBtn", CharacterFrame)
		btn:SetSize(60, 18)
		btn:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -34, -2)
		S:SetTemplate(btn, "Default")
		local t = S:FontString(btn, 10, "OUTLINE")
		t:SetAllPoints()
		t:SetText(L["Stats"])
		btn:SetScript("OnClick", function() CS:Toggle() end)
	end
end

function CS:Toggle()
	self:Build()
	if self.frame:IsShown() then self.frame:Hide() else self:Render() self.frame:Show() end
end

function CS:Render()
	if not self.frame then return end
	local rows = Rows()
	for i, ln in ipairs(self.frame.lines) do
		local r = rows[i]
		if not r then
			ln:SetText("")
		elseif r.cat then
			ln:SetText("|cff" .. S.accentHex .. r.cat .. "|r")
		else
			ln:SetFormattedText("%s: |cffffffff%s|r", r.name, r.val)
		end
	end
end

function CS:Initialize()
	self.db = S.db.profile.charstats
	if CharacterFrame then
		self:Build()
		CharacterFrame:HookScript("OnHide", function() if CS.frame then CS.frame:Hide() end end)
	end
end
