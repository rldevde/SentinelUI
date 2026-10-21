local _, ns = ...
local S = ns.S
local L = S.L
local CH = S:NewModule("Chat")

local _G = _G
local pairs, ipairs, format, gsub, date, pcall = pairs, ipairs, format, string.gsub, date, pcall
local IsSecret = S.IsSecret
local BLANK = [[Interface\Buttons\WHITE8X8]]

CH.styled = {}

local shortChannels = {
	GUILD = "G", OFFICER = "O", PARTY = "P", PARTY_LEADER = "PL", RAID = "R", RAID_LEADER = "RL",
	RAID_WARNING = "RW", INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL", BATTLEGROUND = "BG", BATTLEGROUND_LEADER = "BGL",
}

-- channel-notice lines ("Changed Channel: [1. General]") must keep the full
-- channel name - shortening them to [1] loses the only information they carry.
local noticePatterns = {}
do
	for _, g in ipairs({
		"CHAT_CHANNEL_JOIN_GET", "CHAT_CHANNEL_LEAVE_GET", "CHAT_CHANNEL_LIST_GET", "CHAT_CHANNEL_OWNER_NOTICE",
		"CHAT_YOU_JOINED_NOTICE", "CHAT_YOU_LEFT_NOTICE", "CHAT_SUSPENDED_NOTICE", "CHAT_NOT_MEMBER_NOTICE",
		"CHAT_YOU_CHANGED_NOTICE", "CHAT_INVALID_NAME_NOTICE", "CHAT_PLAYER_NOT_MEMBER_NOTICE",
		"CHAT_CHANNEL_PASSWORD_NOTICE", "CHAT_MODERATION_ON_NOTICE", "CHAT_MODERATION_OFF_NOTICE",
		"CHAT_PLAYER_KICKED_NOTICE", "CHAT_PLAYER_BANNED_NOTICE", "CHAT_PLAYER_UNBANNED_NOTICE",
		"CHAT_PLAYER_ALREADY_MEMBER_NOTICE", "CHAT_NOT_MODERATOR_NOTICE", "CHAT_WRONG_PASSWORD_NOTICE",
	}) do
		local f = _G[g]
		if type(f) == "string" and f ~= "" then
			-- "Channel gewechselt: %s" -> pattern "Channel gewechselt: .*"
			local pat = f:gsub("%%[sd]", "\1")
			pat = (pat:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")):gsub("\1", ".*")
			if #pat > 3 then noticePatterns[#noticePatterns + 1] = pat end
		end
	end
end

-- Panels --------------------------------------------------------------------
function CH:CreatePanels()
	local db = self.db
	local function Panel(name, point, title)
		local p = CreateFrame("Frame", name, UIParent)
		p:SetSize(db.panelWidth, db.panelHeight)
		p:SetFrameStrata("BACKGROUND")
		p:SetFrameLevel(1)
		-- Sentinel chat: no boxed panel - a shade that fades out towards the top,
		-- a hairline under the tab row and accent corner ticks at the bottom edge
		local fade = p:CreateTexture(nil, "BACKGROUND")
		fade:SetAllPoints()
		p.fade = fade
		local tabBG = CreateFrame("Frame", nil, p)
		tabBG:SetPoint("TOPLEFT", 4, -4)
		tabBG:SetPoint("TOPRIGHT", -4, -4)
		tabBG:SetHeight(22)
		local line = tabBG:CreateTexture(nil, "ARTWORK")
		line:SetTexture(BLANK)
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT") line:SetPoint("BOTTOMRIGHT")
		line:SetVertexColor(1, 1, 1, 0.12)
		p.tabBG = tabBG
		local edge = CreateFrame("Frame", nil, p, S.BackdropTemplate)
		edge:SetAllPoints()
		S:SetTemplate(edge, "NoBackdrop", "BOTTOM")
		p.edge = edge
		S:CreateMover(p, name == "SentinelUILeftChatPanel" and "leftChat" or "rightChat", title, point, "chat")
		return p
	end
	self.leftPanel = Panel("SentinelUILeftChatPanel", { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 6, 32 }, L["Left Chat"])
	self.rightPanel = Panel("SentinelUIRightChatPanel", { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -6, 32 }, L["Right Chat"])
	self:UpdatePanels()
end

function CH:UpdatePanels()
	local db = self.db
	for _, p in ipairs({ self.leftPanel, self.rightPanel }) do
		p:SetSize(db.panelWidth, db.panelHeight)
		local c = S.media.backdropColor or { 0.06, 0.065, 0.09 }
		S:Gradient(p.fade, "VERTICAL", c[1], c[2], c[3], db.panelTransparency and 0.82 or 0.95, db.panelTransparency and 0.0 or 0.35)
	end
	local mode = db.panelBackdrop
	self.leftPanel:SetAlpha((mode == "SHOWBOTH" or mode == "LEFT") and 1 or 0)
	self.rightPanel:SetShown(db.rightPanelEnable)
	self.rightPanel:SetAlpha((mode == "SHOWBOTH" or mode == "RIGHT") and 1 or 0)
end

-- Message filter ------------------------------------------------------------
local urlPatterns = {
	"(%a+://[%w_%-%.%%%?/&=#:~+@!]+)",
	"(www%.[%w_%-%.]+%.%a%a+[%w_%-%.%%%?/&=#:~+@!]*)",
	"([%w_%-%.]+@[%w_%-]+%.%a%a+)",
	"(%d+%.%d+%.%d+%.%d+:?%d*/?[%w_%-%.%%%?/&=#:~+@!]*)",
}
-- bare domains (twitch.tv, discord.gg, youtube.com) only linkify on a known
-- TLD - otherwise normal text like "ach.so" or "hmm.ok" would become a link
local knownTLDs = { com = 1, net = 1, org = 1, de = 1, io = 1, gg = 1, tv = 1, me = 1,
	info = 1, eu = 1, at = 1, ch = 1, fr = 1, uk = 1, co = 1, dev = 1, app = 1, xyz = 1 }
local bareDomainPat = "([%w_%-%.]+%.(%a%a%a?%a?)[%w_%-%.%%%?/&=#:~+@!/]*)"

local function LinkURL(url)
	return format("|cff%s|Hurl:%s|h[%s]|h|r", S.accentHex, url, url)
end

local function LinkBare(url, tld)
	return knownTLDs[(tld or ""):lower()] and LinkURL(url) or url
end

function CH:FilterMessage(text)
	local db = self.db
	local isNotice = false
	for _, p in ipairs(noticePatterns) do
		if text:find(p) then isNotice = true break end
	end
	if db.shortChannels and not isNotice then
		-- one pattern for every channel link form: chan can be
		-- "PARTY"/"GUILD", "channel:2" or a bare "2"; label is "2. General" etc.
		-- Returning nil keeps the original text - never produce empty brackets.
		text = gsub(text, "|Hchannel:(.-)|h%[(.-)%]|h", function(chan, label)
			local ab = shortChannels[chan]
			if not ab then ab = chan:match("channel:(%d+)") or chan:match("CHANNEL:(%d+)") or chan:match("^(%d+)$") end
			if not ab then ab = label and label:match("^(%d+)%.") end
			if ab then return format("|Hchannel:%s|h[%s]|h", chan, ab) end
		end)
	end
	if db.url then
		-- mask existing hyperlinks so nothing inside them gets linkified
		local masks = {}
		text = gsub(text, "(|H.-|h.-%]|h)", function(l) masks[#masks + 1] = l return "\1" .. #masks .. "\2" end)
		for _, pattern in ipairs(urlPatterns) do
			local replaced
			text, replaced = gsub(text, "^" .. pattern, LinkURL)
			if replaced == 0 then text = gsub(text, "([%s\1\2])" .. pattern, function(space, url) return space .. LinkURL(url) end) end
		end
		text = gsub(text, "^" .. bareDomainPat, LinkBare)
		text = gsub(text, "([%s\1\2])" .. bareDomainPat, function(sp, url, tld)
			local l = LinkBare(url, tld)
			return l == url and (sp .. url) or (sp .. l)
		end)
		for i, l in ipairs(masks) do
			text = gsub(text, "\1" .. i .. "\2", function() return l end, 1)
		end
	end
	if self.keywords and #self.keywords > 0 then
		for _, word in ipairs(self.keywords) do
			local lower = text:lower()
			local s = lower:find(word:lower(), 1, true)
			if s and not text:sub(1, s):find("|H[^|]*$") then
				local c = db.keywordColor
				text = text:sub(1, s - 1) .. S:Hex(c) .. text:sub(s, s + #word - 1) .. "|r" .. text:sub(s + #word)
				if db.keywordSound ~= "None" and (not self.lastKeywordSound or GetTime() - self.lastKeywordSound > 5) then
					self.lastKeywordSound = GetTime()
					PlaySoundFile(S:Fetch("sound", db.keywordSound), "Master")
				end
			end
		end
	end
	if db.timestamp ~= "NONE" then
		local c = db.timestampColor
		text = S:Hex(c) .. "[" .. date(db.timestamp) .. "]|r " .. text
	end
	return text
end

local hoverLinks = { item = true, spell = true, enchant = true, quest = true, achievement = true, talent = true, currency = true, unit = false }

local function AddMessageHook(frame, text, ...)
	if type(text) == "string" and not IsSecret(text) then
		local ok, res = pcall(CH.FilterMessage, CH, text)
		if ok then text = res elseif S.LogError then S:LogError(res, "Chat:Filter") end
		if frame == ChatFrame1 and not CH.replaying then CH:RecordHistory(text, ...) end
	end
	return frame.suiAddMessage(frame, text, ...)
end

-- chat history: last N lines of the main chat survive /reload and relog
function CH:RecordHistory(text, r, g, b)
	if not self.db.history or (self.db.historySize or 0) <= 0 then return end
	local h = S.private.chatHistory or {}
	S.private.chatHistory = h
	h[#h + 1] = { text, r, g, b }
	while #h > self.db.historySize do tremove(h, 1) end
end

function CH:ReplayHistory()
	local h = S.private.chatHistory
	if not self.db.history or not h or #h == 0 then return end
	self.replaying = true
	for _, line in ipairs(h) do
		pcall(ChatFrame1.suiAddMessage or ChatFrame1.AddMessage, ChatFrame1, line[1], line[2] or 0.6, line[3] or 0.6, line[4] or 0.6)
	end
	ChatFrame1.suiAddMessage(ChatFrame1, "|cff808080--- " .. L["Chat history"] .. " ---|r")
	self.replaying = nil
end

-- spam throttle: identical message from the same sender within N seconds is dropped
local throttleCache = {}
local function ThrottleFilter(_, _, msg, author)
	local t = CH.db and CH.db.throttle or 0
	if t <= 0 or type(msg) ~= "string" or IsSecret(msg) or IsSecret(author) then return false end
	local key = (author or "") .. "#" .. msg
	local now = GetTime()
	local last = throttleCache[key]
	throttleCache[key] = now
	if last and now - last < t and author ~= S.myName and not (author or ""):find("^" .. S.myName .. "%-") then return true end
	return false
end

-- URL copy popup
StaticPopupDialogs["SENTINELUI_URL"] = {
	text = "URL", button1 = CLOSE, hasEditBox = true, editBoxWidth = 350,
	OnShow = function(self, data)
		local eb = self.editBox or self.EditBox
		eb:SetText(data or "")
		eb:SetFocus()
		eb:HighlightText()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

function CH:HookItemRef()
	local original = SetItemRef
	SetItemRef = function(link, text, button, chatFrame)
		if type(link) == "string" and link:sub(1, 4) == "url:" then
			StaticPopup_Show("SENTINELUI_URL", nil, nil, link:sub(5))
			return
		end
		return original(link, text, button, chatFrame)
	end
end

-- Copy chat -----------------------------------------------------------------
function CH:CopyChat(frame)
	if not self.copyFrame then
		local f = CreateFrame("Frame", "SentinelUIChatCopy", UIParent)
		f:SetSize(640, 340)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		S:SetTemplate(f, "Transparent", "TOP")
		tinsert(UISpecialFrames, "SentinelUIChatCopy")
		local scroll = CreateFrame("ScrollFrame", "SentinelUIChatCopyScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 8, -28)
		scroll:SetPoint("BOTTOMRIGHT", -28, 8)
		S:SkinScrollBar(scroll.ScrollBar or _G.SentinelUIChatCopyScrollScrollBar)
		local eb = CreateFrame("EditBox", nil, scroll)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetFontObject(ChatFontNormal)
		eb:SetWidth(600)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(eb)
		f.edit = eb
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		S:SkinCloseButton(close)
		close:SetPoint("TOPRIGHT", -4, -4)
		local title = S:FontString(f, 13, "OUTLINE")
		title:SetPoint("TOPLEFT", 10, -8)
		title:SetText(L["Copy Chat"])
		self.copyFrame = f
	end
	local lines = {}
	for i = 1, frame:GetNumMessages() do
		local msg = frame:GetMessageInfo(i)
		if msg and not IsSecret(msg) then
			msg = msg:gsub("|T.-|t", ""):gsub("|A.-|a", "")
			lines[#lines + 1] = msg
		end
	end
	self.copyFrame.edit:SetText(table.concat(lines, "\n"))
	self.copyFrame:Show()
end

-- Frame styling -------------------------------------------------------------
local tabTextures = { "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight", "HighlightLeft", "HighlightMiddle", "HighlightRight", "ActiveLeft", "ActiveMiddle", "ActiveRight" }

function CH:StyleTab(tab)
	for _, k in ipairs(tabTextures) do
		local t = tab[k] or _G[tab:GetName() .. k]
		if t then t:SetTexture(nil) t:SetAlpha(0) end
	end
	local glow = tab.glow or _G[tab:GetName() .. "Glow"]
	if glow then
		glow:SetTexture(BLANK)
		glow:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.35)
		glow:ClearAllPoints()
		glow:SetPoint("BOTTOMLEFT", 8, 2)
		glow:SetPoint("BOTTOMRIGHT", -8, 2)
		glow:SetHeight(2)
	end
	local text = tab.Text or _G[tab:GetName() .. "Text"]
	if text then
		S:SetFont(text, self:ChatFont(), self.db.tabFontSize, "OUTLINE")
		text:SetShadowOffset(0, 0)
	end
	if tab.conversationIcon then tab.conversationIcon:SetAlpha(0) end
end

function CH:UpdateTabColors()
	for i = 1, NUM_CHAT_WINDOWS do
		local tab = _G["ChatFrame" .. i .. "Tab"]
		local frame = _G["ChatFrame" .. i]
		local text = tab and (tab.Text or _G[tab:GetName() .. "Text"])
		if text then
			if frame == SELECTED_CHAT_FRAME or (SELECTED_DOCK_FRAME and frame == SELECTED_DOCK_FRAME) then
				text:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
			else
				text:SetTextColor(0.9, 0.9, 0.9)
			end
		end
	end
end

function CH:StyleEditBox(frame)
	local name = frame:GetName()
	local eb = frame.editBox or _G[name .. "EditBox"]
	if not eb or eb.suiStyled then return end
	eb.suiStyled = true
	for _, k in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
		local t = _G[name .. "EditBox" .. k] or eb[k]
		if t then t:SetAlpha(0) end
	end
	if eb.NineSlice then eb.NineSlice:SetAlpha(0) end
	S:SetTemplate(eb, "Default", "TOP")
	eb:SetAltArrowKeyMode(false)
	eb:HookScript("OnEditFocusGained", function(self) self:Show() end)
	if not ChatEdit_UpdateHeader then return end
	hooksecurefunc("ChatEdit_UpdateHeader", function(editBox)
		if editBox ~= eb then return end
		local chatType = editBox:GetAttribute("chatType")
		local info = chatType and ChatTypeInfo[chatType]
		if chatType == "CHANNEL" then
			local id = GetChannelName(editBox:GetAttribute("channelTarget"))
			info = id and id > 0 and ChatTypeInfo["CHANNEL" .. id] or info
		end
		if info and editBox.SetBackdropBorderColor then editBox:SetBackdropBorderColor(info.r, info.g, info.b) end
	end)
end

function CH:PositionEditBox(frame)
	local eb = frame.editBox or _G[frame:GetName() .. "EditBox"]
	if not eb then return end
	local panel = self.leftPanel
	eb:ClearAllPoints()
	if self.db.editboxPosition == "ABOVE_CHAT" then
		eb:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 3)
		eb:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 3)
	else
		local dp = _G.SentinelUILeftChatDataPanel
		if dp then
			eb:SetPoint("TOPLEFT", dp, "TOPLEFT", 0, 0)
			eb:SetPoint("BOTTOMRIGHT", dp, "BOTTOMRIGHT", 0, 0)
		else
			eb:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -3)
			eb:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -3)
		end
	end
	eb:SetHeight(22)
	eb:SetFrameStrata("DIALOG")
end

function CH:StyleChatFrame(frame)
	if not frame or self.styled[frame] then return end
	self.styled[frame] = true
	local name = frame:GetName()
	local id = frame:GetID()

	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") then region:SetTexture(nil) end
	end
	for _, k in ipairs({ "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture", "LeftTexture", "RightTexture", "TopTexture", "BottomTexture", "ResizeButton" }) do
		local t = _G[name .. k]
		if t then t:SetAlpha(0) end
	end
	local buttonFrame = frame.buttonFrame or _G[name .. "ButtonFrame"]
	if buttonFrame then buttonFrame:Hide() buttonFrame.Show = buttonFrame.Hide end
	-- floating/undocked chat windows get a Blizzard minimize (-) button
	for _, k in ipairs({ "MinimizeButton", "MaximizeButton", "CollapseButton" }) do
		local b = frame[k] or frame[k:sub(1,1):lower() .. k:sub(2)] or _G[name .. k]
		if b and b.Hide then
			b:Hide()
			if b.Show then b.Show = function() b:Hide() end end
			if b.HookScript then b:HookScript("OnShow", function(bb) bb:Hide() end) end
		end
	end
	local mmf = frame.MaximizeMinimizeFrame or _G[name .. "MaximizeMinimizeFrame"]
	if mmf then mmf:Hide() mmf:HookScript("OnShow", function(f) f:Hide() end) end
	if frame.ScrollBar then frame.ScrollBar:SetAlpha(0) frame.ScrollBar:EnableMouse(false) end
	local stb = frame.ScrollToBottomButton or _G[name .. "ButtonFrameBottomButton"]
	if stb then
		if self.db.scrollDownButton then
			stb:SetParent(frame)
			S:StripTextures(stb)
			if stb.SetNormalTexture then stb:GetNormalTexture():SetAlpha(0) end
			S:SkinArrowButton(stb, "down")
			stb:SetSize(18, 18)
			stb:ClearAllPoints()
			stb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		else
			stb:SetAlpha(0)
		end
	end
	if frame.Selection then frame.Selection:SetAlpha(0) end

	local _, size = frame:GetFont()
	S:SetFont(frame, self:ChatFont(), size or self.db.fontSize, self.db.fontOutline)
	frame:SetShadowOffset(S.mult, -S.mult)
	frame:SetShadowColor(0, 0, 0, 0.9)
	frame:SetClampRectInsets(0, 0, 0, 0)
	frame:SetClampedToScreen(false)
	-- fading only applies to undocked/floating tabs when configured - otherwise
	-- a floating channel tab silently fades its text away after fadeTime seconds
	local canFade = self.db.fade and (frame.isDocked or self.db.fadeUndockedTabs)
	frame:SetFading(canFade and true or false)
	frame:SetTimeVisible(self.db.fadeTime)
	if frame:GetMaxLines() < self.db.maxLines then frame:SetMaxLines(self.db.maxLines) end

	local tab = _G[name .. "Tab"]
	if tab then self:StyleTab(tab) end
	self:StyleEditBox(frame)
	self:PositionEditBox(frame)

	if frame ~= ChatFrame2 and not frame.suiAddMessage then
		frame.suiAddMessage = frame.AddMessage
		frame.AddMessage = AddMessageHook
	end

	if self.db.copyButton and not frame.suiCopy then
		local copy = CreateFrame("Button", nil, frame)
		copy:SetSize(18, 18)
		copy:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
		copy:SetFrameLevel(frame:GetFrameLevel() + 5)
		S:CreateBackdrop(copy, "Default", nil, 0)
		local t = S:FontString(copy, 10, "OUTLINE")
		t:SetPoint("CENTER")
		t:SetText("C")
		S:RegisterAccent(t, "text")
		local function Rest() return CH.db.fadeChatToggles and 0 or 0.6 end
		copy:SetAlpha(Rest())
		copy:SetScript("OnClick", function() CH:CopyChat(frame) end)
		copy:SetScript("OnEnter", function(b) b:SetAlpha(1) GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT") GameTooltip:AddLine(L["Copy Chat"]) GameTooltip:Show() end)
		copy:SetScript("OnLeave", function(b) b:SetAlpha(Rest()) GameTooltip:Hide() end)
		frame:HookScript("OnEnter", function() copy:SetAlpha(0.6) end)
		frame:HookScript("OnLeave", function() if not copy:IsMouseOver() then copy:SetAlpha(Rest()) end end)
		frame.suiCopy = copy
	end

	-- hovering item/spell/quest links shows their tooltip
	frame:HookScript("OnHyperlinkEnter", function(f, link)
		if not CH.db.hyperlinkHover or type(link) ~= "string" then return end
		local kind = link:match("^(%a+):")
		if kind and hoverLinks[kind] then
			GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
			pcall(GameTooltip.SetHyperlink, GameTooltip, link)
			GameTooltip:Show()
			CH.hoverTip = true
		end
	end)
	frame:HookScript("OnHyperlinkLeave", function()
		if CH.hoverTip then CH.hoverTip = nil GameTooltip:Hide() end
	end)
end

function CH:IsRightChat(frame)
	if not self.db.rightPanelEnable then return false end
	local tab = _G[frame:GetName() .. "Tab"]
	local text = tab and (tab.Text or _G[tab:GetName() .. "Text"])
	local label = text and text:GetText()
	if not label or IsSecret(label) then return false end
	return label == LOOT or label == "Loot" or label == "Beute" or label == L["Right Chat"]
end

function CH:PositionChat()
	if InCombatLockdown() then return S:RunOutOfCombat(self.PositionChat, self) end
	local db = self.db
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame" .. i]
		if frame then
			self:StyleChatFrame(frame)
			local tab = _G["ChatFrame" .. i .. "Tab"]
			if frame == ChatFrame1 then
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", self.leftPanel, "TOPLEFT", 6, -30)
				frame:SetPoint("BOTTOMRIGHT", self.leftPanel, "BOTTOMRIGHT", -6, 6)
				if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(frame) end
			elseif self:IsRightChat(frame) and not frame.isDocked then
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", self.rightPanel, "TOPLEFT", 6, -30)
				frame:SetPoint("BOTTOMRIGHT", self.rightPanel, "BOTTOMRIGHT", -6, 6)
				if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(frame) end
				if tab then
					tab:ClearAllPoints()
					tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4)
				end
			end
		end
	end
	if GeneralDockManager then
		GeneralDockManager:ClearAllPoints()
		GeneralDockManager:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 4)
		GeneralDockManager:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", -20, 4)
		GeneralDockManager:SetHeight(22)
	end
	self:UpdateTabColors()
end

function CH:HideBlizzardButtons()
	for _, n in ipairs({ "ChatFrameMenuButton", "QuickJoinToastButton", "FriendsMicroButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "ChatMenu", "TextToSpeechButton" }) do
		local b = _G[n]
		if b and n ~= "ChatMenu" then
			b:SetAlpha(0)
			b:EnableMouse(false)
			if b.UnregisterAllEvents and n == "QuickJoinToastButton" then b:UnregisterAllEvents() end
		end
	end
	if GeneralDockManagerScrollFrame then
		local sf = GeneralDockManagerScrollFrame
		if sf.ScrollLeftButton then sf.ScrollLeftButton:SetAlpha(0) end
	end
	if GeneralDockManagerOverflowButton then S:StripTextures(GeneralDockManagerOverflowButton) end
end

function CH:SetupClassColors()
	-- Blizzard's ToggleChatColorNamesByClassGroup is unreliable across builds;
	-- flip the underlying flag per group
	local function SetGroupColored(group, flag)
		local info = ChatTypeGroup and ChatTypeGroup[group]
		if info then
			for _, value in next, info do
				SetChatColorNameByClass(strsub(value, 10), flag)
			end
		else
			pcall(SetChatColorNameByClass, group, flag)
		end
	end
	for _, group in ipairs({ "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "ACHIEVEMENT", "WHISPER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "BATTLEGROUND", "BATTLEGROUND_LEADER" }) do
		SetGroupColored(group, true)
	end
	for i = 1, 15 do SetGroupColored("CHANNEL" .. i, true) end
end

-- player level in chat: passive name -> {level, class} cache fed by guild,
-- group and friends data. Note: SendWho is a protected function on modern
-- clients, so unknown senders simply get no level - no active lookup.
CH.levelCache = {}

function CH:LearnPlayer(name, level, class)
	if IsSecret(name) or IsSecret(level) or IsSecret(class) then return end
	if not name or name == "" then return end
	local e = self.levelCache[name]
	if not e or (level or 0) > (e.level or 0) or (class and not e.class) then
		self.levelCache[name] = { level = level or (e and e.level) or 0, class = class or (e and e.class) }
	end
end

function CH:ScanGroup()
	for i = 1, GetNumGroupMembers() do
		local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
		local name, realm = UnitName(unit)
		if name then
			if realm and realm ~= "" then name = name .. "-" .. realm end
			local _, class = UnitClass(unit)
			self:LearnPlayer(name, UnitLevel(unit), class)
		end
	end
end

local function ScanGuild()
	if not IsInGuild() then return end
	if S.GuildRoster then S.GuildRoster() end
	local n = GetNumGuildMembers and GetNumGuildMembers() or 0
	for i = 1, n do
		local name, _, _, level, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
		if name then CH:LearnPlayer(name, level, class) end
	end
end

local function ScanFriends()
	local n = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
	for i = 1, n do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.name then CH:LearnPlayer(info.name, info.level, info.className) end
	end
end

local function ScanWho()
	if not (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo) then return end
	local n = C_FriendList.GetNumWhoResults()
	for i = 1, n do
		local info = C_FriendList.GetWhoInfo(i)
		if info and info.fullName then
			CH:LearnPlayer(info.fullName, info.level, info.classStr or info.filename)
		end
	end
end

local function ShortName(sender)
	return (sender or ""):gsub("%-.*", "")
end

local levelEvents = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER", "CHAT_MSG_EMOTE",
}

local function LevelFilter(_, _, msg, sender, ...)
	if not CH.db or not CH.db.playerLevel or type(msg) ~= "string" or IsSecret(msg) then return false end
	local name = ShortName(sender)
	local e = name and CH.levelCache[name]
	if not e or not e.level or e.level <= 0 then return false end
	-- rewrite the name inside the |Hplayer link: [Name] -> [52 Name]; the level
	-- inherits the class color Blizzard already applies to the link text
	local newMsg, n = gsub(msg, "(|Hplayer:[^|]-|h%[)[^%]]-(%]|h)", "%1" .. e.level .. " " .. name .. "%2", 1)
	if n == 0 then newMsg = msg end
	return false, newMsg, sender, ...
end

function CH:SetupSticky()
	if not self.db.stickyChat then return end
	for _, t in ipairs({ "SAY", "PARTY", "RAID", "GUILD", "OFFICER", "WHISPER", "BN_WHISPER", "CHANNEL", "INSTANCE_CHAT", "YELL" }) do
		if ChatTypeInfo[t] then ChatTypeInfo[t].sticky = 1 end
	end
end

function CH:UpdateKeywords()
	self.keywords = {}
	for word in (self.db.keywords or ""):gmatch("[^,]+") do
		word = word:trim()
		if word == "%MYNAME%" then word = S.myName end
		if word ~= "" then tinsert(self.keywords, word) end
	end
end

function CH:ChatFont()
	return self.db.font and S:Fetch("font", self.db.font) or S.media.font
end

function CH:Update()
	self:UpdatePanels()
	self:UpdateKeywords()
	for frame in pairs(self.styled) do
		local _, size = frame:GetFont()
		S:SetFont(frame, self:ChatFont(), size or self.db.fontSize, self.db.fontOutline)
		frame:SetFading(self.db.fade)
		frame:SetTimeVisible(self.db.fadeTime)
		self:PositionEditBox(frame)
		local tab = _G[frame:GetName() .. "Tab"]
		if tab then self:StyleTab(tab) end
	end
	self:PositionChat()
end

function CH:Initialize()
	self:CreatePanels()
	self:UpdateKeywords()
	self:HideBlizzardButtons()
	self:HookItemRef()
	if self.db.classColorMentions then self:SetupClassColors() end
	self:SetupSticky()
	if self.db.timestamp ~= "NONE" then SetCVar("showTimestamps", "none") end

	self:PositionChat()
	self:SecureHook("FCF_OpenTemporaryWindow", function()
		for _, name in ipairs(CHAT_FRAMES or {}) do CH:StyleChatFrame(_G[name]) end
	end)
	self:SecureHook("FCF_OpenNewWindow", function() CH:PositionChat() end)
	self:SecureHook("FCF_DockFrame", function() CH:UpdateTabColors() end)
	self:SecureHook("FCF_Tab_OnClick", function() CH:UpdateTabColors() end)
	self:SecureHook("FCF_RestorePositionAndDimensions", function(_, frame)
		if frame == ChatFrame1 or CH:IsRightChat(frame) then
			C_Timer.After(0, function() S:SafeCall("Chat:Restore", CH.PositionChat, CH) end)
		end
	end)
	if FCFTab_UpdateColors then self:SecureHook("FCFTab_UpdateColors", function() CH:UpdateTabColors() end) end
	self:SecureHook("FCF_SetWindowName", function(_, frame) if CH:IsRightChat(frame) then CH:PositionChat() end end)

	self:RegisterEvent("UPDATE_CHAT_WINDOWS", "PositionChat")
	self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "PositionChat")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() S:SafeCall("Chat:PEW", CH.PositionChat, CH) end) end)
	local function WhisperSound()
		local snd = CH.db.whisperSound
		if snd and snd ~= "None" and (not CH.lastWhisper or GetTime() - CH.lastWhisper > 2) then
			CH.lastWhisper = GetTime()
			PlaySoundFile(S:Fetch("sound", snd), "Master")
		end
	end
	for _, ev in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }) do
		ChatFrame_AddMessageEventFilter(ev, ThrottleFilter)
	end
	C_Timer.NewTicker(60, function() local now = GetTime() for k, v in pairs(throttleCache) do if now - v > 120 then throttleCache[k] = nil end end end)
	C_Timer.After(0.5, function() S:SafeCall("Chat:History", CH.ReplayHistory, CH) end)
	self:RegisterEvent("CHAT_MSG_WHISPER", WhisperSound)
	self:RegisterEvent("CHAT_MSG_BN_WHISPER", WhisperSound)

	-- player-level in chat: cache feed + message filter + /who fallback pump
	for _, ev in ipairs(levelEvents) do ChatFrame_AddMessageEventFilter(ev, LevelFilter) end
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function() S:SafeCall("Chat:ScanGuild", ScanGuild) end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() S:SafeCall("Chat:ScanGroup", CH.ScanGroup, CH) end)
	self:RegisterEvent("FRIENDLIST_UPDATE", function() S:SafeCall("Chat:ScanFriends", ScanFriends) end)
	self:RegisterEvent("WHO_LIST_UPDATE", function() S:SafeCall("Chat:ScanWho", ScanWho) end)
	ScanGuild() ScanFriends() self:ScanGroup()
end
