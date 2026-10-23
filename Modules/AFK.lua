-- AFK screen "Sentinel Standby": dimmed world with HUD corner brackets, an info
-- column on the left (clock, date, character, zone, gold), the character model on
-- the right and a minute-progress line with the AFK timer at the bottom.
local _, ns = ...
local S = ns.S
local L = S.L
local AFK = S:NewModule("AFK")

local format, floor, sin = format, math.floor, math.sin
local BLANK = [[Interface\Buttons\WHITE8X8]]

local function Gradient(tex, orientation, a1, a2)
	tex:SetTexture(BLANK)
	if tex.SetGradient and CreateColor then
		local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
		if ok then return end
	end
	if tex.SetGradientAlpha then
		tex:SetGradientAlpha(orientation, 0, 0, 0, a1, 0, 0, 0, a2)
	else
		tex:SetVertexColor(0, 0, 0, (a1 + a2) / 2)
	end
end

local function Bracket(parent, point, size, thick)
	local h = parent:CreateTexture(nil, "OVERLAY")
	h:SetTexture(BLANK)
	h:SetSize(size, thick)
	h:SetPoint(point, parent, point, 0, 0)
	local v = parent:CreateTexture(nil, "OVERLAY")
	v:SetTexture(BLANK)
	v:SetSize(thick, size)
	v:SetPoint(point, parent, point, 0, 0)
	S:RegisterAccent(h, "texture")
	S:RegisterAccent(v, "texture")
end

local function Text(parent, size, outline, font, justify)
	return S:FontString(parent, size, outline, font or S.media.font, nil, justify or "LEFT")
end

function AFK:Create()
	local f = CreateFrame("Frame", "SentinelUIAFK", WorldFrame)
	f:SetAllPoints(UIParent)
	f:SetFrameStrata("FULLSCREEN")
	f:SetScale(UIParent:GetScale())
	f:EnableKeyboard(true)
	f:SetPropagateKeyboardInput(true)
	f:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then return end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			AFK:Toggle(false)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
	f:Hide()

	-- dim layers: left-to-right fade behind the info column, bottom fade for the timer
	local left = f:CreateTexture(nil, "BACKGROUND")
	left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT")
	left:SetWidth(UIParent:GetWidth() * 0.55)
	Gradient(left, "HORIZONTAL", 0.82, 0)
	local bottom = f:CreateTexture(nil, "BACKGROUND")
	bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(180)
	Gradient(bottom, "VERTICAL", 0.75, 0)

	-- screen-corner brackets
	local inset = CreateFrame("Frame", nil, f)
	inset:SetPoint("TOPLEFT", 28, -28)
	inset:SetPoint("BOTTOMRIGHT", -28, 28)
	for _, p in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do Bracket(inset, p, 46, 3) end

	-- info column
	local col = CreateFrame("Frame", nil, f)
	col:SetSize(420, 330)
	col:SetPoint("LEFT", f, "LEFT", 90, 20)
	local rail = col:CreateTexture(nil, "ARTWORK")
	rail:SetTexture(BLANK)
	rail:SetPoint("TOPLEFT") rail:SetPoint("BOTTOMLEFT")
	rail:SetWidth(3)
	S:RegisterAccent(rail, "texture")

	local dot = col:CreateTexture(nil, "OVERLAY")
	dot:SetTexture(BLANK)
	dot:SetSize(8, 8)
	dot:SetPoint("TOPLEFT", col, "TOPLEFT", 22, -6)
	S:RegisterAccent(dot, "texture")
	f.dot = dot
	local standby = Text(col, 13, "OUTLINE")
	standby:SetPoint("LEFT", dot, "RIGHT", 8, 0)
	standby:SetText("S T A N D B Y")
	S:RegisterAccent(standby, "text")

	f.clock = Text(col, 72, "OUTLINE", S.media.numberFont)
	f.clock:SetPoint("TOPLEFT", col, "TOPLEFT", 20, -26)
	f.date = Text(col, 15, "NONE")
	f.date:SetPoint("TOPLEFT", f.clock, "BOTTOMLEFT", 2, -2)
	f.date:SetTextColor(0.7, 0.7, 0.75)

	local div = col:CreateTexture(nil, "ARTWORK")
	div:SetTexture(BLANK)
	div:SetHeight(1)
	div:SetPoint("TOPLEFT", f.date, "BOTTOMLEFT", 0, -18)
	div:SetWidth(300)
	div:SetVertexColor(1, 1, 1, 0.15)

	f.name = Text(col, 24, "OUTLINE")
	f.name:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -16)
	f.info = Text(col, 14, "NONE")
	f.info:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -6)
	f.info:SetTextColor(0.8, 0.8, 0.85)
	f.guild = Text(col, 14, "NONE")
	f.guild:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -4)
	f.zone = Text(col, 14, "NONE")
	f.zone:SetPoint("TOPLEFT", f.guild, "BOTTOMLEFT", 0, -14)
	f.zone:SetTextColor(0.75, 0.75, 0.8)
	f.gold = Text(col, 14, "NONE")
	f.gold:SetPoint("TOPLEFT", f.zone, "BOTTOMLEFT", 0, -4)

	-- model on the right
	local model = CreateFrame("PlayerModel", nil, f)
	model:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -60)
	model:SetPoint("BOTTOMLEFT", f, "BOTTOM", 40, 90)
	f.model = model

	-- bottom: minute progress line + timer
	local track = f:CreateTexture(nil, "ARTWORK")
	track:SetTexture(BLANK)
	track:SetSize(360, 2)
	track:SetPoint("BOTTOM", f, "BOTTOM", 0, 64)
	track:SetVertexColor(1, 1, 1, 0.12)
	local fill = f:CreateTexture(nil, "OVERLAY")
	fill:SetTexture(BLANK)
	fill:SetHeight(2)
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetWidth(1)
	S:RegisterAccent(fill, "texture")
	f.fill = fill
	f.timer = Text(f, 18, "OUTLINE", S.media.numberFont, "CENTER")
	f.timer:SetPoint("BOTTOM", track, "TOP", 0, 10)
	local hint = Text(f, 11, "NONE", nil, "CENTER")
	hint:SetPoint("TOP", track, "BOTTOM", 0, -10)
	hint:SetText(L["Press ESC or move to return"])
	hint:SetTextColor(0.55, 0.55, 0.6)

	local brand = Text(f, 11, "OUTLINE", nil, "RIGHT")
	brand:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -16, 14)
	brand:SetText("SENTINEL|cffaaaaaaUI  v" .. S.version .. "|r")

	local elapsed, pulse = 1, 0
	f:SetScript("OnUpdate", function(_, e)
		pulse = pulse + e
		f.dot:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * sin(pulse * 3)))
		elapsed = elapsed + e
		if elapsed < 0.25 then return end
		elapsed = 0
		f.clock:SetText(date("%H:%M"))
		local t = GetTime() - (AFK.start or GetTime())
		f.timer:SetText(format("AFK  %02d:%02d", floor(t / 60), floor(t % 60)))
		f.fill:SetWidth(math.max(1, 360 * ((t % 60) / 60)))
	end)
	self.frame = f
