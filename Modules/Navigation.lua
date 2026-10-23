-- Navigation: rotating direction arrow with title/distance/ETA, world map pins
-- with a dashed route line, minimap edge pin, quest navigation (POI + external
-- DB fallback), corpse waypoint, /sway commands and a TomTom-compat facade.
-- Coordinate math prefers HereBeDragons (vendored) with client fallbacks.
local _, ns = ...
local S = ns.S
local L = S.L
local NAV = S:NewModule("Navigation")

local abs, atan2, cos, floor, sin, sqrt, min, max = math.abs, math.atan2, math.cos, math.floor, math.sin, math.sqrt, math.min, math.max
local tinsert, tremove, format, strtrim, strlower, tonumber = table.insert, table.remove, string.format, strtrim, strlower, tonumber
local IsSecret = S.IsSecret
local PI2 = math.pi * 2

local HBD = LibStub and (LibStub("HereBeDragonsQuestie-2.0", true) or LibStub("HereBeDragons-2.0", true))

-- when the real TomTom addon is installed it owns the arrow/pins; we keep a
-- local waypoint mirror (QuestScope liveness tracking) and forward everything
local RealTomTom

local function ForwardAdd(wp, mapID, crazy)
	if not RealTomTom then return end
	local ok, uid = pcall(RealTomTom.AddWaypoint, RealTomTom, mapID, wp.x, wp.y, {
		title = wp.title, from = "SentinelUI", persistent = false, silent = true,
		-- explicit crazy flag: TomTom's own default is its autoqueue profile
		-- setting, which may be off -> the arrow would never react
		crazy = crazy,
	})
	if ok then wp.ttuid = uid end
end

local function ForwardRemove(wp)
	if RealTomTom and wp and wp.ttuid and RealTomTom.RemoveWaypoint then
		pcall(RealTomTom.RemoveWaypoint, RealTomTom, wp.ttuid)
	end
end

local function ForwardArrow()
	local a = NAV.active
	if not (RealTomTom and a and a.wp.ttuid) then return end
	if RealTomTom.SetCrazyArrow then
		pcall(RealTomTom.SetCrazyArrow, RealTomTom, a.wp.ttuid, NAV.db.arrival or 15, a.wp.title)
	end
end

local function CurrentMap()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function MapWorldSize(mapID)
	if C_Map and C_Map.GetMapWorldSize then
		local w, h = C_Map.GetMapWorldSize(mapID)
		if w and w > 0 then return w, h end
	end
	if GetMapWorldSize then
		local w, h = GetMapWorldSize(mapID)
		if w and w > 0 then return w, h end
	end
end

-- distance (yards) + bearing (clockwise from north) player -> map coords
local function VectorTo(mapID, mx, my)
	if HBD then
		local px, py, pInst = HBD:GetPlayerWorldPosition()
		local wx, wy, wInst = HBD:GetWorldCoordinatesFromZone(mx, my, mapID)
		if px and wx then
			if pInst ~= wInst then return nil, nil, true end
			local angle, dist = HBD:GetWorldVector(pInst, px, py, wx, wy)
			if angle and dist then return dist, angle end
		end
	end
	-- fallback: normalized map math when the player resolves on the same map
	if C_Map and C_Map.GetPlayerMapPosition then
		local ppos = C_Map.GetPlayerMapPosition(mapID, "player")
		local w, h = MapWorldSize(mapID)
		if ppos and ppos.GetXY and w and w > 0 then
			local px, py = ppos:GetXY()
			if px and not IsSecret(px) then
				local dx, dy = (mx - px) * w, (my - py) * h
				local b = atan2(dx, -dy)
				return sqrt(dx * dx + dy * dy), b < 0 and b + PI2 or b
			end
		end
	end
end

-- waypoint store ------------------------------------------------------------
local function WP()
	local g = S.db.global
	g.nav = g.nav or { waypoints = {} }
	return g.nav.waypoints
end

function NAV:AddWaypoint(mapID, x, y, title, opts)
	if not (mapID and x and y) then return end
	opts = opts or {}
	local wp = { x = x, y = y, title = title or L["Waypoint"],
		corpse = opts.corpse, chain = opts.chain, seq = opts.seq }
	local list = WP()[mapID]
	if not list then list = {} WP()[mapID] = list end
	tinsert(list, wp)
	if not opts.silent then
		S:Print(format(L["Waypoint set: %s (%.1f, %.1f)"], wp.title, x * 100, y * 100))
	end
	self:RefreshPins()
	-- non-silent waypoints become the arrow target immediately; silent ones
	-- (multi-spawn chain picks) wait in the queue
	local isTarget = opts.crazy ~= false and not opts.silent
	ForwardAdd(wp, mapID, isTarget)
	if isTarget then
		self.active = { mapID = mapID, wp = wp }
		if self.arrow then self.arrow.title:SetText(wp.title) self.arrow:Show() end
		ForwardArrow()
	end
	return wp
end

function NAV:RemoveWaypoint(mapID, index)
	local list = WP()[mapID]
	if not list then return end
	local removed = tremove(list, index)
	ForwardRemove(removed)
	if not next(list) then WP()[mapID] = nil end
	if removed and self.active and self.active.wp == removed then
		self.active = nil
		if self.arrow then self.arrow:Hide() end
	end
	self:RefreshPins()
end

function NAV:RemoveWaypointRef(mapID, wp)
	local list = WP()[mapID]
	if not (list and wp) then return end
	for i, w in ipairs(list) do
		if w == wp then tremove(list, i) ForwardRemove(wp) break end
	end
	if not next(list) then WP()[mapID] = nil end
	if self.active and self.active.wp == wp then
		self.active = nil
		if self.arrow then self.arrow:Hide() end
	end
	self:RefreshPins()
end

function NAV:IsWaypointLive(mapID, wp)
	local list = WP()[mapID]
	if not (list and wp) then return false end
	for _, w in ipairs(list) do if w == wp then return true end end
	return false
end

function NAV:ClearWaypoints(mapID)
	if RealTomTom then
		for m, list in pairs(WP()) do
			if not mapID or m == mapID then
				for _, wp in ipairs(list) do ForwardRemove(wp) end
			end
		end
	end
	if mapID then WP()[mapID] = nil else wipe(WP()) end
	self.active = nil
	if self.arrow then self.arrow:Hide() end
	if RealTomTom and RealTomTom.ClearWaypoint then pcall(RealTomTom.ClearWaypoint, RealTomTom) end
	self:RefreshPins()
