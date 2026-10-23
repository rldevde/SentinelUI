-- ManaTick: healer QoL - the five-second-rule timer plus the 2s mana-tick
-- cycle. After spending mana the bar counts down 5s (red); afterwards it
-- shows the time to the next mana tick (blue), synced to observed ticks.
local _, ns = ...
local S = ns.S
local L = S.L
local MT = S:NewModule("ManaTick", "manatick")

local floor = math.floor
local CreateFrame = CreateFrame
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
local FSR_SECONDS = 5
local TICK_SECONDS = 2

function MT:BuildBar()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIManaTick", UIParent)
	f:SetSize(180, 18)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -185)
	f:SetFrameStrata("MEDIUM")
	local bar = S:CreateStatusBar(f)
	bar:SetAllPoints()
	local spark = bar:CreateTexture(nil, "OVERLAY")
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetSize(10, 22)
	spark:SetBlendMode("ADD")
	bar.spark = spark
	local label = S:FontString(bar.suiTextOverlay, 10, "OUTLINE", S.media.numberFont)
	label:SetPoint("CENTER")
	local title = S:FontString(f, 9, "OUTLINE", S.media.unitFont)
	title:SetPoint("BOTTOM", f, "TOP", 0, 1)
	title:SetText(L["Mana Tick"])
	title:SetTextColor(0.7, 0.7, 0.7)
	f.bar, f.label, f.title = bar, label, title
	f:Hide()
	S:CreateMover(f, "ManaTick", L["Mana Tick"], { "CENTER", UIParent, "CENTER", 0, -185 }, "manatick")
	self.frame, self.bar, self.label = f, bar, label
end

-- returns "MANA" | "ENERGY" | nil depending on the player's active resource
function MT:TrackedPower()
	local pt = UnitPowerType("player")
	if pt == MANA then return "MANA" end
	if pt == ENERGY then return "ENERGY" end
end

function MT:Start()
	if self.running then return end
	self.running = true
	self.frame:Show()
	self.frame:SetScript("OnUpdate", function()
		local now = GetTime()
		local power = MT:TrackedPower()
		if not power then MT.frame:Hide() return end
		if MT.powerShown ~= power then
			MT.powerShown = power
			MT.frame.title:SetText(power == "ENERGY" and L["Energy Tick"] or L["Mana Tick"])
		end
		-- only show while the info matters: five-second rule active, resource
		-- not full yet, or in combat — parked at 100% out of combat = hidden
		local pt = (power == "ENERGY") and ENERGY or MANA
		local cur, max = UnitPower("player", pt), UnitPowerMax("player", pt)
		local full = not S.IsSecret(cur) and max and max > 0 and cur >= max
		local sinceSpend = self.lastSpend and (now - self.lastSpend) or 999
		local visible = UnitAffectingCombat("player")
			or (power == "MANA" and sinceSpend < FSR_SECONDS + 2)
			or not full
		if not visible then
			if MT.frame:IsShown() then
				MT.frame:Hide()
				MT.hideAt = now
			elseif MT.hideAt and now - MT.hideAt > 10 then
				MT:Stop() -- fully parked, stop paying the OnUpdate cost
			end
			return
		end
		MT.hideAt = nil
		MT.frame:Show()
		local _, bmax = MT.bar:GetMinMaxValues()
		if MT.bar.spark then
			if MT.db.showSpark ~= false and bmax and bmax > 0 then
				MT.bar.spark:ClearAllPoints()
				MT.bar.spark:SetPoint("CENTER", MT.bar, "LEFT", (MT.bar:GetValue() / bmax) * MT.bar:GetWidth(), 0)
				MT.bar.spark:Show()
			else
				MT.bar.spark:Hide()
			end
		end
		if power == "MANA" and sinceSpend < FSR_SECONDS then
			-- inside the five-second rule: no spirit regen yet
			local left = FSR_SECONDS - sinceSpend
			MT.bar:SetMinMaxValues(0, FSR_SECONDS)
			MT.bar:SetValue(left)
			MT.bar:SetStatusBarColor(0.85, 0.3, 0.25)
			MT.label:SetFormattedText("%s %.1f", L["5SR"], left)
		else
			-- outside: mana/energy ticks every 2s, synced to the last observed tick
			local nextTick = (self.lastTick or now) + TICK_SECONDS
			local left = nextTick - now
			if left < 0 then left = TICK_SECONDS end
			MT.bar:SetMinMaxValues(0, TICK_SECONDS)
			MT.bar:SetValue(TICK_SECONDS - left)
			if power == "ENERGY" then
				MT.bar:SetStatusBarColor(0.95, 0.85, 0.15)
				MT.label:SetFormattedText("%s %.1f", L["Energy"], left)
			else
				MT.bar:SetStatusBarColor(0.15, 0.45, 0.95)
				MT.label:SetFormattedText("%s %.1f", L["Tick"], left)
			end
		end
	end)
end

function MT:Stop()
	self.running = false
	if self.frame then self.frame:Hide() self.frame:SetScript("OnUpdate", nil) end
end

function MT:Initialize()
	self.db = S.db.profile.manatick
	local _, cls = UnitClass("player")
	if cls == "WARRIOR" or cls == "DEATHKNIGHT" or cls == "HUNTER" then return end
	self:BuildBar()
	self.prev = {}
	-- UNIT_POWER_UPDATE can be unreliable on this client; catch the alternates
	-- too and kick the bar on combat start / entering world regardless
	for _, ev in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT" }) do
		pcall(self.RegisterEvent, self, ev, function(_, _, unit, ptype)
		if unit ~= "player" then return end
		local pt = (ptype == "ENERGY") and ENERGY or (ptype == "MANA") and MANA
		if not pt or not MT:TrackedPower() then return end
		-- power events still fire while the value itself is a secret on this
		-- client; only spend/tick detection needs a readable number
		MT:Start()
		local cur = UnitPower("player", pt)
		if not cur or S.IsSecret(cur) then return end
		local prev = MT.prev[pt] or 0
		if cur < prev - 0.5 then
			if pt == MANA then MT.lastSpend = GetTime() end
			if MT:TrackedPower() then MT:Start() end
		elseif cur > prev + 0.5 then
			MT.lastTick = GetTime()
			if MT:TrackedPower() and not MT.running then MT:Start() end
		end
		MT.prev[pt] = cur
		end)
	end
	-- kick the bar on login/combat so it shows even when no power event fired
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() if MT:TrackedPower() then MT:Start() end end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() if MT:TrackedPower() then MT:Start() end end)
	-- hide while a druid is in a form (the druid mana strip covers it) and
	-- pause while the active resource is untracked
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
		if MT:TrackedPower() then MT:Start() else MT:Stop() end
	end)
end

function MT:Update()
	self.db = S.db.profile.manatick
	if not self:TrackedPower() then self:Stop() end
end
