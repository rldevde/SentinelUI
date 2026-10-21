-- DiminishingReturns: DR tracker under the target frame. Watches crowd-
-- control aura applications on the target and shows the spell icon with a
-- colored border: green = full, yellow = 50%, orange = 25%, red = immune.
-- The 15 s TBC window is used.
local _, ns = ...
local S = ns.S
local L = S.L
local DR = S:NewModule("DiminishingReturns", "diminishing")

local CreateFrame = CreateFrame
local WINDOW = 15
local MAX_ICONS = 8

-- TBC-era CC spells -> DR category (shared tables cover most ranks)
local CATEGORY = {
	-- Fear (Death Coil horror shares fear DR on TBC)
	[5782]="Fear",[6213]="Fear",[6215]="Fear",[5484]="Fear",[17928]="Fear",
	[8122]="Fear",[8124]="Fear",[10888]="Fear",[10890]="Fear",[6358]="Fear",
	[6789]="Fear",[17925]="Fear",[17926]="Fear",
	-- Controlled stun
	[1833]="Stun",[408]="Stun",[8643]="Stun",[5211]="Stun",[6798]="Stun",[8983]="Stun",
	[20252]="Stun",[25275]="Stun",[12809]="Stun",[30283]="Stun",[34510]="Stun",[9005]="Stun",[9823]="Stun",[9827]="Stun",
	-- Disorient / incapacitate (poly, sap, gouge, scatter, repentance, freezing trap)
	[118]="Disorient",[12824]="Disorient",[12825]="Disorient",[12826]="Disorient",[28271]="Disorient",[28272]="Disorient",
	[6770]="Disorient",[2070]="Disorient",[11297]="Disorient",[1776]="Disorient",[1777]="Disorient",[8629]="Disorient",
	[11285]="Disorient",[11286]="Disorient",[19503]="Disorient",[20066]="Disorient",
	[3355]="Disorient",[14308]="Disorient",[14309]="Disorient",
	-- Root
	[339]="Root",[1062]="Root",[5195]="Root",[5196]="Root",[9852]="Root",[9853]="Root",[26989]="Root",
	[122]="Root",[865]="Root",[6131]="Root",[10230]="Root",[27088]="Root",
	[12494]="Root",[23694]="Root",[12360]="Root",[55536]="Root",
	-- Banish
	[710]="Banish",[18647]="Banish",
	-- Cyclone (self-DR, immune after 3)
	[33786]="Cyclone",
	-- Disarm
	[676]="Disarm",
	-- Hibernate/sleep
	[2637]="Sleep",[18657]="Sleep",[18658]="Sleep",
}
local LABELS = { Fear="Fear", Stun="Stun", Disorient="Disorient", Root="Root", Banish="Banish", Cyclone="Cyclone", Disarm="Disarm", Sleep="Sleep" }
local COLORS = { {0.3,0.9,0.3}, {0.95,0.85,0.2}, {1,0.55,0.1}, {1,0.2,0.2} }
local PCT = { "100%", "50%", "25%", L["IMMUNE"] or "IMM" }

function DR:Active(guid)
	local t = {}
	for key, e in pairs(self.dr or {}) do
		if e.guid == guid and GetTime() - e.t < WINDOW + e.dur then t[key] = e end
	end
	return t
end

function DR:Ensure()
	local UF = S:GetModule("UnitFrames")
	local f = UF and UF.units and UF.units.target
	if not f then return end
	if self.row and self.row:GetParent() == f then return self.row end
	local row = CreateFrame("Frame", "SentinelUIDRTracker", f)
	row:SetSize(MAX_ICONS * 22, 20)
	row:SetPoint("TOP", f, "BOTTOM", 0, -18)
	row.icons = {}
	for i = 1, MAX_ICONS do
		local b = CreateFrame("Frame", nil, row)
		b:SetSize(18, 18)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.brd = b:CreateTexture(nil, "OVERLAY")
		b.brd:SetPoint("TOPLEFT", -1, 1)
		b.brd:SetPoint("BOTTOMRIGHT", 1, -1)
		b.brd:SetTexture("Interface\\Buttons\\WHITE8x8")
		b.brd:SetVertexColor(0, 0, 0, 0) -- tinted on use
		b.pct = S:FontString(b, 9, "OUTLINE", S.media.numberFont)
		b.pct:SetPoint("TOP", b, "BOTTOM", 0, -1)
		b:Hide()
		row.icons[i] = b
	end
	self.row = row
	return row
end

function DR:Draw()
	local row = self:Ensure()
	if not row then return end
	local guid = UnitExists("target") and UnitGUID("target")
	local i = 0
	if guid then
		for key, e in pairs(self:Active(guid)) do
			i = i + 1
			local b = row.icons[i]
			if not b then break end
			b.tex:SetTexture(e.icon or 134400)
			local c = COLORS[math.min(e.level, 4)]
			b.brd:SetVertexColor(c[1], c[2], c[3], 0.9)
			b.pct:SetText(PCT[math.min(e.level, 4)])
			b.pct:SetTextColor(c[1], c[2], c[3])
			b:Show()
		end
	end
	for j = i + 1, MAX_ICONS do row.icons[j]:Hide() end
end

function DR:Initialize()
	self.db = S.db.profile.diminishing
	self.dr = {}
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		local _, sub, _, _, _, _, _, dguid, _, _, _, spellId, _, _, dtype = CombatLogGetCurrentEventInfo()
		if (sub ~= "SPELL_AURA_APPLIED" and sub ~= "SPELL_AURA_REFRESH") or not dguid then return end
		local cat = spellId and CATEGORY[spellId]
		if not cat then return end
		local tguid = UnitExists("target") and UnitGUID("target")
		if tguid ~= dguid then return end -- only track the watched target
		local key = cat
		local e = DR.dr[key]
		local now = GetTime()
		if e and e.guid == dguid and now - e.t < WINDOW + (e.dur or 0) then
			e.level = math.min((e.level or 0) + 1, 4)
		else
			e = { guid = dguid, level = 1 }
			DR.dr[key] = e
		end
		e.t = now
		e.dur = 0
		e.icon = S.GetSpellInfo and select(3, S.GetSpellInfo(spellId))
		DR:Draw()
	end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() DR:Draw() end)
	-- periodic cleanup of expired icons
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() DR:Draw() end)
end

function DR:Update()
	self.db = S.db.profile.diminishing
	self:Draw()
end
