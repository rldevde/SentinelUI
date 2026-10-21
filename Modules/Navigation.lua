-- Navigation: waypoint system - crazy arrow, world map pins,
-- minimap edge indicator, /sway commands, corpse arrow and quest navigation.
-- All math works in WoW world coordinates (Y = north axis, X = west axis).
local _, ns = ...
local S = ns.S
local L = S.L
local NAV = S:NewModule("Navigation")

local abs, atan2, cos, floor, sin, sqrt = math.abs, math.atan2, math.cos, math.floor, math.sin, math.sqrt
local IsSecret = S.IsSecret
local PI2 = math.pi * 2
local tinsert, tremove, format, strtrim, strlower, tonumber, ipairs, pairs = table.insert, table.remove, string.format, strtrim, strlower, tonumber, ipairs, pairs

-- waypoints live in the global db so they survive profile switches/reloads
local function WaypointDB()
	local g = S.db.global
	g.nav = g.nav or { waypoints = {} }
	return g.nav.waypoints
end

local CurrentMap -- forward: used by VectorTo, defined below

local function PlayerWorld()
	if not UnitPosition then return end
	-- UnitPosition quirk: first return is posY (west axis), second posX (north)
	local posW, posN, posZ, inst = UnitPosition("player")
	if not posN then return end
	return posN, posW, inst, posZ
end

