-- SwingTimer: auto-attack countdown (main hand melee, ranged for hunters).
-- The last 0.5s of the bar is tinted red: on hunters that is the window in
-- which a hard-cast (Aimed/Steady) would clip the auto shot.
local _, ns = ...
local S = ns.S
local L = S.L
local SW = S:NewModule("SwingTimer", "swingtimer")

local floor = math.floor
local CreateFrame = CreateFrame

function SW:BuildBar()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUISwingTimer", UIParent)
	f:SetSize(200, (self.db and self.db.height) or 12)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -210)
	f:SetFrameStrata("MEDIUM")
	local bar = S:CreateStatusBar(f)
	bar:SetAllPoints()
	bar:SetStatusBarColor(0.9, 0.75, 0.3)
	-- red clip window at the bar's right edge (hunter: don't hard-cast there)
	local clip = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	clip:SetTexture(S.media.statusbar)
	clip:SetVertexColor(0.9, 0.2, 0.15, 0.7)
	clip:SetPoint("TOPRIGHT")
	clip:SetPoint("BOTTOMRIGHT")
	bar.clip = clip
	local label = S:FontString(bar.suiTextOverlay, 10, "OUTLINE", S.media.numberFont)
	label:SetPoint("CENTER")
	local title = S:FontString(f, 9, "OUTLINE", S.media.unitFont)
	title:SetPoint("BOTTOM", f, "TOP", 0, 1)
	title:SetText(L["Swing Timer"])
	title:SetTextColor(0.7, 0.7, 0.7)
	f.bar, f.label, f.title = bar, label, title
	f:Hide()
	S:CreateMover(f, "SwingTimer", L["Swing Timer"], { "CENTER", UIParent, "CENTER", 0, -210 }, "swingtimer")
	self.frame, self.bar, self.label = f, bar, label
end

function SW:Speed(ranged)
	if ranged then
		local spd = UnitRangedDamage and UnitRangedDamage("player")
		return (spd and spd > 0.1) and spd or 2.0
	end
	local spd = UnitAttackSpeed and UnitAttackSpeed("player")
	return (spd and spd > 0.1) and spd or 2.0
end

function SW:Reset(ranged)
	if not self.db.enable then return end
	self.ranged = ranged
	self.duration = self:Speed(ranged)
	self.endsAt = GetTime() + self.duration
	self:BuildBar()
	local f = self.frame
	if not f:IsShown() or not f:GetScript("OnUpdate") then
		f:Show()
		f:SetScript("OnUpdate", function()
			local left = SW.endsAt - GetTime()
			if left <= 0 then
				-- latency/miss grace: hold the full bar briefly, then wait for
				-- the next hit event instead of flicking
				if GetTime() - SW.endsAt > 0.5 then f:SetScript("OnUpdate", nil) f:Hide() end
				SW.bar:SetValue(SW.duration)
				return
			end
			SW.bar:SetValue(SW.duration - left)
			if SW.db.showText then SW.label:SetFormattedText("%.1f", left) else SW.label:SetText("") end
			if SW.ranged then
				local w = SW.bar:GetWidth()
				local cw = math.min(w * 0.5 / SW.duration, w)
				SW.bar.clip:SetWidth(cw)
			else
				SW.bar.clip:SetWidth(0.001)
			end
		end)
	end
end

function SW:Initialize()
	self.db = S.db.profile.swingtimer
	if not self.db.enable then return end
	self:BuildBar()
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		local _, sub, _, sguid = CombatLogGetCurrentEventInfo()
		if sguid ~= UnitGUID("player") then return end
		if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
			SW:Reset(false)
		elseif sub == "RANGE_DAMAGE" or sub == "RANGE_MISSED" then
			SW:Reset(true)
		end
	end)
end

function SW:Update()
	self.db = S.db.profile.swingtimer
	if not self.db.enable and self.frame then
		self.frame:SetScript("OnUpdate", nil)
		self.frame:Hide()
	elseif self.frame then
		self.frame:SetHeight(self.db.height or 12)
	end
end
