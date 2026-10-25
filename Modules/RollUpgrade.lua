-- RollUpgrade: adds an ilvl-delta badge to Blizzard's group loot roll frames
-- so you can see at a glance if the item is an upgrade for your equipped slot.
local _, ns = ...
local S = ns.S
local L = S.L
local RU = S:NewModule("RollUpgrade", "rollupgrade")

local GetLootRollItemLink = GetLootRollItemLink
local GetLootRollItemInfo = GetLootRollItemInfo
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemID = GetInventoryItemID

local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
	INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
	INVTYPE_TABARD = { 19 },
}

local function Ilvl(link)
	if not link or not GetItemInfo then return nil end
	local _, _, _, il = GetItemInfo(link)
	return il
end

local function Decorate(f, tries)
	if not f or not f.rollID then return end
	if not f.suiRollBadge then
		local b = S:FontString(f.IconFrame or f, 11, "OUTLINE", S.media.numberFont)
		b:SetPoint("TOPRIGHT", f.IconFrame or f, "TOPRIGHT", 2, 2)
		f.suiRollBadge = b
	end
	local b = f.suiRollBadge
	local link = GetLootRollItemLink and GetLootRollItemLink(f.rollID)
	if not link or not GetItemInfo then b:Hide() return end
	local _, _, _, ilvl, _, _, _, _, invType = GetItemInfo(link)
	local slots = invType and SLOTS[invType]
	if not ilvl or not slots then
		b:Hide()
		-- item data may not be cached yet: look again a few times
		if not ilvl and (tries or 0) < 3 then
			C_Timer.After(0.5, function() if f:IsShown() then Decorate(f, (tries or 0) + 1) end end)
		end
		return
	end
	local best = 0
	for _, s in ipairs(slots) do
		local eq = GetInventoryItemLink and GetInventoryItemLink("player", s)
		local eil = Ilvl(eq) or 0
		if eil > best then best = eil end
	end
	local diff = ilvl - best
	if diff > 0 then
		b:SetFormattedText("|cff4ce34c+%d|r", diff)
	elseif diff < 0 then
		b:SetFormattedText("|cffff5555%d|r", diff)
	else
		b:SetText("|cffaaaaaa=|r")
	end
	b:Show()
end

function RU:Initialize()
	self:RegisterEvent("START_LOOT_ROLL", function()
		C_Timer.After(0.2, function()
			for i = 1, 8 do
				local f = _G["GroupLootFrame" .. i]
				if f and f:IsShown() then Decorate(f) end
			end
		end)
	end)
end
