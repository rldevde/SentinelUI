-- Button bars: collects minimap/LDB/Blizzard buttons into expandable bars.
-- Bars either dock to a screen edge (draggable handle line) or hang on their
-- own minimap rim button. Grabbed buttons keep their scripts and tooltips;
-- their position/visibility methods are neutralized so the owning addon
-- cannot yank them back while collected.
local _, ns = ...
local S = ns.S
local L = S.L
local BB = S:NewModule("ButtonBars", "buttonBars")

local _G = _G
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local sort, tinsert, tremove, unpack, pcall = sort, tinsert, tremove, unpack, pcall
local BLANK = [[Interface\Buttons\WHITE8X8]]

local IsSecret = S.IsSecret
local ldb = LibStub("LibDataBroker-1.1", true)
local ldbi = LibStub("LibDBIcon-1.0", true)

local function ResolvePath(path)
	local obj = _G
	for part in path:gmatch("[^%.]+") do
		obj = obj and obj[part]
	end
	return obj
end

BB.buttons = {}      -- ordered list of collected buttons (created + grabbed)
BB.grabbed = {}      -- button -> params table
BB.created = {}      -- name -> button created from an LDB data object
BB.focusMap = {}     -- any frame inside a collected button -> owning button
BB.bars = {}         -- bar frames by index
BB.names = {}        -- name -> button lookup for options

local function void() end

local function RawCall(obj, method, ...)
	return getmetatable(obj).__index[method](obj, ...)
end

-- frame names that must never be collected
local builtinIgnore = {
	SentinelUIMinimapCollector = true,
	SentinelUIMinimapCollectorToggle = true,
	SentinelUIMinimapHolder = true,
	-- UI chrome stays on the minimap: main logo + burger menu are part of
	-- the interface itself, not collectable module shortcuts
	SentinelUIMinimapButton = true,
	SentinelUIMinimapMenuButton = true,
}
local builtinPatterns = {
	"^SentinelUIButtonBar",
	"^SentinelUIMinimapButton_SUIBar",
	"^GatherMatePin%d+$",
	"^TTMinimapButton%d+$",
	"^MinimapBackdrop$",
	"^HandyNotes",
}

-- Blizzard's own minimap cluster buttons, collectable via `grabBlizzard`
local blizzardButtons = {
	"MiniMapTracking", "MiniMapTrackingButton", "MiniMapMailFrame",
	"MiniMapBattlefieldFrame", "MiniMapLFGFrame", "LFGMinimapFrame",
	"MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton",
	"GameTimeFrame", "TimeManagerClockButton", "QueueStatusMinimapButton",
	"ExpansionLandingPageMinimapButton", "GarrisonLandingPageMinimapButton",
	"MiniMapVoiceChatFrame",
}
local blizzardSet = {}
for _, n in ipairs(blizzardButtons) do blizzardSet[n] = true end

-------------------------------------------------------------------------------
-- button config helpers
-------------------------------------------------------------------------------

function BB:BtnCfg(name)
	local cfg = self.db.btn[name]
	if not cfg then
		cfg = {}
		self.db.btn[name] = cfg
	end
	return cfg
end

function BB:BarOf(name)
	local cfg = self.db.btn[name]
	local idx = cfg and cfg.bar or 1
	return self.bars[idx] or self.bars[1]
end

function BB:Ignored(name)
	if not name then return true end
	if builtinIgnore[name] then return true end
	for _, pat in ipairs(builtinPatterns) do
		if name:match(pat) then return true end
	end
	for pat in self.db.ignorePatterns:gmatch("[^,]+") do
		pat = strtrim(pat)
		if pat ~= "" and name:match(pat) then return true end
	end
	local cfg = self.db.btn[name]
	if cfg and cfg.ignore then return true end
	return self.db.ignore[name] and true or false
end

-- desired visibility inside the bar. Default follows the owning addon's own
-- Show/Hide calls (mail icon only shows when mail waits etc.); `off` hides it
-- entirely, `auto = false` pins it visible even when the addon hid it.
function BB:WantedShown(btn)
	local p = self.grabbed[btn]
	if not p then return true end
	local cfg = self.db.btn[p.name]
	if cfg and cfg.off then return false end
	if cfg and cfg.auto == false then return true end
	return p.isShown and true or false
end

-------------------------------------------------------------------------------
-- collected-button enter/leave -> bar show/hide plumbing
-------------------------------------------------------------------------------

-- bars may sit on TOOLTIP strata (docked bars do); without this a button
-- tooltip renders UNDER the bar/buttons -> unreadable. Measured against the
-- hovered button itself: collected buttons can carry a pinned frame level
-- well above their bar's.
local function RaiseTooltip(frame)
	if not GameTooltip:IsShown() then return end
	GameTooltip:SetFrameStrata("TOOLTIP")
	-- bars are SetToplevel(true): toplevel frames render above normal frames
	-- of the same strata regardless of level -> the tooltip must be toplevel
	-- too, or it can never win against the bar
	GameTooltip:SetToplevel(true)
	local lvl = frame and frame.GetFrameLevel and frame:GetFrameLevel() or 0
	local need = math.min(lvl + 20, 10000)
	if GameTooltip:GetFrameLevel() < need then
		GameTooltip:SetFrameLevel(need)
	end
end

local function BtnEnter(btn)
	local p = BB.grabbed[btn]
	local bar = p and p.bar
	if not bar or not bar:IsShown() then return end
	bar.isMouse = true
	bar:DoEnter()
	C_Timer.After(0, function()
		if not bar:IsShown() then return end
		RaiseTooltip(btn)
		if BB.db.interceptTooltip then
			S:SafeCall("ButtonBars:Tooltip", bar.FixTooltip, bar, btn)
		end
	end)
end

local function BtnLeave(btn)
	local p = BB.grabbed[btn]
	local bar = p and p.bar
	if bar and bar:IsShown() then
		bar.isMouse = false
		bar:DoLeave()
	end
end

-- safety net for every tooltip whose owner lives inside one of our bars
-- (covers delayed OnTooltipShow callbacks and foreign OnEnter scripts)
GameTooltip:HookScript("OnShow", function(tt)
	local f = tt:GetOwner()
	while f and f ~= UIParent do
		if BB.grabbed and BB.grabbed[f] then
			RaiseTooltip(f)
			return
		end
		if not (f.GetParent) then break end
		local ok, parent = pcall(f.GetParent, f)
		if not ok or not parent then break end
		f = parent
	end
end)

-- neutralize every way the owning addon could move/size/hide the button while
-- it lives on our bar; Show/Hide still work logically and drive `isShown`
local voidMethods = {
	"SetFrameStrata", "SetFixedFrameStrata", "SetFrameLevel", "SetFixedFrameLevel",
	"SetHitRectInsets", "ClearAllPoints", "StartMoving", "SetParent", "SetPoint",
	"SetAlpha", "SetIgnoreParentScale", "SetScale", "SetSize", "SetWidth",
	"SetHeight", "SetMotionScriptsWhileDisabled",
}

local function FilteredSetScript(self, event, func, ...)
	event = event:lower()
	if func == nil or (event ~= "ondragstart" and event ~= "ondragstop") then
		return RawCall(self, "SetScript", event, func, ...)
	end
end

local function FilteredHookScript(self, event, ...)
	event = event:lower()
	if event ~= "ondragstart" and event ~= "ondragstop" then
		return RawCall(self, "HookScript", event, ...)
	end
end

local function NeuterAnimations(btn)
	btn.CreateAnimationGroup = function(self, ...)
		local group = RawCall(self, "CreateAnimationGroup", ...)
		group.Play = void
		group.Restart = void
		return group
	end
	for _, group in ipairs({ RawCall(btn, "GetAnimationGroups") }) do
		local disable
		for _, anim in ipairs({ group:GetAnimations() }) do
			local t = anim:GetObjectType()
			if anim:GetTarget() == btn and t ~= "Animation" and t ~= "Rotation" then
				disable = true
				break
			end
		end
		if disable then
			group:Stop()
			group.Play = void
			group.Restart = void
		elseif group:IsPlaying() then
			C_Timer.After(0, function() group:Restart() end)
		end
	end
end

-- a LibDBIcon button "LibDBIcon10_X" and our LDB-created button "X" are the
-- same addon entry - compare stripped names so we never collect both
local function BaseName(name)
	return name and (name:gsub("^LibDBIcon10_", "") or name) or name
end

