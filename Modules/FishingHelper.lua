-- FishingHelper: "Fishing" data text. Shows the remaining fishing-lure time
-- on the weapon (temporary enchant) and the current fishing skill; tooltip
-- lists session skill-ups. Registers as data text only when enabled.
local _, ns = ...
local S = ns.S
local L = S.L
local FH = S:NewModule("FishingHelper", "fishinghelper")

local floor, format = math.floor, format

local ups = 0

local FISHING_NAMES = { Fishing = true, Angeln = true, ["Pêche"] = true, Pesca = true, ["Рыбная ловля"] = true }
local function FishingSkillFromList()
	if not (GetNumSkillLines and GetSkillLineInfo) then return end
	local localized = GetSpellInfo and GetSpellInfo(7620) -- Fishing, localized by the client
	for i = 1, GetNumSkillLines() do
		local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
		if name and not isHeader and not (S.IsSecret and S.IsSecret(name))
			and (name == localized or FISHING_NAMES[name]) then
			return rank, maxRank
		end
	end
end

local function FishingSkill()
	if not GetProfessions or not GetProfessionInfo then return FishingSkillFromList() end
	for _, idx in ipairs({ GetProfessions() }) do
		local name, _, _, rank, maxRank = GetProfessionInfo(idx)
		if name and not (S.IsSecret and S.IsSecret(name))
			and (name == "Fishing" or name == "Angeln" or name == "Pêche"
				or name == "Pesca" or name == "Рыбная ловля") then
			return rank, maxRank
		end
	end
end

local function LureLeft()
	if not GetWeaponEnchantInfo then return 0 end
	local has, expire = GetWeaponEnchantInfo()
	if has and expire and expire > 0 then return floor(expire / 1000) end
	return 0
end

local function Text()
	local rank, maxR = FishingSkill()
	local lure = LureLeft()
	local parts = {}
	if rank then parts[#parts + 1] = format("%s %d/%d", L["Fishing"], rank, maxR or 0) end
	if lure > 0 then parts[#parts + 1] = format("%s %d:%02d", L["Lure"], floor(lure / 60), lure % 60) end
	return #parts > 0 and table.concat(parts, "  ") or L["Fishing"]
end

function FH:Initialize()
	self.db = S.db.profile.fishinghelper
	local DT = S:GetModule("DataTexts")
	if not (DT and DT.Register) then return end
	DT:Register("Fishing", {
		name = "Fishing",
		update = function(slot) slot.text:SetText(Text()) end,
		interval = 5,
		enter = function(slot)
			GameTooltip:SetOwner(slot, "ANCHOR_TOP")
			GameTooltip:AddLine(L["Fishing"])
			local rank, maxR = FishingSkill()
			if rank then GameTooltip:AddDoubleLine(L["Skill"], rank .. "/" .. (maxR or 0), 1, 1, 1, 1, 1, 1) end
			local lure = LureLeft()
			GameTooltip:AddDoubleLine(L["Lure"], lure > 0 and format("%d:%02d", floor(lure / 60), lure % 60) or "-", 1, 1, 1, 1, 1, 1)
			GameTooltip:AddDoubleLine(L["Skill-ups this session"], ups, 1, 1, 1, 1, 1, 1)
			GameTooltip:Show()
		end,
	})
	self:RegisterEvent("CHAT_MSG_SKILL", function(_, _, msg)
		-- "Your skill in Fishing has increased to 226."
		if type(msg) ~= "string" or (S.IsSecret and S.IsSecret(msg)) then return end
		if msg:find("Fishing") or msg:find("Angeln") or msg:find("Pêche")
			or msg:find("Pesca") or msg:find("Рыбная") then
			ups = ups + 1
		end
	end)
end

function FH:Update()
	self.db = S.db.profile.fishinghelper
end
