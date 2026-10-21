-- BanishTimer (warlock): icon + remaining duration while your Banish sits
-- on the target or focus. Keeps re-banish timing visible without digging
-- through target debuffs.
local _, ns = ...
local S = ns.S
local L = S.L
local BT = S:NewModule("BanishTimer", "banishtimer")

local CreateFrame = CreateFrame
local UnitAura, UnitExists = UnitAura, UnitExists
local GetTime = GetTime
local BANISH = { [710] = true, [18647] = true }
local ICON = 30

local frame
local function Ensure()
	if frame then return end
	frame = CreateFrame("Frame", "SentinelUIBanishTimer", UIParent)
	frame:SetSize(ICON, ICON)
	S:CreateMover(frame, "banishtimer", L["Banish Timer"], { "CENTER", UIParent, "CENTER", 200, -60 }, "banishtimer")
	frame.tex = frame:CreateTexture(nil, "ARTWORK")
	frame.tex:SetAllPoints()
	frame.time = S:FontString(frame, 12, "OUTLINE", S.media.numberFont)
	frame.time:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	frame:Hide()
end

local function FindBanish(unit)
	for i = 1, 40 do
		local name, icon, _, _, _, exp, src, _, _, spellId = S.UnitAura(unit, i, "HARMFUL")
		if not name then break end
		if spellId and BANISH[spellId] and src and UnitIsUnit(src, "player") then
			return icon, exp
		end
	end
end

function BT:Refresh()
	local icon, exp = FindBanish("target")
	if not icon then icon, exp = FindBanish("focus") end
	if icon then
		frame.tex:SetTexture(icon)
		frame.time:SetFormattedText("%.0fs", math.max(0, (exp or 0) - GetTime()))
		frame:Show()
	else
		frame:Hide()
	end
end

function BT:Initialize()
	if S.myClass ~= "WARLOCK" then return end
	self.db = S.db.profile.banishtimer
	Ensure()
	self:RegisterEvent("UNIT_AURA", function(_, unit)
		if unit == "target" or unit == "focus" then BT:Refresh() end
	end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() BT:Refresh() end)
	if not S.isTBC then -- TBC clients have no focus unit/event
		self:RegisterEvent("PLAYER_FOCUS_CHANGED", function() BT:Refresh() end)
	end
	frame:SetScript("OnUpdate", function(_, el)
		frame.e = (frame.e or 0) + el
		if frame.e > 0.25 then frame.e = 0 BT:Refresh() end
	end)
end

function BT:Update()
	self.db = S.db.profile.banishtimer
	if frame then frame:SetShown(self.db.enable ~= false) end
end
