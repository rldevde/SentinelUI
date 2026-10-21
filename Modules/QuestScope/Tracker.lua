-- QuestScope tracker: SentinelUI's own side-screen quest tracker. Replaces the
-- Blizzard watch frame with a styled, movable, scrollable list of the quest
-- log: zone groups (collapsible), live objective progress, quest item buttons,
-- a focus quest (auto-waypoint) and click actions.
local _, ns = ...
local S = ns.S
local L = S.L
local QS = S:GetModule("QuestScope")

local _G = _G
local ipairs, wipe, sort = ipairs, wipe, sort
local format = string.format
local CreateFrame, GameTooltip = CreateFrame, GameTooltip
local InCombatLockdown = InCombatLockdown

-- ---------------------------------------------------------------------------
-- client compat helpers
-- ---------------------------------------------------------------------------
local function Untrack(index, qid)
	if C_QuestLog and C_QuestLog.RemoveQuestWatch and qid then
		local ok = pcall(C_QuestLog.RemoveQuestWatch, qid)
		if ok then return end
	end
	if RemoveQuestWatch then pcall(RemoveQuestWatch, index) end
end

local function OpenQuest(index, qid)
	-- resolve the CURRENT log index: saved indices go stale whenever the log
	-- changes (accept/abandon/header collapse) and would open the wrong quest
	if qid and C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and info.questID == qid then index = i break end
		end
	elseif qid and GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, GetNumQuestLogEntries() do
			local _, _, _, _, _, _, _, iq = GetQuestLogTitle(i)
			if iq == qid then index = i break end
		end
	end
	if qid and C_QuestLog and C_QuestLog.SetSelectedQuest then
		pcall(C_QuestLog.SetSelectedQuest, qid)
	end
	if index and QuestLog_SetSelection then pcall(QuestLog_SetSelection, index) end
	if QuestLogFrame then
		if not QuestLogFrame:IsShown() then ShowUIPanel(QuestLogFrame) end
	elseif ToggleQuestLog then
		pcall(ToggleQuestLog)
	end
end

local function ObjectiveState(qid, index)
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, r = pcall(C_QuestLog.GetQuestObjectives, qid)
		if ok and type(r) == "table" and #r > 0 then return r end
	end
	-- classic fallback: leaderboard lines keyed by the current log index
	if index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
		local ok, n = pcall(GetNumQuestLeaderBoards, index)
		if ok and n and n > 0 then
			local out = {}
			for i = 1, n do
				local text, _, done = GetQuestLogLeaderBoard(i, index)
				if text then
					local have, need = text:match("(%d+)%s*/%s*(%d+)")
					out[#out + 1] = { text = text, finished = done and true or false,
						numFulfilled = tonumber(have) or 0, numNeeded = tonumber(need) or 0 }
				end
			end
			return out
		end
	end
	return nil
end

local function QuestComplete(qid, index)
	if C_QuestLog and C_QuestLog.IsComplete then
		local ok, r = pcall(C_QuestLog.IsComplete, qid)
		if ok then return r and true or false end
	end
	if IsQuestComplete and index then
		local ok, r = pcall(IsQuestComplete, index)
		if ok and r ~= nil then return r and true or false end
	end
	-- fallback: treat "every objective finished" as complete
	local objs = ObjectiveState(qid, index)
	if objs and #objs > 0 then
		for _, o in ipairs(objs) do
			if not o.finished then return false end
		end
		return true
	end
	return false
end

-- quest item attached to a log entry (classic API; nil on clients without it)
local function QuestItem(index)
	if not GetQuestLogSpecialItemInfo then return end
	local ok, link, icon, charges, show = pcall(GetQuestLogSpecialItemInfo, index)
	if ok and link and show then return link, icon, charges end
end

local function AccentHex()
	local c = S.accent or { r = 0.92, g = 0.68, b = 0.2 }
	return format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function DiffColor(level)
	local c = GetQuestDifficultyColor and GetQuestDifficultyColor(level or 1)
	if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end
	-- older clients returned r,g,b directly; worst case compute from level diff
	local diff = (level or UnitLevel("player")) - UnitLevel("player")
	if diff >= 5 then return 1, 0.2, 0.2
	elseif diff >= 3 then return 1, 0.5, 0.25
	elseif diff >= -2 then return 1, 0.82, 0
	elseif diff >= -7 then return 0.25, 1, 0.25 end
	return 0.5, 0.5, 0.5
