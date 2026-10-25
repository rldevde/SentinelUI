--[[
	SentinelUI error log.
	All errors, taint/blocked actions and warnings caused by SentinelUI are stored in the
	SavedVariable "SentinelUILog". WoW writes it to disk on /reload or logout:
	  WTF\Account\<ACCOUNT>\SavedVariables\SentinelUI.lua
]]
local _, ns = ...
local S = ns.S
-- no cached L: this file loads before Locales/enUS.lua

local MAX_ENTRIES, MAX_SESSIONS, MAX_STACK = 200, 15, 1200
local pending, sessionId, notified = {}, nil, false
local strfind, strsub, gsub, tostring, date, time = string.find, string.sub, string.gsub, tostring, date, time

local function GetDB()
	return type(_G.SentinelUILog) == "table" and _G.SentinelUILog or nil
end

local function CleanStack(stack)
	if not stack then return nil end
	stack = gsub(stack, "Interface[\\/]AddOns[\\/]", "")
	stack = gsub(stack, "%[string \"@", "[")
	if #stack > MAX_STACK then stack = strsub(stack, 1, MAX_STACK) .. "\n..." end
	return stack
end

local function Location()
	local zone = GetRealZoneText and GetRealZoneText() or "?"
	local _, instanceType = IsInInstance()
	return zone .. (instanceType and instanceType ~= "none" and (" (" .. instanceType .. ")") or "")
end

