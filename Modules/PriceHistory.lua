-- PriceHistory: passive auction-house price tracking. Whenever the browse
-- list updates, each item's lowest buyout is stored account-wide; item
-- tooltips then show the cheapest seen price and its age. No active
-- scanning - prices grow organically while you browse the AH.
local _, ns = ...
local S = ns.S
local L = S.L
local PH = S:NewModule("PriceHistory", "pricehistory")

local ipairs, pairs = ipairs, pairs
local floor, format, tremove = math.floor, format, tremove
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

-- time series: one sample per ~6h window, entries older than MAX_AGE pruned.
-- exported so the AH full scan can feed the same history.
function PH:RecordPrice(e, per, now)
	if not e.hist then e.hist = {} end
	local last = e.hist[#e.hist]
	if not last or (now - (last.t or 0)) > 21600 then
		e.hist[#e.hist + 1] = { t = now, p = per }
	elseif per < (last.p or per) then
		last.p = per -- keep the cheapest observation inside the window
	end
	local i = 1
	while e.hist[i] and now - (e.hist[i].t or 0) > MAX_AGE do i = i + 1 end
	if i > 1 then
		for j = 1, #e.hist - i + 1 do e.hist[j] = e.hist[j + i - 1] end
		for j = #e.hist - i + 2, #e.hist do e.hist[j] = nil end
	end
	while #e.hist > 40 do tremove(e.hist, 1) end
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
				e = { min = per, avg = per, n = 0, t = now }
				store[id] = e
			else
				e.min = math.min(e.min or per, per)
				e.avg = floor(((e.avg or per) * (e.n or 1) + per) / ((e.n or 1) + 1))
				e.n = (e.n or 1) + 1
				e.t = now
			end
			PH:RecordPrice(e, per, now)
		end
	end
end

-- freshest price: the AH module's getAll scan DB (per realm+faction)
local function ScanPrice(id)
	local db = S.db.global.auctionDB
	if not db then return end
	local key = (GetRealmName and GetRealmName() or "?") .. "-" .. (UnitFactionGroup and UnitFactionGroup("player") or "?")
	local e = db[key] and db[key][id]
	if e and e.p then return e.p, e.t end
end

local function AgeText(t)
	local age = floor((time() - (t or 0)) / 3600)
	return format(L["%s ago"], age >= 48 and format("%dd", floor(age / 24)) or format("%dh", age))
end

local function TooltipLine(tt)
	if not (PH.db and PH.db.enable and PH.db.tooltip) then return end
	local _, link = tt:GetItem()
	local id = link and ItemID(link)
	if not id then return end
	local added
	local sp, st = ScanPrice(id)
	if sp then
		tt:AddDoubleLine(L["AH"], format("%s |cff888888(%s)|r", Money(sp), AgeText(st)), 0.4, 0.75, 1, 1, 1, 1)
		added = true
	end
	local e = Store()[id]
	if e and e.min and (not sp or e.min ~= sp) then
		tt:AddDoubleLine(L["AH min"], format("%s |cff888888(%s)|r", Money(e.min), AgeText(e.t)), 0.4, 0.75, 1, 1, 1, 1)
		added = true
	end
	if e and e.avg and e.avg ~= e.min then
		tt:AddDoubleLine(L["AH avg"], Money(e.avg), 0.5, 0.6, 0.9, 0.7, 0.7, 0.7)
		added = true
	end
	if e and e.hist and #e.hist >= 2 then
		local first, last = e.hist[1], e.hist[#e.hist]
		if first.p and first.p > 0 and last.p ~= first.p then
			local pct = (last.p - first.p) / first.p * 100
			local days = max(1, floor(((last.t or 0) - (first.t or 0)) / 86400))
			local col = pct > 0 and "|cffff6060" or "|cff60ff60"
			tt:AddDoubleLine(format(L["Trend %dd"], days), format("%s%+.0f%%|r", col, pct), 0.9, 0.9, 0.9, 1, 1, 1)
			added = true
		end
	end
	local sellPrice = select(11, S.GetItemInfo(link))
	if sellPrice and sellPrice > 0 then
		tt:AddDoubleLine(L["Vendor"], Money(sellPrice), 0.7, 0.7, 0.7, 1, 1, 1)
		added = true
	end
	if added then tt:Show() end
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
