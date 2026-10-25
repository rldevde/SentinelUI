-- AuctionHouse: SentinelUI's Auctionator-style suite for the legacy AH.
-- Adds a "S-AH" tab to Blizzard's AuctionFrame with three sub-tabs:
-- Buy (shopping lists + filtered search), Sell (bag items + undercut
-- suggestion) and Auctions (own auctions + undercut marker + cancel).
-- A full scan feeds the shared price DB (same store as PriceHistory, so
-- the tooltip module picks scan results up automatically).
-- Module is DISABLED by default - enable via /sui Modules.
local _, ns = ...
local S = ns.S
local L = S.L
local AH = S:NewModule("AuctionHouse", "auctionhouse")
ns.AH = AH

local ipairs, pairs = ipairs, pairs
local floor, format = math.floor, format
local tinsert, tremove, sort = tinsert, tremove, table.sort

AH.panels = {}
AH.panelOrder = { "buy", "sell", "cancel" }
AH.panelNames = { buy = "Shopping", sell = "Selling", cancel = "Cancelling" }

-- ------------------------------------------------------------ shared helpers --
-- external feed: a companion data addon (SentinelAHData, written by an
-- outside tool like TSM's app helper) exposes SENTINEL_AH_DATA. Entries for
-- the current realm+faction are merged in and flagged src="ext" so scans
-- can tell them apart. Newer external timestamps win over older local data.
function AH:MergeExternalDB()
	local ext = _G.SENTINEL_AH_DATA
	if type(ext) ~= "table" or type(ext.realms) ~= "table" then return 0 end
	local realm = GetRealmName and GetRealmName() or "?"
	local fac = UnitFactionGroup and UnitFactionGroup("player") or "?"
	local list = ext.realms[realm .. "-" .. fac] or ext.realms[realm]
	if type(list) ~= "table" then return 0 end
	local db, n, ts = self:PriceDB(), 0, ext.updated or time()
	for id, price in pairs(list) do
		id, price = tonumber(id), tonumber(price)
		if id and price and price > 0 then
			local e = db[id]
			if not e or (e.t or 0) <= ts then
				db[id] = { p = price, t = ts, src = "ext" }
				n = n + 1
			end
		end
	end
	self.externalInfo = { updated = ts, count = n, source = ext.source }
	return n
end

function AH:PriceDB()
	local realm = GetRealmName and GetRealmName() or "?"
	local fac = UnitFactionGroup and UnitFactionGroup("player") or "?"
	S.db.global.auctionDB = S.db.global.auctionDB or {}
	local key = realm .. "-" .. fac
	if not S.db.global.auctionDB[key] then S.db.global.auctionDB[key] = {} end
	return S.db.global.auctionDB[key]
end

-- The anniversary client uses the 9-argument query signature
-- (text, minLvl, maxLvl, page, usable, quality, getAll, exact, filterData).
-- The old 11-argument legacy form shifted every argument (a "0" ended up as
-- quality filter = grey items only, so searches returned nothing).
-- quality stays nil = all qualities; filterData = { { classID = n }, ... }.
function AH:Query(text, minLvl, maxLvl, page, usable, exact, filterData, getAll)
	if not QueryAuctionItems then return false end
	QueryAuctionItems(text or "",
		(minLvl and minLvl > 0) and minLvl or nil, (maxLvl and maxLvl > 0) and maxLvl or nil,
		page or 0, usable and true or nil, nil,
		getAll and true or false, exact and true or false, filterData)
	return true
end

function AH:ItemID(link)
	if not link or type(link) ~= "string" then return end
	if GetItemInfoInstant then
		local id = GetItemInfoInstant(link)
		if id then return id end
	end
	return tonumber(link:match("item:(%d+)"))
end

function AH:Money(c)
	if not c or c <= 0 then return "-" end
	if S.FormatMoney then return S.FormatMoney(c) end
	return format("%dg %ds %dc", floor(c / 10000), floor(c / 100) % 100, c % 100)
end

function AH:CopperFromText(text)
	-- parse "12g 30s 5c" / "12.30.05" style input, returns copper or nil
	if not text or text == "" then return end
	local g = tonumber(text:match("(%d+)%s*[gG]"))
	local s = tonumber(text:match("(%d+)%s*[sS]"))
	local c = tonumber(text:match("(%d+)%s*[cC]"))
	if g or s or c then return (g or 0) * 10000 + (s or 0) * 100 + (c or 0) end
	local n = tonumber((text:gsub(",", ".")))
	if n then return floor(n * 10000 + 0.5) end -- bare number = gold
end

function AH:PriceFor(id)
	local e = id and self:PriceDB()[id]
	return e and e.p or nil
end

-- store a seen unit-buyout into the shared price DB AND the PriceHistory
-- store so tooltips benefit from scan/sell data as well
function AH:StorePrice(id, unitPrice)
	if not id or not unitPrice or unitPrice <= 0 then return end
	local now = time()
	local db = self:PriceDB()
	local e = db[id]
	if not e then db[id] = { p = unitPrice, t = now } else e.p, e.t = unitPrice, now end
	local store = S.db.global.ahPrices
	if not store then S.db.global.ahPrices = {}; store = S.db.global.ahPrices end
	local h = store[id]
	if not h then
		store[id] = { min = unitPrice, avg = unitPrice, n = 1, t = now }
	else
		h.min = math.min(h.min or unitPrice, unitPrice)
		h.avg = floor(((h.avg or unitPrice) * (h.n or 1) + unitPrice) / ((h.n or 1) + 1))
		h.n = (h.n or 1) + 1
		h.t = now
	end
end

function AH:Status(msg)
	if self.statusText then self.statusText:SetText(msg or "") end
	if msg and msg ~= "" and self.db and self.db.scanAlerts then
		S:Print("|cff4aa3ff[AH]|r " .. msg)
	end
end

-- shared multi-line text dialog for import/export strings
function AH:TextDialog(title, text, okLabel, onAccept)
	local d = self.dlg
	if not d then
		d = CreateFrame("Frame", "SentinelAHDialog", UIParent,
			S.BackdropTemplate or "BackdropTemplateMixin")
		d:SetSize(320, 240)
		d:SetPoint("CENTER")
		d:SetFrameStrata("DIALOG")
		d:SetMovable(true)
		d:EnableMouse(true)
		d:RegisterForDrag("LeftButton")
		d:SetScript("OnDragStart", function(f) f:StartMoving() end)
		d:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
		S:CreateBackdrop(d, "Default")
		d.title = S:FontString(d, 11, "OUTLINE", S.media.unitFont)
		d.title:SetPoint("TOP", 0, -8)
		local sf = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 10, -28)
		sf:SetPoint("BOTTOMRIGHT", -30, 38)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetWidth(260)
		eb:SetFontObject(GameFontHighlightSmall or GameFontHighlight)
		eb:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
		sf:SetScrollChild(eb)
		d.eb = eb
		local ok = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
		ok:SetSize(110, 20)
		ok:SetPoint("BOTTOMLEFT", 10, 8)
		if S.SkinButton then S:SkinButton(ok) end
		ok:SetScript("OnClick", function()
			if d.onAccept then S:SafeCall("AH:Dialog", d.onAccept, d.eb:GetText()) end
			d:Hide()
		end)
		d.ok = ok
		local cc = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
		cc:SetSize(110, 20)
		cc:SetPoint("BOTTOMRIGHT", -10, 8)
		cc:SetText(L["Cancel"])
		if S.SkinButton then S:SkinButton(cc) end
		cc:SetScript("OnClick", function() d:Hide() end)
		if UISpecialFrames then tinsert(UISpecialFrames, d:GetName()) end
		d:Hide()
		self.dlg = d
	end
	d.title:SetText(title or "")
	d.ok:SetText(okLabel or "OK")
	d.onAccept = onAccept
	d.eb:SetText(text or "")
	d:Show()
	if text and text ~= "" then d.eb:HighlightText() d.eb:SetFocus() end
