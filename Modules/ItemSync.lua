-- ItemSync (BagSync replacement): tracks bag/bank/mail/equipped/guild-bank
-- item counts per character in the account-wide db, shows them in item
-- tooltips and offers a searchable item browser + minimap button.
local _, ns = ...
local S = ns.S
local L = S.L
local IS = S:NewModule("ItemSync", "itemsync")
local pairs, ipairs, wipe, sort = pairs, ipairs, wipe, table.sort
local format, tostring, tonumber = format, tostring, tonumber
local tinsert, tconcat = tinsert, table.concat
local strlower, strfind, strtrim = string.lower, string.find, strtrim
local CreateFrame, UIParent = CreateFrame, UIParent
local GetRealmName, UnitName, UnitClass = GetRealmName, UnitName, UnitClass
local GetInventoryItemLink = GetInventoryItemLink
local GetMoney = GetMoney
local time, date = time, date
local GameTooltip = GameTooltip
local PlaySound = PlaySound

local SCAN_DEBOUNCE = 0.4

local function GlobalStore()
	local g = S.db.global
	g.itemSync = g.itemSync or {}
	g.itemSync.guilds = g.itemSync.guilds or {}
	return g.itemSync
end

local function Store()
	local g = GlobalStore()
	local key = format("%s-%s", UnitName("player") or "?", GetRealmName() or "?")
	local e = g[key]
	if not e then
		e = { bags = {}, bank = {}, equip = {}, mail = {} }
		g[key] = e
	end
	e.mail = e.mail or {}
	local _, class = UnitClass("player")
	e.class, e.name = class, UnitName("player")
	e.key = key
	e.money = GetMoney and GetMoney() or e.money
	return e
end

local function ItemID(link)
	return link and tonumber(link:match("item:(%d+)"))
end

local function AddItem(t, id, count)
	if id then t[id] = (t[id] or 0) + (count or 1) end
end

local function ScanBagInto(t, bag)
	local n = (C_Container and C_Container.GetContainerNumSlots) and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
	for slot = 1, n or 0 do
		local info = S.GetContainerItemInfo(bag, slot)
		if info then
			local id = info.itemID or ItemID(info.hyperlink)
			AddItem(t, id, info.stackCount or 1)
		end
	end
end

local function ScanBags()
	local e = Store()
	wipe(e.bags)
	for bag = S.BACKPACK_CONTAINER or 0, S.NUM_BAG_SLOTS or 4 do
		ScanBagInto(e.bags, bag)
	end
	if S.KEYRING_CONTAINER then ScanBagInto(e.bags, S.KEYRING_CONTAINER) end
	e.bagsUpdated = time()
	e.money = GetMoney and GetMoney() or e.money
end

local function ScanBank()
	local e = Store()
	wipe(e.bank)
	ScanBagInto(e.bank, S.BANK_CONTAINER or -1)
	local first = S.BANK_BAG_FIRST or 5
	for bag = first, first + (S.NUM_BANKBAGSLOTS or 7) - 1 do
		ScanBagInto(e.bank, bag)
	end
	e.bankUpdated = time()
end

-- GetInboxItem's return layout differs between clients; the stack count is
-- the first plausible small number that isn't the itemID
local function InboxCount(i, j, id)
	if not GetInboxItem then return 1 end
	for n = 1, select("#", GetInboxItem(i, j)) do
		local v = select(n, GetInboxItem(i, j))
		if type(v) == "number" and v > 0 and v <= 1000 and v ~= id then return v end
	end
	return 1
end

local function ScanMail()
	local e = Store()
	wipe(e.mail)
	local n = GetInboxNumItems and GetInboxNumItems() or 0
	for i = 1, n do
		for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
			local link = GetInboxItemLink and GetInboxItemLink(i, j)
			if link then
				local id = ItemID(link)
				AddItem(e.mail, id, InboxCount(i, j, id))
			end
		end
	end
	e.mailUpdated = time()
end

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local function ScanEquip()
	local e = Store()
	wipe(e.equip)
	for _, slot in ipairs(EQUIP_SLOTS) do
		AddItem(e.equip, ItemID(GetInventoryItemLink("player", slot)), 1)
	end
	e.equipUpdated = time()
end

