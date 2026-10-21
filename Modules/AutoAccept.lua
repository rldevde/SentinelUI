-- AutoAccept: optionally auto-accepts resurrections and summon dialogs that
-- come from your own group members. Both toggled separately; only fires while
-- out of combat and never for strangers.
local _, ns = ...
local S = ns.S
local L = S.L
local AA = S:NewModule("AutoAccept", "autoaccept")

local function FromGroup(name)
	if not name then return false end
	name = name:gsub("%-.*", "")
	if name == S.myName then return true end
	for i = 1, 4 do
		local n = UnitName("party" .. i)
		if n and n:gsub("%-.*", "") == name then return true end
	end
	for i = 1, 40 do
		local n = UnitName("raid" .. i)
		if n and n:gsub("%-.*", "") == name then return true end
	end
	if IsInGuild and IsInGuild() then
		local n = GetNumGuildMembers and GetNumGuildMembers() or 0
		for i = 1, n do
			local gname = GetGuildRosterInfo(i)
			if gname and gname:gsub("%-.*", "") == name then return true end
		end
	end
	return false
end

function AA:Initialize()
	self.db = S.db.profile.autoaccept
	self:RegisterEvent("RESURRECT_REQUEST", function(_, _, inviter)
		if InCombatLockdown() or AA.db.resurrect == false then return end
		if FromGroup(inviter) then
			if AcceptResurrect then AcceptResurrect() end
			if AA.db.chatNote ~= false then S:Print(format(L["Auto-accepted resurrect from %s"], inviter or "?")) end
		end
	end)
	self:RegisterEvent("CONFIRM_SUMMON", function()
		if InCombatLockdown() or AA.db.summon == false then return end
		local inviter = GetSummonConfirmSummoner and GetSummonConfirmSummoner()
		if FromGroup(inviter) then
			-- slight delay so the stone actually clicks through
			C_Timer.After(0.5, function()
				if GetSummonConfirmTimeLeft and GetSummonConfirmTimeLeft() > 0 then
					if AcceptSummon then AcceptSummon() end
					if AA.db.chatNote ~= false then S:Print(format(L["Auto-accepted summon from %s"], inviter or "?")) end
				end
			end)
		end
	end)
	-- auto-confirm the summon/invite popups when open
	self:RegisterEvent("GROUP_INVITE_CONFIRMATION", function()
		if InCombatLockdown() or AA.db.invites == false then return end
		if AcceptGroup then AcceptGroup() end
	end)
end

function AA:Update()
	self.db = S.db.profile.autoaccept
end
