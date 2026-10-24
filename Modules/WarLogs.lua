-- WarLogs: in-game "Warcraft Logs" - records every fight (duration, per-player
-- damage / healing / deaths / interrupts), keeps a history, shows a report
-- window with breakdown tabs and lets you share reports with other
-- SentinelUI users over the addon channel.
local _, ns = ...
local S = ns.S
local L = S.L
local WL = S:NewModule("WarLogs", "warlogs")

local CreateFrame = CreateFrame
local GetTime, date = GetTime, date
local UnitInCombat, UnitName = UnitInCombat, UnitName
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local tinsert, tremove, wipe = table.insert, table.remove, table.wipe
local format, floor = format, math.floor
local strsplit, select = strsplit, select

local PREFIX = "SUIWL"
local MAX_HISTORY = 20
local DMG = { SWING_DAMAGE = true, SPELL_DAMAGE = true, RANGE_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true }
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

local frame, listScroll, detail
local cur -- live fight being recorded

-- -------------------------------------------------------------------------
-- recording
local function NewFight()
	return { t0 = GetTime(), ts = date("%H:%M:%S"), zone = GetZoneText and GetZoneText() or "?",
		dmg = {}, heal = {}, taken = {}, deaths = {}, inter = {}, names = {} }
end

local function PlayerName(flags, guid, name)
	if IsSecret and IsSecret(name) then return nil end
	if not name then return nil end
	if type(flags) == "number" and bit and bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x4000) == 0 then return nil end
	return strsplit("-", name)
end

function WL:OnCLE()
	if not cur then return end
	local r = { CombatLogGetCurrentEventInfo() }
	local sub, srcGUID, srcName, srcFlags = r[2], r[4], r[5], r[6]
	local dstGUID, dstName, dstFlags = r[8], r[9], r[10]
	if DMG[sub] then
		local n = PlayerName(srcFlags, srcGUID, srcName)
		if n then
			cur.dmg[n] = (cur.dmg[n] or 0) + (r[12] or 0)
			cur.names[n] = true
		end
		local t = PlayerName(dstFlags, dstGUID, dstName)
		if t then cur.taken[t] = (cur.taken[t] or 0) + (r[12] or 0) end
	elseif HEAL[sub] then
		local n = PlayerName(srcFlags, srcGUID, srcName)
		if n then
			cur.heal[n] = (cur.heal[n] or 0) + (r[12] or 0)
			cur.names[n] = true
		end
	elseif sub == "SPELL_INTERRUPT" then
		local n = PlayerName(srcFlags, srcGUID, srcName)
		if n then cur.inter[n] = (cur.inter[n] or 0) + 1 end
	elseif sub == "UNIT_DIED" then
		local t = PlayerName(dstFlags, dstGUID, dstName)
		if t then cur.deaths[t] = (cur.deaths[t] or 0) + 1 end
	end
end

function WL:StartCombat()
	cur = cur or NewFight()
end

