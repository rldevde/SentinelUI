-- ProcAlert: flashing icon when a proc/usable ability lights up.
-- Two mechanisms: aura procs (Omen of Clarity, Clearcasting, Nightfall…)
-- checked via UNIT_AURA spell ids, and usable procs (Overpower, Revenge,
-- Riposte, Kill Command…) polled via IsUsableSpell while in combat.
local _, ns = ...
local S = ns.S
local L = S.L
local PA = S:NewModule("ProcAlert", "procalert")

local CreateFrame = CreateFrame
local GetAuraByID = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID
local GetSpellInfo = GetSpellInfo
local IsUsableSpell = IsUsableSpell

-- aura procs: show while the buff is up
local AURAS = {
	MAGE = { 12536 },              -- Clearcasting (Arcane Concentration)
	DRUID = { 16870 },             -- Clearcasting (Omen of Clarity)
	WARLOCK = { 17941, 54277 },    -- Shadow Trance, Backdraft
	PRIEST = { 33151 },            -- Surge of Light
	SHAMAN = { 16246 },            -- Clearcasting (Elemental Focus)
	PALADIN = {}, WARRIOR = {}, ROGUE = {}, HUNTER = {},
	DEATHKNIGHT = { 51124, 59052, 53365 }, -- Killing Machine, Freezing Fog, Rune Strike(unholy)
}
-- usable procs: poll IsUsableSpell (they stay "unusable" until the proc fires)
local USABLE = {
	WARRIOR = { 7384, 6572 },      -- Overpower, Revenge
	ROGUE = { 14251 },             -- Riposte
	HUNTER = { 34026 },            -- Kill Command
	DRUID = { 6785 },              -- Ravage (prowl) — placeholder, harmless if absent
	MAGE = {}, PRIEST = {}, SHAMAN = {}, WARLOCK = {}, PALADIN = {}, DEATHKNIGHT = {},
}

function PA:BuildIcon()
	if self.icon then return end
	local b = CreateFrame("Frame", "SentinelUIProcAlert", UIParent)
	b:SetSize(48, 48)
	b:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	b:SetFrameStrata("HIGH")
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	S:CreateBackdrop(b, "Default")
	b:SetScript("OnUpdate", function(_, el)
		b.t = (b.t or 0) + el
		b:SetAlpha(0.6 + 0.4 * math.abs(math.sin(b.t * 6)))
	end)
	b:Hide()
	S:CreateMover(b, "ProcAlert", L["Proc Alert"], { "CENTER", UIParent, "CENTER", 0, 60 }, "procalert")
	self.icon = b
end

local function AuraTex(id)
	local _, _, tex
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		if info then tex = info.iconID end
	else
		tex = select(3, GetSpellInfo(id))
	end
	return tex
end

function PA:Check()
	if self.db.enable == false then return self.icon:Hide() end
	for _, id in ipairs(AURAS[S.myClass] or {}) do
		local hit
		if GetAuraByID then
			hit = GetAuraByID("player", id, "HELPFUL")
		else
			for i = 1, 40 do
				local sid = select(10, S.UnitAura("player", i, "HELPFUL"))
				if not sid then break end
				if sid == id then hit = true break end
			end
		end
		if hit then
			self.icon.tex:SetTexture(AuraTex(id) or 134400)
			self.icon:Show()
			return
		end
	end
	self.icon:Hide()
end

function PA:Poll()
	if self.db.enable == false or self.icon:IsShown() then return end
	for _, id in ipairs(USABLE[S.myClass] or {}) do
		if (S.IsSpellKnown and S.IsSpellKnown(id)) and IsUsableSpell then
			local name = GetSpellInfo(id)
			if name and IsUsableSpell(name) then
				self.icon.tex:SetTexture(AuraTex(id) or 134400)
				self.icon:Show()
				return
			end
		end
	end
end

function PA:Initialize()
	self.db = S.db.profile.procalert
	if not (AURAS[S.myClass] and (#AURAS[S.myClass] > 0 or #USABLE[S.myClass] > 0)) then return end
	self:BuildIcon()
	self:RegisterEvent("UNIT_AURA", function(_, _, unit) if unit == "player" then PA:Check() end end)
	if #USABLE[S.myClass] > 0 then
		self.timer = 0
		self.poller = self.poller or CreateFrame("Frame")
		self.poller:SetScript("OnUpdate", function(_, el)
			PA.timer = PA.timer + el
			if PA.timer < 0.3 then return end
			PA.timer = 0
			if UnitAffectingCombat("player") then PA:Poll() elseif PA.icon:IsShown() then PA:Check() end
		end)
	end
	self:Check()
end

function PA:Update()
	self.db = S.db.profile.procalert
	if self.icon then self:Check() end
end
