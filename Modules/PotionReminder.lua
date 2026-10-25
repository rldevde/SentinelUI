-- PotionReminder: flashing, click-to-use potion button while the player's
-- health is below the threshold and a usable healing potion/healthstone is
-- in the bags and off cooldown.
local _, ns = ...
local S = ns.S
local L = S.L
local PR = S:NewModule("PotionReminder", "potionreminder")

local CreateFrame = CreateFrame
local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)
local GetItemCooldown = GetItemCooldown or (C_Item and C_Item.GetItemCooldown)

-- strongest first: super/major healing potions, then healthstones, then the
-- classic healing potion tiers
local ITEMS = {
	43531, 33447, 22829, 13446, 3928, 1710, 929, 858, 118, 4596,
	36894, 36893, 36892, 22105, 22104, 22103, 19005, 19004, 5512, 5511, 5510, 5509,
}

local function UsableItem()
	for _, id in ipairs(ITEMS) do
		if GetItemCount and (GetItemCount(id) or 0) > 0 then
			local start, dur
			if GetItemCooldown then
				local ok, s, d = pcall(GetItemCooldown, id)
				if ok then start, dur = s, d end
			end
			if not start or start == 0 or dur == 0 then return id end
		end
	end
end

function PR:BuildButton()
	if self.btn then return end
	-- a frame with a protected child may not be shown/hidden in combat at all,
	-- so both holder and button stay visible permanently; "hidden" is emulated
	-- via alpha (unrestricted) plus a cover frame that eats stray clicks
	local h = CreateFrame("Frame", "SentinelUIPotionReminderHolder", UIParent)
	h:SetAllPoints(UIParent)
	h:Show()
	self.holder = h
	local b = CreateFrame("Button", "SentinelUIPotionReminder", h, "SecureActionButtonTemplate")
	b:SetSize(36, 36)
	b:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
	b:SetAttribute("type", "item")
	b:SetFrameStrata("MEDIUM")
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	S:CreateBackdrop(b, "Default")
	local cap = S:FontString(b, 9, "OUTLINE", S.media.unitFont)
	cap:SetPoint("TOP", b, "BOTTOM", 0, -2)
	cap:SetText(L["Potion Reminder"])
	cap:SetTextColor(1, 0.4, 0.3)
	local cover = CreateFrame("Frame", nil, h)
	cover:SetAllPoints(b)
	cover:EnableMouse(true)
	cover:SetFrameStrata("HIGH")
	cover:Hide()
	self.cover = cover
	b:SetScript("OnUpdate", function(self, el)
		if not b._pulse then return end
		self.t = (self.t or 0) + el
		b:SetAlpha(0.55 + 0.45 * math.abs(math.sin(self.t * 5)))
	end)
	b:SetAlpha(0)
	b:Show()
	S:CreateMover(b, "PotionReminder", L["Potion Reminder"], { "CENTER", UIParent, "CENTER", 0, -140 }, "potionreminder")
	self.btn = b
end

local function HideBtn(self)
	self.btn._pulse = nil
	self.btn:SetAlpha(0)
	-- Show/Hide on the holder's children is protected in combat (the holder
	-- parents a secure button); the cover just eats clicks, defer it
	if InCombatLockdown() then
		if S.RunOutOfCombat then S:RunOutOfCombat(function() if self.cover then self.cover:Show() end end) end
	else
		self.cover:Show()
	end
end

function PR:Refresh()
	if self.db.enable == false then if self.btn then HideBtn(self) end return end
	self:BuildButton()
	local hp, max = UnitHealth("player"), UnitHealthMax("player")
	if S.IsSecret(hp) or not max or max <= 0 or UnitIsDeadOrGhost("player") then HideBtn(self) return end
	if hp / max > (self.db.threshold or 0.35) then HideBtn(self) return end
	local id = UsableItem()
	if not id then HideBtn(self) return end
	-- protected attributes can't change mid-combat; keep the last assigned item
	-- (correct in ~all cases) and re-apply on PLAYER_REGEN_ENABLED
	if not InCombatLockdown() then
		self.btn:SetAttribute("item", "item:" .. id)
	end
	self.btn.tex:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or select(10, S.GetItemInfo(id)) or 134400)
	if InCombatLockdown() then
		if S.RunOutOfCombat then S:RunOutOfCombat(function() if self.cover then self.cover:Hide() end end) end
	else
		self.cover:Hide()
	end
	self.btn._pulse = true
end

function PR:Initialize()
	self.db = S.db.profile.potionreminder
	for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "BAG_UPDATE", "BAG_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED" }) do
		self:RegisterEvent(ev, function(_, _, unit) if not unit or unit == "player" then PR:Refresh() end end)
	end
	self:Refresh()
end

function PR:Update()
	self.db = S.db.profile.potionreminder
	self:Refresh()
end
