-- WildBuffs: druid buff manager in Blessings style. One row per raid group
-- (G1..G8, solo = "You"): Gift / Mark / Thorns icons with missing badges and
-- timers. Left-click casts, right-click singles the next missing member -
-- clicks rotate through the missing list in order. Position persists.
local _, ns = ...
local S = ns.S
local L = S.L
local WB = S:NewModule("WildBuffs", "wildbuffs")

local CreateFrame = CreateFrame
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local UnitName, UnitClass, UnitExists = UnitName, UnitClass, UnitExists
local IsInRaid = IsInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local format, floor, min = format, math.floor, math.min

local MARK_ID, GIFT_ID, THORNS_ID = 9885, 26991, 26992
local function SpellName(id)
	if S.GetSpellInfo then return S.GetSpellInfo(id) end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

local frame
local rows = {} -- per-group row tables

-- units grouped by raid subgroup (party = single bucket) ---------------
local function Groups()
	if IsInRaid() and GetRaidRosterInfo then
		local g = {}
		for i = 1, GetNumGroupMembers and GetNumGroupMembers() or 40 do
			local _, _, sub = GetRaidRosterInfo(i)
			if sub then
				g[sub] = g[sub] or {}
				tinsert(g[sub], "raid" .. i)
			end
		end
		if next(g) then return g end
	end
	local g1 = {}
	for i = 1, 4 do
		if UnitExists("party" .. i) then tinsert(g1, "party" .. i) end
	end
	tinsert(g1, "player")
	return { [1] = g1 }
end

local function HasAuraName(unit, ...)
	if not S.GetAura then return end
	for i = 1, 40 do
		local r = S.GetAura(unit, i)
		local name, exp, dur
		if type(r) == "table" then
			name, exp, dur = r.name or r[1], r.expirationTime, r.duration
		else
			local a = { S.GetAura(unit, i) }
			name, exp, dur = a[1], a[6], a[5]
		end
		if not name then break end
		for _, want in ipairs({ ... }) do
			if name == want then
				local left = exp and (exp - GetTime())
				if (not left or left <= 0) and dur then left = dur end
				return true, left
			end
		end
	end
end

local function InBuffRange(u, spellName)
	if u == "player" then return true end
	if not UnitExists(u) or UnitIsDeadOrGhost(u) or (UnitIsConnected and not UnitIsConnected(u)) then return false end
	if IsSpellInRange and spellName then
		local r = IsSpellInRange(spellName, u)
		if r == 1 or r == true then return true end
		if r == 0 or r == false then return false end
	end
	-- IsSpellInRange can't check some units -> coarser ~40y band
	if UnitInRange then return UnitInRange(u) and true or false end
	return true
end

local function ScanUnits(units, spellName, ...)
	-- three buckets: buffed (drives the timer), missing-in-range (buffable
	-- now) and missing-but-out-of-range/dead/offline (skipped, they re-enter
	-- the missing list automatically once they are back in range)
	local missing, far, minLeft = {}, {}, nil
	for _, u in ipairs(units) do
		local has, left = HasAuraName(u, ...)
		if has then
			if left and (not minLeft or left < minLeft) then minLeft = left end
		elseif InBuffRange(u, spellName) then
			tinsert(missing, u)
		else
			tinsert(far, u)
		end
	end
	return missing, minLeft, far
end

local function FmtTime(sec)
	if not sec then return "--" end
	return format("%d:%02d", floor(sec / 60), floor(sec % 60))
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

local function BuildIcon(parent, x, key)
	local b = CreateFrame("Button", "SentinelUIWild" .. key, parent, "SecureActionButtonTemplate")
	b:SetSize(26, 26)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
	S:SetTemplate(b, "Default")
	b:RegisterForClicks("AnyDown", "AnyUp", "LeftButtonUp", "RightButtonUp")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	b.cnt = S:FontString(b, 10, "OUTLINE", S.media.numberFont)
	b.cnt:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 0)
	b.selIdx = 1
	return b
end

