-- DeathRecap: ring buffer of the last combat events that hit the player.
-- On death a small window lists them ("what killed me") with a button to
-- report the killing blow to the group.
local _, ns = ...
local S = ns.S
local L = S.L
local DR = S:NewModule("DeathRecap", "deathrecap")

local CreateFrame = CreateFrame
local MAX = 8
local DAMAGE_SUBS = {
	SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, ENVIRONMENTAL_DAMAGE = true,
	SWING_MISSED = false,
}
local ROWS = 6

function DR:Push(src, what, amt)
	local buf = self.buf
	buf[#buf + 1] = { src = src or "?", what = what or "?", amt = amt or 0 }
	if #buf > MAX then table.remove(buf, 1) end
end

function DR:OnCLEU()
	local _, sub, _, sg, sname, _, _, dg, _, _, _, a12, a13, a14, a15, a16, a17 = CombatLogGetCurrentEventInfo()
	if dg ~= UnitGUID("player") then return end
	if sub == "SWING_DAMAGE" then
		self:Push(sname, L["Melee"], a12)
	elseif sub == "RANGE_DAMAGE" or sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "DAMAGE_SHIELD" then
		self:Push(sname, a13 or "?", a15)
	elseif sub == "ENVIRONMENTAL_DAMAGE" then
		self:Push(L["Environment"], a12 or "?", a13)
	end
end

function DR:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIDeathRecap", UIParent)
	tinsert(UISpecialFrames, "SentinelUIDeathRecap")
	f:SetSize(300, 44 + ROWS * 16)
	f:SetPoint("TOP", UIParent, "TOP", 0, -180)
	f:SetFrameStrata("DIALOG")
	S:CreateBackdrop(f, "Default")
	f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont)
	f.title:SetPoint("TOP", 0, -6)
	f.title:SetText(L["Death Recap"])
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -3, -3)
	if S.SkinCloseButton then S:SkinCloseButton(close) end
	f.rows = {}
	for i = 1, ROWS do
		local t = S:FontString(f, 10, nil, S.media.unitFont)
		t:SetPoint("TOPLEFT", 12, -24 - (i - 1) * 16)
		t:SetJustifyH("LEFT")
		f.rows[i] = t
	end
	f.report = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.report:SetSize(90, 20)
	f.report:SetPoint("BOTTOM", 0, 8)
	f.report:SetText(L["Report"])
	S:SkinButton(f.report)
	f.report:SetScript("OnClick", function() DR:Report() end)
	f:Hide()
	self.frame = f
end

function DR:Fill()
	local n = #self.buf
	for i, t in ipairs(self.frame.rows) do
		local e = self.buf[n - (i - 1)]
		if e then t:SetFormattedText("%s — %s |cffff6a6a%s|r", e.src, e.what, S:Abbrev(e.amt)) else t:SetText("") end
	end
end

function DR:Report()
	local e = self.buf[#self.buf] or self.last
	if not e then return end
	local ch = IsInRaid() and "RAID" or IsInGroup() and "PARTY"
	if not ch then return end
	SendChatMessage(format(L["Killed by %s (%s, %s)"], e.src, e.what, S:Abbrev(e.amt)), ch)
end

function DR:Initialize()
	self.db = S.db.profile.deathrecap
	self.buf = {}
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function() DR:OnCLEU() end)
	self:RegisterEvent("PLAYER_DEAD", function()
		if DR.db.enable == false or #DR.buf == 0 then return end
		DR:BuildFrame()
		DR:Fill()
		DR.frame:Show()
		DR.last = DR.buf[#DR.buf] -- keep the killing blow for the Report button
		wipe(DR.buf) -- next death starts clean
		C_Timer.After(20, function() if DR.frame then DR.frame:Hide() end end)
	end)
end

function DR:Update()
	self.db = S.db.profile.deathrecap
	if self.db.enable == false and self.frame then self.frame:Hide() end
end
