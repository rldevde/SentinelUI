-- InstanceTracker: dungeon/raid instance log with stats (mobs, xp, gold,
-- rep, group), hourly lockout counter, trade log, alt tracking, level log,
-- auto NPC dialogue and instance-reset announcements.
local _, ns = ...
local S = ns.S
local L = S.L
local IT = S:NewModule("InstanceTracker")
ns.InstanceTracker = IT

local D = ns.InstanceTrackerData or {}

local _G = _G
local ipairs, pairs, sort, wipe, tinsert, tremove = ipairs, pairs, sort, wipe, table.insert, table.remove
local format, floor, ceil, min, max = string.format, math.floor, math.ceil, math.min, math.max
local time, date = time, date
local strmatch, strfind, gsub, tostring, tonumber = strmatch, strfind, string.gsub, tostring, tonumber
local GetServerTime = GetServerTime or time
local IsSecret = S.IsSecret
local pcall = pcall

IT.hourlyLimit = 5
IT.dailyLimit = 999
IT.maxRecordsKept = 250
IT.maxTradesKept = 300

-- ---------------------------------------------------------------------------
-- saved data (per realm): instances (newest first), trades, chars
-- ---------------------------------------------------------------------------
local function Realm()
	local r = GetRealmName and GetRealmName() or "?"
	return (r:gsub("%s+", ""))
end

function IT:Data()
	if type(SentinelUIInstanceDB) ~= "table" then SentinelUIInstanceDB = {} end
	local db = SentinelUIInstanceDB
	local realm = self.realm or Realm()
	self.realm = realm
	db[realm] = db[realm] or {}
	local d = db[realm]
	d.instances = d.instances or {}
	d.trades = d.trades or {}
	d.chars = d.chars or {}
	return d
end

function IT:Char()
	local d = self:Data()
	local name = UnitName("player") or "?"
	d.chars[name] = d.chars[name] or { instances = {}, savedInstances = {}, levelLog = {} }
	return d.chars[name]
end

-- all realms' char tables -> iterator callback(char, realm, data)
function IT:EachChar(func)
	for realm, d in pairs(SentinelUIInstanceDB or {}) do
		if type(d) == "table" and type(d.chars) == "table" then
			for char, cdata in pairs(d.chars) do
				func(char, realm, cdata)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function UnitNameShort(unit)
	local n, r = UnitName(unit)
	if r and r ~= "" then return n .. "-" .. r end
	return n or unit
end

function IT:TimeString(seconds, style)
	if not seconds or seconds < 0 then seconds = 0 end
	style = style or self.db.timeStringType or "medium"
	local d = floor(seconds / 86400)
	local h = floor((seconds % 86400) / 3600)
	local m = floor((seconds % 3600) / 60)
	local s = floor(seconds % 60)
	local parts = {}
	local limit = style == "long" and 4 or 2
	if d > 0 then parts[#parts + 1] = d .. (style == "short" and "d" or " " .. L["days"]) end
	if h > 0 and #parts < limit then parts[#parts + 1] = h .. (style == "short" and "h" or " " .. L["hours"]) end
	if m > 0 and #parts < limit then parts[#parts + 1] = m .. (style == "short" and "m" or " " .. L["minutes"]) end
	if s > 0 and #parts < limit then parts[#parts + 1] = s .. (style == "short" and "s" or " " .. L["seconds"]) end
	if #parts == 0 then return style == "short" and "0s" or ("0 " .. L["seconds"]) end
	return table.concat(parts, style == "short" and " " or " ")
end

function IT:Stamp(ts)
	ts = ts or GetServerTime()
	if (self.db.timeStampFormat or 12) == 24 then
		return date("%H:%M:%S", ts)
	end
	local h = tonumber(date("%I", ts))
	local ampm = date("%p", ts):lower()
	return format("%d:%s%s", h, date("%M", ts), ampm)
end

function IT:Ago(ts)
	local diff = GetServerTime() - ts
	if diff < 60 then return L["just now"] end
	if diff < 3600 then return format(L["%d min ago"], floor(diff / 60)) end
	if diff < 86400 then return format(L["%d hours ago"], floor(diff / 3600)) end
	return format(L["%d days ago"], floor(diff / 86400))
end

local function Comma(n)
	n = tonumber(n) or 0
	local s = tostring(floor(n))
	while true do
		local s2 = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if s2 == s then return s end
		s = s2
	end
end

-- number helper that tolerates retail "secret" values
local function Num(v, d)
	if IsSecret and IsSecret(v) then return d or 0 end
	return tonumber(v) or d or 0
end
IT.Comma = Comma

function IT:CoinString(money)
	money = tonumber(money) or 0
	if GetCoinTextureString then
		return GetCoinTextureString(money, 12)
	end
	local g = floor(money / 10000)
	local s = floor((money % 10000) / 100)
	local c = money % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
	return table.concat(out, " ")
end

function IT:LevelPct()
	local lvl = UnitLevel("player") or 1
	local max = UnitXPMax and UnitXPMax("player") or 0
	local cur = UnitXP and UnitXP("player") or 0
	if max > 0 then return lvl + cur / max end
	return lvl
end

local function ClassColor(file)
	local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

function IT:ColoredName(name, classFile, realm)
	local r, g, b = ClassColor(classFile)
	local txt = name or "?"
	if realm and realm ~= self.realm then txt = txt .. "-" .. realm end
	return format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, txt)
end

-- send one line to a chat channel type with validation
function IT:SendLine(msg, channel)
	channel = channel or "self"
	if channel == "self" or channel == "print" then
		self:Print(msg)
		return
	end
	if channel == "group" or channel == "party" then
		if IsInRaid and IsInRaid() then channel = "raid"
		elseif not (GetNumGroupMembers and GetNumGroupMembers() > 0) then
			self:Print(msg)
			return
		else channel = "party" end
	end
	if channel == "raid" and not (IsInRaid and IsInRaid()) then
		self:Print(msg)
		return
	end
	if channel == "party" and not (GetNumGroupMembers and GetNumGroupMembers() > 0) then
		self:Print(msg)
		return
	end
	local ok = pcall(SendChatMessage, msg, channel:upper())
	if not ok then self:Print(msg) end
end

local function StripColors(str)
	if not str then return "" end
	str = gsub(str, "|c%x%x%x%x%x%x%x%x", "")
	str = gsub(str, "|r", "")
	return str
end
IT.StripColors = StripColors

-- ---------------------------------------------------------------------------
-- zone helpers
-- ---------------------------------------------------------------------------
function IT:ZoneType(instanceID)
	local z = instanceID and D.zones and D.zones[instanceID]
	return z and z.t or nil
end

