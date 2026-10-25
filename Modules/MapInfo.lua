-- MapInfo: recommended zone level range + minimum fishing skill shown on the
-- world map for the currently viewed zone.
local _, ns = ...
local S = ns.S
local L = S.L
local MI = S:NewModule("MapInfo", "mapinfo")

-- zone levels / fishing skill come from the shared WorldMap data (real uiMapIDs)
local function ZoneInfo(mapID)
	local z = mapID and ns.MapZoneLevels and ns.MapZoneLevels[mapID]
	if z and z.minLevel and z.maxLevel then return z.minLevel, z.maxLevel, tonumber(z.minFish) end
end

function MI:RefreshText()
	if not self.text then return end
	local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local lo, hi, fish = ZoneInfo(mapID)
	if not lo then
		self.text:SetText("")
	elseif fish then
		self.text:SetFormattedText("%s %d-%d   |   %s %d", L["Zone Level"], lo, hi, L["Fishing"], fish)
	else
		self.text:SetFormattedText("%s %d-%d", L["Zone Level"], lo, hi)
	end
end

function MI:Build()
	if self.text or not WorldMapFrame then return end
	local fs = S:FontString(WorldMapFrame, 11, "OUTLINE", S.media.unitFont)
	fs:SetPoint("TOP", WorldMapFrame, "TOP", 0, -36)
	self.text = fs
	-- refresh while the map is open and whenever the viewed map changes
	local ticker = CreateFrame("Frame")
	ticker:Hide()
	ticker:SetScript("OnUpdate", function(_, e)
		MI.t = (MI.t or 0) + e
		if MI.t > 0.5 then MI.t = 0 MI:RefreshText() end
	end)
	WorldMapFrame:HookScript("OnShow", function() ticker:Show() MI:RefreshText() end)
	WorldMapFrame:HookScript("OnHide", function() ticker:Hide() end)
	fs:SetShown(self.db.enable ~= false)
end

function MI:Initialize()
	self.db = S.db.profile.mapinfo
	if WorldMapFrame then self:Build() return end
	-- the map frame is load-on-demand: poll until Blizzard_WorldMap is up
	C_Timer.NewTicker(2, function(t)
		if WorldMapFrame then MI:Build() t:Cancel() end
	end, 90)
end

function MI:Update()
	self.db = S.db.profile.mapinfo
	if self.text then
		self.text:SetShown(self.db.enable ~= false)
	end
	self:RefreshText()
end
