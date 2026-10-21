-- PetHappiness (hunter): colored icon + damage-modifier tooltip pinned to the
-- pet unit frame. Red/yellow/green matching unhappy/content/happy.
local _, ns = ...
local S = ns.S
local L = S.L
local PH = S:NewModule("PetHappiness", "pethappiness")

local CreateFrame = CreateFrame
local COLORS = { [1] = { 1, 0.25, 0.25 }, [2] = { 1, 0.85, 0.2 }, [3] = { 0.35, 0.95, 0.35 } }
local NAMES = { [1] = "Unhappy", [2] = "Content", [3] = "Happy" }
local DMG = { [1] = "75%", [2] = "100%", [3] = "125%" }

function PH:Ensure()
	local UF = S:GetModule("UnitFrames")
	local f = UF and UF.units and UF.units.pet
	if not f then return end
	if self.icon and self.icon:GetParent() == f then return self.icon end
	local b = CreateFrame("Frame", "SentinelUIPetHappiness", f)
	b:SetSize(16, 16)
	b:SetPoint("LEFT", f, "RIGHT", 4, 0)
	b.tex = b:CreateTexture(nil, "OVERLAY")
	b.tex:SetAllPoints()
	b.tex:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
	b.tex:SetTexCoord(0.125, 0.375, 0, 0.375) -- happy face slice, tinted below
	b:EnableMouse(true)
	b:SetScript("OnEnter", function()
		local h = GetPetHappiness()
		if not h then return end
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Pet Happiness"], S.accent.r, S.accent.g, S.accent.b)
		GameTooltip:AddDoubleLine(L["Status"], L[NAMES[h]] or NAMES[h], 1, 1, 1, unpack(COLORS[h]))
		GameTooltip:AddDoubleLine(L["Damage"], DMG[h], 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.icon = b
	return b
end

function PH:Refresh()
	local b = self:Ensure()
	if not b then return end
	local h = GetPetHappiness and GetPetHappiness()
	if not h or not UnitExists("pet") or self.db.enable == false then
		b:Hide()
		return
	end
	local c = COLORS[h] or COLORS[2]
	b.tex:SetVertexColor(c[1], c[2], c[3])
	b:Show()
	-- feed reminder: unhappy pet -> flashing icon + one chat note per drop
	if h == 1 and self.db.feedWarn ~= false then
		b:SetScript("OnUpdate", function(_, el)
			b.t = (b.t or 0) + el
			b:SetAlpha(0.4 + 0.6 * math.abs(math.sin(b.t * 6)))
		end)
		if self.lastHappy ~= 1 then
			S:Print(L["Pet is unhappy - feed it!"])
		end
	else
		b:SetScript("OnUpdate", nil)
		b:SetAlpha(1)
	end
	self.lastHappy = h
end

function PH:Initialize()
	self.db = S.db.profile.pethappiness
	if S.myClass ~= "HUNTER" then return end
	self:RegisterEvent("UNIT_PET", function(_, _, unit) if unit == "player" then PH:Refresh() end end)
	self:RegisterEvent("UNIT_HAPPINESS", function() PH:Refresh() end)
	self:RegisterEvent("UNIT_AURA", function(_, _, unit) if unit == "pet" then PH:Refresh() end end)
	self:Refresh()
end

function PH:Update()
	self.db = S.db.profile.pethappiness
	self:Refresh()
end
