-- LootBrowser: standalone loot table browser (AtlasLoot-style) powered by the
-- generated SentinelUI_LootData addon. Browses instances/collections/factions/
-- PvP/crafting content by category -> boss -> loot table, shows item tooltips,
-- drop chances, prices and per-difficulty tables. It also annotates item
-- tooltips everywhere with "where does this drop" info. The database is
-- generated offline by gen_loot_data.py; nothing is read from other addons.
local _, ns = ...
local S = ns.S
local L = S.L
local LB = S:NewModule("LootBrowser", "lootbrowser")

local _G = _G
local ipairs, pairs, wipe, tinsert, sort = ipairs, pairs, wipe, table.insert, table.sort
local format, floor = string.format, math.floor
local strmatch, strlower, strtrim, tonumber, type = strmatch, strlower, strtrim, tonumber, type
local CreateFrame, C_Timer = CreateFrame, C_Timer

local D -- SUILootData
local V -- SUILootData.<versionTag>
local F -- browser frame
local sel = { ver = nil, cat = nil, inst = nil, boss = 1, diff = nil, page = 1, query = "" }
local COLS, ROWS, BTN_H = 2, 12, 27
local PAGE_ITEMS = COLS * ROWS

-- ---------------------------------------------------------------------------
-- localisation + version helpers
-- ---------------------------------------------------------------------------
local function LocStr(en)
	if type(en) ~= "string" then return en end
	local loc = D and D.loc
	if loc then
		local lt = loc[GetLocale()] or (GetLocale() == "esMX" and loc.esES)
		if lt and lt[en] and lt[en] ~= "" then return lt[en] end
	end
	return en
end
LB.LocStr = LocStr

local DIFF_L = {
	NORMAL = "Normal", HEROIC = "Heroic",
	["10RAID"] = "10", ["10RAIDH"] = "10 " .. (ITEM_HEROIC or "Heroic"),
	["25RAID"] = "25", ["25RAIDH"] = "25 " .. (ITEM_HEROIC or "Heroic"),
}
local function DiffName(en)
	if type(en) ~= "string" then return tostring(en) end
	return DIFF_L[en] or L[en] or LocStr(en)
end

local function VersionTag()
	if C_Seasons and C_Seasons.GetActiveSeason and C_Seasons.GetActiveSeason() == 2 then
		return "SOD"
	end
	if S.isTBC then return "TBC"
	elseif S.isWrath then return "WRATH"
	elseif S.isCata or S.isMists then return "WRATH" -- best available classic data
	elseif S.isRetail then return "RETAIL"
	else return "VANILLA" end
end

local VERSION_LABEL = {
	VANILLA = "Classic", TBC = "The Burning Crusade", WRATH = "Wrath of the Lich King",
	SOD = "Season of Discovery", RETAIL = "Retail",
}
local VERSION_NUM = { VANILLA = 1, SOD = 1, TBC = 2, WRATH = 3, RETAIL = 99 }

-- content only makes sense if the client's item database contains it:
-- a TBC client has no Wrath items, so don't offer those tables
local function ClientMaxVersion()
	if S.isRetail then return 99 end
	if S.isMists then return 5 end
	if S.isCata then return 4 end
	if S.isWrath then return 3 end
	if S.isTBC then return 2 end
	return 1
end

local function VersionVisible(tag)
	local n = VERSION_NUM[tag] or 99
	if tag == "SOD" then
		return C_Seasons and C_Seasons.GetActiveSeason and C_Seasons.GetActiveSeason() == 2
	end
	return n <= ClientMaxVersion()
end

-- keep sel.ver in sync with the version table actually displayed, otherwise
-- a missing table leaves V=VANILLA while the dropdown claims TBC
local function ResolveVersion()
	if D and D[sel.ver] and D[sel.ver].inst and #D[sel.ver].inst > 0 then
		V = D[sel.ver]
		return
	end
	for _, tag in ipairs({ "VANILLA", "SOD", "TBC", "WRATH", "RETAIL" }) do
		local tv = D and D[tag]
		if type(tv) == "table" and tv.inst and #tv.inst > 0 then
			sel.ver, V = tag, tv
			return
		end
	end
	V = nil
end

local function CatName(ci)
	local c = V and V.cats and V.cats[ci]
	return (c and (L[c] or LocStr(c))) or "?"
end