function BB:SimilarCollected(name)
	local base = BaseName(name)
	for _, btn in ipairs(self.buttons) do
		local p = self.grabbed[btn]
		if p and BaseName(p.name) == base then return btn end
	end
end

function BB:GrabButton(btn, name, autoDefault)
	if self.grabbed[btn] or not self.db.enabled then return end
	if type(btn) ~= "table" or type(btn[0]) ~= "userdata" then return end
	if btn.IsProtected and btn:IsProtected() then return end
	local oType = btn:GetObjectType()
	if oType ~= "Button" and oType ~= "Frame" and oType ~= "CheckButton" then return end
	name = name or btn:GetName()
	if not name or self:Ignored(name) then return end
	if InCombatLockdown() then
		return S:RunOutOfCombat(self.GrabButton, self, btn, name, autoDefault)
	end
	-- a real minimap button beats an LDB-created stand-in for the same object
	local dup = self.created[name] or self.created[BaseName(name)]
	if dup then self:ReleaseButton(dup) end
	if not self.created[name] and self:SimilarCollected(name) then return end

	local cfg = self:BtnCfg(name)
	if cfg.auto == nil and autoDefault then cfg.auto = true end

	local p = {
		name = name,
		isShown = RawCall(btn, "IsShown"),
		parent = RawCall(btn, "GetParent"),
		alpha = RawCall(btn, "GetAlpha"),
		scale = RawCall(btn, "GetScale"),
		strata = RawCall(btn, "GetFrameStrata"),
		level = RawCall(btn, "GetFrameLevel"),
		points = {},
		regions = {},
	}
	p.w, p.h = RawCall(btn, "GetSize")
	if btn.IsIgnoringParentScale then p.ignoreScale = btn:IsIgnoringParentScale() end
	if btn.HasFixedFrameStrata then p.fixedStrata = btn:HasFixedFrameStrata() end
	if btn.HasFixedFrameLevel then p.fixedLevel = btn:HasFixedFrameLevel() end
	for i = 1, RawCall(btn, "GetNumPoints") do
		p.points[i] = { RawCall(btn, "GetPoint", i) }
	end
	if oType == "Button" or oType == "CheckButton" then
		p.onDragStart = btn:GetScript("OnDragStart")
		p.onDragStop = btn:GetScript("OnDragStop")
		if btn.GetMotionScriptsWhileDisabled then
			p.motionDisabled = btn:GetMotionScriptsWhileDisabled()
		end
	end
	self.grabbed[btn] = p
	self.names[name] = btn
	tinsert(self.buttons, btn)

	-- recursive enter/leave wiring so hovering any part of the button counts
	local function wire(f)
		self.focusMap[f] = btn
		local hasMouse = f.IsMouseMotionEnabled and f:IsMouseMotionEnabled()
			or f.IsMouseClickEnabled and f:IsMouseClickEnabled()
		if hasMouse then
			local fp = { insets = { RawCall(f, "GetHitRectInsets") } }
			p.regions[f] = fp
			RawCall(f, "SetHitRectInsets", 0, 0, 0, 0)
			if f:HasScript("OnEnter") then
				fp.onEnter = f:GetScript("OnEnter")
				f:HookScript("OnEnter", function() BtnEnter(btn) end)
			else
				f:SetScript("OnEnter", function() BtnEnter(btn) end)
			end
			if f:HasScript("OnLeave") then
				fp.onLeave = f:GetScript("OnLeave")
				f:HookScript("OnLeave", function() BtnLeave(btn) end)
			else
				f:SetScript("OnLeave", function() BtnLeave(btn) end)
			end
		else
			p.regions[f] = false
		end
		for _, child in ipairs({ f:GetChildren() }) do wire(child) end
	end
	wire(btn)

	for _, m in ipairs(voidMethods) do btn[m] = void end
	btn.SetScript = FilteredSetScript
	btn.HookScript = FilteredHookScript
	btn.SetShown = function(b, show)
		if p.isShown == show then return end
		p.isShown = show
		if cfg.auto and not cfg.off and p.bar then BB:LayoutBar(p.bar) end
	end
	btn.Show = function(b) b:SetShown(true) end
	btn.Hide = function(b) b:SetShown(false) end
	btn.IsShown = function(b)
		local show = BB:WantedShown(b)
		RawCall(b, "SetShown", show)
		return show
	end
	NeuterAnimations(btn)

	-- strip the round minimap chrome and pull the icon edge-in - but never
	-- touch the textures the button actually needs to render/click with
	local keepTex = {}
	local icon = btn.icon or btn.Icon
	if icon then keepTex[icon] = true end
	for _, m in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetCheckedTexture" }) do
		if btn[m] then
			local t = btn[m](btn)
			if t then keepTex[t] = true end
		end
	end
	for _, region in ipairs({ btn:GetRegions() }) do
		if region:IsObjectType("Texture") and not keepTex[region] then
			local tex = region:GetTexture()
			if type(tex) == "string" and (tex:find("Border") or tex:find("Background") or tex:find("TrackingBorder")) then
				p.hiddenRegions = p.hiddenRegions or {}
				p.hiddenRegions[region] = region:GetAlpha()
				region:SetAlpha(0)
			elseif type(tex) == "number" and (tex == 136430 or tex == 136467) then
				p.hiddenRegions = p.hiddenRegions or {}
				p.hiddenRegions[region] = region:GetAlpha()
				region:SetAlpha(0)
			end
		end
	end
	if icon and icon.SetTexCoord then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	-- no backdrop on foreign buttons: keep the addon's own look and never
	-- cover the icon (a child frame would render grey over it)
	if oType == "Button" or oType == "CheckButton" then
		RawCall(btn, "SetMotionScriptsWhileDisabled", true)
		RawCall(btn, "SetScript", "OnDragStart", nil)
		RawCall(btn, "SetScript", "OnDragStop", nil)
	end
	RawCall(btn, "SetIgnoreParentScale", false)
	-- fixed strata/level (LibDBIcon sets both) pins the button to its own
	-- MEDIUM/level-8 layer under our bar - it would render behind the bar
	-- backdrop and clicks would land on the bar instead of the button
	if btn.SetFixedFrameStrata then RawCall(btn, "SetFixedFrameStrata", false) end
	if btn.SetFixedFrameLevel then RawCall(btn, "SetFixedFrameLevel", false) end
	RawCall(btn, "SetAlpha", 1)
	RawCall(btn, "SetParent", self:BarOf(name))
	p.bar = self:BarOf(name)
end

-- put a collected button back where it came from
function BB:ReleaseButton(btn)
	local p = self.grabbed[btn]
	if not p then return end
	if InCombatLockdown() then
		return S:RunOutOfCombat(self.ReleaseButton, self, btn)
	end
	self.grabbed[btn] = nil
	if p.name then self.names[p.name] = nil self.created[p.name] = nil end
	for i, b in ipairs(self.buttons) do
		if b == btn then tremove(self.buttons, i) break end
	end

	-- created LDB buttons have no original spot: just orphan and hide them
	if p.created then
		btn:Hide()
		RawCall(btn, "SetParent", nil)
		if p.bar then self:LayoutBar(p.bar) end
		return
	end

	for _, m in ipairs(voidMethods) do btn[m] = nil end
	btn.SetScript = nil
	btn.HookScript = nil
	btn.SetShown = nil
	btn.Show = nil
	btn.Hide = nil
	btn.IsShown = nil
	btn.CreateAnimationGroup = nil
	for _, group in ipairs({ RawCall(btn, "GetAnimationGroups") }) do
		group.Play = nil
		group.Restart = nil
	end

	for frame, fp in pairs(p.regions) do
		self.focusMap[frame] = nil
		if fp then
			RawCall(frame, "SetHitRectInsets", unpack(fp.insets))
			if frame.HasScript and frame:HasScript("OnEnter") then RawCall(frame, "SetScript", "OnEnter", fp.onEnter) end
			if frame.HasScript and frame:HasScript("OnLeave") then RawCall(frame, "SetScript", "OnLeave", fp.onLeave) end
		end
	end
	if p.hiddenRegions then
		for region, alpha in pairs(p.hiddenRegions) do region:SetAlpha(alpha) end
	end
	if p.motionDisabled ~= nil then RawCall(btn, "SetMotionScriptsWhileDisabled", p.motionDisabled) end
	RawCall(btn, "SetScript", "OnDragStart", p.onDragStart)
	RawCall(btn, "SetScript", "OnDragStop", p.onDragStop)

	RawCall(btn, "SetShown", p.isShown)
	RawCall(btn, "SetParent", p.parent or Minimap)
	RawCall(btn, "SetAlpha", p.alpha)
	if btn.SetIgnoreParentScale then RawCall(btn, "SetIgnoreParentScale", p.ignoreScale) end
	RawCall(btn, "SetScale", p.scale)
	RawCall(btn, "SetFrameStrata", p.strata)
	RawCall(btn, "SetFrameLevel", p.level)
	if btn.SetFixedFrameStrata then RawCall(btn, "SetFixedFrameStrata", p.fixedStrata) end
	if btn.SetFixedFrameLevel then RawCall(btn, "SetFixedFrameLevel", p.fixedLevel) end
	RawCall(btn, "ClearAllPoints")
	if p.points[1] then
		for _, pt in ipairs(p.points) do RawCall(btn, "SetPoint", unpack(pt)) end
	else
		local r = Minimap:GetWidth() / 2
		RawCall(btn, "SetPoint", "CENTER", Minimap, "CENTER", 0, r + 3)
	end
	-- released SentinelUI buttons go back to the minimap ring - re-spread so
	-- it does not land exactly on another module button again
	if p.name and p.name:find("^SentinelUI") and S.LayoutMinimapButtons then
		S:LayoutMinimapButtons()
	end
	if p.w then RawCall(btn, "SetSize", p.w, p.h) end
	if btn.suiBackdrop then btn.suiBackdrop:Hide() end
	if p.bar then self:LayoutBar(p.bar) end
