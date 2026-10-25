-- TauntResist: warns the tank when a taunt/mock ability is resisted,
-- dodged, parried, missed or immune. Small but raid-critical on fights
-- where a taunt swap has to land.
local _, ns = ...
local S = ns.S
local L = S.L
local TR = S:NewModule("TauntResist", "tauntresist")

local format = format
local TAUNTS = {
	[355] = true,    -- taunt (warrior)
	[694] = true, [7400] = true, [7402] = true, [20559] = true, [20560] = true, [25266] = true, -- mocking blow ranks
	[1161] = true,   -- challenging shout
	[6795] = true,   -- growl (druid)
	[5209] = true,   -- challenging roar
	[31789] = true,  -- righteous defense
	[62124] = true,  -- hand of reckoning (wrath)
	[49560] = true,  -- death grip (wrath, forces target)
	[56222] = true,  -- dark command
}
local lastWarn = 0
local myGUID

function TR:Initialize()
	self.db = S.db.profile.tauntresist
	if not CombatLogGetCurrentEventInfo then return end
	myGUID = UnitGUID and UnitGUID("player")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		local _, sub, _, sGuid, sName, _, _, _, dName, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
		if sub ~= "SPELL_MISSED" or sGuid ~= myGUID then return end
		if not (spellId and TAUNTS[spellId]) then return end
		local now = GetTime()
		if now - lastWarn < 5 then return end
		lastWarn = now
		local miss = _G["MISS_" .. (missType or "")] or missType or "?"
		local msg = format(L["%s missed on %s (%s)"], spellName or "Taunt", dName or "?", miss)
		S:Print("|cffff4040" .. msg .. "|r")
		if TR.db.chat == "party" and IsInGroup() then
			SendChatMessage(msg, S.GroupChannel())
		end
		if TR.db.sound ~= false and PlaySoundFile then pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.wav") end
	end)
end

function TR:Update()
	self.db = S.db.profile.tauntresist
end
