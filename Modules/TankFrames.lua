-- TankFrames: main tank / off-tank / assist list built from the raid roster
-- roles (MAINTANK / MAINASSIST flags set via the raid UI or SetPartyAssignment).
-- Each row shows the tank's name+HP and their current target's name+HP.
local _, ns = ...
local S = ns.S
local L = S.L
local TF = S:NewModule("TankFrames", "tankframes")

local CreateFrame = CreateFrame
local GetRaidRosterInfo = GetRaidRosterInfo
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local UnitName, UnitHealth, UnitHealthMax = UnitName, UnitHealth, UnitHealthMax
local UnitExists, UnitIsUnit, UnitClass = UnitExists, UnitIsUnit, UnitClass
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local UnitIsConnected = UnitIsConnected
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local ROW_H = 20
local TGT_H = 12
local PAD = 3
local MAX_ROWS = 6

function TF:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUITankFrames", UIParent)
	f:SetSize(180, 40)
	f:SetPoint("LEFT", UIParent, "LEFT", 12, 0)
	f:SetFrameStrata("LOW")
	S:SetTemplate(f, "Transparent")
	local title = S:FontString(f, 10, "OUTLINE", S.media.unitFont)
	title:SetPoint("TOPLEFT", 4, -2)
	title:SetText(L["Tanks"])
	title:SetTextColor(0.9, 0.8, 0.4)
	f.rows = {}
	for i = 1, MAX_ROWS do
		local r = CreateFrame("Frame", nil, f)
		r:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -14 - (i - 1) * (ROW_H + TGT_H + PAD * 3))
		r:SetSize(176, ROW_H + TGT_H + PAD)
		-- tank row
		local icon = r:CreateTexture(nil, "OVERLAY")
		icon:SetSize(16, 16)
		icon:SetPoint("TOPLEFT", 2, 0)
		icon:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
		local bar = S:CreateStatusBar(r)
		bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 3, -1)
		bar:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -1)
		bar:SetHeight(ROW_H - 2)
		local name = S:FontString(bar.suiTextOverlay, 10, "OUTLINE", S.media.unitFont)
		name:SetPoint("LEFT", 4, 0)
		local role = S:FontString(bar.suiTextOverlay, 9, "OUTLINE", S.media.unitFont)
		role:SetPoint("RIGHT", -4, 0)
		role:SetTextColor(1, 0.8, 0.3)
		-- target sub-row
		local tbar = S:CreateStatusBar(r)
		tbar:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 2, -PAD)
		tbar:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -ROW_H)
		tbar:SetHeight(TGT_H)
		tbar:SetStatusBarColor(0.6, 0.15, 0.15)
		local tname = S:FontString(tbar.suiTextOverlay, 9, "OUTLINE", S.media.unitFont)
		tname:SetPoint("LEFT", 4, 0)
		r.icon, r.bar, r.name, r.role = icon, bar, name, role
		r.tbar, r.tname = tbar, tname
		r:Hide()
		f.rows[i] = r
	end
	f:Hide()
	S:CreateMover(f, "tankframes", L["Tank Frames"], { "LEFT", UIParent, "LEFT", 12, 0 }, "tankframes")
	self.frame = f
end

function TF:Refresh()
	if not self.db.enable or not IsInGroup() then
		if self.frame then self.frame:Hide() end
		return
	end
	self:BuildFrame()
	local tanks = {}
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	for i = 1, n do
		local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
		local name, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
		local u = IsInRaid() and unit or (name and UnitExists(unit) and UnitName(unit) == name and unit or nil)
		if IsInRaid() and role and (role == "MAINTANK" or role == "MAINASSIST") then
			tanks[#tanks + 1] = { unit = "raid" .. i, role = role }
		elseif not IsInRaid() and GetPartyAssignment then
			for _, want in ipairs({ "MAINTANK", "MAINASSIST" }) do
				local ok, r = pcall(GetPartyAssignment, want, "party" .. i)
				if ok and r and not tanks[want] then
					tanks[#tanks + 1] = { unit = "party" .. i, role = want }
					tanks[want] = true
				end
			end
		end
	end
	local shown = 0
	for i = 1, MAX_ROWS do
		local r = self.frame.rows[i]
		local t = tanks[i]
		if t and UnitExists(t.unit) then
			shown = shown + 1
			local nm = UnitName(t.unit) or "?"
			local hp, max = UnitHealth(t.unit), UnitHealthMax(t.unit)
			r.bar:SetMinMaxValues(0, max > 0 and max or 1)
			r.bar:SetValue(hp)
			local _, cls = UnitClass(t.unit)
			local cc = cls and RAID_CLASS_COLORS[cls]
			if cc then r.bar:SetStatusBarColor(cc.r, cc.g, cc.b) else r.bar:SetStatusBarColor(0.3, 0.3, 0.5) end
			r.name:SetText(nm)
			r.role:SetText(t.role == "MAINTANK" and "MT" or "OT")
			r.icon:Hide() -- could show raid icon if set
			local tu = t.unit .. "target"
			if UnitExists(tu) then
				local thp, tmax = UnitHealth(tu), UnitHealthMax(tu)
				r.tbar:SetMinMaxValues(0, tmax > 0 and tmax or 1)
				r.tbar:SetValue(thp)
				r.tbar:Show()
				r.tname:SetText("→ " .. (UnitName(tu) or "?"))
			else
				r.tbar:Hide()
				r.tname:SetText("")
			end
			r:Show()
		else
			r:Hide()
		end
	end
	self.frame:SetShown(shown > 0)
end

local function SetTank(role, name)
	if not name or name == "" then
		S:Print((L["Usage"] or "Usage") .. ": /smt Name")
		return
	end
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	for i = 1, n do
		local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
		local un = UnitExists(unit) and Ambiguate(UnitName(unit), "short")
		if un and un:lower() == Ambiguate(name, "short"):lower() then
			if SetPartyAssignment then
				local ok = pcall(SetPartyAssignment, role, unit)
				S:Print(ok and un .. " -> " .. role or (L["Assignment failed (need lead/assist?)"] or "Assignment failed (need lead/assist?)"))
			else
				S:Print(L["No SetPartyAssignment on this client"] or "No SetPartyAssignment on this client")
			end
			return
		end
	end
	S:Print(L["Unit not found in group"] or "Unit not found in group")
end

SLASH_SUITANK1 = "/smt"
SlashCmdList.SUITANK = function(msg) SetTank("MAINTANK", msg) end
SLASH_SUIOFFTANK1 = "/sot"
SlashCmdList.SUIOFFTANK = function(msg) SetTank("MAINASSIST", msg) end

function TF:Initialize()
	self:BuildFrame()
	self.t = 0
	self.frame:SetScript("OnUpdate", function(_, dt)
		self.t = self.t + dt
		if self.t < 0.5 then return end
		self.t = 0
		TF:Refresh()
	end)
	if self.frame.RegisterEvent then end
	self:Refresh()
end
