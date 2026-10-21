-- Questie compat bridge: speaks the on-the-wire format that the Questie addon
-- uses for party progress sync so SentinelUI users can exchange objective
-- progress with group members running Questie. This is an independent
-- implementation of the message format only - no Questie code, data or
-- runtime dependency is involved; everything is decoded/encoded locally.
local _, ns = ...
local S = ns.S
local QS = S:GetModule("QuestScope")

local floor, ceil = math.floor, math.ceil
local byte, char, sub = string.byte, string.char, string.sub
local tconcat = table.concat

local QST_PREFIX = "questie"
local QST_MSGVER = 5
local QST_VER = "0.0.0"

-- message ids of the packets we understand
local ID_UPDATE, ID_REMOVE, ID_FULL, ID_REQUEST = 1, 2, 10, 11
local ID_FULLV2, ID_YELL, ID_UPDATEV2 = 12, 13, 14

QS.Questie = {}
local QC = QS.Questie

-- ---------------------------------------------------------------------------
-- stream decoder (the "1short" channel encoding plus the "b89" yell encoding)
-- ---------------------------------------------------------------------------
local CTRL, ZERO = 237, 238
local B89_LEVEL = { [120] = 0, [121] = 1, [122] = 2 }  -- 'x' 'y' 'z'
local B89_TRANS = { [123] = 1, [124] = 6, [125] = 59 } -- '{' '|' '}'

local function Stream(data, mode)
	return { bin = data, ptr = 1, level = 0, mode = mode or "1short" }
end

local function RawByte(st)
	local b = byte(st.bin, st.ptr)
	if not b then error("eof") end
	st.ptr = st.ptr + 1
	return b
end

local function ReadByte(st)
	if st.mode == "b89" then
		local v = RawByte(st)
		if B89_LEVEL[v] then
			st.level = B89_LEVEL[v]
			v = RawByte(st)
		end
		if B89_TRANS[v] then
			return st.level * 86 + B89_TRANS[v]
		end
		return st.level * 86 + v - 33
	end
	local v = RawByte(st)
	if v == ZERO then return 0 end
	if v == CTRL then
		v = RawByte(st)
		return (v == 2) and 238 or 237
	end
	return v
end

local function ReadShort(st) return ReadByte(st) * 256 + ReadByte(st) end
local function ReadInt(st)
	return ReadByte(st) * 16777216 + ReadByte(st) * 65536 + ReadByte(st) * 256 + ReadByte(st)
end
local function ReadLong(st)
	local hi = ReadInt(st)
	return hi * 4294967296 + ReadInt(st)
end

local function ReadChars(st, len)
	if st.mode == "b89" then
		-- b89 strings carry raw bytes
		local p = st.ptr
		st.ptr = p + len
		return sub(st.bin, p, p + len - 1)
	end
	local t = {}
	for i = 1, len do t[i] = ReadByte(st) end
	return char(unpack(t, 1, len))
end

local function ReadTinyString(st) return ReadChars(st, ReadByte(st)) end
local function ReadShortString(st) return ReadChars(st, ReadShort(st)) end

-- djb2-style rolling hash, matching the writer's string interning
local function HashStr(str)
	local h = 5381
	for i = 1, #str do
		h = (31 * h + byte(str, i)) % 4294967296
	end
	return h
end

local function BitsToFloat(i)
	local b1 = floor(i / 16777216) % 256
	local b2 = floor(i / 65536) % 256
	local b3 = floor(i / 256) % 256
	local b4 = i % 256
	local sign = b1 > 0x7F and -1 or 1
	local expo = (b1 % 0x80) * 2 + floor(b2 / 0x80)
	local mant = ((b2 % 0x80) * 0x100 + b3) * 0x100 + b4
	if mant == 0 and expo == 0 then return sign * 0.0 end
	if expo == 0xFF then return mant == 0 and sign * math.huge or 0 / 0 end
	return sign * (1.0 + mant / 0x800000) * 2 ^ (expo - 0x7F)
end

local ReadObject -- fwd

local function ReadTable(st, count, hashDB)
	local ret = {}
	for _ = 1, count do
		local key = ReadObject(st, hashDB)
		local value = ReadObject(st, hashDB)
		if type(key) == "string" then hashDB[HashStr(key)] = key end
		if type(value) == "string" then hashDB[HashStr(value)] = value end
		if key ~= nil then ret[key] = value end
	end
	return ret
end

local function ReadArray(st, count, hashDB)
	local ret = {}
	for i = 1, count do
		local v = ReadObject(st, hashDB)
		if type(v) == "string" then hashDB[HashStr(v)] = v end
		ret[i] = v
	end
	return ret
end