local function MapToWorld(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
	local ok, inst, vec = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not ok or not vec then return end
	return vec.x, vec.y, inst, vec.z -- vec.x = north axis, vec.y = west axis (per HBD convention)
end

-- map size in yards: C_Map.GetMapWorldSize is missing on some clients,
-- the legacy global GetMapWorldSize often still exists
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

-- measured scale: yards per worldpos-unit, derived on the current map where
-- BOTH the real yard width (GetMapWorldSize) and the worldpos-space width
-- (GetWorldPosFromMapPos delta) are known. Caches the ratio globally.
local worldScale
local function WorldToYards()
	if worldScale then return worldScale end
	local cur = CurrentMap()
	if not (cur and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return 1 end
	local w = MapWorldSize(cur)
	if not w then return 1 end
	local okA, _, a = pcall(C_Map.GetWorldPosFromMapPos, cur, CreateVector2D(0, 0))
	local okB, _, b = pcall(C_Map.GetWorldPosFromMapPos, cur, CreateVector2D(1, 0))
	if okA and okB and a and b then
		local wpw = sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		if wpw and wpw > 0 then worldScale = w / wpw end
	end
	return worldScale or 1
end

-- measured unitpos->worldpos ratio: convert the player's own map position
-- into worldpos space and compare against UnitPosition's magnitude. Tells us
-- whether UnitPosition shares the worldpos space (ratio ~1) or not.
local unitScale
local function UnitToWorldPos()
	if unitScale then return unitScale end
	unitScale = 1
	local cur = CurrentMap()
	local pN, pW = PlayerWorld()
	if not (cur and pN and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return unitScale
	end
	local mpos = C_Map.GetPlayerMapPosition(cur, "player")
	if not (mpos and mpos.GetXY) then return unitScale end
	local px, py = mpos:GetXY()
	if not px or IsSecret(px) then return unitScale end
	local ok, _, w = pcall(C_Map.GetWorldPosFromMapPos, cur, CreateVector2D(px, py))
	if ok and w then
		local magU, magW = sqrt(pN ^ 2 + pW ^ 2), sqrt(w.x ^ 2 + w.y ^ 2)
		if magW and magW > 0 and magU > 0 then
			local r = magU / magW
			if r > 0.3 and r < 10 then unitScale = r end
		end
	end
	return unitScale
end

-- HereBeDragons provides proven world-coordinate transforms for this client
-- (vendored, BSD-licensed; works without Questie). Both names are tried: the
-- bundled copy registers as the Questie-forked MAJOR, other addons may ship the
-- upstream name.
local HBD = LibStub and (LibStub("HereBeDragonsQuestie-2.0", true) or LibStub("HereBeDragons-2.0", true))

-- distance (yards), bearing (clockwise from north) from player to map coords.
local function VectorTo(mapID, mx, my)
	-- primary path: HBD world-vector math, correct across zones/sub-maps
	if HBD then
		local px, py, pInst = HBD:GetPlayerWorldPosition()
		local wx, wy, wInst = HBD:GetWorldCoordinatesFromZone(mx, my, mapID)
		if px and wx then
			if pInst ~= wInst then return nil, nil, true end -- different continent/instance
			local angle, dist = HBD:GetWorldVector(pInst, px, py, wx, wy)
			if angle and dist then return dist, angle end
		end
	end
	-- fallback: map-unit math when the player resolves on the waypoint's map
	if C_Map.GetPlayerMapPosition then
		local ppos = C_Map.GetPlayerMapPosition(mapID, "player")
		local w, h = MapWorldSize(mapID)
		if ppos and ppos.GetXY and w and h and w > 0 and h > 0 then
			local px, py = ppos:GetXY()
			if px and not IsSecret(px) then
				local dx, dy = (mx - px) * w, (my - py) * h
				local bearing = atan2(dx, -dy) -- map y grows southward
				if bearing < 0 then bearing = bearing + PI2 end
				return sqrt(dx * dx + dy * dy), bearing
			end
		end
	end
	-- last resort: raw worldpos space with self-calibrated scale
	local pN, pW, inst, pZ = PlayerWorld()
	local wN, wW, wInst, wZ = MapToWorld(mapID, mx, my)
	if not pN or not wN then return nil end
	if inst ~= wInst then return nil, nil, true end
	local scale = WorldToYards()
	local us = UnitToWorldPos()
	local dN, dW = (wN - pN / us) * scale, (wW - pW / us) * scale
	local bearing = atan2(-dW, dN)
	if bearing < 0 then bearing = bearing + PI2 end
	local dz = (wZ and pZ and not IsSecret(wZ) and not IsSecret(pZ)) and (wZ - pZ) * scale or nil
	return sqrt(dN * dN + dW * dW), bearing, nil, dz
end

CurrentMap = function()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

-- storage -------------------------------------------------------------------
function NAV:AddWaypoint(mapID, x, y, title, opts)
	if not mapID or not x or not y then return end
	opts = opts or {}
	local wp = { x = x, y = y, title = title or L["Waypoint"], corpse = opts.corpse,
		chain = opts.chain, seq = opts.seq }
	local db = WaypointDB()
	local list = db[mapID]
	if not list then list = {} db[mapID] = list end
	tinsert(list, wp)
	if not opts.silent then S:Print(format(L["Waypoint set: %s (%.1f, %.1f)"], wp.title, x * 100, y * 100)) end
	self:RefreshPins()
	-- a freshly set waypoint becomes the arrow target immediately (TomTom-style);
	-- silent extra picks of a multi-spawn chain stay in the queue instead of
	-- stealing the arrow from the first (nearest) target
	if opts.crazy ~= false and not opts.silent then
		self.active = { mapID = mapID, wp = wp }
		if self.arrow then
			self.arrow.title:SetText(wp.title)
			self.arrow:Show()
		end
	end
	return wp
end

function NAV:RemoveWaypoint(mapID, index)
	local list = WaypointDB()[mapID]
	if not list then return end
	tremove(list, index)
	if not next(list) then WaypointDB()[mapID] = nil end
	self:RefreshPins()
end

-- ref-based lookup/removal for callers that keep their own waypoint sets
-- (QuestScope nav chains): lets them detect consumed picks and drop stale
-- leftovers without touching entries added by other callers
function NAV:IsWaypointLive(mapID, wp)
	local list = WaypointDB()[mapID]
	if not (list and wp) then return false end
	for _, w in ipairs(list) do
		if w == wp then return true end
	end
	return false
end

function NAV:RemoveWaypointRef(mapID, wp)
	local list = WaypointDB()[mapID]
	if not (list and wp) then return end
	for i, w in ipairs(list) do
		if w == wp then tremove(list, i) break end
	end
	if not next(list) then WaypointDB()[mapID] = nil end
	if self.active and self.active.wp == wp then
		self.active = nil
		if self.arrow then self.arrow:Hide() end
	end
	self:RefreshPins()
end

function NAV:ClearWaypoints(mapID)
	if mapID then
		WaypointDB()[mapID] = nil
	else
		wipe(WaypointDB())
	end
	self.active = nil
	self:RefreshPins()
end

-- pick the waypoint closest to the player (current continent only)
function NAV:SetArrowToClosest()
	local best, bestDist
	local pN, pW, inst = PlayerWorld()
	if not pN then return end
	for mapID, list in pairs(WaypointDB()) do
		for _, wp in ipairs(list) do
			local wN, wW, wInst = MapToWorld(mapID, wp.x, wp.y)
			if wN and wInst == inst then
				local d = sqrt((wN - pN) ^ 2 + (wW - pW) ^ 2)
				if not bestDist or d < bestDist then bestDist, best = d, { mapID = mapID, wp = wp } end
			end
		end
	end
	if best then
		self.active = best
		if self.arrow then
			self.arrow.title:SetText(best.wp.title or L["Waypoint"])
			self.arrow:Show()
		end
	else
		self.active = nil
		if self.arrow then self.arrow:Hide() end
	end
end

-- advance after arrival: continue the SAME chain in seq order (quest picks
-- 2/n, 3/n ...) instead of jumping to whatever waypoint happens to be
-- closest globally (which sent players on detours). Only when the chain is
-- exhausted do we fall back to the closest remaining waypoint.
function NAV:SetArrowToNext(chain, seq)
	if chain then
		seq = seq or 0
		local nxt, nxtSeq
		for mapID, list in pairs(WaypointDB()) do
			for _, wp in ipairs(list) do
				if wp.chain == chain and (wp.seq or 0) > seq then
					if not nxtSeq or wp.seq < nxtSeq then nxt, nxtSeq = { mapID = mapID, wp = wp }, wp.seq end
				end
			end
		end
		if nxt then
			self.active = nxt
			if self.arrow then
				self.arrow.title:SetText(nxt.wp.title or L["Waypoint"])
				self.arrow:Show()
			end
			return
		end
	end
	self:SetArrowToClosest()
end

-- crazy arrow ---------------------------------------------------------------
local function Gradient(perc, ...)
	local n = select("#", ...) / 3
	local seg, rel = math.modf(perc * (n - 1))
	local r1, g1, b1 = select(seg * 3 + 1, ...)
	local r2, g2, b2 = select(seg * 3 + 4, ...)
	if not r2 then return r1, g1, b1 end
	return r1 + (r2 - r1) * rel, g1 + (g2 - g1) * rel, b2 + (b2 - b1) * rel
end

function NAV:BuildArrow()
	local f = CreateFrame("Button", "SentinelUINavArrow", UIParent, S.BackdropTemplate)
	f:SetSize(self.db.arrowSize or 56, (self.db.arrowSize or 56) + 56)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForClicks("RightButtonUp")
	S:CreateBackdrop(f, "Transparent")
	f.backdrop:Hide()

	f.tex = f:CreateTexture(nil, "OVERLAY")
	f.tex:SetPoint("TOP", f, "TOP", 0, 0)
	f.tex:SetSize(self.db.arrowSize or 56, self.db.arrowSize or 56)
	f.tex:SetTexture(S.media.navArrow)

	local texts = CreateFrame("Frame", nil, f)
	texts:SetAllPoints()
	f.title = S:FontString(texts, 11, "OUTLINE")
	f.title:SetPoint("TOP", f.tex, "BOTTOM", 0, -2)
	f.dist = S:FontString(texts, 10, "OUTLINE")
	f.dist:SetPoint("TOP", f.title, "BOTTOM", 0, -1)
	f.tta = S:FontString(texts, 10, "OUTLINE")
	f.tta:SetPoint("TOP", f.dist, "BOTTOM", 0, -1)
	f.elev = S:FontString(texts, 10, "OUTLINE")
	f.elev:SetPoint("TOP", f.tta, "BOTTOM", 0, -1)

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
	-- mouse wheel over the arrow resizes it live (persisted to settings)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		local s = min(160, max(24, (NAV.db.arrowSize or 56) + delta * 4))
		NAV.db.arrowSize = s
		f:SetSize(s, s + 56)
		f.tex:SetSize(s, s)
		S:Print(format(L["Arrow size: %d (scroll on the arrow to resize)"], s))
	end)

	local lastDist, elapsedAcc, speed = 0, 0, 0
	f:SetScript("OnUpdate", function(self2, elapsed)
		local active = NAV.active
		if not active then self2:Hide() return end
		local dist, bearing, otherZone, dz = VectorTo(active.mapID, active.wp.x, active.wp.y)
	-- one-shot diagnostics per activation: tells us which math stage is wrong
	if not active.diagLogged then
		active.diagLogged = true
		local dbg = { "wp=" .. tostring(active.wp.title), "map=" .. tostring(active.mapID),
			format("xy=%.3f,%.3f", active.wp.x or -1, active.wp.y or -1) }
		local cur = CurrentMap()
		dbg[#dbg + 1] = "cur=" .. tostring(cur)
		if cur and C_Map.GetPlayerMapPosition then
			local p = C_Map.GetPlayerMapPosition(cur, "player")
			if p and p.GetXY then local a, b = p:GetXY() dbg[#dbg + 1] = format("pMap=%.3f,%.3f", a or -1, b or -1) end
		end
		if HBD then
			local hx, hy, hi = HBD:GetPlayerWorldPosition()
			local wx, wy, wi = HBD:GetWorldCoordinatesFromZone(active.wp.x, active.wp.y, active.mapID)
			dbg[#dbg + 1] = format("hbd=p:%.0f,%.0f@%s w:%.0f,%.0f@%s",
				hx or -1, hy or -1, tostring(hi), wx or -1, wy or -1, tostring(wi))
		end
		dbg[#dbg + 1] = format("=> dist=%s bear=%.2f face=%.2f", tostring(dist and floor(dist)), bearing or -1, GetPlayerFacing and GetPlayerFacing() or -1)
		local line = table.concat(dbg, " | ")
		S:LogInfo("nav", line)
		S:Print("|cff88ff88nav:|r " .. line)
	end
		if not dist then
			if otherZone then
				-- waypoint on another continent: dimmed arrow + zone hint
				self2.tex:SetVertexColor(0.5, 0.5, 0.5)
				self2.dist:SetText(L["other zone"])
				self2.tta:SetText("")
				self2.elev:SetText("")
			else
				self2:Hide()
			end
			return
		end
		-- arrival
		if dist <= (NAV.db.arrival or 15) then
			S:Print(format(L["Arrived: %s"], active.wp.title or L["Waypoint"]))
			if NAV.db.pingOnArrive ~= false then pcall(PlaySound, 3175) end
			local chain, seq = active.wp.chain, active.wp.seq
			NAV:RemoveActiveWaypoint()
			NAV:SetArrowToNext(chain, seq)
			return
		end
		-- direction: bearing + facing sign depends on the client's facing
		-- convention (CW vs CCW). /sway conv 1-4 switches live for testing.
		local facing = GetPlayerFacing and GetPlayerFacing() or 0
		local conv = NAV.db.arrowConv or 1 -- 1 = verified: rel = bearing + facing, rotate -rel
		local rel = bearing + ((conv == 1 or conv == 3) and facing or -facing)
		if self2.tex.SetRotation then
			self2.tex:SetRotation((conv <= 2) and -rel or rel)
		end
		-- color: green when heading right at it, red when opposite
		local relWrapped = abs((math.pi - abs((rel % PI2))) / math.pi)
		local c = NAV.db
		local r, g, b = Gradient(relWrapped, c.badColor.r, c.badColor.g, c.badColor.b, c.midColor.r, c.midColor.g, c.midColor.b, c.goodColor.r, c.goodColor.g, c.goodColor.b)
		if relWrapped > 0.98 then r, g, b = c.exactColor.r, c.exactColor.g, c.exactColor.b end
		self2.tex:SetVertexColor(r, g, b)
		-- pseudo-depth: arrow grows with distance, shrinks when close
		local sz = NAV.db.arrowSize or 56
		local sc = min(1.35, max(0.75, 0.55 + dist / 500))
		self2.tex:SetSize(sz * sc, sz * sc)
		if NAV.db.showDistance ~= false then
			self2.dist:SetFormattedText("%d " .. L["yards"], dist)
		else
			self2.dist:SetText("")
		end
		-- ETA from measured approach speed (smoothed once a second)
		if NAV.db.showETA ~= false then
			elapsedAcc = elapsedAcc + elapsed
			if elapsedAcc >= 1 then
				local cur = lastDist > 0 and (lastDist - dist) / elapsedAcc or 0
				speed = (speed + cur) / 2
				if speed > 0.5 then
					local eta = abs(dist / speed)
					self2.tta:SetFormattedText("%d:%02d", floor(eta / 60), floor(eta % 60))
				else
					self2.tta:SetText("–:––")
				end
				lastDist, elapsedAcc = dist, 0
			end
		else
			self2.tta:SetText("")
		end
		-- elevation difference to the waypoint (when the client exposes world Z)
		if dz and abs(dz) > 8 then
			self2.elev:SetFormattedText("%s %dm", dz > 0 and "+" or "-", floor(abs(dz)))
			self2.elev:SetTextColor(dz > 0 and 0.4 or 0.9, dz > 0 and 0.8 or 0.5, 0.3)
		else
			self2.elev:SetText("")
		end
	end)
	f:Hide()
	self.arrow = f
	S:CreateMover(f, "navArrow", L["Navigation Arrow"], { "TOP", "UIParent", "TOP", 0, -220 }, "navigation")
	S:AttachMoverDrag(f, "navArrow") -- drag the arrow itself anytime
end

function NAV:RemoveActiveWaypoint()
	local active = self.active
	if not active then return end
	local list = WaypointDB()[active.mapID]
	if list then
		for i, wp in ipairs(list) do
			if wp == active.wp then tremove(list, i) break end
		end
		if not next(list) then WaypointDB()[active.mapID] = nil end
	end
	self.active = nil
	self:RefreshPins()
end

-- world map pins + right-click creation --------------------------------------
function NAV:RefreshPins()
	local wmf = _G.WorldMapFrame
	if not wmf or not self.pins then return end
	for _, pin in ipairs(self.pins) do pin:Hide() end
	if not self.db.worldmapPin then return end
	local canvas = wmf.GetCanvas and wmf:GetCanvas() or wmf.ScrollContainer
	if not canvas or not wmf:IsShown() then return end
	local mapID = wmf.GetMapID and wmf:GetMapID()
	if not mapID then return end
	local cw, ch = canvas:GetSize()
	if not cw or cw == 0 then return end
	-- client uiMapIDs can differ from the quest-db zone ids: translate every
	-- stored waypoint onto the displayed map and draw the ones in bounds
	local shown = {}
	for wmap, list in pairs(WaypointDB()) do
		for _, wp in ipairs(list) do
			local tx, ty
			if wmap == mapID then tx, ty = wp.x, wp.y
			elseif HBD then tx, ty = HBD:TranslateZoneCoordinates(wp.x, wp.y, wmap, mapID) end
			if tx and ty and tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1 then
				shown[#shown + 1] = { wp = wp, mapID = wmap, x = tx, y = ty }
			end
		end
	end
	local n = 0
	for _, item in ipairs(shown) do
		local wp, wmap = item.wp, item.mapID
		n = n + 1
		local pin = self.pins[n]
		if not pin then
			pin = CreateFrame("Button", nil, canvas)
			pin.tex = pin:CreateTexture(nil, "OVERLAY")
			pin.tex:SetAllPoints()
			pin.tex:SetTexture(S.media.navPin)
			pin:SetScript("OnEnter", function(self2)
				GameTooltip:SetOwner(self2, "ANCHOR_CURSOR")
				GameTooltip:AddLine(self2.wp and self2.wp.title or L["Waypoint"], 1, 1, 1)
				GameTooltip:AddLine(L["Left-click: navigate | Right-click: remove"], 0.6, 0.6, 0.6)
				GameTooltip:Show()
			end)
			pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
			pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			pin:SetScript("OnClick", function(self2, btn)
				if btn == "RightButton" then
					local list2 = WaypointDB()[self2.mapID]
					if list2 then for i2, w in ipairs(list2) do if w == self2.wp then NAV:RemoveWaypoint(self2.mapID, i2) break end end end
				else
					NAV.active = { mapID = self2.mapID, wp = self2.wp }
					if NAV.arrow then NAV.arrow.title:SetText(self2.wp.title or L["Waypoint"]) NAV.arrow:Show() end
				end
			end)
			self.pins[n] = pin
		end
		pin.mapID, pin.wp = wmap, wp
		local size = self.db.pinSize or 16
		local isActive = self.active and self.active.mapID == wmap and self.active.wp == wp
		pin:SetSize(isActive and size * 1.5 or size, isActive and size * 1.5 or size)
		if pin.tex.SetVertexColor then
			if isActive then pin.tex:SetVertexColor(0.3, 0.9, 1, 1)
			else pin.tex:SetVertexColor(1, 1, 1, 1) end
		end
		pin:SetAlpha(self.db.pinAlpha or 1)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", canvas, "TOPLEFT", item.x * cw, -item.y * ch)
		pin:Show()
	end
	self:UpdateRoute()
end

-- route line on the world map: dashed path player -> active waypoint
function NAV:UpdateRoute()
	local wmf = _G.WorldMapFrame
	if not wmf then return end
	local canvas = wmf.GetCanvas and wmf:GetCanvas() or wmf.ScrollContainer
	local segs = self.routeSegs
	local function hideSegs()
		if segs then for _, t in ipairs(segs) do t:Hide() end end
	end
	if not canvas or not wmf:IsShown() then hideSegs() return end
	local mapID = wmf.GetMapID and wmf:GetMapID()
	local wp = self.active and self.active.wp
	if not (wp and mapID) then hideSegs() return end
	-- player position on the displayed map
	local ppos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
	if not (ppos and ppos.GetXY) then hideSegs() return end
	local px, py = ppos:GetXY()
	if not px or IsSecret(px) then hideSegs() return end
	-- target on the displayed map: zone->zone translation, clamped to the edge.
	-- Fallback: project along the verified bearing to the map border so a
	-- route line shows even for targets outside the displayed map.
	local tx, ty
	if HBD then tx, ty = HBD:TranslateZoneCoordinates(wp.x, wp.y, self.active.mapID, mapID, true) end
	if tx then
		if tx < 0 then tx = 0 elseif tx > 1 then tx = 1 end
		if ty < 0 then ty = 0 elseif ty > 1 then ty = 1 end
	else
		local _, bearing = VectorTo(self.active.mapID, wp.x, wp.y)
		if not bearing then hideSegs() return end
		local dx, dy = sin(bearing), -cos(bearing) -- map coords: x east, y south
		local t = math.huge
		if dx > 1e-6 then t = math.min(t, (1 - px) / dx) elseif dx < -1e-6 then t = math.min(t, -px / dx) end
		if dy > 1e-6 then t = math.min(t, (1 - py) / dy) elseif dy < -1e-6 then t = math.min(t, -py / dy) end
		if t == math.huge or t <= 0 then hideSegs() return end
		tx, ty = px + dx * t, py + dy * t
	end
	local cw, ch = canvas:GetSize()
	if not cw or cw == 0 then hideSegs() return end
	local x1, y1, x2, y2 = px * cw, py * ch, tx * cw, ty * ch
	local dx, dy = x2 - x1, y2 - y1
	local len = sqrt(dx * dx + dy * dy)
	if len < 20 then hideSegs() return end
	segs = self.routeSegs or {}
	self.routeSegs = segs
	local ux, uy = dx / len, dy / len
	local ang = atan2(-uy, ux)
	local dash, step, thick = 10, 18, 4
	local n = 0
	for d = 0, len - dash, step do
		n = n + 1
		local t = segs[n]
		if not t then
			t = canvas:CreateTexture(nil, "OVERLAY", nil, 6)
			t:SetTexture("Interface\\Buttons\\WHITE8X8")
			t:SetVertexColor(0.25, 0.85, 1, 0.9)
			segs[n] = t
		end
		t:ClearAllPoints()
		t:SetPoint("CENTER", canvas, "TOPLEFT", x1 + ux * (d + dash / 2), -(y1 + uy * (d + dash / 2)))
		t:SetSize(dash, thick)
		t:SetRotation(ang)
		t:Show()
	end
	for i = n + 1, #segs do segs[i]:Hide() end
end

local function ModifierDown(mod)
	if mod == "CTRL" then return IsControlKeyDown() end
	if mod == "ALT" then return IsAltKeyDown() end
	if mod == "SHIFT" then return IsShiftKeyDown() end
	return true -- NONE
end

function NAV:HookWorldMap()
	local wmf = _G.WorldMapFrame
	if not wmf or not wmf.ScrollContainer then return end
	self.pins = self.pins or {}
	local canvas = wmf.GetCanvas and wmf:GetCanvas() or wmf.ScrollContainer
	if not canvas then return end
	local sc = wmf.ScrollContainer
	local function CursorToMap()
		if sc.GetNormalizedCursorPosition then return sc:GetNormalizedCursorPosition() end
		local cx, cy = GetCursorPosition()
		local l, b, w, h = canvas:GetRect()
		if not l then return end
		local scale = canvas:GetEffectiveScale()
		return (cx / scale - l) / w, (b + h - cy / scale) / h
	end
	-- hook both: the scroll container usually gets mouse events, the canvas on some clients
	for _, target in ipairs({ sc, canvas }) do
		target:HookScript("OnMouseUp", function(_, btn)
			if btn ~= "RightButton" or not NAV.db.clickCreate or InCombatLockdown() then return end
			if not ModifierDown(NAV.db.createModifier or "CTRL") then return end
			local x, y = CursorToMap()
			if not x or x < 0 or x > 1 or y < 0 or y > 1 then return end
			local mapID = wmf:GetMapID()
			if mapID then
				local now = GetTime()
				if NAV.lastMapClick and now - NAV.lastMapClick < 0.5 then return end -- double-fire guard
				NAV.lastMapClick = now
				NAV:AddWaypoint(mapID, x, y, L["Waypoint"])
			end
		end)
	end
	-- coordinate readout at the bottom of the map: player + cursor position
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
			local cx, cy = CursorToMap()
			local left = px and format("%s: %.1f, %.1f", L["Player"], px * 100, py * 100) or L["Player"] .. ": -"
			local right = (cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1) and format("  %s: %.1f, %.1f", L["Cursor"], cx * 100, cy * 100) or ""
			fs:SetText(left .. right)
		end)
	end
	wmf:HookScript("OnShow", function() NAV:RefreshPins() end)
	if wmf.OnMapChanged then hooksecurefunc(wmf, "OnMapChanged", function() NAV:RefreshPins() end) end
	if canvas.HookScript then canvas:HookScript("OnSizeChanged", function() NAV:RefreshPins() end) end
	-- keep the route line tracking the moving player while the map is open
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
	-- dashed path from minimap center toward the waypoint edge pin
	pin.lines = {}
	pin:SetScript("OnUpdate", function(self2)
		local active = NAV.active
		local function hideLines() for _, t in ipairs(self2.lines) do t:Hide() end end
		if not active or not NAV.db.minimapPin then self2:Hide() hideLines() return end
		local dist, bearing = VectorTo(active.mapID, active.wp.x, active.wp.y)
		if not dist then self2:Hide() hideLines() return end
		local angle = bearing
		if GetCVar("rotateMinimap") == "1" then
			angle = (bearing + (GetPlayerFacing and GetPlayerFacing() or 0)) % PI2
		end
		local radius = (mm:GetWidth() / 2) - 8
		-- bearing 0 = north = top of minimap
		local x = sin(angle) * radius
		local y = cos(angle) * radius
		-- clamp to square if minimap is square
		if S.db.profile.minimap and S.db.profile.minimap.shape ~= "ROUND" then
			local half = radius
			x = math.max(-half, math.min(half, x))
			y = math.max(-half, math.min(half, y))
		end
		self2:ClearAllPoints()
		self2:SetPoint("CENTER", mm, "CENTER", x, y)
		self2:Show()
		-- dashed path: center -> edge pin (bearing 0 = up)
		local ux, uy = sin(angle), cos(angle) -- unit dir, y up
		local rot = math.pi / 2 - angle
		local dash, step, thick = 6, 10, 3
		local n = 0
		for d = 4, radius - 10, step do
			n = n + 1
			local t = self2.lines[n]
			if not t then
				t = self2:CreateTexture(nil, "OVERLAY")
				t:SetTexture("Interface\\Buttons\\WHITE8X8")
				t:SetVertexColor(0.25, 0.85, 1, 0.85)
				self2.lines[n] = t
			end
			t:ClearAllPoints()
			t:SetPoint("CENTER", mm, "CENTER", ux * (d + dash / 2), uy * (d + dash / 2))
			t:SetSize(dash, thick)
			t:SetRotation(rot)
			t:Show()
		end
		for i = n + 1, #self2.lines do self2.lines[i]:Hide() end
	end)
	self.mmPin = pin
end

-- quest navigation ------------------------------------------------------------
-- maps already searched for POIs; filled lazily, quests can live in other zones
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

-- external quest databases keep their own spawn data (way richer than
-- Blizzard POIs on classic). Pull the nearest objective spawn when available.
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
	-- retail waypoint API
	if C_QuestLog and C_QuestLog.GetNextWaypointForQuest and mapID then
		local ok, x, y = pcall(C_QuestLog.GetNextWaypointForQuest, questID, mapID)
		if ok and x and y then return mapID, x, y end
	end
	-- quest POIs: current map first, then every known zone map
	local m, x, y = QuestPOIOnMap(questID, mapID)
	if m then return m, x, y end
	for m2 in pairs(ZoneMaps()) do
		if m2 ~= mapID then
			m, x, y = QuestPOIOnMap(questID, m2)
			if m then return m, x, y end
		end
	end
	-- legacy POI API: QuestPOIGetIconInfo(questId, index) -> questID, ?, ?, ?, x, y on current map
	if QuestPOIGetIconInfo and mapID then
		for i = 1, 16 do
			local ok, qid, _, _, _, x2, y2 = pcall(QuestPOIGetIconInfo, questID, i)
			if not ok or qid == nil then break end
			if qid == questID and x2 and y2 and x2 > 0 then return mapID, x2, y2 end
		end
	end
	-- external spawn database as last resort (covers nearly every quest)
	return ExternalQuestPosition(questID)
end

-- resolve the questID for a quest log index on any client
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

-- resolve the questID behind a quest log button on any client
local function QuestIDForButton(btn)
	if not btn then return end
	if btn.questID then return btn.questID end
	return QuestIDForLogIndex(btn.questLogIndex or (btn.GetID and btn:GetID()))
end

function NAV:NavigateToQuest(questID)
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
		or (GetQuestLogTitle and select(1, GetQuestLogTitle(questID))) or (L["Quest"])
	local mapID, x, y = self:QuestPosition(questID)
	if mapID and x and y then
		self:AddWaypoint(mapID, x, y, title)
	else
		S:Print(format(L["No map position for quest '%s'."], title or "?"))
	end
end

function NAV:HookQuestLog()
	-- modern quest map buttons (the quest log embedded in the world map)
	if _G.QuestMapLogTitleButton_OnClick and not self.qmHooked then
		self.qmHooked = true
		hooksecurefunc("QuestMapLogTitleButton_OnClick", function(btn, button)
			if button == "RightButton" and btn and btn.questID then
				NAV:NavigateToQuest(btn.questID)
			end
		end)
	end
	-- classic quest log: hook the title buttons directly. Names differ per
	-- client (QuestLogTitleButton* vs. unnamed scroll children), so scan.
	local function QuestLogRows()
		local rows, seen = {}, {}
		local function Add(b)
			if b and not seen[b] then seen[b] = true rows[#rows + 1] = b end
		end
		for i = 1, 40 do Add(_G["QuestLogTitleButton" .. i]) end
		-- scroll children (classic scroll child or modern contents frame)
		local scroll = _G.QuestLogListScrollFrame or _G.QuestLogScrollFrame or _G.QuestScrollFrame
		local child = scroll and ((scroll.GetScrollChild and scroll:GetScrollChild()) or scroll.Contents or scroll)
		if child and child.GetChildren then
			for _, c in ipairs({ child:GetChildren() }) do
				if c.IsObjectType and c:IsObjectType("Button") then Add(c) end
			end
		end
		-- last resort: recurse the quest log for buttons that look like rows
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
		return rows
	end
	local hooked = 0
	for _, btn in ipairs(QuestLogRows()) do
		if not btn.suiNavHooked then
			btn.suiNavHooked = true
			hooked = hooked + 1
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
		-- visible per-row navigation button ("»" arrow at the row's right edge)
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
	-- show the arrow only on real quest rows (not zone headers)
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
	-- visible navigate button in the quest log bottom bar (selected quest)
	local qf = _G.QuestLogFrame
	if qf and not qf.suiNavBtn then
		local nav = CreateFrame("Button", "SuiQuestNavBtn", qf)
		nav:SetSize(100, 20)
		S:CreateBackdrop(nav, "Default")
		-- Blizzard puts Abandon/Share at the bottom-left; park ours bottom-right
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
	S:LogInfo("nav", format("questlog hooked: rows=%d detailBtn=%s abandon=%s selFn=%s", hooked,
		tostring(qf and qf.suiNavBtn ~= nil), tostring(_G.QuestLogFrameAbandonButton ~= nil), tostring(GetQuestLogSelection ~= nil)))
	-- fallback: global handler name on clients that keep it
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

-- quest tracker (side panel): right-click a tracked quest line -> navigate.
-- QuestWatchLine is a FontString on classic (no mouse), so invisible overlay
-- buttons sit on top of each line and get the quest index after every update.
local function QuestTitleOfIndex(idx)
	if not GetQuestLogTitle then return end
	local ok, a = pcall(GetQuestLogTitle, idx)
	if not ok then return end
	if type(a) == "table" then return a.title end
	return a
end

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
					local title = QuestTitleOfIndex(self.questIndex)
					GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
					if title then GameTooltip:AddLine(title, 1, 1, 1) end
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

-- slash commands --------------------------------------------------------------
local function FindZone(name)
	if not C_Map or not C_Map.GetMapChildrenInfo then return end
	name = strlower(name)
	-- continents: 946 cosmic -> continents; try common continent maps
	for _, continent in ipairs({ 1414, 1415, 1945, 113, 424, 619, 875, 876, 1550, 1978, 2132, 2274 }) do
		local ok, children = pcall(C_Map.GetMapChildrenInfo, continent)
		if ok and children then
			for _, info in ipairs(children) do
				if info.name and strlower(info.name) == name then return info.mapID end
			end
			for _, info in ipairs(children) do -- partial match fallback
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
		print("  /sway debug / conv 1-4 - arrow diagnostics")
		print("  " .. L["World map:"] .. " Ctrl+" .. L["Right-click"] .. " = " .. L["set waypoint"])
		print("  " .. L["Quest log:"] .. " " .. L["Right-click"] .. " = " .. L["navigate to quest"])
		return
	end
	local cmd, rest = input:match("^(%S+)%s*(.*)$")
	cmd = strlower(cmd or "")
	if cmd == "debug" then
		local cur = CurrentMap()
		local a = self.active
		S:Print(format("nav debug: curMap=%s", tostring(cur)))
		if a then S:Print(format("  wp: map=%s x=%.4f y=%.4f title=%s", tostring(a.mapID), a.wp.x or -1, a.wp.y or -1, tostring(a.wp.title))) end
		if C_Map and C_Map.GetPlayerMapPosition and cur then
			local p = C_Map.GetPlayerMapPosition(cur, "player")
			if p and p.GetXY then local px, py = p:GetXY() S:Print(format("  playerMapPos: %.4f %.4f", px or -1, py or -1)) end
		end
		if UnitPosition then
			local py, px, pz, inst = UnitPosition("player")
			S:Print(format("  unitPos: y=%.1f x=%.1f z=%.1f inst=%s", py or -1, px or -1, pz or -1, tostring(inst)))
		end
		if a and C_Map.GetMapPosFromWorldPos and CreateVector3D and UnitPosition then
			local py, px, pz = UnitPosition("player")
			local ok, rmap, mpos = pcall(C_Map.GetMapPosFromWorldPos, a.mapID, CreateVector3D(px or 0, py or 0, pz or 0))
			if ok and mpos and mpos.GetXY then
				local mx, my = mpos:GetXY()
				S:Print(format("  convToWpMap: rmap=%s %.4f %.4f", tostring(rmap), mx or -1, my or -1))
			else S:Print("  convToWpMap: failed " .. tostring(mpos)) end
		end
		if C_Map and C_Map.GetMapWorldSize and a then
			local w, h = C_Map.GetMapWorldSize(a.mapID)
			S:Print(format("  wpMapSize: %sx%s", tostring(w), tostring(h)))
		end
		if a then
			local d, b, oz = VectorTo(a.mapID, a.wp.x, a.wp.y)
			S:Print(format("  result: dist=%s bearing=%.2f otherZone=%s facing=%.2f",
				tostring(d and floor(d)), b or -1, tostring(oz), GetPlayerFacing and GetPlayerFacing() or -1))
		end
		return
	end
	if cmd == "reset" or cmd == "clearall" then
		self:ClearWaypoints() S:Print(L["All waypoints removed."]) return
	elseif cmd == "clear" then
		self.active = nil if self.arrow then self.arrow:Hide() end return
	elseif cmd == "arrow" then
		if self.arrow then self.arrow:SetShown(not self.arrow:IsShown()) end return
	elseif cmd == "closest" then
		self:SetArrowToClosest() return
	elseif cmd == "route" then
		local wmf = _G.WorldMapFrame
		local canvas = wmf and (wmf.GetCanvas and wmf:GetCanvas() or wmf.ScrollContainer)
		S:Print(format("route: wmf=%s shown=%s canvas=%s", tostring(wmf ~= nil),
			tostring(wmf and wmf:IsShown()), tostring(canvas ~= nil)))
		local mapID = wmf and wmf.GetMapID and wmf:GetMapID()
		S:Print(format("  mapID=%s active=%s wpmap=%s", tostring(mapID),
			tostring(self.active ~= nil), tostring(self.active and self.active.mapID)))
		if self.active and HBD then
			local wx, wy, wi = HBD:GetWorldCoordinatesFromZone(self.active.wp.x, self.active.wp.y, self.active.mapID)
			local px, py, pi = HBD:GetPlayerWorldPosition()
			S:Print(format("  hbd w=%s,%s@%s p=%s,%s@%s", tostring(wx), tostring(wy), tostring(wi),
				tostring(px), tostring(py), tostring(pi)))
			if mapID and px and wx then
				local mx1, my1 = HBD:GetZoneCoordinatesFromWorldInstance(px, py, pi, mapID, true)
				local mx2, my2 = HBD:GetZoneCoordinatesFromWorldInstance(wx, wy, wi, mapID, true)
				S:Print(format("  onMap p=%.3f,%.3f w=%.3f,%.3f", mx1 or -1, my1 or -1, mx2 or -1, my2 or -1))
			end
		elseif self.active then
			S:Print("  HBD=nil")
		end
		if canvas then local cw, ch = canvas:GetSize() S:Print(format("  canvas=%.0fx%.0f", cw or -1, ch or -1)) end
	elseif cmd == "conv" then
		local c = tonumber(rest)
		if not (c and c >= 1 and c <= 4) then S:Print(L["Usage: /sway conv 1-4"]) return end
		self.db.arrowConv = floor(c)
		S:Print(format("nav conv -> %d", self.db.arrowConv))
		return
	elseif cmd == "size" then
		local s = tonumber(rest)
		if not s then S:Print(L["Usage: /sway size 24-160"]) return end
		s = min(160, max(24, floor(s)))
		self.db.arrowSize = s
		if self.arrow then self.arrow:SetSize(s, s + 56) self.arrow.tex:SetSize(s, s) end
		S:Print(format(L["Arrow size: %d (scroll on the arrow to resize)"], s))
		return
	elseif cmd == "list" then
		local found
		for mapID, list in pairs(WaypointDB()) do
			local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
			for _, wp in ipairs(list) do
				found = true
				S:Print(format("%s: %.1f, %.1f - %s", info and info.name or ("map " .. mapID), wp.x * 100, wp.y * 100, wp.title or ""))
			end
		end
		if not found then S:Print(L["No waypoints."]) end
		return
	end
	-- parse: "x y [title]" for current map, or "<zone> x y [title]"
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

-- corpse arrow ----------------------------------------------------------------
function NAV:CorpseWaypoint()
	if not self.db.corpseArrow then return end
	if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return end
	local mapID = CurrentMap()
	if not mapID then return end
	local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
	if ok and pos and pos.GetXY then
		local x, y = pos:GetXY()
		if x and y and x > 0 then self:AddWaypoint(mapID, x, y, L["Corpse"], { corpse = true }) end
	end
end

function NAV:Update()
	self.db = S.db.profile.navigation
	if self.arrow then
		local size = self.db.arrowSize or 56
		self.arrow:SetSize(size, size + 56)
		self.arrow.tex:SetSize(size, size)
		self.arrow:SetAlpha(self.db.arrowAlpha or 1)
		self:RefreshPins()
	end
end

-- Waypoint-compat facade -------------------------------------------------------
-- quest guide addons look for the global "TomTom" table and call its API for
-- waypoints/navigation. We expose our own nav through the same public
-- interface so they integrate automatically. If the real addon is installed
-- we take its methods over so a single (Sentinel) arrow is used.
function NAV:SetupWaypointFacade()
	local TT = _G.TomTom
	if TT then
		TT.__sui_orig = TT.__sui_orig or { AddWaypoint = TT.AddWaypoint, RemoveWaypoint = TT.RemoveWaypoint }
	else
		TT = { version = "SentinelUI", api = "compat" }
	end
	local function WpTitle(opts)
		return type(opts) == "table" and (opts.title or opts.minimap_desc or opts.worldmap_desc) or nil
	end
	function TT:AddWaypoint(mapID, x, y, opts)
		opts = opts or {}
		return NAV:AddWaypoint(mapID, x, y, WpTitle(opts), { silent = opts.silent, crazy = opts.crazy, corpse = opts.corpse })
	end
	TT.AddMFWaypoint = TT.AddWaypoint
	-- classic waypoint signature: AddZWaypoint(continent, zoneMapID, x, y, desc, ...)
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
		for mapID, list in pairs(WaypointDB()) do
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
	if S.LogInfo then S:LogInfo("navigation", "waypoint facade installed (override=" .. tostring(TT.__sui_orig ~= nil) .. ")") end
end

function NAV:Initialize()
	self.db = S.db.profile.navigation
	if self.db.enable == false then return end
	-- arrowConv values saved during broken-math testing are meaningless now;
	-- verified convention (bearing + facing, CCW-negated = conv 1, matching
	-- HereBeDragons-Pins' proven facing math) is the default
	if not self.db.convV3 then self.db.convV3 = true self.db.arrowConv = nil end
	self.pins = {}
	self:BuildArrow()
	self:BuildMinimapPin()
	self:HookWorldMap()
	self:HookQuestLog()
	self:HookTracker()
	-- rescan rows whenever the quest log shows (rows may be created lazily);
	-- per-button guards make the hook idempotent
	local qf = _G.QuestLogFrame
	if qf then
		qf:HookScript("OnShow", function()
			S:SafeCall("Nav:QuestLog", function() NAV:HookQuestLog() end)
		end)
	end
	self:SetupWaypointFacade()
	self:RegisterEvent("PLAYER_DEAD", function() C_Timer.After(1, function() NAV:CorpseWaypoint() end) end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() NAV:RefreshPins() if NAV.active == nil and NAV.db.autoQueue ~= false then NAV:SetArrowToClosest() end end)
	S:RegisterChatCommand("sway", function(msg) NAV:Slash(msg) end)
	S:RegisterChatCommand("suiway", function(msg) NAV:Slash(msg) end)
	S:LogInfo("nav", format("apis: unitPos=%s worldPos=%s facing=%s", tostring(UnitPosition ~= nil),
		tostring(C_Map and C_Map.GetWorldPosFromMapPos ~= nil), tostring(GetPlayerFacing ~= nil)))
	-- hard diagnosis: is the vendored HBD actually registered, and does it know
	-- our zone maps? Without this VectorTo silently falls back to bad math.
	local hbdInfo = "hbd=" .. tostring(HBD ~= nil)
	if HBD then
		local md = HBD.mapData and (HBD.mapData[1436] ~= nil)
		local px, py, pi = HBD:GetPlayerWorldPosition()
		hbdInfo = hbdInfo .. format(" md1436=%s p=%s,%s@%s", tostring(md),
			tostring(px), tostring(py), tostring(pi))
	end
	S:LogInfo("nav", hbdInfo)
	S:Print("|cff88ff88nav:|r " .. hbdInfo)
	local externalNav = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("TomTom")) or (IsAddOnLoaded and IsAddOnLoaded("TomTom"))
	if not externalNav then
		S:RegisterChatCommand("way", function(msg) NAV:Slash(msg) end)
	end
end
