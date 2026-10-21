-- Sell tab: left column lists sellable bag items, right column shows the
-- current competition for the selected item plus price/stack/duration
-- controls. Posting goes through the Blizzard sell slot (item is placed
-- there, prices passed to PostAuction).
local _, ns = ...
local S = ns.S
local L = S.L
local AH = ns.AH

local ipairs, pairs = ipairs, pairs
local floor, format = math.floor, format
local tinsert, sort = tinsert, table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end end

local sell = { items = {}, comp = {} }
AH.sell = sell

local ROW_H, VISIBLE = 20, 13
local COMP_ROWS = 5

local GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerItemInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
local GetContainerItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
local PickupContainerItem = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

local function BagScan()
	wipe(sell.items)
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local info, count, link
			if C_Container and C_Container.GetContainerItemInfo then
				local t = C_Container.GetContainerItemInfo(bag, slot)
				if t then info = t.iconFileID count = t.stackCount link = t.hyperlink end
			elseif GetContainerItemInfo then
				local tex, n, _, q, _, _, l = GetContainerItemInfo(bag, slot)
				info, count, link = tex, n, l
			end
			if link then
				local name, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
				local id = AH:ItemID(link)
				if name and id then
					tinsert(sell.items, {
						bag = bag, slot = slot, name = name, tex = info,
						count = count or 1, quality = quality or 1,
						link = link, id = id, vendor = sellPrice,
					})
				end
			end
		end
	end
	sort(sell.items, function(a, b) return (a.name or "") < (b.name or "") end)
end

-- ----------------------------------------------------------- item selection --
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
evFrame:SetScript("OnEvent", function()
	if sell.querying then S:SafeCall("AH:SellComp", sell.CollectComp, sell) end
end)

function sell:Select(r)
	local it = r.data
	if not it then return end
	self.selected = it
	self.selName:SetText("|cffffffff" .. it.name .. "|r  x" .. it.count)
	if self.stackBox then
		self.stackBox:SetText(tostring(it.count))
		self.numBox:SetText("1")
	end
	if self.lastText then self.lastText:SetText("") end
	-- query competition: exact name search
	wipe(self.comp)
	self:FillComp()
	if QueryAuctionItems and (not CanSendAuctionQuery or CanSendAuctionQuery()) then
		self.querying = true
		QueryAuctionItems(it.name, 0, 0, 0, 0, 0, 0, 0, 0, false, 1)
		self.statusL:SetText(L["Searching competitors..."])
	end
	self:Suggest()
end