-- does this record count toward the hourly instance limit?
function IT:CountsForLockout(inst)
	if not inst or inst.isPvp then return false end
	if inst.type == "raid" or inst.type == "scenario" or inst.type == "delve" then
		local z = inst.instanceID and D.zones and D.zones[inst.instanceID]
		if z and z.nl then return false end
		return inst.type ~= "raid" -- raids without nl still count (ZG/AQ20)
	end
	return true
end

-- count instances in last hour / 24h; returns counts + oldest timestamps
function IT:LockoutInfo()
	local now = GetServerTime()
	local h, h24, hTS, h24TS = 0, 0, 0, 0
	for _, inst in ipairs(self:Data().instances) do
		if self:CountsForLockout(inst) then
			local t = inst.leftTime and inst.leftTime > 0 and inst.leftTime or inst.enteredTime
			if t and now - t < 3600 then
				h = h + 1
				if hTS == 0 or t < hTS then hTS = t end
			end
			if t and now - t < 86400 then
				h24 = h24 + 1
				if h24TS == 0 or t < h24TS then h24TS = t end
			end
		end
	end
	return h, h24, hTS, h24TS
end

function IT:LockoutString()
	local h, h24, hTS, h24TS = self:LockoutInfo()
	local now = GetServerTime()
	local nextFree
	if h24 >= self.dailyLimit and h24TS > 0 then
		nextFree = format(L["in %s (24h lockout active)"], self:TimeString(h24TS + 86400 - now, "short"))
	elseif h >= self.hourlyLimit and hTS > 0 then
		nextFree = format(L["in %s"], self:TimeString(hTS + 3600 - now, "short"))
	else
		nextFree = L["now"]
	end
	return format(L["You have entered %d instances in the past hour and %d in the past 24h. Next instance available %s."], h, h24, nextFree)
end

-- per-instance list of entries still inside the hour window
function IT:HourLockouts()
	local now = GetServerTime()
	local out = {}
	for _, inst in ipairs(self:Data().instances) do
		if self:CountsForLockout(inst) then
			local t = inst.leftTime and inst.leftTime > 0 and inst.leftTime or inst.enteredTime
			if t and now - t < 3600 then
				out[#out + 1] = { name = inst.instanceName, left = t + 3600 - now }
			elseif t and now - t >= 3600 then
				break
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- instance enter/leave
-- ---------------------------------------------------------------------------
function IT:Entered(isReload, isLogon)
	local inInst, instType = IsInInstance()
	if not inInst then return end
	if instType ~= "party" and instType ~= "raid" and instType ~= "pvp" and instType ~= "arena" and instType ~= "scenario" then
		return
	end
	local name, _, difficultyID, difficultyName, maxPlayers, _, _, instanceID = GetInstanceInfo()
	if not name or name == "" then
		self:Delay(1, self.Entered, self, isReload, isLogon)
		return
	end

	-- moved directly into another instance -> close the previous record first
	if self.inInstance and self.lastInstanceName ~= name then
		self:Left()
	elseif self.inInstance and self.lastInstanceName == name then
		return
	end

	local data = self:Data()

	-- reload / logon inside the same open record: reuse it instead of
	-- creating a duplicate that would inflate the hourly counter
	local last = data.instances[1]
	if (isReload or isLogon) and last and last.leftTime == 0 and last.instanceName == name then
		self.inInstance = last.enteredTime
		self.currentInstanceID = instanceID
		self.lastInstanceName = name
		self.isGhost = nil
		self:RecordGroup()
		if isLogon then
			self:Delay(3, function()
				IT:Print(format(L["You have logged in inside %s, if this is not a new instance type /itrack delete to remove it."], name))
			end)
		else
			self:Delay(3, function()
				IT:Print(format(L["UI Reload detected %s, loading last instance data instead of creating new."], name))
			end)
		end
		self:RefreshUI()
		return
	end

	local now = GetServerTime()
	local _, classFile = UnitClass("player")
	local r = {
		playerName = UnitName("player"),
		classFile = classFile,
		instanceName = name,
		instanceID = instanceID,
		difficultyID = difficultyID,
		type = instType == "pvp" and "bg" or instType,
		enteredTime = now,
		enteredLevel = UnitLevel("player") or 1,
		enteredLevelPct = self:LevelPct(),
		enteredXP = Num(UnitXP and UnitXP("player")),
		enteredMoney = Num(GetMoney and GetMoney()),
		leftTime = 0, leftMoney = 0,
		mobCount = 0, mobCountFromKill = 0,
		rawMoneyCount = 0, xpFromChat = 0,
		group = {}, rep = {},
	}
	if UnitLevel("player") < (self.maxLevel or 80) then
		r.xpForNextLevel = UnitXPMax and UnitXPMax("player") or 0
	end
	if r.type == "bg" or r.type == "arena" then
		r.isPvp = true
		r.honor = 0
		r.difficultyID = nil
		r.enteredMoney = nil
		r.mobCount = nil
		r.mobCountFromKill = nil
		r.rawMoneyCount = nil
	end

	tinsert(data.instances, 1, r)
	self.inInstance = now
	self.currentInstanceID = instanceID
	self.lastInstanceName = name
	self.isGhost = nil

	-- per-char instance count
	local char = self:Char()
	char.instances = char.instances or {}
	char.instances[instanceID or name] = (char.instances[instanceID or name] or 0) + 1

	self:RecordGroup()

	local h = select(1, self:LockoutInfo())
	if not isReload and not isLogon then
		local isRaidNoLock = r.type == "raid" and not self:CountsForLockout(r)
		if r.isPvp then
			if self.db.pvpEnteredMsg then self:EnteredMsg(r, h) end
		elseif isRaidNoLock then
			if self.db.raidEnteredMsg then self:Print(format(L["New instance %s, this raid doesn't count towards lockout."], name)) end
		elseif self.db.enteredMsg then
			self:EnteredMsg(r, h)
		end
	elseif isLogon then
		self:Delay(3, function()
			IT:Print(format(L["You have logged in inside %s (%d this hour), if this is not a new instance type /itrack delete to remove it."], name, h))
		end)
	elseif isReload then
		self:Delay(3, function()
			IT:Print(format(L["UI Reload detected %s, loading last instance data instead of creating new."], name))
		end)
	end
	self:RefreshUI()
end

function IT:EnteredMsg(r, h)
	local name = r.instanceName .. self:DifficultyTag(r)
	self:Print(format(L["New instance %s (%d this hour), click %s to open the log."], name, h, "|Hsuiit:log|h[X]|h"))
end

function IT:DifficultyTag(r)
	local d = r and r.difficultyID
	if not d then return "" end
	if d == 2 or d == 174 then return " (|cffff2222H|r)" end
	if d == 1 then return "" end
	return ""
end

function IT:RecordLeftStats()
	local r = self:Data().instances[1]
	if not r then return end
	local now = GetServerTime()
	r.leftTime = now
	r.leftLevel = UnitLevel("player") or r.enteredLevel
	r.leftLevelPct = self:LevelPct()
	r.leftXP = Num(UnitXP and UnitXP("player"), r.leftXP)
	r.leftMoney = Num(GetMoney and GetMoney(), r.leftMoney)
end

function IT:Left()
	if not self.inInstance then return end
	self:RecordLeftStats()
	self.inInstance = nil
	self.currentInstanceID = nil
	self.lastInstanceName = nil
	self.lastNpcID = nil
	if self.db.instanceStatsOutput then
		self:Delay(0.7, self.ShowStats, self, 1, nil)
	end
	self:RefreshUI()
end

-- ---------------------------------------------------------------------------
-- stat capture
-- ---------------------------------------------------------------------------
function IT:Current()
	if not self.inInstance then return nil end
	return self:Data().instances[1]
end

function IT:OnXpGain(msg)
	local r = self:Current()
	if not r then return end
	local xp = tonumber(strmatch(msg, "(%d+)"))
	if not xp then return end
	r.xpFromChat = (r.xpFromChat or 0) + xp
	if not r.isPvp then
		r.mobCount = (r.mobCount or 0) + 1
	end
end

function IT:OnMoney(msg)
	local r = self:Current()
	if not r or r.isPvp then return end
	local total = 0
	local g = tonumber(strmatch(msg, GOLD_AMOUNT and GOLD_AMOUNT:gsub("%%d", "(%%d+)") or "(%d+)"))
	local s = tonumber(strmatch(msg, SILVER_AMOUNT and SILVER_AMOUNT:gsub("%%d", "(%%d+)") or "(%d+)"))
	local c = tonumber(strmatch(msg, COPPER_AMOUNT and COPPER_AMOUNT:gsub("%%d", "(%%d+)") or "(%d+)"))
	if not g and not s and not c then
		-- generic fallback: largest number is probably gold
		for num in msg:gmatch("(%d+)") do
			local n = tonumber(num)
			if n and n > total then total = n end
		end
		r.rawMoneyCount = (r.rawMoneyCount or 0) + total
		return
	end
	total = (g or 0) * 10000 + (s or 0) * 100 + (c or 0)
	r.rawMoneyCount = (r.rawMoneyCount or 0) + total
end

-- parse "Reputation with %s increased by %d." style globals
local function DeformatRep(msg)
	local increased = FACTION_STANDING_INCREASED or "Reputation with %s increased by %d."
	local decreased = FACTION_STANDING_DECREASED or "Reputation with %s decreased by %d."
	local pat = increased:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)"):gsub("%.", "%%.")
	local fac, amt = msg:match(pat)
	if fac and amt then return fac, tonumber(amt) end
	pat = decreased:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)"):gsub("%.", "%%.")
	fac, amt = msg:match(pat)
	if fac and amt then return fac, -tonumber(amt) end
	return nil
