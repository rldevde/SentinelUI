-- RaidReset: instance lockout + reset overview (own implementation, replaces
-- the standalone RLRaidDungeonReset addon). Shows saved raids/dungeons with
-- their reset timers, the full instance list of the current expansion with
-- availability, daily dungeon run counters and the TBC Shattrath daily quests.
-- Data lives in RLRaidDungeonResetDB so old saves keep working.
local _, ns = ...
local S = ns.S
local L = S.L
local RR = S:NewModule("RaidReset")

local InstanceData = ns.RDResetInstanceData
local QuestData = ns.RDResetQuestData

local _G = _G
local ipairs, pairs, sort, wipe = ipairs, pairs, sort, wipe
local tinsert = tinsert
local format, floor = format, math.floor
local time, date = time, date
local unpack = unpack
local CreateFrame = CreateFrame
local IsSecret = S.IsSecret

local ICON = S.media.iconReset
local ROW_H = 20
local MAX_ROWS = 15
local WIN_W, WIN_H = 560, 440

-- persistent store (shared with the old standalone addon on purpose)
local function Data()
	if type(RLRaidDungeonResetDB) ~= "table" then RLRaidDungeonResetDB = {} end
	local d = RLRaidDungeonResetDB
	d.minimap = d.minimap or {}
	if d.minimap.show == nil then d.minimap.show = true end
	d.dailyRuns = d.dailyRuns or {}
	d.dailyRuns.lastResetTime = d.dailyRuns.lastResetTime or 0
	d.dailyRuns.runs = d.dailyRuns.runs or {}
	d.dailyQuests = d.dailyQuests or {}
	d.dailyQuests.lastResetTime = d.dailyQuests.lastResetTime or 0
	d.dailyQuests.completed = d.dailyQuests.completed or {}
	if d.dailyQuests.showQuests == nil then d.dailyQuests.showQuests = true end
	return d
end

-- reset timestamps -----------------------------------------------------------
local function NextDailyReset()
	if GetQuestResetTime then
		local ok, secs = pcall(GetQuestResetTime)
		if ok and secs and not IsSecret(secs) and secs > 0 then
			return time() + secs
		end
	end
	-- fallback: 03:00 local time (server daily reset hour on most realms)
	local now = time()
	local secs = tonumber(date("%H", now)) * 3600 + tonumber(date("%M", now)) * 60 + tonumber(date("%S", now))
	local untilReset = 3 * 3600 - secs
	if untilReset <= 0 then untilReset = untilReset + 86400 end
	return now + untilReset
end

local function CheckDailyReset()
	local d = Data()
	local lastReset = NextDailyReset() - 86400
	if d.dailyRuns.lastResetTime < lastReset then
		d.dailyRuns.lastResetTime = lastReset
		wipe(d.dailyRuns.runs)
	end
	if d.dailyQuests.lastResetTime < lastReset then
		d.dailyQuests.lastResetTime = lastReset
		wipe(d.dailyQuests.completed)
	end
end

local function FmtRemaining(seconds)
	if not seconds or seconds <= 0 then return "|cff44dd66" .. L["Available"] .. "|r" end
	local days = floor(seconds / 86400)
	local hours = floor((seconds % 86400) / 3600)
	local mins = floor((seconds % 3600) / 60)
	if days > 0 then return format("%dd %dh", days, hours) end
	if hours > 0 then return format("%dh %dm", hours, mins) end
	return format("%dm", mins)
end

local function ResetCountdown()
	local r = NextDailyReset() - time()
	if r <= 0 then r = 0 end
	return FmtRemaining(r):gsub("|cff%x%x%x%x%x%x", "|cffebad33")
end

