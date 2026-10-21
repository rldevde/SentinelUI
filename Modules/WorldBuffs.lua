local addonName, ns = ...
local S = ns.S
local L = S.L
local D = ns.WorldBuffsData
local WB = S:NewModule("WorldBuffs", "worldbuffs")

local GetServerTime = GetServerTime
local UnitName, UnitGUID, UnitFactionGroup = UnitName, UnitGUID, UnitFactionGroup
local GetLocale = GetLocale
local floor = math.floor
local max = math.max
local random = math.random
local sort = table.sort
local format = string.format
local strsplit = strsplit
local tonumber = tonumber
local pairs, ipairs = pairs, ipairs
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local date, time = date, time

local PREFIX = "SUIWB"
local BUFF_ORDER = { "rend", "ony", "nef", "zan" }
local YELL_KEYS = {
	rend = "Rend buff drops in %s seconds.",
	ony = "Onyxia buff drops in %s seconds.",
	nef = "Nefarian buff drops in %s seconds.",
	zan = "Zandalar buff drops in %s seconds.",
}
local DROP_KEYS = {
	rend = "Warchief's Blessing (Rend) has dropped.",
	ony = "Rallying Cry of the Dragonslayer (Onyxia) has dropped.",
	nef = "Rallying Cry of the Dragonslayer (Nefarian) has dropped.",
	zan = "Spirit of Zandalar (Hakkar) has dropped.",
}
local NAME_KEYS = { rend = "Rend", ony = "Onyxia", nef = "Nefarian", zan = "Zandalar" }

function WB:BuffName(kind)
	return L[NAME_KEYS[kind]] or kind
end

-- ---------------------------------------------------------------------------
-- data
-- ---------------------------------------------------------------------------
local function Realm()
	local r = GetRealmName and GetRealmName() or "?"
	return (r:gsub("%s+", ""))
end

function WB:Data()
	if type(SentinelUIBuffDB) ~= "table" then SentinelUIBuffDB = {} end
	local db = SentinelUIBuffDB
	local realm = self.realm or Realm()
	self.realm = realm
	db[realm] = db[realm] or {}
	local d = db[realm]
	d.layers = d.layers or {}
	d.timerLog = d.timerLog or {}
	d.songflowers = d.songflowers or {}
	return d
end

function WB:IT()
	return S:GetModule("InstanceTracker", true)
end

-- layers live in the instancetracker table so numbering stays identical;
-- buff fields get attached to the same entries.
function WB:Layers()
	local IT = self:IT()
	if IT and IT.Data then
		local d = IT:Data()
		d.layers = d.layers or {}
		return d.layers
	end
	return self:Data().layers
end

function WB:LayerEntry(zoneID, create)
	local layers = self:Layers()
	local e = layers[zoneID]
	if not e and create then
		local count = 0
		for _ in pairs(layers) do count = count + 1 end
		if count >= 20 then return end
		e = { firstSeen = GetServerTime() }
		layers[zoneID] = e
	end
	return e
end

function WB:CurrentLayerID()
	local IT = self:IT()
	return IT and IT.currentLayerID
end

