local addon = RLBetterItem

-- ============================================================================
-- GearScore (classic gear score formula: ilvl x rarity x slot modifier).
-- Score is driven by item level, rarity and equip slot; hunters score their
-- ranged weapon high and melee weapons low.
-- ============================================================================
local floor, select = math.floor, select

-- gear tables hold item links for the player, but inspected units often only
-- yield item IDs (GetInventoryItemLink is unreliable there, so we capture
-- GetInventoryItemID instead). GetItemInfo accepts both.
local function ItemIDOf(v)
	if type(v) == "number" then return v end
	return tonumber((v or ""):match("item:(%d+)"))
end

local BRACKET = (WOW_PROJECT_ID == (WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5)) and 400
	or (WOW_PROJECT_ID == (WOW_PROJECT_CLASSIC or 2)) and 200 or 1000
local MAX_SCORE = BRACKET * 6 - 1
local SCALE = 1.8618

local ITEM_TYPES = {
	["INVTYPE_RELIC"] = 0.3164, ["INVTYPE_TRINKET"] = 0.5625,
	["INVTYPE_2HWEAPON"] = 2.000, ["INVTYPE_WEAPONMAINHAND"] = 1.0000,
	["INVTYPE_WEAPONOFFHAND"] = 1.0000, ["INVTYPE_RANGED"] = 0.3164,
	["INVTYPE_THROWN"] = 0.3164, ["INVTYPE_RANGEDRIGHT"] = 0.3164,
	["INVTYPE_SHIELD"] = 1.0000, ["INVTYPE_WEAPON"] = 1.0000,
	["INVTYPE_HOLDABLE"] = 1.0000, ["INVTYPE_HEAD"] = 1.0000,
	["INVTYPE_NECK"] = 0.5625, ["INVTYPE_SHOULDER"] = 0.7500,
	["INVTYPE_CHEST"] = 1.0000, ["INVTYPE_ROBE"] = 1.0000,
	["INVTYPE_WAIST"] = 0.7500, ["INVTYPE_LEGS"] = 1.0000,
	["INVTYPE_FEET"] = 0.75, ["INVTYPE_WRIST"] = 0.5625,
	["INVTYPE_HAND"] = 0.7500, ["INVTYPE_FINGER"] = 0.5625,
	["INVTYPE_CLOAK"] = 0.5625, ["INVTYPE_BODY"] = 0,
}

local FORMULA = {
	A = { [4] = { 91.4500, 0.6500 }, [3] = { 81.3750, 0.8125 }, [2] = { 73.0000, 1.0000 } },
	B = { [4] = { 26.0000, 1.2000 }, [3] = { 0.7500, 1.8000 }, [2] = { 8.0000, 2.0000 }, [1] = { 0.0000, 2.2500 } },
	C = { [4] = { 0.2500, 1.6275 } },
}

-- per-bracket color interpolation for the score text
local QUALITY = {
	[6] = { { 0.94, 5, 0.00006, 1 }, { 0.47, 5, 0.00047, -1 }, { 0, 0, 0, 0 } },
	[5] = { { 0.69, 4, 0.00025, 1 }, { 0.28, 4, 0.00019, 1 }, { 0.97, 4, 0.00096, -1 } },
	[4] = { { 0.0, 3, 0.00069, 1 }, { 0.5, 3, 0.00022, -1 }, { 1, 3, 0.00003, -1 } },
	[3] = { { 0.12, 2, 0.00012, -1 }, { 1, 2, 0.00050, -1 }, { 0, 2, 0.001, 1 } },
	[2] = { { 1, 1, 0.00088, -1 }, { 1, 0, 0, 0 }, { 1, 1, 0.001, -1 } },
	[1] = { { 0.55, 0, 0.00045, 1 }, { 0.55, 0, 0.00045, 1 }, { 0.55, 0, 0.00045, 1 } },
}

function addon:GSQualityColor(score)
	score = tonumber(score) or 0
	if score > MAX_SCORE then score = MAX_SCORE end
	for i = 0, 6 do
		if score > i * BRACKET and score <= (i + 1) * BRACKET then
			local q = QUALITY[i + 1]
			local function cv(p)
				return q[p][1] + ((score - q[p][2] * BRACKET) * q[p][3]) * q[p][4]
			end
			return cv(1), cv(2), cv(3)
		end
	end
	return 0.1, 0.1, 0.1
end

-- returns gearScore, itemLevel (0 for heirlooms on classic), r, g, b
-- real item level of a link/id: prefers the effective level (upgrades,
-- scaled items) when the client provides it, falls back to the base level
local function ItemLevelOf(link)
	local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
	local ilvl = f and f(link)
	if not ilvl or ilvl <= 0 then ilvl = select(4, GetItemInfo(link)) end
	return ilvl or 0
