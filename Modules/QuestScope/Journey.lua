-- QuestScope Journey: quest browser. Left column lists zones (with quest
-- counts), right column the quests of the selected zone — name, level,
-- completion state — searchable. Click a quest to waypoint its starter.
local _, ns = ...
local S = ns.S
local L = S.L
local QS = S:GetModule("QuestScope")

local _G = _G
local ipairs, sort, tinsert = ipairs, sort, table.insert
local format, strlower = string.format, string.lower
local CreateFrame, GameTooltip = CreateFrame, GameTooltip

-- data field indices (see generated Data_*.lua)
local Q_NAME, Q_START, Q_FINISH, Q_REQLVL, Q_LVL, Q_OBJTEXT, Q_ZONE, Q_SPECIAL = 1, 2, 3, 4, 5, 8, 17, 24
local Q_PREGROUP, Q_PRESINGLE, Q_NEXTCHAIN = 12, 13, 22
local N_NAME, N_SPAWNS, O_NAME, O_SPAWNS = 1, 7, 1, 4
local I_NAME, I_NPCDROP = 1, 2

local ROW_H = 16
local J -- journey frame

local function DiffHex(level)
	local c = GetQuestDifficultyColor and GetQuestDifficultyColor(level or 1)
	local r, g, b
	if type(c) == "table" then
		r, g, b = c.r or 1, c.g or 1, c.b or 1
	else
		local diff = (level or 1) - UnitLevel("player")
		if diff >= 5 then r, g, b = 1, 0.2, 0.2
		elseif diff >= 3 then r, g, b = 1, 0.5, 0.25
		elseif diff >= -2 then r, g, b = 1, 0.82, 0
		elseif diff >= -7 then r, g, b = 0.25, 1, 0.25
		else r, g, b = 0.55, 0.55, 0.55 end
	end
	return format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function QuestDone(qid)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		local ok, r = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
		if ok then return r and true or false end
	end
	return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(qid) and true or false
end