function sell:CollectComp()
	if not self.selected or not self.querying then return end
	self.querying = false
	local n = GetNumAuctionItems("list")
	local me = UnitName("player")
	for i = 1, math.min(n, 50) do
		local name, _, count, _, _, _, _, _, _, buyout, _, _, _, owner =
			GetAuctionItemInfo("list", i)
		if name == self.selected.name and buyout and buyout > 0 then
			tinsert(self.comp, {
				owner = owner or "?", count = count or 1,
				unit = floor(buyout / max(count or 1, 1)),
				own = owner == me or (owner and me and owner:find(me, 1, true) == 1),
			})
		end
	end
	sort(self.comp, function(a, b) return a.unit < b.unit end)
	self:FillComp()
	self:Suggest()
	self.statusL:SetText(format(L["%d competitors"], #self.comp))
end

function sell:Suggest()
	local it = self.selected
	if not it then return end
	local lowest = self.comp[1] and self.comp[1].unit
	if lowest and self.comp[1].own and self.comp[2] then lowest = self.comp[2].unit end
	local db = AH:PriceFor(it.id)
	local base = lowest or db or (it.vendor and it.vendor * 2)
	if not base or base <= 0 then return end
	local under = (AH.db and AH.db.undercut or 0) / 100
	local price = math.max(1, floor(base * (1 - under)))
	if lowest and lowest <= price and base == lowest then
		price = math.max(1, lowest - 1) -- 1c undercut when matching lowest
	end
	self.suggested = price
	self.priceBox:SetText(format("%dg %ds %dc",
		floor(price / 10000), floor(price / 100) % 100, price % 100))
	-- last own posting price hint
	local h = S.db.global.ahPostHistory and S.db.global.ahPostHistory[it.id]
	if h and self.lastText then
		self.lastText:SetText(format(L["Last posted: %s"], AH:Money(h.p)))
	end
	self:Deposit()
end

function sell:Deposit()
	if not GetAuctionDeposit then return end
	local unit = AH:CopperFromText(self.priceBox and self.priceBox:GetText()) or 0
	local stack = tonumber(self.stackBox and self.stackBox:GetText()) or (self.selected and self.selected.count) or 1
	local num = tonumber(self.numBox and self.numBox:GetText()) or 1
	local bid = floor(unit * stack * 0.95)
	local d = GetAuctionDeposit(AH.db.duration or 2, math.min(bid, MAXIMUM_BID_PRICE or 2147483647),
		math.min(unit * stack, MAXIMUM_BID_PRICE or 2147483647), stack, num)
	self.depoText:SetText(L["Deposit"] .. ": " .. AH:Money(d or 0))
end

-- count of the selected itemID across all bag slots (multisell can pull
-- from several stacks)
function sell:TotalCount(id)
	local n = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local link, c
			if C_Container and C_Container.GetContainerItemInfo then
				local t = C_Container.GetContainerItemInfo(bag, slot)
				if t then link, c = t.hyperlink, t.stackCount end
			elseif GetContainerItemLink then
				link = GetContainerItemLink(bag, slot)
				local _, cc = GetContainerItemInfo(bag, slot)
				c = cc
			end
			if link and AH:ItemID(link) == id then n = n + (c or 1) end
		end
	end
	return n
end

function sell:Post()
	local it = self.selected
	if not it then AH:Status(L["No item selected"]) return end
	local unit = AH:CopperFromText(self.priceBox:GetText())
	if not unit or unit <= 0 then AH:Status(L["Invalid price"]) return end
	if not (PickupContainerItem and ClickAuctionSellItemButton and PostAuction) then
		AH:Status(L["AH API unavailable"])
		return
	end
	local total = self:TotalCount(it.id)
	local stack = tonumber(self.stackBox:GetText()) or it.count
	stack = math.max(1, math.min(stack, total))
	local num = tonumber(self.numBox:GetText()) or 1
	num = math.max(1, math.min(num, floor(total / stack)))
	-- placement ritual (same as Auctionator): clear, clear slot, pick, place
	ClearCursor()
	ClickAuctionSellItemButton()
	ClearCursor()
	PickupContainerItem(it.bag, it.slot)
	ClickAuctionSellItemButton()
	ClearCursor()
	if not (GetAuctionSellItemInfo and GetAuctionSellItemInfo()) then
		AH:Status(L["Item could not be placed"])
		return
	end
	local stackBuyout = unit * stack
	local bid = floor(stackBuyout * 0.95)
	-- PostAuction(bid, stackBuyout, runTime, stackSize, numStacks[, skip])
	if StaticPopupDialogs and StaticPopupDialogs["AUCTION_HOUSE_POST_WARNING"] then
		PostAuction(bid, stackBuyout, AH.db.duration or 2, stack, num, true)
	else
		PostAuction(bid, stackBuyout, AH.db.duration or 2, stack, num)
	end
	S.db.global.ahPostHistory = S.db.global.ahPostHistory or {}
	S.db.global.ahPostHistory[it.id] = { p = unit, n = stack, t = time() }
	AH:Status(format(L["Posted: %s x%d for %s"], it.name, stack * num, AH:Money(stackBuyout * num)))
	C_Timer.After(1, function() BagScan(); sell:FillItems() end)
end

-- ------------------------------------------------------------------- frames --
function sell:Build(pf)
	self.parent = pf
	local pw = pf:GetWidth() or 800

	local left = CreateFrame("Frame", nil, pf)
	left:SetPoint("TOPLEFT", 6, -4)
	left:SetSize(240, pf:GetHeight() - 8)
	S:CreateBackdrop(left, "Hover")
	S:FontString(left, 10, "OUTLINE", S.media.unitFont)
		:SetPoint("TOP", 0, -6):SetText(L["Bags"])

	local sf = CreateFrame("ScrollFrame", "SentinelAHSellScroll", left, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 4, -22)
	sf:SetSize(232, left:GetHeight() - 30)
	left.rows = {}
	for i = 1, 14 do
		local r = CreateFrame("Button", nil, left)
		r:SetSize(224, 18)
		r:SetPoint("TOPLEFT", 6, -22 - (i - 1) * 18)
		S:CreateBackdrop(r, "Hover")
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 4, 0)
		r.name = S:FontString(r, 9, nil, S.media.unitFont)
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
		r.name:SetWidth(160); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
		r.cnt = S:FontString(r, 9, nil, S.media.numberFont)
		r.cnt:SetPoint("RIGHT", -4, 0)
		r:SetScript("OnClick", function() sell:Select(r) end)
		r:Hide()
		left.rows[i] = r
	end
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(232, 14 * 18)
	sf:SetScrollChild(child)
	sf:SetScript("OnVerticalScroll", function(_, off)
		FauxScrollFrame_OnVerticalScroll(sf, off, 18, function() sell:FillItems() end)
	end)
	self.sf = sf

	local right = CreateFrame("Frame", nil, pf)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	right:SetPoint("BOTTOMRIGHT", -6, -4)
	S:CreateBackdrop(right, "Hover")

	self.selName = S:FontString(right, 12, "OUTLINE", S.media.unitFont)
	self.selName:SetPoint("TOPLEFT", 10, -8)

	-- competition list
	self.statusL = S:FontString(right, 9, nil, S.media.numberFont)
	self.statusL:SetPoint("TOPLEFT", 10, -28)
	self.compRows = {}
	for i = 1, COMP_ROWS do
		local r = S:FontString(right, 9, nil, S.media.numberFont)
		r:SetPoint("TOPLEFT", 10, -42 - (i - 1) * 14)
		r:SetJustifyH("LEFT")
		self.compRows[i] = r
	end

	-- controls
	local py = -42 - COMP_ROWS * 14 - 14
	local lbl = S:FontString(right, 9, nil, S.media.unitFont)
	lbl:SetPoint("TOPLEFT", 10, py); lbl:SetText(L["Price/item"])
	local pb = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
	pb:SetSize(110, 18); pb:SetAutoFocus(false)
	pb:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
	if S.SkinEditBox then S:SkinEditBox(pb) end
	pb:SetScript("OnTextChanged", function() sell:Deposit() end)
	self.priceBox = pb

	-- stack size + num stacks (multisell)
	local slbl = S:FontString(right, 9, nil, S.media.unitFont)
	slbl:SetPoint("TOPLEFT", pb, "TOPRIGHT", 12, 0); slbl:SetText(L["Stack size"])
	local sb = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
	sb:SetSize(40, 18); sb:SetAutoFocus(false); sb:SetNumeric(true); sb:SetMaxLetters(3)
	sb:SetPoint("LEFT", slbl, "RIGHT", 4, 0)
	if S.SkinEditBox then S:SkinEditBox(sb) end
	self.stackBox = sb
	local nlbl = S:FontString(right, 9, nil, S.media.unitFont)
	nlbl:SetPoint("LEFT", sb, "RIGHT", 8, 0); nlbl:SetText("x")
	local nb = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
	nb:SetSize(30, 18); nb:SetAutoFocus(false); nb:SetNumeric(true); nb:SetMaxLetters(2)
	nb:SetPoint("LEFT", nlbl, "RIGHT", 4, 0)
	if S.SkinEditBox then S:SkinEditBox(nb) end
	nb:SetText("1")
	self.numBox = nb
	for _, b in ipairs({ sb, nb }) do
		b:SetScript("OnTextChanged", function() sell:Deposit() end)
	end

	self.lastText = S:FontString(right, 9, nil, S.media.numberFont)
	self.lastText:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)

	local durLbl = S:FontString(right, 9, nil, S.media.unitFont)
	durLbl:SetPoint("TOPLEFT", self.lastText, "BOTTOMLEFT", 0, -8); durLbl:SetText(L["Duration"])
	local durations = { { 1, "12h" }, { 2, "24h" }, { 3, "48h" } }
	self.durBtns = {}
	local pa = durLbl
	for _, d in ipairs(durations) do
		local cb = CreateFrame("CheckButton", nil, right, "UIRadioButtonTemplate")
		cb:SetSize(16, 16)
		cb:SetPoint("LEFT", pa, "RIGHT", 8, 0)
		cb:SetScript("OnClick", function()
			AH.db.duration = d[1]
			for _, o in ipairs(sell.durBtns) do o:SetChecked(o == cb) end
			sell:Deposit()
		end)
		local dl = S:FontString(cb, 9, nil, S.media.unitFont)
		dl:SetPoint("LEFT", cb, "RIGHT", 2, 0); dl:SetText(d[2])
		cb:SetChecked((AH.db.duration or 2) == d[1])
		self.durBtns[d[1]] = cb
		pa = dl
	end

	self.depoText = S:FontString(right, 9, nil, S.media.numberFont)
	self.depoText:SetPoint("TOPLEFT", durLbl, "BOTTOMLEFT", 0, -8)

	local postBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	postBtn:SetSize(130, 24)
	postBtn:SetPoint("BOTTOMRIGHT", -10, 8)
	postBtn:SetText(L["Auction"])
	if S.SkinButton then S:SkinButton(postBtn) end
	postBtn:SetScript("OnClick", function() sell:Post() end)

	local refBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	refBtn:SetSize(110, 24)
	refBtn:SetPoint("RIGHT", postBtn, "LEFT", -6, 0)
	refBtn:SetText(L["Rescan bags"])
	if S.SkinButton then S:SkinButton(refBtn) end
	refBtn:SetScript("OnClick", function() BagScan(); sell:FillItems() end)

	BagScan()
	self:FillItems()