end
addon.ItemLevelOf = ItemLevelOf

function addon:GearScoreForItem(link)
	if not link then return 0, 0, 0.1, 0.1, 0.1 end
	local _, _, rarity, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
	if not (rarity and ilvl and ITEM_TYPES[equipLoc]) then
		return 0, 0, 0.1, 0.1, 0.1
	end
	local table_, qualityScale = nil, 1
	if rarity == 5 then qualityScale = 1.3 rarity = 4
	elseif rarity == 0 or rarity == 1 then qualityScale = 0.005 rarity = 2
	elseif rarity == 7 then rarity = 3 ilvl = 187.05 end
	if ilvl < 100 and rarity == 4 then table_ = FORMULA.C
	elseif ilvl < 168 and rarity == 4 then table_ = FORMULA.B
	elseif ilvl < 148 and rarity == 3 then table_ = FORMULA.B
	elseif ilvl < 138 and rarity == 2 then table_ = FORMULA.B
	elseif ilvl <= 120 then table_ = FORMULA.B
	else table_ = FORMULA.A end
	if not (rarity >= 2 and rarity <= 4 and table_ and table_[rarity]) then
		return 0, 0, 0.1, 0.1, 0.1
	end
	local base = (ilvl - table_[rarity][1]) / table_[rarity][2]
	local r, g, b = self:GSQualityColor(floor(base * SCALE) * 11.25)
	local gs = floor(base * ITEM_TYPES[equipLoc] * SCALE * qualityScale)
	if ilvl == 187.05 then ilvl = 0 end
	if gs < 0 then
		gs = 0
		r, g, b = self:GSQualityColor(1)
	end
	return gs, ilvl, r, g, b
end

-- core scorer: works on a { slotId = itemLink } table instead of a unit so
-- cached inspect gear can be recomputed without another NotifyInspect round
-- trip (we keep the links ourselves). Missing item data is actively
-- requested, not just skipped.
-- returns gearScore, avgItemLevel, ready (false while item data is loading)
function addon:GearScoreForLinks(links, class)
	local hunter = class == "HUNTER"
	local gs, count, levelTotal, ready = 0, 0, 0, true
	local mh, oh = links[16], links[17]
	local mhID, ohID = ItemIDOf(mh), ItemIDOf(oh)
	local mh2H = mh and select(9, GetItemInfo(mh)) == "INVTYPE_2HWEAPON"
	local oh2H = oh and select(9, GetItemInfo(oh)) == "INVTYPE_2HWEAPON"
	-- Titan's Grip halves each 2H's score only when two are worn; a single 2H
	-- keeps its full 2.0 slot mod
	local both2H = mh2H and oh2H
	for i = 1, 18 do
		-- slot 17 is skipped when the main hand is a 2H: some clients report the
		-- same weapon in both slots, which would count its ilvl/score twice
		if i ~= 4 and not (i == 17 and (mh2H or (mhID and ohID == mhID))) then
			local item = links[i]
			if item then
				if not GetItemInfo(item) then
					ready = false
					local id = ItemIDOf(item)
					if id and C_Item and C_Item.RequestLoadItemDataByID then
						pcall(C_Item.RequestLoadItemDataByID, id)
					end
				else
					local s = self:GearScoreForItem(item)
					-- the ilvl average covers every equipped piece, even ones
					-- the score table can't value; scoring them as 0 used to
					-- drag the average down
					local ilvl = ItemLevelOf(item)
					if hunter then
						if i == 16 or i == 17 then s = s * 0.3164
						elseif i == 18 then s = s * 5.3224 end
					end
					if both2H and (i == 16 or i == 17) then s = s * 0.5 end
					gs = gs + s
					if ilvl > 0 then
						count = count + 1
						levelTotal = levelTotal + ilvl
					end
				end
			end
		end
	end
	if count == 0 then return 0, 0, ready end
	return floor(gs), floor(levelTotal / count), ready
end

-- returns gearScore, avgItemLevel, ready, items (slot->link or itemID), class
function addon:GearScoreForUnit(unit)
	local _, class = UnitClass(unit)
	local links = {}
	for i = 1, 18 do
		if i ~= 4 then
			-- inspected units often don't resolve links client-side; their
			-- item IDs always arrive with the inspect payload
			local link = GetInventoryItemLink(unit, i)
			if link then
				links[i] = link
			else
				local id = GetInventoryItemID(unit, i)
				if id then links[i] = id end
			end
		end
	end
	local gs, ilvl, ready = self:GearScoreForLinks(links, class)
	return gs, ilvl, ready, links, class
end