end

-------------------------------------------------------------------------------
-- button sources
-------------------------------------------------------------------------------

-- LibDBIcon creates "LibDBIcon10_<name>" minimap buttons; the callback fires
-- for late-created ones too. Without ldbi we catch them in the minimap scan.
function BB:TryGrab(child)
	if type(child) ~= "table" or not child.GetSize then return end
	if child.IsProtected and child:IsProtected() then return end
	local w, h = child:GetSize()
	if not w or not h then return end
	local mw, mh = Minimap:GetSize()
	if w > mw * 0.5 or h > mh * 0.5 then return end
	if max(w, h) <= 14 or abs(w - h) > 6 then return end
	local name = child:GetName()
	if name and self:Ignored(name) then return end
	-- Blizzard's own cluster buttons only get collected when grabBlizzard
	-- is on - otherwise they keep their native place (inactive ones render
	-- greyed and dead in the bar)
	if name and blizzardSet[name] and not self.db.grabBlizzard then return end
	if not name and not self.db.grabUnnamed then return end

	local clickable = child.HasScript and child:HasScript("OnClick") and child:GetScript("OnClick")
	if not clickable then
		local function scan(f)
			if f.HasScript then
				for _, ev in ipairs({ "OnClick", "OnMouseUp", "OnMouseDown" }) do
					if f:HasScript(ev) and f:GetScript(ev) then return true end
				end
			end
			for _, c in ipairs({ f:GetChildren() }) do
				if scan(c) then return true end
			end
		end
		clickable = scan(child)
	end
	if not clickable then return end

	local isSUI = name and name:find("^SentinelUI")
	if isSUI and not self.db.collectSUI then return end
	self:GrabButton(child, name)
end

function BB:ScanMinimap()
	if not self.db.grabMinimap then return end
	for _, child in ipairs({ Minimap:GetChildren() }) do self:TryGrab(child) end
	if MinimapBackdrop then
		for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do self:TryGrab(child) end
	end
end

function BB:GrabBlizzard()
	if not self.db.grabBlizzard then return end
	for _, name in ipairs(blizzardButtons) do
		local btn = ResolvePath(name)
		if btn then self:GrabButton(btn, name, true) end
	end
end

function BB:CustomGrab()
	for name in self.db.customGrab:gmatch("[^,]+") do
		name = strtrim(name)
		if name ~= "" then
			local f = ResolvePath(name)
			if f then self:GrabButton(f, name) end
		end
	end
end

