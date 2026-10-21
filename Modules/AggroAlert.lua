-- AggroAlert: screen flash + sound + chat warning when the player gains
-- aggro (threat status 3). Useful for dps and healers; tanks can disable
-- it or use it to notice target swaps.
local _, ns = ...
local S = ns.S
local L = S.L
local AA = S:NewModule("AggroAlert", "aggroalert")

local GetTime = GetTime
local UnitThreatSituation = UnitThreatSituation
local last = 0

local function Warn()
	local now = GetTime()
	if now - last < 8 then return end
	last = now
	if AA.db.chat ~= false then S:Print("|cffff4040" .. L["You have aggro!"] .. "|r") end
	if AA.db.sound ~= false and PlaySoundFile then pcall(PlaySoundFile, "Sound\\Interface\\AlarmClockWarning3.wav") end
	if AA.db.flash ~= false then
		if not AA.flash then
			local t = UIParent:CreateTexture(nil, "OVERLAY")
			t:SetAllPoints()
			t:SetTexture("Interface\\Buttons\\WHITE8x8")
			t:SetVertexColor(1, 0.1, 0.1)
			AA.flash = t
		end
		AA.flash:SetAlpha(0.3)
		UIFrameFadeOut(AA.flash, 0.8, 0.3, 0)
	end
end

function AA:Initialize()
	self.db = S.db.profile.aggroalert
	if not UnitThreatSituation then return end
	self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", function(_, unit)
		if unit ~= "player" then return end
		local status = UnitThreatSituation("player")
		if status and status >= 3 then Warn() end
	end)
end

function AA:Update()
	self.db = S.db.profile.aggroalert
end