end

-- --------------------------------------------------------------- the AH tab --
function AH:ShowSubTab(name)
	for n, p in pairs(self.panels) do
		if p.frame then p.frame:SetShown(n == name) end
		if p.tab then
			if n == name then p.tab:LockHighlight() else p.tab:UnlockHighlight() end
		end
	end
	self.currentTab = name
	local p = self.panels[name]
	if p and p.refresh then S:SafeCall("AH:" .. name, p.refresh, p) end
end

function AH:BuildUI()
	if self.frame or not AuctionFrame then return end
	local f = CreateFrame("Frame", "SentinelAHFrame", AuctionFrame)
	-- occupy the space the browse list normally uses
	f:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 10, -68)
	f:SetPoint("BOTTOMRIGHT", AuctionFrame, "BOTTOMRIGHT", -10, 34)
	S:CreateBackdrop(f, "Default")
	f:Hide()
	self.frame = f

	-- own top-level tab appended to the AuctionFrame tab row
	local idx = (AuctionFrame.numTabs or 3) + 1
	AuctionFrame.numTabs = idx
	local tab = CreateFrame("Button", "AuctionFrameTab" .. idx, AuctionFrame, "CharacterFrameTabButtonTemplate")
	tab:SetID(idx)
	tab:SetText("S-AH")
	tab:SetPoint("LEFT", _G["AuctionFrameTab" .. (idx - 1)] or AuctionFrameTab3, "RIGHT", -15, 0)
	if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
	if S.SkinTab then S:SkinTab(tab) end
	tab:SetScript("OnClick", function()
		PanelTemplates_SetTab(AuctionFrame, idx)
		if AuctionFrameBrowse then AuctionFrameBrowse:Hide() end
		if AuctionFrameBid then AuctionFrameBid:Hide() end
		if AuctionFrameAuctions then AuctionFrameAuctions:Hide() end
		f:Show()
		AH:ShowSubTab(AH.currentTab or "buy")
	end)
	self.tab = tab

	-- hide our page when a Blizzard tab takes over
	if AuctionFrameTab_OnClick then
		hooksecurefunc("AuctionFrameTab_OnClick", function(btn)
			if btn ~= tab then f:Hide() end
		end)
	end
	AuctionFrame:HookScript("OnHide", function() f:Hide() end)

	-- sub-tab bar inside our page
	local prev
	for _, name in ipairs(self.panelOrder) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(110, 20)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		else b:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6) end
		b:SetText(L[AH.panelNames[name]] or AH.panelNames[name])
		if S.SkinButton then S:SkinButton(b) end
		local n = name
		b:SetScript("OnClick", function() AH:ShowSubTab(n) end)
		local pf = CreateFrame("Frame", nil, f)
		pf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
		pf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		pf:Hide()
		self.panels[name] = self.panels[name] or {}
		self.panels[name].tab = b
		self.panels[name].frame = pf
		prev = b
	end

	-- status line along the bottom
	self.statusText = S:FontString(f, 10, nil, S.media.numberFont)
	self.statusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 6)

	-- full-scan button top-right
	local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	scan:SetSize(110, 20)
	scan:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
	scan:SetText(L["Full Scan"])
	if S.SkinButton then S:SkinButton(scan) end
	scan:SetScript("OnClick", function() AH.scan:Start() end)
	self.scanBtn = scan

	-- let the sub-modules fill their panels
	if self.buy and self.buy.Build then self.buy:Build(self.panels.buy.frame) end
	if self.sell and self.sell.Build then self.sell:Build(self.panels.sell.frame) end
	if self.cancel and self.cancel.Build then self.cancel:Build(self.panels.cancel.frame) end
