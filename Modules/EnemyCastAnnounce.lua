-- EnemyCastAnnounce: prints a short alert when a hostile unit starts
-- casting a noteworthy spell (CC or a heal). Self-chat only to stay
-- spam-free; deduplicated per caster+spell for a few seconds.
local _, ns = ...
local S = ns.S
local L = S.L
local EC = S:NewModule("EnemyCastAnnounce", "enemycastannounce")

local format = format
local GetTime = GetTime

local WATCH = {
	-- crowd control
	[118] = true, [12824] = true, [12825] = true, [12826] = true, [28271] = true, [28272] = true, -- polymorph
	[5782] = true, [6213] = true, [6215] = true,           -- fear
	[8122] = true, [8124] = true, [10888] = true, [10890] = true, -- psychic scream
	[710] = true, [18647] = true,                          -- banish
	[6358] = true,                                         -- seduction
	[605] = true,                                          -- mind control
	[33786] = true,                                        -- cyclone
	[20066] = true,                                        -- repentance
	[853] = true, [5588] = true, [5589] = true, [10308] = true, -- hammer of justice
	-- heals
	[2061] = true, [9472] = true, [9473] = true, [9474] = true, [10915] = true, [10916] = true, [10917] = true, [25235] = true, -- flash heal
	[2060] = true, [10963] = true, [10964] = true, [10965] = true, [25314] = true, -- greater heal
	[635] = true, [639] = true, [647] = true, [1026] = true, [1042] = true, [3472] = true, [10328] = true, [10329] = true, [25292] = true, [27135] = true, -- holy light
	[8005] = true, [10395] = true, [10396] = true, [25357] = true, [25391] = true, -- healing wave
	[1064] = true, [10622] = true, [10623] = true, [25422] = true, [25423] = true, -- chain heal
	[8936] = true, [9750] = true, [9876] = true, [26980] = true, -- regrowth
	[2006] = true, [2010] = true, [20770] = true, [20776] = true, [10880] = true, [10881] = true, [25435] = true, -- resurrections
}
local seen = {}
local DEDUP = 4

function EC:Initialize()
	self.db = S.db.profile.enemycastannounce
	if not CombatLogGetCurrentEventInfo then return end
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		local _, sub, _, _, sName, sFlags, _, _, dName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
		if sub ~= "SPELL_CAST_START" or not (spellId and WATCH[spellId]) then return end
		if sName == S.myName then return end
		local hostile = sFlags and bit and bit.band(sFlags, COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40)
		if hostile ~= (COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40) then return end
		local key = (sName or "?") .. ":" .. spellId
		local now = GetTime()
		if seen[key] and now - seen[key] < DEDUP then return end
		seen[key] = now
		S:Print("|cffff8040" .. format(L["%s is casting %s"], sName or "?", spellName or "?") .. "|r")
	end)
end

function EC:Update()
	self.db = S.db.profile.enemycastannounce
end