local function BuildRow(parent, gi)
	local r = CreateFrame("Frame", nil, parent)
	r:SetSize(150, 28)
	r.label = S:FontString(r, 9, "OUTLINE", S.media.numberFont)
	r.label:SetPoint("LEFT", 2, 0)
	r.label:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
	r.gift = BuildIcon(r, 20, "G" .. gi)
	r.mark = BuildIcon(r, 50, "M" .. gi)
	r.thorns = BuildIcon(r, 80, "T" .. gi)
	r.timer = S:FontString(r, 9, "OUTLINE", S.media.numberFont)
	r.timer:SetPoint("LEFT", r.thorns, "RIGHT", 5, 0)
	return r
end

function WB:BuildFrame()
	if frame or select(2, UnitClass("player")) ~= "DRUID" then return end
	local f = CreateFrame("Frame", "SentinelUIWildBuffs", UIParent, S.BackdropTemplate)
	f:SetSize(150, 46)
	f:SetFrameStrata("LOW")
	S:SetTemplate(f, "Default", "MEDIUM")
	f.title = S:FontString(f, 8, "OUTLINE")
	f.title:SetPoint("TOP", 0, -3)
	f.title:SetText("|cffff7c0aWild|r")
	-- drag strip with persisted position
	f:SetMovable(true)
	local grip = CreateFrame("Button", nil, f)
	grip:SetPoint("TOPLEFT") grip:SetPoint("TOPRIGHT") grip:SetHeight(12)
	grip:EnableMouse(true)
	grip:RegisterForDrag("LeftButton")
	grip:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
	grip:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local p, _, rp, x, y = f:GetPoint(1)
		S.db.profile.wildbuffs.pos = { p, "UIParent", rp, x, y }
	end)
	-- single expiry badge: pulses when a buff in YOUR OWN group has <10s
	-- left. No per-person spam, other raid groups stay silent
	f.warn = S:FontString(f, 11, "OUTLINE", S.media.numberFont)
	f.warn:SetPoint("RIGHT", -4, -2)
	f.warn:SetText("|cffff5555!|r")
	f.warn:Hide()
	f.wt = 0
	frame = f
	local pos = S.db.profile.wildbuffs and S.db.profile.wildbuffs.pos
	if pos then f:SetPoint(unpack(pos)) else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -420) end
	f:Hide()
end

