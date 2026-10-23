-- BisGuide: best-in-slot item database and guide. Tooltip rank annotations,
-- a browsable BiS list per class/spec/phase, consumable and rotation windows,
-- talent build suggestions and inspect integration. Data ships in generated
-- files under Modules/BisGuide/Data_*.lua as the SUIBisData global; nothing is
-- loaded from or tied to any other addon.
local _, ns = ...
local S = ns.S
local L = S.L
local BG = S:NewModule("BisGuide", "bisguide")

local _G = _G
local ipairs, pairs, wipe, tinsert = ipairs, pairs, wipe, table.insert
local format, floor = string.format, math.floor
local strmatch, strlower, strupper, tonumber, type = strmatch, strlower, strupper, tonumber, type
local CreateFrame, C_Timer = CreateFrame, C_Timer
local IsSecret = S.IsSecret

local D -- SUIBisData

-- generated item entry fields: {itemId, rank, enchant, gems, source, sourceType, dropChance}
local SLOT_LABEL = {
	head = HEAD_SLOT or "Head", neck = NECK_SLOT or "Neck", shoulder = SHOULDER_SLOT or "Shoulder",
	back = BACK_SLOT or "Back", chest = CHEST_SLOT or "Chest", wrist = WRIST_SLOT or "Wrist",
	hands = HANDS_SLOT or "Hands", waist = WAIST_SLOT or "Waist", legs = LEGS_SLOT or "Legs",
	feet = FEET_SLOT or "Feet", ["finger 1"] = (FINGER0SLOT or "Finger") .. " 1", ["finger 2"] = (FINGER0SLOT or "Finger") .. " 2",
	["trinket 1"] = (TRINKET0SLOT or "Trinket") .. " 1", ["trinket 2"] = (TRINKET0SLOT or "Trinket") .. " 2",
	weapon = MAINHANDSLOT or "Weapon", ["off hand"] = SECONDARYHANDSLOT or "Off Hand",
	ranged = RANGEDSLOT or "Ranged", relic = L["Relic"] or "Relic",
}
local SLOT_INV = {
	head = { 1 }, neck = { 2 }, shoulder = { 3 }, back = { 15 }, chest = { 5 },
	wrist = { 9 }, hands = { 10 }, waist = { 6 }, legs = { 7 }, feet = { 8 },
	["finger 1"] = { 11 }, ["finger 2"] = { 12 }, ["trinket 1"] = { 13 }, ["trinket 2"] = { 14 },
	weapon = { 16 }, ["off hand"] = { 17 }, ranged = { 18 }, relic = { 18 },
}

local CLASS_FILE = {
	Druid = "DRUID", Hunter = "HUNTER", Mage = "MAGE", Paladin = "PALADIN", Priest = "PRIEST",
	Rogue = "ROGUE", Shaman = "SHAMAN", Warlock = "WARLOCK", Warrior = "WARRIOR",
}

local function ClassName(ci)
	local cn = D and D.classes and D.classes[ci]
	local f = cn and CLASS_FILE[cn]
	return (f and (LOCALIZED_CLASS_NAMES_MALE[f] or cn)) or cn or "?"
end

local function ClassColor(ci)
	local cn = D and D.classes and D.classes[ci]
	local f = cn and CLASS_FILE[cn]
	local c = f and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[f]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function ClassIconTag(ci, sz)
	local cn = D and D.classes and D.classes[ci]
	local f = cn and CLASS_FILE[cn]
	local t = f and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[f]
	if t then
		return format("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t",
			sz or 14, sz or 14, t[1] * 256, t[2] * 256, t[3] * 256, t[4] * 256)
	end
	return ""
end

-- ---------------------------------------------------------------------------
-- data layer
-- ---------------------------------------------------------------------------
function BG:SpecIndex(ci, specName)
	for si, n in ipairs((D.specs or {})[ci] or {}) do
		if n == specName then return si end
	end
end

function BG:BuildIndex()
	self.itemIndex = {}
	self.itemMeta = {} -- itemId -> {slot, src, stype, drop, ench, gems} of its best appearance
	local bis = D.bis or {}
	for ci, specs in pairs(bis) do
		for si, phases in pairs(specs) do
			for pi, slots in pairs(phases) do
				for _, se in ipairs(slots) do
					for _, it in ipairs(se.i or {}) do
						local iid = it[1]
						if iid and iid > 0 then
							local lst = self.itemIndex[iid]
							if not lst then lst = {}; self.itemIndex[iid] = lst end
							tinsert(lst, { ci = ci, si = si, pi = pi, slot = se.s, rank = it[2],
								ench = it[3], gems = it[4], src = it[5], stype = it[6], drop = it[7] })
							local m = self.itemMeta[iid]
							if not m or (it[2] or 99) < m.rank then
								self.itemMeta[iid] = { slot = se.s, rank = it[2], ench = it[3], gems = it[4],
									src = it[5], stype = it[6], drop = it[7] }
							end
						end
					end
				end
			end
		end
	end
end

