-- ExternalBuffs: movable list showing which group members currently carry
-- important external buffs (Misdirection, Power Infusion, Earth Shield,
-- paladin hands, Pain Suppression, Guardian Spirit, Innervate).
-- Same pattern as the soulstone/fear-ward trackers.
local _, ns = ...
local S = ns.S
local L = S.L
local EB = S:NewModule("ExternalBuffs", "externalbuffs")

local ipairs = ipairs
local CreateFrame = CreateFrame
local UnitName, UnitClass = UnitName, UnitClass
local IsInGroup, IsInRaid = IsInGroup, IsInRaid
local GetNumGroupMembers, GetNumSubgroupMembers = GetNumGroupMembers, GetNumSubgroupMembers
local GetTime = GetTime
local ICON, MAX_ROWS = 20, 8

-- spellId -> label key (names come from the aura itself, this is only a set)
local WATCH = {
	[34477] = true,                                     -- misdirection
	[10060] = true,                                     -- power infusion
	[974] = true, [32593] = true, [32594] = true,        -- earth shield
	[49283] = true, [49284] = true,
	[6940] = true, [20729] = true,                       -- hand of sacrifice
	[27147] = true, [27148] = true,
	[1044] = true,                                       -- hand of freedom
	[1022] = true, [5599] = true, [10278] = true,        -- hand of protection
	[1038] = true,                                       -- hand of salvation
	[33206] = true,                                      -- pain suppression
	[47788] = true,                                      -- guardian spirit
	[29166] = true,                                      -- innervate
}

local holder, rows = nil, {}

local function Ensure()
	if holder then return end
	holder = CreateFrame("Frame", "SentinelUIExternalBuffs", UIParent)
	holder:SetSize(150, MAX_ROWS * (ICON + 4))
	S:CreateMover(holder, "externalbuffs", L["External Buffs"], { "TOPLEFT", UIParent, "TOP", -240, -170 }, "externalbuffs")
	for i = 1, MAX_ROWS do
		local r = CreateFrame("Frame", nil, holder)
		r:SetSize(150, ICON)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * (ICON + 4))
		r.tex = r:CreateTexture(nil, "ARTWORK")
		r.tex:SetSize(ICON, ICON)
		r.tex:SetPoint("LEFT")
		r.name = S:FontString(r, 10, "OUTLINE", S.media.unitFont)
		r.name:SetPoint("LEFT", ICON + 5, 3)
		r.name:SetJustifyH("LEFT")
		r.name:SetWidth(110)
		r.buff = S:FontString(r, 9, nil, S.media.unitFont)
		r.buff:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
		r.buff:SetJustifyH("LEFT")
		r.buff:SetWidth(120)
		r.time = S:FontString(r, 9, "OUTLINE", S.media.numberFont)
		r.time:SetPoint("RIGHT")
		r:Hide()
		rows[i] = r
	end
end

local function Scan(unit, list)
	for i = 1, 40 do
		local name, icon, _, _, _, exp, _, _, _, spellId = S.UnitAura(unit, i, "HELPFUL")
		if not name then break end
		if spellId and WATCH[spellId] then
			list[#list + 1] = { unit = unit, buff = name, icon = icon, exp = exp or 0 }
		end
	end
end

function EB:Refresh()
	if not IsInGroup() then for _, r in ipairs(rows) do r:Hide() end return end
	local list = {}
	local raid = IsInRaid()
	local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, n do Scan((raid and "raid" or "party") .. i, list) end
	Scan("player", list)
	for i, r in ipairs(rows) do
		local d = list[i]
		if d then
			local nm = UnitName(d.unit) or "?"
			local _, cls = UnitClass(d.unit)
			local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
			r.tex:SetTexture(d.icon)
			if c then r.name:SetFormattedText("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, nm)
			else r.name:SetText(nm) end
			r.buff:SetText(d.buff)
			local left = (d.exp or 0) - GetTime()
			r.time:SetFormattedText("%ds", left > 0 and left or 0)
			r:Show()
		else
			r:Hide()
		end
	end
end

function EB:Initialize()
	self.db = S.db.profile.externalbuffs
	Ensure()
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() EB:Refresh() end)
	self:RegisterEvent("UNIT_AURA", function(_, _, unit)
		if unit and (unit == "player" or unit:find("^party") or unit:find("^raid")) then EB:Refresh() end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() EB:Refresh() end)
end

function EB:Update()
	self.db = S.db.profile.externalbuffs
	if holder then holder:SetShown(self.db.enable ~= false) end
end
