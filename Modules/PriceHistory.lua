-- PriceHistory: passive auction-house price tracking. Whenever the browse
-- list updates, each item's lowest buyout is stored account-wide; item
-- tooltips then show the cheapest seen price and its age. No active
-- scanning - prices grow organically while you browse the AH.
local _, ns = ...
local S = ns.S
local L = S.L
local PH = S:NewModule("PriceHistory", "pricehistory")

local ipairs, pairs = ipairs, pairs
local floor, format = math.floor, format
local GetNumAuctionItems, GetAuctionItemInfo, GetAuctionItemLink =
	GetNumAuctionItems, GetAuctionItemInfo, GetAuctionItemLink

local MAX_AGE = 14 * 24 * 3600 -- drop entries older than two weeks

local function Store()
	S.db.global.ahPrices = S.db.global.ahPrices or {}
	return S.db.global.ahPrices
end

local function Money(c)
	if not c or c <= 0 then return "-" end
	if S.FormatMoney then return S.FormatMoney(c) end
	return format("%dg %ds %dc", floor(c / 10000), floor(c / 100) % 100, c % 100)
end

local function ItemID(link)
	if not link then return end
	local id = GetItemInfoInstant and GetItemInfoInstant(link)
	if id then return id end
	return tonumber(link:match("item:(%d+)"))
end

function PH:Scan()
	if not self.db.enable or not GetNumAuctionItems then return end
	local n = GetNumAuctionItems("list")
	if not n or n == 0 then return end
	local store, now = Store(), time()
	for i = 1, n do
		local name, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo("list", i)
		local link = GetAuctionItemLink and GetAuctionItemLink("list", i)
		local id = link and ItemID(link)
		if id and buyout and buyout > 0 and count and count > 0 then
			local per = floor(buyout / count)
			local e = store[id]
			if not e then
				store[id] = { min = per, avg = per, n = 1, t = now }
			else
				e.min = math.min(e.min or per, per)
				e.avg = floor(((e.avg or per) * (e.n or 1) + per) / ((e.n or 1) + 1))
				e.n = (e.n or 1) + 1
				e.t = now
			end
		end
	end
end

local function TooltipLine(tt)
	if not (PH.db and PH.db.enable and PH.db.tooltip) then return end
	local _, link = tt:GetItem()
	local id = link and ItemID(link)
	local e = id and Store()[id]
	if not e or not e.min then return end
	local age = floor((time() - (e.t or 0)) / 3600)
	local ageText = age >= 48 and format("%dd", floor(age / 24)) or format("%dh", age)
	tt:AddDoubleLine(L["AH min"], format("%s |cff888888(%s)|r",
		Money(e.min), format(L["%s ago"], ageText)), 0.4, 0.75, 1, 1, 1, 1)
	if e.avg and e.avg ~= e.min then
		tt:AddDoubleLine(L["AH avg"], Money(e.avg), 0.5, 0.6, 0.9, 0.7, 0.7, 0.7)
	end
	tt:Show()
end

function PH:Initialize()
	self.db = S.db.profile.pricehistory
	if not self.db.enable then return end
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE", function() S:SafeCall("PriceHistory:Scan", PH.Scan, PH) end)
	-- prune stale prices once per session
	local store = Store()
	for id, e in pairs(store) do
		if time() - (e.t or 0) > MAX_AGE then store[id] = nil end
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,
			function(tt) S:SafeCall("PriceHistory:Tip", TooltipLine, tt) end)
	elseif GameTooltip then
		GameTooltip:HookScript("OnTooltipSetItem", function(tt) S:SafeCall("PriceHistory:Tip", TooltipLine, tt) end)
	end
end

function PH:Update()
	self.db = S.db.profile.pricehistory
end
