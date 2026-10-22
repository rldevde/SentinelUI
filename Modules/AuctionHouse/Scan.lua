-- Full AH scan: QueryAuctionItems with getAll pulls the entire list in one
-- batch; results are then digested in chunks so a 50k+ auction house does
-- not freeze the client. Feeds AH:PriceDB and the shared ahPrices store.
local _, ns = ...
local S = ns.S
local L = S.L
local AH = ns.AH

local floor = math.floor
local CHUNK = 2000 -- rows processed per frame tick

local scan = { running = false, progress = 0 }
AH.scan = scan

local function Track(update)
	-- process results incrementally; 'update' repeats every tick
	if not scan.running then return end
	local total = GetNumAuctionItems("list")
	local i = scan.cursor or 1
	local last = math.min(i + CHUNK - 1, total)
	local now = time()
	for j = i, last do
		local name, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo("list", j)
		if name and buyout and buyout > 0 and count and count > 0 then
			local id
			if GetAuctionItemLink then
				id = AH:ItemID(GetAuctionItemLink("list", j))
			end
			if not id then
				id = select(17, GetAuctionItemInfo("list", j)) -- itemID on legacy
			end
			local per = floor(buyout / count)
			if id and per > 0 then
				-- keep the cheapest unit price seen this scan
				local e = scan.seen[id]
				if not e or per < e then scan.seen[id] = per end
			end
		end
	end
	scan.cursor = last + 1
	AH:Status(format(L["Scanning auction house: %d / %d"], last, total))
	if last >= total then
		-- commit
		local db, n = AH:PriceDB(), 0
		for id, per in pairs(scan.seen) do
			local e = db[id]
			if not e then db[id] = { p = per, t = now } else e.p, e.t = per, now end
			n = n + 1
			-- feed the PriceHistory tooltip store as well
			local store = S.db.global.ahPrices
			if not store then S.db.global.ahPrices = {}; store = S.db.global.ahPrices end
			local h = store[id]
			if not h then store[id] = { min = per, avg = per, n = 1, t = now } h = store[id]
			else h.min = math.min(h.min or per, per); h.t = now end
			local ph = S.GetModule and S:GetModule("PriceHistory", true)
			if ph and ph.RecordPrice then ph:RecordPrice(h, per, now) end
		end
		scan.running = false
		scan.ticker = nil
		scan.lastDone = now
		if AH.scanBtn then AH.scanBtn:Enable() end
		AH:Status(format(L["Scan complete: %d items"], n))
		return true -- done
	end
end

local tickerFrame = CreateFrame("Frame")
local accum = 0
tickerFrame:SetScript("OnUpdate", function(_, elapsed)
	if not scan.running then return end
	accum = accum + elapsed
	if accum < 0.05 then return end -- ~20 ticks/s
	accum = 0
	S:SafeCall("AH:ScanTick", Track)
end)

function scan:Start()
	if self.running then AH:Status(L["Scan already running"]) return end
	if not QueryAuctionItems then AH:Status(L["AH API unavailable"]) return end
	local can, canAll = true, true
	if CanSendAuctionQuery then can, canAll = CanSendAuctionQuery() end
	if not can then AH:Status(L["AH not ready - wait a moment"]) return end
	if not canAll then AH:Status(L["Full scan not possible right now (cooldown)"]) return end
	-- QueryAuctionItems(text, minLvl, maxLvl, invType, class, subClass, page,
	--   usable, quality, getAll, exactMatch)
	QueryAuctionItems("", 0, 0, 0, 0, 0, 0, 0, 0, true, false)
	self.running = true
	self.seen = {}
	self.cursor = nil -- set when the batch arrives
	AH:Status(L["Full scan started - waiting for data..."])
	if AH.scanBtn then AH.scanBtn:Disable() end
end

function scan:Hook()
	local f = CreateFrame("Frame")
	f:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	f:SetScript("OnEvent", function()
		if scan.running and scan.cursor == nil then
			scan.cursor = 1 -- first tick picks the batch up
		end
	end)
end
