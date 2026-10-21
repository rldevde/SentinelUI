-- BugFolder: internal BugGrabber + BugSack replacement. Captures every Lua
-- error from ALL addons (not just SentinelUI), deduplicates them, keeps
-- stack/locals and shows them in a Sentinel-styled sack window with tabs,
-- search, prev/next navigation, wipe and an export view.
--
-- The grabber installs itself at file scope (SavedVariables are loaded, but
-- S.db is not yet): load-time errors land in `loadErrors` and get merged into
-- the account db during Initialize - same semantics as !BugGrabber.
local _, ns = ...
local S = ns.S
local L = S.L
local BF = S:NewModule("BugFolder", "bugfolder")
local pairs, ipairs, wipe, sort = pairs, ipairs, wipe, table.sort
local tinsert, tremove, tconcat = tinsert, table.remove, table.concat
local format, date, tostring, tonumber = format, date, tostring, tonumber
local strfind, strlower, strtrim = string.find, string.lower, strtrim
local time, GetTime = time, GetTime
local CreateFrame, UIParent = CreateFrame, UIParent
local GameTooltip = GameTooltip
local PlaySound, PlaySoundFile = PlaySound, PlaySoundFile
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown, IsAltKeyDown = IsShiftKeyDown, IsAltKeyDown
local UnitName = UnitName
local debugstack, debuglocals = debugstack, debuglocals
local GetCallstackHeight, GetErrorCallstackHeight = GetCallstackHeight, GetErrorCallstackHeight
local ReloadUI = ReloadUI

local MAX_ERRORS = 500
local ERRORS_PER_SEC = 10

----------------------------------------------------------------------
-- Error capture (file scope: catches load errors of other addons too)
----------------------------------------------------------------------
local loadErrors = {}
local paused
local msgsAllowed = ERRORS_PER_SEC
local msgsAllowedLast = GetTime()
local lastWarn = 0
local lastErrTime = 0

local function ErrorDB()
	return BF.store or loadErrors
end

function BF:GetSessionId()
	local gb = S.db and S.db.global.bugFolder
	return (gb and gb.session) or -1
end

local function GetErrorStack()
	local cur = GetCallstackHeight and GetCallstackHeight()
	local errH = GetErrorCallstackHeight and GetErrorCallstackHeight()
	if cur and errH then
		local level = cur - (errH - 1)
		return debugstack(level), level
	end
	return debugstack(3), 3
end

local function ExtractAddon(stack)
	if not stack or stack == "" then return nil end
	for line in stack:gmatch("[^\n]+") do
		local addon = line:match("[Ii]nterface[\\/]AddOns[\\/]([^\\/%s]+)[\\/]")
		if addon then return addon end
	end
end
BF.ExtractAddon = ExtractAddon

local function FindError(database, message)
	for i = #database, 1, -1 do
		local e = database[i]
		if e.message == message then return e, i end
	end
end

