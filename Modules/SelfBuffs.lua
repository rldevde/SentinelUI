-- SelfBuffs: reminds you about missing class self-buffs (mage armors,
-- priest Inner Fire, warlock demon/fel armor, shaman lightning/water
-- shield, druid thorns). Paladin blessings are handled by the Blessings
-- module, rogues/shaman weapon enchants by WeaponBuff.
local _, ns = ...
local S = ns.S
local L = S.L
local SB = S:NewModule("SelfBuffs", "selfbuffs")

local pairs, ipairs = pairs, ipairs
local CreateFrame = CreateFrame
local GetSpellInfo = GetSpellInfo or C_Spell and C_Spell.GetSpellInfo
local UnitAura = S.UnitAura
local GetTime = GetTime
local ICON = 28
local GAP = 4

-- aura groups: show a reminder when NONE of the listed spells is active
local GROUPS = {
	MAGE = {
		{ 168, 7300, 7301, 7302, 7320, 7321, 10219, 10220, -- frost/ice armor
		  6117, 22782, 22783, 27125,                            -- mage armor
		  30482, 27124 },                                -- molten armor
	},
	PRIEST = {
		{ 588, 602, 1006, 7128, 10951, 10952, 25431, 48168 }, -- inner fire
	},
	WARLOCK = {
		{ 687, 696, 706, 1086, 11733, 11734, 11735, 27260,   -- demon armor
		  28176, 28189, 47889, 47893 },                      -- fel armor
	},
	SHAMAN = {
		{ 324, 325, 905, 945, 8134, 10431, 10432, 25469,     -- lightning shield
		  24398, 33736, 25472, 57960, 49280, 49281 },               -- water shield
	},
	DRUID = {
		{ 467, 782, 1075, 8914, 9756, 9910, 26992, 53307 },  -- thorns
	},
}

-- texture paths always resolve if the art exists; fileIDs can point at
-- assets missing on this client build
local iconPath = {
	[168] = [[Interface\Icons\Spell_Frost_FrostArmor02]],
	[588] = [[Interface\Icons\Spell_Holy_InnerFire]],
	[687] = [[Interface\Icons\Spell_Shadow_RagingScream]],
	[324] = [[Interface\Icons\Spell_Nature_LightningShield]],
	[467] = [[Interface\Icons\Spell_Nature_Thorns]],
}

local function SpellInfo(id)
	local name, icon
	if S.GetSpellInfo then name, _, icon = S.GetSpellInfo(id) end
	if not name and GetSpellInfo then
		local n = GetSpellInfo(id)
		if type(n) == "table" then name, icon = n.name, n.iconID
		else name, _, icon = GetSpellInfo(id) end
	end
	if S.IsSecret and (S.IsSecret(name) or S.IsSecret(icon)) then icon = nil end
	return name, iconPath[id] or icon
end

local function HasAnyAura(list)
	for i = 1, 40 do
		local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
		if not name then break end
		if spellId then
			for _, id in ipairs(list) do if spellId == id then return true end end
		end
	end
	return false
end

local holder
function SB:EnsureHolder()
	if holder then return holder end
	holder = CreateFrame("Frame", "SentinelUISelfBuffs", UIParent)
	holder:SetSize(1, ICON)
	S:CreateMover(holder, "selfbuffs", L["Self Buffs"], { "TOP", UIParent, "TOP", 0, -170 }, "selfbuffs")
	holder:SetScript("OnEvent", function(_, _, unit)
		if unit == nil or unit == "player" then SB:Refresh() end
	end)
	return holder
end

function SB:Refresh()
	if not self.groups then return end
	local h = self:EnsureHolder()
	local missing = {}
	for _, list in ipairs(self.groups) do
		if not HasAnyAura(list) then missing[#missing + 1] = list end
	end
	h.icons = h.icons or {}
	for i, list in ipairs(missing) do
		local b = h.icons[i]
		if not b then
			b = CreateFrame("Frame", nil, h)
			b:SetSize(ICON, ICON)
			b.tex = b:CreateTexture(nil, "ARTWORK")
			b.tex:SetAllPoints()
			b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
			b:EnableMouse(true)
			b:SetScript("OnEnter", function(s2)
				GameTooltip:SetOwner(s2, "ANCHOR_BOTTOM")
				GameTooltip:AddLine(s2.spellName or "", 1, 1, 1)
				GameTooltip:AddLine(L["Self buff missing"], 1, 0.3, 0.3)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			h.icons[i] = b
		end
		local name, icon = SpellInfo(list[1])
		b.spellName = name
		b.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		b.tex:SetDesaturated(true)
		b:SetPoint("LEFT", h, "CENTER", -( (#missing * (ICON + GAP) - GAP) / 2 ) + (i - 1) * (ICON + GAP), 0)
		b:Show()
	end
	for i = #missing + 1, #(h.icons) do h.icons[i]:Hide() end
end

function SB:Initialize()
	self.db = S.db.profile.selfbuffs
	self.groups = GROUPS[S.myClass]
	if not self.groups then return end
	local h = self:EnsureHolder()
	h:RegisterEvent("UNIT_AURA")
	h:RegisterEvent("PLAYER_ENTERING_WORLD")
	h.elapsed = 0
	h:SetScript("OnUpdate", function(_, el)
		h.elapsed = h.elapsed + el
		if h.elapsed > 2 then h.elapsed = 0 SB:Refresh() end -- cheap rescan; auras can arrive without our event
	end)
end

function SB:Update()
	self.db = S.db.profile.selfbuffs
	if holder then holder:SetShown(self.db.enable ~= false) end
end
