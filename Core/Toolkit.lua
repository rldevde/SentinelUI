-- Visual toolkit: pixel-perfect templates and widget skinning helpers.
local _, ns = ...
local S = ns.S

local pairs, ipairs, type, select, floor, max, min = pairs, ipairs, type, select, math.floor, math.max, math.min
local BLANK = [[Interface\Buttons\WHITE8X8]]

S.mult = 1
S.templated = setmetatable({}, { __mode = "k" })
S.accentFrames = setmetatable({}, { __mode = "k" })

function S:UpdatePixelScale()
	-- 1 physical pixel = 1 / effectiveScale points (at scale 0.711 -> ~1.406 pt).
	-- Anything sized/offset by S.mult lands exactly on the pixel grid.
	local scale = UIParent:GetEffectiveScale()
	if not scale or scale <= 0 then scale = 1 end
	self.mult = 1 / scale
	local _, height = GetPhysicalScreenSize()
	self.screenHeight = height
end

function S:Scale(v)
	local m = self.mult
	return m * floor(v / m + 0.5)
end

-- Instance-level pixel snapping: wraps SetPoint/SetSize on our own frames so every
-- offset and size lands on the physical pixel grid (no blurry borders/text).
local function SnapSetPoint(self, point, rel, relPoint, x, y)
	if type(rel) == "number" then
		-- short form: SetPoint(point, x, y)
		return self.suiSetPoint(self, point, S:Scale(rel), relPoint and S:Scale(relPoint))
	end
	if type(x) == "number" then x = S:Scale(x) end
	if type(y) == "number" then y = S:Scale(y) end
	-- IMPORTANT: forward only the args actually given. Passing explicit nils makes
	-- the client treat relativeTo=nil as "screen" -> the element lands at screen
	-- center instead of anchoring to its parent.
	if rel == nil then
		return self.suiSetPoint(self, point)
	elseif relPoint == nil then
		return self.suiSetPoint(self, point, rel)
	end
	return self.suiSetPoint(self, point, rel, relPoint, x, y)
end
local function SnapSetSize(self, w, h)
	if type(w) == "number" then w = S:Scale(w) end
	if type(h) == "number" then h = S:Scale(h) end
	return self.suiSetSize(self, w, h)
end
local function SnapSetWidth(self, w)
	return self.suiSetWidth(self, type(w) == "number" and S:Scale(w) or w)
end
local function SnapSetHeight(self, h)
	return self.suiSetHeight(self, type(h) == "number" and S:Scale(h) or h)
end

function S:EnablePixelSnap(f)
	if not f or f.suiPixelSnap then return end
	-- never wrap methods on protected/secure frames: calling the wrapper during combat
	-- taints the secure call chain (ADDON_ACTION_BLOCKED on suiSetSize)
	if f.IsProtected and f:IsProtected() then return end
	f.suiPixelSnap = true
	f.suiSetPoint, f.suiSetSize = f.SetPoint, f.SetSize
	f.suiSetWidth, f.suiSetHeight = f.SetWidth, f.SetHeight
	f.SetPoint, f.SetSize = SnapSetPoint, SnapSetSize
	f.SetWidth, f.SetHeight = SnapSetWidth, SnapSetHeight
end

function S:SetOutside(obj, anchor, x, y)
	anchor = anchor or obj:GetParent()
	x, y = x or self.mult, y or x or self.mult
	obj:ClearAllPoints()
	obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -x, y)
	obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x, -y)
end

function S:SetInside(obj, anchor, x, y)
	anchor = anchor or obj:GetParent()
	x, y = x or self.mult, y or x or self.mult
	obj:ClearAllPoints()
	obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
	obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
end

local function EnsureBackdrop(frame)
	if frame.SetBackdrop then return end
	if not BackdropTemplateMixin then return end
	Mixin(frame, BackdropTemplateMixin)
	if frame.OnBackdropSizeChanged then
		frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
	end
end

