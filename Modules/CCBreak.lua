-- CCBreak: announces who broke a breakable crowd-control effect on an
-- enemy (sheep, freezing trap, sap, hibernate, repentance, seduce, gouge,
-- wyvern sting, scatter shot). The breaker is attributed from the last
-- damage event on that target shortly before the aura was removed.
local _, ns = ...
local S = ns.S
local L = S.L
local CB = S:NewModule("CCBreak", "ccbreak")

local format = format
local GetTime = GetTime
local WINDOW = 1.6

-- spell ids of CC auras that break on damage (classic through wrath ranks)
local CC = {
	[118] = true, [12824] = true, [12825] = true, [12826] = true,   -- polymorph
	[28271] = true, [28272] = true, [61721] = true, [61780] = true, -- pig/turtle/rabbit/cat
	[3355] = true, [14308] = true, [14309] = true,                  -- freezing trap
	[6770] = true, [2070] = true, [11297] = true,                   -- sap
	[2637] = true, [18657] = true, [18658] = true,                  -- hibernate
	[20066] = true,                                               -- repentance
	[6358] = true,                                                -- seduction
	[1776] = true, [1777] = true, [8629] = true, [11285] = true, [11286] = true, -- gouge
	[24132] = true, [24133] = true, [24135] = true, [27068] = true, [49011] = true, [49012] = true, -- wyvern sting
	[19503] = true, [23601] = true,                                 -- scatter shot
}

local lastHit = {} -- destGUID -> { name=breaker, t=time }

function CB:Announce(breaker, ccName, destName)
	if self.db.chat == "party" and IsInGroup() then
		SendChatMessage(format(L["%s broke %s on %s"], breaker, ccName, destName), S.GroupChannel())
	else
		S:Print(format("|cffffd040" .. L["%s broke %s on %s"], breaker, ccName, destName) .. "|r")
	end
end

function CB:Initialize()
	self.db = S.db.profile.ccbreak
	if not CombatLogGetCurrentEventInfo then return end
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		local _, sub, _, _, sName, _, _, dGuid, dName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
		if sub == "SPELL_DAMAGE" or sub == "SWING_DAMAGE" or sub == "RANGE_DAMAGE"
			or sub == "SPELL_PERIODIC_DAMAGE" or sub == "DAMAGE_SHIELD" or sub == "DAMAGE_SPLIT" then
			if dGuid and sName then lastHit[dGuid] = { name = sName, t = GetTime() } end
		elseif sub == "SPELL_AURA_REMOVED" or sub == "SPELL_AURA_BROKEN" or sub == "SPELL_AURA_BROKEN_SPELL" then
			if not (spellId and CC[spellId]) then return end
			local hit = dGuid and lastHit[dGuid]
			if hit and GetTime() - hit.t <= WINDOW then
				CB:Announce(hit.name, spellName or "CC", dName or "?")
			elseif CB.db.expired then
				S:Print(format(L["%s on %s expired or was dispelled"], spellName or "CC", dName or "?"))
			end
			if dGuid then lastHit[dGuid] = nil end
		end
	end)
end

function CB:Update()
	self.db = S.db.profile.ccbreak
end