local function Store(level, msg, context, stack)
	local db = GetDB()
	local entry = {
		level = level,
		msg = tostring(msg),
		context = context,
		stack = CleanStack(stack),
	}
	if not db then
		entry.time = date("%Y-%m-%d %H:%M:%S")
		pending[#pending + 1] = entry
		return
	end

	local key = entry.level .. "|" .. entry.msg .. "|" .. (entry.context or "")
	for i = #db.entries, math.max(1, #db.entries - 50), -1 do
		local e = db.entries[i]
		if e.key == key and e.session == sessionId then
			e.count = (e.count or 1) + 1
			e.last = date("%H:%M:%S")
			return e
		end
	end

	entry.key = key
	entry.count = 1
	entry.session = sessionId
	entry.time = entry.time or date("%Y-%m-%d %H:%M:%S")
	entry.combat = InCombatLockdown() or nil
	entry.location = Location()
	db.entries[#db.entries + 1] = entry
	while #db.entries > MAX_ENTRIES do tremove(db.entries, 1) end

	if level == "ERROR" and not notified and S.Print then
		notified = true
		S:Print("|cffff5555Fehler protokolliert.|r /sui log zum Anzeigen · /sui save schreibt ihn auf Disk.")
	end
	return entry
end

function S:LogError(err, context, stack)
	return Store("ERROR", err, context, stack)
end

function S:LogWarn(context, msg)
	return Store("WARN", msg, context)
end

function S:LogInfo(context, msg)
	return Store("INFO", msg, context)
end

function S:ClearLog()
	local db = GetDB()
	if db then wipe(db.entries) wipe(db.sessions) end
	self:Print("Log geleert.")
end

local function IsOurs(text)
	return text and (strfind(text, "SentinelUI", 1, true) ~= nil)
end

local function StartSession()
	_G.SentinelUILog = GetDB() or {}
	local db = _G.SentinelUILog
	db.entries = db.entries or {}
	db.sessions = db.sessions or {}
	db.info = "SentinelUI error log. Entries are written on /reload or logout."
	-- also trim on load, so oversized old logs shrink at the next reload
	while #db.entries > MAX_ENTRIES do tremove(db.entries, 1) end
	while #db.sessions > MAX_SESSIONS do tremove(db.sessions, 1) end

	local version, build, _, interface = GetBuildInfo()
	sessionId = (db.lastSession or 0) + 1
	db.lastSession = sessionId
	db.sessions[#db.sessions + 1] = {
		id = sessionId,
		start = date("%Y-%m-%d %H:%M:%S"),
		addon = S.version,
		client = S.flavor or "?",
		build = version .. "." .. build,
		interface = interface,
		locale = GetLocale(),
	}
	while #db.sessions > MAX_SESSIONS do tremove(db.sessions, 1) end
	for _, e in ipairs(pending) do Store(e.level, e.msg, e.context, e.stack) end
	wipe(pending)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
pcall(f.RegisterEvent, f, "LUA_WARNING")
f:SetScript("OnEvent", function(_, event, a1, a2)
	if event == "ADDON_LOADED" then
		if a1 == S.name then StartSession() end
	elseif event == "PLAYER_LOGIN" then
		local db = GetDB()
		local s = db and db.sessions[#db.sessions]
		if s then
			s.character = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
			s.class = select(2, UnitClass("player"))
			s.level = UnitLevel("player")
			local resolution = GetPhysicalScreenSize and table.concat({ GetPhysicalScreenSize() }, "x")
			s.resolution = resolution
			local others = {}
			local count = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or GetNumAddOns()
			for i = 1, count do
				local name, _, _, loaded = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
				if name and loaded and name ~= "SentinelUI" then others[#others + 1] = name end
			end
			s.otherUIAddons = #others > 0 and table.concat(others, ", ") or nil
		end
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		if a1 == S.name then
			Store("TAINT", event .. ": " .. tostring(a2), "Blocked", debugstack(2))
		end
	elseif event == "LUA_WARNING" then
		if IsOurs(a2) then Store("WARN", a2, "LUA_WARNING") end
	end
end)

-- Errors that escape SafeCall (e.g. inside secure hooks of Blizzard code) end up in the
-- global error handler. BugGrabber owns the handler when installed, so use its callback.
local function HookGlobalErrors()
	local bg = _G.BugGrabber
	if bg and bg.GetErrorByID and EventRegistry and EventRegistry.RegisterCallback then
		-- current BugGrabber: EventRegistry "BugGrabber.BugGrabbed" with the error table id
		EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, id)
			local err = bg:GetErrorByID(id)
			if err and (IsOurs(err.message) or IsOurs(err.stack)) then
				Store("ERROR", err.message, "Global", err.stack)
			end
		end, S)
		return
	end
	if bg and bg.RegisterCallback then
		bg.RegisterCallback(S, "BugGrabber_BugGrabbed", function(_, err)
			if err and (IsOurs(err.message) or IsOurs(err.stack)) then
				Store("ERROR", err.message, "Global", err.stack)
			end
		end)
		return
	end
	local original = geterrorhandler()
	seterrorhandler(function(msg, ...)
		if IsOurs(msg) then Store("ERROR", msg, "Global", debugstack(3)) end
		return original(msg, ...)
	end)
end
HookGlobalErrors()

-- In-game viewer: /sui log
local viewer
local function FormatEntries()
	local db = GetDB()
	if not db or #db.entries == 0 then return S.L["No entries."] end
	local lines = {}
	for i = #db.entries, 1, -1 do
		local e = db.entries[i]
		lines[#lines + 1] = format("[%s] #%s %s x%d  (%s)%s", e.time or "?", e.session or "?", e.level, e.count or 1, e.context or "-", e.combat and S.L[" [combat]"] or "")
		lines[#lines + 1] = e.msg
		if e.stack then lines[#lines + 1] = e.stack end
		lines[#lines + 1] = " "
	end
	return table.concat(lines, "\n")
end

-- copyable link popup (WoW can't open URLs: the text is preselected for Ctrl+C)
StaticPopupDialogs["SENTINELUI_LINK"] = {
	text = "%s",
	button1 = CLOSE or "Close",
	hasEditBox = true,
	editBoxWidth = 300,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnShow = function(self, data)
		data = data or self.data
		local eb = self.editBox or self.EditBox
		if not eb then return end
		eb:SetText(data or "")
		eb:SetFocus()
		eb:HighlightText()
		eb:SetScript("OnTextChanged", function(e) if e:GetText() ~= data then e:SetText(data or "") e:HighlightText() end end)
	end,
	OnHide = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetScript("OnTextChanged", nil) end
	end,
	EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function S:ShowLink(url, text)
	StaticPopup_Show("SENTINELUI_LINK", text or (S.L and S.L["Copy the link with Ctrl+C:"] or "Ctrl+C:"), nil, url)
end

function S:ShowBugtracker()
	self:ShowLink(self.bugtracker, S.L and S.L["Report bugs here (Ctrl+C to copy):"] or "Bugtracker (Ctrl+C):")
end

function S:ShowLog()
	if viewer and not viewer.edit then viewer = nil end -- recover from a half-built frame
	if not viewer then
		local f = CreateFrame("Frame", "SentinelUILogViewer", UIParent, "BackdropTemplate")
		f:SetSize(760, 460)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		if S.SetTemplate then pcall(S.SetTemplate, S, f, "Transparent", true) end
		tinsert(UISpecialFrames, "SentinelUILogViewer")

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 10, -8)
		title:SetText(S.title .. " - Fehlerprotokoll")

		local scroll = CreateFrame("ScrollFrame", "SentinelUILogScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 10, -30)
		scroll:SetPoint("BOTTOMRIGHT", -30, 40)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(710)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		f.edit = edit

		local function Button(text, point, x, onClick)
			local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			b:SetSize(110, 22)
			b:SetPoint(point, x, 10)
			b:SetText(text)
			b:SetScript("OnClick", onClick)
			if S.SkinButton then pcall(S.SkinButton, S, b) end
			return b
		end
		Button(S.L["Close"], "BOTTOMRIGHT", -10, function() f:Hide() end)
		Button(S.L["Clear"], "BOTTOMLEFT", 10, function() S:ClearLog() edit:SetText(FormatEntries()) end)
		Button(S.L["Reload"], "BOTTOMLEFT", 126, ReloadUI)
		Button(S.L["Select all"], "BOTTOMLEFT", 242, function() edit:SetFocus() edit:HighlightText() end)
		Button(S.L["Report bug"], "BOTTOMRIGHT", -126, function() S:ShowBugtracker() end)
		local hint = f:CreateFontString(nil, "OVERLAY")
		if hint.SetFontObject then pcall(hint.SetFontObject, hint, GameFontDisableSmall or GameFontNormalSmall or ChatFontNormal) end
		hint:SetPoint("TOPRIGHT", -12, -10)
		hint:SetText("Bugtracker: " .. (S.bugtracker or ""))
		viewer = f
	end
	viewer.edit:SetText(FormatEntries())
	viewer:Show()
end