local function ApplyTemplate(frame)
	local template = frame.suiTemplate
	local m = S.media
	local mult = S.mult
	if template == "NoBackdrop" then
		frame:SetBackdrop(nil)
		if frame.suiSheen then frame.suiSheen:Hide() end
	else
		frame:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = mult, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
		if template == "Transparent" then
			frame:SetBackdropColor(unpack(m.backdropFadeColor or { 0.05, 0.06, 0.08, 0.82 }))
		elseif template == "Clear" then
			frame:SetBackdropColor(0, 0, 0, 0)
		else
			frame:SetBackdropColor(unpack(m.backdropColor or { 0.075, 0.08, 0.1, 1 }))
		end
		frame:SetBackdropBorderColor(unpack(frame.suiBorderColor or m.borderColor or { 0, 0, 0, 1 }))

		-- Sentinel "glass": soft light sheen fading from the top edge downwards
		-- (instead of the classic inner 1px highlight border)
		local glow = S.db and S.db.profile.general.innerGlow
		if glow and template ~= "Clear" then
			if not frame.suiSheen then
				frame.suiSheen = frame:CreateTexture(nil, "BORDER", nil, -7)
				S:Gradient(frame.suiSheen, "VERTICAL", 1, 1, 1, 0, 0.06)
			end
			local sheen = frame.suiSheen
			sheen:ClearAllPoints()
			sheen:SetPoint("TOPLEFT", frame, "TOPLEFT", mult, -mult)
			sheen:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -mult, -mult)
			sheen:SetPoint("BOTTOM", frame, "CENTER", 0, 0)
			sheen:Show()
		elseif frame.suiSheen then
			frame.suiSheen:Hide()
		end
	end
	if frame.suiInner then frame.suiInner:Hide() end

	-- Sentinel signature: HUD corner brackets on the accent edge instead of a
	-- continuous line. 4 textures per frame (2 per corner), accent-colored.
	if frame.suiAccent and S.db and S.db.profile.general.accentLines then
		if not frame.suiTicks then
			frame.suiTicks = {}
			for i = 1, 4 do
				local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
				t:SetTexture(BLANK)
				frame.suiTicks[i] = t
			end
		end
		local ticks = frame.suiTicks
		local len, th = S:Scale(9), 2 * mult
		local vSide = frame.suiAccent == "BOTTOM" and "BOTTOM" or "TOP"
		-- left corner: horizontal + vertical
		ticks[1]:ClearAllPoints() ticks[1]:SetPoint(vSide .. "LEFT", frame, vSide .. "LEFT", 0, 0)
		ticks[1]:SetSize(len, th)
		ticks[2]:ClearAllPoints() ticks[2]:SetPoint(vSide .. "LEFT", frame, vSide .. "LEFT", 0, 0)
		ticks[2]:SetSize(th, len)
		-- right corner
		ticks[3]:ClearAllPoints() ticks[3]:SetPoint(vSide .. "RIGHT", frame, vSide .. "RIGHT", 0, 0)
		ticks[3]:SetSize(len, th)
		ticks[4]:ClearAllPoints() ticks[4]:SetPoint(vSide .. "RIGHT", frame, vSide .. "RIGHT", 0, 0)
		ticks[4]:SetSize(th, len)
		for i = 1, 4 do
			ticks[i]:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.95)
			ticks[i]:Show()
		end
		if frame.suiAccentLine then frame.suiAccentLine:Hide() end
	elseif frame.suiTicks then
		for i = 1, 4 do frame.suiTicks[i]:Hide() end
	end
end

-- template: "Default" | "Transparent" | "Clear" | "NoBackdrop"; accent: nil | "TOP" | "BOTTOM"
function S:SetTemplate(frame, template, accent, borderColor)
	if not frame then return end
	self:EnablePixelSnap(frame)
	EnsureBackdrop(frame)
	if not frame.SetBackdrop then return end
	frame.suiTemplate = template or "Default"
	frame.suiAccent = accent == true and "TOP" or accent
	frame.suiBorderColor = borderColor
	self.templated[frame] = true
	ApplyTemplate(frame)
end

function S:UpdateTemplates()
	for frame in pairs(self.templated) do ApplyTemplate(frame) end
	for obj, kind in pairs(self.accentFrames) do
		if kind == "texture" and obj.SetVertexColor then obj:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
		elseif kind == "text" and obj.SetTextColor then obj:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
	end
end

function S:RegisterAccent(obj, kind)
	self.accentFrames[obj] = kind
	if kind == "texture" then obj:SetVertexColor(S.accent.r, S.accent.g, S.accent.b) else obj:SetTextColor(S.accent.r, S.accent.g, S.accent.b) end
end

function S:CreateBackdrop(frame, template, accent, inset)
	if frame.suiBackdrop then return frame.suiBackdrop end
	local parent = frame.IsObjectType and frame:IsObjectType("Texture") and frame:GetParent() or frame
	local level = parent:GetFrameLevel()
	-- a backdrop at the same level as its parent covers the parent's regions
	-- (e.g. button text) -> bump the parent instead of staying at level 0
	if level == 0 then parent:SetFrameLevel(1) level = 1 end
	local bd = CreateFrame("Frame", nil, parent, self.BackdropTemplate)
	bd:SetFrameLevel(level - 1)
	if inset then self:SetInside(bd, frame, inset, inset) else self:SetOutside(bd, frame) end
	self:SetTemplate(bd, template, accent)
	frame.suiBackdrop = bd
	frame.backdrop = frame.backdrop or bd
	return bd
