-- QuestScope: quest helper with world map + minimap pins for available quests,
-- objectives and turn-ins, plus quest progress lines in NPC/item tooltips.
-- All quest data comes from SentinelUI's own generated tables
-- (Modules/QuestScope/*.lua); no other addon's data or code is used.
local _, ns = ...
local S = ns.S
local L = S.L
local QS = S:NewModule("QuestScope", "questscope")

local _G = _G
local ipairs, pairs, wipe, tinsert = ipairs, pairs, wipe, table.insert
local format, floor, strsplit = string.format, math.floor, strsplit
local sqrt, sin, cos, atan2 = math.sqrt, math.sin, math.cos, math.atan2
local min, max = math.min, math.max
local CreateFrame, C_Timer = CreateFrame, C_Timer
local UnitLevel, UnitFactionGroup = UnitLevel, UnitFactionGroup
local IsSecret = S.IsSecret
local PI2 = math.pi * 2
local strtrim, strlower, strmatch, tonumber, type = strtrim, strlower, strmatch, tonumber, type

-- ---------------------------------------------------------------------------
-- own data layer (generated rows; numeric field indices). The dataset ships
-- inside this addon (Modules/QuestScope/Data_<flavor>.lua, each guarded by
-- interface version) as the SUIQuestScopeData global; ns.QuestScopeData stays
-- as a fallback.
-- ---------------------------------------------------------------------------
local QD -- SUIQuestScopeData, set at init
-- quest field indices:
local Q_NAME, Q_START, Q_FINISH, Q_REQLVL, Q_LVL, Q_RACES, Q_CLASSES = 1, 2, 3, 4, 5, 6, 7
local Q_OBJTEXT, Q_OBJS, Q_PREGROUP, Q_PRESINGLE, Q_ZONE = 8, 10, 12, 13, 17
local Q_NEXTCHAIN, Q_SPECIAL = 22, 24
-- npc field indices:
local N_NAME, N_SPAWNS, N_QSTART, N_QEND, N_FRIENDLY = 1, 7, 10, 11, 13
-- object field indices:
local O_NAME, O_QSTART, O_QEND, O_SPAWNS = 1, 2, 3, 4
-- item field indices:
local I_NAME, I_NPCDROP, I_OBJDROP, I_STARTQUEST, I_VENDORS, I_RELQUESTS = 1, 2, 3, 5, 14, 15

local function AreaToMap(areaId)
	local t = QD and QD.AreaToMap
	if not t then return end
	local mapID = t[areaId]
	if not mapID and QD.SubZone then
		-- spawn data may point at a sub-zone (caves, cities, starting areas);
		-- walk the parent chain until a mappable zone is found
		local aid, guard = areaId, 0
		while aid and not mapID and guard < 8 do
			aid = QD.SubZone[aid]
			mapID = aid and t[aid]
			guard = guard + 1
		end
	end
	return mapID
end

-- localized names from the generated L10n blocks (deDE etc.)
local clientLocale = GetLocale and GetLocale() or "enUS"
local function L10nName(kind, id, enName)
	local lt = QD and QD.L10n and QD.L10n[clientLocale]
	local row = lt and lt[kind] and lt[kind][id]
	if type(row) == "table" then return row[1] or enName end
	return row or enName
end

local myFacTag = UnitFactionGroup("player") == "Horde" and "H" or "A"

-- spawns: { [areaId] = { {x,y,phase?}, ... } } with x/y in 0-100 percent space
local function SpawnPoints(spawnList)
	local out = {}
	if type(spawnList) ~= "table" then return out end
	local dgs, dgAlt = QD.Dungeons, QD.DungeonAlt
	for areaId, coords in pairs(spawnList) do
		-- spawn sits inside a dungeon (direct or via a floor/alt id): pin the
		-- entrance coordinates on the parent zone instead
		local dg = dgs and (dgs[areaId] or (dgAlt and dgs[dgAlt[areaId]]))
		if dg then
			for _, l in ipairs(dg.l or {}) do
				if not l[4] or l[4] == myFacTag then
					local m = AreaToMap(l[1])
					if m and m ~= 0 then
						local x, y = l[2], l[3]
						if x > 1 or y > 1 then x, y = x / 100, y / 100 end
						tinsert(out, { mapID = m, x = x, y = y })
					end
				end
			end
		else
			local mapID = AreaToMap(areaId)
			if mapID and mapID ~= 0 and type(coords) == "table" then
				for _, c in ipairs(coords) do
					if type(c) == "table" and c[1] and c[2] then
						local x, y = c[1], c[2]
						if x > 1 or y > 1 then x, y = x / 100, y / 100 end
						tinsert(out, { mapID = mapID, x = x, y = y })
					end
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- quest state helpers
-- ---------------------------------------------------------------------------
local function QuestCompleted(qid)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		local ok, r = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
		if ok then return r and true or false end
	end
	return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(qid) and true or false
end

local function LogQuests()
	-- questID -> { index, title, level, complete }
	local out = wipe(QS.logQuests or {})
	QS.logQuests = out
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID then
				local complete
				if C_QuestLog.IsComplete then
					local ok, r = pcall(C_QuestLog.IsComplete, info.questID)
					if ok then complete = r and true or false end
				end
				out[info.questID] = { index = i, title = info.title, level = info.level, complete = complete }
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		-- classic quest log API
		for i = 1, GetNumQuestLogEntries() do
			local title, level, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
			if qid and not isHeader then
				out[qid] = { index = i, title = title, level = level, complete = isComplete and true or nil }
			end
		end
	end
	return out
end

local function QuestObjectives(qid)
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, r = pcall(C_QuestLog.GetQuestObjectives, qid)
		if ok and type(r) == "table" then
			-- normalize modern field names (numRequired/objectID -> numNeeded/id)
			for _, o in ipairs(r) do
				if o.numNeeded == nil then o.numNeeded = o.numRequired end
				if o.id == nil then o.id = o.objectID end
			end
			return r
		end
	end
	-- classic fallback: leaderboard lines via the quest's current log index
	local idx = QS.logQuests and QS.logQuests[qid] and QS.logQuests[qid].index
	if idx and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
		local ok, n = pcall(GetNumQuestLeaderBoards, idx)
		if ok and n and n > 0 then
			local out = {}
			for i = 1, n do
				local text, _, done = GetQuestLogLeaderBoard(i, idx)
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

QS.ObjectivesOf = QuestObjectives

-- ---------------------------------------------------------------------------
-- availability engine
-- ---------------------------------------------------------------------------
local classMask
local function PlayerClassMask()
	if classMask then return classMask end
	local classID = (select(3, UnitClass("player")))
	classMask = classID and (2 ^ (classID - 1)) or 0
	return classMask
end

local raceMask
local function PlayerRaceMask()
	if raceMask then return raceMask end
	-- UnitRace's third return is the numeric race id; its bit (2^(id-1)) matches
	-- the requiredRaces bitmask layout the generated data uses
	-- (1=Human,2=Orc,3=Dwarf,4=NightElf,5=Scourge,6=Tauren,7=Gnome,8=Troll,
	-- 9=Goblin,10=BloodElf,11=Draenei)
	local raceID = (select(3, UnitRace("player")))
	raceMask = raceID and (2 ^ (raceID - 1)) or 0
	return raceMask
end

local function PreQuestsMet(qd)
	local group, single = qd[Q_PREGROUP], qd[Q_PRESINGLE]
	if group then
		for _, pq in ipairs(group) do
			if not QuestCompleted(pq) then return false end
		end
	end
	if single then
		local any = false
		for _, pq in ipairs(single) do
			if QuestCompleted(pq) then any = true break end
		end
		if not any then return false end
	end
	return true
end

local bit_band = _G.bit and _G.bit.band or _G.bit32 and _G.bit32.band
if not bit_band then
	bit_band = function(a, b)
		local res, bitv = 0, 1
		while a > 0 or b > 0 do
			local abit, bbit = a % 2, b % 2
			if abit == 1 and bbit == 1 then res = res + bitv end
			a, b = floor(a / 2), floor(b / 2)
			bitv = bitv * 2
		end
		return res
	end
end

-- faction fallback mask used only if UnitRace yields no id (shouldn't happen)
local FACTION_MASKS = {
	Alliance = 1 + 4 + 8 + 64 + 1024 + 2097152,
	Horde = 2 + 16 + 32 + 128 + 256 + 512,
}

function QS:NpcFriendly(npcId)
	local nd = QD.Npc and QD.Npc[npcId]
	if not nd then return true end
	local f = nd[N_FRIENDLY]
	if not f then return true end
	local mine = UnitFactionGroup("player") == "Horde" and "H" or "A"
	return f == "AH" or f == mine
end

-- available quest giver icons: { qid, title, level, mapID, x, y, kind }
function QS:BuildAvailable()
	local out = wipe(self.avail or {})
	self.avail = out
	local quests = QD.Quest
	if not quests then return out end
	local lvl = UnitLevel("player")
	local raceMask = PlayerRaceMask()
	if raceMask == 0 then raceMask = FACTION_MASKS[UnitFactionGroup("player")] end
	local clsMask = PlayerClassMask()
	local db = self.db
	local log = LogQuests()
	local npcData = QD.Npc or {}
	local objData = QD.Object or {}
	for qid, qd in pairs(quests) do
		local reqLvl = qd[Q_REQLVL] or 0
		local qLvl = qd[Q_LVL] or reqLvl
		if qLvl and qLvl > 0 and reqLvl <= lvl and (db.showTrivial or qLvl >= lvl - 9) and qLvl <= lvl + 5
			and not log[qid] and not QuestCompleted(qid)
			and PreQuestsMet(qd) then
			local races = qd[Q_RACES]
			local classes = qd[Q_CLASSES]
			if (not races or races == 0 or (raceMask and bit_band(races, raceMask) ~= 0))
				and (not classes or classes == 0 or bit_band(classes, clsMask) ~= 0) then
				local start = qd[Q_START]
				if start then
					local title = L10nName("Quest", qid, qd[Q_NAME]) or ("Quest " .. qid)
					local trivial = qLvl < lvl - 4
					local repeatable = qd[Q_SPECIAL] and bit_band(qd[Q_SPECIAL], 1) ~= 0
					-- startedBy: { npcIds?, objectIds?, itemIds? } (positional slots)
					if start[1] then
						for _, npcId in ipairs(start[1]) do
							if self:NpcFriendly(npcId) then
								local nd = npcData[npcId]
								for _, p in ipairs(SpawnPoints(nd and nd[N_SPAWNS])) do
									tinsert(out, { qid = qid, title = title, level = qLvl, mapID = p.mapID, x = p.x, y = p.y,
										kind = repeatable and "repeatable" or (trivial and "trivial" or "avail") })
								end
							end
						end
					end
					if start[2] then
						for _, objId in ipairs(start[2]) do
							local od = objData[objId]
							for _, p in ipairs(SpawnPoints(od and od[O_SPAWNS])) do
								tinsert(out, { qid = qid, title = title, level = qLvl, mapID = p.mapID, x = p.x, y = p.y,
									kind = trivial and "trivial" or "avail" })
							end
						end
					end
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- gossip/quest-giver decoration: prepend [level] to quest names in NPC dialogs
-- (Questie-style). Quests are matched to the DB by localized/english name.
-- ---------------------------------------------------------------------------
local gossipNameIndex
local function GossipNameIndex()
	if gossipNameIndex then return gossipNameIndex end
	gossipNameIndex = {}
	local lt = QD.L10n and QD.L10n[clientLocale]
	for qid, qd in pairs(QD.Quest or {}) do
		local row = lt and lt.Quest and lt.Quest[qid]
		local loc = type(row) == "table" and row[1] or row
		for _, n in ipairs({ loc, qd[Q_NAME] }) do
			if type(n) == "string" and n ~= "" then
				local k = strlower(n)
				gossipNameIndex[k] = gossipNameIndex[k] or qid
			end
		end
	end
	return gossipNameIndex
end

local function QuestLevelOfName(text)
	if not text or text == "" or text:sub(1, 1) == "[" then return nil end
	local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*(.-)%s*$", "%1")
	local qid = GossipNameIndex()[strlower(clean)]
	if not qid then return nil end
	local qd = QD.Quest[qid]
	return qd and (qd[Q_LVL] or qd[Q_REQLVL])
end

local function DecorateGossipButton(btn)
	local fs = btn and btn.GetFontString and btn:GetFontString()
	local text = fs and fs:GetText() or (btn and btn.GetText and btn:GetText())
	local lvl = QuestLevelOfName(text)
	if lvl then btn:SetText(format("[%d] %s", lvl, text)) end
end

local function DecorateGossip()
	local i = 1
	while true do
		local b = _G["QuestTitleButton" .. i] or _G["GossipTitleButton" .. i]
		if not b then break end
		if b:IsShown() then DecorateGossipButton(b) end
		i = i + 1
	end
	-- modern clients: greeting panel buttons inside the ScrollBox
	local gp = _G.GossipFrame and (_G.GossipFrame.GreetingPanel or _G.GossipFrameGreetingPanel)
	local sb = gp and gp.ScrollBox
	if sb and sb.ForEachFrame then
		sb:ForEachFrame(function(f)
			if f:IsObjectType("Button") and f:IsShown() then DecorateGossipButton(f) end
		end)
	end
end

local function DecorateQuestTitle()
	local qid = GetQuestID and GetQuestID()
	if not qid or qid == 0 then return end
	local qd = QD.Quest and QD.Quest[qid]
	local lvl = qd and (qd[Q_LVL] or qd[Q_REQLVL])
	if not lvl then return end
	for _, n in ipairs({ "QuestInfoTitleHeader", "QuestTitleText", "QuestProgressTitleText", "QuestLogTitleText" }) do
		local fs = _G[n]
		local t = fs and fs.GetText and fs:GetText()
		if t and t ~= "" and t:sub(1, 1) ~= "[" then
			fs:SetText(format("[%d] %s", lvl, t))
		end
	end
end

-- ---------------------------------------------------------------------------
-- quest-log objectives -> positions
-- ---------------------------------------------------------------------------
function QS:BuildObjectives()
	local out = wipe(self.obj or {})
	self.obj = out
	local quests = QD.Quest
	if not quests then return out end
	local db = self.db
	local npcData = QD.Npc or {}
	local objData = QD.Object or {}
	local itemData = QD.Item or {}
	local nav = S:GetModule("Navigation")
	for qid, qs in pairs(LogQuests()) do
		local qd = quests[qid]
		if not qd then
			-- unknown quest in the log: skip it, do not abort the whole build
		elseif qs.complete then
			if db.showTurnIn then
				-- Blizzard's own quest POI is the authoritative "?" spot;
				-- our spawn DB can drift a few meters off (patrol NPCs,
				-- stale crowd-sourced coords), so prefer it when present
				local pm, px, py = nav and nav.QuestPosition and nav:QuestPosition(qid)
				if pm then
					tinsert(out, { qid = qid, title = qs.title, level = qs.level, mapID = pm, x = px, y = py, kind = "turnin" })
				end
				local fin = (not pm) and qd[Q_FINISH]
				if fin and fin[1] then
					for _, npcId in ipairs(fin[1]) do
						local nd = npcData[npcId]
						for _, p in ipairs(SpawnPoints(nd and nd[N_SPAWNS])) do
							tinsert(out, { qid = qid, title = qs.title, level = qs.level, mapID = p.mapID, x = p.x, y = p.y, kind = "turnin" })
						end
					end
				end
			end
		else
			local state = QuestObjectives(qid)
			local objs = state and qd[Q_OBJS]
			if state then
			for oi, o in ipairs(state) do
				if not o.finished then
					if o.type == "monster" then
						-- kill-credit lists may map the credit npc to other spawns;
						-- objs[5][i] = {creditNpcList, targetNpcId, ...} per objective
						local want = {}
						if objs and objs[1] then
							for _, c in ipairs(objs[1]) do want[c[1]] = true end
						end
						if objs and objs[5] then
							for _, kc in pairs(objs[5]) do
								if kc[2] then want[kc[2]] = true end
								if kc[1] then
									for _, n in ipairs(kc[1]) do want[n] = true end
								end
							end
						end
						if want[o.id] or not next(want) then
							local nd = npcData[o.id]
							for _, p in ipairs(SpawnPoints(nd and nd[N_SPAWNS])) do
								tinsert(out, { qid = qid, title = qs.title .. " - " .. (o.text or ""), level = qs.level, objIdx = oi, mapID = p.mapID, x = p.x, y = p.y, kind = "obj_monster" })
							end
						end
					elseif o.type == "object" then
						local od = objData[o.id]
						for _, p in ipairs(SpawnPoints(od and od[O_SPAWNS])) do
							tinsert(out, { qid = qid, title = qs.title .. " - " .. (o.text or ""), level = qs.level, objIdx = oi, mapID = p.mapID, x = p.x, y = p.y, kind = "obj_object" })
						end
					elseif o.type == "item" then
						local it = itemData[o.id]
						if it then
							if it[I_NPCDROP] then
								for _, npcId in ipairs(it[I_NPCDROP]) do
									local nd = npcData[npcId]
									for _, p in ipairs(SpawnPoints(nd and nd[N_SPAWNS])) do
										tinsert(out, { qid = qid, title = qs.title .. " - " .. (o.text or ""), level = qs.level, objIdx = oi, mapID = p.mapID, x = p.x, y = p.y, kind = "obj_item" })
									end
								end
							end
							if it[I_OBJDROP] then
								for _, objId in ipairs(it[I_OBJDROP]) do
									local od = objData[objId]
									for _, p in ipairs(SpawnPoints(od and od[O_SPAWNS])) do
										tinsert(out, { qid = qid, title = qs.title .. " - " .. (o.text or ""), level = qs.level, objIdx = oi, mapID = p.mapID, x = p.x, y = p.y, kind = "obj_item" })
									end
								end
							end
						end
					end
				end
			end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- pin rendering - world map
-- ---------------------------------------------------------------------------
local PIN_KIND = {
	avail       = { tex = [[Interface\GossipFrame\AvailableQuestIcon]] },
	trivial     = { tex = [[Interface\GossipFrame\AvailableQuestIcon]], gray = true },
	repeatable  = { tex = [[Interface\GossipFrame\AvailableLegendaryQuestIcon]] },
	turnin      = { tex = [[Interface\GossipFrame\ActiveQuestIcon]] },
	obj_monster = { tex = [[Interface\TargetingFrame\UI-RaidTargetingIcon_8]] },
	obj_item    = { tex = [[Interface\Icons\INV_Misc_Bag_08]] },
	obj_object  = { tex = [[Interface\Icons\INV_Misc_Gear_01]] },
	obj_other   = { tex = [[Interface\GossipFrame\ChatGossipIcon]] },
	objective   = { tex = [[Interface\GossipFrame\ChatGossipIcon]] },
	dungeon     = { tex = [[Interface\Icons\Spell_Arcane_TeleportIronForge]] },
}

-- cluster display priority: which member's icon represents the merged pin
local PIN_RANK = { turnin = 4, avail = 3, repeatable = 3, trivial = 1 }
local function PinRank(kind)
	if kind and kind:sub(1, 4) == "obj_" then return 2 end
	return PIN_RANK[kind] or 2
end

-- live objective lines for pin tooltips: {text, done, party, i} per objective
local function ObjectiveLines(qid)
	local out = {}
	local state = QuestObjectives(qid)
	if state then
		for i, o in ipairs(state) do
			local t = o.text
			if (not t or t == "") and o.numNeeded and o.numNeeded > 0 then
				t = format("%d/%d", o.numFulfilled or 0, o.numNeeded)
			end
			if t and t ~= "" then
				out[#out + 1] = { text = t, done = o.finished, party = QS:PartyLine(qid, i), i = i }
			end
		end
	end
	return out
end

-- pin tooltip lines: only the objective this pin stands for when it has one
local function AddObjLines(d, indent)
	for _, ol in ipairs(ObjectiveLines(d.qid)) do
		if not d.objIdx or ol.i == d.objIdx then
			local col = ol.done and 0.35 or 0.75
			GameTooltip:AddLine((indent or "- ") .. ol.text ..
				(ol.party and ("  |cff66ccff" .. ol.party .. "|r") or ""), col, col, col)
		end
	end
end

function QS:MapPin(canvas, n)
	local pin = self.mapPins[n]
	if not pin then
		pin = CreateFrame("Button", nil, canvas)
		pin:SetFrameLevel(canvas:GetFrameLevel() + 6)
		pin.tex = pin:CreateTexture(nil, "ARTWORK")
		pin.tex:SetAllPoints()
		pin:SetScript("OnEnter", function(self2)
			local d = self2.data
			if not d then return end
			GameTooltip:SetOwner(self2, "ANCHOR_CURSOR")
			local c = self2.cluster
			if c and #c.members > 1 then
				GameTooltip:AddLine(format("%d %s", #c.members, L["objectives here"] or "objectives here"), 1, 1, 1)
				for _, m in ipairs(c.members) do
					GameTooltip:AddLine("- " .. (m.title or ""), 0.9, 0.9, 0.9)
					if m.qid and (m.kind or ""):sub(1, 4) == "obj_" then AddObjLines(m, "    ") end
				end
			else
				GameTooltip:AddLine(d.title or "", 1, 1, 1)
				if d.level then GameTooltip:AddLine(format("%s %d", LEVEL or "Level", d.level), 0.8, 0.8, 0.8) end
				if d.kind == "avail" or d.kind == "trivial" then
					GameTooltip:AddLine(L["Quest available"] or "Quest available", 0.4, 0.9, 0.3)
				elseif d.kind == "turnin" then
					GameTooltip:AddLine(L["Turn in quest"] or "Turn in quest", 1, 0.85, 0.1)
				elseif d.kind == "dungeon" then
					GameTooltip:AddLine(L["Dungeon entrance"] or "Dungeon entrance", 0.6, 0.8, 1)
				elseif d.qid and (d.kind or ""):sub(1, 4) == "obj_" then
					AddObjLines(d)
				end
			end
			GameTooltip:AddLine(L["Click: navigate here"] or "Click: navigate here", 0.55, 0.55, 0.55)
			GameTooltip:Show()
		end)
		pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
		pin:RegisterForClicks("LeftButtonUp")
		pin:SetScript("OnClick", function(self2)
			QS:NavTo(self2.data, true)
		end)
		self.mapPins[n] = pin
	end
	return pin
end

function QS:StylePin(pin, d)
	local k = PIN_KIND[d.kind] or PIN_KIND.avail
	local isObj = d.kind and d.kind:sub(1, 4) == "obj_"
	local sz = (self.db.mapPinSize or 14) * (isObj and 0.85 or 1)
	pin:SetSize(sz, sz)
	pin.tex:SetTexture(k.tex)
	pin.tex:SetTexCoord(0, 1, 0, 1)
	pin.tex:SetVertexColor(1, 1, 1, 1)
	pin.tex:SetDesaturated(k.gray and true or false)
end

-- build the standalone dungeon-entrance pin list once (zone entrance coords on
-- the parent outdoor map, faction-gated entrances filtered)
function QS:DungPins()
	if self.dung or not QD.Dungeons then return self.dung or {} end
	self.dung = {}
	for did, dg in pairs(QD.Dungeons) do
		for _, l in ipairs(dg.l or {}) do
			if not l[4] or l[4] == myFacTag then
				local m = AreaToMap(l[1])
				if m and m ~= 0 then
					local x, y = l[2], l[3]
					if x > 1 or y > 1 then x, y = x / 100, y / 100 end
					local nm = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(did)
					tinsert(self.dung, { qid = -did, title = nm or ("Instance " .. did),
						mapID = m, x = x, y = y, kind = "dungeon" })
				end
			end
		end
	end
	return self.dung
end

function QS:RefreshWorldMap()
	if not self.mapPins then return end
	for _, p in ipairs(self.mapPins) do p:Hide() end
	if not (self.db.showMap and WorldMapFrame and WorldMapFrame:IsShown()) then return end
	local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas() or WorldMapFrame.ScrollContainer
	if not canvas then return end
	local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	if not mapID then return end
	local cw, ch = canvas:GetSize()
	if not cw or cw == 0 then return end
	local n, clusters = 0, {}
	local function Place(d)
		-- merge pins within ~2.5% map radius into a cluster pin with a count
		if self.db.clusterPins then
			for _, c in ipairs(clusters) do
				local dx, dy = c.d.x - d.x, c.d.y - d.y
				if dx * dx + dy * dy < 0.000625 then
					c.members[#c.members + 1] = d
					if PinRank(d.kind) > PinRank(c.d.kind) then c.d = d end
					return
				end
			end
		end
		local c = { d = d, members = { d } }
		clusters[#clusters + 1] = c
		n = n + 1
		local pin = self:MapPin(canvas, n)
		pin.data = d
		pin.cluster = c
		self:StylePin(pin, d)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", canvas, "TOPLEFT", d.x * cw, -d.y * ch)
		pin:Show()
		c.pin = pin
	end
	-- debug: real canvas mapID vs pin table ids (mapID mismatch = invisible pins)
	local hit, hitA = 0, 0
	for _, d in ipairs(self.obj or {}) do
		if d.mapID == mapID then Place(d) hit = hit + 1 end
	end
	for _, d in ipairs(self.avail or {}) do
		if d.mapID == mapID then Place(d) hitA = hitA + 1 end
	end
	S:Log("questscope", format("mapID=%s pins=%d avail=%d", tostring(mapID), hit, hitA))
	if self.db.showDungeons then
		for _, d in ipairs(self:DungPins()) do
			if d.mapID == mapID then Place(d) end
		end
	end
	-- second pass: cluster badges + representative icon
	for _, c in ipairs(clusters) do
		local pin = c.pin
		if #c.members > 1 then
			pin.data = c.d
			self:StylePin(pin, c.d)
			pin.count = pin.count or S:FontString(pin, 10, "OUTLINE")
			pin.count:SetPoint("BOTTOMRIGHT", 4, -2)
			pin.count:SetText(#c.members)
			pin.count:Show()
		elseif pin.count then
			pin.count:Hide()
		end
	end
end

-- ---------------------------------------------------------------------------
-- minimap pins- projected from normalized map coords like the nav waypoint pin
-- ---------------------------------------------------------------------------
local function MapToWorld(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
	local ok, inst, vec = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not ok or not vec then return end
	return vec.x, vec.y, inst, vec.z
end

local function PlayerWorld()
	if not UnitPosition then return end
	-- UnitPosition quirk: first return is posY (west axis), second posX (north)
	local posW, posN, posZ, inst = UnitPosition("player")
	if not posN then return end
	return posN, posW, inst, posZ
end

-- waypoint helper: auto-nav (focus follow) never re-sets an identical target;
-- forced clicks may re-set, but not faster than every 3 s
function QS:NavTo(d, force)
	local nav = S:GetModule("Navigation")
	if not (d and nav and nav.AddWaypoint) then return end
	local last = self._lastNav
	if last and last.mapID == d.mapID and last.x == d.x and last.y == d.y then
		if not force then return end
		local now = GetTime and GetTime() or 0
		if now - (last.t or 0) < 3 then return end
	end
	self._lastNav = { mapID = d.mapID, x = d.x, y = d.y, t = GetTime and GetTime() or 0 }
	nav:AddWaypoint(d.mapID, d.x, d.y, d.title or L["Quest"])
end

function QS:EnsureMiniPins()
	if self.miniPins or not _G.Minimap then return end
	self.miniPins = {}
	local mm = _G.Minimap
	for i = 1, (self.db.miniPool or 40) do
		local pin = CreateFrame("Button", nil, mm)
		pin:SetSize(12, 12)
		pin:SetFrameLevel(mm:GetFrameLevel() + 6)
		pin.tex = pin:CreateTexture(nil, "ARTWORK")
		pin.tex:SetAllPoints()
		pin.count = S:FontString(pin, 9, "OUTLINE")
		pin.count:SetPoint("BOTTOMRIGHT", 4, -4)
		pin.count:Hide()
		pin:SetScript("OnEnter", function(self2)
			local d = self2.data
			if not d then return end
			GameTooltip:SetOwner(self2, "ANCHOR_CURSOR")
			if self2._titles then
				GameTooltip:AddLine(format("%d %s", self2._n or 1, L["objectives"] or "objectives"), 1, 1, 1)
				for i, t in ipairs(self2._titles) do
					if i > 5 then GameTooltip:AddLine("...", 0.6, 0.6, 0.6) break end
					GameTooltip:AddLine(t, 0.8, 0.8, 0.8)
					local m = self2._members and self2._members[i]
					if m and m.qid and (m.kind or ""):sub(1, 4) == "obj_" then AddObjLines(m, "    ") end
				end
			else
				GameTooltip:AddLine(d.title or "", 1, 1, 1)
				if d.qid and (d.kind or ""):sub(1, 4) == "obj_" then AddObjLines(d) end
			end
			GameTooltip:AddLine(L["Click: navigate here"] or "Click: navigate here", 0.55, 0.55, 0.55)
			GameTooltip:Show()
		end)
		pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
		pin:RegisterForClicks("LeftButtonUp")
		pin:SetScript("OnClick", function(self2)
			QS:NavTo(self2.data, true)
		end)
		self.miniPins[i] = pin
	end
end

function QS:UpdateMinimap()
	local pins = self.miniPins
	if not pins then return end
	for _, p in ipairs(pins) do p:Hide() end
	if not self.db.showMinimap then return end
	local mm = _G.Minimap
	if not mm or not mm:IsShown() then return end
	local pN, pW, _, inst = PlayerWorld()
	if not pN then return end
	local facing = 0
	if GetCVar("rotateMinimap") == "1" then facing = (GetPlayerFacing and GetPlayerFacing()) or 0 end
	local radius = (mm:GetWidth() / 2) - 10
	local used = 0
	local cells = {}
	local CELL = 13
	local maxDist = self.db.miniMaxDist or 250
	local viewDist = self.db.miniViewDist or 160
	local function Place(d)
		if used >= #pins then return end
		local wN, wW, wInst = MapToWorld(d.mapID, d.x, d.y)
		if not wN or wInst ~= inst then return end
		local dN, dW = wN - pN, wW - pW
		local dist = sqrt(dN * dN + dW * dW)
		if dist > maxDist then return end
		local bearing = atan2(-dW, dN)
		local pxPerYard = radius / viewDist
		local pr = min(dist * pxPerYard, radius)
		local ang = bearing + facing
		local x = sin(ang) * pr
		local y = cos(ang) * pr
		if S.db.profile.minimap and S.db.profile.minimap.shape ~= "ROUND" then
			x = max(-radius, min(radius, x))
			y = max(-radius, min(radius, y))
		end
		local key
		if self.db.clusterMinimap then
			key = floor((x + radius) / CELL) .. ":" .. floor((y + radius) / CELL)
			local cp = cells[key]
			if cp then
				cp._n = (cp._n or 1) + 1
				cp._titles = cp._titles or { cp.data.title }
				cp._titles[#cp._titles + 1] = d.title
				cp._members = cp._members or { cp.data }
				cp._members[#cp._members + 1] = d
				cp.count:SetText(cp._n)
				cp.count:Show()
				return
			end
		end
		used = used + 1
		local pin = pins[used]
		pin.data = d
		pin._n, pin._titles, pin._members = nil, nil, nil
		pin.count:Hide()
		if key then cells[key] = pin end
		local k = PIN_KIND[d.kind] or PIN_KIND.avail
		pin.tex:SetTexture(k.tex)
		pin.tex:SetTexCoord(0, 1, 0, 1)
		pin.tex:SetDesaturated(k.gray and true or false)
		pin.tex:SetVertexColor(1, 1, 1, 1)
		pin:SetAlpha(dist > viewDist * 0.9 and 0.65 or 1)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", mm, "CENTER", x, y)
		pin:Show()
	end
	for _, d in ipairs(self.obj or {}) do Place(d) end
	for _, d in ipairs(self.avail or {}) do Place(d) end
	if self.db.showDungeons then
		for _, d in ipairs(self:DungPins()) do Place(d) end
	end
end

-- ---------------------------------------------------------------------------
-- tooltips: quest progress on NPC/object/item tooltips
-- ---------------------------------------------------------------------------
local function TooltipNpcId(tt)
	local _, unit = tt:GetUnit()
	if not unit then return end
	local guid = UnitGUID(unit)
	if not guid then return end
	local parts = { strsplit("-", guid) }
	return tonumber(parts[6] or "")
end

function QS:OnTooltipUnit(tt)
	if not self.db.tooltips then return end
	local npcId = TooltipNpcId(tt)
	if not npcId then return end
	local quests = QD.Quest
	if not quests then return end
	local shownSomething
	local npcData = QD.Npc or {}
	local nd = npcData[npcId]
	if nd and nd[N_QSTART] then
		for _, qid in ipairs(nd[N_QSTART]) do
			for _, d in ipairs(self.avail) do
				if d.qid == qid then
					tt:AddLine(format("%s%s [%d]", "|cffffd100!|r ", d.title, d.level or 0), 1, 1, 1)
					shownSomething = true
				end
			end
		end
	end
	local itemData = QD.Item or {}
	for qid, qs in pairs(self.logQuests or {}) do
		local qd = quests[qid]
		if qd then
			local objs = qd[Q_OBJS]
			local state = QuestObjectives(qid)
			local added
			if qs.complete then
				-- ready to turn in at this npc
				local fin = qd[Q_FINISH]
				if fin and fin[1] then
					for _, n in ipairs(fin[1]) do
						if n == npcId then
							tt:AddLine(format("|cff40ff40[?] [%d] %s|r", qs.level or 0, qs.title or ("Quest " .. qid)), 0.4, 1, 0.4)
							added, shownSomething = true, true
							break
						end
					end
				end
			elseif state then
				for i, o in ipairs(state) do
					-- does this npc contribute to objective i?
					local match
					if o.type == "monster" then
						if o.id == npcId then
							match = true
						elseif objs then
							-- kill-credit: this npc's kills count for the objective's
							-- target npc; objs[5][i] = {creditList, targetId, ...}
							local kc = objs[5] and objs[5][i]
							if kc then
								if kc[2] == npcId then match = true end
								if not match and kc[1] then
									for _, n in ipairs(kc[1]) do
										if n == npcId then match = true break end
									end
								end
							end
							if not match and objs[1] then
								for _, c in ipairs(objs[1]) do
									if c[1] == npcId then match = true break end
								end
							end
						end
					elseif o.type == "object" then
						if o.id == npcId then match = true end
					elseif o.type == "item" then
						-- this npc drops a required quest item
						local it = itemData[o.id]
						if it and it[I_NPCDROP] then
							for _, n in ipairs(it[I_NPCDROP]) do
								if n == npcId then match = true break end
							end
						end
					end
					if match then
						local prog = ""
						if o.text and o.text ~= "" then
							prog = "  " .. o.text
						elseif o.numNeeded and o.numNeeded > 0 then
							prog = format("  (%d/%d)", o.numFulfilled or 0, o.numNeeded)
						end
						local pl = self:PartyLine(qid, i)
						if pl then prog = prog .. "  |cff66ccff" .. pl .. "|r" end
						local col = o.finished and "|cff40ff40" or "|cffffd200"
						tt:AddLine(format("%s[%d] %s|r%s", col, qs.level or 0, qs.title or ("Quest " .. qid), prog), 0.9, 0.7, 0.2)
						added, shownSomething = true, true
					end
				end
			end
			-- no live state: fall back to static data so the npc is still marked
			if not added and objs then
				local hit
				if objs[1] then
					for _, c in ipairs(objs[1]) do if c[1] == npcId then hit = true break end end
				end
				if not hit and objs[5] then
					for _, kc in pairs(objs[5]) do
						if kc[2] == npcId then hit = true break end
						if not hit and kc[1] then
							for _, n in ipairs(kc[1]) do if n == npcId then hit = true break end end
						end
						if hit then break end
					end
				end
				if not hit and objs[3] then
					for _, it in ipairs(objs[3]) do
						local row = type(it) == "table" and itemData[it[1]]
						if row and row[I_NPCDROP] then
							for _, n in ipairs(row[I_NPCDROP]) do
								if n == npcId then hit = true break end
							end
						end
						if hit then break end
					end
				end
				if hit then
					tt:AddLine(format("|cffffd200[%d] %s|r", qs.level or 0, qs.title or ("Quest " .. qid)), 0.9, 0.7, 0.2)
					shownSomething = true
				end
			end
		end
	end
	if shownSomething then tt:Show() end
end

-- game objects have no unit/item on the tooltip; the first line is the
-- object's localized name. Resolve it against the data (EN + client locale).
function QS:ObjectIdsByName(name)
	if not name or name == "" then return end
	local map = self._objByName
	if not map then
		map = {}
		self._objByName = map
		for objId, od in pairs(QD.Object or {}) do
			local en = od[O_NAME]
			if en then
				map[en] = map[en] or {}
				map[en][#map[en] + 1] = objId
			end
			local loc = L10nName("Object", objId, en)
			if loc and loc ~= en then
				map[loc] = map[loc] or {}
				map[loc][#map[loc] + 1] = objId
			end
		end
	end
	return map[name]
end

function QS:OnTooltipObject(tt)
	if not self.db.tooltips then return end
	-- only fire for plain object captions (not unit/item/spell tooltips)
	if tt:GetUnit() or tt:GetItem() or (tt.GetSpell and tt:GetSpell()) then return end
	local fs = _G[tt:GetName() .. "TextLeft1"]
	local name = fs and fs:GetText()
	if not name or name == "" then return end
	if tt._suiObjDone == name then return end -- already annotated this hover
	local ids = self:ObjectIdsByName(name)
	if not ids then return end
	local quests = QD.Quest
	if not quests then return end
	local shownSomething
	local itemData = QD.Item or {}
	for _, objId in ipairs(ids) do
		local od = (QD.Object or {})[objId]
		-- quests this object offers / accepts
		if od then
			for _, qid in ipairs(od[O_QSTART] or {}) do
				for _, d in ipairs(self.avail or {}) do
					if d.qid == qid then
						tt:AddLine(format("%s%s [%d]", "|cffffd100!|r ", d.title, d.level or 0), 1, 1, 1)
						shownSomething = true
					end
				end
			end
		end
		for qid, qs in pairs(self.logQuests or {}) do
			local qd = quests[qid]
			if qd then
				-- turn-in at this object (object side keeps the reverse map)
				local isFin
				if od and od[O_QEND] then
					for _, fqid in ipairs(od[O_QEND]) do
						if fqid == qid then isFin = true break end
					end
				end
				if qs.complete and isFin then
					tt:AddLine(format("|cff40ff40[?] [%d] %s|r", qs.level or 0, qs.title or ("Quest " .. qid)), 0.4, 1, 0.4)
					shownSomething = true
				else
					local objs = qd[Q_OBJS]
					local state = QuestObjectives(qid)
					local added
					if state then
						for i, o in ipairs(state) do
							local match
							if o.type == "object" then
								if o.id == objId then match = true end
								if not match and objs and objs[2] then
									for _, c in ipairs(objs[2]) do
										if c[1] == objId then match = true break end
									end
								end
							elseif o.type == "item" then
								local it = itemData[o.id]
								if it and it[I_OBJDROP] then
									for _, n in ipairs(it[I_OBJDROP]) do
										if n == objId then match = true break end
									end
								end
							end
							if match then
								local prog = ""
								if o.text and o.text ~= "" then
									prog = "  " .. o.text
								elseif o.numNeeded and o.numNeeded > 0 then
									prog = format("  (%d/%d)", o.numFulfilled or 0, o.numNeeded)
								end
								local pl = self:PartyLine(qid, i)
								if pl then prog = prog .. "  |cff66ccff" .. pl .. "|r" end
								local col = o.finished and "|cff40ff40" or "|cffffd200"
								tt:AddLine(format("%s[%d] %s|r%s", col, qs.level or 0, qs.title or ("Quest " .. qid), prog), 0.9, 0.7, 0.2)
								added, shownSomething = true, true
							end
						end
					end
					-- static fallback when there is no live objective state
					if not added and objs and objs[2] then
						for _, c in ipairs(objs[2]) do
							if c[1] == objId then
								tt:AddLine(format("|cffffd200[%d] %s|r", qs.level or 0, qs.title or ("Quest " .. qid)), 0.9, 0.7, 0.2)
								shownSomething = true
								break
							end
						end
					end
				end
			end
		end
	end
	if shownSomething then
		tt._suiObjDone = name
		tt:Show()
	end
end

function QS:OnTooltipItem(tt)
	if not self.db.tooltips then return end
	local _, link = tt:GetItem()
	local itemId = link and tonumber(strmatch(link, "item:(%d+)"))
	if not itemId then return end
	local quests = QD.Quest
	if not quests then return end
	local shown
	for qid, qs in pairs(self.logQuests or {}) do
		local qd = quests[qid]
		if qd then
			local objs = qd[Q_OBJS]
			if objs and objs[3] then
				for _, it in ipairs(objs[3]) do
					if type(it) == "table" and it[1] == itemId then
						local state = QuestObjectives(qid)
						local prog = ""
						if state then
							for i, o in ipairs(state) do
								if o.type == "item" and o.id == itemId and o.numNeeded then
									prog = format(" (%d/%d)", o.numFulfilled or 0, o.numNeeded)
									local pl = self:PartyLine(qid, i)
									if pl then prog = prog .. "  |cff66ccff" .. pl .. "|r" end
									break
								end
							end
						end
						tt:AddLine(format("|cffffd200[%d] %s|r%s", qs.level or 0, qs.title or ("Quest " .. qid), prog), 0.9, 0.7, 0.2)
						shown = true
						break
					end
				end
			end
		end
	end
	local it = QD.Item and QD.Item[itemId]
	-- this item starts a quest itself (dropped quest starters like old letters)
	if it and it[I_STARTQUEST] then
		local qd = quests[it[I_STARTQUEST]]
		if qd and not (self.logQuests or {})[it[I_STARTQUEST]] then
			tt:AddLine(format("%s%s [%d]", "|cffffd100!|r ",
				L10nName("Quest", it[I_STARTQUEST], qd[Q_NAME]), qd[Q_LVL] or 0), 1, 1, 1)
			shown = true
		end
	end
	-- drop/loot/vendor sources for any quest-relevant item
	if self.db.dropSource and (shown or (it and (it[I_NPCDROP] or it[I_OBJDROP] or it[I_VENDORS]))) then
		if it then
			local names = {}
			if it[I_NPCDROP] then
				for _, npcId in ipairs(it[I_NPCDROP]) do
					if #names >= 3 then break end
					local nm = L10nName("Npc", npcId, QD.Npc and QD.Npc[npcId] and QD.Npc[npcId][N_NAME])
					if nm then names[#names + 1] = nm end
				end
			end
			if #names > 0 then
				tt:AddLine((L["Drops from:"] or "Drops from:") .. " " .. table.concat(names, ", "), 0.6, 0.6, 0.6)
				shown = true
			end
			if it[I_OBJDROP] then
				local onames = {}
				for _, objId in ipairs(it[I_OBJDROP]) do
					if #onames >= 3 then break end
					local nm = L10nName("Object", objId, QD.Object and QD.Object[objId] and QD.Object[objId][O_NAME])
					if nm then onames[#onames + 1] = nm end
				end
				if #onames > 0 then
					tt:AddLine((L["Contained in:"] or "Contained in:") .. " " .. table.concat(onames, ", "), 0.6, 0.6, 0.6)
					shown = true
				end
			end
			if it[I_VENDORS] then
				local vnames = {}
				for _, npcId in ipairs(it[I_VENDORS]) do
					if #vnames >= 3 then break end
					local nm = L10nName("Npc", npcId, QD.Npc and QD.Npc[npcId] and QD.Npc[npcId][N_NAME])
					if nm then vnames[#vnames + 1] = nm end
				end
				if #vnames > 0 then
					tt:AddLine((L["Sold by:"] or "Sold by:") .. " " .. table.concat(vnames, ", "), 0.6, 0.6, 0.6)
					shown = true
				end
			end
		end
	end
	if shown then tt:Show() end
end

-- ---------------------------------------------------------------------------
-- quest completion announce + focused quest (auto-waypoint)
-- ---------------------------------------------------------------------------
local function QuestDing()
	local kit = SOUNDKIT and (SOUNDKIT.UI_AUTO_QUEST_COMPLETE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if kit then pcall(PlaySound, kit) end
end

function QS:AnnounceProgress()
	if not self.db.announce then self._prog = nil return end
	local prev = self._prog or {}
	local cur = {}
	for qid, qs in pairs(self.logQuests or {}) do
		local objs = QuestObjectives(qid)
		local st, any, done = {}, false, true
		for i, o in ipairs(objs or {}) do
			if o.numNeeded and o.numNeeded > 0 then
				any = true
				st[i] = o.numFulfilled or 0
				if st[i] < o.numNeeded then done = false end
			end
		end
		st.done = any and done or nil
		cur[qid] = st
		local p = prev[qid]
		if p then
			for i, o in ipairs(objs or {}) do
				local f = o.numFulfilled or 0
				if p[i] and o.numNeeded and p[i] < o.numNeeded and f >= o.numNeeded then
					S:Print(format("%s |cff33ff33(%s)|r", qs.title or qid, o.text or ""))
					break
				end
			end
			if st.done and not p.done then
				S:Print(format("%s |cff33ff33%s|r", qs.title or qid, L["Complete!"] or "Complete!"))
				QuestDing()
			end
		end
	end
	self._prog = cur
end

-- ---------------------------------------------------------------------------
-- party progress sync: objective progress is broadcast to the group and shown
-- in NPC/item tooltips ("<name>: 3/10") like Questie's party sync
-- ---------------------------------------------------------------------------
local SYNC_PREFIX = "SUIQS"

function QS:SyncProgress()
	local sent, cur = {}, {}
	local prev = self._sent or {}
	local prevQ = self._sentQuests or {}
	local changed
	local inGroup = self.db.partySync and IsInGroup and IsInGroup()
		and C_ChatInfo and C_ChatInfo.SendAddonMessage
	for qid in pairs(self.logQuests or {}) do
		cur[qid] = true
		for i, o in ipairs(QuestObjectives(qid) or {}) do
			if o.numNeeded and o.numNeeded > 0 then
				local key = qid .. ":" .. i
				local f = o.numFulfilled or 0
				sent[key] = f
				if prev[key] ~= f then
					changed = changed or {}
					changed[qid] = true
					if inGroup then
						C_ChatInfo.SendAddonMessage(SYNC_PREFIX,
							format("%d:%d:%d:%d", qid, i, f, o.numNeeded),
							(IsInRaid and IsInRaid()) and "RAID" or "PARTY")
					end
				end
			end
		end
	end
	-- interop: mirror changes to Questie clients in the group
	if inGroup and self.Questie then
		if changed then self.Questie:BroadcastUpdates(changed) end
		for qid in pairs(prevQ) do
			if not cur[qid] then self.Questie:BroadcastRemove(qid) end
		end
	end
	self._sent = sent
	self._sentQuests = cur
end

-- "<name>: f/n, <name>: f/n" for a shared objective, capped at 3 members
function QS:PartyLine(qid, objIdx)
	if not (self.db.partySync and self.party) then return end
	local key = qid .. ":" .. objIdx
	local out, n
	for name, p in pairs(self.party) do
		local v = p[key]
		if v then
			n = (n or 0) + 1
			if n > 3 then out = out .. ", ..." break end
			local tag = (p._src == "questie") and "|cff777777Q|r " or ""
			out = out and (out .. ", " .. tag .. name .. ": " .. v) or (tag .. name .. ": " .. v)
		end
	end
	return out
end

-- all waypoint candidates for a quest: built objective/turn-in pins first,
-- then quest-data fallbacks (finisher, then starter) so navigation still works
-- when the pin lists are empty or the quest has no live objectives
function QS:QuestWaypoints(qid)
	local out = {}
	for _, list in ipairs({ self.obj, self.avail }) do
		for _, p in ipairs(list or {}) do
			if p.qid == qid then out[#out + 1] = p end
		end
	end
	if #out > 0 then return out end
	local qd = QD.Quest and QD.Quest[qid]
	if not qd then return out end
	local function addPts(kind, id)
		local tbl = kind == "npc" and QD.Npc or QD.Object
		local row = tbl and tbl[id]
		for _, p in ipairs(SpawnPoints(row and row[kind == "npc" and N_SPAWNS or O_SPAWNS])) do
			out[#out + 1] = p
		end
	end
	local qs = self.logQuests and self.logQuests[qid]
	local chain = (qs and qs.complete) and { qd[Q_FINISH], qd[Q_START] } or { qd[Q_START], qd[Q_FINISH] }
	for _, ref in ipairs(chain) do
		if ref then
			for _, id in ipairs(ref[1] or {}) do addPts("npc", id) end
			for _, id in ipairs(ref[2] or {}) do addPts("object", id) end
			-- item-started quests: waypoint the item's drop sources instead
			for _, itemId in ipairs(ref[3] or {}) do
				local it = QD.Item and QD.Item[itemId]
				for _, npcId in ipairs(it and it[I_NPCDROP] or {}) do addPts("npc", npcId) end
			end
			if #out > 0 then break end
		end
	end
	return out
end

-- nearest pins for a quest, preferring the player's current zone map. Up to
-- `multiWaypoints` candidates are added as a numbered chain — the nav arrow
-- advances to the next one automatically when a waypoint is reached
function QS:NavToQuest(qid, title, force)
	local cands = self:QuestWaypoints(qid)
	if #cands == 0 then return end
	local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local n = (self.db.multiWaypoints ~= false) and 3 or 1
	local pN, pW, inst = PlayerWorld()
	local function distOf(p)
		local wN, wW, wInst = MapToWorld(p.mapID, p.x, p.y)
		if not wN or not pN or wInst ~= inst then return math.huge end
		local dN, dW = wN - pN, wW - pW
		return sqrt(dN * dN + dW * dW)
	end
	local same, other = {}, {}
	for _, p in ipairs(cands) do
		tinsert((here and p.mapID == here) and same or other, p)
	end
	table.sort(same, function(a, b) return distOf(a) < distOf(b) end)
	table.sort(other, function(a, b) return distOf(a) < distOf(b) end)
	local picks, seen = {}, {}
	for _, list in ipairs({ same, other }) do
		for _, p in ipairs(list) do
			if #picks >= n then break end
			local k = format("%s:%.4f:%.4f", p.mapID, p.x, p.y)
			if not seen[k] then seen[k] = true picks[#picks + 1] = p end
		end
	end
	if #picks == 0 then return end
	local nav = S:GetModule("Navigation")
	if not (nav and nav.AddWaypoint) then return end
	-- our previous nav set still has unconsumed picks: the chain keeps
	-- driving the arrow, so don't re-add duplicates or steal a manually
	-- set target just because a refresh fired / the pick order changed
	if not force and self._navQid == qid and self._navRefs and nav.IsWaypointLive then
		for _, r in ipairs(self._navRefs) do
			if nav:IsWaypointLive(r.mapID, r.wp) then return true end
		end
	end
	-- composite dedup over the whole chain: identical auto-nav repeats are
	-- dropped; forced clicks may re-set but not faster than every 3 s
	local parts = {}
	for _, p in ipairs(picks) do parts[#parts + 1] = format("%s:%.4f:%.4f", p.mapID, p.x, p.y) end
	local key = table.concat(parts, "|")
	if self._lastNavK == key then
		if not force then return true end
		if (GetTime() - (self._lastNavT or 0)) < 3 then return true end
	end
	self._lastNavK, self._lastNavT = key, GetTime()
	-- drop leftovers of the previous nav set before installing the new one
	-- (repeated refreshes used to append the same picks again and again,
	-- letting stale entries hijack the arrow via closest-fallback)
	if self._navRefs and nav.RemoveWaypointRef then
		for _, r in ipairs(self._navRefs) do nav:RemoveWaypointRef(r.mapID, r.wp) end
	end
	self._navRefs, self._navQid = {}, qid
	local chainId = #picks > 1 and {} or nil -- shared table marker links a chain
	for i, p in ipairs(picks) do
		local t = (#picks > 1) and format("%s (%d/%d)", title or p.title or L["Quest"], i, #picks)
			or (title or p.title)
		local wp = nav:AddWaypoint(p.mapID, p.x, p.y, t, { silent = i > 1, chain = chainId, seq = i })
		if wp then self._navRefs[i] = { mapID = p.mapID, wp = wp } end
	end
	return true
end

function QS:FocusQuest(qid, title, forceSet)
	if forceSet then
		self.focusQid = qid
	else
		self.focusQid = (self.focusQid == qid) and nil or qid
	end
	-- unfocusing (or refocusing a different quest) drops the auto-nav set
	-- so its waypoints can't keep hijacking the arrow
	if self.focusQid ~= self._navQid and self._navRefs then
		local nav = S:GetModule("Navigation")
		if nav and nav.RemoveWaypointRef then
			for _, r in ipairs(self._navRefs) do nav:RemoveWaypointRef(r.mapID, r.wp) end
		end
		self._navRefs, self._navQid = nil, nil
	end
	if self.focusQid and not self:NavToQuest(qid, title, true) then
		S:Print(format("%s: %s", title or qid, L["no map location known"] or "no map location known"))
	end
	if self.UpdateTracker then self:UpdateTracker() end
end

-- shared helpers for the Tracker/Journey files (QD is a file-local)
function QS:GetData() return QD end
QS._AreaToMap = AreaToMap
QS._L10nName = L10nName
QS._MapToWorld = MapToWorld
QS._SpawnPoints = SpawnPoints

-- ---------------------------------------------------------------------------
-- auto accept / turn-in (hold Shift to bypass automation for one dialog)
-- ---------------------------------------------------------------------------
function QS:AutoQuest(event)
	if IsShiftKeyDown and IsShiftKeyDown() then return end
	local db = self.db
	if event == "QUEST_DETAIL" then
		C_Timer.After(0, DecorateQuestTitle)
		if db.autoAccept and AcceptQuest then pcall(AcceptQuest) end
	elseif event == "QUEST_ACCEPT_CONFIRM" then
		if db.autoAccept and ConfirmAcceptQuest then pcall(ConfirmAcceptQuest) end
	elseif event == "QUEST_PROGRESS" then
		C_Timer.After(0, DecorateQuestTitle)
		if db.autoTurnIn and IsQuestCompletable and IsQuestCompletable() then pcall(CompleteQuest) end
	elseif event == "QUEST_COMPLETE" then
		C_Timer.After(0, DecorateQuestTitle)
		if db.autoTurnIn then
			local n = GetNumQuestChoices and GetNumQuestChoices() or 0
			if n <= 1 then
				C_Timer.After(0.1, function()
					if GetQuestReward then pcall(GetQuestReward, n == 1 and 1 or nil) end
				end)
			end
		end
	elseif event == "QUEST_GREETING" then
		C_Timer.After(0, DecorateGossip)
		-- multi-quest NPC dialog: hand in first, otherwise take the first offer
		if db.autoTurnIn and GetNumActiveQuests and GetNumActiveQuests() > 0 and SelectActiveQuest then
			pcall(SelectActiveQuest, 1)
		elseif db.autoAccept and GetNumAvailableQuests and GetNumAvailableQuests() > 0 and SelectAvailableQuest then
			pcall(SelectAvailableQuest, 1)
		end
	elseif event == "GOSSIP_SHOW" then
		C_Timer.After(0, DecorateGossip)
		if db.autoTurnIn and C_GossipInfo and C_GossipInfo.GetActiveQuests then
			for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
				if q.isComplete then pcall(C_GossipInfo.SelectActiveQuest, q.questID) return end
			end
		elseif db.autoTurnIn and GetNumGossipActiveQuests and GetNumGossipActiveQuests() == 1 and SelectGossipActiveQuest then
			pcall(SelectGossipActiveQuest, 1)
			return
		end
		if db.autoAccept then
			local n = (C_GossipInfo and C_GossipInfo.GetNumAvailableQuests and C_GossipInfo.GetNumAvailableQuests())
				or (GetNumGossipAvailableQuests and GetNumGossipAvailableQuests()) or 0
			if n == 1 then
				if C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest then
					local q = (C_GossipInfo.GetAvailableQuests() or {})[1]
					if q and q.questID then pcall(C_GossipInfo.SelectAvailableQuest, q.questID) end
				elseif SelectGossipAvailableQuest then
					pcall(SelectGossipAvailableQuest, 1)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- refresh scheduling
-- ---------------------------------------------------------------------------
function QS:RefreshAll()
	if not (self.initialized and QD) then return end
	S:SafeCall("QuestScope:Build", function()
		QS:BuildAvailable()
		QS:BuildObjectives()
		QS:AnnounceProgress()
		QS:SyncProgress()
		if QS.focusQid and not (QS.logQuests and QS.logQuests[QS.focusQid]) then
			QS.focusQid = nil
			-- quest gone: its auto-nav waypoints are leftovers now
			local nav = S:GetModule("Navigation")
			if QS._navRefs and nav and nav.RemoveWaypointRef then
				for _, r in ipairs(QS._navRefs) do nav:RemoveWaypointRef(r.mapID, r.wp) end
			end
			QS._navRefs, QS._navQid = nil, nil
		end
		if QS.focusQid then QS:NavToQuest(QS.focusQid) end
		QS:RefreshWorldMap()
		if QS.UpdateTracker then QS:UpdateTracker() end
	end)
end

function QS:ScheduleRefresh()
	if self.refreshQueued then return end
	self.refreshQueued = true
	C_Timer.After(0.3, function()
		self.refreshQueued = nil
		QS:RefreshAll()
	end)
end

-- ---------------------------------------------------------------------------
-- module lifecycle
-- ---------------------------------------------------------------------------
function QS:Initialize()
	-- respect the module toggle: a disabled QuestScope must not spawn its
	-- tracker, pins, tickers or hooks (users running Questie saw double trackers)
	if (self.private and self.private.enable == false) or (self.db and self.db.enable == false) then return end
	QD = _G.SUIQuestScopeData or ns.QuestScopeData
	if not (QD and QD.Quest and QD.Npc and QD.AreaToMap) then
		S:Print(L["QuestScope: no quest data for this client flavor."] or "QuestScope: no quest data for this client flavor.")
		return
	end
	self.avail, self.obj = {}, {}
	self.mapPins = {}
	self:EnsureMiniPins()

	if WorldMapFrame then
		WorldMapFrame:HookScript("OnShow", function() QS:RefreshWorldMap() end)
		if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() QS:RefreshWorldMap() end) end
		local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas() or WorldMapFrame.ScrollContainer
		if canvas and canvas.HookScript then canvas:HookScript("OnSizeChanged", function() QS:RefreshWorldMap() end) end
	end

	C_Timer.NewTicker(0.2, function() S:SafeCall("QuestScope:Minimap", QS.UpdateMinimap, QS) end)

	if GameTooltip then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tt) S:SafeCall("QuestScope:TipUnit", QS.OnTooltipUnit, QS, tt) end)
		GameTooltip:HookScript("OnTooltipSetItem", function(tt) S:SafeCall("QuestScope:TipItem", QS.OnTooltipItem, QS, tt) end)
		-- game objects have no native tooltip event: detect them by the caption
		-- line while the tooltip is shown (deduped per hover)
		GameTooltip:HookScript("OnUpdate", function(tt) S:SafeCall("QuestScope:TipObject", QS.OnTooltipObject, QS, tt) end)
		GameTooltip:HookScript("OnHide", function(tt) tt._suiObjDone = nil end)
		if ItemRefTooltip then
			ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt) S:SafeCall("QuestScope:TipItem", QS.OnTooltipItem, QS, tt) end)
		end
	end

	-- party sync: receive progress from group members, prune on roster change
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, SYNC_PREFIX)
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, "questie") -- interop prefix
	end
	self.party = {}
	self:RegisterEvent("CHAT_MSG_ADDON", function(_, _, prefix, msg, channel, sender)
		if type(msg) ~= "string" then return end
		if prefix == SYNC_PREFIX then
			local qid, i, f, n = strmatch(msg, "^(%d+):(%d+):(%d+):(%d+)$")
			if not qid then return end
			local name = sender and strsplit("-", sender)
			if not name or name == UnitName("player") then return end
			local p = QS.party[name]
			if not p then p = {} QS.party[name] = p end
			p._src = "sui"
			p[qid .. ":" .. i] = f .. "/" .. n
		elseif prefix == "questie" and QS.Questie then
			S:SafeCall("QuestScope:QuestieComms", QS.Questie.OnMessage, QS.Questie, msg, channel, sender)
		end
	end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		if not QS.party then return end
		local members = {}
		for i = 1, 4 do
			local n = UnitName("party" .. i)
			if n then members[strsplit("-", n)] = true end
		end
		for i = 1, 40 do
			local n = UnitName("raid" .. i)
			if n then members[strsplit("-", n)] = true end
		end
		for name in pairs(QS.party) do
			if not members[name] then QS.party[name] = nil end
		end
		local count = 0
		for _ in pairs(members) do count = count + 1 end
		QS._sent = nil -- resend own progress to (new) members
		-- interop: hand our quest log to Questie clients when the roster grows
		if QS.Questie and count > (QS._memberCount or 0) then
			C_Timer.After(2, function()
				if QS.party then QS.Questie:BroadcastLog() end
			end)
		end
		QS._memberCount = count
		QS:ScheduleRefresh()
	end)

	-- warn before abandoning a quest that belongs to a chain (popup is up,
	-- user hasn't confirmed yet)
	hooksecurefunc("StaticPopup_Show", function(which)
		if which ~= "ABANDON_QUEST" or not QD.Quest then return end
		local idx = GetQuestLogSelection and GetQuestLogSelection()
		local qid = idx and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex
			and C_QuestLog.GetQuestIDForLogIndex(idx)
		if not qid and idx and GetQuestLogTitle then
			qid = select(8, GetQuestLogTitle(idx))
		end
		local qd = qid and QD.Quest[qid]
		if not qd then return end
		local title = L10nName("Quest", qid, qd[Q_NAME]) or ("Quest " .. qid)
		local nxt = qd[Q_NEXTCHAIN]
		if nxt then
			local nm = L10nName("Quest", nxt, QD.Quest[nxt] and QD.Quest[nxt][Q_NAME]) or ("Quest " .. nxt)
			S:Print(format("|cffffcc00%s:|r %s → %s",
				L["Quest chain"] or "Quest chain", title, nm))
		elseif qd[Q_PRESINGLE] or qd[Q_PREGROUP] then
			S:Print(format("|cffffcc00%s:|r %s",
				L["Quest chain"] or "Quest chain", title))
		end
	end)

	self:RegisterEvent("QUEST_LOG_UPDATE", function() QS:ScheduleRefresh() end)
	self:RegisterEvent("QUEST_ACCEPTED", function() QS:ScheduleRefresh() end)
	self:RegisterEvent("QUEST_REMOVED", function() QS:ScheduleRefresh() end)
	self:RegisterEvent("QUEST_TURNED_IN", function() QS:ScheduleRefresh() end)
	self:RegisterEvent("PLAYER_LEVEL_UP", function() QS:ScheduleRefresh() end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() QS:ScheduleRefresh() end)

	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "questscope", glyph = "QS",
		store = self.private.minimap, angle = 275,
		onLeft = function() S:ToggleConfig("questscope") end,
		onRight = function() QS:RefreshAll() end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. (L["Quest Scope"] or "Quest Scope"))
			GameTooltip:AddLine(L["Left-click: options  |  Right-click: refresh quest pins"], 1, 1, 1)
		end,
	})

	SlashCmdList.SUIQUESTSCOPE = function(msg)
		msg = strtrim(strlower(msg or ""))
		if msg == "refresh" or msg == "r" then QS:RefreshAll()
		elseif (msg == "journey" or msg == "j") and QS.ToggleJourney then QS:ToggleJourney()
		elseif msg == "debug" or msg == "d" then
			local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
				or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or -1
			local logN, hits, miss = 0, 0, {}
			for qid in pairs(self.logQuests or {}) do
				logN = logN + 1
				if QD and QD.Quest and QD.Quest[qid] then hits = hits + 1
				elseif #miss < 6 then miss[#miss + 1] = tostring(qid) end
			end
			local objN, avN = #(self.obj or {}), #(self.avail or {})
			local partyN = 0
			for _ in pairs(self.party or {}) do partyN = partyN + 1 end
			-- interop diagnostics: decoded packets + spooled multipart chunks
			local qc = self.Questie
			local qRx, qSpool = 0, 0
			if qc then
				qRx = qc._rx or 0
				for _ in pairs(qc._spool or {}) do qSpool = qSpool + 1 end
			end
			S:Print(format("QS: GetInfo=%s LogTitle=%s entries=%s log=%d hits=%d miss=%s obj=%d avail=%d wp156=%d trk=%s party=%d sent=%d qRx=%d qSpool=%d qst=%s",
				tostring(C_QuestLog and C_QuestLog.GetInfo ~= nil),
				tostring(GetQuestLogTitle ~= nil),
				tostring(n), logN, hits, table.concat(miss, ","),
				objN, avN,
				#(self.QuestWaypoints and self:QuestWaypoints(156) or {}),
				tostring(self.tracker and self.tracker:IsShown()),
				partyN,
				(function() local c = 0 for _ in pairs(self._sent or {}) do c = c + 1 end return c end)(),
				qRx, qSpool, tostring(qc ~= nil)))
		else S:ToggleConfig("questscope") end
	end
	SLASH_SUIQUESTSCOPE1, SLASH_SUIQUESTSCOPE2 = "/suiqs", "/questscope"

	for _, ev in ipairs({ "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "GOSSIP_SHOW" }) do
		self:RegisterEvent(ev, function(_, e) QS:AutoQuest(e) end)
	end

	if self.CreateTracker then S:SafeCall("QuestScope:Tracker", self.CreateTracker, self) end
	C_Timer.After(2, function() QS:RefreshAll() end)
end

function QS:Update()
	-- runtime disable: hide everything the module drew; the framework only
	-- gates Initialize, so a toggled-off module would linger without this
	if (self.private and self.private.enable == false) or (self.db and self.db.enable == false) then
		if self.tracker then self.tracker:Hide() end
		for _, pin in pairs(self.mapPins or {}) do if pin.Hide then pin:Hide() end end
		return
	end
	self:ScheduleRefresh()
end
