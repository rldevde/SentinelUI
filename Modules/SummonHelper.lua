-- SummonHelper (warlock): announces Ritual of Summoning casts to the group -
-- who is being summoned, how many clicks are needed and when the stone is
-- up or the cast was interrupted.
local _, ns = ...
local S = ns.S
local L = S.L
local SH = S:NewModule("SummonHelper", "summonhelper")

local CreateFrame = CreateFrame
local SUMMON_SPELLS = { [698] = true } -- Ritual of Summoning

local function Target()
	if UnitExists("target") and (UnitIsPlayer("target") or UnitPlayerControlled("target")) then
		local n, r = UnitName("target")
		if n then return r and r ~= "" and (n .. "-" .. r) or n end
	end
end

function SH:Announce(msg)
	local ch = S.GroupChannel()
	if ch and self.db.announce ~= false then
		SendChatMessage(msg, ch)
	else
		S:Print(msg)
	end
end

function SH:CastStart(spellId, castGUID)
	local name = Target() or L["target"]
	self.targetName = name
	self.casting = true
	self.castGUID = castGUID
	local clicks = math.max(0, (self.db.clicksNeeded or 2))
	local msg = format(L["Summoning %s - %d clicks needed!"], name, clicks)
	local canWarn = IsInRaid() and ((IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer()))
	if self.db.announceWarn ~= false and canWarn then
		SendChatMessage(msg, "RAID_WARNING") -- instead of (not in addition to) the raid line
	else
		self:Announce(msg)
	end
end

function SH:CastDone(spellId)
	if not self.casting then return end
	self.casting = false
	self:Announce(format(L["Summoning %s - stone is up!"], self.targetName or L["target"]))
end

function SH:CastStopped(spellId)
	if not self.casting then return end
	self.casting = false
	self:Announce(format(L["Summon interrupted - %s still needs a stone!"], self.targetName or L["target"]))
end

function SH:Initialize()
	self.db = S.db.profile.summonhelper
	if S.myClass ~= "WARLOCK" then return end
	self:RegisterEvent("UNIT_SPELLCAST_START", function(_, _, unit, castGUID, spellId)
		if unit == "player" and SUMMON_SPELLS[spellId] then SH:CastStart(spellId, castGUID) end
	end)
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, castGUID, spellId)
		if unit == "player" and SUMMON_SPELLS[spellId] then SH:CastDone(spellId) end
	end)
	for _, ev in ipairs({ "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET" }) do
		self:RegisterEvent(ev, function(_, _, unit, castGUID, spellId)
			-- a failed re-click while the real cast runs carries a different castGUID
			if unit == "player" and SUMMON_SPELLS[spellId] and not (SH.castGUID and castGUID and castGUID ~= SH.castGUID) then
				SH:CastStopped(spellId)
			end
		end)
	end
end

function SH:Update()
	self.db = S.db.profile.summonhelper
end