end

function S:Kill(obj)
	if not obj then return end
	if obj.IsProtected and obj:IsProtected() and InCombatLockdown() then
		return S:RunOutOfCombat(S.Kill, S, obj)
	end
	if obj.UnregisterAllEvents then
		obj:UnregisterAllEvents()
		obj:SetParent(self.hiddenFrame)
	else
		obj.Show = obj.Hide
	end
	obj:Hide()
end

local stripNames = { "NineSlice", "Bg", "BG", "Background", "TitleBg", "TopTileStreaks", "Inset", "InsetBg", "Border", "BorderFrame", "Left", "Middle", "Right", "Mid", "LeftDisabled", "MiddleDisabled", "RightDisabled", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "portrait", "PortraitContainer", "PortraitFrame", "TitleContainer" }
local keepNames = { TitleContainer = true, PortraitContainer = false }

function S:StripTextures(frame, kill, keepText)
	if not frame then return end
	for i = 1, select("#", frame:GetRegions()) do
		local region = select(i, frame:GetRegions())
		if region and region.IsObjectType and region:IsObjectType("Texture") then
			if kill then self:Kill(region) else region:SetAlpha(0) end
		end
	end
	local name = frame.GetName and frame:GetName()
	for _, key in ipairs(stripNames) do
		local obj = frame[key] or (name and _G[name .. key])
		if obj and type(obj) == "table" and obj ~= frame and obj.GetObjectType then
			if obj:IsObjectType("Texture") then
				obj:SetAlpha(0)
			elseif keepNames[key] then
				self:StripTextures(obj)
			elseif obj.SetAlpha and not obj:IsObjectType("FontString") then
				if key == "NineSlice" or key == "Bg" or key == "Background" or key == "Inset" or key == "PortraitContainer" or key == "BorderFrame" or key == "Border" or key == "TopTileStreaks" or key == "InsetBg" then
					obj:SetAlpha(0)
				end
			end
		end
	end
end

-- Gradient fill (works on old SetGradientAlpha and new CreateColor clients).
-- orientation "VERTICAL": a1 = bottom alpha, a2 = top alpha
function S:Gradient(tex, orientation, r, g, b, a1, a2)
	tex:SetTexture(BLANK)
	if tex.SetGradient and CreateColor then
		if pcall(tex.SetGradient, tex, orientation, CreateColor(r, g, b, a1), CreateColor(r, g, b, a2)) then return end
	end
	if tex.SetGradientAlpha then
		tex:SetGradientAlpha(orientation, r, g, b, a1, r, g, b, a2)
	else
		tex:SetVertexColor(r, g, b, (a1 + a2) / 2)
	end
end

-- Fonts
function S:SetFont(fs, font, size, outline)
	if not fs or not fs.SetFont then return end
	font = font or self.media.font or STANDARD_TEXT_FONT
	size = self:Scale(size or self.media.fontSize or 12)
	outline = outline or self.media.fontOutline or "NONE"
	-- only pass flags every client accepts
	if outline == "MONOCHROMEOUTLINE" then outline = "MONOCHROME,OUTLINE"
	elseif outline ~= "OUTLINE" and outline ~= "THICKOUTLINE" and outline ~= "MONOCHROME" and outline ~= "MONOCHROME,OUTLINE" then outline = "" end
	-- SetFont with an unreadable/unloadable font leaves the string invisible
	-- (returns false, no error) -> fall back to the client default font
	local ok, applied = pcall(fs.SetFont, fs, font, size, outline)
	if not ok or applied == false then
		pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, outline ~= "" and outline or nil)
	end
	if outline == "" then
		fs:SetShadowColor(0, 0, 0, 0.9)
		fs:SetShadowOffset(self.mult, -self.mult)
	else
		fs:SetShadowColor(0, 0, 0, 0.4)
		fs:SetShadowOffset(0, 0)
	end
end

