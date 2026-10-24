local _, ns = ...
local S = ns.S
local L = S.L
local WM = S:NewModule("WorldMap", "worldmap")

local floor = math.floor
local sqrt = math.sqrt

-- World map enhancements: zone level ranges on hover, fishing skill,
-- dungeon/raid pins with level ranges, flight/travel points, spirit
-- healers and zone-crossing arrows. Pin data lives in
-- Modules/WorldMap/MapData.lua (generated, factual game coordinates).

local pins = ns.MapPins or {}
local zoneLevels = ns.MapZoneLevels or {}

local isDE = GetLocale() == "deDE"
local function PinName(p) return (isDE and p[5]) or p[4] end
local function PinDesc(p) return (isDE and p[7]) or p[6] end

-- icon set per pin type: atlas first, file fallback
local function AtlasOK(name)
	return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true
end

local PIN_ICONS = {
	Dungeon = { atlas = "Dungeon", file = "Interface\\LFGFrame\\UI-LFG-ICON-DUNGEONRAID", size = 18 },
	Raid = { atlas = "Raid", file = "Interface\\LFGFrame\\UI-LFG-ICON-RAID", size = 18 },
	Dunraid = { atlas = "Dungeon", file = "Interface\\LFGFrame\\UI-LFG-ICON-DUNGEONRAID", size = 18 },
	FlightA = { atlas = "TaxiNode_Alliance", file = "Interface\\TaxiFrame\\UI-Taxi-Icon-Alliance", size = 16 },
	FlightH = { atlas = "TaxiNode_Horde", file = "Interface\\TaxiFrame\\UI-Taxi-Icon-Horde", size = 16 },
	FlightN = { atlas = "TaxiNode_Neutral", file = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green", size = 16 },
	TravelA = { file = "Interface\\Icons\\Spell_Arcane_PortalStormWind", size = 16 },
	TravelH = { file = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar", size = 16 },
	TravelN = { file = "Interface\\Icons\\Spell_Arcane_TeleportShattrath", size = 16 },
	Spirit = { file = "Interface\\Icons\\Spell_Holy_Resurrection", size = 14 },
	Arrow = { atlas = "Garr_LevelUpgradeArrow", file = "Interface\\Minimap\\MinimapArrow", size = 12 },
}

-- level range text colored like quest difficulty vs the player
local function LevelRangeText(lo, hi)
	if not (lo and hi and lo > 0 and hi > 0) then return "" end
	local plvl = UnitLevel("player") or 1
	local color
	local getCol = GetQuestDifficultyColor or function()
		return QuestDifficultyColors and QuestDifficultyColors.difficult or { r = 1, g = 1, b = 0 }
	end
	if plvl < lo then
		color = getCol(lo)
	elseif plvl > hi then
		color = getCol(hi - 2)
	else
		color = QuestDifficultyColors and QuestDifficultyColors.difficult or { r = 1, g = 0.5, b = 0.25 }
	end
	local hex = color and string.format("|cff%02x%02x%02x", (color.r or 1) * 255, (color.g or 1) * 255, (color.b or 1) * 255) or "|cffffffff"
	if lo ~= hi then
		return hex .. " (" .. lo .. "-" .. hi .. ")|r"
	end
	return hex .. " (" .. hi .. ")|r"
end

-- ---------------------------------------------------------------------------
-- zone level hover label (replaces the area-label provider's OnUpdate)
-- ---------------------------------------------------------------------------
local origLabelUpdate

local function AreaLabelOnUpdate(self)
	self:ClearLabel(MAP_AREA_LABEL_TYPE.AREA_NAME)
	local map = self.dataProvider:GetMap()
	if map:IsCanvasMouseFocus() then
		local name, description
		local mapID = map:GetMapID()
		local x, y = map:GetNormalizedCursorPosition()
		local posInfo = x and y and C_Map.GetMapInfoAtPosition(mapID, x, y)
		if posInfo and posInfo.mapID ~= mapID then
			name = posInfo.name
			local z = zoneLevels[posInfo.mapID]
			if z then
				if WM.db.zoneLevels and z.minLevel and z.maxLevel then
					name = name .. LevelRangeText(z.minLevel, z.maxLevel)
				end
				if WM.db.fishingLevels and z.minFish then
					description = (L["Fishing"] or "Fishing") .. ": " .. z.minFish
				end
			end
		elseif MapUtil and MapUtil.FindBestAreaNameAtMouse then
			name = MapUtil.FindBestAreaNameAtMouse(mapID, x, y)
		end
		if name then
			self:SetLabel(MAP_AREA_LABEL_TYPE.AREA_NAME, name, description)
		end
	end
	self:EvaluateLabels()
end

function WM:ApplyZoneLevels()
	if not WorldMapFrame or not WorldMapFrame.dataProviders then return end
	for provider in next, WorldMapFrame.dataProviders do
		if provider.setAreaLabelCallback and provider.Label then
			if not origLabelUpdate then
				origLabelUpdate = provider.Label:GetScript("OnUpdate")
			end
			provider.Label:SetScript("OnUpdate",
				(self.db.zoneLevels or self.db.fishingLevels) and AreaLabelOnUpdate or origLabelUpdate)
		end
	end
end

-- ---------------------------------------------------------------------------
-- map pins
-- ---------------------------------------------------------------------------
local function PinAllowed(pin)
	local db = WM.db
	local t = pin[1]
	if t == "Dungeon" or t == "Raid" or t == "Dunraid" then return db.pinDungeons end
	if t == "Spirit" then return db.pinSpirits end
	if t == "Arrow" then return db.pinCrossings end
	if t == "FlightA" then
		return (S.myFaction == "Alliance" and db.pinFlights) or db.pinFlightsOpp
	end
	if t == "FlightH" then
		return (S.myFaction == "Horde" and db.pinFlights) or db.pinFlightsOpp
	end
	if t == "FlightN" then return db.pinFlights end
	if t == "TravelA" then
		return (S.myFaction == "Alliance" and db.pinTravel) or db.pinTravelOpp
	end
	if t == "TravelH" then
		return (S.myFaction == "Horde" and db.pinTravel) or db.pinTravelOpp
	end
	if t == "TravelN" then return db.pinTravel end
	return false
end

-- the live map id lives on different frames depending on the client:
-- WorldMapFrame.mapID (canvas mixin), the inner canvas frame, or the
-- ScrollContainer. Resolve in order instead of trusting one field.
local function CurrentMapID()
	if WorldMapFrame.mapID then return WorldMapFrame.mapID end
	local sc = WorldMapFrame.ScrollContainer
	if sc and sc.mapID then return sc.mapID end
	local canvas = sc and ((sc.GetMap and sc:GetMap()) or sc.canvas or sc.Child)
	if canvas and canvas.mapID then return canvas.mapID end
end

local function GoToMap(id)
	if not id then return end
	if WorldMapFrame.SetMapID then return WorldMapFrame:SetMapID(id) end
	local sc = WorldMapFrame.ScrollContainer
	if sc and sc.SetMapID then return sc:SetMapID(id) end
	local canvas = sc and ((sc.GetMap and sc:GetMap()) or sc.canvas or sc.Child)
	if canvas and canvas.SetMapID then return canvas:SetMapID(id) end
end

local function SetupProvider()
	if WM.provider or not WorldMapFrame then return end
	if not (MapCanvasDataProviderMixin and BaseMapPoiPinMixin and CreateVector2D) then return end

	_G.SuiMapPinMixin = BaseMapPoiPinMixin:CreateSubPin("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE")

	function SuiMapPinMixin:OnAcquired(info)
		BaseMapPoiPinMixin.OnAcquired(self, info)
		if self.suiLabel then self.suiLabel:Hide() end
		local ic = info.suiIcon
		local sz = ((ic and ic.size) or 12) * (WM.db.pinScale or 1)
		if info.zoneText then
			-- zone link: small marker dot; the zone name only shows on hover
			self.Texture:SetTexture("Interface\\COMMON\\Indicator-Yellow")
			self.HighlightTexture:SetTexture("Interface\\COMMON\\Indicator-Yellow")
			self.Texture:SetVertexColor(1, 0.82, 0, 0.85)
			self.HighlightTexture:SetVertexColor(1, 1, 1)
			self.Texture:SetScale(1)
			self.HighlightTexture:SetScale(1)
			self.Texture:SetRotation(0)
			self.HighlightTexture:SetRotation(0)
			self.Texture:SetSize(sz * 0.6, sz * 0.6)
			self.HighlightTexture:SetSize(sz * 0.6, sz * 0.6)
			local lbl = self.suiLabel or self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			self.suiLabel = lbl
			lbl:ClearAllPoints()
			lbl:SetPoint("TOP", self, "BOTTOM", 0, -1)
			lbl:SetText(info.zoneText)
			lbl:SetTextColor(1, 0.82, 0)
			lbl:SetShadowOffset(1, -1)
			lbl:Hide()
			if not self.suiZoneHover then
				self.suiZoneHover = true
				-- HookScript, not SetScript: the pin template's own OnEnter
				-- (tooltip) must keep working
				self:HookScript("OnEnter", function(s)
					if s.suiLabel then s.suiLabel:Show() end
				end)
				self:HookScript("OnLeave", function(s)
					if s.suiLabel then s.suiLabel:Hide() end
				end)
			end
			-- hitbox stays the size of the dot so the hidden label does not
			-- swallow map clicks; the dungeon-entrance template we inherit
			-- from ships huge negative HitRectInsets -> clamp them
			self:SetSize(sz + 8, sz + 8)
			self:SetHitRectInsets(0, 0, 0, 0)
		elseif ic then
			if ic.atlas and AtlasOK(ic.atlas) then
				self.Texture:SetAtlas(ic.atlas)
				self.HighlightTexture:SetAtlas(ic.atlas)
				self.Texture:SetVertexColor(1, 1, 1)
				self.HighlightTexture:SetVertexColor(1, 1, 1)
			elseif ic.file then
				self.Texture:SetTexture(ic.file)
				self.HighlightTexture:SetTexture(ic.file)
				self.Texture:SetVertexColor(1, 1, 1)
				self.HighlightTexture:SetVertexColor(1, 1, 1)
			end
			self.Texture:SetScale(0.8)
			self.HighlightTexture:SetScale(0.8)
			self.Texture:SetRotation(0)
			self.HighlightTexture:SetRotation(0)
			self.Texture:SetSize(sz, sz)
			self.HighlightTexture:SetSize(sz, sz)
			self:SetSize(sz + 6, sz + 6)
		end
		if info.rot and not info.zoneText then
			self.Texture:SetRotation(info.rot)
			self.HighlightTexture:SetRotation(info.rot)
		end
		self.zoneCrossing = info.targetMap
		-- Frames have no OnClick script on this client; OnMouseUp is the one
		-- that fires when the template is mouse-enabled
		self:SetScript("OnMouseUp", SuiMapPinMixin.OnMouseUp)
		if self.HasScript and self:HasScript("OnClick") then
			self:SetScript("OnClick", function(s, btn) SuiMapPinMixin.OnMouseUp(s, btn or "LeftButton") end)
		end
	end

	function SuiMapPinMixin:OnMouseUp(btn)
		if btn == "LeftButton" and self.zoneCrossing then
			GoToMap(self.zoneCrossing)
		elseif btn == "RightButton" then
			if WorldMapFrame.NavigateToParentMap then WorldMapFrame:NavigateToParentMap() end
		end
	end

	local provider = CreateFromMixins(MapCanvasDataProviderMixin)

	function provider:RefreshAllData()
		self:GetMap():RemoveAllPinsByTemplate("SuiMapPinTemplate")
		local mapID = CurrentMapID()
		local list = mapID and pins[mapID]
		if list then
			for _, pin in ipairs(list) do
				if PinAllowed(pin) then
					local info = {}
					info.position = CreateVector2D(pin[2] / 100, pin[3] / 100)
					local name = PinName(pin)
					local lo, hi = pin[8], pin[9]
					if WM.db.zoneLevels and lo and hi then
						name = name .. LevelRangeText(lo, hi)
					end
					info.name = name
					info.description = PinDesc(pin)
					info.suiIcon = PIN_ICONS[pin[1]]
					info.rot = pin[10]
					info.targetMap = pin[11]
					info.atlasName = "Dungeon" -- base mixin requires one; we override in OnAcquired
					self:GetMap():AcquirePin("SuiMapPinTemplate", info)
				end
			end
		end
		-- zone links: every child map becomes a clickable label at the center
		-- of its area on this map (continent -> zones, zone -> sub-maps)
		if mapID and WM.db.pinZoneLinks ~= false and C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap then
			for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
				local x1, y1, x2, y2 = C_Map.GetMapRectOnMap(child.mapID, mapID)
				if x1 and x1 ~= x2 and y1 ~= y2 then
					local info = {}
					info.position = CreateVector2D((x1 + x2) / 2, (y1 + y2) / 2)
					local name = child.name or "?"
					info.name = name -- tooltip
					local lvl = zoneLevels[child.mapID]
					if WM.db.zoneLevels and lvl and lvl.minLevel then
						name = name .. LevelRangeText(lvl.minLevel, lvl.maxLevel)
					end
					info.zoneText = name
					info.targetMap = child.mapID
					info.atlasName = "Dungeon"
					self:GetMap():AcquirePin("SuiMapPinTemplate", info)
				end
			end
		end
	end

	WorldMapFrame:AddDataProvider(provider)
	WM.provider = provider
end

function WM:RefreshPins()
	if self.provider then self.provider:RefreshAllData() end
end

-- ---------------------------------------------------------------------------
-- own window chrome: every piece of Blizzard chrome (border, nav, title,
-- stock controls) is hidden and replaced with a Sentinel-styled title bar,
-- dark edge and scale grip drawn onto WorldMapFrame. The map canvas itself
-- is left untouched so every pin provider (ours, third-party, quest blobs,
-- ...) keeps rendering exactly where it always did.
-- ---------------------------------------------------------------------------
local lastMapID, lastZoom, lastH, lastV
local chrome

-- another map addon drives frame scale/position: if we also move, scale and
-- re-anchor the canvas, the client's zone hit-polygons desync from the
-- rendered map (clicks land offset). In that case we leave the window frame
-- alone entirely; our pins/zone levels are canvas-relative and coexist fine.
local MAP_CONFLICTS = { "Leatrix_Maps", "Mapster", "WorldMapEnhanced" }
local function ConflictingMapAddon()
	for _, other in ipairs(MAP_CONFLICTS) do
		local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(other))
			or (IsAddOnLoaded and IsAddOnLoaded(other))
		if loaded then return other end
	end
end

local CONTINENTS = { 1415, 1414, 1945 } -- Eastern Kingdoms, Kalimdor, Outland

function WM:SaveMapPos()
	local a, _, r, x, y = WorldMapFrame:GetPoint()
	self.db.mapPos = { a = a or "TOPLEFT", r = r or "TOPLEFT", x = x or 0, y = y or 0 }
end

function WM:ApplyMapPos()
	local p = self.db.mapPos or {}
	WorldMapFrame:ClearAllPoints()
	WorldMapFrame:SetPoint(p.a or "TOPLEFT", UIParent, p.r or "TOPLEFT", p.x or 16, p.y or -104)
end

function WM:ApplyMapScale()
	WorldMapFrame:SetScale(self.db.mapScale or 1)
end

function WM:ApplyMapFade()
	local db = self.db
	if db.mapFade and PlayerMovementFrameFader and PlayerMovementFrameFader.AddDeferredFrame then
		PlayerMovementFrameFader.AddDeferredFrame(WorldMapFrame, db.fadeAlpha or 0.4, 1, 0.5,
			function() return not WorldMapFrame:IsMouseOver() end)
		if not (IsPlayerMoving and IsPlayerMoving()) then WorldMapFrame:SetAlpha(1) end
	elseif PlayerMovementFrameFader and PlayerMovementFrameFader.RemoveDeferredFrame then
		PlayerMovementFrameFader.RemoveDeferredFrame(WorldMapFrame)
		WorldMapFrame:SetAlpha(1)
	end
end

local function CursorDist()
	local left, top = WorldMapFrame:GetLeft(), WorldMapFrame:GetTop()
	local scale = WorldMapFrame:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x = x / scale - left
	y = top - y / scale
	return sqrt(x * x + y * y)
end

local function UpdateZoneName()
	if not chrome then return end
	local info = CurrentMapID() and C_Map.GetMapInfo(CurrentMapID())
	chrome.zoneName:SetText(info and info.name or "")
end

local function HideBlizzardChrome()
	for _, key in ipairs({ "BorderFrame", "MiniBorderFrame", "NavBar" }) do
		local f = WorldMapFrame[key]
		if f and f.Hide and not f.suiChromeKilled then
			f.suiChromeKilled = true
			f:Hide()
			f:HookScript("OnShow", function(frame) frame:Hide() end)
		end
	end
end

local function BuildChrome()
	if chrome then return end
	local host = WorldMapFrame
	local lvl = (host.BorderFrame or host):GetFrameLevel() + 60

	-- dark Sentinel edge; the canvas is a child and renders above the fill
	S:SetTemplate(host, "Default", "TOP")

	-- title bar ----------------------------------------------------------------
	chrome = CreateFrame("Frame", "SentinelUIMapBar", host)
	chrome:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
	chrome:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
	chrome:SetHeight(24)
	chrome:SetFrameStrata(host:GetFrameStrata())
	chrome:SetFrameLevel(lvl)
	chrome:EnableMouse(true)
	S:SetTemplate(chrome, "Default")
	chrome:RegisterForDrag("LeftButton")
	chrome:SetScript("OnDragStart", function()
		if WM.db.mapUnlock then host:StartMoving() end
	end)
	chrome:SetScript("OnDragStop", function()
		host:StopMovingOrSizing()
		host:SetUserPlaced(false)
		WM:SaveMapPos()
	end)

	-- map selection dropdown ---------------------------------------------------
	local drop = CreateFrame("Frame", "SuiWorldMapMenu", chrome, "UIDropDownMenuTemplate")

	local function AddZoneButtons(cid)
		local cinfo = C_Map.GetMapInfo(cid)
		UIDropDownMenu_AddButton({
			text = "|cffebad33" .. (cinfo and cinfo.name or "?") .. "|r",
			notCheckable = true,
			func = function() GoToMap(cid) CloseDropDownMenus() end,
		}, 2)
		local children = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(cid)
		local zones = {}
		if children then
			for _, zm in ipairs(children) do
				if zm.mapType == 3 or zm.mapType == 4 then -- zone or dungeon map
					local z = zoneLevels[zm.mapID]
					zones[#zones + 1] = {
						text = zm.name .. ((z and z.minLevel) and (" |cff888888(" .. z.minLevel .. "-" .. z.maxLevel .. ")|r") or ""),
						notCheckable = true,
						func = function() GoToMap(zm.mapID) CloseDropDownMenus() end,
					}
				end
			end
			table.sort(zones, function(a, b) return a.text < b.text end)
		end
		for _, zi in ipairs(zones) do UIDropDownMenu_AddButton(zi, 2) end
	end

	UIDropDownMenu_Initialize(drop, function(_, level)
		if level == 1 then
			for _, cid in ipairs(CONTINENTS) do
				local cinfo = C_Map.GetMapInfo(cid)
				if cinfo then
					UIDropDownMenu_AddButton({
						text = cinfo.name,
						notCheckable = true,
						hasArrow = true,
						value = cid,
					}, level)
				end
			end
		elseif level == 2 then
			AddZoneButtons(UIDROPDOWNMENU_MENU_VALUE)
		end
	end, "MENU")

	local mapBtn = CreateFrame("Button", nil, chrome)
	mapBtn:SetSize(64, 18)
	mapBtn:SetPoint("LEFT", 4, 0)
	S:CreateBackdrop(mapBtn, "Default")
	mapBtn.fs = S:FontString(mapBtn, 10, "OUTLINE", nil, nil, "CENTER")
	mapBtn.fs:SetPoint("CENTER")
	mapBtn.fs:SetText((L["Maps"] or "Maps") .. " v")
	S:RegisterAccent(mapBtn.fs, "text")
	mapBtn:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, drop, mapBtn, 0, -4)
	end)

	local back = CreateFrame("Button", nil, chrome)
	back:SetSize(18, 18)
	back:SetPoint("LEFT", mapBtn, "RIGHT", 4, 0)
	S:CreateBackdrop(back, "Default")
	back.fs = S:FontString(back, 11, "OUTLINE", nil, nil, "CENTER")
	back.fs:SetPoint("CENTER")
	back.fs:SetText("<")
	back:SetScript("OnClick", function()
		if host.NavigateToParentMap then host:NavigateToParentMap() end
	end)
	back:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Back to parent map"] or "Back to parent map")
		GameTooltip:Show()
	end)
	back:SetScript("OnLeave", GameTooltip_Hide)

	-- centered zone name
	chrome.zoneName = S:FontString(chrome, 12, "OUTLINE", S.media.unitFont, nil, "CENTER")
	chrome.zoneName:SetPoint("CENTER")

	-- coordinates, right-aligned left of the close button
	chrome.coords = S:FontString(chrome, 10, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	chrome.coords:SetPoint("RIGHT", -28, 0)
	chrome.coords:SetText("")

	local tick = 0
	local lastShownID
	chrome:SetScript("OnUpdate", function(_, elapsed)
		tick = tick + elapsed
		if tick < 0.1 then return end
		tick = 0
		-- mapID is applied asynchronously after SetMapID -> refresh the title
		-- whenever the shown map actually changed instead of relying on hooks
		local curID = CurrentMapID()
		if curID ~= lastShownID then
			lastShownID = curID
			UpdateZoneName()
		end
		if not (WM.db.mapCoords and curID and host:IsShown()) then
			chrome.coords:SetText("")
			return
		end
		local ptxt, ctxt = "--", "--"
		local ppos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(curID, "player")
		if ppos then
			local px, py = ppos:GetXY()
			if px then ptxt = string.format("%.1f, %.1f", px * 100, py * 100) end
		end
		local canvas = WorldMapFrame.ScrollContainer
		if canvas and canvas.GetNormalizedCursorPosition then
			local cx, cy = canvas:GetNormalizedCursorPosition()
			if cx and cy then ctxt = string.format("%.1f, %.1f", cx * 100, cy * 100) end
		end
		chrome.coords:SetFormattedText("%s  |  %s", ptxt, ctxt)
	end)

	-- close button
	local close = CreateFrame("Button", nil, chrome)
	close:SetSize(16, 16)
	close:SetPoint("RIGHT", -4, 0)
	S:CreateBackdrop(close, "Default")
	close.fs = S:FontString(close, 11, "OUTLINE", nil, nil, "CENTER")
	close.fs:SetPoint("CENTER")
	close.fs:SetText("x")
	close:SetScript("OnClick", function() HideUIPanel(WorldMapFrame) end)

	-- inset the canvas a bit so our dark edge reads as the window border
	local canvas = host.ScrollContainer
	canvas:ClearAllPoints()
	canvas:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -26)
	canvas:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)

	-- corner scale handle --------------------------------------------------------
	local handle = CreateFrame("Frame", nil, host)
	handle:SetSize(20, 20)
	handle:SetAlpha(0.6)
	handle:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -4, 4)
	handle:SetFrameLevel(lvl)
	handle.t = handle:CreateTexture(nil, "OVERLAY")
	handle.t:SetAllPoints()
	handle.t:SetTexture([[Interface\Buttons\UI-AutoCastableOverlay]])
	handle.t:SetTexCoord(0.619, 0.760, 0.612, 0.762)
	handle.t:SetDesaturated(true)

	local grab = CreateFrame("Frame", nil, host)
	grab:SetFrameLevel(lvl + 5)
	grab:SetAllPoints(handle)
	grab:EnableMouse(true)
	grab:SetScript("OnEnter", function() handle.t:SetDesaturated(false) end)
	grab:SetScript("OnLeave", function() handle.t:SetDesaturated(true) end)
	grab:SetHitRectInsets(-16, 0, -16, 0)

	local baseDist, baseScale, mapX, mapY
	grab:SetScript("OnMouseDown", function(self)
		baseScale = host:GetScale()
		mapX = host:GetLeft()
		mapY = host:GetTop() - (UIParent:GetHeight() / baseScale)
		baseDist = CursorDist()
		self:SetScript("OnUpdate", function()
			local scale = CursorDist() / baseDist * baseScale
			if scale < 0.4 then scale = 0.4 elseif scale > 3 then scale = 3 end
			host:SetScale(scale)
			local s = baseScale / host:GetScale()
			host:ClearAllPoints()
			host:SetPoint("TOPLEFT", nil, "TOPLEFT", mapX * s, mapY * s)
		end)
		self:SetAllPoints(UIParent)
	end)
	grab:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		self:SetAllPoints(handle)
		WM.db.mapScale = host:GetScale()
		WM:SaveMapPos()
		WM:ApplyMapPos()
	end)
	WM.mapHandle, WM.mapGrab = handle, grab