local TagReaders = {
	[1] = function() return nil end,
	[2] = function(st) return ReadInt(st) end,
	[3] = function(st) return -ReadInt(st) end,
	[4] = function(st) return ReadLong(st) end,
	[5] = function(st) return -ReadLong(st) end,
	[6] = function(st) return BitsToFloat(ReadInt(st)) end,
	[7] = function(st) return ReadTinyString(st) end,
	[8] = function(st) return ReadShortString(st) end,
	[9] = function(st, hashDB) return hashDB[ReadInt(st)] end,
	[10] = function(st, hashDB) return ReadTable(st, ReadByte(st), hashDB) end,
	[11] = function(st, hashDB) return ReadTable(st, ReadShort(st), hashDB) end,
	[12] = function(st) return ReadByte(st) end,
	[13] = function(st) return -ReadByte(st) end,
	[14] = function(st) return ReadShort(st) end,
	[15] = function(st) return -ReadShort(st) end,
	[16] = function() return false end,
	[17] = function() return true end,
	[18] = function() return nil end,
	[19] = function() return nil end,
	[20] = function(st, hashDB) return ReadArray(st, ReadByte(st), hashDB) end,
	[21] = function(st, hashDB) return ReadArray(st, ReadShort(st), hashDB) end,
	[22] = function(st, hashDB) return ReadArray(st, ReadInt(st), hashDB) end,
}

ReadObject = function(st, hashDB)
	local tag = ReadByte(st)
	if tag > 31 then return tag - 32 end -- small literal ints are packed in the tag
	local r = TagReaders[tag]
	if not r then error("bad tag " .. tag) end
	return r(st, hashDB)
end

local function Decode(msg, mode)
	local st = Stream(msg, mode)
	local hashDB = {}
	local t = ReadTable(st, 1, hashDB)
	return t[1]
end

-- ---------------------------------------------------------------------------
-- stream encoder (1short) so Questie clients can see our progress too
-- ---------------------------------------------------------------------------
local function WStream() return { parts = {}, n = 0, hashes = {} } end

local function WRaw(st, b)
	st.n = st.n + 1
	st.parts[st.n] = char(b)
end

local function WByte(st, e)
	e = floor(e)
	if e == 0 then WRaw(st, ZERO)
	elseif e == 237 or e == 238 then WRaw(st, CTRL) WRaw(st, e == 237 and 1 or 2)
	else WRaw(st, e) end
end

local function WShort(st, v) WByte(st, floor(v / 256) % 256) WByte(st, v % 256) end
local function WInt(st, v)
	WByte(st, floor(v / 16777216) % 256)
	WByte(st, floor(v / 65536) % 256)
	WByte(st, floor(v / 256) % 256)
	WByte(st, v % 256)
end

local WriteObject -- fwd

local function IsArray(t)
	local i = 0
	for e in pairs(t) do
		i = i + 1
		if i ~= e then return false end
	end
	return true
end

local function WNumber(st, v)
	local _, fract = math.modf(v)
	if fract ~= 0 then
		WByte(st, 6)
		-- IEEE754 single precision bits, little helper inline
		local sign = 0
		if v < 0 then sign = 0x80 v = -v end
		local mant, expo = math.frexp(v)
		local int
		if mant ~= mant or mant == math.huge or expo > 0x80 then
			int = (sign == 0 and 0x7F or 0xFF) * 16777216 + 0x800000
		elseif (mant == 0 and expo == 0) or expo < -0x7E then
			int = sign * 16777216
		else
			expo = expo + 0x7E
			mant = floor((mant * 2 - 1) * 0x800000)
			int = (sign + floor(expo / 2)) * 16777216 + (expo % 2) * 8388608 + mant
		end
		WInt(st, int)
		return
	end
	local sign = 0
	if v < 0 then v = -v sign = 1 end
	if v > 2147483646 then
		WByte(st, 4 + sign)
		WInt(st, floor(v / 4294967296))
		WInt(st, v % 4294967296)
	elseif v < 222 and sign == 0 then
		WByte(st, 32 + v)
	elseif v < 255 then
		WByte(st, 12 + sign) WByte(st, v)
	elseif v < 65530 then
		WByte(st, 14 + sign) WShort(st, v)
	else
		WByte(st, 2 + sign) WInt(st, v)
	end
end

local function WString(st, v)
	local len = #v
	if len > 4 and st.hashes[v] then
		WByte(st, 9)
		WInt(st, st.hashes[v])
		return
	end
	if len > 254 then
		WByte(st, 8)
		WShort(st, len)
	else
		WByte(st, 7)
		WByte(st, len)
	end
	for i = 1, len do WByte(st, byte(v, i)) end
	if len > 4 then st.hashes[v] = HashStr(v) end
end

