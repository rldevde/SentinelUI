-- HunterTools: two hunter-specific warnings.
--  * low ammunition warning (chat + screen flash), throttled
--  * Aspect of the Cheetah/Pack warning when entering combat with it up
local _, ns = ...
local S = ns.S
local L = S.L
local HT = S:NewModule("HunterTools", "huntertools")

local format, floor = format, math.floor
local CreateFrame = CreateFrame
local UnitAura = S.UnitAura
local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)
local GetTime = GetTime
local CHEETAH = { 5118, 13159 } -- cheetah, pack
local lastWarn = 0
local lastAmmoWarn = 0

local function AmmoInfo()
	-- classic: GetInventoryItemCount on the ammo slot covers both ammo types;
	-- fall back to scanning the equipped ammo item
	local n = GetInventoryItemCount and GetInventoryItemCount("player", 0)
	if n and n > 0 then return n end
	local itemId = GetInventoryItemID and GetInventoryItemID("player", 0)
	if itemId and GetItemCount then return GetItemCount(itemId) or 0 end
	return 0
end

local function HasCheetah()
	for i = 1, 40 do
		local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
		if not name then break end
		for _, id in ipairs(CHEETAH) do if spellId == id then return true end end
	end
	return false
end

function HT:CheckAmmo()
	local db = self.db
	if db.ammoWarn == false then return end
	local threshold = db.ammoThreshold or 200
	local n = AmmoInfo()
	if n <= 0 or n > threshold then return end
	local now = GetTime()
	if now - lastAmmoWarn < 120 then return end
	lastAmmoWarn = now
	S:Print("|cffffd040" .. format(L["Low ammo: %d left"], n) .. "|r")
	if db.sound ~= false and PlaySoundFile then pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.wav") end
end

function HT:CheckCheetah()
	local db = self.db
	if db.cheetahWarn == false or not InCombatLockdown() then return end
	if not HasCheetah() then return end
	local now = GetTime()
	if now - lastWarn < 20 then return end
	lastWarn = now
	S:Print("|cffff4040" .. (L["Aspect of the Cheetah/Pack is active in combat!"]) .. "|r")
end

function HT:Initialize()
	if S.myClass ~= "HUNTER" then return end
	self.db = S.db.profile.huntertools
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() HT:CheckCheetah() end)
	self:RegisterEvent("UNIT_AURA", function(_, unit) if unit == "player" then HT:CheckAmmo() end end)
	self:RegisterEvent("BAG_UPDATE", function() HT:CheckAmmo() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() HT:CheckAmmo() end)
end

function HT:Update()
	self.db = S.db.profile.huntertools
end
