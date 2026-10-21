-- Auctions tab: lists your own auctions (owner list) with bid/buyout,
-- time left and an undercut marker comparing your unit price against the
-- cheapest competitor seen in the DB / last competition query.
local _, ns = ...
local S = ns.S
local L = S.L
local AH = ns.AH

local ipairs, pairs = ipairs, pairs
local floor, format = math.floor, format
local tinsert, tremove, sort = tinsert, tremove, table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end end

local cancel = { list = {}, ucQueue = {}, uc = {}, ucRunning = false }
AH.cancel = cancel

local ROW_H, VISIBLE = 22, 12
local TIMELEFT = { L["Short"], L["Medium"], L["Long"], L["Very Long"] }

-- --------------------------------------------------------- undercut check --
local function SendNextUC()
	local term = cancel.ucQueue[1]
	if not term then
		cancel.ucRunning = false
		cancel:Fill()
		AH:Status(L["Undercut check done"])
		return
	end
	if CanSendAuctionQuery and not CanSendAuctionQuery() then return end
	tremove(cancel.ucQueue, 1)
	cancel.ucTerm = term
	QueryAuctionItems(term, 0, 0, 0, 0, 0, 0, 0, 0, false, 1)
end

local ucTicker = CreateFrame("Frame")
local ucAccum = 0
ucTicker:SetScript("OnUpdate", function(_, elapsed)
	if not cancel.ucRunning then return end
	ucAccum = ucAccum + elapsed
	if ucAccum < 0.3 then return end
	ucAccum = 0
	S:SafeCall("AH:UCNext", SendNextUC)
end)