end

function IT:OnRepChange(msg)
	local r = self:Current()
	if not r then return end
	local fac, amt = DeformatRep(msg)
	if not fac or not amt then return end
	r.rep = r.rep or {}
	r.rep[fac] = (r.rep[fac] or 0) + amt
end

function IT:OnHonorGain(msg)
	local r = self:Current()
	if not r then return end
	local n = tonumber(strmatch(msg, "(%d+%.?%d*)"))
	if n then r.honor = (r.honor or 0) + n end
end

function IT:OnLoot(msg, self2)
	local r = self:Current()
	if not r then return end
	local link = strmatch(msg, "|H(item:[^|]+)|h")
	if not link then return end
	local itemID = tonumber(strmatch(link, "item:(%d+)"))
	if not itemID then return end
	local tracked = (self2 and D.lootCurrency and D.lootCurrency[itemID])
		or (D.lootCurrencyAll and D.lootCurrencyAll[itemID])
	if not tracked then return end
	local amount = tonumber(strmatch(msg, "x(%d+)")) or 1
	r.currencies = r.currencies or {}
	local c = r.currencies[itemID]
	if not c then
		c = { count = 0 }
		r.currencies[itemID] = c
	end
	c.count = c.count + amount
	c.name = GetItemInfo and select(1, GetItemInfo(itemID)) or nil
	c.icon = select(5, GetItemInfoInstant and GetItemInfoInstant(itemID) or 0) or nil
end

local function NpcIDFromGUID(guid)
	if not guid or type(guid) ~= "string" then return end
	-- Creature-0-server-instance-zoneID-npcID-spawnUID
	local utype, _, _, _, zoneID, npcID = guid:match("([^-]+)-([^-]+)-([^-]+)-([^-]+)-([^-]+)-([^-]+)")
	if utype == "Creature" or utype == "Cast" or utype == "Vehicle" then
		return tonumber(npcID), tonumber(zoneID), utype
	end
end

function IT:OnUnitDied(destGUID)
	local npcID = NpcIDFromGUID(destGUID)
	if not npcID or (D.critters and D.critters[npcID]) then return end
	self.mobsSinceLevel = (self.mobsSinceLevel or 0) + 1
	local r = self:Current()
	if not r or r.isPvp then return end
	r.mobCountFromKill = (r.mobCountFromKill or 0) + 1
end

-- same-instance merge via zone id from npc guids
function IT:ParseGUID(guid)
	self:CheckLayer(guid)
	if not self.db.detectSameInstance then return end
	local r = self:Current()
	if not r or r.isPvp then return end
	local npcID, zoneID = NpcIDFromGUID(guid)
	if not npcID or not zoneID then return end
	if D.companions and D.companions[npcID] then return end
	local data = self:Data()
	if data.instances[2] and data.instances[2].zoneID == zoneID and not r.zoneID then
		self:MergeLastInstances()
		return
	end
	if not r.zoneID then
		if self.lastNpcID == npcID then
			r.zoneID = zoneID
			r.guid = guid
		end
		self.lastNpcID = npcID
	end
end

-- ---------------------------------------------------------------------------
-- layer detection: the shard id embedded in npc
-- guids identifies which server layer you are standing on
-- ---------------------------------------------------------------------------
function IT:CheckLayer(guid)
	if self.inInstance then return end
	local npcID, zoneID, utype = NpcIDFromGUID(guid)
	if not zoneID or zoneID == 0 or not npcID then return end
	if utype ~= "Creature" then return end
	if D.companions and D.companions[npcID] then return end
	if D.critters and D.critters[npcID] then return end
	local data = self:Data()
	data.layers = data.layers or {}
	local e = data.layers[zoneID]
	if not e then
		-- cap stored layer ids (mirrors the 20 layer cap used for launch realms)
		local count = 0
		for _ in pairs(data.layers) do count = count + 1 end
		if count >= 20 then return end
		e = { firstSeen = GetServerTime() }
		data.layers[zoneID] = e
	end
	e.lastSeen = GetServerTime()
	e.guid = guid
	if self.currentLayerID ~= zoneID then
		self.currentLayerID = zoneID
		self:UpdateLayerFrame()
		if self.db.shareLayer then self:BroadcastLayer() end
	end