-- LDB data objects -> our own square buttons (no frame grabbing involved)
function BB:AddLDBObject(name, data)
	if self.created[name] or self:Ignored(name) then return end
	if self:SimilarCollected(name) then return end -- real button already in a bar
	if not data.icon then return end -- nothing to render -> dead grey box
	if name:find("^SentinelUI") and not self.db.collectSUI then return end
	if data.type ~= "launcher" and not (self.db.ldbAny and data.icon and data.OnClick) then return end
	if InCombatLockdown() then
		return S:RunOutOfCombat(self.AddLDBObject, self, name, data)
	end
	local cfg = self:BtnCfg(name)

	local btn = CreateFrame("Button", "SentinelUIButtonBarLDB_" .. name, nil)
	btn:SetSize(26, 26)
	btn:SetFrameStrata("MEDIUM")
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexture(data.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
	icon:SetTexCoord(unpack(data.iconCoords or { 0.07, 0.93, 0.07, 0.93 }))
	icon:SetVertexColor(data.iconR or 1, data.iconG or 1, data.iconB or 1)
	if data.iconDesaturated ~= nil then icon:SetDesaturated(data.iconDesaturated) end
	btn.icon = icon
	btn.data = data
	S:CreateBackdrop(btn, "Default")
	S:AddHover(btn)

	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetScript("OnClick", function(b, button, down)
		if data.OnClick then S:SafeCall("LDB:" .. name, data.OnClick, b, button, down) end
	end)
	btn:SetScript("OnEnter", function(b)
		BtnEnter(b)
		if data.OnEnter then
			S:SafeCall("LDB:" .. name, data.OnEnter, b)
		elseif data.OnTooltipShow then
			GameTooltip:SetOwner(b, "ANCHOR_NONE")
			S:SafeCall("LDB:" .. name, data.OnTooltipShow, GameTooltip)
			GameTooltip:Show()
		elseif data.label or data.text or name then
			GameTooltip:SetOwner(b, "ANCHOR_LEFT")
			GameTooltip:AddLine(data.label or data.text or name)
			GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function(b)
		BtnLeave(b)
		if data.OnLeave then S:SafeCall("LDB:" .. name, data.OnLeave, b)
		else GameTooltip:Hide() end
	end)

	local p = { name = name, isShown = true, created = true }
	self.grabbed[btn] = p
	self.created[name] = btn
	self.names[name] = btn
	tinsert(self.buttons, btn)
	p.bar = self:BarOf(name)
	RawCall(btn, "SetParent", p.bar)
end

function BB:ScanLDB()
	if not ldb or not self.db.grabLDB then return end
	for name, data in ldb:DataObjectIterator() do
		-- a LibDBIcon button for this object is collected by the minimap scan;
		-- only objects without a visible icon need a created button
		local hasIcon = ldbi and ldbi:IsRegistered(name)
		if not hasIcon then self:AddLDBObject(name, data) end
	end
end

function BB:Rescan()
	if not self.db.enabled then return end
	-- DataTexts panels may be created after us: retry pending dock buttons
	for _, bar in ipairs(self.bars) do
		if bar.cfg.mode == "DOCK" then
			if not bar.dockBtn then
				self:CreateDockButton(bar)
				bar:RefreshState()
			elseif not bar.dockPanel and not bar.cfg.dockPos then
				-- parked as fallback; dock once the data strip exists
				self:ReDock(bar)
			end
		end
	end
	local n = #self.buttons
	self:ScanMinimap()
	self:GrabBlizzard()
	self:ScanLDB()
	self:CustomGrab()
	-- drop created LDB stand-ins once the addon's real button got collected
	local seen = {}
	for i = #self.buttons, 1, -1 do
		local btn = self.buttons[i]
		local p = self.grabbed[btn]
		if p then
			local base = BaseName(p.name)
			if p.created and seen[base] then
				self:ReleaseButton(btn)
			else
				seen[base] = true
			end
		end
	end
	if #self.buttons ~= n then
		self:SortButtons()
		for _, bar in ipairs(self.bars) do self:LayoutBar(bar) end
		self:NotifyOptions()
	end
end

function BB:SortButtons()
	local grabbed = self.grabbed
	sort(self.buttons, function(a, b)
		local pa, pb = grabbed[a], grabbed[b]
		local an, bn = tostring(pa and pa.name), tostring(pb and pb.name)
		-- SentinelUI's own buttons stay grouped before the foreign ones
		local as_, bs = an:find("^SentinelUI") and 1 or 2, bn:find("^SentinelUI") and 1 or 2
		if as_ ~= bs then return as_ < bs end
		local ca, cb = pa and self.db.btn[pa.name], pb and self.db.btn[pb.name]
		local oa, ob = ca and ca.order, cb and cb.order
		if oa or ob then return (oa or 999) < (ob or 999) end
		return an < bn
	end)
end

function BB:NotifyOptions()
	if S.options then
		S.options = S:BuildOptions()
		local ACR = LibStub("AceConfigRegistry-3.0", true)
		if ACR then ACR:NotifyChange("SentinelUI") end
	end
end

-- resync per-button settings (ignore/off/bar/order) -> release or re-grab
function BB:ApplyButtonSettings()
	for i = #self.buttons, 1, -1 do
		local btn = self.buttons[i]
		local p = self.grabbed[btn]
		if p and (self:Ignored(p.name) or (blizzardSet[p.name] and not self.db.grabBlizzard)) then
			self:ReleaseButton(btn)
		end
	end
	for _, btn in ipairs(self.buttons) do
		local p = self.grabbed[btn]
		local bar = self:BarOf(p.name)
		if p.bar ~= bar then
			p.bar = bar
			RawCall(btn, "SetParent", bar)
		end
	end
	self:SortButtons()
	for _, bar in ipairs(self.bars) do self:LayoutBar(bar) end
end

-------------------------------------------------------------------------------
-- bar mixin
-------------------------------------------------------------------------------

local barMixin = {}

-- point on the bar's edge that sits at `position`, per anchor + expand mode
local expandPoint = {
	left   = { "TOPLEFT", "BOTTOMLEFT", "LEFT" },
	right  = { "TOPRIGHT", "BOTTOMRIGHT", "RIGHT" },
	top    = { "TOPLEFT", "TOPRIGHT", "TOP" },
	bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOM" },
}

-- TOOLTIP strata is deliberately never used for a bar: many addon buttons
-- draw their own tooltip frames (not GameTooltip) on TOOLTIP strata and a bar
-- living there would cover them. FULLSCREEN_DIALOG is still above chat/panels.
local function StrataName(i)
	return ({ "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "FULLSCREEN_DIALOG" })[i] or "MEDIUM"
end

function barMixin:IsVertical()
	local cfg = self.cfg
	if cfg.orientation == "HORIZONTAL" then return false end
	if cfg.orientation == "VERTICAL" then return true end
	if cfg.mode == "MINIMAP" then
		return self.ombSide == "LEFT" or self.ombSide == "RIGHT" or not self.ombSide
	end
	if cfg.mode == "DOCK" then
		-- rows of buttons expanding away from the data strip
		return self.dockSide == "LEFT" or self.dockSide == "RIGHT"
	end
	-- AUTO: the bar extends perpendicular to its edge - top/bottom edges
	-- grow columns downward, left/right edges grow rows sideways
	return cfg.anchor == "top" or cfg.anchor == "bottom"
end

function barMixin:Directions()
	local cfg = self.cfg
	if cfg.dirV == "AUTO" or not cfg.dirV then
		if cfg.mode == "DOCK" then
			-- bar above the strip grows up, below grows down; side bars grow
			-- away from their alignment edge
			if self.dockSide == "BOTTOM" then self.dirV = "TOP"
			elseif self.dockSide == "TOP" then self.dirV = "BOTTOM"
			else self.dirV = (self.dockAlign == "TOP") and "TOP" or "BOTTOM" end
		else
			self.dirV = (cfg.anchor == "bottom") and "BOTTOM" or "TOP"
		end
	else
		self.dirV = cfg.dirV
	end
	if cfg.dirH == "AUTO" or not cfg.dirH then
		if cfg.mode == "DOCK" then
			if self.dockSide == "LEFT" then self.dirH = "RIGHT"
			elseif self.dockSide == "RIGHT" then self.dirH = "LEFT"
			else self.dirH = (self.dockAlign == "RIGHT") and "RIGHT" or "LEFT" end
		else
			self.dirH = (cfg.anchor == "right") and "RIGHT" or "LEFT"
		end
	else
		self.dirH = cfg.dirH
	end
	self.rPoint = self.dirV .. self.dirH
end

function barMixin:Layout()
	self:Directions()
	local cfg = self.cfg
	local bs, spacing = cfg.buttonSize, cfg.spacing
	local perLine = max(1, cfg.size)
	local vert = self:IsVertical()
	local off = cfg.offset

	local list = {}
	for _, btn in ipairs(BB.buttons) do
		local p = BB.grabbed[btn]
		if p and p.bar == self then
			local show = BB:WantedShown(btn)
			RawCall(btn, "SetShown", show)
			if show then list[#list + 1] = btn end
		end
	end

	for i, btn in ipairs(list) do
		local p = BB.grabbed[btn]
		local n = i - 1
		local step = bs + spacing
		local col, row = n % perLine, floor(n / perLine)
		local x = off + bs / 2 + (vert and row or col) * step
		local y = -(off + bs / 2) - (vert and col or row) * step
		if self.dirV == "BOTTOM" then y = -y end
		if self.dirH == "RIGHT" then x = -x end
		local w, h = p.w or 26, p.h or 26
		if p.created then w, h = RawCall(btn, "GetWidth"), RawCall(btn, "GetHeight") end
		local scale = bs / max(w, h)
		if not p.created then RawCall(btn, "SetScale", scale) end
		if p.created then btn:SetSize(bs, bs) scale = 1 end
		RawCall(btn, "ClearAllPoints")
		RawCall(btn, "SetPoint", "CENTER", self, self.rPoint, x / scale, y / scale)
	end

	local n = max(1, #list)
	local a, b = min(perLine, n), ceil(n / perLine)
	local cols, rows = (vert and b or a), (vert and a or b)
	local w = off * 2 + cols * (bs + spacing) - spacing
	local h = off * 2 + rows * (bs + spacing) - spacing
	self:SetSize(max(w, bs + off * 2), max(h, bs + off * 2))
	self:PositionHandle()
	if self.cfg.mode == "MINIMAP" then self:UpdateMinimapPosition() end
	if self.cfg.mode == "DOCK" then self:UpdateDockPosition() end
end

-- thin drag line on the side of the bar facing the screen edge
function barMixin:PositionHandle()
	local h = self.handle
	local cfg = self.cfg
	if cfg.mode ~= "EDGE" then
		h:Hide()
		return
	end
	local lw = cfg.lineWidth
	h:ClearAllPoints()
	if not self:IsShown() then
		-- collapsed: a small handle resting on the edge
		if cfg.anchor == "left" then
			h:SetPoint("LEFT", self, "LEFT", 0, 0)
			h:SetSize(lw, max(30, cfg.buttonSize + cfg.offset * 2))
		elseif cfg.anchor == "right" then
			h:SetPoint("RIGHT", self, "RIGHT", 0, 0)
			h:SetSize(lw, max(30, cfg.buttonSize + cfg.offset * 2))
		elseif cfg.anchor == "top" then
			h:SetPoint("TOP", self, "TOP", 0, 0)
			h:SetSize(max(30, cfg.buttonSize + cfg.offset * 2), lw)
		else
			h:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
			h:SetSize(max(30, cfg.buttonSize + cfg.offset * 2), lw)
		end
		return
	end
	if cfg.anchor == "left" then
		h:SetPoint("TOPLEFT", self, "TOPRIGHT", cfg.gap, 0)
		h:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", cfg.gap, 0)
		h:SetWidth(lw)
	elseif cfg.anchor == "right" then
		h:SetPoint("TOPRIGHT", self, "TOPLEFT", -cfg.gap, 0)
		h:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", -cfg.gap, 0)
		h:SetWidth(lw)
	elseif cfg.anchor == "top" then
		h:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -cfg.gap)
		h:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -cfg.gap)
		h:SetHeight(lw)
	else
		h:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, cfg.gap)
		h:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, cfg.gap)
		h:SetHeight(lw)
	end
end

function barMixin:UpdatePosition()
	local cfg = self.cfg
	if cfg.mode == "DOCK" then return self:UpdateDockPosition() end
	if cfg.mode ~= "EDGE" then return self:UpdateMinimapPosition() end
	local point = expandPoint[cfg.anchor][(cfg.expand or 2) + 1]
	local sec = cfg.secondPosition or 0
	local pos = cfg.position or 0
	self:ClearAllPoints()
	if cfg.anchor == "left" then
		self:SetPoint(point, UIParent, "BOTTOMLEFT", sec, pos)
	elseif cfg.anchor == "right" then
		self:SetPoint(point, UIParent, "BOTTOMRIGHT", -sec, pos)
	elseif cfg.anchor == "top" then
		self:SetPoint(point, UIParent, "TOPLEFT", pos, -sec)
	else
		self:SetPoint(point, UIParent, "BOTTOMLEFT", pos, sec)
	end
	self:PositionHandle()
end

-- MINIMAP mode: bar hangs off its own rim button, on the side facing the
-- screen interior, centered on the button
function barMixin:UpdateMinimapPosition()
	local omb = self.omb
	if not omb then return end
	local cfg = self.cfg
	local cx, cy = omb:GetCenter()
	if not cx then return end
	local W, H = UIParent:GetSize()
	local dx, dy = cx - W / 2, cy - H / 2
	local dist = cfg.ombDistance
	local oldSide = self.ombSide
	self:ClearAllPoints()
	if abs(dx) >= abs(dy) then
		if dx > 0 then
			self:SetPoint("RIGHT", omb, "LEFT", -dist, 0)
			self.ombSide = "LEFT"
		else
			self:SetPoint("LEFT", omb, "RIGHT", dist, 0)
			self.ombSide = "RIGHT"
		end
	else
		if dy > 0 then
			self:SetPoint("TOP", omb, "BOTTOM", 0, -dist)
			self.ombSide = "BOTTOM"
		else
			self:SetPoint("BOTTOM", omb, "TOP", 0, dist)
			self.ombSide = "TOP"
		end
	end
	if oldSide ~= self.ombSide then self:Layout() end
end

-- DOCK mode: bar sprouts from the dock button in the configured grow
-- direction (default: away from the nearest screen edge)
function barMixin:UpdateDockPosition()
	local btn = self.dockBtn or self.dockPanel
	if not btn then return end
	local cx, cy = btn:GetCenter()
	if not cx then return end
	local W, H = UIParent:GetSize()
	local dx, dy = cx - W / 2, cy - H / 2
	local dist = self.cfg.ombDistance or 4
	local grow = self.cfg.dockGrow or "AUTO"
	local oldSide, oldAlign = self.dockSide, self.dockAlign
	if grow == "AUTO" then
		grow = (abs(dy) >= abs(dx))
			and (dy > 0 and "DOWN" or "UP")
			or (dx > 0 and "LEFT" or "RIGHT")
	end
	self:ClearAllPoints()
	if grow == "UP" then
		self.dockAlign = (dx > 0) and "RIGHT" or "LEFT"
		self:SetPoint("BOTTOM" .. self.dockAlign, btn, "TOP" .. self.dockAlign, 0, dist)
		self.dockSide = "TOP"
	elseif grow == "DOWN" then
		self.dockAlign = (dx > 0) and "RIGHT" or "LEFT"
		self:SetPoint("TOP" .. self.dockAlign, btn, "BOTTOM" .. self.dockAlign, 0, -dist)
		self.dockSide = "BOTTOM"
	elseif grow == "LEFT" then
		self.dockAlign = (dy > 0) and "TOP" or "BOTTOM"
		self:SetPoint(self.dockAlign .. "RIGHT", btn, self.dockAlign .. "LEFT", -dist, 0)
		self.dockSide = "LEFT"
	else
		self.dockAlign = (dy > 0) and "TOP" or "BOTTOM"
		self:SetPoint(self.dockAlign .. "LEFT", btn, self.dockAlign .. "RIGHT", dist, 0)
		self.dockSide = "RIGHT"
	end
	-- arrow on the dock button points in the grow direction
	local icon = self.dockBtn and self.dockBtn.icon
	if icon then
		local rot = (self.dockSide == "TOP" and 0) or (self.dockSide == "BOTTOM" and 180)
			or (self.dockSide == "LEFT" and 90) or 270
		icon:SetRotation(math.rad(rot))
	end
	if oldSide ~= self.dockSide or oldAlign ~= self.dockAlign then self:Layout() end
end

-- cursor-driven drag for the EDGE handle (port of HidingBar's edge logic:
-- slide along the edge, re-anchor when pushed past a corner)
function barMixin:OnDrag()
	local cfg = self.cfg
	local scale = self:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale + self.dragDX, y / scale + self.dragDY
	local W, H = UIParent:GetSize()
	local w, h = self:GetSize()
	local anchor = cfg.anchor

	if not IsShiftKeyDown() then
		if anchor == "top" or anchor == "bottom" then
			if abs(W / 2 - x) < 10 / scale then x = W / 2 end
		elseif abs(H / 2 - y) < 10 / scale then y = H / 2 end
	end

	local edge = 70 / scale
	if (anchor == "left" and x > w) or (anchor == "right" and x < W - w) then
		if y > H - edge then anchor = "top" elseif y < edge then anchor = "bottom" end
	elseif (anchor == "top" and y < H - h) or (anchor == "bottom" and y > h) then
		if x < edge then anchor = "left" elseif x > W - edge then anchor = "right" end
	end
	if anchor ~= cfg.anchor then
		cfg.anchor = anchor
		self:Directions()
		self:Layout()
	end

	local pos
	if anchor == "left" or anchor == "right" then
		local delta = cfg.expand == 0 and -h / 2 or cfg.expand == 1 and h / 2 or 0
		pos = y - delta
	else
		local delta = cfg.expand == 0 and w / 2 or cfg.expand == 1 and -w / 2 or 0
		pos = x - delta
	end
	cfg.position = pos
	self:UpdatePosition()
end

-- is the mouse currently over one of our buttons (incl. children/menus)?
function barMixin:FocusInside()
	local f = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
	local guard = 0
	while f and guard < 60 do
		guard = guard + 1
		if f == self or f == self.handle or f == self.omb or f == self.dockBtn then return true end
		local btn = BB.focusMap[f]
		if btn then
			local p = BB.grabbed[btn]
			if p and p.bar == self then return true end
		end
		local ok, pf = pcall(f.GetParent, f)
		f = ok and pf or nil
	end
	return false
end

function barMixin:FixTooltip(btn)
	if not GameTooltip:IsShown() then return end
	RaiseTooltip(btn or self)
	local cfg = self.cfg
	GameTooltip:ClearAllPoints()
	if cfg.mode == "MINIMAP" or cfg.mode == "DOCK" then
		local side = self.ombSide or self.dockSide or "LEFT"
		if side == "LEFT" then GameTooltip:SetPoint("RIGHT", self, "LEFT", -6, 0)
		elseif side == "RIGHT" then GameTooltip:SetPoint("LEFT", self, "RIGHT", 6, 0)
		elseif side == "TOP" then GameTooltip:SetPoint("TOP", self, "BOTTOM", 0, -6)
		else GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 6) end
		return
	end
	if cfg.anchor == "left" then GameTooltip:SetPoint("LEFT", self, "RIGHT", 6, 0)
	elseif cfg.anchor == "right" then GameTooltip:SetPoint("RIGHT", self, "LEFT", -6, 0)
	elseif cfg.anchor == "top" then GameTooltip:SetPoint("TOP", self, "BOTTOM", 0, -6)
	else GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 6) end
