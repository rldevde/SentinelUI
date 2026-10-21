-- CooldownTracker: row of icons for the player's major cooldowns that stay
-- lit while they are on cooldown (with sweep + seconds text). Per-class
-- spell sets, only spells actually known are tracked.
local _, ns = ...
local S = ns.S
local L = S.L
local CDT = S:NewModule("CooldownTracker", "cooldowntracker")

local CreateFrame = CreateFrame
local GetSpellCooldown = GetSpellCooldown or (C_Spell and C_Spell.GetSpellCooldown)

-- major/long cooldowns per class (vanilla + TBC + a few wrath ids)
local SPELLS = {
	WARRIOR = { 871, 12975, 1719, 20252, 676 },
	PALADIN = { 642, 498, 1022, 633, 1044 },
	PRIEST = { 33206, 10060, 14751, 15286 },
	WARLOCK = { 18708, 1122, 18540 },
	MAGE = { 45438, 11958, 12042, 11129, 12472 },
	ROGUE = { 5277, 31224, 13750, 13877, 1856 },
	HUNTER = { 19263, 19574, 3045, 1543 },
	SHAMAN = { 16166, 16188, 30823, 2894, 2062 },
	DRUID = { 22812, 740, 17116, 1850 },
	DEATHKNIGHT = { 48707, 48792, 55233, 49028, 47568 },
}
local MAX_SLOTS = 10

local function SpellKnown(id)
	if S.IsSpellKnown and S.IsSpellKnown(id) then return true end
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	return GetSpellInfo and GetSpellInfo(id) and IsSpellKnown and IsSpellKnown(id)
end

local function CooldownOf(id)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(id)
		if info then return info.startTime, info.duration end
	elseif GetSpellCooldown then
		return GetSpellCooldown(id)
	end
end

function CDT:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUICooldownTracker", UIParent)
	f:SetSize(MAX_SLOTS * 34, 30)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
	f:SetFrameStrata("LOW")
	f.icons = {}
	for i = 1, MAX_SLOTS do
		local b = CreateFrame("Frame", nil, f)
		b:SetSize(28, 28)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		b.cd:SetAllPoints()
		b.text = S:FontString(b, 11, "OUTLINE", S.media.numberFont)
		b.text:SetPoint("BOTTOM", 0, -2)
		S:CreateBackdrop(b, "Default")
		b:Hide()
		f.icons[i] = b
	end
	f:Hide()
	S:CreateMover(f, "CooldownTracker", L["Cooldown Tracker"], { "CENTER", UIParent, "CENTER", 0, -260 }, "cooldowntracker")
	self.frame = f
end

function CDT:Refresh()
	if self.db.enable == false then if self.frame then self.frame:Hide() end return end
	self:BuildFrame()
	local spells = SPELLS[S.myClass]
	if not spells then self.frame:Hide() return end
	-- first pass: know spells and whether any is on cooldown
	local idx = 0
	for _, id in ipairs(spells) do
		if SpellKnown(id) then
			local start, dur = CooldownOf(id)
			local onCD = start and dur and dur > (self.db.minCooldown or 15) and (start + dur) > GetTime()
			if onCD then
				idx = idx + 1
				local b = self.frame.icons[idx]
				if b then
					b.tex:SetTexture(select(3, S.GetSpellInfo(id)) or 134400)
					if b.cd.SetCooldown then b.cd:SetCooldown(start, dur)
					elseif b.cd.SetCooldownUNIX then b.cd:SetCooldownUNIX(start, dur) end
					b:SetAlpha(0.85)
					b.spellId = id
					b:Show()
				end
			end
		end
	end
	-- equipped trinkets with a use-effect join the row as well
	if self.db.trinkets ~= false and GetInventoryItemID then
		for _, slot in ipairs({ 13, 14 }) do
			local itemId = GetInventoryItemID("player", slot)
			if itemId and GetItemSpell then
				local spellName = GetItemSpell(itemId)
				if spellName and GetInventoryItemCooldown then
					local start, dur = GetInventoryItemCooldown("player", slot)
					if start and dur and dur > (self.db.minCooldown or 15) and (start + dur) > GetTime() then
						idx = idx + 1
						local b = self.frame.icons[idx]
						if b then
							b.tex:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemId)) or select(10, S.GetItemInfo(itemId)) or 134400)
							if b.cd.SetCooldown then b.cd:SetCooldown(start, dur)
							elseif b.cd.SetCooldownUNIX then b.cd:SetCooldownUNIX(start, dur) end
							b:SetAlpha(0.85)
							b.spellId = nil
							b.trinketSlot = slot
							b:Show()
						end
					end
				end
			end
		end
	end
	for i = idx + 1, MAX_SLOTS do self.frame.icons[i]:Hide() end
	if idx > 0 then
		local w = idx * 34 - 6
		self.frame:SetWidth(w)
		for i = 1, idx do
			self.frame.icons[i]:ClearAllPoints()
			self.frame.icons[i]:SetPoint("LEFT", (i - 1) * 34, 0)
		end
		self.frame:Show()
	else
		self.frame:Hide()
	end
end

function CDT:Initialize()
	self.db = S.db.profile.cooldowntracker
	if not SPELLS[S.myClass] then return end
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function() CDT:Refresh() end)
	self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() CDT:Refresh() end)
	self:RegisterEvent("SPELLS_CHANGED", function() CDT:Refresh() end)
	self:RegisterEvent("PLAYER_TALENT_UPDATE", function() CDT:Refresh() end)
	-- countdown text + expiry cleanup at 4 Hz
	self.tick = self.tick or CreateFrame("Frame")
	local acc = 0
	self.tick:SetScript("OnUpdate", function(_, el)
		acc = acc + el
		if acc < 0.25 then return end
		acc = 0
		if CDT.frame and CDT.frame:IsShown() then
			for i = 1, MAX_SLOTS do
				local b = CDT.frame.icons[i]
				if b:IsShown() then
					local start, dur
					if b.spellId then start, dur = CooldownOf(b.spellId)
					elseif b.trinketSlot and GetInventoryItemCooldown then start, dur = GetInventoryItemCooldown("player", b.trinketSlot) end
					local left = start and (start + dur - GetTime()) or 0
					b.text:SetText(left > 0 and (left >= 60 and format("%dm", left / 60) or format("%.0f", left)) or "")
				end
			end
			CDT:Refresh() -- drop icons whose cooldown expired
		end
	end)
	self:Refresh()
end

function CDT:Update()
	self.db = S.db.profile.cooldowntracker
	self:Refresh()
end
