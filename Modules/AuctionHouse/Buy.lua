-- Buy tab: search box + filters on top, shopping lists on the left,
-- merged results on the right. List searches fire the terms one after
-- another at the AH's query pace and merge the hits, sorted by unit price.
local _, ns = ...
local S = ns.S
local L = S.L
local AH = ns.AH

local ipairs, pairs = ipairs, pairs
local floor, format = math.floor, format
local tinsert, tremove, sort = tinsert, tremove, table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end end

local buy = { results = {}, queue = {}, searching = false }
AH.buy = buy

local ROW_H, VISIBLE = 20, 13
local LIST_ROWS = 10

-- ------------------------------------------------------------- query engine --
local function SendNext()
	local term = buy.queue[1]
	if not term then
		buy.searching = false
		buy:FillResults()
		AH:Status(format(L["Search done: %d hits"], #buy.results))
		return
	end
	local can = true
	if CanSendAuctionQuery then can = CanSendAuctionQuery() end
	if not can then return end -- ticker retries
	tremove(buy.queue, 1)
	buy.lastTerm = term
	AH:Status(format(L["Searching: %s"], term))
	QueryAuctionItems(term, buy.minLvl or 0, buy.maxLvl or 0, 0, 0, 0, 0,
		buy.usable and 1 or 0, 0, false, buy.exact and 1 or 0)
end

local tickerFrame = CreateFrame("Frame")
local accum = 0
tickerFrame:SetScript("OnUpdate", function(_, elapsed)
	if not buy.searching then return end
	accum = accum + elapsed
	if accum < 0.3 then return end -- AH query pace
	accum = 0
	S:SafeCall("AH:BuyNext", SendNext)
end)

function buy:SearchTerms(terms)
	if self.searching then AH:Status(L["Search already running"]) return end
	wipe(self.results)
	wipe(self.queue)
	for _, t in ipairs(terms) do tinsert(self.queue, t) end
	if #self.queue == 0 then return end
	-- manual single-term searches land in the recent strip
	if #self.queue == 1 then self:AddRecent(self.queue[1]) end
	self.searching = true
	self:FillResults()
	SendNext()
end

function buy:AddRecent(t)
	t = (t or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if t == "" then return end
	self.recent = self.recent or {}
	for i, v in ipairs(self.recent) do
		if v:lower() == t:lower() then tremove(self.recent, i) break end
	end
	tinsert(self.recent, 1, t)
	while #self.recent > 6 do tremove(self.recent) end
	self:FillRecent()
end

local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
evFrame:SetScript("OnEvent", function()
	if buy.searching then S:SafeCall("AH:BuyCollect", buy.Collect, buy) end
end)

function buy:Collect()
	local n = GetNumAuctionItems("list")
	local term = self.lastTerm or "?"
	for i = 1, n do
		local name, tex, count, quality, canUse, level, lch, minBid, minInc,
			buyout, bid, highBidder, bidderFN, owner, ownerFN, saleStatus, itemID =
			GetAuctionItemInfo("list", i)
		if not itemID and GetAuctionItemLink then
			itemID = AH:ItemID(GetAuctionItemLink("list", i))
		end
		if name and buyout and buyout > 0 then
			tinsert(self.results, {
				i = i, term = term, name = name, tex = tex, count = count or 1,
				quality = quality or 1, level = level, buyout = buyout,
				owner = ownerFN or owner or "?", id = itemID,
				unit = floor(buyout / max(count or 1, 1)),
			})
			if itemID then AH:StorePrice(itemID, floor(buyout / max(count or 1, 1))) end
		end
	end
	-- re-sort each batch: cheapest unit price first
	sort(self.results, function(a, b) return a.unit < b.unit end)
	self:FillResults()
	-- proceed to next queued term
	SendNext()
end

-- ------------------------------------------------------------------- frames --
function buy:Build(pf)
	self.parent = pf
	local pw = pf:GetWidth() or 800

	-- ---------- left: shopping lists ----------
	local left = CreateFrame("Frame", nil, pf)
	left:SetPoint("TOPLEFT", 6, -4)
	left:SetSize(180, pf:GetHeight() - 8)
	S:CreateBackdrop(left, "Hover")
	self.left = left

	S:FontString(left, 10, "OUTLINE", S.media.unitFont)
		:SetPoint("TOP", 0, -6):SetText(L["Shopping Lists"])
	-- list-name rows
	left.lists = {}
	for i = 1, 5 do
		local r = CreateFrame("Button", nil, left)
		r:SetSize(168, 18)
		r:SetPoint("TOPLEFT", 6, -22 - (i - 1) * 20)
		S:CreateBackdrop(r, "Hover")
		r.fs = S:FontString(r, 10, nil, S.media.unitFont)
		r.fs:SetPoint("LEFT", 6, 0)
		r.fs:SetJustifyH("LEFT")
		r:SetScript("OnClick", function()
			AH.shopping:SetCurrent(i + (left.lOffset or 0))
			buy:FillLists()
			if buy.itemsFill then buy.itemsFill() end
		end)
		r:Hide()
		left.lists[i] = r
	end

	local newBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
	newBtn:SetSize(80, 18); newBtn:SetPoint("TOPLEFT", 6, -22 - 5 * 20 - 4)
	newBtn:SetText("+ " .. L["New List"])
	if S.SkinButton then S:SkinButton(newBtn) end
	newBtn:SetScript("OnClick", function()
		StaticPopup_Show("SUI_AH_NEW_LIST")
	end)
	local delBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
	delBtn:SetSize(80, 18); delBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
	delBtn:SetText(L["Delete"])
	if S.SkinButton then S:SkinButton(delBtn) end
	delBtn:SetScript("OnClick", function()
		local st = S.db.global.ahShopping
		AH.shopping:DeleteList(st and st.current or 1)
		buy:FillLists(); buy:FillItems()
	end)

	-- items of the current list
	S:FontString(left, 10, "OUTLINE", S.media.unitFont)
		:SetPoint("TOP", newBtn, "BOTTOM", 0, -8):SetText(L["Entries"])
	left.items = {}
	for i = 1, LIST_ROWS do
		local r = CreateFrame("Button", nil, left)
		r:SetSize(168, 16)
		r:SetPoint("TOPLEFT", 6, -22 - 5 * 20 - 26 - (i - 1) * 17)
		r.fs = S:FontString(r, 9, nil, S.media.unitFont)
		r.fs:SetPoint("LEFT", 4, 0); r.fs:SetJustifyH("LEFT")
		r.fs:SetWidth(140)
		r.fs:SetWordWrap(false)
		r.del = S:FontString(r, 9, nil, S.media.unitFont)
		r.del:SetPoint("RIGHT", -4, 0); r.del:SetText("|cffff5555x|r")
		r:SetScript("OnClick", function(_, btn)
			if btn == "RightButton" then
				AH.shopping:RemoveItem(i + (left.iOffset or 0))
				buy:FillItems()
			else
				buy.searchBox:SetText(r.fs:GetText() or "")
			end
		end)
		r:Hide()
		left.items[i] = r
	end

	local addBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
	addBox:SetSize(120, 18); addBox:SetAutoFocus(false)
	addBox:SetPoint("BOTTOMLEFT", 6, 26)
	if S.SkinEditBox then S:SkinEditBox(addBox) end
	local addBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
	addBtn:SetSize(48, 18); addBtn:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
	addBtn:SetText("+")
	if S.SkinButton then S:SkinButton(addBtn) end
	local function AddItem()
		if AH.shopping:AddItem(addBox:GetText()) then addBox:SetText("") end
		buy:FillItems()
	end
	addBtn:SetScript("OnClick", AddItem)
	addBox:SetScript("OnEnterPressed", function(b) AddItem() b:ClearFocus() end)

	-- import/export: Auctionator-compatible "Name^item^item" strings
	local impBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
	impBtn:SetSize(80, 16); impBtn:SetPoint("BOTTOMLEFT", 6, 6)
	impBtn:SetText(L["Import"])
	if S.SkinButton then S:SkinButton(impBtn) end
	impBtn:SetScript("OnClick", function()
		AH:TextDialog(L["Import"], "", L["Import"], function(text)
			local n, lists = AH.shopping:Import(text)
			buy:FillLists(); buy:FillItems()
			AH:Status(format(L["Imported %d items into %d lists"], n or 0, lists or 0))
		end)
	end)
	local expBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
	expBtn:SetSize(80, 16); expBtn:SetPoint("LEFT", impBtn, "RIGHT", 4, 0)
	expBtn:SetText(L["Export"])
	if S.SkinButton then S:SkinButton(expBtn) end
	expBtn:SetScript("OnClick", function()
		AH:TextDialog(L["Export string (Ctrl+A, Ctrl+C)"],
			AH.shopping:ExportAll(), L["Done"])
	end)

	-- ---------- right: search + results ----------
	local right = CreateFrame("Frame", nil, pf)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	right:SetPoint("BOTTOMRIGHT", -6, -4)
	S:CreateBackdrop(right, "Hover")
	self.right = right

	local eb = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
	eb:SetSize(200, 20); eb:SetAutoFocus(false)
	eb:SetPoint("TOPLEFT", 8, -8)
	if S.SkinEditBox then S:SkinEditBox(eb) end
	eb:SetScript("OnEnterPressed", function(b2)
		buy:SearchTerms({ b2:GetText() })
		b2:ClearFocus()
	end)
	self.searchBox = eb

	local sBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	sBtn:SetSize(70, 20); sBtn:SetPoint("LEFT", eb, "RIGHT", 4, 0)
	sBtn:SetText(L["Search"])
	if S.SkinButton then S:SkinButton(sBtn) end
	sBtn:SetScript("OnClick", function() buy:SearchTerms({ eb:GetText() }) end)

	local allBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	allBtn:SetSize(110, 20); allBtn:SetPoint("LEFT", sBtn, "RIGHT", 4, 0)
	allBtn:SetText(L["Search List"])
	if S.SkinButton then S:SkinButton(allBtn) end
	allBtn:SetScript("OnClick", function()
		buy:SearchTerms(AH.shopping:Current().items)
	end)

	-- filters: usable / exact / min level / max level
	local usable = CreateFrame("CheckButton", nil, right, "UICheckButtonTemplate")
	usable:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -4)
	usable:SetScript("OnClick", function(b) buy.usable = b:GetChecked() end)
	if S.SkinCheckBox then S:SkinCheckBox(usable) end
	local ul = S:FontString(usable, 9, nil, S.media.unitFont)
	ul:SetPoint("LEFT", usable, "RIGHT", 2, 0)
	ul:SetText(L["Usable only"])

	local exact = CreateFrame("CheckButton", nil, right, "UICheckButtonTemplate")
	exact:SetPoint("LEFT", ul, "RIGHT", 14, 0)
	exact:SetScript("OnClick", function(b) buy.exact = b:GetChecked() end)
	if S.SkinCheckBox then S:SkinCheckBox(exact) end
	local el = S:FontString(exact, 9, nil, S.media.unitFont)
	el:SetPoint("LEFT", exact, "RIGHT", 2, 0)
	el:SetText(L["Exact"])

	local function lvlBox(point, anchor)
		local b = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
		b:SetSize(32, 16); b:SetAutoFocus(false)
		b:SetNumeric(true); b:SetMaxLetters(3)
		b:SetPoint(point, anchor, (point == "LEFT") and "RIGHT" or "LEFT",
			(point == "LEFT") and 8 or -8, 0)
		if S.SkinEditBox then S:SkinEditBox(b) end
		return b
	end
	local minB = lvlBox("LEFT", el)
	minB:SetScript("OnTextChanged", function(b) buy.minLvl = tonumber(b:GetText()) or 0 end)
	local l1 = S:FontString(right, 9, nil, S.media.unitFont)
	l1:SetPoint("LEFT", minB, "RIGHT", 4, 0); l1:SetText("-")
	local maxB = lvlBox("LEFT", l1)
	maxB:SetScript("OnTextChanged", function(b) buy.maxLvl = tonumber(b:GetText()) or 0 end)
	local l2 = S:FontString(right, 9, nil, S.media.unitFont)
	l2:SetPoint("LEFT", maxB, "RIGHT", 4, 0); l2:SetText(L["Level"])

	-- results list (rows are siblings of the scroll frame, cf. GroupBulletin)
	local sf = CreateFrame("ScrollFrame", "SentinelAHBuyScroll", right, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 8, -62)
	sf:SetSize(pw - 220, VISIBLE * ROW_H)
	right.rows = {}
	for i = 1, VISIBLE do
		local r = CreateFrame("Button", nil, right)
		r:SetSize(pw - 236, ROW_H)
		r:SetPoint("TOPLEFT", 8, -62 - (i - 1) * ROW_H)
		S:CreateBackdrop(r, "Hover")
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0)
		r.name = S:FontString(r, 10, nil, S.media.unitFont)
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
		r.name:SetWidth(pw - 480); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
		r.qty = S:FontString(r, 10, nil, S.media.numberFont)
		r.qty:SetPoint("RIGHT", r, "RIGHT", -170, 0)
		r.unit = S:FontString(r, 10, nil, S.media.numberFont)
		r.unit:SetPoint("RIGHT", r, "RIGHT", -85, 0)
		r.total = S:FontString(r, 10, nil, S.media.numberFont)
		r.total:SetPoint("RIGHT", -6, 0)
		r:SetScript("OnClick", function() buy:SelectRow(r) end)
		r:SetScript("OnEnter", function(self2)
			if self2.data and self2.data.id then
				GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
				GameTooltip:SetItemByID(self2.data.id)
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		r:Hide()
		right.rows[i] = r
	end
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(pw - 220, VISIBLE * ROW_H)
	sf:SetScrollChild(child)
	sf:SetScript("OnVerticalScroll", function(_, off)
		FauxScrollFrame_OnVerticalScroll(sf, off, ROW_H, function() buy:FillResults() end)
	end)
	self.sf = sf

	-- buy bar
	local buyBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	buyBtn:SetSize(110, 22)
	buyBtn:SetPoint("BOTTOMRIGHT", -8, 6)
	buyBtn:SetText(L["Buy"])
	if S.SkinButton then S:SkinButton(buyBtn) end
	buyBtn:SetScript("OnClick", function() buy:Buy() end)
	self.buyBtn = buyBtn
	self.selText = S:FontString(right, 10, nil, S.media.unitFont)
	self.selText:SetPoint("BOTTOMLEFT", 8, 10)
	self.selText:SetJustifyH("LEFT")

	-- recent searches: clickable strip above the selection line
	self.recentLabel = S:FontString(right, 9, nil, S.media.unitFont)
	self.recentLabel:SetPoint("BOTTOMLEFT", 8, 26)
	self.recentLabel:SetText(L["Recent:"])
	self.recentBtns = {}
	local prev = self.recentLabel
	for i = 1, 6 do
		local b = CreateFrame("Button", nil, right)
		b:SetSize(80, 12)
		b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		b.fs = S:FontString(b, 9, nil, S.media.unitFont)
		b.fs:SetAllPoints()
		b.fs:SetJustifyH("LEFT")
		b.fs:SetTextColor(0.4, 0.7, 1)
		b:SetScript("OnClick", function()
			if buy.searchBox then buy.searchBox:SetText(b.term or "") end
			buy:SearchTerms({ b.term })
		end)
		b:SetScript("OnEnter", function() b.fs:SetTextColor(1, 1, 1) end)
		b:SetScript("OnLeave", function() b.fs:SetTextColor(0.4, 0.7, 1) end)
		b:Hide()
		self.recentBtns[i] = b
		prev = b
	end
	self:FillLists()
	self:FillItems()
	self:FillResults()

	StaticPopupDialogs["SUI_AH_NEW_LIST"] = {
		text = L["Shopping list name:"],
		button1 = ACCEPT, button2 = CANCEL,
		hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function(self2)
			local name = self2.editBox and self2.editBox:GetText() or self2.EditBox and self2.EditBox:GetText()
			AH.shopping:NewList(name)
			buy:FillLists(); buy:FillItems()
		end,
	}
end

function buy:FillLists()
	if not self.left then return end
	local lists = AH.shopping:Lists()
	local cur = S.db.global.ahShopping.current or 1
	for i = 1, #self.left.lists do
		local r, l = self.left.lists[i], lists[i]
		if l then
			r.fs:SetText((i == cur and "|cff4aa3ff" or "|cffffffff") .. l.name .. "|r")
			r:Show()
		else r:Hide() end
	end
end

function buy:FillRecent()
	if not self.recentBtns then return end
	for i = 1, #self.recentBtns do
		local b, t = self.recentBtns[i], self.recent and self.recent[i]
		if t then
			b.term = t
			b.fs:SetText(t)
			b:SetWidth(min(90, (b.fs:GetStringWidth() or 40) + 4))
			b:Show()
		else b:Hide() end
	end
end

function buy:FillItems()
	if not self.left then return end
	local items = AH.shopping:Current().items
	for i = 1, LIST_ROWS do
		local r, v = self.left.items[i], items[i]
		if v then r.fs:SetText(v) r:Show() else r:Hide() end
	end
end

function buy:FillResults()
	if not self.right then return end
	FauxScrollFrame_Update(self.sf, #self.results, VISIBLE, ROW_H)
	local off = FauxScrollFrame_GetOffset(self.sf) or 0
	for i = 1, VISIBLE do
		local r, e = self.right.rows[i], self.results[i + off]
		if e then
			r.data = e
			r.icon:SetTexture(e.tex)
			local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
			r.name:SetText((qc and qc.hex or "") .. (e.name or "?") .. "|r")
			r.qty:SetText("x" .. (e.count or 1))
			r.unit:SetText(AH:Money(e.unit))
			r.total:SetText(AH:Money(e.buyout))
			r:Show()
		else
			r.data = nil
			r:Hide()
		end
	end
end

function buy:SelectRow(r)
	self.selected = r.data
	if r.data then
		if SetSelectedAuctionItem then SetSelectedAuctionItem("list", r.data.i) end
		self.selText:SetText(format("%s x%d - %s", r.data.name or "?", r.data.count or 1, AH:Money(r.data.buyout)))
	end
end

function buy:Buy()
	local e = self.selected
	if not e then AH:Status(L["No entry selected"]) return end
	if not PlaceAuctionBid then return end
	-- index must still match the current result page; verify name+price
	local name, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo("list", e.i)
	if name ~= e.name or buyout ~= e.buyout then
		AH:Status(L["Entry stale - search again"])
		return
	end
	PlaceAuctionBid("list", e.i, e.buyout)
end

function buy.Refresh(p)
	if buy.FillLists then buy:FillLists() buy:FillItems() buy:FillResults() end
end
AH.panels.buy = AH.panels.buy or {}
AH.panels.buy.refresh = buy.Refresh
