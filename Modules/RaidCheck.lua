-- Raid/group check: shows at a glance whether every member is buffed,
-- fed, flasked and has a weapon enchant. Aura based for remote members;
-- weapon enchants are reported via an internal addon channel since the
-- API only exposes them for the local player.
local _, ns = ...
local S = ns.S
local L = S.L
local RC = S:NewModule("RaidCheck", "raidcheck")

local _G = _G
local ipairs, pairs, wipe, tinsert, sort = ipairs, pairs, wipe, table.insert, table.sort
local format, strfind, strmatch, gmatch, strlower = string.format, string.find, string.match, string.gmatch, string.lower
local tonumber, min, max, floor = tonumber, math.min, math.max, math.floor
local GetTime, GetWeaponEnchantInfo = GetTime, GetWeaponEnchantInfo
local IsInGroup, IsInRaid = IsInGroup, IsInRaid
local GetNumGroupMembers, UnitName, UnitClass, UnitExists = GetNumGroupMembers, UnitName, UnitClass, UnitExists
local UnitIsPlayer, UnitPowerType, Ambiguate = UnitIsPlayer, UnitPowerType, Ambiguate
local GetInventoryItemLink, GetItemInfoInstant = GetInventoryItemLink, GetItemInfoInstant
local CanInspect, CheckInteractDistance, NotifyInspect = CanInspect, CheckInteractDistance, NotifyInspect
local SendChatMessage = SendChatMessage
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip

local PREFIX = "SUIRC"
local ROW_H, NAME_W, CELL, MAX_VIS = 20, 130, 24, 16

local members = {}        -- { unit, name, class }
local auraSets = {}       -- name -> { [auraname]=true, list={} }
local remoteWE = {}       -- name -> { mh=bool, oh=bool, t=time }
local inspectData = {}    -- name -> { enchMiss=N, enchItems={...}, gemsEmpty=N, t=time }
local inspectQueue, inspectUnit = {}, nil
local providers = {}      -- class -> true
local auraPending = false
local INSPECT_TTL = 120

-- spell id tables resolved to localized aura names at runtime
local function NameSet(ids)
	local t = {}
	for _, id in ipairs(ids) do
		local n = S.GetSpellInfo(id)
		if n then t[n] = true end
	end
	return t
end

local FORT_N, SPIRIT_N, SHADOW_N, INT_N, MOTW_N, FOOD_N, BLESS_KW, FLASK_KW, ELIXIR_KW, WB_N

local function BuildSets()
	FORT_N = NameSet({ 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564, 25362, 48161, 48162 })
	SPIRIT_N = NameSet({ 14752, 14818, 14819, 27841, 25312, 27681, 32999, 48073, 48074 })
	SHADOW_N = NameSet({ 976, 10957, 10958, 27683, 39374, 48169, 48170 })
	INT_N = NameSet({ 1459, 1460, 1461, 10156, 10157, 23028, 27127, 42995, 43002, 61024 })
	MOTW_N = NameSet({ 1126, 5232, 5234, 6756, 8907, 9884, 9885, 21849, 21850, 26991, 48469, 48470 })

	-- blessings: keyword matching catches every blessing incl. greater ones
	BLESS_KW = { Blessing = true, Segen = true }
	local bn = S.GetSpellInfo(19740)
	if bn then for w in gmatch(bn, "%S+") do BLESS_KW[w] = true end end
	bn = S.GetSpellInfo(25894)
	if bn then for w in gmatch(bn, "%S+") do BLESS_KW[w] = true end end

	-- food: the "well fed" aura name is shared, spell ids differ per food
	FOOD_N = NameSet({
		19705, 19706, 19708, 19709, 19710, 19711, 25660, 25661, 33254, 33256, 33257, 33259,
		33261, 33263, 33264, 33265, 33268, 35272, 43706, 43722, 44166, 45619, 46899, 53284,
		57085, 57325, 57327, 57329, 57332, 57334, 57356, 57358, 57360, 57363, 57365, 57367,
		57371, 57373, 57397, 57399, 57435, 59230, 59232, 64054, 64368, 65414, 65415, 65416,
		65417, 65418, 87545, 87546, 87547, 87548, 87549, 87550, 87551, 87552, 87554, 87555,
		87556, 87558, 87559, 87560, 87561, 87562, 87563, 87564, 87955, 87956, 87957, 87958,
	})
	for _, n in ipairs({ "Well Fed", "Gesättigt", "Bien nourri", "Saciado", "Saziato", "Сытость" }) do FOOD_N[n] = true end

	-- flask/elixir: substring matching on the aura name (localized keywords +
	-- dynamically resolved first words catch oddballs like "Destillierte Weisheit")
	FLASK_KW = { flask = true, ["fläschchen"] = true }
	for _, id in ipairs({ 28518, 17627, 28540, 53752, 53749, 53751, 53755, 54212, 28520, 28521 }) do
		local n = S.GetSpellInfo(id)
		if n then local w = strmatch(n, "%S+") if w then FLASK_KW[strlower(w)] = true end end
	end
	-- elixirs & buff potions: battle+guardian coverage needs 2+ distinct auras;
	-- "Trank" catches potions with persistent buffs (e.g. Trollbluttrank)
	ELIXIR_KW = { elixir = true, elixier = true, trank = true, potion = true }
	for _, id in ipairs({ 39625, 39626, 39627, 33721, 17538, 54452, 53746, 53747, 53748, 60341 }) do
		local n = S.GetSpellInfo(id)
		if n then local w = strmatch(n, "%S+") if w then ELIXIR_KW[strlower(w)] = true end end
	end

	-- world buffs (classic era raiding)
	WB_N = NameSet({
		22888, 24425, 15366, 23735, 23736, 23737, 23738, 23766, 23767, 23768, 23769,
		22817, 22818, 22820, 16609, 46017, 19506, 22888, 28126, 28127, 28128, 28129, 28130,
	})