function S:FontString(parent, size, outline, font, layer, justify)
	-- a backdrop is a child frame and children always draw above the parent's
	-- own regions -> a FontString put directly on a backdropped frame would be
	-- covered by the dark fill, so create it on the backdrop instead. Status
	-- bars additionally redirect onto suiTextOverlay so text stays above the
	-- fill texture (the backdrop sits below the bar's own regions).
	local host = (type(parent) == "table" and (parent.suiTextOverlay or parent.suiBackdrop)) or parent
	local fs = host:CreateFontString(nil, layer or "OVERLAY")
	self:EnablePixelSnap(fs)
	self:SetFont(fs, font, size, outline)
	fs:SetJustifyH(type(justify) == "string" and justify or "CENTER")
	fs:SetWordWrap(false)
	return fs
end

-- Status bars
function S:CreateStatusBar(parent, name, template)
	local bar = CreateFrame("StatusBar", name, parent)
	self:EnablePixelSnap(bar)
	bar:SetStatusBarTexture(self.media.statusbar)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	if template ~= false then self:CreateBackdrop(bar, template or "Default") end
	local bg = bar:CreateTexture(nil, "BORDER")
	bg:SetAllPoints()
	bg:SetTexture(self.media.statusbar)
	bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)
	bar.bg = bg
	-- overlay for text/icons: FontStrings parked on suiBackdrop would render
	-- under the statusbar fill; this frame sits above everything on the bar
	local overlay = CreateFrame("Frame", nil, bar)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(bar:GetFrameLevel() + 3)
	bar.suiTextOverlay = overlay
	self.statusbars = self.statusbars or setmetatable({}, { __mode = "k" })
	self.statusbars[bar] = true
	return bar
end

function S:UpdateStatusBars()
	if not self.statusbars then return end
	for bar in pairs(self.statusbars) do
		if not bar.suiCustomTexture then
			bar:SetStatusBarTexture(self.media.statusbar)
			if bar.bg then bar.bg:SetTexture(self.media.statusbar) end
		end
	end
end

-- Number / time formatting
function S:Abbrev(value)
	if value == nil then return "" end
	if self.IsSecret(value) then
		if AbbreviateNumbers then return AbbreviateNumbers(value) end
		return value
	end
	local fmt = self.db and self.db.profile.general.numberFormat or "SHORT"
	local abs = math.abs(value)
	if fmt == "FULL" then return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value) end
	local dec = self.db and self.db.profile.general.decimals or 1
	local german = fmt == "GERMAN"
	if abs >= 1e9 then return format("%." .. dec .. "f" .. (german and " Mrd" or "B"), value / 1e9)
	elseif abs >= 1e6 then return format("%." .. dec .. "f" .. (german and " Mio" or "M"), value / 1e6)
	elseif abs >= 1e3 then return format("%." .. dec .. "f" .. (german and " Tsd" or "K"), value / 1e3)
	end
	return tostring(floor(value + 0.5))
end

function S:FormatTime(sec, precise)
	if sec >= 86400 then return format("%dd", floor(sec / 86400 + 0.5)), 60
	elseif sec >= 3600 then return format("%dh", floor(sec / 3600 + 0.5)), 30
	elseif sec >= 90 then return format("%dm", floor(sec / 60 + 0.5)), 1
	elseif sec >= (precise or 0) then return format("%d", floor(sec + 0.5)), 0.2
	end
	return format("%.1f", sec), 0.05
end

function S:FormatMoney(copper, style, coins)
	copper = copper or 0
	local gold, silver, cop = floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
	local g, s, c = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
	if coins then
		g = [[|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t]]
		s = [[|TInterface\MoneyFrame\UI-SilverIcon:0:0:2:0|t]]
		c = [[|TInterface\MoneyFrame\UI-CopperIcon:0:0:2:0|t]]
	end
	if style == "FULL" then
		return format("%s%s %d%s %d%s", BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold, g, silver, s, cop, c)
	elseif style == "SHORT" then
		return format("%s%s", BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold, g)
	end
	if gold > 0 then return format("%s%s %d%s", BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold, g, silver, s) end
	if silver > 0 then return format("%d%s %d%s", silver, s, cop, c) end
	return format("%d%s", cop, c)
end

-- Cooldown text
local cooldowns = setmetatable({}, { __mode = "k" })

local function CooldownOnUpdate(holder, elapsed)
	holder.wait = (holder.wait or 0) - elapsed
	if holder.wait > 0 then return end
	local cd = holder.cd
	local remain = (cd.suiStart + cd.suiDuration) - GetTime()
	if remain <= 0.05 then
		holder:Hide()
		return
	end
	local text, nextUpdate = S:FormatTime(remain)
	local threshold = S.db.profile.general.cooldownThreshold or 3
	holder.text:SetText(text)
	if remain <= threshold then holder.text:SetTextColor(1, 0.25, 0.2)
	elseif remain < 60 then holder.text:SetTextColor(1, 0.95, 0.6)
	elseif remain < 3600 then holder.text:SetTextColor(0.8, 0.9, 1)
	else holder.text:SetTextColor(0.7, 0.7, 0.7) end
	holder.wait = remain <= threshold and 0.05 or nextUpdate