-- deDE client: GetSavedInstanceInfo returns localized names while our data
-- list is english — map german -> english so locked entries dedupe correctly.
-- Covers Classic/TBC/WotLK (everything reachable on anniversary clients).
local NAME_DE = {
	-- Classic raids
	["Geschmolzener Kern"] = "Molten Core",
	["Pechschwingenhort"] = "Blackwing Lair",
	["Tempel von Ahn'Qiraj"] = "Ahn'Qiraj Temple",
	["Ruinen von Ahn'Qiraj"] = "Ruins of Ahn'Qiraj",
	["Zul'Gurub"] = "Zul'Gurub",
	["Onyxias Hort"] = "Onyxia's Lair",
	["Naxxramas"] = "Naxxramas",
	-- Classic dungeons
	["Die Todesminen"] = "Deadmines",
	["Die Höhlen des Wehklagens"] = "Wailing Caverns",
	["Burg Schattenfang"] = "Shadowfang Keep",
	["Die Tiefschwarze Grotte"] = "Blackfathom Deeps",
	["Der Kral von Razorfen"] = "Razorfen Kraul",
	["Die Hügel von Razorfen"] = "Razorfen Downs",
	["Uldaman"] = "Uldaman",
	["Maraudon"] = "Maraudon",
	["Zul'Farrak"] = "Zul'Farrak",
	["Der Tempel von Atal'Hakkar"] = "Temple of Atal'Hakkar",
	["Schwarzfelstiefen"] = "Blackrock Depths",
	["Schwarzfelsspitze"] = "Blackrock Spire",
	["Düsterbruch"] = "Dire Maul",
	["Stratholme"] = "Stratholme",
	["Scholomance"] = "Scholomance",
	-- TBC raids
	["Karazhan"] = "Karazhan",
	["Gruuls Unterschlupf"] = "Gruul's Lair",
	["Magtheridons Kammer"] = "Magtheridon's Lair",
	["Höhle des Schlangenschreins"] = "Serpentshrine Cavern",
	["Das Auge"] = "The Eye",
	["Hyjalgipfel"] = "Hyjal Summit",
	["Der Schwarze Tempel"] = "Black Temple",
	["Sonnenbrunnenplateau"] = "Sunwell Plateau",
	["Zul'Aman"] = "Zul'Aman",
	-- TBC dungeons
	["Höllenfeuerbollwerk"] = "Hellfire Ramparts",
	["Der Blutkessel"] = "The Blood Furnace",
	["Die Zerschmetterten Hallen"] = "The Shattered Halls",
	["Managruft"] = "Mana-Tombs",
	["Auchenaikrypta"] = "Auchenai Crypts",
	["Sethekkhallen"] = "Sethekk Halls",
	["Schattenlabyrinth"] = "Shadow Labyrinth",
	["Die Sklavenunterkünfte"] = "Slave Pens",
	["Der Tiefensumpf"] = "The Underbog",
	["Die Dampfkammer"] = "The Steamvault",
	["Die Mechanar"] = "The Mechanar",
	["Die Botanika"] = "The Botanica",
	["Die Arkatraz"] = "The Arcatraz",
	["Terrasse der Magister"] = "Magisters' Terrace",
	-- WotLK raids
	["Das Obsidiansanktum"] = "Obsidian Sanctum",
	["Das Auge der Ewigkeit"] = "Eye of Eternity",
	["Ulduar"] = "Ulduar",
	["Prüfung des Kreuzfahrers"] = "Trial of the Crusader",
	["Die Eiskronenzitadelle"] = "Icecrown Citadel",
	["Archavons Kammer"] = "Vault of Archavon",
	["Das Rubinsanktum"] = "Ruby Sanctum",
	-- WotLK dungeons
	["Burg Utgarde"] = "Utgarde Keep",
	["Der Nexus"] = "The Nexus",
	["Azjol-Nerub"] = "Azjol-Nerub",
	["Ahn'kahet: Das Alte Königreich"] = "Ahn'kahet: The Old Kingdom",
	["Burg Drak'Tharon"] = "Drak'Tharon Keep",
	["Die Violette Festung"] = "Violet Hold",
	["Gundrak"] = "Gundrak",
	["Hallen des Steins"] = "Halls of Stone",
	["Hallen der Blitze"] = "Halls of Lightning",
	["Das Ausmerzen von Stratholme"] = "The Culling of Stratholme",
	["Prüfung des Champions"] = "Trial of the Champion",
	["Die Schmiede der Seelen"] = "Forge of Souls",
	["Die Grube von Saron"] = "Pit of Saron",
	["Hallen der Reflexion"] = "Halls of Reflection",
}

