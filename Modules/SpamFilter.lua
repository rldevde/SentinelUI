-- SpamFilter: blocks gold-seller / advertising spam in whispers and public
-- channels via keyword patterns. Friends, guildies and group members always
-- pass through. Optional chat note counts blocked messages.
local _, ns = ...
local S = ns.S
local L = S.L
local SF = S:NewModule("SpamFilter", "spamfilter")

-- a message is spam when it carries a link AND a sales word, or two distinct
-- sales words. A single "gold"/"boost"/".de" no longer kills normal chat.
local LINKS = { "www%.", "http", "%a%.com", "%a%.net", "%a%.cn", "%a%.de%f[%A]" }
local SALES = {
	"g%s?o%s?l%s?d", "powerlevel", "power%-level", "boost",
	"mmo", "igxe", "mmoga", "g2g", "buy now", "kaufen",
}
local CHANNEL_EVENTS = {
	CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_WHISPER = true,
}

local function IsKnown(name)
	if not name then return false end
	local plain = (name:gsub("%-.*", ""))
	if IsInGuild and IsInGuild() and GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() do
			local n = GetGuildRosterInfo(i)
			if n and (n:gsub("%-.*", "")) == plain then return true end
		end
	end
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() do
			local fi = C_FriendList.GetFriendInfoByIndex(i)
			if fi and fi.name == plain then return true end
		end
	end
	if IsInGroup() then
		for i = 1, GetNumGroupMembers() do
			local u = (IsInRaid() and "raid" or "party") .. i
			if UnitName(u) == plain then return true end
		end
	end
	return false
end

local function Filter(_, event, msg, sender)
	if SF.db.enable == false then return end
	if event ~= "CHAT_MSG_WHISPER" and SF.db.channels == false then return end
	if sender and (sender:gsub("%-.*", "")) == S.myName then return end -- never hide your own lines
	if IsKnown(sender) then return end
	if S.IsSecret and S.IsSecret(msg) then return end
	local m = (msg or ""):lower()
	local link, sales = false, 0
	for _, p in ipairs(LINKS) do if m:find(p) then link = true break end end
	for _, p in ipairs(SALES) do if m:find(p) then sales = sales + 1 end end
	if (link and sales >= 1) or sales >= 2 then
		SF.blocked = (SF.blocked or 0) + 1
		if SF.db.chatNote then
			S:Print(format(L["Blocked spam from %s"], sender or "?"))
		end
		return true
	end
end

function SF:Initialize()
	self.db = S.db.profile.spamfilter
	for ev in pairs(CHANNEL_EVENTS) do
		if ChatFrame_AddMessageEventFilter then
			ChatFrame_AddMessageEventFilter(ev, Filter)
		end
	end
end

function SF:Update()
	self.db = S.db.profile.spamfilter
end