end

local function CooldownSet(cd, start, duration)
	local holder = cd.suiHolder
	if S.IsSecret(start) or S.IsSecret(duration) then
		holder:Hide()
		cd:SetHideCountdownNumbers(false)
		return
	end
	local width = cd:GetWidth() or 0
	if not S.db.profile.general.cooldownText or not start or not duration or duration <= 1.6 or start <= 0 or width < (S.db.profile.general.cooldownMinSize or 18) * 0.7 then
		holder:Hide()
		return
	end
	cd:SetHideCountdownNumbers(true)
	cd.suiStart, cd.suiDuration = start, duration
	S:SetFont(holder.text, S.media.numberFont, max(8, min(22, floor(width * 0.42))), "OUTLINE")
	holder.wait = 0
	holder:Show()
end

function S:RegisterCooldown(cd)
	if not cd or cooldowns[cd] then return end
	cooldowns[cd] = true
	local holder = CreateFrame("Frame", nil, cd)
	holder:SetAllPoints()
	holder:SetFrameLevel(cd:GetFrameLevel() + 3)
	holder:Hide()
	holder.cd = cd
	holder.text = self:FontString(holder, 14, "OUTLINE", self.media.numberFont)
	holder.text:SetPoint("CENTER", 1, 0)
	holder:SetScript("OnUpdate", CooldownOnUpdate)
	cd.suiHolder = holder
	if cd.SetDrawEdge then cd:SetDrawEdge(false) end
	if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.7) end
	hooksecurefunc(cd, "SetCooldown", function(...) S:SafeCall("Cooldown", CooldownSet, ...) end)
	if cd.SetCooldownFromDurationObject then
		hooksecurefunc(cd, "SetCooldownFromDurationObject", function(self)
			if not self then return end
			if self.suiHolder then self.suiHolder:Hide() end
			if self.SetHideCountdownNumbers then self:SetHideCountdownNumbers(false) end
		end)
	end
	if cd.Clear then
		hooksecurefunc(cd, "Clear", function(self) if self and self.suiHolder then self.suiHolder:Hide() end end)
	end
	cd:HookScript("OnHide", function(self) if self and self.suiHolder then self.suiHolder:Hide() end end)
end

-- Widget skins ---------------------------------------------------------------

local function HoverEnter(self)
	local bd = self.suiBackdrop or self
	if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b, 1) end
end

local function HoverLeave(self)
	local bd = self.suiBackdrop or self
	if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(unpack(S.media.borderColor)) end
end
S.HoverEnter, S.HoverLeave = HoverEnter, HoverLeave

function S:AddHover(frame)
	if frame.suiHover then return end
	frame.suiHover = true
	frame:HookScript("OnEnter", HoverEnter)
	frame:HookScript("OnLeave", HoverLeave)
end

local function ClearTex(btn, getter, setter)
	local tex = btn[getter] and btn[getter](btn)
	if tex then tex:SetAlpha(0) end
end