function cancel:CheckUndercuts()
	if not QueryAuctionItems then return end
	if self.ucRunning then AH:Status(L["Search already running"]) return end
	wipe(self.ucQueue)
	local seen = {}
	for _, e in ipairs(self.list) do
		if e.unit and not e.sold and not seen[e.name] then
			seen[e.name] = true
			tinsert(self.ucQueue, e.name)
		end
	end
	if #self.ucQueue == 0 then AH:Status(L["No auctions to check"]) return end
	self.ucRunning = true
	AH:Status(format(L["Checking %d items for undercuts"], #self.ucQueue))
	SendNextUC()
end

function cancel:CollectUC()
	if not self.ucRunning or not self.ucTerm then return end
	local me = UnitName("player")
	local n = GetNumAuctionItems("list")
	local lowest
	for i = 1, math.min(n, 100) do
		local name, _, count, _, _, _, _, _, _, buyout, _, _, _, owner =
			GetAuctionItemInfo("list", i)
		if name == self.ucTerm and buyout and buyout > 0 and owner ~= me then
			local unit = floor(buyout / max(count or 1, 1))
			if not lowest or unit < lowest then lowest = unit end
		end
	end
	self.uc[self.ucTerm] = lowest
	-- mark matching rows
	for _, e in ipairs(self.list) do
		if e.name == self.ucTerm and e.unit and not e.sold then
			e.under = lowest and lowest < e.unit
		end
	end
	self:Fill()
	SendNextUC()
end

function cancel:Refresh()
	if not GetNumAuctionItems then return end
	wipe(self.list)
	local n = GetNumAuctionItems("owner") or 0
	for i = 1, n do
		local name, tex, count, quality, canUse, level, lch, minBid, minInc,
			buyout, bid, highBidder, bidderFN, owner, ownerFN, saleStatus, itemID =
			GetAuctionItemInfo("owner", i)
		if not itemID and GetAuctionItemLink then
			itemID = AH:ItemID(GetAuctionItemLink("owner", i))
		end
		local tl = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("owner", i) or 0
		local unit = buyout and count and count > 0 and floor(buyout / count) or nil
		local dbp = AH:PriceFor(itemID)
		local liveLow = self.uc[name]
		-- undercut: a live-check result wins, price DB as fallback
		local low = liveLow or dbp
		local under = unit and low and low < unit and not (saleStatus == 1)
		tinsert(self.list, {
			i = i, name = name or "?", tex = tex, count = count or 1,
			buyout = buyout or 0, bid = bid or 0, tl = tl, id = itemID,
			unit = unit, under = under, sold = saleStatus == 1,
		})
	end
	sort(self.list, function(a, b) return a.name < b.name end)
	self:Fill()
	-- mass-cancel chain: continue with the next undercut row after each
	-- owner-list update
	if self.massCancel and not self:CancelNext() then
		self:StopMassCancel(L["Mass cancel done"])
	end
end

function cancel:Cancel(e)
	if not e or not CancelAuction then return end
	-- verify the row still matches (list may have shifted)
	local name, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo("owner", e.i)
	if name ~= e.name or buyout ~= e.buyout then
		self:Refresh()
		AH:Status(L["List updated - try again"])
		return
	end
	CancelAuction(e.i)
end

-- mass-cancel: each CancelAuction triggers AUCTION_OWNED_LIST_UPDATE ->
-- Refresh -> chain continues with the next undercut row until none remain
function cancel:CancelNext()
	for _, e in ipairs(self.list) do
		if e.under and not e.sold then self:Cancel(e) return true end
	end
	return false
end

function cancel:StopMassCancel(msg)
	self.massCancel = false
	if self.mcBtn then self.mcBtn:SetText(L["Cancel undercut"]) end
	AH:Status(msg)
end

function cancel:CancelUndercut()
	if self.massCancel then self:StopMassCancel(L["Mass cancel stopped"]) return end
	if self.ucRunning then AH:Status(L["Search already running"]) return end
	self.massCancel = true
	if self.mcBtn then self.mcBtn:SetText(L["Stop"]) end
	if not self:CancelNext() then
		self:StopMassCancel(L["Nothing undercut"])
	end
end

function cancel:Hook()
	local f = CreateFrame("Frame")
	f:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
	f:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	f:SetScript("OnEvent", function(_, ev)
		if ev == "AUCTION_ITEM_LIST_UPDATE" then
			if cancel.ucRunning then
				S:SafeCall("AH:CollectUC", cancel.CollectUC, cancel)
			end
		elseif cancel.list then
			S:SafeCall("AH:CancelRefresh", cancel.Refresh, cancel)
		end
	end)
end

function cancel:Build(pf)
	local pw = pf:GetWidth() or 800
	local sf = CreateFrame("ScrollFrame", "SentinelAHCancelScroll", pf, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 8, -8)
	sf:SetSize(pw - 40, VISIBLE * ROW_H)
	pf.rows = {}
	for i = 1, VISIBLE do
		local r = CreateFrame("Button", nil, pf)
		r:SetSize(pw - 60, ROW_H - 2)
		r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * ROW_H)
		S:CreateBackdrop(r, "Hover")
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0)
		r.name = S:FontString(r, 10, nil, S.media.unitFont)
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
		r.name:SetWidth(220); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
		r.tl = S:FontString(r, 9, nil, S.media.numberFont)
		r.tl:SetPoint("RIGHT", r, "RIGHT", -300, 0)
		r.unit = S:FontString(r, 10, nil, S.media.numberFont)
		r.unit:SetPoint("RIGHT", r, "RIGHT", -190, 0)
		r.buyout = S:FontString(r, 10, nil, S.media.numberFont)
		r.buyout:SetPoint("RIGHT", r, "RIGHT", -90, 0)
		r.cancel = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
		r.cancel:SetSize(70, 16); r.cancel:SetPoint("RIGHT", -4, 0)
		r.cancel:SetText(L["Cancel"])
		if S.SkinButton then S:SkinButton(r.cancel) end
		r.cancel:SetScript("OnClick", function() cancel:Cancel(r.data) end)
		r:SetScript("OnEnter", function(self2)
			if self2.data and self2.data.id then
				GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
				GameTooltip:SetItemByID(self2.data.id)
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		r:Hide()
		pf.rows[i] = r
	end
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(pw - 40, VISIBLE * ROW_H)
	sf:SetScrollChild(child)
	sf:SetScript("OnVerticalScroll", function(_, off)
		FauxScrollFrame_OnVerticalScroll(sf, off, ROW_H, function() cancel:Fill() end)
	end)
	self.sf = sf
	self.rows = pf.rows

	local refBtn = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
	refBtn:SetSize(120, 20)
	refBtn:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -8, 8)
	refBtn:SetText(L["Refresh"])
	if S.SkinButton then S:SkinButton(refBtn) end
	refBtn:SetScript("OnClick", function()
		if GetOwnerAuctionItems then GetOwnerAuctionItems() end
		cancel:Refresh()
	end)

	local ucBtn = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
	ucBtn:SetSize(140, 20)
	ucBtn:SetPoint("RIGHT", refBtn, "LEFT", -6, 0)
	ucBtn:SetText(L["Check undercuts"])
	if S.SkinButton then S:SkinButton(ucBtn) end
	ucBtn:SetScript("OnClick", function() cancel:CheckUndercuts() end)

	local mcBtn = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
	mcBtn:SetSize(140, 20)
	mcBtn:SetPoint("RIGHT", ucBtn, "LEFT", -6, 0)
	mcBtn:SetText(L["Cancel undercut"])
	if S.SkinButton then S:SkinButton(mcBtn) end
	mcBtn:SetScript("OnClick", function() cancel:CancelUndercut() end)
	self.mcBtn = mcBtn
end

function cancel:Fill()
	if not self.sf then return end
	FauxScrollFrame_Update(self.sf, #self.list, VISIBLE, ROW_H)
	local off = FauxScrollFrame_GetOffset(self.sf) or 0
	for i = 1, VISIBLE do
		local r, e = self.rows[i], self.list[i + off]
		if e then
			r.data = e
			r.icon:SetTexture(e.tex)
			local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality or 1]
			r.name:SetText((qc and qc.hex or "") .. e.name .. "|r x" .. e.count)
			r.tl:SetText(TIMELEFT[e.tl] or "-")
			r.unit:SetText(AH:Money(e.unit))
			if e.sold then
				r.buyout:SetText("|cff00ff00" .. L["Sold"] .. "|r")
			elseif e.under then
				r.buyout:SetText("|cffff5555" .. AH:Money(e.buyout) .. " !|r")
			else
				r.buyout:SetText(AH:Money(e.buyout))
			end
			r:Show()
		else r.data = nil r:Hide() end
	end
end

AH.panels.cancel = AH.panels.cancel or {}
AH.panels.cancel.refresh = function()
	-- owner list is populated asynchronously: request, fill on the event
	if GetOwnerAuctionItems then GetOwnerAuctionItems() end
	cancel:Refresh()
end