local function StoreError(err)
	local store = ErrorDB()
	store[#store + 1] = err
	if #store > MAX_ERRORS then tremove(store, 1) end
end

-- Blizzard_FrameXML/GuildUtil.lua:99 - the guild news list formats an event
-- type the classic client has no string for (nil formatString); fires on
-- every GUILD_NEWS_UPDATE while the Communities frame exists.
BF.blizzardNoise = {
	"Blizzard_FrameXML/GuildUtil.lua:99: attempt to index local 'formatString'",
}

local function GrabError(errorMessage, isSimple, forcedAddon)
	local db = BF.db
	if db and db.throttle then
		msgsAllowed = msgsAllowed + (GetTime() - msgsAllowedLast) * ERRORS_PER_SEC
		msgsAllowedLast = GetTime()
		if msgsAllowed < 1 then
			if not paused and GetTime() > lastWarn + 10 then
				lastWarn = GetTime()
				paused = true
				S:Print("|cffffff00" .. L["There are too many errors in your UI - error capture is throttled. Disable or update the failing addons."] .. "|r")
			end
			return
		end
		paused = false
		if msgsAllowed > ERRORS_PER_SEC then msgsAllowed = ERRORS_PER_SEC end
		msgsAllowed = msgsAllowed - 1
	end

	errorMessage = tostring(errorMessage)
	if S.IsSecret and S.IsSecret(errorMessage) then return end
	-- known client-side bugs that no addon can fix (pure Blizzard stacks) are
	-- dropped so they do not bury real errors
	for _, pat in ipairs(BF.blizzardNoise) do
		if strfind(errorMessage, pat, 1, true) then return end
	end

	local store = ErrorDB()
	local errorObject, pos = FindError(store, errorMessage)
	local session = BF:GetSessionId()

	if not errorObject then
		errorObject = { message = errorMessage, session = session, time = time(), counter = 1 }
		StoreError(errorObject)
		if not isSimple then
			local stack, level = GetErrorStack()
			errorObject.stack = stack or "Debugstack was nil."
			errorObject.addon = forcedAddon or ExtractAddon(stack)
			errorObject.locals = (debuglocals and debuglocals(level)) or nil
		end
	else
		errorObject.counter = (errorObject.counter or 1) + 1
		local cur = time()
		local elapsed = cur - (errorObject.time or cur)
		errorObject.time = cur
		if errorObject.session ~= session then
			tremove(store, pos)
			StoreError(errorObject)
			errorObject.session = session
			if not isSimple then
				local stack, level = GetErrorStack()
				errorObject.stack = stack or "Debugstack was nil."
				errorObject.addon = forcedAddon or ExtractAddon(stack)
				errorObject.locals = (debuglocals and debuglocals(level)) or nil
			end
			BF:PrintChatLink(errorObject)
		elseif elapsed > 10 then
			tremove(store, pos)
			StoreError(errorObject)
			if elapsed > 30 then
				BF:PrintChatLink(errorObject)
				if not isSimple and elapsed > 120 then
					local stack, level = GetErrorStack()
					errorObject.stack = stack or "Debugstack was nil."
					errorObject.addon = forcedAddon or ExtractAddon(stack)
					errorObject.locals = (debuglocals and debuglocals(level)) or nil
				end
			end
		end
	end

	-- BugGrabber-compat: anything else listening still gets notified
	if EventRegistry and EventRegistry.TriggerEvent then
		EventRegistry:TriggerEvent("BugGrabber.BugGrabbed", nil, tostring(errorObject))
	end
	BF:OnBugGrabbed(errorObject)
end
BF.GrabError = GrabError

function BF:GetErrors(sessionId)
	local store = ErrorDB()
	if not sessionId then return store end
	local out = {}
	for i, e in ipairs(store) do
		if e.session == sessionId then out[#out + 1] = e end
	end
	return out
end

function BF:Wipe(silent)
	wipe(ErrorDB())
	wipe(loadErrors)
	if not silent then S:Print(L["All stored bugs have been exterminated."]) end
	BF:UpdateDisplay()
end

----------------------------------------------------------------------
-- Formatting + chat links: [Error x] clickable -> prints the error
----------------------------------------------------------------------
function BF:FormatError(err)
	if not err then return "" end
	local msg = tostring(err.message) .. (err.stack and ("\n" .. tostring(err.stack)) or "")
	msg = msg:gsub("[%.I][%.n][%.t][%.e][%.r]face/", ""):gsub("%.?%.?%.?/?AddOns/", "")
	msg = msg:gsub("|([^chHr])", "||%1")
	msg = msg:gsub("([^/]+%.lua)", "|cffffffff%1|r")
	msg = msg:gsub(":(%d+)", ":|cff00ff00%1|r")
	local head = (err.addon and ("|cffffea00[" .. err.addon .. "]|r ") or "")
	local out = format("%dx %s%s", err.counter or 1, head, msg)
	if err.locals and err.locals ~= "" then
		local lo = tostring(err.locals):gsub("[%.I][%.n][%.t][%.e][%.r]face/", ""):gsub("%.?%.?%.?/?AddOns/", "")
		lo = lo:gsub("|(%a)", "||%1")
		lo = lo:gsub("> @(.-):(%d+)", "> @|cffeda55f%1|r:|cff00ff00%2|r")
		out = out .. "\n\nLocals:\n" .. lo
	end
	return out
end

function BF:PrintChatLink(err)
	local idx = 0
	local store = ErrorDB()
	for i, e in ipairs(store) do if e == err then idx = i break end end
	if idx == 0 then return end
	S:Print(format("|Haddon:suibug:%d|h|cffff0000[%s %d]|r|h |cffffff00%s|r", idx, L["Error"], err.counter or 1, L["captured - click the link for details"]))
end

hooksecurefunc("SetItemRef", function(link)
	local idx = link:match("^addon:suibug:(%d+)")
	if idx then
		local e = ErrorDB()[tonumber(idx)]
		if e then print(BF:FormatError(e)) end
	end
end)

----------------------------------------------------------------------
-- Error-source events (file scope, protected from outside unregister)
----------------------------------------------------------------------
local badAddons = {}
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
evFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
evFrame:RegisterEvent("MACRO_ACTION_BLOCKED")
evFrame:RegisterEvent("MACRO_ACTION_FORBIDDEN")
evFrame:RegisterEvent("LUA_WARNING")
evFrame:RegisterEvent("UI_ERROR_MESSAGE")
evFrame:SetScript("OnEvent", function(_, event, a, b)
	if event == "LUA_WARNING" then
		GrabError("LUA_WARNING: " .. tostring(b or a or ""), true)
	elseif event == "UI_ERROR_MESSAGE" then
		local msg = tostring(b or a or "")
		local low = strlower(msg)
		if strfind(low, "addon", 1, true) or strfind(low, "interface", 1, true)
			or strfind(low, "script", 1, true) or strfind(low, "protected", 1, true) then
			GrabError("UI_ERROR: " .. msg, true)
		end
	else
		-- ADDON_ACTION_BLOCKED / _FORBIDDEN / MACRO_ACTION_*
		if BF.db and BF.db.filterAddonMistakes then return end
		local name = tostring(a or "<name>")
		if not badAddons[name] then
			badAddons[name] = true
			GrabError(format("[%s] %s '%s': %s", event, L["Addon"], name, tostring(b or "<func>")), false, name)
		end
	end
end)
evFrame.RegisterEvent = function() end
evFrame.UnregisterEvent = function() end
evFrame.SetScript = function() end

-- Blizzard would surface the same warnings/errors itself
if UIParent.UnregisterEvent then
	UIParent:UnregisterEvent("ADDON_ACTION_FORBIDDEN")
	UIParent:UnregisterEvent("ADDON_ACTION_BLOCKED")
	UIParent:UnregisterEvent("MACRO_ACTION_FORBIDDEN")
	UIParent:UnregisterEvent("MACRO_ACTION_BLOCKED")
end
if ScriptErrorsFrame and ScriptErrorsFrame.UnregisterEvent then
	ScriptErrorsFrame:UnregisterEvent("LUA_WARNING")
end

----------------------------------------------------------------------
-- Handler install: standalone mode (or mirror mode if !BugGrabber exists)
----------------------------------------------------------------------
local real_seterrorhandler = seterrorhandler

if _G.BugGrabber then
	-- an external BugGrabber owns the error handler: mirror its db instead
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, tableID)
			for _, err in next, BugGrabber:GetDB() do
				if tostring(err) == tableID then
					if not FindError(ErrorDB(), err.message) then
						StoreError({ message = err.message, session = err.session, time = err.time,
							counter = err.counter or 1, stack = err.stack, locals = err.locals,
							addon = err.addon or ExtractAddon(err.stack or "") })
					end
					BF:OnBugGrabbed(err)
					break
				end
			end
		end, BF)
	end