end

-- Blizzard's canvas math (NormalizeUIPosition: cursor / canvasScale -
-- Child:GetLeft()) assumes the map frame renders at effective scale 1 - the
-- stock frame has ignoreParentScale="true" for exactly this reason. As soon
-- as the frame is scaled (by us or any other addon) every hover/click/zoom
-- position lands offset. GetCursorPosition is the single cursor source for
-- all of that math, so compensating it there fixes zone hover + navigation.
local function InstallCursorFix()
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if not sc or sc.suiCursorFix then return end
	sc.suiCursorFix = true
	local orig = sc.GetCursorPosition
	sc.GetCursorPosition = function(self, ...)
		local x, y = orig(self, ...)
		local es = WorldMapFrame:GetEffectiveScale()
		if x and es and es > 0 and es ~= 1 then x, y = x / es, y / es end
		return x, y
	end
end

local function SetupMapFrame()
	if WM.mapDone or not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
	WM.mapDone = true
	InstallCursorFix()

	-- detach from the UI panel system so other panels cannot move/close it
	WorldMapFrame:SetAttribute("UIPanelLayout-area", nil)
	WorldMapFrame:SetAttribute("UIPanelLayout-enabled", false)
	WorldMapFrame:SetIgnoreParentScale(false)
	WorldMapFrame.ScrollContainer:SetIgnoreParentScale(false)
	local found
	for _, name in ipairs(UISpecialFrames) do
		if name == "WorldMapFrame" then found = true break end
	end
	if not found then table.insert(UISpecialFrames, "WorldMapFrame") end

	WorldMapFrame:SetMovable(true)
	WorldMapFrame:SetClampedToScreen(true)
	WorldMapFrame:SetClampRectInsets(600, -600, -500, 500)

	BuildChrome()
	HideBlizzardChrome()

	-- re-anchor the canvas into our dark edge whenever Blizzard touches it
	local function FitCanvas()
		local canvas = WorldMapFrame.ScrollContainer
		canvas:ClearAllPoints()
		canvas:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 2, -26)
		canvas:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -2, 2)
	end
	if WorldMapFrame.OnFrameSizeChanged then
		hooksecurefunc(WorldMapFrame, "OnFrameSizeChanged", FitCanvas)
	end
	if WorldMapFrame.SynchronizeDisplayState then
		hooksecurefunc(WorldMapFrame, "SynchronizeDisplayState", function()
			WM:ApplyMapPos()
			FitCanvas()
		end)
	end

	WorldMapFrame:HookScript("OnShow", function()
		HideBlizzardChrome()
		FitCanvas()
		UpdateZoneName()
		WM:ApplyMapPos()
		WM:ApplyMapScale()
		-- remember-zoom restore
		local db = WM.db
		if db.rememberZoom and CurrentMapID() == lastMapID and lastZoom then
			local sc = WorldMapFrame.ScrollContainer
			if sc.InstantPanAndZoom then
				sc:InstantPanAndZoom(lastZoom, lastH, lastV)
				if sc.SetPanTarget then sc:SetPanTarget(lastH, lastV) end
			end
		end
	end)
	WorldMapFrame:HookScript("OnHide", function()
		local sc = WorldMapFrame.ScrollContainer
		lastMapID = CurrentMapID()
		lastZoom = sc and sc.GetCurrentZoom and sc:GetCurrentZoom()
		if sc and sc.GetCurrentPanTarget then
			lastH, lastV = sc:GetCurrentPanTarget()
		end
	end)
	if WorldMapFrame.SetMapID then
		hooksecurefunc(WorldMapFrame, "SetMapID", UpdateZoneName)
	end

	-- click a zone on a continent map -> navigate into it. Drags (panning the
	-- zoomed canvas) and combat clicks are ignored; GetMapInfoAtPosition returns
	-- the zone map itself on zone maps, so the mapID check filters those out.
	local downX, downY
	local scroll = WorldMapFrame.ScrollContainer
	-- clicks may land on the scroll child (map canvas) or the container itself,
	-- depending on which frame Blizzard made mouse-enabled on this client
	local clickFrames = { scroll }
	local child = scroll and ((scroll.GetCanvas and scroll:GetCanvas()) or scroll.Child)
	if child then clickFrames[#clickFrames + 1] = child end
	for _, cf in ipairs(clickFrames) do
		cf:HookScript("OnMouseDown", function(_, btn)
			if btn == "LeftButton" or btn == "RightButton" then downX, downY = GetCursorPosition() else downX = nil end
		end)
		cf:HookScript("OnMouseUp", function(_, btn)
			if btn == "RightButton" then
				-- right click anywhere on the canvas -> parent map (Blizzard behavior)
				local rdx, rdy = GetCursorPosition()
				local rmoved = rdx and math.abs(rdx - downX) + math.abs(rdy - downY) or 0
				downX = nil
				if rmoved <= 6 and WorldMapFrame.NavigateToParentMap then
					WorldMapFrame:NavigateToParentMap()
				end
				return
			end
			if btn ~= "LeftButton" or not downX then return end
			local dx, dy = GetCursorPosition()
			local moved = dx and math.abs(dx - downX) + math.abs(dy - downY) or 0
			downX = nil
			if moved > 6 or (InCombatLockdown and InCombatLockdown()) then return end
			local x, y
			if scroll.GetNormalizedCursorPosition then
				x, y = scroll:GetNormalizedCursorPosition()
			else
				-- manual fallback: cursor offset within the canvas rect
				local l, t, w, h = scroll:GetLeft(), scroll:GetTop(), scroll:GetWidth(), scroll:GetHeight()
				local es = scroll:GetEffectiveScale()
				if l and w and w > 0 and h > 0 then
					x = (dx / es - l) / w
					y = (t - dy / es) / h
				end
			end
			local curID = CurrentMapID()
			if not (x and y and curID) then return end
			local target
			if C_Map.GetMapInfoAtPosition then
				local info = C_Map.GetMapInfoAtPosition(curID, x, y)
				if info and info.mapID and info.mapID ~= curID then target = info.mapID end
			end
			-- fallback: hit-test child zone rects (clients without GetMapInfoAtPosition)
			if not target and C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap then
				for _, zm in ipairs(C_Map.GetMapChildrenInfo(curID) or {}) do
					if zm.mapType == 3 or zm.mapType == 4 then
						local x1, y1, x2, y2 = C_Map.GetMapRectOnMap(zm.mapID, curID)
						if x1 and x >= math.min(x1, x2) and x <= math.max(x1, x2)
							and y >= math.min(y1, y2) and y <= math.max(y1, y2) then
							target = zm.mapID
							break
						end
					end
				end
			end
			if target then GoToMap(target) end
		end)
	end

	WM:ApplyMapPos()
	WM:ApplyMapScale()
	WM:ApplyMapFade()
	UpdateZoneName()
end

function WM:UpdateMapFrame()
	if not self.mapDone then return end
	self:ApplyMapScale()
	self:ApplyMapFade()
	if self.mapHandle then
		local on = self.db.mapUnlock
		self.mapHandle:SetShown(on)
		self.mapGrab:SetShown(on)
	end
end

-- ---------------------------------------------------------------------------
-- fog reveal: unexplored map tiles are painted back at low alpha so the whole
-- zone outline is visible instead of black. Tile file data lives in
-- Modules/WorldMap/RevealData.lua keyed by map art ID.
-- ---------------------------------------------------------------------------
local revealPins = {}

local function RevealExploredSet(mapID)
	local seen = {}
	local list = C_MapExplorationInfo.GetExploredMapTextures(mapID)
	if list then
		for _, t in ipairs(list) do
			seen[t.textureWidth .. ":" .. t.textureHeight .. ":" .. t.offsetX .. ":" .. t.offsetY] = true
		end
	end
	return seen
end

-- explored areas as rect list (needed for the dynamic tile path)
local function RevealExploredRects(mapID)
	local out = {}
	local list = C_MapExplorationInfo.GetExploredMapTextures(mapID)
	if list then
		for _, t in ipairs(list) do
			out[#out + 1] = { w = t.textureWidth, h = t.textureHeight, x = t.offsetX, y = t.offsetY }
		end
	end
	return out
end

-- dynamic path: pull the zone's art tiles straight from the client so the
-- reveal works on flavors we have no baked tile table for (WotLK, Cata, retail)
local function NextPow2(n)
	local p = 16
	while p < n do p = p * 2 end
	return p
end

local function PaintTile(pin, ids, idx, pxW, pxH, x, y, tint, fullUpdate)
	local texture = pin.overlayTexturePool:Acquire()
	texture:SetSize(pxW, pxH)
	texture:SetTexCoord(0, pxW / NextPow2(pxW), 0, pxH / NextPow2(pxH))
	texture:SetPoint("TOPLEFT", x, -y)
	texture:SetTexture(ids[idx], nil, nil, "TRILINEAR")
	texture:SetDrawLayer("ARTWORK", -1)
	texture:SetVertexColor(tint.r, tint.g, tint.b)
	texture:SetAlpha(tint.a or 0.4)
	if fullUpdate and pin.textureLoadGroup then pin.textureLoadGroup:AddTexture(texture) end
	texture:Show()
end

local function RevealDynamic(pin, mapID, layerIndex, layerInfo, exploredRects, tint, fullUpdate)
	if not C_Map.GetMapArtLayerTextures then return false end
	local ids = C_Map.GetMapArtLayerTextures(mapID, layerIndex)
	local tileW, tileH = layerInfo.tileWidth, layerInfo.tileHeight
	if not (ids and tileW and tileH) or #ids == 0 then return false end
	local layerW = layerInfo.layerWidth or tileW
	local layerH = layerInfo.layerHeight or tileH
	local numWide, numTall = ceil(layerW / tileW), ceil(layerH / tileH)
	for j = 1, numTall do
		for k = 1, numWide do
			local idx = (j - 1) * numWide + k
			if ids[idx] then
				local x, y = (k - 1) * tileW, (j - 1) * tileH
				local pxW, pxH = min(tileW, layerW - x), min(tileH, layerH - y)
				local cx, cy = x + pxW / 2, y + pxH / 2
				local covered = false
				for _, r in ipairs(exploredRects) do
					if cx >= r.x and cx < r.x + r.w and cy >= r.y and cy < r.y + r.h then covered = true break end
				end
				if not covered then PaintTile(pin, ids, idx, pxW, pxH, x, y, tint, fullUpdate) end
			end
		end
	end
	return true
end

function WM:RevealOverlays(pin, fullUpdate)
	if not self.db.mapReveal then return end
	local mapID = pin:GetMap():GetMapID()
	if not mapID then return end

	local canvas = pin:GetMap():GetCanvasContainer()
	pin.layerIndex = canvas and canvas:GetCurrentLayerIndex() or 1
	local layers = C_Map.GetMapArtLayers(mapID)
	local layerInfo = layers and layers[pin.layerIndex]
	if not layerInfo then return end
	local tileW, tileH = layerInfo.tileWidth, layerInfo.tileHeight
	if not (tileW and tileH) then return end

	local tint = self.db.revealTint or { r = 0.4, g = 0.6, b = 1, a = 0.4 }

	-- dynamic path first: client-provided tile list works on every flavor
	if RevealDynamic(pin, mapID, pin.layerIndex, layerInfo, RevealExploredRects(mapID), tint, fullUpdate) then return end

	local data = ns.MapReveal
	local artID = C_Map.GetMapArtID(mapID)
	local artData = data and artID and data[artID]
	if not artData then return end
	local explored = RevealExploredSet(mapID)
	for key, fileDataIDs in pairs(artData) do
		if not explored[key] then
			local w, h, ox, oy = strsplit(":", key)
			w, h, ox, oy = tonumber(w), tonumber(h), tonumber(ox), tonumber(oy)
			local ids = {}
			for id in fileDataIDs:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
			local numWide = ceil(w / tileW)
			local numTall = ceil(h / tileH)
			local pxW, fileW, pxH, fileH
			for j = 1, numTall do
				if j < numTall then
					pxH, fileH = tileH, 256
				else
					pxH = mod(h, tileH)
					if pxH == 0 then pxH = tileH end
					fileH = 16
					while fileH < pxH do fileH = fileH * 2 end
				end
				for k = 1, numWide do
					if k < numWide then
						pxW, fileW = tileW, 256
					else
						pxW = mod(w, tileW)
						if pxW == 0 then pxW = tileW end
						fileW = 16
						while fileW < pxW do fileW = fileW * 2 end
					end
					local texture = pin.overlayTexturePool:Acquire()
					texture:SetSize(pxW, pxH)
					texture:SetTexCoord(0, pxW / fileW, 0, pxH / fileH)
					texture:SetPoint("TOPLEFT", ox + tileW * (k - 1), -(oy + tileH * (j - 1)))
					texture:SetTexture(ids[(j - 1) * numWide + k], nil, nil, "TRILINEAR")
					texture:SetDrawLayer("ARTWORK", -1)
					texture:SetVertexColor(tint.r, tint.g, tint.b)
					texture:SetAlpha(tint.a or 0.4)
					if fullUpdate and pin.textureLoadGroup then pin.textureLoadGroup:AddTexture(texture) end
					texture:Show()
				end
			end
		end
	end
end

local function HookExplorationPin(pin)
	if pin.suiRevealHooked or not pin.RefreshOverlays then return end
	pin.suiRevealHooked = true
	revealPins[#revealPins + 1] = pin
	-- pool textures must come back untinted or Blizzard's own overlays inherit it
	local pool = pin.overlayTexturePool
	if pool and not pool.suiResetHooked then
		pool.suiResetHooked = true
		local orig = pool.resetterFunc
		pool.resetterFunc = function(p, tex)
			if orig then orig(p, tex) end
			tex:SetVertexColor(1, 1, 1, 1)
			tex:SetAlpha(1)
			tex:ClearAllPoints()
		end
	end
	hooksecurefunc(pin, "RefreshOverlays", function(self, fullUpdate)
		S:SafeCall("WorldMap:Reveal", WM.RevealOverlays, WM, self, fullUpdate)
	end)
end

local function InstallReveal()
	if WM.revealInit or not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return end
	if not (C_Map and C_Map.GetMapArtID and C_Map.GetMapArtLayers
		and C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return end
	WM.revealInit = true
	WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate", HookExplorationPin)
	if BattlefieldMapFrame and BattlefieldMapFrame.EnumeratePinsByTemplate then
		BattlefieldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate", HookExplorationPin)
	end
	-- late-created pins (first map open, data providers re-registered)
	WorldMapFrame:HookScript("OnShow", function()
		WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate", HookExplorationPin)
		if BattlefieldMapFrame and BattlefieldMapFrame.EnumeratePinsByTemplate then
			BattlefieldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate", HookExplorationPin)
		end
	end)
end

function WM:ApplyReveal()
	for _, pin in ipairs(revealPins) do
		if pin.overlayTexturePool then pin.overlayTexturePool:ReleaseAll() end
		if pin.RefreshOverlays then pin:RefreshOverlays() end
	end
end

-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- SentinelUI chrome: skinned window, zoom controls, coord readout, fade
-- ---------------------------------------------------------------------------
local function Zoom(btn, dir)
	-- Blizzard exposes ZoomIn/ZoomOut on the ScrollContainer (newer clients)
	-- or the map frame itself; fall through both paths
	local sc = WorldMapFrame.ScrollContainer or WorldMapFrame
	if dir > 0 then
		if sc.ZoomIn then pcall(function() sc:ZoomIn() end) end
	else
		if sc.ZoomOut then pcall(function() sc:ZoomOut() end) end
	end
end

function WM:ApplyChrome()
	if self._chromeDone then return end
	local wmf = WorldMapFrame
	if not wmf then
		-- map addon may already be loaded (event fired before we registered)
		-- or load on demand later: poll until it exists, plus hook the toggle
		if not self._chromeWait then
			self._chromeWait = true
			if type(ToggleWorldMap) == "function" then
				hooksecurefunc("ToggleWorldMap", function()
					C_Timer.After(0, function() S:SafeCall("WorldMap:Chrome", WM.ApplyChrome, WM) end)
				end)
			end
			C_Timer.NewTicker(2, function(t)
				if WorldMapFrame or (t and t.cancelled) then
					t:Cancel()
					S:SafeCall("WorldMap:Chrome", WM.ApplyChrome, WM)
				end
			end)
		end
		return
	end
	WorldMapFrame:HookScript("OnShow", function() S:SafeCall("WorldMap:Chrome", WM.ApplyChrome, WM) end)
	self._chromeDone = true
	-- backdrop around the whole map window in our dark template style
	local okSkin = pcall(function()
		if WorldMapFrame.NineSlice then WorldMapFrame.NineSlice:Hide() end
		if WorldMapFrame.BorderFrame then WorldMapFrame.BorderFrame:Hide() end
		S:SetTemplate(WorldMapFrame, "Default", "MEDIUM")
	end)
	if not okSkin then S:LogWarn("worldmap", "skin apply failed - frame protected") end
	-- accent title strip
	local strip = CreateFrame("Frame", "SentinelUIWorldMapStrip", WorldMapFrame)
	strip:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 1, -1)
	strip:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -1, -1)
	strip:SetHeight(24)
	S:SetTemplate(strip, "Default")
	local t = S:FontString(strip, 11, "OUTLINE")
	t:SetPoint("LEFT", 8, 0)
	t:SetText("|cff" .. S.accentHex .. "Weltkarte|r")
	strip.title = t
	self._strip = strip
	-- coordinates readout right side
	local coords = S:FontString(strip, 10, "OUTLINE")
	coords:SetPoint("RIGHT", -8, 0)
	strip.coords = coords
	-- zoom buttons +/-/reset bottom right of the window
	local function ZBtn(label, xOff, fn)
		local b = CreateFrame("Button", nil, WorldMapFrame)
		b:SetSize(22, 22)
		b:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", xOff, 6)
		S:SetTemplate(b, "Default")
		local s = S:FontString(b, 12, "OUTLINE")
		s:SetAllPoints() s:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	ZBtn("-", -8, function() Zoom(nil, -1) end)
	ZBtn("+", -32, function() Zoom(nil, 1) end)
	local rst = CreateFrame("Button", nil, WorldMapFrame)
	rst:SetSize(44, 22)
	rst:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -56, 6)
	S:SetTemplate(rst, "Default")
	local rs = S:FontString(rst, 9, "OUTLINE")
	rs:SetAllPoints() rs:SetText("RESET")
	rst:SetScript("OnClick", function()
		local sc = WorldMapFrame.ScrollContainer
		if sc and sc.ResetZoom then pcall(function() sc:ResetZoom() end)
		elseif sc and sc.ZoomOut then for _ = 1, 10 do pcall(function() sc:ZoomOut() end) end end
	end)
	-- live cursor coords ticker
	strip:SetScript("OnUpdate", function(self2, dt)
		self2._t = (self2._t or 0) + dt
		if self2._t < 0.1 then return end
		self2._t = 0
		local sc = WorldMapFrame.ScrollContainer or WorldMapFrame
		if not sc then return end
		local mx, my = GetCursorPosition()
		local scale = sc.GetEffectiveScale and sc:GetEffectiveScale() or 1
		local l, b2 = sc:GetLeft() or 0, sc:GetBottom() or 0
		local w, h = sc:GetWidth() or 1, sc:GetHeight() or 1
		local cx = (mx / scale - l) / w
		local cy = 1 - (my / scale - b2) / h
		if cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
			coords:SetText(format("%.1f, %.1f", cx * 100, cy * 100))
		else coords:SetText("") end
	end)
	S:LogInfo("worldmap", "chrome applied")
	-- fade the whole window slightly when the cursor leaves it
	WorldMapFrame:HookScript("OnEnter", function() WorldMapFrame:SetAlpha(1) end)
	WorldMapFrame:HookScript("OnLeave", function()
		if self.db and self.db.fadeOut ~= false then WorldMapFrame:SetAlpha(0.92) end
	end)
end

function WM:Initialize()
	S:SafeCall("WorldMap:Chrome", WM.ApplyChrome, WM)
	-- world map is a load-on-demand panel on some clients
	local function Setup()
		SetupProvider()
		self:ApplyZoneLevels()
		InstallReveal()
		InstallCursorFix() -- harmless at scale 1, essential whenever anything scales the map
		if self.db.customMap and not ConflictingMapAddon() then SetupMapFrame() end
	end
	if WorldMapFrame and WorldMapFrame.dataProviders then
		Setup()
	else
		self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_WorldMap" and WorldMapFrame then Setup() end
		end)
		C_Timer.After(5, function()
			if not WM.provider or (self.db.customMap and not WM.mapDone) then Setup() end
		end)
	end
	local conflict = ConflictingMapAddon()
	if conflict then
		S:Print(L["Another map addon is enabled - map pin and zone level features may overlap."])
		if self.db.customMap then
			S:Print(L["Another addon manages the map window - SentinelUI map window disabled."])
		end
	end
end

function WM:Update()
	self:ApplyZoneLevels()
	self:RefreshPins()
	self:UpdateMapFrame()
	if self.revealInit then self:ApplyReveal() end
end
