-- InterruptTracker: shows enemy interrupt cooldowns as an icon row near the
-- target. Watches SPELL_CAST_SUCCESS by hostile players for classic kicks.
local _, ns = ...
local S = ns.S
local L = S.L
local IT = S:NewModule("InterruptTracker", "interrupttracker")

local CreateFrame = CreateFrame
local MAX_ICONS = 6

-- spellId -> cooldown seconds (TBC-era interrupts + wrath additions)
local KICKS = {
	[1766] = 10, [1767] = 10, [1768] = 10, [1769] = 10,   -- Kick
	[6552] = 10, [6554] = 10,                             -- Pummel
	[2139] = 24,                                          -- Counterspell
	[8042] = 6, [10412] = 6, [10413] = 6, [10414] = 6,     -- Earth Shock
	[19647] = 24, [119910] = 24,                          -- Spell Lock
	[34490] = 24,                                         -- Silencing Shot
	[15487] = 45,                                         -- Silence
	[47528] = 15,                                         -- Mind Freeze (DK)
	[57994] = 12,                                         -- Wind Shear
	[96231] = 15,                                         -- Rebuke
	[72] = 12,                                            -- Shield Bash (vanilla warrior)
	[29704] = 12,                                         -- Shield Bash rank 4
	[19244] = 24, [19245] = 24,                           -- Spell Lock (felhunter low ranks)
}
local ICON = "Interface\\Icons\\Ability_Kick"

function IT:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIInterruptTracker", UIParent)
	f:SetSize(MAX_ICONS * 24, 24)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -240)
	f.icons = {}
	for i = 1, MAX_ICONS do
		local ic = CreateFrame("Frame", nil, f)
		ic:SetSize(20, 20)
		ic.slot = i
		ic:SetPoint("LEFT", (i - 1) * 24, 0)
		ic.tex = ic:CreateTexture(nil, "ARTWORK")
		ic.tex:SetAllPoints()
		ic.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
		ic.cd:SetAllPoints()
		ic:Hide()
		f.icons[i] = ic
	end
	f:Hide()
	S:CreateMover(f, "InterruptTracker", L["Interrupt Tracker"], { "CENTER", UIParent, "CENTER", 0, -240 }, "interrupttracker")
	self.frame = f
end

local function PlateFor(guid)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit and UnitGUID) then return end
	for i = 1, 40 do
		local u = "nameplate" .. i
		if UnitExists(u) and UnitGUID(u) == guid then
			return C_NamePlate.GetNamePlateForUnit(u)
		end
	end
end

-- reparent an icon onto the caster's nameplate (above the plate) or back
-- into the movable row when no plate is visible
local function AnchorIcon(ic, f, guid, db)
	if db.anchorPlates then
		local plate = PlateFor(guid)
		if plate then
			ic:SetParent(plate)
			ic:ClearAllPoints()
			ic:SetPoint("BOTTOMLEFT", plate, "TOPLEFT", 0, 4)
			return
		end
	end
	ic:SetParent(f)
	ic:ClearAllPoints()
	ic:SetPoint("LEFT", (ic.slot - 1) * 24, 0)
end

function IT:OnCLEU()
	local _, sub, _, sg, _, sflags, _, dg, _, dflags, _, sid, _, _, _, _, _, _, _, _, extra = CombatLogGetCurrentEventInfo()
	if sub ~= "SPELL_CAST_SUCCESS" or not sid then return end
	local cd = KICKS[sid]
	if not cd or not self.db.enable then return end
	-- hostile players only (bit 0x40 = hostile, player-type flag 0x40000)
	if not sflags or (bit.band(sflags, COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40) == 0) then return end
	if bit.band(sflags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x400) == 0 then return end
	self:BuildFrame()
	local f = self.frame
	for _, ic in ipairs(f.icons) do
		if ic.sid == sid then
			ic.cd:SetCooldown(GetTime(), cd)
			AnchorIcon(ic, f, sg, self.db)
			return
		end
	end
	for _, ic in ipairs(f.icons) do
		if not ic:IsShown() then
			ic.sid = sid
			ic.tex:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or ICON)
			ic.cd:SetCooldown(GetTime(), cd)
			AnchorIcon(ic, f, sg, self.db)
			ic:Show()
			f:Show()
			C_Timer.After(cd, function()
				ic:Hide()
				ic:SetParent(f)
				ic:ClearAllPoints()
				ic:SetPoint("LEFT", (ic.slot - 1) * 24, 0)
				if not self:AnyShown() then f:Hide() end
			end)
			return
		end
	end
end

function IT:AnyShown()
	for _, ic in ipairs(self.frame.icons) do if ic:IsShown() then return true end end
end

function IT:Initialize()
	self.db = S.db.profile.interrupttracker
	if not CombatLogGetCurrentEventInfo then return end
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function() IT:OnCLEU() end)
end

function IT:Update()
	self.db = S.db.profile.interrupttracker
	if self.frame and self.db.enable == false then self.frame:Hide() end
end