else
	real_seterrorhandler(GrabError)
	_G.seterrorhandler = function() end
end

-- BugGrabber-compatible global so other addons find what they expect
if not _G.BugGrabber then
	_G.BugGrabber = {
		GetDB = function() return ErrorDB() end,
		GetSessionId = function() return BF:GetSessionId() end,
		IsPaused = function() return paused end,
		Reset = function() BF:Wipe(true) end,
		GetErrorByID = function(_, id)
			local store = ErrorDB()
			for i = #store, 1, -1 do
				if tostring(store[i]) == id then return store[i] end
			end
		end,
	}
end

----------------------------------------------------------------------
-- Notification
----------------------------------------------------------------------
local function PlayErrorSound()
	local db = BF.db
	if not db or db.mute then return end
	local chan = db.useMaster and "Master" or nil
	if db.errorSound and db.errorSound ~= "None" then
		local file = S:Fetch("sound", db.errorSound, "Sentinel Warning")
		if file then pcall(PlaySoundFile, file, chan) return end
	end
	PlaySound(846, chan)
end

function BF:OnBugGrabbed()
	local now = GetTime()
	if now > lastErrTime + 2 then
		lastErrTime = now
		PlayErrorSound()
		if self.db and self.db.chatframe then
			S:Print("|cffff5555" .. L["There's a bug in your soup!"] .. "|r")
		end
	end
	if self.db and self.db.auto and not InCombatLockdown() then
		self:OpenSack()
	end
	self:UpdateDisplay()