function S:SkinButton(btn, noTemplate)
	if not btn or btn.suiSkinned then return end
	btn.suiSkinned = true
	for _, key in ipairs({ "Left", "Middle", "Center", "Right", "LeftSeparator", "RightSeparator", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopMiddle", "MiddleLeft", "MiddleRight", "BottomMiddle", "MiddleMiddle" }) do
		local t = btn[key] or (btn:GetName() and _G[btn:GetName() .. key])
		-- textures only: on some clients a key can resolve to the button's FontString
		if t and t.SetAlpha and (not t.IsObjectType or t:IsObjectType("Texture")) then t:SetAlpha(0) end
	end
	ClearTex(btn, "GetNormalTexture")
	ClearTex(btn, "GetPushedTexture")
	ClearTex(btn, "GetDisabledTexture")
	local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
	if hl then
		hl:SetTexture(BLANK)
		hl:SetVertexColor(1, 1, 1, 0.08)
		self:SetInside(hl, btn)
	end
	if not noTemplate then
		self:CreateBackdrop(btn, "Default", nil, 0)
		self:AddHover(btn)
	end
	-- the caption stays the button's own FontString: the backdrop is created
	-- one frame level BELOW the button, so the button's regions (text) render
	-- above the dark fill. A mirrored copy of the caption is deliberately NOT
	-- used - the engine re-shows the original on state changes, which made
	-- both render on top of each other (glaring doubled text).
	local fs = btn.GetFontString and btn:GetFontString()
	if fs then
		self:SetFont(fs, nil, 12)
		fs:SetAlpha(1)
		fs:Show()
	end
	local bd = btn.suiBackdrop
	if bd then
		-- keep the fill below the caption even if something re-levels the button
		local function KeepBelow()
			local lvl = btn:GetFrameLevel()
			if lvl == 0 then btn:SetFrameLevel(1) lvl = 1 end
			if bd:GetFrameLevel() >= lvl then bd:SetFrameLevel(lvl - 1) end
		end
		KeepBelow()
		btn:HookScript("OnShow", KeepBelow)
	end
end

function S:SkinCloseButton(btn, point)
	if not btn or btn.suiSkinned then return end
	btn.suiSkinned = true
	self:StripTextures(btn)
	ClearTex(btn, "GetNormalTexture")
	ClearTex(btn, "GetPushedTexture")
	ClearTex(btn, "GetDisabledTexture")
	ClearTex(btn, "GetHighlightTexture")
	btn:SetSize(18, 18)
	local bd = self:CreateBackdrop(btn, "Default", nil, 0)
	-- regions on btn sit below the backdrop child frame -> draw the "x" on bd
	local x = (bd or btn):CreateFontString(nil, "OVERLAY")
	self:SetFont(x, self.media.font, 14, "OUTLINE")
	x:SetPoint("CENTER", 1, 0)
	x:SetText("x")
	btn.suiX = x
	btn:HookScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) HoverEnter(btn) end)
	btn:HookScript("OnLeave", function() x:SetTextColor(1, 1, 1) HoverLeave(btn) end)
	if point then
		btn:ClearAllPoints()
		btn:SetPoint("TOPRIGHT", point, "TOPRIGHT", -4, -4)
	end
	return bd
end

local function SkinArrow(btn, dir)
	if not btn or btn.suiSkinned then return end
	btn.suiSkinned = true
	S:StripTextures(btn)
	ClearTex(btn, "GetNormalTexture")
	ClearTex(btn, "GetPushedTexture")
	ClearTex(btn, "GetDisabledTexture")
	ClearTex(btn, "GetHighlightTexture")
	local bd = S:CreateBackdrop(btn, "Default", nil, 0)
	local t = (bd or btn):CreateFontString(nil, "OVERLAY")
	S:SetFont(t, S.media.font, 10, "OUTLINE")
	t:SetPoint("CENTER")
	t:SetText(dir == "up" and "^" or dir == "down" and "v" or dir == "left" and "<" or ">")
	S:AddHover(btn)
end
S.SkinArrowButton = function(_, btn, dir) SkinArrow(btn, dir) end

function S:SkinScrollBar(sb)
	if not sb or sb.suiSkinned then return end
	sb.suiSkinned = true
	self:StripTextures(sb)
	local name = sb:GetName()
	local up = sb.ScrollUpButton or sb.Back or (name and (_G[name .. "ScrollUpButton"] or _G[name .. "UpButton"]))
	local down = sb.ScrollDownButton or sb.Forward or (name and (_G[name .. "ScrollDownButton"] or _G[name .. "DownButton"]))
	SkinArrow(up, "up")
	SkinArrow(down, "down")
	local track = sb.Track
	if track then self:StripTextures(track) end
	local thumb = (track and track.Thumb) or (sb.GetThumbTexture and sb:GetThumbTexture()) or sb.ThumbTexture
	if thumb then
		if thumb.IsObjectType and thumb:IsObjectType("Texture") then
			thumb:SetAlpha(1) -- StripTextures hid the template thumb region
			thumb:SetTexture(BLANK)
			thumb:SetVertexColor(0.35, 0.38, 0.42)
			thumb:SetWidth(max(6, (sb:GetWidth() or 16) - 6))
		else
			self:StripTextures(thumb)
			for _, k in ipairs({ "Begin", "Middle", "End" }) do if thumb[k] then thumb[k]:SetAlpha(0) end end
			self:CreateBackdrop(thumb, "Default", nil, 1)
			thumb.suiBackdrop:SetBackdropColor(0.3, 0.33, 0.37)
		end
	end
	local bg = CreateFrame("Frame", nil, sb, self.BackdropTemplate)
	bg:SetFrameLevel(max(0, sb:GetFrameLevel() - 1))
	bg:SetPoint("TOPLEFT", up or sb, up and "BOTTOMLEFT" or "TOPLEFT", 0, -1)
	bg:SetPoint("BOTTOMRIGHT", down or sb, down and "TOPRIGHT" or "BOTTOMRIGHT", 0, 1)
	self:SetTemplate(bg, "Transparent")
end

