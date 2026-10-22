-- PriceHistory: passive auction-house price tracking. Whenever the browse
-- list updates, each item's lowest buyout is stored account-wide; item
-- tooltips then show the cheapest seen price and its age. No active
-- scanning - prices grow organically while you browse the AH.
local _, ns = ...
local S = ns.S
local L = S.L
local PH = S:NewModule("PriceHistory", "pricehistory")

local ipairs, pairs = ipairs, pairs
local floor, format, tremove, tinsert = math.floor, format, tremove, tinsert
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

-- watchlist: itemID -> target unit price; alerted once per 12h per item
local function Alerts()
	S.db.global.ahAlerts = S.db.global.ahAlerts or {}
	return S.db.global.ahAlerts
end

local function CheckAlert(id, per, now)
	local a = Alerts()[id]
	if not a or not a.p or per > a.p then return end
	if a.last and (now - a.last) < 43200 then return end
	a.last = now
	local name = (GetItemInfo and select(1, GetItemInfo(id))) or ("item:" .. id)
	S:Print(format(L["Price alert: %s is at %s (target %s)"], name or ("item:" .. id), Money(per), Money(a.p)))
	if PlaySound and SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_CLOSE then pcall(PlaySound, SOUNDKIT.AUCTION_WINDOW_CLOSE) end
end

-- time series: one sample per ~6h window, entries older than MAX_AGE pruned.
-- exported so the AH full scan can feed the same history.
function PH:RecordPrice(e, per, now, id)
	if id then CheckAlert(id, per, now) end
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
			PH:RecordPrice(e, per, now, id)
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

local function AlertCmd(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local alerts = Alerts()
	if msg == "" then
		local n = 0
		for id, a in pairs(alerts) do
			n = n + 1
			local name = select(1, S.GetItemInfo(id)) or ("item:" .. id)
			S:Print(format("|cffffd700%s|r: %s", name, Money(a.p)))
		end
		if n == 0 then S:Print(L["No price alerts set"]) end
		return
	end
	local link, rest = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)%s*(.*)")
	if not link then link, rest = msg:match("(|Hitem:%d+[^|]*|h%[.-%]|h)%s*(.*)") end
	local id = link and ItemID(link)
	if not id then S:Print(L["Usage: /suialert [itemlink] <price|off>"]) return end
	if rest == "off" or rest == "" then
		alerts[id] = nil
		S:Print(L["Price alert removed"])
		return
	end
	local g, s, c = rest:match("(%d+)%s*g"), rest:match("(%d+)%s*s"), rest:match("(%d+)%s*c")
	local copper = (tonumber(g) or 0) * 10000 + (tonumber(s) or 0) * 100 + (tonumber(c) or 0)
	if copper == 0 and not (g or s or c) then copper = (tonumber(rest) or 0) * 10000 end -- bare number = gold
	if copper <= 0 then S:Print(L["Usage: /suialert [itemlink] <price|off>"]) return end
	alerts[id] = { p = copper }
	S:Print(format(L["Price alert set: %s at %s"], link, Money(copper)))
end

-- price chart: bar graph of the stored time series ---------------------------
local chart
local function ShowChart(itemID, link)
	local e = Store()[itemID]
	local hist = e and e.hist
	if not hist or #hist == 0 then S:Print(L["No price data for that item"]) return end
	if not chart then
		chart = CreateFrame("Frame", "SentinelUIPriceChart", UIParent, S.BackdropTemplate)
		chart:SetSize(290, 180)
		chart:SetPoint("CENTER")
		S:SetTemplate(chart, "Default")
		chart:SetMovable(true)
		chart:EnableMouse(true)
		chart:RegisterForDrag("LeftButton")
		chart:SetScript("OnDragStart", chart.StartMoving)
		chart:SetScript("OnDragStop", chart.StopMovingOrSizing)
		chart:SetClampedToScreen(true)
		chart:SetFrameStrata("DIALOG")
		chart.title = S:FontString(chart, 12, "OUTLINE", S.media.unitFont)
		chart.title:SetPoint("TOP", 0, -10)
		chart.plot = CreateFrame("Frame", nil, chart)
		chart.plot:SetPoint("TOPLEFT", 16, -30)
		chart.plot:SetPoint("BOTTOMRIGHT", -16, 26)
		chart.minmax = S:FontString(chart, 10, "OUTLINE", S.media.numberFont)
		chart.minmax:SetPoint("BOTTOM", 0, 8)
		local close = CreateFrame("Button", nil, chart, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)
		chart.bars = {}
		tinsert(UISpecialFrames, "SentinelUIPriceChart")
	end
	local W, H = chart.plot:GetWidth(), chart.plot:GetHeight()
	local n = #hist
	local lo, hi = math.huge, 0
	for _, s in ipairs(hist) do if s.p < lo then lo = s.p end if s.p > hi then hi = s.p end end
	local range = math.max(hi - lo, 1)
	local bw = W / n
	for i, s in ipairs(hist) do
		local bar = chart.bars[i] or chart.plot:CreateTexture(nil, "ARTWORK")
		chart.bars[i] = bar
		local bh = math.max(2, (s.p - lo) / range * (H - 16) + 4)
		bar:ClearAllPoints()
		bar:SetSize(math.max(1, bw - 1), bh)
		bar:SetPoint("BOTTOMLEFT", chart.plot, "BOTTOMLEFT", (i - 1) * bw, 4)
		bar:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, i == n and 1 or 0.7)
		bar:Show()
	end
	for i = n + 1, #chart.bars do chart.bars[i]:Hide() end
	local name = link or select(1, S.GetItemInfo(itemID)) or ("item:" .. itemID)
	chart.title:SetText(name)
	chart.minmax:SetText(format("min %s   max %s   last %s", Money(lo), Money(hi), Money(hist[#hist].p)))
	chart:Show()
end

local function ChartCmd(msg)
	msg = (msg or ""):gsub("^%s+", "")
	local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or msg:match("(|Hitem:%d+[^|]*|h%[.-%]|h)")
	if not link then S:Print(L["Usage: /suiprice [itemlink]"]) return end
	local id = ItemID(link)
	if id then ShowChart(id, link) end
end

function PH:Initialize()
	self.db = S.db.profile.pricehistory
	if not self.db.enable then return end
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE", function() S:SafeCall("PriceHistory:Scan", PH.Scan, PH) end)
	S:RegisterChatCommand("suialert", AlertCmd)
	S:RegisterChatCommand("ahalert", AlertCmd)
	S:RegisterChatCommand("suiprice", ChartCmd)
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