end

----------------------------------------------------------------------
-- Sack window (Sentinel look, same layout language as /sui log)
----------------------------------------------------------------------
local window
local state = "ALL"
local searchResults = {}
local searchThrough
local curIndex, curContents, curSession, curObject
local countFS, sessionFS, textArea, prevBtn, nextBtn, searchBox
local tabs = {}

local function Contents()
	if state == "SESSION" then return BF:GetErrors(BF:GetSessionId())
	elseif state == "LAST" then return BF:GetErrors(BF:GetSessionId() - 1)
	elseif state == "SEARCH" then return searchResults
	end
	return BF:GetErrors()
end

local function NavState(btn, enabled)
	btn:SetEnabled(enabled)
	btn:SetAlpha(enabled and 1 or 0.4)
end

local function Refresh()
	curContents = Contents()
	curSession = BF:GetSessionId()
	local size = #curContents
	curObject = curIndex and curContents[curIndex]
	if not curObject then curIndex = size curObject = curContents[size] end
	if curObject and curObject.session then curSession = curObject.session end

	if size > 0 and curObject then
		local when = (curObject.session == BF:GetSessionId()) and L["Today"] or date("%H:%M:%S", curObject.time or time())
		sessionFS:SetText(format("%s - |cffff4444%s|r - |cff44ff44%s|r", when, curObject.addon or L["Unknown"], tostring(curObject.session or "?")))
		countFS:SetText(format("%d/%d", curIndex or 0, size))
		textArea:SetText(BF:FormatError(curObject))
		textArea:HighlightText(0, 0)
	else
		sessionFS:SetText(format("%s (Session %d)", L["Today"], BF:GetSessionId()))
		countFS:SetText("")
		textArea:SetText(L["You have no bugs, yay!"])
	end
	NavState(nextBtn, curIndex and curIndex < size)
	NavState(prevBtn, curIndex and curIndex > 1)

	for _, t in pairs(tabs) do
		local active = state == t.key
		t.text:SetTextColor(1, active and 0.82 or 0.82, 0)
		if not active then t.text:SetTextColor(0.75, 0.75, 0.75) end
		if t.suiBackdrop then
			local bc = S.media.borderColor
			t.suiBackdrop:SetBackdropBorderColor(active and S.accent.r or bc[1], active and S.accent.g or bc[2], active and S.accent.b or bc[3], 1)
		end
	end
end

function BF:UpdateDisplay()
	if window and window:IsShown() then Refresh() end
end

local function MakeBtn(parent, text, w, h)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(w, h)
	btn:SetText(text)
	S:SkinButton(btn)
	return btn
end