-- all BiS entries that concern this item id (incl. token / recipe expansion)
function BG:EntriesFor(itemId)
	local out, seenIds = {}, {}
	local function addId(id)
		if seenIds[id] then return end
		seenIds[id] = true
		for _, e in ipairs(self.itemIndex[id] or {}) do tinsert(out, e) end
	end
	addId(itemId)
	for _, tid in ipairs((D.tokens or {})[itemId] or {}) do addId(tid) end
	local crafted = (D.recipes or {})[itemId]
	if crafted then addId(crafted) end
	return out
end

-- spec display name: data ships english labels, localized via L when present
local function SpecName(ci, si)
	local sn = (D.specs or {})[ci] and D.specs[ci][si]
	return (sn and (L[sn] or sn)) or "?"
end
BG.SpecName = SpecName

-- talent tree name -> spec index. Talent tabs are localized on non-english
-- clients ("Heilig"/"Vergeltung"), so each spec is matched against both its
-- english label and its localized alias.
function BG:TreeToSpec(ci, treeName)
	local specs = (D.specs or {})[ci] or {}
	if not treeName then return end
	local tw = strlower(strmatch(treeName, "^(%S+)") or "")
	local best, bestLen
	for si, sn in ipairs(specs) do
		for _, cand in ipairs({ sn, L[sn] }) do
			if cand then
				local sw = strlower(strmatch(cand, "^(%S+)") or "")
				if sw == tw and (not bestLen or #cand < bestLen) then
					best, bestLen = si, #cand
				end
			end
		end
	end
	if best then return best end
	for si, sn in ipairs(specs) do
		if strlower(sn) == strlower(treeName)
			or (L[sn] and strlower(L[sn]) == strlower(treeName)) then return si end
	end
end

function BG:PlayerClassIndex()
	if self._pci then return self._pci end
	local _, f = UnitClass("player")
	for ci, cn in ipairs(D.classes or {}) do
		if CLASS_FILE[cn] == f then self._pci = ci return ci end
	end
end

-- dominant talent tree -> own spec index (TBC API; guarded for other clients)
function BG:GetPlayerSpec()
	local ci = self:PlayerClassIndex()
	if not ci then return end
	if GetTalentTabInfo then
		local bestTab, bestPts
		for t = 1, tonumber(GetNumTalentTabs and GetNumTalentTabs() or 3) or 3 do
			local name, _, pts = GetTalentTabInfo(t)
			pts = tonumber(pts) or 0
			if pts > (bestPts or 0) then bestTab, bestPts = t, pts end
		end
		if bestTab and (bestPts or 0) > 0 then
			local tname = GetTalentTabInfo(bestTab)
			local si = self:TreeToSpec(ci, tname)
			if si then return si end
		end
	end
	return 1
end

-- best BiS rank of an item for the player's own class+spec (nil = not listed)
function BG:PlayerRank(itemId)
	local ci = self:PlayerClassIndex()
	if not ci then return end
	local si = self:GetPlayerSpec()
	local best
	for _, e in ipairs(self:EntriesFor(itemId)) do
		if e.ci == ci and (not si or e.si == si) then
			if not best or (e.rank or 99) < best then best = e.rank end
		end
	end
	return best
end

-- star overlay on reward buttons that are BiS for the player's spec
local function MarkRewardButton(btn, iid)
	if not btn then return end
	if not btn.suiBisMark then
		local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetSize(14, 14)
		t:SetPoint("TOPRIGHT", 2, 2)
		t:SetTexture([[Interface\Common\ReputationStar]])
		t:SetTexCoord(0, 0.5, 0, 0.5) -- filled gold star
		btn.suiBisMark = t
	end
	btn.suiBisMark:SetShown(iid ~= nil and BG:PlayerRank(iid) ~= nil)
end

function BG:MarkQuestRewards()
	for i = 1, 10 do
		local btn = _G["QuestInfoItem" .. i]
		if not btn then break end
		if btn:IsShown() and btn.type and (btn:GetID() or 0) > 0 then
			local link = GetQuestItemLink and GetQuestItemLink(btn.type, btn:GetID())
			MarkRewardButton(btn, link and tonumber(strmatch(link, "item:(%d+)")))
		elseif btn.suiBisMark then
			btn.suiBisMark:Hide()
		end
	end
	for i = 1, 10 do
		local btn = _G["QuestLogItem" .. i]
		if not btn then break end
		if btn:IsShown() and btn.type and (btn:GetID() or 0) > 0 then
			local link = GetQuestLogItemLink and GetQuestLogItemLink(btn.type, btn:GetID())
			MarkRewardButton(btn, link and tonumber(strmatch(link, "item:(%d+)")))
		elseif btn.suiBisMark then
			btn.suiBisMark:Hide()
		end
	end
end

-- async item icon loader: cache-first via every API the client exposes, then
-- a real fetch (Item mixin on modern engines, GetItemInfo+event on classic).
local pendingIcon = {}
local iconWatcher = CreateFrame("Frame")
pcall(iconWatcher.RegisterEvent, iconWatcher, "GET_ITEM_INFO_RECEIVED")

local function CachedIcon(iid)
	local _, _, _, _, icon = GetItemInfoInstant and GetItemInfoInstant(iid)
	if icon and icon > 0 then return icon end
	if C_Item and C_Item.GetItemIconByID then
		local ic = C_Item.GetItemIconByID(iid)
		if ic and ic > 0 then return ic end
	end
	if GetItemIcon then -- classic-era global
		local ic = GetItemIcon(iid)
		if ic and ic > 0 then return ic end
	end
end

local function ResolveIcons(iid)
	local cbs = pendingIcon[iid]
	if not cbs then return end
	local icon = CachedIcon(iid)
	if not icon then return end
	pendingIcon[iid] = nil
	for _, cb in ipairs(cbs) do cb(icon) end
end

iconWatcher:SetScript("OnEvent", function(_, _, iid)
	if iid then ResolveIcons(iid) end
end)

local function WarmItem(iid)
	-- modern engine: the Item mixin is the official async loader
	if Item and Item.CreateFromItemID then
		local ok, it = pcall(Item.CreateFromItemID, Item, iid)
		if ok and it and it.ContinueOnItemLoad then
			it:ContinueOnItemLoad(function() ResolveIcons(iid) end)
			return
		end
	end
	if GetItemInfo then pcall(GetItemInfo, iid) end -- classic: triggers the fetch
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, iid) end
end