-- guild bank: scan whichever tab currently has data; each tab fills in over
-- time as the user clicks through them (GUILDBANKBAGSLOTS_CHANGED refires)
local function ScanGuildTab()
	if not GetNumGuildBankTabs or not GetGuildBankItemLink then return end
	local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
	if not tab or tab < 1 then return end
	local guild = GetGuildInfo and GetGuildInfo("player") or "Guild"
	local g = GlobalStore().guilds
	local ge = g[guild]
	if not ge then ge = { name = guild, tabs = {} } g[guild] = ge end
	local items = {}
	for slot = 1, 98 do
		local link = GetGuildBankItemLink(tab, slot)
		if link then
			local count = select(2, GetGuildBankItemInfo and GetGuildBankItemInfo(tab, slot)) or 1
			AddItem(items, ItemID(link), count)
		end
	end
	ge.tabs[tab] = items
	ge.updated = time()
end

local pending = {}
local function QueueScan(kind)
	pending[kind] = true
	if IS.scanQueued then return end
	IS.scanQueued = true
	C_Timer.After(SCAN_DEBOUNCE, function()
		IS.scanQueued = nil
		if pending.bags then ScanBags() end
		if pending.bank then ScanBank() end
		if pending.equip then ScanEquip() end
		if pending.mail then ScanMail() end
		if pending.guild then ScanGuildTab() end
		wipe(pending)
	end)
end

----------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------
local function CharLineCounts(e, id, db)
	local b = (db.countBags ~= false and e.bags and e.bags[id]) or 0
	local k = (db.countBank ~= false and e.bank and e.bank[id]) or 0
	local q = (db.countEquip ~= false and e.equip and e.equip[id]) or 0
	local m = (db.countMail ~= false and e.mail and e.mail[id]) or 0
	return b, k, q, m, b + k + q + m
end