end

function AH:Initialize()
	self.db = S.db.profile.auctionhouse
	-- feature switch: turning the module off in profile stops every hook,
	-- event and the auto-scan even if the private module flag stayed on
	if self.db.enable == false then return end
	S.db.global.ahShopping = S.db.global.ahShopping
		or { lists = { { name = L["Default List"], items = {} } }, current = 1 }
	-- pull the external feed (SentinelAHData) once at init and again when
	-- the AH opens, so a tool that rewrites it between sessions always lands
	S:SafeCall("AH:MergeExternal", self.MergeExternalDB, self)
	self:RegisterEvent("AUCTION_HOUSE_SHOW", function()
		local n = S:SafeCall("AH:MergeExternal", self.MergeExternalDB, self)
		if n and n > 0 then
			AH:Status(format(L["External price feed: %d item(s)"], n))
		end
		S:SafeCall("AH:BuildUI", AH.BuildUI, AH)
		-- background re-scan: keeps the price DB fresh without a manual button
		-- (the getAll cooldown still applies, CanSendAuctionQuery gates it)
		if AH.db.autoScan ~= false and AH.scan and not AH.scan.running then
			local can = true
			if CanSendAuctionQuery then can = CanSendAuctionQuery() end
			local stale = not AH.scan.lastDone or (time() - AH.scan.lastDone) > 900
			if can and stale then
				AH:Status(L["Auto-scanning auction house..."])
				AH.scan:Start()
			end
		end
	end)
	if self.scan and self.scan.Hook then self.scan:Hook() end
	if self.cancel and self.cancel.Hook then self.cancel:Hook() end
end

function AH:Update()
	self.db = S.db.profile.auctionhouse
end
