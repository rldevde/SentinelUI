-- Staged AH scan: walks the item classes one by one and pages through each
-- (50 rows per page, short pause between queries, one page digested per
-- step). Nothing is ever dumped in one batch -> no client freeze. Uses the
-- client's 9-argument QueryAuctionItems via AH:Query with a class filter
-- (filterData = { { classID = n } }). Feeds AH:PriceDB + ahPrices store.
local _, ns = ...
local S = ns.S
local L = S.L
local AH = ns.AH

local floor = math.floor
local PAGE_SIZE = 50
local STAGE_DELAY = 0.30 -- seconds between queries
local STAGE_TIMEOUT = 4.0 -- skip a page the server never answers
local MAX_PAGES = 400 -- per class, guards broken clients
local COMMIT_CHUNK = 4000 -- DB writes per tick at the end
local MAX_DROPS = 12

local scan = { running = false }
AH.scan = scan

-- Enum.ItemClass ids that can appear on the AH (Consumable .. Miscellaneous)
local function ClassList()
	local E = Enum and Enum.ItemClass
	if E then
		local l = { E.Consumable, E.Container, E.Weapon, E.Gem, E.Armor, E.Reagent, E.Projectile,
			E.Tradegoods, E.Recipe, E.Quiver, E.Questitem or E.Quest, E.Key, E.Miscellaneous }
		local out = {}
		for _, v in pairs(l) do out[#out + 1] = v end
		table.sort(out)
		if #out > 0 then return out end
	end
	return { 0, 1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 15 }
end

-- digest the rows of the page that just arrived (<= 50, trivial cost)
local function DigestPage(total)
	for j = 1, total do
		local name, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo("list", j)
		if name and buyout and buyout > 0 and count and count > 0 then
			local id = select(17, GetAuctionItemInfo("list", j))
			if not id and GetAuctionItemLink then id = AH:ItemID(GetAuctionItemLink("list", j)) end
			local per = floor(buyout / count)
			if id and per > 0 then
				local e = scan.seen[id]
				if not e or per < e then scan.seen[id] = per end
			end
		end
	end
end

-- final commit, chunked so a big seen-table can't hitch a frame
local commitKey
local function CommitTick()
	local db = AH:PriceDB()
	local store = S.db.global.ahPrices or {}
	S.db.global.ahPrices = store
	local ph = S.GetModule and S:GetModule("PriceHistory", true)
	local now, i = time(), 0
	while true do
		local per
		commitKey, per = next(scan.seen, commitKey)
		if commitKey == nil then break end
		local id = commitKey
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
	scan.running, scan.committing = false, false
	scan.lastDone = time()
	if AH.scanBtn then AH.scanBtn:Enable() end
	if n == 0 then
		AH:Status(L["Scan returned no items (empty AH or query blocked)"])
	else
		AH:Status(format(L["Scan complete: %d items"], n))
	end
end

local function Abort(msg)
	scan.running, scan.committing, scan.pending = false, false, false
	if AH.scanBtn then AH.scanBtn:Enable() end
	AH:Status(msg)
end

-- advance to the next class (page counter reset)
local function NextClass()
	scan.ci, scan.page, scan.retries = scan.ci + 1, 0, 0
end

local waitT = 0
local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function(_, elapsed)
	if not scan.running then return end
	if scan.committing then
		if CommitTick() then Done() end
		return
	end
	waitT = waitT + elapsed
	if scan.pending then
		if waitT > STAGE_TIMEOUT then
			scan.drops = scan.drops + 1
			if scan.drops > MAX_DROPS then
				Abort(L["Scan failed - the AH never answered page queries"])
				return
			end
			scan.retries = scan.retries + 1
			if scan.retries > 2 then NextClass() end -- give this class up
			scan.pending = false
			waitT = 0
		end
		return
	end
	if waitT < STAGE_DELAY then return end
	if scan.ci > #scan.classes then
		commitKey = nil
		scan.committing = true
		return
	end
	if CanSendAuctionQuery and not CanSendAuctionQuery() then return end
	if AH:Query("", nil, nil, scan.page, false, false, { { classID = scan.classes[scan.ci] } }) then
		scan.pending = true
		waitT = 0
	end
end)

frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function()
	if not scan.running or not scan.pending then return end
	scan.pending, waitT = false, 0
	local total = GetNumAuctionItems("list") or 0
	S:SafeCall("AH:ScanPage", function()
		scan.drops = 0
		if total > 0 then DigestPage(total) end
		AH:Status(format(L["Scanning auction house: category %d / %d (page %d)"], scan.ci, #scan.classes, scan.page + 1))
		if total < PAGE_SIZE or scan.page + 1 >= MAX_PAGES then
			NextClass() -- partial/empty page = last page of this class
		else
			scan.page = scan.page + 1
		end
	end)
end)

function scan:Start()
	if self.running then AH:Status(L["Scan already running"]) return end
	if not QueryAuctionItems then AH:Status(L["AH API unavailable"]) return end
	if CanSendAuctionQuery and not CanSendAuctionQuery() then AH:Status(L["AH not ready - wait a moment"]) return end
	self.running, self.committing, self.pending = true, false, false
	self.seen, self.classes = {}, ClassList()
	self.ci, self.page, self.retries, self.drops = 1, 0, 0, 0
	waitT = STAGE_DELAY
	AH:Status(format(L["Staged scan started: %d categories..."], #self.classes))
	if AH.scanBtn then AH.scanBtn:Disable() end
end

function scan:Stop()
	if not self.running then return end
	Abort(L["Scan stopped"])
end

-- kept for API compatibility; the flow is driven by the OnUpdate frame
function scan:Hook() end