local function MakeTab(key, text, x)
	local t = MakeBtn(window, text, 132, 22)
	t.key = key
	t:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", x, -26)
	t.text = t:GetFontString()
	t:SetScript("OnClick", function() state = key curIndex = nil Refresh() end)
	tabs[#tabs + 1] = t
	return t
end

local function CreateWindow()
	if window then return end
	window = CreateFrame("Frame", "SentinelUIBugFolder", UIParent)
	window:SetSize(820, 430)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetMovable(true)
	window:EnableMouse(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	S:SetTemplate(window, "Transparent", true)
	tinsert(UISpecialFrames, "SentinelUIBugFolder")

	local title = window:CreateFontString(nil, "OVERLAY")
	S:SetFont(title, S.media.font, 14, "OUTLINE")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetText("|cff" .. S.accentHex .. "SentinelUI|r |cffff5555BugFolder|r")

	sessionFS = window:CreateFontString(nil, "OVERLAY")
	S:SetFont(sessionFS, S.media.font, 12, "OUTLINE")
	sessionFS:SetPoint("TOP", window, "TOP", 0, -9)

	countFS = window:CreateFontString(nil, "OVERLAY")
	S:SetFont(countFS, S.media.font, 12, "OUTLINE")
	countFS:SetPoint("TOPRIGHT", -32, -9)
	countFS:SetJustifyH("RIGHT")

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	S:SkinCloseButton(close, window)
	close:SetScript("OnClick", function() window:Hide() end)

	-- scrollable error text
	local scroll = CreateFrame("ScrollFrame", "SentinelUIBugScroll", window, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -30)
	scroll:SetPoint("BOTTOMRIGHT", -28, 78)
	if scroll.ScrollBar then S:SkinScrollBar(scroll.ScrollBar) end

	textArea = CreateFrame("EditBox", nil, scroll)
	textArea:SetAutoFocus(false)
	textArea:SetMultiLine(true)
	textArea:SetMaxLetters(99999)
	textArea:EnableMouse(true)
	S:SetFont(textArea, S.media.font, BF.db and BF.db.fontSize or 12, "NONE")
	textArea:SetWidth(760)
	textArea:SetHeight(2000)
	textArea:SetTextInsets(4, 4, 4, 4)
	textArea:SetScript("OnEscapePressed", textArea.ClearFocus)
	textArea:SetScript("OnTextChanged", function(self, user) if user then self:SetText(BF:FormatError(curObject)) end end)
	scroll:SetScrollChild(textArea)
	window.textArea = textArea

	-- search box (hidden, toggled by Filter button)
	searchBox = CreateFrame("EditBox", nil, window)
	searchBox:SetSize(300, 22)
	searchBox:SetPoint("TOP", window, "TOP", 0, -5)
	searchBox:SetAutoFocus(false)
	searchBox:SetMaxLetters(60)
	S:SkinEditBox(searchBox)
	searchBox:SetScript("OnShow", function(self) self:SetFocus() end)
	searchBox:SetScript("OnEscapePressed", function(self) self:Hide() self:SetText("") state = "ALL" curIndex = nil Refresh() end)
	searchBox:SetScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or "")
		wipe(searchResults)
		if text == "" then
			state = "ALL"
		else
			for _, err in ipairs(searchThrough or BF:GetErrors()) do
				if (err.message and strfind(err.message, text, 1, true)) or (err.stack and strfind(err.stack, text, 1, true)) or (err.locals and strfind(err.locals, text, 1, true)) then
					searchResults[#searchResults + 1] = err
				end
			end
			state = "SEARCH"
		end
		curIndex = nil
		Refresh()
	end)
	searchBox:Hide()

	-- bottom toolbar
	prevBtn = MakeBtn(window, L["< Previous"], 110, 24)
	prevBtn:SetPoint("BOTTOMLEFT", 10, 12)
	prevBtn:SetScript("OnClick", function()
		curIndex = IsShiftKeyDown() and 1 or (curIndex or 1) - 1
		Refresh()
	end)

	nextBtn = MakeBtn(window, L["Next >"], 110, 24)
	nextBtn:SetPoint("BOTTOMRIGHT", -10, 12)
	nextBtn:SetScript("OnClick", function()
		curIndex = IsShiftKeyDown() and #(curContents or {}) or (curIndex or 0) + 1
		Refresh()
	end)

	local wipeBtn = MakeBtn(window, L["Wipe bugs"], 110, 24)
	wipeBtn:SetPoint("BOTTOM", 0, 12)
	wipeBtn:SetScript("OnClick", function() BF:Wipe() end)

	local filterBtn = MakeBtn(window, L["Filter"], 80, 24)
	filterBtn:SetPoint("BOTTOMLEFT", 128, 12)
	filterBtn:SetScript("OnClick", function()
		searchThrough = curContents
		searchBox:SetShown(not searchBox:IsShown())
	end)

	local exportBtn = MakeBtn(window, L["Export"], 80, 24)
	exportBtn:SetPoint("BOTTOMRIGHT", -98, 12)
	exportBtn:SetScript("OnClick", function() BF:OpenExport() end)

	local settingsBtn = MakeBtn(window, L["Settings"], 80, 24)
	settingsBtn:SetPoint("BOTTOMRIGHT", -186, 12)
	settingsBtn:SetScript("OnClick", function() S:ToggleConfig("bugfolder") end)

	-- report the shown error to the bugtracker (ready-to-paste ticket + url)
	local reportBtn = MakeBtn(window, L["Report"], 80, 24)
	reportBtn:SetPoint("BOTTOMLEFT", 216, 12)
	reportBtn:SetScript("OnClick", function() BF:OpenReport(curObject) end)
	reportBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Report to bugtracker"])
		GameTooltip:AddLine(L["Opens a ready-to-paste report for the shown error together with the tracker link."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	reportBtn:SetScript("OnLeave", GameTooltip_Hide)

	-- tabs under the window edge
	MakeTab("ALL", L["All bugs"], 10)
	MakeTab("SESSION", L["Current session"], 150)
	MakeTab("LAST", L["Previous session"], 290)

	window:SetScript("OnShow", function() PlaySound(844) end)
	window:SetScript("OnHide", function() curObject, curContents, curSession, curIndex = nil, nil, nil, nil end)
end

function BF:OpenSack()
	CreateWindow()
	if not window:IsShown() then window:Show() end
	Refresh()
end

function BF:CloseSack()
	if window then window:Hide() end
end

----------------------------------------------------------------------
-- Export viewer (plain text, copyable)
----------------------------------------------------------------------
local exportFrame
local function MatchesFilter(e, f)
	if not f or f == "" then return true end
	f = strlower(f)
	return strfind(strlower(e.message or ""), f, 1, true) or strfind(strlower(e.stack or ""), f, 1, true)
end

function BF:BuildExportText(filter)
	local store = ErrorDB()
	if #store == 0 then return L["No errors saved."] end
	local lines = { "SentinelUI BugFolder Export" }
	if filter and filter ~= "" then tinsert(lines, L["Filter"] .. ": " .. filter) end
	tinsert(lines, "")
	local n = 0
	for _, e in ipairs(store) do
		if MatchesFilter(e, filter) then
			n = n + 1
			tinsert(lines, format("#%d | Session %s | %s", n, tostring(e.session), e.time and date("%Y-%m-%d %H:%M:%S", e.time) or "?"))
			tinsert(lines, "Addon: " .. (e.addon or L["Unknown"]))
			tinsert(lines, "Message: " .. (e.message or ""))
			if e.stack and e.stack ~= "" then tinsert(lines, "Stack:") tinsert(lines, e.stack) end
			if e.locals and e.locals ~= "" then tinsert(lines, "Locals:") tinsert(lines, e.locals) end
			tinsert(lines, ("-"):rep(40))
		end
	end
	if n == 0 then return L["No errors found for filter"] .. ": " .. tostring(filter) end
	return tconcat(lines, "\n")
end

function BF:AddonSummary()
	local counts = {}
	for _, e in ipairs(ErrorDB()) do
		local n = e.addon or L["Unknown"]
		counts[n] = (counts[n] or 0) + 1
	end
	local list = {}
	for n in pairs(counts) do list[#list + 1] = n end
	sort(list, function(a, b) return strlower(a) < strlower(b) end)
	local lines = { L["Addon Summary"] .. ":" }
	for _, n in ipairs(list) do tinsert(lines, format("  %s: %d", n, counts[n])) end
	return tconcat(lines, "\n")
end

----------------------------------------------------------------------
-- Bugtracker report: a ready-to-paste ticket for the current error
-- (environment + error + stack + locals) plus the tracker URL
----------------------------------------------------------------------
function BF:BuildReportText(err)
	local lines = { "=== SentinelUI Bug Report ===" }
	tinsert(lines, L["Bugtracker"] .. ": " .. tostring(S.bugtracker))
	tinsert(lines, "")
	local ver, build, _, toc = GetBuildInfo()
	tinsert(lines, format("SentinelUI %s | %s | client %s (%s) toc %s | locale %s | uiScale %.2f",
		tostring(S.version), tostring(S.flavor), tostring(ver), tostring(build), tostring(toc), tostring(GetLocale()),
		UIParent and UIParent:GetEffectiveScale() or 1))
	local _, class = UnitClass("player")
	tinsert(lines, format("%s %s lvl %s | %s", tostring(UnitRace("player")), tostring(class), tostring(UnitLevel("player")), tostring(GetRealmName())))
	local others, total = {}, 0
	local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
	for i = 1, num do
		local name, _, _, loadable = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
		local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)(i)
		if loaded and name ~= S.name and not strfind(name, "^Blizzard_") then total = total + 1 if total <= 25 then others[#others + 1] = name end end
	end
	tinsert(lines, format(L["Other addons (%d)"], total) .. ": " .. (#others > 0 and tconcat(others, ", ") or "-") .. (total > #others and ", ..." or ""))
	tinsert(lines, "")
	if err then
		tinsert(lines, format("Error (x%d, session %s, %s)", err.counter or 1, tostring(err.session), err.time and date("%Y-%m-%d %H:%M:%S", err.time) or "?"))
		tinsert(lines, "Addon: " .. (err.addon or L["Unknown"]))
		tinsert(lines, "Message: " .. (err.message or ""))
		if err.stack and err.stack ~= "" then tinsert(lines, "") tinsert(lines, "Stack:") tinsert(lines, err.stack) end
		if err.locals and err.locals ~= "" then tinsert(lines, "") tinsert(lines, "Locals:") tinsert(lines, err.locals) end
	else
		tinsert(lines, L["No error selected - describe the problem here:"])
		tinsert(lines, "")
	end
	tinsert(lines, "")
	tinsert(lines, L["Steps to reproduce:"])
	tinsert(lines, "1. ")
	tinsert(lines, "2. ")
	return tconcat(lines, "\n")
end

function BF:OpenReport(err)
	self:OpenExport(nil, self:BuildReportText(err), true)
end

function BF:OpenExport(filter, text, isReport)
	if not exportFrame then
		local f = CreateFrame("Frame", "SentinelUIBugExport", UIParent)
		f:SetSize(700, 440)
		f:SetPoint("CENTER")
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:SetClampedToScreen(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		S:SetTemplate(f, "Transparent", true)
		tinsert(UISpecialFrames, "SentinelUIBugExport")

		local title = f:CreateFontString(nil, "OVERLAY")
		S:SetFont(title, S.media.font, 14, "OUTLINE")
		title:SetPoint("TOPLEFT", 10, -8)
		f.title = title

		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		S:SkinCloseButton(close, f)
		close:SetScript("OnClick", function() f:Hide() end)

		-- tracker url row (report mode only): single-line box, preselected for Ctrl+C
		local urlLabel = f:CreateFontString(nil, "OVERLAY")
		S:SetFont(urlLabel, S.media.font, 12, "OUTLINE")
		urlLabel:SetPoint("TOPLEFT", 10, -32)
		urlLabel:SetText(L["Bugtracker"] .. ":")
		local url = CreateFrame("EditBox", nil, f)
		url:SetSize(420, 22)
		url:SetPoint("LEFT", urlLabel, "RIGHT", 8, 0)
		url:SetAutoFocus(false)
		S:SkinEditBox(url)
		url:SetScript("OnEscapePressed", url.ClearFocus)
		url:SetScript("OnTextChanged", function(self, user) if user then self:SetText(S.bugtracker) self:HighlightText() end end)
		url:SetScript("OnMouseUp", function(self) self:HighlightText() end)
		local copyHint = f:CreateFontString(nil, "OVERLAY")
		S:SetFont(copyHint, S.media.font, 11)
		copyHint:SetPoint("LEFT", url, "RIGHT", 8, 0)
		copyHint:SetText("|cff888888" .. L["Ctrl+C"] .. "|r")
		f.urlRow = { urlLabel, url, copyHint }
		f.url = url

		local scroll = CreateFrame("ScrollFrame", "SentinelUIBugExportScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 10, -30)
		scroll:SetPoint("BOTTOMRIGHT", -28, 30)
		f.scroll = scroll
		if scroll.ScrollBar then S:SkinScrollBar(scroll.ScrollBar) end

		local eb = CreateFrame("EditBox", nil, scroll)
		eb:SetAutoFocus(false)
		eb:SetMultiLine(true)
		eb:SetMaxLetters(0)
		eb:EnableMouse(true)
		S:SetFont(eb, S.media.font, 11, "NONE")
		eb:SetWidth(640)
		eb:SetHeight(3000)
		eb:SetTextInsets(4, 4, 4, 4)
		eb:SetScript("OnEscapePressed", eb.ClearFocus)
		scroll:SetScrollChild(eb)
		f.editBox = eb

		local hint = f:CreateFontString(nil, "OVERLAY")
		S:SetFont(hint, S.media.font, 11, "OUTLINE")
		hint:SetPoint("BOTTOM", 0, 8)
		hint:SetText("|cff888888" .. L["Ctrl+A to select all, Ctrl+C to copy."] .. "|r")
		exportFrame = f
	end
	local f = exportFrame
	f.title:SetText("|cff" .. S.accentHex .. "SentinelUI|r BugFolder |cffaaaaaa" .. (isReport and L["Report"] or L["Export"]) .. "|r")
	for _, w in ipairs(f.urlRow) do w:SetShown(isReport and true or false) end
	f.scroll:SetPoint("TOPLEFT", 10, isReport and -58 or -30)
	if isReport then f.url:SetText(S.bugtracker or "") end
	f.editBox:SetText(text or BF:BuildExportText(filter))
	f.editBox:HighlightText(0, 0)
	f:Show()
	if isReport then f.url:SetFocus() f.url:HighlightText() end
end

----------------------------------------------------------------------
-- Minimap button + module lifecycle
----------------------------------------------------------------------
function BF:CreateMinimapBtn()
	if self.minimapBtn then return end
	local store = S.db.global.bugFolder.minimap
	self.minimapBtn = S:CreateMinimapButton({
		name = "BugFolder",
		glyph = "BF",
		angle = 200,
		store = store,
		onLeft = function()
			if IsShiftKeyDown() then ReloadUI()
			elseif IsAltKeyDown() and BF.db.altwipe then BF:Wipe()
			else BF:OpenSack() end
		end,
		onRight = function() S:ToggleConfig("bugfolder") end,
		tooltip = function()
			GameTooltip:AddLine("|cff" .. S.accentHex .. "SentinelUI|r |cffff5555BugFolder|r")
			local n = #BF:GetErrors(BF:GetSessionId())
			GameTooltip:AddLine(format("|cffeda55f%d|r %s", n, L["errors this session"]))
			GameTooltip:AddLine("|cffeda55f" .. L["Click: open sack"] .. "|r", 1, 1, 1)
			GameTooltip:AddLine("|cffeda55f" .. L["Right-click: settings"] .. "|r", 1, 1, 1)
			GameTooltip:AddLine("|cffeda55f" .. L["Shift-click: reload"] .. "|r", 0.7, 0.7, 0.7)
			if BF.db.altwipe then GameTooltip:AddLine("|cffeda55f" .. L["Alt-click: wipe"] .. "|r", 0.7, 0.7, 0.7) end
		end,
	})
end

function BF:Initialize()
	self.db = S.db.profile.bugfolder

	-- account-wide store + session counter
	local gb = S.db.global.bugFolder or {}
	S.db.global.bugFolder = gb
	gb.session = (tonumber(gb.session) or 0) + 1
	if type(gb.errors) ~= "table" then gb.errors = {} end
	if type(gb.minimap) ~= "table" then gb.minimap = {} end
	-- saveErrors=false keeps everything in a session-only table (never saved)
	if self.db.saveErrors then
		self.store = gb.errors
	else
		self.sessionErrors = self.sessionErrors or {}
		self.store = self.sessionErrors
	end
	self.gb = gb

	-- move load-time errors into the db under this session
	for _, err in ipairs(loadErrors) do
		err.session = gb.session
		local exists, pos = FindError(gb.errors, err.message)
		if exists then
			err.counter = (exists.counter or 1) + 1
			tremove(gb.errors, pos)
		end
		StoreError(err)
	end
	wipe(loadErrors)
	while #gb.errors > MAX_ERRORS do tremove(gb.errors, 1) end

	if self.db.minimapIcon then self:CreateMinimapBtn() end

	-- report errors captured during load
	for _, err in ipairs(gb.errors) do
		if err.session == gb.session and not err.reported then
			err.reported = true
			self:OnBugGrabbed(err)
		end
	end
end

function BF:Update()
	self.db = S.db.profile.bugfolder
	if self.gb then
		if self.db.saveErrors then
			if self.store ~= self.gb.errors then
				for _, e in ipairs(self.store) do tinsert(self.gb.errors, e) end
				self.store = self.gb.errors
			end
		elseif self.store == self.gb.errors then
			local copy = {}
			for _, e in ipairs(self.store) do copy[#copy + 1] = e end
			self.sessionErrors = copy
			self.store = copy
			wipe(self.gb.errors)
		end
	end
	if textArea then S:SetFont(textArea, S.media.font, self.db.fontSize, "NONE") end
	if self.db.minimapIcon then
		self:CreateMinimapBtn()
		if self.minimapBtn then self.minimapBtn:Show() end
	elseif self.minimapBtn then
		self.minimapBtn:Hide()
	end
end

----------------------------------------------------------------------
-- Slash commands: /sbug  /sbugs
----------------------------------------------------------------------
SLASH_SENTINELBUG1 = "/sbug"
SLASH_SENTINELBUG2 = "/sbugs"
SlashCmdList.SENTINELBUG = function(msg)
	msg = strtrim(strlower(msg or ""))
	if msg == "test" then
		GrabError("Test error from /sbug test", false, "SentinelUI")
		S:Print("Test error stored.")
	elseif msg == "wipe" or msg == "reset" then
		BF:Wipe()
	elseif msg == "summary" then
		print(BF:AddonSummary())
	elseif msg == "export" then
		BF:OpenExport()
	elseif msg == "report" or msg == "tracker" then
		local store = ErrorDB()
		BF:OpenReport(store[#store])
	else
		BF:OpenSack()
	end
end
