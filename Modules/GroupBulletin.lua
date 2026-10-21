-- GroupBulletin: LFG board. Parses the LookingForGroup/SucheNachGruppe channel
-- (plus LFM-sounding chatter elsewhere) into a scrollable board window.
-- Seller/shop spam is filtered out. Left-click a row to whisper, right-click
-- to invite. Names are class-colored when the class can be resolved (party,
-- raid, guild, friends, else a throttled /who lookup). Entries expire.
local _, ns = ...
local S = ns.S
local L = S.L
local GB = S:NewModule("GroupBulletin", "groupbulletin")

local format, floor, sort = format, math.floor, table.sort
local CreateFrame = CreateFrame
local TTL = 600

local LFG_WORDS = { "lfm", "lf1m", "lf2m", "lf3m", "lfg", "lf healer", "lf tank", "lf dd",
	"suche", "suchen", "sucht", "gesucht", "brauchen", "need", "looking" }
local DUNGEON_WORDS = { "ramp", "bf ", "blood furnace", "sh ", "shattered", "sp ", "slave", "sv ",
	"ub ", "underbog", "mt ", "mana", "crypt", "ac ", "sethekk", "sl ", "slabs", "steamvault",
	"bm ", "morass", "mech", "bot ", "arc ", "durn", "rampen", "kessel", "sklaven", "sumpf",
	"gruft", "krypta", "halle", "morast", "dampfkammer", "mechanar", "botanica", "arkatraz",
	"schattenlab", "höllenfeuer", "kara", "gruul", "mag", "ssc", "tk", "hyjal", "bt ", "za ", "swp",
	"hc", "hero", "normal", "daily", "heroic" }
-- seller/shop spam: any hit disqualifies the message even inside the LFG channel
local SELL_WORDS = { "wts", "wtb", "sell", "selling", "verkaufe", "vk ", "biete",
	"shop", "store", "auction", "ah ", "gold", "price", "preis", "crafting service",
	"enchant service", "boost", "trage", "carry", "gdkp" }

local function LooksLFG(msg)
	local m = msg:lower()
	for _, w in ipairs(SELL_WORDS) do if m:find(w) then return false end end
	local hit = false
	for _, w in ipairs(LFG_WORDS) do if m:find(w, 1, true) then hit = true break end end
	if not hit then return false end
	for _, w in ipairs(DUNGEON_WORDS) do if m:find(w, 1, true) then return true end end
	return true -- pure "lfm x"-style messages without a dungeon word still count
end

local function Entries()
	S.db.global.groupBulletin = S.db.global.groupBulletin or {}
	return S.db.global.groupBulletin
end

-- ---------------------------------------------------------------- classes --
-- NOTE: SendWho is a protected function — addons may not queue /who queries.
-- Classes resolve from party/raid/guild/friends only; if the user runs /who
-- by hand we still pick up WHO_LIST_UPDATE and fill in the colors.
local function KnownClass(name)
	if not name then return end
	local plain = (name:gsub("%-.*", ""))
	for i = 1, GetNumGroupMembers() do
		local u = (IsInRaid() and "raid" or "party") .. i
		if UnitName(u) == plain then return select(2, UnitClass(u)) end
	end
	if UnitName("player") == plain then return select(2, UnitClass("player")) end
	if IsInGuild and IsInGuild() and GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() do
			local n, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
			if n and (n:gsub("%-.*", "")) == plain then return classFile end
		end
	end
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() do
			local fi = C_FriendList.GetFriendInfoByIndex(i)
			if fi and fi.name == plain and fi.classFileName then return fi.classFileName end
		end
	end
end

function GB:Add(sender, msg, channel)
	if not sender or (S.IsSecret and S.IsSecret(sender)) then return end
	local e = Entries()
	local key = sender:lower()
	local cls = KnownClass(sender)
	-- secretAPI client: chat payloads can arrive as secret strings — they
	-- break :lower()/SetText later, so strip them at the boundary
	if S.IsSecret and S.IsSecret(msg) then msg = nil end
	e[key] = { name = sender, msg = msg or "", t = time(), ch = channel, class = cls or (e[key] and e[key].class) }
	if self.frame and self.frame:IsShown() then self:Fill() end
end

