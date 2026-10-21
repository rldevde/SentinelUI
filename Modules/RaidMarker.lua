-- RaidMarker: movable strip with the 8 raid target icons plus a clear
-- button. Click an icon to mark the current target. Visible whenever the
-- player can mark (group/raid or solo with the option on).
local _, ns = ...
local S = ns.S
local L = S.L
local RM = S:NewModule("RaidMarker", "raidmarker")

local CreateFrame = CreateFrame
local SetMark = SetRaidTarget or SetRaidTargetIcon
local NUM_ICONS = 8

function RM:CanMark()
	return IsInRaid() or IsInGroup() or self.db.alwaysShow == true
end

function RM:BuildBar()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIRaidMarker", UIParent)
	f:SetSize((NUM_ICONS + 1) * 26 + 8, 30)
	f:SetPoint("TOP", UIParent, "TOP", 0, -140)
	f:SetFrameStrata("MEDIUM")
	S:CreateBackdrop(f, "Default")
	f.btns = {}
	for i = 1, NUM_ICONS do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(24, 24)
		b:SetPoint("LEFT", 4 + (i - 1) * 26, 0)
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
		b:SetScript("OnClick", function()
			if UnitExists("target") and SetMark then SetMark("target", i) end
		end)
		b:SetScript("OnEnter", function(b2) b2:SetAlpha(0.7) end)
		b:SetScript("OnLeave", function(b2) b2:SetAlpha(1) end)
		f.btns[i] = b
	end
	local clear = CreateFrame("Button", nil, f)
	clear:SetSize(24, 24)
	clear:SetPoint("LEFT", 4 + NUM_ICONS * 26, 0)
	clear.text = S:FontString(clear, 13, "OUTLINE")
	clear.text:SetPoint("CENTER")
	clear.text:SetText("X")
	clear.text:SetTextColor(1, 0.3, 0.3)
	clear:SetScript("OnClick", function()
		if UnitExists("target") and SetMark then SetMark("target", 0) end
	end)
	f:Hide()
	S:CreateMover(f, "RaidMarker", L["Raid Marker"], { "TOP", UIParent, "TOP", 0, -140 }, "raidmarker")
	self.frame = f
end

function RM:UpdateVisibility()
	if not self.frame then return end
	if self.db.enable == false then self.frame:Hide() return end
	if self:CanMark() then self.frame:Show() else self.frame:Hide() end
end

function RM:Initialize()
	self.db = S.db.profile.raidmarker
	self:BuildBar()
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() RM:UpdateVisibility() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() RM:UpdateVisibility() end)
	self:UpdateVisibility()
end

function RM:Update()
	self.db = S.db.profile.raidmarker
	self:UpdateVisibility()
end
