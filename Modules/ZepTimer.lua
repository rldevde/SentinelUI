-- ZepTimer: zeppelin/ship trip tracker. Boarding is detected through the
-- vessel name that replaces the zone text while aboard; every completed trip
-- stores its duration per vessel so the next crossing shows an ETA bar.
local _, ns = ...
local S = ns.S
local L = S.L
local ZT = S:NewModule("ZepTimer", "zeptimer")

local floor = floor
local CreateFrame = CreateFrame
local GetSubZoneText, GetZoneText = GetSubZoneText, GetZoneText

-- known vessels (en + de) — zone text shows the ship name while aboard
local VESSELS = {
	["The Thundercaller"]=1, ["Die Donnersturm"]=1,
	["The Zephyr"]=1, ["Die Zephyr"]=1,
	["The Iron Eagle"]=1, ["Der Eiserne Adler"]=1,
	["The Purple Princess"]=1, ["Die purpurne Prinzessin"]=1,
	["The Maiden's Fancy"]=1, ["Die M\195\164dchenlaune"]=1, ["Die Mädchenlaune"]=1,
	["The Lady Mehley"]=1, ["Die Lady Mehley"]=1,
	["The Bravery"]=1, ["Die Tapferkeit"]=1, ["Die Bravour"]=1, ["Die Bravoure"]=1,
	["The Moonspray"]=1, ["Die Mondgischt"]=1,
	["Elune's Blessing"]=1, ["Elunes Segen"]=1,
	["The Kraken"]=1, ["Der Kraken"]=1,
	["Walker of Waves"]=1, ["Wellenwanderer"]=1,
	["The Stormbringer"]=1, ["Der Sturmbringer"]=1,
	["The Mighty Wind"]=1, ["Der m\195\164chtige Wind"]=1, ["Der mächtige Wind"]=1,
	["Cloudkisser"]=1, ["Wolkenkuss"]=1,
	["The Sunspring"]=1, ["Die Sonnenquelle"]=1,
}

local function Hist()
	S.db.global.zepHistory = S.db.global.zepHistory or {}
	return S.db.global.zepHistory
end

local function ZoneLabel()
	return (GetSubZoneText and GetSubZoneText() ~= "" and GetSubZoneText()) or (GetZoneText and GetZoneText()) or ""
end

local function IsVessel(name) return name and VESSELS[name] end

function ZT:BuildBar()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIZepTimer", UIParent)
	f:SetSize(240, 18)
	f:SetPoint("TOP", UIParent, "TOP", 0, -300)
	f:SetFrameStrata("MEDIUM")
	local bar = S:CreateStatusBar(f)
	bar:SetAllPoints()
	bar:SetStatusBarColor(0.35, 0.65, 0.9)
	local label = S:FontString(bar.suiTextOverlay, 10, "OUTLINE", S.media.numberFont)
	label:SetPoint("CENTER")
	f.bar, f.label = bar, label
	f:Hide()
	S:CreateMover(f, "ZepTimer", L["Ship Timer"], { "TOP", UIParent, "TOP", 0, -300 }, "zeptimer")
	self.frame, self.bar, self.label = f, bar, label
end

function ZT:Board(vessel)
	self.vessel = vessel
	self.from = self.lastZone
	self.boardTime = GetTime()
	self:BuildBar()
	self.frame:Show()
	self.frame:SetScript("OnUpdate", function()
		local elapsed = GetTime() - ZT.boardTime
		local avg = Hist()[ZT.vessel] and Hist()[ZT.vessel].avg
		if avg then
			local left = math.max(0, avg - elapsed)
			ZT.bar:SetMinMaxValues(0, avg)
			ZT.bar:SetValue(elapsed)
			ZT.label:SetFormattedText("%s - %s %.0f:%02.0f", ZT.vessel, L["arrival in"], floor(left / 60), left % 60)
		else
			ZT.bar:SetMinMaxValues(0, 1)
			ZT.bar:SetValue(0)
			ZT.label:SetFormattedText("%s - %s %.0f:%02.0f", ZT.vessel, L["aboard"], floor(elapsed / 60), elapsed % 60)
		end
	end)
end

function ZT:Disembark(zone)
	local f = self.frame
	if f then f:SetScript("OnUpdate", nil) f:Hide() end
	-- learn the trip duration for this vessel
	if self.vessel and self.boardTime then
		local dur = GetTime() - self.boardTime
		if dur > 30 and dur < 3600 then
			local h = Hist()
			local e = h[self.vessel] or { trips = 0 }
			e.trips = (e.trips or 0) + 1
			e.avg = (e.avg and ((e.avg * (e.trips - 1) + dur) / e.trips)) or dur
			h[self.vessel] = e
			if self.db.chatNote ~= false then
				S:Print(format(L["Trip recorded: %s - %.0f:%02.0f min"], self.vessel, floor(dur / 60), dur % 60))
			end
		end
	end
	self.vessel, self.boardTime = nil, nil
end

function ZT:CheckZone()
	local here = ZoneLabel()
	if IsVessel(here) then
		if not self.vessel then self:Board(here) end
	else
		if self.vessel then self:Disembark(here) end
		if here ~= "" then self.lastZone = here end
	end
end

function ZT:Initialize()
	self.db = S.db.profile.zeptimer
	self.lastZone = ZoneLabel()
	for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
		self:RegisterEvent(ev, function() ZT:CheckZone() end)
	end
end

function ZT:Update()
	self.db = S.db.profile.zeptimer
end