end

local function FadeTo(frame, alpha, time)
	if UIFrameFadeOut then
		UIFrameFadeOut(frame, time or 0.4, frame:GetAlpha(), alpha)
	else
		frame:SetAlpha(alpha)
	end
end

function barMixin:DoEnter()
	if self.isDrag then return end
	self:SetScript("OnUpdate", nil)
	self.hideTimer = nil
	if self.cfg.showHandler == "ALWAYS" then
		if self.cfg.fade then FadeTo(self, 1, 0.2) end
		return
	end
	if not self:IsShown() then
		self:Show()
		self:Layout()
		self:UpdatePosition()
	end
	if self.handle then FadeTo(self.handle, 1, 0.15) end
end

function barMixin:DoLeave(force)
	if self.isDrag then return end
	if self.cfg.showHandler == "ALWAYS" then
		if self.cfg.fade then FadeTo(self, self.cfg.fadeOpacity, 0.4) end
		return
	end
	if not self:IsShown() then return end
	if self.pinned then return end
	local mode = self.cfg.hideHandler
	if mode == "NEVER" then return end
	if mode == "CLICKOUT" and not force then
		-- stays until a click outside; nothing to schedule on leave
		return
	end
	self.hideTimer = self.cfg.hideDelay
	self:SetScript("OnUpdate", self.HideTick)
end

function barMixin:HideTick(elapsed)
	if self:FocusInside() then
		self.hideTimer = self.cfg.hideDelay
		return
	end
	self.hideTimer = self.hideTimer - elapsed
	if self.hideTimer <= 0 then
		self:SetScript("OnUpdate", nil)
		self:HideNow()
	end
