-- RaidGrid: healer-oriented raid grid (own implementation). Members are laid
-- out by raid subgroup as clickable unit cells: class-colored or health-
-- gradient health bar, mana/power bar, name, hp/deficit text, dead/offline/
-- AFK states, aggro dot, dispel-typed debuff icons with colored border, own
-- HoT tracking, incoming-heal + absorb preview, raid marker, role badge,
-- ready-check state, resurrection icon, missing-buff watch, range fade and a
-- full click-cast system (same binding format as unit frames).
local _, ns = ...
local S = ns.S
local L = S.L
local RG = S:NewModule("RaidGrid", "raidgrid")

local _G = _G
local ipairs, pairs, wipe, tinsert, sort = ipairs, pairs, wipe, table.insert, table.sort
local format, lower, strtrim, strrep = string.format, string.lower, strtrim, strrep
local min, max, floor = math.min, math.max, math.floor
local tremove = table.remove
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local IsInGroup, IsInRaid, GetNumGroupMembers = IsInGroup, IsInRaid, GetNumGroupMembers
local UnitName, UnitClass, UnitExists, UnitIsPlayer = UnitName, UnitClass, UnitExists, UnitIsPlayer
local UnitHealth, UnitHealthMax, UnitIsConnected, UnitIsDeadOrGhost = UnitHealth, UnitHealthMax, UnitIsConnected, UnitIsDeadOrGhost
local UnitIsAFK, UnitInRange, UnitThreatSituation = UnitIsAFK, UnitInRange, UnitThreatSituation
local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local UnitGetIncomingHeals, UnitGetTotalAbsorbs = UnitGetIncomingHeals, UnitGetTotalAbsorbs
local UnitGroupRolesAssigned, UnitIsUnit = UnitGroupRolesAssigned, UnitIsUnit
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local GetReadyCheckStatus, GetRaidTargetIndex = GetReadyCheckStatus, GetRaidTargetIndex
local Ambiguate, GetRaidRosterInfo, SetRaidTargetIconTexture = Ambiguate, GetRaidRosterInfo, SetRaidTargetIconTexture
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip

local MAX_GROUPS, MAX_ROWS = 8, 5
local MAX_DEBUFFS, MAX_HOTS, MAX_BUFFWATCH = 3, 3, 2
local members = {}        -- group -> { unit, name, class }
local ticker

local DEBUFF_COLORS = {
	Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0.0, 1 },
	Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 }, [""] = { 0.8, 0, 0 },
}
local ROLE_MARK = { TANK = "|cff8888ffT|r", HEALER = "|cff55ff55H|r", DAMAGER = "" }
local POWER_COLORS = { [0] = { 0, 0.45, 1 }, [1] = { 1, 0.2, 0.2 }, [3] = { 1, 0.6, 0.2 } } -- mana / rage / energy
local DISPEL_SPELLS = { -- first known spell of the player's class wins
	PRIEST = { 527, 988, 552, 528 },
	PALADIN = { 4987, 1152 },
	DRUID = { 8946, 2893, 2782 },          -- Cure Poison, Abolish Poison, Remove Curse
	SHAMAN = { 51886, 526, 2870 },         -- Cleanse Spirit (Wrath+), Cure Poison, Cure Disease
	MAGE = { 475 },
	WARLOCK = { 19505 },
}
-- buff watch: spell-id groups; shown as icon when *no* aura of the group is up.
-- name/icon resolve lazily so each client/localization uses live data.
local BUFFWATCH = {
	{ 1243, 21562 },        -- Power Word: Fortitude / Prayer of Fortitude
	{ 1126, 21849, 5234 },  -- Mark of the Wild / Gift of the Wild
	{ 1459, 10157, 23028 }, -- Arcane Intellect / Brilliance
	{ 14752, 27681 },       -- Divine Spirit / Prayer of Spirit
	{ 976, 27683 },         -- Shadow Protection / Prayer of Shadow Protection
}
local buffNames -- [group] -> {name, icon} once resolved

local function ResolveBuffWatch()
	if buffNames then return end
	buffNames = {}
	for gi, ids in ipairs(BUFFWATCH) do
		for _, id in ipairs(ids) do
			local name, _, icon = S.GetSpellInfo(id)
			if name then buffNames[gi] = { name = name, icon = icon, ids = ids } break end
		end
	end
end

-- click-cast: same binding format as unitframes.clickCast ---------------------
-- { button = "1".."5", mod = "none"|"shift"|"ctrl"|"alt", type = "spell"|"macro"|"item"|"target"|"togglemenu"|"focus", value = "..." }
-- spell value "dispel"/"heal"/"rez" resolves to the class spell automatically.
-- while cell.isDead and db.rezOnDead, every spell binding becomes the class rez.
local CC_VALUE_ATTR = { spell = "spell", macro = "macrotext", item = "item" }

local function ResolveDispel()
	for _, id in ipairs(DISPEL_SPELLS[S.myClass] or {}) do
		if S.IsSpellKnown and S.IsSpellKnown(id) then
			return S.GetSpellInfo(id)
		end
	end
end

-- class heal spells (IDs, resolved to localized names; ordered by preference
-- so "heal" picks the main heal). Covers every WoW healer class; entries the
-- client does not know (other expansions/specs) are skipped.
local CLASS_SPELLS = {
	PRIEST = { 2061, 2054, 2050, 2060, 139, 596, 32546, 17 },
	-- Flash Heal, Heal, Lesser Heal, Greater Heal, Renew, Prayer of Healing, Binding Heal, PW: Shield
	PALADIN = { 19750, 635, 20473 },           -- Flash of Light, Holy Light, Holy Shock
	DRUID = { 8936, 5185, 774, 33763, 18562, 48438, 740 },
	-- Regrowth, Healing Touch, Rejuvenation, Lifebloom, Swiftmend, Wild Growth, Tranquility
	SHAMAN = { 8004, 331, 1064, 61295, 974 },  -- Lesser Healing Wave, Healing Wave, Chain Heal, Riptide, Earth Shield
	MONK = { 116670, 124682, 115151, 115175, 115310, 191837 },
	-- Vivify, Enveloping Mist, Renewing Mist, Soothing Mist, Revival, Essence Font
	EVOKER = { 361469, 355913, 355936, 367226, 364343, 360995, 363534 },
	-- Living Flame, Emerald Blossom, Dream Breath, Spiritbloom, Echo, Verdant Embrace, Rewind
}

