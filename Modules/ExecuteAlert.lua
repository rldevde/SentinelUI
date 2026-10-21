-- ExecuteAlert: pulsing red glow + one-shot sound when the target drops into
-- the player's execute range. Warrior/Paladin 20% everywhere; hunter Kill
-- Shot, warlock Drain Soul and priest SW:Death bonus only exist on Wrath+.
local _, ns = ...
local S = ns.S
local L = S.L
local EA = S:NewModule("ExecuteAlert", "executealert")

local CreateFrame = CreateFrame

local function Threshold()
	local cls = S.myClass
	if cls == "WARRIOR" or cls == "PALADIN" then return 0.20 end
	if not S.isRetail and not S.isWrath and not S.isCata and not S.isMists then return nil end
	if cls == "HUNTER" then return 0.20 end   -- Kill Shot (Wrath+)
	if cls == "WARLOCK" then return 0.25 end  -- Drain Soul x4 (Wrath+)
	if cls == "PRIEST" then return 0.25 end   -- SW:Death bonus (Wrath+)
end

function EA:BuildGlow(target)
	-- glowing border around the target unit frame
	local g = CreateFrame("Frame", "SentinelUIExecuteAlert", target)
	g:SetAllPoints()
	g:SetFrameStrata("HIGH")
	g.tex = g:CreateTexture(nil, "OVERLAY")
	g.tex:SetAllPoints()
	g.tex:SetTexture(S.media.glow or "Interface\\Buttons\\UI-ActionButton-Border")
	g.tex:SetBlendMode("ADD")
	g.tex:SetVertexColor(1, 0.1, 0.1, 0.9)
	g:Hide()
	g:SetScript("OnUpdate", function(self, el)
		self.t = (self.t or 0) + el
		local a = 0.45 + 0.45 * math.abs(math.sin(self.t * 6))
		self.tex:SetAlpha(a)
	end)
	return g
end

function EA:Check()
	local t = self.thresh
	if not t or not UnitExists("target") or UnitIsDeadOrGhost("target") then return self:SetActive(false) end
	local hp, max = UnitHealth("target"), UnitHealthMax("target")
	if S.IsSecret(hp) or not max or max <= 0 then return self:SetActive(false) end
	self:SetActive(hp / max <= t)
end

function EA:SetActive(on)
	if on == self.active then return end
	self.active = on
	local UF = S:GetModule("UnitFrames")
	local frame = UF and UF.units and UF.units.target
	if on and frame then
		if not self.glow then self.glow = self:BuildGlow(frame) end
		if self.glow:GetParent() ~= frame then self.glow:SetParent(frame) self.glow:SetAllPoints() end
		self.glow:Show()
		if self.db.sound ~= false then
			if PlaySoundFile then pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.wav") end
		end
		if self.db.chatNote then S:Print(L["EXECUTE RANGE!"]) end
	elseif self.glow then
		self.glow:Hide()
	end
end

function EA:Initialize()
	self.db = S.db.profile.executealert
	self.thresh = Threshold()
	if not self.thresh then return end
	for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT" }) do
		self:RegisterEvent(ev, function(_, _, unit) if unit == "target" then EA:Check() end end)
	end
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() EA:Check() end)
end

function EA:Update()
	self.db = S.db.profile.executealert
	self.thresh = Threshold()
	if not self.thresh then self:SetActive(false) end
end