end

function sell:FillItems()
	if not self.sf then return end
	local rows = self.parent and self.sf:GetParent().rows
	if not rows then return end
	FauxScrollFrame_Update(self.sf, #self.items, 14, 18)
	local off = FauxScrollFrame_GetOffset(self.sf) or 0
	for i = 1, 14 do
		local r, it = rows[i], self.items[i + off]
		if it then
			r.data = it
			r.icon:SetTexture(it.tex)
			local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality]
			r.name:SetText((qc and qc.hex or "") .. (it.name or "?") .. "|r")
			r.cnt:SetText("x" .. it.count)
			r:Show()
		else r.data = nil r:Hide() end
	end
end

function sell:FillComp()
	if not self.compRows then return end
	for i = 1, COMP_ROWS do
		local r, c = self.compRows[i], self.comp[i]
		if c then
			r:SetText(format("%s x%d - %s/Stk%s",
				c.owner, c.count, AH:Money(c.unit),
				c.own and " |cff00ff00(" .. L["you"] .. ")|r" or ""))
		else
			r:SetText("")
		end
	end
end

function sell.Refresh()
	BagScan()
	sell:FillItems()
	sell:FillComp()
end
AH.panels.sell = AH.panels.sell or {}
AH.panels.sell.refresh = sell.Refresh
