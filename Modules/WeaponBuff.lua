-- WeaponBuff: reminder icon when the main-hand weapon lacks its temporary
-- enchant — rogue poisons, shaman imbues, oils/sharpening stones for melee.
-- Flashes when the enchant is missing, dim-warns when it expires soon.
local _, ns = ...
local S = ns.S
local L = S.L
local WB = S:NewModule("WeaponBuff", "weaponbuff")

local CreateFrame = CreateFrame
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
-- classes that always run a temp weapon enchant; others opt-in via `allClasses`
local ENCHANT_CLASSES = { ROGUE = true, SHAMAN = true }
local SOON_MS = 5 * 60 * 1000

function WB:BuildIcon()
	if self.icon then return end
	local b = CreateFrame("Frame", "SentinelUIWeaponBuff", UIParent)
	b:SetSize(30, 30)
	b:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.tex:SetTexture("Interface\\Icons\\Ability_Poisons")
	S:CreateBackdrop(b, "Default")
	b:SetScript("OnUpdate", function(_, el)
		if not b._flash then return end
		b.t = (b.t or 0) + el
		b:SetAlpha(0.5 + 0.5 * math.abs(math.sin(b.t * 5)))
	end)
	b:Hide()
	S:CreateMover(b, "WeaponBuff", L["Weapon Buff"], { "CENTER", UIParent, "CENTER", 0, -220 }, "weaponbuff")
	self.icon = b
end

function WB:Refresh()
	local b = self.icon
	if self.db.enable == false or not GetWeaponEnchantInfo then return b:Hide() end
	local relevant = ENCHANT_CLASSES[S.myClass] or self.db.allClasses
	if not relevant then return b:Hide() end
	local hasMain, mExp, _, hasOff, oExp = GetWeaponEnchantInfo()
	if not hasMain then
		b.tex:SetVertexColor(1, 0.3, 0.3)
		b._flash = true
		b:Show()
		return
	end
	if mExp and mExp > 0 and mExp < SOON_MS then
		b.tex:SetVertexColor(1, 0.8, 0.3)
		b._flash = true
		b:Show()
		return
	end
	b._flash = nil
	b:SetAlpha(1)
	b:Hide()
end

function WB:Initialize()
	self.db = S.db.profile.weaponbuff
	if S.myClass == "MAGE" or S.myClass == "PRIEST" or S.myClass == "WARLOCK" or S.myClass == "DRUID" then return end
	self:BuildIcon()
	self:RegisterEvent("UNIT_INVENTORY_CHANGED", function(_, _, unit) if unit == "player" then WB:Refresh() end end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() WB:Refresh() end)
	-- expirations don't fire events: light poller
	self.poller = self.poller or CreateFrame("Frame")
	self.poller:SetScript("OnUpdate", function(_, el)
		WB.t = (WB.t or 0) + el
		if WB.t < 10 then return end
		WB.t = 0
		WB:Refresh()
	end)
	self:Refresh()
end

function WB:Update()
	self.db = S.db.profile.weaponbuff
	if self.icon then self:Refresh() end
end
