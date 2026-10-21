-- RezAnnouncer: announces resurrections to the group. Watches the combat log
-- for SPELL_RESURRECT where the player is source (announce target) or
-- destination (announce who rezzed you).
local _, ns = ...
local S = ns.S
local L = S.L
local RA = S:NewModule("RezAnnouncer", "rezannouncer")

local RES_SPELLS = {
	[2006] = true, [2010] = true, [10880] = true, [10881] = true, [20770] = true, -- Resurrection (priest)
	[7328] = true, [10322] = true, [10324] = true, [20772] = true, [20773] = true, -- Redemption (paladin)
	[2008] = true, [20609] = true, [20610] = true, [20776] = true, [20777] = true, -- Ancestral Spirit (shaman)
	[20484] = true, [20739] = true, [20740] = true, [20742] = true, [20747] = true, [20748] = true, -- Rebirth (druid)
	[50769] = true, [95750] = true, -- Revive (druid, later)
	[8342] = true, -- Defibrillate-ish engineering? harmless if unused
}

local function GroupChannel()
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
end

function RA:OnCLEU()
	local _, sub, _, sg, sname, _, _, dg, dname, _, _, sid = CombatLogGetCurrentEventInfo()
	if sub ~= "SPELL_RESURRECT" or not RES_SPELLS[sid] then return end
	local me = UnitGUID("player")
	local ch = GroupChannel()
	if sg == me and self.db.announceOut and ch then
		SendChatMessage(format(L["Resurrecting %s"], dname or "?"), ch)
	elseif dg == me and self.db.announceIn then
		S:Print(format(L["Resurrected by %s"], sname or "?"))
	end
end

function RA:Initialize()
	self.db = S.db.profile.rezannouncer
	if not CombatLogGetCurrentEventInfo then return end
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function() RA:OnCLEU() end)
end

function RA:Update()
	self.db = S.db.profile.rezannouncer
end
