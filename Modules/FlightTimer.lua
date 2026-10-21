-- FlightTimer: records taxi flight durations per route and shows an ETA
-- bar while flying (first ride on a route only shows elapsed time).
local _, ns = ...
local S = ns.S
local L = S.L
local FT = S:NewModule("FlightTimer", "flighttimer")

local format, floor = format, math.floor
local CreateFrame = CreateFrame
local GetTime = GetTime

local bar, flight
local function Routes()
	S.db.global.flightTimes = S.db.global.flightTimes or {}
	return S.db.global.flightTimes
end

local function SourceName()
	-- the node with type CURRENT is where we are
	if not NumTaxiNodes or not TaxiNodeGetType or not TaxiNodeName then return end
	for i = 1, NumTaxiNodes() do
		if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
	end
end

local function EndFlight()
	if not flight then return end
	local total = GetTime() - flight.t0
	if total > 30 then -- ignore instant cancels/dismounts under half a minute
		Routes()[flight.key] = total
	end
	flight = nil
	if bar then bar:Hide() end
end

local function Ensure()
	if bar then return end
	bar = CreateFrame("StatusBar", "SentinelUIFlightTimer", UIParent)
	bar:SetSize(220, 14)
	bar:SetStatusBarTexture(S.media.statusbar or "Interface\\Buttons\\WHITE8x8")
	bar:SetMinMaxValues(0, 1)
	S:CreateBackdrop(bar, "Default")
	bar:SetStatusBarColor(0.3, 0.6, 1)
	bar.text = S:FontString(bar, 10, "OUTLINE", S.media.unitFont)
	bar.text:SetPoint("CENTER")
	S:CreateMover(bar, "FlightTimer", L["Flight Timer"], { "TOP", UIParent, "TOP", 0, -100 }, "flighttimer")
	bar:Hide()
	bar:SetScript("OnUpdate", function()
		if not flight then bar:Hide() return end
		-- reliable end detection: PLAYER_CONTROL_GAINED never fires on
		-- classic taxi rides, so poll UnitOnTaxi once the flight is airborne
		if UnitOnTaxi and UnitOnTaxi("player") then
			flight.onTaxi = true
		elseif flight.onTaxi then
			EndFlight()
			return
		end
		local el = GetTime() - flight.t0
		local total = Routes()[flight.key]
		if total and total > 0 then
			bar:SetValue(el / total)
			local left = math.max(0, total - el)
			bar.text:SetFormattedText("%s - %dm %02ds", flight.dest or "?", floor(left / 60), floor(left % 60))
		else
			bar:SetValue(1)
			bar.text:SetFormattedText("%s - %dm %02ds", flight.dest or "?", floor(el / 60), floor(el % 60))
		end
	end)
end

local function BeginFlight(destIndex)
	local dest = TaxiNodeName and TaxiNodeName(destIndex)
	local src = SourceName()
	if not dest then return end
	flight = { key = (src or "?") .. ">" .. dest, dest = dest, t0 = GetTime() }
	Ensure()
	bar:Show()
end

function FT:Initialize()
	self.db = S.db.profile.flighttimer
	Ensure()
	hooksecurefunc("TakeTaxiNode", function(slot) S:SafeCall("FlightTimer:Take", BeginFlight, slot) end)
	-- regaining control = landed (also covers summon/portal, those have no flight table)
	self:RegisterEvent("PLAYER_CONTROL_GAINED", function() EndFlight() end)
	-- UNIT_FLAGS as fallback end-detection; handler args are (module, event, unit)
	self:RegisterEvent("UNIT_FLAGS", function(_, _, unit)
		if unit == "player" and flight and UnitOnTaxi and not UnitOnTaxi("player") then
			EndFlight()
		end
	end)
end

function FT:Update()
	self.db = S.db.profile.flighttimer
	if bar then bar:SetShown(self.db.enable ~= false and bar:IsShown()) end
end
