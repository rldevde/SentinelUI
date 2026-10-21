-- FastLoot: loots every slot the instant LOOT_READY fires, before the loot
-- window renders its list. Respects the client's autoloot modifier unless
-- "always" is set; skips during combat loot lockdown edge cases via SafeCall.
local _, ns = ...
local S = ns.S
local L = S.L
local FL = S:NewModule("FastLoot", "fastloot")

local GetNumLootItems = GetNumLootItems
local LootSlot = LootSlot

function FL:Initialize()
	self.db = S.db.profile.fastloot
	self:RegisterEvent("LOOT_READY", function(_, _, autoloot)
		if FL.db.enable == false then return end
		local loot = FL.db.always or autoloot or (GetCVarBool and GetCVarBool("autoLootDefault"))
		if not loot then return end
		for i = (GetNumLootItems and GetNumLootItems() or 0), 1, -1 do
			S:SafeCall("FastLoot", LootSlot, i)
		end
	end)
end

function FL:Update()
	self.db = S.db.profile.fastloot
end
