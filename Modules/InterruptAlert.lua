-- Group interrupt alert: reports successful interrupts by group members to
-- the matching group channel (party / raid / instance chat), so everyone sees
-- "Enemy X interrupted by Y" including which cast was stopped.
local _, ns = ...
local S = ns.S
local L = S.L
local IA = S:NewModule("InterruptAlert", "interruptalert")

local bit_band = _G.bit and _G.bit.band
local format = string.format
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local SendChatMessage = SendChatMessage
local IsInGroup, IsInRaid, IsInInstance = IsInGroup, IsInRaid, IsInInstance
local UnitGUID, GetTime = UnitGUID, GetTime
local UnitInParty, UnitInRaid = UnitInParty, UnitInRaid

local AFFIL_GROUP = (COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1) + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2) + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4)

local lastKey, lastTime = nil, 0

local function GroupChat()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
end

local function Announce(channel, msg)
	if channel == "AUTO" then
		local ch = GroupChat()
		if ch then SendChatMessage(msg, ch) end
	elseif channel == "PARTY" and IsInGroup() then SendChatMessage(msg, "PARTY")
	elseif channel == "RAID" and IsInRaid() then SendChatMessage(msg, "RAID")
	elseif channel == "RAID_WARNING" and IsInRaid() then SendChatMessage(msg, "RAID_WARNING")
	elseif channel == "INSTANCE_CHAT" and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then SendChatMessage(msg, "INSTANCE_CHAT")
	end
end

function IA:COMBAT_LOG_EVENT_UNFILTERED()
	local db = self.db
	if not db or db.enable == false then return end
	if db.channel == "NONE" and not db.localEcho then return end
	local _, sub, _, sourceGUID, sourceName, sourceFlags, _, _, destName, _, _, _, spellName, _, _, extraSpellName = CombatLogGetCurrentEventInfo()
	if sub ~= "SPELL_INTERRUPT" then return end
	if not sourceFlags or S.IsSecret(sourceFlags) then return end
	-- only interrupts performed by the player or group members
	local inGroup
	if bit_band then
		inGroup = bit_band(sourceFlags, AFFIL_GROUP) ~= 0
	else
		inGroup = sourceGUID == UnitGUID("player") or sourceGUID == UnitGUID("pet")
			or (UnitInParty and sourceName and UnitInParty(sourceName))
			or (UnitInRaid and sourceName and UnitInRaid(sourceName))
	end
	if not inGroup then return end
	if db.onlyOwn and sourceGUID ~= UnitGUID("player") and sourceGUID ~= UnitGUID("pet") then return end
	-- combat log can deliver the same interrupt twice in quick succession
	local key = tostring(sourceGUID) .. tostring(extraSpellName or spellName)
	local now = GetTime()
	if key == lastKey and now - lastTime < 1.5 then return end
	lastKey, lastTime = key, now
	local msg = format(L["%s interrupted %s's %s"], sourceName or "?", destName or "?", extraSpellName or spellName or "?")
	if db.localEcho then self:Print(msg) end
	if db.channel ~= "NONE" then Announce(db.channel or "AUTO", msg) end
end

function IA:Initialize()
	self.db = S.db.profile.interruptalert
	if self.db.enable == false then return end
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
