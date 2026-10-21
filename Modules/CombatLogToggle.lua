-- CombatLogToggle: starts Blizzard's combat log writer automatically when
-- entering a raid (or dungeon, per option) so logs land in Logs/ for tools
-- like WarcraftLogs — and stops it when leaving.
local _, ns = ...
local S = ns.S
local L = S.L
local CL = S:NewModule("CombatLogToggle", "combatlog")

function CL:Check()
	if not LoggingCombat then return end
	local inInst, itype = IsInInstance()
	local want = inInst and (itype == "raid" or (itype == "party" and self.db.dungeons))
	local logging = LoggingCombat()
	if want and not logging then
		LoggingCombat(true)
		self.autoStarted = true
		if self.db.chatNote ~= false then S:Print(L["Combat log enabled"]) end
	elseif not want and logging and self.autoStarted then
		LoggingCombat(false)
		self.autoStarted = nil
		if self.db.chatNote ~= false then S:Print(L["Combat log disabled"]) end
	end
end

function CL:Initialize()
	self.db = S.db.profile.combatlog
	if not LoggingCombat then return end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() CL:Check() end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() CL:Check() end)
	self:Check()
end

function CL:Update()
	self.db = S.db.profile.combatlog
	self:Check()
end
