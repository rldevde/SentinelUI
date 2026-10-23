-- Decurse: vertical dispel strip like RL Decurse — a column of small unit
-- squares (5 per column, next column to the right), colored by debuff type.
-- Left-click casts the primary dispel, right-click the secondary (e.g.
-- priest: magic / disease). The strip shows all group members; bright =
-- in range & dispellable debuff, green = in range & clean, grey = OOR.
local _, ns = ...
local S = ns.S
local L = S.L
local DC = S:NewModule("Decurse")
local wipe, sort, tinsert = wipe, sort, tinsert
local ipairs, pairs, select = ipairs, pairs, select
local unpack = unpack
local floor = floor
local CreateFrame = CreateFrame
local UnitClass, UnitExists, UnitName = UnitClass, UnitExists, UnitName
local IsInRaid, IsInGroup, InCombatLockdown = IsInRaid, IsInGroup, InCombatLockdown
local GetSpellInfo = S.GetSpellInfo
local IsSpellKnown, IsPlayerSpell = S.IsSpellKnown, IsPlayerSpell
local IsSpellInRange = IsSpellInRange
local GetRaidRosterInfo = GetRaidRosterInfo

-- per-class dispel candidates: primary (left-click) / secondary (right-click)
-- and which debuff types each spell removes. Ordered by preference.
local DISPEL_PRIMARY = {
	PALADIN = { 4987, 1152 },               -- Cleanse, Purify
	PRIEST = { 527, 213634 },               -- Dispel Magic, Purify(retail)
	SHAMAN = { 526, 51886, 77130 },         -- Cure Toxins, Cleanse Spirit, Purify Spirit
	DRUID = { 88423, 8946, 2893 },          -- Nature's Cure, Cure Poison, Abolish Poison
	MAGE = { 475 },                         -- Remove Curse
	MONK = { 115450, 218164 },              -- Detox
	EVOKER = { 374227, 360823 },            -- Naturalize / Cauterizing
}
local DISPEL_SECONDARY = {
	PALADIN = { 1152 },                     -- Purify (fallback)
	PRIEST = { 552, 528 },                  -- Abolish Disease, Cure Disease
	SHAMAN = { 2870 },                      -- Cure Disease
	DRUID = { 2782 },                       -- Remove Curse
	MAGE = {},
	MONK = { 218164 },
	EVOKER = {},
}
local SPELL_TYPES = {
	[4987] = { Magic = 1, Poison = 1, Disease = 1 },
	[1152] = { Poison = 1, Disease = 1 },
	[527] = { Magic = 1 },
	[213634] = { Disease = 1 },
	[552] = { Disease = 1 },
	[528] = { Disease = 1 },
	[526] = { Poison = 1, Disease = 1 },
	[2870] = { Disease = 1 },
	[51886] = { Curse = 1, Poison = 1, Disease = 1 },
	[77130] = { Curse = 1, Poison = 1, Disease = 1, Magic = 1 },
	[88423] = { Magic = 1, Poison = 1, Curse = 1 },
	[8946] = { Poison = 1 },
	[2893] = { Poison = 1 },
	[2782] = { Curse = 1 },
	[475] = { Curse = 1 },
	[115450] = { Poison = 1, Disease = 1, Magic = 1 },
	[218164] = { Poison = 1, Disease = 1 },
	[374227] = { Curse = 1, Poison = 1, Disease = 1 },
	[360823] = { Magic = 1, Poison = 1, Disease = 1 },
}
-- 526 is "Cure Toxins" (poison+disease) on Classic Era/SoD but plain
-- "Cure Poison" on TBC+ where disease is a separate spell (2870)
if not S.isClassic then SPELL_TYPES[526] = { Poison = 1 } end

-- RLCurse colors: custom debuff palette (in-range / out-of-range)
local DEBUFF_COLORS = {
	Magic = { inRange = { 0.2, 0.4, 0.9, 1 }, outOfRange = { 0.1, 0.2, 0.5, 0.9 } },
	Curse = { inRange = { 0.7, 0.2, 0.9, 1 }, outOfRange = { 0.4, 0.1, 0.5, 0.9 } },
	Poison = { inRange = { 0.0, 0.9, 0.9, 1 }, outOfRange = { 0.0, 0.5, 0.5, 0.9 } },
	Disease = { inRange = { 0.9, 0.6, 0.0, 1 }, outOfRange = { 0.6, 0.4, 0.0, 0.9 } },
}
local CLEAN_IN_RANGE = { 0.1, 0.6, 0.1, 0.9 }
local CLEAN_OOR = { 0.3, 0.3, 0.3, 0.9 }