function GB:Prune()
	local now = time()
	local e = Entries()
	for k, v in pairs(e) do if now - (v.t or 0) > TTL then e[k] = nil end end
end

-- --------------------------------------------------------------- the board --
local WIN_W, WIN_H, ROW_H, VISIBLE = 460, 440, 36, 10
function GB:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIGroupBulletin", UIParent)
	tinsert(UISpecialFrames, "SentinelUIGroupBulletin")
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:CreateBackdrop(f, "Default")
	local title = S:FontString(f, 13, "OUTLINE", S.media.unitFont)
	title:SetPoint("TOP", 0, -10)
	title:SetText(L["Group Bulletin"])
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	if S.SkinCloseButton then S:SkinCloseButton(close) end

	-- scrollable list
	local sf = CreateFrame("ScrollFrame", "SentinelUIGBScroll", f, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 12, -32)
	sf:SetSize(WIN_W - 40, VISIBLE * ROW_H)
	f.rows = {}
	for i = 1, VISIBLE do
		-- rows must be siblings of sf, not children: FauxScrollFrame_Update
		-- calls sf:Hide() whenever the list fits on one page, which would
		-- hide all rows. Blizzard parents the buttons to the owner frame.
		local r = CreateFrame("Button", nil, f)
		r:SetSize(WIN_W - 44, ROW_H - 4)
		r:SetPoint("TOPLEFT", 12, -32 - (i - 1) * ROW_H)
		S:CreateBackdrop(r, "Hover")
		r.name = S:FontString(r, 11, "OUTLINE", S.media.unitFont)
		r.name:SetPoint("TOPLEFT", 8, -3)
		r.name:SetJustifyH("LEFT")
		r.age = S:FontString(r, 10, "OUTLINE", S.media.numberFont)
		r.age:SetPoint("TOPRIGHT", -8, -3)
		r.msg = S:FontString(r, 10, nil, S.media.unitFont)
		r.msg:SetPoint("TOPLEFT", 8, -18)
		r.msg:SetWidth(WIN_W - 60)
		r.msg:SetJustifyH("LEFT")
		r.msg:SetWordWrap(false)
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r:SetScript("OnClick", function(self2, btn)
			if not self2.sender then return end
			if btn == "RightButton" then
				if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(self2.sender)
				elseif InviteUnit then InviteUnit(self2.sender) end
			elseif ChatFrame_OpenChat then
				ChatFrame_OpenChat("/w " .. self2.sender .. " ")
			end
		end)
		r:SetScript("OnEnter", function(self2)
			GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self2.rawMsg or "", 1, 1, 1, true)
			GameTooltip:AddLine(L["Click: whisper - Right click: invite"], 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		r:Hide()
		f.rows[i] = r
	end
	-- FauxScrollFrame_Update dereferences GetScrollChild() when the scrollbar
	-- shows (>VISIBLE entries) — a nil child would error out mid-fill
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(WIN_W - 40, VISIBLE * ROW_H)
	sf:SetScrollChild(child)
	sf:SetScript("OnVerticalScroll", function(_, offset)
		FauxScrollFrame_OnVerticalScroll(sf, offset, ROW_H, function() GB:Fill() end)
	end)
	f.scroll = sf
	f.pager = S:FontString(f, 10, "OUTLINE", S.media.numberFont)
	f.pager:SetPoint("BOTTOM", 0, 8)
	f:Hide()
	self.frame = f
end

local function SortedList()
	local e = Entries()
	local list = {}
	for _, v in pairs(e) do list[#list + 1] = v end
	sort(list, function(a, b) return (tonumber(a.t) or 0) > (tonumber(b.t) or 0) end)
	return list
end

local function FillRow(row, d, idx)
	if not d then row:Hide() return end
	-- secretAPI client: secret name/class strings poison table lookups and
	-- SetText/SetFormattedText -> render fallbacks instead of killing the row
	local sender = d.name or d.sender
	local msg = d.msg or ""
	local t = tonumber(d.t) or 0
	local secName = S.IsSecret and S.IsSecret(sender)
	local secMsg = S.IsSecret and S.IsSecret(msg)
	local secClass = S.IsSecret and S.IsSecret(d.class)
	-- legacy/malformed entries: non-string fields break SetText
	if type(sender) ~= "string" or secName then sender = "?" end
	if type(msg) ~= "string" or secMsg then msg = "…" end
	row.sender = sender
	row.rawMsg = msg
	local c = (not secClass and type(d.class) == "string") and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
	if c then row.name:SetFormattedText("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, sender)
	else row.name:SetText(sender) end
	row.msg:SetText(msg)
	row.age:SetFormattedText(L["%d min"], floor((time() - t) / 60))
	row:Show()
end

function GB:Fill()
	self:BuildFrame()
	self:Prune()
	local list = SortedList()
	local sf = self.frame.scroll
	FauxScrollFrame_Update(sf, #list, VISIBLE, ROW_H)
	local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(sf)) or 0
	-- one bad entry must not blank the board: fill each row in isolation
	for i, row in ipairs(self.frame.rows) do
		S:SafeCall("GroupBulletin:Row", FillRow, row, list[offset + i])
	end
	if not self._fillLogged then
		self._fillLogged = true
		local d = list[1]
		local s = format("fill: entries=%d offset=%d d1={n=%s s=%s c=%s t=%s m=%s}",
			#list, offset, tostring(d and d.name), tostring(d and d.sender),
			tostring(d and d.class), tostring(d and d.t), tostring(d and (S.IsSecret and S.IsSecret(d.msg))))
		S:LogInfo("gb", s)
		if print then print("|cff7fff9fgb: " .. s .. "|r") end
	end
	self.frame.pager:SetFormattedText("%d %s", #list, L["entries"])
end

function GB:Toggle()
	self:BuildFrame()
	if self.frame:IsShown() then self.frame:Hide() else self:Fill() self.frame:Show() end
end

function GB:UpdateMinimap()
	if not self.minimapBtn then
		self.private = self.private or {}
		self.private.minimap = self.private.minimap or {}
		self.minimapBtn = S:CreateMinimapButton({
			name = "groupbulletin", glyph = "GF", store = self.private.minimap,
			onLeft = function() GB:Toggle() end,
			tooltip = function()
				GameTooltip:AddLine("SentinelUI " .. (L["Group Bulletin"] or ""), S.accent.r, S.accent.g, S.accent.b)
				GameTooltip:AddLine(L["Left click: open"], 0.7, 0.7, 0.7)
			end,
		})
	end
	self.minimapBtn:SetShown(self.db.minimapIcon ~= false)
	self.minimapBtn:UpdatePosition()
end

function GB:Initialize()
	self.db = S.db.profile.groupbulletin
	self.private = S.private.groupbulletin or {}
	-- periodic expiry: entries live at most TTL seconds, not just until the
	-- next board open; refresh the list live while the window is open
	if C_Timer and C_Timer.NewTicker then
		self._pruneTicker = C_Timer.NewTicker(30, function()
			GB:Prune()
			if GB.frame and GB.frame:IsShown() then GB:Fill() end
		end)
	end
	self:RegisterEvent("CHAT_MSG_CHANNEL", function(_, _, msg, sender, _, _, _, _, _, chnum, chname)
		if not sender or sender == S.myName then return end
		local cn = (chname or ""):lower()
		local lfgChan = cn:find("lookingforgroup") or cn:find("suchenachgruppe") or cn:find("lfg") or cn:find("suche")
		if (lfgChan or self.db.allChannels) and LooksLFG(msg) then
			GB:Add(sender, msg, chname or chnum)
		end
	end)
	self:RegisterEvent("WHO_LIST_UPDATE", function()
		-- resolve classes from the throttled who answers
		if not C_FriendList or not C_FriendList.GetNumWhoResults then return end
		local e = Entries()
		for i = 1, C_FriendList.GetNumWhoResults() do
			local info = C_FriendList.GetWhoInfo(i)
			if info and info.fullName and info.filename then
				local k = info.fullName:lower()
				if e[k] then e[k].class = info.filename end
			end
		end
		if GB.frame and GB.frame:IsShown() then GB:Fill() end
	end)
	self:UpdateMinimap()
	S:RegisterChatCommand("suilfg", function() GB:Toggle() end)
end

function GB:Update()
	self.db = S.db.profile.groupbulletin
	self:UpdateMinimap()
end