end

function NAV:SetArrowToClosest()
	local px, py, pInst = HBD and HBD:GetPlayerWorldPosition()
	local best, bestDist
	for mapID, list in pairs(WP()) do
		for _, wp in ipairs(list) do
			local wx, wy, wInst = HBD and HBD:GetWorldCoordinatesFromZone(wp.x, wp.y, mapID)
			if px and wx and pInst == wInst then
				local d = sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
				if not bestDist or d < bestDist then
					bestDist, best = d, { mapID = mapID, wp = wp }
				end
			end
		end
	end
	self.active = best
	if self.arrow then
		if best then self.arrow.title:SetText(best.wp.title or L["Waypoint"]) self.arrow:Show()
		else self.arrow:Hide() end
	end
	ForwardArrow()
end

-- arrival: continue the same chain (pick 2/n, 3/n ...); never jump to an
-- unrelated leftover waypoint — with nothing left the arrow just hides
function NAV:SetArrowToNext(chain, seq)
	if chain then
		seq = seq or 0
		local nxt, nxtSeq
		for mapID, list in pairs(WP()) do
			for _, wp in ipairs(list) do
				if wp.chain == chain and (wp.seq or 0) > seq and (not nxtSeq or wp.seq < nxtSeq) then
					nxt, nxtSeq = { mapID = mapID, wp = wp }, wp.seq
				end
			end
		end
		if nxt then
			self.active = nxt
			if self.arrow then self.arrow.title:SetText(nxt.wp.title or L["Waypoint"]) self.arrow:Show() end
			ForwardArrow()
			return
		end
	end
	self.active = nil
	if self.arrow then self.arrow:Hide() end
end

function NAV:RemoveActiveWaypoint()
	local active = self.active
	if not active then return end
	local list = WP()[active.mapID]
	if list then
		for i, wp in ipairs(list) do
			if wp == active.wp then tremove(list, i) ForwardRemove(wp) break end
		end
		if not next(list) then WP()[active.mapID] = nil end
	end
	self.active = nil
	self:RefreshPins()
end

-- the arrow ------------------------------------------------------------------
local function HeadingColor(a)
	-- a = 0 (dead-on) .. 1 (opposite): green -> yellow -> red
	local c = NAV.db
	if a <= 0.02 then return c.exactColor.r, c.exactColor.g, c.exactColor.b end
	if a < 0.5 then
		local t = a * 2
		return c.goodColor.r + (c.midColor.r - c.goodColor.r) * t,
			c.goodColor.g + (c.midColor.g - c.goodColor.g) * t,
			c.goodColor.b + (c.midColor.b - c.goodColor.b) * t
	end
	local t = (a - 0.5) * 2
	return c.midColor.r + (c.badColor.r - c.midColor.r) * t,
		c.midColor.g + (c.badColor.g - c.midColor.g) * t,
		c.midColor.b + (c.badColor.b - c.badColor.b) * t
end