local function SpellUsable(id)
	if not GetSpellInfo(id) then return false end
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	if IsSpellKnown and IsSpellKnown(id) then return true end
	return false
end

DC.dispellableTypes = {}

-- resolve primary/secondary spell names + the set of removable debuff types
local function RefreshSpells()
	local _, class = UnitClass("player")
	DC.spell1, DC.spell2 = nil, nil
	wipe(DC.dispellableTypes)
	local prim = DISPEL_PRIMARY[class]
	if prim then
		for _, id in ipairs(prim) do
			if SpellUsable(id) then
				local name = GetSpellInfo(id)
				if name then DC.spell1 = name end
				local t = SPELL_TYPES[id]
				if t then for ty in pairs(t) do DC.dispellableTypes[ty] = true end end
				break
			end
		end
	end
	local sec = DISPEL_SECONDARY[class]
	if sec then
		for _, id in ipairs(sec) do
			if SpellUsable(id) then
				local name = GetSpellInfo(id)
				if name and name ~= DC.spell1 then DC.spell2 = name end
				local t = SPELL_TYPES[id]
				if t then for ty in pairs(t) do DC.dispellableTypes[ty] = true end end
				break
			end
		end
	end
	DC.anyUsable = DC.spell1 ~= nil or DC.spell2 ~= nil
end

local function FirstDispellable(unit)
	for i = 1, 40 do
		local a = S.GetAura(unit, i, "HARMFUL")
		if not a or not a.name then break end
		local t = a.dispelName
		if t and DC.dispellableTypes[t] then return t end
	end
	return nil
end

local function InDispelRange(unit)
	if not unit or not UnitExists(unit) then return false end
	local spell = DC.spell1 or DC.spell2
	if spell and IsSpellInRange then
		local r = IsSpellInRange(spell, unit)
		if r == 1 then return true end
		if r == 0 then return false end
	end
	return true
end

local COLGAP, ROWGAP, PER_COL = 5, 2, 5
local function UnitSize() return (DC.db and DC.db.unitSize) or 18 end

-- RLCurse look: ChatFrameBackground fill + tooltip border, blue edge
local BUTTON_BACKDROP = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 8, edgeSize = 12,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local BORDER_R, BORDER_G, BORDER_B = 0.15, 0.45, 0.9

local function Cell(f, i)
	local b = f.cells[i]
	if b then return b end
	b = CreateFrame("Button", nil, f, "SecureActionButtonTemplate" .. (S.BackdropTemplate and ("," .. S.BackdropTemplate) or ""))
	b:SetBackdrop(BUTTON_BACKDROP)
	b:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)
	b:SetBackdropColor(0.08, 0.36, 0.08, 0.9)
	b:RegisterForClicks("AnyDown")
	local gloss = b:CreateTexture(nil, "OVERLAY")
	gloss:SetTexture("Interface\\Buttons\\WHITE8x8")
	gloss:SetPoint("TOPLEFT", 2, -2)
	gloss:SetPoint("TOPRIGHT", -2, -2)
	gloss:SetVertexColor(1, 1, 1, 0.16)
	b.gloss = gloss
	b:SetScript("OnEnter", function(s2)
		if not GameTooltip or not s2.unit or not UnitExists(s2.unit) then return end
		GameTooltip:SetOwner(s2, "ANCHOR_RIGHT")
		GameTooltip:SetUnit(s2.unit)
		for j = 1, 10 do
			local a = S.GetAura(s2.unit, j, "HARMFUL")
			if not a or not a.name then break end
			local t = a.dispelName
			if t and DC.dispellableTypes[t] then
				local c = DEBUFF_COLORS[t]
				if c then GameTooltip:AddLine(a.name, c.inRange[1], c.inRange[2], c.inRange[3]) end
			end
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	f.cells[i] = b
	return b
end

local function SetCellColor(b, r, g, bl, a)
	b:SetBackdropColor(r, g, bl, a)
end

-- RLCurse one-button mode: a single 48x48 button that always targets the
-- first group member with a removable debuff ("Safe" when nobody needs one)
local function OneButton(f)
	local b = f.oneBtn
	if b then return b end
	b = CreateFrame("Button", nil, f, "SecureActionButtonTemplate" .. (S.BackdropTemplate and ("," .. S.BackdropTemplate) or ""))
	b:SetSize(48, 48)
	b:SetBackdrop(BUTTON_BACKDROP)
	b:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)
	b:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
	b:RegisterForClicks("AnyDown")
	local gloss = b:CreateTexture(nil, "OVERLAY")
	gloss:SetTexture("Interface\\Buttons\\WHITE8x8")
	gloss:SetPoint("TOPLEFT", 3, -3)
	gloss:SetPoint("TOPRIGHT", -3, -3)
	gloss:SetHeight(24)
	gloss:SetVertexColor(1, 1, 1, 0.18)
	b.label = S:FontString(b, 14, "OUTLINE")
	b.label:SetPoint("CENTER")
	f.oneBtn = b
	return b