-- the data carries "Alliance" / "Horde" categories; only show the player's own
local function CatVisible(ci)
	local c = V and V.cats and V.cats[ci]
	if c == "Alliance" then return S.myFaction == "Alliance" end
	if c == "Horde" then return S.myFaction == "Horde" end
	return true
end

local function InstName(inst)
	local n = inst.name
	if not n and inst.map and C_Map and C_Map.GetAreaInfo then
		n = C_Map.GetAreaInfo(inst.map)
	end
	if not n and inst.fac then
		n = GetFactionInfoByID and GetFactionInfoByID(inst.fac)
	end
	if not n and inst.k then
		n = inst.k:gsub("(%u)", " %1"):gsub("^ ", "")
	end
	n = LocStr(n) or inst.k
	if inst.fmt then
		n = format(inst.fmt, n)
	end
	return n
end

local function BossName(b)
	return b.n and LocStr(b.n) or (L["Miscellaneous"] or "Misc")
end

-- ---------------------------------------------------------------------------
-- selection state
-- ---------------------------------------------------------------------------

local function DiffKeys(boss)
	local t = {}
	if boss and boss.d then
		for k in pairs(boss.d) do t[#t + 1] = k end
		sort(t)
	end
	return t
end

local function CurInst()
	if not (V and V.inst and sel.inst) then return end
	return V.inst[sel.inst]
end

local function CurBoss()
	local inst = CurInst()
	return inst and inst.b and inst.b[sel.boss]
end

local function CurEntries()
	local b = CurBoss()
	if not (b and b.d) then return {} end
	local keys = DiffKeys(b)
	if #keys == 0 then return {} end
	if not sel.diff or not b.d[sel.diff] then
		-- prefer the registered "normal-ish" first diff
		sel.diff = keys[1]
	end
	return b.d[sel.diff] or {}
end

-- entry -> {id, horde, alliance, price, amount, header}
local function EntryID(e)
	if type(e) == "number" then return e end
	if type(e) == "table" then
		if S.myFaction == "Alliance" and e.a then return e.a end
		if S.myFaction == "Horde" and e.h then return e.h end
		return e.i or e.h or e.a
	end
end

local function Normalize(e)
	if type(e) == "number" then return { id = e } end
	if type(e) == "table" then
		return {
			id = EntryID(e), horde = e.h, alliance = e.a,
			price = e.p, amount = e.n or e.n2, header = e.t,
			quest = e.q, ignore = e.ig,
		}
	end
	return {}
end

-- ---------------------------------------------------------------------------
-- item icon loading (shared pattern with BisGuide, kept self-contained)
-- ---------------------------------------------------------------------------
local pendingIcon = {}
local iconWatcher = CreateFrame("Frame")
iconWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local function CachedIcon(iid)
	local _, _, _, _, icon = GetItemInfoInstant and GetItemInfoInstant(iid)
	if icon and icon > 0 then return icon end
	if C_Item and C_Item.GetItemIconByID then
		local ic = C_Item.GetItemIconByID(iid)
		if ic and ic > 0 then return ic end
	end
	if GetItemIcon then
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
	if Item and Item.CreateFromItemID then
		local ok, it = pcall(Item.CreateFromItemID, Item, iid)
		if ok and it and it.ContinueOnItemLoad then
			local ok2 = pcall(it.ContinueOnItemLoad, it, function() ResolveIcons(iid) end)
			if ok2 then return end
		end
	end
	if GetItemInfo then pcall(GetItemInfo, iid) end
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
				pendingIcon[iid] = nil
			end
		end
		C_Timer.After(0.6, poll)
	end
	lst[#lst + 1] = cb
	cb(134400)
end
LB.ItemIcon = ItemIcon

-- ---------------------------------------------------------------------------
-- drop chance + price helpers
-- ---------------------------------------------------------------------------
local function DropChance(inst, boss, iid)
	local npc = boss and boss.npc
	npc = type(npc) == "table" and npc[1] or npc
	local dd = D and D.drop
	if npc and dd and dd[npc] and dd[npc][iid] then
		return dd[npc][iid]
	end
end

-- price keys -> token item (names come localized from the client item cache)
local PRICE_ITEM = {
	burningblossom = 23247, ancestrycoin = 21100, NecroticRune = 22484,
	wildoffering = 221262, emeraldchip = 219927, firelandsember = 227801,
	TUF = 226404, silvermassacre = 221365, silverblood = 213169,
	goldblood = 213170, bloodCakedSilver = 235142, bloodCakedGold = 235143,
	holydust = 29735, arcanerune = 29736, SpiritShard = 28558, spiritshard = 28558,
	HalaaRT = 26044, HalaaBT = 26045, halaa = 26045,
	MarkOfThrallmar = 24581, MarkOfHonorHold = 24579,
	BoJ = 29434, badge = 29434, glowcap = 24245,
	ApexisC = 32572, ApexisS = 32569, Brewfest = 37829, sunmote = 34664,
	pvpAlterac = 20560, pvpWarsong = 20558, pvpArathi = 20559, pvpEye = 29024,
}
-- price keys -> Blizzard currencyID (name via C_CurrencyInfo)
local PRICE_CURRENCY = {
	honor = 1901, honorA = 1901, honorH = 1901, arena = 1900,
	epicurean = 81, championsSeal = 241,
	EmblemOfHeroism = 101, EmblemOfValor = 102, EmblemOfTriumph = 301,
	EmblemOfConquest = 221, EmblemOfFrost = 341,
	SiderealEssence = 2589, DefilersScourgestone = 2711,
	cpvpAlterac = 121, cpvpWarsong = 125, cpvpArathi = 122, cpvpEye = 123,
	cpvpWintergrasp = 126, cpvpIsle = 321, cpvpStrand = 124,
}
local function CurName(cur)
	if PRICE_CURRENCY[cur] and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local ci = C_CurrencyInfo.GetCurrencyInfo(PRICE_CURRENCY[cur])
		if ci and ci.name then return ci.name end
	end
	local iid = PRICE_ITEM[cur]
	if iid then
		local nm = GetItemInfo(iid)
		if nm then return nm end
		WarmItem(iid)
	end
	return L[cur] or cur
end
local function PriceText(p)
	if not p then return end
	local out = {}
	for cur, amt in p:gmatch("([%a]+):([%d%.]+)") do
		if cur == "money" then
			amt = tonumber(amt) or 0
			local g, s, c = floor(amt / 10000), floor(amt / 100) % 100, amt % 100
			tinsert(out, format("%dg %ds %dc", g, s, c))
		else
			tinsert(out, format("%s x%s", CurName(cur), amt))
		end
	end
	if #out == 0 then return p end
	return table.concat(out, ", ")
end

-- ---------------------------------------------------------------------------
-- UI construction
-- ---------------------------------------------------------------------------
local function MakeDD(parent, name, w, init)
	local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(dd, w or 140)
	UIDropDownMenu_Initialize(dd, init)
	return dd
end

local function SetDDText(dd, text)
	UIDropDownMenu_SetText(dd, text)
end

local function MakeInstRow(i)
	local inst = F.instRows[i]
	if not inst then
		inst = CreateFrame("Button", nil, F.instContent)
		inst:SetHeight(20)
		inst.name = S:FontString(inst, 11, "OUTLINE")
		inst.name:SetPoint("LEFT", 6, 0)
		inst.name:SetJustifyH("LEFT")
		inst.lvl = S:FontString(inst, 10)
		inst.lvl:SetPoint("RIGHT", -18, 0)
		inst.name:SetPoint("RIGHT", inst.lvl, "LEFT", -4, 0)
		inst.name:SetWordWrap(false)
		inst.hl = inst:CreateTexture(nil, "BACKGROUND")
		inst.hl:SetAllPoints()
		inst.hl:SetColorTexture(0.3, 0.6, 1, 0.18)
		inst.hl:Hide()
		inst:SetScript("OnClick", function()
			sel.inst = inst.idx
			sel.boss, sel.page, sel.diff = 1, 1, nil
			LB:RefreshAll()
		end)
		F.instRows[i] = inst
	end
	return inst
end

local function MakeItemBtn(col, row)
	local b = F.itemBtns[(row - 1) * COLS + col]
	if b then return b end
	b = CreateFrame("Button", nil, F.itemArea)
	b:SetSize(250, BTN_H)
	b:SetPoint("TOPLEFT", (col - 1) * 254 + 4, -((row - 1) * (BTN_H + 1)) - 4)
	b.ic = b:CreateTexture(nil, "ARTWORK")
	b.ic:SetSize(BTN_H - 3, BTN_H - 3)
	b.ic:SetPoint("LEFT", 2, 0)
	b.ic:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	b.nm = S:FontString(b, 11, "OUTLINE")
	b.nm:SetPoint("TOPLEFT", b.ic, "TOPRIGHT", 6, -1)
	b.nm:SetPoint("RIGHT", -2, 0)
	b.nm:SetJustifyH("LEFT")
	b.sub = S:FontString(b, 9)
	b.sub:SetPoint("TOPLEFT", b.nm, "BOTTOMLEFT", 0, -2)
	b.sub:SetPoint("RIGHT", -2, 0)
	b.sub:SetJustifyH("LEFT")
	b.sub:SetTextColor(0.7, 0.7, 0.7)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(1, 1, 1, 0.02)
	b:SetScript("OnEnter", function()
		b.bg:SetColorTexture(1, 1, 1, 0.07)
		if b.eid and b.eid > 0 then
			GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:" .. b.eid)
			local drop = b.drop
			local extra = {}
			if drop then extra[#extra + 1] = format("|cff00ff00%s %.1f%%|r", L["Drop chance"] or "Drop chance", drop) end
			if b.price then extra[#extra + 1] = "|cffffff00" .. b.price .. "|r" end
			if #extra > 0 then
				GameTooltip:AddLine(" ")
				for _, x in ipairs(extra) do GameTooltip:AddLine(x) end
				GameTooltip:Show()
			end
		end
	end)
	b:SetScript("OnLeave", function()
		b.bg:SetColorTexture(1, 1, 1, 0.02)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(_, btn)
		if b.eid and IsShiftKeyDown() and ChatEdit_InsertLink then
			local _, link = GetItemInfo(b.eid)
			if link then ChatEdit_InsertLink(link) end
		elseif b.eid and IsControlKeyDown() and DressUpItemLink then
			local _, link = GetItemInfo(b.eid)
			if link then DressUpItemLink(link) end
		end
	end)
	F.itemBtns[(row - 1) * COLS + col] = b
	return b
end

-- ---------------------------------------------------------------------------
-- refresh
-- ---------------------------------------------------------------------------
local function InstMatches(inst, q)
	if q == "" then return true end
	local n = strlower(InstName(inst))
	if n:find(q, 1, true) then return true end
	for _, b in ipairs(inst.b or {}) do
		local bn = strlower(BossName(b))
		if bn:find(q, 1, true) then return true end
	end
	return false
end

function LB:RefreshInstList()
	if not F then return end
	local rows = F.instRows
	local n = 0
	if V and V.inst then
		for i, inst in ipairs(V.inst) do
			if inst.c == sel.cat and InstMatches(inst, sel.query) then
				n = n + 1
				local r = MakeInstRow(n)
				r.idx = i
				r:SetPoint("TOPLEFT", 0, -(n - 1) * 20)
				r:SetPoint("TOPRIGHT", 0, -(n - 1) * 20)
				r.name:SetText(InstName(inst))
				r.lvl:SetText(inst.lvl and format("%d-%d", inst.lvl[1] or 0, inst.lvl[3] or inst.lvl[2] or 0) or "")
				r.hl:SetShown(i == sel.inst)
				r:Show()
			end
		end
	end
	for i = n + 1, #rows do rows[i]:Hide() end
	F.instContent:SetHeight(math.max(1, n * 20))

	-- keep selection valid
	local inst = CurInst()
	if not inst or inst.c ~= sel.cat then
		sel.inst = nil
		for i, x in ipairs(V.inst) do
			if x.c == sel.cat then sel.inst = i break end
		end
		sel.boss, sel.page, sel.diff = 1, 1, nil
	end
end

function LB:RefreshBossDD()
	if not F then return end
	local inst = CurInst()
	UIDropDownMenu_Initialize(F.bossDD, function(_, level)
		if not inst then return end
		for i, b in ipairs(inst.b) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = BossName(b)
			info.checked = i == sel.boss
			info.func = function()
				sel.boss, sel.page, sel.diff = i, 1, nil
				LB:RefreshItems()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	local b = CurBoss()
	SetDDText(F.bossDD, b and BossName(b) or "-")
end

local DIFF_BTN_W = 66
function LB:RefreshDiffBtns()
	if not F then return end
	local inst = CurInst()
	local keys = DiffKeys(CurBoss())
	local btns = F.diffBtns
	local n = 0
	for i, dk in ipairs(keys) do
		n = n + 1
		local b = btns[n]
		if not b then
			b = CreateFrame("Button", nil, F.diffBar)
			S:SkinButton(b)
			b.txt = S:FontString(b, 10, "OUTLINE")
			b.txt:SetPoint("CENTER")
			b:SetScript("OnClick", function()
				sel.diff, sel.page = b.dk, 1
				LB:RefreshDiffBtns()
				LB:RefreshItems()
			end)
			btns[n] = b
		end
		b.dk = dk
		local dn = (inst and inst.dn and inst.dn[dk]) or tostring(dk)
		b.txt:SetText(DiffName(dn))
		local w = math.max(48, b.txt:GetStringWidth() + 14)
		b:SetSize(w, 18)
		b:ClearAllPoints()
		if n == 1 then
			b:SetPoint("LEFT", 0, 0)
		else
			b:SetPoint("LEFT", btns[n - 1], "RIGHT", 4, 0)
		end
		b:SetShown(true)
		if dk == sel.diff then b:SetAlpha(1) else b:SetAlpha(0.55) end
	end
	for i = n + 1, #btns do btns[i]:Hide() end
end

function LB:RefreshItems()
	if not F then return end
	self:RefreshBossDD()
	self:RefreshDiffBtns()
	local inst = CurInst()
	local boss = CurBoss()
	local entries = CurEntries()

	-- header line
	local title = inst and InstName(inst) or ""
	if boss then
		title = title .. "  |cff888888—|r  " .. BossName(boss)
		-- boss.l is a level list per data entry ({15,24,32}), not a scalar
		local bl = type(boss.l) == "table" and boss.l[1] or boss.l
		if type(bl) == "number" and bl < 100 then
			title = title .. format("  |cff777777[%d]|r", bl)
		end
	end
	F.subTitle:SetText(title)
	F.phaseNote:SetText(inst and inst.ph and format("%s %d", L["Phase"] or "Phase", inst.ph) or "")

	-- flat entry list (headers become their own row spanning both columns)
	local flat = {}
	for _, e in ipairs(entries) do
		local ne = Normalize(e)
		if not ne.ignore then flat[#flat + 1] = ne end
	end

	local startIdx = (sel.page - 1) * PAGE_ITEMS + 1
	local shown = 0
	local col, row = 1, 1
	for i = startIdx, #flat do
		local e = flat[i]
		if e.header then
			-- header label row
			if row <= ROWS then
				local hb = F.headRows[row]
				if not hb then
					hb = S:FontString(F.itemArea, 11, "OUTLINE")
					F.headRows[row] = hb
				end
				hb:SetPoint("TOPLEFT", 4, -((row - 1) * (BTN_H + 1)) - 4)
				hb:SetText("|cffffcc00" .. LocStr(e.header) .. "|r")
				hb:Show()
				row = row + 1
				col = 1
			end
		else
			if row <= ROWS then
				local b = MakeItemBtn(col, row)
				b.eid = e.id
				b.price = e.price and PriceText(e.price)
				b.drop = e.id and DropChance(inst, boss, e.id)
				b.nm:SetText(e.id and (GetItemInfo(e.id) or ("#" .. e.id)) or "?")
				if e.id then
					local nm = GetItemInfo(e.id)
					if not nm then
						local btn = b
						WarmItem(e.id)
						C_Timer.After(1.2, function()
							local nm2 = GetItemInfo(e.id)
							if nm2 and btn:IsShown() then btn.nm:SetText(nm2) end
						end)
					end
					ItemIcon(e.id, function(t) if b:IsShown() and b.eid == e.id then b.ic:SetTexture(t) end end)
					-- quality color on the name
					local _, _, q = GetItemInfo(e.id)
					if q then
						local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
						if c then b.nm:SetTextColor(c.r, c.g, c.b) end
					else
						b.nm:SetTextColor(1, 1, 1)
					end
				else
					b.ic:SetTexture(134400)
					b.nm:SetTextColor(1, 1, 1)
				end
				b.sub:SetText(e.amount and format("x%d", e.amount) or (e.price and b.price) or "")
				b:Show()
				shown = shown + 1
				col = col + 1
				if col > COLS then col = 1 row = row + 1 end
			end
		end
		if row > ROWS then break end
	end
	for i = shown + 1, PAGE_ITEMS do
		local b = F.itemBtns[i]
		if b then b:Hide() end
	end
	for i = row, #F.headRows do
		F.headRows[i]:Hide()
	end

	-- pagination
	local pages = math.max(1, math.ceil(#flat / PAGE_ITEMS))
	F.pageText:SetText(format("%d / %d", sel.page, pages))
	F.prevBtn:SetShown(pages > 1)
	F.nextBtn:SetShown(pages > 1)
end

function LB:RefreshAll()
	if not F then return end
	if V and V.cats and sel.cat and not CatVisible(sel.cat) then
		sel.cat = nil
		for ci = 1, #V.cats do
			if CatVisible(ci) then sel.cat = ci break end
		end
	end
	self:RefreshCatDD()
	self:RefreshInstList()
	self:RefreshItems()
end

function LB:RefreshCatDD()
	if not F or not V then return end
	UIDropDownMenu_Initialize(F.catDD, function(_, level)
		for ci = 1, #V.cats do
			if CatVisible(ci) then
			local info = UIDropDownMenu_CreateInfo()
			info.text = CatName(ci)
			info.checked = ci == sel.cat
			info.func = function()
				sel.cat = ci
				sel.inst, sel.boss, sel.page, sel.diff = nil, 1, 1, nil
				LB:RefreshAll()
			end
			UIDropDownMenu_AddButton(info, level)
			end
		end
	end)
	SetDDText(F.catDD, CatName(sel.cat))
end

function LB:RefreshVerDD()
	if not F or not D then return end
	UIDropDownMenu_Initialize(F.verDD, function(_, level)
		for tag in pairs(D) do
			if type(D[tag]) == "table" and D[tag].inst and VersionVisible(tag) then
				local info = UIDropDownMenu_CreateInfo()
				info.text = VERSION_LABEL[tag] or tag
				info.checked = tag == sel.ver
				info.func = function()
					sel.ver = tag
					V = D[tag]
					sel.cat, sel.inst, sel.boss, sel.page, sel.diff = 1, nil, 1, 1, nil
					LB:RefreshAll()
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end)
	SetDDText(F.verDD, VERSION_LABEL[sel.ver] or sel.ver)
end

function LB:CreateBrowser()
	if F then return F end
	F = CreateFrame("Frame", "SentinelUILootBrowser", UIParent, S.BackdropTemplate)
	F:SetSize(780, 560)
	F:SetPoint("CENTER")
	F:SetFrameStrata("DIALOG")
	F:EnableMouse(true)
	F:SetMovable(true)
	F:RegisterForDrag("LeftButton")
	F:SetScript("OnDragStart", F.StartMoving)
	F:SetScript("OnDragStop", F.StopMovingOrSizing)
	S:CreateBackdrop(F, "Default", "TOP")
	S:EnablePixelSnap(F)
	tinsert(UISpecialFrames, F:GetName())
	F:Hide()

	F.title = S:FontString(F, 14, "OUTLINE", S.media.unitFont)
	F.title:SetPoint("TOPLEFT", 12, -10)
	F.title:SetText("|cff66c2ffSentinelUI|r " .. (L["Loot Browser"] or "Loot Browser"))

	F.close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
	F.close:SetPoint("TOPRIGHT", -4, -4)
	if S.SkinCloseButton then S:SkinCloseButton(F.close) end

	-- top row: expansion + category dropdowns
	local function DDLabel(txt, anchor, x, y)
		local fs = S:FontString(F, 10, "OUTLINE")
		fs:SetPoint("TOPLEFT", anchor, x, y)
		fs:SetText(txt)
		return fs
	end
	DDLabel(L["Expansion"] or "Expansion", F, 10, -30)
	F.verDD = MakeDD(F, "SentinelUILootVerDD", 170, function() end)
	F.verDD:SetPoint("TOPLEFT", F, "TOPLEFT", -6, -44)
	DDLabel(L["Category"] or "Category", F, 200, -30)
	F.catDD = MakeDD(F, "SentinelUILootCatDD", 140, function() end)
	F.catDD:SetPoint("TOPLEFT", F, "TOPLEFT", 184, -44)

	-- search box
	F.search = CreateFrame("EditBox", nil, F, "InputBoxTemplate")
	F.search:SetSize(150, 20)
	F.search:SetAutoFocus(false)
	F.search:SetPoint("TOPRIGHT", -12, -32)
	F.search:SetMaxLetters(60)
	F.search:SetScript("OnTextChanged", function(eb)
		sel.query = strtrim(strlower(eb:GetText() or ""))
		LB:RefreshInstList()
		LB:RefreshItems()
	end)
	F.search:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
	F.search:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
	local slbl = S:FontString(F, 10, "OUTLINE")
	slbl:SetPoint("BOTTOMRIGHT", F.search, "TOPRIGHT", 0, 2)
	slbl:SetText(L["Search"] or "Search")

	-- left: instance list in a scroll frame
	F.instScroll = CreateFrame("ScrollFrame", "SentinelUILootInstScroll", F, "UIPanelScrollFrameTemplate")
	F.instScroll:SetPoint("TOPLEFT", 12, -86)
	F.instScroll:SetSize(244, F:GetHeight() - 100)
	F.instContent = CreateFrame("Frame", nil, F.instScroll)
	F.instContent:SetSize(224, 1)
	F.instScroll:SetScrollChild(F.instContent)
	if F.instScroll.ScrollBar then S:SkinScrollBar(F.instScroll.ScrollBar) end
	F.instRows = {}

	-- right: boss dropdown + difficulty bar + item area
	DDLabel(L["Boss"] or "Boss", F, 268, -86)
	F.bossDD = MakeDD(F, "SentinelUILootBossDD", 230, function() end)
	F.bossDD:SetPoint("TOPLEFT", F, "TOPLEFT", 252, -100)

	F.diffBar = CreateFrame("Frame", nil, F)
	F.diffBar:SetPoint("TOPLEFT", 262, -140)
	F.diffBar:SetSize(500, 20)
	F.diffBtns = {}

	F.subTitle = S:FontString(F, 12, "OUTLINE")
	F.subTitle:SetPoint("TOPLEFT", 262, -164)
	F.subTitle:SetPoint("RIGHT", F, "RIGHT", -100, 0)
	F.subTitle:SetJustifyH("LEFT")
	F.subTitle:SetWordWrap(false)
	F.phaseNote = S:FontString(F, 10, "OUTLINE")
	F.phaseNote:SetPoint("TOPRIGHT", -14, -166)

	F.itemArea = CreateFrame("Frame", nil, F, S.BackdropTemplate)
	F.itemArea:SetPoint("TOPLEFT", 258, -182)
	F.itemArea:SetSize(COLS * 254 + 8, ROWS * (BTN_H + 1) + 8)
	S:CreateBackdrop(F.itemArea, "Transparent")
	F.itemBtns = {}
	F.headRows = {}

	-- pagination
	F.prevBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
	F.prevBtn:SetSize(70, 20)
	F.prevBtn:SetPoint("BOTTOMLEFT", 262, 10)
	F.prevBtn:SetText("<")
	S:SkinButton(F.prevBtn)
	F.prevBtn:SetScript("OnClick", function()
		if sel.page > 1 then sel.page = sel.page - 1 LB:RefreshItems() end
	end)
	F.nextBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
	F.nextBtn:SetSize(70, 20)
	F.nextBtn:SetPoint("LEFT", F.prevBtn, "RIGHT", 6, 0)
	F.nextBtn:SetText(">")
	S:SkinButton(F.nextBtn)
	F.nextBtn:SetScript("OnClick", function()
		sel.page = sel.page + 1
		LB:RefreshItems()
	end)
	F.pageText = S:FontString(F, 11, "OUTLINE")
	F.pageText:SetPoint("LEFT", F.nextBtn, "RIGHT", 10, 0)

	-- source hint bottom right
	F.hint = S:FontString(F, 9)
	F.hint:SetPoint("BOTTOMRIGHT", -12, 12)
	F.hint:SetText(L["Shift-click: link  |  Ctrl-click: dress up"] or "Shift-click: link  |  Ctrl-click: dress up")

	return F
end

-- ---------------------------------------------------------------------------
-- tooltip annotation: "drop source" on any item tooltip
-- ---------------------------------------------------------------------------
local srcIndex -- {itemID -> {inst=..., boss=..., typ=...}}

local SOURCE_TYPE_L = { -- mirrors SOURCE_TYPES ids from the source files
	[0] = "?", [1] = "Loot", [2] = "Quest", [3] = "Vendor",
	[4] = "First Aid", [5] = "Blacksmithing", [6] = "Leatherworking",
	[7] = "Alchemy", [8] = "Herbalism", [9] = "Cooking", [10] = "Mining",
	[11] = "Tailoring", [12] = "Engineering", [13] = "Enchanting",
	[14] = "Fishing", [15] = "Skinning", [16] = "Poisons",
	[17] = "Jewelcrafting", [18] = "Inscription",
}

local function BuildSrcIndex()
	srcIndex = {}
	local sv = D and D.src and D.src[sel.ver]
	if not (sv and sv.map) then return end
	local instByKey = {}
	if V then
		for _, inst in ipairs(V.inst) do instByKey[inst.k] = inst end
	end
	for iid, e in pairs(sv.map) do
		if type(e) == "number" then
			e = sv.map[e] -- alias: entry redirects to another item's source
		end
		if type(e) == "table" then
			-- entry is either one tuple {iniIdx, bossIdx, typ, ref, diffID}
			-- or a list of tuples for multi-source items
			local tuples = (type(e[1]) == "table") and e or { e }
			for _, t in ipairs(tuples) do
				if type(t) ~= "table" then break end
				if type(t[1]) == "number" and sv.ids and sv.ids[t[1]] then
					local inst = instByKey[sv.ids[t[1]]]
					if inst then
						local boss = inst.b and tonumber(t[2]) and inst.b[t[2]]
						srcIndex[iid] = srcIndex[iid] or {}
						srcIndex[iid][#srcIndex[iid] + 1] = {
							inst = inst, boss = boss,
							typ = tonumber(t[3]), diff = t[5],
						}
					end
				elseif tonumber(t[3]) and tonumber(t[3]) > 3 then
					-- profession source
					srcIndex[iid] = srcIndex[iid] or {}
					srcIndex[iid][#srcIndex[iid] + 1] = { typ = tonumber(t[3]) }
				end
			end
		end
	end
end

function LB:OnTooltipItem(tt)
	if not self.db.tooltipSource then return end
	local _, link = tt:GetItem()
	local iid = link and tonumber(strmatch(link, "item:(%d+)"))
	if not iid or not srcIndex then return end
	local list = srcIndex[iid]
	if not list or #list == 0 then return end
	tt:AddLine(" ")
	tt:AddLine("|cff66c2ffSentinelUI|r " .. (L["Source"] or "Source"), 0.4, 0.76, 1)
	for i = 1, math.min(3, #list) do
		local s = list[i]
		if s.inst then
			local line = InstName(s.inst)
			if s.boss then
				line = line .. " - " .. BossName(s.boss)
				local dc = DropChance(s.inst, s.boss, iid)
				if dc then line = line .. format(" (%.1f%%)", dc) end
			end
			tt:AddLine(line, 1, 1, 1)
		elseif s.typ then
			tt:AddLine(L[SOURCE_TYPE_L[s.typ]] or SOURCE_TYPE_L[s.typ] or "?", 1, 1, 1)
		end
	end
	if #list > 3 then
		tt:AddLine(format("... +%d", #list - 3), 0.7, 0.7, 0.7)
	end
end

-- ---------------------------------------------------------------------------
-- init / events
-- ---------------------------------------------------------------------------
function LB:OpenBrowser()
	self:CreateBrowser()
	if sel.cat == nil then
		ResolveVersion()
		sel.cat = 1
		sel.inst, sel.boss, sel.page, sel.diff = nil, 1, 1, nil
	end
	F:Show()
	self:RefreshVerDD()
	self:RefreshAll()
end

function LB:ToggleBrowser()
	if F and F:IsShown() then F:Hide() else self:OpenBrowser() end
end

function LB:ChatCommand()
	self:ToggleBrowser()
end

function LB:Initialize()
	D = _G.SUILootData
	if not (D and type(D) == "table" and (D.TBC or D.VANILLA or D.WRATH or D.SOD)) then
		S:Print(L["LootBrowser: no loot data for this client (enable SentinelUI_LootData)."] or "LootBrowser: no loot data for this client (enable SentinelUI_LootData).")
		return
	end
	sel.ver = VersionTag()
	ResolveVersion()
	BuildSrcIndex()

	-- tooltip source annotation
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,
			function(tt) S:SafeCall("LootBrowser:TipItem", LB.OnTooltipItem, LB, tt) end)
	else
		GameTooltip:HookScript("OnTooltipSetItem",
			function(tt) S:SafeCall("LootBrowser:TipItem", LB.OnTooltipItem, LB, tt) end)
	end

	SLASH_SUILOOT1 = "/suiloot"
	SLASH_SUILOOT2 = "/loot"
	SlashCmdList["SUILOOT"] = function() S:SafeCall("LootBrowser:Cmd", LB.ChatCommand, LB) end

	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "lootbrowser", glyph = "LB",
		store = self.private.minimap, angle = 84,
		onLeft = function() LB:ToggleBrowser() end,
		onRight = function() S:ToggleConfig("lootbrowser") end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. (L["Loot Browser"] or "Loot Browser"))
			GameTooltip:AddLine(L["Left-click: browser  |  Right-click: options  |  Drag: move"], 1, 1, 1)
		end,
	})
end

function LB:Update()
	if F and F:IsShown() then self:RefreshAll() end
end
