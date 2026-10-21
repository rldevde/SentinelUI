local _, ns = ...

-- SentinelUI trainer data shim.
-- Provides the small "wt" namespace surface that the class data files in
-- Modules/Trainer/Data/ rely on: currentClass, SpellsByLevel, FactionFilter,
-- RaceFilter and AddOverriddenSpells. Spell data itself lives in Data/*.lua.

local WTData = {}
ns.WTData = WTData

WTData.currentClass = select(2, UnitClass("player"))

local playerFaction = UnitFactionGroup("player")
local playerRace = select(3, UnitRace("player"))

local tinsert = tinsert
local ipairs = ipairs
local pairs = pairs

local function filter(spellsByLevel, pred)
	local output = {}
	for level, spells in pairs(spellsByLevel) do
		output[level] = {}
		for _, spell in ipairs(spells) do
			if pred(spell) == true then
				tinsert(output[level], spell)
			end
		end
	end
	return output
end

function WTData.FactionFilter(spellsByLevel)
	return filter(spellsByLevel, function(spell)
		return spell.faction == nil or spell.faction == playerFaction
	end)
end

function WTData.RaceFilter(spellsByLevel)
	return filter(spellsByLevel, function(spell)
		if spell.race == nil and spell.races == nil then return true end
		if spell.races == nil then return spell.race == playerRace end
		for _, r in ipairs(spell.races) do
			if r == playerRace then return true end
		end
		return false
	end)
end

-- varargs: each entry is an ordered list of spell ids that replace each other
-- rank by rank (a learned higher rank marks lower ranks as learned).
function WTData:AddOverriddenSpells(...)
	local abilityMap = {}
	for _, abilityIds in ipairs({...}) do
		for _, abilityId in ipairs(abilityIds) do
			abilityMap[abilityId] = abilityIds
		end
	end
	self.overriddenSpellsMap = abilityMap
end