end

local function BindDispels(b, unit)
	b:SetAttribute("unit", unit)
	if DC.spell1 then
		b:SetAttribute("type1", "spell")
		b:SetAttribute("spell1", DC.spell1)
	else
		b:SetAttribute("type1", nil)
	end
	if DC.spell2 then
		b:SetAttribute("type2", "spell")
		b:SetAttribute("spell2", DC.spell2)
	else
		b:SetAttribute("type2", nil)
	end
end

function DC:BuildFrame()
	if self.frame then return self.frame end
	-- like RLCurse: the main frame itself is invisible; only the yellow drag
	-- handle and the cluster of unit squares are visible
	local f = CreateFrame("Frame", "SentinelUIDecurse", UIParent)
	f:SetSize(40, 200)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(false)
	f.cells = {}
	self.frame = f
	S:CreateMover(f, "decurse", L["Decurse"], { "CENTER", "UIParent", "CENTER", -560, 0 }, "general")
	-- the tiny 14px corner square was nearly impossible to grab; the whole
	-- top strip of the frame is the drag handle now
	local handle = CreateFrame("Button", nil, f, S.BackdropTemplate)
	handle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	handle:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	handle:SetHeight(18)
	handle:SetBackdrop(BUTTON_BACKDROP)
	handle:SetBackdropColor(0.2, 0.2, 0.2, 0.6)
	handle:SetBackdropBorderColor(1, 1, 0, 0.8)
	handle:EnableMouse(true)
	S:AttachMoverDrag(handle, "decurse")
	f.handle = handle
	return f
end

-- visual refresh: colors only, safe in combat
local function UpdateColors()
	local f = DC.frame
	if not f then return end
	if f.mode == "onebutton" then
		local b = f.oneBtn
		if not b then return end
		local target, dtype
		for _, u in ipairs(DC.scanUnits or {}) do
			if UnitExists(u) then
				local t = FirstDispellable(u)
				if t then target, dtype = u, t break end
			end
		end
		if target then
			local name = UnitName(target) or "?"
			b.label:SetText(name)
			local c = DEBUFF_COLORS[dtype]
			local col = InDispelRange(target) and c.inRange or c.outOfRange
			b:SetBackdropColor(col[1], col[2], col[3], col[4])
			if b:GetAttribute("unit") ~= target then
				if InCombatLockdown() then
					b.label:SetText(name .. "\n(Combat)")
				else
					BindDispels(b, target)
				end
			end
		else
			b.label:SetText("Safe")
			b:SetBackdropColor(0.1, 0.6, 0.1, 0.9)
			if not InCombatLockdown() and b:GetAttribute("unit") then
				b:SetAttribute("unit", nil)
			end
		end
		return
	end
	for _, b in ipairs(f.cells) do
		if b:IsShown() and b.unit and UnitExists(b.unit) then
			local t = FirstDispellable(b.unit)
			local inRange = InDispelRange(b.unit)
			if t then
				local c = DEBUFF_COLORS[t]
				local col = inRange and c.inRange or c.outOfRange
				SetCellColor(b, col[1], col[2], col[3], col[4])
			else
				local col = inRange and CLEAN_IN_RANGE or CLEAN_OOR
				SetCellColor(b, col[1], col[2], col[3], col[4])
			end
		end
	end
end

