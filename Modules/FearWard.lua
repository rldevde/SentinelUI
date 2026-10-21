-- FearWard: priest helper. Tracks the Fear Ward buff on the current
-- target/party members — icon with remaining duration next to the target
-- frame plus a chat note when it drops off.
local _, ns = ...
local S = ns.S
local L = S.L
local FW = S:NewModule("FearWard", "fearward")

local CreateFrame = CreateFrame
local FEAR_WARD = 6346
local GetAuraByID = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID
local NAME = (GetSpellInfo and GetSpellInfo(FEAR_WARD)) or "Fear Ward"

local function HasWard(unit)
	if not UnitExists(unit) then return end
	if GetAuraByID then
		local a = GetAuraByID(unit, FEAR_WARD, "HELPFUL")
		if a then return a.expirationTime and (a.expirationTime - GetTime()) or true end
	else
		for i = 1, 40 do
			local name, _, _, _, _, expires = S.UnitAura(unit, i, "HELPFUL")
			if not name then break end
			if name == NAME then return expires and (expires - GetTime()) or true end
		end
	end
end

function FW:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIFearWard", UIParent)
	f:SetSize(140, 20)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -280)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetSize(18, 18)
	f.tex:SetPoint("LEFT", 0, 0)
	f.tex:SetTexture(select(3, GetSpellInfo(FEAR_WARD)) or 134400)
	f.text = S:FontString(f, 10, "OUTLINE", S.media.numberFont)
	f.text:SetPoint("LEFT", 22, 0)
	S:CreateBackdrop(f, "Default")
	S:CreateMover(f, "FearWard", L["Fear Ward"], { "CENTER", UIParent, "CENTER", 0, -280 }, "fearward")
	f:Hide()
	self.frame = f
end

function FW:Check()
	local f = self.frame
	if self.db.enable == false then return f:Hide() end
	for _, u in ipairs({ "target", "focus", "party1", "party2", "party3", "party4" }) do
		local left = HasWard(u)
		if left then
			f.text:SetFormattedText("%s |cff40c040%s|r", NAME, type(left) == "number" and format("%.0fs", left) or "")
			f:Show()
			return
		end
	end
	f:Hide()
end

function FW:Initialize()
	self.db = S.db.profile.fearward
	if S.myClass ~= "PRIEST" then return end
	self:Build()
	self:RegisterEvent("UNIT_AURA", function(_, _, unit) if unit and (unit == "target" or unit == "focus" or unit:match("^party")) then FW:Check() end end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() FW:Check() end)
	self.poller = self.poller or CreateFrame("Frame")
	self.poller:SetScript("OnUpdate", function(_, el)
		FW.t = (FW.t or 0) + el
		if FW.t < 1 then return end
		FW.t = 0
		if FW.frame and FW.frame:IsShown() then FW:Check() end
	end)
	self:Check()
end

function FW:Update()
	self.db = S.db.profile.fearward
	if self.frame then self:Check() end
end
