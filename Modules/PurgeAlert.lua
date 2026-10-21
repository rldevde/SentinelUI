-- PurgeAlert: shows dispellable (magic) buffs on the enemy target as
-- highlighted icons above the target frame, for classes with a purge/
-- steal/dispel/devour/tranquilizing tool.
local _, ns = ...
local S = ns.S
local L = S.L
local PA = S:NewModule("PurgeAlert", "purgealert")

local CreateFrame = CreateFrame
local UnitAura = S.UnitAura
local UnitExists, UnitCanAttack = UnitExists, UnitCanAttack
local ICON, MAX_ICONS, GAP = 24, 6, 3

-- classes with an enemy-magic removal tool on classic/tbc/wrath
local CLASSES = {
	MAGE = true,    -- spellsteal
	PRIEST = true,  -- dispel magic / mass dispel
	SHAMAN = true,  -- purge
	WARLOCK = true, -- felhunter: devour magic
	HUNTER = true,  -- tranquilizing shot (frenzy; magic shown as best-effort)
}
local CAN_PURGE = CLASSES[S.myClass]

local holder, icons = nil, {}

local function Ensure()
	if holder then return end
	holder = CreateFrame("Frame", "SentinelUIPurgeAlert", UIParent)
	holder:SetSize(1, ICON)
	S:CreateMover(holder, "purgealert", L["Purge Alert"], { "TOP", UIParent, "TOP", 0, -230 }, "purgealert")
	for i = 1, MAX_ICONS do
		local b = CreateFrame("Frame", nil, holder)
		b:SetSize(ICON, ICON)
		b:SetPoint("CENTER", holder, "CENTER", -((MAX_ICONS * (ICON + GAP) - GAP) / 2) + (i - 1) * (ICON + GAP), 0)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.border = b:CreateTexture(nil, "OVERLAY")
		b.border:SetPoint("CENTER")
		b.border:SetSize(ICON * 1.4, ICON * 1.4)
		b.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
		b.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
		b.border:SetVertexColor(1, 1, 0)
		b:EnableMouse(true)
		b:SetScript("OnEnter", function(s2)
			GameTooltip:SetOwner(s2, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(s2.spellName or "", 1, 1, 1)
			GameTooltip:AddLine(L["Magic buff - purgeable"], 1, 1, 0)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:Hide()
		icons[i] = b
	end
end

function PA:Refresh()
	if not CAN_PURGE or self.db.enable == false then return end
	Ensure()
	if not (UnitExists("target") and UnitCanAttack("player", "target")) then
		for _, b in ipairs(icons) do b:Hide() end
		return
	end
	local n = 0
	for i = 1, 40 do
		local name, icon, _, dtype = UnitAura("target", i, "HELPFUL")
		if not name then break end
		if dtype == "Magic" and n < MAX_ICONS then
			n = n + 1
			icons[n].tex:SetTexture(icon)
			icons[n].spellName = name
			icons[n]:Show()
		end
	end
	for i = n + 1, MAX_ICONS do icons[i]:Hide() end
end

function PA:Initialize()
	self.db = S.db.profile.purgealert
	if not CAN_PURGE then return end
	Ensure()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() PA:Refresh() end)
	self:RegisterEvent("UNIT_AURA", function(_, unit) if unit == "target" then PA:Refresh() end end)
end

function PA:Update()
	self.db = S.db.profile.purgealert
	if holder then holder:SetShown(self.db.enable ~= false) end
end
