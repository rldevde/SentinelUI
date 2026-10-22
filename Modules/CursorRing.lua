-- CursorRing: subtle glowing ring that follows the mouse cursor so it stays
-- visible during raid clutter. Purely cosmetic, no combat interaction.
local _, ns = ...
local S = ns.S
local L = S.L
local CR = S:NewModule("CursorRing", "cursorring")

local ring

local function Build()
	if ring then return end
	ring = CreateFrame("Frame", "SentinelUICursorRing", UIParent)
	ring:SetSize(64, 64)
	ring:SetFrameStrata("TOOLTIP")
	ring.tex = ring:CreateTexture(nil, "OVERLAY")
	ring.tex:SetAllPoints()
	ring.tex:SetTexture([[Interface\Minimap\Minimap-TrackingBorder]])
	ring.tex:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.5)
	ring.tex:SetBlendMode("ADD")
	ring:SetScript("OnUpdate", function(f)
		local x, y = GetCursorPosition()
		local scale = f:GetEffectiveScale()
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	end)
end

function CR:Update()
	self.db = S.db.profile.general
	if not ring then return end
	local size = (self.db.cursorRingSize or 64)
	ring:SetSize(size, size)
	ring.tex:SetAlpha(self.db.cursorRingAlpha or 0.5)
	ring.tex:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 1)
	ring:SetShown(self.db.cursorRing == true)
end

function CR:Initialize()
	self.db = S.db.profile.general
	Build()
	self:Update()
end