function NAV:BuildArrow()
	local size = self.db.arrowSize or 56
	local f = CreateFrame("Button", "SentinelUINavArrow", UIParent, S.BackdropTemplate)
	f:SetSize(size, size + 44)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f:RegisterForClicks("RightButtonUp")

	-- thin accent ring behind the arrow head
	f.ring = f:CreateTexture(nil, "BACKGROUND")
	f.ring:SetPoint("TOP", f, "TOP", 0, 0)
	f.ring:SetSize(size + 6, size + 6)
	f.ring:SetTexture("Interface\\Buttons\\WHITE8X8")
	f.ring:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.15)

	f.tex = f:CreateTexture(nil, "OVERLAY")
	f.tex:SetPoint("TOP", f, "TOP", 0, 0)
	f.tex:SetSize(size, size)
	f.tex:SetTexture(S.media.navArrow)

	f.title = S:FontString(f, 11, "OUTLINE")
	f.title:SetPoint("TOP", f.tex, "BOTTOM", 0, -2)
	f.dist = S:FontString(f, 10, "OUTLINE")
	f.dist:SetPoint("TOP", f.title, "BOTTOM", 0, -1)
	f.tta = S:FontString(f, 10, "OUTLINE")
	f.tta:SetPoint("TOP", f.dist, "BOTTOM", 0, -1)

	f:SetScript("OnEnter", function(self2)
		GameTooltip:SetOwner(self2, "ANCHOR_CURSOR")
		GameTooltip:AddLine(L["Navigation Arrow"], 1, 1, 1)
		GameTooltip:AddLine(L["Right-click: clear waypoint"], 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:SetScript("OnClick", function(_, btn)
		if btn == "RightButton" then
			NAV.active = nil
			f:Hide()
			S:Print(L["Waypoint cleared."])
		end
	end)
	f:SetScript("OnMouseWheel", function(_, delta)
		local s = min(160, max(24, (NAV.db.arrowSize or 56) + delta * 4))
		NAV.db.arrowSize = s
		f:SetSize(s, s + 44)
		f.tex:SetSize(s, s)
		f.ring:SetSize(s + 6, s + 6)
	end)

	local lastDist, acc, speed = 0, 0, 0
	f:SetScript("OnUpdate", function(self2, elapsed)
		local active = NAV.active
		if not active then self2:Hide() return end
		local dist, bearing, otherZone = VectorTo(active.mapID, active.wp.x, active.wp.y)
		if not dist then
			self2.tex:SetVertexColor(0.5, 0.5, 0.5)
			self2.dist:SetText(otherZone and L["other zone"] or "")
			self2.tta:SetText("")
			return
		end
		if dist <= (NAV.db.arrival or 15) then
			S:Print(format(L["Arrived: %s"], active.wp.title or L["Waypoint"]))
			if NAV.db.pingOnArrive ~= false then pcall(PlaySound, 3175) end
			local chain, seq = active.wp.chain, active.wp.seq
			NAV:RemoveActiveWaypoint()
			NAV:SetArrowToNext(chain, seq)
			return
		end
		-- verified convention on this client: relative = bearing + facing,
		-- texture rotates by -relative (CCW positive)
		local facing = GetPlayerFacing and GetPlayerFacing() or 0
		local rel = (bearing + facing) % PI2
		if self2.tex.SetRotation then self2.tex:SetRotation(-rel) end
		self2.tex:SetVertexColor(HeadingColor(abs((math.pi - abs(rel % PI2)) / math.pi)))
		-- grow with distance for pseudo-depth
		local sz = NAV.db.arrowSize or 56
		local sc = min(1.35, max(0.75, 0.55 + dist / 500))
		self2.tex:SetSize(sz * sc, sz * sc)
		self2.dist:SetText(NAV.db.showDistance ~= false and format("%d " .. L["yards"], dist) or "")
		if NAV.db.showETA ~= false then
			acc = acc + elapsed
			if acc >= 1 then
				local cur = lastDist > 0 and (lastDist - dist) / acc or 0
				speed = (speed + cur) / 2
				if speed > 0.5 then
					local eta = abs(dist / speed)
					self2.tta:SetFormattedText("%d:%02d", floor(eta / 60), floor(eta % 60))
				else
					self2.tta:SetText("-:--")
				end
				lastDist, acc = dist, 0
			end
		else
			self2.tta:SetText("")
		end
	end)
	f:Hide()
	self.arrow = f
	S:CreateMover(f, "navArrow", L["Navigation Arrow"], { "TOP", "UIParent", "TOP", 0, -220 }, "navigation")
	S:AttachMoverDrag(f, "navArrow")
end

-- world map pins + route ------------------------------------------------------
local function MapCanvas()
	local wmf = _G.WorldMapFrame
	return wmf and (wmf.GetCanvas and wmf:GetCanvas() or wmf.ScrollContainer)
end

local function CursorToMap(sc, canvas)
	if sc.GetNormalizedCursorPosition then return sc:GetNormalizedCursorPosition() end
	local cx, cy = GetCursorPosition()
	local l, b, w, h = canvas:GetRect()
	if not l then return end
	local scale = canvas:GetEffectiveScale()
	return (cx / scale - l) / w, (b + h - cy / scale) / h
end

function NAV:RefreshPins()
	local wmf = _G.WorldMapFrame
	if not wmf or not self.pins then return end
	-- real TomTom draws its own pins; ours would double every marker
	if RealTomTom then
		for _, pin in ipairs(self.pins) do pin:Hide() end
		self:UpdateRoute()
		return
	end
	for _, pin in ipairs(self.pins) do pin:Hide() end
	local canvas = MapCanvas()
	if not (canvas and wmf:IsShown() and self.db.worldmapPin) then self:UpdateRoute() return end
	local mapID = wmf.GetMapID and wmf:GetMapID()
	local cw, ch = canvas:GetSize()
	if not (mapID and cw and cw > 0) then self:UpdateRoute() return end
	local shown = {}
	for wmap, list in pairs(WP()) do
		for _, wp in ipairs(list) do
			local tx, ty
			if wmap == mapID then tx, ty = wp.x, wp.y
			elseif HBD then tx, ty = HBD:TranslateZoneCoordinates(wp.x, wp.y, wmap, mapID) end
			if tx and tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1 then
				shown[#shown + 1] = { wp = wp, mapID = wmap, x = tx, y = ty }
			end
		end
	end
	local size = self.db.pinSize or 16
	for n, item in ipairs(shown) do
		local pin = self.pins[n]
		if not pin then
			pin = CreateFrame("Button", nil, canvas)
			pin.tex = pin:CreateTexture(nil, "OVERLAY")
			pin.tex:SetAllPoints()
			pin.tex:SetTexture(S.media.navPin)
			pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			pin:SetScript("OnEnter", function(self2)
				GameTooltip:SetOwner(self2, "ANCHOR_CURSOR")
				GameTooltip:AddLine(self2.wp and self2.wp.title or L["Waypoint"], 1, 1, 1)
				GameTooltip:AddLine(L["Left-click: navigate | Right-click: remove"], 0.6, 0.6, 0.6)
				GameTooltip:Show()
			end)
			pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
			pin:SetScript("OnClick", function(self2, btn)
				if btn == "RightButton" then
					local list = WP()[self2.mapID]
					if list then for i, w in ipairs(list) do if w == self2.wp then NAV:RemoveWaypoint(self2.mapID, i) break end end end
				else
					NAV.active = { mapID = self2.mapID, wp = self2.wp }
					if NAV.arrow then NAV.arrow.title:SetText(self2.wp.title or L["Waypoint"]) NAV.arrow:Show() end
				end
			end)
			self.pins[n] = pin
		end
		pin.mapID, pin.wp = item.mapID, item.wp
		local active = self.active and self.active.mapID == item.mapID and self.active.wp == item.wp
		pin:SetSize(active and size * 1.5 or size, active and size * 1.5 or size)
		pin.tex:SetVertexColor(active and 0.3 or 1, active and 0.9 or 1, active and 1 or 1, 1)
		pin:SetAlpha(self.db.pinAlpha or 1)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", canvas, "TOPLEFT", item.x * cw, -item.y * ch)
		pin:Show()
	end
	self:UpdateRoute()
end

function NAV:UpdateRoute()
	local segs = self.routeSegs
	local function HideAll() if segs then for _, t in ipairs(segs) do t:Hide() end end end
	local wmf = _G.WorldMapFrame
	local canvas = MapCanvas()
	local active = self.active
	if not (wmf and wmf:IsShown() and canvas and active) then return HideAll() end
	local mapID = wmf.GetMapID and wmf:GetMapID()
	if not mapID then return HideAll() end
	local ppos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
	local px = ppos and ppos.GetXY and ppos:GetXY()
	local py = ppos and select(2, ppos:GetXY())
	if not px or IsSecret(px) then return HideAll() end
	local tx, ty
	if HBD then tx, ty = HBD:TranslateZoneCoordinates(active.wp.x, active.wp.y, active.mapID, mapID, true) end
	if tx then
		tx, ty = min(max(tx, 0), 1), min(max(ty, 0), 1)
	else
		local _, bearing = VectorTo(active.mapID, active.wp.x, active.wp.y)
		if not bearing then return HideAll() end
		local dx, dy = sin(bearing), -cos(bearing)
		local t = math.huge
		if dx > 1e-6 then t = min(t, (1 - px) / dx) elseif dx < -1e-6 then t = min(t, -px / dx) end
		if dy > 1e-6 then t = min(t, (1 - py) / dy) elseif dy < -1e-6 then t = min(t, -py / dy) end
		if t == math.huge or t <= 0 then return HideAll() end
		tx, ty = px + dx * t, py + dy * t
	end
	local cw, ch = canvas:GetSize()
	if not cw or cw == 0 then return HideAll() end
	local x1, y1, x2, y2 = px * cw, py * ch, tx * cw, ty * ch
	local dx, dy = x2 - x1, y2 - y1
	local len = sqrt(dx * dx + dy * dy)
	if len < 20 then return HideAll() end
	segs = segs or {}
	self.routeSegs = segs
	local ux, uy = dx / len, dy / len
	local ang = atan2(-uy, ux)
	local n = 0
	for d = 0, len - 10, 18 do
		n = n + 1
		local t = segs[n]
		if not t then
			t = canvas:CreateTexture(nil, "OVERLAY", nil, 6)
			t:SetTexture("Interface\\Buttons\\WHITE8X8")
			t:SetVertexColor(0.25, 0.85, 1, 0.9)
			segs[n] = t
		end
		t:ClearAllPoints()
		t:SetPoint("CENTER", canvas, "TOPLEFT", x1 + ux * (d + 5), -(y1 + uy * (d + 5)))
		t:SetSize(10, 4)
		t:SetRotation(ang)
		t:Show()
	end
	for i = n + 1, #segs do segs[i]:Hide() end
end

function NAV:HookWorldMap()
	local wmf = _G.WorldMapFrame
	if not wmf or not wmf.ScrollContainer then return end
	self.pins = self.pins or {}
	local canvas = MapCanvas()
	if not canvas then return end
	local sc = wmf.ScrollContainer
	for _, target in ipairs({ sc, canvas }) do
		target:HookScript("OnMouseUp", function(_, btn)
			if btn ~= "RightButton" or not NAV.db.clickCreate or InCombatLockdown() then return end
			local mod = NAV.db.createModifier or "CTRL"
			local down = mod == "NONE" or
				(mod == "CTRL" and IsControlKeyDown()) or
				(mod == "ALT" and IsAltKeyDown()) or
				(mod == "SHIFT" and IsShiftKeyDown())
			if not down then return end
			local x, y = CursorToMap(sc, canvas)
			if not x or x < 0 or x > 1 or y < 0 or y > 1 then return end
			local mapID = wmf.GetMapID and wmf:GetMapID()
			if not mapID then return end
			local now = GetTime()
			if NAV.lastMapClick and now - NAV.lastMapClick < 0.5 then return end
			NAV.lastMapClick = now
			NAV:AddWaypoint(mapID, x, y, L["Waypoint"])
		end)
	end
	-- coordinate readout: player + cursor at the bottom of the map
	if not wmf.suiCoords then
		local fs = S:FontString(wmf, 11, "OUTLINE", S.media.numberFont, nil, "LEFT")
		fs:SetPoint("BOTTOMLEFT", wmf, "BOTTOMLEFT", 10, 6)
		wmf.suiCoords = fs
		wmf:HookScript("OnUpdate", function()
			if not NAV.db or NAV.db.mapCoords == false then fs:Hide() return end
			local mapID = wmf.GetMapID and wmf:GetMapID()
			if not mapID then fs:Hide() return end
			fs:Show()
			local px, py
			if C_Map and C_Map.GetPlayerMapPosition then
				local pos = C_Map.GetPlayerMapPosition(mapID, "player")
				if pos and pos.GetXY then px, py = pos:GetXY() end
			end
			local cx, cy = CursorToMap(sc, canvas)
			local left = px and format("%s: %.1f, %.1f", L["Player"], px * 100, py * 100) or L["Player"] .. ": -"
			local right = (cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1)
				and format("  %s: %.1f, %.1f", L["Cursor"], cx * 100, cy * 100) or ""
			fs:SetText(left .. right)
		end)
	end
	wmf:HookScript("OnShow", function() NAV:RefreshPins() end)
	if wmf.OnMapChanged then hooksecurefunc(wmf, "OnMapChanged", function() NAV:RefreshPins() end) end
	if canvas.HookScript then canvas:HookScript("OnSizeChanged", function() NAV:RefreshPins() end) end
	local ticker = CreateFrame("Frame", nil, canvas)
	ticker.t = 0
	ticker:SetScript("OnUpdate", function(s, e)
		s.t = s.t + e
		if s.t < 0.25 then return end
		s.t = 0
		NAV:UpdateRoute()
	end)
end

-- minimap edge pin ------------------------------------------------------------
function NAV:BuildMinimapPin()
	local mm = _G.Minimap
	if not mm then return end
	local pin = CreateFrame("Frame", "SentinelUIMinimapWaypoint", mm)
	pin:SetSize(18, 18)
	pin:SetFrameLevel(mm:GetFrameLevel() + 5)
	pin.tex = pin:CreateTexture(nil, "OVERLAY")
	pin.tex:SetAllPoints()
	pin.tex:SetTexture(S.media.navPin)
	pin.lines = {}
	pin:SetScript("OnUpdate", function(self2)
		local function HideAll()
			self2:Hide()
			for _, t in ipairs(self2.lines) do t:Hide() end
		end
		local active = NAV.active
		if not active or not NAV.db.minimapPin then return HideAll() end
		local dist, bearing = VectorTo(active.mapID, active.wp.x, active.wp.y)
		if not dist then return HideAll() end
		local angle = bearing
		if GetCVar("rotateMinimap") == "1" then
			angle = (bearing + (GetPlayerFacing and GetPlayerFacing() or 0)) % PI2
		end
		local radius = mm:GetWidth() / 2 - 8
		local x, y = sin(angle) * radius, cos(angle) * radius
		if S.db.profile.minimap and S.db.profile.minimap.shape ~= "ROUND" then
			x = min(radius, max(-radius, x))
			y = min(radius, max(-radius, y))
		end
		self2:ClearAllPoints()
		self2:SetPoint("CENTER", mm, "CENTER", x, y)
		self2:Show()
		local ux, uy = sin(angle), cos(angle)
		local rot = math.pi / 2 - angle
		local n = 0
		for d = 4, radius - 10, 10 do
			n = n + 1
			local t = self2.lines[n]
			if not t then
				t = self2:CreateTexture(nil, "OVERLAY")
				t:SetTexture("Interface\\Buttons\\WHITE8X8")
				t:SetVertexColor(0.25, 0.85, 1, 0.85)
				self2.lines[n] = t
			end
			t:ClearAllPoints()
			t:SetPoint("CENTER", mm, "CENTER", ux * (d + 3), uy * (d + 3))
			t:SetSize(6, 3)
			t:SetRotation(rot)
			t:Show()
		end
		for i = n + 1, #self2.lines do self2.lines[i]:Hide() end
	end)
	self.mmPin = pin
end

-- quest navigation -------------------------------------------------------------
local zoneMaps
local function ZoneMaps()
	if zoneMaps then return zoneMaps end
	zoneMaps = {}
	local current = CurrentMap()
	if current then zoneMaps[current] = true end
	if C_Map and C_Map.GetMapChildrenInfo then
		for _, continent in ipairs({ 1414, 1415, 1945, 113, 424, 619, 875, 876, 1550, 1978, 2132, 2274 }) do
			local ok, children = pcall(C_Map.GetMapChildrenInfo, continent)
			if ok and children then
				for _, info in ipairs(children) do if info.mapID then zoneMaps[info.mapID] = true end end
			end
		end
	end
	return zoneMaps
end

local function QuestPOIOnMap(questID, mapID)
	if not (C_QuestLog and C_QuestLog.GetQuestsOnMap and mapID) then return end
	local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	if ok and quests then
		for _, info in ipairs(quests) do
			if info.questID == questID and info.x and info.y and info.x > 0 then
				return mapID, info.x, info.y
			end
		end
	end
end

local function ExternalQuestPosition(questID)
	local loader = _G.QuestieLoader
	if not (loader and loader.ImportModule) then return end
	local okDU, DU = pcall(loader.ImportModule, loader, "DistanceUtils")
	local okDB, QDB = pcall(loader.ImportModule, loader, "QuestieDB")
	local okZB, ZDB = pcall(loader.ImportModule, loader, "ZoneDB")
	if not (okDU and DU and okDB and QDB and okZB and ZDB) then return end
	local okQ, quest = pcall(QDB.GetQuest, QDB, questID)
	if not (okQ and quest) then return end
	local okS, spawn, zone = pcall(DU.GetNearestSpawnForQuest, quest)
	if not (okS and spawn and zone and spawn[1] and spawn[2]) then return end
	local okZ, mapID = pcall(function() return ZDB:GetUiMapIdByAreaId(zone) end)
	if okZ and mapID and spawn[1] > 0 then
		return mapID, spawn[1] / 100, spawn[2] / 100
	end
end

function NAV:QuestPosition(questID)
	if not questID then return end
	local mapID = CurrentMap()
	if C_QuestLog and C_QuestLog.GetNextWaypointForQuest and mapID then
		local ok, x, y = pcall(C_QuestLog.GetNextWaypointForQuest, questID, mapID)
		if ok and x and y then return mapID, x, y end
	end
	local m, x, y = QuestPOIOnMap(questID, mapID)
	if m then return m, x, y end
	for m2 in pairs(ZoneMaps()) do
		if m2 ~= mapID then
			m, x, y = QuestPOIOnMap(questID, m2)
			if m then return m, x, y end
		end
	end
	if QuestPOIGetIconInfo and mapID then
		for i = 1, 16 do
			local ok, qid, _, _, _, x2, y2 = pcall(QuestPOIGetIconInfo, questID, i)
			if not ok or qid == nil then break end
			if qid == questID and x2 and y2 and x2 > 0 then return mapID, x2, y2 end
		end
	end
	return ExternalQuestPosition(questID)
end

local function QuestIDForLogIndex(idx)
	if not idx or idx == 0 then return end
	if C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
		local ok, r = pcall(C_QuestLog.GetQuestIDForLogIndex, idx)
		if ok and r then return r end
	end
	if C_QuestLog and C_QuestLog.GetInfo then
		local ok, info = pcall(C_QuestLog.GetInfo, idx)
		if ok and info and info.questID and not info.isHeader then return info.questID end
	end
	if GetQuestLogTitle then
		local ok, a, _, _, isHeader, _, _, _, questID = pcall(GetQuestLogTitle, idx)
		if ok then
			if type(a) == "table" and a.questID and not a.isHeader then return a.questID end
			if type(questID) == "number" and questID > 0 and not isHeader then return questID end
		end
	end
end

local function QuestIDForButton(btn)
	if not btn then return end
	if btn.questID then return btn.questID end
	return QuestIDForLogIndex(btn.questLogIndex or (btn.GetID and btn:GetID()))
end

function NAV:NavigateToQuest(questID)
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
		or (GetQuestLogTitle and select(1, GetQuestLogTitle(questID))) or L["Quest"]
	local mapID, x, y = self:QuestPosition(questID)
	if mapID and x and y then
		self:AddWaypoint(mapID, x, y, title)
	else
		S:Print(format(L["No map position for quest '%s'."], title or "?"))
	end
end

function NAV:HookQuestLog()
	if _G.QuestMapLogTitleButton_OnClick and not self.qmHooked then
		self.qmHooked = true
		hooksecurefunc("QuestMapLogTitleButton_OnClick", function(btn, button)
			if button == "RightButton" and btn and btn.questID then
				NAV:NavigateToQuest(btn.questID)
			end
		end)
	end
	local rows, seen = {}, {}
	local function Add(b) if b and not seen[b] then seen[b] = true rows[#rows + 1] = b end end
	for i = 1, 40 do Add(_G["QuestLogTitleButton" .. i]) end
	local scroll = _G.QuestLogListScrollFrame or _G.QuestLogScrollFrame or _G.QuestScrollFrame
	local child = scroll and ((scroll.GetScrollChild and scroll:GetScrollChild()) or scroll.Contents or scroll)
	if child and child.GetChildren then
		for _, c in ipairs({ child:GetChildren() }) do
			if c.IsObjectType and c:IsObjectType("Button") then Add(c) end
		end
	end
	if #rows == 0 and _G.QuestLogFrame then
		local function Scan(f, depth)
			if not f or depth > 5 then return end
			for _, c in ipairs({ f:GetChildren() }) do
				local n = c.GetName and c:GetName() or ""
				if c.IsObjectType and c:IsObjectType("Button")
					and (n:find("Title") or c.questID or c.questLogIndex) then Add(c) end
				Scan(c, depth + 1)
			end
		end
		Scan(_G.QuestLogFrame, 1)
	end
	for _, btn in ipairs(rows) do
		if not btn.suiNavHooked then
			btn.suiNavHooked = true
			pcall(btn.RegisterForClicks, btn, "LeftButtonUp", "RightButtonUp", "LeftButtonDown", "RightButtonDown")
			btn:HookScript("OnClick", function(self, button)
				if button == "RightButton" then
					local qid = QuestIDForButton(self)
					if qid then NAV:NavigateToQuest(qid) end
				end
			end)
			btn:HookScript("OnEnter", function(self)
				local qid = QuestIDForButton(self)
				if qid and GameTooltip then
					if not GameTooltip:IsShown() or GameTooltip:GetOwner() ~= self then
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					end
					GameTooltip:AddLine("|cff" .. S.accentHex .. L["Right-click: navigate to quest"] .. "|r", 1, 1, 1)
					GameTooltip:Show()
				end
			end)
			if not btn.suiNav then
				local nav = CreateFrame("Button", nil, btn)
				self.questRows = self.questRows or {}
				self.questRows[#self.questRows + 1] = btn
				nav:SetSize(16, 14)
				nav:SetPoint("RIGHT", btn, "RIGHT", -1, 0)
				nav:SetFrameLevel(btn:GetFrameLevel() + 3)
				nav.fs = S:FontString(nav, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
				nav.fs:SetPoint("CENTER")
				nav.fs:SetText("»")
				nav.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
				nav:SetScript("OnClick", function()
					local qid = QuestIDForButton(btn)
					if qid then NAV:NavigateToQuest(qid) end
				end)
				nav:SetScript("OnEnter", function(self)
					self.fs:SetTextColor(1, 1, 1)
					local qid = QuestIDForButton(btn)
					if qid and GameTooltip then
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						GameTooltip:AddLine(L["Navigate to quest"], 1, 1, 1)
						GameTooltip:Show()
					end
				end)
				nav:SetScript("OnLeave", function(self)
					self.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
					if GameTooltip then GameTooltip:Hide() end
				end)
				btn.suiNav = nav
			end
		end
	end
	local function RefreshRowNav()
		for _, btn in ipairs(NAV.questRows or {}) do
			if btn.suiNav then btn.suiNav:SetShown(QuestIDForButton(btn) ~= nil and btn:IsShown()) end
		end
	end
	if _G.QuestLog_Update and not self.qlUpdateHooked then
		self.qlUpdateHooked = true
		hooksecurefunc("QuestLog_Update", function() S:SafeCall("Nav:RowNav", RefreshRowNav) end)
	end
	S:SafeCall("Nav:RowNav", RefreshRowNav)
	local qf = _G.QuestLogFrame
	if qf and not qf.suiNavBtn then
		local nav = CreateFrame("Button", "SuiQuestNavBtn", qf)
		nav:SetSize(100, 20)
		S:CreateBackdrop(nav, "Default")
		nav:SetPoint("BOTTOMRIGHT", qf, "BOTTOMRIGHT", -26, 15)
		nav.fs = S:FontString(nav, 11, "OUTLINE", S.media.unitFont, nil, "CENTER")
		nav.fs:SetAllPoints(nav)
		nav.fs:SetText(L["Navigate to quest"])
		S:RegisterAccent(nav.fs, "text")
		nav:SetScript("OnClick", function()
			local idx = GetQuestLogSelection and GetQuestLogSelection()
			local qid = QuestIDForLogIndex(idx)
			if qid then NAV:NavigateToQuest(qid)
			else S:Print(L["Select a quest in the log first."]) end
		end)
		nav:SetScript("OnEnter", function(s) s:SetAlpha(0.75) end)
		nav:SetScript("OnLeave", function(s) s:SetAlpha(1) end)
		qf.suiNavBtn = nav
	end
	if _G.QuestLogTitleButton_OnClick and not self.qlClickHooked then
		self.qlClickHooked = true
		hooksecurefunc("QuestLogTitleButton_OnClick", function(btn, button)
			if button == "RightButton" and btn then
				local qid = QuestIDForButton(btn)
				if qid then NAV:NavigateToQuest(qid) end
			end
		end)
	end
end

-- tracker: invisible right-click overlays on each watch line -------------------
local function RefreshTrackerMap()
	if not (GetNumQuestWatches and GetQuestIndexForWatch) then return end
	local watch = 0
	for i = 1, 30 do
		local btn = _G["SuiTrackerNav" .. i]
		local line = _G["QuestWatchLine" .. i] or _G["WatchFrameLine" .. i]
		if not btn then break end
		local text = line and line.GetText and line:GetText()
		local shown = line and line:IsShown() and text and text ~= ""
		if shown then
			if not text:find("^%s*%-") then watch = watch + 1 end
			btn.questIndex = GetQuestIndexForWatch(watch)
			btn:SetShown(btn.questIndex ~= nil)
		else
			btn.questIndex = nil
			btn:Hide()
		end
	end
end

function NAV:HookTracker()
	local holder = _G.QuestWatchFrame or _G.WatchFrame
	if not holder then return end
	for i = 1, 30 do
		local line = _G["QuestWatchLine" .. i] or _G["WatchFrameLine" .. i]
		if not line then break end
		if not line.suiNavClick then
			line.suiNavClick = true
			local btn = CreateFrame("Button", "SuiTrackerNav" .. i, holder)
			btn:SetAllPoints(line)
			btn:SetFrameLevel((line.GetParent and line:GetParent():GetFrameLevel() or 1) + 5)
			btn:RegisterForClicks("RightButtonUp")
			btn:SetScript("OnClick", function(self)
				if self.questIndex then
					local qid = QuestIDForLogIndex(self.questIndex)
					if qid then NAV:NavigateToQuest(qid) end
				end
			end)
			btn:SetScript("OnEnter", function(self)
				if self.questIndex and GameTooltip then
					GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
					GameTooltip:AddLine("|cff" .. S.accentHex .. L["Right-click: navigate to quest"] .. "|r", 1, 1, 1)
					GameTooltip:Show()
				end
			end)
			btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			btn:Hide()
		end
	end
	if QuestWatch_Update then hooksecurefunc("QuestWatch_Update", function() S:SafeCall("Nav:TrackerMap", RefreshTrackerMap) end) end
	self:RegisterEvent("QUEST_WATCH_UPDATE", function() S:SafeCall("Nav:TrackerMap", RefreshTrackerMap) end)
	self:RegisterEvent("QUEST_LOG_UPDATE", function() S:SafeCall("Nav:TrackerMap", RefreshTrackerMap) end)
	S:SafeCall("Nav:TrackerMap", RefreshTrackerMap)
end

-- corpse waypoint ---------------------------------------------------------------
function NAV:CorpseWaypoint()
	if not self.db.corpseArrow then return end
	if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return end
	local mapID = CurrentMap()
	if not mapID then return end
	local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
	if ok and pos and pos.GetXY then
		local x, y = pos:GetXY()
		if x and y and x > 0 then
			-- replace any previous corpse marker so deaths don't pile up
			for mID, list in pairs(WP()) do
				for i = #list, 1, -1 do
					if list[i].corpse then
						if self.active and self.active.wp == list[i] then self.active = nil end
						tremove(list, i)
					end
				end
				if not next(list) then WP()[mID] = nil end
			end
			self:AddWaypoint(mapID, x, y, L["Corpse"], { corpse = true })
		end
	end
end

-- slash -----------------------------------------------------------------------
local function FindZone(name)
	if not C_Map or not C_Map.GetMapChildrenInfo then return end
	name = strlower(name)
	for _, continent in ipairs({ 1414, 1415, 1945, 113, 424, 619, 875, 876, 1550, 1978, 2132, 2274 }) do
		local ok, children = pcall(C_Map.GetMapChildrenInfo, continent)
		if ok and children then
			for _, info in ipairs(children) do
				if info.name and strlower(info.name) == name then return info.mapID end
			end
			for _, info in ipairs(children) do
				if info.name and strlower(info.name):find(name, 1, true) then return info.mapID end
			end
		end
	end
end

function NAV:Slash(input)
	input = strtrim(input or "")
	if input == "" or input == "help" then
		S:Print("|cff" .. S.accentHex .. "/sway|r " .. L["commands:"])
		print("  /sway x y [name] - " .. L["set waypoint on current map"])
		print("  /sway <zone> x y [name] - " .. L["set waypoint in zone"])
		print("  /sway arrow - " .. L["toggle arrow"])
		print("  /sway closest - " .. L["arrow to closest waypoint"])
		print("  /sway size <24-160> - " .. L["arrow size"])
		print("  /sway list - " .. L["list waypoints"])
		print("  /sway clear - " .. L["clear arrow"])
		print("  /sway reset - " .. L["remove all waypoints"])
		print("  " .. L["World map:"] .. " Ctrl+" .. L["Right-click"] .. " = " .. L["set waypoint"])
		print("  " .. L["Quest log:"] .. " " .. L["Right-click"] .. " = " .. L["navigate to quest"])
		return
	end
	local cmd, rest = input:match("^(%S+)%s*(.*)$")
	cmd = strlower(cmd or "")
	if cmd == "reset" or cmd == "clearall" then
		self:ClearWaypoints() S:Print(L["All waypoints removed."])
	elseif cmd == "clear" then
		self.active = nil if self.arrow then self.arrow:Hide() end
	elseif cmd == "arrow" then
		if self.arrow then self.arrow:SetShown(not self.arrow:IsShown()) end
	elseif cmd == "closest" then
		self:SetArrowToClosest()
	elseif cmd == "size" then
		local s = tonumber(rest)
		if not s then S:Print(L["Usage: /sway size 24-160"]) return end
		s = min(160, max(24, floor(s)))
		self.db.arrowSize = s
		if self.arrow then
			self.arrow:SetSize(s, s + 44)
			self.arrow.tex:SetSize(s, s)
			if self.arrow.ring then self.arrow.ring:SetSize(s + 6, s + 6) end
		end
		S:Print(format(L["Arrow size: %d (scroll on the arrow to resize)"], s))
	elseif cmd == "list" then
		local found
		for mapID, list in pairs(WP()) do
			local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
			for _, wp in ipairs(list) do
				found = true
				S:Print(format("%s: %.1f, %.1f - %s", info and info.name or ("map " .. mapID), wp.x * 100, wp.y * 100, wp.title or ""))
			end
		end
		if not found then S:Print(L["No waypoints."]) end
		return
	else
		local xs, ys, title = input:match("^([%d%.]+)%s+([%d%.]+)%s*(.-)$")
		if xs then
			self:AddWaypoint(CurrentMap(), tonumber(xs) / 100, tonumber(ys) / 100, strtrim(title) ~= "" and title or nil)
			return
		end
		local zone, zx, zy, zt = input:match("^(.-)%s+([%d%.]+)%s+([%d%.]+)%s*(.-)$")
		if zone then
			local mapID = tonumber(zone) or FindZone(zone)
			if mapID and zx and zy then
				self:AddWaypoint(mapID, tonumber(zx) / 100, tonumber(zy) / 100, strtrim(zt) ~= "" and zt or nil)
				return
			end
			S:Print(format(L["Unknown zone: %s"], zone))
			return
		end
		S:Print(L["Usage: /sway x y [name] - or /sway help"])
	end
end

-- TomTom-compat facade -----------------------------------------------------------
function NAV:SetupWaypointFacade()
	-- a real TomTom install keeps its own methods and drives everything;
	-- we only forward into it (no fake facade, no method overrides)
	if _G.TomTom and _G.TomTom.AddWaypoint then
		RealTomTom = _G.TomTom
		-- other addons (Questie tracker) call RemoveWaypoint on uids TomTom
		-- already cleared on arrival -> internal nil arithmetic. Guard it.
		if RealTomTom.RemoveWaypoint and not RealTomTom.__suiGuardedRemove then
			RealTomTom.__suiGuardedRemove = true
			local origRemove = RealTomTom.RemoveWaypoint
			RealTomTom.RemoveWaypoint = function(self, uid)
				if uid == nil or (type(uid) == "table" and uid[1] == nil and uid.m == nil) then return end
				local ok, err = pcall(origRemove, self, uid)
				if not ok and S.LogWarn then S:LogWarn("navigation", "TomTom RemoveWaypoint ignored: " .. tostring(err)) end
			end
		end
		if S.LogInfo then S:LogInfo("navigation", "real TomTom detected - forwarding waypoints") end
		return
	end
	local TT = { version = "SentinelUI", api = "compat" }
		TT.__sui_orig = TT.__sui_orig or { AddWaypoint = TT.AddWaypoint, RemoveWaypoint = TT.RemoveWaypoint }
	local function WpTitle(opts)
		return type(opts) == "table" and (opts.title or opts.minimap_desc or opts.worldmap_desc) or nil
	end
	function TT:AddWaypoint(mapID, x, y, opts)
		opts = opts or {}
		return NAV:AddWaypoint(mapID, x, y, WpTitle(opts), { silent = opts.silent, crazy = opts.crazy, corpse = opts.corpse })
	end
	TT.AddMFWaypoint = TT.AddWaypoint
	function TT:AddZWaypoint(_, mapID, x, y, desc)
		return NAV:AddWaypoint(mapID, x, y, desc)
	end
	function TT:SetCrazyArrow(mapID, x, y, title)
		local wp = NAV:AddWaypoint(mapID, x, y, title, { silent = true })
		if wp then NAV.active = { mapID = mapID, wp = wp } end
		if NAV.arrow then NAV.arrow.title:SetText(title or L["Waypoint"]) NAV.arrow:Show() end
		return wp
	end
	function TT:ClearWaypoint() NAV.active = nil if NAV.arrow then NAV.arrow:Hide() end end
	function TT:ClearAllWaypoints() NAV:ClearWaypoints() end
	function TT:RemoveWaypoint(wp)
		if type(wp) ~= "table" then return end
		for mapID, list in pairs(WP()) do
			for i, w in ipairs(list) do
				if w == wp then NAV:RemoveWaypoint(mapID, i) return end
			end
		end
	end
	function TT:SetClosestWaypoint() NAV:SetArrowToClosest() end
	function TT:ShowHideCrazyArrow() if NAV.arrow then NAV.arrow:SetShown(not NAV.arrow:IsShown()) end end
	function TT:EnableDisablePOIIntegration() end
	function TT:HijackCrazyArrow() end
	function TT:IsAddOnLoaded() return true end
	_G.TomTom = TT
	if S.LogInfo then S:LogInfo("navigation", "waypoint facade installed") end
end

function NAV:Update()
	self.db = S.db.profile.navigation
	if self.arrow then
		local size = self.db.arrowSize or 56
		self.arrow:SetSize(size, size + 44)
		self.arrow.tex:SetSize(size, size)
		if self.arrow.ring then self.arrow.ring:SetSize(size + 6, size + 6) end
		self.arrow:SetAlpha(self.db.arrowAlpha or 1)
		self:RefreshPins()
	end
end

function NAV:Initialize()
	self.db = S.db.profile.navigation
	if self.db.enable == false then return end
	self.pins = {}
	-- a real TomTom install owns the arrow/pins; we stay a waypoint front-end.
	-- TomTom may load after us -> also re-check on ADDON_LOADED.
	if _G.TomTom and _G.TomTom.AddWaypoint then RealTomTom = _G.TomTom end
	if not RealTomTom then
		self:BuildArrow()
		self:BuildMinimapPin()
	end
	self:HookWorldMap()
	self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
		if addon == "TomTom" and _G.TomTom and _G.TomTom.AddWaypoint and not RealTomTom then
			RealTomTom = _G.TomTom
			if NAV.arrow then NAV.arrow:Hide() end
			if NAV.mmPin then NAV.mmPin:Hide() end
			NAV:RefreshPins()
		end
		if addon == "Blizzard_WorldMap" then NAV:HookWorldMap() NAV:RefreshPins() end
		if addon == "Blizzard_QuestLog" or addon == "Blizzard_WorldMap" then
			S:SafeCall("Nav:QuestLog", function() NAV:HookQuestLog() end)
		end
	end)
	self:HookQuestLog()
	self:HookTracker()
	local qf = _G.QuestLogFrame
	if qf then
		qf:HookScript("OnShow", function()
			S:SafeCall("Nav:QuestLog", function() NAV:HookQuestLog() end)
		end)
	end
	self:SetupWaypointFacade()
	-- with real TomTom driving the arrow there is no OnUpdate ticker of our
	-- own: watch arrival so chains still advance and waypoint pins clear up
	if RealTomTom then
		local w = CreateFrame("Frame")
		w.t = 0
		w:SetScript("OnUpdate", function(s, e)
			s.t = s.t + e
			if s.t < 0.5 then return end
			s.t = 0
			local a = NAV.active
			if not a then return end
			local dist = VectorTo(a.mapID, a.wp.x, a.wp.y)
			if dist and dist <= (NAV.db.arrival or 15) then
				if NAV.db.pingOnArrive ~= false then pcall(PlaySound, 3175) end
				local chain, seq = a.wp.chain, a.wp.seq
				NAV:RemoveActiveWaypoint()
				NAV:SetArrowToNext(chain, seq)
			end
		end)
	end
	self:RegisterEvent("PLAYER_DEAD", function() C_Timer.After(1, function() NAV:CorpseWaypoint() end) end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() NAV:RefreshPins() end)
	S:RegisterChatCommand("sway", function(msg) NAV:Slash(msg) end)
	S:RegisterChatCommand("suiway", function(msg) NAV:Slash(msg) end)
	local externalNav = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("TomTom")) or (IsAddOnLoaded and IsAddOnLoaded("TomTom"))
	if not externalNav then
		S:RegisterChatCommand("way", function(msg) NAV:Slash(msg) end)
	end
end