end

function barMixin:HideNow()
	if self.cfg.showHandler == "ALWAYS" then return end
	self:Hide()
	self.pinned = false
	self:PositionHandle()
	if self.cfg.fade and self.handle then FadeTo(self.handle, self.cfg.fadeOpacity, 0.6) end
end

function barMixin:OnGlobalClick(button)
	if button ~= "LeftButton" and button ~= "RightButton" then return end
	if self.isMouse or self:FocusInside() then return end
	local h = self.handle
	if h and h:IsShown() and h:IsMouseOver() then return end
	if self.omb and self.omb:IsShown() and self.omb:IsMouseOver() then return end
	if self.dockBtn and self.dockBtn:IsShown() and self.dockBtn:IsMouseOver() then return end
	self:HideNow()
end

function barMixin:ApplyStyle()
	local cfg = self.cfg
	S:SetTemplate(self, cfg.border and "Default" or "Transparent")
	self:SetBackdropColor(0.05, 0.05, 0.05, cfg.bgAlpha)
	self:SetFrameStrata(StrataName(cfg.strata))
	if self.handle then self.handle:SetFrameStrata(StrataName(cfg.strata)) end
end

function barMixin:RefreshState()
	local cfg = self.cfg
	if cfg.hidden or (BB.petBattle and BB.db.petBattleHide) then
		self:Hide()
		if self.handle then self.handle:Hide() end
		if self.omb then self.omb:Hide() end
		if self.dockBtn then self.dockBtn:Hide() end
		return
	end
	if self.omb then self.omb:Show() end
	if self.dockBtn then self.dockBtn:Show() end
	-- the handle line is the opener in EDGE mode; lock only disables dragging
	self.handle:SetShown(cfg.mode == "EDGE")
	if cfg.showHandler == "ALWAYS" then
		self:Show()
		self:Layout()
		self:UpdatePosition()
		if cfg.fade then self:SetAlpha(cfg.fadeOpacity) end
	else
		if self.handle and cfg.fade then self.handle:SetAlpha(cfg.fadeOpacity) else if self.handle then self.handle:SetAlpha(1) end end
		if self:IsShown() and not self.isMouse then self:DoLeave() end
	end
	self:ApplyStyle()
end

-------------------------------------------------------------------------------
-- handle (drag line) + own minimap button
-------------------------------------------------------------------------------

local function LineTitle(bar)
	return "|cffffb347" .. (bar.cfg.name or L["Button Bar"]) .. "|r"
end

local function handle_OnEnter(self)
	local bar = self.bar
	S.HoverEnter(self)
	if bar.cfg.showHandler == "HOVER" then
		if bar.cfg.showDelay > 0 then
			bar.hoverTimer = bar.cfg.showDelay
			bar:SetScript("OnUpdate", function(b, elapsed)
				b.hoverTimer = b.hoverTimer - elapsed
				if b.hoverTimer <= 0 then
					b:SetScript("OnUpdate", nil)
					b:DoEnter()
				end
			end)
		else
			bar:DoEnter()
		end
	elseif bar.cfg.showHandler ~= "ALWAYS" and bar.cfg.fade and not bar:IsShown() then
		FadeTo(self, 1, 0.2)
	end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(LineTitle(self.bar))
	GameTooltip:AddLine(L["Drag: move  |  Click: open/close  |  Alt+Right click: lock"], 0.7, 0.7, 0.7)
	GameTooltip:Show()
	RaiseTooltip(self.bar)
end

local function handle_OnLeave(self)
	local bar = self.bar
	S.HoverLeave(self)
	GameTooltip:Hide()
	bar.hoverTimer = nil
	bar:SetScript("OnUpdate", nil)
	if bar.cfg.showHandler ~= "ALWAYS" and bar.cfg.fade and not bar:IsShown() then
		FadeTo(self, bar.cfg.fadeOpacity, 0.6)
	end
	bar:DoLeave()
end

local function handle_OnClick(self, button)
	local bar = self.bar
	if button ~= "LeftButton" then return end
	if bar:IsShown() then
		if bar.cfg.showHandler == "ALWAYS" then return end
		bar:HideNow()
	else
		-- a click always pins the bar open until clicked again (or hidden)
		bar.pinned = true
		bar:DoEnter()
	end
end

local function handle_OnMouseDown(self, button)
	local bar = self.bar
	if button == "LeftButton" and not bar.cfg.lock and bar:IsShown() then
		local x, y = GetCursorPosition()
		local cx, cy = self:GetCenter()
		local scale = bar:GetEffectiveScale()
		if cx then
			bar.dragDX = cx - x / scale
			bar.dragDY = cy - y / scale
		end
	elseif button == "RightButton" then
		if IsAltKeyDown() then
			bar.cfg.lock = not bar.cfg.lock
			bar:RefreshState()
			S:Print((bar.cfg.lock and L["Bar locked"] or L["Bar unlocked"]) .. " (" .. tostring(bar.cfg.name) .. ")")
		end
		if IsShiftKeyDown() then
			S:ToggleConfig({ "buttonBars" })
		end
	end
end

local cover = CreateFrame("Frame")
cover:Hide()
cover:EnableMouse(true)

local function handle_OnDragStart(self)
	local bar = self.bar
	if bar.cfg.lock or not bar:IsShown() then return end
	bar.isDrag = true
	cover:SetFrameStrata(bar:GetFrameStrata())
	cover:SetFrameLevel(bar:GetFrameLevel() + 10)
	cover:SetAllPoints(bar)
	cover:Show()
	bar:SetScript("OnUpdate", function() bar:OnDrag() end)
end

local function handle_OnDragStop(self)
	local bar = self.bar
	if not bar.isDrag then return end
	bar.isDrag = false
	cover:Hide()
	bar:SetScript("OnUpdate", nil)
	if not bar.isMouse then bar:DoLeave() end
end

local function bar_OnEnter(self)
	if self:IsShown() then
		self.isMouse = true
		self:DoEnter()
	end
end

local function bar_OnLeave(self)
	self.isMouse = false
	self:DoLeave()
end

local function bar_OnShow(self)
	if self.cfg.hideHandler == "CLICKOUT" or self.cfg.hideHandler == "BOTH" then
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end
end

local function bar_OnHide(self)
	self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
end

local function bar_OnEvent(self, event, button)
	self:OnGlobalClick(button)
end

-- own rim button for MINIMAP-mode bars (draggable along the map edge)
function BB:CreateOMB(bar)
	local cfg = bar.cfg
	cfg.omb = cfg.omb or {}
	local btn = S:CreateMinimapButton({
		name = "SUIBar" .. bar.id,
		glyph = tostring(bar.id),
		angle = cfg.omb.angle or 200,
		store = cfg.omb,
		onLeft = function()
			if bar:IsShown() then bar:HideNow()
			else bar.pinned = true bar:DoEnter() end
		end,
		onRight = function()
			bar.cfg.lock = not bar.cfg.lock
			S:Print((bar.cfg.lock and L["Bar locked"] or L["Bar unlocked"]) .. " (" .. tostring(bar.cfg.name) .. ")")
		end,
		tooltip = function(b)
			GameTooltip:AddLine("|cffffb347" .. (cfg.name or L["Button Bar"]) .. "|r")
			GameTooltip:AddLine(L["Click: open/close  |  Right click: lock"], 0.7, 0.7, 0.7)
		end,
	})
	bar.omb = btn
	btn:HookScript("OnEnter", function()
		if bar.cfg.showHandler == "HOVER" then bar:DoEnter() end
		C_Timer.After(0, function() RaiseTooltip(bar) end)
	end)
	btn:HookScript("OnLeave", function() bar:DoLeave() end)
	-- the button is the handle: bar re-anchors whenever it moves
	hooksecurefunc(btn, "SetPoint", function()
		if bar.cfg.mode == "MINIMAP" then C_Timer.After(0, function() if bar:IsShown() then bar:UpdateMinimapPosition() end end) end
	end)
	-- ungrab our own handle
	local name = btn:GetName()
	self.db.btn[name] = self.db.btn[name] or {}
	self.db.btn[name].ignore = true
end

-- small square button docked inside a DataTexts panel (DOCK mode); clicking it
-- expands the bar away from the strip (bottom strip -> upward)
function BB:LayoutDockButtons(panel)
	local list = panel.suiDockBtns
	if not list then return end
	local w = 0
	for i, b in ipairs(list) do
		b:ClearAllPoints()
		b:SetPoint("RIGHT", panel, "RIGHT", -2 - (w), 0)
		w = w + b:GetWidth() + 2
	end
	panel.suiDockW = #list > 0 and (w + 2) or 0
	local DT = S:GetModule("DataTexts")
	if DT and DT.LayoutPanel then DT:LayoutPanel(panel) end