-- saved-instance API (guarded: signatures differ between clients) ------------
local function SavedInstances()
	local out = {}
	if not GetNumSavedInstances or not GetSavedInstanceInfo then return out end
	local n = GetNumSavedInstances() or 0
	for i = 1, n do
		local name, _, reset, _, locked, extended, _, isRaid, maxPlayers, diffName = GetSavedInstanceInfo(i)
		if name and locked then
			tinsert(out, {
				name = name, reset = reset or 0, locked = true,
				extended = extended, isRaid = isRaid,
				maxPlayers = maxPlayers, difficulty = diffName,
			})
		end
	end
	return out
end

-- all expansions, current one first, then release order
local EXP_ORDER = { "CLASSIC", "TBC", "WOTLK", "CATA", "MOP", "WOD", "LEGION", "BFA", "SHADOWLANDS", "DRAGONFLIGHT", "WAR_WITHIN" }
local EXP_LABEL = {
	CLASSIC = "Classic", TBC = "The Burning Crusade", WOTLK = "Wrath of the Lich King",
	CATA = "Cataclysm", MOP = "Mists of Pandaria", WOD = "Warlords of Draenor",
	LEGION = "Legion", BFA = "Battle for Azeroth", SHADOWLANDS = "Shadowlands",
	DRAGONFLIGHT = "Dragonflight", WAR_WITHIN = "The War Within",
}

-- rows = header entries + instance entries covering EVERY expansion.
-- Saved lockouts (live API data, localized names) always sit on top.
local function InstanceRows(wantRaid)
	local saved, savedNames = {}, {}
	for _, s in ipairs(SavedInstances()) do
		if (s.isRaid and true or false) == wantRaid then
			tinsert(saved, s)
			savedNames[s.name] = true
			local en = NAME_DE[s.name]
			if en then savedNames[en] = true end
		end
	end
	sort(saved, function(a, b) return (a.reset or 0) < (b.reset or 0) end) -- soonest reset first
	local rows = {}
	if #saved > 0 then
		tinsert(rows, { header = L["Locked"] })
		for _, s in ipairs(saved) do tinsert(rows, s) end
	end
	local curKey = InstanceData and InstanceData.GetCurrentVersionData and select(2, InstanceData.GetCurrentVersionData())
	if curKey then
		local data = InstanceData[curKey]
		local list = data and (wantRaid and data.raids or data.dungeons)
		if list and #list > 0 then
			tinsert(rows, { header = L[EXP_LABEL[curKey]] })
			for _, inst in ipairs(list) do
				if not savedNames[inst.name] then
					tinsert(rows, { name = inst.name, maxPlayers = inst.maxPlayers, reset = 0, locked = false, isRaid = wantRaid })
				end
			end
		end
	end
	for _, key in ipairs(EXP_ORDER) do
		if key ~= curKey then
			local data = InstanceData and InstanceData[key]
			local list = data and (wantRaid and data.raids or data.dungeons)
			if list and #list > 0 then
				tinsert(rows, { header = L[EXP_LABEL[key]] })
				for _, inst in ipairs(list) do
					if not savedNames[inst.name] then
						tinsert(rows, { name = inst.name, maxPlayers = inst.maxPlayers, reset = 0, locked = false, isRaid = wantRaid })
					end
				end
			end
		end
	end
	return rows
end

-- daily quest status ---------------------------------------------------------
local function QuestInLog(name)
	if not name or not GetNumQuestLogEntries or not GetQuestLogTitle then return false end
	for i = 1, GetNumQuestLogEntries() or 0 do
		local title, _, _, isHeader = GetQuestLogTitle(i)
		if not isHeader and title == name then return true end
	end
	return false
end