local function AddCounts(tt)
	if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
	local db = IS.db
	if not db or db.enable == false then return end
	local _, link = tt:GetItem()
	if not link or S.IsSecret(link) then return end
	local id = ItemID(link)
	if not id then return end
	local store = S.db.global.itemSync
	if not store then return end
	local me = format("%s-%s", UnitName("player") or "", GetRealmName() or "")
	local total, shown = 0, 0
	for key, e in pairs(store) do
		if type(e) == "table" and e.bags then
			local b, k, q, m, n = CharLineCounts(e, id, db)
			if n > 0 and (db.countCurrent ~= false or key ~= me) then
				total = total + n
				shown = shown + 1
				if shown == 1 then
					tt:AddLine(" ")
					tt:AddLine("|cff" .. S.accentHex .. L["Item Sync"] .. "|r", 1, 1, 1)
				end
				local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
				local name = e.name or key
				local parts = {}
				if b > 0 then parts[#parts + 1] = format("%d %s", b, L["Bags"]) end
				if k > 0 then parts[#parts + 1] = format("%d %s", k, L["Bank"]) end
				if q > 0 then parts[#parts + 1] = format("%d %s", q, L["Equipped"]) end
				if m > 0 then parts[#parts + 1] = format("%d %s", m, L["Mail"]) end
				local label = (key == me) and ("|cff" .. S.accentHex .. name .. "|r") or name
				if c then
					tt:AddDoubleLine(label, tconcat(parts, " · "), c.r, c.g, c.b, 0.85, 0.85, 0.85)
				else
					tt:AddDoubleLine(label, tconcat(parts, " · "), 1, 1, 1, 0.85, 0.85, 0.85)
				end
			end
		end
	end
	-- guild bank section
	if db.countGuild ~= false and store.guilds then
		for gname, ge in pairs(store.guilds) do
			local n = 0
			for _, items in pairs(ge.tabs or {}) do n = n + (items[id] or 0) end
			if n > 0 then
				total = total + n
				if shown == 0 then
					tt:AddLine(" ")
					tt:AddLine("|cff" .. S.accentHex .. L["Item Sync"] .. "|r", 1, 1, 1)
				end
				shown = shown + 1
				tt:AddDoubleLine("|cff00ff98" .. gname .. "|r", format("%d %s", n, L["Guild Bank"]), 1, 1, 1, 0.85, 0.85, 0.85)
			end
		end
	end
	if shown > 1 then
		tt:AddDoubleLine(" ", format("%s: %d", L["Total"], total), 0, 0, 0, 0.6, 0.6, 0.6)
	end
	tt:Show()
end

----------------------------------------------------------------------
-- Search window: browses every tracked item id across all characters
----------------------------------------------------------------------
local searchFrame
local ROW_H = 24
local function RefreshSearch()
	local f = searchFrame
	if not f then return end
	local filter = strlower(strtrim(f.searchBox:GetText() or ""))
	local store = S.db.global.itemSync or {}
	local db = IS.db

	-- aggregate item -> {total, per-owner lines}
	local agg = {}
	for key, e in pairs(store) do
		if type(e) == "table" and e.bags then
			local seen = {}
			for _, inv in ipairs({ e.bags, e.bank, e.equip, e.mail }) do
				for id in pairs(inv or {}) do seen[id] = true end
			end
			for id in pairs(seen) do
				local _, _, _, _, n = CharLineCounts(e, id, db)
				local a = agg[id] or { total = 0, owners = {} }
				a.total = a.total + n
				if n > 0 then tinsert(a.owners, format("%s: %d", e.name or key, n)) end
				agg[id] = a
			end
		end
	end
	if store.guilds then
		for gname, ge in pairs(store.guilds) do
			local seen = {}
			for _, items in pairs(ge.tabs or {}) do for id in pairs(items) do seen[id] = true end end
			for id in pairs(seen) do
				local n = 0
				for _, items in pairs(ge.tabs or {}) do n = n + (items[id] or 0) end
				local a = agg[id] or { total = 0, owners = {} }
				a.total = a.total + n
				if n > 0 then tinsert(a.owners, format("%s: %d", gname, n)) end
				agg[id] = a
			end
		end
	end

	local rows = {}
	for id, a in pairs(agg) do
		local name, link, quality, _, _, _, _, _, _, icon = S.GetItemInfo(id)
		if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
		if filter == "" or (name and strfind(strlower(name), filter, 1, true)) then
			rows[#rows + 1] = { id = id, name = name or ("item:" .. id), link = link, quality = quality or 1, icon = icon, total = a.total, owners = a.owners }
		end
	end
	sort(rows, function(x, y)
		if x.total ~= y.total then return x.total > y.total end
		return strlower(x.name) < strlower(y.name)
	end)

	local n = #rows
	if FauxScrollFrame_Update then
		FauxScrollFrame_Update(f.scroll, n, floor((f.scroll:GetHeight() or 300) / ROW_H), ROW_H)
		f.offset = FauxScrollFrame_GetOffset(f.scroll) or 0
	else
		f.offset = 0
	end
	for i = 1, #f.rows do
		local btn = f.rows[i]
		local r = rows[i + f.offset]
		if r then
			btn.item = r
			btn.icon:SetTexture(r.icon or 134400)
			btn.name:SetText(r.name)
			if r.quality and S.GetItemQualityColor then
				local qr, qg, qb = S.GetItemQualityColor(r.quality)
				btn.name:SetTextColor(qr or 1, qg or 1, qb or 1)
			else
				btn.name:SetTextColor(1, 1, 1)
			end
			btn.count:SetText(format("|cffaaaaaax%d|r  %s", r.total, tconcat(r.owners, "  |cff666666·|r  ")))
			btn:Show()
		else
			btn:Hide()
		end
	end
	f.status:SetText(format("%d Items", n))
end

local function CreateSearch()
	local f = CreateFrame("Frame", "SentinelUIItemSync", UIParent)
	f:SetSize(520, 440)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SetTemplate(f, "Transparent", true)
	tinsert(UISpecialFrames, "SentinelUIItemSync")

	local title = f:CreateFontString(nil, "OVERLAY")
	S:SetFont(title, S.media.font, 14, "OUTLINE")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetText("|cff" .. S.accentHex .. "SentinelUI|r ItemSync")

	f.status = f:CreateFontString(nil, "OVERLAY")
	S:SetFont(f.status, S.media.font, 11, "OUTLINE")
	f.status:SetPoint("TOPRIGHT", -32, -10)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	S:SkinCloseButton(close, f)
	close:SetScript("OnClick", function() f:Hide() end)

	local sb = CreateFrame("EditBox", nil, f)
	sb:SetSize(200, 22)
	sb:SetPoint("TOPLEFT", 12, -32)
	sb:SetAutoFocus(false)
	sb:SetMaxLetters(60)
	S:SkinEditBox(sb)
	sb:SetScript("OnTextChanged", function() C_Timer.After(0.15, RefreshSearch) end)
	sb:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	f.searchBox = sb

	local hint = f:CreateFontString(nil, "OVERLAY")
	S:SetFont(hint, S.media.font, 11, "NONE")
	hint:SetPoint("LEFT", sb, "RIGHT", 10, 0)
	hint:SetText("|cff888888" .. L["Search by item name"] .. "|r")

	local scroll = CreateFrame("ScrollFrame", "SentinelUIItemSyncScroll", f, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -62)
	scroll:SetPoint("BOTTOMRIGHT", -28, 12)
	f.scroll = scroll
	if scroll.ScrollBar then S:SkinScrollBar(scroll.ScrollBar) end
	if FauxScrollFrame_OnVerticalScroll then
		scroll:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, RefreshSearch) end)
	end

	f.rows = {}
	for i = 1, floor((f:GetHeight() - 80) / ROW_H) do
		local btn = CreateFrame("Button", nil, f)
		btn:SetSize(470, ROW_H)
		btn:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_H)
		S:CreateBackdrop(btn, "Default")
		S:AddHover(btn)
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetSize(ROW_H - 6, ROW_H - 6)
		btn.icon:SetPoint("LEFT", 3, 0)
		btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.name = S:FontString(btn, 12, "OUTLINE")
		btn.name:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
		btn.name:SetWidth(180)
		btn.name:SetJustifyH("LEFT")
		btn.count = S:FontString(btn, 11, "NONE")
		btn.count:SetPoint("LEFT", btn.name, "RIGHT", 6, 0)
		btn.count:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
		btn.count:SetJustifyH("LEFT")
		btn:SetScript("OnEnter", function(self)
			if not self.item then return end
			S.HoverEnter(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if self.item.link then GameTooltip:SetHyperlink(self.item.link)
			else GameTooltip:SetItemByID(self.item.id) end
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() S.HoverLeave(self) GameTooltip:Hide() end)
		btn:SetScript("OnClick", function(self)
			if self.item and self.item.link and IsShiftKeyDown() then
				if ChatEdit_InsertLink then ChatEdit_InsertLink(self.item.link)
				elseif ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(self.item.link) end
			end
		end)
		f.rows[i] = btn
	end
	-- refresh names once item data lands in the cache
	f:SetScript("OnEvent", function() if f:IsShown() then RefreshSearch() end end)
	f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	searchFrame = f
end

function IS:OpenSearch()
	CreateSearch()
	if searchFrame:IsShown() then
		searchFrame:Hide()
		return
	end
	searchFrame.searchBox:SetText("")
	RefreshSearch()
	searchFrame:Show()
end

----------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------
function IS:Initialize()
	self.db = S.db.profile.itemsync
	Store()
	ScanBags()
	ScanEquip()
	self:RegisterEvent("BAG_UPDATE_DELAYED", function() QueueScan("bags") end)
	self:RegisterEvent("BAG_UPDATE", function() QueueScan("bags") end)
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() QueueScan("equip") end)
	self:RegisterEvent("BANKFRAME_OPENED", function() QueueScan("bank") end)
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() QueueScan("bank") end)
	self:RegisterEvent("PLAYER_MONEY", function() local e = Store() e.money = GetMoney() end)
	self:RegisterEvent("MAIL_INBOX_UPDATE", function() QueueScan("mail") end)
	self:RegisterEvent("MAIL_SHOW", function() QueueScan("mail") end)
	self:RegisterEvent("GUILDBANKFRAME_OPENED", function() QueueScan("guild") end)
	self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", function() QueueScan("guild") end)
	-- tooltip hook: same dual strategy as the Tooltip module
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
			S:SafeCall("ItemSync:Item", AddCounts, tt)
		end)
	else
		for _, t in ipairs({ GameTooltip, ItemRefTooltip }) do
			if t and t.HookScript then
				t:HookScript("OnTooltipSetItem", function(tt) S:SafeCall("ItemSync:Item", AddCounts, tt) end)
			end
		end
	end
end

function IS:Update()
	self.db = S.db.profile.itemsync
end

----------------------------------------------------------------------
-- Slash: /isync opens the item search
----------------------------------------------------------------------
SLASH_SENTINELISYNC1 = "/isync"
SLASH_SENTINELISYNC2 = "/itemsync"
SlashCmdList.SENTINELISYNC = function(msg)
	msg = strtrim(strlower(msg or ""))
	if msg == "wipe" then
		wipe(S.db.global.itemSync or {})
		Store() ScanBags() ScanEquip()
		S:Print("ItemSync: " .. L["wiped - this character was rescanned"])
	else
		IS:OpenSearch()
	end
end