-- ---------------------------------------------------------------------------
-- zone index (built lazily on first open)
-- ---------------------------------------------------------------------------
local function BuildZones()
	if J.zones then return end
	local QD = QS:GetData() or {}
	local zones = {}
	for qid, qd in pairs(QD.Quest or {}) do
		local zid = qd[Q_ZONE]
		if zid then
			local z = zones[zid]
			if not z then
				local mapID = QS._AreaToMap(zid)
				local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
				z = { id = zid, name = (info and info.name) or ("Zone " .. zid), quests = {} }
				zones[zid] = z
			end
			z.quests[#z.quests + 1] = qid
		end
	end
	J.zones = {}
	for _, z in pairs(zones) do J.zones[#J.zones + 1] = z end
	sort(J.zones, function(a, b) return a.name < b.name end)
	-- "everything" bucket for the global search
	J.allZone = { id = -2, name = "All", quests = {} }
	for qid in pairs(QD.Quest or {}) do J.allZone.quests[#J.allZone.quests + 1] = qid end
	for _, z in ipairs(J.zones) do
		sort(z.quests, function(a, b)
			local qa, qb = QD.Quest[a], QD.Quest[b]
			if (qa[Q_LVL] or 0) == (qb[Q_LVL] or 0) then return a < b end
			return (qa[Q_LVL] or 0) < (qb[Q_LVL] or 0)
		end)
	end
	sort(J.allZone.quests, function(a, b)
		local qa, qb = QD.Quest[a], QD.Quest[b]
		if (qa[Q_LVL] or 0) == (qb[Q_LVL] or 0) then return a < b end
		return (qa[Q_LVL] or 0) < (qb[Q_LVL] or 0)
	end)
end

-- waypoint to the first known spawn of whatever starts the quest
local function WaypointToStarter(qid)
	local QD = QS:GetData() or {}
	local qd = QD.Quest and QD.Quest[qid]
	if not qd then return end
	local start = qd[Q_START]
	if not start then return end
	local title = QS._L10nName("Quest", qid, qd[Q_NAME])
	local function nav(spawns)
		for _, p in ipairs(QS._SpawnPoints(spawns)) do
			p.title = title
			QS:NavTo(p)
			return true
		end
	end
	for _, npcId in ipairs(start[1] or {}) do
		local nd = QD.Npc and QD.Npc[npcId]
		if nav(nd and nd[N_SPAWNS]) then return end
	end
	for _, objId in ipairs(start[2] or {}) do
		local od = QD.Object and QD.Object[objId]
		if nav(od and od[O_SPAWNS]) then return end
	end
	-- item-started quests: waypoint the drop source NPCs
	for _, itemId in ipairs(start[3] or {}) do
		local it = QD.Item and QD.Item[itemId]
		for _, npcId in ipairs(it and it[I_NPCDROP] or {}) do
			local nd = QD.Npc and QD.Npc[npcId]
			if nav(nd and nd[N_SPAWNS]) then return end
		end
	end
end

-- ---------------------------------------------------------------------------
-- detail pane (rightmost column)
-- ---------------------------------------------------------------------------
local function FillDetail(qid)
	local QD = QS:GetData() or {}
	local qd = qid and QD.Quest and QD.Quest[qid]
	if not qd then
		J.dFrame:Hide()
		return
	end
	J.selQid = qid
	local name = QS._L10nName("Quest", qid, qd[Q_NAME]) or ("Quest " .. qid)
	local lvl = qd[Q_LVL] or qd[Q_REQLVL] or 0
	local lines = {}
	local function add(t) lines[#lines + 1] = t end

	add(format("|cff%s[%d] %s|r", DiffHex(lvl), lvl, name))
	local zid = qd[Q_ZONE]
	local mapID = zid and QS._AreaToMap(zid)
	local zinfo = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	if zinfo then add("|cff888888" .. zinfo.name .. "|r") end
	local done = QuestDone(qid)
	local inlog = QS.logQuests and QS.logQuests[qid]
	if done then
		add("|cff33ff33" .. (L["Completed"] or "Completed") .. "|r")
	elseif inlog then
		add("|cffffff00" .. (L["In quest log"] or "In quest log") .. "|r")
	end

	-- objective text (localized when available)
	local lt = QD.L10n and QD.L10n[GetLocale()]
	local locRow = lt and lt.Quest and lt.Quest[qid]
	local obj = (type(locRow) == "table" and locRow[2] and locRow[2][1]) or qd[Q_OBJTEXT]
	if type(obj) == "table" then obj = obj[1] end
	if obj then add(" ") add("|cffcccccc" .. obj .. "|r") end

	-- live objectives when the quest is in the log
	if inlog and QS.ObjectivesOf then
		local state = QS.ObjectivesOf(qid)
		if state and #state > 0 then
			add(" ")
			for _, o in ipairs(state) do
				local need, have = o.numNeeded or 1, o.numFulfilled or 0
				local fin = o.finished or have >= need
				add(format("|cff%s- %s %d/%d|r",
					fin and "66cc66" or "ffcc66", o.text or "?", have, need))
			end
		end
	end

	-- started by / turn in at
	local function names(kind, ids, nameFld)
		local out = {}
		for _, id in ipairs(ids or {}) do
			local ed = QD[kind] and QD[kind][id]
			out[#out + 1] = QS._L10nName(kind, id, ed and ed[nameFld]) or (kind .. " " .. id)
		end
		return table.concat(out, ", ")
	end
	local start = qd[Q_START]
	if start then
		local g = {}
		local n = names("Npc", start[1], N_NAME)
		if n ~= "" then g[#g + 1] = n end
		n = names("Object", start[2], O_NAME)
		if n ~= "" then g[#g + 1] = n end
		for _, itemId in ipairs(start[3] or {}) do
			local it = QD.Item and QD.Item[itemId]
			local inm = QS._L10nName("Item", itemId, it and it[I_NAME]) or ("Item " .. itemId)
			g[#g + 1] = "|cffffffff" .. inm .. "|r"
		end
		if #g > 0 then
			add(" ")
			add("|cffFFD100" .. (L["Given by:"] or "Given by:") .. "|r " .. table.concat(g, ", "))
		end
	end
	local finish = qd[Q_FINISH]
	if finish then
		local g = {}
		local n = names("Npc", finish[1], N_NAME)
		if n ~= "" then g[#g + 1] = n end
		n = names("Object", finish[2], O_NAME)
		if n ~= "" then g[#g + 1] = n end
		if #g > 0 then
			add("|cffFFD100" .. (L["Turn in at:"] or "Turn in at:") .. "|r " .. table.concat(g, ", "))
		end
	end

	-- quest chain
	local function chainName(pid)
		local pqd = QD.Quest[pid]
		local nm = QS._L10nName("Quest", pid, pqd and pqd[Q_NAME]) or ("Quest " .. pid)
		return format("|cff%s%s|r", QuestDone(pid) and "33ff33" or "ff6666", nm)
	end
	local pre = {}
	for _, pid in ipairs(qd[Q_PREGROUP] or {}) do pre[#pre + 1] = chainName(pid) end
	for _, pid in ipairs(qd[Q_PRESINGLE] or {}) do pre[#pre + 1] = chainName(pid) end
	if #pre > 0 then
		add(" ")
		add("|cff888888" .. (L["Requires:"] or "Requires:") .. "|r " .. table.concat(pre, ", "))
	end
	if qd[Q_NEXTCHAIN] then
		add("|cff888888" .. (L["Continues with:"] or "Continues with:") .. "|r " .. chainName(qd[Q_NEXTCHAIN]))
	end

	J.dText:SetText(table.concat(lines, "\n"))
	J.dContent:SetHeight(J.dText:GetStringHeight() + 8)
	J.dScroll:SetVerticalScroll(0)
	J.dFrame:Show()
	-- buttons: waypoint always when a starter exists, track only for log quests
	J.dWay.qid = qid
	J.dWay:SetShown(qd[Q_START] ~= nil)
	J.dTrack.qid = qid
	J.dTrack:SetShown(inlog and true or false)
end

-- ---------------------------------------------------------------------------
-- quest list (right side)
-- ---------------------------------------------------------------------------
local function QuestRow(i)
	local row = J.qRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, J.qContent)
	row:SetHeight(ROW_H)
	row.sel = row:CreateTexture(nil, "BACKGROUND")
	row.sel:SetAllPoints()
	row.sel:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.22)
	row.sel:Hide()
	row.hl = row:CreateTexture(nil, "BACKGROUND")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.07)
	row.hl:Hide()
	row.fs = S:FontString(row, 12)
	row.fs:SetPoint("LEFT", 4, 0)
	row.fs:SetPoint("RIGHT", -4, 0)
	row.fs:SetJustifyH("LEFT")
	row.fs:SetWordWrap(false)
	row:SetScript("OnClick", function(r)
		J.selQid = r.qid
		for _, q in ipairs(J.qRows) do q.sel:Hide() end
		r.sel:Show()
		FillDetail(r.qid)
	end)
	row:SetScript("OnEnter", function(r)
		r.hl:Show()
		local qid = r.qid
		local QD = QS:GetData() or {}
		local qd = qid and QD.Quest and QD.Quest[qid]
		if not qd then return end
		GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
		GameTooltip:AddLine(QS._L10nName("Quest", qid, qd[Q_NAME]) or "", 1, 1, 1)
		local lt = QD.L10n and QD.L10n[GetLocale()]
		local locRow = lt and lt.Quest and lt.Quest[qid]
		local obj = (type(locRow) == "table" and locRow[2] and locRow[2][1]) or qd[8]
		if type(obj) == "table" then obj = obj[1] end
		if obj then GameTooltip:AddLine(obj, 0.8, 0.8, 0.8, true) end
		-- quest chain: prerequisites (green = done, red = open) and continuation
		local function chainName(pid)
			local pqd = QD.Quest[pid]
			local nm = QS._L10nName("Quest", pid, pqd and pqd[Q_NAME]) or ("Quest " .. pid)
			return format("|cff%s%s|r", QuestDone(pid) and "33ff33" or "ff6666", nm)
		end
		local pre = {}
		for _, pid in ipairs(qd[Q_PREGROUP] or {}) do pre[#pre + 1] = chainName(pid) end
		for _, pid in ipairs(qd[Q_PRESINGLE] or {}) do pre[#pre + 1] = chainName(pid) end
		if #pre > 0 then
			GameTooltip:AddLine((L["Requires:"] or "Requires:") .. " " .. table.concat(pre, ", "), 0.8, 0.8, 0.8)
		end
		local nxt = qd[Q_NEXTCHAIN]
		if nxt then
			GameTooltip:AddLine((L["Continues with:"] or "Continues with:") .. " " .. chainName(nxt), 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine(L["Click: show details"] or "Click: show details", 0.55, 0.55, 0.55)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(r) r.hl:Hide() GameTooltip:Hide() end)
	J.qRows[i] = row
	return row
end

local function FillQuests(zone, filter)
	local QD = QS:GetData() or {}
	-- the "quest log" pseudo-zone rebuilds from the live log on every view
	if zone.id == -1 then
		zone.quests = {}
		for qid in pairs(QS.logQuests or {}) do zone.quests[#zone.quests + 1] = qid end
		sort(zone.quests, function(a, b)
			local qa, qb = QD.Quest and QD.Quest[a], QD.Quest and QD.Quest[b]
			return ((qa and qa[Q_LVL]) or 0) < ((qb and qb[Q_LVL]) or 0)
		end)
	end
	local n, y = 0, 0
	local w = J.qContent:GetWidth()
	local f = filter and strlower(filter)
	for _, qid in ipairs(zone.quests) do
		local qd = QD.Quest and QD.Quest[qid]
		local name = QS._L10nName("Quest", qid, qd and qd[Q_NAME]) or ("Quest " .. qid)
		-- match localized AND english name
		if not f or strlower(name):find(f, 1, true)
			or (qd and qd[Q_NAME] and strlower(qd[Q_NAME]):find(f, 1, true)) then
			n = n + 1
			local row = QuestRow(n)
			row.qid = qid
			row.sel:SetShown(J.selQid == qid)
			row:SetPoint("TOPLEFT", 0, y)
			row:SetWidth(w)
			local done = QuestDone(qid)
			local inlog = QS.logQuests and QS.logQuests[qid]
			local lvl = (qd and (qd[Q_LVL] or qd[Q_REQLVL])) or 0
			row.fs:SetText(format("|cff%s[%d]|r %s%s%s", DiffHex(lvl), lvl, name,
				done and " |cff33ff33✓|r" or "",
				inlog and " |cffffff00◆|r" or ""))
			if done then
				row.fs:SetTextColor(0.5, 0.9, 0.5)
			elseif inlog then
				row.fs:SetTextColor(1, 0.85, 0.3)
			elseif lvl <= UnitLevel("player") then
				row.fs:SetTextColor(1, 1, 1)
			else
				row.fs:SetTextColor(0.5, 0.5, 0.5)
			end
			row:Show()
			y = y - ROW_H
		end
	end
	for i = n + 1, #J.qRows do J.qRows[i]:Hide() end
	J.qContent:SetHeight(-y)
end

-- ---------------------------------------------------------------------------
-- zone list (left side)
-- ---------------------------------------------------------------------------
local function ZoneRow(i)
	local row = J.zRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, J.zContent)
	row:SetHeight(ROW_H)
	row.sel = row:CreateTexture(nil, "BACKGROUND")
	row.sel:SetAllPoints()
	row.sel:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.22)
	row.sel:Hide()
	row.hl = row:CreateTexture(nil, "BACKGROUND")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.06)
	row.hl:Hide()
	row.fs = S:FontString(row, 12)
	row.fs:SetPoint("LEFT", 4, 0)
	row.fs:SetPoint("RIGHT", -4, 0)
	row.fs:SetJustifyH("LEFT")
	row.fs:SetWordWrap(false)
	row:SetScript("OnEnter", function(r) r.hl:Show() end)
	row:SetScript("OnLeave", function(r) r.hl:Hide() end)
	row:SetScript("OnClick", function(r)
		J.selZone = r.zone
		for _, z in ipairs(J.zRows) do z.fs:SetTextColor(1, 1, 1) z.sel:Hide() end
		r.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
		r.sel:Show()
		FillQuests(r.zone, J.search:GetText())
	end)
	J.zRows[i] = row
	return row
end

local function FillZones()
	BuildZones()
	-- live "quest log" pseudo-zone on top: the player's active quests
	local zones = {}
	if next(QS.logQuests or {}) then
		local logZone = { id = -1, name = L["Quest Log"] or "Quest Log", quests = {} }
		for qid in pairs(QS.logQuests) do logZone.quests[#logZone.quests + 1] = qid end
		local QD = QS:GetData() or {}
		sort(logZone.quests, function(a, b)
			local qa, qb = QD.Quest and QD.Quest[a], QD.Quest and QD.Quest[b]
			return ((qa and qa[Q_LVL]) or 0) < ((qb and qb[Q_LVL]) or 0)
		end)
		zones[1] = logZone
	end
	for _, z in ipairs(J.zones) do zones[#zones + 1] = z end

	local w = J.zContent:GetWidth()
	for i, z in ipairs(zones) do
		local row = ZoneRow(i)
		row.zone = z
		row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		row:SetWidth(w)
		if z.id == -1 then
			row.fs:SetText(format("|cff33ff33%s|r |cff888888(%d)|r", z.name, #z.quests))
		else
			row.fs:SetText(format("%s |cff888888(%d)|r", z.name, #z.quests))
		end
		row:Show()
	end
	for i = #zones + 1, #J.zRows do J.zRows[i]:Hide() end
	J.zContent:SetHeight(#zones * ROW_H)
	-- select the player's current zone by default, else the first entry
	if not J.selZone then
		local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		local info = here and C_Map.GetMapInfo(here)
		J.selZone = J.zones[1]
		if info then
			for _, z in ipairs(J.zones) do
				if z.name == info.name then J.selZone = z break end
			end
		end
	end
	for _, z in ipairs(J.zRows) do z.fs:SetTextColor(1, 1, 1) z.sel:Hide() end
	if J.selZone then
		for _, z in ipairs(J.zRows) do
			if z.zone == J.selZone then
				z.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
				z.sel:Show()
			end
		end
		FillQuests(J.selZone, J.search:GetText())
	end
end

-- ---------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------
local function CreateJourney()
	if J then return end
	J = CreateFrame("Frame", "SentinelUIQuestJourney", UIParent, S.BackdropTemplate)
	J:SetSize(880, 430)
	J:SetPoint("CENTER")
	J:SetFrameStrata("DIALOG")
	J:SetClampedToScreen(true)
	J:EnableMouse(true)
	J:SetMovable(true)
	J:RegisterForDrag("LeftButton")
	J:SetScript("OnDragStart", J.StartMoving)
	J:SetScript("OnDragStop", J.StopMovingOrSizing)
	S:CreateBackdrop(J, "Default")
	J:Hide()

	J.title = S:FontString(J, 13, "OUTLINE")
	J.title:SetPoint("TOP", 0, -8)
	J.title:SetText("SentinelUI " .. (L["Quest Journey"] or "Quest Journey"))
	S:RegisterAccent(J.title, "text")

	local tline = J:CreateTexture(nil, "ARTWORK")
	tline:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.5)
	tline:SetHeight(1)
	tline:SetPoint("TOPLEFT", 10, -26)
	tline:SetPoint("TOPRIGHT", -10, -26)

	local close = CreateFrame("Button", nil, J, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	-- search box
	J.search = CreateFrame("EditBox", nil, J, "InputBoxTemplate")
	J.search:SetSize(160, 20)
	J.search:SetPoint("TOPLEFT", 14, -30)
	J.search:SetAutoFocus(false)
	S:SetFont(J.search)
	S:SkinEditBox(J.search)
	J.search:SetScript("OnTextChanged", function(e)
		local t = e:GetText()
		if t and t ~= "" then
			-- global search across the whole database (like Questie's advanced search)
			if J.allZone then FillQuests(J.allZone, t) end
		elseif J.selZone then
			FillQuests(J.selZone, nil)
		end
	end)
	J.search:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
	local shint = S:FontString(J, 10)
	shint:SetPoint("LEFT", J.search, "RIGHT", 8, 0)
	shint:SetText(L["Search"] or "Search")
	shint:SetTextColor(0.5, 0.5, 0.5)

	-- left: zone list
	J.zScroll = CreateFrame("ScrollFrame", "SentinelUIQuestJourneyZones", J, "UIPanelScrollFrameTemplate")
	J.zScroll:SetPoint("TOPLEFT", 10, -56)
	J.zScroll:SetPoint("BOTTOMLEFT", 10, 10)
	J.zScroll:SetWidth(210)
	J.zContent = CreateFrame("Frame", nil, J.zScroll)
	J.zContent:SetSize(190, 10)
	J.zScroll:SetScrollChild(J.zContent)
	S:SkinScrollBar(J.zScroll.ScrollBar or _G[J.zScroll:GetName() .. "ScrollBar"])

	-- middle: quest list
	J.qScroll = CreateFrame("ScrollFrame", "SentinelUIQuestJourneyQuests", J, "UIPanelScrollFrameTemplate")
	J.qScroll:SetPoint("TOPLEFT", 240, -56)
	J.qScroll:SetPoint("BOTTOMRIGHT", -370, 10)
	J.qContent = CreateFrame("Frame", nil, J.qScroll)
	J.qContent:SetSize(J.qScroll:GetWidth() > 0 and J.qScroll:GetWidth() or 290, 10)
	J.qScroll:SetScrollChild(J.qContent)
	S:SkinScrollBar(J.qScroll.ScrollBar or _G[J.qScroll:GetName() .. "ScrollBar"])

	-- right: detail pane for the selected quest
	J.dFrame = CreateFrame("Frame", nil, J, S.BackdropTemplate)
	J.dFrame:SetPoint("TOPRIGHT", -8, -56)
	J.dFrame:SetPoint("BOTTOMRIGHT", -8, 10)
	J.dFrame:SetWidth(330)
	S:CreateBackdrop(J.dFrame, "Default")
	J.dFrame:Hide()

	J.dScroll = CreateFrame("ScrollFrame", "SentinelUIQuestJourneyDetail", J.dFrame, "UIPanelScrollFrameTemplate")
	J.dScroll:SetPoint("TOPLEFT", 6, -6)
	J.dScroll:SetPoint("BOTTOMRIGHT", -24, 34)
	J.dContent = CreateFrame("Frame", nil, J.dScroll)
	J.dContent:SetSize(296, 10)
	J.dScroll:SetScrollChild(J.dContent)
	S:SkinScrollBar(J.dScroll.ScrollBar or _G[J.dScroll:GetName() .. "ScrollBar"])

	J.dText = S:FontString(J.dContent, 11)
	J.dText:SetPoint("TOPLEFT", 4, -4)
	J.dText:SetWidth(288)
	J.dText:SetJustifyH("LEFT")
	J.dText:SetWordWrap(true)
	J.dText:SetSpacing(2)

	local function detailBtn(label)
		local b = CreateFrame("Button", nil, J.dFrame, "UIPanelButtonTemplate")
		b:SetSize(100, 20)
		S:SkinButton(b)
		b:SetText(label)
		return b
	end
	J.dWay = detailBtn(L["Waypoint"] or "Waypoint")
	J.dWay:SetPoint("BOTTOMLEFT", 8, 8)
	J.dWay:SetScript("OnClick", function(b)
		if b.qid then WaypointToStarter(b.qid) end
	end)
	J.dTrack = detailBtn(L["Track"] or "Track")
	J.dTrack:SetPoint("LEFT", J.dWay, "RIGHT", 6, 0)
	J.dTrack:SetScript("OnClick", function(b)
		if b.qid then QS:FocusQuest(b.qid) end
	end)

	J.zRows, J.qRows = {}, {}
	J:SetScript("OnShow", function()
		S:SafeCall("QuestScope:Journey", FillZones)
	end)
	tinsert(UISpecialFrames, J:GetName())
end

function QS:ToggleJourney()
	CreateJourney()
	if J:IsShown() then J:Hide() else J:Show() end
end