end

-- (re)docks the button into its configured panel or parks it free-floating
function BB:ReDock(bar)
	local cfg = bar.cfg
	local btn = bar.dockBtn
	if not btn then return end
	local oldPanel = bar.dockPanel
	if oldPanel and oldPanel.suiDockBtns then
		for j, b2 in ipairs(oldPanel.suiDockBtns) do
			if b2 == btn then tremove(oldPanel.suiDockBtns, j) break end
		end
		self:LayoutDockButtons(oldPanel)
	end
	if cfg.dockPos then
		bar.dockPanel = nil
		btn:SetParent(UIParent)
		btn:ClearAllPoints()
		btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cfg.dockPos.x, cfg.dockPos.y)
	else
		local DT = S:GetModule("DataTexts")
		local panel = DT and DT.panels and DT.panels[cfg.panel or "LeftChat"]
		if panel and panel:IsObjectType("Frame") then
			bar.dockPanel = panel
			btn:SetParent(panel)
			panel.suiDockBtns = panel.suiDockBtns or {}
			tinsert(panel.suiDockBtns, btn)
			self:LayoutDockButtons(panel)
		else
			-- no data strip (module off or panel gone): park the button below
			-- the minimap so the bar always has a reachable opener
			bar.dockPanel = nil
			btn:SetParent(UIParent)
			btn:ClearAllPoints()
			btn:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
		end
	end
	bar:UpdateDockPosition()
end

function BB:CreateDockButton(bar)
	if bar.dockBtn then return end
	local cfg = bar.cfg
	local DT = S:GetModule("DataTexts")
	local panel = DT and DT.panels and DT.panels[cfg.panel or "LeftChat"]
	local h = max(16, (panel and panel:GetHeight() or 22) - 2)
	local btn = CreateFrame("Button", "SentinelUIDockBtn" .. bar.id, UIParent, S.BackdropTemplate)
	btn:SetSize(h, h)
	S:CreateBackdrop(btn, "Default")
	S:AddHover(btn)
	local icon = btn:CreateTexture(nil, "OVERLAY")
	icon:SetPoint("CENTER", 0, 0)
	icon:SetSize(h * 0.7, h * 0.7)
	icon:SetTexture([[Interface\Buttons\Arrow-Up-Up]])
	icon:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
	btn.icon = icon
	btn.bar = bar
	bar.dockBtn = btn
	self:ReDock(bar)
	local dockPanel = panel
	if dockPanel then
		dockPanel:HookScript("OnShow", function() if bar.cfg.mode == "DOCK" and bar.dockPanel == dockPanel and not (BB.petBattle and BB.db.petBattleHide) and not bar.cfg.hidden then btn:Show() end end)
		dockPanel:HookScript("OnHide", function() if bar.dockPanel == dockPanel then btn:Hide() bar:HideNow() end end)
		hooksecurefunc(dockPanel, "SetHeight", function()
			if bar.cfg.mode == "DOCK" and bar.dockPanel == dockPanel then
				local nh = max(16, (dockPanel:GetHeight() or 22) - 2)
				btn:SetSize(nh, nh)
				icon:SetSize(nh * 0.7, nh * 0.7)
				BB:LayoutDockButtons(dockPanel)
			end
		end)
	end

	-- drag to reposition: drop inside a data strip to dock there, drop
	-- anywhere else to park it free-floating
	btn:RegisterForDrag("LeftButton")
	btn:SetMovable(true)
	btn:SetScript("OnDragStart", function(b)
		if bar.cfg.lock then return end
		b.dragged = true
		if not b:IsMovable() then b:SetMovable(true) end
		-- StartMoving can throw "Frame is not movable" under taint; drag is
		-- purely cosmetic, so a failed start just skips the drag
		pcall(b.StartMoving, b)
	end)
	btn:SetScript("OnDragStop", function(b)
		b:StopMovingOrSizing()
		C_Timer.After(0, function() b.dragged = nil end)
		local cx, cy = b:GetCenter()
		if cx and DT and DT.panels then
			for name, p in pairs(DT.panels) do
				if p:IsShown() then
					local l, bo, r, t = p:GetLeft(), p:GetBottom(), p:GetRight(), p:GetTop()
					if l and cx >= l and cx <= r and cy >= bo and cy <= t then
						cfg.panel = name
						cfg.dockPos = nil
						BB:ReDock(bar)
						return
					end
				end
			end
		end
		cfg.dockPos = { x = b:GetLeft() or 0, y = b:GetBottom() or 0 }
		BB:ReDock(bar)
	end)

	btn:RegisterForClicks("AnyUp")
	btn:SetScript("OnClick", function(b, button)
		if b.dragged then return end
		if button == "LeftButton" then
			if bar:IsShown() then bar:HideNow()
			else bar.pinned = true bar:DoEnter() end
		elseif button == "RightButton" then
			if IsShiftKeyDown() then
				S:ToggleConfig({ "buttonBars" })
			else
				bar.cfg.lock = not bar.cfg.lock
				S:Print((bar.cfg.lock and L["Bar locked"] or L["Bar unlocked"]) .. " (" .. tostring(bar.cfg.name) .. ")")
			end
		end
	end)
	btn:SetScript("OnEnter", function(b)
		bar.isMouse = true
		icon:SetVertexColor(1, 1, 1)
		if bar.cfg.showHandler == "HOVER" then
			if bar.cfg.showDelay > 0 then
				bar.hoverTimer = bar.cfg.showDelay
				bar:SetScript("OnUpdate", function(bb, elapsed)
					bb.hoverTimer = bb.hoverTimer - elapsed
					if bb.hoverTimer <= 0 then
						bb:SetScript("OnUpdate", nil)
						bb:DoEnter()
					end
				end)
			else
				bar:DoEnter()
			end
		end
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		GameTooltip:AddLine(LineTitle(bar))
		GameTooltip:AddLine(L["Click: open/close  |  Drag: move  |  Right click: lock"], 0.7, 0.7, 0.7)
		GameTooltip:Show()
		RaiseTooltip(bar)
	end)
	btn:SetScript("OnLeave", function(b)
		bar.isMouse = false
		icon:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
		GameTooltip:Hide()
		bar.hoverTimer = nil
		if not bar.isDrag then bar:SetScript("OnUpdate", nil) end
		bar:DoLeave()
	end)
end

function BB:CreateBar(i)
	local cfg = self.db.bars[i]
	local bar = CreateFrame("Frame", "SentinelUIButtonBar" .. i, UIParent, S.BackdropTemplate)
	bar.id = i
	bar.cfg = cfg
	bar:SetClampedToScreen(true)
	bar:SetToplevel(true)
	bar:EnableMouse(true)
	bar:SetFrameStrata("MEDIUM")
	bar:SetFrameLevel(50)
	for k, v in pairs(barMixin) do bar[k] = v end
	S:SetTemplate(bar, "Default")
	bar:SetScript("OnEnter", bar_OnEnter)
	bar:SetScript("OnLeave", bar_OnLeave)
	bar:SetScript("OnShow", bar_OnShow)
	bar:SetScript("OnHide", bar_OnHide)
	bar:SetScript("OnEvent", bar_OnEvent)
	bar:Hide()

	-- drag line
	local h = CreateFrame("Button", "SentinelUIButtonBarDrag" .. i, UIParent, S.BackdropTemplate)
	h.bar = bar
	h:SetClampedToScreen(true)
	h:SetHitRectInsets(-2, -2, -2, -2)
	h:SetFrameLevel(60)
	S:SetTemplate(h, "Default")
	local strip = h:CreateTexture(nil, "OVERLAY")
	strip:SetTexture(BLANK)
	strip:SetPoint("TOPLEFT", 1, -1)
	strip:SetPoint("BOTTOMRIGHT", -1, 1)
	strip:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.7)
	S:RegisterAccent(strip, "texture")
	h:RegisterForDrag("LeftButton")
	h:RegisterForClicks("AnyUp")
	h:SetScript("OnEnter", handle_OnEnter)
	h:SetScript("OnLeave", handle_OnLeave)
	h:SetScript("OnClick", handle_OnClick)
	h:SetScript("OnMouseDown", handle_OnMouseDown)
	h:SetScript("OnDragStart", handle_OnDragStart)
	h:SetScript("OnDragStop", handle_OnDragStop)
	bar.handle = h

	if cfg.mode == "MINIMAP" then
		self:CreateOMB(bar)
	elseif cfg.mode == "DOCK" then
		self:CreateDockButton(bar)
	end

	self.bars[i] = bar
	bar:Directions()
	bar:Layout()
	bar:UpdatePosition()
	bar:RefreshState()
	return bar