local function ItemIcon(iid, cb)
	local icon = CachedIcon(iid)
	if icon then cb(icon) return end
	local lst = pendingIcon[iid]
	if not lst then
		lst = {}
		pendingIcon[iid] = lst
		WarmItem(iid)
		-- poll fallback: retries until the icon lands (cap ~5s per item)
		local tries = 0
		local function poll()
			if not pendingIcon[iid] then return end
			tries = tries + 1
			if CachedIcon(iid) then
				ResolveIcons(iid)
			elseif tries < 5 then
				if tries > 1 then WarmItem(iid) end
				C_Timer.After(1, poll)
			else
				pendingIcon[iid] = nil -- item does not exist client-side -> "?"
			end
		end
		C_Timer.After(0.6, poll)
	end
	lst[#lst + 1] = cb
	cb(134400) -- question mark placeholder meanwhile
end
BG.ItemIcon = ItemIcon

function BG:ItemTooltip(btn, iid)
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. iid)
	GameTooltip:Show()
end

local function InsertItemLink(iid)
	local _, link = GetItemInfo(iid)
	if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

-- ---------------------------------------------------------------------------
-- tooltip annotation
-- ---------------------------------------------------------------------------
function BG:OnTooltipItem(tt)
	if not self.db.tooltip then return end
	local _, link = tt:GetItem()
	local itemId = link and tonumber(strmatch(link, "item:(%d+)"))
	if not itemId then return end
	local entries = self:EntriesFor(itemId)
	if #entries == 0 then return end

	-- group: ci -> si -> {pi -> rank, bestEntry}
	local byClass = {}
	for _, e in ipairs(entries) do
		local c = byClass[e.ci]
		if not c then c = {}; byClass[e.ci] = c end
		local s = c[e.si]
		if not s then s = {}; c[e.si] = s end
		if not s[e.pi] or (e.rank or 99) < s[e.pi] then
			s[e.pi] = e.rank
		end
		if not s.best or (e.rank or 99) < (s.best.rank or 99) or (e.rank == s.best.rank and e.pi > s.best.pi) then
			s.best = e
		end
	end

	local myCi, mySi = self:PlayerClassIndex(), self:GetPlayerSpec()
	local ownOnly = self.db.ownSpecOnly
	if IsAltKeyDown and IsAltKeyDown() then ownOnly = not ownOnly end

	tt:AddLine(" ")
	tt:AddLine("|cff66c2ffSentinelUI|r " .. (L["Best in Slot"] or "Best in Slot"), 0.4, 0.76, 1)
	local phases = D.phases or {}
	for ci = 1, #(D.classes or {}) do
		local specs = byClass[ci]
		if specs then
			local cr, cg, cb = ClassColor(ci)
			tt:AddLine(format("%s %s", ClassIconTag(ci, 13), ClassName(ci)), cr, cg, cb)
			local specList = {}
			for si in pairs(specs) do tinsert(specList, si) end
			table.sort(specList)
			for _, si in ipairs(specList) do
				local sdata = specs[si]
				local sn = SpecName(ci, si)
				if sn ~= "?" then
					local own = ci == myCi and si == mySi
					if not ownOnly or own then
						local parts = {}
						for pi = 1, #phases do
							local rk = sdata[pi]
							if rk then
								local col = pi == self.db.phaseIndex and "|cffffd100" or "|cff9e9e9e"
								tinsert(parts, col .. (phases[pi] or "?") .. "#" .. (rk or "?") .. "|r")
							end
						end
						local prefix = own and "|cff66ff66»|r " or "   "
						tt:AddLine(prefix .. sn .. "  " .. table.concat(parts, " "), 0.95, 0.95, 0.95)
					end
				end
			end
		end
	end
	-- source line for the best relevant entry
	local best
	for _, e in ipairs(entries) do
		if not best or (e.rank or 99) < (best.rank or 99) then best = e end
	end
	if best and best.src and best.src ~= "" and self.db.tooltipSource then
		local src = best.src
		if best.drop and best.drop > 0 then src = src .. format(" (%d%%)", floor(best.drop * 100 + 0.5)) end
		tt:AddLine(format("%s: %s", best.stype ~= "" and best.stype or (L["Source"] or "Source"), src), 0.6, 0.8, 0.9)
	end
	tt:Show()
