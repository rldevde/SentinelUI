-- WeaponSkill: small reminder listing weapon skills below the current cap
-- (level * 5 on Classic/TBC). Detected by max rank, not by skill names - so
-- it works in every locale. Defense counts too when it lags behind.
local _, ns = ...
local S = ns.S
local L = S.L
local WS = S:NewModule("WeaponSkill", "weaponskill")

local CreateFrame = CreateFrame
local UnitLevel, UnitIsDeadOrGhost = UnitLevel, UnitIsDeadOrGhost
local GetNumSkillLines, GetSkillLineInfo = GetNumSkillLines, GetSkillLineInfo

local function UnderMax(skipDefense)
	local out = {}
	if not (GetNumSkillLines and GetSkillLineInfo) then return out end
	local cap = (UnitLevel("player") or 1) * 5
	local secret = S.IsSecret or _G.IsSecret
	for i = 1, (GetNumSkillLines() or 0) do
		local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
		if name and not isHeader and not (secret and (secret(name) or secret(rank) or secret(maxRank)))
			and maxRank == cap and rank < maxRank then
			if not (skipDefense and DEFENSE and name == DEFENSE) then
				out[#out + 1] = { name = name, rank = rank, max = maxRank }
			end
		end
	end
	return out
end

function WS:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIWeaponSkill", UIParent)
	f:SetSize(170, 40)
	f:SetPoint("CENTER", UIParent, "CENTER", 210, -230)
	S:CreateBackdrop(f, "Default")
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(24, 24)
	f.icon:SetPoint("LEFT", f, "LEFT", 6, 0)
	f.icon:SetTexture("Interface\\Icons\\Inv_Sword_27")
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.title = S:FontString(f, 10, "OUTLINE", S.media.unitFont)
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -6)
	f.title:SetText("|cffebad33" .. (L["Weapon Skills"] or "Weapon Skills") .. "|r")
	f.lines = {}
	f:Hide()
	S:CreateMover(f, "weaponSkill", L["Weapon Skills"], { "CENTER", UIParent, "CENTER", 210, -230 }, "general")
	self.frame = f
end

function WS:Refresh()
	local f = self.frame
	if not f then return end
	local list = (self.db.enable ~= false and not UnitIsDeadOrGhost("player")) and UnderMax(self.db.showDefense == false) or {}
	local shown = 0
	for i, s in ipairs(list) do
		shown = i
		local t = f.lines[i]
		if not t then
			t = S:FontString(f, 10, "OUTLINE", S.media.numberFont)
			t:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -20 - (i - 1) * 13)
			f.lines[i] = t
		end
		t:SetFormattedText("%s: |cff80ff80%s|r/|cffff4040%s|r",
			tostring(s.name or "?"), tostring(s.rank or "?"), tostring(s.max or "?"))
		t:Show()
	end
	for i = shown + 1, #f.lines do f.lines[i]:Hide() end
	f:SetSize(170, shown > 0 and (22 + shown * 13) or 40)
	f:SetShown(shown > 0)
end

function WS:Initialize()
	self.db = S.db.profile.weaponskill or {}
	self:BuildFrame()
	for _, ev in ipairs({ "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "CHAT_MSG_SKILL" }) do
		self:RegisterEvent(ev, function() WS:Refresh() end)
	end
	self:Refresh()
end

function WS:Update()
	self.db = S.db.profile.weaponskill or {}
	self:Refresh()
end