end

local function HasName(set, names)
	for n in pairs(names) do if set[n] then return true end end
end

local function KwMatch(name, kws)
	local lname = strlower(name)
	for kw in pairs(kws) do
		if strfind(lname, kw, 1, true) then return true end
	end
end

local function HasKeyword(list, kws)
	for _, n in ipairs(list) do
		if KwMatch(n, kws) then return true end
	end
end

local function CountKeyword(list, kws)
	local seen, n = {}, 0
	for _, a in ipairs(list) do
		if KwMatch(a, kws) and not seen[a] then seen[a] = true n = n + 1 end
	end
	return n
end

local function HasBlessing(list)
	for _, n in ipairs(list) do
		for kw in pairs(BLESS_KW) do
			if strfind(n, kw, 1, true) then return true end
		end
	end
end

-- checks ------------------------------------------------------------------
local CHECKS = {
	{ key = "bless", label = L["Blessing"], iconId = 19740, provider = "PALADIN",
		eval = function(set, list) return HasBlessing(list) end },
	{ key = "motw", label = L["Mark of the Wild"], iconId = 1126, provider = "DRUID",
		eval = function(set) return HasName(set, MOTW_N) end },
	{ key = "int", label = L["Arcane Intellect"], iconId = 1459, provider = "MAGE", manaOnly = true,
		eval = function(set) return HasName(set, INT_N) end },
	{ key = "fort", label = L["Fortitude"], iconId = 1243, provider = "PRIEST",
		eval = function(set) return HasName(set, FORT_N) end },
	{ key = "spirit", label = L["Divine Spirit"], iconId = 14752, provider = "PRIEST", manaOnly = true,
		eval = function(set) return HasName(set, SPIRIT_N) end },
	{ key = "shadow", label = L["Shadow Protection"], iconId = 976, provider = "PRIEST",
		eval = function(set) return HasName(set, SHADOW_N) end },
	{ key = "food", label = L["Food"], iconId = 19705, dbKey = "showFood",
		eval = function(set) return HasName(set, FOOD_N) end },
	{ key = "flask", label = L["Flask/Elixir"], iconId = 28518, dbKey = "showFlask",
		eval = function(set, list)
			if HasKeyword(list, FLASK_KW) then return true end
			local elix = CountKeyword(list, ELIXIR_KW)
			if elix >= 2 then return true end
			if elix == 1 then return "warn" end -- only one elixir: battle+guardian not covered
			return false
		end },
	{ key = "wb", label = L["World buff"], iconId = 22888, dbKey = "showWorld",
		eval = function(set) return HasName(set, WB_N) end },
	{ key = "ench", label = L["Gear enchanted"], icon = "Interface\\Icons\\Spell_Holy_GreaterHeal", dbKey = "showEnch",
		eval = nil }, -- needs inspection, handled separately
	{ key = "gems", label = L["Gems socketed"], icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_01", dbKey = "showGems",
		eval = nil }, -- needs inspection, handled separately
	{ key = "wep", label = L["Weapon enchant"], icon = "Interface\\Icons\\INV_Stone_SharpeningStone_01", dbKey = "showWeapon",
		eval = nil }, -- handled separately (weapon enchants are not auras)
}

