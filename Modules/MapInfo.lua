-- MapInfo: recommended zone level range + minimum fishing skill shown on the
-- world map for the currently viewed zone.
local _, ns = ...
local S = ns.S
local L = S.L
local MI = S:NewModule("MapInfo", "mapinfo")

-- uiMapID -> { levelLo, levelHi, minFishingSkill }
local ZONES = {
	[1] = { 1, 10, 1 }, [7] = { 1, 10, 1 }, [10] = { 10, 20, 55 }, [14] = { 30, 40, 205 },
	[15] = { 35, 45, 215 }, [17] = { 45, 55, 300 }, [18] = { 1, 10, 1 }, [21] = { 10, 20, 55 },
	[22] = { 51, 58, 330 }, [23] = { 53, 60, 355 }, [25] = { 20, 30, 130 }, [26] = { 40, 50, 280 },
	[27] = { 1, 10, 1 }, [32] = { 43, 50, 300 }, [36] = { 50, 58, 330 }, [37] = { 1, 10, 1 },
	[42] = { 55, 60, 355 }, [47] = { 18, 30, 130 }, [48] = { 10, 20, 55 }, [49] = { 15, 25, 110 },
	[50] = { 30, 45, 225 }, [51] = { 35, 45, 240 }, [52] = { 10, 20, 55 }, [56] = { 20, 30, 150 },
	[57] = { 1, 10, 1 }, [62] = { 10, 20, 55 }, [63] = { 18, 30, 130 }, [64] = { 25, 35, 205 },
	[65] = { 15, 27, 110 }, [66] = { 30, 40, 205 }, [69] = { 40, 50, 280 }, [70] = { 35, 45, 240 },
	[71] = { 40, 50, 280 }, [76] = { 45, 55, 300 }, [77] = { 48, 55, 330 }, [78] = { 48, 55, 330 },
	[80] = { 1, 60, 300 }, [81] = { 55, 60, 355 }, [83] = { 55, 60, 355 },
	[199] = { 30, 40, 205 }, [210] = { 30, 40, 225 },
	-- TBC zones
	[94] = { 1, 10, 1 }, [95] = { 10, 20, 55 }, [97] = { 1, 10, 1 }, [106] = { 10, 20, 55 },
	[100] = { 58, 63, 280 }, [102] = { 60, 64, 340 }, [104] = { 67, 70, 380 }, [105] = { 65, 68, 355 },
	[107] = { 64, 67, 355 }, [108] = { 62, 65, 355 }, [109] = { 67, 70, 400 },
}

function MI:RefreshText()
	if not self.text then return end
	local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local z = mapID and ZONES[mapID]
	if z then
		self.text:SetFormattedText("%s %d-%d   |   %s %d", L["Zone Level"], z[1], z[2], L["Fishing"], z[3])
	else
		self.text:SetText("")
	end
end

function MI:Initialize()
	self.db = S.db.profile.mapinfo
	if not WorldMapFrame then return end
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
end

function MI:Update()
	self.db = S.db.profile.mapinfo
	if self.text then
		self.text:SetShown(self.db.enable ~= false)
	end
	self:RefreshText()
end