local function WPair(st, key, value)
	if not key or value == nil then return end
	WriteObject(st, key)
	WriteObject(st, value)
end

WriteObject = function(st, v)
	local t = type(v)
	if t == "number" then
		WNumber(st, v)
	elseif t == "string" then
		WString(st, v)
	elseif t == "boolean" then
		WByte(st, v and 17 or 16)
	elseif t == "table" then
		local count = 0
		for k, val in pairs(v) do
			if k and val ~= nil then count = count + 1 end
		end
		if IsArray(v) then
			if count > 65530 then WByte(st, 22) WInt(st, count)
			elseif count > 254 then WByte(st, 21) WShort(st, count)
			else WByte(st, 20) WByte(st, count) end
			for _, val in ipairs(v) do WriteObject(st, val) end
		else
			if count > 254 then WByte(st, 11) WShort(st, count)
			else WByte(st, 10) WByte(st, count) end
			for k, val in pairs(v) do WPair(st, k, val) end
		end
	end
	-- nil / function / userdata are dropped by the writer too
end

local function Encode(tab)
	local st = WStream()
	WPair(st, 1, tab)
	return tconcat(st.parts)
end

-- ---------------------------------------------------------------------------
-- wire framing: messages travel inside AceComm's framing (single part, or
-- \001 first / \002 next / \003 last multipart chunks of <=254 bytes)
-- ---------------------------------------------------------------------------
local MULTI_FIRST, MULTI_NEXT, MULTI_LAST, ESCAPE = 1, 2, 3, 4

local function SendWire(text, distribution, target)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	local len = #text
	local first = byte(text, 1)
	if first and first >= 1 and first <= 9 then
		text = char(ESCAPE) .. text -- escape control-char first byte
		len = len + 1
	end
	if len <= 255 then
		C_ChatInfo.SendAddonMessage(QST_PREFIX, text, distribution, target)
		return
	end
	local chunk = 254
	local pos = 1
	C_ChatInfo.SendAddonMessage(QST_PREFIX, char(MULTI_FIRST) .. sub(text, 1, chunk), distribution, target)
	pos = pos + chunk
	while pos + chunk <= len do
		C_ChatInfo.SendAddonMessage(QST_PREFIX, char(MULTI_NEXT) .. sub(text, pos, pos + chunk - 1), distribution, target)
		pos = pos + chunk
	end
	C_ChatInfo.SendAddonMessage(QST_PREFIX, char(MULTI_LAST) .. sub(text, pos), distribution, target)
end

QC._spool = {} -- sender+distribution -> accumulated multipart bytes