local function WeaponEnchant(m)
	if m.unit == "player" then
		if not GetWeaponEnchantInfo then return "na" end
		local mh = GetWeaponEnchantInfo()
		return mh and true or false
	end
	local r = remoteWE[m.name]
	if not r then return "?" end
	return r.mh and true or false
end

-- equipment inspection ------------------------------------------------------
-- slots that can carry an enchant on this client flavor
local ENCH_SLOTS = { 1, 3, 5, 7, 8, 9, 10, 15, 16 } -- head, shoulder, chest, legs, feet, wrist, hands, back, main hand
if S.isWrath or S.isCata or S.isMists or S.isRetail then ENCH_SLOTS[#ENCH_SLOTS + 1] = 6 end -- belt buckle
-- ranged slot: only guns/bows/crossbows take scopes (weapon subclasses 2,3,18)
local RANGED_OK = { [2] = true, [3] = true, [18] = true }

local EMPTY_SOCK = {}
for k, v in pairs(_G) do
	if type(v) == "string" and strfind(k, "^EMPTY_SOCKET") then EMPTY_SOCK[v] = true end
end
local sockTip
local function CountEmptySockets(unit, slot)
	if not next(EMPTY_SOCK) then return 0 end
	sockTip = sockTip or CreateFrame("GameTooltip", "SentinelUIInspectTip", UIParent, "GameTooltipTemplate")
	sockTip:SetOwner(UIParent, "ANCHOR_NONE")
	sockTip:SetInventoryItem(unit, slot)
	local n = 0
	for i = 1, sockTip:NumLines() do
		local fs = _G["SentinelUIInspectTipTextLeft" .. i]
		local t = fs and fs:GetText()
		if t and EMPTY_SOCK[t] then n = n + 1 end
	end
	sockTip:Hide()
	return n
end

local function ReadEquipment(unit)
	local res = { enchMiss = 0, enchItems = {}, enchOk = {}, enchTotal = 0, gemsEmpty = 0, gemsFilled = 0, gemItems = {}, gemOk = {}, t = GetTime() }
	local function Gems(link)
		local g1, g2, g3, g4 = strmatch(link, "item:%d+:%d+:(%d*):(%d*):(%d*):(%d*)")
		return (tonumber(g1) or 0) + (tonumber(g2) or 0) + (tonumber(g3) or 0) + (tonumber(g4) or 0)
	end
	local function GemsAndSockets(link, unit, slot)
		local filled = Gems(link)
		local empty = CountEmptySockets(unit, slot)
		if empty > 0 then
			tinsert(res.gemItems, (strmatch(link, "%[(.-)%]") or "?") .. " (" .. empty .. ")")
		elseif filled > 0 then
			tinsert(res.gemOk, strmatch(link, "%[(.-)%]") or "?")
		end
		res.gemsFilled = res.gemsFilled + filled
		res.gemsEmpty = res.gemsEmpty + empty
	end
	for _, slot in ipairs(ENCH_SLOTS) do
		local link = GetInventoryItemLink(unit, slot)
		if link then
			res.enchTotal = res.enchTotal + 1
			local enchId = tonumber(strmatch(link, "item:%d+:(%d+)")) or 0
			if enchId == 0 then
				res.enchMiss = res.enchMiss + 1
				tinsert(res.enchItems, strmatch(link, "%[(.-)%]") or "?")
			else
				tinsert(res.enchOk, strmatch(link, "%[(.-)%]") or "?")
			end
			GemsAndSockets(link, unit, slot)
		end
	end
	-- off hand: only shields/off-hand weapons take enchants (17)
	local oh = GetInventoryItemLink(unit, 17)
	if oh then
		local loc = select(4, GetItemInfoInstant(oh))
		if loc == "INVTYPE_SHIELD" or loc == "INVTYPE_WEAPONOFFHAND" or loc == "INVTYPE_WEAPON" then
			res.enchTotal = res.enchTotal + 1
			local enchId = tonumber(strmatch(oh, "item:%d+:(%d+)")) or 0
			if enchId == 0 then
				res.enchMiss = res.enchMiss + 1
				tinsert(res.enchItems, strmatch(oh, "%[(.-)%]") or "?")
			else
				tinsert(res.enchOk, strmatch(oh, "%[(.-)%]") or "?")
			end
		end
		GemsAndSockets(oh, unit, 17)
	end
	-- ranged slot: scopes only on guns/bows/crossbows (18)
	local rw = GetInventoryItemLink(unit, 18)
	if rw then
		local _, _, _, _, _, _, sub = GetItemInfoInstant(rw)
		if sub and RANGED_OK[sub] then
			res.enchTotal = res.enchTotal + 1
			local enchId = tonumber(strmatch(rw, "item:%d+:(%d+)")) or 0
			if enchId == 0 then
				res.enchMiss = res.enchMiss + 1
				tinsert(res.enchItems, strmatch(rw, "%[(.-)%]") or "?")
			else
				tinsert(res.enchOk, strmatch(rw, "%[(.-)%]") or "?")
			end
		end
		GemsAndSockets(rw, unit, 18)
	end
	return res
end

local function EquipmentState(m, key)
	local d
	if m.unit == "player" then
		d = ReadEquipment("player")
	else
		d = inspectData[m.name]
		if not d then return "?", nil end
	end
	-- nothing to enchant / nothing socketable -> "not applicable", not "ok"
	if key == "ench" and d.enchTotal == 0 then return "na", d end
	if key == "gems" and (d.gemsEmpty + (d.gemsFilled or 0)) == 0 then return "na", d end
	local ok
	if key == "ench" then ok = d.enchMiss == 0 else ok = d.gemsEmpty == 0 end
	return ok and true or false, d
end

function RC:NextInspect()
	if inspectUnit then return end
	local m = tremove(inspectQueue, 1)
	if not m then return end
	local can = CanInspect and CheckInteractDistance and CanInspect(m.unit) and CheckInteractDistance(m.unit, 1)
	local blocked = InspectFrame and InspectFrame:IsShown()
	if not can or blocked then self:NextInspect() return end
	inspectUnit = m.unit
	NotifyInspect(m.unit)
	C_Timer.After(6, function()
		if inspectUnit == m.unit then
			inspectUnit = nil
			if ClearInspectPlayer then ClearInspectPlayer() end
			RC:NextInspect()
		end
	end)
end

function RC:INSPECT_READY(event)
	if not inspectUnit then return end
	local unit = inspectUnit
	inspectUnit = nil
	local name = ShortName(UnitName(unit))
	if name then inspectData[name] = ReadEquipment(unit) end
	if ClearInspectPlayer then ClearInspectPlayer() end
	self:NextInspect()
	if self.frame and self.frame:IsShown() then self:Render() end
end

function RC:QueueInspects()
	if not NotifyInspect then return end
	for _, m in ipairs(members) do
		if m.unit ~= "player" then
			local d = inspectData[m.name]
			if not d or GetTime() - d.t > INSPECT_TTL then
				tinsert(inspectQueue, m)
			end
		end
	end
	self:NextInspect()
end

-- roster ------------------------------------------------------------------
local function ShortName(n) return n and Ambiguate(n, "short") or n end

function RC:Collect()
	wipe(members)
	wipe(providers)
	local seen = {}
	local function Add(unit)
		if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
		local name = ShortName(UnitName(unit))
		if not name or seen[name] then return end
		seen[name] = true
		local _, class = UnitClass(unit)
		members[#members + 1] = { unit = unit, name = name, class = class }
	end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do Add("raid" .. i) end
	elseif IsInGroup() then
		Add("player")
		for i = 1, GetNumGroupMembers() - 1 do Add("party" .. i) end
	else
		Add("player")
	end
	sort(members, function(a, b) return a.name < b.name end)
	for _, m in ipairs(members) do providers[m.class] = true end
end

local function ScanAuras(unit)
	local set, list = {}, {}
	for i = 1, 40 do
		local a = S.GetAura(unit, i, "HELPFUL")
		if not a then break end
		if a.name and not S.IsSecret(a.name) then
			set[a.name] = true
			list[#list + 1] = a.name
		end
	end
	return set, list
end

-- visible columns depend on db toggles + provider classes in the group
function RC:VisibleChecks()
	local out = {}
	for _, c in ipairs(CHECKS) do
		if c.dbKey and self.db[c.dbKey] == false then
		elseif c.provider and not providers[c.provider] then
		else
			out[#out + 1] = c
		end
	end
	return out
end

function RC:Refresh()
	self:Collect()
	wipe(auraSets)
	for _, m in ipairs(members) do
		local set, list = ScanAuras(m.unit)
		auraSets[m.name] = { set = set, list = list }
	end
	if IsInGroup() then S.SendAddonMessage(PREFIX, "Q", S.GroupChannel()) end
	self:QueueInspects()
	self.cols = self:VisibleChecks()
	self:Render()
end

-- window -------------------------------------------------------------------
function RC:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIRaidCheck", UIParent, S.BackdropTemplate)
	f:SetSize(320, 420)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetFrameStrata("DIALOG")
	S:SetTemplate(f, "Default", "DIALOG")
	f:Hide()
	tinsert(UISpecialFrames, "SentinelUIRaidCheck")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(fr) fr:StopMovingOrSizing()
		local point, _, rel, x, y = fr:GetPoint(1)
		RC.db.point = { point = point, rel = rel, x = x, y = y }
	end)
	local p = self.db.point
	if p and p.point then f:SetPoint(p.point, UIParent, p.rel or "CENTER", p.x or 0, p.y or 0)
	else f:SetPoint("CENTER", UIParent, "CENTER", 0, 60) end

	f.title = S:FontString(f, 13, "OUTLINE")
	f.title:SetPoint("TOPLEFT", 12, -10)
	f.title:SetText("SentinelUI " .. L["Raid Check"])
	local close = CreateFrame("Button", nil, f)
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", -8, -8)
	close:EnableMouse(true)
	close:SetScript("OnClick", function() f:Hide() end)
	S:SkinCloseButton(close)

	f.colHeads = {}
	f.rows = {}
	for i = 1, MAX_VIS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(NAME_W + #CHECKS * (CELL + 2), ROW_H)
		row:SetPoint("TOPLEFT", 8, -52 - (i - 1) * ROW_H)
		row.name = S:FontString(row, 11)
		row.name:SetPoint("LEFT", 2, 0)
		row.name:SetWidth(NAME_W - 8)
		row.name:SetJustifyH("LEFT")
		row.cells = {}
		for c = 1, #CHECKS do
			local cell = CreateFrame("Button", nil, row)
			cell:SetSize(CELL - 4, CELL - 4)
			cell:EnableMouse(true)
			local bg = cell:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			cell.bg = bg
			local ic = cell:CreateTexture(nil, "ARTWORK")
			ic:SetAllPoints()
			cell.icon = ic
			cell.txt = S:FontString(cell, 11)
			cell.txt:SetPoint("CENTER")
			row.cells[c] = cell
		end
		f.rows[i] = row
	end

	local scroll = CreateFrame("ScrollFrame", "SentinelUIRaidCheckScroll", f, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -52)
	scroll:SetPoint("BOTTOMRIGHT", -26, 36)
	scroll:SetScript("OnVerticalScroll", function(s, off)
		FauxScrollFrame_OnVerticalScroll(s, off, ROW_H, function() RC:Render() end)
	end)
	f.scroll = scroll

	-- footer
	local function FooterBtn(label, w, fn)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(w, 20)
		S:SkinButton(b)
		local t = S:FontString(b, 11)
		t:SetPoint("CENTER")
		t:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	f.refresh = FooterBtn(L["Refresh"], 76, function() RC:Refresh() end)
	f.refresh:SetPoint("BOTTOMLEFT", 10, 10)
	f.report = FooterBtn(L["Report missing"], 100, function() RC:ReportMissing() end)
	f.report:SetPoint("LEFT", f.refresh, "RIGHT", 6, 0)
	f.status = S:FontString(f, 10)
	f.status:SetPoint("BOTTOMRIGHT", -10, 14)
	f.status:SetJustifyH("RIGHT")

	self.frame = f
end

local TEX_OK = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local TEX_NO = "Interface\\RAIDFRAME\\ReadyCheck-NotReady"
local TEX_WAIT = "Interface\\RAIDFRAME\\ReadyCheck-Waiting"

local function CellState(cell, state, tipTitle, tipLine)
	if state == true then
		cell.bg:SetColorTexture(0.13, 0.55, 0.13, 0.25)
		cell.icon:SetTexture(TEX_OK)
		cell.icon:SetDesaturated(false)
		cell.icon:SetAlpha(1)
		cell.txt:SetText("")
	elseif state == "warn" then
		cell.bg:SetColorTexture(0.6, 0.55, 0.1, 0.25)
		cell.icon:SetTexture(TEX_WAIT)
		cell.icon:SetDesaturated(false)
		cell.icon:SetAlpha(1)
		cell.txt:SetText("")
	elseif state == false then
		cell.bg:SetColorTexture(0.55, 0.13, 0.13, 0.25)
		cell.icon:SetTexture(TEX_NO)
		cell.icon:SetDesaturated(false)
		cell.icon:SetAlpha(1)
		cell.txt:SetText("")
	elseif state == "na" then
		cell.bg:SetColorTexture(0.25, 0.25, 0.25, 0.15)
		cell.icon:SetTexture(TEX_NO)
		cell.icon:SetDesaturated(true)
		cell.icon:SetAlpha(0.25)
		cell.txt:SetText("")
	else
		cell.bg:SetColorTexture(0.25, 0.25, 0.25, 0.3)
		cell.icon:SetTexture(TEX_WAIT)
		cell.icon:SetDesaturated(true)
		cell.icon:SetAlpha(0.5)
		cell.txt:SetText("")
	end
	cell:SetScript("OnEnter", function()
		GameTooltip:SetOwner(cell, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(tipTitle)
		if type(tipLine) == "table" then
			for _, tl in ipairs(tipLine) do
				GameTooltip:AddLine(tl[1], tl[2] or 1, tl[3] or 1, tl[4] or 1)
			end
		elseif tipLine then
			GameTooltip:AddLine(tipLine, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function RC:Render()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local cols = self.cols or {}
	local missing = {}
	for _, c in ipairs(cols) do missing[c.key] = {} end

	-- column headers
	for i, c in ipairs(cols) do
		local h = f.colHeads[i]
		if not h then
			h = CreateFrame("Button", nil, f)
			h:SetSize(18, 18)
			h:EnableMouse(true)
			h.icon = h:CreateTexture(nil, "ARTWORK")
			h.icon:SetAllPoints()
			h.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			f.colHeads[i] = h
		end
		h:SetPoint("TOPLEFT", 10 + NAME_W + (i - 1) * (CELL + 2), -28)
		local icon = c.icon
		if not icon and c.iconId then
			icon = select(3, S.GetSpellInfo(c.iconId)) or 134400
			c.icon = icon
		end
		h.icon:SetTexture(icon or 134400)
		h.check = c
		h:SetScript("OnEnter", function()
			GameTooltip:SetOwner(h, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(c.label)
			local miss = missing[c.key] or {}
			if #miss > 0 then
				GameTooltip:AddLine(L["Missing:"] .. " " .. table.concat(miss, ", "), 1, 0.3, 0.3, true)
			else
				GameTooltip:AddLine(L["Everyone covered"], 0.3, 1, 0.3)
			end
			GameTooltip:Show()
		end)
		h:SetScript("OnLeave", function() GameTooltip:Hide() end)
		h:Show()
	end
	for i = #cols + 1, #f.colHeads do f.colHeads[i]:Hide() end

	-- evaluate + render
	local scroll = f.scroll
	FauxScrollFrame_Update(scroll, #members, MAX_VIS, ROW_H)
	local offset = FauxScrollFrame_GetOffset(scroll)
	for i = 1, MAX_VIS do
		local row = f.rows[i]
		local m = members[i + offset]
		if m then
			local data = auraSets[m.name] or { set = {}, list = {} }
			local color = RAID_CLASS_COLORS[m.class]
			row.name:SetText(m.name)
			row.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
			for cIdx, c in ipairs(cols) do
				local cell = row.cells[cIdx]
				cell:SetPoint("LEFT", NAME_W + (cIdx - 1) * (CELL + 2), 0)
				local state, extra
				if c.key == "wep" then
					state = WeaponEnchant(m)
				elseif c.key == "ench" or c.key == "gems" then
					local d
					state, d = EquipmentState(m, c.key)
					if d then
						if c.key == "ench" then
							extra = {}
							for _, it in ipairs(d.enchItems) do tinsert(extra, { it, 1, 0.3, 0.3 }) end
							for _, it in ipairs(d.enchOk) do tinsert(extra, { it, 0.3, 1, 0.3 }) end
							if #extra == 0 then extra = nil end
						elseif c.key == "gems" then
							extra = {}
							for _, it in ipairs(d.gemItems) do tinsert(extra, { it, 1, 0.3, 0.3 }) end
							for _, it in ipairs(d.gemOk) do tinsert(extra, { it, 0.3, 1, 0.3 }) end
							if #extra == 0 then extra = nil end
						end
					end
				elseif c.manaOnly and UnitPowerType(m.unit) ~= 0 then
					state = "na"
				else
					local r = c.eval(data.set, data.list, m)
					state = (r == "warn" and "warn") or (r and true or false)
				end
				if state == false or state == "warn" then tinsert(missing[c.key], m.name) end
				CellState(cell, state, m.name .. " — " .. c.label,
					extra or (state == true and L["OK"] or state == false and L["Missing"]
						or state == "warn" and L["Incomplete"] or state == "?" and L["Unknown"] or L["n/a"]))
				cell:Show()
			end
			for cIdx = #cols + 1, #CHECKS do row.cells[cIdx]:Hide() end
			row:Show()
		else
			row:Hide()
		end
	end
	f:SetWidth(NAME_W + #cols * (CELL + 2) + 44)
	f:SetHeight(52 + min(#members, MAX_VIS) * ROW_H + 42)

	-- status summary
	local missCount = 0
	for _, list in pairs(missing) do missCount = missCount + #list end
	if missCount == 0 then
		f.status:SetText("|cff33ff33" .. L["All covered"] .. "|r")
	else
		f.status:SetText(format("|cffff5533%d " .. L["buffs missing"] .. "|r", missCount))
	end
	RC.missing = missing
end

function RC:ReportMissing()
	if not self.missing then self:Refresh() end
	local ch = S.GroupChannel() or "SAY"
	for _, c in ipairs(self.cols or {}) do
		local list = self.missing and self.missing[c.key]
		if list and #list > 0 then
			SendChatMessage(format("[%s] %s: %s", L["Raid Check"], c.label, table.concat(list, ", ")), ch)
		end
	end
end

function RC:Toggle()
	self:BuildFrame()
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		self:Refresh()
	end
end

-- events --------------------------------------------------------------------
function RC:CHAT_MSG_ADDON(event, prefix, msg, channel, sender)
	if prefix ~= PREFIX then return end
	if msg == "Q" then
		if GetWeaponEnchantInfo then
			local mh, _, _, _, oh = GetWeaponEnchantInfo()
			S.SendAddonMessage(PREFIX, format("R%d%d", mh and 1 or 0, oh and 1 or 0), "WHISPER", sender)
		end
		return
	end
	local mh, oh = strmatch(msg, "^R(%d)(%d)")
	if mh then
		remoteWE[ShortName(sender)] = { mh = mh == "1", oh = oh == "1", t = GetTime() }
		if self.frame and self.frame:IsShown() then self:Render() end
	end
end

function RC:GROUP_ROSTER_UPDATE()
	if self.frame and self.frame:IsShown() then self:Refresh() end
end

function RC:UNIT_AURA()
	if not auraPending then
		auraPending = true
		C_Timer.After(0.6, function()
			auraPending = false
			if RC.frame and RC.frame:IsShown() then RC:Refresh() end
		end)
	end
end

function RC:Update()
	if self.frame and self.frame:IsShown() then self:Refresh() end
end

function RC:Initialize()
	self.db = S.db.profile.raidcheck
	if self.db.enable == false then return end
	BuildSets()
	if S.RegisterAddonPrefix then pcall(S.RegisterAddonPrefix, PREFIX) end

	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "raidcheck", glyph = "RC",
		store = self.private.minimap, angle = 300,
		onLeft = function() RC:Toggle() end,
		onRight = function() RC:Toggle() if RC.frame and RC.frame:IsShown() then RC:Refresh() end end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. L["Raid Check"])
			GameTooltip:AddLine(L["Click: buff/food/flask overview for the group"], 1, 1, 1)
		end,
	})

	self:RegisterEvent("CHAT_MSG_ADDON")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("UNIT_AURA")
	self:RegisterEvent("INSPECT_READY")
	SlashCmdList.SENTINELUIRAIDCHECK = function() RC:Toggle() end
	SLASH_SENTINELUIRAIDCHECK1 = "/suirc"
	SLASH_SENTINELUIRAIDCHECK2 = "/suicheck"
end