end

function BB:RebuildBars()
	-- release every button first, then drop/recreate bar frames
	for i = #self.buttons, 1, -1 do
		self:ReleaseButton(self.buttons[i])
	end
	for _, bar in ipairs(self.bars) do
		bar:Hide()
		bar.handle:Hide()
		if bar.omb then bar.omb:Hide() end
		if bar.dockBtn then
			local panel = bar.dockPanel
			bar.dockBtn:Hide()
			if panel and panel.suiDockBtns then
				for j, b in ipairs(panel.suiDockBtns) do
					if b == bar.dockBtn then tremove(panel.suiDockBtns, j) break end
				end
				self:LayoutDockButtons(panel)
			end
		end
	end
	wipe(self.bars)
	for i = 1, #self.db.bars do self:CreateBar(i) end
	self:Rescan()
end

function BB:LayoutBar(bar)
	if bar then bar:Layout() end
end

-------------------------------------------------------------------------------
-- diagnostics
-------------------------------------------------------------------------------

function BB:Dump()
	S:Print("enabled=" .. tostring(self.db.enabled),
		"bars=" .. #self.bars,
		"buttons=" .. #self.buttons,
		"ldb=" .. tostring(ldb ~= nil), "ldbi=" .. tostring(ldbi ~= nil))
	for i, bar in ipairs(self.bars) do
		local x, y = bar:GetCenter()
		S:Print(("bar%d '%s' mode=%s shown=%s size=%dx%d pos=%s,%s anchor=%s handle=%s"):format(
			i, tostring(bar.cfg.name), tostring(bar.cfg.mode), tostring(bar:IsShown()),
			floor(bar:GetWidth()), floor(bar:GetHeight()),
			tostring(x and floor(x)), tostring(y and floor(y)),
			tostring(bar.cfg.anchor), tostring(bar.handle:IsShown())))
	end
	for _, btn in ipairs(self.buttons) do
		local p = self.grabbed[btn]
		local enabled = btn.IsEnabled and btn:IsEnabled()
		local click = btn.HasScript and btn:HasScript("OnClick") and btn:GetScript("OnClick") and true or false
		local clickUp = btn.HasScript and btn:HasScript("OnMouseUp") and btn:GetScript("OnMouseUp") and true or false
		local l, r, t, bo = RawCall(btn, "GetHitRectInsets")
		S:Print("  - " .. tostring(p and p.name),
			"shown=" .. tostring(btn:IsShown()),
			"enab=" .. tostring(enabled),
			"click=" .. tostring(click or clickUp),
			"alpha=" .. tostring(RawCall(btn, "GetAlpha")),
			"hr=" .. tostring(l) .. "," .. tostring(r) .. "," .. tostring(t) .. "," .. tostring(bo),
			"bar=" .. tostring(p and p.bar and p.bar.id))
	end
	local n = 0
	for _, child in ipairs({ Minimap:GetChildren() }) do
		if child.GetName and child:GetName() then n = n + 1 S:Print("  mm-child: " .. child:GetName()) end
	end
	S:Print("minimap children: " .. n)
end

-------------------------------------------------------------------------------
-- module lifecycle
-------------------------------------------------------------------------------

function BB:Initialize()
	if not self.db.enabled then return end

	-- one-time migration of the old single collector settings
	local old = S.db.profile.minimap
	if old and old.buttonCollector ~= nil and not self.db.migrated then
		self.db.migrated = true
		self.db.collectSUI = old.collectSUI ~= false
		self.db.ignore = old.buttonIgnore or {}
		local b1 = self.db.bars[1]
		if b1 then
			b1.buttonSize = old.collectorSize or b1.buttonSize
			b1.spacing = old.collectorSpacing or b1.spacing
			b1.size = old.collectorPerRow or b1.size
			b1.showHandler = (old.collectorExpand == "CLICK") and "CLICK" or (old.collectorExpand == "ALWAYS") and "ALWAYS" or "HOVER"
		end
	end

	-- one-time move to the docked layout: opener lives in the bottom data
	-- strip (where Gold sits) and the bar expands upward on click
	if not self.db.dockMigrated then
		self.db.dockMigrated = true
		local b1 = self.db.bars[1]
		if b1 and b1.mode == "MINIMAP" then
			b1.mode = "DOCK"
			b1.panel = "LeftChat"
			b1.showHandler = "CLICK"
			b1.ombDistance = 4
		end
	end
	-- docked bars must render above the chat windows; default docks at the
	-- minimap strip and opens sideways
	local wasMigrated = self.db.dockFixed3
	if not self.db.dockFixed3 then
		self.db.dockFixed3 = true
		local b1 = self.db.bars[1]
		if b1 and b1.mode == "DOCK" then
			b1.strata = 6
			b1.panel = "Minimap"
			b1.dockGrow = "LEFT"
			b1.dockPos = nil
		end
	end
	-- profiles from before the collectSUI default flip relied on SUI buttons
	-- being collected; restore that behaviour exactly once per profile
	if not self.db.collectSUIMigrated then
		self.db.collectSUIMigrated = true
		if wasMigrated and self.db.collectSUI == false then
			self.db.collectSUI = true
		end
	end

	self:RegisterEvent("ADDON_LOADED", function() C_Timer.After(1, function() S:SafeCall("ButtonBars:Scan", BB.Rescan, BB) end) end)
	self:RegisterEvent("PET_BATTLE_OPENING_START", function() BB.petBattle = true for _, b in ipairs(BB.bars) do b:RefreshState() end end)
	self:RegisterEvent("PET_BATTLE_CLOSE", function() BB.petBattle = false for _, b in ipairs(BB.bars) do b:RefreshState() end end)

	for i = 1, #self.db.bars do self:CreateBar(i) end
	self.lastDb = self.db

	if ldbi and ldbi.RegisterCallback then
		ldbi.RegisterCallback(self, "LibDBIcon_IconCreated", function(_, button, name)
			S:SafeCall("ButtonBars:ldbi", function()
				if not BB:Ignored(name) and not BB.grabbed[button] then
					BB:GrabButton(button, name)
					BB:SortButtons()
					for _, bar in ipairs(BB.bars) do bar:Layout() end
					BB:NotifyOptions()
				end
			end)
		end)
	end
	if ldb and ldb.RegisterCallback then
		ldb.RegisterCallback(self, "LibDataBroker_DataObjectCreated", function(_, name, data)
			S:SafeCall("ButtonBars:ldb", function()
				BB:AddLDBObject(name, data)
				BB:SortButtons()
				for _, bar in ipairs(BB.bars) do bar:Layout() end
			end)
		end)
		ldb.RegisterCallback(self, "LibDataBroker_AttributeChanged__icon", function(_, name, key, value)
			local btn = BB.created[name]
			if btn then btn.icon:SetTexture(value) end
		end)
		ldb.RegisterCallback(self, "LibDataBroker_AttributeChanged__iconCoords", function(_, name, key, value)
			local btn = BB.created[name]
			if btn and type(value) == "table" then btn.icon:SetTexCoord(unpack(value)) end
		end)
	end

	-- initial + lazy scans: addons create buttons at arbitrary times
	self:Rescan()
	C_Timer.After(3, function() S:SafeCall("ButtonBars:Scan", BB.Rescan, BB) end)
	C_Timer.NewTicker(5, function()
		if BB.db and BB.db.enabled then S:SafeCall("ButtonBars:Scan", BB.Rescan, BB) end
	end)

	S:RegisterChatCommand("suibtn", function()
		S:SafeCall("ButtonBars:Dump", BB.Dump, BB)
		if BB.bars[1] then BB.bars[1]:Show() BB.bars[1]:Layout() end
	end)
end

function BB:Update()
	if not self.db.enabled then return end
	-- profile switches swap self.db: bar cfg references go stale -> rebuild
	if self.lastDb ~= self.db then
		self.lastDb = self.db
		self:RebuildBars()
		return
	end
	self:ApplyButtonSettings()
	for _, bar in ipairs(self.bars) do
		bar:Directions()
		bar:Layout()
		bar:UpdatePosition()
		bar:RefreshState()
	end
end