local function PartyChannel()
	return (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
end

local function StoreObjective(name, qid, idx, ful, req)
	if not (name and qid and idx and ful and req) then return end
	if req <= 0 then return end
	local p = QS.party[name]
	if not p then p = {} QS.party[name] = p end
	p._src = "questie"
	p[qid .. ":" .. idx] = ful .. "/" .. req
end

-- v1 quest packet: { id=qid, objectives={ [idx]={ful=?,req=?} } }
local function InsertV1(quest, name)
	if type(quest) ~= "table" or not quest.id then return end
	if type(quest.objectives) ~= "table" then return end
	for idx, o in pairs(quest.objectives) do
		if type(o) == "table" then
			StoreObjective(name, quest.id, tonumber(idx), tonumber(o.ful), tonumber(o.req))
		end
	end
end

-- v2 flat array: qid, count [, class], {objId,typeByte,ful,req} * count
local function InsertFlat(arr, name, offset, hasClass, disableComplete)
	local qid = arr[offset]
	local count = arr[offset + 1]
	if not (qid and count) then return offset + 2 end
	offset = offset + (hasClass and 3 or 2)
	local allDone = true
	local idx = 0
	while idx < count and arr[offset + 1] do
		idx = idx + 1
		local ful, req = arr[offset + 2], arr[offset + 3]
		if ful ~= req then allDone = false end
		if not disableComplete or ful ~= req then
			StoreObjective(name, qid, idx, ful, req)
		end
		offset = offset + 4
	end
	if allDone and disableComplete then
		local p = QS.party[name]
		if p then
			for k in pairs(p) do
				if strmatch(k, "^" .. qid .. ":") then p[k] = nil end
			end
		end
	end
	return offset
end

local function HandlePacket(pkt, name, fullSender)
	if type(pkt) ~= "table" then return end
	local msgId = pkt.msgId
	if msgId == ID_UPDATE then
		InsertV1(pkt.quest, name)
	elseif msgId == ID_REMOVE then
		local p = QS.party[name]
		if p and pkt.id then
			for k in pairs(p) do
				if strmatch(k, "^" .. tonumber(pkt.id) .. ":") then p[k] = nil end
			end
		end
	elseif msgId == ID_FULL and type(pkt.rawQuestList) == "table" then
		for _, q in pairs(pkt.rawQuestList) do InsertV1(q, name) end
	elseif msgId == ID_FULLV2 and type(pkt[1]) == "table" then
		local arr = pkt[1]
		local offset = 2
		for _ = 1, arr[1] or 0 do
			offset = InsertFlat(arr, name, offset, false, false)
		end
	elseif msgId == ID_YELL and type(pkt[1]) == "table" then
		InsertFlat(pkt[1], name, 1, true, true)
	elseif msgId == ID_UPDATEV2 and type(pkt[1]) == "table" then
		InsertFlat(pkt[1], name, 1, false, false)
	elseif msgId == ID_REQUEST then
		-- a Questie client asked the group for full quest logs: answer in
		-- whisper so their tooltips get our progress right away
		C_Timer.After(1, function()
			QC:BroadcastLog("WHISPER", fullSender or name)
		end)
	end
end

local function ShortName(sender)
	return sender and (strsplit("-", sender))
end

function QC:OnMessage(msg, channel, sender)
	if not (QS.db and QS.db.partySync and QS.party) then return end
	local name = ShortName(sender)
	if not name or name == UnitName("player") then return end
	local b1 = byte(msg, 1)
	if b1 and b1 <= 9 then
		-- AceComm multipart / escape framing
		local key = (channel or "?") .. ":" .. name
		if b1 == MULTI_FIRST then
			self._spool[key] = sub(msg, 2)
			return
		elseif b1 == MULTI_NEXT then
			local buf = self._spool[key]
			if buf then self._spool[key] = buf .. sub(msg, 2) end
			return
		elseif b1 == MULTI_LAST then
			local buf = self._spool[key]
			if not buf then return end
			self._spool[key] = nil
			msg = buf .. sub(msg, 2)
		elseif b1 == ESCAPE then
			msg = sub(msg, 2)
		else
			return
		end
	end
	local ok, pkt = pcall(Decode, msg, channel == "YELL" and "b89" or "1short")
	if ok and pkt then
		self._rx = (self._rx or 0) + 1
		HandlePacket(pkt, name, sender)
	end
end

-- ---------------------------------------------------------------------------
-- sending: UPDATEV2 per changed quest, FULLV2 for log sync, REMOVE on abandon
-- ---------------------------------------------------------------------------
local function ObjectivesFlat(qid)
	local state = QS.ObjectivesOf and QS.ObjectivesOf(qid)
	if not state then return nil end
	local out, n = {}, 0
	for _, o in ipairs(state) do
		if o.numNeeded and o.numNeeded > 0 then
			n = n + 1
			out[#out + 1] = o.id or 0
			out[#out + 1] = byte(strsub(o.type or "e", 1, 1))
			out[#out + 1] = o.numFulfilled or 0
			out[#out + 1] = o.numNeeded
		end
	end
	return out, n
end

local function Packet(msgId, extra)
	local pkt = { ver = QST_VER, msgVer = QST_MSGVER, msgId = msgId }
	if extra then for k, v in pairs(extra) do pkt[k] = v end end
	return pkt
end

function QC:SendUpdate(qid, channel, target)
	if not (IsInGroup and IsInGroup()) and channel ~= "WHISPER" then return end
	local flat, n = ObjectivesFlat(qid)
	if not n or n == 0 then return end
	local arr = { qid, n }
	for _, v in ipairs(flat) do arr[#arr + 1] = v end
	SendWire(Encode(Packet(ID_UPDATEV2, { [1] = arr })), channel or PartyChannel(), target)
end

function QC:BroadcastLog(channel, target)
	if channel ~= "WHISPER" and not (IsInGroup and IsInGroup()) then return end
	local full = { 0 } -- [1] = quest count, filled below
	local quests = 0
	for qid in pairs(QS.logQuests or {}) do
		local flat, n = ObjectivesFlat(qid)
		if n and n > 0 then
			quests = quests + 1
			full[#full + 1] = qid
			full[#full + 1] = n
			for _, v in ipairs(flat) do full[#full + 1] = v end
		end
	end
	if quests == 0 then return end
	full[1] = quests
	SendWire(Encode(Packet(ID_FULLV2, { [1] = full })), channel or PartyChannel(), target)
end

function QC:BroadcastRemove(qid)
	if not (IsInGroup and IsInGroup()) then return end
	SendWire(Encode(Packet(ID_REMOVE, { id = qid })), PartyChannel())
end

function QC:BroadcastUpdates(changed)
	if not (IsInGroup and IsInGroup()) then return end
	if not changed or not next(changed) then return end
	local ch = PartyChannel()
	for qid in pairs(changed) do
		self:SendUpdate(qid, ch)
	end
end