end

function IT:LayerNum(zoneID)
	local keys = {}
	for k in pairs(self:Data().layers or {}) do keys[#keys + 1] = k end
	sort(keys)
	for i, k in ipairs(keys) do if k == zoneID then return i end end
	return 0
end

function IT:CurrentLayer()
	if self.currentLayerID then return self:LayerNum(self.currentLayerID) end
end

function IT:BroadcastLayer()
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or not self.currentLayerID then return end
	local channel = IsInRaid and IsInRaid() and "RAID" or (IsInGroup and IsInGroup() and "PARTY" or nil)
	if channel then
		pcall(C_ChatInfo.SendAddonMessage, "SUITIT", "layer " .. self.currentLayerID, channel)
	end
end

-- layers the group members report to us (session only)
IT.friendLayers = IT.friendLayers or {}

function IT:UpdateLayerFrame()
	local f = self.layerFrame
	if not f then return end
	local num = self:CurrentLayer()
	f.fs:SetText(num and num > 0 and format(L["Layer %d"], num) or L["Layer ?"])
end

function IT:SetupLayerFrame()
	local f = CreateFrame("Frame", "SentinelUILayerFrame", UIParent)
	f:SetSize(90, 22)
	f:SetPoint("CENTER", UIParent, "TOP", 0, -220)
	S:CreateBackdrop(f, "Default")
	f.fs = S:FontString(f, 11, "OUTLINE", S.media.unitFont, nil, "CENTER")
	f.fs:SetPoint("CENTER")
	f.fs:SetText(L["Layer ?"])
	f:EnableMouse(true)
	f:SetScript("OnEnter", function()
		GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Instance Tracker"], 1, 1, 1)
		local n = IT:CurrentLayer()
		GameTooltip:AddLine(n and format(L["You are currently on layer %d."], n) or L["No layer detected yet, target an NPC."], 0.9, 0.9, 0.95)
		for id, e in pairs(IT.friendLayers) do
			local num = IT:LayerNum(id)
			GameTooltip:AddLine(format(L["%s is on layer %s"], id, num > 0 and num or "?"), 0.6, 0.6, 0.65)
		end
		GameTooltip:AddLine(L["Move with /sui move"], 0.5, 0.5, 0.55)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	S:CreateMover(f, "instancelayer", L["Layer"], { "TOP", "UIParent", "TOP", 0, -220 }, "instancetracker")
	self.layerFrame = f
	self:UpdateLayerFrame()
	f:SetShown(self.db.layerFrame == true)
end

function IT:PrintLayers()
	local data = self:Data()
	if not data.layers or not next(data.layers) then
		self:Print(L["No layers detected yet, target an NPC."])
		return
	end
	local keys = {}
	for k in pairs(data.layers) do keys[#keys + 1] = k end
	sort(keys)
	self:Print(L["Detected layers:"])
	for i, k in ipairs(keys) do
		local e = data.layers[k]
		local cur = (k == self.currentLayerID) and (" |cff00ff00(" .. L["current"] .. ")|r") or ""
		self:Print(format("  " .. L["Layer %d"] .. " |cff888888(ID %s, %s)|r%s", i, tostring(k), e.lastSeen and self:Ago(e.lastSeen) or "?", cur))
	end
end

function IT:MergeLastInstances()
	local data = self:Data()
	local a, b = data.instances[1], data.instances[2]
	if not a or not b then return end
	for _, k in ipairs({ "mobCount", "mobCountFromKill", "rawMoneyCount", "xpFromChat" }) do
		b[k] = (b[k] or 0) + (a[k] or 0)
	end
	b.oldZoneID = a.zoneID
	tremove(data.instances, 1)
	self.inInstance = GetServerTime()
	self.lastMerge = GetServerTime()
	if not (a.type == "raid" and self.db.noRaidInstanceMergeMsg) then
		self:Print(format(L["Same instance ID as last detected %s, merging database entries."], a.instanceName or "?"))
	end
	self:RefreshUI()
end

function IT:RecordGroup()
	local r = self:Current()
	if not r then return end
	r.group = r.group or {}
	local total, count = UnitLevel("player") or 0, 1
	local function add(unit)
		local n, rl = UnitName(unit)
		if not n then return end
		if rl and rl ~= "" then n = n .. "-" .. rl end
		local _, cf = UnitClass(unit)
		local g = GetGuildInfo and select(1, GetGuildInfo(unit)) or nil
		r.group[n] = { level = UnitLevel(unit) or 0, classFile = cf, guild = g }
		if unit ~= "player" then
			total = total + (UnitLevel(unit) or 0)
			count = count + 1
		end
	end
	add("player")
	local prefix, n = "party", GetNumGroupMembers and GetNumGroupMembers() or 0
	if IsInRaid and IsInRaid() then prefix = "raid" n = GetNumGroupMembers() end
	for i = 1, n do
		local u = prefix .. i
		if UnitExists(u) then add(u) end
	end
	r.groupAverage = floor(total / count * 10) / 10
end

-- ---------------------------------------------------------------------------
-- stats output
-- ---------------------------------------------------------------------------
function IT:StatLine(idx, showAll)
	local r = self:Data().instances[idx or 1]
	if not r then return nil end
	local db = self.db
	local parts = {}
	parts[#parts + 1] = "|cff00c800" .. L["Dungeon"] .. ": " .. (r.instanceName or "?") .. self:DifficultyTag(r) .. "|r"
	if r.isPvp then
		if db.instanceStatsOutputHK or showAll then
			parts[#parts + 1] = L["Honor"] .. ": " .. Comma(r.honor or 0)
		end
		if r.battleground then
			parts[#parts + 1] = (r.battleground.win and "|cff44dd66" .. L["Won"] or "|cffff5555" .. L["Lost"]) .. "|r"
		end
		return table.concat(parts, " ")
	end
	local mobs = (r.mobCount and r.mobCount > 0) and r.mobCount or r.mobCountFromKill
	if (db.instanceStatsOutputMobCount or showAll) and mobs and mobs > 0 then
		parts[#parts + 1] = L["Mobs"] .. ": " .. Comma(mobs)
	end
	local secs = (r.leftTime and r.leftTime > 0) and (r.leftTime - r.enteredTime) or (GetServerTime() - r.enteredTime)
	if (db.instanceStatsOutputXP or showAll) and r.xpFromChat and r.xpFromChat > 0 then
		local pct = ""
		if r.xpForNextLevel and r.xpForNextLevel > 0 and db.instanceStatsOutputXPPercent then
			pct = format(" (%.1f%%)", r.xpFromChat / r.xpForNextLevel * 100)
		end
		parts[#parts + 1] = L["XP"] .. ": " .. Comma(r.xpFromChat) .. pct
	end
	if (db.instanceStatsOutputXpPerHour or showAll) and r.xpFromChat and r.xpFromChat > 0 and secs > 60 then
		parts[#parts + 1] = L["XP/Hour"] .. ": " .. Comma(floor(r.xpFromChat / secs * 3600))
	end
	if (db.instanceStatsOutputAverageXP or showAll) and r.xpFromChat and mobs and mobs > 0 then
		parts[#parts + 1] = L["Average XP/Mob"] .. ": " .. Comma(floor(r.xpFromChat / mobs))
	end
	if db.instanceStatsOutputTime or showAll then
		parts[#parts + 1] = L["Time"] .. ": " .. self:TimeString(secs, "short")
	end
	if (db.instanceStatsOutputAverageGroupLevel or showAll) and r.groupAverage then
		parts[#parts + 1] = L["Average Group Level"] .. ": " .. r.groupAverage
	end
	if db.instanceStatsOutputGold or showAll then
		local gold = r.rawMoneyCount or ((r.leftMoney or 0) - (r.enteredMoney or 0))
		if gold and gold > 0 then
			parts[#parts + 1] = L["Gold"] .. " " .. self:CoinString(gold)
		end
	end
	if idx == 1 and r.xpFromChat and r.xpFromChat > 0 and r.xpForNextLevel and r.xpForNextLevel > 0 then
		if db.instanceStatsOutputRunsPerLevel or showAll then
			parts[#parts + 1] = L["Runs per level"] .. ": " .. format("%.1f", r.xpForNextLevel / r.xpFromChat)
		end
		if db.instanceStatsOutputRunsNextLevel or showAll then
			local cur = UnitXP and UnitXP("player") or 0
			local remaining = r.xpForNextLevel - cur
			if remaining > 0 then
				parts[#parts + 1] = L["Runs until next level"] .. ": " .. format("%.1f", remaining / r.xpFromChat)
			end
		end
	end
	if (db.instanceStatsOutputRep or showAll) and r.rep then
		local rep = {}
		for fac, amt in pairs(r.rep) do
			if amt ~= 0 then rep[#rep + 1] = format("%s %+d", fac, amt) end
		end
		sort(rep)
		if #rep > 0 then parts[#parts + 1] = L["Rep"] .. ": (" .. table.concat(rep, ", ") .. ")" end
	end
	if (db.instanceStatsOutputCurrency or showAll) and r.currencies then
		for _, c in pairs(r.currencies) do
			if c.count and c.count > 0 then
				parts[#parts + 1] = format("%s +%d", c.name or L["Currency"], c.count)
			end
		end
	end
	return table.concat(parts, " ")
end

function IT:ShowStats(idx, output, showAll, prefix)
	local r = self:Data().instances[idx or 1]
	if not r then return end
	if self.db.statsOnlyWhenActivity and not showAll then
		local act = (r.xpFromChat or 0) + (r.mobCountFromKill or 0) + (r.rawMoneyCount or 0) + (r.honor or 0)
		if act <= 0 then return end
	end
	local line = self:StatLine(idx, showAll)
	if not line then return end
	output = output or self.db.instanceStatsOutputWhere or "self"
	prefix = prefix or (self.inInstance and L["Current Dungeon"] or L["Last Dungeon"])
	local msg = prefix .. ": " .. line
	if output == "group" then
		if IsInRaid and IsInRaid() then
			if self.db.showStatsInRaid then self:SendLine(StripColors(msg), "raid")
			elseif self.db.printRaidInstead then self:Print(msg) end
		elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then
			self:SendLine(StripColors(msg), "party")
		else
			self:Print(msg)
		end
	elseif output == "self" or output == "send" then
		self:Print(msg)
	else
		self:SendLine(StripColors(msg), output)
	end
end

-- ---------------------------------------------------------------------------
-- lockout data for the char record (weekly saved instances)
-- ---------------------------------------------------------------------------
function IT:RecordLockouts()
	local char = self:Char()
	char.savedInstances = wipe(char.savedInstances or {})
	if not GetNumSavedInstances or not GetSavedInstanceInfo then return end
	local now = GetServerTime()
	for i = 1, GetNumSavedInstances() or 0 do
		local name, id, reset, _, locked, _, _, _, _, diffName = GetSavedInstanceInfo(i)
		if name and locked then
			char.savedInstances[id or i] = {
				name = name, resetTime = now + (reset or 0),
				difficulty = diffName, locked = true,
			}
		end
	end
end

-- ---------------------------------------------------------------------------
-- char record (alts window data)
-- ---------------------------------------------------------------------------
function IT:RecordCharData()
	local char = self:Char()
	local name = UnitName("player") or "?"
	char.realm = self.realm or Realm()
	char.level = UnitLevel("player") or 1
	char.classFile = select(2, UnitClass("player"))
	char.class = UnitClass("player")
	char.race = select(2, UnitRace("player"))
	char.raceLocalized = UnitRace("player")
	char.sex = UnitSex("player")
	char.currentXP = UnitXP and UnitXP("player") or 0
	char.maxXP = UnitXPMax and UnitXPMax("player") or 0
	char.restedXP = GetXPExhaustion and GetXPExhaustion() or 0
	char.resting = IsResting and IsResting() or false
	char.time = GetServerTime()
	char.money = GetMoney and GetMoney() or 0
	char.guild, char.guildRankName = GetGuildInfo and GetGuildInfo("player") or nil
	-- attunement quests
	if IsQuestFlaggedCompleted then
		for _, a in ipairs(D.attunements or {}) do
			if not char[a.key] then
				local done, all = true, a.all
				for _, q in ipairs(a.quests) do
					local ok, c = pcall(IsQuestFlaggedCompleted, q)
					if ok and c then
						if not all then char[a.key] = true break end
					elseif all then
						done = false break
					end
				end
				if all and done then char[a.key] = true end
			end
		end
	end
	-- keyring attunement items (classic bag keyring)
	if KeyRingButtonIDToInvSlotID and GetInventoryItemID then
		for slot = 1, 32 do
			local slotID = KeyRingButtonIDToInvSlotID(slot)
			if slotID then
				local itemID = GetInventoryItemID("player", slotID)
				local flag = itemID and D.keyAttunements and D.keyAttunements[itemID]
				if flag then char[flag] = true end
			end
		end
	end
	self:RecordLockouts()
end

-- remove every char below level N across all realms
function IT:TrimCharsBelow(level)
	level = tonumber(level) or 1
	local removed = 0
	self:EachChar(function(char, realm, cdata)
		if (cdata.level or 1) <= level then
			SentinelUIInstanceDB[realm].chars[char] = nil
			removed = removed + 1
		end
	end)
	if removed > 0 then
		self:Print(format(L["Removed %d characters below level %d from the database."], removed, level))
	end
	self:RefreshUI()
end

function IT:TrimDatabase()
	local inst = self:Data().instances
	for i = #inst, self.maxRecordsKept + 1, -1 do tremove(inst, i) end
	local tr = self:Data().trades
	for i = #tr, self.maxTradesKept + 1, -1 do tremove(tr, i) end
end

function IT:DeleteInstance(idx)
	local r = self:Data().instances[idx]
	if not r then return end
	local char = self:Char()
	if r.instanceID and char.instances and char.instances[r.instanceID] then
		char.instances[r.instanceID] = max(0, (char.instances[r.instanceID] or 1) - 1)
	end
	self:Print(format(L["Deleted instance %s (%s ago) from the database."], r.instanceName or "?", self:Ago(r.enteredTime or GetServerTime())))
	tremove(self:Data().instances, idx)
	self:RefreshUI()
end

function IT:ResetAllInstances()
	wipe(self:Data().instances)
	self:Print(L["All instance log data has been deleted."])
	self:RefreshUI()
end

-- ---------------------------------------------------------------------------
-- trade log (money only)
-- ---------------------------------------------------------------------------
function IT:OnTradeShow()
	self.tradeWho = UnitName("npc") or UnitName("target") or "?"
	local cf = select(2, UnitClass("npc")) or select(2, UnitClass("target"))
	self.tradeWhoClass = cf
end

function IT:OnTradeComplete()
	if not self.tradeMoneyActive then return end
	local pm = self.tradePlayerMoney or 0
	local tm = self.tradeTargetMoney or 0
	if pm <= 0 and tm <= 0 then return end
	tinsert(self:Data().trades, 1, {
		playerMoney = pm, targetMoney = tm,
		tradeWho = self.tradeWho, tradeWhoClass = self.tradeWhoClass,
		where = GetZoneText and GetZoneText() or "",
		time = GetServerTime(),
	})
	self:TrimDatabase()
	if self.db.showMoneyTradedChat then
		if pm > 0 then
			self:Print(format(L["Gave %s to %s."], self:CoinString(pm), "|Hsuiit:trades|h" .. (self.tradeWho or "?") .. "|h"))
		end
		if tm > 0 then
			self:Print(format(L["Received %s from %s."], self:CoinString(tm), "|Hsuiit:trades|h" .. (self.tradeWho or "?") .. "|h"))
		end
	end
	self.tradeMoneyActive = nil
	self:RefreshUI()
end

-- ---------------------------------------------------------------------------
-- auto gossip
-- ---------------------------------------------------------------------------
local gossipFrame = CreateFrame("Frame")
gossipFrame:RegisterEvent("GOSSIP_SHOW")
gossipFrame:SetScript("OnEvent", function()
	if not IT.db then return end
	local guid = UnitGUID and UnitGUID("npc")
	if not guid then return end
	local npcID = NpcIDFromGUID(guid)
	local rule = npcID and D.autoGossip and D.autoGossip[npcID]
	if not rule then return end
	if rule.opt and IT.db[rule.opt] == false then return end
	if rule.inInstance and not (IsInInstance and select(1, IsInInstance())) then return end
	if rule.quest then
		local ok, done = pcall(IsQuestFlaggedCompleted, rule.quest)
		if not (ok and done) then return end
	end
	-- pick first gossip option
	if C_GossipInfo and C_GossipInfo.SelectOptionByIndex then
		pcall(C_GossipInfo.SelectOptionByIndex, 0)
	elseif SelectGossipOption then
		pcall(SelectGossipOption, 1)
	end
end)

-- ---------------------------------------------------------------------------
-- system message handling (instance reset / saved / too many instances)
-- ---------------------------------------------------------------------------
function IT:OnSystemMsg(msg)
	if not msg then return end
	if INSTANCE_RESET_SUCCESS and msg:match(INSTANCE_RESET_SUCCESS:gsub("%%s", "(.+)"):gsub("%.", "%%.")) then
		local inst = msg:match(INSTANCE_RESET_SUCCESS:gsub("%%s", "(.+)"):gsub("%.", "%%."))
		if self.db.instanceResetMsg and inst then
			if IsInGroup and (IsInGroup() or IsInRaid()) and (UnitIsGroupLeader and UnitIsGroupLeader("player")) then
				self:SendLine(format(L["%s has been reset."], inst), "party")
			end
		end
	end
	if INSTANCE_SAVED and msg:find(INSTANCE_SAVED:sub(1, 8)) then
		self:Delay(1, self.RecordLockouts, self)
		self:Delay(10, self.RecordLockouts, self)
	end
	if TRANSFER_ABORT_TOO_MANY_INSTANCES and msg:find(TRANSFER_ABORT_TOO_MANY_INSTANCES:sub(1, 15)) then
		self:Delay(0.2, function() IT:Print(IT:LockoutString()) end)
	end
end

-- ---------------------------------------------------------------------------
-- ticker: notify when a lockout slot frees up + refresh timer displays
-- ---------------------------------------------------------------------------
function IT:Tick()
	if not self.inInstance then
		local h = select(1, self:LockoutInfo())
		if h < self.hourlyLimit and self.wasHourCapped then
			self.wasHourCapped = nil
			if GetServerTime() - (self.lastMerge or 0) > 3 then
				self:Print(format(L["A new instance can be entered now (%d this hour)."], h))
			end
		elseif h >= self.hourlyLimit then
			self.wasHourCapped = true
		end
	end
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
function IT:OnEnterWorld(_, isLogon, isReload)
	self:Delay(0.5, function()
		local inInst = IsInInstance()
		if inInst then
			IT:Entered(isReload, isLogon)
		elseif IT.inInstance and not isReload then
			IT:Left()
		else
			-- logged out inside an instance and came back outside:
			-- close the still-open record so it stops looking "current"
			local last = IT:Data().instances[1]
			if last and last.leftTime == 0 and not inInst then
				IT:RecordLeftStats()
			end
		end
	end)
	if isLogon then
		self:Delay(3, self.RecordLockouts, self)
		self:Delay(5, self.RecordCharData, self)
	end
end

function IT:Initialize()
	self.db = S.db.profile.instancetracker
	self.realm = Realm()
	self.maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or MAX_PLAYER_LEVEL or 70
	self:Data()
	self:Char()
	self:TrimDatabase()
	self:RecordCharData()

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
	self:RegisterEvent("PLAYER_LEAVING_WORLD", function()
		if IT.inInstance and UnitIsGhost and UnitIsGhost("player") then
			IT.isGhost = true
		end
	end)
	self:RegisterEvent("PLAYER_CAMPING", function()
		if IT.inInstance then
			IT:RecordLeftStats()
			IT:ShowStats(1, nil)
		end
		IT:RecordLockouts()
	end)
	self:RegisterEvent("PLAYER_LOGOUT", function() IT:RecordLockouts() end)
	self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(_, _, msg) IT:OnXpGain(msg) end)
	self:RegisterEvent("CHAT_MSG_MONEY", function(_, _, msg) IT:OnMoney(msg) end)
	self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", function(_, _, msg) IT:OnRepChange(msg) end)
	self:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN", function(_, _, msg) IT:OnHonorGain(msg) end)
	self:RegisterEvent("CHAT_MSG_LOOT", function(_, _, msg, _, _, _, _, _, _, _, _, guid)
		IT:OnLoot(msg, guid ~= nil and guid == (UnitGUID and UnitGUID("player")))
	end)
	self:RegisterEvent("CHAT_MSG_SYSTEM", function(_, _, msg) IT:OnSystemMsg(msg) end)
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		local _, sub, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
		if sub == "UNIT_DIED" then
			IT:OnUnitDied(destGUID)
		end
		-- feed every npc guid through the merge detector
		IT:ParseGUID(destGUID)
	end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
		IT:ParseGUID(UnitGUID and UnitGUID("target"))
	end)
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
		IT:ParseGUID(UnitGUID and UnitGUID("mouseover"))
	end)
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, _, unit)
		IT:ParseGUID(UnitGUID and UnitGUID(unit))
	end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() IT:RecordGroup() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() IT:RecordGroup() end)
	self:RegisterEvent("ENCOUNTER_END", function()
		if RequestRaidInfo then pcall(RequestRaidInfo) end
		IT:Delay(3, IT.RecordLockouts, IT)
	end)
	self:RegisterEvent("UPDATE_INSTANCE_INFO", function() IT:RecordLockouts() end)
	self:RegisterEvent("QUEST_TURNED_IN", function()
		IT.questsSinceLevel = (IT.questsSinceLevel or 0) + 1
		IT:Delay(5, IT.RecordLockouts, IT)
		IT:RecordCharData()
	end)
	self:RegisterEvent("PLAYER_LEVEL_UP", function(_, _, newLevel)
		IT:Delay(2, function()
			local r = IT:Current()
			if r then r.xpForNextLevel = UnitXPMax and UnitXPMax("player") or r.xpForNextLevel end
		end)
		IT:RecordCharData()
		IT:OnLevelUp(newLevel)
	end)
	self:RegisterEvent("PLAYER_XP_UPDATE", function() IT:RecordCharData() end)
	self:RegisterEvent("PLAYER_UPDATE_RESTING", function() IT:RecordCharData() end)
	self:RegisterEvent("PLAYER_GUILD_UPDATE", function() IT:RecordCharData() end)
	self:RegisterEvent("PLAYER_MONEY", function() IT:RecordCharData() end)
	self:RegisterEvent("UPDATE_BATTLEFIELD_SCORE", function() IT:RecordBGStats() end)
	-- trade events
	self:RegisterEvent("TRADE_SHOW", function() IT:OnTradeShow() end)
	self:RegisterEvent("TRADE_MONEY_CHANGED", function()
		IT.tradeMoneyActive = true
		IT.tradePlayerMoney = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
		IT.tradeTargetMoney = GetTargetTradeMoney and GetTargetTradeMoney() or 0
	end)
	self:RegisterEvent("TRADE_REQUEST_CANCEL", function() IT.tradeMoneyActive = nil end)
	self:RegisterEvent("UI_INFO_MESSAGE", function(_, _, a, b)
		local msg = type(b) == "string" and b or a
		if msg == ERR_TRADE_COMPLETE or (msg and msg:find("Trade complete")) then
			IT:OnTradeComplete()
		end
	end)
	self:RegisterEvent("TIME_PLAYED_MSG", function(_, _, total)
		IT.playedCache = total
		IT.playedCacheWhen = GetServerTime()
	end)
	-- version / group comms
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, "SUITIT")
		self:RegisterEvent("CHAT_MSG_ADDON", function(_, _, prefix, msg, _, sender)
			if prefix ~= "SUITIT" then return end
			local cmd, a = msg:match("^(%S+)%s*(%S*)")
			if cmd == "douse" and IT.inInstance then
				local r = IT:Data().instances[1]
				if r then
					r.douses = r.douses or {}
					r.douses[tonumber(a) or 0] = { name = sender, time = GetServerTime() }
				end
			elseif cmd == "layer" and a and a ~= "" then
				IT.friendLayers[Ambiguate and Ambiguate(sender, "short") or sender] = tonumber(a)
			elseif cmd == "ver" and a and a ~= "" then
				local remote = tonumber(a)
				local mine = tonumber((S.version or ""):match("%d+%.?%d*")) or 0
				if remote and remote > mine and not IT.newerVersionWarned then
					IT.newerVersionWarned = true
					IT:Print(format(L["A newer version of SentinelUI (v%s) is running in your group, consider updating."], tostring(a)))
				end
			end
		end)
		-- lightweight version broadcast when joining a group
		self:RegisterEvent("GROUP_JOINED", function()
			-- joining a group can layer-hop us: forget the old detection
			IT.currentLayerID = nil
			IT:UpdateLayerFrame()
			IT:BroadcastVersion()
			IT:Delay(30, IT.BroadcastLayer, IT)
		end)
		self:Delay(10, function() IT:BroadcastVersion() end)
	end
	-- 1s ticker for lockout-free notices
	C_Timer.NewTicker(1, function() IT:Tick() end)
	-- refresh visible timers every minute
	C_Timer.NewTicker(60, function() IT:RefreshUI() end)

	self:SetupMinimapButton()
	self:SetupSlash()
	self:SetupClickLinks()
	self:SetupLayerFrame()
	if IT.LevelLogInit then IT:LevelLogInit() end
end

function IT:BroadcastVersion()
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	local channel = IsInRaid and IsInRaid() and "RAID" or (IsInGroup and IsInGroup() and "PARTY" or nil)
	if channel then
		pcall(C_ChatInfo.SendAddonMessage, "SUITIT", "ver " .. tostring(S.version or "0"), channel)
	end
end

function IT:RecordBGStats()
	local r = self:Current()
	if not r or not r.isPvp then return end
	if not GetNumBattlefieldScores or not GetBattlefieldScore then return end
	for i = 1, GetNumBattlefieldScores() or 0 do
		local name, kb, hk, deaths, _, faction, _, _, _, _, dmg, heal = GetBattlefieldScore(i)
		if name == UnitName("player") then
			r.battleground = r.battleground or {}
			r.battleground.kb = kb
			r.battleground.hk = hk
			r.battleground.deaths = deaths
			r.battleground.faction = faction
			r.battleground.damage = dmg
			r.battleground.healing = heal
			break
		end
	end
	if GetBattlefieldWinner then
		local winner = GetBattlefieldWinner()
		if winner ~= nil and r.battleground then
			r.battleground.win = winner == r.battleground.faction
		end
	end
end

-- ---------------------------------------------------------------------------
-- custom chat link type (clickable [X] / names in our prints)
-- ---------------------------------------------------------------------------
function IT:SetupClickLinks()
	local orig = ItemRefTooltip.SetHyperlink
	function ItemRefTooltip:SetHyperlink(link, ...)
		local action = link and link:match("^suiit:(%w+)")
		if action then
			if action == "log" then IT:Toggle() end
			if action == "trades" then IT:Toggle("trades") end
			if action == "deletelast" then IT:DeleteInstance(1) end
			return
		end
		return orig(self, link, ...)
	end
end

-- ---------------------------------------------------------------------------
-- slash
-- ---------------------------------------------------------------------------
function IT:SetupSlash()
	local function handler(msg)
		msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		if msg == "" then IT:Toggle() return end
		if msg == "add" or msg == "new" then
			IT:Entered()
			return
		end
		if msg == "delete" or msg == "del" then
			IT:DeleteInstance(1)
			return
		end
		if msg == "reset" then
			IT:ResetAllInstances()
			return
		end
		if msg == "trades" or msg == "trade" or msg == "gold" or msg == "money" or msg == "tradelog" then
			IT:Toggle("trades")
			return
		end
		if msg == "chars" or msg == "alts" then
			IT:Toggle("chars")
			return
		end
		if msg == "lockouts" then
			IT:Toggle("lockouts")
			return
		end
		if msg == "levellog" or msg == "level" or msg == "levels" then
			if IT.LevelLogToggle then IT:LevelLogToggle() end
			return
		end
		if msg == "layers" or msg == "layer" then
			IT:PrintLayers()
			return
		end
		local ch, all = msg:match("^stats?%s*(%S*)%s*(all?)")
		if ch or msg:match("^stats?") then
			IT:ShowStats(1, ch ~= "" and ch or nil, all == "all")
			return
		end
		local lvl = msg:match("^delchars%s+(%d+)")
		if lvl then
			IT:TrimCharsBelow(tonumber(lvl))
			return
		end
		-- anything else: treat as channel -> post lockout info
		if msg == "party" or msg == "raid" or msg == "guild" or msg == "say" or msg == "yell" or msg == "officer" then
			IT:SendLine(IT:LockoutString(), msg)
			return
		end
		IT:Print(L["Commands"] .. ": /itrack [add|delete|reset|trades|chars|lockouts|levellog|layers|stats <channel>|delchars <level>|party|raid|guild]")
	end
	S:RegisterChatCommand("itrack", handler)
	S:RegisterChatCommand("instances", handler)
end

-- ---------------------------------------------------------------------------
-- minimap button
-- ---------------------------------------------------------------------------
function IT:SetupMinimapButton()
	local store = (self.db.minimapStore or {})
	self.db.minimapStore = store
	self.minimapBtn = S:CreateMinimapButton({
		name = "instancetracker",
		glyph = "IT",
		store = store, angle = 200,
		onLeft = function() IT:Toggle() end,
		onRight = function() IT:Toggle("chars") end,
		tooltip = function() IT:MinimapTooltip() end,
	})
	if self.db.minimapButton == false then self.minimapBtn:Hide() end
end

function IT:MinimapTooltip()
	GameTooltip:AddLine("|cff" .. S.accentHex .. "SentinelUI|r " .. L["Instance Tracker"])
	local r = self:Current()
	if r then
		local name = r.instanceName .. self:DifficultyTag(r)
		GameTooltip:AddLine((r.isPvp and "|cffffa500" or "|cff00c800") .. name .. "|r")
		local inside = GetServerTime() - r.enteredTime
		GameTooltip:AddLine(L["Time inside"] .. ": |cffffffff" .. self:TimeString(inside, "short") .. "|r")
		if not r.isPvp then
			local mobs = (r.mobCount and r.mobCount > 0) and r.mobCount or r.mobCountFromKill
			if mobs and mobs > 0 then
				GameTooltip:AddLine(L["Mobs"] .. ": |cffffffff" .. Comma(mobs) .. "|r")
			end
			if r.xpFromChat and r.xpFromChat > 0 then
				local pct = ""
				if r.xpForNextLevel and r.xpForNextLevel > 0 then
					pct = format(" (%.1f%%)", r.xpFromChat / r.xpForNextLevel * 100)
				end
				GameTooltip:AddLine(L["XP"] .. ": |cffffffff" .. Comma(r.xpFromChat) .. pct .. "|r")
				if inside > 60 then
					GameTooltip:AddLine(L["XP/Hour"] .. ": |cffffffff" .. Comma(floor(r.xpFromChat / inside * 3600)) .. "|r")
				end
			end
			if r.rawMoneyCount and r.rawMoneyCount > 0 then
				GameTooltip:AddLine(L["Raw gold from mobs"] .. ": |cffffffff" .. self:CoinString(r.rawMoneyCount) .. "|r")
			end
			if r.groupAverage then
				GameTooltip:AddLine(L["Average Group Level"] .. ": |cffffffff" .. r.groupAverage .. "|r")
			end
			if r.rep then
				for fac, amt in pairs(r.rep) do
					if amt ~= 0 then
						GameTooltip:AddLine(format("%s |cffffffff%+d|r", fac, amt))
					end
				end
			end
		elseif r.honor and r.honor > 0 then
			GameTooltip:AddLine(L["Honor"] .. ": |cffffffff" .. Comma(r.honor) .. "|r")
		end
		GameTooltip:AddLine(" ")
	end
	local h, h24 = self:LockoutInfo()
	GameTooltip:AddLine(format(L["%d instances in the past hour"], h))
	GameTooltip:AddLine(format(L["%d instances in the past 24h"], h24))
	local layer = self:CurrentLayer()
	if layer and layer > 0 then
		GameTooltip:AddLine(format(L["Layer %d"], layer))
	end
	local wb = S:GetModule("WorldBuffs", true)
	if wb and wb.AppendTooltip then wb:AppendTooltip() end
	local list = self:HourLockouts()
	if #list > 0 then
		GameTooltip:AddLine(L["Current Hour Lockouts:"])
		for _, e in ipairs(list) do
			GameTooltip:AddLine(format("  %s |cff888888(%s)|r", e.name, self:TimeString(e.left, "short")))
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Left-click: instance log  |  Right-click: characters"], 0.6, 0.6, 0.65)
end

-- ---------------------------------------------------------------------------
-- UI entry points (implemented in InstanceTracker/UI.lua)
-- ---------------------------------------------------------------------------
function IT:Toggle(tab)
	if self.ToggleFrame then self:ToggleFrame(tab) end
end

function IT:RefreshUI()
	if self.RefreshFrame then self:RefreshFrame() end
end

function IT:Update()
	self.db = S.db.profile.instancetracker
	if self.minimapBtn then
		if self.db.minimapButton == false then self.minimapBtn:Hide() else self.minimapBtn:Show() end
	end
	if self.layerFrame then
		self.layerFrame:SetShown(self.db.layerFrame == true)
	end
end
