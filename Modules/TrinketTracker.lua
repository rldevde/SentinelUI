-- TrinketTracker: watches combat log for enemy PvP trinket usage and shows a
-- 120 s cooldown icon next to the target (and arena) frames.
local _, ns = ...
local S = ns.S
local L = S.L
local TT = S:NewModule("TrinketTracker", "trinkettracker")

local CreateFrame = CreateFrame
local TRINKET_CD = 120
-- PvP trinket use spells across clients
local TRINKETS = { [42292]=1, [59752]=1, [7744]=1 } -- PvP trinket, Every Man (wrath), Will of Forsaken
local REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400

function TT:EnsureIcon(unit)
	local UF = S:GetModule("UnitFrames")
	local f = UF and UF.units and UF.units[unit]
	if not f then return end
	self.icons = self.icons or {}
	local b = self.icons[unit]
	if b and b:GetParent() == f then return b end
	b = CreateFrame("Frame", "SentinelUITrinket_" .. unit, f)
	b:SetSize(22, 22)
	b:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	S:CreateBackdrop(b, "Default")
	b:Hide()
	self.icons[unit] = b
	return b
end

function TT:Fire(unit, spellId)
	local b = self:EnsureIcon(unit)
	if not b then return end
	b.tex:SetTexture(select(3, S.GetSpellInfo(spellId)) or 134400)
	if b.cd.SetCooldown then b.cd:SetCooldown(GetTime(), TRINKET_CD)
	elseif b.cd.SetCooldownUNIX then b.cd:SetCooldownUNIX(GetTime(), TRINKET_CD) end
	b:Show()
	C_Timer.After(TRINKET_CD, function() if b then b:Hide() end end)
end

function TT:Initialize()
	self.db = S.db.profile.trinkettracker
	if not CombatLogGetCurrentEventInfo then return end
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		local _, sub, _, sguid, _, sflags, _, _, _, _, _, spellId = CombatLogGetCurrentEventInfo()
		if sub ~= "SPELL_CAST_SUCCESS" then return end
		if not spellId or not TRINKETS[spellId] then return end
		if not sflags or bit.band(sflags, TYPE_PLAYER) == 0 or bit.band(sflags, REACTION_HOSTILE) == 0 then return end
		-- attribute the trinket to whichever watched unit matches the caster
		for _, unit in ipairs({ "target", "focus", "arena1", "arena2", "arena3", "arena4", "arena5" }) do
			if UnitExists(unit) and UnitGUID(unit) == sguid then TT:Fire(unit, spellId) end
		end
	end)
end

function TT:Update()
	self.db = S.db.profile.trinkettracker
end