end

-- ---------------------------------------------------------------------------
-- browser window
-- ---------------------------------------------------------------------------
local B -- browser frame

local function MakeIcon(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	b.rank = S:FontString(b, size * 0.36, "OUTLINE")
	b.rank:SetPoint("BOTTOM", 0, 0)
	b.rank:SetTextColor(1, 0.82, 0)
	b:EnableMouse(true)
	return b
end

local function IconTipItem(b, iid)
	b:SetScript("OnEnter", function() BG:ItemTooltip(b, iid) end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function()
		if IsShiftKeyDown and IsShiftKeyDown() then InsertItemLink(iid) end
	end)
end

local function IconTipEnchant(b, ench)
	if not ench or not ench.i or ench.i <= 0 then b:Hide() return end
	if ench.item then
		ItemIcon(ench.i, function(t) b.tex:SetTexture(t) end)
	else
		local tex = GetSpellTexture and GetSpellTexture(ench.i)
		b.tex:SetTexture(tex or 134400)
	end
	b:SetScript("OnEnter", function()
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		if ench.item then GameTooltip:SetHyperlink("item:" .. ench.i)
		else GameTooltip:SetSpellByID(ench.i) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function()
		if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
		if ench.item then InsertItemLink(ench.i)
		else
			local l = GetSpellLink and GetSpellLink(ench.i)
			if l and ChatEdit_InsertLink then ChatEdit_InsertLink(l) end
		end
	end)
	b:Show()
end

local function SlotGroup(s)
	return (s:gsub(" %d$", ""))
end

function BG:CreateBrowser()
	if B then return B end
	B = CreateFrame("Frame", "SentinelUIBisBrowser", UIParent, S.BackdropTemplate)
	B:SetSize(600, 520)
	B:SetPoint("CENTER")
	B:SetFrameStrata("DIALOG")
	B:EnableMouse(true)
	B:SetMovable(true)
	B:RegisterForDrag("LeftButton")
	B:SetScript("OnDragStart", B.StartMoving)
	B:SetScript("OnDragStop", B.StopMovingOrSizing)
	S:CreateBackdrop(B, "Default", "TOP")
	S:EnablePixelSnap(B)
	tinsert(UISpecialFrames, B:GetName())
	B:Hide()

	B.title = S:FontString(B, 14, "OUTLINE", S.media.unitFont)
	-- left-aligned so the centered title can't collide with the Phase label
	B.title:SetPoint("TOPLEFT", 12, -8)
	B.title:SetText("|cff66c2ffSentinelUI|r " .. (L["BiS Guide"] or "BiS Guide"))
	B.sep = B:CreateTexture(nil, "ARTWORK")
	B.sep:SetSize(1, 1)
	B.sep:SetPoint("TOPLEFT", 10, -28)
	B.sep:SetPoint("TOPRIGHT", -10, -28)
	B.sep:SetHeight(1)
	B.sep:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.8)

	local close = CreateFrame("Button", nil, B, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	S:SkinCloseButton(close)

	-- dropdowns -----------------------------------------------------------
	local function MakeDropDown(name, label, x)
		local dd = CreateFrame("Frame", name, B, "UIDropDownMenuTemplate")
		dd:SetPoint("TOPLEFT", x, -30)
		UIDropDownMenu_SetWidth(dd, 130)
		local fs = S:FontString(B, 10, "OUTLINE")
		fs:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 20, 2)
		fs:SetText(label)
		fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
		return dd
	end

	B.classDD = MakeDropDown("SentinelUIBisClassDD", L["Class"] or "Class", -6)
	B.specDD = MakeDropDown("SentinelUIBisSpecDD", L["Spec"] or "Spec", 154)
	B.phaseDD = MakeDropDown("SentinelUIBisPhaseDD", L["Phase"] or "Phase", 314)

	UIDropDownMenu_Initialize(B.classDD, function(_, level)
		for ci, cn in ipairs(D.classes or {}) do
			local info = UIDropDownMenu_CreateInfo()
			local r, g, b2 = ClassColor(ci)
			info.text, info.value = ClassName(ci), ci
			info.colorCode = format("|cff%02x%02x%02x", r * 255, g * 255, b2 * 255)
			info.func = function()
				BG.selCi = ci
				BG.selSi = (ci == BG:PlayerClassIndex()) and BG:GetPlayerSpec() or 1
				BG.selSi = BG.selSi or 1
				BG:RefreshBrowser()
			end
			info.checked = BG.selCi == ci
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	UIDropDownMenu_Initialize(B.specDD, function(_, level)
		for si, sn in ipairs((D.specs or {})[BG.selCi or 1] or {}) do
			local info = UIDropDownMenu_CreateInfo()
			info.text, info.value = SpecName(BG.selCi or 1, si), si
			info.func = function() BG.selSi = si BG:RefreshBrowser() end
			info.checked = BG.selSi == si
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	UIDropDownMenu_Initialize(B.phaseDD, function(_, level)
		for pi, ph in ipairs(D.phases or {}) do
			local info = UIDropDownMenu_CreateInfo()
			info.text, info.value = ph, pi
			info.func = function() BG.selPi = pi BG.db.phaseIndex = pi BG:RefreshBrowser() end
			info.checked = BG.selPi == pi
			UIDropDownMenu_AddButton(info, level)
		end
	end)

	-- extra buttons ---------------------------------------------------------
	local function SmallBtn(text, x, w, fn)
		local b = CreateFrame("Button", nil, B, "UIPanelButtonTemplate")
		b:SetSize(w, 22)
		b:SetPoint("TOPRIGHT", x, -58)
		b:SetText(text)
		S:SkinButton(b)
		b:SetScript("OnClick", fn)
		return b
	end
	SmallBtn(L["Consumes"] or "Consumes", -34, 84, function() BG:ToggleWindow("consumes") end)
	SmallBtn(L["Rotation"] or "Rotation", -122, 80, function() BG:ToggleWindow("rotation") end)
	SmallBtn(L["Talents"] or "Talents", -206, 74, function() BG:ToggleWindow("talents") end)

	-- scroll list -----------------------------------------------------------
	B.scroll = CreateFrame("ScrollFrame", "SentinelUIBisScroll", B, "UIPanelScrollFrameTemplate")
	B.scroll:SetPoint("TOPLEFT", 10, -86)
	B.scroll:SetPoint("BOTTOMRIGHT", -30, 8)
	B.content = CreateFrame("Frame", nil, B.scroll)
	B.content:SetSize(556, 10)
	B.scroll:SetScrollChild(B.content)
	if B.scroll.ScrollBar then S:SkinScrollBar(B.scroll.ScrollBar) end

	B.rows = {}
	self:CreateStatsPanel()
	return B
end

-- row layout: [slot 84px] [ench 22] [gems 3x14] [item icons 6x30]
local function GetRow(i)
	local r = B.rows[i]
	if not r then
		r = CreateFrame("Frame", nil, B.content)
		r:SetSize(540, 36)
		r.slot = S:FontString(r, 11, "OUTLINE")
		r.slot:SetPoint("LEFT", 2, 0)
		r.slot:SetWidth(84)
		r.slot:SetJustifyH("LEFT")
		r.slot:SetTextColor(0.95, 0.8, 0.35)
		r.ench = MakeIcon(r, 22)
		r.ench:SetPoint("LEFT", 88, 0)
		r.gems = {}
		for g = 1, 3 do
			local ic = MakeIcon(r, 14)
			ic:SetPoint("LEFT", 112 + (g - 1) * 16, 0)
			r.gems[g] = ic
		end
		r.items = {}
		for j = 1, 6 do
			local ic = MakeIcon(r, 28)
			ic:SetPoint("LEFT", 168 + (j - 1) * 30, 0)
			ic.edge = ic:CreateTexture(nil, "OVERLAY")
			ic.edge:SetPoint("TOPLEFT", -2, 2)
			ic.edge:SetPoint("BOTTOMRIGHT", 2, -2)
			ic.edge:SetDrawLayer("OVERLAY", 7)
			ic.edge:SetColorTexture(0, 0, 0, 0)
			r.items[j] = ic
		end
		B.rows[i] = r
	end
	return r
end

function BG:RefreshBrowser()
	if not B or not B:IsShown() then return end
	UIDropDownMenu_SetText(B.classDD, ClassName(self.selCi))
	UIDropDownMenu_SetText(B.specDD, SpecName(self.selCi, self.selSi))
	UIDropDownMenu_SetText(B.phaseDD, (D.phases or {})[self.selPi] or "?")

	local slots = (((D.bis or {})[self.selCi] or {})[self.selSi] or {})[self.selPi] or {}

	-- itemId -> equipped slot group for the player
	local equipped = {}
	for s = 1, 18 do
		if s ~= 4 then
			local id = GetInventoryItemID("player", s)
			if id then
				for sl, inv in pairs(SLOT_INV) do
					for _, is in ipairs(inv) do
						if is == s then equipped[id] = SlotGroup(sl) break end
					end
				end
			end
		end
	end
	local inspected = self.inspectedItems or {}

	local y = -4
	local shown = 0
	for row, se in ipairs(slots) do
		local r = GetRow(row)
		r:SetPoint("TOPLEFT", 0, y)
		y = y - 40
		shown = shown + 1
		r.slot:SetText(SLOT_LABEL[se.s] or se.s)
		r:Show()

		-- enchant + gems of the rank-1 item
		local first = se.i and se.i[1]
		IconTipEnchant(r.ench, first and first[3])
		for g = 1, 3 do
			local ic, gid = r.gems[g], first and first[4] and first[4][g]
			if gid then
				ItemIcon(gid, function(t) ic.tex:SetTexture(t) end)
				ic.rank:SetText("")
				IconTipItem(ic, gid)
				ic:Show()
			else
				ic:Hide()
			end
		end

		-- ranked item icons
		for j = 1, 6 do
			local ic, it = r.items[j], se.i and se.i[j]
			if it then
				local iid = it[1]
				ItemIcon(iid, function(t) ic.tex:SetTexture(t) end)
				ic.rank:SetText("#" .. (it[2] or j))
				IconTipItem(ic, iid)
				if inspected[iid] then
					ic.edge:SetColorTexture(0.25, 0.55, 1, 0.9)
				elseif equipped[iid] and equipped[iid] == SlotGroup(se.s) then
					ic.edge:SetColorTexture(0.2, 1, 0.25, 0.9)
				else
					ic.edge:SetColorTexture(0, 0, 0, 0)
				end
				ic:Show()
			else
				ic:Hide()
			end
		end
	end
	for i = shown + 1, #B.rows do B.rows[i]:Hide() end
	B.content:SetHeight(math.max(10, -y + 8))
	self:RefreshStatsPanel()
end

-- ---------------------------------------------------------------------------
-- stat caps side panel
-- ---------------------------------------------------------------------------
local SPEC_KIND = {
	Druid = { ["Balance"] = "CASTER_DPS", ["Feral DPS"] = "MELEE_DW", ["Feral Tank"] = "TANK_DRUID", ["Restoration"] = "HEALER" },
	Hunter = { ["Beast Mastery"] = "HUNTER", ["Marksmanship"] = "HUNTER", ["Survival"] = "HUNTER" },
	Mage = { ["Arcane"] = "CASTER_DPS", ["Fire"] = "CASTER_DPS", ["Frost"] = "CASTER_DPS" },
	Paladin = { ["Holy"] = "HEALER", ["Protection"] = "TANK_BLOCK", ["Retribution"] = "MELEE_2H" },
	Priest = { ["Discipline"] = "HEALER", ["Holy"] = "HEALER", ["Shadow"] = "CASTER_DPS" },
	Rogue = { ["Assassination"] = "MELEE_DW", ["Combat"] = "MELEE_DW", ["Subtlety"] = "MELEE_DW" },
	Shaman = { ["Elemental"] = "CASTER_DPS", ["Enhancement"] = "MELEE_DW", ["Restoration"] = "HEALER" },
	Warlock = { ["Affliction"] = "CASTER_DPS", ["Demonology"] = "CASTER_DPS", ["Destruction"] = "CASTER_DPS", ["Destruction Fire"] = "CASTER_DPS" },
	Warrior = { ["Arms"] = "MELEE_2H", ["Fury"] = "MELEE_DW", ["Protection"] = "TANK_BLOCK" },
}

local function Pct(v) return format("%.2f%%", v or 0) end
local function RatingBonus(cr)
	local ok, v = pcall(GetCombatRatingBonus, cr)
	return (ok and v) or 0
end
local function Mod(fn)
	local ok, v = pcall(fn)
	return (ok and v) or 0
end

local CAPS
local function CapLines(kind)
	if not CAPS then
		local LS = {
			hit_spell = L["Spell Hit"] or "Spell Hit", hit_melee = L["Melee Hit"] or "Melee Hit",
			hit_ranged = L["Ranged Hit"] or "Ranged Hit", crit = L["Crit"] or "Crit",
			crit_spell = L["Spell Crit"] or "Spell Crit", expertise = L["Expertise"] or "Expertise",
			defense = L["Defense"] or "Defense", avoidance = L["Avoidance"] or "Avoidance",
			specials = L["specials"] or "specials", dodge = L["dodge"] or "dodge",
		}
		local function spellHit() return Pct(RatingBonus(8) + (GetSpellHitModifier and Mod(GetSpellHitModifier) or 0)) end
		local function meleeHit() return Pct(RatingBonus(6) + (GetHitModifier and Mod(GetHitModifier) or 0)) end
		local function rangedHit() return Pct(RatingBonus(7) + (GetHitModifier and Mod(GetHitModifier) or 0)) end
		local function expertise()
			if GetExpertise then
				local ok, e = pcall(GetExpertise)
				if ok and e then return format("%.2f%% (%.1f exp) %s", e * 0.25, e, LS.dodge) end
			end
			return Pct(RatingBonus(24))
		end
		local function defense()
			local base, mod2 = UnitDefense("player")
			return tostring((base or 0) + (mod2 or 0))
		end
		local function avoidance()
			return Pct((GetDodgeChance() or 0) + (GetParryChance() or 0) + (GetBlockChance() or 0) + 5)
		end
		local function meleeCrit() return Pct(GetCritChance and GetCritChance() or 0) end
		local function spellCrit() return Pct(GetSpellCritChance and GetSpellCritChance(2) or 0) end
		local function rangedCrit() return Pct(GetRangedCritChance and Mod(GetRangedCritChance) or 0) end
		CAPS = {
			CASTER_DPS = {
				{ LS.hit_spell, "16% (202 rtg)", spellHit },
				{ LS.crit_spell, "—", spellCrit },
			},
			HEALER = {
				{ LS.hit_spell, L["No cap (healing)"] or "No cap (healing)", function() return "—" end },
				{ LS.crit_spell, "—", spellCrit },
			},
			MELEE_2H = {
				{ LS.hit_melee, "9% (142 rtg) " .. LS.specials, meleeHit },
				{ LS.expertise, "6.5% " .. LS.dodge .. " (26)", expertise },
				{ LS.crit, "—", meleeCrit },
			},
			MELEE_DW = {
				{ LS.hit_melee, "9% " .. LS.specials .. " / 28% DW", meleeHit },
				{ LS.expertise, "6.5% " .. LS.dodge .. " (26)", expertise },
				{ LS.crit, "—", meleeCrit },
			},
			HUNTER = {
				{ LS.hit_ranged, "9% (142 rtg)", rangedHit },
				{ LS.crit, "—", rangedCrit },
			},
			TANK_BLOCK = {
				{ LS.defense, "490 " .. (L["anti-crit"] or "anti-crit"), defense },
				{ LS.avoidance, "102.4% " .. (L["anti-crush"] or "anti-crush"), avoidance },
				{ LS.hit_melee, "9% (142 rtg)", meleeHit },
				{ LS.expertise, "6.5% " .. LS.dodge, expertise },
			},
			TANK_DRUID = {
				{ LS.defense, "415 " .. (L["+ resilience"] or "+ resilience"), defense },
				{ LS.hit_melee, "9% (142 rtg)", meleeHit },
				{ LS.expertise, "6.5% " .. LS.dodge, expertise },
			},
		}
	end
	return CAPS[kind] or {}
end

function BG:CreateStatsPanel()
	if B.statsPanel or not B then return end
	local p = CreateFrame("Frame", "SentinelUIBisStatsPanel", B, S.BackdropTemplate)
	p:SetSize(230, 90)
	p:SetPoint("TOPLEFT", B, "TOPRIGHT", 2, 0)
	S:CreateBackdrop(p, "Default")
	S:EnablePixelSnap(p)
	p.title = S:FontString(p, 12, "OUTLINE", S.media.unitFont)
	p.title:SetPoint("TOP", 0, -8)
	p.title:SetText(L["Stats Cap"] or "Stats Cap")
	p.lines = {}
	for i = 1, 4 do
		local l = {}
		l.h = S:FontString(p, 11, "OUTLINE")
		l.c = S:FontString(p, 10, "")
		l.v = S:FontString(p, 10, "")
		p.lines[i] = l
	end
	B.statsPanel = p
	p:Hide()
end

function BG:RefreshStatsPanel()
	local p = B and B.statsPanel
	if not p then return end
	local cn = D.classes[self.selCi]
	local sn = SpecName(self.selCi, self.selSi)
	local kind = cn and sn and (SPEC_KIND[cn] or {})[sn]
	local caps = kind and CapLines(kind) or {}
	if #caps == 0 then
		p:Hide()
		return
	end
	p.title:SetText((L["Stats Cap"] or "Stats Cap") .. " — " .. (sn or "?"))
	local y = 30
	for i, entry in ipairs(caps) do
		local l = p.lines[i]
		if not l then break end
		l.h:ClearAllPoints() l.h:SetPoint("TOPLEFT", 12, -y)
		l.h:SetText(entry[1])
		l.h:SetTextColor(1, 0.84, 0)
		y = y + 15
		l.c:ClearAllPoints() l.c:SetPoint("TOPLEFT", 18, -y)
		l.c:SetText((L["Cap"] or "Cap") .. ": " .. entry[2])
		l.c:SetTextColor(0.7, 0.7, 0.7)
		y = y + 14
		l.v:ClearAllPoints() l.v:SetPoint("TOPLEFT", 18, -y)
		l.v:SetText((L["Current"] or "Current") .. ": " .. (entry[3]() or "?"))
		l.v:SetTextColor(0.4, 1, 0.4)
		y = y + 20
		l.h:Show() l.c:Show() l.v:Show()
	end
	for i = #caps + 1, #p.lines do
		p.lines[i].h:Hide() p.lines[i].c:Hide() p.lines[i].v:Hide()
	end
	p:SetHeight(y + 10)
	p:SetShown(B:IsShown() and self.db.statsPanel ~= false)
end

function BG:OpenBrowser(ci, si, pi)
	D = D or SUIBisData
	if not D or not D.bis then
		S:Print((L["BiS Guide"] or "BiS Guide") .. ": " .. (L["data not loaded"] or "data not loaded"))
		return
	end
	if not B then self:CreateBrowser() end
	self.selCi = ci or self.selCi or self:PlayerClassIndex() or 1
	self.selSi = si or self.selSi or self:GetPlayerSpec() or 1
	self.selPi = pi or self.selPi or self.db.phaseIndex or #(D.phases or {})
	B:Show()
	self:RefreshBrowser()
end

-- ---------------------------------------------------------------------------
-- inspect integration
-- ---------------------------------------------------------------------------
function BG:DetectInspectedSpec(unit, ci)
	-- count talent points per tree via the inspectable talent API
	if not (GetTalentTabInfo and GetNumTalentTabs) then return 1 end
	local bestTab, bestPts
	for t = 1, GetNumTalentTabs() do
		local name, _, pts
		local ok = pcall(function()
			name, _, pts = GetTalentTabInfo(t, true)
		end)
		if ok and pts and (not bestPts or pts > bestPts) then
			bestTab, bestPts = name, pts
		end
	end
	if bestTab then
		local si = self:TreeToSpec(ci, bestTab)
		if si then return si end
	end
	return 1
end

function BG:InspectBis()
	local unit = InspectFrame and InspectFrame.unit or "target"
	if not (unit and UnitExists(unit)) then return end
	local _, f = UnitClass(unit)
	local ci
	for i, cn in ipairs(D.classes or {}) do
		if CLASS_FILE[cn] == f then ci = i break end
	end
	if not ci then return end
	self.inspectedItems = {}
	for s = 1, 18 do
		if s ~= 4 then
			local id = GetInventoryItemID(unit, s)
			if id then self.inspectedItems[id] = true end
		end
	end
	local si = self:DetectInspectedSpec(unit, ci)
	self:OpenBrowser(ci, si)
end

function BG:CreateInspectButton()
	if not (InspectFrame and self.db.inspectBtn) then return end
	if self.inspectBtn then return end
	local b = CreateFrame("Button", nil, InspectFrame, "UIPanelButtonTemplate")
	b:SetSize(80, 20)
	b:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMLEFT", 10, 42)
	b:SetText(L["BiS List"] or "BiS List")
	S:SkinButton(b)
	b:SetScript("OnClick", function() S:SafeCall("BisGuide:InspectBis", BG.InspectBis, BG) end)
	self.inspectBtn = b
end

function BG:CreateTalentButton()
	local tf = _G.PlayerTalentFrame
	if not (tf and self.db.talentBtn ~= false) then return end
	if self.talentBtn then return end
	local b = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
	b:SetSize(90, 20)
	b:SetPoint("BOTTOMRIGHT", tf, "TOPRIGHT", 0, -2)
	b:SetText(L["BiS Talents"] or "BiS Talents")
	S:SkinButton(b)
	b:SetScript("OnClick", function() S:SafeCall("BisGuide:Talents", BG.ToggleWindow, BG, "talents") end)
	b:SetShown(tf:IsShown())
	hooksecurefunc(tf, "Show", function() b:Show() end)
	hooksecurefunc(tf, "Hide", function() b:Hide() end)
	self.talentBtn = b
end

-- ---------------------------------------------------------------------------
-- init / events
-- ---------------------------------------------------------------------------
function BG:ChatCommand(arg)
	arg = strlower(strtrim and strtrim(arg or "") or arg or "")
	if arg == "conso" or arg == "consumes" or arg == "consumables" then self:ToggleWindow("consumes")
	elseif arg == "rot" or arg == "rotation" then self:ToggleWindow("rotation")
	elseif arg == "tal" or arg == "talents" then self:ToggleWindow("talents")
	else self:OpenBrowser() end
end

function BG:Initialize()
	D = SUIBisData
	if not (D and D.bis) then
		S:Debug("BisGuide: SUIBisData missing")
		return
	end
	self:BuildIndex()
	self.db.phaseIndex = self.db.phaseIndex or #(D.phases or {})
	self.selPi = self.db.phaseIndex

	-- item tooltip annotation (modern path + classic fallback)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,
			function(tt) S:SafeCall("BisGuide:TipItem", BG.OnTooltipItem, BG, tt) end)
	else
		GameTooltip:HookScript("OnTooltipSetItem",
			function(tt) S:SafeCall("BisGuide:TipItem", BG.OnTooltipItem, BG, tt) end)
	end

	-- inspect button appears once InspectFrame exists; talent button once the
	-- talent UI is loaded
	if InspectFrame then self:CreateInspectButton() end
	if _G.PlayerTalentFrame then self:CreateTalentButton() end
	if not (InspectFrame and _G.PlayerTalentFrame) then
		local h = CreateFrame("Frame")
		h:RegisterEvent("ADDON_LOADED")
		h:SetScript("OnEvent", function(_, _, name)
			if name == "Blizzard_InspectUI" and InspectFrame then
				BG:CreateInspectButton()
			end
			if (name == "Blizzard_TalentUI" or name == "Blizzard_PlayerSpells") and _G.PlayerTalentFrame then
				BG:CreateTalentButton()
			end
			if (not InspectFrame or self.inspectBtn) and (not _G.PlayerTalentFrame or self.talentBtn) then
				h:UnregisterAllEvents()
			end
		end)
	end

	-- star quest rewards that are BiS for the player's spec
	if QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", function()
			C_Timer.After(0, function() S:SafeCall("BisGuide:Rewards", BG.MarkQuestRewards, BG) end)
		end)
	end
	self:RegisterEvent("QUEST_ITEM_UPDATE", function()
		S:SafeCall("BisGuide:Rewards", BG.MarkQuestRewards, BG)
	end)

	SLASH_SUIBIS1 = "/suibis"
	SLASH_SUIBIS2 = "/bisguide"
	SlashCmdList["SUIBIS"] = function(a) S:SafeCall("BisGuide:Cmd", BG.ChatCommand, BG, a) end

	-- minimap launcher (SentinelUI monogram family)
	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "bisguide", glyph = "BG",
		store = self.private.minimap, angle = 60,
		onLeft = function()
			if B and B:IsShown() then B:Hide() else BG:OpenBrowser() end
		end,
		onRight = function() S:ToggleConfig("bisguide") end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. (L["BiS Guide"] or "BiS Guide"))
			GameTooltip:AddLine(L["Left-click: browser  |  Right-click: options  |  Drag: move"], 1, 1, 1)
		end,
	})
end

function BG:Update()
	if B and B:IsShown() then self:RefreshBrowser() end
	if self.db.inspectBtn then
		self:CreateInspectButton()
	end
	if self.inspectBtn then
		self.inspectBtn:SetShown(self.db.inspectBtn ~= false)
	end
end
