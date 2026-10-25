-- GatherNotes: remembers gather-node positions (herbs, ore, skinning corpses)
-- per map, drawn as small icons on the world map. Positions are stored
-- account-wide so nodes accumulate over sessions and characters.
local _, ns = ...
local S = ns.S
local L = S.L
local GN = S:NewModule("GatherNotes", "gathernotes")

local CreateFrame = CreateFrame
local GetBestMap = C_Map and C_Map.GetBestMapForUnit
local GetPos = C_Map and C_Map.GetPlayerMapPosition

-- gather cast spell ids (vanilla through TBC/Wrath share these)
local KINDS = {
	[2366] = "Herb", [2368] = "Herb", [3570] = "Herb", [11993] = "Herb", [28695] = "Herb", -- Herb Gathering ranks
	[2575] = "Ore", [2576] = "Ore", [3564] = "Ore", [10248] = "Ore", [29354] = "Ore",      -- Mining ranks
	[8613] = "Skin", [8617] = "Skin", [8618] = "Skin", [10768] = "Skin", [32678] = "Skin", -- Skinning ranks
}
local MAX_PINS = 200
local MERGE_DIST = 0.02

local function Store()
	S.db.global.gatherNotes = S.db.global.gatherNotes or {}
	return S.db.global.gatherNotes
end

local function KindIcon(kind)
	local spellFor = { Herb = 2366, Ore = 2575, Skin = 8613 }
	local icon = S.GetSpellInfo and select(3, S.GetSpellInfo(spellFor[kind]))
	return icon or 134400
end

function GN:Record(spellId)
	local kind = KINDS[spellId]
	if not kind or not (GetBestMap and GetPos) then return end
	local map = GetBestMap("player")
	local pos = map and GetPos(map, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or x == 0 then return end
	local g = Store()
	local list = g[map .. ":" .. kind]
	if not list then list = {} g[map .. ":" .. kind] = list end
	for _, n in ipairs(list) do
		if math.abs(n[1] - x) < MERGE_DIST and math.abs(n[2] - y) < MERGE_DIST then return end
	end
	list[#list + 1] = { x, y }
	if self.db.chatNote then S:Print(format(L["Node saved: %s"], L[kind] or kind)) end
	self:Draw()
end

function GN:Draw()
	if self.pool then -- always park stale pins before deciding visibility
		for _, pin in ipairs(self.pool) do pin:Hide() end
	end
	self.using = 0
	if not (self.db.showMap ~= false) then return end
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas() or WorldMapFrame.ScrollContainer
	if not canvas then return end
	local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	if not mapID then return end
	self.pool = self.pool or {}
	local g = Store()
	local cw, ch = canvas:GetSize()
	if cw <= 0 then return end
	for key, list in pairs(g) do
		local mid, kind = key:match("^(%d+):(.+)$")
		if tonumber(mid) == mapID then
			for _, n in ipairs(list) do
				self.using = self.using + 1
				local pin = self.pool[self.using]
				if not pin then
					pin = CreateFrame("Frame", nil, canvas)
					pin:SetSize(10, 10)
					pin.tex = pin:CreateTexture(nil, "OVERLAY")
					pin.tex:SetAllPoints()
					pin:EnableMouse(true)
					pin:SetScript("OnEnter", function(p)
						GameTooltip:SetOwner(p, "ANCHOR_CURSOR")
						GameTooltip:AddLine(L[p.kind] or p.kind, 1, 1, 1)
						GameTooltip:Show()
					end)
					pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
					self.pool[self.using] = pin
				end
				pin.kind = kind
				pin.tex:SetTexture(KindIcon(kind))
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", canvas, "TOPLEFT", n[1] * cw, -n[2] * ch)
				pin:Show()
				if self.using >= MAX_PINS then break end
			end
		end
		if self.using >= MAX_PINS then break end
	end
end

function GN:Initialize()
	self.db = S.db.profile.gathernotes
	if not (C_Map and GetBestMap) then return end
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellId)
		if unit == "player" then GN:Record(spellId) end
	end)
	-- redraw whenever the map is shown/resized or another zone is opened
	if WorldMapFrame then
		WorldMapFrame:HookScript("OnShow", function() GN:Draw() end)
	end
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() GN:Draw() end)
	C_Timer.After(2, function()
		local canvas = WorldMapFrame and (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas() or WorldMapFrame.ScrollContainer)
		if canvas and canvas.HookScript then canvas:HookScript("OnSizeChanged", function() GN:Draw() end) end
	end)
end

function GN:Update()
	self.db = S.db.profile.gathernotes
	self:Draw()
end