end

-- nearest pin distance (yards) for a quest, or nil when nothing is mapped
function QS:QuestDist(qid)
	local MapToWorld = self._MapToWorld
	if not (MapToWorld and UnitPosition) then return end
	local pN, pW, _, inst = UnitPosition("player")
	if not pN then return end
	local best
	for _, list in ipairs({ self.obj, self.avail }) do
		for _, p in ipairs(list or {}) do
			if p.qid == qid then
				local wN, wW, wI = MapToWorld(p.mapID, p.x, p.y)
				if wN and wI == inst then
					local d = math.sqrt((wN - pN) ^ 2 + (wW - pW) ^ 2)
					if not best or d < best then best = d end
				end
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------------
-- pooled rows (quest title buttons, zone collapse buttons, plain text lines)
-- ---------------------------------------------------------------------------
local HEADER_H, TITLE_H, OBJ_H, ZONE_H = 22, 16, 14, 16

function QS:TrackRow(i)
	local row = self.tRows and self.tRows[i]
	if row then return row end
	self.tRows = self.tRows or {}
	local f = self.tContent
	row = CreateFrame("Button", nil, f)
	row:SetHeight(TITLE_H)
	-- hover highlight
	row.hl = row:CreateTexture(nil, "BACKGROUND")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.07)
	row.hl:Hide()
	row.fs = S:FontString(row, self.db.trackerFontSize or 12)
	row.fs:SetPoint("LEFT", 4, 0)
	row.fs:SetPoint("RIGHT", -20, 0)
	row.fs:SetJustifyH("LEFT")
	row.fs:SetWordWrap(false)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(r, btn)
		local d = r.data
		if not d then return end
		if btn == "LeftButton" then
			if IsShiftKeyDown() then
				QS.private = QS.private or {}
				QS.private.untracked = QS.private.untracked or {}
				QS.private.untracked[d.qid] = true
				Untrack(d.index, d.qid)
				if QS.focusQid == d.qid then QS.focusQid = nil end
				QS:UpdateTracker()
			else
				OpenQuest(d.index, d.qid)
				QS:FocusQuest(d.qid, d.title, true)
			end
		elseif btn == "RightButton" then
			QS:TrackMenu(r)
		end
	end)
	row:SetScript("OnEnter", function(r)
		r.hl:Show()
		local d = r.data
		if not d then return end
		GameTooltip:SetOwner(r, "ANCHOR_LEFT")
		GameTooltip:AddLine(d.title, 1, 1, 1)
		GameTooltip:AddLine(L["Click: open quest + waypoint  |  Shift-click: untrack  |  Right-click: menu"], 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(r) r.hl:Hide() GameTooltip:Hide() end)
	-- quest item button (secure use-item)
	row.item = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
	row.item:SetSize(TITLE_H - 2, TITLE_H - 2)
	row.item:SetPoint("RIGHT", -2, 0)
	-- protected attribute: set now if possible, otherwise on the next OOC pass
	if not InCombatLockdown() then row.item:SetAttribute("type", "item") end
	row.item.tex = row.item:CreateTexture(nil, "ARTWORK")
	row.item.tex:SetAllPoints()
	row.item.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.item:SetScript("OnEnter", function(b)
		if b.link then
			GameTooltip:SetOwner(b, "ANCHOR_LEFT")
			GameTooltip:SetHyperlink(b.link)
			GameTooltip:Show()
		end
	end)
	row.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.item:Hide()
	self.tRows[i] = row
	return row
end

function QS:TrackZone(i)
	local btn = self.tZones and self.tZones[i]
	if btn then return btn end
	self.tZones = self.tZones or {}
	btn = CreateFrame("Button", nil, self.tContent)
	btn:SetHeight(ZONE_H)
	btn.fs = S:FontString(btn, self.db.trackerFontSize or 12)
	btn.fs:SetPoint("LEFT", 4, 0)
	btn.fs:SetJustifyH("LEFT")
	-- accent divider under the zone header
	btn.line = btn:CreateTexture(nil, "ARTWORK")
	btn.line:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.45)
	btn.line:SetHeight(1)
	btn.line:SetPoint("BOTTOMLEFT", 4, 0)
	btn.line:SetPoint("BOTTOMRIGHT", -4, 0)
	btn.hl = btn:CreateTexture(nil, "BACKGROUND")
	btn.hl:SetAllPoints()
	btn.hl:SetColorTexture(1, 1, 1, 0.05)
	btn.hl:Hide()
	btn:SetScript("OnEnter", function(x) x.hl:Show() end)
	btn:SetScript("OnLeave", function(x) x.hl:Hide() end)
	btn:SetScript("OnClick", function(b)
		local z = b.zone
		if not z then return end
		QS.private = QS.private or {}
		QS.private.collapsed = QS.private.collapsed or {}
		QS.private.collapsed[z] = not QS.private.collapsed[z] or nil
		QS:UpdateTracker()
	end)
	self.tZones[i] = btn
	return btn
