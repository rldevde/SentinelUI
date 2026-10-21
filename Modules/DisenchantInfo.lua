-- DisenchantInfo: item tooltips show what the item disenchants into, based
-- on item level / quality / weapon-vs-armor weighting (TBC-era tables).
local _, ns = ...
local S = ns.S
local L = S.L
local DI = S:NewModule("DisenchantInfo", "disenchant")

-- [ilvl cap] = { dust-name, essence-name, shard-name }
-- dusts get armor weighting (~75%), essences weapon weighting (~75%)
local GREEN = {
	[15] = { "Strange Dust", "Lesser Magic Essence", "Small Glimmering Shard" },
	[20] = { "Strange Dust", "Greater Magic Essence", "Small Glimmering Shard" },
	[25] = { "Soul Dust", "Lesser Astral Essence", "Small Glimmering Shard" },
	[30] = { "Soul Dust", "Greater Astral Essence", "Large Glimmering Shard" },
	[35] = { "Vision Dust", "Lesser Mystic Essence", "Small Glowing Shard" },
	[40] = { "Vision Dust", "Greater Mystic Essence", "Large Glowing Shard" },
	[45] = { "Dream Dust", "Lesser Nether Essence", "Small Radiant Shard" },
	[50] = { "Dream Dust", "Greater Nether Essence", "Large Radiant Shard" },
	[55] = { "Illusion Dust", "Lesser Eternal Essence", "Small Brilliant Shard" },
	[60] = { "Illusion Dust", "Greater Eternal Essence", "Large Brilliant Shard" },
	[99] = { "Arcane Dust", "Lesser Planar Essence", "Small Prismatic Shard" },
	[999] = { "Arcane Dust", "Greater Planar Essence", "Small Prismatic Shard" },
}
local BLUE = {
	[65] = "Large Brilliant Shard",
	[70] = "Large Brilliant Shard",
	[94] = "Large Prismatic Shard",
	[115] = "Large Prismatic Shard",
	[999] = "Void Crystal",
}
local EPIC = {
	[65] = "Nexus Crystal",
	[999] = "Void Crystal",
}

local function Bracket(tbl, ilvl)
	local best
	for cap in pairs(tbl) do if ilvl <= cap and (not best or cap < best) then best = cap end end
	return best and tbl[best]
end

function DI:Result(link)
	local _, _, quality, ilvl, _, _, _, _, equipLoc = S.GetItemInfo(link)
	if not quality or not ilvl or ilvl < 5 then return end
	if equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then return end
	local isWeapon = equipLoc:find("WEAPON") or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_WEAPONOFFHAND"
	if quality == 2 then
		local res = Bracket(GREEN, ilvl)
		if res then
			return format("%s / %s / %s", L[res[1]] or res[1], L[res[2]] or res[2], L[res[3]] or res[3]),
				isWeapon and L["mostly essence"] or L["mostly dust"]
		end
	elseif quality == 3 then
		local r = Bracket(BLUE, ilvl)
		if r then return L[r] or r end
	elseif quality == 4 then
		local r = Bracket(EPIC, ilvl)
		if r then return L[r] or r end
	end
end

function DI:Initialize()
	self.db = S.db.profile.disenchant
	local function Hook(tt, data)
		if not tt.GetItem then return end
		local _, link = tt:GetItem()
		if not link then return end
		if DI.db and DI.db.enable == false then return end
		local res, bias = DI:Result(link)
		if res then
			tt:AddLine("|cffb080ff" .. (L["Disenchants into:"] or "Disenchants into:") .. "|r " .. res .. (bias and (" |cff808080(" .. bias .. ")|r") or ""))
			tt:Show()
		end
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt) Hook(tt) end)
	else
		for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
			local tt = _G[name]
			if tt and tt.HookScript then
				tt:HookScript("OnTooltipSetItem", function(t) Hook(t) end)
			end
		end
	end
end

function DI:Update()
	self.db = S.db.profile.disenchant
end
