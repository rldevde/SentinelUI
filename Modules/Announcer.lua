-- Auto Announcer: scheduled chat messages (interval, channel) with a small
-- management window (/sui ann). Messages are stored account wide.
local _, ns = ...
local S = ns.S
local L = S.L
local AN = S:NewModule("Announcer", "announcer")

local _G = _G
local ipairs, pairs, tinsert, tremove = ipairs, pairs, table.insert, table.remove
local format, tonumber, gsub = string.format, tonumber, string.gsub

local C_Timer = C_Timer
local GetChannelName = GetChannelName
local GetChannelList = GetChannelList
local SendChatMessage = SendChatMessage
local InCombatLockdown = InCombatLockdown

local CHANNELS = { "SAY", "PARTY", "RAID", "RAID_WARNING", "GUILD", "YELL", "CHANNEL" }
local CHANNEL_LABEL = {
	SAY = "Say", PARTY = "Party", RAID = "Raid", RAID_WARNING = "RW",
	GUILD = "Guild", YELL = "Yell", CHANNEL = "Custom",
}
local ROW_H, VISIBLE_ROWS = 30, 9

local function store()
	local g = S.db and S.db.global
	if not g then return nil end
	g.announcer = g.announcer or { messages = {} }
	g.announcer.messages = g.announcer.messages or {}
	return g.announcer
end

local function messages()
	local st = store()
	return st and st.messages or {}
end

local function nextId()
	local max = 0
	for _, m in ipairs(messages()) do if (m.id or 0) > max then max = m.id end end
	return max + 1
end

-- is the destination usable right now?
local function channelAvailable(msg)
	local ch = msg.channel
	if ch == "SAY" or ch == "YELL" then return true end
	if ch == "PARTY" then return IsInGroup() and not IsInRaid() end
	if ch == "RAID" then return IsInRaid() end
	if ch == "RAID_WARNING" then
		return IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
	end
	if ch == "GUILD" then return IsInGuild() end
	if ch == "CHANNEL" then
		return msg.channelName and msg.channelName ~= "" and GetChannelName(msg.channelName) > 0
	end
	return IsInGroup()
end

function AN:PostMessage(msg)
	if not msg.text or msg.text == "" then return end
	if not channelAvailable(msg) then return end
	if msg.channel == "CHANNEL" then
		local chId = GetChannelName(msg.channelName)
		if chId > 0 then SendChatMessage(msg.text, "CHANNEL", nil, chId) end
	else
		SendChatMessage(msg.text, msg.channel)
	end
end

function AN:StartMessage(msg)
	self:StopMessage(msg)
	msg.active = true
	msg.interval = tonumber(msg.interval) or 5
	if msg.interval < 0.1 then msg.interval = 0.1 end
	self.timers[msg.id] = C_Timer.NewTicker(msg.interval * 60, function()
		S:SafeCall("Announcer:Post", AN.PostMessage, AN, msg)
	end)
	-- first post right away so the user gets feedback it is running
	self:PostMessage(msg)
end

function AN:StopMessage(msg)
	msg.active = false
	local t = self.timers[msg.id]
	if t then t:Cancel() self.timers[msg.id] = nil end
end

function AN:StopAll()
	for _, m in ipairs(messages()) do self:StopMessage(m) end
end

function AN:StartAll()
	for _, m in ipairs(messages()) do self:StartMessage(m) end
end

-- resume timers that were active before a reload
function AN:ResumeTimers()
	for _, m in ipairs(messages()) do
		if m.active then
			m.active = false
			self:StartMessage(m)
		end
	end
end

-- ── management window ────────────────────────────────────────────────

local function makeButton(parent, w, h, label)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	S:SkinButton(b)
	b.fs = S:FontString(b, 11)
	b.fs:SetPoint("CENTER")
	b.fs:SetWidth(w - 4)
	b.SetText = function(self, t) self.fs:SetText(t) end
	b:SetText(label)
	return b
end

local function makeEdit(parent, w)
	local eb = CreateFrame("EditBox", nil, parent)
	eb:SetSize(w, 20)
	eb:SetAutoFocus(false)
	eb:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
	S:SkinEditBox(eb)
	return eb
end