-- full rebuild: button binding + layout, out of combat only
local function Rebuild()
	local f = DC.frame
	if not f then return end
	if InCombatLockdown() then
		S:RunOutOfCombat(Rebuild)
		return
	end
	if not DC.anyUsable or (DC.db and DC.db.enable == false) then
		f:Hide()
		return
	end
	-- roster: raid sorted by subgroup, else party incl. player, else solo
	local units = {}
	if IsInRaid() then
		for i = 1, 40 do
			local u = "raid" .. i
			if UnitExists(u) then
				local _, _, subgroup = GetRaidRosterInfo(i)
				units[#units + 1] = { unit = u, g = subgroup or 9, o = i }
			end
		end
		sort(units, function(a, b)
			if a.g ~= b.g then return a.g < b.g end
			return a.o < b.o
		end)
	elseif IsInGroup() then
		units[#units + 1] = { unit = "player" }
		for i = 1, 4 do
			local u = "party" .. i
			if UnitExists(u) then units[#units + 1] = { unit = u } end
		end
	else
		units[#units + 1] = { unit = "player" }
	end
	local n = #units
	DC.scanUnits = DC.scanUnits or {}
	wipe(DC.scanUnits)
	for i = 1, n do DC.scanUnits[i] = units[i].unit end
	f.mode = (DC.db and DC.db.mode) or "grid"
	if f.mode == "onebutton" then
		for _, c in ipairs(f.cells) do c:Hide() c.unit = nil end
		local b = OneButton(f)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -32)
		BindDispels(b, nil)
		b:Show()
		f:SetSize(68, 90)
		f:Show()
		UpdateColors()
		return
	end
	if f.oneBtn then f.oneBtn:Hide() end
	local sz = UnitSize()
	for i = 1, n do
		local u = units[i].unit
		local b = Cell(f, i)
		b.unit = u
		-- RLCurse semantics: left-click = primary dispel, right-click = secondary
		BindDispels(b, u)
		b:SetSize(sz, sz)
		b.gloss:SetHeight(sz * 0.45)
		b:ClearAllPoints()
		local col = floor((i - 1) / PER_COL)
		local row = (i - 1) % PER_COL
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 10 + col * (sz + COLGAP), -32 - row * (sz + ROWGAP))
		b:Show()
	end
	for i = n + 1, #f.cells do
		f.cells[i]:Hide()
		f.cells[i].unit = nil
	end
	local cols = floor((n - 1) / PER_COL) + 1
	local rows = math.min(n, PER_COL)
	f:SetSize(20 + cols * (sz + COLGAP), 42 + rows * (sz + ROWGAP))
	f:Show()
	UpdateColors()
end

-- minimap button: left-click toggles the strip (like RLCurse's button)
function DC:UpdateMinimap()
	local d = S.private.decurse
	if not d or d.minimapShow == false or not self.anyUsable or (self.db and self.db.enable == false) then
		if self.minimapBtn then self.minimapBtn:Hide() end
		return
	end
	if not self.minimapBtn then
		self.minimapBtn = S:CreateMinimapButton({
			name = "decurse", glyph = "DC", store = d, angle = -55,
			onLeft = function()
				local f = DC.frame
				if not f then return end
				if f:IsShown() then f:Hide() else Rebuild() end
			end,
			tooltip = function()
				GameTooltip:AddLine("SentinelUI " .. L["Decurse"])
				GameTooltip:AddLine(L["Left-click: show / hide  |  Drag: move"], 1, 1, 1)
			end,
		})
	end
	self.minimapBtn:Show()
	self.minimapBtn:UpdatePosition()
end

function DC:OnAura(_, unit)
	if unit == "player" or (unit and (unit:match("^party%d") or unit:match("^raid%d"))) then
		UpdateColors()
	end
end

function DC:Initialize()
	self.db = S.db.profile.decurse
	RefreshSpells()
	self:RegisterEvent("UNIT_AURA", "OnAura")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupChanged")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnGroupChanged")
	self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnGroupChanged")
	local f = self:BuildFrame()
	self:UpdateMinimap()
	-- range re-check like RLCurse: cheap color pass every 0.2s
	f:SetScript("OnUpdate", function(_, e)
		self.el = (self.el or 0) + e
		if self.el < 0.2 then return end
		self.el = 0
		UpdateColors()
	end)
	Rebuild()
end

function DC:OnGroupChanged()
	Rebuild()
end

function DC:OnSpellsChanged()
	RefreshSpells()
	Rebuild()
end

function DC:Update()
	self.db = S.db.profile.decurse
	RefreshSpells()
	self:UpdateMinimap()
	Rebuild()
end