function WB:LayerNum(zoneID)
	local IT = self:IT()
	if IT and IT.LayerNum then return IT:LayerNum(zoneID) end
	local keys = {}
	for k in pairs(self:Layers()) do keys[#keys + 1] = k end
	sort(keys)
	for i, k in ipairs(keys) do if k == zoneID then return i end end
	return 0
end

-- current layer entry + number, or nils when not yet detected
function WB:LayerContext()
	local id = self:CurrentLayerID()
	if id then
		return self:LayerEntry(id, true), self:LayerNum(id), id
	end
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
function WB:Print(msg)
	S:Print("|cff00aaff" .. L["World Buffs"] .. "|r " .. tostring(msg))
end

function WB:TimeString(seconds)
	if not seconds or seconds < 0 then seconds = 0 end
	local h = floor(seconds / 3600)
	local m = floor((seconds % 3600) / 60)
	local s = floor(seconds % 60)
	if h > 0 then return format("%dh %dm", h, m) end
	if m > 0 then return format("%dm %ds", m, s) end
	return format("%ds", s)
end

local function NpcFields(guid)
	if not guid or type(guid) ~= "string" then return end
	-- Creature-0-server-instance-zoneID-npcID-spawnUID
	local utype, _, _, _, zoneID, npcID = strsplit("-", guid)
	if utype ~= "Creature" and utype ~= "Vehicle" then return end
	return tonumber(npcID), tonumber(zoneID)
end

-- ---------------------------------------------------------------------------
-- comm
-- ---------------------------------------------------------------------------
function WB:SendComm(msg, channel, target)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
end

function WB:GuildComm(msg)
	if IsInGuild and IsInGuild() then self:SendComm(msg, "GUILD") end
end

function WB:BroadcastTimer(kind, zoneID, ts)
	self:GuildComm(format("T|%s|%d|%d", kind, zoneID, ts))
end

function WB:BroadcastYell(kind, zoneID, delay)
	self:GuildComm(format("Y|%s|%d|%s", kind, zoneID, tostring(delay or "")))
end

function WB:BroadcastNpc(kind, zoneID)
	self:GuildComm(format("N|%s|%d|%d", kind, zoneID, GetServerTime()))
end

function WB:BroadcastFlower(zoneID, idx, ts)
	self:GuildComm(format("F|%d|%d|%d", zoneID or 0, idx, ts))
end

function WB:RequestSync()
	self:GuildComm("Q")
end

function WB:SendSync(target)
	for zoneID, e in pairs(self:Layers()) do
		if type(e) == "table" then
			self:SendComm(format("S|%d|%d|%d|%d|%d", zoneID,
				e.rendTimer or 0, e.onyTimer or 0, e.nefTimer or 0, e.zanTimer or 0),
				"WHISPER", target)
		end
	end
end

function WB:OnComm(_, _, msg, dist, sender)
	if type(msg) ~= "string" then return end
	local cmd, a, b, c = strsplit("|", msg)
	local who = Ambiguate and Ambiguate(sender, "short") or sender
	if cmd == "Y" then
		local zoneID, delay = tonumber(b), tonumber(c)
		if not zoneID or zoneID == 0 or zoneID == self:CurrentLayerID() then
			self:FirstYell(a, zoneID, who, delay)
		end
	elseif cmd == "T" then
		local zoneID, ts = tonumber(b), tonumber(c)
		if zoneID and ts and D.cooldowns[a] then
			local e = self:LayerEntry(zoneID, true)
			if e and (not e[a .. "Timer"] or e[a .. "Timer"] < ts) then
				e[a .. "Timer"] = ts
				self:LogDrop(a, ts, who, self:LayerNum(zoneID))
				self:RefreshUI()
			end
		end
	elseif cmd == "N" then
		local zoneID, ts = tonumber(b), tonumber(c)
		if (a == "ony" or a == "nef") and zoneID and ts then
			local e = self:LayerEntry(zoneID, true)
			if e then e[a .. "NpcDied"] = ts end
			self:RefreshUI()
		end
	elseif cmd == "F" then
		local zoneID, idx, ts = tonumber(a), tonumber(b), tonumber(c)
		if zoneID and idx and ts then self:SetFlower(zoneID, idx, ts, true) end
	elseif cmd == "S" then
		local _, zid, rt, ot, nt, zt = strsplit("|", msg)
		local zoneID = tonumber(zid)
		if zoneID then
			local e = self:LayerEntry(zoneID, true)
			if e then
				e.rendTimer = max(e.rendTimer or 0, tonumber(rt) or 0)
				e.onyTimer = max(e.onyTimer or 0, tonumber(ot) or 0)
				e.nefTimer = max(e.nefTimer or 0, tonumber(nt) or 0)
				e.zanTimer = max(e.zanTimer or 0, tonumber(zt) or 0)
				self:RefreshUI()
			end
		end
	elseif cmd == "Q" then
		self:Delay(2 + random(0, 5), function() self:SendSync(who) end)
	end
end

-- ---------------------------------------------------------------------------
-- timers + log
-- ---------------------------------------------------------------------------
function WB:LogDrop(kind, ts, who, layerNum)
	local log = self:Data().timerLog
	log[#log + 1] = { t = kind, ts = ts or GetServerTime(), who = who, layer = layerNum }
	while #log > 100 do table.remove(log, 1) end
end

function WB:SetTimer(kind, zoneID, ts, silent)
	local e = self:LayerEntry(zoneID, true)
	if not e then return end
	ts = ts or GetServerTime()
	if e[kind .. "Timer"] and e[kind .. "Timer"] >= ts then return end
	e[kind .. "Timer"] = ts
	self:LogDrop(kind, ts, nil, self:LayerNum(zoneID))
	if not silent then self:BroadcastTimer(kind, zoneID, ts) end
	self:RefreshUI()
end

-- returns remaining cooldown seconds (0 when hand-in is possible again)
function WB:Remaining(kind, entry)
	local cd = D.cooldowns[kind]
	if not cd or cd == 0 or not entry then return 0 end
	local t = entry[kind .. "Timer"]
	if not t then return 0 end
	return max(0, cd - (GetServerTime() - t))
end

-- ---------------------------------------------------------------------------
-- yell detection
-- ---------------------------------------------------------------------------
local function YellTable()
	local loc = GetLocale and GetLocale() or "enUS"
	return D.yells[loc] or D.yells.enUS
end

function WB:MatchYell(msg, name)
	local yt = YellTable()
	for kind, def in pairs(yt) do
		if def.names[name] then
			for _, frag in ipairs(def.frags) do
				if msg:find(frag, 1, true) then return kind end
			end
		end
	end
end

local firstYellAt = {}

function WB:FirstYell(kind, zoneID, source, delay)
	if not D.cooldowns[kind] then return end
	if GetServerTime() - (firstYellAt[kind] or 0) < 40 then return end
	firstYellAt[kind] = GetServerTime()

	local e = zoneID and self:LayerEntry(zoneID, true)
	if e then e[kind .. "Yell"] = GetServerTime() end

	local delay = delay or D.dropDelay[kind] or 14
	local layerMsg = ""
	if zoneID and zoneID > 0 then
		local num = self:LayerNum(zoneID)
		if num > 0 then layerMsg = " (" .. format(L["Layer %d"], num) .. ")" end
	end
	local dropMsg = format(L[YELL_KEYS[kind]], delay)
	if self.db.announceYell ~= false then
		self:Print(dropMsg .. layerMsg)
	end
	if self.db.middleWarning ~= false then
		self:MiddleWarning(dropMsg .. layerMsg, 5)
	end
	if self.db.playSound ~= false and PlaySound then
		pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
	end
	-- mirror the incoming buff as a bar in an external boss-mod timer addon
	if self.db.bossModTimers ~= false then
		local bossmod = _G.DBM
		if bossmod and type(bossmod.CreatePizzaTimer) == "function" then
			pcall(bossmod.CreatePizzaTimer, bossmod, delay, dropMsg .. layerMsg)
		end
	end
	-- approximate the drop time when the second yell / aura never arrives
	local zid = zoneID
	C_Timer.After(delay + 4, function()
		local entry = zid and WB:LayerEntry(zid)
		if entry and (not entry[kind .. "Timer"] or entry[kind .. "Timer"] < GetServerTime() - 60) then
			WB:SetTimer(kind, zid, GetServerTime() - 4)
		end
	end)
	self:RefreshUI()
end

function WB:OnMonsterYell(msg, name)
	if type(msg) ~= "string" or type(name) ~= "string" then return end
	local kind = self:MatchYell(msg, name)
	if not kind then return end

	local _, _, zoneID = self:LayerContext()
	if kind:sub(-1) == "2" then
		-- second yell right before the buff lands
		local base = kind:sub(1, -2)
		local e = zoneID and self:LayerEntry(zoneID, true)
		if e then e[base .. "Yell2"] = GetServerTime() end
		return
	end
	if kind == "hellfire" then
		local e = zoneID and self:LayerEntry(zoneID, true)
		if e then e.hellfireRep = GetServerTime() end
		self:RefreshUI()
		return
	end
	-- first yell: announce + share so guild mates see the warning too
	self:FirstYell(kind, zoneID, "yell")
	if zoneID then self:BroadcastYell(kind, zoneID, D.dropDelay[kind]) end
end

-- ---------------------------------------------------------------------------
-- buff application + npc deaths (combat log)
-- ---------------------------------------------------------------------------
function WB:OnBuffApplied(destGUID, spellID)
	if destGUID ~= UnitGUID("player") then return end
	if spellID == D.songflowerSpell then
		self:SongflowerPicked()
		return
	end
	if D.dmfSpells[spellID] then
		self:Data().dmfTs = GetServerTime()
		self:RefreshUI()
		return
	end
	local kind = D.spellIDs[spellID]
	if not kind then return end
	local e, _, zoneID = self:LayerContext()
	if not e or not zoneID then return end
	if kind == "dragon" then
		-- ony and nef share the aura; whichever had the recent first yell wins
		local onyYell, nefYell = e.onyYell or 0, e.nefYell or 0
		if onyYell > nefYell and onyYell > GetServerTime() - 120 then kind = "ony"
		elseif nefYell > GetServerTime() - 120 then kind = "nef"
		else return end -- can't tell them apart, leave timers alone
	end
	self:SetTimer(kind, zoneID, GetServerTime())
	if self.db.chatBuffDropped ~= false then
		local key = DROP_KEYS[kind]
		if key and L[key] then self:Print(L[key]) end
	end
end

function WB:OnUnitDied(destGUID)
	local npcID = NpcFields(destGUID)
	if not npcID then return end
	local kind = D.buffNpcs[npcID]
	if not kind then return end
	local e, _, zoneID = self:LayerContext()
	if not e or not zoneID then return end
	if kind == "dragon" then
		-- the hidden npc despawns after both heads; no way to tell which
		return
	end
	e[kind .. "NpcDied"] = GetServerTime()
	self:BroadcastNpc(kind, zoneID)
	if self.db.chatBuffDropped ~= false then
		self:Print(format(L["%s buff NPC was killed, respawns in ~2 min."], self:BuffName(kind)))
	end
	self:RefreshUI()
end

function WB:OnCombatLog()
	if not CombatLogGetCurrentEventInfo then return end
	local _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID = CombatLogGetCurrentEventInfo()
	if subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED" then
		self:OnUnitDied(destGUID)
	elseif subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH" then
		self:OnBuffApplied(destGUID, spellID)
	end
end

-- ---------------------------------------------------------------------------
-- songflowers (felwood)
-- ---------------------------------------------------------------------------
function WB:ClosestFlower()
	if not (C_Map and C_Map.GetPlayerMapPosition and C_Map.GetBestMapForUnit) then return end
	local mapID = C_Map.GetBestMapForUnit("player")
	if mapID ~= D.felwoodMapID then return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local best, bestDist
	for i, f in ipairs(D.songflowers) do
		local dx, dy = f.x - pos.x, f.y - pos.y
		local d = dx * dx + dy * dy
		if not bestDist or d < bestDist then best, bestDist = i, d end
	end
	return best
end

function WB:SetFlower(zoneID, idx, ts, fromComm)
	local sf = self:Data().songflowers
	sf[zoneID] = sf[zoneID] or {}
	if (sf[zoneID][idx] or 0) >= ts then return end
	sf[zoneID][idx] = ts
	if not fromComm then self:BroadcastFlower(zoneID, idx, ts) end
	if self.db.chatBuffDropped ~= false then
		self:Print(format(L["Songflower %d picked, respawns in ~25 min."], idx))
	end
	self:RefreshUI()
end

function WB:SongflowerPicked()
	if not self.db.songflowers then return end
	if self._sfGrace and self._sfGrace > GetServerTime() then return end
	local idx = self:ClosestFlower()
	if not idx then return end
	self._sfGrace = GetServerTime() + 10
	self:SetFlower(self:CurrentLayerID() or 0, idx, GetServerTime())
end

-- ---------------------------------------------------------------------------
-- world pvp objectives (hellfire ramparts forts, spirit towers, beacons, halaa)
-- ---------------------------------------------------------------------------
-- live list of the client's world pvp areas; waitTime counts down to the next
-- possible capture on tbc objectives
function WB:WorldPvpList()
	if not (GetNumWorldPVPAreas and GetWorldPVPAreaInfo) then return end
	local out = {}
	for i = 1, GetNumWorldPVPAreas() do
		local _, name, isActive, _, wait = GetWorldPVPAreaInfo(i)
		if name and name ~= "" then
			out[#out + 1] = { name = name, wait = wait, active = isActive }
		end
	end
	if #out > 0 then return out end
end

-- worldstate ui rows (tower counts) while standing inside a pvp objective zone
function WB:WorldStateRows()
	if not (NUM_WORLD_STATE_UI and GetWorldStateUIInfo) then return end
	local out = {}
	for i = 1, NUM_WORLD_STATE_UI do
		local _, _, hidden, text = GetWorldStateUIInfo(i)
		if not hidden and type(text) == "string" and text ~= "" then
			out[#out + 1] = text
		end
	end
	if #out > 0 then return out end
end

-- ---------------------------------------------------------------------------
-- darkmoon faire / sayge / chronoboon
-- ---------------------------------------------------------------------------
local function FirstFriday(year, month)
	local ms = time({ year = year, month = month, day = 1, hour = 12 })
	local w = date("*t", ms).wday -- 1 = sunday .. 6 = friday
	return ms + ((6 - w) % 7) * 86400
end

-- returns status ("active"/"upcoming"), secs until the state flips, location
function WB:DmfInfo()
	local now = GetServerTime()
	local t = date("*t", now)
	local monthIdx = t.year * 12 + t.month
	local loc = function(mi) return D.dmfLocations[((mi - D.dmfAnchorMonth) % 3) + 1] end
	local start = FirstFriday(t.year, t.month)
	local close = start + 10 * 86400 -- setup friday + a week of faire
	if now >= start and now < close then
		return { status = "active", secs = close - now, loc = loc(monthIdx) }
	end
	if now < start then
		return { status = "upcoming", secs = start - now, loc = loc(monthIdx) }
	end
	local nm, ny = t.month + 1, t.year
	if nm > 12 then nm, ny = 1, ny + 1 end
	return { status = "upcoming", secs = FirstFriday(ny, nm) - now, loc = loc(ny * 12 + nm) }
end

-- remaining seconds on sayge's dark fortune (2h buff)
function WB:SaygeRemaining()
	local ts = self:Data().dmfTs
	if not ts then return 0 end
	return max(0, D.saygeDuration - (GetServerTime() - ts))
end

function WB:ChronoboonCount()
	if not (S.GetContainerNumSlots and S.GetContainerItemInfo) then return 0 end
	local n = 0
	for bag = 0, S.NUM_BAG_SLOTS do
		for slot = 1, (S.GetContainerNumSlots(bag) or 0) do
			local info = S.GetContainerItemInfo(bag, slot)
			if info and info.itemID == D.chronoboonID then n = n + (info.stackCount or 1) end
		end
	end
	return n
end

-- ---------------------------------------------------------------------------
-- mid-screen warning
-- ---------------------------------------------------------------------------
function WB:MiddleWarning(text, secs)
	if not self.warnFrame then
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetPoint("TOP", UIParent, "TOP", 0, -140)
		f:SetSize(600, 40)
		f.fs = S:FontString(f, 20, "OUTLINE", S.media.unitFont, nil, "CENTER")
		f.fs:SetPoint("CENTER")
		f.fs:SetTextColor(1, 0.85, 0.2)
		f:Hide()
		f:SetScript("OnUpdate", function()
			if f.until_ and GetServerTime() >= f.until_ then f:Hide() end
		end)
		self.warnFrame = f
	end
	self.warnFrame.fs:SetText(text)
	self.warnFrame.until_ = GetServerTime() + (secs or 5)
	self.warnFrame:Show()
end

-- ---------------------------------------------------------------------------
-- guid sources for layer detection (works even if IT is the primary feeder)
-- ---------------------------------------------------------------------------
function WB:FeedUnit(unit)
	local IT = self:IT()
	if IT and IT.CheckLayer then IT:CheckLayer(UnitGUID(unit)) end
end

-- ---------------------------------------------------------------------------
-- status helpers for the ui / tooltips
-- ---------------------------------------------------------------------------
function WB:BuffStatus(entry, kind)
	-- returns text, r, g, b
	if not entry then return "-", 0.6, 0.6, 0.6 end
	local rem = self:Remaining(kind, entry)
	if rem > 0 then return self:TimeString(rem), 1, 0.6, 0.2 end
	if entry[kind .. "Timer"] then return L["Ready"], 0.3, 1, 0.3 end
	return "-", 0.6, 0.6, 0.6
end

function WB:AppendTooltip()
	if self.db.minimapTimers == false then return end
	local layers = self:Layers()
	local keys = {}
	for k in pairs(layers) do keys[#keys + 1] = k end
	sort(keys)
	if #keys == 0 then return end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["World Buffs"], 1, 0.8, 0.3)
	for _, zoneID in ipairs(keys) do
		local e = layers[zoneID]
		local parts = {}
		for _, kind in ipairs(BUFF_ORDER) do
			local rem = self:Remaining(kind, e)
			if rem > 0 then
				parts[#parts + 1] = self:BuffName(kind) .. " " .. self:TimeString(rem)
			end
		end
		local num = self:LayerNum(zoneID)
		local label = format(L["Layer %d"], num > 0 and num or "?")
		GameTooltip:AddLine(label .. (#parts > 0 and (": |cffffaa00" .. table.concat(parts, " |r· |cffffaa00") .. "|r") or ""))
	end
	if self.db.dmf ~= false then
		local info = self:DmfInfo()
		if info then
			local loc = " |cff888888(" .. (L[info.loc] or info.loc) .. ")|r"
			local txt = info.status == "active" and ("|cff40ff40" .. L["open now"] .. "|r") or self:TimeString(info.secs)
			GameTooltip:AddLine(L["Darkmoon Faire"] .. ": " .. txt .. loc)
		end
	end
	if self.db.chronoboon ~= false then
		local n = self:ChronoboonCount()
		if n > 0 then GameTooltip:AddLine(L["Chronoboon Displacer"] .. ": |cff40ff40" .. n .. "|r") end
	end
end

-- ---------------------------------------------------------------------------
-- slash
-- ---------------------------------------------------------------------------
function WB:SetupSlash()
	local function handler(msg)
		msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		if msg == "timers" or msg == "" then
			WB:ToggleWindow()
		elseif msg == "sync" then
			WB:RequestSync()
			WB:Print(L["Sync requested."])
		elseif msg == "reset" then
			for _, e in pairs(WB:Layers()) do
				if type(e) == "table" then
					e.rendTimer, e.onyTimer, e.nefTimer, e.zanTimer = nil, nil, nil, nil
					e.onyNpcDied, e.nefNpcDied = nil, nil
				end
			end
			WB:Print(L["Buff timers reset."])
			WB:RefreshUI()
		else
			WB:ToggleWindow()
		end
	end
	SLASH_SENTINELUIWB1, SLASH_SENTINELUIWB2, SLASH_SENTINELUIWB3 = "/buffs", "/suibuffs", "/suib"
	SlashCmdList.SENTINELUIWB = handler
end

function WB:RefreshUI()
	if self.buffWindow and self.buffWindow.Refresh then self.buffWindow:Refresh() end
end

function WB:ToggleWindow()
	if self.CreateWindow then
		if not self.buffWindow then self:CreateWindow() end
		local f = self.buffWindow
		if f:IsShown() then f:Hide() else f:Show(); f:Refresh() end
	end
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------
function WB:Initialize()
	self.db = S.db.profile.worldbuffs
	-- migrate renamed option keys from older profiles
	if self.db.dbmTimers ~= nil then self.db.bossModTimers = self.db.dbmTimers self.db.dbmTimers = nil end
	self.faction = UnitFactionGroup("player")
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end

	self:RegisterEvent("CHAT_MSG_ADDON", function(_, _, prefix, msg, dist, sender)
		if prefix == PREFIX then WB:OnComm(_, _, msg, dist, sender) end
	end)
	self:RegisterEvent("CHAT_MSG_MONSTER_YELL", function(_, _, msg, name)
		WB:OnMonsterYell(msg, name)
	end)
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		WB:OnCombatLog()
	end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() WB:FeedUnit("target") end)
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() WB:FeedUnit("mouseover") end)
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, _, unit) WB:FeedUnit(unit) end)
	self:Delay(20, self.RequestSync, self)

	self:SetupSlash()
	self:Update()
end

function WB:Update()
	self.db = S.db.profile.worldbuffs
end