local function UpdateBtn(btn, iconTex, spellId, missing, unit, rotate, far)
	btn.icon:SetTexture(iconTex)
	local n, nf = #missing, #(far or {})
	if n > 0 then
		btn.cnt:SetText("|cffff5555" .. n .. "|r")
	elseif nf > 0 then
		btn.cnt:SetText("|cffffcc00" .. nf .. "|r") -- missing but out of range
	else
		btn.cnt:SetText("|cff66ff66+|r")
	end
	if rotate and n > 0 then
		-- sequential targeting: keep cycling the missing list
		if btn.selIdx > n then btn.selIdx = 1 end
		SetSpell(btn, 1, spellId, missing[btn.selIdx])
		SetSpell(btn, 2, spellId, missing[btn.selIdx])
	else
		SetSpell(btn, 1, spellId, unit)
		SetSpell(btn, 2, spellId, unit)
	end
	btn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
		GameTooltip:AddLine(SpellName(spellId) or "?")
		for _, u in ipairs(missing) do
			GameTooltip:AddLine("  " .. (UnitName(u) or u), 1, 0.5, 0.5)
		end
		for _, u in ipairs(far or {}) do
			GameTooltip:AddLine("  " .. (UnitName(u) or u) .. " |cffffcc00(" .. L["out of range"] .. ")|r", 1, 0.5, 0.5)
		end
		if n == 0 and nf == 0 then GameTooltip:AddLine("|cff66ff66OK|r") end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function WB:Update()
	self.db = self.db or S.db.profile.wildbuffs
	if not frame then return end
	-- in combat the frame/buttons are protected: layout + unit attributes
	-- must not change, but the scan itself is read-only and SHOULD run so
	-- buffs cast mid-fight show up right away
	local combat = InCombatLockdown()
	if not combat then
		if self.db.enable == false or select(2, UnitClass("player")) ~= "DRUID" then frame:Hide() return end
		frame:Show()
	elseif self.db.enable == false then return end
	local markN, giftN, thornN = SpellName(MARK_ID), SpellName(GIFT_ID), SpellName(THORNS_ID)
	if not markN then return end
	local FALLBACK = {
		[GIFT_ID] = [[Interface\Icons\Spell_Nature_GiftoftheWild]],
		[MARK_ID] = [[Interface\Icons\Spell_Nature_Regeneration]],
		[THORNS_ID] = [[Interface\Icons\Spell_Nature_Thorns]],
	}
	local function Tex(id) return (GetSpellTexture and GetSpellTexture(id)) or FALLBACK[id] end

	local groups = Groups()
	local ownGroup
	for g, units in pairs(groups) do
		for _, u in ipairs(units) do if u == "player" then ownGroup = g end end
	end
	local sorted = {}
	for g in pairs(groups) do sorted[#sorted + 1] = g end
	table.sort(sorted)
	local y, expiring = 0, false
	for idx, g in ipairs(sorted) do
		local r = rows[idx]
		if not r then
			r = BuildRow(frame, idx)
			rows[idx] = r
		end
		if not combat then
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -14 - y)
		end
		y = y + 30
		r.label:SetText(IsInRaid() and ("G" .. g) or "")
		local units = groups[g]
		local missM, leftM, farM = ScanUnits(units, markN, markN, giftN)
		local missT, leftT, farT = ScanUnits(units, thornN, thornN)
		-- rotate target through the missing list on click (OOC only)
		for _, b in ipairs({ r.mark, r.thorns }) do
			if not b.suiRotate then
				b.suiRotate = true
				b:HookScript("OnClick", function(self) self.selIdx = (self.selIdx or 1) + 1 S:SafeCall("WildBuffs:Update", WB.Update, WB) end)
			end
		end
		-- Gift is only learned at 50: dim it until it is in the spellbook
		r.gift.icon:SetDesaturated(not (giftN and GetSpellInfo and GetSpellInfo(giftN)))
		UpdateBtn(r.gift, Tex(GIFT_ID), GIFT_ID, missM, units[1], nil, farM)
		UpdateBtn(r.mark, Tex(MARK_ID), MARK_ID, missM, nil, true, farM)
		UpdateBtn(r.thorns, Tex(THORNS_ID), THORNS_ID, missT, nil, true, farT)
		local worst = leftM or leftT
		if leftM and leftT then worst = min(leftM, leftT) end
		-- expiry warning only in party (never in raid), player's own group
		if not IsInRaid() and g == ownGroup and worst and worst <= (self.db.warnSeconds or 10) then expiring = true end
		r.timer:SetText(FmtTime(worst))
		if not combat then r:Show() end
	end
	if not combat then
		for i = #sorted + 1, #rows do rows[i]:Hide() end
		frame:SetHeight(18 + y)
	end
	-- badge visibility is layout-free -> safe even in combat
	if frame.warn then
		if expiring then frame.warn:Show() else frame.warn:Hide() end
	end
	self.expiring = expiring
end

function WB:Initialize()
	self.db = S.db.profile.wildbuffs
	if select(2, UnitClass("player")) ~= "DRUID" then return end
	self:BuildFrame()
	self.t = 0
	frame:SetScript("OnUpdate", function(_, dt)
		if frame and frame.warn and frame.warn:IsShown() then
			frame.wt = (frame.wt or 0) + dt
			frame.warn:SetAlpha(0.4 + 0.6 * math.abs(math.sin(frame.wt * 6)))
		end
		self.t = self.t + dt
		if self.t < 1.5 then return end
		self.t = 0
		S:SafeCall("WildBuffs:Update", WB.Update, WB)
	end)
	self:Update()
end