function WL:EndCombat()
	if not cur then return end
	cur.dur = GetTime() - cur.t0
	if cur.dur < 8 or not next(cur.dmg) then cur = nil return end -- ignore trash blips
	cur.boss = UnitExists and UnitExists("target") and UnitName("target") or nil
	self.db.history[#self.db.history + 1] = cur
	while #self.db.history > MAX_HISTORY do tremove(self.db.history, 1) end
	cur = nil
	self:RefreshList()
	S:Print(format("%s %s (%ds) - %s", L["Fight recorded:"] or "Fight recorded:",
		cur and cur.zone or (self.db.history[#self.db.history].zone or "?"),
		floor(self.db.history[#self.db.history].dur or 0),
		L["type /suilog to view"] or "type /suilog to view"))
end

-- -------------------------------------------------------------------------
-- UI
local function SortDesc(t)
	local arr = {}
	for n, v in pairs(t or {}) do arr[#arr + 1] = { n = n, v = v } end
	table.sort(arr, function(a, b) return a.v > b.v end)
	return arr
end

local function FmtK(v)
	if v >= 1e6 then return format("%.2fM", v / 1e6) end
	if v >= 1e3 then return format("%.1fk", v / 1e3) end
	return format("%d", v)
end

local function BuildUI()
	if frame then return end
	local f = CreateFrame("Frame", "SentinelUIWarLogs", UIParent, S.BackdropTemplate)
	f:SetSize(560, 420)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	S:SetTemplate(f, "Default", "MEDIUM")
	f:EnableMouse(true)
	f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()

	local t = S:FontString(f, 12, "OUTLINE")
	t:SetPoint("TOP", 0, -8)
	t:SetText("|cffff5555War|r|cffffffffLogs|r")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	-- left: fight history
	local list = CreateFrame("Frame", nil, f)
	list:SetPoint("TOPLEFT", 8, -34)
	list:SetSize(190, 340)
	S:SetTemplate(list, "Default")
	f.listRows = {}
	for i = 1, 14 do
		local r = CreateFrame("Button", nil, list)
		r:SetSize(180, 22)
		r:SetPoint("TOPLEFT", 5, -((i - 1) * 24) - 4)
		S:SetTemplate(r, "Default")
		r.txt = S:FontString(r, 9, "OUTLINE")
		r.txt:SetPoint("LEFT", 4, 0)
		r:SetScript("OnClick", function() WL:ShowFight(r.fidx) end)
		f.listRows[i] = r
	end

	-- right: detail with tabs (damage / healing / deaths / interrupts)
	detail = CreateFrame("Frame", nil, f)
	detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
	detail:SetSize(348, 340)
	S:SetTemplate(detail, "Default")
	f.tabs = {}
	local tabDefs = { { "Damage", "dmg" }, { "Healing", "heal" }, { "Deaths", "deaths" }, { "Interrupts", "inter" } }
	for i, td in ipairs(tabDefs) do
		local tb = CreateFrame("Button", nil, detail)
		tb:SetSize(82, 18)
		tb:SetPoint("TOPLEFT", 4 + (i - 1) * 86, -3)
		S:SetTemplate(tb, "Default")
		tb.txt = S:FontString(tb, 9, "OUTLINE")
		tb.txt:SetAllPoints() tb.txt:SetText(td[1])
		tb.key = td[2]
		tb:SetScript("OnClick", function() WL.tab = tb.key WL:ShowFight(WL._lastIdx) end)
		f.tabs[i] = tb
	end
	f.detailRows = {}
	for i = 1, 12 do
		local r = S:FontString(detail, 9, "OUTLINE")
		r:SetPoint("TOPLEFT", 6, -((i - 1) * 26) - 26)
		r:SetJustifyH("LEFT")
		f.detailRows[i] = r
	end
	f.detailBars = {}
	for i = 1, 12 do
		local b = detail:CreateTexture(nil, "BACKGROUND")
		b:SetPoint("TOPLEFT", detail, "TOPLEFT", 6, -((i - 1) * 26) - 26)
		b:SetHeight(12)
		b:SetTexture(S.media.statusbar or "Interface/Buttons/WHITE8x8")
		b:SetVertexColor(0.4, 0.4, 0.4, 0.4)
		f.detailBars[i] = b
	end
	f.title = S:FontString(detail, 10, "OUTLINE")
	f.title:SetPoint("BOTTOM", 0, 6)

	-- bottom buttons
	local function Btn(txt, x, fn)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(96, 20)
		b:SetPoint("BOTTOMLEFT", x, 10)
		S:SetTemplate(b, "Default")
		local s = S:FontString(b, 9, "OUTLINE")
		s:SetAllPoints() s:SetText(txt)
		s:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
		b:SetScript("OnClick", fn)
		return b
	end
	Btn(L["Share in group"] or "Share in group", 8, function() WL:Share() end)
	Btn(L["Clear history"] or "Clear history", 110, function() wipe(WL.db.history) WL:RefreshList() end)
	Btn(L["Close"] or "Close", 464, function() f:Hide() end)
	frame = f
end

function WL:RefreshList()
	if not frame then return end
	local h = self.db.history
	for i, r in ipairs(frame.listRows) do
		local fi = #h - (i - 1) -- newest first
		local f = h[fi]
		if f then
			r.fidx = fi
			r.txt:SetText(format("%s  |cff888888%s  %ds|r", f.zone or "?", f.ts or "", floor(f.dur or 0)))
			r:Show()
		else r:Hide() end
	end
end

function WL:ShowFight(idx)
	local f = self.db.history[idx]
	if not f then return end
	WL._lastIdx = idx
	local tab = self.tab or "dmg"
	for _, tb in ipairs(frame.tabs) do
		tb.txt:SetTextColor(tb.key == tab and S.accent.r or 0.6, tb.key == tab and S.accent.g or 0.6, tb.key == tab and S.accent.b or 0.6)
	end
	local dur = f.dur or 1
	local data = tab == "dmg" and f.dmg or tab == "heal" and f.heal or tab == "deaths" and f.deaths or f.inter
	local arr = SortDesc(data)
	local mx = arr[1] and arr[1].v or 1
	local perSec = (tab == "dmg" or tab == "heal")
	for i, r in ipairs(frame.detailRows) do
		local e = arr[i]
		if e then
			local sec = perSec and format(" |cff888888(%s/s)|r", FmtK(e.v / dur)) or ""
			local dd = tab == "dmg" and (f.deaths[e.n] or 0)
			r:SetText(format("%d. %s: |cff00ff00%s|r%s%s", i, e.n, FmtK(e.v), sec,
				dd and dd > 0 and format(" |cffff5555(x%d)|r", dd) or ""))
			local b = frame.detailBars[i]
			b:SetWidth(330 * (e.v / mx))
			b:SetVertexColor(tab == "dmg" and 0.8 or 0.2, tab == "heal" and 0.6 or 0.3, tab == "deaths" and 0.15 or 0.9, 0.35)
			b:Show()
		else
			r:SetText("")
			frame.detailBars[i]:Hide()
		end
	end
	frame.title:SetText(format("%s - %s | %ds | %s %d",
		f.zone or "?", f.ts or "", floor(dur), L["players:"] or "players:",
		(function() local c = 0 for _ in pairs(f.names or {}) do c = c + 1 end return c end)()))
	WL._lastIdx = idx
end

-- -------------------------------------------------------------------------
-- sharing (AceSerializer over the addon channel)
function WL:Share()
	local f = self.db.history[WL._lastIdx or #self.db.history]
	if not f then S:Print(L["No fight to share."] or "No fight to share.") return end
	local ser = S.AceSerializer and S.AceSerializer:Serialize({
		zone = f.zone, dur = f.dur, dmg = f.dmg, heal = f.heal, deaths = f.deaths, from = S.myName,
	})
	if not ser then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage and ser:len() < 250 then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, ser, S.GroupChannel())
		S:Print(L["Fight report shared."] or "Fight report shared.")
	elseif ser:len() >= 250 then
		S:Print(L["Report too large to share."] or "Report too large to share.")
	end
end

function WL:OnAddonMsg(prefix, msg, _, sender)
	if prefix ~= PREFIX or not S.AceSerializer then return end
	local ok, rep = S.AceSerializer:Deserialize(msg)
	if not ok or type(rep) ~= "table" or not rep.zone then return end
	rep.shared, rep.ts = true, date("%H:%M:%S")
	rep.title = (sender or "?") .. " -> " .. rep.zone
	-- shared reports land in the same history ring, flagged
	rep.names = rep.names or {}
	self.db.history[#self.db.history + 1] = rep
	while #self.db.history > MAX_HISTORY do tremove(self.db.history, 1) end
	self:RefreshList()
	S:Print(format("%s %s", sender or "?", L["shared a fight report."] or "shared a fight report."))
end

function WL:Toggle()
	BuildUI()
	if frame:IsShown() then frame:Hide() else self:RefreshList() frame:Show() if #self.db.history > 0 then self:ShowFight(#self.db.history) end end
end

function WL:Initialize()
	self.db = S.db.profile.warlogs
	self.db.history = self.db.history or {}
	S:SafeCall("WarLogs:RegMsg", function()
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
			pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
		end
	end)
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCLE")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "StartCombat")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "EndCombat")
	self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMsg")
	SLASH_SUILOG1, SLASH_SUILOG2 = "/suilog", "/suiwarlogs"
	SlashCmdList.SUILOG = function() WL:Toggle() end
end