end

function QS:TrackLine(i, small)
	local fs = self.tLines and self.tLines[i]
	if fs then return fs end
	self.tLines = self.tLines or {}
	fs = S:FontString(self.tContent, (self.db.trackerFontSize or 12) - (small and 1 or 0))
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	self.tLines[i] = fs
	return fs
end

-- right-click context menu (Questie-style): focus/waypoint, open log, untrack
function QS:TrackMenu(row)
	local d = row and row.data
	if not d then return end
	local menu = self.tMenu
	if not menu then
		menu = CreateFrame("Frame", "SentinelUIQuestTrackMenu", UIParent, S.BackdropTemplate)
		menu:SetFrameStrata("TOOLTIP")
		menu:SetClampedToScreen(true)
		menu:EnableMouse(true)
		S:CreateBackdrop(menu, "Default")
		menu.btns = {}
		menu:SetScript("OnLeave", function()
			C_Timer.After(0.35, function()
				if menu:IsShown() and not menu:IsMouseOver() then menu:Hide() end
			end)
		end)
		menu.title = S:FontString(menu, 11)
		menu.title:SetPoint("TOPLEFT", 8, -6)
		menu.title:SetJustifyH("LEFT")
		menu.line = menu:CreateTexture(nil, "ARTWORK")
		menu.line:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.5)
		menu.line:SetHeight(1)
		menu.line:SetPoint("TOPLEFT", menu.title, "BOTTOMLEFT", 0, -3)
		menu.line:SetPoint("RIGHT", menu, "RIGHT", -8, 0)
		self.tMenu = menu
	end
	menu.title:SetText(d.title)
	menu.title:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
	local items = {
		{ L["Focus + waypoint"], function() QS:FocusQuest(d.qid, d.title, true) end },
		{ L["Open quest log"], function() OpenQuest(d.index, d.qid) end },
		{ L["Untrack"], function()
			QS.private = QS.private or {}
			QS.private.untracked = QS.private.untracked or {}
			QS.private.untracked[d.qid] = true
			Untrack(d.index, d.qid)
			if QS.focusQid == d.qid then QS.focusQid = nil end
			QS:UpdateTracker()
		end },
	}
	local w = 0
	for i, it in ipairs(items) do
		local b = menu.btns[i]
		if not b then
			b = CreateFrame("Button", nil, menu)
			b:SetHeight(18)
			b.fs = S:FontString(b, self.db.trackerFontSize or 12)
			b.fs:SetPoint("LEFT", 8, 0)
			b.fs:SetJustifyH("LEFT")
			b.hl = b:CreateTexture(nil, "BACKGROUND")
			b.hl:SetAllPoints()
			b.hl:SetColorTexture(1, 1, 1, 0.08)
			b.hl:Hide()
			b:SetScript("OnEnter", function(x) x.hl:Show() x.fs:SetTextColor(1, 1, 1) end)
			b:SetScript("OnLeave", function(x) x.hl:Hide() x.fs:SetTextColor(0.95, 0.75, 0.3) end)
			menu.btns[i] = b
		end
		b.fs:SetText(it[1])
		b.fs:SetTextColor(0.95, 0.75, 0.3)
		b:SetScript("OnClick", function() menu:Hide() it[2]() end)
		b:SetPoint("TOPLEFT", 0, -(i - 1) * 18 - 26)
		w = math.max(w, (b.fs:GetStringWidth() or 60) + 16)
		b:Show()
	end
	for i = #items + 1, #menu.btns do menu.btns[i]:Hide() end
	w = math.max(w, (menu.title:GetStringWidth() or 0) + 16, 80)
	for _, b in ipairs(menu.btns) do b:SetWidth(w) end
	menu:SetSize(w, #items * 18 + 30)
	local x, y = GetCursorPosition()
	local sc = UIParent:GetEffectiveScale()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc + 4, y / sc - 4)
	menu:Show()
