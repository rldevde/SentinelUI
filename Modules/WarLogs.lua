-- WarLogs: in-game "Warcraft Logs" for raids. A raid session = one instance
-- run: every fight (trash + boss) with per-player damage/healing/deaths/
-- interrupts plus all loot (who got what). Tabs like the real site:
-- Summary / Damage / Healing / Deaths / Interrupts / Loot / Fights.
-- Minimap button + /suilog. Share reports with other SentinelUI users.
local _, ns = ...
local S = ns.S
local L = S.L
local WL = S:NewModule("WarLogs", "warlogs")

local CreateFrame = CreateFrame
local GetTime, date = GetTime, date
local UnitName, UnitExists = UnitName, UnitExists
local IsInRaid, IsInInstance = IsInRaid, IsInInstance
local GetInstanceInfo = GetInstanceInfo
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local tinsert, tremove, wipe = table.insert, table.remove, table.wipe
local format, floor, max = format, math.floor, math.max
local strmatch, strsplit = strmatch, strsplit

local PREFIX = "SUIWL"
local MAX_SESSIONS = 8
local DMG = { SWING_DAMAGE = true, SPELL_DAMAGE = true, RANGE_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true }
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

local frame, sess
local cur -- live fight inside the session

-- -------------------------------------------------------------------------
-- recording
local function NewFight()
	return { t0 = GetTime(), dmg = {}, heal = {}, taken = {}, deaths = {}, inter = {} }
end

local function NewSession()
	local name, _, _, _, _, _, _, instID = GetInstanceInfo and GetInstanceInfo() or {}
	return { t0 = GetTime(), ts = date("%Y-%m-%d %H:%M"), inst = name or "?",
		fights = {}, kills = {}, loot = {},
		dmg = {}, heal = {}, taken = {}, deaths = {}, inter = {}, names = {} }
end

local function PName(flags, guid, name)
	if IsSecret and IsSecret(name) then return nil end
	if not name then return nil end
	if type(flags) == "number" and bit and bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x4000) == 0 then return nil end
	return strsplit("-", name)
end

local function Bump(t, n, v) if n then t[n] = (t[n] or 0) + v end end

function WL:OnCLE()
	if not cur or not sess then return end
	local r = { CombatLogGetCurrentEventInfo() }
	local sub, srcGUID, srcName, srcFlags = r[2], r[4], r[5], r[6]
	local dstGUID, dstName, dstFlags = r[8], r[9], r[10]
	if DMG[sub] then
		local n = PName(srcFlags, srcGUID, srcName)
		if n then Bump(cur.dmg, n, r[12] or 0) Bump(sess.dmg, n, r[12] or 0) sess.names[n] = true end
		Bump(cur.taken, PName(dstFlags, dstGUID, dstName), r[12] or 0)
		Bump(sess.taken, PName(dstFlags, dstGUID, dstName), r[12] or 0)
	elseif HEAL[sub] then
		local n = PName(srcFlags, srcGUID, srcName)
		if n then Bump(cur.heal, n, r[12] or 0) Bump(sess.heal, n, r[12] or 0) sess.names[n] = true end
	elseif sub == "SPELL_INTERRUPT" then
		local n = PName(srcFlags, srcGUID, srcName)
		Bump(cur.inter, n, 1) Bump(sess.inter, n, 1)
	elseif sub == "UNIT_DIED" then
		local t = PName(dstFlags, dstGUID, dstName)
		if t then
			Bump(cur.deaths, t, 1) Bump(sess.deaths, t, 1)
			if not cur.boss then cur.boss = dstName end
		elseif not cur.boss and dstName and not IsSecret(dstName) then
			-- first hostile kill of the fight names it (boss add otherwise)
			cur.boss = strsplit("-", dstName)
		end
	end
end

