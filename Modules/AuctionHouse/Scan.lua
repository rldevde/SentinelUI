-- Staged AH scan. A blank-text non-getAll query is silently dropped by the
-- server (the client only accepts unfiltered searches via getAll or with a
-- class filter), so the scan walks the item CLASSES instead of getAll:
-- each QueryAuctionItems("", ..., classIndex=i) returns one moderate batch
-- (hundreds to a few thousand rows, not the whole house) which is digested
-- in small chunks -> no freeze. Feeds AH:PriceDB + ahPrices store.
local _, ns = ...
local S = ns.S
local L = S.L
local AH = ns.AH

local floor = math.floor
local STAGE_DELAY = 0.30 -- seconds between class queries
local STAGE_TIMEOUT = 4.0 -- give up on a class batch if the server stalls
local DIGEST_CHUNK = 1500 -- rows digested per frame tick
local COMMIT_CHUNK = 4000 -- DB writes per tick at the end

local scan = { running = false }
AH.scan = scan

-- --------------------------------------------------------------------------
-- class list: GetAuctionItemClasses indexes are what the query wants
-- --------------------------------------------------------------------------
local function ClassCount()
	if GetAuctionItemClasses then
		local n = select("#", GetAuctionItemClasses())
		if n and n > 0 then return n end
	end
	return 10 -- sane fallback for the classic category count
end

-- --------------------------------------------------------------------------
-- batch digest, chunked across ticks so a big class can't hitch a frame
-- --------------------------------------------------------------------------
local digestI = 1
local function DigestTick(total)
	local last = math.min(digestI + DIGEST_CHUNK - 1, total)
	for j = digestI, last do
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
			end
		end
	end
	digestI = last + 1
	return last >= total
end

-- --------------------------------------------------------------------------
-- final commit, chunked as well
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

local function Done()
	local n = 0
	for _ in pairs(scan.seen or {}) do n = n + 1 end
	scan.running, scan.digesting, scan.committing = false, false, false
	scan.lastDone = time()
	if AH.scanBtn then AH.scanBtn:Enable() end
	if n == 0 then
		AH:Status(L["Scan returned no items (empty AH or query blocked)"])
	else
		AH:Status(format(L["Scan complete: %d items"], n))
	end
end

-- --------------------------------------------------------------------------
-- query driver: one class query -> wait for the batch -> digest -> next
-- --------------------------------------------------------------------------
local waitT, pending = 0, false

local function QueryClass()
	local can = true
	if CanSendAuctionQuery then can = CanSendAuctionQuery() end
	if not can then return false end
	-- QueryAuctionItems(text, minLvl, maxLvl, invType, class, subClass, page,
	--   usable, quality, getAll, exactMatch) - class filter makes the blank
	--   text acceptable, page 0 grabs the whole class batch
	QueryAuctionItems("", 0, 0, 0, scan.classIndex, 0, 0, 0, 0, false, false)
	pending = true
	waitT = 0
	return true
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function(_, elapsed)
	if not scan.running then return end
	if scan.committing then
		if CommitTick() then Done() end
		return
	end
	if scan.digesting then
		local total = scan.batchTotal or 0
		if DigestTick(total) then
			scan.digesting = false
			scan.classIndex = scan.classIndex + 1
			waitT = 0
			AH:Status(format(L["Scanning auction house: category %d / %d"], scan.classIndex, scan.classCount or 0))
		end
		return
	end
	waitT = waitT + elapsed
	if pending then
		if waitT > STAGE_TIMEOUT then
			-- class query dropped: skip this class rather than stalling
			scan.classIndex = scan.classIndex + 1
			pending = false
			waitT = 0
		end
		return
	end
	if waitT < STAGE_DELAY then return end
	if scan.classIndex > (scan.classCount or 0) then
		commitIter = pairs(scan.seen or {})
		scan.committing = true
		return
	end
	QueryClass()
end)

frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function()
	if not scan.running or not pending then return end
	pending = false
	waitT = 0
	local total = GetNumAuctionItems("list") or 0
	S:SafeCall("AH:ScanBatch", function()
		if total == 0 then
			scan.classIndex = scan.classIndex + 1
			return
		end
		scan.batchTotal = total
		digestI = 1
		scan.digesting = true -- chunked digest starts next tick
	end)
end)

function scan:Start()
	if self.running then AH:Status(L["Scan already running"]) return end
	if not QueryAuctionItems then AH:Status(L["AH API unavailable"]) return end
	local can = true
	if CanSendAuctionQuery then can = CanSendAuctionQuery() end
	if not can then AH:Status(L["AH not ready - wait a moment"]) return end
	self.running = true
	self.digesting, self.committing = false, false
	self.seen = {}
	self.classIndex, self.classCount = 1, ClassCount()
	pending, waitT = false, STAGE_DELAY
	AH:Status(format(L["Staged scan started: %d categories..."], self.classCount))
	if AH.scanBtn then AH.scanBtn:Disable() end
end

function scan:Stop()
	if not self.running then return end
	pending = false
	self.running, self.digesting, self.committing = false, false, false
	if AH.scanBtn then AH.scanBtn:Enable() end
	AH:Status(L["Scan stopped"])
end

-- kept for API compatibility; the flow is driven by the OnUpdate frame
function scan:Hook() end
