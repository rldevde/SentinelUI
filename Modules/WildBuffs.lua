-- WildBuffs: druid buff manager in Blessings style. Rows for Mark/Gift of
-- the Wild and Thorns: missing count + min remaining time, left-click casts
-- the group spell, right-click singles the first missing member. Tooltip
-- lists who is missing. Druid only.
local _, ns = ...
local S = ns.S
local L = S.L
local WB = S:NewModule("WildBuffs", "wildbuffs")

local CreateFrame = CreateFrame
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local UnitName, UnitClass, UnitExists, UnitIsDeadOrGhost = UnitName, UnitClass, UnitExists, UnitIsDeadOrGhost
local IsInGroup, IsInRaid = IsInGroup, IsInRaid
local GetNumGroupMembers, GetNumSubgroupMembers = GetNumGroupMembers, GetNumSubgroupMembers
local format, floor = format, math.floor

-- spell ids -> localized names via GetSpellInfo at runtime
local MARK_ID, GIFT_ID, THORNS_ID = 9885, 26990, 26992
local function SpellName(id)
	if S.GetSpellInfo then return S.GetSpellInfo(id) end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

local frame

local function GroupUnits()
	local units = {}
	local n = IsInRaid() and GetNumGroupMembers() or (IsInGroup() and GetNumSubgroupMembers() or 0)
	for i = 1, n do
		local u = IsInRaid() and ("raid" .. i) or ("party" .. i)
		if UnitExists(u) and UnitIsConnected(u) then units[#units + 1] = u end
	end
	units[#units + 1] = "player"
	return units
end

local function HasAuraName(unit, ...)
	if not S.GetAura then return end
	for i = 1, 40 do
		local a = { S.GetAura(unit, i) }
		if not a[1] then break end
		for _, want in ipairs({ ... }) do
			if a[1] == want then return true, a[6] and (a[6] - GetTime()) end -- a[6]=expiration
		end
	end
end

local function ScanBuff(...)
	local missing, minLeft, count = {}, nil, 0
	for _, u in ipairs(GroupUnits()) do
		count = count + 1
		local has, left = HasAuraName(u, ...)
		if has then
			if left and (not minLeft or left < minLeft) then minLeft = left end
		else
			missing[#missing + 1] = u
		end
	end
	return missing, minLeft, count
end

local function BuildRow(parent, x, label)
	-- small icon button: count badge on the icon, mini timer under it
	local b = CreateFrame("Button", "SentinelUIWild" .. label, parent, "SecureActionButtonTemplate")
	b:SetSize(30, 30)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -16)
	S:SetTemplate(b, "Default")
	-- AnyDown/AnyUp variants so the secure click fires on every client
	b:RegisterForClicks("AnyDown", "AnyUp", "LeftButtonUp", "RightButtonUp")
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	local cnt = S:FontString(b, 11, "OUTLINE", S.media.numberFont)
	cnt:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
	local timer = S:FontString(b, 9, "OUTLINE", S.media.numberFont)
	timer:SetPoint("TOP", b, "BOTTOM", 0, -1)
	b.icon, b.fs, b.timer = icon, cnt, timer
	return b
end

local function FmtTime(sec)
	if not sec then return "--" end
	return format("%d:%02d", floor(sec / 60), floor(sec % 60))
end

function WB:BuildFrame()
	if frame or select(2, UnitClass("player")) ~= "DRUID" then return end
	local f = CreateFrame("Frame", "SentinelUIWildBuffs", UIParent, S.BackdropTemplate)
	f:SetSize(78, 50)
	f:SetFrameStrata("LOW")
	S:SetTemplate(f, "Default", "MEDIUM")
	f.title = S:FontString(f, 9, "OUTLINE")
	f.title:SetPoint("TOP", 0, -4)
	f.title:SetText("|cffff7c0aWild|r")
	-- direct drag on the title strip (mover still works via /suim)
	f:SetMovable(true)
	local grip = CreateFrame("Button", nil, f)
	grip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	grip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	grip:SetHeight(12)
	grip:EnableMouse(true)
	grip:RegisterForDrag("LeftButton")
	grip:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
	grip:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		-- keep the mover anchor in sync so /suim does not snap it back
		local m = f.suiMover or (S.movers and S.movers.wildbuffs)
		if m and m.SetPoint then
			m:ClearAllPoints()
			m:SetPoint("CENTER", f, "CENTER")
			if m.SavePosition then pcall(m.SavePosition, m) end
		end
	end)
	f.mark = BuildRow(f, 8, "Mark")
	f.thorns = BuildRow(f, 42, "Thorns")
	S:CreateMover(f, "wildbuffs", L["Wild Buffs"], { "TOPLEFT", "UIParent", "TOPLEFT", 60, -420 }, "wildbuffs")
	f:Hide()
	frame = f
end

local function SetSpell(btn, mouse, id, unit)
	if InCombatLockdown() then return end
	local name = SpellName(id)
	if not name then return end
	local sfx = mouse == 2 and "2" or ""
	btn:SetAttribute("type" .. sfx, "spell")
	btn:SetAttribute("spell" .. sfx, name)
	btn:SetAttribute("unit" .. sfx, unit or "player")
end

local function RefreshRow(btn, iconTex, label, missing, minLeft, total)
	btn.icon:SetTexture(iconTex)
	local n = #missing
	btn.fs:SetText(n == 0 and "|cff66ff66+|r" or ("|cffff5555" .. n .. "|r"))
	btn.timer:SetText(n == 0 and FmtTime(minLeft) or (FmtTime(minLeft) .. ""))
	btn.timer:SetTextColor(n == 0 and 0.6 or 1, n == 0 and 0.9 or 0.55, n == 0 and 0.6 or 0.55)
	btn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
		GameTooltip:AddLine(label)
		if n > 0 then
			GameTooltip:AddLine(L["missing on:"] or "missing on:")
			for _, u in ipairs(missing) do
				GameTooltip:AddLine("  " .. (UnitName(u) or u), 1, 0.5, 0.5)
			end
		else
			GameTooltip:AddLine("|cff66ff66" .. (L["all buffed"] or "all buffed") .. "|r")
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function WB:Update()
	self.db = self.db or S.db.profile.wildbuffs
	if not frame then return end
	if self.db.enable == false or select(2, UnitClass("player")) ~= "DRUID" then frame:Hide() return end
	frame:Show()
	local markN, giftN, thornN = SpellName(MARK_ID), SpellName(GIFT_ID), SpellName(THORNS_ID)
	if not markN then return end
	local function Tex(id)
		return (GetSpellTexture and GetSpellTexture(id)) or [[Interface\Icons\Spell_Nature_Regeneration]]
	end

	-- mark/gift row: missing either-name counts as missing the buff
	local missM, leftM, total = ScanBuff(markN, giftN)
	RefreshRow(frame.mark, Tex(GIFT_ID), "MotW", missM, leftM, total)
	SetSpell(frame.mark, 1, GIFT_ID)
	SetSpell(frame.mark, 2, MARK_ID, missM[1])

	local missT, leftT = ScanBuff(thornN)
	RefreshRow(frame.thorns, Tex(THORNS_ID), "Thorns", missT, leftT, total)
	SetSpell(frame.thorns, 1, THORNS_ID, missT[1])
	SetSpell(frame.thorns, 2, THORNS_ID, missT[1])
end

function WB:Initialize()
	self.db = S.db.profile.wildbuffs
	if select(2, UnitClass("player")) ~= "DRUID" then return end
	self:BuildFrame()
	self.t = 0
	frame:SetScript("OnUpdate", function(_, dt)
		self.t = self.t + dt
		if self.t < 1.5 then return end
		self.t = 0
		if not InCombatLockdown() then S:SafeCall("WildBuffs:Update", WB.Update, WB) end
	end)
	self:Update()
end