function AN:BuildWindow()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIAnnouncer", UIParent)
	f:SetSize(560, 60 + VISIBLE_ROWS * ROW_H)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetFrameStrata("DIALOG")
	S:SetTemplate(f, "Default")
	f:Hide()
	tinsert(UISpecialFrames, "SentinelUIAnnouncer")
	f.title = S:FontString(f, 13, "OUTLINE")
	f.title:SetText(L["Announcer"])
	f.title:SetPoint("TOPLEFT", 12, -10)

	local close = CreateFrame("Button", nil, f)
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", -8, -8)
	S:SkinCloseButton(close)
	close:SetScript("OnClick", function() f:Hide() end)

	local newBtn = makeButton(f, 60, 20, L["New"])
	newBtn:SetPoint("TOP", 0, -8)
	newBtn:SetScript("OnClick", function()
		tinsert(messages(), { id = nextId(), text = "", channel = "SAY", interval = 5, channelName = "", active = false })
		AN:RefreshRows()
	end)

	local startAll = makeButton(f, 70, 20, L["Start All"])
	startAll:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
	startAll:SetScript("OnClick", function() AN:StartAll() AN:RefreshRows() end)

	local stopAll = makeButton(f, 70, 20, L["Stop All"])
	stopAll:SetPoint("LEFT", startAll, "RIGHT", 6, 0)
	stopAll:SetScript("OnClick", function() AN:StopAll() AN:RefreshRows() end)

	-- column header
	local hdr = S:FontString(f, 10)
	hdr:SetText(L["On"] .. "  |  " .. L["Channel"] .. "  |  " .. L["Min"] .. "  |  " .. L["Message"])
	hdr:SetPoint("TOPLEFT", 12, -32)

	local scroll = CreateFrame("ScrollFrame", "SentinelUIAnnouncerScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -46)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	local sb = scroll.ScrollBar or _G[scroll:GetName() .. "ScrollBar"]
	if sb then S:SkinScrollBar(sb) end
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(520, VISIBLE_ROWS * ROW_H)
	scroll:SetScrollChild(child)
	f.child = child
	f.rows = {}
	self.frame = f
end

local chanMenu = CreateFrame("Frame", "SentinelAnnouncerChannelMenu",
	UIParent, "UIDropDownMenuTemplate")

-- channel picker: standard destinations plus every channel the player is
-- currently in (General, Trade, World, customs). "Custom..." keeps the
-- free-text box for names that are not joined
local function OpenChannelMenu(msg)
	UIDropDownMenu_Initialize(chanMenu, function(_, level)
		local info = UIDropDownMenu_CreateInfo()
		for _, ch in ipairs(CHANNELS) do
			if ch ~= "CHANNEL" then
				info.text = L[CHANNEL_LABEL[ch]] or ch
				info.checked = msg.channel == ch
				info.func = function() msg.channel = ch msg.channelName = "" AN:RefreshRows() end
				info.notCheckable = nil
				UIDropDownMenu_AddButton(info, level)
			end
		end
		local joined, customSel = {}, msg.channel == "CHANNEL"
		if GetChannelList then
			local cl = { GetChannelList() }
			for i = 1, #cl, 3 do
				local id, name = cl[i], cl[i + 1]
				if name and name ~= "" then
					tinsert(joined, { id = id, name = name })
					if name == msg.channelName then customSel = false end
				end
			end
		end
		if #joined > 0 then
			info = UIDropDownMenu_CreateInfo()
			info.text = L["Channels"] info.isTitle = true info.notCheckable = true
			info.checked = nil info.func = nil
			UIDropDownMenu_AddButton(info, level)
			table.sort(joined, function(a, b) return (a.id or 0) < (b.id or 0) end)
			for _, c in ipairs(joined) do
				info = UIDropDownMenu_CreateInfo()
				info.text = format("%d. %s", c.id or 0, c.name)
				info.checked = msg.channel == "CHANNEL" and msg.channelName == c.name
				info.func = function() msg.channel = "CHANNEL" msg.channelName = c.name AN:RefreshRows() end
				UIDropDownMenu_AddButton(info, level)
			end
		end
		info = UIDropDownMenu_CreateInfo()
		info.text = L["Custom..."]
		info.checked = customSel
		info.func = function() msg.channel = "CHANNEL" AN:RefreshRows() end
		UIDropDownMenu_AddButton(info, level)
	end)
	ToggleDropDownMenu(1, nil, chanMenu, "cursor", 0, 0)
end

function AN:GetRow(i)
	local row = self.frame.rows[i]
	if row then return row end
	local parent = self.frame.child
	row = CreateFrame("Frame", nil, parent)
	row:SetSize(520, ROW_H - 4)

	row.toggle = makeButton(row, 44, 18, "")
	row.toggle:SetPoint("LEFT", 0, 0)

	row.chanBtn = makeButton(row, 84, 18, "")
	row.chanBtn:SetPoint("LEFT", row.toggle, "RIGHT", 4, 0)

	row.chanName = makeEdit(row, 62)
	row.chanName:SetPoint("LEFT", row.chanBtn, "RIGHT", 4, 0)

	row.interval = makeEdit(row, 30)
	row.interval:SetPoint("LEFT", row.chanBtn, "RIGHT", 4, 0)
	row.interval:SetNumeric(true)
	row.interval:SetMaxLetters(4)

	row.text = makeEdit(row, 240)

	row.del = CreateFrame("Button", nil, row)
	row.del:SetSize(18, 18)
	row.del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	S:SkinCloseButton(row.del)

	self.frame.rows[i] = row
	return row
end

function AN:RefreshRows()
	if not self.frame then return end
	local list = messages()
	for i, msg in ipairs(list) do
		local row = self:GetRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
		row.msg = msg

		row.toggle:SetText(msg.active and "|cff66ff66" .. L["On"] .. "|r" or "|cff888888" .. L["Off"] .. "|r")
		row.toggle:SetScript("OnClick", function()
			if msg.active then AN:StopMessage(msg) else AN:StartMessage(msg) end
			AN:RefreshRows()
		end)

		local lbl = L[CHANNEL_LABEL[msg.channel]] or msg.channel
		if msg.channel == "CHANNEL" and msg.channelName and msg.channelName ~= "" then
			lbl = msg.channelName
		end
		row.chanBtn:SetText(lbl)
		row.chanBtn:SetScript("OnClick", function() OpenChannelMenu(msg) end)

		row.chanName:SetText(msg.channelName or "")
		row.chanName:SetShown(msg.channel == "CHANNEL")
		row.chanName:SetScript("OnEnterPressed", function(eb) msg.channelName = gsub(eb:GetText(), "^%s*(.-)%s*$", "%1") eb:ClearFocus() end)
		row.chanName:SetScript("OnEditFocusLost", function(eb) msg.channelName = gsub(eb:GetText(), "^%s*(.-)%s*$", "%1") end)

		row.interval:ClearAllPoints()
		if msg.channel == "CHANNEL" then
			row.interval:SetPoint("LEFT", row.chanName, "RIGHT", 4, 0)
		else
			row.interval:SetPoint("LEFT", row.chanBtn, "RIGHT", 4, 0)
		end
		row.interval:SetText(tostring(msg.interval or 5))
		row.interval:SetScript("OnEnterPressed", function(eb) msg.interval = tonumber(eb:GetText()) or 5 eb:ClearFocus() if msg.active then AN:StartMessage(msg) end end)
		row.interval:SetScript("OnEditFocusLost", function(eb) msg.interval = tonumber(eb:GetText()) or msg.interval end)

		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", row.interval, "RIGHT", 4, 0)
		row.text:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
		row.text:SetText(msg.text or "")
		row.text:SetScript("OnEnterPressed", function(eb) msg.text = eb:GetText() eb:ClearFocus() end)
		row.text:SetScript("OnEditFocusLost", function(eb) msg.text = eb:GetText() end)

		row.del:SetScript("OnClick", function()
			AN:StopMessage(msg)
			tremove(list, i)
			AN:RefreshRows()
		end)
		row:Show()
	end
	for i = #list + 1, #self.frame.rows do self.frame.rows[i]:Hide() end
	self.frame.child:SetHeight(math.max(#list, 1) * ROW_H)
end

function AN:ToggleWindow()
	self:BuildWindow()
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self:RefreshRows()
		self.frame:Show()
	end
end

function AN:Initialize()
	self.db = S.db.profile.announcer or {}
	if self.db.enable == false then return end
	self.timers = {}
	-- minimap button (like RLAutoAnnouncer's launcher)
	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "announcer", glyph = "AN",
		store = self.private.minimap, angle = 200,
		onLeft = function() AN:ToggleWindow() end,
		onRight = function() AN:StopAll() S:Print(L["Stop All"]) end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. L["Announcer"])
			GameTooltip:AddLine(L["Left-click: open  |  Right-click: stop all  |  Drag: move"], 1, 1, 1)
		end,
	})
	-- timers resume after login once channel info is reliable
	C_Timer.After(5, function() S:SafeCall("Announcer:Resume", AN.ResumeTimers, AN) end)
	SlashCmdList.SENTINELUIANN = function(msg)
		msg = (msg or ""):gsub("^%s*", ""):lower()
		if msg == "start" then AN:StartAll()
		elseif msg == "stop" then AN:StopAll()
		else AN:ToggleWindow() end
		if msg == "start" or msg == "stop" then AN:RefreshRows() end
	end
	SLASH_SENTINELUIANN1 = "/suiann"
	SLASH_SENTINELUIANN2 = "/sann"
end