local function QuestStatus(q)
	local d = Data()
	if q.id and d.dailyQuests.completed[q.id] then return "completed" end
	if q.id and IsQuestFlaggedCompleted then
		local ok, done = pcall(IsQuestFlaggedCompleted, q.id)
		if ok and done then
			d.dailyQuests.completed[q.id] = true
			return "completed"
		end
	end
	if QuestInLog(q.name) then return "active" end
	return "none"
end

-- rows ----------------------------------------------------------------------
local function MakeRow(list, i)
	local r = list.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, list)
	r:SetHeight(ROW_H)
	S:CreateBackdrop(r, "Default")
	r.name = S:FontString(r, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
	r.name:SetPoint("LEFT", 8, 0)
	r.name:SetWidth(280)
	r.name:SetWordWrap(false)
	r.mid = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	r.mid:SetPoint("LEFT", 296, 0)
	r.mid:SetWidth(60)
	r.status = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	r.status:SetPoint("LEFT", 362, 0)
	r.status:SetWidth(70)
	r.right = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	r.right:SetPoint("RIGHT", -8, 0)
	r.action = CreateFrame("Button", nil, r)
	r.action:SetSize(16, 16)
	r.action:SetPoint("RIGHT", -64, 0)
	S:CreateBackdrop(r.action, "Default")
	r.action.fs = S:FontString(r.action, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
	r.action.fs:SetPoint("CENTER")
	r:SetScript("OnEnter", function(s)
		local bd = s.suiBackdrop or s
		if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b, 1) end
		if s.tip and GameTooltip then
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			GameTooltip:AddLine(s.tip, 1, 1, 1, true)
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
	r.action:Hide()
	r.action:SetScript("OnClick", nil)
	r.tip = nil
	r.name:SetText("")
	r.mid:SetText("")
	r.status:SetText("")
	r.right:SetText("")
	r:Hide()
end

-- tab content ----------------------------------------------------------------
function RR:RenderInstances(wantRaid)
	local f = self.frame
	if not f then return end
	local rows = InstanceRows(wantRaid)
	f.colMid:SetText(L["Players"])
	f.colStatus:SetText(wantRaid and L["Difficulty"] or L["Status"])
	f.colRight:SetText(L["Reset in"])
	local list = f.list
	local nVis = #rows
	if self.scroll > nVis - MAX_ROWS then self.scroll = math.max(0, nVis - MAX_ROWS) end
	for i = 1, MAX_ROWS do
		local inst = rows[i + self.scroll]
		local r = MakeRow(list, i)
		if inst then
			FillRow(r, i)
			if inst.header then
				r.name:SetText(inst.header)
				r.name:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
				r.mid:SetText("")
				r.status:SetText("")
				r.right:SetText("")
				r.action:Hide()
				r.tip = nil
			else
				r.name:SetText(inst.name)
				r.name:SetTextColor(inst.locked and 1 or 0.7, inst.locked and 0.85 or 0.7, inst.locked and 0.3 or 0.75)
				r.mid:SetText(inst.maxPlayers and tostring(inst.maxPlayers) or "-")
				r.mid:SetTextColor(0.6, 0.6, 0.65)
				if inst.locked then
					r.status:SetText(inst.extended and ("|cff55aaff" .. L["Extended"] .. "|r") or ("|cffff5555" .. L["Locked"] .. "|r"))
					r.right:SetText(FmtRemaining(inst.reset))
					r.tip = inst.difficulty and (L["Difficulty"] .. ": " .. inst.difficulty) or nil
				else
					r.status:SetText("|cff44dd66" .. L["Available"] .. "|r")
					r.right:SetText("-")
					r.tip = nil
				end
			end
		else
			ClearRow(r)
		end
	end
	local total = 0
	for _, inst in ipairs(rows) do if not inst.header then total = total + 1 end end
	f.summary:SetText(format(L["%d instances  —  %d locked"], total, self:LockedCount(wantRaid)))
end

function RR:LockedCount(wantRaid)
	local n = 0
	for _, s in ipairs(SavedInstances()) do
		if (s.isRaid and true or false) == wantRaid then n = n + 1 end
	end
	return n
end

-- every dungeon across all expansions (for run tracking + the daily tab)
local function AllDungeons()
	local out = {}
	for _, key in ipairs(EXP_ORDER) do
		local data = InstanceData and InstanceData[key]
		for _, dg in ipairs((data and data.dungeons) or {}) do
			out[#out + 1] = dg.name
		end
	end
	return out
end

function RR:RenderDaily()
	local f = self.frame
	if not f then return end
	CheckDailyReset()
	local d = Data()
	f.colMid:SetText("")
	f.colStatus:SetText(L["Status"])
	f.colRight:SetText(L["Runs today"])

	-- entries: dungeon run counters (all expansions, counted ones first),
	-- then the two daily-quest lines
	local entries = {}
	local names = AllDungeons()
	sort(names, function(a, b)
		local ca, cb = d.dailyRuns.runs[a] or 0, d.dailyRuns.runs[b] or 0
		if ca ~= cb then return ca > cb end
		return a < b
	end)
	for _, name in ipairs(names) do
		tinsert(entries, { kind = "run", name = name })
	end
	local quests = QuestData and QuestData.GetCurrentVersionQuests and QuestData.GetCurrentVersionQuests()
	if quests and d.dailyQuests.showQuests then
		for _, cat in ipairs({ "normal", "heroic" }) do
			local found, status
			for _, q in ipairs(quests[cat] or {}) do
				local st = QuestStatus(q)
				if st ~= "none" then found, status = q, st break end
			end
			if not found then found = quests[cat][1] status = "none" end
			tinsert(entries, {
				kind = "quest", cat = cat, quest = found, status = status,
				name = (cat == "heroic" and L["Heroic daily"] or L["Normal daily"]) .. ": " .. (found and found.dungeon or "?"),
			})
		end
	end

	local list = f.list
	local nVis = #entries
	if self.scroll > nVis - MAX_ROWS then self.scroll = math.max(0, nVis - MAX_ROWS) end
	for i = 1, MAX_ROWS do
		local e = entries[i + self.scroll]
		local r = MakeRow(list, i)
		if e then
			FillRow(r, i)
			r.name:SetText(e.name)
			if e.kind == "run" then
				local count = d.dailyRuns.runs[e.name] or 0
				r.name:SetTextColor(0.85, 0.85, 0.9)
				r.status:SetText("")
				r.right:SetText(count > 0 and ("|cffebad33" .. count .. "|r") or "|cff6666660|r")
				r.tip = nil
			else
				local st = e.status
				if st == "completed" then
					r.name:SetTextColor(0.45, 0.9, 0.45)
					r.status:SetText("|cff44dd66" .. L["Completed"] .. "|r")
				elseif st == "active" then
					r.name:SetTextColor(1, 0.85, 0.3)
					r.status:SetText("|cffebad33" .. L["In questlog"] .. "|r")
				else
					r.name:SetTextColor(0.55, 0.55, 0.6)
					r.status:SetText("|cff888888" .. L["Not taken"] .. "|r")
				end
				r.right:SetText("")
				if e.quest and e.quest.id then
					r.action.fs:SetText(st == "completed" and "-" or "+")
					r.action:SetScript("OnClick", function()
						local dd = Data()
						dd.dailyQuests.completed[e.quest.id] = not dd.dailyQuests.completed[e.quest.id] or nil
						RR:Refresh()
					end)
					r.action:Show()
					r.tip = (st == "completed" and L["Undo completion"] or L["Mark as completed"]) .. "\n" .. (e.quest.name or "")
				end
			end
		else
			ClearRow(r)
		end
	end
	f.summary:SetText(L["Daily reset in"] .. ": |cffebad33" .. ResetCountdown())
end

function RR:RenderSettings()
	local f = self.frame
	if not f then return end
	f.colMid:SetText("")
	f.colStatus:SetText("")
	f.colRight:SetText("")
	local list = f.list
	local d = Data()
	local opts = {
		{ label = L["Show minimap button"], get = function() return d.minimap.show end,
		  set = function(v) d.minimap.show = v self:UpdateMinimap() end },
		{ label = L["Track daily quests"], get = function() return d.dailyQuests.showQuests end,
		  set = function(v) d.dailyQuests.showQuests = v end },
	}
	for i = 1, MAX_ROWS do
		local o = opts[i + self.scroll]
		local r = MakeRow(list, i)
		if o then
			FillRow(r, i)
			r.name:SetText(o.label)
			r.name:SetTextColor(0.85, 0.85, 0.9)
			r.status:SetText("")
			r.action.fs:SetText(o.get() and "|cff44dd66x|r" or "")
			r.action:SetScript("OnClick", function()
				o.set(not o.get())
				RR:Refresh()
			end)
			r.action:Show()
			r.tip = nil
		else
			ClearRow(r)
		end
	end
	f.summary:SetText("|cff666666SentinelUI " .. (S.version or "") .. "  —  xrl-dev.de|r")
end

function RR:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	if self.tab == "raids" then self:RenderInstances(true)
	elseif self.tab == "dungeons" then self:RenderInstances(false)
	elseif self.tab == "daily" then self:RenderDaily()
	else self:RenderSettings() end
end

-- window ---------------------------------------------------------------------
local function SetRowBorder(r, ...)
	local bd = r.suiBackdrop or r
	if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(...) end
end

function RR:SetTab(tab)
	self.tab = tab
	self.scroll = 0
	local f = self.frame
	for _, t in pairs(f.tabs) do
		local active = t.key == tab
		local label = t.fs
		label:SetTextColor(active and S.accent.r or 0.6, active and S.accent.g or 0.6, active and S.accent.b or 0.65)
		SetRowBorder(t, active and S.accent.r or S.media.borderColor[1],
			active and S.accent.g or S.media.borderColor[2],
			active and S.accent.b or S.media.borderColor[3], 1)
	end
	self:Refresh()
end

function RR:BuildFrame()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "SentinelUIRaidReset", UIParent)
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
	f.logo:SetTexture(ICON)
	f.logo:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)

	f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 6, 0)
	f.title:SetText(L["Instance Resets"])
	S:RegisterAccent(f.title, "text")

	f.close = CreateFrame("Button", nil, f)
	f.close:SetSize(16, 16)
	f.close:SetPoint("TOPRIGHT", -7, -6)
	S:CreateBackdrop(f.close, "Default")
	f.close.fs = S:FontString(f.close, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.close.fs:SetPoint("CENTER")
	f.close.fs:SetText("x")
	f.close:SetScript("OnClick", function() f:Hide() end)

	-- tabs
	f.tabs = {}
	local tabDefs = {
		{ key = "raids", label = L["Raids"] },
		{ key = "dungeons", label = L["Dungeons"] },
		{ key = "daily", label = L["Daily"] },
		{ key = "settings", label = L["Settings"] },
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
		t:SetScript("OnClick", function() RR:SetTab(def.key) end)
		f.tabs[i] = t
	end

	-- column header
	f.colName = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.colName:SetPoint("TOPLEFT", 16, -54)
	f.colName:SetText(L["Instance"])
	f.colName:SetTextColor(0.5, 0.5, 0.55)
	f.colMid = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.colMid:SetPoint("TOPLEFT", 304, -54)
	f.colMid:SetTextColor(0.5, 0.5, 0.55)
	f.colStatus = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.colStatus:SetPoint("TOPLEFT", 370, -54)
	f.colStatus:SetTextColor(0.5, 0.5, 0.55)
	f.colRight = S:FontString(f, 9, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	f.colRight:SetPoint("TOPRIGHT", -16, -54)
	f.colRight:SetTextColor(0.5, 0.5, 0.55)

	-- list area
	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", 8, -64)
	f.list:SetPoint("BOTTOMRIGHT", -8, 30)
	f.list:EnableMouse(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta)
		RR.scroll = RR.scroll - delta * 4
		if RR.scroll < 0 then RR.scroll = 0 end
		RR:Refresh()
	end)
	f.list.rows = {}

	-- footer
	f.summary = S:FontString(f, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.summary:SetPoint("BOTTOMLEFT", 10, 10)
	f.summary:SetPoint("RIGHT", -90, 0)
	f.summary:SetTextColor(0.65, 0.65, 0.7)

	f.refresh = CreateFrame("Button", nil, f)
	f.refresh:SetSize(76, 18)
	f.refresh:SetPoint("BOTTOMRIGHT", -8, 8)
	S:SkinButton(f.refresh)
	f.refresh.label = S:FontString(f.refresh, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.refresh.label:SetPoint("CENTER")
	f.refresh.label:SetText(L["Refresh"])
	f.refresh:SetScript("OnClick", function()
		if RequestRaidInfo then pcall(RequestRaidInfo) end
		RR:Refresh()
	end)

	tinsert(UISpecialFrames, "SentinelUIRaidReset")
	self.frame = f
	return f
end

function RR:Toggle()
	local f = self:BuildFrame()
	if f:IsShown() then f:Hide() return end
	f:Show()
	if not self.tab then self.tab = "raids" end
	self:SetTab(self.tab)
end

-- minimap button --------------------------------------------------------------
function RR:UpdateMinimap()
	local d = Data()
	if not d.minimap.show then
		if self.minimapBtn then self.minimapBtn:Hide() end
		return
	end
	-- one-time migration: the old implementation stored radians, the shared
	-- minimap-button factory stores degrees
	if d.minimap.angle and not d.minimap.deg then
		d.minimap.angle = math.deg(d.minimap.angle)
		d.minimap.deg = true
	end
	if not self.minimapBtn then
		self.minimapBtn = S:CreateMinimapButton({
			name = "raidreset", glyph = "RR", store = d.minimap, angle = -137,
			onLeft = function() RR:Toggle() end,
			tooltip = function()
				GameTooltip:AddLine("SentinelUI " .. L["Instance Resets"])
				GameTooltip:AddLine(L["Left-click: open  |  Drag: move"], 1, 1, 1)
				local locked = 0
				for _ in pairs(SavedInstances()) do locked = locked + 1 end
				if locked > 0 then
					GameTooltip:AddLine(format(L["%d instances locked"], locked), 1, 0.4, 0.4)
				end
			end,
		})
	end
	self.minimapBtn:Show()
	self.minimapBtn:UpdatePosition()
end

-- daily-run tracking ----------------------------------------------------------
RR.lastZone = nil
function RR:OnEnterWorld()
	CheckDailyReset()
	local inInst, itype = IsInInstance()
	if not inInst then
		self.lastZone = nil
		return
	end
	if itype ~= "party" and itype ~= "dungeon" and itype ~= "scenario" then return end
	local name = GetInstanceInfo()
	if not name or name == "" or name == self.lastZone then return end
	local key = NAME_DE[name] or name
	for _, dgName in ipairs(AllDungeons()) do
		if dgName == key then
			local d = Data()
			d.dailyRuns.runs[key] = (d.dailyRuns.runs[key] or 0) + 1
			self.lastZone = name
			break
		end
	end
end

function RR:Update()
	self.db = S.db.profile.raidreset
	self:UpdateMinimap()
end

function RR:Initialize()
	self.db = S.db.profile.raidreset
	Data() -- migrate/create saved store
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
	self:RegisterEvent("UPDATE_INSTANCE_INFO", "Refresh")
	self:UpdateMinimap()
	S:RegisterChatCommand("resets", function() RR:Toggle() end)
	S:RegisterChatCommand("rdreset", function() RR:Toggle() end)
	-- keep the old slash command working
	SLASH_RLRAIDDUNGEONRESET1 = "/rlrdr"
	SlashCmdList["RLRAIDDUNGEONRESET"] = function() RR:Toggle() end
	-- refresh the visible timers once a minute while open
	C_Timer.NewTicker(60, function()
		if RR.frame and RR.frame:IsShown() then RR:Refresh() end
	end)
end
