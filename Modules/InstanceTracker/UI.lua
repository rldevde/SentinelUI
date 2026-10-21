-- InstanceTracker UI: main window with Log / Chars / Trades / Lockouts tabs,
-- a post-stats dialog and a copy-paste frame. SentinelUI window style.
local _, ns = ...
local S = ns.S
local L = S.L
local IT = ns.InstanceTracker

local _G = _G
local ipairs, pairs, sort, tinsert, tremove = ipairs, pairs, sort, table.insert, table.remove
local format, floor, min, max = string.format, math.floor, math.min, math.max
local unpack = unpack or table.unpack
local CreateFrame = CreateFrame
local GetServerTime = GetServerTime or time
local date = date

local WIN_W, WIN_H, ROW_H = 560, 420, 20

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function RowColor(inst, i, now)
	-- newest/current green, within the hour yellow-ish, old grey
	if i == 1 and inst.leftTime == 0 then return 0.35, 0.9, 0.4 end
	local t = inst.leftTime and inst.leftTime > 0 and inst.leftTime or inst.enteredTime
	if t and now - t < 3600 then return 0.9, 0.8, 0.3 end
	return 0.65, 0.65, 0.7
end

local function MakeRow(list, i)
	local r = list.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, list)
	r:SetHeight(ROW_H)
	S:CreateBackdrop(r, "Default")
	r.name = S:FontString(r, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
	r.name:SetPoint("LEFT", 8, 0)
	r.name:SetWidth(330)
	r.name:SetWordWrap(false)
	r.mid = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	r.mid:SetPoint("LEFT", 344, 0)
	r.mid:SetWidth(84)
	r.status = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	r.status:SetPoint("RIGHT", -30, 0)
	r.del = CreateFrame("Button", nil, r)
	r.del:SetSize(14, 14)
	r.del:SetPoint("RIGHT", -6, 0)
	S:CreateBackdrop(r.del, "Default")
	r.del.fs = S:FontString(r.del, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
	r.del.fs:SetPoint("CENTER")
	r.del.fs:SetText("x")
	r:SetScript("OnEnter", function(s)
		local bd = s.suiBackdrop or s
		if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b, 1) end
		if s.tip and GameTooltip then
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			GameTooltip:AddLine(s.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end
		if s.tipFunc and GameTooltip then
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			s.tipFunc()
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(s)
		local bd = s.suiBackdrop or s
		if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(unpack(S.media.borderColor)) end
		if GameTooltip then GameTooltip:Hide() end
	end)
	list.rows[i] = r
	return r
end

local function FillRow(r, i)
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", r:GetParent(), "TOPLEFT", 0, -((i - 1) * (ROW_H + 2)))
	r:SetPoint("RIGHT", r:GetParent(), "RIGHT", 0, 0)
	r:Show()
end

local function ClearRow(r)
	r.del:Hide()
	r.del:SetScript("OnClick", nil)
	r:SetScript("OnClick", nil)
	r.tip = nil
	r.tipFunc = nil
	r.name:SetText("")
	r.mid:SetText("")
	r.status:SetText("")
	r:Hide()
end

-- ---------------------------------------------------------------------------
-- instance tooltip body (shared between log row + minimap)
-- ---------------------------------------------------------------------------
local function InstanceTip(inst, i)
	local lines = {}
	local db = IT.db
	lines[#lines + 1] = (inst.instanceName or "?") .. IT:DifficultyTag(inst)
	lines[#lines + 1] = L["Time inside"] .. ": " .. IT:TimeString((inst.leftTime > 0 and inst.leftTime or GetServerTime()) - inst.enteredTime, "short")
	if inst.isPvp then
		if inst.honor and inst.honor > 0 then lines[#lines + 1] = L["Honor"] .. ": " .. IT.Comma(inst.honor) end
		if inst.battleground then
			local b = inst.battleground
			if b.win ~= nil then lines[#lines + 1] = b.win and L["Won"] or L["Lost"] end
			if b.kb then lines[#lines + 1] = format("%d KB / %d HK / %d " .. L["Deaths"], b.kb or 0, b.hk or 0, b.deaths or 0) end
		end
	else
		local mobs = (inst.mobCount and inst.mobCount > 0) and inst.mobCount or inst.mobCountFromKill
		if mobs and mobs > 0 then lines[#lines + 1] = L["Mobs killed"] .. ": " .. IT.Comma(mobs) end
		if inst.xpFromChat and inst.xpFromChat > 0 then
			local s = L["XP gained"] .. ": " .. IT.Comma(inst.xpFromChat)
			if inst.xpForNextLevel and inst.xpForNextLevel > 0 then
				s = s .. format(" (%.1f%%)", inst.xpFromChat / inst.xpForNextLevel * 100)
			end
			lines[#lines + 1] = s
		end
		local secs = (inst.leftTime > 0 and inst.leftTime or GetServerTime()) - inst.enteredTime
		if inst.xpFromChat and inst.xpFromChat > 0 and secs > 60 then
			lines[#lines + 1] = L["XP/Hour"] .. ": " .. IT.Comma(floor(inst.xpFromChat / secs * 3600))
		end
		if inst.rawMoneyCount and inst.rawMoneyCount > 0 then
			lines[#lines + 1] = L["Raw gold from mobs"] .. ": " .. IT:CoinString(inst.rawMoneyCount)
		end
		if inst.leftMoney and inst.enteredMoney and inst.leftMoney > inst.enteredMoney then
			lines[#lines + 1] = L["Gold gained"] .. ": " .. IT:CoinString(inst.leftMoney - inst.enteredMoney)
		end
		if inst.rep then
			for fac, amt in pairs(inst.rep) do
				if amt ~= 0 then lines[#lines + 1] = format("%s %+d", fac, amt) end
			end
		end
		if inst.currencies then
			for _, c in pairs(inst.currencies) do
				if c.count and c.count > 0 then lines[#lines + 1] = format("%s +%d", c.name or L["Currency"], c.count) end
			end
		end
		if inst.groupAverage then
			lines[#lines + 1] = L["Average Group Level"] .. ": " .. inst.groupAverage
		end
		if inst.group then
			local names = {}
			for n, m in pairs(inst.group) do
				names[#names + 1] = format("%s (%s)", IT:ColoredName(n, m.classFile), m.level or "?")
			end
			sort(names)
			if #names > 0 then
				lines[#lines + 1] = L["Group"] .. ": " .. table.concat(names, " ")
			end
		end
		if inst.douses then
			for id, d in pairs(inst.douses) do
				lines[#lines + 1] = format(L["Rune doused"] .. ": %s (ID %s)", d.name or "?", tostring(id))
			end
		end
	end
	return lines
end

-- ---------------------------------------------------------------------------
-- main window
-- ---------------------------------------------------------------------------
local function BuildFrame()
	if IT.frame then return IT.frame end
	local f = CreateFrame("Frame", "SentinelUIInstanceTracker", UIParent)
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER", UIParent, "CENTER", -60, 30)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SetTemplate(f, "Transparent", "TOP")
	f:Hide()

	f.logo = f:CreateTexture(nil, "OVERLAY")
	f.logo:SetSize(16, 16)
	f.logo:SetPoint("TOPLEFT", 8, -6)
	f.logo:SetTexture("Interface\\Icons\\Spell_Arcane_TeleportOrgrimmar")
	f.logo:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)

	f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 6, 0)
	f.title:SetText(L["Instance Tracker"])
	S:RegisterAccent(f.title, "text")

	f.close = CreateFrame("Button", nil, f)
	f.close:SetSize(16, 16)
	f.close:SetPoint("TOPRIGHT", -7, -6)
	S:CreateBackdrop(f.close, "Default")
	f.close.fs = S:FontString(f.close, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.close.fs:SetPoint("CENTER")
	f.close.fs:SetText("x")
	f.close:SetScript("OnClick", function() f:Hide() end)

	f.tabs = {}
	local tabDefs = {
		{ key = "log", label = L["Log"] },
		{ key = "chars", label = L["Chars"] },
		{ key = "trades", label = L["Trades"] },
		{ key = "lockouts", label = L["Lockouts"] },
	}
	for i, def in ipairs(tabDefs) do
		local t = CreateFrame("Button", nil, f)
		t:SetSize(90, 20)
		t:SetPoint("TOPLEFT", 8 + (i - 1) * 94, -28)
		t.key = def.key
		S:CreateBackdrop(t, "Default")
		t.fs = S:FontString(t, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
		t.fs:SetPoint("CENTER")
		t.fs:SetText(def.label)
		t:SetScript("OnClick", function() IT:SetTab(def.key) end)
		f.tabs[i] = t
	end

	-- column headers
	f.colName = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.colName:SetPoint("TOPLEFT", 16, -54)
	f.colName:SetTextColor(0.5, 0.5, 0.55)
	f.colMid = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.colMid:SetPoint("TOPLEFT", 350, -54)
	f.colMid:SetTextColor(0.5, 0.5, 0.55)
	f.colRight = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	f.colRight:SetPoint("TOPRIGHT", -44, -54)
	f.colRight:SetTextColor(0.5, 0.5, 0.55)

	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", 8, -64)
	f.list:SetPoint("BOTTOMRIGHT", -8, 30)
	f.list:EnableMouse(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta)
		IT.scroll = (IT.scroll or 0) - delta * 4
		if IT.scroll < 0 then IT.scroll = 0 end
		IT:RefreshFrame()
	end)
	f.list.rows = {}

	f.summary = S:FontString(f, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.summary:SetPoint("BOTTOMLEFT", 10, 10)
	f.summary:SetPoint("RIGHT", -220, 0)
	f.summary:SetTextColor(0.65, 0.65, 0.7)

	f.statsBtn = CreateFrame("Button", nil, f)
	f.statsBtn:SetSize(96, 18)
	f.statsBtn:SetPoint("BOTTOMRIGHT", -8, 8)
	S:SkinButton(f.statsBtn)
	f.statsBtn.label = S:FontString(f.statsBtn, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.statsBtn.label:SetPoint("CENTER")
	f.statsBtn.label:SetText(L["Post Stats"])
	f.statsBtn:SetScript("OnClick", function() IT:PostStatsDialog() end)

	f.copyBtn = CreateFrame("Button", nil, f)
	f.copyBtn:SetSize(70, 18)
	f.copyBtn:SetPoint("RIGHT", f.statsBtn, "LEFT", -6, 0)
	S:SkinButton(f.copyBtn)
	f.copyBtn.label = S:FontString(f.copyBtn, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.copyBtn.label:SetPoint("CENTER")
	f.copyBtn.label:SetText(L["Copy"])
	f.copyBtn:SetScript("OnClick", function() IT:CopyDialog() end)

	tinsert(UISpecialFrames, "SentinelUIInstanceTracker")
	IT.frame = f
	return f
end

function IT:SetTab(key)
	local f = BuildFrame()
	self.tab = key
	self.scroll = 0
	for _, t in ipairs(f.tabs) do
		local bd = t.suiBackdrop or t
		if t.key == key then
			if bd.SetBackdropColor then bd:SetBackdropColor(S.accent.r * 0.3, S.accent.g * 0.3, S.accent.b * 0.3, 0.8) end
			t.fs:SetTextColor(1, 1, 1)
		else
			if bd.SetBackdropColor then bd:SetBackdropColor(0.08, 0.08, 0.1, 0.8) end
			t.fs:SetTextColor(0.6, 0.6, 0.65)
		end
	end
	self:RefreshFrame()
end

function IT:ToggleFrame(tab)
	local f = BuildFrame()
	if f:IsShown() and (not tab or tab == self.tab) then
		f:Hide()
		return
	end
	f:Show()
	self:SetTab(tab or self.tab or "log")
end

-- ---------------------------------------------------------------------------
-- tab renderers
-- ---------------------------------------------------------------------------
local function RenderLog(f)
	local inst = IT:Data().instances
	f.colName:SetText(L["Instance"])
	f.colMid:SetText(L["Time"])
	f.colRight:SetText(L["Entered"])
	local now = GetServerTime()
	local scroll = IT.scroll or 0
	local shown = 0
	for i = 1 + scroll, #inst do
		shown = shown + 1
		local r = MakeRow(f.list, shown)
		local v = inst[i]
		local rr, gg, bb = RowColor(v, i, now)
		local label = format("%d) %s %s", i, v.instanceName or "?", IT:DifficultyTag(v))
		if v.isPvp then label = label .. " (PvP)" end
		r.name:SetText(label)
		r.name:SetTextColor(rr, gg, bb)
		local secs = (v.leftTime and v.leftTime > 0) and (v.leftTime - v.enteredTime) or (now - v.enteredTime)
		r.mid:SetText(IT:TimeString(secs, "short"))
		r.mid:SetTextColor(rr * 0.9, gg * 0.9, bb * 0.9)
		r.status:SetText(IT:Ago(v.enteredTime))
		r.status:SetTextColor(rr * 0.8, gg * 0.8, bb * 0.8)
		local idx = i
		r.del:Show()
		r.del:SetScript("OnClick", function() IT:DeleteInstance(idx) end)
		r:SetScript("OnClick", function(_, btn)
			if btn == "RightButton" then
				IT:ShowStats(idx, nil)
			end
		end)
		local lines = InstanceTip(v, i)
		r.tipFunc = function()
			for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.92, 0.92, 0.95, true) end
			GameTooltip:AddLine(L["Right-click: post stats to chat"], 0.5, 0.5, 0.55)
		end
		FillRow(r, shown)
		if shown * (ROW_H + 2) > f.list:GetHeight() then break end
	end
	for j = shown + 1, #f.list.rows do ClearRow(f.list.rows[j]) end
	local h, h24 = IT:LockoutInfo()
	f.summary:SetText(format(L["%d in the last hour, %d in the last 24h  |  %d records"], h, h24, #inst))
end

local function CharLine(char, realm, c)
	local lvl = c.level or "?"
	local rest = ""
	if c.restedXP and c.restedXP > 0 and c.maxXP and c.maxXP > 0 then
		rest = format(" (+%d%%)", floor(c.restedXP / c.maxXP * 100 + 0.5))
	end
	local guild = c.guild and format(" <%s>", c.guild) or ""
	local realmTag = realm ~= IT.realm and ("-" .. realm) or ""
	return format("%s%s%s %s%s", IT:ColoredName(char, c.classFile, nil), realmTag, guild, L["Level"] .. " " .. lvl, rest)
end

local function RenderChars(f)
	f.colName:SetText(L["Character"])
	f.colMid:SetText(L["Money"])
	f.colRight:SetText(L["Seen"])
	local list = {}
	IT:EachChar(function(char, realm, cdata) list[#list + 1] = { char = char, realm = realm, c = cdata } end)
	sort(list, function(a, b)
		if (a.c.level or 0) ~= (b.c.level or 0) then return (a.c.level or 0) > (b.c.level or 0) end
		return a.char < b.char
	end)
	local shown = 0
	local scroll = IT.scroll or 0
	for i = 1 + scroll, #list do
		shown = shown + 1
		local e = list[i]
		local r = MakeRow(f.list, shown)
		r.name:SetText(CharLine(e.char, e.realm, e.c))
		r.name:SetTextColor(1, 1, 1)
		r.mid:SetText(e.c.money and IT:CoinString(e.c.money) or "")
		r.mid:SetTextColor(0.9, 0.8, 0.4)
		r.status:SetText(e.c.time and IT:Ago(e.c.time) or "")
		r.status:SetTextColor(0.65, 0.65, 0.7)
		local entry = e
		r.tipFunc = function()
			local c = entry.c
			GameTooltip:AddLine(entry.char .. (entry.realm ~= IT.realm and ("-" .. entry.realm) or ""), 1, 1, 1)
			if c.guild then GameTooltip:AddLine(format("%s <%s>", c.guildRankName or "", c.guild), 0.7, 0.7, 0.75) end
			GameTooltip:AddLine(L["Level"] .. ": " .. (c.level or "?") .. "  |  " .. L["XP"] .. ": " .. IT.Comma(c.currentXP or 0) .. "/" .. IT.Comma(c.maxXP or 0), 0.85, 0.85, 0.9)
			if c.resting then GameTooltip:AddLine(L["Resting"], 0.4, 0.8, 0.4) end
			local atts = {}
			for key, flag in pairs(c) do
				if flag == true and key:match("Attune$") then atts[#atts + 1] = key:gsub("Attune$", "") end
			end
			if #atts > 0 then
				sort(atts)
				GameTooltip:AddLine(L["Attunements"] .. ": " .. table.concat(atts, ", "), 0.9, 0.8, 0.4)
			end
			if c.instances and next(c.instances) then
				local pairs_ = {}
				for id, n in pairs(c.instances) do pairs_[#pairs_ + 1] = format("%s: %d", tostring(id), n) end
				GameTooltip:AddLine(L["Instance counts"] .. ":", 0.7, 0.7, 0.75)
				for _, s in ipairs(pairs_) do GameTooltip:AddLine("  " .. s, 0.6, 0.6, 0.65) end
			end
			if c.savedInstances and next(c.savedInstances) then
				GameTooltip:AddLine(L["Saved instances"] .. ":", 0.7, 0.7, 0.75)
				for _, s in pairs(c.savedInstances) do
					GameTooltip:AddLine(format("  %s (%s) %s", s.name or "?", s.difficulty or "", s.resetTime and IT:Ago(s.resetTime) or ""), 0.6, 0.6, 0.65)
				end
			end
			GameTooltip:AddLine(L["Right-click: delete character data"], 0.5, 0.5, 0.55)
		end
		r:SetScript("OnClick", function(_, btn)
			if btn == "RightButton" and entry.char ~= UnitName("player") then
				SentinelUIInstanceDB[entry.realm].chars[entry.char] = nil
				IT:Print(format(L["Deleted %s from the database."], entry.char))
				IT:RefreshFrame()
			end
		end)
		FillRow(r, shown)
		if shown * (ROW_H + 2) > f.list:GetHeight() then break end
	end
	for j = shown + 1, #f.list.rows do ClearRow(f.list.rows[j]) end
	f.summary:SetText(format(L["%d characters tracked"], #list))
end

local function RenderTrades(f)
	f.colName:SetText(L["Trade"])
	f.colMid:SetText(L["Zone"])
	f.colRight:SetText(L["When"])
	local trades = IT:Data().trades
	local shown = 0
	local scroll = IT.scroll or 0
	for i = 1 + scroll, #trades do
		shown = shown + 1
		local t = trades[i]
		local r = MakeRow(f.list, shown)
		local gave = t.playerMoney and t.playerMoney > 0
		local dir = gave and format(L["Gave %s to %s"], IT:CoinString(t.playerMoney), IT:ColoredName(t.tradeWho, t.tradeWhoClass))
			or format(L["Received %s from %s"], IT:CoinString(t.targetMoney or 0), IT:ColoredName(t.tradeWho, t.tradeWhoClass))
		r.name:SetText(dir)
		r.name:SetTextColor(gave and 0.9 or 0.4, gave and 0.5 or 0.9, 0.4)
		r.mid:SetText(t.where or "")
		r.mid:SetTextColor(0.65, 0.65, 0.7)
		r.status:SetText(IT:Ago(t.time))
		r.status:SetTextColor(0.65, 0.65, 0.7)
		local idx = i
		r.del:Show()
		r.del:SetScript("OnClick", function()
			tremove(IT:Data().trades, idx)
			IT:RefreshFrame()
		end)
		FillRow(r, shown)
		if shown * (ROW_H + 2) > f.list:GetHeight() then break end
	end
	for j = shown + 1, #f.list.rows do ClearRow(f.list.rows[j]) end
	f.summary:SetText(format(L["%d trades logged"], #trades))
end

local function RenderLockouts(f)
	f.colName:SetText(L["Saved instances"])
	f.colMid:SetText(L["Difficulty"])
	f.colRight:SetText(L["Resets"])
	local list = {}
	IT:EachChar(function(char, realm, cdata)
		if cdata.savedInstances then
			for _, s in pairs(cdata.savedInstances) do
				if s.locked then
					list[#list + 1] = { char = char, realm = realm, cf = cdata.classFile, s = s }
				end
			end
		end
	end)
	sort(list, function(a, b)
		if a.s.name ~= b.s.name then return (a.s.name or "") < (b.s.name or "") end
		return a.char < b.char
	end)
	local shown = 0
	local scroll = IT.scroll or 0
	for i = 1 + scroll, #list do
		shown = shown + 1
		local e = list[i]
		local r = MakeRow(f.list, shown)
		r.name:SetText(format("%s  |cff888888%s%s|r", e.s.name or "?", IT:ColoredName(e.char, e.cf), e.realm ~= IT.realm and ("-" .. e.realm) or ""))
		r.name:SetTextColor(1, 1, 1)
		r.mid:SetText(e.s.difficulty or "")
		r.mid:SetTextColor(0.75, 0.75, 0.8)
		local left = (e.s.resetTime or 0) - GetServerTime()
		r.status:SetText(left > 0 and IT:TimeString(left, "short") or L["now"])
		r.status:SetTextColor(0.9, 0.7, 0.3)
		FillRow(r, shown)
		if shown * (ROW_H + 2) > f.list:GetHeight() then break end
	end
	for j = shown + 1, #f.list.rows do ClearRow(f.list.rows[j]) end
	local h, h24 = IT:LockoutInfo()
	f.summary:SetText(format(L["Hourly: %d/%d  |  Daily: %d  |  %d saved instances"], h, IT.hourlyLimit, h24, #list))
end

function IT:RefreshFrame()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local tab = self.tab or "log"
	if tab == "log" then RenderLog(f)
	elseif tab == "chars" then RenderChars(f)
	elseif tab == "trades" then RenderTrades(f)
	elseif tab == "lockouts" then RenderLockouts(f) end
	f.statsBtn:SetShown(tab == "log")
	f.copyBtn:SetShown(tab == "log")
end

-- ---------------------------------------------------------------------------
-- post-stats + copy dialogs
-- ---------------------------------------------------------------------------
local function MakeDialog(name, title, w, h)
	if _G[name] then return _G[name] end
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(w, h)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SetTemplate(f, "Transparent", "TOP")
	f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("TOPLEFT", 10, -8)
	f.title:SetText(title)
	S:RegisterAccent(f.title, "text")
	f.close = CreateFrame("Button", nil, f)
	f.close:SetSize(16, 16)
	f.close:SetPoint("TOPRIGHT", -7, -6)
	S:CreateBackdrop(f.close, "Default")
	f.close.fs = S:FontString(f.close, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.close.fs:SetPoint("CENTER")
	f.close.fs:SetText("x")
	f.close:SetScript("OnClick", function() f:Hide() end)
	f:Hide()
	tinsert(UISpecialFrames, name)
	return f
end

local STAT_TARGETS = { "party", "raid", "guild", "say", "yell", "officer" }
function IT:PostStatsDialog()
	local r = self:Data().instances[1]
	if not r then self:Print(L["No instance data to post."]) return end
	local f = MakeDialog("SentinelUIITStats", L["Post stats to chat"], 240, 30 + #STAT_TARGETS * 26 + 10)
	for i, ch in ipairs(STAT_TARGETS) do
		local b = f["btn" .. i]
		if not b then
			b = CreateFrame("Button", nil, f)
			b:SetSize(210, 22)
			b:SetPoint("TOP", 0, -30 - (i - 1) * 26)
			S:SkinButton(b)
			b.fs = S:FontString(b, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
			b.fs:SetPoint("CENTER")
			f["btn" .. i] = b
		end
		b.fs:SetText(L[ch:sub(1, 1):upper() .. ch:sub(2)] or ch)
		b:SetScript("OnClick", function()
			IT:ShowStats(1, ch, true)
			f:Hide()
		end)
		b:Show()
	end
	f:Show()
end

function IT:CopyDialog()
	local r = self:Data().instances[1]
	if not r then self:Print(L["No instance data to copy."]) return end
	local f = MakeDialog("SentinelUIITCopy", L["Copy instance data"], 440, 300)
	if not f.box then
		local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 10, -30)
		sf:SetPoint("BOTTOMRIGHT", -30, 10)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetFontObject(ChatFontNormal or GameFontNormal)
		eb:SetWidth(390)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		sf:SetScrollChild(eb)
		f.box = eb
	end
	local lines = { (self:StatLine(1, true) or "") }
	for i = 2, min(#self:Data().instances, 10) do
		lines[#lines + 1] = self:StatLine(i, true) or ""
	end
	f.box:SetText(table.concat(lines, "\n"))
	f:Show()
	f.box:HighlightText()
	f.box:SetFocus()
end

-- ---------------------------------------------------------------------------
-- level log (tracked + its own window)
-- ---------------------------------------------------------------------------
function IT:LevelLogInit()
	local char = self:Char()
	char.levelLog = char.levelLog or {}
end

function IT:OnLevelUp(newLevel)
	local char2 = self:Char()
	char2.levelLog = char2.levelLog or {}
	if RequestTimePlayed then pcall(RequestTimePlayed) end
	local x, y = 0, 0
	if C_Map and C_Map.GetPlayerMapPosition and C_Map.GetBestMapForUnit then
		local map = C_Map.GetBestMapForUnit("player")
		local pos = map and C_Map.GetPlayerMapPosition(map, "player")
		if pos then x, y = pos.x * 100, pos.y * 100 end
	end
	C_Timer.After(1.5, function()
		tinsert(char2.levelLog, {
			level = newLevel,
			time = GetServerTime(),
			zone = GetZoneText and GetZoneText() or "",
			x = x, y = y,
			gold = GetMoney and GetMoney() or 0,
			played = IT.playedCache or 0,
			quests = IT.questsSinceLevel or 0,
			mobs = IT.mobsSinceLevel or 0,
		})
		IT.questsSinceLevel, IT.mobsSinceLevel = 0, 0
		IT:RefreshLevelLog()
	end)
end

function IT:LevelLogToggle()
	local f = MakeDialog("SentinelUILevelLog", L["Level Log"], 480, 380)
	if not f.list then
		local list = CreateFrame("Frame", nil, f)
		list:SetPoint("TOPLEFT", 8, -30)
		list:SetPoint("BOTTOMRIGHT", -8, 8)
		list:EnableMouse(true)
		list:EnableMouseWheel(true)
		list.rows = {}
		list:SetScript("OnMouseWheel", function(_, delta)
			IT.llScroll = max(0, (IT.llScroll or 0) - delta * 4)
			IT:RefreshLevelLog()
		end)
		f.list = list
	end
	f:Show()
	self:RefreshLevelLog()
end

function IT:RefreshLevelLog()
	local f = _G.SentinelUILevelLog
	if not f or not f:IsShown() then return end
	local char = self:Char()
	local log = char.levelLog or {}
	f.list.rows = f.list.rows or {}
	local shown = 0
	local scroll = self.llScroll or 0
	for i = #log - scroll, 1, -1 do
		shown = shown + 1
		local e = log[i]
		local r = f.list.rows[shown]
		if not r then
			r = CreateFrame("Button", nil, f.list)
			r:SetHeight(ROW_H)
			S:CreateBackdrop(r, "Default")
			r.fs = S:FontString(r, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
			r.fs:SetPoint("LEFT", 8, 0)
			r.fs:SetWidth(455)
			r.fs:SetWordWrap(false)
			f.list.rows[shown] = r
		end
		r.fs:SetText(format(L["Level %d  |  %s  |  %s (%.0f,%.0f)  |  %s  |  %dq %dm  |  %s"],
			e.level or 0,
			e.time and date("%d.%m %H:%M", e.time) or "?",
			e.zone or "?", e.x or 0, e.y or 0,
			e.played and IT:TimeString(e.played, "short") or "?",
			e.quests or 0, e.mobs or 0,
			IT:CoinString(e.gold or 0)))
		r.fs:SetTextColor(1, 1, 1)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -((shown - 1) * (ROW_H + 2)))
		r:SetPoint("RIGHT", f.list, "RIGHT", 0, 0)
		r:Show()
		if shown * (ROW_H + 2) > f.list:GetHeight() then break end
	end
	for j = shown + 1, #f.list.rows do f.list.rows[j]:Hide() end
end
