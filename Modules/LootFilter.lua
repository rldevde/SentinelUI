-- LootFilter: hides loot spam in chat. Poor-quality drops and solo coin
-- messages get filtered via ChatFrame_AddMessageEventFilter; the quality
-- threshold is configurable (hide anything below it).
local _, ns = ...
local S = ns.S
local L = S.L
local LF = S:NewModule("LootFilter", "lootfilter")

local function Filter(_, _, msg)
	if LF.db.enable == false then return end
	local link = msg and msg:match("|Hitem:.-|h%[.-%]|h")
	if not link then
		-- messages without an item link are coin/loot system text
		return LF.db.hideCoin or nil
	end
	local q = GetItemInfo and select(3, GetItemInfo(link))
	if not q then
		-- item not cached yet: fall back to the link colour. ITEM_QUALITY_COLORS.hex
		-- carries a "|c" prefix, the link capture does not, so strip it before comparing
		local quality = link:match("|c(%x%x%x%x%x%x%x%x)")
		if not quality then return end
		quality = quality:upper()
		for i = 0, 7 do
			local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[i]
			local hex = c and c.hex and (c.hex:gsub("^|[cC]", "")):upper()
			if hex and hex == quality then q = i break end
		end
	end
	if q then return q < (LF.db.minQuality or 0) end
end

function LF:Initialize()
	self.db = S.db.profile.lootfilter
	if ChatFrame_AddMessageEventFilter then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_LOOT", Filter)
		-- coin messages arrive on CHAT_MSG_MONEY; hideCoin never saw them before
		ChatFrame_AddMessageEventFilter("CHAT_MSG_MONEY", Filter)
	end
end

function LF:Update()
	self.db = S.db.profile.lootfilter
end