end

function AFK:Fill()
	local f = self.frame
	local c = S.ClassColor(S.myClass)
	f.name:SetText(S:Hex(c) .. S.myName .. "|r")
	local className = UnitClass("player")
	local race = UnitRace("player")
	f.info:SetText(format("%s %d  ·  %s %s", LEVEL, UnitLevel("player"), race or "", className or ""))
	local guild, rank = GetGuildInfo("player")
	f.guild:SetText(guild and ("<" .. guild .. ">  |cffaaaaaa" .. (rank or "") .. "|r") or "")
	local sub = GetSubZoneText and GetSubZoneText() or ""
	local zone = GetZoneText and GetZoneText() or ""
	f.zone:SetText(sub ~= "" and sub ~= zone and (sub .. ", " .. zone) or zone)
	f.gold:SetText(GetCoinTextureString and GetCoinTextureString(GetMoney()) or "")
	local wd = CALENDAR_WEEKDAY_NAMES and CALENDAR_WEEKDAY_NAMES[tonumber(date("%w")) + 1]
	f.date:SetText((wd and (wd .. ", ") or "") .. date("%d.%m.%Y"))
end

function AFK:Toggle(show)
	local f = self.frame
	if show then
		-- re-entrant guard: PLAYER_FLAGS_CHANGED fires for every flag flip,
		-- re-running the show path restarted the model animation and timer
		if self.active then return end
		if InCombatLockdown() or (CinematicFrame and CinematicFrame:IsShown()) or (MovieFrame and MovieFrame:IsShown()) then return end
		if UnitCastingInfo("player") then return end
		self.start = GetTime()
		S:SafeCall("AFK:Fill", self.Fill, self)
		UIParent:Hide()
		f:Show()
		f.model:SetUnit("player")
		f.model:SetFacing(-0.4)
		f.model:SetCamDistanceScale(1.15)
		if f.model.SetAnimation then pcall(f.model.SetAnimation, f.model, 0) end
		MoveViewLeftStart(0.025)
		self.active = true
	elseif self.active then
		self.active = nil
		MoveViewLeftStop()
		f:Hide()
		if not InCombatLockdown() then UIParent:Show() else S:RunOutOfCombat(function() UIParent:Show() end) end
	end
end

function AFK:PLAYER_FLAGS_CHANGED(_, unit)
	if unit ~= "player" then return end
	if not S.db.profile.general.afk then return end
	self:Toggle(UnitIsAFK("player") and true or false)
end

function AFK:Initialize()
	self:Create()
	-- Blizzard's Keyring.lua:23 errors inside KeyRingButton's OnShow every time
	-- UIParent is re-shown (AFK exit, cinematics). Wrap the stock handler so the
	-- error can't surface through our UIParent:Show() call path.
	local krb = _G.KeyRingButton
	if krb and not krb.suiOnShowWrapped then
		local orig = krb:GetScript("OnShow")
		if orig then krb:SetScript("OnShow", function(...) pcall(orig, ...) end) end
		krb.suiOnShowWrapped = true
	end
	self:RegisterEvent("PLAYER_FLAGS_CHANGED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() AFK:Toggle(false) end)
	self:RegisterEvent("LFG_PROPOSAL_SHOW", function() AFK:Toggle(false) end)
	self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", function() AFK:Toggle(false) end)
	self:RegisterEvent("PLAYER_STARTED_MOVING", function() AFK:Toggle(false) end)
end