function S:SkinTab(tab, noBackdrop)
	if not tab or tab.suiSkinned then return end
	tab.suiSkinned = true
	self:StripTextures(tab)
	for _, k in ipairs({ "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight", "RightHighlight", "Left", "Middle", "Right" }) do
		if tab[k] then tab[k]:SetAlpha(0) end
	end
	local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
	if hl then hl:SetAlpha(0) end
	if not noBackdrop then
		local bd = self:CreateBackdrop(tab, "Transparent", "BOTTOM")
		bd:ClearAllPoints()
		bd:SetPoint("TOPLEFT", 8, -3)
		bd:SetPoint("BOTTOMRIGHT", -8, 3)
		self:AddHover(tab)
	end
	local fs = tab.Text or (tab.GetFontString and tab:GetFontString())
	if fs then self:SetFont(fs, nil, 12) end
end

function S:SkinEditBox(eb, height)
	if not eb or eb.suiSkinned then return end
	eb.suiSkinned = true
	local name = eb:GetName()
	for _, k in ipairs({ "Left", "Middle", "Right", "Mid", "LeftTexture", "RightTexture", "MiddleTexture" }) do
		local t = eb[k] or (name and _G[name .. k])
		if t and t.SetAlpha then t:SetAlpha(0) end
	end
	local bd = self:CreateBackdrop(eb, "Default")
	bd:ClearAllPoints()
	bd:SetPoint("TOPLEFT", -3, 0)
	bd:SetPoint("BOTTOMRIGHT", 0, 0)
	if height then eb:SetHeight(height) end
	eb:HookScript("OnEditFocusGained", function() bd:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b) end)
	eb:HookScript("OnEditFocusLost", function() bd:SetBackdropBorderColor(unpack(S.media.borderColor)) end)
end

function S:SkinCheckBox(cb)
	if not cb or cb.suiSkinned then return end
	cb.suiSkinned = true
	ClearTex(cb, "GetNormalTexture")
	ClearTex(cb, "GetPushedTexture")
	ClearTex(cb, "GetHighlightTexture")
	local bd = self:CreateBackdrop(cb, "Default", nil, 5)
	if cb.SetCheckedTexture then
		cb:SetCheckedTexture(BLANK)
		local tex = cb:GetCheckedTexture()
		tex:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
		self:SetInside(tex, bd, 3, 3)
		self:RegisterAccent(tex, "texture")
	end
	if cb.SetDisabledCheckedTexture then
		cb:SetDisabledCheckedTexture(BLANK)
		local d = cb:GetDisabledCheckedTexture()
		if d then d:SetVertexColor(0.4, 0.4, 0.4) self:SetInside(d, bd, 3, 3) end
	end
	self:AddHover(cb)
end

function S:SkinDropDown(dd, width)
	if not dd or dd.suiSkinned then return end
	dd.suiSkinned = true
	local name = dd:GetName()
	for _, k in ipairs({ "Left", "Middle", "Right" }) do
		local t = dd[k] or (name and _G[name .. k])
		if t and t.SetAlpha then t:SetAlpha(0) end
	end
	if dd.Background then dd.Background:SetAlpha(0) end
	if dd.NineSlice then dd.NineSlice:SetAlpha(0) end
	local bd = self:CreateBackdrop(dd, "Default")
	if name and _G[name .. "Left"] then
		bd:ClearAllPoints()
		bd:SetPoint("TOPLEFT", 18, -3)
		bd:SetPoint("BOTTOMRIGHT", -18, 6)
	end
	local btn = dd.Button or (name and _G[name .. "Button"])
	if btn then SkinArrow(btn, "down") btn:SetSize(16, 16) end
	if dd.Arrow then dd.Arrow:SetAlpha(0.8) end
	if width and UIDropDownMenu_SetWidth and name then UIDropDownMenu_SetWidth(dd, width) end
	self:AddHover(dd)
end

function S:SkinIcon(icon, createBackdrop, parent)
	if not icon then return end
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if createBackdrop then
		local holder = parent or icon:GetParent()
		local bd = CreateFrame("Frame", nil, holder, self.BackdropTemplate)
		bd:SetFrameLevel(max(0, holder:GetFrameLevel() - 1))
		self:SetOutside(bd, icon)
		self:SetTemplate(bd, "Default")
		icon.suiBackdrop = bd
		return bd
	end
end

