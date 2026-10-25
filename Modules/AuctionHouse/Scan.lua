-- Staged AH scan: instead of one getAll query that makes the server dump
-- the whole list in a single batch (and freezes the client for seconds),
-- the scan walks the AH page by page - 50 auctions per query, a short
-- pause between queries, results digested per page. A 50k+ house takes a
-- while but the game stays smooth. Feeds AH:PriceDB + ahPrices store.
local _, ns = ...
local S = ns.S
local L = S.L
local AH = ns.AH

local floor = math.floor
local PAGE_DELAY = 0.35 -- seconds between page queries
local PAGE_TIMEOUT = 3.0 -- requery/skip a page if the server stalls
local PAGE_MAX_RETRY = 2
local COMMIT_CHUNK = 4000 -- DB writes per tick at the end

local scan = { running = false, page = 0, totalPages = 0, seen = nil }
AH.scan = scan

-- --------------------------------------------------------------------------
-- page digest: read the 50 rows of the page that just arrived
-- --------------------------------------------------------------------------
local function DigestPage(total)
	local n = 0
	for j = 1, total do
		local name, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo("list", j)
		if name and buyout and buyout > 0 and count and count > 0 then
			-- itemID sits at index 17 on legacy clients; the link parse is
			-- the slow path and only runs as fallback
			local id = select(17, GetAuctionItemInfo("list", j))
			if not id and GetAuctionItemLink then
				id = AH:ItemID(GetAuctionItemLink("list", j))
			end
			local per = floor(buyout / count)
			if id and per > 0 then
				local e = scan.seen[id]
				if not e or per < e then scan.seen[id] = per end
				n = n + 1
			end
		end
	end
	return n
end

-- --------------------------------------------------------------------------
-- final commit, chunked so even a huge seen-table can't hitch a frame
-- --------------------------------------------------------------------------
local commitIter
local function CommitTick()
	local db = AH:PriceDB()
	local store = S.db.global.ahPrices or {}
	S.db.global.ahPrices = store
	local ph = S.GetModule and S:GetModule("PriceHistory", true)
	local now, i = time(), 0
	for id, per in commitIter do
		local e = db[id]
		if not e then db[id] = { p = per, t = now } else e.p, e.t = per, now end
		local h = store[id]
		if not h then store[id] = { min = per, avg = per, n = 1, t = now } else h.min = math.min(h.min or per, per) h.t = now end
		if ph and ph.RecordPrice then ph:RecordPrice(h, per, now, id) end
		i = i + 1
		if i >= COMMIT_CHUNK then return false end
	end
	return true
end

local function Finish()
	commitIter = pairs(scan.seen or {})
	scan.committing = true
end

local function Done(n)
	scan.running, scan.committing = false, false
	scan.lastDone = time()
	if AH.scanBtn then AH.scanBtn:Enable() end
	AH:Status(format(L["Scan complete: %d items"], n or 0))
end

-- --------------------------------------------------------------------------
-- query driver: one page query, wait for the list update, next page
-- --------------------------------------------------------------------------
local waitT, pending = 0, false

local function QueryPage()
	if not QueryAuctionItems then return false end
	local can = true
	if CanSendAuctionQuery then can = CanSendAuctionQuery() end
	if not can then return false end -- try again next tick
	-- QueryAuctionItems(text, minLvl, maxLvl, invType, class, subClass, page,
	--   usable, quality, getAll, exactMatch)
	QueryAuctionItems("", 0, 0, 0, 0, 0, scan.page, 0, 0, false, false)
	pending = true
	waitT = 0
	return true
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function(_, elapsed)
	if not scan.running then return end
	if scan.committing then
		if CommitTick() then
			local n = 0
			for _ in pairs(scan.seen or {}) do n = n + 1 end
			Done(n)
		end
		return
	end
	waitT = waitT + elapsed
	if pending then
		if waitT > PAGE_TIMEOUT then
			-- server dropped the page: retry a few times, then skip ahead
			scan.retries = (scan.retries or 0) + 1
			if scan.retries > PAGE_MAX_RETRY then
				scan.retries, scan.page = 0, scan.page + 1
			end
			pending = false
			waitT = -PAGE_DELAY -- small pause before the retry
		end
		return
	end
	if waitT < PAGE_DELAY then return end
	if scan.totalPages > 0 and scan.page >= scan.totalPages then
		Finish()
		return
	end
	if not QueryPage() then return end
end)

frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function()
	if not scan.running or not pending then return end
	pending = false
	waitT = 0
	local total = GetNumAuctionItems("list") or 0
	S:SafeCall("AH:ScanPage", function()
		local got = DigestPage(total)
		-- the full list advertises ~50 rows per page; the last page is partial
		if scan.totalPages == 0 then
			scan.totalPages = math.max(1, math.ceil((total or 0) / 50))
			-- GetNumAuctionItems returns the page size only, so estimate the
			-- real total differently: keep paging until an empty page shows
			scan.totalPages = 0
		end
		scan.retries = 0
		if total == 0 then
			Finish() -- empty page = end of the list
			return
		end
		scan.page = scan.page + 1
		local est = (scan.page * 50) + (total == 50 and 50 or total)
		AH:Status(format(L["Scanning auction house: page %d (~%d auctions)"], scan.page, est))
	end)
end)

function scan:Start()
	if self.running then AH:Status(L["Scan already running"]) return end
	if not QueryAuctionItems then AH:Status(L["AH API unavailable"]) return end
	local can = true
	if CanSendAuctionQuery then can = CanSendAuctionQuery() end
	if not can then AH:Status(L["AH not ready - wait a moment"]) return end
	self.running, self.committing = true, false
	self.seen, self.page, self.retries = {}, 0, 0
	pending, waitT = false, PAGE_DELAY
	AH:Status(L["Staged scan started - page by page..."])
	if AH.scanBtn then AH.scanBtn:Disable() end
end

function scan:Stop()
	if not self.running then return end
	pending = false
	self.running, self.committing = false, false
	if AH.scanBtn then AH.scanBtn:Enable() end
	AH:Status(L["Scan stopped"])
end

-- kept for API compatibility; the page flow is driven by the OnUpdate frame
function scan:Hook() end
