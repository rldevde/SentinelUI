-- FlightTimer: records taxi flight durations per route and shows a slim ETA
-- bar while flying. First ride on a route counts elapsed time; afterwards
-- the bar fills toward the known duration.
local _, ns = ...
local S = ns.S
local L = S.L
local FT = S:NewModule("FlightTimer", "flighttimer")

local format, floor = format, math.floor
local GetTime = GetTime

local bar, flight
local function Routes()
	S.db.global.flightTimes = S.db.global.flightTimes or {}
	return S.db.global.flightTimes
end

local function SourceName()
	if not (NumTaxiNodes and TaxiNodeGetType and TaxiNodeName) then return end
	for i = 1, NumTaxiNodes() do
		if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
	end
end

local function Fmt(sec)
	sec = floor(sec + 0.5)
	return format("%d:%02d", floor(sec / 60), sec % 60)
end

local function EndFlight()
	if not flight then return end
	local total = GetTime() - flight.t0
	-- ignore instant cancels/dismounts under half a minute
	if total > 30 then Routes()[flight.key] = total end
	S.db.global.activeFlight = nil
	flight = nil
	if bar then bar:Hide() end
end

local function Ensure()
	if bar then return end
	local f = CreateFrame("Button", "SentinelUIFlightTimer", UIParent)
	f:SetSize(240, 18)
	f:SetFrameStrata("MEDIUM")
	S:SetTemplate(f, "Default")
	f:RegisterForClicks("RightButtonUp")
	-- fill
	local fill = f:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 2, -2)
	fill:SetPoint("BOTTOMLEFT", 2, 2)
	fill:SetTexture(S.media.statusbar or "Interface\\Buttons\\WHITE8x8")
	fill:SetVertexColor(0.25, 0.55, 0.95, 0.85)
	f.fill = fill
	-- spark at the fill edge
	local spark = f:CreateTexture(nil, "OVERLAY")
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetSize(8, 24)
	spark:SetBlendMode("ADD")
	spark:Hide()
	f.spark = spark
	-- texts: route label left, timer right
	local route = S:FontString(f, 10, "OUTLINE", S.media.unitFont)
	route:SetPoint("LEFT", 6, 0)
	local time = S:FontString(f, 10, "OUTLINE", S.media.numberFont)
	time:SetPoint("RIGHT", -6, 0)
	f.route, f.time = route, time
	f:SetScript("OnClick", function(self, btn)
		if btn == "RightButton" then self:Hide() end
	end)
	f:SetScript("OnUpdate", function(self)
		if not flight then self:Hide() return end
		-- reliable end detection: PLAYER_CONTROL_GAINED never fires on
		-- classic taxi rides, so poll UnitOnTaxi once airborne
		if UnitOnTaxi and UnitOnTaxi("player") then
			flight.onTaxi = true
		elseif flight.onTaxi then
			EndFlight()
			return
		end
		local el = GetTime() - flight.t0
		local total = Routes()[flight.key]
		self.route:SetText(flight.dest or "?")
		local w = self:GetWidth() - 4
		if total and total > 0 then
			local p = math.min(1, el / total)
			self.fill:SetWidth(math.max(1, w * p))
			self.spark:ClearAllPoints()
			self.spark:SetPoint("CENTER", self.fill, "RIGHT", 0, 0)
			self.spark:Show()
			self.time:SetFormattedText("-%s", Fmt(math.max(0, total - el)))
		else
			-- no ETA on a new route: thin progress strip + elapsed time
			self.fill:SetWidth(math.max(1, w * math.min(1, el / 120)))
			self.spark:Hide()
			self.time:SetText(Fmt(el))
		end
	end)
	S:CreateMover(f, "FlightTimer", L["Flight Timer"], { "TOP", UIParent, "TOP", 0, -100 }, "flighttimer")
	f:Hide()
	bar = f
end

local function BeginFlight(destIndex)
	local dest = TaxiNodeName and TaxiNodeName(destIndex)
	if not dest then return end
	flight = { key = (SourceName() or "?") .. ">" .. dest, dest = dest, t0 = GetTime() }
	-- persist so the route survives a /reload mid-flight
	S.db.global.activeFlight = { key = flight.key, dest = flight.dest, t0 = flight.t0 }
	Ensure()
	bar.route:SetText(dest)
	bar.time:SetText("…")
	bar.fill:SetWidth(1)
	bar.spark:Hide()
	bar:Show()
end

function FT:Initialize()
	self.db = S.db.profile.flighttimer
	Ensure()
	hooksecurefunc("TakeTaxiNode", function(slot) S:SafeCall("FlightTimer:Take", BeginFlight, slot) end)
	-- regaining control = landed (also covers summon/portal, no flight table)
	self:RegisterEvent("PLAYER_CONTROL_GAINED", function() EndFlight() end)
	-- UNIT_FLAGS as fallback end-detection; handler args are (module, event, unit)
	self:RegisterEvent("UNIT_FLAGS", function(_, _, unit)
		if unit == "player" and flight and UnitOnTaxi and not UnitOnTaxi("player") then
			EndFlight()
		end
	end)
	-- reload mid-flight: restore the persisted route if still airborne
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		if not (UnitOnTaxi and UnitOnTaxi("player")) then
			S.db.global.activeFlight = nil
			return
		end
		local saved = S.db.global.activeFlight
		if saved and saved.t0 then
			flight = { key = saved.key, dest = saved.dest, t0 = saved.t0, onTaxi = true }
		else
			flight = { key = "?>", dest = L["In flight"], t0 = GetTime(), onTaxi = true }
		end
		Ensure()
		bar.route:SetText(flight.dest or "?")
		bar:Show()
	end)
end

function FT:Update()
	self.db = S.db.profile.flighttimer
	if bar and self.db.enable == false then bar:Hide() end
end
