-- KeywordInvite: auto-invite guild members and friends who whisper a
-- trigger keyword ("inv", "invite", "einladen" — configurable list).
local _, ns = ...
local S = ns.S
local L = S.L
local KI = S:NewModule("KeywordInvite", "keywordinvite")

local lower, trim = string.lower, strtrim
local gsub = gsub

local DEFAULT_WORDS = { "inv", "invite", "einladen", "einladung" }

local function Keywords()
	if KI.db.keywords and KI.db.keywords ~= "" then
		local out = {}
		for w in gmatch(KI.db.keywords, "[^,%s]+") do out[lower(w)] = true end
		if next(out) then return out end
	end
	local out = {}
	for _, w in ipairs(DEFAULT_WORDS) do out[w] = true end
	return out
end

local function Allowed(name)
	local plain = (gsub(name or "", "%-.*", ""))
	if KI.db.allowGuild ~= false and IsInGuild and IsInGuild() and GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() do
			local n = GetGuildRosterInfo(i)
			if n and (gsub(n, "%-.*", "")) == plain then return true end
		end
	end
	if KI.db.allowFriends ~= false and C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() do
			local fi = C_FriendList.GetFriendInfoByIndex(i)
			if fi and fi.name == plain then return true end
		end
	end
	return KI.db.allowAll and true or false
end

function KI:Initialize()
	self.db = S.db.profile.keywordinvite
	self:RegisterEvent("CHAT_MSG_WHISPER", function(_, _, msg, sender)
		if not sender or sender == S.myName or not msg then return end
		local words = Keywords()
		local m = lower(trim(msg))
		if not words[m] and not words[m:gsub("^!", "")] then return end
		if not Allowed(sender) then
			if KI.db.deny ~= false then
				SendChatMessage(L["Sorry, invites are limited to guild and friends."], "WHISPER", nil, sender)
			end
			return
		end
		if InCombatLockdown() then return end
		if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(sender)
		elseif InviteUnit then InviteUnit(sender) end
		S:Print(format(L["Invited %s (keyword)"], sender))
	end)
end

function KI:Update()
	self.db = S.db.profile.keywordinvite
end