function S:SkinStatusBar(bar)
	if not bar or bar.suiSkinned then return end
	bar.suiSkinned = true
	self:StripTextures(bar)
	bar:SetStatusBarTexture(self.media.statusbar)
	-- StripTextures zeroed the fill region's alpha on pre-existing bars
	-- (e.g. Blizzard's roll timer) - put it back
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if fill then fill:SetAlpha(1) end
	self:CreateBackdrop(bar, "Default")
	self.statusbars = self.statusbars or setmetatable({}, { __mode = "k" })
	self.statusbars[bar] = true
end

function S:SkinSlider(slider)
	if not slider or slider.suiSkinned then return end
	slider.suiSkinned = true
	self:StripTextures(slider)
	local bd = self:CreateBackdrop(slider, "Default")
	bd:ClearAllPoints()
	bd:SetPoint("TOPLEFT", 0, -4)
	bd:SetPoint("BOTTOMRIGHT", 0, 4)
	local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
	if thumb then
		thumb:SetAlpha(1) -- StripTextures hid the template thumb region
		thumb:SetTexture(BLANK)
		thumb:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
		thumb:SetSize(8, 14)
		self:RegisterAccent(thumb, "texture")
	end
end

-- Full window skin used by Skins module and by our own panels
function S:SkinFrame(frame, template, noClose)
	if not frame or frame.suiFrameSkinned then return end
	frame.suiFrameSkinned = true
	self:StripTextures(frame)
	-- backdrop stays below the frame level so stripped-but-kept regions (portrait)
	-- still render above the dark background
	local bd = self:CreateBackdrop(frame, template or "Transparent", "TOP")
	local name = frame:GetName()
	local close = frame.CloseButton or (name and (_G[name .. "CloseButton"])) or (frame.TitleContainer and frame.TitleContainer.CloseButton)
	if close and not noClose then self:SkinCloseButton(close) end
	local portrait = frame.portrait or frame.Portrait or (name and _G[name .. "Portrait"]) or (frame.PortraitContainer and frame.PortraitContainer.portrait)
	if portrait and portrait.SetAlpha and not frame.suiKeepPortrait then portrait:SetAlpha(0) end
	for _, k in ipairs({ "Inset", "LeftInset", "RightInset", "InsetFrame" }) do
		local inset = frame[k] or (name and _G[name .. k])
		if inset and inset.GetObjectType and not inset:IsObjectType("Texture") then self:StripTextures(inset) end
	end
	return bd
end

-- Generic deep-skin for children (buttons, editboxes, checkboxes, scrollbars, tabs)
function S:SkinChildren(frame, depth)
	depth = depth or 0
	if not frame or depth > 4 or not frame.GetChildren then return end
	for i = 1, select("#", frame:GetChildren()) do
		local child = select(i, frame:GetChildren())
		if child and not child.suiSkinned and not child:IsForbidden() then
			local otype = child:GetObjectType()
			local name = child:GetName() or ""
			if otype == "Button" and (name:find("PrevPage") or name:find("NextPage") or name:find("DecrementButton$") or name:find("IncrementButton$")) then
				SkinArrow(child, (name:find("Prev") or name:find("Decrement")) and "left" or "right")
			elseif otype == "Button" and ((child.Left or _G[name .. "Left"]) and (child.Middle or child.Center or _G[name .. "Middle"] or _G[name .. "Center"]) and (child.Right or _G[name .. "Right"]) or name:find("Button$") and child:GetText() and child:GetText() ~= "" and (child.GetNormalTexture and child:GetNormalTexture())) then
				local fs = child.GetFontString and child:GetFontString()
				if fs and (fs:GetText() or "") ~= "" then self:SkinButton(child) end
			elseif otype == "CheckButton" and (name:find("Check") or child.Text) and not name:find("Tab") then
				local w = child:GetWidth() or 0
				if w > 0 and w <= 32 then self:SkinCheckBox(child) end
			elseif otype == "EditBox" and (child.Left or (name ~= "" and _G[name .. "Left"])) then
				self:SkinEditBox(child)
			elseif otype == "Slider" and (name:find("ScrollBar") or child.ScrollUpButton) then
				self:SkinScrollBar(child)
			elseif otype == "Slider" and child.GetThumbTexture and child:GetThumbTexture() then
				self:SkinSlider(child)
			elseif otype == "EventFrame" and child.Track then
				self:SkinScrollBar(child)
			elseif otype == "Frame" and name ~= "" and (child.Left or _G[name .. "Left"]) and (child.Middle or _G[name .. "Middle"]) and (child.Right or _G[name .. "Right"]) and (child.Button or _G[name .. "Button"]) then
				self:SkinDropDown(child)
			elseif otype == "StatusBar" then
				self:SkinStatusBar(child)
			end
			self:SkinChildren(child, depth + 1)
		end
	end
end
