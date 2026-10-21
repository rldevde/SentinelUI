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
	local quality = link:match("|c(%x%x%x%x%x%x%x%x)")
	if not quality then return end
	-- hex color -> quality via ITEM_QUALITY_COLORS
	for q = 0, 7 do
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
		if c and quality:upper() == c.hex:upper() then
			return q < (LF.db.minQuality or 0)
		end
	end
end

function LF:Initialize()
	self.db = S.db.profile.lootfilter
	if ChatFrame_AddMessageEventFilter then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_LOOT", Filter)
	end
end

function LF:Update()
	self.db = S.db.profile.lootfilter
end