local function ResolveHeal()
	for _, id in ipairs(CLASS_SPELLS[S.myClass] or {}) do
		if S.IsSpellKnown and S.IsSpellKnown(id) then
			return S.GetSpellInfo(id)
		end
	end
end

-- class resurrection spells (normal rez first, then battle/mass rez)
local REZ_SPELLS = {
	PRIEST = { 2006, 212036 },               -- Resurrection, Mass Resurrection
	PALADIN = { 7328, 212056 },              -- Redemption, Absolution
	DRUID = { 50769, 20484, 212040 },        -- Revive, Rebirth, Revitalize
	SHAMAN = { 2008, 212048 },               -- Ancestral Spirit, Ancestral Vision
	MONK = { 115178, 212051 },               -- Resuscitate, Reawaken
	EVOKER = { 361227, 361178 },             -- Return, Mass Return
	WARLOCK = { 20707 },                     -- Soulstone (rez-capable on later clients)
}

local function ResolveRez()
	for _, id in ipairs(REZ_SPELLS[S.myClass] or {}) do
		if S.IsSpellKnown and S.IsSpellKnown(id) then
			return S.GetSpellInfo(id)
		end
	end
end

-- spell picker list for the options window: keywords first, then every known
-- class heal spell by localized name
local spellPickerList
local function ClassSpellList()
	if spellPickerList then return spellPickerList end
	spellPickerList = { "heal", "dispel", "rez" }
	for _, id in ipairs(CLASS_SPELLS[S.myClass] or {}) do
		local name = S.GetSpellInfo(id)
		if name and (not S.IsSpellKnown or S.IsSpellKnown(id)) then
			spellPickerList[#spellPickerList + 1] = name
		end
	end
	return spellPickerList
end

function RG:ApplyClicksTo(cell)
	if not cell.ccKeys then cell.ccKeys = {} end
	for _, k in ipairs(cell.ccKeys) do cell:SetAttribute(k, nil) end
	wipe(cell.ccKeys)
	cell:SetAttribute("type1", "target") -- plain left click always targets
	cell.ccKeys[#cell.ccKeys + 1] = "type1"
	local cc = self.db.clickCast
	if not cc or not cc.enable or not cc.bindings then return end
	for _, b in ipairs(cc.bindings) do
		local btn = tonumber(b.button) or 1
		local mod = (b.mod and b.mod ~= "none" and b.mod ~= "") and (b.mod:lower() .. "-") or ""
		local tattr = mod .. "type" .. btn
		cell:SetAttribute(tattr, b.type or "spell")
		cell.ccKeys[#cell.ccKeys + 1] = tattr
		local vname = CC_VALUE_ATTR[b.type or ""]
		local value = b.value
		if b.type == "spell" then
			local lv = lower(value or "")
			if cell.isDead and self.db.rezOnDead then
				-- dead units: every spell binding becomes the class rez (VuhDo-style)
				value = ResolveRez()
				if not value then cell:SetAttribute(tattr, "togglemenu") end
			elseif lv == "dispel" or lv == "heal" or lv == "rez" then
				value = lv == "dispel" and ResolveDispel() or (lv == "heal" and ResolveHeal() or ResolveRez())
				if not value then cell:SetAttribute(tattr, "togglemenu") end -- no spell known -> menu
			end
		end
		if vname and value and value ~= "" then
			local vattr = mod .. vname .. btn
			cell:SetAttribute(vattr, value)
			cell.ccKeys[#cell.ccKeys + 1] = vattr
		end
		if cell.unit then
			local uattr = mod .. "unit" .. btn
			cell:SetAttribute(uattr, cell.unit)
			cell.ccKeys[#cell.ccKeys + 1] = uattr
		end
	end
end

function RG:ApplyClicks()
	if InCombatLockdown() or not self.cells then return end
	for _, grp in pairs(self.cells) do
		for _, cell in ipairs(grp) do self:ApplyClicksTo(cell) end
	end
end

-- cell ----------------------------------------------------------------------
local function MakeCell(parent)
	local b = CreateFrame("Button", nil, parent, "SecureUnitButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:EnableMouse(true)
	S:SetTemplate(b, "Default")

	b.hp = CreateFrame("StatusBar", nil, b)
	b.hp:SetPoint("TOPLEFT", 1, -1)
	b.hp:SetPoint("BOTTOMRIGHT", -1, 1)
	b.hp:SetMinMaxValues(0, 1)
	b.hp:SetStatusBarTexture(S.media.statusbar)
	b.hp.bg = b.hp:CreateTexture(nil, "BACKGROUND")
	b.hp.bg:SetAllPoints()
	b.hp.bg:SetTexture(S.media.statusbar)
	b.hp.bg:SetVertexColor(0.08, 0.08, 0.08, 0.9)

	-- heal/absorb previews are statusbars so the client itself clips their fill
	-- inside the cell; raw textures can render outside the frame bounds
	b.inc = CreateFrame("StatusBar", nil, b)
	b.inc:SetPoint("TOP", b.hp)
	b.inc:SetPoint("BOTTOM", b.hp)
	b.inc:SetPoint("LEFT", b.hp)
	b.inc:SetPoint("RIGHT", b.hp)
	b.inc:SetMinMaxValues(0, 1)
	b.inc:SetStatusBarTexture(S.media.statusbar)
	b.inc:SetStatusBarColor(0.2, 0.8, 0.2, 0.4)
	b.inc:SetFrameLevel(b.hp:GetFrameLevel() + 1)
	b.inc:Hide()
	b.abs = CreateFrame("StatusBar", nil, b)
	b.abs:SetAllPoints(b.hp)
	b.abs:SetMinMaxValues(0, 1)
	b.abs:SetStatusBarTexture(S.media.statusbar)
	b.abs:SetStatusBarColor(1, 0.85, 0.2, 0.45)
	b.abs:SetReverseFill(true)
	b.abs:SetFrameLevel(b.hp:GetFrameLevel() + 2)
	b.abs:Hide()

	b.pow = CreateFrame("StatusBar", nil, b)
	b.pow:SetPoint("BOTTOMLEFT", 1, 1)
	b.pow:SetPoint("BOTTOMRIGHT", -1, 1)
	b.pow:SetHeight(3)
	b.pow:SetMinMaxValues(0, 1)
	b.pow:SetStatusBarTexture(S.media.statusbar)
	b.pow:SetFrameLevel(b.hp:GetFrameLevel() + 1)

	b.hl = b:CreateTexture(nil, "OVERLAY", nil, 5)
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.12)
	b.hl:Hide()

	b.name = S:FontString(b.hp, 10, "OUTLINE")
	b.name:SetPoint("TOPLEFT", 3, -1)
	b.name:SetWidth(0)
	b.hpText = S:FontString(b.hp, 9, "OUTLINE")
	b.hpText:SetPoint("BOTTOMRIGHT", -3, 4)

	b.aggro = b:CreateTexture(nil, "OVERLAY", nil, 4)
	b.aggro:SetSize(10, 10)
	b.aggro:SetPoint("TOPLEFT", 2, -2)
	b.aggro:SetColorTexture(1, 0, 0, 0.85)
	b.aggro:Hide()
	b.raidIcon = b:CreateTexture(nil, "OVERLAY", nil, 4)
	b.raidIcon:SetSize(12, 12)
	b.raidIcon:SetPoint("TOP", 0, -2)
	b.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	b.raidIcon:Hide()
	b.ready = b:CreateTexture(nil, "OVERLAY", nil, 4)
	b.ready:SetSize(12, 12)
	b.ready:SetPoint("CENTER", 0, -2)
	b.ready:Hide()
	b.res = b:CreateTexture(nil, "OVERLAY", nil, 4)
	b.res:SetSize(14, 14)
	b.res:SetPoint("CENTER", 0, 0)
	b.res:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
	b.res:Hide()
	b.role = S:FontString(b.hp, 9, "OUTLINE")
	b.role:SetPoint("TOPRIGHT", -3, -1)

	b.debuffs = {}
	for i = 1, MAX_DEBUFFS do
		local t = b:CreateTexture(nil, "OVERLAY", nil, 4)
		t:SetSize(12, 12)
		t:SetPoint("TOPRIGHT", -(2 + (i - 1) * 13), -2)
		t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		t:Hide()
		b.debuffs[i] = t
	end
	b.hots = {}
	for i = 1, MAX_HOTS do
		local t = b:CreateTexture(nil, "OVERLAY", nil, 4)
		t:SetSize(11, 11)
		t:SetPoint("BOTTOMLEFT", 3 + (i - 1) * 13, 4)
		t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		t:Hide()
		b.hots[i] = t
	end
	b.buffs = {}
	for i = 1, MAX_BUFFWATCH do
		local t = b:CreateTexture(nil, "OVERLAY", nil, 4)
		t:SetSize(10, 10)
		t:SetPoint("BOTTOMRIGHT", -(3 + (i - 1) * 11), 4)
		t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		t:SetVertexColor(1, 0.3, 0.3)
		t:Hide()
		b.buffs[i] = t
	end

	b:SetScript("OnEnter", function(c)
		c.hl:Show()
		if RG.db.unitTooltip and c.unit then
			GameTooltip:SetOwner(c, "ANCHOR_BOTTOMRIGHT")
			GameTooltip:SetUnit(c.unit)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(c) c.hl:Hide() GameTooltip:Hide() end)
	b:Hide()
	return b
end

-- frame ---------------------------------------------------------------------
function RG:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIRaidGrid", UIParent, S.BackdropTemplate)
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetFrameStrata("MEDIUM")
	S:SetTemplate(f, "Default")
	f:Hide()
	f:SetScript("OnDragStart", function(fr) if not RG.db.lockFrame then fr:StartMoving() end end)
	f:SetScript("OnDragStop", function(fr)
		fr:StopMovingOrSizing()
		local point, _, rel, x, y = fr:GetPoint(1)
		RG.db.point = { point = point, rel = rel, x = x, y = y }
	end)
	local p = self.db.point
	if p and p.point then f:SetPoint(p.point, UIParent, p.rel or "CENTER", p.x or 0, p.y or 0)
	else f:SetPoint("CENTER", UIParent, "CENTER", -250, -80) end

	-- small move-anchor: a tiny accent tab above the top-left corner so the
	-- whole grid can be dragged without a title bar sitting on top of cells
	f.anchor = CreateFrame("Button", nil, f)
	f.anchor:SetSize(16, 10)
	f.anchor:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, -1)
	f.anchor:EnableMouse(true)
	f.anchor:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	S:SetTemplate(f.anchor, "Default")
	local at = f.anchor:CreateTexture(nil, "OVERLAY")
	at:SetPoint("CENTER")
	at:SetSize(8, 3)
	at:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.9)
	f.anchor:SetScript("OnMouseDown", function(_, btn)
		if btn == "LeftButton" and not RG.db.lockFrame then f:StartMoving() end
	end)
	f.anchor:SetScript("OnMouseUp", function() f:StopMovingOrSizing()
		local point, _, rel, x, y = f:GetPoint(1)
		RG.db.point = { point = point, rel = rel, x = x, y = y }
	end)
	f.anchor:SetScript("OnEnter", function(a)
		GameTooltip:SetOwner(a, "ANCHOR_TOP")
		GameTooltip:AddLine("HealGrid")
		GameTooltip:AddLine(L["Drag: move  |  Right-click: options"], 1, 1, 1)
		GameTooltip:Show()
	end)
	f.anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.anchor:SetScript("OnClick", function(_, btn)
		if btn == "RightButton" then RG:ToggleConfig() end
	end)

	self.cells = {}
	for g = 1, MAX_GROUPS do
		self.cells[g] = {}
		for r = 1, MAX_ROWS do
			self.cells[g][r] = MakeCell(f)
		end
	end
	self.frame = f
end

-- roster --------------------------------------------------------------------
function RG:Collect()
	wipe(members)
	local function Add(unit, grp)
		if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
		grp = min(max(grp or 1, 1), MAX_GROUPS)
		local list = members[grp] or {}
		members[grp] = list
		if #list < MAX_ROWS then
			local _, class = UnitClass(unit)
			list[#list + 1] = { unit = unit, name = Ambiguate(UnitName(unit), "short"), class = class }
		end
	end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local _, _, subgroup = GetRaidRosterInfo(i)
			Add("raid" .. i, subgroup)
		end
	elseif IsInGroup() then
		Add("player", 1)
		for i = 1, GetNumGroupMembers() - 1 do Add("party" .. i, 1) end
	elseif self.db.showWhenSolo then
		Add("player", 1)
	end
	if self.db.sortMethod == "NAME" then
		for _, list in pairs(members) do
			sort(list, function(a, b) return a.name < b.name end)
		end
	end
end

-- per-cell paint ------------------------------------------------------------
local function GradColor(frac) -- green -> yellow -> red
	if frac > 0.5 then return (1 - frac) * 2, 1, 0 end
	return 1, frac * 2, 0
end

function RG:Paint(cell, m)
	local unit = m.unit
	local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
	local dead = UnitIsDeadOrGhost(unit)
	local offline = not UnitIsConnected(unit)
	if cell.isDead ~= dead then
		cell.isDead = dead
		if InCombatLockdown() then
			S:RunOutOfCombat(self.ApplyClicksTo, self, cell)
		else
			self:ApplyClicksTo(cell)
		end
	end
	local color = RAID_CLASS_COLORS[m.class] or { r = 0.5, g = 0.5, b = 0.5 }
	local frac = hpMax > 0 and hp / hpMax or 0

	cell.hp:SetMinMaxValues(0, hpMax)
	cell.hp:SetValue(hp)
	if dead or offline then
		cell.hp:SetStatusBarColor(0.18, 0.18, 0.18)
	elseif self.db.healthMode == "GRADIENT" then
		cell.hp:SetStatusBarColor(GradColor(frac))
	else
		cell.hp:SetStatusBarColor(color.r, color.g, color.b)
	end

	-- power bar
	if self.db.showPower and not dead and not offline then
		local p, pMax = UnitPower(unit), UnitPowerMax(unit)
		local ptype = UnitPowerType(unit)
		if pMax > 0 then
			local pc = POWER_COLORS[ptype] or POWER_COLORS[0]
			cell.pow:SetMinMaxValues(0, pMax)
			cell.pow:SetValue(p)
			cell.pow:SetStatusBarColor(pc[1], pc[2], pc[3])
			cell.pow:Show()
		else
			cell.pow:Hide()
		end
	else
		cell.pow:Hide()
	end

	local mark = ROLE_MARK[UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or ""] or ""
	if dead then
		cell.name:SetText("|cff888888" .. m.name .. "|r")
		cell.hpText:SetText(L["Dead"])
	elseif offline then
		cell.name:SetText("|cff888888" .. m.name .. "|r")
		cell.hpText:SetText(L["Offline"])
	else
		cell.name:SetText(m.name)
		if self.db.showDeficit then
			local def = hp - hpMax
			cell.hpText:SetText(def < 0 and format("|cffff7766%d|r", def) or format("%d%%", frac * 100))
		else
			cell.hpText:SetText(format("%d%%", frac * 100))
		end
	end
	cell.role:SetText(mark)

	-- incoming heals + absorbs preview. secret values (12.x) are skipped
	-- entirely; the statusbars clip their own fill inside the cell
	local w = cell.hp:GetWidth()
	local secret = S.IsSecret(hp) or S.IsSecret(hpMax)
	if self.db.showIncHeal and UnitGetIncomingHeals and not dead and not secret and w > 0 then
		local inc = UnitGetIncomingHeals(unit)
		if inc and not S.IsSecret(inc) and inc > 0 and hpMax > 0 then
			if hpMax > hp then
				-- heal lands inside the missing health: green segment at the hp edge
				-- (right edge stays anchored to the cell so it can never overflow)
				local off = min(w, hp / hpMax * w)
				cell.inc:SetReverseFill(false)
				cell.inc:SetPoint("LEFT", cell.hp, "LEFT", off, 0)
				cell.inc:SetMinMaxValues(0, hpMax - hp)
				cell.inc:SetValue(min(hpMax - hp, inc))
			else
				-- full health: overheal wedge from the right edge, width = heal size
				cell.inc:SetReverseFill(true)
				cell.inc:SetPoint("LEFT", cell.hp, "LEFT", 0, 0)
				cell.inc:SetMinMaxValues(0, hpMax)
				cell.inc:SetValue(min(hpMax, inc))
			end
			cell.inc:Show()
		else
			cell.inc:Hide()
		end
	else
		cell.inc:Hide()
	end
	if self.db.showAbsorb and UnitGetTotalAbsorbs and not dead and not secret and hpMax > 0 then
		local ab = UnitGetTotalAbsorbs(unit)
		if ab and not S.IsSecret(ab) and ab > 0 then
			cell.abs:SetMinMaxValues(0, hpMax)
			cell.abs:SetValue(min(hpMax, ab))
			cell.abs:Show()
		else
			cell.abs:Hide()
		end
	else
		cell.abs:Hide()
	end

	-- aggro dot
	cell.aggro:SetShown(not dead and (UnitThreatSituation(unit) or 0) >= 2)

	-- raid marker
	local ri = GetRaidTargetIndex and GetRaidTargetIndex(unit)
	if ri and ri > 0 then
		cell.raidIcon:Show()
		SetRaidTargetIconTexture(cell.raidIcon, ri)
	else
		cell.raidIcon:Hide()
	end

	-- ready check state + incoming resurrection
	if self.db.showReadyCheck and GetReadyCheckStatus then
		local st = GetReadyCheckStatus(unit)
		if st == "ready" then
			cell.ready:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready") cell.ready:Show()
		elseif st == "notready" then
			cell.ready:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady") cell.ready:Show()
		elseif st == "waiting" then
			cell.ready:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting") cell.ready:Show()
		else
			cell.ready:Hide()
		end
	else
		cell.ready:Hide()
	end
	cell.res:SetShown(not offline and UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit) or false)

	-- auras: debuff icons + dispel border, own HoTs, missing buffs
	local dN, hN, auraNames = 0, 0, self.db.buffWatch and {} or nil
	for i = 1, 40 do
		local a = S.GetAura(unit, i, "HARMFUL")
		if not a then break end
		if a.name and not S.IsSecret(a.name) and dN < MAX_DEBUFFS then
			dN = dN + 1
			cell.debuffs[dN]:SetTexture(a.icon)
			cell.debuffs[dN].dispel = a.dispelName
			cell.debuffs[dN]:Show()
		end
	end
	for i = 1, 40 do
		local a = S.GetAura(unit, i, "HELPFUL")
		if not a then break end
		if a.name and not S.IsSecret(a.name) then
			if auraNames then auraNames[lower(a.name)] = true end
			if self.db.showHots and a.sourceUnit == "player" and a.duration and a.duration > 0 and hN < MAX_HOTS then
				hN = hN + 1
				cell.hots[hN]:SetTexture(a.icon)
				cell.hots[hN]:Show()
			end
		end
	end
	for i = dN + 1, MAX_DEBUFFS do cell.debuffs[i]:Hide() cell.debuffs[i].dispel = nil end
	for i = hN + 1, MAX_HOTS do cell.hots[i]:Hide() end

	-- border: debuff color > own target accent > default
	local bcol
	if dN > 0 and self.db.showDebuffs then
		for i = 1, dN do
			local dn = cell.debuffs[i].dispel
			if dn then bcol = DEBUFF_COLORS[dn] or DEBUFF_COLORS[""] break end
		end
		bcol = bcol or DEBUFF_COLORS[""]
	elseif self.db.targetHighlight and UnitIsUnit(unit, "target") then
		bcol = { S.accent.r, S.accent.g, S.accent.b }
	end
	if bcol then S:SetTemplate(cell, "Default", nil, bcol) else S:SetTemplate(cell, "Default") end

	-- buff watch: icon for each missing raid buff
	if auraNames then
		ResolveBuffWatch()
		local w = 0
		for _, g in pairs(buffNames) do
			local has
			for _, id in ipairs(g.ids) do
				local nm = S.GetSpellInfo(id)
				if nm and auraNames[lower(nm)] then has = true break end
			end
			if not has and w < MAX_BUFFWATCH then
				w = w + 1
				cell.buffs[w]:SetTexture(g.icon)
				cell.buffs[w]:Show()
			end
		end
		for i = w + 1, MAX_BUFFWATCH do cell.buffs[i]:Hide() end
	else
		for i = 1, MAX_BUFFWATCH do cell.buffs[i]:Hide() end
	end

	-- range fade
	if self.db.rangeFade and not dead then
		local inRange = S.UnitInRange and S.UnitInRange(unit)
		cell:SetAlpha(inRange == false and (self.db.rangeAlpha or 0.4) or 1)
	else
		cell:SetAlpha(1)
	end
end

function RG:Layout()
	local f = self.frame
	if not f then return end
	local w, h, sp, gsp = self.db.barW, self.db.barH, self.db.spacing, self.db.groupSpacing
	local scale = self.db.scale or 1
	local gx = self.db.growthX == "LEFT" and -1 or 1
	local gy = self.db.growthY == "UP" and 1 or -1
	for g = 1, MAX_GROUPS do
		local col = gx == 1 and (g - 1) or (MAX_GROUPS - g)
		for r = 1, MAX_ROWS do
			local cell = self.cells[g][r]
			local row = gy == -1 and (r - 1) or (MAX_ROWS - r)
			cell:SetSize(w, h)
			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", 4 + col * (w + gsp), -(4 + row * (h + sp)))
		end
	end
	f:SetSize(8 + MAX_GROUPS * w + (MAX_GROUPS - 1) * gsp, 8 + MAX_ROWS * h + (MAX_ROWS - 1) * sp)
	f:SetScale(scale)
	f:SetAlpha(self.db.frameAlpha or 1)
end

function RG:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	self:Collect()
	local maxUsed = 0
	local combat = InCombatLockdown()
	local function PaintCell(cell, m)
		local ok, err = pcall(self.Paint, self, cell, m)
		if not ok and not self.paintErrLogged then
			self.paintErrLogged = true
			S:LogError(tostring(err), "RaidGrid:Paint")
		end
	end
	for g = 1, MAX_GROUPS do
		local list = members[g]
		if list and #list > 0 then maxUsed = g end
		for r = 1, MAX_ROWS do
			local cell, m = self.cells[g][r], list and list[r]
			if combat then
				-- protected frames: Show/Hide/SetAttribute are blocked in combat.
				-- Repaint slots still showing the same unit, alpha-hide the rest
				-- and re-layout after combat.
				if m and cell:IsShown() and cell.unit == m.unit then
					cell.m = m
					PaintCell(cell, m)
				elseif cell:IsShown() then
					cell:SetAlpha(0)
					self.combatDirty = true
				end
			elseif m then
				if cell.unit ~= m.unit then
					cell.unit = m.unit
					cell:SetAttribute("unit", m.unit)
					self:ApplyClicksTo(cell)
				end
				cell.m = m
				cell:Show()
				PaintCell(cell, m)
			else
				cell:Hide()
			end
		end
	end
	-- shrink the panel to the populated columns when hideEmpty is on
	if not combat and self.db.hideEmpty and maxUsed > 0 then
		local w, h, sp, gsp = self.db.barW, self.db.barH, self.db.spacing, self.db.groupSpacing
		f:SetSize(8 + maxUsed * w + (maxUsed - 1) * gsp, 8 + MAX_ROWS * h + (MAX_ROWS - 1) * sp)
	end
	-- deferred fixup once combat ends (re-run is throttled: only one queued)
	if combat and self.combatDirty and not self._regenQueued then
		self._regenQueued = true
		S:RunOutOfCombat(function()
			self._regenQueued, self.combatDirty = nil, nil
			self:Layout()
			self:ApplyClicks()
			self:Refresh()
		end)
	end
end

-- dedicated options window (own frame, not inside /sui) ----------------------
local CC_MOD_ORDER = { "none", "shift", "ctrl", "alt" }
local CC_MOD_LABEL = { none = "–", shift = "Shift", ctrl = "Ctrl", alt = "Alt" }
local CC_BTN_ORDER = { "1", "2", "3", "4", "5" }
local CC_BTN_LABEL = { ["1"] = L["Left Button"], ["2"] = L["Right Button"], ["3"] = L["Middle Button"], ["4"] = "4", ["5"] = "5" }
local CC_TYPE_ORDER = { "spell", "macro", "item", "target", "focus", "togglemenu" }
local CC_TYPE_LABEL = { spell = L["Cast Spell"], macro = L["Run Macro"], item = L["Use Item"], target = L["Target Unit"], focus = L["Set Focus"], togglemenu = L["Toggle Menu"] }

local function CycleVal(order, cur)
	for i, v in ipairs(order) do if v == cur then return order[(i % #order) + 1] end end
	return order[1]
end

local function CycleBtn(parent, w, label, tooltip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, 20)
	S:SkinButton(b)
	b.txt = S:FontString(b, 10, "OUTLINE")
	b.txt:SetPoint("CENTER")
	b.txt:SetText(label)
	return b
end

local function CheckRow(parent, key, label, y)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", 6, y)
	cb:SetSize(20, 20)
	S:SkinCheckBox(cb)
	cb:SetChecked(S.db.profile.raidgrid[key] and true or false)
	cb:SetScript("OnClick", function(c)
		S.db.profile.raidgrid[key] = c:GetChecked() and true or false
		RG:Update()
	end)
	local t = S:FontString(cb, 10)
	t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	t:SetText(label)
	return cb
end

local function SliderRow(parent, key, label, mn, mx, step, y, isScale)
	local name = "SentinelUIRGSlider" .. key
	local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	sl:SetPoint("TOPLEFT", 16, y)
	sl:SetSize(190, 14)
	sl:SetMinMaxValues(mn, mx)
	sl:SetValueStep(step)
	sl:SetObeyStepOnDrag(true)
	sl:SetValue(S.db.profile.raidgrid[key])
	S:SkinSlider(sl)
	_G[name .. "Text"]:SetText(label .. ": " .. format(isScale and "%.2f" or "%d", S.db.profile.raidgrid[key]))
	_G[name .. "Low"]:SetText(tostring(mn))
	_G[name .. "High"]:SetText(tostring(mx))
	sl:SetScript("OnValueChanged", function(_, v)
		v = floor(v / step + 0.5) * step
		if S.db.profile.raidgrid[key] ~= v then
			S.db.profile.raidgrid[key] = v
			_G[name .. "Text"]:SetText(label .. ": " .. format(isScale and "%.2f" or "%d", v))
			RG:Update()
		end
	end)
	return sl
end

local function BindingRow(parent, idx, y)
	local B = function() return S.db.profile.raidgrid.clickCast.bindings[idx] end
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetSize(430, 24)

	row.mod = CycleBtn(row, 56, CC_MOD_LABEL[B().mod or "none"] or "–")
	row.mod:SetPoint("LEFT", 0, 0)
	row.mod:SetScript("OnClick", function()
		B().mod = CycleVal(CC_MOD_ORDER, B().mod or "none")
		row.mod.txt:SetText(CC_MOD_LABEL[B().mod])
		RG:Update()
	end)

	row.btn = CycleBtn(row, 64, CC_BTN_LABEL[B().button or "1"] or "1")
	row.btn:SetPoint("LEFT", row.mod, "RIGHT", 4, 0)
	row.btn:SetScript("OnClick", function()
		B().button = CycleVal(CC_BTN_ORDER, B().button or "1")
		row.btn.txt:SetText(CC_BTN_LABEL[B().button])
		RG:Update()
	end)

	row.typ = CycleBtn(row, 84, CC_TYPE_LABEL[B().type or "spell"] or "?")
	row.typ:SetPoint("LEFT", row.btn, "RIGHT", 4, 0)
	row.typ:SetScript("OnClick", function()
		B().type = CycleVal(CC_TYPE_ORDER, B().type or "spell")
		row.typ.txt:SetText(CC_TYPE_LABEL[B().type])
		RG:Update()
	end)

	row.val = CreateFrame("EditBox", nil, row)
	row.val:SetPoint("LEFT", row.typ, "RIGHT", 6, 0)
	row.val:SetSize(150, 20)
	row.val:SetAutoFocus(false)
	row.val:SetText(B().value or "")
	row.val:SetFontObject("GameFontHighlightSmall")
	S:SkinEditBox(row.val)
	row.val:SetScript("OnEnterPressed", function(e) B().value = strtrim(e:GetText()) e:ClearFocus() row.pick.txt:SetText(row.pick:Label()) RG:Update() end)
	row.val:SetScript("OnEditFocusLost", function(e) B().value = strtrim(e:GetText()) row.pick.txt:SetText(row.pick:Label()) RG:Update() end)

	-- class spell picker: cycles keywords + every known class heal spell
	row.pick = CycleBtn(row, 110, "?")
	row.pick:SetPoint("LEFT", row.val, "RIGHT", 4, 0)
	function row.pick:Label()
		local v = B().value or ""
		if v == "" then return "…" end
		return (v:len() > 18) and (v:sub(1, 17) .. "…") or v
	end
	row.pick.txt:SetText(row.pick:Label())
	row.pick:SetScript("OnClick", function()
		B().value = CycleVal(ClassSpellList(), B().value or "")
		row.val:SetText(B().value)
		row.pick.txt:SetText(row.pick:Label())
		RG:Update()
	end)
	row.pick:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Pick class spell"] or "Pick class spell")
		GameTooltip:Show()
	end)
	row.pick:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.del = CreateFrame("Button", nil, row)
	row.del:SetPoint("LEFT", row.pick, "RIGHT", 4, 0)
	row.del:SetSize(18, 18)
	S:SkinButton(row.del)
	local dtxt = S:FontString(row.del, 10, "OUTLINE")
	dtxt:SetPoint("CENTER")
	dtxt:SetText("x")
	row.del:SetScript("OnClick", function()
		tremove(S.db.profile.raidgrid.clickCast.bindings, idx)
		RG:RefreshConfig() RG:Update()
	end)
	return row
end

local function OptRow(parent, key, label, order, labels, y)
	local t = S:FontString(parent, 10)
	t:SetPoint("TOPLEFT", 16, y)
	t:SetText(label)
	local b = CycleBtn(parent, 110, labels[S.db.profile.raidgrid[key]] or S.db.profile.raidgrid[key])
	b:SetPoint("LEFT", t, "RIGHT", 10, 0)
	b:SetScript("OnClick", function()
		S.db.profile.raidgrid[key] = CycleVal(order, S.db.profile.raidgrid[key])
		b.txt:SetText(labels[S.db.profile.raidgrid[key]] or S.db.profile.raidgrid[key])
		RG:Update()
	end)
	return b
end

function RG:BuildConfig()
	if self.cfg then return self.cfg end
	local f = CreateFrame("Frame", "SentinelUIRaidGridConfig", UIParent, S.BackdropTemplate)
	f:SetSize(560, 660)
	f:SetPoint("CENTER")
	f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true) f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SkinFrame(f, "Default")
	local title = S:FontString(f, 13, "OUTLINE")
	title:SetPoint("TOP", 0, -10)
	title:SetText("|cff" .. S.accentHex .. "HealGrid|r  " .. L["Settings"])
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	S:SkinCloseButton(close)
	close:SetScript("OnClick", function() f:Hide() end)
	tinsert(UISpecialFrames, "SentinelUIRaidGridConfig")

	-- left: toggles ----------------------------------------------------------
	local left = CreateFrame("Frame", nil, f)
	left:SetPoint("TOPLEFT", 8, -34)
	left:SetSize(240, 354)
	local lh = S:FontString(left, 11, "OUTLINE")
	lh:SetPoint("TOPLEFT", 0, 0)
	lh:SetText("|cff" .. S.accentHex .. (L["Show"] or "Show") .. "|r")
	local toggles = {
		{ "showWhenSolo", L["Show When Solo"] }, { "showPower", L["Show Power"] },
		{ "showDebuffs", L["Show Debuffs"] }, { "showHots", L["Show Hots"] },
		{ "showIncHeal", L["Show Inc Heal"] }, { "showAbsorb", L["Show Absorb"] },
		{ "buffWatch", L["Buff Watch"] }, { "showReadyCheck", L["Show Ready Check"] },
		{ "targetHighlight", L["Target Highlight"] }, { "unitTooltip", L["Unit Tooltip"] },
		{ "rangeFade", L["Range Fade"] }, { "showDeficit", L["Show Deficit"] },
		{ "rezOnDead", L["Rez On Dead"] },
		{ "hideEmpty", L["Hide Empty"] }, { "lockFrame", L["Lock Frame"] },
	}
	for i, t in ipairs(toggles) do CheckRow(left, t[1], t[2], -18 - (i - 1) * 24) end

	-- right: sliders -----------------------------------------------------------
	local right = CreateFrame("Frame", nil, f)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
	right:SetSize(300, 200)
	local rh = S:FontString(right, 11, "OUTLINE")
	rh:SetPoint("TOPLEFT", 0, 0)
	rh:SetText("|cff" .. S.accentHex .. (L["Layout"] or "Layout") .. "|r")
	SliderRow(right, "barW", L["Bar W"], 24, 200, 1, -34)
	SliderRow(right, "barH", L["Bar H"], 12, 80, 1, -66)
	SliderRow(right, "spacing", L["Spacing"], 0, 20, 1, -98)
	SliderRow(right, "groupSpacing", L["Group Spacing"], 0, 40, 1, -130)
	SliderRow(right, "scale", L["Scale"], 0.4, 2, 0.05, -162, true)
	OptRow(right, "growthX", L["Groups grow"], { "RIGHT", "LEFT" },
		{ RIGHT = L["Right"], LEFT = L["Left"] }, -196)
	OptRow(right, "growthY", L["Cells grow"], { "DOWN", "UP" },
		{ DOWN = L["Down"], UP = L["Up"] }, -222)
	OptRow(right, "sortMethod", L["Sort by"], { "INDEX", "NAME" },
		{ INDEX = L["Index"], NAME = L["Name"] }, -248)
	OptRow(right, "healthMode", L["Health color"], { "CLASS", "GRADIENT" },
		{ CLASS = L["Class colored bar"], GRADIENT = L["Health gradient (green to red)"] }, -274)

	-- bottom: click-cast bindings ----------------------------------------------
	local bot = CreateFrame("Frame", nil, f)
	bot:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -6)
	bot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
	local bh = S:FontString(bot, 11, "OUTLINE")
	bh:SetPoint("TOPLEFT", 0, 0)
	bh:SetText("|cff" .. S.accentHex .. L["Click Cast"] .. "|r  |cff888888" .. (L["mod · button · action · spell (click to cycle, 'heal'/'dispel' = class spells)"] or "") .. "|r")
	f.bindRows = CreateFrame("Frame", nil, bot)
	f.bindRows:SetPoint("TOPLEFT", 0, -18)
	f.bindRows:SetSize(540, 240)
	local add = CreateFrame("Button", nil, bot)
	add:SetSize(110, 20)
	add:SetPoint("BOTTOMLEFT", 0, 0)
	S:SkinButton(add)
	local addTxt = S:FontString(add, 10, "OUTLINE")
	addTxt:SetPoint("CENTER")
	addTxt:SetText(L["Add Binding"])
	add:SetScript("OnClick", function()
		tinsert(S.db.profile.raidgrid.clickCast.bindings, { button = "3", mod = "none", type = "spell", value = "" })
		RG:RefreshConfig() RG:Update()
	end)
	f:Hide()
	self.cfg = f
	return f
end

function RG:RefreshConfig()
	local f = self.cfg
	if not f then return end
	for _, r in ipairs(f._brows or {}) do r:Hide() end
	wipe(f._brows or {})
	f._brows = f._brows or {}
	local binds = S.db.profile.raidgrid.clickCast.bindings
	local maxShow = 8
	for i, _ in ipairs(binds) do
		if i > maxShow then break end
		local row = BindingRow(f.bindRows, i, -(i - 1) * 26)
		f._brows[i] = row
		row:Show()
	end
end

function RG:ToggleConfig()
	local f = self:BuildConfig()
	if f:IsShown() then f:Hide() else self:RefreshConfig() f:Show() end
end

-- diagnostic: dump every visible region >60px wide near the grid so we can
-- identify stray bars in-game via /suirg scan
local function DumpRegions(obj, depth, tag)
	if depth > 5 or not obj then return end
	for i = 1, obj.GetNumRegions and select("#", obj:GetRegions()) or 0 do
		local r = select(i, obj:GetRegions())
		if r and r.IsShown and r:IsShown() then
			local w = r.GetWidth and r:GetWidth() or 0
			if w and w > 60 then
				local vr, vg, vb = r.GetVertexColor and r:GetVertexColor()
				S:Print(format("%s[%s] %s w=%.0f h=%.0f col=%s",
					strrep("  ", depth), tag, tostring(r:GetObjectType()),
					w, r.GetHeight and r:GetHeight() or 0,
					vr and format("%.2f/%.2f/%.2f", vr, vg or 0, vb or 0) or "-"))
			end
		end
	end
	for _, child in ipairs({ obj.GetChildren and obj:GetChildren() }) do
		if child.IsShown and child:IsShown() then DumpRegions(child, depth + 1, tag) end
	end
end

function RG:ScanRegions()
	local f = self.frame
	if not f then S:Print("HealGrid: no frame") return end
	S:Print("HealGrid regions >60px wide:")
	DumpRegions(f, 0, "f")
	for g = 1, MAX_GROUPS do for r = 1, MAX_ROWS do
		local c = self.cells[g][r]
		if c:IsShown() then DumpRegions(c, 1, "cell" .. g .. "," .. r) end
	end end
end

-- driver ---------------------------------------------------------------------
local function Tick()
	if not RG.frame or not RG.frame:IsShown() then return end
	local ok, err = pcall(RG.Refresh, RG)
	if not ok and not RG.tickErrLogged then
		RG.tickErrLogged = true
		S:LogError(tostring(err), "RaidGrid:Refresh")
	end
end

function RG:Toggle()
	local ok, err = pcall(function()
		self:BuildFrame()
		if self.frame:IsShown() then
			self.frame:Hide()
			if ticker then ticker:Cancel() ticker = nil end
		else
			self.frame:Show()
			if InCombatLockdown() then
				S:RunOutOfCombat(self.Layout, self)
				S:RunOutOfCombat(self.ApplyClicks, self)
			else
				self:Layout()
				self:ApplyClicks()
			end
			self:Refresh()
			if not ticker then ticker = C_Timer.NewTicker(0.2, Tick) end
		end
	end)
	if not ok then
		S:LogError(tostring(err), "RaidGrid:Toggle")
		S:Print("|cffff5555RaidGrid: error logged — check /sui log|r")
	end
end

function RG:GROUP_ROSTER_UPDATE()
	if self.frame and self.frame:IsShown() then self:Refresh() end
end

function RG:READY_CHECK_FINISHED()
	if self.frame and self.frame:IsShown() then self:Refresh() end
end

function RG:Update()
	if self.frame and self.frame:IsShown() then
		if InCombatLockdown() then
			-- Layout moves/sizes protected cells — defer everything to combat end
			S:RunOutOfCombat(self.Layout, self)
			S:RunOutOfCombat(self.ApplyClicks, self)
		else
			self:Layout()
			self:ApplyClicks()
		end
		self:Refresh()
	end
end

function RG:Initialize()
	self.db = S.db.profile.raidgrid
	-- migrate any previous default binding set (dispel or plain menu on right
	-- click) to heal-on-right-click; only touches uncustomized profiles
	local b = self.db.clickCast and self.db.clickCast.bindings
	if b and #b == 2 and b[1].button == "1" and b[1].type == "target" and b[2].button == "2"
		and ((b[2].type == "spell" and b[2].value == "dispel") or b[2].type == "togglemenu")
	then
		b[2] = { button = "2", mod = "none", type = "spell", value = "heal" }
	end
	if self.db.enable == false then return end

	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "raidgrid", glyph = "HG",
		store = self.private.minimap, angle = 330,
		onLeft = function() RG:Toggle() end,
		onRight = function() RG:ToggleConfig() end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. L["Heal Grid"])
			GameTooltip:AddLine(L["Left-click: toggle  |  Right-click: options  |  Drag: move"], 1, 1, 1)
		end,
	})

	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("READY_CHECK_FINISHED")
	SlashCmdList.SENTINELUIRAIDGRID = function(arg)
		arg = strtrim(arg or ""):lower()
		if arg == "options" or arg == "config" or arg == "opt" then
			RG:ToggleConfig()
		elseif arg == "scan" then
			RG:ScanRegions()
		else
			RG:Toggle()
		end
	end
	SLASH_SENTINELUIRAIDGRID1 = "/suirg"
	SLASH_SENTINELUIRAIDGRID2 = "/suiheal"
	SLASH_SENTINELUIRAIDGRID3 = "/suihg"
end