end

-- hide the blizzard objective list while ours is active
function QS:ApplyBlizzardTracker()
	local wf = _G.ObjectiveTrackerFrame or _G.WatchFrame or _G.QuestWatchFrame
	if not wf then return end
	if not self._wfHooked then
		self._wfHooked = true
		wf:HookScript("OnShow", function(f)
			if QS.db and QS.db.trackerEnable and QS.db.trackerHideBlizzard then f:Hide() end
		end)
	end
	local function SetHidden()
		if QS.db and QS.db.trackerEnable and QS.db.trackerHideBlizzard then
			wf:Hide()
		else
			wf:Show()
		end
	end
	if InCombatLockdown() then S:RunOutOfCombat(SetHidden) else SetHidden() end
end

-- ---------------------------------------------------------------------------
-- content
-- ---------------------------------------------------------------------------

-- combat-safe refresh: FontString:SetText / texture ops are allowed even on
-- the anchor-restricted tracker, so progress still updates live while
-- fighting. Layout (rows/zones/sizes) waits for PLAYER_REGEN_ENABLED.
function QS:UpdateTrackerTexts()
	if self._headLine then
		local n = 0
		for _ in pairs(self.logQuests or {}) do n = n + 1 end
		self._headLine:SetText(format("|cff%s%s: %d|r", AccentHex(), L["Active Quests"] or "Active Quests", n))
	end
	for _, row in ipairs(self.tRows or {}) do
		local q = row.data
		if row:IsShown() and q then
			local done = QuestComplete(q.qid, q.index)
			local focused = self.focusQid == q.qid
			local r, g, b = DiffColor(q.level)
			local dist = (self.db.trackerDistance and self:QuestDist(q.qid))
			row.fs:SetText(format("%s|cff%02x%02x%02x[%d]|r %s%s%s",
				focused and "|cff" .. (AccentHex()) .. "»|r " or "",
				r * 255, g * 255, b * 255,
				q.level or 0, q.title or ("Quest " .. q.qid),
				done and " |cff33ff33?|r" or "",
				dist and format(" |cff888888(%d m)|r", dist) or ""))
			row.fs:SetTextColor(done and 0.45 or 1, 1, done and 0.45 or 1)
			-- reuse the row's objective lines in place; extras blank out, new
			-- objectives that need more lines appear after combat
			local li = 0
			local objs = not done and ObjectiveState(q.qid, q.index)
			local texts = {}
			if done then
				texts[1] = format("|cff33ff33» %s|r", L["Ready for turn-in"] or "Ready for turn-in")
			elseif objs then
				for _, o in ipairs(objs) do
					if o.text and o.text ~= "" then
						texts[#texts + 1] = format(o.finished and "|cff33cc33- %s|r" or "|cff9e9e9e- %s|r", o.text)
					end
				end
			end
			for _, ol in ipairs(row.objLines or {}) do
				li = li + 1
				ol:SetText(texts[li] or "")
			end
		end
	end
end

function QS:SetTrackerCombatState()
	local inCombat = InCombatLockdown()
	local scroll = self.tScroll
	if not scroll then return end
	scroll:EnableMouseWheel(not inCombat)
	local sb = scroll.ScrollBar
	if sb then
		sb:EnableMouse(not inCombat)
		sb:EnableMouseWheel(not inCombat)
	end
end

function QS:UpdateTracker()
	local f = self.tracker
	if not f then return end
	if InCombatLockdown() then
		-- every row contains a secure item button, which anchor-restricts the
		-- whole tracker hierarchy: any Show/Hide/SetPoint/SetSize on it or its
		-- children is blocked in combat. Texts are still allowed, so we only
		-- refresh those and rebuild the layout on PLAYER_REGEN_ENABLED.
		self:UpdateTrackerTexts()
		return
	end
	if not (self.db and self.db.trackerEnable) then
		f:Hide()
		self:ApplyBlizzardTracker()
		return
	end
	self:ApplyBlizzardTracker()

	-- Questie-style: the tracker lists every quest in the log; shift-clicking a
	-- title hides that quest in our own untracked set (per character)
	self.private = self.private or {}
	self.private.untracked = self.private.untracked or {}
	self.private.collapsed = self.private.collapsed or {}
	local hidden, collapsed = self.private.untracked, self.private.collapsed

	local quests = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		local zone, zoneCollapsed
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info then
				if info.isHeader then
					zone = info.title
					zoneCollapsed = info.isCollapsed
				elseif not zoneCollapsed and info.questID and not hidden[info.questID] then
					quests[#quests + 1] = { index = i, qid = info.questID, zone = zone,
						title = info.title, level = info.level }
				end
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		-- classic quest log API
		local zone, zoneCollapsed
		for i = 1, GetNumQuestLogEntries() do
			local title, level, _, isHeader, isCollapsed, _, _, qid = GetQuestLogTitle(i)
			if isHeader then
				zone, zoneCollapsed = title, isCollapsed
			elseif not zoneCollapsed and qid and not hidden[qid] then
				quests[#quests + 1] = { index = i, qid = qid, zone = zone, title = title, level = level }
			end
		end
	end

	if #quests == 0 then f:Hide() return end
	f:Show()

	-- sort order
	local mode = self.db.trackerSort
	if mode == "level" then
		sort(quests, function(a, b)
			if (a.level or 0) == (b.level or 0) then return (a.title or "") < (b.title or "") end
			return (a.level or 0) < (b.level or 0)
		end)
	elseif mode == "proximity" then
		for _, q in ipairs(quests) do q._d = self:QuestDist(q.qid) end
		sort(quests, function(a, b)
			if a._d and b._d then return a._d < b._d end
			if a._d then return true end
			if b._d then return false end
			return (a.title or "") < (b.title or "")
		end)
	end

	local width = self.db.trackerWidth or 230
	local objIndent = 14
	local y = -4
	local rowN, lineN, zoneN = 0, 0, 0

	-- header
	local head = self:TrackLine(1)
	self._headLine = head
	lineN = 1
	head:SetPoint("TOPLEFT", 6, y)
	head:SetWidth(width - 8)
	head:SetText(format("|cff%s%s: %d|r", AccentHex(), L["Active Quests"] or "Active Quests", #quests))
	if not f._headLine then
		f._headLine = self.tContent:CreateTexture(nil, "ARTWORK")
		f._headLine:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.5)
		f._headLine:SetHeight(1)
		f._headLine:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
		f._headLine:SetPoint("RIGHT", head, "RIGHT", -2, 0)
	end
	y = y - HEADER_H

	local lastZone
	for _, q in ipairs(quests) do
		if q.zone and q.zone ~= lastZone then
			lastZone = q.zone
			zoneN = zoneN + 1
			local zb = self:TrackZone(zoneN)
			zb.zone = q.zone
			zb:SetPoint("TOPLEFT", 0, y)
			zb:SetWidth(width)
			-- zone header in accent color with collapse marker (Questie-like)
			zb.fs:SetText(format("|cff%s%s %s|r", AccentHex(),
				collapsed[q.zone] and "+" or "-", q.zone))
			zb:Show()
			y = y - (ZONE_H + 2)
		end
		if q.zone and collapsed[q.zone] then
			-- zone group is collapsed: skip its quests but keep scanning zones
		else
			rowN = rowN + 1
			local row = self:TrackRow(rowN)
			row.data = q
			row:SetPoint("TOPLEFT", 0, y)
			row:SetWidth(width)
			local done = QuestComplete(q.qid, q.index)
			local focused = self.focusQid == q.qid
			local r, g, b = DiffColor(q.level)
			local dist = (self.db.trackerDistance and self:QuestDist(q.qid))
			-- [lvl] in difficulty color, title white, ? when ready, gold » when focused
			row.fs:SetText(format("%s|cff%02x%02x%02x[%d]|r %s%s%s",
				focused and "|cff" .. (AccentHex()) .. "»|r " or "",
				r * 255, g * 255, b * 255,
				q.level or 0, q.title or ("Quest " .. q.qid),
				done and " |cff33ff33?|r" or "",
				dist and format(" |cff888888(%d m)|r", dist) or ""))
			row.fs:SetTextColor(done and 0.45 or 1, 1, done and 0.45 or 1)
			-- quest item (secure button: Show/Hide is forbidden in combat, so we
			-- toggle alpha instead and let the next out-of-combat refresh fix it)
			local itemLink, itemIcon
			if self.db.trackerItemButtons then itemLink, itemIcon = QuestItem(q.index) end
			if itemLink then
				row.item.link = itemLink
				row.item.tex:SetTexture(itemIcon)
				if not InCombatLockdown() then
					row.item:SetAttribute("type", "item")
					row.item:SetAttribute("item", itemLink)
				end
			end
			if InCombatLockdown() then
				row.item:SetAlpha(itemLink and 1 or 0)
			else
				row.item:SetAlpha(1)
				row.item:SetShown(itemLink ~= nil)
			end
			row:Show()
			y = y - TITLE_H
			row.objLines = wipe(row.objLines or {})

			-- objectives
			if done then
				lineN = lineN + 1
				local ol = self:TrackLine(lineN)
				row.objLines[#row.objLines + 1] = ol
				ol:SetPoint("TOPLEFT", objIndent + 4, y)
				ol:SetWidth(width - objIndent - 8)
				ol:SetText(format("|cff33ff33» %s|r", L["Ready for turn-in"] or "Ready for turn-in"))
				y = y - OBJ_H
			else
				local objs = ObjectiveState(q.qid, q.index)
				if objs then
					for _, o in ipairs(objs) do
						if o.text and o.text ~= "" then
							lineN = lineN + 1
							local ol = self:TrackLine(lineN)
							row.objLines[#row.objLines + 1] = ol
							ol:SetPoint("TOPLEFT", objIndent + 4, y)
							ol:SetWidth(width - objIndent - 8)
							if o.finished then
								ol:SetText(format("|cff33cc33- %s|r", o.text))
							else
								ol:SetText(format("|cff9e9e9e- %s|r", o.text))
							end
							y = y - OBJ_H
						end
					end
				end
			end
			y = y - 2
		end
	end

	-- hide unused pool entries
	for i = rowN + 1, #(self.tRows or {}) do self.tRows[i]:Hide() end
	for i = lineN + 1, #(self.tLines or {}) do self.tLines[i]:Hide() end
	for i = zoneN + 1, #(self.tZones or {}) do self.tZones[i]:Hide() end

	-- size + scroll clamp; resizing the scroll child OR the scroll frame fires
	-- OnScrollRangeChanged -> SetValue -> SetVerticalScroll, which moves the
	-- secure item buttons and is blocked in combat. Row positions don't depend
	-- on either size, so all resizing is deferred until PLAYER_REGEN_ENABLED.
	local contentH = -y + 6
	local maxH = self.db.trackerMaxHeight or 420
	if not InCombatLockdown() then
		self.tContent:SetSize(width, contentH)
		f:SetSize(width, math.min(contentH, maxH))
		local sb = self.tScroll and self.tScroll.ScrollBar
		if sb then
			if contentH > maxH then sb:Show() else sb:Hide() end
		end
	end
end

-- ---------------------------------------------------------------------------
function QS:CreateTracker()
	if self.tracker then return end
	local f = CreateFrame("Frame", "SentinelUIQuestTracker", UIParent)
	f:SetSize(self.db.trackerWidth or 230, 200)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
	f:SetClampedToScreen(true)
	f:SetFrameStrata("MEDIUM")

	-- scrollable content (scrollbar only appears when the list exceeds max height)
	local scroll = CreateFrame("ScrollFrame", "SentinelUIQuestTrackerScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -16, 0)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(self.db.trackerWidth or 230, 200)
	scroll:SetScrollChild(content)
	scroll.ScrollBar = _G[scroll:GetName() .. "ScrollBar"]
	if scroll.ScrollBar then
		scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, -16)
		S:SkinScrollBar(scroll.ScrollBar)
	end
	if self.db.trackerBackdrop ~= false then
		S:CreateBackdrop(f, "Transparent")
	end
	self.tScroll, self.tContent = scroll, content
	self.tracker = f

	S:CreateMover(f, "questtracker", L["Quest Tracker"] or "Quest Tracker",
		{ "RIGHT", "UIParent", "RIGHT", -40, 0 }, "questscope")

	self:RegisterEvent("QUEST_LOG_UPDATE", function() QS:UpdateTracker() end)
	self:RegisterEvent("QUEST_WATCH_UPDATE", function() QS:UpdateTracker() end)
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED", function(_, _, unit)
		if unit == "player" then QS:UpdateTracker() end
	end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() QS:UpdateTracker() end)
	-- scrolling moves the secure quest-item buttons, which is forbidden in
	-- combat: lock the wheel and scrollbar while fighting
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() QS:SetTrackerCombatState() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		QS:SetTrackerCombatState()
		QS:UpdateTracker()
	end)
	self:SetTrackerCombatState()
	self:UpdateTracker()
end
