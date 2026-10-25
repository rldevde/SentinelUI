-- MarkedTargets: right-side list of the top raid-marked enemies your group
-- is engaged with - marker icon + HP bar, sorted skull-first. Pure display,
-- updates via a light unit scan on a short throttle.
local _, ns = ...
local S = ns.S
local L = S.L
local MK = S:NewModule("MarkedTargets", "markedtargets")

local CreateFrame = CreateFrame
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local UnitGUID, UnitHealth, UnitHealthMax = UnitGUID, UnitHealth, UnitHealthMax
local UnitName, UnitExists, UnitIsDead = UnitName, UnitExists, UnitIsDead
local UnitIsFriend = UnitIsFriend
local wipe = wipe

local MAX_ROWS = 5
local ROW_H = 20
local PAD = 2

-- skull (8) is kill-first priority, then cross (7), then the rest
local PRIO = { [8] = 1, [7] = 2, [6] = 3, [5] = 4, [4] = 5, [3] = 6, [2] = 7, [1] = 8 }

local function BuildUnits(buf, seenU)
	local function add(u)
		if UnitExists(u) and not seenU[u] then
			seenU[u] = true
			local idx = GetRaidTargetIndex(u)
			if idx and idx >= 1 and idx <= 8 and not UnitIsFriend("player", u) and not UnitIsDead(u) then
				buf[#buf + 1] = u
			end
		end
	end
	add("target")
	add("focus")
	for i = 1, 4 do add("party" .. i) end
	for i = 1, 4 do add("party" .. i .. "target") end
	for i = 1, 40 do add("raid" .. i .. "target") end
	for i = 1, 40 do add("nameplate" .. i) end
	return buf
end

function MK:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIMarkedTargets", UIParent)
	f:SetSize(170, (ROW_H + PAD) * MAX_ROWS)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -220, 0)
	f:SetFrameStrata("LOW")
	S:SetTemplate(f, "Transparent")
	f.rows = {}
	for i = 1, MAX_ROWS do
		local r = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
		r:SetSize(166, ROW_H)
		r:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -((i - 1) * (ROW_H + PAD)) - 2)
		local icon = r:CreateTexture(nil, "OVERLAY")
		icon:SetSize(18, 18)
		icon:SetPoint("LEFT", 2, 0)
		icon:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
		local bar = S:CreateStatusBar(r)
		bar:SetPoint("LEFT", icon, "RIGHT", 3, 0)
		bar:SetPoint("RIGHT", -2, 0)
		bar:SetHeight(ROW_H - 4)
		local name = S:FontString(bar.suiTextOverlay, 10, "OUTLINE", S.media.unitFont)
		name:SetPoint("LEFT", 4, 0)
		local hp = S:FontString(bar.suiTextOverlay, 10, "OUTLINE", S.media.numberFont)
		hp:SetPoint("RIGHT", -4, 0)
		r:SetAttribute("type1", "target")
		r:RegisterForClicks("AnyUp", "AnyDown")
		r.icon, r.bar, r.name, r.hp = icon, bar, name, hp
		r:EnableMouse(false)
		r:SetAlpha(0)
		f.rows[i] = r
	end
	f:SetAlpha(0) -- never Hide(): the frame parents secure buttons (blocked in combat)
	S:CreateMover(f, "markedtargets", L["Marked Targets"], { "RIGHT", UIParent, "RIGHT", -220, 0 }, "markedtargets")
	self.frame = f
end

local found = {}
function MK:Refresh()
	self.db = self.db or S.db.profile.markedtargets
	if not self.db.enable then
		if self.frame then self.frame:SetAlpha(0) end
		return
	end
	self:BuildFrame()
	local units = BuildUnits({}, {})
	-- dedupe by GUID, first-seen wins
	wipe(found)
	local list = {}
	for _, u in ipairs(units) do
		local g = UnitGUID(u)
		if g and not found[g] then
			found[g] = true
			list[#list + 1] = u
		end
	end
	table.sort(list, function(a, b)
		local ia, ib = GetRaidTargetIndex(a) or 0, GetRaidTargetIndex(b) or 0
		return (PRIO[ia] or 9) < (PRIO[ib] or 9)
	end)
	local n = math.min(#list, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local r = self.frame.rows[i]
		local u = list[i]
		if u then
			if not InCombatLockdown() then r:SetAttribute("unit", u) end
			local idx = GetRaidTargetIndex(u)
			SetRaidTargetIconTexture(r.icon, idx)
			local hp, max = UnitHealth(u), UnitHealthMax(u)
			r.bar:SetMinMaxValues(0, max > 0 and max or 1)
			r.bar:SetValue(hp)
			r.bar:SetStatusBarColor(0.75, 0.18, 0.18)
			local nm = UnitName(u) or "?"
			if #nm > 18 then nm = nm:sub(1, 17) .. "…" end
			r.name:SetText(nm)
			r.hp:SetText(max > 0 and (math.floor(hp / max * 100 + 0.5) .. "%") or "")
			r:SetAlpha(1)
			if not InCombatLockdown() then r:EnableMouse(true) end
		else
			r:SetAlpha(0)
			if not InCombatLockdown() then r:EnableMouse(false) end
		end
	end
	self.frame:SetAlpha(n > 0 and 1 or 0)
end

function MK:Initialize()
	self.db = S.db.profile.markedtargets
	self:BuildFrame()
	self.t = 0
	self.driver = self.driver or CreateFrame("Frame") -- always shown, so it keeps ticking while the list is empty
	self.driver:SetScript("OnUpdate", function(_, dt)
		self.t = self.t + dt
		if self.t < 0.4 then return end
		self.t = 0
		MK:Refresh()
	end)
	self:Refresh()
end
