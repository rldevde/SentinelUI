-- SoulstoneTracker: shows which raid/party members currently carry a
-- soulstone, with remaining duration. Scans group auras for the
-- "Soulstone Resurrection" buff; used stones disappear on their own.
local _, ns = ...
local S = ns.S
local L = S.L
local ST = S:NewModule("SoulstoneTracker", "soulstonetracker")

local ipairs = ipairs
local CreateFrame = CreateFrame
local UnitName, UnitClass = UnitName, UnitClass
local IsInGroup = IsInGroup
local ICON, MAX = 22, 5
local SS = { [20707] = true, [47883] = true, [47884] = true } -- soulstone resurrection aura

local holder, icons = nil, {}

local function Ensure()
	if holder then return end
	holder = CreateFrame("Frame", "SentinelUISoulstones", UIParent)
	holder:SetSize(1, ICON)
	S:CreateMover(holder, "soulstones", L["Soulstones"], { "TOP", UIParent, "TOP", -180, -170 }, "soulstonetracker")
	for i = 1, MAX do
		local b = CreateFrame("Frame", nil, holder)
		b:SetSize(ICON, ICON)
		b:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (ICON + 60), 0)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.name = S:FontString(b, 9, "OUTLINE", S.media.unitFont)
		b.name:SetPoint("LEFT", b, "RIGHT", 3, 0)
		b.name:SetJustifyH("LEFT")
		b.name:SetWidth(56)
		b.time = S:FontString(b, 9, "OUTLINE", S.media.numberFont)
		b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
		b:Hide()
		icons[i] = b
	end
end

local function Scan(unit, list)
	for i = 1, 40 do
		local name, icon, _, _, _, exp, _, _, _, spellId = S.UnitAura(unit, i, "HELPFUL")
		if not name then break end
		if spellId and SS[spellId] then
			list[#list + 1] = { unit = unit, icon = icon, exp = exp or 0 }
		end
	end
end

function ST:Refresh()
	if not IsInGroup() then for _, b in ipairs(icons) do b:Hide() end return end
	local list = {}
	local raid = IsInRaid()
	local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, n do Scan((raid and "raid" or "party") .. i, list) end
	Scan("player", list)
	for i, b in ipairs(icons) do
		local d = list[i]
		if d then
			local nm = UnitName(d.unit) or "?"
			local _, cls = UnitClass(d.unit)
			local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
			b.tex:SetTexture(d.icon)
			if c then b.name:SetFormattedText("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, nm)
			else b.name:SetText(nm) end
			local left = d.exp - GetTime()
			b.time:SetFormattedText("%dm", left > 0 and left / 60 or 0)
			b:Show()
		else
			b:Hide()
		end
	end
end

function ST:Initialize()
	self.db = S.db.profile.soulstonetracker
	Ensure()
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() ST:Refresh() end)
	self:RegisterEvent("UNIT_AURA", function(_, unit)
		if unit and (unit == "player" or unit:find("^party") or unit:find("^raid")) then ST:Refresh() end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() ST:Refresh() end)
	-- on TBC soulstones are carried items, not auras — the aura scan only
	-- works on Wrath+. Catch the stone's consumption from the combat log so
	-- the group at least sees when a stone was spent.
	if CombatLogGetCurrentEventInfo then
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
			local _, sub, _, _, sName = CombatLogGetCurrentEventInfo()
			local spellId = select(12, CombatLogGetCurrentEventInfo())
			if (sub == "SPELL_RESURRECT" or sub == "SPELL_CAST_SUCCESS") and spellId and SS[spellId] and sName then
				S:Print(format(L["%s used a soulstone"], sName))
				ST:Refresh()
			end
		end)
	end
end

function ST:Update()
	self.db = S.db.profile.soulstonetracker
	if holder then holder:SetShown(self.db.enable ~= false) end
end
