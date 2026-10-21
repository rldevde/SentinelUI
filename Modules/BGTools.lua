-- BGTools: Warsong flag carrier tracking. Detects the flag aura on
-- nameplates/friendly units, shows both carriers on a movable frame and
-- announces pickups/drops in chat.
local _, ns = ...
local S = ns.S
local L = S.L
local BG = S:NewModule("BGTools", "bgtools")

local CreateFrame = CreateFrame
local UnitName = UnitName
local UnitClass = UnitClass
local UnitAura = S.UnitAura
local IsInInstance = IsInInstance
local FLAG_ALLY, FLAG_HORDE = 23333, 23335
local GetAuraByID = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID

local function FlagOf(unit)
	if GetAuraByID then
		if GetAuraByID(unit, FLAG_ALLY, "HELPFUL") then return "ally" end
		if GetAuraByID(unit, FLAG_HORDE, "HELPFUL") then return "horde" end
	elseif UnitAura then
		for i = 1, 40 do
			local sid = select(10, UnitAura(unit, i, "HELPFUL"))
			if not sid then break end
			if sid == FLAG_ALLY then return "ally" end
			if sid == FLAG_HORDE then return "horde" end
		end
	end
end

function BG:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIBGTools", UIParent)
	f:SetSize(220, 44)
	f:SetPoint("TOP", UIParent, "TOP", 0, -120)
	S:CreateBackdrop(f, "Default")
	f.title = S:FontString(f, 10, "OUTLINE", S.media.unitFont)
	f.title:SetPoint("TOP", 0, -4)
	f.title:SetText(L["Flag Carriers"])
	f.ally = S:FontString(f, 10, nil, S.media.unitFont)
	f.ally:SetPoint("TOPLEFT", 8, -18)
	f.horde = S:FontString(f, 10, nil, S.media.unitFont)
	f.horde:SetPoint("TOPLEFT", 8, -30)
	S:CreateMover(f, "BGTools", L["Flag Carriers"])
	f:Hide()
	self.frame = f
end

local function ColoredName(unit)
	local name = UnitName(unit) or "?"
	local _, class = UnitClass(unit)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
	return name
end

function BG:Refresh()
	local a, h
	for unit, flag in pairs(self.units) do
		if flag == "ally" then a = unit elseif flag == "horde" then h = unit end
	end
	self.frame.ally:SetFormattedText("|cff69ccf0%s:|r %s", L["Alliance flag"], a and ColoredName(a) or L["at base"])
	self.frame.horde:SetFormattedText("|cffff5a5a%s:|r %s", L["Horde flag"], h and ColoredName(h) or L["at base"])
end

function BG:ScanUnit(unit)
	if self.units[unit] == FlagOf(unit) then return end
	self.units[unit] = FlagOf(unit)
	if self.units[unit] and self.db.announce ~= false then
		S:Print(format(self.units[unit] == "ally" and L["Alliance flag carried by %s"] or L["Horde flag carried by %s"], ColoredName(unit)))
	end
	self:Refresh()
end

function BG:SetActive(on)
	self.frame:SetShown(on and self.db.enable ~= false)
	if not on then wipe(self.units) end
	if self.frame:IsShown() then self:Refresh() end
end

function BG:Initialize()
	self.db = S.db.profile.bgtools
	self.units = {}
	self:BuildFrame()
	self:RegisterEvent("UNIT_AURA", function(_, _, unit)
		if unit and (unit:match("^nameplate") or unit:match("^raid%d+$") or unit:match("^party%d+$")) then
			BG:ScanUnit(unit)
		end
	end)
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, _, unit)
		if self.units[unit] then self.units[unit] = nil BG:Refresh() end
	end)
	local vis = function() BG:SetActive(select(2, IsInInstance()) == "pvp") end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", vis)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", vis)
	vis()
end

function BG:Update()
	self.db = S.db.profile.bgtools
	self:SetActive(select(2, IsInInstance()) == "pvp")
end