-- loot: raid member loot messages
function WL:OnLoot(_, _, msg)
	if not sess or type(msg) ~= "string" then return end
	local who, item = strmatch(msg, "^(.-) erhält Beute: (.+)$")
		or strmatch(msg, "^(.-) receives loot: (.+)$")
		or strmatch(msg, "^(.-) receives item: (.+)$")
	if who and item then
		tinsert(sess.loot, { who = (who == "Ihr" or who == "You") and S.myName or who, item = item, t = date("%H:%M") })
	end
end

local function InRaidInstance()
	if not IsInRaid or not IsInRaid() then return false end
	local inInst, kind = IsInInstance and IsInInstance() or false
	return (not inInst) or kind == "raid" or true -- raid group anywhere = log
end

function WL:CombatStart()
	if not InRaidInstance() then return end
	if not sess then
		sess = NewSession()
		S:LogInfo("warlogs", "session started: " .. (sess.inst or "?"))
	end
	cur = cur or NewFight()
end

function WL:CombatEnd()
	if not cur then return end
	cur.dur = GetTime() - cur.t0
	cur.name = cur.boss or (UnitExists("target") and UnitName("target")) or "Trash"
	if cur.dur >= 5 and next(cur.dmg) then
		tinsert(sess.fights, cur)
		-- boss kill = fight target died this pull; no kill + player deaths = wipe
		local playerDeaths = 0 for _ in pairs(cur.deaths or {}) do playerDeaths = playerDeaths + 1 end
		if cur.boss then
			tinsert(sess.kills, { boss = cur.boss, t = date("%H:%M"), dur = floor(cur.dur), wipe = false })
			self.db.kills[#self.db.kills + 1] = { boss = cur.boss, inst = sess.inst, ts = date("%Y-%m-%d"), clear = true }
		elseif playerDeaths >= 3 then
			tinsert(sess.kills, { boss = cur.name, t = date("%H:%M"), dur = floor(cur.dur), wipe = true })
			self.db.kills[#self.db.kills + 1] = { boss = cur.name, inst = sess.inst, ts = date("%Y-%m-%d"), clear = false }
		end
		if #self.db.kills > 200 then tremove(self.db.kills, 1) end
	end
	cur = nil
end

function WL:ZoneChange()
	-- leaving the raid instance ends the session
	if sess and not InRaidInstance() then
		sess.dur = GetTime() - sess.t0
		tinsert(self.db.sessions, sess)
		while #self.db.sessions > MAX_SESSIONS do tremove(self.db.sessions, 1) end
		S:Print(format("%s %s - %d Kämpfe, %d Loot", L["Raid log saved:"] or "Raid log saved:",
			sess.inst, #sess.fights, #sess.loot))
		sess = nil
		self:RefreshList()
	end
end

-- -------------------------------------------------------------------------
-- helpers
local function SortDesc(t)
	local a = {}
	for n, v in pairs(t or {}) do a[#a + 1] = { n = n, v = v } end
	table.sort(a, function(x, y) return x.v > y.v end)
	return a
end
local function FmtK(v)
	if v >= 1e6 then return format("%.2fM", v / 1e6) end
	if v >= 1e3 then return format("%.1fk", v / 1e3) end
	return format("%d", v)
end
local function MergeSessions(idx)
	if idx == "live" and sess then return sess end
	return WL.db.sessions[idx]
end

-- -------------------------------------------------------------------------
-- UI
local TABS = {
	{ L["Summary"] or "Summary", "summary" }, { L["Damage"] or "Damage", "dmg" }, { L["Healing"] or "Healing", "heal" },
	{ L["Deaths"] or "Deaths", "deaths" }, { L["Interrupts"] or "Interrupts", "inter" }, { L["Loot"] or "Loot", "loot" },
	{ L["Fights"] or "Fights", "fights" },
}

local function BuildUI()
	if frame then return end
	local f = CreateFrame("Frame", "SentinelUIWarLogs", UIParent, S.BackdropTemplate)
	f:SetSize(640, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	S:SetTemplate(f, "Default", "MEDIUM")
	f:EnableMouse(true)
	f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()

	local t = S:FontString(f, 13, "OUTLINE")
	t:SetPoint("TOP", 0, -8)
	t:SetText("|cffff5555War|r|cffffffffLogs|r")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	-- left: raid session list
	local list = CreateFrame("Frame", nil, f)
	list:SetPoint("TOPLEFT", 8, -34)
	list:SetSize(200, 372)
	S:SetTemplate(list, "Default")
	f.listRows = {}
	for i = 1, 14 do
		local r = CreateFrame("Button", nil, list)
		r:SetSize(190, 24)
		r:SetPoint("TOPLEFT", 5, -((i - 1) * 26) - 4)
		S:SetTemplate(r, "Default")
		r.txt = S:FontString(r, 9, "OUTLINE")
		r.txt:SetPoint("LEFT", 4, 0)
		r:SetScript("OnClick", function() WL:ShowSession(r.sidx) end)
		f.listRows[i] = r
	end

	-- right: tab strip + content
	local detail = CreateFrame("Frame", nil, f)
	detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
	detail:SetSize(410, 372)
	S:SetTemplate(detail, "Default")
	f.detail = detail
	f.tabs = {}
	for i, td in ipairs(TABS) do
		local tb = CreateFrame("Button", nil, detail)
		tb:SetSize(56, 18)
		tb:SetPoint("TOPLEFT", 3 + (i - 1) * 58, -3)
		S:SetTemplate(tb, "Default")
		tb.txt = S:FontString(tb, 8, "OUTLINE")
		tb.txt:SetAllPoints() tb.txt:SetText(td[1])
		tb.key = td[2]
		tb:SetScript("OnClick", function() WL.tab = tb.key WL:ShowSession(WL._lastIdx) end)
		f.tabs[i] = tb
	end
	f.rows, f.bars = {}, {}
	for i = 1, 13 do
		local b = detail:CreateTexture(nil, "BACKGROUND")
		b:SetPoint("TOPLEFT", detail, "TOPLEFT", 6, -((i - 1) * 26) - 28)
		b:SetHeight(12)
		b:SetTexture(S.media.statusbar or "Interface/Buttons/WHITE8x8")
		b:Hide()
		f.bars[i] = b
		local r = S:FontString(detail, 9, "OUTLINE")
		r:SetPoint("TOPLEFT", 6, -((i - 1) * 26) - 28)
		r:SetJustifyH("LEFT")
		f.rows[i] = r
	end
	f.foot = S:FontString(detail, 9, "OUTLINE")
	f.foot:SetPoint("BOTTOM", 0, 8)
	f.empty = S:FontString(detail, 11, "OUTLINE")
	f.empty:SetPoint("CENTER", 0, -30)
	f.empty:SetText("|cff888888" .. (L["No raid logs yet - join a raid to start recording"] or "No raid logs yet - join a raid to start recording") .. "|r")

	local function Btn(txt, x, fn)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(100, 20)
		b:SetPoint("BOTTOMLEFT", x, 12)
		S:SetTemplate(b, "Default")
		local s = S:FontString(b, 9, "OUTLINE")
		s:SetAllPoints() s:SetText(txt)
		s:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
		b:SetScript("OnClick", fn)
	end
	Btn(L["Share in group"] or "Share in group", 8, function() WL:Share() end)
	Btn(L["Clear history"] or "Clear history", 116, function() wipe(WL.db.sessions) WL:RefreshList() end)
	frame = f
end

function WL:RefreshList()
	if not frame then return end
	local s = self.db.sessions
	local li = 0
	-- live session first
	if sess then
		li = li + 1
		local r = frame.listRows[li]
		r.sidx = "live"
		r.txt:SetText(format("|cff66ff66LIVE|r %s", sess.inst or "?"))
		r:Show()
	end
	for i = #s, 1, -1 do
		li = li + 1
		local r = frame.listRows[li]
		if not r then break end
		local v = s[i]
		r.sidx = i
		r.txt:SetText(format("%s\n|cff888888%s|r", v.inst or "?", v.ts or ""))
		r:Show()
	end
	for i = li + 1, #frame.listRows do frame.listRows[i]:Hide() end
end

local function PaintStats(f, s, arr, mx, perSec, extra)
	for i, r in ipairs(frame.rows) do
		local e = arr[i]
		if e then
			local sec = perSec and format(" |cff888888(%s/s)|r", FmtK(e.v / (s.dur or 1))) or ""
			r:SetText(format("%d. %s: |cff00ff00%s|r%s%s", i, e.n, FmtK(e.v), sec, extra and extra(e) or ""))
			local b = frame.bars[i]
			b:SetWidth(396 * (e.v / mx))
			b:SetVertexColor(0.75, 0.75, 0.75, 0.35)
			b:Show()
		else r:SetText("") frame.bars[i]:Hide() end
	end
end

function WL:ShowSession(idx)
	local s = MergeSessions(idx)
	frame.empty:SetShown(s == nil)
	if not s then
		for i, r in ipairs(frame.rows) do r:SetText("") frame.bars[i]:Hide() end
		frame.foot:SetText("")
		return
	end
	WL._lastIdx = idx
	local tab = self.tab or "summary"
	for _, tb in ipairs(frame.tabs) do
		local on = tb.key == tab
		tb.txt:SetTextColor(on and S.accent.r or 0.6, on and S.accent.g or 0.6, on and S.accent.b or 0.6)
	end
	local dur = s.dur or (sess == s and (GetTime() - s.t0) or 1)

	if tab == "summary" then
		local pl = 0 for _ in pairs(s.names or {}) do pl = pl + 1 end
		local td, th = 0, 0 for _, v in pairs(s.dmg) do td = td + v end for _, v in pairs(s.heal) do th = th + v end
		local lines = {
			format("|cffffff00%s|r", s.inst or "?"), format("%s | %dmin", s.ts or "?", floor(dur / 60)),
			format("%d %s | %d %s", pl, L["players"] or "players", #s.fights, L["fights"] or "fights"),
			format("%s |cff00ff00%s|r  |  %s |cff66ccff%s|r", L["Damage:"] or "Damage:", FmtK(td), L["Healing:"] or "Healing:", FmtK(th)),
			format("%s %d  |  %s %d", L["Deaths:"] or "Deaths:", (function() local n = 0 for _, v in pairs(s.deaths) do n = n + v end return n end)(), L["Loot:"] or "Loot:", #s.loot),
		}
		for i, r in ipairs(frame.rows) do r:SetText(lines[i] or "") frame.bars[i]:Hide() end
	elseif tab == "dmg" or tab == "heal" or tab == "inter" or tab == "deaths" then
		local arr = SortDesc(tab == "dmg" and s.dmg or tab == "heal" and s.heal or tab == "inter" and s.inter or s.deaths)
		PaintStats(frame, s, arr, arr[1] and arr[1].v or 1, tab == "dmg" or tab == "heal",
			tab == "dmg" and function(e) local dd = s.deaths[e.n] or 0 return dd > 0 and format(" |cffff5555(x%d)|r", dd) or "" end or nil)
	elseif tab == "loot" then
		for i, r in ipairs(frame.rows) do
			local e = s.loot[i]
			if e then
				r:SetText(format("%s  %s  |cff888888%s|r", e.t or "", e.who or "?", e.item or "?"))
			else r:SetText("") end
			frame.bars[i]:Hide()
		end
	elseif tab == "fights" then
		for i, r in ipairs(frame.rows) do
			local e = s.fights[i]
			if e then
				local td = 0 for _, v in pairs(e.dmg or {}) do td = td + v end
				r:SetText(format("%d. %s  |cff888888%ds  %s|r", i, e.name or "?", floor(e.dur or 0), FmtK(td)))
			else r:SetText("") end
			frame.bars[i]:Hide()
		end
	end
	frame.foot:SetText(format("%s - %d %s | %d %s", s.inst or "?", #s.fights, L["fights"] or "fights",
		#s.loot, L["loot"] or "loot"))
end

-- -------------------------------------------------------------------------
-- sharing
function WL:Share()
	local s = MergeSessions(WL._lastIdx) or sess or self.db.sessions[#self.db.sessions]
	if not s then S:Print(L["No log to share."] or "No log to share.") return end
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage and S.AceSerializer) then return end
	-- top-10 only so it fits one message
	local top = {}
	for i, e in ipairs(SortDesc(s.dmg)) do if i > 10 then break end top[e.n] = e.v end
	local ok, ser = pcall(S.AceSerializer.Serialize, S.AceSerializer,
		{ inst = s.inst, dur = s.dur, dmg = top, from = S.myName })
	if ok and ser and #ser < 250 then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, ser, S.GroupChannel())
		S:Print(L["Report shared."] or "Report shared.")
	else
		S:Print(L["Report too large."] or "Report too large.")
	end
end

function WL:OnAddonMsg(prefix, msg, _, sender)
	if prefix ~= PREFIX or not S.AceSerializer then return end
	if msg:sub(1, 2) == "P!" then
		local name = sender and strsplit("-", sender)
		if name and name ~= S.myName then self.db.profiles[name] = msg:sub(3) end
		return
	end
	local ok, rep = S.AceSerializer:Deserialize(msg)
	if not ok or type(rep) ~= "table" or not rep.inst then return end
	rep.shared, rep.ts, rep.names = true, date("%H:%M"), rep.names or {}
	rep.fights, rep.loot, rep.heal, rep.taken, rep.deaths, rep.inter =
		rep.fights or {}, rep.loot or {}, rep.heal or {}, rep.taken or {}, rep.deaths or {}, rep.inter or {}
	tinsert(self.db.sessions, rep)
	while #self.db.sessions > MAX_SESSIONS do tremove(self.db.sessions, 1) end
	self:RefreshList()
	S:Print(format("%s %s", sender or "?", L["shared a raid log."] or "shared a raid log."))
end

function WL:Toggle()
	BuildUI()
	if frame:IsShown() then frame:Hide() return end
	self:RefreshList()
	frame:Show()
	frame.empty:SetShown(#self.db.sessions == 0 and not sess)
	if sess then self:ShowSession("live") elseif #self.db.sessions > 0 then self:ShowSession(#self.db.sessions) end
end

-- -------------------------------------------------------------------------
-- player profiles: compact progression string shared in groups
-- "WL:ZG:10/10|MC:8/8" style summary built from the kill history
local function BuildProfile()
	local by = {}
	for _, k in ipairs(WL.db.kills or {}) do
		local e = by[k.inst or "?"] or { n = 0, w = 0 }
		if k.clear then e.n = e.n + 1 else e.w = e.w + 1 end
		by[k.inst or "?"] = e
	end
	local parts = {}
	for inst, e in pairs(by) do parts[#parts + 1] = inst .. ":" .. e.n .. "/" .. (e.n + e.w) end
	return table.concat(parts, "|"):sub(1, 200)
end

function WL:BroadcastProfile()
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	local p = BuildProfile()
	if p == "" then return end
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, "P!" .. p, S.GroupChannel())
end

function WL:OnRoster()
	-- auto-send on join; also (re)start session logging when a raid forms
	if IsInRaid() and not sess then
		self._joinT = (self._joinT or 0)
		if GetTime() - self._joinT > 5 then
			self._joinT = GetTime()
			sess = sess or NewSession()
		end
	end
	self:BroadcastProfile()
end

-- tooltip: show the player's raid progression under their name
function WL:OnTooltip(tt)
	local _, unit = tt:GetUnit()
	if not unit or not UnitIsPlayer(unit) then return end
	local name = UnitName(unit)
	if not name then return end
	name = strsplit("-", name)
	local prof = name == S.myName and BuildProfile() or (self.db.profiles[name])
	if prof and prof ~= "" then
		tt:AddLine("|cffeaad33WarLogs:|r " .. prof)
		tt:Show()
	end
end

-- inspect window: append progression when inspecting someone
function WL:InspectHook()
	if not InspectFrame then return end
	if not self._inspHooked then
		self._inspHooked = true
		InspectFrame:HookScript("OnShow", function()
			if InspectFrame.unit then
				local name = UnitName(InspectFrame.unit)
				if name then
					local p = WL.db.profiles[strsplit("-", name)]
					if p and InspectFrame.TitleText then
						InspectFrame.TitleText:SetText(name .. " |cffeaad33" .. p .. "|r")
					end
				end
			end
		end)
	end
end

-- export: copy/paste window with JSON of all sessions for external tooling
local exportBox
function WL:Export()
	if not exportBox then
		local f = CreateFrame("Frame", "SentinelUIWarLogsExport", UIParent, S.BackdropTemplate)
		f:SetSize(560, 400) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG")
		f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
		S:SetTemplate(f, "Default", "MEDIUM")
		local t = S:FontString(f, 11, "OUTLINE")
		t:SetPoint("TOP", 0, -10) t:SetText(L["Export log"] or "Export log")
		local sc = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		sc:SetPoint("TOPLEFT", 12, -36) sc:SetPoint("BOTTOMRIGHT", -32, 40)
		local eb = CreateFrame("EditBox", nil, sc)
		eb:SetMultiLine(true) eb:SetWidth(520) eb:SetAutoFocus(false)
		eb:SetFontObject(GameFontHighlightSmall)
		sc:SetScrollChild(eb)
		f.eb = eb
		local cl = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		cl:SetPoint("TOPRIGHT", -4, -4)
		exportBox = f
	end
	-- serialize all sessions as simple JSON
	local function esc(s) return tostring(s):gsub('"', '\\"') end
	local function tbl(t)
		local o = {}
		for n, v in pairs(t or {}) do o[#o + 1] = format('{"n":%q,"v":%d}', esc(n), floor(v)) end
		return "[" .. table.concat(o, ",") .. "]"
	end
	local out = { '["sentinelui_warlogs_version":1,' }
	for i, s in ipairs(self.db.sessions) do
		out[#out + 1] = format(
			'{"inst":%q,"ts":%q,"dur":%d,"dmg":%s,"heal":%s,"deaths":%s,"loot":%d,"fights":%d},',
			esc(s.inst), esc(s.ts), floor(s.dur or 0), tbl(s.dmg), tbl(s.heal), tbl(s.deaths), #(s.loot or {}), #(s.fights or {}))
	end
	out[#out + 1] = "]"
	exportBox.eb:SetText(table.concat(out, "\n"):gsub(",%]", "]"))
	exportBox.eb:HighlightText()
	exportBox:Show()
end

function WL:Initialize()
	self.db = S.db.profile.warlogs
	self.db.sessions = self.db.sessions or {}
	self.db.kills = self.db.kills or {}
	self.db.profiles = self.db.profiles or {}
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCLE")
	self:RegisterEvent("CHAT_MSG_LOOT", "OnLoot")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "CombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "CombatEnd")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "ZoneChange")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ZoneChange")
	if self.private then self.private.minimap = self.private.minimap or {} end
	self.minimapBtn = S:CreateMinimapButton({
		name = "warlogs", glyph = "WL",
		store = (self.private and self.private.minimap) or nil,
		onLeft = function() WL:Toggle() end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI WarLogs")
			GameTooltip:AddLine("Left-click: open raid logs", 1, 1, 1)
		end,
	})
	SLASH_SUILOG1, SLASH_SUILOG2 = "/suilog", "/suiwarlogs"
	SlashCmdList.SUILOG = function() WL:Toggle() end
	SLASH_SUILOGEXP1 = "/suilogexport"
	SlashCmdList.SUILOGEXP = function() WL:Export() end
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
	if GameTooltip then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tt) S:SafeCall("WarLogs:Tip", WL.OnTooltip, WL, tt) end)
	end
	S:SafeCall("WarLogs:Inspect", WL.InspectHook, WL)
end
