-- RankReminder: after leveling, action bars often still hold outdated spell
-- ranks. Scans the spellbook for each spell's max rank, then compares every
-- spell placed on an action button and warns once per spell per session.
local _, ns = ...
local S = ns.S
local L = S.L
local RR = S:NewModule("RankReminder", "rankreminder")

local pairs, tonumber = pairs, tonumber
local format = format
local GetActionInfo = GetActionInfo

local warned = {}
local lastScan = 0

local function BookName(i)
	if GetSpellBookItemName then return GetSpellBookItemName(i, "spell") end
	if GetSpellName then return GetSpellName(i, "spell") end
end

-- "Blitzheilung (Rang 3)" -> "Blitzheilung", 3
local function SplitRank(name, rankText)
	local base = name
	local rank = rankText and tonumber(rankText:match("(%d+)")) or 0
	if rank == 0 then
		local b, r = (name or ""):match("^(.-)%s*%((%d+)%)%s*$")
			or (name or ""):match("^(.-)%s*%(.-%s(%d+)%)%s*$")
		if b and b ~= "" then base, rank = b, tonumber(r) or 0 end
	end
	return base, rank
end

local function MaxRanks()
	local maxRank = {}
	local tabs = (GetNumSpellTabs and GetNumSpellTabs()) or 0
	for tab = 1, tabs do
		local _, _, offset, num = GetSpellTabInfo(tab)
		for i = offset + 1, offset + (num or 0) do
			local name, rankText = BookName(i)
			if name and not (S.IsSecret and S.IsSecret(name)) then
				local base, rank = SplitRank(name, rankText)
				if not maxRank[base] or rank > maxRank[base] then
					maxRank[base] = rank
				end
			end
		end
	end
	return maxRank
end

function RR:Scan()
	if not self.db.enable then return end
	if GetTime() - lastScan < 30 then return end
	lastScan = GetTime()
	local maxRank = MaxRanks()
	for slot = 1, 120 do
		local atype, id = GetActionInfo(slot)
		if atype == "spell" and id then
			local name, rankText
			if GetSpellInfo then
				name, rankText = GetSpellInfo(id)
			end
			if name and not (S.IsSecret and S.IsSecret(name)) then
				local base, rank = SplitRank(name, rankText)
				local max = maxRank[base]
				if max and max > 0 and rank > 0 and rank < max
					and not warned[base] then
					warned[base] = true
					S:Print(format("|cffff8040" .. L["Outdated rank: %s (Rank %d of %d) on the action bar"] .. "|r",
						base, rank, max))
				end
			end
		end
	end
end

function RR:Initialize()
	self.db = S.db.profile.rankreminder
	if not self.db.enable then return end
	self:RegisterEvent("SPELLS_CHANGED", "Scan")
	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", "Scan")
	self:RegisterEvent("PLAYER_LEVEL_UP", function() wipe(warned) self:Scan() end)
end

function RR:Update()
	self.db = S.db.profile.rankreminder
end
